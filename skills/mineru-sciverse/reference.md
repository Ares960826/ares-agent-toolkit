# MinerU + SciVerse — full reference

## What each piece is

- **MinerU** — OpenDataLab document parsing engine. PDF / image / DOCX / PPTX / XLSX → LLM-ready Markdown + JSON. Formulas→LaTeX, tables→HTML, 109-lang OCR, layout cleanup. Two ways to run: locally (offline, free) or via the cloud API.
- **SciVerse** — OpenDataLab "AI-ready" scientific data platform. Agentic + semantic literature search with traceable citations, metadata faceted search, full-text/attachment fetch. Cloud-only, needs a token.

## Components installed by this skill

| Component | Mechanism | Token | Location |
|-----------|-----------|-------|----------|
| MinerU local CLI | `uv tool install "mineru[core]"` | none | `~/.local/bin/mineru` |
| `pdf2md` wrapper | bundled script | none | `~/.local/bin/pdf2md` |
| `mineru-cloud` MCP | `uvx mineru-open-mcp` | `MINERU_API_TOKEN` (optional; Flash mode works blank) | `~/.claude.json` |
| `sciverse` MCP | `npx -y sciverse-mcp-server` | `SCIVERSE_API_TOKEN` (required) | `~/.claude.json` |

## Bundled scripts (in this skill folder)

| Script | What it does |
|--------|--------------|
| `setup.sh` | Idempotent bootstrap for a new device; never overwrites tokens; backs up `~/.claude.json` first. |
| `scripts/check.sh` | Preflight/doctor — prints install + token status (no secrets). Run before token-gated tools. |
| `scripts/batch-local.sh` | Parse an entire folder LOCALLY (the no-token, on-machine batch fallback). |
| `pdf2md` | Single-file local wrapper (installed to `~/.local/bin`). |

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

## Disk / resource notes (measured on M3 Pro / 18GB)

- MinerU program (incl. torch): ~1.0 GB at `~/.local/share/uv/tools/mineru`
- pipeline models: ~1.1 GB at `~/.cache/modelscope` (biggest: formula model 773MB)
- Total one-time ~2.1 GB. `hybrid/vlm` backends download an extra ~1–2 GB on first use.
- Runtime: only while actively parsing; bursty MPS+CPU, ~3–6 GB RAM peak; nothing like training. Idle = zero.

## MinerU CLI cheatsheet

```bash
mineru -p IN -o OUT -b pipeline           # general, most compatible on Mac
mineru -p IN -o OUT -m ocr                # force OCR (scanned)
mineru -p IN -o OUT -s 0 -e 9             # page range 0..9
mineru -p IN -o OUT -l en                 # OCR language hint
mineru -p IN -o OUT -b hybrid-auto-engine # higher accuracy VLM (heavier)
MINERU_MODEL_SOURCE=huggingface mineru …  # switch model source (default modelscope)
```
Outputs per doc: `<name>.md`, `<name>_content_list.json`, `<name>_middle.json`, `<name>_model.json`, `images/`, plus annotated `_layout.pdf` / `_span.pdf`.

## mineru-cloud MCP

- Tools: `parse_documents` (local paths and/or remote URLs → Markdown), `get_ocr_languages`.
- Env: `MINERU_API_TOKEN` (blank → Flash mode: free, ≤20p/10MB, markdown only), `OUTPUT_DIR` (default `~/mineru-downloads`).
- Single-file parses return inline markdown; batch parses save to `OUTPUT_DIR` and return file metadata + a zip URL.
- Token: https://mineru.net (API management). Flash docs: https://mineru.net/apiManage/docs

## sciverse MCP / REST

- MCP: `npx -y sciverse-mcp-server`, env `SCIVERSE_API_TOKEN` (`sv-...`). Tools: `search_papers`, `semantic_search`, `list_catalog`, `read_content`, `get_resource`.
- REST base (if calling directly): `https://api.sciverse.space` — endpoints `/agentic-search`, `/meta-search`, `/meta-catalog`, `/content`, `/resource`. Header: `Authorization: Bearer <TOKEN>`.
- Token: https://sciverse.space/tokens (≤10 per account, long-lived). Same token also works for DianShi (`https://dianshi.opendatalab.com/api/mcp`) and Skills.

## Typical research pipeline

1. `sciverse` → find / semantic-search relevant papers, get PDFs.
2. Parse them: single → local `pdf2md`; batch/large → `mineru-cloud`.
3. Hand the Markdown to the agent for analysis / writing / Zotero notes.

## New device

`bash ~/.claude/skills/mineru-sciverse/setup.sh` then fill the two tokens. Idempotent; never overwrites existing tokens. Tokens are intentionally NOT stored in this skill.

## Uninstall / reclaim space

```bash
uv tool uninstall mineru          # remove program
rm -rf ~/.cache/modelscope        # remove downloaded models
# then delete the two servers from ~/.claude.json if desired
```
