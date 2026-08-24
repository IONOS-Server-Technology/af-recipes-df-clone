#!/usr/bin/env python3
"""Generate the ImageTester config the live recipe pipeline runs.

The checks themselves live in tests/checks/: one INI template per check kind, plus
manifest.yaml giving their emission order, their scope (once per VM or once per app)
and the name of the gate that decides whether each one is emitted. This script is the
assembler -- it resolves the gates, substitutes the app id and concatenates. It emits
no INI of its own, so a check that is not in tests/checks/ runs nowhere, and neither
does one the manifest leaves out.

A static config cannot do the job: it has to bake in a single $RECIPE_NAME, so it
can only ever describe a one-app VM. With two or three apps installed on the same
VM its /opt/$RECIPE_NAME assertions collapse onto whichever app the workflow
happened to put in RECIPE_NAME, and the others go unchecked. Here the per-app
blocks are expanded once per member of the selection, each carrying the app name
in its section name so a red run says WHICH app failed.

The app name is substituted at generation time. The TestSuite only expands $VARS
declared in [require_env]; it has no notion of a per-app loop.

A recipe that cannot satisfy the default per-app checks may ship
recipes/<id>/test-checks.yaml to replace the per-app check list for itself; see the
"Per-recipe override" section of tests/checks/manifest.yaml. None does today.

IMPORTANT: write the output into the tests/ directory (next to auto-inject/).
[include_auto_inject] uses the relative path "auto-inject", and the TestSuite
resolves an [include_*] path against the directory of the including config. A
missing include target is a hard exit before any test runs, so a copy of this
config outside tests/ aborts the whole suite. tests/recipe-health-check.combo.conf
is the intended destination.

Usage:
    scripts/gen-health-check-conf.py gitea n8n --base-domain example.invalid \\
        --output tests/recipe-health-check.combo.conf
"""

import argparse
import difflib
import importlib.util
import json
import re
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NamedTuple

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
CHECKS_DIR = REPO_ROOT / "tests" / "checks"
RECIPES_DIR = REPO_ROOT / "recipes"
CATALOGUE_PATH = REPO_ROOT / "catalogue.json"

MANIFEST_NAME = "manifest.yaml"

# Templates end in .conf.tmpl, never .conf: the TestSuite loads a directory of checks
# by matching endswith(".conf"), so a template named *.conf would be picked up as a
# test config in its own right the moment tests/checks/ came into its reach.
TEMPLATE_SUFFIX = ".conf.tmpl"

# A recipe may replace the per-app check list for itself with this file. Full
# replace, no merge. Ships with no recipe today.
RECIPE_OVERRIDE_NAME = "test-checks.yaml"

PER_VM = "per_vm"
PER_APP = "per_app"
SCOPES = (PER_VM, PER_APP)

# The one gate that cannot resolve false, so the only one a floor may count on.
ALWAYS_GATE = "always"

# A TestSuite section header: "[name]" alone on its line. The suite keys its tests
# by these, so counting them counts the tests (and executors, and includes) the
# emitted config actually declares.
SECTION_HEADER_RE = re.compile(r"^\[([^\[\]]+)\][ \t]*$", re.MULTILINE)

# How a block attaches to the one before it. "tight" is for a fragment that continues
# the previous block rather than starting a new one -- the gated header lines and the
# BASE_DOMAIN entry of [require_env].
JOINS = {"blank": "\n\n", "tight": "\n"}
DEFAULT_JOIN = "blank"

ENTRY_KEYS = frozenset({"template", "scope", "gate", "join"})

# @APP@ is the only placeholder a check template may use, and only a per_app template
# has an app to substitute. The two header fragments that report a value rather than
# describe a check take the other two.
APP_PLACEHOLDER = "@APP@"
APPS_PLACEHOLDER = "@APPS@"
BASE_DOMAIN_PLACEHOLDER = "@BASE_DOMAIN@"
# IF-1458: "true"/"false" baked into the per-app app-password block, so check-app-password.sh
# asserts the direction af-api actually applies for this recipe.
BASIC_AUTH_PLACEHOLDER = "@BASIC_AUTH@"

# Recipe ids reach shell commands, file paths and TestSuite section names, so keep
# them to the shape af-recipes already uses for its recipe directories.
RECIPE_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")

