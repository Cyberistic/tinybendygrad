# The 14 `UNVERIFIABLE` flags, classified via `git grep` over TRACKED files
# (the worktree population is what git tracks) and over the upstream PIN.
# `git grep` is a directory walk by the tree's own index -- not a hand list.
import json, subprocess
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
OUT = ROOT / ".agents" / "slop" / "unverified9"
PIN = "ad117c928^"
FLAGS = [
    "NOLOCALS", "JIT_BATCH_SIZE", "PCONTIG", "GRAPH_ONE_KERNEL", "BROWSER", "THREADS",
    "APL_REMOTE_SOCK", "TINYFS_ENDPOINT", "TINYFS_TIMEOUT", "ASYNC_COPY_WORKERS",
    "HCQDEV_WAIT_TIMEOUT_MS", "AMD_SDMA_BIND", "FIX_METAL_ICB", "MLX_IP",
]

def grep(rev=None):
    cmd = ["git", "grep", "-n", "-w", "-F"]
    for f in FLAGS:
        cmd += ["-e", f]
    if rev:
        cmd.append(rev)
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    # output: [rev:]path:lineno:text
    rows = []
    for line in r.stdout.splitlines():
        if rev:
            _, path, ln, text = line.split(":", 3)
        else:
            path, ln, text = line.split(":", 2)
        rows.append({"file": path, "line": int(ln), "text": text.strip()[:160]})
    return rows

rows = grep()
report = {}
for f in FLAGS:
    mine = [r for r in rows if f" {f} " in f" {r['text']} " or r["text"].startswith(f)
            or f"({f}" in r["text"] or f'"{f}"' in r["text"] or f"[{f}" in r["text"]]
    # simpler: re-match word in text
    import re
    rx = re.compile(rf'\b{f}\b')
    mine = [r for r in rows if rx.search(r["text"])]
    files = sorted({r["file"] for r in mine})
    tiny = [x for x in files if x.startswith("tinygrad/")]
    port = [x for x in files if x.startswith("tinybendygrad/")]
    extra = [x for x in files if x.startswith("extra/")]
    report[f] = {
        "files": files, "hits": len(mine),
        "tinygrad": tiny, "port": port, "extra": extra,
        "agents_md": "AGENTS.md" in files,
        "other": [x for x in files if not x.startswith(("tinygrad/", "tinybendygrad/", "extra/")) and x != "AGENTS.md"],
    }

(OUT / "classify.json").write_text(json.dumps(report, indent=2))

print(f"{'flag':24s} {'hits':>4s} {'tiny':>4s} {'port':>4s} {'extra':>5s} {'AGENTS.md':>9s}  other files")
for f in FLAGS:
    r = report[f]
    print(f"{f:24s} {r['hits']:4d} {len(r['tinygrad']):4d} {len(r['port']):4d} "
          f"{len(r['extra']):5d} {str(r['agents_md']):>9s}  {r['other'][:4]}")

pin_rows = grep(PIN)
print(f"\n== PIN {PIN}: tracked lines for any of the 14 ==")
import re
for f in FLAGS:
    m = [r for r in pin_rows if re.search(rf'\b{f}\b', r["text"]) or re.search(rf'\b{f}\b', r["file"])]
    print(f"{f:24s} {'PIN: ' + str(len(m)) + ' hit(s) ' + str([r['file'] for r in m][:3]) if m else 'PIN: none'}")
