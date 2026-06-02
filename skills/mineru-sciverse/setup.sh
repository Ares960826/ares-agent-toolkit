#!/usr/bin/env bash
# Bootstrap the MinerU + SciVerse toolkit on a new device.
# Idempotent: safe to re-run. NEVER overwrites existing API tokens.
#
#   bash ~/.claude/skills/mineru-sciverse/setup.sh
#
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_JSON="${HOME}/.claude.json"
BIN_DIR="${HOME}/.local/bin"
OUT_DIR="${HOME}/mineru-downloads"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# 1) uv -----------------------------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  warn "uv not found. Install it first:  curl -LsSf https://astral.sh/uv/install.sh | sh"
  warn "Then re-run this script."
  exit 1
fi
say "uv: $(uv --version)"

# 2) MinerU local CLI ---------------------------------------------------------
say "Installing/updating MinerU local CLI (uv tool, isolated)…"
uv tool install -U "mineru[core]" >/dev/null
say "mineru: $("${BIN_DIR}/mineru" --version 2>/dev/null || mineru --version)"

# 3) pdf2md wrapper -----------------------------------------------------------
mkdir -p "$BIN_DIR"
install -m 0755 "${SKILL_DIR}/pdf2md" "${BIN_DIR}/pdf2md"
say "Installed wrapper: ${BIN_DIR}/pdf2md"
case ":$PATH:" in *":${BIN_DIR}:"*) ;; *) warn "${BIN_DIR} is not on PATH — add it to your shell rc.";; esac

# 4) output dir ---------------------------------------------------------------
mkdir -p "$OUT_DIR"
say "Cloud output dir: ${OUT_DIR}"

# 5) MCP servers in ~/.claude.json (blank tokens, never clobber existing) ------
if [[ ! -f "$CLAUDE_JSON" ]]; then
  warn "${CLAUDE_JSON} not found — run the agent once to create it, then re-run."
  exit 1
fi
cp "$CLAUDE_JSON" "${CLAUDE_JSON}.bak.mineru-sciverse-setup"
OUT_DIR="$OUT_DIR" python3 - "$CLAUDE_JSON" <<'PY'
import json, os, sys
p = sys.argv[1]
out_dir = os.environ["OUT_DIR"]
d = json.load(open(p))
m = d.setdefault("mcpServers", {})
added = []
if "sciverse" not in m:
    m["sciverse"] = {
        "command": "npx",
        "args": ["-y", "sciverse-mcp-server"],
        "env": {"SCIVERSE_API_TOKEN": ""},
        "timeout": 20,
    }
    added.append("sciverse")
if "mineru-cloud" not in m:
    m["mineru-cloud"] = {
        "command": "uvx",
        "args": ["mineru-open-mcp"],
        "env": {"MINERU_API_TOKEN": "", "OUTPUT_DIR": out_dir},
        "timeout": 30,
    }
    added.append("mineru-cloud")
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
print("ADDED:", ", ".join(added) if added else "(none — already present, tokens left untouched)")
PY

cat <<EOF

────────────────────────────────────────────────────────────────────
 Done. Manual step — fill the two tokens (only if blank), then restart:

   ~/.claude.json  →  mcpServers.sciverse.env.SCIVERSE_API_TOKEN
       get it at  https://sciverse.space/tokens   (format sv-...)

   ~/.claude.json  →  mcpServers.mineru-cloud.env.MINERU_API_TOKEN
       get it at  https://mineru.net  (API management page)

 Local 'pdf2md' works now with no token. 'mineru-cloud' works in free
 Flash mode with no token (<=20p/10MB); fill MINERU_API_TOKEN for scale.
 Backup written: ${CLAUDE_JSON}.bak.mineru-sciverse-setup
────────────────────────────────────────────────────────────────────
EOF