# The workflow passes `--testsuite-exclude af_FIN_` on break-glass runs. Matching is
# a case-insensitive substring test OR a regex match against the loaded test name,
# so a section name containing this marker would be silently skipped.
EXCLUDE_MARKER = "af_FIN_"

# RFC 2606 / RFC 6761 reserved TLDs, plus mDNS .local. A name under any of these can
# never complete an ACME order, so a served-certificate check on it cannot pass by
# construction -- af-test.invalid, the combination default, is exactly that case.
UNROUTABLE_TLDS: frozenset[str] = frozenset({"invalid", "test", "example", "localhost", "local"})

DEFAULT_OUTPUT_DIR_NAME = "tests"

# IF-1458: the wants-basic-auth rule mirrors af-api's Recipe.wants_basic_auth and already
# lives in scripts/recipe-wants-basic-auth.py. Load it by path ONCE rather than reimplement
# it -- the hyphenated filename is not importable as a normal module, and a second copy of
# the rule would be a third thing to keep in parity with af-api.
_WANTS_BASIC_AUTH_SCRIPT = Path(__file__).resolve().parent / "recipe-wants-basic-auth.py"
_spec = importlib.util.spec_from_file_location("recipe_wants_basic_auth", _WANTS_BASIC_AUTH_SCRIPT)
_wants_basic_auth_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_wants_basic_auth_module)


def recipe_wants_basic_auth(recipe: str) -> bool:
    """Whether this recipe gets a Traefik basicauth middleware (IF-1458).

    Delegates to scripts/recipe-wants-basic-auth.py's wants_basic_auth(), reading the
    recipe's metadata.yaml exactly as that script's main() does, so the rule stays a
    single definition shared between the CLI script and this generator.
    """
    metadata = yaml.safe_load((RECIPES_DIR / recipe / "metadata.yaml").read_text()) or {}
    return bool(_wants_basic_auth_module.wants_basic_auth(metadata))


class ManifestError(Exception):
    """A manifest or a template it names is unusable."""


@dataclass(frozen=True)
class CheckEntry:
    """One line of a manifest: which template, emitted how often, and when."""

    template: str
    scope: str
    gate: str
    join: str


class Block(NamedTuple):
    """One rendered block, and how it attaches to the block before it."""

    join: str
    text: str


def cert_check_applies(
    recipes: list[str],
    base_domain: str | None,
    le_staging: bool,
    catalogue_ports: Mapping[str, list[dict[str, Any]]],
    recipe_label: str | None = None,
) -> bool:
    """Whether the served-certificate check can pass for this selection.

    check-traefik-cert.sh lives in if-image-tests, not here, and curls
    https://$RECIPE_NAME.$BASE_DOMAIN, then asserts the issuer is LE staging. The
    host it builds therefore comes from RECIPE_NAME, and the workflow sets that from
    the combination LABEL, not from the app list -- so the label, not the app count,
    is the real precondition. Traefik only has a router for <recipe-id>.<base_domain>,
    so the check can only pass when the label IS the single recipe id. A two-app
    selection fails that by construction ("immich+n8n" is a job name), but so does a
    one-app combination dispatched with a label of its own: the combos input validates
    a label only against the recipe-id character class, so
    [{"apps":"n8n","label":"n8n-smoke"}] is accepted and would curl a host that
    resolves to no router -- a red run reporting a bug that does not exist.

    Four things must hold, then: a label equal to the one and only recipe id; a
    base_domain that could actually be issued a certificate; a run that requested the
    staging directory on its /compose call, so that "issuer is LE staging" is the right
    expectation rather than an accident; and a recipe that af-api actually routes
    through Traefik. That last one matters even on a real domain: a recipe with no
    routable port -- adguard-home, reached over WireGuard only -- gets no
    <recipe>.<base_domain> router, so curling that host resolves to nothing and the
    served-cert check could only ever be red. is_traefik_routed() decides it from the
    catalogue's declared ports, so this stays a routability question about the recipe,
    not a resolvability question about the domain.

    recipe_label defaults to "same as the recipe id" when the caller passes nothing.
    That is what the workflow's own single-recipe selection produces (label == recipe),
    and it keeps a bare CLI run emitting what it emitted before the flag existed. The
    workflow always passes it explicitly, so the default never decides a CI run.

    A pure string test on purpose: routability is read from catalogue.json (via
    is_traefik_routed), never from a live DNS or network lookup. Resolving the name
    would make the generated config depend on DNS at generation time, and a config that
    differs between two runs of the same command is not reproducible.
    """
    if not le_staging or len(recipes) != 1 or not base_domain:
        return False
    label = recipes[0] if recipe_label is None else recipe_label
    if label != recipes[0]:
        return False
    if base_domain.rsplit(".", 1)[-1].lower() in UNROUTABLE_TLDS:
        return False
    return is_traefik_routed(recipes[0], catalogue_ports)


