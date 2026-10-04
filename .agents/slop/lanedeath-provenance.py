#!/usr/bin/env python3
"""lanedeath-provenance.py -- THE CONTROL.  A deliberately planted compile error, and the
question "does the new reporting NAME THE FILE AND THE REVISION?"

WHY THIS IS A SEPARATE FILE AND NOT A BLOCK IN THE SELFTEST.  `rebase-gate-selftest.py` drives
`gate_port()` over SYNTHETIC lane dicts with `run_port()` stubbed (its own header records that the
six states "made this file pass by measuring the re-implementation"), so a control added there
would be graded by the same stub that hid the bug.  This one runs the REAL `run_port()` over REAL
.bend files on disk.

AND IT DOES NOT TOUCH `tinybendygrad/`.  The planted error goes into this directory's own
`planted/substrate.bend`, and the "port" is `planted/port.bend`.  Agent-core.md records that a
harness which patches the live tree leaves the tree wired to a plant when it is killed, and the
lesson generalises: a harness that plants in its own directory cannot corrupt a subtree it is
measuring somebody else's.

THE FIVE CELLS, and the reason there are five.  Three controls in this project were found to be
DISARMED -- `cmp -s` on two empty files printing BYTE-IDENTICAL, a digest guard whose `grep`
matched nothing so it hashed the empty string at every level, and a plant that landed in the `py=`
column while `row()` compares `left`, leaving SIX LANES GREEN WHILE DISARMED.  Every one of those
fails the same way: the check has no state in which it can fail.  So each cell here asserts BOTH
directions, and asserts a NON-EMPTY denominator before it is allowed to report a count:

  C1 plant in the PORT ITSELF          -> the site must be the port, named with a line number
  C2 plant in an IMPORTED FILE         -> the site must be the IMPORTED file, NOT the port.  This
                                          is the event: the port the sweep named is not where the
                                          error lives, and this is the cell that fails on the old
                                          reporting and passes on the new one.
  C3 plant, then the def is DELETED     -> the reported site must become NOT FOUND, with the
                                          denominator printed.  This is the phantom: the message
                                          outlives the def.  A tool that cannot print this state
                                          would report C3 exactly as it reports C2.
  C4 no plant                          -> no site at all, over a non-empty closure.  This is the
                                          cell a control with no negative direction is missing.
  C5 a file in the closure MOVES while the lane runs -> drift must be named.  Driven with a
                                          background thread that rewrites the substrate mid-lane,
                                          and it asserts the drift was DETECTED, not that it was
                                          absent -- an absent drift is the boring outcome.

RUN:  .venv/bin/python .agents/slop/lanedeath-provenance.py
"""
from __future__ import annotations

import pathlib
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

GATE = HERE / "rebase-gate.py"
PLANTED = HERE / "phantom-repro" / "planted"
ORACLE = ".agents/slop/prepare-oracle.py"   # any existing oracle: C1-C5 are about the BEND lane

SUB_HEAD = """import Base

type Op is Data:
  OpsCONST{}

type Const is Data:
  CBool{b: Bool}

type Arg is Data:
  ANone{}
  APy{v: Const}

type Tag is Data:
  TNone{}

type Arena is Data:
  Arena{nodes: List<&2, U32>}

type Found is Data:
  Found{ar: Arena, i: U32}

def Arena.empty() -> Arena:
  Arena{Nil{}}

def UOp.new(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Found:
  Found{ar, 0}

def answer() -> Bool:
  True{}
"""

# The plant, and the def NAME it will be reported under.  Copied from the real event's recorded
# text so C2's output can be read against the real sweep's output.
PLANT = """def t_const_bool_int_splits() -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, CBool{True{}}, TNone{})
  True{}
"""

PORT = """import Base
import ./substrate.bend as Sub

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["port=", Bool.show(Sub.answer())]))
"""


def load_gate(name: str):
  import importlib.util
  spec = importlib.util.spec_from_file_location(name, GATE)
  mod = importlib.util.module_from_spec(spec)
  sys.modules[name] = mod
  spec.loader.exec_module(mod)
  return mod


def write_pair(plant: str, port: str = PORT) -> pathlib.Path:
  """(substrate, port) on disk. `plant` goes into the SUBSTRATE; `port` may itself carry a plant,
  which is how C1 puts the defect in the port instead."""
  PLANTED.mkdir(parents=True, exist_ok=True)
  (PLANTED / "substrate.bend").write_text(SUB_HEAD + ("\n" + plant if plant else ""))
  (PLANTED / "port.bend").write_text(port)
  return PLANTED / "port.bend"


