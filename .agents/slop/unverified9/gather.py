# Final gather: for each of the 14, the tracked files that name it, minus AGENTS.md
# and .agents/ (the audit's own artifacts). One `git grep -w -F` per flag.
import json, re, subprocess
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
OUT = ROOT / ".agents" / "slop" / "unverified9"
PIN = "ad117c928^"
FLAGS = [
    "NOLOCALS", "JIT_BATCH_SIZE", "PCONTIG", "GRAPH_ONE_KERNEL", "BROWSER", "THREADS",
    "APL_REMOTE_SOCK", "TINYFS_ENDPOINT", "TINYFS_TIMEOUT", "ASYNC_COPY_WORKERS",
    "HCQDEV_WAIT_TIMEOUT_MS", "AMD_SDMA_BIND", "FIX_METAL_ICB", "MLX_IP",
]
DECL = re.compile(r'(?:getenv|ContextVar|_DEV)\(\s*"')

def files(flag, rev=None):
    cmd = ["git", "grep", "-n", "-w", "-F", "-e", flag, "--",
           ":!AGENTS.md", ":!.agents/"]
    if rev:
        cmd = ["git", "grep", "-n", "-w", "-F", "-e", flag, rev, "--",
               ":!AGENTS.md", ":!.agents/"]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    return [l for l in r.stdout.splitlines()]

report = {}
for f in FLAGS:
    now = files(f)
    pin = files(f, PIN)
    def summarize(rows):
        out = []
        for l in rows:
            # worktree: path:line:text ; pin: rev:path:line:text
            if PIN in l and l.startswith(PIN + ":"):
                body = l[len(PIN) + 1:]
            else:
                body = l
            parts = body.split(":", 2)
            path = parts[0]
            text = parts[2] if len(parts) > 2 else ""
            out.append({"file": path, "line": parts[1] if len(parts) > 1 else "",
                        "decl": bool(DECL.search(text)), "text": text.strip()[:140]})
        return out
    report[f] = {"now": summarize(now), "pin": summarize(pin)}

(OUT / "gather.json").write_text(json.dumps(report, indent=2))

for f in FLAGS:
    n, p = report[f]["now"], report[f]["pin"]
    def brk(rows):
        return (f"{len(rows)} hit(s) in {len({r['file'] for r in rows})} file(s); "
                f"decl={sum(1 for r in rows if r['decl'])}")
    print(f"{f:24s} NOW {brk(n):40s} PIN {brk(p)}")
