"""RE-FREEZE `checks/e2e.py`'S TWO PINS FROM THE TWO FILES, AND PROVE THE DECLARED-EDIT INVARIANT.

THE PIN MOVES WITH THE EDIT, AND A PIN MOVED BY HAND IS A PIN THAT WILL EVENTUALLY NOT MATCH. So
this derives both hashes from disk, writes them into `checks/e2e.py`, and then CHECKS what it wrote
by reading `checks/e2e.py` BACK and asking three questions that share no code with the writer:

  1. does `checks/e2e.py` report drift?  (`oracle_drift() == []`)
  2. does reverting the copy's DOCUMENTED EDITS reproduce `checks/e2e.sh` byte for byte?
  3. does `sha256(checks/e2e.sh)` equal the `BODY_SHA` now in the file?

(2) and (3) are checked with `difflib` and `hashlib` respectively, so a bug in the rewriter that
wrote a consistent-looking but wrong pair still fails here.

`--check` DOES NOT WRITE and is what the other gates and this file's own prose refer to; with no flag
it rewrites the two `*_SHA = "..."` lines in place and nothing else.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import re
import sys
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve()
REPO = HERE.parents[3]
PORT, BODY, ORACLE = REPO / "checks/e2e.py", REPO / "checks/e2e.sh", \
    REPO / ".agents/slop/e2epy/oracle-e2e.sh"
SHA_LINE = re.compile(r'^(ORACLE_SHA|BODY_SHA) = "[0-9a-f]{64}"$', re.M)


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load_port():
    """`checks/e2e.py` as a MODULE, so `oracle_drift()` is callable without running seven stages.

    **COMPILED FROM THE SOURCE TEXT, NOT `module_from_spec`, AND THE REASON IS MEASURED.** The
    import machinery resolves a module through `__pycache__` and treats a cached `.pyc` as current when
    the source's **mtime AND SIZE** both match. A `*_SHA` line is 64 hex characters, so every
    re-freeze this file has ever performed replaced 64 characters with 64 characters -- the size never
    changes. MEASURED 2026-10-19, in a scratch tree of this exact shape: overwrite
    `BODY_SHA = "2ef51412..."` with `"9925f75c..."` (length preserved) within the same wall-clock
    second as an import, load again, and the second load answers **`2ef51412`** -- the PRE-EDIT pin,
    served from `checks/__pycache__/e2e.cpython-312.pyc`, which this tree's own readers create.
    **A PIN THAT CAN BE READ BACK STALE IS NOT A PIN, AND THE ERROR IS SILENT IN BOTH DIRECTIONS:**
    this file would have reported a green against bytes that no longer existed. `.agents/slop/e2esh/
    plant.py:drift()` has always used `exec(compile(src, ...))` and is immune; this adopts its idiom
    rather than inventing a second one.
    """
    ns: dict = {"__file__": str(PORT), "__name__": "e2epin"}
    exec(compile(PORT.read_text(), str(PORT), "exec"), ns)   # noqa: S102 -- it is our own file
    return SimpleNamespace(**{k: v for k, v in ns.items() if not k.startswith("__")})


def verify() -> list[str]:
    """THE THREE QUESTIONS. An empty list means the pair is right."""
    port = load_port()
    bad = [f"oracle_drift(): {d}" for d in port.oracle_drift()]
    # `revert_oracle()` IS `checks/e2e.py`'S OWN TRANSFORM, so this reader and `oracle_drift()` cannot
    # disagree about what the declared delta is. MEASURED 2026-10-19, before this line: it applied
    # `ORACLE_EDIT` ALONE -- one pair out of the eleven -- so question (2) reported a byte difference
    # that was really the ten pairs this reader had never heard of, and its own comment admitted it.
    reverted = port.revert_oracle(ORACLE.read_bytes().decode()).encode()
    if reverted != BODY.read_bytes():
        delta = "".join(difflib.unified_diff(BODY.read_text().splitlines(True),
                                             reverted.decode().splitlines(True), "e2e.sh", "reverted",
                                             n=0))[:600]
        bad.append(f"revert(oracle) != checks/e2e.sh\n{delta}")
    if sha(BODY) != port.BODY_SHA:
        bad.append(f"BODY_SHA in {PORT.name} is {port.BODY_SHA[:16]}, file is {sha(BODY)[:16]}")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(prog=__file__, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="verify only, write nothing")
    opts = ap.parse_args()
    want = {"ORACLE_SHA": sha(ORACLE), "BODY_SHA": sha(BODY)}
    print(f"ORACLE_SHA {want['ORACLE_SHA']}  {ORACLE.relative_to(REPO)}")
    print(f"BODY_SHA   {want['BODY_SHA']}  {BODY.relative_to(REPO)}")
    if opts.check:
        print("(check only: nothing written)")
    else:
        src = PORT.read_text()
        for name, value in want.items():
            src, n = re.subn(rf'^{name} = "[0-9a-f]{{64}}"$', f'{name} = "{value}"', src,
                             count=1, flags=re.M)
            assert n == 1, f"{name} not found in {PORT}"
        PORT.write_text(src)
        print(f"(rewrote both *_SHA lines in {PORT.relative_to(REPO)})")
    bad = verify()
    for b in bad:
        print(f"  FAIL {b}")
    print("the declared-edit invariant holds" if not bad else f"{len(bad)} failure(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())