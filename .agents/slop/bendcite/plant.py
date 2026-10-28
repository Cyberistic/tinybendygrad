#!/usr/bin/env python3
"""THE PLANT: a TEXT EDIT on a COPY that moves a cited line, and a BYTE-IDENTICAL copy.

NEVER `git show HEAD:` -- the subject of the plant is a COPY of the port tree on disk,
edited as TEXT, so the plant proves the instrument reads the tree it is pointed at.

    .venv/bin/python .agents/slop/bendcite/plant.py
"""
import importlib.util
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(".").resolve()
spec = importlib.util.spec_from_file_location("bc", ROOT / "gates/bendcite-gate.py")
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)

BAD = ("WRONG-LINE", "DANGLING-LINE", "ABSENT-FILE")
#: THE CITING FILE AND THE CITED FILE THIS PLANT USES. A row of MINE, so the plant is
#: about a pointer this slice actually rewrote.
CITING = "tinybendygrad/nn/mnist_cnn.bend"
CITED = "tinybendygrad/nn/layers.bend"


def rows_for(base: Path) -> list[dict]:
  rows, _c = bc.census(base)
  return [r for r in rows
          if r["rel"] == CITING and r["subject"].endswith("layers.bend")]


def main() -> int:
  bad: list[str] = []
  with tempfile.TemporaryDirectory(prefix="bendcite-slice-plant-") as raw:
    td = Path(raw)
    snap = td / "snap"
    snap.mkdir(parents=True)
    shutil.copytree(ROOT / "tinybendygrad", snap / "tinybendygrad")
    control = rows_for(snap)
    print(f"PLANT control   : {[(r['subject'], r['lo'], r['verdict']) for r in control]}")
    if not control or any(r["verdict"] in BAD for r in control):
      bad.append("the control does not hold")

    # ---- ARM ONE: A TEXT EDIT THAT MOVES THE CITED LINE. Three lines are inserted at
    # the TOP of the cited file, so the construct the pointer names moves DOWN by 3.
    moved = td / "moved"
    shutil.copytree(snap, moved)
    victim = moved / CITED
    body = victim.read_text(encoding="utf-8").splitlines()
    victim.write_text("\n".join(["# PLANT: a line inserted above the cited construct"] * 3
                                + body) + "\n")
    after = rows_for(moved)
    print(f"PLANT moved     : {[(r['subject'], r['lo'], r['verdict']) for r in after]}")
    if not after or after[0]["verdict"] != "WRONG-LINE":
      bad.append("the moved copy did not go red")
    if after and after[0].get("decl") is None:
      bad.append("the moved row does not say where the construct IS")

    # ---- ARM TWO: A BYTE-IDENTICAL COPY. Same snapshot, same bytes, same verdicts.
    twin = td / "twin"
    shutil.copytree(snap, twin)
    same = all((snap / p).read_bytes() == (twin / p).read_bytes()
               for p in ("tinybendygrad/nn/layers.bend", "tinybendygrad/nn/mnist_cnn.bend"))
    twin_rows = rows_for(twin)
    print(f"PLANT twin      : {[(r['subject'], r['lo'], r['verdict']) for r in twin_rows]}  "
          f"byte-identical={same}")
    if not same or [r["verdict"] for r in twin_rows] != [r["verdict"] for r in control]:
      bad.append("the byte-identical twin did not reproduce the control")

  if bad:
    print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
    return 1
  print("PLANT OK: a moved line makes the pointer stale, a byte-identical copy does not.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
