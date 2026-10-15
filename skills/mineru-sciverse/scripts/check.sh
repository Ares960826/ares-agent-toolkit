#!/usr/bin/env bash
# check.sh — preflight status for the MinerU + SciVerse toolkit.
# Reports what's installed and each token's source and expiry, never printing secrets.
#
#   bash check.sh            # local checks only (JWT expiry decoded offline)
#   bash check.sh --online   # also probe each service once; reports HTTP status only
set -euo pipefail
CLAUDE_JSON="${HOME}/.claude.json"
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
if [ -d "${HOME}/.cache/modelscope" ] || [ -d "${HOME}/.cache/huggingface" ]; then ok "parse models cached"; else warn "no model cache yet (first local parse will download ~1GB)"; fi

echo "── MCP servers / tokens ──"
if [ ! -f "$CLAUDE_JSON" ]; then no "~/.claude.json missing (start the agent once, then run install/install.sh)"; exit 0; fi
ONLINE="$ONLINE" python3 - "$CLAUDE_JSON" <<'PY'
import base64, json, os, shutil, subprocess, sys, time, urllib.error, urllib.request

m = json.load(open(sys.argv[1])).get("mcpServers", {})
online = os.environ.get("ONLINE") == "1"
G="\033[1;32m"; R="\033[1;31m"; Y="\033[1;33m"; Z="\033[0m"
def line(sym, col, msg): print(f"  {col}{sym}{Z} {msg}")

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
        f = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "with-secret", var)
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
    "sciverse": "https://api.sciverse.space/meta-catalog",
    "mineru-cloud": "https://mineru.net/api/v4/extract-results/batch/00000000-0000-0000-0000-000000000000",
}
def probe(name, tok):
    req = urllib.request.Request(PROBES[name], headers={"Authorization": f"Bearer {tok}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:
        return f"unreachable ({type(e).__name__})"

for name, label, var, required, url in [
    ("sciverse", "SciVerse (literature search)", "SCIVERSE_API_TOKEN", True, "https://sciverse.space/tokens"),
    ("mineru-cloud", "MinerU cloud (uploads to mineru.net)", "MINERU_API_TOKEN", False, "https://mineru.net"),
]:
    s = m.get(name)
    if not s:
        line("✗", R, f"{label}: server NOT configured — run install/install.sh"); continue
    argv = [s.get("command", "")] + list(s.get("args") or [])
    tok = (s.get("env") or {}).get(var, "")
    if tok:
        source = "plaintext in MCP config env (move it to the secret store)"
    elif "with-secret" in os.path.basename(argv[0]) and var in argv:
        tok, source = secret_store(var), f"secret store claude-mcp:{var}"
    elif name == "sciverse" and os.path.isfile(os.path.expanduser("~/.sciverse/credentials.json")):
        line("✓", G, f"{label}: token via ~/.sciverse/credentials.json (auth login; expiry not checked)"); continue
    else:
        source = None
    if not tok:
        where = f"{source}: not found" if source else "no token configured"
        (line("✗", R, f"{label}: {where} → {url}") if required
         else line("!", Y, f"{label}: {where} → free Flash mode only; token: {url}"))
        continue
    exp = expiry(tok)
    status = probe(name, tok) if online else None
    detail = ", ".join(x for x in [source, exp or "expiry unknown (not a JWT)",
                                   f"online HTTP {status}" if status is not None else None] if x)
    if (exp or "").startswith("EXPIRED") or status in (401, 403):
        line("✗", R, f"{label}: token INVALID — {detail}; renew at {url}")
    elif status is not None and status != 200 and name == "sciverse":
        line("!", Y, f"{label}: {detail}")
    else:
        line("✓", G, f"{label}: {detail}" + ("" if online else "; not probed (use --online)"))
PY
echo "Note: reads ~/.claude.json only; Codex/Cursor use the same secret store when wrapped by with-secret."
echo "Done. Missing/invalid token → store a new one (see bin/with-secret) and restart the agents."
