#!/usr/bin/env python3
"""Apply the canonical MCP server defs (mcp/servers.json) into each agent's
native config, in that agent's own format and file. Idempotent. Tokens are
written BLANK and existing tokens are never overwritten.

Usage:
  python3 apply_mcp.py --agent claude --agent cursor ...   # specific agents
  python3 apply_mcp.py --agent all                          # all four
  python3 apply_mcp.py --agent all --home /tmp/sandbox      # test against fake HOME
  python3 apply_mcp.py --agent claude --dry-run             # show plan only

Each agent writes ONLY to its own file:
  claude   -> $HOME/.claude.json                 (JSON  mcpServers{})
  cursor   -> $HOME/.cursor/mcp.json             (JSON  mcpServers{})
  codex    -> $HOME/.codex/config.toml           (TOML  [mcp_servers.*])
  opencode -> $HOME/.config/opencode/opencode.json (JSON mcp{} local shape)
"""
import argparse, json, os, sys, shutil
from pathlib import Path

try:
    import tomllib  # py3.11+
except Exception:
    tomllib = None

AGENTS = ["claude", "cursor", "codex", "opencode"]


def load_servers(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    return data["servers"]


def expand_env(env: dict, home: Path) -> dict:
    out = {}
    for k, v in env.items():
        if isinstance(v, str) and v.startswith("~"):
            v = str(home) + v[1:]
        out[k] = v
    return out


def backup(p: Path):
    if p.exists():
        b = p.with_suffix(p.suffix + ".bak.agent-toolkit")
        shutil.copy2(p, b)
        return b
    return None


def report(agent, name, action, token_env, token_val, required):
    if action == "skipped":
        state = "exists (left untouched)"
    else:
        if not token_env:
            state = "added"
        elif token_val:
            state = "added (token already set)"
        elif required:
            state = "added — TOKEN BLANK, REQUIRED"
        else:
            state = "added — token blank (optional / free tier)"
    print(f"  [{agent}] {name}: {state}")


# ---------- JSON agents (claude / cursor) -------------------------------------
def apply_json_mcpservers(agent, file: Path, servers, home, dry):
    file.parent.mkdir(parents=True, exist_ok=True)
    cfg = {}
    if file.exists():
        try:
            cfg = json.loads(file.read_text(encoding="utf-8") or "{}")
        except json.JSONDecodeError:
            print(f"  [{agent}] ERROR: {file} is not valid JSON — skipping for safety")
            return
    m = cfg.setdefault("mcpServers", {})
    changed = False
    for name, s in servers.items():
        if name in m:
            report(agent, name, "skipped", s.get("token_env"), None, s.get("required"))
            continue
        entry = {"command": s["command"], "args": s["args"],
                 "env": expand_env(s.get("env", {}), home)}
        if agent == "claude" and s.get("timeout_sec"):
            entry["timeout"] = s["timeout_sec"]
        m[name] = entry
        changed = True
        tv = entry["env"].get(s.get("token_env", ""), "")
        report(agent, name, "added", s.get("token_env"), tv, s.get("required"))
    if changed and not dry:
        backup(file)
        file.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------- OpenCode (JSON, different shape) ----------------------------------
def apply_opencode(file: Path, servers, home, dry):
    file.parent.mkdir(parents=True, exist_ok=True)
    cfg = {}
    if file.exists():
        try:
            cfg = json.loads(file.read_text(encoding="utf-8") or "{}")
        except json.JSONDecodeError:
            print(f"  [opencode] ERROR: {file} is not valid JSON — skipping for safety")
            return
    cfg.setdefault("$schema", "https://opencode.ai/config.json")
    m = cfg.setdefault("mcp", {})
    changed = False
    for name, s in servers.items():
        if name in m:
            report("opencode", name, "skipped", s.get("token_env"), None, s.get("required"))
            continue
        m[name] = {
            "type": "local",
            "command": [s["command"]] + list(s["args"]),
            "environment": expand_env(s.get("env", {}), home),
            "enabled": True,
        }
        changed = True
        tv = m[name]["environment"].get(s.get("token_env", ""), "")
        report("opencode", name, "added", s.get("token_env"), tv, s.get("required"))
    if changed and not dry:
        backup(file)
        file.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------- Codex (TOML, append-if-absent) -----------------------------------
def codex_present(file: Path, name: str) -> bool:
    if not file.exists():
        return False
    if tomllib:
        try:
            data = tomllib.loads(file.read_text(encoding="utf-8"))
            return name in data.get("mcp_servers", {})
        except Exception:
            pass
    # fallback: text scan
    needle = f"[mcp_servers.{name}]"
    return needle in file.read_text(encoding="utf-8")


def toml_arr(items):
    return "[" + ", ".join('"' + str(i).replace('"', '\\"') + '"' for i in items) + "]"


def apply_codex(file: Path, servers, home, dry):
    file.parent.mkdir(parents=True, exist_ok=True)
    blocks = []
    for name, s in servers.items():
        if codex_present(file, name):
            report("codex", name, "skipped", s.get("token_env"), None, s.get("required"))
            continue
        env = expand_env(s.get("env", {}), home)
        b = [f"\n[mcp_servers.{name}]",
             f'command = "{s["command"]}"',
             f"args = {toml_arr(s['args'])}"]
        if s.get("timeout_sec"):
            b.append(f"startup_timeout_sec = {s['timeout_sec']}")
        if env:
            b.append(f"\n[mcp_servers.{name}.env]")
            for k, v in env.items():
                b.append(f'{k} = "{v}"')
        blocks.append("\n".join(b) + "\n")
        report("codex", name, "added", s.get("token_env"),
               env.get(s.get("token_env", ""), ""), s.get("required"))
    if blocks and not dry:
        backup(file)
        existing = file.read_text(encoding="utf-8") if file.exists() else ""
        if existing and not existing.endswith("\n"):
            existing += "\n"
        file.write_text(existing + "".join(blocks), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    here = Path(__file__).resolve().parent.parent
    ap.add_argument("--servers", default=str(here / "mcp" / "servers.json"))
    ap.add_argument("--agent", action="append", default=[],
                    help="claude|cursor|codex|opencode|all (repeatable)")
    ap.add_argument("--home", default=os.path.expanduser("~"))
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    agents = AGENTS if ("all" in a.agent or not a.agent) else a.agent
    home = Path(a.home)
    servers = load_servers(Path(a.servers))
    paths = {
        "claude":   home / ".claude.json",
        "cursor":   home / ".cursor" / "mcp.json",
        "codex":    home / ".codex" / "config.toml",
        "opencode": home / ".config" / "opencode" / "opencode.json",
    }
    print(f"Applying MCP servers {list(servers)} -> {agents}"
          + ("  (DRY RUN)" if a.dry_run else ""))
    for ag in agents:
        if ag not in paths:
            print(f"  [{ag}] unknown agent, skipped"); continue
        print(f"-- {ag}: {str(paths[ag]).replace(str(home), '~')}")
        if ag in ("claude", "cursor"):
            apply_json_mcpservers(ag, paths[ag], servers, home, a.dry_run)
        elif ag == "opencode":
            apply_opencode(paths[ag], servers, home, a.dry_run)
        elif ag == "codex":
            apply_codex(paths[ag], servers, home, a.dry_run)
    print("Done. Fill blank tokens in each agent's own config, then restart that agent.")


if __name__ == "__main__":
    main()
