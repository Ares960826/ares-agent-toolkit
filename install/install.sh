#!/usr/bin/env bash
# agent-toolkit installer — install our DIY skills + MCP servers into whichever
# AI coding agents you use, each in its OWN config location/format. Idempotent;
# never overwrites existing MCP entries. Skills are symlinked, not copied, so a
# `git pull` in this checkout updates every agent. No secrets are stored in this repo or in any
# agent config: tokens live in the OS secret store and are injected by with-secret.
#
#   bash install/install.sh                 # auto-detect installed agents
#   bash install/install.sh --agents claude,codex
#   bash install/install.sh --with-mineru-cli   # also install local MinerU (~2GB)
#   bash install/install.sh --dry-run
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
TILDE="~"   # literal ~ for messages (bash 3.2 keeps a backslash in ${var/x/\~})
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
if [[ $DRY -eq 0 && -f "$ROOT/.gitmodules" ]] && command -v git >/dev/null 2>&1; then
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
  # secret wrapper used by token-gated MCP servers (path must match mcp/servers.json)
  if [[ -e "$HOME_DIR/.claude/bin/with-secret" ]]; then
    note "~/.claude/bin/with-secret already exists; left untouched"
  else
    mkdir -p "$HOME_DIR/.claude/bin"
    install -m 0755 "$ROOT/bin/with-secret" "$HOME_DIR/.claude/bin/with-secret"
    say "Installed with-secret -> ~/.claude/bin/with-secret"
  fi
fi

# ---- 2) skills (Agent Skills standard, cross-agent discovery) ---------------
# All four agents support SKILL.md and auto-discover from shared home dirs:
#   ~/.claude/skills  -> read by Claude Code, Cursor, OpenCode
#   ~/.agents/skills  -> read by Codex, Cursor, OpenCode
# So we only populate these two producer dirs (never .cursor/.opencode separately),
# choosing the minimal set that covers the targeted agents without needless dupes.
# Codex documents ~/.agents/skills as its user skills location and follows symlinks.
# An existing symlink to somewhere else (e.g. the official `mineru` skill) is kept.
BACKUP_DIR="$HOME_DIR/.claude/backups/agent-toolkit-skills-$(date +%Y%m%d-%H%M%S)"
link_skills(){  # $1 = dest dir; symlink every skill dir that has a SKILL.md
  local dest="$1" src name target current
  [[ $DRY -eq 1 ]] || mkdir -p "$dest"
  for src in "$ROOT"/skills/*/; do
    src="${src%/}"; name="$(basename "$src")"
    [[ -f "$src/SKILL.md" ]] || continue            # skips empty submodules
    target="$dest/$name"
    if [[ "$name" == luffy-arm ]]; then
      # luffy-arm ships its own installer (product allowlist + companion switches).
      [[ $DRY -eq 1 ]] && { echo "  (dry) would run luffy-arm installer -> $dest"; continue; }
      [[ -f "$src/install.sh" ]] || { echo "luffy-arm submodule is not populated" >&2; return 1; }
      LUFFY_ARM_DIR="$dest" bash "$src/install.sh"
      continue
    fi
    if [[ -L "$target" ]]; then
      current="$(readlink "$target")"
      if [[ "$current" == "$src" ]]; then continue; fi
      note "$name: ${target/$HOME_DIR/$TILDE} is a symlink to $current; left untouched"
      continue
    fi
    if [[ -e "$target" ]]; then                      # an old copied install: back it up, then link
      if [[ $DRY -eq 1 ]]; then echo "  (dry) would back up and link $name"; continue; fi
      mkdir -p "$BACKUP_DIR"
      mv "$target" "$BACKUP_DIR/$name"
      note "$name: previous copy moved to ${BACKUP_DIR/$HOME_DIR/$TILDE}/$name"
    elif [[ $DRY -eq 1 ]]; then
      echo "  (dry) would link $name"; continue
    fi
    ln -s "$src" "$target"
  done
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
  link_skills "$HOME_DIR/.claude/skills"
fi
if [[ $need_agents_dir -eq 1 ]]; then
  say "Skills -> ~/.agents/skills  (discovered by Codex, Cursor, OpenCode)"
  link_skills "$HOME_DIR/.agents/skills"
fi
[[ $need_claude_dir -eq 1 && $need_agents_dir -eq 1 ]] && \
  note "Cursor/OpenCode read both dirs and may list each skill twice (same-name skills are not merged). Target only the agents you use."

# ---- 3) MCP servers per agent (native format, idempotent) -------------------
say "Applying MCP servers (tokens via secret store, never clobbering existing)…"
DRY_FLAG=(); [[ $DRY -eq 1 ]] && DRY_FLAG=(--dry-run)
AG_FLAGS=(); for ag in "${AGENT_ARR[@]}"; do AG_FLAGS+=(--agent "$ag"); done
python3 "$ROOT/install/apply_mcp.py" "${AG_FLAGS[@]}" ${DRY_FLAG[@]+"${DRY_FLAG[@]}"}

# ---- 4) optional heavy local CLI -------------------------------------------
if [[ $WITH_CLI -eq 1 ]]; then
  say "Installing local MinerU CLI (~2GB)…"
  [[ $DRY -eq 1 ]] || bash "$ROOT/skills/mineru-sciverse/setup.sh" || note "mineru setup had issues; see output"
fi

cat <<EOF

────────────────────────────────────────────────────────────────────
 Done. Store each token ONCE in the OS secret store (never in a config), then
 restart the agents:
   SciVerse  SCIVERSE_API_TOKEN  (required)  -> https://sciverse.space/tokens
   MinerU    MINERU_API_TOKEN    (optional)  -> https://mineru.net
 macOS : printf 'add-generic-password -U -s "claude-mcp:NAME" -a "%s" -w "VALUE"\n' "\$USER" | security -i
 Linux : secret-tool store --label="claude-mcp:NAME" service "claude-mcp:NAME"
 Check : bash ~/.claude/skills/mineru-sciverse/scripts/check.sh --online
 mineru-cloud UPLOADS documents to mineru.net: agents must ask before using it.
 See docs/COMPATIBILITY.md for which agents share dirs and which don't.
────────────────────────────────────────────────────────────────────
EOF
