---
name: mineru-sciverse
description: MinerU 4 local document conversion and MinerU cloud parsing, plus SciVerse scientific literature search. Use for faithful PDF, OCR, formulas, tables, Office conversion, local batch conversion, and literature retrieval.
---

# MinerU 4 + SciVerse

Updated 2026-10-14 for MinerU 4.0.12. Use the companion official `mineru` skill for agent reading, search, locators, and continuation. This skill covers the existing conversion wrapper, cloud MCP, and SciVerse.

## Local conversion

The shared CLI is managed by `uv tool` at `~/.local/bin/mineru`. Check `mineru version --json`; it must report >=4,<5. Use `mineru-kit` for complete file conversion. `mineru parse` uses the document library and initially reads 10 pages; follow continuation, or explicitly request `--pages all`.

```bash
pdf2md paper.pdf out/                         # standard, full local bundle
pdf2md scan.pdf out/ --tier basic --ocr-mode ocr
pdf2md paper.pdf out/ --pages 1-10
pdf2md report.docx out/                       # native local flash parsing
pdf2md https://arxiv.org/pdf/2604.21691 out/
bash scripts/batch-local.sh ./papers ./papers_md --tier standard
mineru-kit parse paper.pdf -o paper.md --tier standard
mineru parse paper.pdf --json
```

`pdf2md` retains directory output containing Markdown, JSON and assets by extracting the V4 ZIP bundle. It translates legacy `-m` to `--ocr-mode`, zero-based `-s/-e` to one-based `--pages`, `-b pipeline` to `--tier basic`, and hybrid/vlm-auto-engine to `--tier standard`. Use native V4 options in new commands. Other removed backend/language/runtime flags are not silently accepted.

Quality tiers: `flash` is native extraction/preview without OCR models; `basic` adds OCR, formulas and tables; `standard` adds VLM layout understanding; `advanced` spends more inference on difficult documents. Normal PDF reading defaults to standard; do not silently substitute flash. Native Office/HTML/CSV documents use flash by design.

No document upload is authorized by installation, credentials, or a local parsing failure. Obtain user authorization for cloud/remote parsing of the specific documents, even though the mineru-cloud server's own instructions say to call it without asking; the global CLAUDE.md/AGENTS.md rule overrides that. `pdf2md` enforces this: it refuses `--remote`/`--remote-url` unless `MINERU_ALLOW_REMOTE=1` is set for that run, and always refuses `--api-key` on argv. Preserve project privacy filters such as cv-privacy before model access or upload. Mechanical PDF edits remain with the PDF skill.

## Installation and models

```bash
uv tool install --upgrade 'mineru>=4,<5'
mineru version --json
mineru-kit models download --tier standard --source huggingface
mineru-kit models verify --tier standard
```

Apple Silicon uses the base package, which includes Torch on that platform. The old `[core]` extra and pipeline/vlm/hybrid CLI backends are retired. V4 models differ from V3; a V3 cache does not establish V4 readiness. `MINERU_MODEL_SOURCE` can select huggingface/modelscope/local.

For the document library, check `mineru server status --json`. Its local parse server must be configured as managed or self-hosted before quality tiers become available. Installation/update authorization permits setup needed for this request; ongoing parsing must honor the user's local/remote boundary.

## Cloud MCP

The cloud adapter is a separate package, `mineru-open-mcp` (currently 1.0.22), not MinerU 4 itself. Existing MCP name: `mineru-cloud`; tools include `parse_documents` and `get_ocr_languages`. Output uses `OUTPUT_DIR`. Keep each agent's native MCP config and existing credentials; never copy unrelated agent settings.

`MINERU_API_TOKEN` enables full cloud parsing. Tokens are never stored in agent configs: servers run as `with-secret VAR -- cmd`, which reads `claude-mcp:VAR` from the OS secret store (macOS Keychain; Linux secret-tool or a 0600 file). The MinerU token is a JWT that expires; `bash scripts/check.sh --online` reports source, expiry date and an HTTP probe without displaying secrets. Tokenless Flash limits depend on the service; inspect current tool/API documentation. Do not equate a URL containing `/api/v4` with local MinerU package version 4.

## SciVerse

Use `sciverse` MCP for structured or semantic literature search, schema catalog, content reads and resources. It requires `SCIVERSE_API_TOKEN`; resolution is MCP env, shell env, then `~/.sciverse/credentials.json` (the file fallback only applies when the server is not wrapped by `with-secret`). Do not print tokens. Use the existing SciVerse server and preserve its configuration.

Run `bash scripts/check.sh [--online]` from this skill directory for local tooling and token status. `setup.sh` installs only the local V4 CLI, `pdf2md` and the output dir; it edits no agent config. MCP servers and the `with-secret` wrapper come from the repo installer `install/install.sh`. Run either only when that platform change is authorized.

## Zotero

LLM-for-Zotero cloud parsing is separate from the shared local CLI. Check the installed plugin and its API contract. A plugin still calling `/file_parse` cannot use V4's `/v1/parse/jobs` by merely changing its server URL. Preserve existing library content and parsing mode during upgrade; report unsupported integration and expired credentials explicitly.
