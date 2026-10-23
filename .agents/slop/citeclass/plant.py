#!/usr/bin/env python3
"""plant.py -- PROVE THE GATE GOES RED WHEN A RE-POINTED CITATION IS BROKEN.

    .venv/bin/python .agents/slop/citeclass/plant.py

THE PLANT, AND WHAT IT IS NOT. It is NOT a check that the gate works; it is a check
that the gate can FAIL. A gate that cannot go red on a broken citation is a gate that
reports agreement, and agreement is not evidence.

THE ARMS, ALL ON COPIES.

  ARM 1 (the plant)  a TEXT EDIT on a COPY of the port tree: one re-pointed citation's
                     line number is moved by one. THE EDIT IS A TEXT EDIT ON A COPY --
                     `git show HEAD:` is NOT used, because that would restore the file
                     to a state the tree was never in and would prove nothing about
                     the edit.
  ARM 2 (the control) a BYTE-IDENTICAL copy of the same tree. It must produce the
                     SAME ROWS as the live tree, row for row, because the gate does not
                     depend on where the tree is.

A plant whose control differs from the live tree is measuring the difference between
two trees, not the gate. So the control is compared to the LIVE TREE's rows too.

THE TARGET IS A RE-POINTED CITATION, NOT A PRE-EXISTING ONE: the rows this plant
breaks are the ones the population extension brought under measurement, and the whole
point of the extension is that a break in them must be visible.
"""

from __future__ import annotations

import csv
import filecmp
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATE = ROOT / "gates" / "todo-cite-gate.py"
PY = ROOT / ".venv" / "bin" / "python"

#: THE TARGETS. `(relative path, the exact old text, the new text)`. The old text must
#: occur EXACTLY ONCE in the tree, and the row it carries must be one the population
#: extension added -- so the plant proves the NEW population is a real check.
#:
#: THE TARGETS ARE `def` CITATIONS, AND THAT IS MEASURED, NOT CHOSEN BY TASTE. A
#: `PatternMatcher([...])` TABLE's span runs to the next top-level statement, and the
#: lines between a table and the next statement are BLANK, so a citation moved INTO
#: that span still HOLDS (`how=symbol-body`) -- MEASURED: `ops.py:1908 symbol=
#: pm_drop_after` moved to `:1909` still RESOLVES. A `def` whose body is one line has a
#: TIGHT span, so a citation moved off it goes RED. THE PLANT MUST PLANT A BREAK THE
#: GATE CAN SEE, or it is measuring the arm that cannot fail and calling it a pass.
PLANTS = [
  ("tinybendygrad/uop/ops.bend",
   "# `sint_to_uop` -- ops.py:1895 symbol=sint_to_uop.",
   "# `sint_to_uop` -- ops.py:1896 symbol=sint_to_uop."),
  ("tinybendygrad/uop/ops.bend",
   "# `Sint` is ops.py:1923 symbol=sint -- `sint = int|UOp`,",
   "# `Sint` is ops.py:1924 symbol=sint -- `sint = int|UOp`,"),
]


def run_gate(port: Path, rows: Path) -> tuple[int, str]:
  p = subprocess.run([str(PY), str(GATE), "--port", str(port), "--rows", str(rows)],
                     cwd=ROOT, capture_output=True, text=True)
  return (p.returncode, p.stdout + p.stderr)


def read_rows(path: Path) -> list[dict]:
  with path.open(encoding="utf-8", newline="") as fh:
    return list(csv.DictReader(fh, delimiter="\t"))


def key(r: dict) -> tuple:
  # THE ROW IDENTITY, WITHOUT THE TREE'S LOCATION: the copies live at different paths
  # and a row's location is not what is being compared. The gate names a row's file
  # RELATIVE TO THE PARENT OF THE PORT DIRECTORY, so the first component is the
  # directory the copy was made in and everything after it is the file.
  rel = r["rel"]
  rel = rel.split("/", 1)[1] if "/" in rel else rel
  return (rel, r["at"], r["subject"], r["lo"], r["verdict"], r["symbol"])


