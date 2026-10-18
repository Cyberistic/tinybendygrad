#!/usr/bin/env python3
"""corpuslane-gate.py -- IS THE `graphcmp` CPYTHON LANE ALIVE, AND IS IT READING UPSTREAM?

    .venv/bin/python gates/corpuslane-gate.py
    .venv/bin/python gates/corpuslane-gate.py --driver PATH   # point at another driver

WHY THIS GATE EXISTS, AND THE SHAPE OF THE GAP. The corpus's headline oracle is
`.agents/slop/graphcmp.py emit --side py`, and it reads `tinygrad/` through attributes, so a
re-vendor that moves one of them turns every read into an `AttributeError`. That is what the
re-vendor `a741a469f` did on 2026-10-17: run against that `tinygrad/`, the PRE-re-vendor
driver (`git show a741a469f^:.agents/slop/graphcmp.py`) raised across most of
`graphcmp.GRAPHS`, and the graphs that did NOT raise were the ones with no `BUFFER`/`ALLOC`/
`PARAM` node (`range`, `rangeflat`, `sink`, `special`) -- they never reach the broken read,
so their survival was never evidence that the lane worked.

**NOT ONE FIGURE OF THAT RUN IS REPEATED HERE, AND THAT IS DELIBERATE.** A count read off one
`tinygrad/` tree is a transcription, and `AGENTS.md`: "A LINE IN HERE WITH NO MEASUREMENT AND
NO NAMED INSTRUMENT IS A LINE YOU MUST NOT TRUST, AND DELETING IT IS CHEAPER THAN LEAVING
IT." THE ONLY PLACE THIS GATE'S CURRENT FIGURES LIVE IS ITS OWN TOTALS LINE, WHICH
`gates/prose-census.py` READS BACK AND CHECKS AGAINST THIS FILE -- so a reader who wants the
numbers runs `.venv/bin/python gates/corpuslane-gate.py` and reads its last line, and a
reviewer who wants to know whether THIS PARAGRAPH agrees with this gate gets an answer
instead of having to take a docstring's word for it.

**A RAISER IS INVISIBLE TO EVERY EXISTING GATE, AND THAT IS THE POINT.** `checks/differ.py`
runs the corpus and counts ROWS; a lane that raised produced no rows, so the count read as
"a graph with nothing to say" and the run reported a FULL SLATE OF AGREEMENT from
PRE-re-vendor artefacts. Those artefacts are `runs/graphcmp/D/D0-run-summary.txt`, and what
dates one is its own `substrate-start` / `substrate-end` pair -- the substrate it was written
against -- and not its mtime, which dates the WRITE. **A gate that runs ITS OWN driver cannot
see this one raise**, which is why this gate is a separate file and not a line in `differ.py`.

WHAT IT MEASURES, TWO THINGS, BOTH OF WHICH A COUNT CANNOT:

  1. **THE LANE PRODUCES ROWS.** Every graph in `graphcmp.GRAPHS` -- LOADED OFF THE DRIVER,
     not named here (`AGENTS.md` doctrine 1: "Never list in this file what an instrument
     discovers") -- is emitted, and a raise is a FAIL with its type and message. `SKIP IS NOT
     PASS`: an unrunnable graph is `FAIL` here, not a skip, because the corpus's own
     denominator is "every graph in `graphcmp.GRAPHS` answered" and a graph that cannot
     answer is not in it.
  2. **THE LANE READS ONLY WHAT UPSTREAM STILL HAS.** A `__getattr__` recorder is installed
     on every class the emitter receives a value of. `__getattr__` is reached ONLY when
     normal lookup FAILS, so every name it records is a name the class does not have. This is
     what found `ParamArg.size` -- the attribute the `a741a469f` re-vendor moved -- and it
     is what will find the next one. Its current read count is not written here: every miss
     is its own `missing.<class>.<name>` row in this gate's artifact, and a clean run prints
     `0 missing attrs` only because the control below proved the recorder fires.

THE POSITIVE CONTROL, AND IT IS THE GATE'S MOST IMPORTANT LINE. An instrument that cannot
detect anything reports a clean zero, and "0 missing attributes" from an instrument that was
never proved able to see one is the `DEAD` of `gates/gatekit.py:55` wearing a count. So
every run FIRST asserts the recorder fires on a name that does not exist and stays silent on
one that does. **A control that fails is `REFUSED`, not `PASS`**: the gate measured nothing,
and reporting that as green is the defect it was written for.

A MISSING TOKEN IS NOT A VERDICT. The `?NOTOKEN` spelling is COPIED from
`checks/compile-census.py:146` (`state = state + "?NOTOKEN"`), which is the one place in this
tree that already handles "the instrument's own verdict line is absent": a row keeps its
state and gains the marker, so a reader sees that the token was unread rather than trusting a
verdict that is not there. `--driver` naming a file that does not resolve is that row's
`REFUSED?NOTOKEN`.

WHY THIS IS NOT A `gatekit.Gate`. `Gate` is one `.bend` driver against one CPython oracle,
diffed. This lane has NO `.bend` half: it asks whether the CPython half can read upstream at
all, and the bend half's answer cannot make that either true or false. Forcing it into
`Gate` would mean naming a bend driver the gate never runs. The five verdicts and the
`name=value` totals are `gatekit`'s, imported rather than re-spelled.

THE TWO PLANTS `differ.py` NEVER RUNS. `graphcmp.PLANTS` has 9 members;
`checks/differ.py:230` declares 7 of them on a graph (`6 on matmul`, `sym1 on sym`) and the
corpus runs those 7. `dsexpand` and `disarm` are in NO declaration anywhere, so their lane
was NEVER EXERCISED by a run -- and `dsexpand` reads `src[1].as_shape`, the `marg` that
`72f98ffe0` moved through on its way to moving `size`. They are run here on `bw` (which is
what `plant_dsexpand`'s own docstring names) and reported as their own class, `unwired`, so
the number of plants the corpus exercises and the number that exist stop being different
numbers that nobody notices.
"""
from __future__ import annotations

