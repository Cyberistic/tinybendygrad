#!/usr/bin/env python3
"""Is jjreset's generated pre-push DEAD? Push a real catastrophe and see.

    jjreset/wire.py generates:  pre-push -> `... git-massdelete-gate.py push "$@"`

MEASURED argv shape on this git: a pre-push hook receives argc=2 ($1 remote name, $2 remote
URL) and the refspecs on STDIN. So `push "$@"` hands the gate argv = ("push","origin","<url>")
and `mode_push` takes the `len(argv) >= 2` branch, so `specs = "origin"` -- one token, not four
-- every line hits `continue`, and the function falls through to `return PASS`.

This script does not read the code. It installs the hook, makes a 520-file deletion commit,
pushes it, and reports what came back.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

LIVE = Path(__file__).resolve().parents[3]
WORK = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/deadpush")
REMOTE = WORK.parent / "deadpush-remote"
PY = sys.executable


def git(*a, cwd=WORK, check=True):
    r = subprocess.run(["git", "-C", str(cwd), *a], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {a}: rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout


def main():
    if WORK.exists():
        shutil.rmtree(WORK)
    (WORK / ".agents/slop/jjreset").mkdir(parents=True)
    shutil.copy2(LIVE / ".agents/slop/jjreset/git-massdelete-gate.py",
                 WORK / ".agents/slop/jjreset/git-massdelete-gate.py")
    git("init", "-q", "-b", "main")
    git("config", "user.email", "a@b.c")
    git("config", "user.name", "d")
    (WORK / "x").write_text("x\n")
    git("add", "x"); git("commit", "-q", "-m", "seed")
    if REMOTE.exists():
        shutil.rmtree(REMOTE)
    subprocess.run(["git", "clone", "-q", "--bare", str(WORK), str(REMOTE)],
                   capture_output=True, text=True)
    git("remote", "add", "origin", str(REMOTE))
    git("push", "-q", "-u", "origin", "main")

    # a real catastrophe: 520 files committed, then deleted in the next commit
    big = WORK / "big"; big.mkdir()
    for i in range(520):
        (big / f"f{i}.tsv").write_text(f"{i}\n")
    git("add", "big"); git("commit", "-q", "-m", "520 files")
    git("rm", "-r", "-q", "big"); git("commit", "-q", "-m", "delete all 520")
    del_sha = git("rev-parse", "HEAD").strip()
    n, lines, _ = [0, 0, []]
    r = subprocess.run([PY, str(WORK / ".agents/slop/jjreset/git-massdelete-gate.py"),
                        "check", del_sha], capture_output=True, text=True, cwd=str(WORK))
    print(f"the pushed commit {del_sha[:12]} judged DIRECTLY (not through a hook):")
    print(f"   rc={r.returncode}  {r.stderr.strip().splitlines()[0][:88]}")

    # jjreset's exact generated body
    hook = WORK / ".git/hooks/pre-push"
    hook.write_text(f'#!/bin/sh\nexec "{PY}" "{WORK}/.agents/slop/jjreset/'
                    f'git-massdelete-gate.py" push "$@"\n')
    hook.chmod(0o755)
    print("\ninstalling jjreset's pre-push verbatim:")
    print("   " + hook.read_text().strip().replace("\n", "\n   "))

    p = subprocess.run(["git", "push", "-q", "origin", "main"], capture_output=True,
                       text=True, cwd=str(WORK))
    out = (p.stdout + p.stderr).strip()
    print(f"\n   `git push` rc={p.returncode}")
    print(f"   hook output: {out[:120] if out else '<NOTHING AT ALL>'}")
    if p.returncode == 0 and not out:
        print("\nVERDICT: DEAD. The catastrophe was PUSHED, the hook said nothing, and the")
        print("         exit code was 0. A guard that exits 0 having measured nothing is")
        print("         worse than no guard, because it is trusted -- and this one would")
        print("         have been trusted for exactly the event it was written to stop.")
    elif p.returncode != 0:
        print("\nVERDICT: not dead.")

    # and the same push through a correctly-wired hook, for the contrast.
    # A SECOND push must carry a NEW catastrophe: the first one already landed, and a
    # push with nothing to send never runs the hook at all.
    big2 = WORK / "big2"; big2.mkdir()
    for i in range(540):
        (big2 / f"g{i}.tsv").write_text(f"{i}\n")
    git("add", "big2"); git("commit", "-q", "-m", "540 more files")
    git("rm", "-r", "-q", "big2"); git("commit", "-q", "-m", "delete all 540")
    hook.write_text(f'#!/bin/sh\nexec "{PY}" "{WORK}/.agents/slop/jjreset/'
                    f'git-massdelete-gate.py" push\n')
    hook.chmod(0o755)
    print("\nfor contrast, a NEW 540-file catastrophe with the refspec taken from STDIN")
    print("(the gate's own line 6: `the guard reads the index for one and stdin for the other`):")
    p2 = subprocess.run(["git", "push", "-q", "origin", "main"], capture_output=True,
                        text=True, cwd=str(WORK))
    print(f"   `git push` rc={p2.returncode}")
    for line in (p2.stdout + p2.stderr).strip().splitlines()[:2]:
        print(f"   {line[:104]}")


if __name__ == "__main__":
    sys.exit(main())
