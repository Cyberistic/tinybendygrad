#!/usr/bin/env python3
"""repro2.py -- which ROUTE actually arms git's index, isolated.

Every scenario runs in its own mkdtemp.  Nothing here touches the real repo.
Signals are sha256 + size + inode of .git/index (not mtime, whose 1-second
granularity made the first run of repro.py report "no change" across a real
change) so an unchanged index and a changed index can never look alike.

Scenarios -- each names a ROUTE and prints BEFORE/AFTER:
  R1  jj status after a tracked file is deleted        (jj EXPORTS the delete?)
  R2  git rm --cached <p>, file left on disk          (the shape found at 01:55:33)
  R3  git read-tree HEAD   (disarm), then jj status    (does jj RE-ARM?)
  R4  git read-tree HEAD   (disarm), then idle 5 s     (does anything RE-ARM unattended?)
  R5  git commit, then jj status                       (jjhazard's "import git head" route)
  R6  git add -A with a file transiently absent        (the classic broad-add route)
"""

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

JJ = shutil.which("jj")
CONFIG = """\
[snapshot]
auto-update-stale = true
max-new-file-size = 3000000

[visualjj]
snapshot-workspaces = true
"""


def run(cwd, *args):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False)


def idxsig(cwd):
    p = Path(cwd) / ".git" / "index"
    if not p.exists():
        return "ABSENT"
    b = p.read_bytes()
    st = p.stat()
    return f"{hashlib.sha256(b).hexdigest()[:10]}/{st.st_size}/{st.st_ino}"


def state(cwd) -> dict:
    ls = run(cwd, "git", "--no-optional-locks", "ls-files", "--stage").stdout
    return {
        "sig": idxsig(cwd),
        "n_index": len(ls.splitlines()),
        "staged_D": run(cwd, "git", "--no-optional-locks", "diff", "--cached", "--name-only",
                        "--diff-filter=D", "HEAD").stdout.split(),
        "staged_M": run(cwd, "git", "--no-optional-locks", "diff", "--cached", "--name-only",
                        "--diff-filter=M", "HEAD").stdout.split(),
        "staged_A": run(cwd, "git", "--no-optional-locks", "diff", "--cached", "--name-only",
                        "--diff-filter=A", "HEAD").stdout.split(),
        "empty": sum(1 for ln in ls.splitlines() if ln.startswith("0" * 40)),
        "ontree": run(cwd, "git", "--no-optional-locks", "ls-tree", "-r", "HEAD", "--name-only").stdout.split(),
    }


def fmt(tag, s):
    return (f"{tag:44s} sig={s['sig']:22s} nidx={s['n_index']:3d} "
            f"D={s['staged_D']} M={s['staged_M']} A={s['staged_A']} empty={s['empty']}")


def fresh(d, cfg, name):
    r = d / name
    r.mkdir()
    env = {**os.environ, "JJ_CONFIG": cfg}
    run(r, "git", "init", "-q", "-b", "master")
    run(r, "git", "config", "user.email", "t@t")
    run(r, "git", "config", "user.name", "t")
    for n in ("a.rows", "b.rows"):
        (r / n).write_text(f"{n} keep\n")
    run(r, "git", "add", "-A")
    run(r, "git", "commit", "-q", "-m", "seed")
    p = subprocess.run([JJ, "git", "init", "--colocate", "."], cwd=r, env=env,
                       capture_output=True, text=True, check=False)
    assert p.returncode == 0, p.stderr
    return r, env


def main() -> int:
    if not JJ:
        print("DEAD: no jj on PATH")
        return 5
    d = Path(tempfile.mkdtemp(prefix="whyarms2-"))
    cfgdir = d / "cfg"
    cfgdir.mkdir()
    (cfgdir / "config.toml").write_text(CONFIG)
    cfg = str(cfgdir)
    armed, disarmed = [], []
    try:
        # ---------- R1 ----------
        r, env = fresh(d, cfg, "R1")
        print(fmt("R1-0 seed", state(r)))
        (r / "a.rows").unlink()
        subprocess.run([JJ, "status"], cwd=r, env=env, capture_output=True, text=True)
        time.sleep(1.1)
        s = state(r)
        print(fmt("R1-1 jj status after delete", s))
        (armed if s["staged_D"] else disarmed).append("R1 jj-exports-delete")

        # ---------- R2 ----------
        r, env = fresh(d, cfg, "R2")
        run(r, "git", "rm", "--cached", "-q", "--", "a.rows")
        print(fmt("R2-1 git rm --cached a.rows", state(r)))
        s = state(r)
        print(f"{'R2-2 a.rows still on disk?':44s} {(r / 'a.rows').exists()}")
        (armed if s["staged_D"] else disarmed).append("R2 git-rm--cached")

        # ---------- R3 ----------
        r, env = fresh(d, cfg, "R3")
        run(r, "git", "rm", "--cached", "-q", "--", "a.rows")
        run(r, "git", "read-tree", "HEAD")
        s0 = state(r)
        print(fmt("R3-1 DISARMED by read-tree HEAD", s0))
        (disarmed if not s0["staged_D"] else armed).append("R3 read-tree")
        subprocess.run([JJ, "status"], cwd=r, env=env, capture_output=True, text=True)
        time.sleep(1.1)
        s = state(r)
        print(fmt("R3-2 after jj status", s))
        (armed if s["staged_D"] else disarmed).append("R3 jj-RE-ARMS-after-read-tree")

        # ---------- R4 ----------
        r, env = fresh(d, cfg, "R4")
        run(r, "git", "read-tree", "HEAD")
        s0 = state(r)
        print(fmt("R4-1 DISARMED, now idling", s0))
        time.sleep(6)
        s = state(r)
        print(fmt("R4-2 after 6 s idle, nothing invoked", s))
        (armed if s["staged_D"] else disarmed).append("R4 unattended-re-arm")

        # ---------- R5 ----------
        r, env = fresh(d, cfg, "R5")
        run(r, "git", "commit", "-q", "--allow-empty", "-m", "unit commit, bare")
        subprocess.run([JJ, "status"], cwd=r, env=env, capture_output=True, text=True)
        time.sleep(1.1)
        s = state(r)
        print(fmt("R5-1 git commit, then jj status", s))
        (armed if s["staged_D"] else disarmed).append("R5 commit-then-jj")

        # ---------- R6 ----------
        r, env = fresh(d, cfg, "R6")
        (r / "b.rows").unlink()
        run(r, "git", "add", "-A")
        (r / "b.rows").write_text("b.rows keep\n")   # back before the commit
        s = state(r)
        print(fmt("R6-1 git add -A during a transient absence", s))
        (armed if s["staged_D"] else disarmed).append("R6 transient-absence-add-A")
        if s["staged_D"]:
            run(r, "git", "commit", "-q", "-m", "bare")
            t = run(r, "git", "--no-optional-locks", "ls-tree", "-r", "HEAD", "--name-only").stdout.split()
            print(f"{'R6-2 b.rows survives a bare commit?':44s} {'b.rows' in t}  tree={sorted(t)}")

        print()
        print(f"ARMED-BY   ({len(armed)}): {armed}")
        print(f"NOT-ARMED  ({len(disarmed)}): {disarmed}")
        return 0
    finally:
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
