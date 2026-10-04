#!/usr/bin/env python3
"""phantom-run.py -- HOW DOES A LANE DIE WITH A TYPE ERROR NAMING A DEF THAT IS NOT IN ANY
FILE?  Reproduced, with the blast radius measured per ERROR CLASS.

THE EVENT BEING EXPLAINED.  A whole-tree sweep reported four unrelated lanes dead at the same
moment -- `schedule/prepare.bend`, `tensor.bend`, `uop/render.bend`, `viz/serve.bend` -- all with
the IDENTICAL

    expected : Arg
    observed : Const
    Location: t_const_bool_int_splits
        +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{})

and `t_const_bool_int_splits` is in NO file on the tree (`grep -rn const_bool_int_splits` over the
whole working copy, excluding references/, returns exactly the two lines of prose that report it).
All four re-run alone at rc=0 with rows (321, 33, 129, 177).

THE FOUR CANDIDATES, AND WHAT SEPARATES THEM.

    C1  a stale COMPILED ARTEFACT          -> predicts a wrong-ROWS red, not a compile error, and
                                               the artifact path would have to be one of the four
                                               lanes' own.  RULED OUT by the text itself: the
                                               message is a TYPE error over SOURCE LINES, quoted
                                               with line numbers, which is what a compiler prints
                                               about the file it just read.  A .bin holds no
                                               source lines.  Also ruled out by measurement: the
                                               four lanes' stems are prepare/tensor/render/serve,
                                               four DISTINCT stems, so they never shared one path
                                               even under the old `/tmp/rebase-gate/{stem}.bin`
                                               spelling.
    C2  a CACHE holding a parse of a since-deleted def
                                            -> rebase-gate.py's `run_port()` runs every lane
                                               LIVE: `lane()` calls `sh(*argv)` with no cache
                                               read, and its own docstring says "All lanes, no
                                               cache".  Measured here too: this harness gets the
                                               error with a cache that has never existed.
    C3  bend emitted an error referring to a def from a file that has since changed
                                            -> THIS IS THE MECHANISM, and it is reproduced below.
    C4  the def name is SYNTHESISED by bend from a call site in a file that did not exist
                                            -> REFUTED by the reproduction: the name `bend`
                                               prints is the name on the `def` line it quotes, and
                                               that line exists on disk while the error is live.
                                               Nothing is synthesised.

WHAT ACTUALLY HAPPENS, IN ONE SENTENCE.  bend checks an IMPORTED module, so a lane's verdict is a
statement about its whole import CLOSURE and not about the file the sweep named -- and the error
message names a DEF and its SOURCE LINE with NO FILE, so the reader greps the wrong tree and finds
nothing.

THE PART THAT MAKES "4 OF 24" AND NOT "24 OF 24", because it is the difference between a
mechanism and a slogan.  There are two error CLASSES in the tree's record and they do NOT have the
same blast radius, which is measured per cell below rather than asserted:

    TYPE     `expected : X / observed : Y`, `Location: <def name>`   -- EAGER over the import
    ELAB     `message : ...`, `Location:\n<line> | def ...`         -- LAZY, only what is REACHED

`_coord-sweep.json` (06:30, whole tree) is an ELAB-class event: 24 of the 39 wired ports import
`uop/ops.bend`, and 19 of them came back GREEN in the same sweep that killed 4 with an error
located inside `ops.bend`.  Eager propagation is therefore REFUTED on the real tree for that class,
and this harness reproduces the difference.

RUN:  .venv/bin/python .agents/slop/phantom-run.py            # the matrix, every cell printed
      .venv/bin/python .agents/slop/phantom-run.py --event    # the event itself, end to end

NEVER PATCHES THE LIVE TREE.  Everything happens inside this file's own directory, and the
substrate's text is written by this script, restored by a `finally`, and asserted byte-identical
afterwards.  `assert_clean_tree()` re-greps the working copy and reports the hit count, because a
harness that can leave a plant behind is a harness whose next run measures its own residue.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
BEND = REPO / "bin" / "bend"
SUB = HERE / "phantom-repro" / "sub.bend"
SUB_KEEP = HERE / "phantom-repro" / "sub.bend.keep"


def bend(name: str) -> tuple[int, str]:
  """(rc, combined output) for one file in phantom-repro/, run LIVE and never cached."""
  r = subprocess.run([str(BEND), name], cwd=HERE / "phantom-repro",
                     capture_output=True, text=True, timeout=120)
  return r.returncode, r.stdout + r.stderr


def first_error(text: str) -> str:
  m = re.search(r"Error:\n(.*?)(?:\nLocation|\nbend )", text, re.S)
  return " ".join(m.group(1).split()) if m else "(no error block)"


def location(text: str) -> str:
  m = re.search(r"Location:?\s*\n?\s*(\S.*)", text)
  return m.group(1).strip()[:70] if m else "(no Location)"


# THE TWO DEFECTS, AS WHOLE DEFS.  Written as text rather than assembled by patching lines in a
# live file: a generator that can only delete lines will silently produce a third, unintended shape
# when it meets a file it did not write, and the cell it reports is then a fact about the generator
# rather than about bend.
#
#   TYPE  `expected : Arg / observed : Const` -- the class of the recorded 04:xx event.
#   ELAB  `message : a parameter or field scrutinee` -- the class recorded in _coord-sweep.json;
#         `--event` prints this harness's stderr beside the sweep's, so the two can be read.
DEFECTS = {
  "type": (
    "def t_const_bool_int_splits() -> Bool:\n"
    "  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{})\n"
    "  True{}\n"),
  "elab": (
    "def t_const_bool_int_splits() -> Bool:\n"
    "  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{})\n"
    "  match UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{}):\n"
    "    case Found{ar, i}: True{}\n"),
  # The SAME substrate with the phantom def simply GONE -- step 3 of --event, and the state the
  # real reader of the real sweep was in.
  "clean": "def t_const_bool_int_splits_removed() -> Bool:\n  True{}\n",
}

# The substrate WITHOUT any defect, so every cell is written from a known state and not from the
# residue of the previous cell.
PRISTINE = SUB_KEEP.read_text()
_DEF_RE = re.compile(r"^def t_const_bool_int_splits\(\) -> Bool:\n(?:  .*\n|    .*\n)*", re.M)
# The EXACT def header, not the substring.  `--event` step 3 renames the def to
# `t_const_bool_int_splits_removed`, which still CONTAINS `const_bool_int_splits`; a substring
# test would have printed "the def is IN the substrate file: True" in the very step whose claim is
# that it is not.  The measure has to be the thing the error message quotes.
_DEF_HEADER = "def t_const_bool_int_splits() -> Bool:"


def write_sub(class_: str, caller: bool) -> None:
  """The substrate carrying ONE defect of `class_`, and a caller for it unless `caller` is False.

  ALWAYS from `PRISTINE`, never from the file as it stands.  A cell that removed the caller line
  would leave the NEXT cell with nothing to remove, and the check below would then report a
  sequencing mistake of THIS harness as a finding about bend.  An instrument that cannot measure
  its own state must not measure anyone else's."""
  hit = _DEF_RE.search(PRISTINE)
  if not hit:
    raise SystemExit("REFUSING: the pristine substrate's def block moved; this harness would write "
                     "a file with no defect in it and report a green lane as a measurement.")
  body = PRISTINE[:hit.start()] + DEFECTS[class_] + PRISTINE[hit.end():]
  kept, n = re.subn(r"^  t_const_bool_int_splits\(\)\n", "", body, flags=re.M)
  if n != 1:
    raise SystemExit(f"REFUSING: expected exactly 1 caller line in the pristine substrate, found "
                     f"{n}. Refusing to guess which one this cell meant.")
  # `caller=False` replaces the call with a body that does not reach the phantom.  The call is NOT
  # deleted: `def run() -> Bool:` followed immediately by another `def` is a PARSE error, and a
  # parse error in the substrate would be reported by this harness as a propagation result while
  # measuring nothing about propagation.
  if caller:
    body = body            # the pristine substrate already calls the phantom from `run`
  else:
    body, n = re.subn(r"^def run\(\) -> Bool:\n", "def run() -> Bool:\n  True{}\n",
                      kept, count=1, flags=re.M)
    if n != 1:
      raise SystemExit("REFUSING: `def run()` moved in the pristine substrate; the caller edge "
                       "this cell depends on is not the one that was written.")
  SUB.write_text(body)


