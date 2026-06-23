# agent-toolkit

Portable, single-source-of-truth repo for **my DIY agent skills + MCP servers**, with a
one-command installer that sets them up across **Claude Code, Codex, Cursor, and OpenCode**
— each in its own native config, idempotently, **never overwriting tokens** and **never
storing secrets**.

Inspired by [`anthropics/skills`](https://github.com/anthropics/skills), extended to also
carry MCP server definitions and a multi-agent installer.

## What's inside
```
skills/
  mineru-sciverse/    # high-fidelity PDF→Markdown (MinerU) + literature search (SciVerse)
  learning-mechanics/ # applied "learning mechanics" DL-engineering reference (from arXiv 2604.21691)
  tentacle/           # local Claude Code + native SSH into a remote Linux server (submodule)
mcp/
  servers.json        # canonical, agent-neutral MCP server defs (source of truth)
install/
  install.sh          # detect agents → copy skills → apply MCP (native format) → fill-token notes
  apply_mcp.py        # translates servers.json into each agent's config (idempotent)
docs/
  COMPATIBILITY.md    # per-agent skill/MCP paths + which agents share vs. stay separate
```

## Quick start (new device)
```bash
git clone --recurse-submodules <this-repo> ~/agent-toolkit   # --recurse-submodules pulls the tentacle skill
cd ~/agent-toolkit
bash install/install.sh                 # auto-detects installed agents
# optional: also install local MinerU CLI (~2GB, offline parsing)
bash install/install.sh --with-mineru-cli
```
Then fill the two tokens in **each agent's own** config and restart that agent:
- `SCIVERSE_API_TOKEN` (required) — https://sciverse.space/tokens
- `MINERU_API_TOKEN` (optional; blank = free Flash mode) — https://mineru.net

Useful flags: `--agents claude,codex` · `--dry-run`.

All four agents implement the **Agent Skills** standard and cross-read each other's home
skill dirs, so the installer only populates `~/.claude/skills` (read by Claude/Cursor/OpenCode)
and `~/.agents/skills` (read by Codex/Cursor/OpenCode) — never per-agent duplicates. MCP config
is the opposite: each agent has its own file/format, so it's written four separate ways. See
`docs/COMPATIBILITY.md`.

## Design rules
- **One source of truth** (`mcp/servers.json`); the installer fans it out per agent.
- **Each agent in its own lane** — only ever writes its own config file. No cross-writes
  (this is what prevents one agent from clobbering another's setup).
- **Idempotent** — re-runnable; existing servers and tokens are left untouched.
- **No secrets in git** — tokens are written blank and filled per device; `.gitignore`
  blocks real-config filenames as a backstop.

See `docs/COMPATIBILITY.md` for exact paths and the share-vs-separate matrix.

## Verify
```bash
bash skills/mineru-sciverse/scripts/check.sh   # status of local tools + tokens
python3 install/apply_mcp.py --agent all --home /tmp/sandbox   # safe dry test
```