def load_catalogue_ports(path: Path) -> dict[str, list[dict[str, Any]]]:
    """Map recipe id -> its declared ports, from the committed catalogue.json.

    catalogue.json is generated from the recipes' metadata.yaml by bin/build-catalogue
    and committed, and the pipeline's validate job fails on drift, so reading it here
    is reading the recipes -- without this script having to parse 24 metadata files or
    grow an af-core dependency it has no other use for.
    """
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ManifestError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ManifestError(f"{path} is not valid JSON: {exc}") from exc
    entries = document.get("recipes") if isinstance(document, dict) else None
    if not isinstance(entries, list):
        raise ManifestError(f"{path}: expected a top-level 'recipes' list")
    ports: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise ManifestError(f"{path}: every catalogue entry needs a string 'id'")
        declared = entry.get("ports") or []
        if not isinstance(declared, list):
            raise ManifestError(f"{path}: recipe {entry['id']!r} has a non-list 'ports'")
        ports[entry["id"]] = [port for port in declared if isinstance(port, dict)]
    return ports


def is_traefik_routed(recipe: str, catalogue_ports: Mapping[str, list[dict[str, Any]]]) -> bool:
    """Whether af-api gives this recipe a Traefik router, i.e. a <recipe>.<domain> host.

    Mirrors PortDefinition.traefik_routed in af-api: public, http and tcp. The renderer
    only writes router labels when at least one port satisfies all three, so a recipe
    that satisfies none is reachable at no such host no matter what base_domain the
    run used, and a route check for it could only ever be red.

    "http" is OMIT-MEANS-TRUE in the port model (PortDefinition.http defaults to True)
    and the catalogue faithfully omits it wherever the recipe did -- which is on every
    routed port there is today. Hence the True default here: a plain truthiness test on
    port["http"] would read "absent" as "not http" and silently suppress the check for
    immich, n8n, open-webui and every other routed recipe. Only an explicit
    "http": false (anytype-server's sync ports) may turn a public tcp port down.

    Unknown recipe is a hard error, not a default: it means catalogue.json no longer
    lists a recipe the pipeline is installing, and guessing either way would either
    invent a check that cannot pass or drop one that should run.
    """
    try:
        ports = catalogue_ports[recipe]
    except KeyError:
        raise ManifestError(
            f"recipe {recipe!r} has no entry in {CATALOGUE_PATH.name}, so whether it is "
            "routed through Traefik cannot be decided -- the catalogue is stale or the "
            "recipe id is a typo. Run 'python3 bin/build-catalogue' and commit the result."
        ) from None
    return any(
        port.get("public") and port.get("http", True) and port.get("protocol") == "tcp"
        for port in ports
    )


def resolve_gates(
    recipes: list[str],
    base_domain: str | None,
    le_staging: bool,
    catalogue_ports: Mapping[str, list[dict[str, Any]]],
    recipe_label: str | None = None,
) -> dict[str, bool]:
    """Resolve every per-run gate the manifest can name, once, for this selection.

    The gate LOGIC lives here and nowhere else; the manifest only names a gate. The
    four header TLS lines are mutually exclusive and jointly exhaustive by
    construction, since cert_check implies both a base_domain and LE staging.

    A gate whose answer differs between two apps of the same selection belongs in
    resolve_app_gates() instead -- these are resolved before the app list is expanded
    and are therefore the same for every block in the config.
    """
    cert_check = cert_check_applies(
        recipes, base_domain, le_staging, catalogue_ports, recipe_label
    )
    routed = bool(base_domain)
    return {
        "always": True,
        # A base_domain means af-api routes through Traefik instead of publishing
        # host ports, which is what the routing blocks assert against.
        "base_domain": routed,
        "no_base_domain": not routed,
        # The LE-staging block only cats Traefik's compose file on the VM, so it needs
        # nothing beyond a Traefik deployment and a run that asked for staging.
        "le_staging": routed and le_staging,
        "le_staging_not_requested": routed and not le_staging,
        "cert_check": cert_check,
        "le_staging_without_cert_check": routed and le_staging and not cert_check,
        # Only where the numbers could actually surprise: a multi-app VM, whose
        # combined footprint nothing in af-api validates, or a Traefik run, which adds
        # a container the declared per-app app_min_ram_mb figures never counted. A
        # plain single-app install is the case those figures were written against.
        "multi_app_or_routed": len(recipes) > 1 or routed,
    }


