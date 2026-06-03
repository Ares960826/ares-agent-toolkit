---
name: mineru-sciverse
description: >-
  High-fidelity academic document parsing (MinerU) + scientific literature
  retrieval (SciVerse), with one-command setup. Use when the user wants to
  parse/convert a PDF, image, Word, PPT, or Excel into Markdown/JSON —
  especially papers with formulas, tables, or scanned/multi-column layout
  ("解析PDF", "PDF转markdown", "提取论文内容", "公式转LaTeX", "mineru", "pdf2md");
  to search scientific papers / literature ("文献检索", "sciverse", "找论文",
  "semantic search papers"); or to bootstrap this toolchain on a new device
  ("配置文档解析环境", "新设备装 mineru/sciverse"). For generic PDF ops (merge,
  split, rotate, fill forms, plain text extract) prefer the built-in `pdf` skill.
---

# MinerU + SciVerse Toolkit

This skill covers **both setup and day-to-day use** of three capabilities. The
local CLI is not an MCP, and the routing/fallback logic spans tools — so this
guidance is needed on top of the raw MCP tool descriptions. Deep detail lives in
`reference.md`; read it when you need backends, REST endpoints, or disk/uninstall info.

## When NOT to use this skill
Generic PDF manipulation — merge, split, rotate, watermark, encrypt, fill a form,
or quick plain-text extraction — is better served by the built-in **`pdf`** skill
(pypdf/pdfplumber/reportlab). Use THIS skill when fidelity matters: scientific
papers, formulas → LaTeX, complex tables → HTML, multi-column or scanned/OCR docs,
or when you need literature search.

## Decision: which tool

| Need | Use | Token? |
|------|-----|--------|
| Parse ONE local doc, offline | local `pdf2md` / `mineru` | no |
| Parse a folder locally, keep it on-machine | `scripts/batch-local.sh` | no |
| Cloud parse, small files (≤20p/10MB, md only) | `mineru-cloud` MCP (Flash) | no |
| **Large-scale / batch / big files, spare the laptop** | `mineru-cloud` MCP (full) | **yes** `MINERU_API_TOKEN` |
| Search / semantic-search literature | `sciverse` MCP | **yes** `SCIVERSE_API_TOKEN` |

Rule of thumb: **single paper → local**; **batch/large → cloud**; **find papers → sciverse**, then feed the PDFs back into parsing.

## Fallback — the two parsers cover for each other
They are complementary; if the preferred one is unavailable, use the other:

- **Want local but it can't run** (mineru not installed, models not yet downloaded
  and you're offline, or the machine is busy) → **use `mineru-cloud`** (Flash mode
  needs no token; just smaller limits).
- **Want cloud but it can't run** (no `MINERU_API_TOKEN` and file >20p/10MB, or no
  network, or the API errors/quota) → **fall back to local `pdf2md`** (unlimited, offline).
- **A parse fails or returns garbage on one path** → retry the same file on the other
  path before giving up; report which path produced the result.
- **Batch is large but no cloud token** → run `scripts/batch-local.sh <dir>` locally
  instead of blocking on the token.

State which path you used when results differ, so the user knows the trade-off taken.

## Preflight — check tokens before using a token-gated tool
Before invoking `sciverse` or `mineru-cloud` in full mode, verify the token is set
(especially on a fresh device). Run the bundled checker **from this skill's directory**
(don't hardcode a home path — the skill may live under `~/.claude/skills/`,
`~/.agents/skills/`, or a project `.claude/skills/`):
```bash
bash "$(dirname "$0")/scripts/check.sh"   # or: cd into this skill dir, then: bash scripts/check.sh
```
If a required token is blank, **do not silently fail** — tell the user exactly what
to fill and where, then either proceed on the no-token path (local, or cloud Flash)
or wait. Put tokens in **your agent's own** MCP config (`~/.claude.json` for Claude Code;
`~/.codex/config.toml` for Codex; `~/.cursor/mcp.json` for Cursor; OpenCode's `opencode.json`):
- `SCIVERSE_API_TOKEN` blank → SciVerse can't run at all. Get it at
  https://sciverse.space/tokens (format `sv-...`). Token resolution order is:
  MCP-config `env` → `SCIVERSE_API_TOKEN` shell env → `~/.sciverse/credentials.json`
  (written by `sciverse auth login`). `check.sh` detects the credentials-file case too.
- `MINERU_API_TOKEN` blank → `mineru-cloud` still works in **Flash mode** (≤20p/10MB,
  md only). For scale, get a token at https://mineru.net (API management page).
  Meanwhile local `pdf2md` covers anything Flash can't.

## Usage

### Local parsing (no token, on this machine)
```bash
pdf2md paper.pdf                 # -> ./paper/  (markdown + json + images)
pdf2md https://arxiv.org/pdf/2604.21691   # URL ok: auto-downloads then parses
pdf2md paper.pdf out/            # custom output dir
pdf2md scan.pdf out/ -m ocr      # force OCR for scanned PDFs
pdf2md paper.pdf out/ -s 0 -e 9  # only pages 0..9
bash scripts/batch-local.sh ~/papers ~/papers_md   # whole folder, locally
```
`pdf2md` accepts a local path OR an http(s) URL (it downloads to a temp file first),
so local and cloud paths take the same kind of input.
Backends: `-b pipeline` (default, most compatible on Apple Silicon) |
`-b hybrid-auto-engine` / `vlm-auto-engine` (higher accuracy, heavier, downloads a
bigger model on first use). `MINERU_MODEL_SOURCE=modelscope|huggingface` switches model source.
The local install (`mineru[core]`) supports **all** these backends — pipeline models
are fetched at setup; vlm/hybrid models download lazily the first time you pick them.

### Cloud parsing (`mineru-cloud` MCP — tool `parse_documents`)
Ask in natural language; the MCP uploads/parses and saves to `OUTPUT_DIR` (`~/mineru-downloads`):
- "把这批 PDF 全部解析成 markdown：<dir or paths>"
- "解析这篇论文 https://arxiv.org/pdf/2509.22186"
- "解析 fileA 第1-5页、fileB 第2-9页"

### Literature search (`sciverse` MCP)
Tools: `search_papers`, `semantic_search`, `list_catalog`, `read_content`, `get_resource`.
- "用 sciverse 搜 KAN 相关近两年文献"
- "语义检索：low-rank adaptation 的后续工作"

## Setup on a new device
Idempotent bootstrap — never overwrites existing tokens, backs up first. Run it
**from this skill's directory** (path varies by install location):
```bash
cd "$(dirname SKILL.md)"   # the dir containing this skill
bash setup.sh
```
Installs MinerU CLI (`uv`), the `pdf2md` wrapper, adds the `sciverse` + `mineru-cloud`
MCP servers to `~/.claude.json` with **blank tokens**, creates `~/mineru-downloads`,
then prints the two-token manual step. Tokens are per-device/account and are
intentionally NOT stored in this skill (safe to sync the skill folder via git/dotfiles).

> **Scope note:** `setup.sh` is **Claude-Code-specific** — it writes only `~/.claude.json`.
> For Codex/Cursor/OpenCode, use the repo-level installer (`install/install.sh` in
> ares-agent-toolkit), which writes each agent's own config.
> **JSON note:** `setup.sh` round-trips `~/.claude.json` (content preserved, tokens & other
> servers untouched, backup written first), but it does re-serialize the file with 2-space
> indent — i.e. it reformats whitespace of Claude's global state file. Harmless but expected.
