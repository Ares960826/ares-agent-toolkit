#!/usr/bin/env bash
# check.sh — preflight status for the MinerU + SciVerse toolkit.
# Reports what is installed, which agent configs carry each MCP server, and each
# token's source and expiry. Never prints secret values.
#
#   bash check.sh            # local checks only (JWT expiry decoded offline)
#   bash check.sh --online   # also probe each service once; reports HTTP status only
set -euo pipefail
ONLINE=0
[[ "${1:-}" == "--online" ]] && ONLINE=1

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
no()   { printf '  \033[1;31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

echo "MinerU + SciVerse — status"
echo "── local tooling ──"
command -v uv      >/dev/null 2>&1 && ok "uv: $(uv --version)"        || no "uv not found (install: curl -LsSf https://astral.sh/uv/install.sh | sh)"
command -v mineru  >/dev/null 2>&1 && ok "mineru: $(mineru --version 2>/dev/null | head -1)" || no "mineru CLI not installed (run setup.sh)"
command -v pdf2md  >/dev/null 2>&1 && ok "pdf2md wrapper on PATH"     || warn "pdf2md not on PATH (run setup.sh; ensure ~/.local/bin on PATH)"
if command -v mineru-kit >/dev/null 2>&1; then
  if mineru-kit models verify --tier standard >/dev/null 2>&1; then
    ok "standard-tier models verified (mineru-kit models verify --tier standard)"
  else
    warn "standard-tier models not ready; run: mineru-kit models download --tier standard"
  fi
fi

ONLINE="$ONLINE" python3 - <<'PY'
import base64, json, os, shutil, subprocess, sys, time, urllib.error, urllib.request
try:
    import tomllib
except Exception:
    tomllib = None

online = os.environ.get("ONLINE") == "1"
G="\033[1;32m"; R="\033[1;31m"; Y="\033[1;33m"; Z="\033[0m"
def line(sym, col, msg): print(f"  {col}{sym}{Z} {msg}")
home = os.path.expanduser("~")

SERVICES = [  # (server name, label, token var, required, where to get one)
    ("sciverse", "SciVerse", "SCIVERSE_API_TOKEN", True, "https://sciverse.space/tokens"),
    ("mineru-cloud", "MinerU cloud MCP", "MINERU_API_TOKEN", False, "https://mineru.net"),
]
EXTRA_VARS = [  # not tied to an MCP server
    ("MinerU CLI remote key", "MINERU_API_KEY", "only needed for `mineru parse --remote` / `mineru usage`"),
]

def secret_store(var):
    """Read claude-mcp:VAR the same way with-secret does. Value is returned, never printed."""
    try:
        if os.path.exists("/usr/bin/security"):
            r = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", f"claude-mcp:{var}",
                                "-a", os.environ.get("USER", ""), "-w"], capture_output=True, text=True)
            return r.stdout.strip() if r.returncode == 0 else ""
        if shutil.which("secret-tool"):
            r = subprocess.run(["secret-tool", "lookup", "service", f"claude-mcp:{var}"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
        f = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(home, ".config")), "with-secret", var)
        if os.path.isfile(f) and (os.stat(f).st_mode & 0o777) in (0o600, 0o400):  # same rule as with-secret
            return open(f).read().strip()
    except OSError:
        pass
    return ""

def expiry(tok):
    """'expires YYYY-MM-DD' / 'EXPIRED YYYY-MM-DD' for JWTs, None otherwise."""
    try:
        exp = json.loads(base64.urlsafe_b64decode(tok.split(".")[1] + "==")).get("exp")
    except Exception:
        return None
    if not exp:
        return None
    day = time.strftime("%Y-%m-%d", time.localtime(exp))
    return ("EXPIRED " if exp < time.time() else "expires ") + day

