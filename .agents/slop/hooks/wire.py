#!/usr/bin/env python3
"""wire.py -- generate the two git hooks, idempotently. Dry run unless --install.

    .venv/bin/python .agents/slop/hooks/wire.py             # show what it would do
    .venv/bin/python .agents/slop/hooks/wire.py --install

WHY A GENERATOR AND NOT A HOOK CHECKED IN. `.git/hooks/` is untracked and per-clone: a hook
committed to the tree is dead weight in every clone that does not install it, and a hook
installed here is invisible to `git status`, to `gates/gates-pop.py:discover()`, and to every
other clone. `AGENTS.md`'s first doctrine -- a population is discovered, not listed -- is not
violated by a hook, but a hook nothing can MEASURE is the "written but never run" state made
permanent. So the generated text is derived here and the installation is one explicit command.

WHICH VERDICT BELONGS TO WHICH HOOK. MEASURED in `_plant.py`, states C/D/E/F:

  pre-commit  reads the INDEX. Only the mass-delete guard has an index mode (`staged`), so
              only the mass-delete guard goes here. It cannot see a message -- the commit
              does not exist yet -- so `msgdiff` CANNOT be a pre-commit gate at all.
  pre-push    reads a refspec on stdin and scopes itself to `local --not remote`, i.e. the
              NEWLY PUSHED commits. That is the whole answer to "a pre-commit hook that
              rejects makes 146 commits unreplayable": it is not a pre-commit hook, and the
              `--not remote_sha` is what excludes the 1 REFUSED commit already in history.
              `_plant.py` E/F measures both shapes: `range local --not remote` PASSes over
              two planted bad ancestors, `range <first>..HEAD` REFUSES forever.

`msgdiff-gate.py` needs NO MODE ADDED for this: `range` forwards its argv to `git rev-list`,
so `range <local> --not <remote>` is already the pre-push half.

THE VERDICT FILE IS NOT OPTIONAL, AND IT IS NOT HERE. MEASURED in `_probe_hooks.py` state H:
`git commit` returns 1 for a pre-commit hook that exited 3, and 1 for one that exited 4, and
1 for one that exited 5. REFUSED, SKIP and DEAD are INDISTINGUISHABLE from the exit code git
hands back. So these bodies are pure `exec` and the verdict is appended by the gate's own
adapter (`pushshim.py`) or read off the gate's stderr -- a hook that only sets an exit code
is a hook that destroys the five-verdict vocabulary at exactly the boundary it was written for.

MEASURED, AND THE PLANT THAT CAUGHT IT: this file's first draft wrote `range "$2" --not "$4"`,
which is wrong in the same way as jjreset's -- worse, because it reads as though the positions
were checked. `_wireplant.py` state 4 got DEAD(5) instead of REFUSED(3) and named the reason.
"""
import os
import stat
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MASS = ROOT / ".agents/slop/jjreset/git-massdelete-gate.py"
SHIM = ROOT / ".agents/slop/hooks/pushshim.py"
PY = sys.executable
HOOKS = ROOT / ".git" / "hooks"
VERDICT = HERE / "last-verdict.tsv"

# BOTH are `#!/bin/sh` with one `exec` and no shell logic, and that is the point:
# `AGENTS.md` records four ways a shell gate failed HERE -- `&&` masking a diff under
# `set -e`, an `EXIT` trap returning `rm`'s status, `<( )` not parsing under `sh`, and
# `${=SUB}` never expanding under `sh`. These bodies contain NONE of the four constructs:
# no `&&`, no trap, no `<( )`, no `${=`. `exec` is the only verb, so the hook's exit status
# IS the gate's exit status and cannot be masked by a pipeline.
#
# `pre-push` carries NO `$@` AND NO `"$@"` -- MEASURED, and the omission is load-bearing:
# a pre-push hook gets argc=2 ($1 remote name, $2 remote URL) and the refspecs on STDIN.
# `.agents/slop/jjreset/wire.py:31` writes `push "$@"`, which hands `mode_push` the remote
# NAME; every line misses its 4-field check and the gate returns PASS having inspected
# nothing. `_deadpush.py` pushes a 520-file deletion through that hook and watches it go.
BODY = {
    "pre-commit": f'#!/bin/sh\nexec "{PY}" "{MASS}" staged\n',
    "pre-push": f'#!/bin/sh\nexec "{PY}" "{SHIM}"\n',
}


def plan():
    rows = []
    for name, body in BODY.items():
        p = HOOKS / name
        old = p.read_text() if p.is_file() else None
        rows.append((name, "replace" if old else "create", old, body))
    return rows


def main(argv):
    do = "--install" in argv
    for name, action, old, body in plan():
        print(f"{name}: {action}")
        if do:
            p = HOOKS / name
            p.write_text(body)
            p.chmod(p.stat().st_mode | stat.S_IXUSR)   # git SILENTLY SKIPS a non-executable hook
    if not do:
        print("(dry run; pass --install to write)")
    else:
        print(f"installed into {HOOKS}; verdicts appended to {VERDICT.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
