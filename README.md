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
  contrastive-reading/ # 对比阅读: anchor on papers you already know, report only the delta
  learning-mechanics/ # applied "learning mechanics" DL-engineering reference (from arXiv 2604.21691)
  luffy-arm/           # multiple SSH targets, key/password sessions (v1.8.0 submodule)
mcp/
  servers.json        # canonical, agent-neutral MCP server defs (source of truth)
install/
  install.sh          # detect agents → symlink skills → apply MCP (native format) → fill-token notes
  apply_mcp.py        # translates servers.json into each agent's config (idempotent)
docs/
  COMPATIBILITY.md    # per-agent skill/MCP paths + which agents share vs. stay separate
```

Luffy Arm v1.8.0 supports named key/password targets. See [registration and upgrade](docs/LUFFY_ARM.md).

## Quick start (new device)
```bash
git clone --recurse-submodules <this-repo> ~/agent-toolkit   # --recurse-submodules pulls the luffy-arm skill
cd ~/agent-toolkit
bash install/install.sh                 # auto-detects installed agents
# optional: also install local MinerU CLI (~2GB, offline parsing)
bash install/install.sh --with-mineru-cli
```
Then store each token **once** in the OS secret store and restart the agents. Token-gated
servers are launched through `bin/with-secret` (installed to `~/.claude/bin/with-secret`),
so no agent config ever contains a token:
- `SCIVERSE_API_TOKEN` (required) — https://sciverse.space/tokens
- `MINERU_API_TOKEN` (optional; the MinerU token is a JWT and expires) — https://mineru.net

```bash
# macOS Keychain (Linux: secret-tool store --label="claude-mcp:NAME" service "claude-mcp:NAME")
printf 'add-generic-password -U -s "claude-mcp:NAME" -a "%s" -w "VALUE"\n' "$USER" | security -i
```
`mineru-cloud` uploads documents to mineru.net; agents must get user consent per request.

Useful flags: `--agents claude,codex` · `--dry-run`.

All four agents implement the **Agent Skills** standard and cross-read each other's home
skill dirs, so the installer only populates `~/.claude/skills` (read by Claude/Cursor/OpenCode)
and `~/.agents/skills` (read by Codex/Cursor/OpenCode) — never per-agent duplicates. Skills are
symlinked to this checkout (an old copied install is moved to `~/.claude/backups/` first), so
`git pull` updates every agent. The official `mineru` skill is not vendored: `setup.sh` installs and updates it from upstream. MCP config
is the opposite: each agent has its own file/format, so it's written four separate ways. See
`docs/COMPATIBILITY.md`.

## Design rules
- **One source of truth** (`mcp/servers.json`); the installer fans it out per agent.
- **Each agent in its own lane** — only ever writes its own config file. No cross-writes
  (this is what prevents one agent from clobbering another's setup).
- **Idempotent** — re-runnable; existing servers and tokens are left untouched.
- **No secrets in git or configs** — tokens live only in the OS secret store and are injected
  at start-up by `with-secret`; `.gitignore` blocks real-config filenames as a backstop.

See `docs/COMPATIBILITY.md` for exact paths and the share-vs-separate matrix.

## Verify
```bash
bash skills/mineru-sciverse/scripts/check.sh --online   # local tools + token source/expiry/probe
python3 install/apply_mcp.py --agent all --home /tmp/sandbox   # safe dry test
```
