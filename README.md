# af-recipes

Application Factory recipes — declarative application definitions consumed by the AF API.

## Recipe Format

Each recipe lives in `recipes/<app-name>/` and contains:

| File | docker-compose | bare-metal | Description |
|---|---|---|---|
| `metadata.yaml` | required | required | App info, parameters, resource requirements |
| `docker-compose.yml` | required | — | Compose v3 service definition |
| `.env.template` | required | — | `{{PARAM}}` placeholders resolved at install time |
| `health-check.sh` | required | required | CI-only health check script |

See [rfc/001-recipe-schema.md](rfc/001-recipe-schema.md) for the full specification.

## Recipes

| App | Type | Category | Min RAM |
|---|---|---|---|
| [n8n](recipes/n8n/) | docker-compose | automation | 2 GB |
| [Portainer](recipes/portainer/) | docker-compose | infrastructure | 512 MB |
| [Ollama](recipes/ollama/) | docker-compose | ai | 8 GB |
| [OpenClaw](recipes/openclaw/) | docker-compose | ai | 2 GB |
| [Claude Code](recipes/claude-code/) | bare-metal | developer-tools | 2 GB |
| [Gemini CLI](recipes/gemini-cli/) | bare-metal | developer-tools | 1 GB |

## Build Catalogue

Generate `catalogue.json` from all `metadata.yaml` files:

```bash
python3 bin/build-catalogue
```

Requires `pyyaml` (`pip install pyyaml`).

## Contributing

1. Create a new directory under `recipes/` matching your app's `name` field.
2. Add all required files for your recipe type.
3. Run `python3 bin/build-catalogue` to validate.
4. Submit a PR for review.
