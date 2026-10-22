#!/usr/bin/env python3
"""bend-absent.py -- THE REFUSAL THAT STANDS IN FOR A COMPILER THAT IS NOT THERE.

    gates/gatekit.py points `BEND` at this file when the tree has no `bin/bend`.

WHY IT EXISTS, AND WHY IT IS A FILE AND NOT AN EXCEPTION. `.gitignore:5` ignores `/bin/bend`
and `git ls-tree -r HEAD -- bin/` is EMPTY, so a CLEAN CHECKOUT HAS NO COMPILER -- and every
GitHub Actions run of `.github/workflows/edge-gates.yml` IS a clean checkout. MEASURED
2026-10-22, in a clean checkout of this tree:

    $ .venv/bin/python checks/bounded.py --seconds 30 --mb 3072 -- \
          .venv/bin/python gates/mixin-op-gate.py
    [bounded] WITHIN-LIMITS  rc=1  peak-RSS=21 MB (ceiling 3072)  0s  :: ... out=0B err=1422B
    Traceback (most recent call last):
      File ".../gates/gatekit.py", line 460, in _warm
        out = subprocess.run([str(BEND), str(self.bend), "--check-only"],
    FileNotFoundError: [Errno 2] No such file or directory: '.../bin/bend'

`checks/gatesweep.py:classify()` reads that as `rc == 1 and "Traceback (most recent call last)"
in text` and answers `("DEAD", "TRACEBACK")`. **THAT VERDICT IS FALSE.** `DEAD` means "it ran and
emitted nothing"; this gate never ran its comparison at all. The absent compiler is a
PRECONDITION THAT WAS ABSENT, and the tree already has a word for that: `REFUSED`. The
workflow's own prose says so -- `.github/workflows/edge-gates.yml:82-85`: "a missing toolchain
makes a gate REFUSE (a precondition was absent), which is the honest verdict" -- and the code
did not do it. **THE PROSE WAS A PROSE PIN.**

SO THE ABSENCE IS SPOKEN BY A PROCESS THAT EXISTS. `gates/gatekit.py` names THIS file instead of
a path that is not there, every caller of `BEND` runs it instead of raising, and the exit status
is the tree's own `REFUSED` (3). A gate that cannot compile REFUSES; it does not crash.

EXIT STATUS: 3 -- `gates/gatekit.py`'s `REFUSED`. The arguments are ignored on purpose: this
file is not a compiler and pretending to accept a driver's path would be a lie a reader has to
unpick. The message names the missing path, because "the toolchain is absent" and "the toolchain
is absent FROM HERE" are different bugs.
"""
import sys

MISSING = "the toolchain is absent: this tree has no `bin/bend` -- REFUSED, NOT A VERDICT"

if __name__ == "__main__":
    print(MISSING, file=sys.stderr)
    sys.exit(3)
