# Agent compatibility & path rules

Where each agent looks for **skills** and **MCP config**, and — critically — which
agents **share** a location (install once) vs. need **separate** installs (and must
not write into each other's files).

## Skills (SKILL.md)

| Agent | Skills location | Shares with Claude Code? |
|-------|-----------------|--------------------------|
| **Claude Code** | `~/.claude/skills/<name>/SKILL.md` | — (this is the origin) |
| **Codex** (OpenAI CLI) | `~/.agents/skills/<name>/SKILL.md` (user) · `.agents/skills/` (repo) | **No** — different dir. Same SKILL.md *format* though, so the files are portable; the installer copies them into both. |
| **Cursor** | ❌ no SKILL.md system. Uses project rules `.cursor/rules/*.mdc` (+ `AGENTS.md` for instructions). | **No** — must hand-port skill guidance into a rule. |
| **OpenCode** | ❌ no SKILL.md system. Uses `AGENTS.md` (+ `instructions` in config). | **No** — reference `skills/*/SKILL.md` from an `AGENTS.md`. |

> The `~/.agents/skills` path is an emerging vendor-neutral convention. Claude Code does
> **not** read it today (it reads `~/.claude/skills`), so Claude and Codex skill dirs are
> separate and the installer populates each. If a future Claude Code reads `~/.agents/skills`,
> these become a shared location — re-check before symlinking.

## MCP servers

| Agent | MCP config file | Format / key | Entry shape |
|-------|-----------------|--------------|-------------|
| **Claude Code** | `~/.claude.json` | JSON · `mcpServers{}` | `{command, args, env, timeout}` |
| **Cursor** | `~/.cursor/mcp.json` (global) · `.cursor/mcp.json` (project) | JSON · `mcpServers{}` | `{command, args, env}` |
| **Codex** | `~/.codex/config.toml` (global) · `.codex/config.toml` (project, trusted) | TOML · `[mcp_servers.<name>]` | `command`, `args`, `startup_timeout_sec`, `[…​.env]` |
| **OpenCode** | `~/.config/opencode/opencode.json` (global) · `opencode.json` (project) | JSON · `mcp{}` | `{type:"local", command:[…], environment, enabled}` |

### Who shares a tool system — read this before editing configs
- **Claude Code and Cursor use the SAME JSON shape** (`mcpServers{}` with `command/args/env`)
  but **DIFFERENT files** (`~/.claude.json` vs `~/.cursor/mcp.json`). You can copy a server
  block between them verbatim, but they are independent — editing one does not affect the other.
- **Codex is fully separate**: its own file (`~/.codex/config.toml`) and its own format (TOML).
  ⚠️ **Codex must never write to `~/.claude.json`.** (That cross-write is exactly the bug that
  motivated this repo.) The installer here only ever touches each agent's own file.
- **OpenCode is fully separate** and uses a *different entry shape* (`command` is an array
  including the binary; env key is `environment`, not `env`). Don't paste a Claude/Cursor
  block into it unchanged.
- **No two agents share an MCP config file.** So there is no clobber risk *between* agents —
  the only clobber risk is an agent editing a file that isn't its own. Keep each agent to its lane.

### Single source of truth
`mcp/servers.json` (agent-neutral) is the canonical definition. `install/apply_mcp.py`
translates it into each agent's native file. To change a server, edit `servers.json` and
re-run the installer — every agent stays in sync, in its own format, without manual TOML/JSON juggling.

## Tokens
Tokens live **only** in each device's real config files, written **blank** by the installer
and filled by you. They are **never** stored in this repo. `.gitignore` blocks the common
real-config filenames as a backstop.
