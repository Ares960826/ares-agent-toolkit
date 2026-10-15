#!/usr/bin/env bash
# Bootstrap the LOCAL part of the MinerU + SciVerse toolkit on a new device:
# MinerU CLI, the pdf2md wrapper and the cloud output dir. Idempotent.
# It does NOT edit any agent config and never handles tokens: MCP servers
# (sciverse, mineru-cloud) and the with-secret wrapper are installed by the repo
# installer, ares-agent-toolkit/install/install.sh.
#
#   bash ~/.claude/skills/mineru-sciverse/setup.sh
#
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
uv tool install --upgrade "mineru>=4,<5" >/dev/null
say "mineru: $("${BIN_DIR}/mineru" --version 2>/dev/null || mineru --version)"

# 3) pdf2md wrapper -----------------------------------------------------------
mkdir -p "$BIN_DIR"
install -m 0755 "${SKILL_DIR}/pdf2md" "${BIN_DIR}/pdf2md"
say "Installed wrapper: ${BIN_DIR}/pdf2md"
case ":$PATH:" in *":${BIN_DIR}:"*) ;; *) warn "${BIN_DIR} is not on PATH — add it to your shell rc.";; esac

# 4) output dir ---------------------------------------------------------------
mkdir -p "$OUT_DIR"
say "Cloud output dir: ${OUT_DIR}"

# 5) MCP servers + tokens: handled by the repo installer -------------------------
cat <<EOF

────────────────────────────────────────────────────────────────────
 Local tooling done: mineru CLI + pdf2md (no token needed).

 MCP servers (sciverse, mineru-cloud) are NOT configured by this script.
 From an ares-agent-toolkit checkout run:
   bash install/install.sh --agents claude,codex      # adds servers via with-secret
 Tokens live only in the OS secret store, never in agent configs:
   macOS: printf 'add-generic-password -U -s "claude-mcp:NAME" -a "%s" -w "VALUE"\n' "\$USER" | security -i
   NAME = SCIVERSE_API_TOKEN (required, https://sciverse.space/tokens)
          MINERU_API_TOKEN   (optional, https://mineru.net)
 Then check: bash "${SKILL_DIR}/scripts/check.sh" --online
────────────────────────────────────────────────────────────────────
EOF
