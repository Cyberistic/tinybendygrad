"""Wire the mass-delete gate into git's own two choke points, idempotently.

    .venv/bin/python .agents/slop/jjreset/wire.py          # show what it would do
    .venv/bin/python .agents/slop/jjreset/wire.py --install

NOT run by the report: `.git/hooks/` is shared, untracked, and per-clone, so installing a
hook changes behaviour for every concurrent unit. The report states the recommendation; this
makes it one command for the person who owns that decision.

pre-commit  checks the STAGED diff    -> stops a mass delete before it becomes a commit
pre-push    checks each pushed commit -> stops one AFTER it is committed but BEFORE it leaves
            the machine, and REFUSES a non-fast-forward (a force push, which this tree forbids)

Both are the SAME guard, two adapters. Git hands a pre-commit hook no arguments and a pre-push
hook a refspec on stdin; the guard reads the index for one and stdin for the other. A hook that
is not executable is silently skipped by git, so `--install` sets the mode.
"""
import os
import stat
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GATE = HERE / "git-massdelete-gate.py"
PY = sys.executable
HOOKS = ROOT / ".git" / "hooks"

BODY = {
    "pre-commit": f'#!/bin/sh\nexec "{PY}" "{GATE}" staged\n',
    "pre-push": f'#!/bin/sh\nexec "{PY}" "{GATE}" push "$@"\n',
}


def install(do_it):
    plan = []
    for name, body in BODY.items():
        p = HOOKS / name
        exist = p.read_text() if p.is_file() else None
        plan.append((name, "replace" if exist else "create", exist, body))
    for name, action, _old, body in plan:
        print(f"{name}: {action}")
        if do_it:
            (HOOKS / name).write_text(body)
            os.chmod(HOOKS / name, os.stat(HOOKS / name).st_mode | stat.S_IXUSR)
    if not do_it:
        print("(dry run; pass --install to write)")
    return 0


if __name__ == "__main__":
    sys.exit(install("--install" in sys.argv[1:]))
