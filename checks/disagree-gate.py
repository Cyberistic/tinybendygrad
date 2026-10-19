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
import ast
import importlib.util
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
  # `cdiv` and `late` LEFT THIS TABLE (2026-10-06): they were NOT-A-ROW, i.e. never asked,
  # and once armed their atoms matched field for field (`threegraphs` §4, predicted AGREE).
  # They are not pinned-and-agreeing; they left, which is why `len(PIN)` is what
  # `graphs-disagree` reads (see `lane_pin`).
  # `lin` LEFT THIS TABLE. Its cause was that the port typed `applied_opts` as `List<&2, U32>`
  # where the pin has a three-field `Opt`; the port now defines `OPT{op, axis, arg}` in
  # `uop/ops.bend` and `graphcmp.bend` renders it. MEASURED on the live driver: row 46 goes
  # 45/46 -> 46/46 and the corpus fraction 311/336 -> 312/336 with no other graph moving.
  # `loop` LEFT THIS TABLE ON 2026-10-06: the port's `callinfo` printed the dtype slot
  # unconditionally where the PIN's own `__repr__` suppresses it for void (`ops.py:1404`), so
  # row 25 read `cI(shcq_fence,b0,b0,Dvoid)` against `cI(shcq_fence,b0,b0)`.  MEASURED 25/25
  # byte-identical on the live driver, and the field itself is CORRECT (`ops.bend:1057`
  # against `ops.py:1398`), so the row was a SPELLING and not a shape.
}
# *** THE TABLE IS EMPTY AND AN EMPTY TABLE IS A CLAIM, NOT A VACUITY. ***
#
# `flip` AND `unshard` LEFT ON 2026-10-18, and this is the FOURTH time this instrument has
# had to do that (`allred`, `cdiv`, `late`, `lin`, `loop` before them).  MEASURED 2026-10-18
# 20:13Z, on the coherent run whose `substrate-start` EQUALS its `substrate-end` at
# `c74f32ca629d` (a run whose two substrate rows differ is a MIXTURE and names nothing):
# `.agents/slop/disagree/names.py --json` answers `disagree: []`, `substituted: []`,
# `wire_shape_defect: null`, and `D0-run-summary.txt` reads `graphs-disagree=0`.  So the pin
# on `['flip','unshard']` was recording "**THESE TWO GRAPHS DISAGREE**", that sentence is
# FALSE, and **A PIN ON AN EMPTY SET IS A CLAIM THAT NOTHING DISAGREES.**
#
# **WHY DELETION AND NOT A "MUST KEEP AGREEING" PIN.** `len(PIN)` IS the `graphs-disagree`
# denominator -- this dict has four columns (`row`, `fields`, `shape`, `fault`) and NOT ONE of
# them can spell "agrees", so a graph that agrees is not representable in this table and a
# regression row added here would break the arithmetic `lane_pin` derives.  The claim is not
# LOST by the deletion: `lane_pin` asserts the generator's OWN `graphs-disagree=0` row
# directly, and MEASURED 2026-10-18 20:13Z `differ.PINS` has **NO `graphs-disagree` key** --
# so that row is asserted HERE and NOWHERE ELSE.  `PINS["graphs-agree"]="34"` over
# `PINS["graphs"]="34"` implies it only ARITHMETICALLY, and only while nothing is REFUSED,
# which is a weaker claim and is not what this lane checks.
#
# **AND THE LANE KEEPS FOUR TEETH WITH AN EMPTY TABLE**, so this is not a gate turned off:
# any disagreement reds it (`named != sorted(PIN)`), any dispatcher substitution reds it, a
# malformed wire reds it, and a summary that stops reading `graphs-disagree=0` reds it.
#
# **`loop` IS DELIBERATELY NOT PINNED, AND IT IS NOT PINNED-AND-AGREEING.**  It AGREES, and
# `lane_pin` below already asserts that twice -- `names.py`'s `disagree: []` and
# `D0-run-summary.txt`'s `graphs-disagree=0` -- so nothing in this paragraph is load-bearing.
# MEASURED 2026-10-19 03:37Z, `cat runs/graphcmp/D/D1-graph-loop.txt`, on the coherent run
# (`substrate-start` EQUALS `substrate-end` at `65d64bb74`): `settled=True`, `?=0/0` on both
# columns, `VERDICT: AGREE`, and `D2-cmp-loop.txt` reads `CANONICAL BYTE-IDENTICAL`.  It ONCE
# read `rc=2` with NO `VERDICT:` line, which was TRUE when written, and ALL FOUR of the line
# numbers this paragraph used to carry were WRONG.  The cause was `dt_of` (`fold.bend:713`),
# reached by the AFTER passthrough `thru0` (`fold.bend:905`, whose body is `fold.bend:906`,
# dispatched from `fold.bend:2580`): its `None` arm answered the PORT-ONLY OUTER `None` --
# the `?` marker CPython cannot print -- where upstream reads `self.src[0]._shape` on the
# AFTER passthrough (`ops.py:377`) off a bare `NOOP`, whose own arm is `ops.py:338`.
# `f251d80d` gave that `None` arm (`fold.bend:716`) the `(dt, None)` pair that `nil_ds.shape`
# (`fold.bend:1133`) already spelled beside `late()` (`fold.bend:1114`), so both `?=0` rows
# are regression rows.  **NO `TODO` STANDS HERE: THE OLD ONE NAMED LINE NUMBERS `f251d80d`
# HAD ALREADY FIXED, AND A TODO THAT ASKS FOR A STATE THE TREE CORRECTLY REFUSES TO REACH IS
# A CLAIM THAT CANNOT FAIL.**  WHEN A FIX MAKES A GRAPH DISAGREE, PIN IT FROM THE RUN, NOT
# FROM THIS NOTE.  The `PLANT+DISARM` lane's `[REFUSED]` on a green corpus is that lane's own
# subject being absent, and it explains itself at `lane_plant`; it is not this paragraph's.
# NO HAND LIST HERE.  `names.py` DERIVES the substituted set from `graphcmp.py`'s `GRAPHS`
# against `rows.pick3`'s own arms: a name with no arm falls through to the dispatcher's
# single fallback builder, so the two sides build DIFFERENT graphs and the disagreement is
# the dispatcher, not the port -- a `SKIP`.  A hand list here could only name what it
# already knew, which is the fault this gate exists to catch, so the set is CONSUMED from
# its generator (the `names.py` JSON this file already loads by path) and must be EMPTY: a
# non-empty one is a fresh substitution.