def resolve_app_gates(
    recipe: str,
    base_domain: str | None,
    catalogue_ports: Mapping[str, list[dict[str, Any]]],
) -> dict[str, bool]:
    """Resolve the gates that answer differently for each app of one selection.

    Same contract as resolve_gates() -- logic here, names in the manifest -- but
    resolved inside the per-app expansion, once per recipe, so a mixed selection can
    emit a block for one app and skip it for another. Only a per_app check may name
    one of these; a per_vm check would have no app to resolve it against, and naming
    one is caught as an unknown gate.
    """
    # Resolved before the base_domain test rather than behind it, so that a recipe the
    # catalogue does not know is reported on every run and not only on the routed ones.
    routed = is_traefik_routed(recipe, catalogue_ports)
    return {
        # Two conditions, both necessary: af-api only puts Traefik in front of the apps
        # at all when the /compose call carried a base_domain, and even then it only
        # routes a recipe that declares a port it can route.
        "traefik_route": bool(base_domain) and routed,
    }


def _parse_entry(raw: object, source: Path) -> CheckEntry:
    if not isinstance(raw, dict):
        raise ManifestError(f"{source}: each check must be a mapping, got {type(raw).__name__}")
    unknown = sorted(set(raw) - ENTRY_KEYS)
    if unknown:
        raise ManifestError(f"{source}: unknown key(s) {unknown} (expected {sorted(ENTRY_KEYS)})")
    template = raw.get("template")
    if not isinstance(template, str) or not template:
        raise ManifestError(f"{source}: every check needs a 'template'")
    if template.startswith("/") or ".." in Path(template).parts:
        raise ManifestError(f"{source}: template {template!r} must stay inside {CHECKS_DIR}")
    scope = raw.get("scope")
    if scope not in SCOPES:
        raise ManifestError(f"{source}: check {template!r} needs scope one of {list(SCOPES)}")
    gate = raw.get("gate")
    if not isinstance(gate, str) or not gate:
        raise ManifestError(f"{source}: check {template!r} needs a 'gate' name ('always' if none)")
    join = raw.get("join", DEFAULT_JOIN)
    if join not in JOINS:
        raise ManifestError(
            f"{source}: check {template!r} has join {join!r}, expected {sorted(JOINS)}"
        )
    return CheckEntry(template=template, scope=scope, gate=gate, join=join)


def load_manifest(path: Path) -> list[CheckEntry]:
    """Read a manifest (the general one, or a recipe's override) into entries."""
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ManifestError(f"cannot read {path}: {exc}") from exc
    except yaml.YAMLError as exc:
        raise ManifestError(f"{path} is not valid YAML: {exc}") from exc
    if not isinstance(document, dict) or not isinstance(document.get("checks"), list):
        raise ManifestError(f"{path}: expected a top-level 'checks' list")
    entries = [_parse_entry(raw, path) for raw in document["checks"]]
    if not entries:
        raise ManifestError(f"{path}: 'checks' is empty, so there is nothing to emit")
    return entries


def load_template(entry: CheckEntry) -> str:
    """Read a template, without its trailing newline -- the joins supply those."""
    path = CHECKS_DIR / f"{entry.template}{TEMPLATE_SUFFIX}"
    try:
        return path.read_text(encoding="utf-8").rstrip("\n")
    except OSError as exc:
        raise ManifestError(f"cannot read template {path}: {exc}") from exc


def per_app_entries(recipe: str, manifest: list[CheckEntry]) -> list[CheckEntry]:
    """The per-app checks for one recipe: its own override, or the general manifest.

    A full replace, never a merge: an override that lists three checks gets exactly
    those three. Only per-app checks can be overridden -- the per-VM blocks describe
    the VM the whole selection shares, so one app cannot have an opinion about them.
    """
    override = RECIPES_DIR / recipe / RECIPE_OVERRIDE_NAME
    if not override.is_file():
        return [entry for entry in manifest if entry.scope == PER_APP]
    entries = load_manifest(override)
    wrong_scope = [entry.template for entry in entries if entry.scope != PER_APP]
    if wrong_scope:
        raise ManifestError(
            f"{override}: {wrong_scope} are not scoped {PER_APP}; a recipe override may "
            f"only list {PER_APP} checks -- a {PER_VM} block describes the VM the whole "
            "selection shares"
        )
    return entries


