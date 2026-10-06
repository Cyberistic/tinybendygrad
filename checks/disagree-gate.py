#!/usr/bin/env python3
"""THE DISAGREEMENTS, PINNED.  What each one is, where it starts, and whose fault.

`checks/differ.py` reports `graphs-disagree=<n>` and stops there.  This gate says which
ones, the FIRST row of each, the field, and the cause -- and it re-derives every claim
from disk on every run, so a claim that goes stale is a MOVED FILE rather than a
sentence a reader has to notice.  **`<n>` IS `len(PIN)` AND IS NEVER WRITTEN DOWN HERE**:
a second hand list of the same population is `checks/sweep.py`'s `LIVE_UNITS` fault, and
the two could be edited apart.

IT READS `runs/graphcmp/D/` AND NEVER WRITES IT.  The plant lane copies the directory
into a temporary tree first; the run under test is not the thing being mutated.

THREE LANES, because a lane that cannot fail is not a lane:

  pin        the six, by name; for each, the first disagreeing canonical line, the
             fields that differ, and the cause class.  Two independent methods read
             the first line and must agree (`.agents/slop/disagree/names.py`'s belt 1
             parses the differ's own `diff` record; belt 2 recomputes it from the two
             canonical files with difflib).
  citations  every source line this gate's diagnosis rests on is read and compared, so
             closing a defect makes THIS gate fail instead of quietly making the prose
             wrong.  A pin that tracks a moving file must be re-measured when the file
             moves, which is exactly when nobody is looking.
  plant      prove the reader can be moved: copy the tree, move ONE byte, and require
             the answer to move with it -- then require it to move BACK.  A plant that
             cannot move is a plant that passes; a check that agrees with itself proves
             only that the check agrees with itself.
  coverage   an op the py side reaches and the bend side does not is a SUBSTITUTION
             ARTEFACT, not a coverage gap, whenever the only graph reaching it is a
             substituted one.  That is eight ops today, and it is the one finding here a
             per-graph verdict cannot see: every one of those eight reports prints
             `ops-reached=n/n` and looks symmetrical, because the numerator and the
             denominator are the same graph.

Exit 0 iff every lane passes.  `--help` before you trust it.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[1]  # checks/disagree-gate.py -> repo root
D = ROOT / "runs" / "graphcmp" / "D"
NAMES = ROOT / ".agents" / "slop" / "disagree" / "names.py"

# --- THE SIX.  `row` is the first disagreeing canonical LINE; `fields` are the chunks
# that differ; `fault` is WHOSE it is; `shape` distinguishes the two bug classes.
#
# WRONG VALUE vs WRONG SHAPE is not a distinction without a definition.  Here:
#   WRONG VALUE  both sides built the same node and one field's VALUE differs.
#   WRONG SHAPE  the port's data model has no spelling for what upstream holds, so the
#                disagreeing chunk cannot agree at any value: the port emits a MARKER
#                (`q`), a DIFFERENT NUMBER OF FIELDS (CallInfo's 4th), or `?`.
#   NOT A ROW    the bend side was never asked the question: its canonical file is
#                byte-identical to another graph's.
PIN = {
  "allred": dict(row=6, fields=("arg",), shape="NOT A ROW", fault="HARNESS"),
  "cdiv":   dict(row=1, fields=("dtype", "arg"), shape="NOT A ROW", fault="HARNESS"),
  "late":   dict(row=6, fields=("dtype", "shape", "arg"), shape="NOT A ROW", fault="HARNESS"),
  "flip":   dict(row=6, fields=("arg",), shape="BOTH", fault="HARNESS+PORT"),
  # `lin` LEFT THIS TABLE. Its cause was that the port typed `applied_opts` as `List<&2, U32>`
  # where the pin has a three-field `Opt`; the port now defines `OPT{op, axis, arg}` in
  # `uop/ops.bend` and `graphcmp.bend` renders it. MEASURED on the live driver: row 46 goes
  # 45/46 -> 46/46 and the corpus fraction 311/336 -> 312/336 with no other graph moving.
  # `loop` LEFT THIS TABLE: the port's `callinfo` printed the dtype slot unconditionally
  # where the PIN's own `__repr__` suppresses it for void (`ops.py:1404`), so row 25 read
  # `cI(shcq_fence,b0,b0,Dvoid)` against `cI(shcq_fence,b0,b0)`.  MEASURED 25/25
  # byte-identical on the live driver, and the field itself is CORRECT (`ops.bend:1057`
  # against `ops.py:1398`), so the row was a SPELLING and not a shape.
}
# the bend side has no fixture for these three, and `rows.pick3`'s default is the
# matmul -- so all three got the matmul back and none of them was compared at all.
SUBSTITUTED = ("allred", "cdiv", "late", "matmul")

# Every claim above rests on a line.  Read it, or the pin is a rumour.
CITES = (
  # (path, line, must-contain, why this line is load-bearing)
  (".agents/slop/graphcmp.bend", 1336, "def rows.pick3",
   "the fixture dispatcher; its DEFAULT arm is what substituted the matmul"),
  (".agents/slop/graphcmp.py", 1393, "def g_allred", "the py fixture that has no bend twin"),
  (".agents/slop/graphcmp.py", 1412, "def g_cdiv", "ditto"),
  (".agents/slop/graphcmp.py", 1457, "def g_late", "ditto"),
  ("tinygrad/uop/ops.py", 559, "if len(srcs) == 1",
   "`UOp.group` of ONE src is the src, so `g_flip` builds NO GROUP node"),
  (".agents/slop/graphcmp.py", 1385, "UOp.group(a.flip(0).uop)",
   "a ONE-element group -- the whole of the bend-only GROUP#7"),
  (".agents/slop/graphcmp.bend", 764, "OpsGROUP",
   "the bend fixture builds that GROUP by hand, bypassing `UOp.group`"),
  ("tinybendygrad/uop/ops.bend", 1117, "dtype: S.Dt",
   "the port's CallInfo carries `dtype`, and SO DOES THE PIN -- `ops.py:1398`"),
  ("ad117c928^:tinygrad/uop/ops.py", 1398, "dtype: DType = dtypes.void",
   "the PIN's LAST CallInfo field IS `dtype`, so 'upstream has no dtype' is false"),
  ("ad117c928^:tinygrad/uop/ops.py", 1404, "self.dtype is not dtypes.void",
   "the PIN's `__repr__` SUPPRESSES the dtype slot for void -- the spelling `loop` broke"),
  ("tinygrad/uop/ops.py", 1405, "aux: Any = None",
   "THE WORKTREE says `aux` is last; the PIN says `dtype` is. Cite the PIN for upstream."),
  ("tinygrad/uop/ops.py", 132, "return src[0].dtype",
   "upstream reads the CALL dtype off the BODY, never off CallInfo"),
  ("tinybendygrad/uop/fold.bend", 1154, "CallInfo.dtype",
   "the port reads it off the field the PIN HAS -- a spelling, not a shape"),
  ("tinybendygrad/uop/ops.bend", 999, "applied_opts: List<&2, OPT>",
   "`lin`'s cause, and THE CAUSE IS FIXED: the port typed these `U32` and this is now `OPT` — "
   "the pin's own three-field `Opt` — which is why `lin` LEAVES `PIN`"),
)


def lane_pin(tree: Path) -> list[str]:
  fails = []
  r = subprocess.run([sys.executable, str(NAMES), "--json", "--tree", str(tree)],
                     capture_output=True, text=True)
  if r.returncode != 0:
    return [f"names.py rc={r.returncode}: {r.stdout.strip()} {r.stderr.strip()}"]
  import json
  got = json.loads(r.stdout)
  named = sorted(g["graph"] for g in got["disagree"])
  if named != sorted(PIN):
    fails.append(f"the disagreeing set moved: {named}, expected {sorted(PIN)}")
  for g in got["disagree"]:
    p = PIN.get(g["graph"])
    if p is None:
      continue
    if not g["belts_agree"]:
      fails.append(f"{g['graph']}: the two first-row methods disagree "
                   f"({g['first_row_from_cmp']} vs {g['first_row_recomputed']})")
    if g["first_row"] != p["row"]:
      fails.append(f"{g['graph']}: first disagreeing row moved "
                   f"{g['first_row_from_cmp']} -> {g['first_row']} (pin {p['row']})")
    if tuple(g["fields"]) != p["fields"]:
      fails.append(f"{g['graph']}: fields moved {g['fields']} (pin {list(p['fields'])})")
  if got["substituted"] != list(SUBSTITUTED):
    fails.append(f"the substituted-fixture cluster moved: {got['substituted']}")
  if got["wire_shape_defect"] is not None:
    fails.append(f"the canonical wire itself is malformed: {got['wire_shape_defect']}")
  summary = (tree / "D0-run-summary.txt").read_text().splitlines()
  # DERIVED, not written down.  This used to read `graphs-disagree=6`, which made the
  # denominator a second hand list of the same population `PIN` already declares -- and
  # the two could be edited apart, which is exactly `checks/sweep.py`'s `LIVE_UNITS` fault.
  # It still FAILS when the count moves: `differ.py`'s summary is the only witness that ran.
  if f"graphs-disagree={len(PIN)}" not in summary:
    fails.append(f"D0-run-summary.txt no longer reads graphs-disagree={len(PIN)}")
  return fails


def cited(line: str, needle: str) -> bool:
  """The needle must appear and must NOT be followed by an identifier character.
  Plain `needle in line` is not a pin: it lets a SUPERSET through, so renaming
  `dtype: S.Dt` to `dtype: S.DtX` -- which breaks the very field this gate blames --
  would pass.  That is the `abi4_gate.py` trap in miniature: the citation still
  resolved, so nothing moved, and the sentence the citation backs went stale."""
  return re.search(re.escape(needle) + r"(?![\w])", line) is not None


def source(rel: str) -> str | None:
  """A `rev:path` row names a BLOB, not a file.  It has to: `ad117c928` re-vendored 16
  `tinygrad/` files, so `tinygrad/uop/ops.py` in the worktree puts `dtype` at :1397 and
  `aux` last at :1405, while the PIN the whole port cites has `aux` at :1397 and `dtype`
  LAST at :1398.  A row that says "upstream has no `dtype`" can only be false, and it
  was false, because it read the worktree.  Reading a blob is how a citation about
  upstream survives the next re-vendor."""
  if ":" not in rel:
    p = ROOT / rel
    return p.read_text() if p.exists() else None
  rev, path = rel.split(":", 1)
  r = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=ROOT,
                     capture_output=True, text=True)
  return r.stdout if r.returncode == 0 else None


def lane_citations() -> list[str]:
  fails = []
  for rel, n, needle, why in CITES:
    text = source(rel)
    if text is None:
      fails.append(f"{rel}:{n} -- gone; {why}")
      continue
    lines = text.splitlines()
    if not (1 <= n <= len(lines)):
      fails.append(f"{rel}:{n} -- past end of file ({len(lines)} lines); {why}")
    elif not cited(lines[n - 1], needle):
      fails.append(f"{rel}:{n} -- reads {lines[n-1].strip()!r}, expected {needle!r}; {why}")
  # The NEGATIVE claim is the load-bearing one and no line can carry it: `rows.pick3`
  # must have NO arm for the three substituted names, or they were compared after all.
  pick3 = (ROOT / ".agents/slop/graphcmp.bend").read_text()
  body = pick3[pick3.index("def rows.pick3"):]
  body = body[:body.index("def rows.pick(")]
  for g in ("allred", "cdiv", "late"):
    if f'"{g}"' in body:
      fails.append(f"rows.pick3 now HAS an arm for {g!r}, so it is no longer "
                   f"substituted; the NOT-A-ROW diagnosis and its pin are both stale")
  return fails


def lane_plant(tree: Path) -> list[str]:
  """Move one byte and require the answer to move with it, then move it back.  Two
  separate plants, one per belt, because a belt that reads nothing and a belt that
  reads the other belt both pass a self-consistent check."""
  import json

  def answer(d: Path) -> tuple[object, ...]:
    r = subprocess.run([sys.executable, str(NAMES), "--json", "--tree", str(d)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    j = json.loads(r.stdout)
    lin = next(g for g in j["disagree"] if g["graph"] == "lin")
    return lin["first_row_from_cmp"], lin["first_row_recomputed"], lin["fields"]

  fails = []
  before = answer(tree)
  with tempfile.TemporaryDirectory() as td:
    work = Path(td) / "D"
    shutil.copytree(tree, work)

    # PLANT A: make the bend canon agree with the py canon on `lin`'s last row.  Belt 2
    # recomputes from the canonical files, so it MUST move from 46 to nothing.  Belt 1
    # reads the differ's own diff record, which this plant deliberately does NOT touch,
    # so it MUST stay.  The two halves moving in OPPOSITE directions is the proof that
    # they read different bytes -- which is the whole point of having two.
    py = (work / "D2-canon-py-lin.txt").read_text().splitlines()
    bend = (work / "D2-canon-bend-lin.txt").read_text().splitlines()
    bend[-1] = py[-1]
    (work / "D2-canon-bend-lin.txt").write_text("\n".join(bend) + "\n")
    a = answer(work)
    if a[1] is not None:
      fails.append(f"PLANT A did not move belt 2 (still {a[1]}): the recomputed "
                   f"first-row method is not reading the canonical files")
    if a[0] != before[0]:
      fails.append(f"PLANT A moved belt 1 too (now {a[0]}, was {before[0]}): it reads "
                   f"the diff record this plant did not touch, so it is reading "
                   f"something shared with belt 2")

    # DISARM A: put the byte back and require the pinned answer to return exactly.
    (work / "D2-canon-bend-lin.txt").write_text("\n".join(
      (tree / "D2-canon-bend-lin.txt").read_text().splitlines()) + "\n")
    if answer(work) != before:
      fails.append(f"DISARM A did not restore the answer: {answer(work)} != {before}")

    # PLANT B: rewrite the differ's own diff record and require belt 1 to move.
    # The canonical files are back to their real contents, so belt 2 MUST NOT move.
    (work / "D2-cmp-lin.txt").write_text("lin BYTE-IDENTICAL (9999 bytes both sides)\n")
    b = answer(work)
    if b[0] is not None:
      fails.append(f"PLANT B did not move belt 1 (still {b[0]}): it is not reading "
                   f"the differ's diff record")
    if b[1] != before[1]:
      fails.append(f"PLANT B moved belt 2 as well (now {b[1]}): the two belts share a "
                   f"source, so this is one check wearing two hats")

  if answer(tree) != before:
    fails.append("the plant lane mutated the tree it was reading")
  return fails


# THE EIGHT OPS REACHED BY PY AND BY NOTHING ELSE, each on exactly one graph, and all
# three of those graphs substituted.  This is the finding a per-graph verdict cannot
# see: `D1-graph-late.txt` prints `ops-reached=9/9` and is symmetrical against itself,
# because py's `late` and bend's `matmul` are two different graphs and only the py one
# has the arithmetic in it.
SUBSTITUTION_ARTEFACTS = {
  "ALLREDUCE": "allred", "COPY": "allred",
  "CDIV": "cdiv", "CMOD": "cdiv",
  "FDIV": "late", "CMPEQ": "late", "NEG": "late", "SUB": "late",
}
PER_OP = re.compile(r"([A-Z_]+) (\d+)/(\d+)")


def lane_coverage(tree: Path) -> list[str]:
  """Re-derive the per-op node counts from every `D1-graph-*.txt` and name every op the
  py side reaches and the bend side does not.  A graph is substituted iff its bend
  canonical file is byte-identical to another graph's, so this lane also refuses to let
  a REAL one-sided op hide behind a fixture that has since been written."""
  py, bend, where = {}, {}, {}
  for p in sorted(tree.glob("D1-graph-*.txt")):
    g = p.name.removeprefix("D1-graph-").removesuffix(".txt")
    for line in p.read_text().splitlines():
      # The OPS REACHED line is the only one shaped `#   NAME n/m  NAME n/m ...`; the
      # LEDGER rows below it start `#   z   arg  py=0 ...` and carry `=`, never `/`.
      if not line.startswith("#   ") or "/" not in line or "=" in line:
        continue
      for op, a, b in PER_OP.findall(line):
        py[op] = py.get(op, 0) + int(a)
        bend[op] = bend.get(op, 0) + int(b)
        if int(a):
          where.setdefault(op, set()).add(g)

  fails = []
  # The SET of one-sided ops is pinned; the node COUNT is a fact about the run, so it is
  # reported when it is not 1 rather than pinned -- a fixture that grew an op into two
  # nodes is a corpus change, and this lane's claim ("only the substituted graphs reach
  # these") survives it, while the count does not.
  one_sided = {o: py[o] for o in py if py[o] and not bend.get(o)}
  if set(one_sided) != set(SUBSTITUTION_ARTEFACTS):
    fails.append(f"the py-only op SET moved: {sorted(one_sided)}, "
                 f"expected {sorted(SUBSTITUTION_ARTEFACTS)}")
  for op, n in one_sided.items():
    if n != 1 and op in SUBSTITUTION_ARTEFACTS:
      fails.append(f"{op}: py-only node count moved {1} -> {n}")
  for op, g in SUBSTITUTION_ARTEFACTS.items():
    if where.get(op) != {g}:
      fails.append(f"{op}: reached only by {sorted(where.get(op, ()))}, expected only {g!r}; "
                   f"the substitution diagnosis is stale")
  return fails


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
  ap.add_argument("--tree", type=Path, default=D,
                  help="the graphcmp run directory to read (default: runs/graphcmp/D)")
  ap.add_argument("--lane", choices=("pin", "citations", "plant", "coverage", "all"),
                  default="all")
  a = ap.parse_args()
  tree = a.tree if a.tree.is_absolute() else ROOT / a.tree

  if not tree.is_dir():
    print(f"FATAL: no run at {tree}.  `python checks/differ.py run` writes one.", file=sys.stderr)
    return 2
  if not NAMES.exists():
    print(f"FATAL: {NAMES} is missing; the pin has no reader.", file=sys.stderr)
    return 2

  lanes = {"pin": ("PIN", lambda: lane_pin(tree)),
           "citations": ("CITATIONS", lane_citations),
           "coverage": ("COVERAGE ARTEFACTS", lambda: lane_coverage(tree)),
           "plant": ("PLANT + DISARM", lambda: lane_plant(tree))}
  bad = 0
  for key in (lanes if a.lane == "all" else (a.lane,)):
    title, fn = lanes[key]
    fails = fn()
    print(f"{'FAIL' if fails else 'ok  '}  {title}")
    for f in fails:
      print(f"        {f}")
    bad += len(fails)

  if a.lane == "all":
    print()
    print(f"{len(PIN)} disagreements pinned, {bad} failure(s).")
    for g in sorted(PIN):
      p = PIN[g]
      print(f"  {g:7s} row {p['row']:>2}  fields {','.join(p['fields']):<17} "
            f"{p['shape']:<11} {p['fault']}")
  return 1 if bad else 0


if __name__ == "__main__":
  raise SystemExit(main())
