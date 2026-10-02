#!/usr/bin/env python3
"""dsp2-gate.py -- the disagreement gate for runtime/ops_dsp.bend.

    .venv/bin/python .agents/slop/dsp_oracle2.py rows > .agents/slop/dsp_py.txt
    ./bin/bend tinybendygrad/runtime/ops_dsp.bend > .agents/slop/dsp_i.txt
    .venv/bin/python .agents/slop/dsp2-gate.py .agents/slop/dsp_py.txt .agents/slop/dsp_i.txt

COMPARES WHOLE `name = [port]   py=[cpython]` ROWS, never row names: a name-comparing
harness reported 0 disagreements over 30 mutations in one unit and 68 in another.

THE EXIT PATH IS CHECKED. A 0-row lane file is indistinguishable from "not started"
(bend 2.0.34 overflows the machine stack on ~1 run in 20 and prints ZERO rows with
exit 0), so this script exits non-zero on a short lane rather than reporting a clean
file. Refuse, do not measure.

Exit 0 means the lane and the CPython reference are byte-identical. Exit 1 means there
are disagreements, and they are listed with BOTH values.
"""
import difflib
import re
import sys

ROW = re.compile(r"^(dsp[\w-]*) = ")


def main():
  ref = open(sys.argv[1]).read()
  lane = open(sys.argv[2]).read()
  # A ROW BEGINS at a line naming a row. `dsp_link_script`'s VALUE holds real newlines
  # and the very next line is another section, so splitting on `   py=[` shreds it --
  # measured: that split yields 513 chunks and then trips over `.rela.plt : ALIGN`.
  # The row NAME is the only unambiguous start, and there is exactly one of them per row.
  ref_rows = re.split(r"(?m)^(?=dsp[\w-]* = )", ref)
  lane_rows = re.split(r"(?m)^(?=dsp[\w-]* = )", lane)
  ref_rows = [r for r in ref_rows if r.strip()]
  lane_rows = [r for r in lane_rows if r.strip()]
  print(f"CPython reference rows: {len(ref_rows)}")
  print(f"port lane rows:         {len(lane_rows)}")
  if len(lane_rows) < len(ref_rows):
    print(f"\nLANE DID NOT RUN: {len(lane_rows)} rows against {len(ref_rows)}. bend "
          f"2.0.34 overflows the machine stack on ~1 run in 20 and prints ZERO rows "
          f"with exit 0. RE-RUN before concluding anything.")
    return 2
  rn, ln_ = [ROW.match(r).group(1) for r in ref_rows], [ROW.match(r).group(1) for r in lane_rows]
  if rn != ln_:
    print("\nROW NAME/ORDER DIFFERS (first 5):")
    for a, b in list(zip(rn, ln_))[:5]:
      print(f"  ref={a} lane={b}")
    return 2
  # The ROW LISTS, not the files: diffing whole text offsets the two by the number of
  # extra lines inside `dsp_link_script` and reports the block as one giant change.
  sm = difflib.SequenceMatcher(None, ref_rows, lane_rows, autojunk=False)
  bad = []
  for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag == "equal":
      continue
    for r in ref_rows[i1:i2]:
      m = ROW.match(r)
      assert m, f"chunk does not start with a row name: {r[:60]!r}"
      if m.group(1) not in bad:
        bad.append(m.group(1))
  print(f"\nDISAGREEING ROWS: {len(bad)}")
  for n in bad:
    a = next(r for r in ref_rows if ROW.match(r).group(1) == n)
    b = next(r for r in lane_rows if ROW.match(r).group(1) == n)
    print(f"  {n}")
    print(f"    cpython: {a!r}")
    print(f"    port:    {b!r}")
  print(f"\nlanes byte-identical: {ref == lane}")
  return 0 if not bad else 1


if __name__ == "__main__":
  raise SystemExit(main())