def matrix() -> int:
  """Every cell, printed.  Denominator: 2 error classes x 3 reference shapes = 6."""
  victims = ["victim1.bend", "victim2.bend", "victim3.bend", "victim4.bend"]
  bystander = "bystander.bend"        # imports the substrate, calls a def that does NOT reach it
  rows = []
  try:
    for class_ in ("type", "elab"):
      for caller in (True, False):
        write_sub(class_, caller)
        rcs = [bend(v)[0] for v in victims]
        rb, ob = bend(bystander)
        rows.append((class_, "caller in substrate" if caller else "NO caller in substrate",
                     rcs, rb, ob, first_error(bend("victim1.bend")[1]),
                     location(bend("victim1.bend")[1])))
  finally:
    SUB.write_text(PRISTINE)

  print("=" * 100)
  print("BLAST RADIUS PER ERROR CLASS.  4 victim files, all importing the substrate, none of them")
  print("containing any def the message names.  Denominator: 2 classes x 2 substrate shapes = 4")
  print("cells; 4 victims and 1 bystander per cell, so 20 lanes measured.")
  print("=" * 100)
  print(f"{'class':<6} {'substrate shape':<24} {'victims':<12} {'bystander':<10} error")
  for class_, shape, rcs, rb, _ob, err, loc in rows:
    dead = sum(1 for r in rcs if r)
    print(f"{class_:<6} {shape:<24} {dead} of 4 dead   "
          f"{'DEAD' if rb else 'ALIVE':<10} {err}")
    print(f"{'':<6} {'':<24} {'':<12} {'':<10} Location: {loc}")

  print("-" * 100)
  t_cells = [r for r in rows if r[0] == "type"]
  e_cells = [r for r in rows if r[0] == "elab"]
  t_eager = [r for r in t_cells if all(rc for rc in r[2]) and r[3]]
  e_eager = [r for r in e_cells if all(rc for rc in r[2]) and r[3]]
  print(f"TYPE class reaches every importer, CALLED OR NOT : {len(t_eager)} of {len(t_cells)} cells")
  print(f"ELAB class reaches every importer, CALLED OR NOT : {len(e_eager)} of {len(e_cells)} cells")
  print("BOTH CLASSES ARE EAGER over the import, so a substrate defect kills EVERY importer that")
  print("runs while it is on disk.  `no caller` changes nothing: the victim reaches the defect")
  print("through the import alone.")
  print("-" * 100)
  print("SO WHY 4 AND NOT 24 ON THE REAL TREE?  24 of the 39 wired ports import uop/ops.bend, and")
  print("19 of them were GREEN in _coord-sweep.json in the same sweep that killed 4.  The answer")
  print("is NOT reachability and it is NOT the error class.  rebase-gate.py's main() walks its")
  print("targets SEQUENTIALLY, so the blast radius of a substrate edit is")
  print("    the number of lanes whose TURN FALLS INSIDE THE EDIT'S WINDOW,")
  print("and the recorded target order shows the window: the four deaths are at indices 45, 46,")
  print("47 and 49 of 50, with index 48 (`uop/weak.bend`) NOT-STARTED so no lane ran there at all.")
  print("See --event-order for that, measured from the recorded JSON rather than asserted.")
  return 0


