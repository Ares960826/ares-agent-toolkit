# MinerU + SciVerse — full reference

## What each piece is

- **MinerU** — OpenDataLab document parsing engine. PDF / image / DOCX / PPTX / XLSX → LLM-ready Markdown + JSON. Formulas→LaTeX, tables→HTML, 109-lang OCR, layout cleanup. Two ways to run: locally (offline, free) or via the cloud API.
- **SciVerse** — OpenDataLab "AI-ready" scientific data platform. Agentic + semantic literature search with traceable citations, metadata faceted search, full-text/attachment fetch. Cloud-only, needs a token.

## Components installed by this skill

| Component | Mechanism | Token | Location |
|-----------|-----------|-------|----------|
| MinerU local CLI | `uv tool install "mineru>=4,<5"` | none | `~/.local/bin/mineru` |
| `pdf2md` wrapper | bundled script | none | `~/.local/bin/pdf2md` |
| `mineru-cloud` MCP | `with-secret --optional MINERU_API_TOKEN -- uvx mineru-open-mcp@latest` | `MINERU_API_TOKEN` (optional; JWT tokens expire) | each agent's config, via `install/install.sh` |
| `sciverse` MCP | `with-secret SCIVERSE_API_TOKEN -- npx -y sciverse-mcp-server@latest` | `SCIVERSE_API_TOKEN` (required) | each agent's config, via `install/install.sh` |
| `with-secret` | repo `bin/with-secret` → `~/.claude/bin/with-secret` | reads `claude-mcp:NAME` from Keychain / secret-tool / 0600 file | — |

## Bundled scripts (in this skill folder)

| Script | What it does |
|--------|--------------|
| `setup.sh` | Idempotent local bootstrap: MinerU CLI, `pdf2md`, output dir. Edits no agent config and handles no tokens. |
| `scripts/check.sh` | Preflight/doctor — install and model status, per-agent MCP wiring (Claude/Cursor/Codex), token source + JWT expiry for `MINERU_API_TOKEN`, `MINERU_API_KEY`, `SCIVERSE_API_TOKEN`; `--online` adds one HTTP probe per service. Never prints secrets. |
| `pdf2md` | Local wrapper for a file, a directory or a URL (installed to `~/.local/bin`). |

## Relationship to the built-in `pdf` skill (don't overlap)

| Task | Use |
|------|-----|
| Merge / split / rotate / watermark / encrypt PDFs | built-in **`pdf`** skill (pypdf/qpdf) |
| Fill a PDF form | built-in **`pdf`** skill (FORMS) |
| Quick plain-text / simple table extract | built-in **`pdf`** skill (pdfplumber) |
| Scientific paper → faithful Markdown, **formulas→LaTeX, tables→HTML** | **this skill** (MinerU) |
| Multi-column / scanned / handwritten academic OCR | **this skill** (MinerU) |
| Find / semantic-search scientific literature | **this skill** (SciVerse) |

Rule: reach for the built-in `pdf` skill for **mechanical** PDF work; reach for MinerU
when **parsing fidelity** of complex/academic content matters.

## MinerU 4 local runtime

The previous V3 pipeline/hybrid resource measurements do not describe V4. On Apple Silicon, install the base MinerU package. Download and verify the V4 models before claiming OCR/standard readiness.

```bash
mineru version --json
mineru-kit models download --tier standard      # source defaults to auto; --source huggingface|modelscope to force
mineru-kit models verify --tier standard
mineru-kit models show                          # effective config and per-repo readiness
pdf2md paper.pdf out/ --tier standard
pdf2md scan.pdf out/ --tier basic --ocr-mode ocr
pdf2md paper.pdf out/ --pages 1-10
mineru-kit parse paper.pdf -o paper.md --tier standard
mineru parse paper.pdf --json
```

The wrapper extracts the V4 ZIP bundle into its output directory. V4 output is not guaranteed to include every V3 debug file. `mineru parse` initially reads 10 pages; follow its locators and continuation. `mineru-kit parse` converts all pages by default.

For V4 HTTP integrations use `/v1/health`, `/v1/tiers`, `/v1/uploads`, `/v1/parse/jobs` and `/v1/files`. Old `/file_parse` clients require an actual migration; merely changing the URL is insufficient. Cloud API `/api/v4` naming is independent from the local package version.

