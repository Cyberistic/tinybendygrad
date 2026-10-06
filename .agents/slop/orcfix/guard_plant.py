#!/usr/bin/env python3
"""Item 5, two states, with the REAL `checks/no-txt.py` for the unwired state.

Running `skipexit/repro.py` is not usable right now: a concurrent unit is editing `checks/e2e.py`
(mtime moved to 00:39) and the post-fix lane no longer writes its `runs/e2e/e2e-f64.out`, so the
harness dies with `FileNotFoundError` before the pre-fix lane leaves its `.txt`. Instead this
materialises EXACTLY the 15 paths `repro.declared()` derives -- i.e. the frozen pre-fix lane's own
output names -- and measures the guard on them. The names are not typed here; they come from
`declared()`, so the plant is the declaration talking.

  1  fixtures clean, fresh tinybendygrad/*.txt removed   -> no-txt rc 0
  2  the 15 declared lane outputs present                 -> no-txt rc 1, NAMING every one
  3  same tree, with the report's one-line wiring         -> rc 0   (the lane is excused)
  4  a FRESH undeclared tinybendygrad/*.txt, wired        -> rc 1, NAMING IT  (the guard sees it)
  5  everything this script created removed               -> no-txt rc 0
"""
from __future__ import annotations
import importlib.util, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PY = str(ROOT / ".venv/bin/python")


def load(rel, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def no_txt() -> tuple[int, list[str]]:
    r = subprocess.run([PY, "checks/no-txt.py"], cwd=ROOT, capture_output=True, text=True)
    hard = [l.strip() for l in r.stdout.splitlines()
            if l.strip().split("/")[0] in (".agents", "tinybendygrad", "oracles")]
    return r.returncode, hard


def wired(extra: set[str]) -> tuple[int, list[str]]:
    nt = load("checks/no-txt.py", "nt_probe")
    found = []
    for dp, dns, fns in os.walk(nt.ROOT):
        dns[:] = [d for d in dns if d not in nt.SKIP]
        for f in sorted(fns):
            if f.endswith(".txt"):
                rel = os.path.relpath(os.path.join(dp, f), nt.ROOT)
                if nt.owned(rel):
                    found.append(rel)
    excused = set(found) & (nt.excused_names() | extra)
    hard = [r for r in found if r not in excused]
    return (1 if hard else 0), hard


def main() -> int:
    repro = load(".agents/slop/skipexit/repro.py", "repro")
    declared = set(repro.declared())
    planted = ROOT / "tinybendygrad/orcfix-plant.txt"
    made = [ROOT / n for n in declared]
    for p in made:
        p.unlink(missing_ok=True)
    planted.unlink(missing_ok=True)
    rc0, _ = no_txt()
    print(f"1. clean                             no-txt rc={rc0}   (want 0)")
    try:
        for p in made:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("lane=1\n")
        rc1, hard1 = no_txt()
        named1 = len(set(hard1) & declared)
        print(f"2. {len(made)} declared lane outputs         no-txt rc={rc1}   names {named1}/{len(made)}")
        rc2, hard2 = wired(declared)
        print(f"3. same tree + one-line wiring        rc={rc2}   (want 0; all named by declared())")
        planted.write_text("planted=1\n")
        rc3, hard3 = wired(declared)
        seen = any("orcfix-plant.txt" in h for h in hard3)
        print(f"4. FRESH undeclared tinybendygrad/*.txt rc={rc3}  names it={seen}  (want rc 1, True)")
    finally:
        for p in made:
            p.unlink(missing_ok=True)
        planted.unlink(missing_ok=True)
    rc4, _ = no_txt()
    print(f"5. cleaned                           no-txt rc={rc4}   (want 0)")
    ok = rc0 == 0 and rc1 == 1 and named1 == len(made) and rc2 == 0 and rc3 == 1 and seen and rc4 == 0
    print(f"\nVERDICT: {'PLANTS HOLD' if ok else 'A PLANT DID NOT MOVE'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