PORT_PLANTED = ("import Base\n"
                "import ./substrate.bend as Sub\n"
                "\n"
                + PLANT
                + "\ndef main() -> IO(Unit):\n"
                  "  do IO<Unit>:\n"
                  "    IO.print(String.concat([\"port=\", Bool.show(Sub.answer())]))\n")


def gate_of(g, bend):
  """The REAL run_port -> verdict -> stamp path, through gate_port(), on the planted pair."""
  v, _ = g.gate_port(bend, [ORACLE], {"lanes": {}, "hunks": {}}, native=False)
  return v


def sites(v, lane="interpreted"):
  return (v.get("error_sites") or {}).get(lane, [])


def no_lane_death(v) -> bool:
  """The lane RAN. The planted pair's `port=` row shares no name with any oracle on this tree, so
  a green verdict is unreachable here and is NOT what this control asserts -- what it asserts is
  that no lane died, which is the only question C1-C5 ask of the BEND side."""
  return v["cause"] != "LANE-DEATH"


def line(label: str, ok: bool, detail: str) -> bool:
  print(f"{'ok  ' if ok else 'FAIL'} {label}\n     {detail}")
  return ok


def c1_port_plant(g) -> bool:
  """The error lives in the PORT. The site must name the PORT, with a line number."""
  bend = write_pair("", PORT_PLANTED)
  v = gate_of(g, bend)
  found = sites(v)
  ok = (v["cause"] == "LANE-DEATH" and len(found) == 1
        and found[0][0] == "t_const_bool_int_splits" and found[0][1] == g.port_key(bend)
        and isinstance(found[0][2], int) and found[0][2] > 0)
  return line("C1 plant in the PORT -> site names the port and its line", ok,
              f"cause={v['cause']} closure={len(v.get('substrate') or [])} file(s) "
              f"sites={[(n, w, l) for n, w, l in found]}  port={g.port_key(bend)}")


def c2_substrate_plant(g) -> bool:
  """THE EVENT. The error lives in an IMPORTED file and the port is clean. The site must name the
  IMPORTED file, AND the verdict's own text must say the port is a victim -- a site printed on its
  own line while `why`/`cause_reason` still blames the port would satisfy this cell's first half
  and none of its point, and that is exactly the state the wrong lift order in `stamp()` produced."""
  bend = write_pair(PLANT)
  v = gate_of(g, bend)
  found = sites(v)
  sub_rel = g.port_key(PLANTED / "substrate.bend")
  ok = (v["cause"] == "LANE-DEATH"
        and found == [("t_const_bool_int_splits", sub_rel, found[0][2] if found else None)]
        and found and isinstance(found[0][2], int)
        and sub_rel in v["cause_reason"] and "NOT IN THE PORT" in v["cause_reason"])
  return line("C2 plant in an IMPORTED file -> site names THAT file, and the verdict says the "
              "port is a victim", ok,
              f"cause={v['cause']} sites={[(n, w, l) for n, w, l in found]}\n"
              f"     cause_reason names the substrate : {sub_rel in v['cause_reason']}   "
              f"says NOT IN THE PORT : {'NOT IN THE PORT' in v['cause_reason']}   "
              f"closure={len(v.get('substrate') or [])} file(s)")