import argparse
import collections
import importlib.util
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
DRIVER = ROOT / ".agents" / "slop" / "graphcmp.py"
ART = HERE / "artifacts" / "corpuslane-gate"
DEV, SPEC = "CPU", "1"

sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

STATE = "state"          # copied from checks/compile-census.py's `state` column
TOK = "token"            # copied likewise: bounded.py's OWN verdict token, never the rc


def load(path: pathlib.Path, name: str):
  """BY PATH, and the path is an ARGUMENT: the whole point is to point this at a driver that
  has been mutated, so that the gate's refusal to a raise can be OBSERVED rather than
  asserted (`gates/corpuslane-mutate.py` does exactly that)."""
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  sys.modules[name] = mod
  spec.loader.exec_module(mod)
  return mod


def instrument(misses: list[tuple[str, str]]):
  """A `__getattr__` recorder on every class the emitter can be handed a value of.

  `Enum` is NOT patched: `EnumMeta` routes member lookup through `__getattr__`, so patching
  it would record every `Ops.CONST` as a miss. Enum coverage is a separate, exhaustive
  `__members__` sweep below, which cannot have that failure because it does not use
  attribute access at all."""
  import tinygrad.dtype as dtm
  import tinygrad.uop.ops as opm
  from tinygrad.device import Buffer, BufferSpec, MultiBuffer

  targets = [("UOp", opm.UOp), ("ParamArg", opm.ParamArg), ("Buffer", Buffer),
             ("BufferSpec", BufferSpec), ("MultiBuffer", MultiBuffer), ("DType", dtm.DType),
             ("AxisType", opm.AxisType), ("AddrSpace", dtm.AddrSpace)]
  for n in ("KernelInfo", "CallInfo", "ProgramInfo", "CustomFunction"):
    if hasattr(opm, n):                       # the class's own declaration, not a hand list
      targets.append((n, getattr(opm, n)))

  def make(label):
    def __getattr__(self, name, _l=label):
      misses.append((_l, name))
      raise AttributeError(name)
    return __getattr__

  for label, cls in targets:
    cls.__getattr__ = make(label)
  return dict(targets)


