#!/usr/bin/env python3
"""plant.py -- THE PLANT: A TEXT EDIT ON A COPY THAT BREAKS ONE RE-POINTED CITATION.

    .venv/bin/python .agents/slop/citefix-runtime/plant.py

THE PLANT IS A PLANT, NOT A FIX: it edits a COPY of the port tree (never the live tree,
never `git show HEAD:`), moves ONE cited line by one, and shows the GATE GOING RED on the
planted copy and staying GREEN on a BYTE-IDENTICAL control.

THE GATE IS `gates/todo-cite-gate.py`, because THAT is the instrument that judges the
durable form (`symbol=`). The pin-cite census is the instrument that MEASURED the class
(the citations the todo-cite gate does not read); after this unit's work every citation in
`tinybendygrad/runtime/` is in the todo-cite gate's population, so the census's slice is
empty and a plant has to break a row the durable instrument reads.

THE CONTROL AND THE PLANT ARE JUDGED ON COPIES, so the two readings compare the same tree
state and differ only by the edit.
"""

from __future__ import annotations

import csv
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".agents" / "slop" / "citefix-runtime"
OK = ("RESOLVES", "PORT-CITATION", "NO-CITATION")


def mine() -> set[str]:
  out = subprocess.run(["git", "diff", "--name-only", "--", "tinybendygrad/runtime/"],
                       cwd=ROOT, capture_output=True, text=True).stdout.split()
  return set(out)


def judge(port: Path, tag: str) -> list[dict]:
  rows_file = WORK / f"plant-{tag}.rows"
  subprocess.run([sys.executable, str(ROOT / "gates" / "todo-cite-gate.py"),
                  "--port", str(port), "--rows", str(rows_file)],
                 cwd=ROOT, capture_output=True, text=True)
  return list(csv.DictReader(open(rows_file, encoding="utf-8"), delimiter="\t"))


def main() -> int:
  files = mine()
  base = Path(tempfile.mkdtemp(prefix="citefix-plant-"))
  control, planted = base / "control", base / "planted"
  for d in (control, planted):
    shutil.copytree(ROOT / "tinybendygrad", d / "tinybendygrad")
  # THE PLANTED EDIT: move ONE cited line by one, in a COPY.
  target = planted / "tinybendygrad" / "runtime" / "ops_amd.bend"
  src = target.read_text(encoding="utf-8").split("\n")
  moved = 0
  for i, ln in enumerate(src):
    if "tinygrad/runtime/ops_amd.py:374 symbol=kernargs" in ln:
      src[i] = ln.replace("tinygrad/runtime/ops_amd.py:374 symbol=kernargs",
                           "tinygrad/runtime/ops_amd.py:380 symbol=kernargs")
      moved += 1
  target.write_text("\n".join(src), encoding="utf-8")
  print(f"PLANT   : moved {moved} citation(s) in the COPY {target}")
  if moved != 1:
    print("PLANT FAILED: the citation to move was not found")
    return 1
  c_rows, p_rows = judge(control / "tinybendygrad", "control"), judge(planted / "tinybendygrad", "planted")
  c_bad = [r for r in c_rows if r["rel"] in files and r["verdict"] not in OK]
  p_bad = [r for r in p_rows if r["rel"] in files and r["verdict"] not in OK]
  print(f"CONTROL : {len(c_bad)} false row(s) in the {len(files)} file(s) this unit touched")
  print(f"PLANT   : {len(p_bad)} false row(s) in the {len(files)} file(s) this unit touched")
  c_key = {(r["rel"], r["at"], r["subject"], r["lo"]) for r in c_bad}
  new = [r for r in p_bad if (r["rel"], r["at"], r["subject"], r["lo"]) not in c_key]
  for r in new:
    print(f"   NEW  {r['rel']}:{r['at']}  {r['subject']}:{r['lo']}  [{r['verdict']}]  {r['how']}")
    print(f"        {r['line'].strip()[:110]}")
  ok = len(new) >= 1 and len(c_bad) == 0
  print("PLANT OK" if ok else "PLANT FAILED")
  shutil.rmtree(base, ignore_errors=True)
  return 0 if ok else 1


if __name__ == "__main__":
  raise SystemExit(main())
