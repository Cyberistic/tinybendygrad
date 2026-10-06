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

FOUR LANES, because a lane that cannot fail is not a lane:

  pin        the disagreements, by name; for each, the first disagreeing canonical line,
             the fields that differ, and the cause class.  Two independent methods read
             the first line and must agree (`.agents/slop/disagree/names.py`'s belt 1
             parses the differ's own `diff` record; belt 2 recomputes it from the two
             canonical files with difflib).
  citations  every source line this gate's diagnosis rests on is read and compared, so
             closing a defect makes THIS gate fail instead of quietly making the prose
             wrong.  A pin that tracks a moving file must be re-measured when the file
             moves, which is exactly when nobody is looking.  The ARMED dispatcher is
             asserted here POSITIVELY (`arms_wired`): a name with no arm falls through to
             `g_matmul()` and is never compared, and a negative claim cannot catch that.
  plant      prove the reader can be moved: copy the tree, move ONE byte, and require
             the answer to move with it -- then require it to move BACK.  A plant that
             cannot move is a plant that passes; a check that agrees with itself proves
             only that the check agrees with itself.
  coverage   an op the py side reaches and the bend side does not means one side was never
             asked the question -- a SUBSTITUTION, AGENTS.md's `SKIP`.  The population is
             EMPTY today (allred/cdiv/late now have arms), which is the one finding here a
             per-graph verdict cannot see: each substituted report prints `ops-reached=n/n`
             and looks symmetrical, because the numerator and the denominator are the same
             graph.

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
GRAPH_BEND = ROOT / ".agents" / "slop" / "graphcmp.bend"
# The three graphs the bend dispatcher had no arm for.  They were SUBSTITUTED by
# `rows.pick3`'s `g_matmul()` fallback; the arms landed 2026-10-06, so the pair is now
# asserted POSITIVELY (see `arms_wired`) instead of by the negative claim that went stale.
ARMED = ("allred", "cdiv", "late")

