#!/usr/bin/env bash
# Bootstrap the LOCAL part of the MinerU + SciVerse toolkit on a new device:
# MinerU CLI, the official mineru skill, the pdf2md wrapper and the cloud
# output dir. Idempotent: run it again at any time to upgrade all of them.
# MCP packages (@latest) need no upgrade step; they follow on each agent start.
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
MINERU_BIN="${BIN_DIR}/mineru"; [ -x "$MINERU_BIN" ] || MINERU_BIN="$(command -v mineru || true)"
before=""
if [ -n "$MINERU_BIN" ]; then
  before="$("$MINERU_BIN" --version 2>/dev/null | head -1 || true)"
  # a running local server holds the old install open; stop it before replacing files
  # `server status` exits 0 either way, so read its text
  if status="$("$MINERU_BIN" server status 2>&1)" && ! printf '%s' "$status" | grep -qi 'not running'; then
    say "Stopping the running MinerU server before the upgrade (start it again with: mineru server start)"
    "$MINERU_BIN" server stop >/dev/null 2>&1 || warn "could not stop the MinerU server; continuing"
  fi
fi
say "Installing/updating MinerU local CLI (uv tool, isolated)…"
uv tool install --upgrade "mineru>=4,<5" >/dev/null
after="$("${BIN_DIR}/mineru" --version 2>/dev/null | head -1 || mineru --version | head -1)"
say "mineru: ${after}${before:+  (was: ${before})}"
if command -v mineru-kit >/dev/null 2>&1 && ! mineru-kit models verify --tier standard >/dev/null 2>&1; then
  warn "standard-tier models are not ready; download them with:  mineru-kit models download --tier standard"
fi

# 3) pdf2md wrapper -----------------------------------------------------------
mkdir -p "$BIN_DIR"
install -m 0755 "${SKILL_DIR}/pdf2md" "${BIN_DIR}/pdf2md"
say "Installed wrapper: ${BIN_DIR}/pdf2md"
case ":$PATH:" in *":${BIN_DIR}:"*) ;; *) warn "${BIN_DIR} is not on PATH — add it to your shell rc.";; esac

# 4) official `mineru` skill (referenced, not vendored) ------------------------
# Installed and updated from upstream, so it follows each official release.
OFFICIAL_ADD='npx --yes skills add opendatalab/MinerU --skill mineru --global --agent claude-code --agent codex --agent cursor --agent opencode --yes'
if command -v npx >/dev/null 2>&1; then
  if [ -d "${HOME}/.agents/skills/mineru" ]; then
    say "Updating the official mineru skill…"
    npx --yes skills update mineru --global --yes >/dev/null 2>&1 || warn "skill update failed; run: npx skills update mineru --global --yes"
  else
    say "Installing the official mineru skill…"
    $OFFICIAL_ADD >/dev/null 2>&1 || warn "skill install failed; run: $OFFICIAL_ADD"
  fi
else
  warn "npx not found; install the official mineru skill with: $OFFICIAL_ADD"
fi

# 5) output dir ---------------------------------------------------------------
mkdir -p "$OUT_DIR"
say "Cloud output dir: ${OUT_DIR}"

# 6) MCP servers + tokens: handled by the repo installer -------------------------
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