def section_names(config: str) -> list[str]:
    """The section names of an assembled config, in emission order."""
    return SECTION_HEADER_RE.findall(config)


def minimum_sections(manifest: list[CheckEntry], recipes: list[str]) -> int:
    """How many sections this manifest MUST produce for this selection.

    Only entries gated "always" are counted: every other gate is allowed to resolve
    false, so nothing they contribute can be required. The templates are read and
    their headers counted rather than assumed to be one apiece -- the AF Logs
    template carries two sections and the executors template three -- and the
    per-app run is counted per recipe, through per_app_entries(), so a recipe
    override shortens the floor for itself instead of tripping it.
    """
    total = 0
    for entry in manifest:
        if entry.scope == PER_VM and entry.gate == ALWAYS_GATE:
            total += len(section_names(load_template(entry)))
    for recipe in recipes:
        for entry in per_app_entries(recipe, manifest):
            if entry.gate == ALWAYS_GATE:
                total += len(section_names(load_template(entry)))
    return total


def assert_config_populated(
    config: str,
    manifest: list[CheckEntry],
    recipes: list[str],
    source: Path,
    base_domain: str | None,
) -> None:
    """Refuse a config that would run fewer tests than the manifest promises.

    The TestSuite exits with the number of FAILED tests, so a config that loads
    nothing at all prints "Run 0 Tests" and exits 0 -- a green pipeline that tested
    nothing. Counting the emitted headers against a floor derived from the manifest
    turns that silent pass into a loud generation failure, and covers the narrower
    version of it too: a per-app run that quietly dropped one of its apps.

    When base_domain is set it also asserts BASE_DOMAIN is declared INSIDE the
    [require_env] section. The require-env-base-domain fragment attaches to that
    section by manifest order and join: tight, not by any header of its own, so a
    reordering could bind it after some later section and leave $BASE_DOMAIN
    undeclared -- which the TestSuite passes through literally, with no warning, into
    every routing block that reads it. Deriving "should be present" from base_domain
    rather than from the emitted fragment is the point: it catches the fragment
    landing in the wrong place.

    Read-only, and deliberately no part of the assembly above: it re-derives the
    floor from the manifest and the templates and then parses the finished text, so
    it does not restate whatever the assembler just did. It never touches the bytes.
    """
    names = section_names(config)
    floor = minimum_sections(manifest, recipes)
    if not names:
        raise ManifestError(
            f"{source}: the assembled config declares no [section] at all -- the "
            "TestSuite would report 'Run 0 Tests' and exit 0, i.e. a green run that "
            "tested nothing"
        )
    if len(names) < floor:
        raise ManifestError(
            f"{source}: the assembled config declares {len(names)} section(s) but the "
            f"manifest's unconditional checks require at least {floor} for "
            f"{len(recipes)} app(s) -- something the manifest names emitted nothing"
        )
    missing = [recipe for recipe in recipes if not any(n.endswith(f"_{recipe}") for n in names)]
    if missing:
        raise ManifestError(
            f"{source}: no per-app section was emitted for {missing} -- those apps "
            "would be installed by the run and then never checked"
        )
    if base_domain:
        in_require_env = False
        seen_require_env = False
        declared: set[str] = set()
        for line in config.splitlines():
            header = SECTION_HEADER_RE.match(line)
            if header is not None:
                in_require_env = header.group(1) == "require_env"
                seen_require_env = seen_require_env or in_require_env
                continue
            if in_require_env:
                declared.add(line.strip())
        if not seen_require_env or "BASE_DOMAIN" not in declared:
            raise ManifestError(
                f"{source}: base_domain is set but BASE_DOMAIN is not declared inside "
                "the [require_env] section -- the require-env-base-domain fragment "
                "mis-bound (a manifest reordering moved it out of that section), so the "
                "TestSuite would leave $BASE_DOMAIN literal in every routing block that "
                "reads it"
            )


