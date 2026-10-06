#!/usr/bin/env python3
"""PLANT: the carve-out's sharp edge, both directions, measured rather than argued.

`.agents/slop/difftxt/DECISION.md` buys its safety with a claim: the excuse is
`differ.declared()` -- IMPORTED, not copied -- so "a `.txt` under `runs/graphcmp/D/` that no
command writes is still reported". A carve-out derived from a declaration is only as good as the
declaration, so this plants both halves of the failure the declaration is supposed to catch:

  PLANT A  an ORPHAN: a `.txt` no command writes. It must appear in `checks/no-txt.py`'s HARD
           set and in `artefacts_ok()`'s findings, as UNEXPECTED. DECISION.md measured
           602 -> 603; this re-measures it on the live tree.

  PLANT B  a DECLARED-BUT-ABSENT name: hide one of the 103 and leave it absent. It must appear
           as MISSING, because the declaration and the tree diverging SILENTLY is the other way
           the carve-out rots. DECISION.md never planted this.

Both plants are undone in a `finally`, and both leave `runs/graphcmp/D` byte-identical.

usage: .venv/bin/python .agents/slop/txtgen/orphan-plant.py

exit 0  both plants behaved as the carve-out claims
exit 1  a plant did not
"""
import importlib.util
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
D = ROOT / "runs/graphcmp/D"
ORPHAN = "D0-PLANTED-ORPHAN.txt"          # a name no table in differ.py can produce
BODY = "planted by orphan-plant.py: a .txt that no command writes\n"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def hard_set(nt):
    """`no-txt.py`'s hard set, by IMPORTING it so the count is the instrument's own."""
    found = []
    for dirpath, dirnames, filenames in __import__("os").walk(nt.ROOT):
        dirnames[:] = [d for d in dirnames if d not in nt.SKIP]
        for f in sorted(filenames):
            if f.endswith(".txt"):
                rel = __import__("os").path.relpath(__import__("os").path.join(dirpath, f),
                                                     nt.ROOT)
                if nt.owned(rel):
                    found.append(rel)
    excused = set(found) & nt.graphcmp_artifacts()
    return [r for r in found if r not in excused]


def main() -> int:
    nt = load(ROOT / "checks/no-txt.py", "nt")
    differ = load(ROOT / "checks/differ.py", "differ")

    baseline_set = hard_set(nt)
    baseline_hard = len(baseline_set)
    baseline_findings = differ.artefacts_ok()
    hidden = sorted(differ.declared())[0]
    saved = (D / hidden).read_bytes()
    ok = True

    print(f"live tree: {baseline_hard} unexcused .txt, "
          f"{len(baseline_findings)} artefacts_ok() finding(s)\n")

    try:
        # ---- PLANT A: AN ORPHAN. A `.txt` under the excused directory that nothing declares.
        (D / ORPHAN).write_text(BODY)
        a_hard = hard_set(nt)
        a_find = differ.artefacts_ok()
        a_excused = f"runs/graphcmp/D/{ORPHAN}" not in a_hard
        print("PLANT A  an orphan `.txt` that no command writes")
        print(f"  in the CARVE-OUT?          {'yes -- LEAKED, the carve-out is a blanket' if a_excused else 'no  -- correct, it is not in declared()'}")
        print(f"  unexcused count           {baseline_hard} -> {len(a_hard)}  "
              f"({'MOVED, as DECISION.md measured' if len(a_hard) > baseline_hard else 'DID NOT MOVE -- carve-out is too wide'})")
        print(f"  artefacts_ok() verdict    {'UNEXPECTED' if any('UNEXPECTED' in f for f in a_find) else 'SILENT -- no guard'}")
        ok &= (not a_excused) and len(a_hard) == baseline_hard + 1
        ok &= any("UNEXPECTED" in f for f in a_find)
        (D / ORPHAN).unlink()

        # ---- PLANT B: A DECLARED NAME THAT IS NOT THERE. The other rot direction.
        (D / hidden).unlink()
        b_find = differ.artefacts_ok()
        b_hard = hard_set(nt)
        print(f"\nPLANT B  declared `{hidden}` removed from the tree")
        print(f"  unexcused count           {len(a_hard)} -> {len(b_hard)}  "
              f"({'down one, because the FILE is gone -- an absent name is not a .txt on disk' if len(b_hard) == len(a_hard) - 1 else 'CHANGED -- unexpected'})")
        print(f"  artefacts_ok() verdict    {'MISSING' if any('MISSING' in f for f in b_find) else 'SILENT -- declaration and tree diverged unnoticed'}")
        ok &= len(b_hard) == len(a_hard) - 1
        ok &= any("MISSING" in f for f in b_find)
    finally:
        (D / hidden).write_bytes(saved)
        (D / ORPHAN).unlink(missing_ok=True)

    after_hard = hard_set(nt)
    after_find = differ.artefacts_ok()
    print(f"\nrestored: {len(after_hard)} unexcused .txt, {len(after_find)} finding(s); "
          f"`{hidden}` is byte-identical again")
    ok &= after_hard == baseline_set and len(after_find) == len(baseline_findings)

    print("\nVERDICT: the carve-out is a DECLARATION, and both plants were caught."
          if ok else "\nVERDICT: A PLANT WAS NOT CAUGHT.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())