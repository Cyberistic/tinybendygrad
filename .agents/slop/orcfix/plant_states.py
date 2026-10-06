#!/usr/bin/env python3
"""Item 5: the two-state plant, and the declaration's effect, measured in one atomic sequence so a
parallel unit cannot change the tree between beats.

  1. clean no-txt                                       -> rc 0
  2. run the pre-fix-lane harness (`skipexit/repro.py`) -> 15 undeclared `.txt` appear
  3. no-txt over them                                   -> rc 1, NAMING them
  4. the SAME tree with the report's one-line wiring    -> rc 0 (the lane is excused)
  5. a FRESH `.txt` under `tinybendygrad/` (wired)      -> rc 1, NAMING IT  (the guard still sees)
  6. remove everything this script created              -> rc 0
"""
from __future__ import annotations
import importlib.util, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PY = str(ROOT / ".venv/bin/python")
FIX = ROOT / ".agents/slop/e2epy/fixtures"


def load(rel, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def no_txt_rc() -> tuple[int, list[str]]:
    r = subprocess.run([PY, "checks/no-txt.py"], cwd=ROOT, capture_output=True, text=True)
    hard = [l.strip() for l in r.stdout.splitlines()
            if l.strip().startswith(".agents/") or l.strip().startswith("tinybendygrad/")
            or l.strip().startswith("oracles/")]
    return r.returncode, hard


def wired_rc(extra: set[str]) -> tuple[int, list[str]]:
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


def fixture_txt() -> set[str]:
    if not FIX.exists():
        return set()
    return {str(p.relative_to(ROOT)) for p in FIX.rglob("*.txt")}


def main() -> int:
    repro = load(".agents/slop/skipexit/repro.py", "repro")
    declared = set(repro.declared())
    planted = ROOT / "tinybendygrad/orcfix-plant.txt"

    def clean_fixtures():
        for p in sorted(FIX.rglob("*.txt")):
            p.unlink()

    clean_fixtures()
    rc0, _ = no_txt_rc()
    print(f"1. clean tree                      no-txt rc={rc0}  (want 0)")

    subprocess.run([PY, ".agents/slop/skipexit/repro.py"], cwd=ROOT,
                   capture_output=True, text=True)
    made = fixture_txt()
    print(f"2. pre-fix lane run                {len(made)} .txt created under fixtures/")

    rc2, hard2 = no_txt_rc()
    named = sorted(set(hard2) & made)
    print(f"3. UNWIRED no-txt                  rc={rc2}  names {len(named)}/{len(made)} of them")

    rc3, hard3 = wired_rc(declared)
    print(f"4. WIRED with repro.declared()     rc={rc3}  (want 0; the {len(declared)}-name lane excused)")

    planted.parent.mkdir(parents=True, exist_ok=True)
    planted.write_text("planted=1\n")
    try:
        rc4, hard4 = wired_rc(declared)
    finally:
        planted.unlink()
    seen = any("orcfix-plant.txt" in h for h in hard4)
    print(f"5. FRESH tinybendygrad/*.txt        rc={rc4}  names it={seen}  (want rc 1, True)")

    clean_fixtures()
    rc5, _ = no_txt_rc()
    print(f"6. cleaned                          no-txt rc={rc5}  (want 0)")

    ok = (rc0 == 0 and len(made) == 15 and rc2 == 1 and len(named) == 15
          and rc3 == 0 and rc4 == 1 and seen and rc5 == 0)
    print(f"\nVERDICT: {'PLANTS HOLD' if ok else 'A PLANT DID NOT MOVE'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