def _per_app_run_start(manifest: list[CheckEntry], source: Path) -> int:
    """Index of the single contiguous run of per-app entries, or -1 if there is none."""
    positions = [index for index, entry in enumerate(manifest) if entry.scope == PER_APP]
    if not positions:
        return -1
    if positions != list(range(positions[0], positions[-1] + 1)):
        raise ManifestError(
            f"{source}: the {PER_APP} checks must be one contiguous run -- they are "
            "expanded together, once per app, so a split run would interleave the apps"
        )
    return positions[0]


def build_config(
    recipes: list[str],
    base_domain: str | None,
    le_staging: bool,
    recipe_label: str | None = None,
) -> str:
    """Assemble the config: resolve gates, expand templates, concatenate."""
    manifest_path = CHECKS_DIR / MANIFEST_NAME
    manifest = load_manifest(manifest_path)
    per_app_start = _per_app_run_start(manifest, manifest_path)
    catalogue_ports = load_catalogue_ports(CATALOGUE_PATH)
    gates = resolve_gates(recipes, base_domain, le_staging, catalogue_ports, recipe_label)
    shared = {
        APPS_PLACEHOLDER: ", ".join(recipes),
        BASE_DOMAIN_PLACEHOLDER: base_domain or "",
    }

    def gate_open(entry: CheckEntry, resolved: Mapping[str, bool]) -> bool:
        if entry.gate not in resolved:
            raise ManifestError(
                f"check {entry.template!r} names unknown gate {entry.gate!r} "
                f"(known for a {entry.scope} check: {sorted(resolved)})"
            )
        return resolved[entry.gate]

    def render(entry: CheckEntry, app_values: dict[str, str] | None = None) -> str:
        text = load_template(entry)
        values = dict(shared) if app_values is None else {**shared, **app_values}
        for placeholder, value in values.items():
            text = text.replace(placeholder, value)
        return text

    blocks: list[Block] = []
    for index, entry in enumerate(manifest):
        if entry.scope == PER_APP:
            if index != per_app_start:
                continue  # the whole run is expanded at its first entry
            for recipe in recipes:
                app_gates = {**gates, **resolve_app_gates(recipe, base_domain, catalogue_ports)}
                app_values = {
                    APP_PLACEHOLDER: recipe,
                    BASIC_AUTH_PLACEHOLDER: "true" if recipe_wants_basic_auth(recipe) else "false",
                }
                for app_entry in per_app_entries(recipe, manifest):
                    if gate_open(app_entry, app_gates):
                        blocks.append(Block(app_entry.join, render(app_entry, app_values)))
            continue
        if gate_open(entry, gates):
            blocks.append(Block(entry.join, render(entry, None)))

    if not blocks:
        raise ManifestError(f"{manifest_path}: every check was gated off, config is empty")
    # The first block's join has nothing to attach to.
    config = blocks[0].text
    for block in blocks[1:]:
        config += JOINS[block.join] + block.text
    config += "\n"
    assert_config_populated(config, manifest, recipes, manifest_path, base_domain)
    return config


def validate_recipes(recipes: list[str]) -> list[str]:
    """Return a list of human-readable problems with the requested recipe ids."""
    problems = []
    seen = set()
    for recipe in recipes:
        if recipe in seen:
            problems.append(
                f"recipe {recipe!r} given more than once: it would produce duplicate "
                "section names, and the TestSuite exits 1 when parsing with strict mode"
            )
        seen.add(recipe)
        if not RECIPE_NAME_PATTERN.match(recipe):
            problems.append(
                f"recipe {recipe!r} is not a valid recipe id "
                f"(expected {RECIPE_NAME_PATTERN.pattern})"
            )
        if EXCLUDE_MARKER.lower() in recipe.lower():
            problems.append(
                f"recipe {recipe!r} contains {EXCLUDE_MARKER!r}, which the workflow "
                "passes to --testsuite-exclude: its tests would be skipped silently"
            )
    return problems