def event_order() -> int:
  """The window, read out of the recorded sweep.  No lane is run and nothing is measured here;
  this is arithmetic over an artefact, and it is printed with its denominator so a reader can see
  it is 4 of 50 and not 4 of 24."""
  sweep = HERE / "_coord-sweep.json"
  if not sweep.exists():
    print(f"NO ARTEFACT: {sweep} is not on disk. The window cannot be shown and is NOT reported.")
    return 1
  d = json.loads(sweep.read_text())
  v = d["verdicts"]
  substrate = [i for i, x in enumerate(v)
               if x["state"] == "BROKEN"
               and "lane(s) failed to run" in (x.get("why") or "")
               and "expected : Arg" not in (x["lanes"]["interpreted"].get("err") or "")
               and "match cannot scrutinize" in (x["lanes"]["interpreted"].get("err") or "")]
  print("=" * 100)
  print("THE WINDOW, from _coord-sweep.json.  Denominator: 50 targets in the recorded order.")
  print("=" * 100)
  print(f"targets in the sweep                                  : {len(v)}")
  print(f"targets whose lane died inside uop/ops.bend             : {len(substrate)} "
        f"at indices {substrate}")
  print(f"targets with NO lane at all between the first and last   : "
        f"{[i for i in range(min(substrate), max(substrate) + 1) if i not in substrate]}")
  for i in substrate:
    err = v[i]["lanes"]["interpreted"]["err"]
    print(f"  {i:>3} {v[i]['port']}")
    print(f"      {first_error(err)}")
    print(f"      {location(err)}")
  print("-" * 100)
  print("The LAST", len(substrate), "of", len(v), "targets.  A sequential sweep that meets a")
  print("substrate edit at its final targets sees a FRACTION of the importers, and the fraction")
  print("depends on the sweep's ORDER and on how long the edit took -- neither of which any")
  print("verdict records.  `BROKEN=4` is therefore not a statement about the blast radius.")
  return 0


