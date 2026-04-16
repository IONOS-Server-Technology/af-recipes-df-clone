# af-recipes

Application Factory recipes — declarative application definitions consumed by the AF API.

## Recipe Format

Each recipe lives in `recipes/<app-name>/` and contains:

| File | docker-compose | bare-metal | Description |
|---|---|---|---|
| `metadata.yaml` | required | required | App info, parameters, resource requirements |
| `docker-compose.yaml` | required | — | Compose v3 service definition |
| `.env.template` | required | — | `{{PARAM}}` placeholders resolved at install time |
| `install.sh` | required | required | Installation orchestration script |
| `health-check.sh` | required | required | CI-only health check script |

See [rfc/001-recipe-schema.md](rfc/001-recipe-schema.md) for the full specification.

## Available Recipes

<table>
<tr>
<td align="center" width="33%">
<a href="recipes/n8n/">
<img src="https://img.shields.io/badge/n8n-EA4B71?style=for-the-badge&logo=n8n&logoColor=white" alt="n8n" />
</a>
<br />
<sub><b>Workflow Automation</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Connect apps and APIs with a low-code visual editor</sub>
</td>
<td align="center" width="33%">
<a href="recipes/portainer/">
<img src="https://img.shields.io/badge/Portainer-13BEF9?style=for-the-badge&logo=portainer&logoColor=white" alt="Portainer" />
</a>
<br />
<sub><b>Container Management</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/512MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>GUI for managing Docker environments</sub>
</td>
<td align="center" width="33%">
<a href="recipes/ollama/">
<img src="https://img.shields.io/badge/Ollama-000000?style=for-the-badge&logo=ollama&logoColor=white" alt="Ollama" />
</a>
<br />
<sub><b>Local LLM Runner</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/8GB_RAM-orange?style=flat-square" />
</sub>
<br />
<sub>Run large language models locally &mdash; GPU recommended</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/openclaw/">
<img src="https://img.shields.io/badge/OpenClaw_🦞-FF6B35?style=for-the-badge" alt="OpenClaw" />
</a>
<br />
<sub><b>AI Agent Runtime</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Personal AI assistant via Telegram, Discord, Slack &amp; more</sub>
</td>
<td align="center" width="33%">
<a href="recipes/claude-code/">
<img src="https://img.shields.io/badge/Claude_Code-D4A574?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude Code" />
</a>
<br />
<sub><b>AI Coding Assistant</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/bare--metal-333?style=flat-square&logo=linux&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Agentic AI tool for terminal-based coding</sub>
</td>
<td align="center" width="33%">
<a href="recipes/gemini-cli/">
<img src="https://img.shields.io/badge/Gemini_CLI-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white" alt="Gemini CLI" />
</a>
<br />
<sub><b>AI Coding Assistant</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/bare--metal-333?style=flat-square&logo=linux&logoColor=white" />
<img src="https://img.shields.io/badge/1GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Interact with Google Gemini models from the terminal</sub>
</td>
</tr>
</table>

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