# --- THE DISAGREEMENTS.  `row` is the first disagreeing canonical LINE; `fields` are the
# chunks that differ; `fault` is WHOSE it is; `shape` distinguishes the two bug classes.
#
# WRONG VALUE vs WRONG SHAPE is not a distinction without a definition.  Here:
#   WRONG VALUE  both sides built the same node and one field's VALUE differs.
#   WRONG SHAPE  the port's data model has no spelling for what upstream holds, so the
#                disagreeing chunk cannot agree at any value: the port emits a MARKER
#                (`q`), a DIFFERENT NUMBER OF FIELDS (CallInfo's 4th), or `?`.
#   NOT A ROW    the bend side was never asked the question: its canonical file is
#                byte-identical to another graph's.
PIN = {
  # *** PREDICTION, NOT A MEASUREMENT (2026-10-06). *** `allred` was SUBSTITUTED by the
  # `g_matmul()` fallback and its old row 6 was matmul's CONST, not `allred`'s.  It now has
  # an arm, so the bend side IS asked -- but no `bend` run has rewritten
  # `runs/graphcmp/D/` for it.  `threegraphs` (§4) predicts the first disagreement is row 8,
  # the COPY row, on the device tuple's NORMAL FORM (`n(sCPU,sCPU)` vs `ssCPU,sCPU`, two
  # renderer spellings of one value, both sides the differ's own text).  Row 8, `arg`,
  # `WRONG VALUE` are UNCONFIRMED until a fresh run exists: **A PIN TAKEN FROM A PREDICTION
  # IS A PIN THAT CANNOT FAIL, so this note is IN THE TABLE, where a reader of the pin
  # lands, and not in a commit message.**
  # *** `allred` LEFT THIS TABLE (2026-10-06), AND IT LEFT BECAUSE THE RUN FALSIFIED IT. *** It was
  # pinned from a PREDICTION -- the COPY row on the device tuple's normal form -- and `adevfix`
  # fixed the normal form, so the CLEAN RE-RUN reads `VERDICT: AGREE` with `D2-cmp-allred.txt`
  # BYTE-IDENTICAL. **A PIN TAKEN FROM A PREDICTION IS A PIN THAT CANNOT FAIL, which is why the
  # prediction lived here where a reader of the pin lands -- and why its REFUTATION belongs here too.**
  "flip":   dict(row=6, fields=("arg",), shape="BOTH", fault="HARNESS+PORT"),
  # `unshard` JOINED THIS TABLE FROM THE CLEAN RE-RUN: row 8, `dtype`/`shape` read `?` where py has
  # `f32` and `(l0:8,l0:3)`. It was NEVER ASKED before (`armfour` armed it, `foldgap` measured it),
  # and `foldgap` REFUSED the fix on purpose: the fold needs `int(r.vmax+1)` and `dt_shape` gets no
  # `BTable`, so claiming a shape would be a LIE and the node stays an honest `?`. **A MEASURED
  # REFUSAL IS NOT AN UNFIXED DEFECT, AND THIS ROW IS THE DIFFERENCE.**
  "unshard": dict(row=8, fields=("dtype", "shape"), shape="WRONG SHAPE", fault="PORT"),
  # `cdiv` and `late` LEFT THIS TABLE (2026-10-06): they were NOT-A-ROW, i.e. never asked,
  # and once armed their atoms matched field for field (`threegraphs` §4, predicted AGREE).
  # They are not pinned-and-agreeing; they left, which is why `len(PIN)` is what
  # `graphs-disagree` reads (see `lane_pin`).
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
# NO HAND LIST HERE.  `names.py` DERIVES the substituted set from `graphcmp.py`'s `GRAPHS`
# against `rows.pick3`'s own arms: a name with no arm falls through to the dispatcher's
# single fallback builder, so the two sides build DIFFERENT graphs and the disagreement is
# the dispatcher, not the port -- a `SKIP`.  A hand list here could only name what it
# already knew, which is the fault this gate exists to catch, so the set is CONSUMED from
# its generator (the `names.py` JSON this file already loads by path) and must be EMPTY: a
# non-empty one is a fresh substitution.

# Every claim above rests on a line.  Read it, or the pin is a rumour.
CITES = (
  # (path, line, must-contain, why this line is load-bearing)
  (".agents/slop/graphcmp.bend", 1571, "def rows.pick3",
   "the fixture dispatcher; its DEFAULT arm is what substituted the matmul"),
  (".agents/slop/graphcmp.py", 1394, "def g_allred", "the py fixture that has no bend twin"),
  (".agents/slop/graphcmp.py", 1413, "def g_cdiv", "ditto"),
  (".agents/slop/graphcmp.py", 1458, "def g_late", "ditto"),
  ("tinygrad/uop/ops.py", 559, "if len(srcs) == 1",
   "`UOp.group` of ONE src is the src, so `g_flip` builds NO GROUP node"),
  (".agents/slop/graphcmp.py", 1386, "UOp.group(a.flip(0).uop)",
   "a ONE-element group -- the whole of the bend-only GROUP#7"),
  (".agents/slop/graphcmp.bend", 777, "OpsGROUP",
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
  if got["substituted"]:
    fails.append(f"names with no arm in rows.pick3, falling through its fallback: "
                 f"{got['substituted']}")
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
  # THE POSITIVE CLAIM.  This used to assert the OPPOSITE -- that `rows.pick3` had NO arm
  # for allred/cdiv/late -- and it went RED the moment the arms landed: a gate failing
  # because the defect it recorded was FIXED.  A negative claim about a dispatch table rots
  # in one direction, and only in the direction that hurts.  The positive claim below goes
  # red when an arm is REMOVED -- the state that silently lies, because a missing arm is not
  # a refusal: the name falls through to `g_matmul()` (a REAL graph) and the differ then
  # compares two different graphs and reports a disagreement that is the dispatcher
  # (AGENTS.md: a `SKIP` is not a pass).
  fails += arms_wired(GRAPH_BEND.read_text())
  return fails


def arms_wired(text: str) -> list[str]:
  """Each ARMED graph must route to a builder of its OWN, defined exactly once.  This is a
  pure function of the dispatcher's text so the plant lane can run it against a scratch
  copy with one arm broken -- a claim nothing can move is not a claim."""
  fails = []
  for g in ARMED:
    if f'String.eq(name, "{g}"), g_{g}()' not in text:
      fails.append(f"rows.pick3 no longer routes {g!r} to g_{g}(); an unarmed name falls "
                   f"through to the g_matmul() fallback and is never compared")
    if text.count(f"def g_{g}()") != 1:
      fails.append(f"g_{g} is defined {text.count(f'def g_{g}()')} times, expected once")
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
    # WHICHEVER GRAPH DISAGREES FIRST. `lin` WAS HARD-CODED HERE, AND WHEN IT STARTED
    # AGREEING `next(...)` RAISED `StopIteration` AND TOOK THE WHOLE PLANT LANE DOWN --
    # a plant that names one graph is a plant that breaks when the tree gets better.
    if not j["disagree"]:
      raise SystemExit("the plant needs one disagreement to move; this run has none")
    g = sorted(j["disagree"], key=lambda x: x["graph"])[0]
    return g["graph"], g["first_row_from_cmp"], g["first_row_recomputed"], g["fields"]

  fails = []
  before = answer(tree)
  graph = before[0]
  with tempfile.TemporaryDirectory() as td:
    work = Path(td) / "D"
    shutil.copytree(tree, work)

    # PLANT A: make the bend canon agree with the py canon on `lin`'s last row.  Belt 2
    # recomputes from the canonical files, so it MUST move from 46 to nothing.  Belt 1
    # reads the differ's own diff record, which this plant deliberately does NOT touch,
    # so it MUST stay.  The two halves moving in OPPOSITE directions is the proof that
    # they read different bytes -- which is the whole point of having two.
    # PLANT A: make the bend canon agree with the py canon ON THE DISAGREEING ROW.  Belt 2
    # recomputes from the canonical files, so its row MUST move.  Belt 1 reads the differ's
    # own diff record, which this plant deliberately does NOT touch, so it MUST stay.  The
    # two halves moving in OPPOSITE directions is the proof that they read different bytes.
    #
    # **`recomputed` IS THE ROW INDEX, NOT AN ENDPOINT.** THIS PLANT USED TO EDIT `bend[-1]`,
    # WHICH ONLY WORKED BECAUSE `lin`'s DISAGREEMENT WAS ITS **LAST** ROW (46 of 46). The
    # subject is chosen from whatever disagrees, so the edit has to follow the index it
    # reports -- otherwise the plant quietly depends on the last row being the broken one.
    row = before[2]
    canon_py = work / f"D2-canon-py-{graph}.txt"
    canon_bend = work / f"D2-canon-bend-{graph}.txt"
    py = canon_py.read_text().splitlines()
    bend = canon_bend.read_text().splitlines()
    if not (isinstance(row, int) and 1 <= row <= len(bend) and row <= len(py)):
      raise SystemExit(f"the plant needs an integer row in range; {graph} reports {row!r}")
    bend[row - 1] = py[row - 1]
    canon_bend.write_text("\n".join(bend) + "\n")
    a = answer(work)
    if a[2] == before[2]:
      fails.append(f"PLANT A did not move belt 2 (still {a[2]}): the recomputed "
                   f"first-row method is not reading the canonical files")
    if a[1] != before[1]:
      fails.append(f"PLANT A moved belt 1 too (now {a[1]}, was {before[1]}): it reads "
                   f"the diff record this plant did not touch, so it is reading "
                   f"something shared with belt 2")

    # DISARM A: put the byte back and require the pinned answer to return exactly.
    canon_bend.write_text("\n".join(
      (tree / f"D2-canon-bend-{graph}.txt").read_text().splitlines()) + "\n")
    if answer(work) != before:
      fails.append(f"DISARM A did not restore the answer: {answer(work)} != {before}")

    # PLANT B: rewrite the differ's own diff record and require belt 1 to move.
    # The canonical files are back to their real contents, so belt 2 MUST NOT move.
    (work / f"D2-cmp-{graph}.txt").write_text(f"{graph} BYTE-IDENTICAL (9999 bytes both sides)\n")
    b = answer(work)
    if b[1] == before[1]:
      fails.append(f"PLANT B did not move belt 1 (still {b[1]}): it is not reading "
                   f"the differ's diff record")
    if b[2] != before[2]:
      fails.append(f"PLANT B moved belt 2 as well (now {b[2]}): the two belts share a "
                   f"source, so this is one check wearing two hats")

  if answer(tree) != before:
    fails.append("the plant lane mutated the tree it was reading")
  return fails


# OPS REACHED BY PY AND BY NOTHING ELSE, each named to the graph that reaches it.  It is
# EMPTY, and empty is the finding: the eight that were here (`ALLREDUCE COPY CDIV CMOD
# FDIV CMPEQ NEG SUB`) were one-sided only because allred/cdiv/late fell through to
# `g_matmul()` -- py built the real graph and bend a different one, so every one of those
# three reports printed `ops-reached=n/n` and looked symmetrical, because the numerator and
# the denominator were the same graph.  With the arms landed both sides reach all eight, so
# a NON-EMPTY set is either a fresh substitution or a REAL one-sided op; the lane must not
# be quiet about either, which is why the SET is pinned and the count is not.
SUBSTITUTION_ARTEFACTS: dict[str, str] = {}
PER_OP = re.compile(r"([A-Z_]+) (\d+)/(\d+)")


def lane_coverage(tree: Path) -> list[str]:
  """Re-derive the per-op node counts from every `D1-graph-*.txt` and name every op the
  py side reaches and the bend side does not.  A one-sided op means one side was never
  asked the question -- a fixture substitution, which is AGENTS.md's `SKIP` -- and no
  per-graph verdict can see it."""
  py, bend = {}, {}
  for p in sorted(tree.glob("D1-graph-*.txt")):
    for line in p.read_text().splitlines():
      # The OPS REACHED line is the only one shaped `#   NAME n/m  NAME n/m ...`; the
      # LEDGER rows below it start `#   z   arg  py=0 ...` and carry `=`, never `/`.
      if not line.startswith("#   ") or "/" not in line or "=" in line:
        continue
      for op, a, b in PER_OP.findall(line):
        py[op] = py.get(op, 0) + int(a)
        bend[op] = bend.get(op, 0) + int(b)

  # The SET is the whole assertion.  It is empty today because the arms landed, and the
  # comparison is against a SET, so it goes red the moment a py-only op appears -- no
  # per-op count loop and no per-op graph loop are needed to say that.
  fails = []
  one_sided = {o: py[o] for o in py if py[o] and not bend.get(o)}
  if set(one_sided) != set(SUBSTITUTION_ARTEFACTS):
    fails.append(f"the py-only op SET moved: {sorted(one_sided)}, "
                 f"expected {sorted(SUBSTITUTION_ARTEFACTS)}")
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
