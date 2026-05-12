#!/usr/bin/env python3
"""Render cloud-init YAML for a recipe with parameters."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

from af_core.recipe import load_recipe
from af_core.renderer import render_cloudinit
from af_core.validator import generate_secret


def main() -> int:
    """Load recipe, merge params, render cloud-init, print to stdout."""
    parser = argparse.ArgumentParser(
        description="Render cloud-init YAML for a recipe"
    )
    parser.add_argument(
        "recipe_dir",
        type=Path,
        help="Path to recipe directory",
    )
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
                params.update(test_params)
        except Exception as e:
            print(f"Error loading test-params.yaml: {e}", file=sys.stderr)
            return 1

    for param in args.params:
        if "=" not in param:
            print(f"Error: invalid parameter format: {param}", file=sys.stderr)
            return 1
        key, value = param.split("=", 1)
        params[key] = value

    # Fill in missing params: auto-generate passwords, apply defaults
    for p in recipe.parameters:
        if p.name not in params:
            if p.auto_generate:
                params[p.name] = generate_secret()
            elif p.default is not None:
                params[p.name] = str(p.default)

    try:
        cloudinit = render_cloudinit(recipe, params)
        print(cloudinit, end="")
        return 0
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
