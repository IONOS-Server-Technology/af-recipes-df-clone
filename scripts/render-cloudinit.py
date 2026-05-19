#!/usr/bin/env python3
"""Render cloud-init YAML for a recipe with parameters."""
from __future__ import annotations

import argparse
import secrets
import string
import sys
from pathlib import Path
from typing import Any

import yaml

from af_core.recipe import load_recipe


def _generate_secret(length: int = 32) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def _render_env(template: str, params: dict[str, str]) -> str:
    result = template
    for key, value in params.items():
        result = result.replace(f"{{{{{key}}}}}", str(value))
    return result


def _render_cloudinit(recipe: Any, params: dict[str, str]) -> str:
    """Render cloud-init YAML with parameter substitution for CI testing."""
    app_dir = f"/opt/{recipe.id}"

    compose_file = recipe.path / "docker-compose.yaml"
    if not compose_file.exists():
        compose_file = recipe.path / "docker-compose.yml"

    env_template = recipe.path / ".env.template"
    compose_content = compose_file.read_text() if compose_file.exists() else ""
    env_content = _render_env(env_template.read_text(), params) if env_template.exists() else ""

    write_files = []
    if compose_content:
        write_files.append({
            "path": f"{app_dir}/docker-compose.yml",
            "content": compose_content,
            "owner": "root:root",
            "permissions": "0644",
        })
    if env_content:
        write_files.append({
            "path": f"{app_dir}/.env",
            "content": env_content,
            "owner": "root:root",
            "permissions": "0600",
        })

    runcmd: list[str] = [
        f"mkdir -p {app_dir}",
        "if ! command -v docker &>/dev/null; then curl -fsSL https://get.docker.com | sh; fi",
        *recipe.preinstall_cmds,
        f"cd {app_dir} && docker compose up -d",
    ]

    doc: dict[str, Any] = {}
    if write_files:
        doc["write_files"] = write_files
    if runcmd:
        doc["runcmd"] = runcmd
    return "#cloud-config\n" + yaml.dump(doc, default_flow_style=False, allow_unicode=True)


def main() -> int:
    """Load recipe, merge params, render cloud-init, print to stdout."""
    parser = argparse.ArgumentParser(description="Render cloud-init YAML for a recipe")
    parser.add_argument("recipe_dir", type=Path, help="Path to recipe directory")
    parser.add_argument(
        "--params",
        nargs="*",
        default=[],
        help="Parameters as key=value pairs (overrides test-params.yaml)",
    )
    args = parser.parse_args()

    recipe_dir = args.recipe_dir.resolve()
    if not recipe_dir.is_dir():
        print(f"Error: recipe directory not found: {recipe_dir}", file=sys.stderr)
        return 1

    try:
        recipe = load_recipe(recipe_dir)
    except RuntimeError as e:
        print(f"Error loading recipe: {e}", file=sys.stderr)
        return 1

    params: dict[str, str] = {}

    test_params_file = recipe_dir / "test-params.yaml"
    if test_params_file.exists():
        try:
            test_params = yaml.safe_load(test_params_file.read_text())
            if test_params:
                params.update({k: str(v) for k, v in test_params.items()})
        except Exception as e:
            print(f"Error loading test-params.yaml: {e}", file=sys.stderr)
            return 1

    for param in args.params:
        if "=" not in param:
            print(f"Error: invalid parameter format: {param}", file=sys.stderr)
            return 1
        key, value = param.split("=", 1)
        params[key] = value

    # af-core no longer exposes recipe.parameters — read from metadata.yaml directly
    raw_meta = yaml.safe_load((recipe_dir / "metadata.yaml").read_text())
    for p in raw_meta.get("parameters", []):
        name = p["name"]
        if name not in params:
            if p.get("auto_generate"):
                params[name] = _generate_secret()
            elif p.get("default") is not None:
                params[name] = str(p["default"])

    print(_render_cloudinit(recipe, params), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
