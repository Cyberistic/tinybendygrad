"""THE SUBSTRATE POPULATION, BEFORE AND AFTER -- counted, not asserted.

Loads `checks/differ.py` BY PATH (so there is exactly one definition, per doctrine 1: a
population is declared by the generator, never restated here) and calls its own
`substrate_entries()`. It does NOT re-derive the walk and it does NOT keep a second copy of
`SUBSTRATE_INPUTS`: the "after" number is obtained by feeding the two candidate names through
`substrate_digest`'s OWN loop shape over the module's OWN `ROOT`, so a typo in the projection
would surface as a non-file rather than as a plausible count.

No compile, no `bend`, no subprocess. `ast.parse`-level cost only.

Usage:  .venv/bin/python .agents/slop/driverfix/population.py
"""

from __future__ import annotations

import hashlib
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[3]
CANDIDATES = (".agents/slop/graphcmp-dbg.bend", ".agents/slop/graphcmp-empty.bend")


def load() -> object:
    spec = importlib.util.spec_from_file_location("differ", HERE / "checks/differ.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main() -> int:
    d = load()
    before = d.substrate_entries()
    walked = len(before) - len(d.SUBSTRATE_INPUTS)

    print(f"SUBSTRATE_INPUTS   {len(d.SUBSTRATE_INPUTS)}")
    for r in d.SUBSTRATE_INPUTS:
        print(f"    {r}")
    print(f"SUBSTRATE_WALKS    {d.SUBSTRATE_WALKS}")
    print(f"\nPOPULATION BEFORE  {len(before)}   (walked {walked} + named {len(d.SUBSTRATE_INPUTS)})")
    print(f"DIGEST BEFORE      {d.substrate_digest()}")

    # --- the projected AFTER, without touching the file ---
    after_inputs = tuple(d.SUBSTRATE_INPUTS) + CANDIDATES
    walked_entries = [(p, b) for p, b in before if p not in d.SUBSTRATE_INPUTS]
    h = hashlib.sha256()
    for rel, blob in sorted(walked_entries + [(r, None) for r in after_inputs]):
        v = blob
        if v is None:
            p = d.ROOT / rel
            v = hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "ABSENT"
        h.update(rel.encode()); h.update(b"\0"); h.update(v.encode()); h.update(b"\0")

    print(f"\nPOPULATION AFTER   {walked + len(after_inputs)}   "
          f"(+{walked + len(after_inputs) - len(before)} vs before)")
    for r in CANDIDATES:
        p = d.ROOT / r
        print(f"    + {r}  {'present, sha256=' + hashlib.sha256(p.read_bytes()).hexdigest()[:16] if p.is_file() else 'ABSENT'}")
    print(f"DIGEST AFTER       {h.hexdigest()}")
    print(f"\nDIGEST MOVES       {h.hexdigest() != d.substrate_digest()}")

    # the question the whole edit turns on: is either already covered?
    have = {p for p, _ in before}
    print("\nALREADY IN THE POPULATION?")
    for r in CANDIDATES:
        print(f"    {r:36s} {'YES' if r in have else 'NO'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())