# Agent compatibility & path rules

Where each agent looks for **skills** and **MCP config**, and — critically — which
agents **share** a location (install once) vs. need **separate** installs (and must
not write into each other's files).

## Skills (SKILL.md)

**All four agents support the Agent Skills standard (SKILL.md).** They also cross-read each
other's home skill dirs, so you do NOT install into all four — two producer dirs cover everyone.

Home-level discovery (verified against each vendor's docs, 2026-06):

| Agent | Reads its own dir | ALSO reads (compat) |
|-------|-------------------|---------------------|
| **Claude Code** | `~/.claude/skills/` | — |
| **Codex** | `~/.agents/skills/` | (`~/.codex/skills/` legacy alias on some builds) |
| **Cursor** | `~/.cursor/skills/`, `~/.agents/skills/` | **`~/.claude/skills/`**, `~/.codex/skills/` |
| **OpenCode** | `~/.config/opencode/skills/` | **`~/.claude/skills/`**, `~/.agents/skills/` |

### Which dirs are shared → where the installer writes
- **`~/.claude/skills/`** is read by **Claude Code + Cursor + OpenCode** (3 of 4).
- **`~/.agents/skills/`** is read by **Codex + Cursor + OpenCode** (3 of 4).
- Their union covers all four, and every agent reads at least one. So the installer writes
  skills to **only these two dirs**:
  - `~/.claude/skills/` whenever Claude / Cursor / OpenCode is a target;
  - `~/.agents/skills/` only when Codex is a target.
  Cursor and OpenCode are "aggregators" — they pick the skills up automatically; we never
  write into `.cursor/skills` or `.config/opencode/skills`.
- No single dir is read by **both** Claude and Codex, so two dirs is the minimum. When both a
  `~/.claude/skills` consumer and Codex are present, Cursor/OpenCode see the skill in both dirs;
  the Agent Skills spec keys skills by a unique `name`, so they **dedupe** and it won't double-apply.
- Project-level equivalents (`.agents/skills/`, `.claude/skills/`, `.cursor/skills/`,
  `.opencode/skills/`) work the same way if you'd rather colocate a skill with a repo.

> This is the genuine "shared tool system" case: **Cursor and OpenCode share Claude Code's
> `~/.claude/skills`** (and Codex's `~/.agents/skills`). MCP config, by contrast, is NOT shared —
> see below.

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