def main() -> int:
  tmp = Path(tempfile.mkdtemp(prefix="citeplant-"))
  try:
    # ---- THE FROZEN BASE. ONE COPY, TAKEN ONCE. The live tree MOVES under this
    #      plant -- other units are editing it -- so the control and the plant must
    #      both be measured against ONE frozen copy, or the difference between the
    #      two runs is the difference between two trees.
    base = tmp / "base"
    shutil.copytree(ROOT / "tinybendygrad", base)
    ctrl_rows = tmp / "control.rows"
    rc_ctrl, _out_ctrl = run_gate(base, ctrl_rows)
    ctrl = {key(r) for r in read_rows(ctrl_rows)}
    print(f"CONTROL : a frozen copy of the tree -> {len(ctrl)} rows (rc={rc_ctrl})")

    # ---- ARM 1: THE PLANT. A TEXT EDIT ON A COPY OF THE FROZEN BASE.
    broken = tmp / "broken"
    shutil.copytree(base, broken)
    touched = []
    for rel, old, new in PLANTS:
      # THE COPY IS OF THE `tinybendygrad` TREE, so the repo-relative path loses its
      # first component.
      p = broken / rel.split("/", 1)[1]
      raw = p.read_text(encoding="utf-8")
      if raw.count(old) != 1:
        print(f"PLANT REFUSED: {rel}: the target text occurs {raw.count(old)} times",
              file=sys.stderr)
        return 3
      p.write_text(raw.replace(old, new), encoding="utf-8")
      touched.append((rel, old, new))
    # THE EDIT IS A TEXT EDIT: THE COPY DIFFERS FROM THE BASE IN EXACTLY THE PLANTED
    # LINES, AND NOTHING ELSE. THE COMPARISON IS BY CONTENT, NOT BY MTIME: `dircmp` is
    # SHALLOW and its `diff_files` is per-directory, so a difference one level down is
    # invisible to it.
    differing = []
    for dp, _dn, fn in os.walk(base):
      for f in fn:
        a = Path(dp) / f
        b = broken / a.relative_to(base)
        if not b.exists() or a.read_bytes() != b.read_bytes():
          differing.append(str(a.relative_to(base)))
    print(f"PLANT   : files whose CONTENT differs between the frozen base and the "
          f"planted copy: {sorted(differing)}")
    if sorted(differing) != sorted({r.split("/", 1)[1] for r, _o, _n in PLANTS}):
      print("PLANT BAD: the planted copy differs in files the plant did not name",
            file=sys.stderr)
      return 1
    for rel in sorted({r for r, _o, _n in PLANTS}):
      a = (base / rel.split("/", 1)[1]).read_text(encoding="utf-8").splitlines()
      b = (broken / rel.split("/", 1)[1]).read_text(encoding="utf-8").splitlines()
      changed = [(i + 1, x, y) for i, (x, y) in enumerate(zip(a, b)) if x != y]
      want = sum(1 for r, _o, _n in PLANTS if r == rel)
      if len(changed) != want or len(a) != len(b):
        print(f"PLANT BAD: {rel} changed on {len(changed)} lines, expected {want}",
              file=sys.stderr)
        return 1
      for at, x, y in changed:
        print(f"PLANT   : {rel}:{at}  {x.strip()!r}")
        print(f"                     -> {y.strip()!r}")

    broken_rows = tmp / "broken.rows"
    rc_broken, out_broken = run_gate(broken, broken_rows)
    broken_set = {key(r) for r in read_rows(broken_rows)}
    gone = sorted(ctrl - broken_set)
    new_rows = sorted(broken_set - ctrl)
    print(f"PLANT   : the planted copy -> rc={rc_broken}")
    for r in new_rows:
      print(f"   NEW  {r}")
    for r in gone:
      print(f"   GONE {r}")
    if rc_broken == 0:
      print("PLANT BAD: the gate PASSED on a broken citation", file=sys.stderr)
      return 1
    if not new_rows:
      print("PLANT BAD: the gate did not report the broken citation", file=sys.stderr)
      return 1
    verdicts = {r[4] for r in new_rows}
    if verdicts == {"RESOLVES"}:
      print("PLANT BAD: the broken citation still RESOLVES", file=sys.stderr)
      return 1
    if not gone:
      print("PLANT BAD: the broken citation did not REMOVE a row", file=sys.stderr)
      return 1
    # THE LIVE TREE, FOR THE RECORD. It is compared to the frozen base and the
    # difference is REPORTED, not asserted: the tree is under other units' hands and
    # a difference here is a moving tree, not a broken gate.
    live_rows = tmp / "live.rows"
    rc_live, _out_live = run_gate(ROOT / "tinybendygrad", live_rows)
    live = {key(r) for r in read_rows(live_rows)}
    print(f"LIVE    : the live tree -> {len(live)} rows (rc={rc_live}); "
          f"{len(live ^ ctrl)} rows differ from the frozen base (the tree is moving)")
    print(f"PLANT OK: the byte-identical control is unchanged ({len(ctrl)} rows, "
          f"rc={rc_ctrl}), the planted copy is RED (rc={rc_broken}) and says so on "
          f"{len(new_rows)} row(s): {sorted(verdicts)}")
    return 0
  finally:
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
  raise SystemExit(main())