def control(misses: list, classes: dict, gc) -> tuple[bool, str]:
  """THE POSITIVE CONTROL. Both halves, because either alone is unfalsifiable: a recorder
  that records everything is not a detector, and one that records nothing is not either.

  THE PROBE'S OWN MISS IS REMOVED FROM THE TALLY, and that is not hygiene -- it is the
  failure this gate would otherwise ship. `PROBE` is popped back off `misses` before the
  count is taken, because a control that leaves its own fingerprint in the population makes
  every run FAIL for a reason that has nothing to do with the driver, and a gate that is
  always red is a gate that is not read."""
  PROBE = "zz_not_a_field"
  opm = sys.modules["tinygrad.uop.ops"]
  try:
    opm.ParamArg(0, sys.modules["tinygrad.dtype"].dtypes.int).__getattr__(PROBE)
  except AttributeError:
    fired = ("ParamArg", PROBE) in misses
  else:
    fired = False
  while ("ParamArg", PROBE) in misses: misses.remove(("ParamArg", PROBE))
  quiet = not any(m == PROBE for _, m in misses) and hasattr(opm.UOp, "toposort")
  return (fired and quiet), f"absent-{'RECORDED' if fired else 'MISSED'} present-{'QUIET' if quiet else 'NOISY'}"


def enum_sweep(gc, src: str) -> list[str]:
  """Every `Ops.X` the driver SPELLS IN CODE, asked of the enum's own `__members__`.

  TWO INSTRUMENTS WERE WRONG HERE BEFORE THIS ONE, AND BOTH ARE THE CLASS `AGENTS.md`
  NAMES. (1) A plain `Ops.` REGEX matches the TAIL of `OptOps.TC`, so it reported `Ops.TC`,
  `Ops.SWAP` and `Ops.PADTO` as GONE -- three members that were never `Ops` at all.
  MEASURED on this file's first draft. (2) ADDING A LOOKBEHIND IS NOT ENOUGH, because a
  regex over SOURCE TEXT also reads COMMENTS: `graphcmp.py:1373` documents
  `UOp(Ops.FLIP, (a,), (0,)).shape` in prose, `FLIP` IS genuinely gone from `Ops`, and a
  sweep that counts the prose reports a member the driver has not read in any executable line
  since the re-vendor. MEASURED: the lookbehind version said `Ops.FLIP` GONE.

  So the population is the parsed SYNTAX TREE's `Ops.<NAME>` attributes, which is neither a
  text shape nor a hand list: a comment and a string literal are not `ast.Attribute` nodes.
  `AGENTS.md` doctrine 1 -- "A BASENAME SHAPE, A SUFFIX SET, AND A HAND LIST ARE NOT
  POPULATIONS." """
  import ast as astmod

  from tinygrad.uop import Ops
  named = set()
  for node in astmod.walk(astmod.parse(src)):
    if (isinstance(node, astmod.Attribute) and isinstance(node.value, astmod.Name)
        and node.value.id == "Ops" and node.attr.isupper()):
      named.add(node.attr)
  return [f"Ops.{m}" for m in sorted(named) if m not in Ops.__members__]


def size_refusals(gc) -> int:
  """HOW OFTEN `size_of`'s `isinstance(src[0], int)` ARM FIRES. It is kept as a named refusal
  rather than an assumption, so it needs a denominator: a counter printed by the run that
  could hit it is a measurement, and a comment is a claim."""
  n = 0
  for g in sorted(gc.GRAPHS):
    ast = gc.base(g)
    for node in ast.toposort(enter_calls=True):
      if not isinstance(getattr(node, "arg", None), gc.ParamArg): continue
      src = node.src[0].as_shape if len(node.src) else ()
      if src and not isinstance(src[0], int): n += 1
  return n


