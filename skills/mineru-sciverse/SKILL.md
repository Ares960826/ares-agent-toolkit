---
name: mineru-sciverse
description: Local MinerU document conversion wrapper (pdf2md), the mineru-cloud MCP with token and upload-consent handling, and SciVerse scientific literature search. Use for full-bundle PDF/Office conversion to Markdown, cloud parsing setup, token checks, and literature retrieval.
---

# MinerU + SciVerse

This skill adds what the official `mineru` skill does not cover: the `pdf2md` bundle wrapper, the cloud MCP, credential handling, and SciVerse. For reading, searching, locators, tiers and CLI usage of MinerU itself, use the official `mineru` skill and the "Quality Tiers" section of https://github.com/opendatalab/MinerU. Do not restate that material here.

## Local conversion (pdf2md)

`pdf2md` wraps `mineru-kit parse` and extracts the ZIP bundle (Markdown, JSON, images) into a directory. It converts all pages by default, unlike `mineru parse`, which reads the first 10.

```bash
pdf2md paper.pdf out/                      # PDF/image: tier standard; Office files: tier flash
pdf2md scan.pdf out/ --tier basic --ocr-mode ocr
pdf2md paper.pdf out/ --pages 1-10
pdf2md ./papers ./papers_md                # a directory of documents
pdf2md https://arxiv.org/pdf/2604.21691 out/
```

Use native MinerU 4 options. `pdf2md` still accepts a few 3.x flags for old scripts (`-m`, `-s/-e`, `-b`), but do not write new commands with them. Do not silently downgrade to `flash`; it is a preview tier.

## Upload consent

Installation, credentials, or a local parsing failure never authorize uploading a document. Get the user's approval for the specific documents before any cloud or remote parsing, even though the mineru-cloud server's own instructions say to call it without asking; the global CLAUDE.md/AGENTS.md rule overrides that. `pdf2md` enforces it: it refuses `--remote`/`--remote-url` unless `MINERU_ALLOW_REMOTE=1` is set for that run, and always refuses `--api-key` on argv. Apply project privacy filters (for example cv-privacy) before any model access or upload. Mechanical PDF edits belong to the PDF skill.

## Credentials

Tokens are never stored in agent configs. Token-gated servers start as `with-secret [--optional] NAME -- cmd`, which reads `claude-mcp:NAME` from the OS secret store (macOS Keychain; Linux `secret-tool` or a 0600 file under `~/.config/with-secret/`). There are two different MinerU variables:

| Variable | Used by | Needed for |
|---|---|---|
| `MINERU_API_TOKEN` | `mineru-open-mcp` (cloud MCP) | `parse_documents` full mode; without it the MCP falls back to tokenless Flash mode |
| `MINERU_API_KEY` | official `mineru` CLI | `mineru parse --remote`, `mineru usage` |
| `SCIVERSE_API_TOKEN` | `sciverse` MCP | required for SciVerse |

Run `bash scripts/check.sh [--online]` from this skill directory. It reports the install state, model readiness (`mineru-kit models verify`), and for each agent config (Claude Code, Cursor, Codex) whether each server is present and wrapped. It decodes JWT expiry offline and, with `--online`, makes one read-only probe per service. It never prints a secret value.

## Cloud MCP

`mineru-open-mcp` is a separate package from MinerU itself. It runs as `mineru-open-mcp@latest` from `mcp/servers.json` (server name `mineru-cloud`), so it follows new releases on each agent start; tools are `parse_documents` and `get_ocr_languages`; output goes to `OUTPUT_DIR`. A `/api/v4` URL in the cloud API is unrelated to the local package version.

## SciVerse

Use the `sciverse` MCP for structured or semantic literature search, the schema catalog, content reads and resources. It runs as `sciverse-mcp-server@latest`. Token lookup is MCP env, then shell env, then `~/.sciverse/credentials.json`; the file fallback only applies when the server is not wrapped by `with-secret`. Never print tokens.

## Install

`setup.sh` installs and upgrades the local pieces (MinerU CLI within `>=4,<5`, the official `mineru` skill from upstream, `pdf2md`, output dir) and edits no agent config. Re-run it to upgrade. Skills, the `with-secret` wrapper and MCP servers come from `install/install.sh` in the ares-agent-toolkit repo; run it only when that platform change is authorized. Details, endpoints and troubleshooting are in `reference.md`.
