"""RE-FREEZE `checks/e2e.py`'S TWO PINS FROM THE TWO FILES, AND PROVE THE ONE-EDIT INVARIANT.

THE PIN MOVES WITH THE EDIT, AND A PIN MOVED BY HAND IS A PIN THAT WILL EVENTUALLY NOT MATCH. So
this derives both hashes from disk, writes them into `checks/e2e.py`, and then CHECKS what it wrote
by reading `checks/e2e.py` BACK and asking three questions that share no code with the writer:

  1. does `checks/e2e.py` report drift?  (`oracle_drift() == []`)
  2. does reverting the copy's ONE documented edit reproduce `checks/e2e.sh` byte for byte?
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
import importlib.util
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
REPO = HERE.parents[3]
PORT, BODY, ORACLE = REPO / "checks/e2e.py", REPO / "checks/e2e.sh", \
    REPO / ".agents/slop/e2epy/oracle-e2e.sh"
SHA_LINE = re.compile(r'^(ORACLE_SHA|BODY_SHA) = "[0-9a-f]{64}"$', re.M)


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load_port():
    """`checks/e2e.py` as a MODULE, so `oracle_drift()` is callable without running seven stages."""
    spec = importlib.util.spec_from_file_location("e2epin", PORT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def verify() -> list[str]:
    """THE THREE QUESTIONS. An empty list means the pair is right."""
    port = load_port()
    bad = [f"oracle_drift(): {d}" for d in port.oracle_drift()]
    reverted = ORACLE.read_bytes().decode().replace(*port.ORACLE_EDIT).encode()
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
    print("the one-documented-edit invariant holds" if not bad else f"{len(bad)} failure(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())