# Every claim above rests on a line.  Read it, or the pin is a rumour.
#
# *** A LINE NUMBER IS NOT STORED HERE, AND THAT IS THE WHOLE FIX. ***  This table used to
# be `(path, line, must-contain, why)` and two of its fourteen rows were already FAILing
# (measured): `graphcmp.bend:1571` and `graphcmp.bend:777`, both by DRIFT -- the text was
# still there at :1595 and :791.  A position is not a fact about a file, it is an accident
# of how many lines happen to sit above it, and `.agents/slop/graphcmp.bend` grew by 24
# lines in two commits without changing one word of either claim.  This is `AGENTS.md`'s
# hand list with the subject swapped: a set of assertions about CONTENT AT A POSITION.
#
# SO THE POSITION IS DERIVED, EVERY RUN, BY AST.  The locator says HOW to find the line:
#
#   DEF:<path>:<name>   the top-level def (or class) named <name>; the assertion is that
#                       its BODY carries the text.  Nine of the fourteen are this form,
#                       and they CANNOT DRIFT -- the name is resolved by the parser on
#                       every run and the line falls out of the node, never out of a list.
#   AT:<path>           the text is searched for as a UNIQUE substring of the whole file.
#                       Five of the fourteen, all of them `.bend`: a `.py` file gets its
#                       `DEF` form and a `.bend` file has no AST to ask.
#
# FOUR of the original needles were AMBIGUOUS and were therefore never pins at all --
# `OpsGROUP` matched 12 lines, `dtype: S.Dt` matched 5, `self.dtype is not dtypes.void`
# matched 2, `return src[0].dtype` matched 5.  An anchor that matches many lines is a
# claim that cannot fail, so the two `DEF` rows are now scoped to their def (which is
# what made those 2 and 5 into 1) and the two `.bend` rows were widened to the statement
# each one actually means.
#
# AN ABSENT ANCHOR IS `REFUSED` (exit 3), NEVER A SILENT PASS AND NEVER A `FAIL`: the gate
# cannot distinguish "the code moved" from "the citation was wrong about the code", and
# guessing is the thing this table is being removed for.
#
# *** ONE ROW OF THIS TABLE WAS A NEGATIVE CLAIM ABOUT A FIXTURE, AND IT ROTTED IN THE ONLY
# DIRECTION A NEGATIVE CLAIM CAN. *** The row read "the bend fixture builds that GROUP by
# hand, bypassing `UOp.group`" and it was TRUE on 2026-10-09. MEASURED 2026-10-18T19:06Z with
# `checks/disagree-gate.py --lane citations`: `[REFUSED] .agents/slop/graphcmp.bend: no line
# carries 'O.UOp.new(O.Found.ar(mul), O.OpsGROUP{}...'`. **AND IT IS **NOT** CAUSED BY ANY
# RECENT COMMIT: `git log -S` puts the needle's last presence at `bbe246aca` (2026-10-09) and
# its removal at `3001661a7` (2026-10-18), and `grep -c` on `git show HEAD~1..HEAD~5` reads 0
# on every one of them -- so the lane was ALREADY RED before the units that are working now
# touched it.
# **THE DEFECT IT RECORDED WAS FIXED, WHICH IS A PIN FAILING BECAUSE THE TREE GOT BETTER** --
# the same one-directional rot `arms_wired` was written to close, in the same table, nine lines
# below it. `bbe246aca` proved `UOp.group` of ONE src RETURNS THE src (`ops.py:559`, still
# `ops.py:537` today) so `g_flip` builds NO group node at all; `69bfc2ee9` then DELETED
# `Ops.GROUP` from the port's enum (77 -> 75 ops), which makes a hand-built one-src GROUP not
# merely wrong but **UNSPELLABLE** -- `bin/bend graphcmp.bend --check-only` rejects a declared
# constructor `ops.Op` does not declare.
# **SO THE ROW IS RESTATED AS THE POSITIVE CLAIM, AND THE REPLACEMENT IS THE PORT's OWN
# `mxw_flip`**: a transcription of CPython's PAD/SHRINK chain would stop testing the port and
# start testing this fixture's typing, which is the `readerdecl` `2x2` rule applied to a
# fixture. It goes red if `g_flip` is ever rewritten by hand, which is the direction that
# matters.
CITES = (
  # (locator, must-contain, why this line is load-bearing)
  ("AT:.agents/slop/graphcmp.bend", "def rows.pick3",
   "the fixture dispatcher; its DEFAULT arm is what substituted the matmul"),
  ("DEF:.agents/slop/graphcmp.py:g_allred", "g_allred",
   "the py fixture for `allred`; `arms_wired` below asserts the bend twin exists, defined once"),
  ("DEF:.agents/slop/graphcmp.py:g_cdiv", "g_cdiv", "ditto"),
  ("DEF:.agents/slop/graphcmp.py:g_late", "g_late", "ditto"),
  ("DEF:tinygrad/uop/ops.py:UOp", "if len(srcs) == 1",
   "`UOp.group` of ONE src is the src, so `g_flip` builds NO GROUP node"),
  ("DEF:.agents/slop/graphcmp.py:g_flip", "UOp.group(a.flip(0).uop)",
   "a ONE-element group -- the whole of the bend-only GROUP#7"),
  ("AT:.agents/slop/graphcmp.bend", "+fk = MX.mxw_flip(fb, [0])",
   "`g_flip` calls the PORT's OWN `mxw_flip`, the way CPython calls `a.flip(0)`, and mints no "
   "group node -- `O.OpsGROUP` was deleted from the port at `69bfc2ee9` (Ops 77 -> 75), so "
   "the hand-built one-src GROUP this row used to cite is no longer spellable"),
  ("AT:tinybendygrad/uop/ops.bend",
   "CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool, "
   "dtype: S.Dt}",
   "the port's CallInfo carries `dtype`, and SO DOES THE PIN -- `ops.py:1398`"),
  ("DEF:ad117c928^:tinygrad/uop/ops.py:CallInfo", "dtype: DType = dtypes.void",
   "the PIN's LAST CallInfo field IS `dtype`, so 'upstream has no dtype' is false"),
  ("DEF:ad117c928^:tinygrad/uop/ops.py:CallInfo",
   'f", dtype={self.dtype})" if self.dtype is not dtypes.void',
   "the PIN's `__repr__` SUPPRESSES the dtype slot for void -- the spelling `loop` broke"),
  ("DEF:tinygrad/uop/ops.py:CallInfo", "aux: Any = None",
   "THE WORKTREE says `aux` is last; the PIN says `dtype` is. Cite the PIN for upstream."),
  ("DEF:tinygrad/uop/ops.py:dtype_from_uop", "return src[0].dtype",
   "upstream reads the CALL dtype off the BODY, never off CallInfo"),
  ("AT:tinybendygrad/uop/fold.bend", "CallInfo.dtype",
   "the port reads it off the field the PIN HAS -- a spelling, not a shape"),
  ("AT:tinybendygrad/uop/ops.bend", "applied_opts: List<&2, OPT>",
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


def defs(text: str, name: str) -> list[str]:
  """The source segment of every top-level def or class called `name`, parsed fresh.

  THIS IS WHAT MAKES A CITATION UNDRIFTABLE.  The name is resolved by the PARSER, so
  inserting a paragraph above the def, deleting a comment below it, or reordering the
  file cannot move the thing the assertion is about -- only renaming the def can, and
  that is the edit a reader of the gate would notice anyway.  Every element past the
  name is a LINE NUMBER WITH A MEANING: none of them is stored in `CITES`."""
  try:
    tree = ast.parse(text)
  except SyntaxError:
    return []
  return [ast.get_source_segment(text, n) or ""
          for n in tree.body
          if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
          and n.name == name]


def locate(loc: str, needle: str) -> tuple[str, str]:
  """Resolve one locator to `(verdict, detail)`.  `verdict` is PASS, FAIL or REFUSED and
  REFUSED is NOT a pass: it means this lane measured nothing about this claim.

  REFUSED IS DELIBERATE FOR THE UNREADABLE AND THE AMBIGUOUS.  An anchor that matches
  zero lines and an anchor that matches twelve are the same kind of event -- the gate
  cannot tell "the code moved" from "this citation never described the code" -- and
  answering either one by guessing is precisely the fault this table was removed for.
  It is not a FAIL, because a FAIL says the tree is wrong and the tree may be right."""
  kind, _, rest = loc.partition(":")
  if kind == "DEF":
    path, _, name = rest.rpartition(":")
    text = source(path)
    if text is None:
      return "REFUSED", f"{path}: unreadable or absent; wanted def {name} carrying {needle!r}"
    found = defs(text, name)
    if len(found) > 1:
      return "FAIL", f"{path}: {name} is defined {len(found)} times, expected once"
    if not found:
      return "REFUSED", f"{path}: no def named {name} carrying {needle!r}"
    if not any(cited(seg, needle) for seg in found):
      return "FAIL", (f"{path}: def {name} no longer carries {needle!r} "
                      f"(it reads {found[0].splitlines()[0].strip()!r}...)")
    return "PASS", ""
  if kind == "AT":
    path = rest
    text = source(path)
    if text is None:
      return "REFUSED", f"{path}: unreadable or absent; wanted {needle!r}"
    hit = [i for i, l in enumerate(text.splitlines(), 1) if cited(l, needle)]
    if not hit:
      return "REFUSED", f"{path}: no line carries {needle[:56]!r}"
    if len(hit) > 1:
      return "REFUSED", (f"{path}: {len(hit)} lines carry {needle[:40]!r} (lines "
                         f"{hit[:6]}), and an anchor that matches many lines is a claim "
                         f"that cannot fail -- widen it or give the row a DEF locator")
    return "PASS", ""
  return "REFUSED", f"{loc}: unknown locator kind {kind!r}"


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
  for loc, needle, why in CITES:
    verdict, detail = locate(loc, needle)
    if verdict != "PASS":
      fails.append(f"[{verdict}] {detail}; {why}")
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

  def answer(d: Path) -> tuple[object, ...] | None:
    r = subprocess.run([sys.executable, str(NAMES), "--json", "--tree", str(d)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    j = json.loads(r.stdout)
    # WHICHEVER GRAPH DISAGREES FIRST. `lin` WAS HARD-CODED HERE, AND WHEN IT STARTED
    # AGREEING `next(...)` RAISED `StopIteration` AND TOOK THE WHOLE PLANT LANE DOWN --
    # a plant that names one graph is a plant that breaks when the tree gets better.
    if not j["disagree"]:
      return None
    g = sorted(j["disagree"], key=lambda x: x["graph"])[0]
    return g["graph"], g["first_row_from_cmp"], g["first_row_recomputed"], g["fields"]

  fails = []
  before = answer(tree)
  # `None` IS A REFUSAL, NOT AN EXCEPTION.  This used to `raise SystemExit`, which took
  # THE WHOLE PROCESS down before `main` could reach its own exit code -- so on a run with
  # no disagreements (the tree's state now: `graphs-disagree=0`) this lane silently became
  # the gate's verdict, and it reported it as `FAIL`.  A missing precondition is REFUSED
  # (exit 3): the plant measured nothing, and the tree getting BETTER is not a defect.
  # It is also what lets a REFUSED from ANOTHER LANE still reach the exit code.
  if before is None:
    return ["[REFUSED] the plant needs one disagreement to move; this run has none"]
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
      return [f"[REFUSED] the plant needs an integer row in range; {graph} reports {row!r}"]
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

  lanes = {"pin": ("PIN", lambda: lane_pin(tree)),
           "citations": ("CITATIONS", lane_citations),
           "coverage": ("COVERAGE ARTEFACTS", lambda: lane_coverage(tree)),
           "plant": ("PLANT + DISARM", lambda: lane_plant(tree))}
  selected = (list(lanes) if a.lane == "all" else [a.lane])

  # THE SUBJECT IS GUARDED, AND ONLY FOR THE LANES THAT READ IT. `citations` takes no `tree` --
  # it reads the PIN file -- so it is not gated on the run directory, and gating it would refuse a
  # lane that measures something else. THIS REPLACED `if not tree.is_dir(): return 2`, and 2 IS
  # NOT NEUTRAL HERE: exit 2 is USAGE in `checks/env-precond.py` and `checks/differ.py`, so a
  # caller reading `$?` could not tell "you passed a bad --tree" from "the corpus was never run".
  # ABSENT AND STALE ARE BOTH REFUSED (3) AND ARE DISTINGUISHED BY TOKEN, NOT BY EXIT.
  if any(k != "citations" for k in selected):
    spec = importlib.util.spec_from_file_location(
      "runs_artifacts", str(ROOT / "checks/runs-artifacts.py"))
    ra = importlib.util.module_from_spec(spec); spec.loader.exec_module(ra)
    try:
      prefix = str(tree.relative_to(ROOT))
    except ValueError:
      prefix = str(tree)
    if code := ra.require(prefix, root=str(ROOT), label="disagree-gate",
                          remedy=ra.REGENERATE):
      return code

  if not NAMES.exists():
    print(f"FATAL: {NAMES} is missing; the pin has no reader.", file=sys.stderr)
    return 2
  bad = 0
  refused = False
  for key in selected:
    title, fn = lanes[key]
    fails = fn()
    refused = refused or any("[REFUSED]" in f for f in fails)
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

  # `REFUSED` IS EXIT 3 AND IT OUTRANKS `FAIL`.  The tree owns five verdicts -- PASS 0,
  # FAIL 1, REFUSED 3, SKIP 4, DEAD 5 -- and collapsing a refusal into a failure would be
  # the one lie this gate exists to catch: a REFUSED row means this lane MEASURED NOTHING
  # about that claim, and a caller reading `$?` as `1` would read "the tree is wrong" when
  # the truth is "this gate cannot see it".  `AGENTS.md`: a gate that exits 0 having
  # measured nothing is worse than no gate, BECAUSE IT IS TRUSTED -- and a gate that exits
  # 1 for a refusal is trusted in exactly the same way, one level down.  THE FLAG IS SET
  # ONCE, INSIDE THE LOOP: calling `lane_citations()` again here would re-run the lane,
  # and a lane called twice is a second measurement of the same thing, which is how a
  # module-level counter makes a stale answer look fresh.
  return 3 if refused else (1 if bad else 0)


if __name__ == "__main__":
  raise SystemExit(main())