def c3_phantom(g) -> bool:
  """THE PHANTOM, at the only place it can be tested without inventing a cache. bend re-reads the
  tree on every run, so a stale parse cannot happen inside one lane -- the thing that outlived the
  def was the RECORDED MESSAGE, read later by a reader with no def to grep for. So this cell keeps
  the stderr from the planted run, deletes the def, and re-resolves that SAME text against the tree
  as it now stands: the site must come back unresolved, and unresolved must be REPORTED with the
  closure's size beside it rather than as a clean bill of health."""
  bend = write_pair(PLANT)
  v = gate_of(g, bend)
  msg = (v["lanes"]["interpreted"]["err"])
  (PLANTED / "substrate.bend").write_text(SUB_HEAD)          # the agent finishes its edit
  closure = g.import_closure(bend)
  after = g.error_site(msg, closure)
  n_closure = len(closure)
  ok = (v["cause"] == "LANE-DEATH"
        and after == [("t_const_bool_int_splits", None, None)]
        and n_closure >= 2)
  fresh = gate_of(g, bend)
  return line("C3 the recorded message outlives the def -> the site becomes UNRESOLVED, "
              "with the denominator", ok,
              f"with the plant    : cause={v['cause']} sites={[(n, w) for n, w, _l in sites(v)]}\n"
              f"     the SAME text re-resolved after the def was deleted : "
              f"{[(n, w) for n, w, _l in after]}   closure={n_closure} file(s)\n"
              f"     a FRESH run on the same files                      : cause={fresh['cause']} "
              f"sites={[(n, w) for n, w, _l in sites(fresh)]}\n"
              f"     so the ghost is in the MESSAGE, not in a cache: bend re-read the tree and "
              f"stopped reporting it, and the number a reader is left holding is a recorded "
              f"string over a tree that no longer exists")


def c4_no_plant(g) -> bool:
  """Nothing planted. No site, and a NON-EMPTY closure -- the cell a one-directional control lacks.
  It is also the cell that fails if the import closure silently comes back empty, which is the
  `md5 -q`-on-several-files shape: a digest of nothing is a famous constant and prints fine."""
  bend = write_pair("")
  v = gate_of(g, bend)
  n = len(v.get("substrate") or [])
  ok = (n >= 2 and sites(v) == [] and no_lane_death(v)
        and all(h and h != "0" * 12 for _p, h, _b in v["substrate"]))
  return line("C4 no plant -> no site, over a NON-EMPTY closure with NON-EMPTY digests", ok,
              f"cause={v['cause']} closure={n} file(s) sites={sites(v)}  "
              f"digests={[h for _p, h, _b in v['substrate']]}\n"
              f"     (a closure of 0, or a digest of the empty string, would make every 'no site' "
              f"below vacuous; both are FAILURES here, not passes)")


def c5_drift_while_running(g) -> bool:
  """A closure file MOVES while the lane runs. The drift must be NAMED.

  Driven with a thread, and it asserts the drift was DETECTED.  The lane is a real `bend` run over
  the planted pair, so the thread has to win the race; it rewrites the substrate repeatedly for a
  fixed window rather than once, because a single write landing after the AFTER manifest reads as a
  control that cannot fail -- which is the whole lesson of this file's header."""
  bend = write_pair("")
  stop = threading.Event()
  payload = SUB_HEAD + "\n# touched while the lane ran\n"

  def churn():
    while not stop.is_set():
      (PLANTED / "substrate.bend").write_text(payload)
      time.sleep(0.005)
      (PLANTED / "substrate.bend").write_text(SUB_HEAD)
      time.sleep(0.005)

  t = threading.Thread(target=churn, daemon=True)
  t.start()
  try:
    seen = None
    for _ in range(6):
      v = gate_of(g, bend)
      d = v.get("substrate_drift") or {}
      if d.get("moved") or d.get("added") or d.get("gone"):
        seen = (v, d)
        break
  finally:
    stop.set()
    t.join(timeout=5)
    (PLANTED / "substrate.bend").write_text(SUB_HEAD)
  ok = bool(seen) and bool(seen[1]["moved"] or seen[1]["added"] or seen[1]["gone"])
  detail = (f"attempts=6  drift seen on attempt "
            f"{'yes' if seen else 'NO'}  "
            + (f"moved={seen[1]['moved']} added={seen[1]['added']} gone={seen[1]['gone']} "
               f"closure={len(seen[0].get('substrate') or [])}" if seen else ""))
  return line("C5 a closure file MOVES while the lane runs -> the drift is NAMED", ok, detail)


