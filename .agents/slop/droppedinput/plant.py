#!/usr/bin/env python3
"""The two directions, on a FABRICATED tree. No live tree is touched and no `bend` runs.

The real `snapshot.py` is LOADED BY PATH and its `ROOT` is re-pointed at a temp tree, so the
functions under test are the shipped ones and not a re-implementation of them.

  A. a DECLARED path PRESENT  -> it is a member, and MANIFEST.tsv carries its SHA.
  B. a DECLARED path ABSENT   -> it is STILL a member, MANIFEST.tsv carries `ABSENT`, the
     path is NAMED in the output, and the count includes it.  <-- the direction that was broken
  C. CONTROL: a path that is neither declared nor under the port is NOT a member. If B were
     implemented by walking the whole tree, C would fail -- so C is the assertion that can be
     false, and it is what stops `B` from being satisfied by "add everything".
  D. `--verify` on the planted snapshot reads the `ABSENT` row without crashing, and says so.

    usage: .venv/bin/python .agents/slop/droppedinput/plant.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
SNAP = ROOT / ".agents/slop/quiesce/snapshot.py"


def load():
    spec = importlib.util.spec_from_file_location("droppedinput_snap", SNAP)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["droppedinput_snap"] = mod
    spec.loader.exec_module(mod)
    return mod


class Tally:
    def __init__(self) -> None:
        self.bad = 0

    def expect(self, label: str, got, want) -> None:
        ok = got == want
        self.bad += not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {label}  got={got!r} want={want!r}")


def main() -> int:
    mod = load()
    t = Tally()
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        tree, dest = td / "tree", td / "snap"
        (tree / "tinybendygrad").mkdir(parents=True)
        (tree / "tinybendygrad/port.bend").write_text("port\n")
        (tree / "harness.py").write_text("harness\n")
        (tree / "undelared.py").write_text("never declared, never walked\n")
        (tree / "gone.bend").write_text("declared then removed\n")
        (tree / "gone.bend").unlink()          # B: a declared member with no bytes
        (tree / "kept.bend").write_text("declared and present\n")   # A

        kept = mod.ROOT
        mod.ROOT = tree
        mod.COPIES = ("harness.py", "kept.bend", "gone.bend")     # `undelared.py` is NOT here
        try:
            pop = [p.relative_to(tree).as_posix() for p in mod.inputs()]
            t.expect("A+B: a declared ABSENT path is still a member", "gone.bend" in pop, True)
            t.expect("A: a declared PRESENT path is a member", "kept.bend" in pop, True)
            # C -- the control that can be FALSE. `undelared.py` is on disk and under the tree's
            # root but was never declared; if `inputs()` had been "walk everything" it would be in.
            t.expect("C CONTROL: an UNDECLARED file is not a member", "undelared.py" in pop, False)
            t.expect("C CONTROL: the port is walked (discovery half still works)",
                     "tinybendygrad/port.bend" in pop, True)

            rc = mod.build(dest, None)
            man = (dest / "MANIFEST.tsv").read_text().splitlines()
            rows = {rel: blob for blob, rel in (r.split("\t") for r in man)}
            t.expect("build rc", rc, 0)
            t.expect("B: the ABSENT member is a MANIFEST row", rows.get("gone.bend"), "ABSENT")
            t.expect("A: the PRESENT member is a MANIFEST row carrying a sha",
                     len(rows.get("kept.bend", "")), 64)
            t.expect("C: the undeclared file has no row", "undelared.py" in rows, False)
            t.expect("count == declared members (3 copies + 1 port file)", len(man), 4)

            vrc = mod.verify(dest)
            t.expect("D: --verify rc", vrc, 0)
        finally:
            mod.ROOT = kept
    print(f"PLANT: {'OK' if t.bad == 0 else 'FAILED'}  ({t.bad} failing assertion(s))")
    return 0 if t.bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())