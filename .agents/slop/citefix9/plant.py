#!/usr/bin/env python3
"""plant.py -- A TEXT EDIT ON A COPY that breaks ONE re-pointed citation, plus a
BYTE-IDENTICAL control.

    .venv/bin/python .agents/slop/citefix9/plant.py

THE PLANT is a TEXT EDIT on a COPY of the port tree -- NEVER `git show HEAD:`, because a
copy is the tree and `git show` is a file. The control is a BYTE-IDENTICAL copy of the
same tree, and it must give the SAME verdict: a plant whose control differs is measuring
the difference between two trees and not the gate.

THE GATE is `gates/pin-cite-gate.py` -- the instrument the census reads -- and the
VERDICT is its EXIT STATUS plus the FALSE ROW COUNT the census reports.
"""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FRZ = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/citefix9")

#: THE RE-POINTED CITATION THE PLANT BREAKS: one line, one number, moved by one.
REL = "tinybendygrad/renderer/llvmir.bend"
AT = 188
OLD = "tinygrad/dtype.py:238"
NEW = "tinygrad/dtype.py:239"


def run_gate(tree_root: Path, rows: Path) -> tuple[int, str]:
  """`tree_root` is the DIRECTORY THAT HOLDS `tinybendygrad/` -- the gate's `--tree`."""
  p = subprocess.run([sys.executable, str(ROOT / "gates" / "pin-cite-gate.py"),
                      "--tree", str(tree_root), "--rows", str(rows)],
                     cwd=ROOT, capture_output=True, text=True)
  return p.returncode, p.stdout + p.stderr


#: THE CENSUS'S OWN CLASSIFICATION, from `.agents/slop/citeclass/census.py`: a row is
#: FALSE unless it is `at_pin`, `uncheckable_no_claim_token` (no claim at all) or
#: `unverifiable` (no claim ABOUT THE CITED FILE).
NOT_FALSE = {"at_pin", "uncheckable_no_claim_token", "unverifiable"}


def false_count(pin_rows: Path) -> int:
  with pin_rows.open() as fh:
    rows = list(csv.DictReader(fh, delimiter="\t"))
  return sum(1 for r in rows
             if r["class"] not in NOT_FALSE
             and not r["rel"].startswith("tinybendygrad/runtime/"))


def main() -> int:
  with tempfile.TemporaryDirectory(prefix="citefix9-plant-") as raw:
    td = Path(raw)
    control, planted = td / "control", td / "planted"
    for dest in (control, planted):
      shutil.copytree(ROOT / "tinybendygrad", dest / "tinybendygrad")
    ctl_rel = control / "tinybendygrad" / REL[len("tinybendygrad/"):]
    plt_rel = planted / "tinybendygrad" / REL[len("tinybendygrad/"):]
    # THE CONTROL IS BYTE-IDENTICAL TO THE LIVE TREE.
    assert ctl_rel.read_bytes() == (ROOT / REL).read_bytes(), "the control is not the live tree"
    # THE PLANT: ONE TEXT EDIT, ON THE COPY.
    lines = plt_rel.read_text().splitlines()
    assert OLD in lines[AT - 1], f"line {AT} does not carry {OLD!r}"
    lines[AT - 1] = lines[AT - 1].replace(OLD, NEW)
    plt_rel.write_text("\n".join(lines) + ("\n" if plt_rel.read_bytes().endswith(b"\n") else ""))

    rc_ctl, out_ctl = run_gate(control, td / "ctl.rows")
    rc_pl, out_pl = run_gate(planted, td / "pl.rows")
    print(f"PLANT    : {REL}:{AT}  {OLD} -> {NEW}")
    print(f"CONTROL  : a byte-identical copy -> rc={rc_ctl} "
          f"{'GREEN' if rc_ctl == 0 else 'RED'}")
    print(f"PLANTED  : the edited copy       -> rc={rc_pl} "
          f"{'GREEN' if rc_pl == 0 else 'RED'}")
    for line in out_pl.splitlines():
      if "FAIL" in line or "dangling" in line:
        print(f"    {line.strip()}")
    # THE CENSUS, on the SAME two trees.
    fc_ctl = false_count(td / "ctl.rows")
    fc_pl = false_count(td / "pl.rows")
    print(f"CENSUS   : control {fc_ctl} false row(s); planted {fc_pl} false row(s)")
    ok = rc_ctl == 0 and rc_pl != 0 and fc_pl == fc_ctl + 1
    print("PLANT OK" if ok else "PLANT FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
  raise SystemExit(main())
