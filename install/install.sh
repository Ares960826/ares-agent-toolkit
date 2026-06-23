#!/usr/bin/env bash
# agent-toolkit installer — install our DIY skills + MCP servers into whichever
# AI coding agents you use, each in its OWN config location/format. Idempotent;
# never overwrites existing tokens. No secrets are stored in this repo.
#
#   bash install/install.sh                 # auto-detect installed agents
#   bash install/install.sh --agents claude,codex
#   bash install/install.sh --with-mineru-cli   # also install local MinerU (~2GB)
#   bash install/install.sh --dry-run
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
AGENTS=""; WITH_CLI=0; DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents) AGENTS="$2"; shift 2;;
    --with-mineru-cli) WITH_CLI=1; shift;;
    --dry-run) DRY=1; shift;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

say(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }
note(){ printf '\033[1;33m  note:\033[0m %s\n' "$*"; }

# ---- 0) ensure bundled submodule skills (e.g. luffy-arm) are populated -------
# Some skills are vendored as git submodules; a plain `git clone` leaves them empty.
if [[ -f "$ROOT/.gitmodules" ]] && command -v git >/dev/null 2>&1; then
  git -C "$ROOT" submodule update --init --recursive >/dev/null 2>&1 \
    || note "couldn't init submodules; run: git -C \"$ROOT\" submodule update --init --recursive"
fi

# ---- detect agents ----------------------------------------------------------
detect(){
  local found=()
  [[ -e "$HOME_DIR/.claude.json" ]] || command -v claude >/dev/null 2>&1 && found+=(claude)
  { [[ -d "$HOME_DIR/.codex" ]] || command -v codex >/dev/null 2>&1; } && found+=(codex)
  { [[ -d "$HOME_DIR/.cursor" ]] || command -v cursor >/dev/null 2>&1; } && found+=(cursor)
  { [[ -d "$HOME_DIR/.config/opencode" ]] || command -v opencode >/dev/null 2>&1; } && found+=(opencode)
  printf '%s\n' "${found[@]:-}"
}
if [[ -z "$AGENTS" ]]; then
  AGENTS="$(detect | paste -sd, -)"
fi
[[ -n "$AGENTS" ]] || { echo "No agents detected. Pass --agents claude,codex,cursor,opencode"; exit 1; }
say "Target agents: $AGENTS"
IFS=',' read -r -a AGENT_ARR <<< "$AGENTS"

# ---- 1) shared local wrapper (agent-agnostic) -------------------------------
if [[ $DRY -eq 0 ]]; then
  mkdir -p "$HOME_DIR/.local/bin"
  install -m 0755 "$ROOT/skills/mineru-sciverse/pdf2md" "$HOME_DIR/.local/bin/pdf2md"
  say "Installed pdf2md -> ~/.local/bin/pdf2md"
  case ":$PATH:" in *":$HOME_DIR/.local/bin:"*) ;; *) note "add ~/.local/bin to PATH";; esac
fi

# ---- 2) skills (Agent Skills standard, cross-agent discovery) ---------------
# All four agents support SKILL.md and auto-discover from shared home dirs:
#   ~/.claude/skills  -> read by Claude Code, Cursor, OpenCode
#   ~/.agents/skills  -> read by Codex, Cursor, OpenCode
# So we only populate these two producer dirs (never .cursor/.opencode separately),
# choosing the minimal set that covers the targeted agents without needless dupes.
copy_skills(){  # $1 = dest dir
  local dest="$1"
  [[ $DRY -eq 1 ]] && { echo "  (dry) would copy skills -> ${dest/$HOME_DIR/\~}"; return; }
  mkdir -p "$dest"
  cp -R "$ROOT/skills/." "$dest/"
}
need_claude_dir=0; need_agents_dir=0
for ag in "${AGENT_ARR[@]}"; do
  case "$ag" in
    claude|cursor|opencode) need_claude_dir=1;;  # all read ~/.claude/skills
    codex) need_agents_dir=1;;                    # only Codex needs ~/.agents/skills
  esac
done
if [[ $need_claude_dir -eq 1 ]]; then
  say "Skills -> ~/.claude/skills  (discovered by Claude, Cursor, OpenCode)"
  copy_skills "$HOME_DIR/.claude/skills"
fi
if [[ $need_agents_dir -eq 1 ]]; then
  say "Skills -> ~/.agents/skills  (discovered by Codex, Cursor, OpenCode)"
  copy_skills "$HOME_DIR/.agents/skills"
fi
[[ $need_claude_dir -eq 1 && $need_agents_dir -eq 1 ]] && \
  note "Cursor/OpenCode read both dirs; skills are deduped by their unique 'name', so the same skill won't double-apply."

# ---- 3) MCP servers per agent (native format, idempotent) -------------------
say "Applying MCP servers (blank tokens, never clobbering existing)…"
DRY_FLAG=(); [[ $DRY -eq 1 ]] && DRY_FLAG=(--dry-run)
AG_FLAGS=(); for ag in "${AGENT_ARR[@]}"; do AG_FLAGS+=(--agent "$ag"); done
python3 "$ROOT/install/apply_mcp.py" "${AG_FLAGS[@]}" "${DRY_FLAG[@]}"

# ---- 4) optional heavy local CLI -------------------------------------------
if [[ $WITH_CLI -eq 1 ]]; then
  say "Installing local MinerU CLI (~2GB)…"
  [[ $DRY -eq 1 ]] || bash "$ROOT/skills/mineru-sciverse/setup.sh" || note "mineru setup had issues; see output"
fi

cat <<EOF

────────────────────────────────────────────────────────────────────
 Done. Fill blank tokens in EACH agent's OWN config, then restart it:
   SciVerse  SCIVERSE_API_TOKEN  (required)  -> https://sciverse.space/tokens
   MinerU    MINERU_API_TOKEN    (optional)  -> https://mineru.net
 Config files: claude=~/.claude.json  cursor=~/.cursor/mcp.json
               codex=~/.codex/config.toml  opencode=~/.config/opencode/opencode.json
 See docs/COMPATIBILITY.md for which agents share dirs and which don't.
────────────────────────────────────────────────────────────────────
EOF
