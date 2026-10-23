#!/usr/bin/env python3
"""plant.py -- A TEXT EDIT ON A COPY, AND A BYTE-IDENTICAL CONTROL.

    .venv/bin/python .agents/slop/citefix/plant.py --port tinybendygrad --rel FILE --at N

The plant takes a COPY of the port tree -- NEVER `git show HEAD:`, because a copy is the
tree and `git show` is a file -- and makes ONE TEXT EDIT that breaks ONE re-pointed
citation: the line moves by one, so the `symbol=` the citation names is no longer at the
line the citation names.

THE CONTROL IS A BYTE-IDENTICAL COPY of the same tree, and it must produce the SAME
verdict as the live tree. A plant whose control differs is measuring the difference
between two trees, not the gate.

THE GATE IS `gates/todo-cite-gate.py` -- the one that judges a `symbol=` row -- and it is
run with `--port` so it reads the COPY.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def run_gate(port: Path, rows: Path) -> tuple[int, list[str]]:
  p = subprocess.run([sys.executable, str(ROOT / "gates" / "todo-cite-gate.py"),
                      "--port", str(port), "--rows", str(rows), "--no-report"],
                     cwd=ROOT, capture_output=True, text=True)
  bad = [ln for ln in p.stdout.splitlines()
         if ln.startswith("  tinybendygrad/")]
  return p.returncode, bad


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--rel", required=True, help="the port file to break")
  ap.add_argument("--at", type=int, required=True, help="its line")
  ap.add_argument("--pattern", default=r"([\w./-]+\.py):(\d+)( symbol=([A-Za-z_][\w.]*))?")
  args = ap.parse_args()
  rel, at = args.rel, args.at
  # THE PATH INSIDE THE COPY: the copy's root IS the port tree.
  inner = rel[len("tinybendygrad/"):] if rel.startswith("tinybendygrad/") else rel
  src = (ROOT / rel).read_text(encoding="utf-8").splitlines()
  line = src[at - 1]
  m = re.search(args.pattern, line)
  if not m:
    print(f"PLANT REFUSED: {rel}:{at} carries no citation to break")
    return 3
  subj, lo, sym = m.group(1), m.group(2), m.group(3)
  new_line = (line[:m.start()] + f"{subj}:{int(lo) + 1}"
              + (f" symbol={sym}" if sym else "") + line[m.end():])

  with tempfile.TemporaryDirectory(prefix="citefix-plant-") as raw:
    td = Path(raw)
    control = td / "control"
    planted = td / "planted"
    for dest in (control, planted):
      shutil.copytree(ROOT / "tinybendygrad", dest / "tinybendygrad")
    # THE PLANT: ONE TEXT EDIT, ON A COPY.
    vp = planted / "tinybendygrad" / inner
    vl = vp.read_text(encoding="utf-8").splitlines()
    vl[at - 1] = new_line
    vp.write_text("\n".join(vl) + "\n", encoding="utf-8")
    # THE CONTROL IS A BYTE-IDENTICAL COPY OF THE PLANTED FILE'S NEIGHBOUR: the whole
    # control tree is a copy of the live tree, so it must agree with the live tree.
    ctl_rel = control / "tinybendygrad" / inner
    assert (control / "tinybendygrad" / inner).read_bytes() == (ROOT / rel).read_bytes()

    rc_ctl, bad_ctl = run_gate(control / "tinybendygrad", td / "ctl.rows")
    rc_pl, bad_pl = run_gate(planted / "tinybendygrad", td / "pl.rows")
    rc_live, bad_live = run_gate(ROOT / "tinybendygrad", td / "live.rows")

    print(f"PLANT    : {rel}:{at}  {subj}:{lo} -> {subj}:{int(lo) + 1}"
          + (f" symbol={sym}" if sym else ""))
    print(f"CONTROL  : a byte-identical copy -> rc={rc_ctl} "
          f"{'GREEN' if rc_ctl == 0 else 'RED'} ({len(bad_ctl)} bad row(s))")
    print(f"LIVE     : the live tree        -> rc={rc_live} "
          f"{'GREEN' if rc_live == 0 else 'RED'} ({len(bad_live)} bad row(s))")
    print(f"PLANTED  : the edited copy       -> rc={rc_pl} "
          f"{'GREEN' if rc_pl == 0 else 'RED'} ({len(bad_pl)} bad row(s))")
    for b in bad_pl:
      print(f"    {b.strip()}")
    ok = rc_ctl == 0 and rc_live == 0 and rc_pl != 0 and bool(bad_pl)
    print("PLANT OK" if ok else "PLANT FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
  raise SystemExit(main())