def main() -> int:
  ap = argparse.ArgumentParser(prog=__file__.split("/")[-1], description=__doc__,
                               formatter_class=argparse.RawDescriptionHelpFormatter)
  ap.add_argument("--driver", type=pathlib.Path, default=DRIVER)
  ap.add_argument("--rows", type=pathlib.Path, default=None)
  a = ap.parse_args()
  os.environ.update(DEV=DEV, SPEC=SPEC)

  rows: list[str] = []

  def emit(name: str, **kv) -> None:
    rows.append("\t".join([name] + [f"{k}={v}" for k, v in kv.items()]))

  if not a.driver.exists():
    emit("driver", **{STATE: "REFUSED", TOK: "NO-TOKEN?NOTOKEN", "rows": 0, "why": "absent"})
    print("corpuslane-gate: REFUSED -- driver absent; this gate measured nothing")
    return REFUSED

  gc = load(a.driver, "corpuslane_driver")
  gc.load_tinygrad()
  misses: list[tuple[str, str]] = []
  classes = instrument(misses)
  ok, note = control(misses, classes, gc)
  emit("control", **{STATE: "OK" if ok else "REFUSED", TOK: "NOTOKEN?NOTOKEN", "note": note})
  if not ok:
    print(f"corpuslane-gate: REFUSED -- the miss-detector is not a detector ({note}); "
          f"a clean zero from it would be a zero over nothing")
    return REFUSED

  tally: collections.Counter = collections.Counter()
  for g in sorted(gc.GRAPHS):
    try:
      n, st, note = len(gc.emit_py(g, None)), "OK", ""
    except BaseException as e:                       # a raiser is a FAIL, never a pass
      n, st, note = 0, f"RAISE:{type(e).__name__}", " ".join(str(e).split())[:110]
    tally[st] += 1
    emit(f"graph.{g}", **{STATE: st, "rows": n, **({"why": note} if st != "OK" else {})})

  # PLANTS, OFF `differ`'s OWN DECLARATION -- `checks/differ.py:230` names which plant runs
  # on which graph, and that is the generator's declaration, so it is loaded by path and read.
  differ = load(ROOT / "checks" / "differ.py", "corpuslane_differ")
  for plant, g in differ.PLANTS:
    try:
      n, st = len(gc.emit_py(g, plant)), "OK"
    except BaseException as e:
      n, st, note = 0, f"RAISE:{type(e).__name__}", " ".join(str(e).split())[:110]
    tally[st] += 1
    emit(f"plant.{plant}", **{STATE: st, "rows": n, "graph": g,
                              **({"why": note} if st != "OK" else {})})

  declared = {p for p, _ in differ.PLANTS}
  for plant in sorted(set(gc.PLANTS) - declared):
    try:
      n, st = len(gc.emit_py("bw", plant)), "OK"
    except BaseException as e:
      n, st, note = 0, f"RAISE:{type(e).__name__}", " ".join(str(e).split())[:110]
    tally[st] += 1
    emit(f"unwired.{plant}", **{STATE: st, "rows": n, "graph": "bw",
                                **({"why": note} if st != "OK" else {})})

  gone = enum_sweep(gc, a.driver.read_text())
  emit("enum", **{STATE: "FAIL" if gone else "OK", "gone": ",".join(gone) or "-",
                 "members": len(list(sys.modules["tinygrad.uop"].Ops))})
  refusals = size_refusals(gc)
  emit("size_of", **{STATE: "OK", "symbolic-refusals": refusals})
  for label, name in sorted(set(misses)):
    emit(f"missing.{label}.{name}", **{STATE: "FAIL"})

  n_rows = tally["OK"]
  totals = "\n".join(f"{k}={v}" for k, v in sorted(tally.items()))
  body = (f"# corpuslane-gate.rows -- GENERATED by `gates/corpuslane-gate.py`, which is its\n"
          f"# ONLY writer. One TAB-separated `name=value` record per lane run: `<name>\\t<state>"
          f"\\t<rows>\\t<key>=<value>...`, i.e. the state AND the row count of every graph and\n"
          f"# plant. `state` is OK or `RAISE:<type>`; a raiser is a FAIL and is never a pass.\n"
          f"# driver={a.driver}\n{totals}\nmissing-attrs={len(set(misses))}\n"
          f"enum-gone={len(gone)}\nsymbolic-refusals={refusals}\n" + "\n".join(rows))
  ART.mkdir(parents=True, exist_ok=True)
  (ART / "corpuslane.rows").write_text(body)
  if a.rows: a.rows.write_text(body)
  for ln in rows:
    if f"{STATE}=OK" not in ln or "control" in ln: print(ln)

  if not rows:                                   # it ran and emitted nothing
    print(f"corpuslane-gate: {verdict_of(DEAD)} -- no rows")
    return DEAD
  bad = sum(v for k, v in tally.items() if k != "OK") + len(set(misses)) + len(gone)
  if bad:
    print(f"corpuslane-gate: {verdict_of(FAIL)} -- {bad} of {n_rows + bad} lane runs did not "
          f"produce rows; {len(set(misses))} missing attrs; {len(gone)} Ops members gone")
    return FAIL
  print(f"corpuslane-gate: PASS -- {n_rows} lane runs produced rows, "
        f"{len(gc.GRAPHS)} graphs + {len(differ.PLANTS)} declared plants + "
        f"{len(set(gc.PLANTS) - declared)} unwired plants, 0 missing attrs, "
        f"{len(list(sys.modules['tinygrad.uop'].Ops))} Ops members, "
        f"{refusals} symbolic size refusals")
  return PASS


if __name__ == "__main__":
  sys.exit(main())