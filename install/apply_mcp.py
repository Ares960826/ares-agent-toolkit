#!/usr/bin/env python3
"""Apply the canonical MCP server defs (mcp/servers.json) into each agent's
native config, in that agent's own format and file. Idempotent; existing
entries are never overwritten. Tokens are never written into any config:
servers with a token_env are launched as `with-secret [--optional] TOKEN_ENV
-- cmd ...`, which reads the value from the OS secret store at start-up
(--optional for required:false servers, so they still start without a token).

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
import argparse, json, os, re, shutil, tempfile, time
from pathlib import Path

try:
    import tomllib  # py3.11+
except Exception:
    tomllib = None

AGENTS = ["claude", "cursor", "codex", "opencode"]


def load_servers(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    return data["servers"], data.get("secret_wrapper")


def launch(s: dict, wrapper, home: Path):
    """Return (command, args, env) for a server, wrapping token-gated ones."""
    env = expand_env(s.get("env", {}), home)
    tok = s.get("token_env")
    env.pop(tok, None)
    if tok and wrapper:
        w = str(home) + wrapper[1:] if wrapper.startswith("~") else wrapper
        names = [tok] if s.get("required") else ["--optional", tok]
        return w, [*names, "--", s["command"], *s["args"]], env
    return s["command"], list(s["args"]), env


def expand_env(env: dict, home: Path) -> dict:
    out = {}
    for k, v in env.items():
        if isinstance(v, str) and v.startswith("~"):
            v = str(home) + v[1:]
        out[k] = v
    return out


def backup(p: Path):
    """Copy p to a timestamped sibling; never overwrites an earlier backup."""
    p = p.resolve()  # a dotfile-managed symlink: back up and edit the real file
    if not p.exists():
        return None
    stamp = time.strftime("%Y%m%d-%H%M%S")
    b = p.with_name(f"{p.name}.bak.agent-toolkit-{stamp}")
    n = 1
    while b.exists():
        b = p.with_name(f"{p.name}.bak.agent-toolkit-{stamp}-{n}")
        n += 1
    shutil.copy2(p, b)
    return b


def write_atomic(p: Path, text: str):
    """Write via a temp file in the same directory, then rename over p (keeps its mode)."""
    p = p.resolve()  # keep a symlinked config a symlink; replace its target
    p.parent.mkdir(parents=True, exist_ok=True)
    mode = (p.stat().st_mode & 0o777) if p.exists() else 0o600
    fd, tmp = tempfile.mkstemp(dir=p.parent, prefix=p.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, p)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def report(agent, name, action, token_env, required):
    if action == "skipped":
        state = "exists (left untouched)"
    elif not token_env:
        state = "added"
    else:
        need = "REQUIRED" if required else "optional"
        state = f"added — token read from secret store claude-mcp:{token_env} ({need})"
    print(f"  [{agent}] {name}: {state}")


# ---------- JSON agents (claude / cursor) -------------------------------------
def apply_json_mcpservers(agent, file: Path, servers, wrapper, home, dry):
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
            report(agent, name, "skipped", s.get("token_env"), s.get("required"))
            continue
        cmd, args, env = launch(s, wrapper, home)
        entry = {"command": cmd, "args": args, "env": env}
        if agent == "claude" and s.get("timeout_sec"):
            entry["timeout"] = s["timeout_sec"]
        m[name] = entry
        changed = True
        report(agent, name, "added", s.get("token_env"), s.get("required"))
    if changed and not dry:
        backup(file)
        write_atomic(file, json.dumps(cfg, ensure_ascii=False, indent=2))


# ---------- OpenCode (JSON, different shape) ----------------------------------
def apply_opencode(file: Path, servers, wrapper, home, dry):
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
            report("opencode", name, "skipped", s.get("token_env"), s.get("required"))
            continue
        cmd, args, env = launch(s, wrapper, home)
        m[name] = {
            "type": "local",
            "command": [cmd] + args,
            "environment": env,
            "enabled": True,
        }
        changed = True
        report("opencode", name, "added", s.get("token_env"), s.get("required"))
    if changed and not dry:
        backup(file)
        write_atomic(file, json.dumps(cfg, ensure_ascii=False, indent=2))


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
    text = file.read_text(encoding="utf-8")
    pat = rf'^\s*\[mcp_servers\.(?:{re.escape(name)}|"{re.escape(name)}")(?:\]|\.)'
    return re.search(pat, text, re.M) is not None


def toml_str(value) -> str:
    """TOML basic string: escape backslash, quote and control characters."""
    out = []
    for ch in str(value):
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20 or ord(ch) == 0x7F:
            out.append(f"\\u{ord(ch):04x}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def toml_key(key: str) -> str:
    return key if re.fullmatch(r"[A-Za-z0-9_-]+", key) else toml_str(key)


def toml_arr(items):
    return "[" + ", ".join(toml_str(i) for i in items) + "]"


def apply_codex(file: Path, servers, wrapper, home, dry):
    blocks = []
    for name, s in servers.items():
        if codex_present(file, name):
            report("codex", name, "skipped", s.get("token_env"), s.get("required"))
            continue
        cmd, args, env = launch(s, wrapper, home)
        b = [f"\n[mcp_servers.{toml_key(name)}]",
             f"command = {toml_str(cmd)}",
             f"args = {toml_arr(args)}"]
        if s.get("timeout_sec"):
            b.append(f"startup_timeout_sec = {s['timeout_sec']}")
        if env:
            b.append(f"\n[mcp_servers.{toml_key(name)}.env]")
            for k, v in env.items():
                b.append(f"{toml_key(k)} = {toml_str(v)}")
        blocks.append("\n".join(b) + "\n")
        report("codex", name, "added", s.get("token_env"), s.get("required"))
    if blocks and not dry:
        backup(file)
        existing = file.read_text(encoding="utf-8") if file.exists() else ""
        if existing and not existing.endswith("\n"):
            existing += "\n"
        write_atomic(file, existing + "".join(blocks))


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
    servers, wrapper = load_servers(Path(a.servers))
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
            apply_json_mcpservers(ag, paths[ag], servers, wrapper, home, a.dry_run)
        elif ag == "opencode":
            apply_opencode(paths[ag], servers, wrapper, home, a.dry_run)
        elif ag == "codex":
            apply_codex(paths[ag], servers, wrapper, home, a.dry_run)
    print("Done. Store tokens in the OS secret store (see bin/with-secret), then restart each agent.")


if __name__ == "__main__":
    main()