def c6_must_be_able_to_fail(g) -> bool:
  """THE CONTROL IS ARMED. Every cell above asks "is the site right?" and a reporting change with
  no site at all would answer NO to all of them -- which is a FAIL, so they are not disarmed by
  construction. What is NOT covered is the DRIFT detector reading a tree that DID move as clean,
  because the churn thread lost every race. So this cell drives `drift()` directly with two
  constructed manifests -- the boring outcome and the interesting one -- and requires both answers.

  It is the shape of the three controls found disarmed in this project (`cmp -s` on two empty
  files, a digest guard whose grep matched nothing, a plant in the column nobody compares): a check
  with no state in which it can fail. `drift()` is handed one pair that differs and one that does
  not, and BOTH answers are printed."""
  base = g.substrate_manifest(PLANTED / "port.bend")
  same = g.drift(base, list(base))
  moved = g.drift(base, [(p, "deadbeefcafe", sz) if p.endswith("substrate.bend") else (p, h, sz)
                         for p, h, sz in base])
  added = g.drift(base, base + [(".agents/slop/phantom-repro/planted/new.bend", "0" * 12, 0)])
  ok = (not any(same["moved"] + same["added"] + same["gone"])
        and moved["moved"] and "substrate.bend" in moved["moved"][0]
        and added["added"] == [".agents/slop/phantom-repro/planted/new.bend"])
  return line("C6 the drift reader has a state in which it can FAIL (boring and interesting)", ok,
              f"identical manifests -> moved={same['moved']} added={same['added']} "
              f"gone={same['gone']}\n"
              f"     one changed byte -> moved={moved['moved']}\n"
              f"     one new file    -> added={added['added']}   (over a closure of "
              f"{len(base)} file(s))")


def c7_the_control_is_armed(g) -> bool:
  """A CHECK THAT HAS NEVER BEEN SEEN TO FAIL IS NOT KNOWN TO WORK.  So neuter the ONE thing C2
  depends on -- `error_site()`, the reader that resolves bend's def name against the closure --
  and require C2's own assertion to come back FALSE.

  The mutation is on the INSTRUMENT, not on the tree, and it is the smallest one that removes the
  whole claim: with `error_site()` returning `[]` there is no site, no "NOT IN THE PORT", and C2
  must fail. If it passed, C2 would be a check that cannot fail -- the shape of the three controls
  this project found disarmed (`cmp -s` on two empty files, a digest guard whose grep matched
  nothing, a plant in the `py=` column while `row()` compares `left`, six lanes green while
  disarmed)."""
  bend = write_pair(PLANT)
  real = g.error_site
  try:
    g.error_site = lambda err, closure: []
    v = gate_of(g, bend)
    found = sites(v)
    sub_rel = g.port_key(PLANTED / "substrate.bend")
    would_pass = (v["cause"] == "LANE-DEATH" and found
                  and all(w == sub_rel for _n, w, _l in found)
                  and "NOT IN THE PORT" in v["cause_reason"])
  finally:
    g.error_site = real
  restored = sites(gate_of(g, bend))
  ok = (not would_pass) and bool(restored)
  return line("C7 the control is ARMED: with error_site() neutered, C2's assertion must FAIL", ok,
              f"C2's assertion with the reader neutered : {'PASSES (THE CONTROL IS DISARMED)' if would_pass else 'fails, as it must'}\n"
              f"     the same cell with the reader restored : "
              f"{[(n, w) for n, w, _l in restored]}  (so the FAIL above was the mutation and not "
              f"a broken pair)")


def main() -> int:
  if not (REPO / "bin" / "bend").exists():
    print(f"REFUSING: {REPO / 'bin' / 'bend'} is not on disk; C1-C5 are bend measurements.")
    return 1
  g = load_gate("rg_lanedeath_control")
  print("=" * 100)
  print("LANE-DEATH PROVENANCE CONTROL.  6 cells, each with the direction that can fail.")
  print(f"planted pair: {PLANTED}/  (NOT under tinybendygrad/ -- nothing here edits a port)")
  print("=" * 100)
  results = [c1_port_plant(g), c2_substrate_plant(g), c3_phantom(g), c4_no_plant(g),
             c5_drift_while_running(g), c6_must_be_able_to_fail(g),
             c7_the_control_is_armed(g)]
  bad = results.count(False)
  print("-" * 100)
  print(f"{len(results) - bad}/{len(results)} cells hold;  {bad} FAIL")
  print("denominator: 7 of 7 named cells exercised, 0 skipped. The planted pair's `port=` row")
  print("shares no name with any oracle on this tree, so a GREEN verdict is unreachable here and")
  print("no cell claims one -- what every cell asks of the BEND side is `cause != LANE-DEATH` for")
  print("the unplanted runs and a resolved site for the planted ones. A cell that asserted a green")
  print("verdict over a synthetic lane would be asserting that GUARD 4 compares rows it cannot")
  print("have, which is the INCOMPARABLE trap rather than a check.")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())