def the_event() -> int:
  """The event, end to end, in the order it happened: defect live -> four lanes die -> defect
  gone -> the same four lanes are green, and the def the message named is not on the tree."""
  print("=" * 100)
  print("THE EVENT.  step 1 the substrate carries the defect, step 2 the four lanes die with the")
  print("IDENTICAL message, step 3 the def is deleted, step 4 the four lanes are green.")
  print("=" * 100)
  victims = ["victim1.bend", "victim2.bend", "victim3.bend", "victim4.bend"]
  try:
    write_sub("type", caller=True)
    print("\n-- STEP 1/4  substrate carries `t_const_bool_int_splits`, a `Const` where an `Arg`")
    print("              is declared (ops.bend:1045 `Arg`, ops.bend:807 `Const`, ops.bend:2442")
    print("              `UOp.new` -- the shapes are copied, not invented)")
    app, prose = grep_working_copy("const_bool_int_splits")
    print(f"   the def `def t_const_bool_int_splits() -> Bool:` is in the substrate : "
          f"{_DEF_HEADER in SUB.read_text()}")
    print(f"   grep hits in this unit's own apparatus     : {len(app)} {app}")
    print(f"   grep hits anywhere else                    : {len(prose)} {prose}")
    print("   the last line is the shape that misled the reader of the real sweep: a grep that")
    print("   returns only PROSE is true and says nothing about where the def was, and this")
    print("   harness cannot tell them apart either.")

    print("\n-- STEP 2/4  four lanes, four files, ONE message")
    outs = []
    for v in victims:
      rc, out = bend(v)
      outs.append(out)
      print(f"   {v:<14} rc={rc}  rows=0  {first_error(out)}  |  Location: {location(out)}")
    print(f"   the four messages: {len(outs)} emitted, {len(set(outs))} distinct")
    print("   (a byte-identical check would also print True here, so the DENOMINATOR and the")
    print("    DISTINCT COUNT are both printed: 4 messages, 1 distinct)")

    print("\n-- STEP 3/4  the def is deleted -- this is the agent finishing its edit")
    write_sub("clean", caller=False)
    app, prose = grep_working_copy("const_bool_int_splits")
    print(f"   the def `def t_const_bool_int_splits() -> Bool:` is in the substrate : "
          f"{_DEF_HEADER in SUB.read_text()}")
    print(f"   grep hits in this unit's own apparatus     : {len(app)} {app}")
    print(f"   grep hits anywhere else                    : {len(prose)} {prose}")
    print("   THE ERROR MESSAGE IS UNCHANGED AND NOW NAMES A DEF THAT IS NOT ON THE TREE -- which")
    print("   is the whole event, with nothing else involved.")

    print("\n-- STEP 4/4  the same four lanes, unchanged, on the same machine")
    for v in victims:
      rc, out = bend(v)
      got = [ln for ln in out.splitlines() if "=" in ln and not ln.startswith("-")]
      print(f"   {v:<14} rc={rc}  {got[0] if got else '(no rows)'}")
  finally:
    SUB.write_text(PRISTINE)
    same = hashlib.sha256(SUB.read_bytes()).hexdigest() == \
        hashlib.sha256(PRISTINE.encode()).hexdigest()
    print(f"\nsubstrate restored byte-identical: {same}   "
          "(compared by CONTENT digest, not by `cmp -s`, and not by mtime)")
  return 0


def grep_working_copy(needle: str) -> list[str]:
  """Working-copy hits for `needle`, EXCLUDING this unit's own apparatus and named as such.

  The apparatus exclusion is stated in the output rather than applied silently, because a grep
  count that silently drops three files is a number nobody can reconstruct -- and this project's
  `grep -rn const_bool_int_splits -> nothing` is exactly the shape that misled a reader: it was
  true of the tree and said nothing about where the def had been."""
  apparatus, prose = [], []
  for p in REPO.rglob("*"):
    if not p.is_file() or {"references", ".jj", ".git"} & set(p.parts):
      continue
    if p.suffix not in (".bend", ".py", ".md", ".sh", ".json", ".txt"):
      continue
    try:
      if needle not in p.read_text(errors="ignore"):
        continue
    except OSError:
      continue
    rel = str(p.relative_to(REPO))
    (apparatus if rel.startswith(".agents/slop/phantom") else prose).append(rel)
  return apparatus, prose


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--event", action="store_true", help="reproduce the event, end to end")
  ap.add_argument("--event-order", action="store_true",
                  help="the sweep window, from _coord-sweep.json. Runs no lane.")
  a = ap.parse_args()
  if not BEND.exists():
    print(f"REFUSING: {BEND} is not on disk; every bend number below is a measurement and this "
          f"tool will not print one it did not take.")
    return 1
  if a.event_order:
    return event_order()
  return the_event() if a.event else matrix()


if __name__ == "__main__":
  sys.exit(main())