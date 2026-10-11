#!/usr/bin/env python3
"""watch2.py -- attribute .git/index writes to a writer, by correlating three clocks.

The instrument jjhazard/REPORT.md already proved: jj's op-store mtime is the
discriminator.  If .git/index changes and the jj op-store mtime does NOT, the
writer is not jj.  This script samples both, plus the live process table, and
prints one row per OBSERVED INDEX CHANGE (not per sample) so the log is a
census of events, not a census of ticks.

Reads only.  Never writes .git/index.  `git --no-optional-locks` throughout.
"""

import hashlib
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GITDIR = ROOT / ".git"
JJDIR = ROOT / ".jj"
INTERVAL = 0.5


def git(*args: str) -> str:
    r = subprocess.run(
        ["git", "--no-optional-locks", *args],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    return r.stdout.strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


def procs() -> dict:
    r = subprocess.run(["ps", "-eo", "pid,command"], capture_output=True, text=True, check=False)
    out = {}
    for line in r.stdout.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        pid, _, cmd = line.partition(" ")
        if "branching server" in cmd:
            out.setdefault("visualjj_branching_server", []).append(pid)
        elif cmd.startswith("git") or " /git " in f" {cmd} ":
            out.setdefault("git", []).append(pid)
        elif cmd.split()[0].endswith("/jj") or cmd == "jj":
            out.setdefault("jj_cli", []).append(pid)
    return out


def jjmtimes() -> dict:
    out = {}
    opstore = JJDIR / "repo" / "store" / "op_store"
    for p in (opstore, JJDIR / "repo" / "store" / "type"):
        if p.exists():
            out[p.name] = p.stat().st_mtime_ns
    return out


def main() -> int:
    idx = GITDIR / "index"
    seen = sha(idx) if idx.exists() else "ABSENT"
    head = git("rev-parse", "HEAD")
    nidx = len(git("ls-files", "--stage").splitlines())
    print(f"WATCH2 begin index={seen} entries={nidx} head={head[:12]} t={time.strftime('%H:%M:%S')}")
    events = 0
    while True:
        time.sleep(INTERVAL)
        try:
            now = sha(idx) if idx.exists() else "ABSENT"
        except OSError as e:
            print(f"WATCH2 UNREADABLE {e}")
            return 5
        if now == seen:
            continue
        events += 1
        jm = jjmtimes()
        p = procs()
        nn = len(git("ls-files", "--stage").splitlines())
        nh = git("rev-parse", "HEAD")
        print(
            f"EVENT {events:03d} t={time.strftime('%H:%M:%S')} index={seen}->{now} "
            f"entries={nidx}->{nn} head={head[:8]}->{nh[:8]} "
            f"jjstore={','.join(f'{k}:{v}' for k, v in sorted(jm.items()))} "
            f"procs={p or '{}'}"
        )
        seen, head, nidx = now, nh, nn
    return 0


if __name__ == "__main__":
    sys.exit(main())
