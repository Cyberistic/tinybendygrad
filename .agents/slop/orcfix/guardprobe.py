#!/usr/bin/env python3
"""Prove the declaration does what item 4 claims, WITHOUT editing `checks/no-txt.py` (another
unit owns it). It loads `no-txt.py`'s own functions by path, adds the ONE new carve-out the report
tells the orchestrator to wire, and reports the hard set -- so the wiring's effect is measured, not
asserted. It also plants a fresh `.txt` under `tinybendygrad/` and shows it still flags.
"""
from __future__ import annotations
import importlib.util, os, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]


def load(rel: str, name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def hard_with(extra: set[str]) -> list[str]:
    nt = load("checks/no-txt.py", "no_txt_probe")
    found = []
    for dirpath, dirnames, filenames in os.walk(nt.ROOT):
        dirnames[:] = [d for d in dirnames if d not in nt.SKIP]
        for f in sorted(filenames):
            if f.endswith(".txt"):
                rel = os.path.relpath(os.path.join(dirpath, f), nt.ROOT)
                if nt.owned(rel):
                    found.append(rel)
    excused = set(found) & (nt.excused_names() | extra)
    return [r for r in found if r not in excused]


def main() -> int:
    repro = load(".agents/slop/skipexit/repro.py", "repro")
    declared = set(repro.declared())
    on_disk = {r for r in hard_with(set())}
    print(f"repro.declared()            {len(declared)} names")
    print(f"declared present on disk    {len(declared & {os.path.relpath(p, ROOT) for p in (ROOT/'.agents/slop/e2epy/fixtures').rglob('*.txt')}) if (ROOT/'.agents/slop/e2epy/fixtures').exists() else 0}")
    print(f"HARD with no extra carve-out    {len(on_disk)}")
    for r in sorted(on_disk)[:20]:
        print(f"    {r}")
    wired = hard_with(declared)
    print(f"HARD after wiring declared()  {len(wired)}")
    for r in sorted(wired):
        print(f"    {r}")
    # THE PLANT: a fresh, undeclared `.txt` under tinybendygrad/ must STILL be reported.
    planted = ROOT / "tinybendygrad/orcfix-plant.txt"
    planted.parent.mkdir(parents=True, exist_ok=True)
    planted.write_text("planted=1\n")
    try:
        after = hard_with(declared)
    finally:
        planted.unlink()
    seen = any("orcfix-plant.txt" in r for r in after)
    print(f"fresh tinybendygrad/*.txt flagged by the wired guard: {seen}")
    ok = all(r.startswith(".agents/slop/e2epy/fixtures/repro-") for r in wired) and seen
    print(f"\nVERDICT: {'OK' if ok else 'PROBLEM'} -- declared lane excused, a new violation still seen.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
