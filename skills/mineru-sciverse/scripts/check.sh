#!/usr/bin/env bash
# check.sh — preflight status for the MinerU + SciVerse toolkit.
# Reports what's installed and whether each token is set (without printing secrets).
set -euo pipefail
CLAUDE_JSON="${HOME}/.claude.json"

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
no()   { printf '  \033[1;31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

echo "MinerU + SciVerse — status"
echo "── local tooling ──"
command -v uv      >/dev/null 2>&1 && ok "uv: $(uv --version)"        || no "uv not found (install: curl -LsSf https://astral.sh/uv/install.sh | sh)"
command -v mineru  >/dev/null 2>&1 && ok "mineru: $(mineru --version 2>/dev/null)" || no "mineru CLI not installed (run setup.sh)"
command -v pdf2md  >/dev/null 2>&1 && ok "pdf2md wrapper on PATH"     || warn "pdf2md not on PATH (run setup.sh; ensure ~/.local/bin on PATH)"
if [ -d "${HOME}/.cache/modelscope" ] || [ -d "${HOME}/.cache/huggingface" ]; then ok "parse models cached"; else warn "no model cache yet (first local parse will download ~1GB)"; fi

echo "── MCP servers / tokens ──"
if [ ! -f "$CLAUDE_JSON" ]; then no "~/.claude.json missing (start the agent once, then run setup.sh)"; exit 0; fi
python3 - "$CLAUDE_JSON" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])).get("mcpServers", {})
G="\033[1;32m"; R="\033[1;31m"; Y="\033[1;33m"; Z="\033[0m"
def line(sym,col,msg): print(f"  {col}{sym}{Z} {msg}")
for name, label, var, required in [
    ("sciverse","SciVerse (literature search)","SCIVERSE_API_TOKEN",True),
    ("mineru-cloud","MinerU cloud (batch/large parse)","MINERU_API_TOKEN",False),
]:
    s = m.get(name)
    if not s:
        line("✗",R,f"{label}: server NOT configured — run setup.sh"); continue
    tok = (s.get("env") or {}).get(var,"")
    if tok:
        line("✓",G,f"{label}: token set")
    elif required:
        line("✗",R,f"{label}: token BLANK → get sv-... at https://sciverse.space/tokens")
    else:
        line("!",Y,f"{label}: token blank → Flash mode only (≤20p/10MB). Token: https://mineru.net")
PY
echo "Done. Blank required token → fill in ~/.claude.json and restart the agent."