## mineru-cloud MCP

- Tools: `parse_documents` (local paths and/or remote URLs → Markdown), `get_ocr_languages`.
- **Uploads documents to mineru.net.** Use only after the user approves uploading the specific documents (global CLAUDE.md/AGENTS.md rule; overrides the server's own "call immediately" instruction).
- Env: `MINERU_API_TOKEN` via `with-secret` (not `MINERU_API_KEY`, which only the official CLI's `--remote` reads; token: ≤200p/200MB, batch ≤200 files; tokenless Flash: ≤20p/10MB, single file, IP rate-limited; the wrapper uses `--optional`, so a missing token falls back to Flash), `OUTPUT_DIR` (default `~/mineru-downloads`).
- Single-file parses return inline markdown; batch parses save to `OUTPUT_DIR` and return file metadata + a zip URL.
- Token: https://mineru.net (API management). Flash docs: https://mineru.net/apiManage/docs

## sciverse MCP / REST

- MCP: `npx -y sciverse-mcp-server`, env `SCIVERSE_API_TOKEN` (`sv-...`). Tools: `search_papers`, `semantic_search`, `list_catalog`, `read_content`, `get_resource`.
- REST base (if calling directly): `https://api.sciverse.space` — endpoints `/agentic-search`, `/meta-search`, `/meta-catalog`, `/content`, `/resource`. Header: `Authorization: Bearer <TOKEN>`.
- Token: https://sciverse.space/tokens (≤10 per account, long-lived). Same token also works for DianShi (`https://dianshi.opendatalab.com/api/mcp`) and Skills.
- **Token resolution order** (per `sciverse-mcp-server`): MCP-config `env` → `SCIVERSE_API_TOKEN`
  shell env → `~/.sciverse/credentials.json` (written by `sciverse auth login`, mode 0600).
  The credentials-file fallback only applies to an unwrapped server: the installer wraps sciverse
  with `with-secret SCIVERSE_API_TOKEN`, which exits before the server starts if the secret is missing.
  `scripts/check.sh` reports the credentials-file case as configured, not blank.

## Caveats
- **MCP config lives in the repo installer only** — `install/install.sh` → `apply_mcp.py` writes
  each agent's own file/format, adds only missing servers, and wraps token-gated servers with
  `with-secret`. It round-trips JSON configs (2-space indent) and writes a backup first.
- **`pdf2md <url>`** downloads to a temp file; if the URL has no known doc extension (e.g.
  `arxiv.org/pdf/2604.21691`) it is saved as `.pdf` so MinerU recognizes the type.

## Typical research pipeline

1. `sciverse` → find / semantic-search relevant papers, get PDFs.
2. Parse them locally with `pdf2md` (single file or directory). Use `mineru-cloud` for batch/large
   jobs only after the user approves uploading those documents.
3. Hand the Markdown to the agent for analysis and writing.

## New device

1. `bash install/install.sh --agents claude,codex[,cursor,opencode] --with-mineru-cli` from an
   ares-agent-toolkit checkout (skills, `pdf2md`, `with-secret`, MCP servers, local CLI).
2. Store tokens once in the OS secret store (never in configs or this repo):
   `printf 'add-generic-password -U -s "claude-mcp:NAME" -a "%s" -w "VALUE"\n' "$USER" | security -i`
   (Linux: `secret-tool store --label="claude-mcp:NAME" service "claude-mcp:NAME"`).
3. `bash scripts/check.sh --online`, then restart the agents.

## Upgrading

One command: `bash setup.sh` (from this skill directory). It stops a running `mineru server`, upgrades the CLI within `>=4,<5`, and updates the official `mineru` skill with `npx skills update mineru --global --yes`. The two MCP packages use `@latest`, so they follow on the next agent start. Nothing here vendors upstream files.

## Uninstall / reclaim space

```bash
uv tool uninstall mineru          # remove program
rm -rf ~/.mineru/models           # MinerU 4 models
# older installs may also hold models in ~/.cache/huggingface or ~/.cache/modelscope
# then delete the two servers from ~/.claude.json if desired
```
