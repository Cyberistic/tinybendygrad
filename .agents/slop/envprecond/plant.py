#!/usr/bin/env python3
"""PLANT: prove `checks/env-precond.py`'s METHOD A can still REFUSE, on a COPY.

Run: .venv/bin/python .agents/slop/envprecond/plant.py

METHOD A now pins an ANCHOR (a token match on the line's job) plus the tokens the line
must carry. So there are two questions a plant has to ask, and the first one is the fix:

  EDIT-ABOVE  insert a line ABOVE the census capture -- the bug that made the old
              line-number pin red. The check must STILL PASS (the anchor moved with it).
  BROKEN      strip PYTHONHASHSEED/NOOPT from differ.py's ENV line. The check must REFUSE.

Sources are copied to a TemporaryDirectory; the live tree is never written.
"""
from __future__ import annotations

import importlib.util
import pathlib
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
TARGETS = ("checks/differ.py", ".agents/slop/graphcmp-oracle.py",
           ".agents/slop/graphcmp.py", "runs/graphcmp/D/D0-run-summary.txt")


def load_env_precond():
    spec = importlib.util.spec_from_file_location("env_precond", ROOT / "checks/env-precond.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["env_precond"] = mod
    spec.loader.exec_module(mod)
    return mod


def sources_of(tree: pathlib.Path) -> dict[str, list[str]]:
    return {p: (tree / p).read_text().splitlines() for p in TARGETS if p.endswith((".py",))}


def run(env, tree: pathlib.Path, label: str, expect: int) -> bool:
    rc = env.check(sources=sources_of(tree), summary=tree / "runs/graphcmp/D/D0-run-summary.txt")
    ok = (rc == 0) == (expect == 0)
    print(f"  {label:<12} -> exit {rc}  (expected {'0' if expect == 0 else '!= 0'}): "
          f"{'CORRECT' if ok else 'WRONG'}")
    return ok


def main() -> int:
    env = load_env_precond()
    bad = []
    with tempfile.TemporaryDirectory() as td:
        tree = pathlib.Path(td) / "tree"
        for p in TARGETS:
            dst = tree / p
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / p, dst)

        print("STATE 1 -- the tree as copied (untouched)")
        if not run(env, tree, "as-is", 0):
            bad.append("state 1")

        print("\nSTATE 2 -- ONE LINE INSERTED ABOVE THE CENSUS CAPTURE (the old bug)")
        differ = tree / "checks/differ.py"
        body = differ.read_text().splitlines()
        at = next(i for i, ln in enumerate(body) if 'capture("D0-coverage-census.txt"' in ln)
        body.insert(at, "# an edit above the pin, exactly what moved :509 to :513")
        differ.write_text("\n".join(body) + "\n")
        if not run(env, tree, "edit-above", 0):
            bad.append("state 2")
        print("  ^ the anchor travelled with the call: a line-number pin would have gone red here")

        print("\nSTATE 3 -- differ.py's ENV STRIPPED OF PYTHONHASHSEED/NOOPT (the assertion)")
        keep = differ.read_text()
        differ.write_text(keep.replace(
            '{"LC_ALL": "C", "DEV": "NULL", "PYTHONHASHSEED": "0", "NOOPT": "0"}',
            '{"LC_ALL": "C", "DEV": "NULL"}'))
        if not run(env, tree, "broken", 1):
            bad.append("state 3")

        print("\nSTATE 4 -- restored")
        differ.write_text(keep)
        if not run(env, tree, "restored", 0):
            bad.append("state 4")

    print("\nPLANT: " + ("FAILED -- " + "; ".join(bad) if bad else
                         "OK -- REFUSES when broken, PASSES when restored"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