PROBES = {  # authenticated, read-only endpoints; 401/403 = token rejected
    "SCIVERSE_API_TOKEN": "https://api.sciverse.space/meta-catalog",
    "MINERU_API_TOKEN": "https://mineru.net/api/v4/extract-results/batch/00000000-0000-0000-0000-000000000000",
}
def probe(var, tok):
    req = urllib.request.Request(PROBES[var], headers={"Authorization": f"Bearer {tok}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:
        return f"unreachable ({type(e).__name__})"

# ---- agent configs ----------------------------------------------------------
def load_agents():
    """{agent: {server: entry}} for every config file that exists and parses."""
    out, notes = {}, []
    for agent, rel, kind in [("claude", ".claude.json", "json"),
                             ("cursor", ".cursor/mcp.json", "json"),
                             ("codex", ".codex/config.toml", "toml")]:
        p = os.path.join(home, rel)
        if not os.path.isfile(p):
            continue
        try:
            if kind == "json":
                out[agent] = json.load(open(p)).get("mcpServers", {}) or {}
            elif tomllib:
                out[agent] = tomllib.load(open(p, "rb")).get("mcp_servers", {}) or {}
            else:
                notes.append(f"{agent}: ~/{rel} not inspected (needs python>=3.11 for TOML)")
        except Exception as e:
            notes.append(f"{agent}: ~/{rel} unreadable ({type(e).__name__})")
    return out, notes

def wrapped_info(entry, var):
    """(state, optional?) where state is 'wrapped' | 'plaintext' | 'bare'."""
    argv = [entry.get("command", "")] + [str(a) for a in (entry.get("args") or [])]
    if (entry.get("env") or {}).get(var):
        return "plaintext", False
    if "with-secret" in os.path.basename(argv[0]) and var in argv:
        i = argv.index(var)
        return "wrapped", i > 0 and argv[i - 1] == "--optional"
    return "bare", False

agents, notes = load_agents()
print("── MCP servers per agent ──")
if not agents:
    line("✗", R, "no agent config found (~/.claude.json, ~/.cursor/mcp.json, ~/.codex/config.toml); run install/install.sh")
for agent, servers in agents.items():
    for name, label, var, required, url in SERVICES:
        e = servers.get(name)
        if not e:
            line("!", Y, f"[{agent}] {name}: not configured — run install/install.sh")
            continue
        state, optional = wrapped_info(e, var)
        if state == "plaintext":
            line("✗", R, f"[{agent}] {name}: token in plaintext env — move it to the secret store")
        elif state == "bare":
            line("!", Y, f"[{agent}] {name}: not wrapped by with-secret (token must come from the environment)")
        elif required or optional:
            line("✓", G, f"[{agent}] {name}: with-secret{' --optional' if optional else ''}")
        else:
            line("!", Y, f"[{agent}] {name}: with-secret strict (no --optional); fails to start without a token")
for n in notes:
    line("!", Y, n)

# ---- tokens (once per variable) ---------------------------------------------
print("── tokens ──")
sciverse_file = os.path.isfile(os.path.join(home, ".sciverse", "credentials.json"))
def report(label, var, required, hint, name=None):
    tok = secret_store(var)
    source = f"secret store claude-mcp:{var}"
    if not tok and os.environ.get(var):
        tok, source = os.environ[var], f"shell env {var}"
    if not tok:
        if var == "SCIVERSE_API_TOKEN" and sciverse_file:
            line("✓", G, f"{label}: via ~/.sciverse/credentials.json (expiry not checked)")
        elif required:
            line("✗", R, f"{label}: no {var} found → {hint}")
        else:
            line("·", "", f"{label}: {var} not set — {hint}")
        return
    exp = expiry(tok)
    status = probe(var, tok) if (online and var in PROBES) else None
    detail = ", ".join(x for x in [source, exp or "expiry unknown (not a JWT)",
                                   f"online HTTP {status}" if status is not None else None] if x)
    if (exp or "").startswith("EXPIRED") or status in (401, 403):
        line("✗", R, f"{label}: token INVALID — {detail}")
    elif status is not None and status != 200:
        line("!", Y, f"{label}: {detail}")
    else:
        probed = "" if (online and var in PROBES) else ("; not probed (use --online)" if var in PROBES else "; not probed")
        line("✓", G, f"{label}: {detail}{probed}")

for name, label, var, required, url in SERVICES:
    report(label, var, required, f"get one at {url}" if required else f"Flash mode only; token: {url}")
for label, var, hint in EXTRA_VARS:
    report(label, var, False, hint)
PY
echo "Done. If a token is missing or INVALID, store a new one (see bin/with-secret) and restart the agents."