def warn_about_missing_health_checks(recipes: list[str]) -> None:
    """Warn if a recipe has no health-check.sh in this checkout.

    Not fatal: WORKFLOW_HOMEDIR on the runner need not be this checkout. But a
    missing src makes the UploadExecute plugin raise an uncaught ValueError at
    run time, which takes down every test after it, so a typo is worth flagging.
    """
    if not RECIPES_DIR.is_dir():
        return
    for recipe in recipes:
        if not (RECIPES_DIR / recipe / "health-check.sh").is_file():
            print(
                f"warning: {RECIPES_DIR / recipe / 'health-check.sh'} not found; "
                "a missing health-check.sh aborts the whole run, not just its test",
                file=sys.stderr,
            )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "recipes",
        nargs="+",
        help="One or more recipe names, in the same order as the /compose selection",
    )
    parser.add_argument(
        "--base-domain",
        default=None,
        help="The base_domain that was sent to /compose. When set, BASE_DOMAIN is added "
        "to [require_env] and a Traefik routing check is emitted for each app that "
        "catalogue.json says af-api would actually route (a port that is public, http "
        "and tcp). Omit it for a single-app run that published host ports instead, in "
        "which case no routing check is emitted at all.",
    )
    parser.add_argument(
        "--expect-le-staging",
        action="store_true",
        help="Emit the two TLS blocks that assert Traefik is pointed at the Let's "
        "Encrypt STAGING directory. Pass it when this run asked af-api for staging, "
        "i.e. sent use_staging_le on its /compose call — which every CI leg does, so "
        "in the workflow it is unconditional. It stays an explicit opt-in so that a "
        "caller that did NOT request staging can omit it: such a VM gets no caserver "
        "line in its Traefik compose, and both blocks would fail there for a reason "
        "that is not a bug.",
    )
    parser.add_argument(
        "--recipe-label",
        default=None,
        help="The combination label the workflow exports as RECIPE_NAME. It decides "
        "whether the served-certificate check is emitted: check-traefik-cert.sh curls "
        "https://$RECIPE_NAME.$BASE_DOMAIN, and Traefik only routes "
        "<recipe-id>.<base_domain>, so the check is emitted only when the label is "
        "exactly the single recipe id. Defaults to the recipe id itself, which is what "
        "a one-app selection produces anyway.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Where to write the config (default: stdout). Write it into the tests/ "
        "directory, e.g. tests/recipe-health-check.combo.conf: [include_auto_inject] "
        "uses a path relative to the including config's own directory, and a missing "
        "include target is a hard exit before any test runs.",
    )
    parser.add_argument(
        "--check",
        default=None,
        help="Generate the config for these recipes/flags, then diff it against TARGET "
        "(a conf file you provide; not committed). Prints a unified diff and exits 1 on "
        "any difference, 0 if identical. Mutually exclusive with --output and --update.",
    )
    parser.add_argument(
        "--update",
        default=None,
        help="Generate the config for these recipes/flags, then WRITE it to TARGET, "
        "creating parent directories as needed. Use it to (re)generate a committed "
        "golden snapshot that --check then diffs against. Mutually exclusive with "
        "--output and --check.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    problems = validate_recipes(args.recipes)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1

    warn_about_missing_health_checks(args.recipes)

    try:
        config = build_config(
            args.recipes, args.base_domain, args.expect_le_staging, args.recipe_label
        )
    except ManifestError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    selected = [
        name
        for name, value in (
            ("--check", args.check),
            ("--output", args.output),
            ("--update", args.update),
        )
        if value is not None
    ]
    if len(selected) > 1:
        print(f"error: {', '.join(selected)} are mutually exclusive", file=sys.stderr)
        return 1

    if args.check is not None:
        target = Path(args.check)
        try:
            target_text = target.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"error: failed to read {target}: {exc}", file=sys.stderr)
            return 1
        if target_text == config:
            print(f"check: generated config matches {target}", file=sys.stderr)
            return 0
        diff = difflib.unified_diff(
            target_text.splitlines(keepends=True),
            config.splitlines(keepends=True),
            fromfile=str(target),
            tofile="<generated>",
        )
        sys.stdout.writelines(diff)
        return 1

    if args.update is not None:
        target = Path(args.update)
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(config, encoding="utf-8")
        except OSError as exc:
            print(f"error: failed to write {target}: {exc}", file=sys.stderr)
            return 1
        print(f"update: wrote generated config to {target}", file=sys.stderr)
        return 0

    if args.output is None:
        print(config, end="")
        return 0

    output = Path(args.output)
    if output.parent.name != DEFAULT_OUTPUT_DIR_NAME:
        print(
            f"warning: {output} is not inside a {DEFAULT_OUTPUT_DIR_NAME}/ directory. "
            "The config must sit next to auto-inject/ or [include_auto_inject] will "
            "not resolve and the run will abort before the first test.",
            file=sys.stderr,
        )
    try:
        output.write_text(config, encoding="utf-8")
    except OSError as exc:
        print(f"failed to write {output}: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
