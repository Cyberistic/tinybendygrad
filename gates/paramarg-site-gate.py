#!/usr/bin/env python3
"""paramarg-site-gate.py -- does every `ParamArg(...)` in THIS TREE still spell a field
upstream has?

    .venv/bin/python gates/paramarg-site-gate.py

WHY IT IS NOT A `gatekit.Gate`. A `Gate` is a `.bend` driver against one CPython oracle,
diffed. This has NO `.bend` half and must not be given one: its subject is whether the
tree's own ORACLES can be CONSTRUCTED at all, and the port cannot answer that by existing.
`gates/corpuslane-gate.py:49-53` records the same conclusion for the same reason. So the
five verdicts are `gatekit`'s, IMPORTED rather than re-spelled, and the rows are `name=value`.

THE POPULATION IS DISCOVERED, TWICE, AND NEVER LISTED.

  1. THE FIELDS COME FROM THE CLASS. `LIVE` is `dataclasses.fields(ParamArg)` read off
     `tinygrad.uop.ops` AT RUN TIME. Nothing here names `size`, so the next re-vendor that
     deletes a field is caught with no edit to this file -- which is the whole point, and is
     what `checks/no-txt.py` does with `differ.declared()`.
  2. THE SITES COME FROM A DIRECTORY WALK. `os.walk` over `ROOTS`, every `.py`, parsed with
     `ast`. A BASENAME SHAPE OR A HAND LIST IS NOT A POPULATION (`AGENTS.md` doctrine 1) --
     `gates/gates-pop.py:95`'s `HOMES` is the named instance of that failure. ROOTS is the
     only thing written down, and it is the place the walk starts, not what it finds.

THE VACATED SLOT IS READ FROM THE PIN, NOT REMEMBERED. Upstream `72f98ffe0` -- "move size
from ParamArg to src (#18624)", George Hotz, 2026-10-06 -- DELETED a field and moved the
value into `src[0]`. WHICH field, and WHERE it sat, is read by running `git show` at
`--pin`. A pin that does not resolve is `REFUSED`, never a silent fallback to a default,
because a gate that guesses its own denominator reports a clean tree over nothing.

THE CLASS IS NOT "THE `size=` KEYWORD". IT IS A VACATED POSITIONAL SLOT, and it fails in
THREE ways, all three re-derived here and none transcribed:

  KEYWORD   `ParamArg(0, dt, size=4)`  -> `TypeError`, rc 1, ZERO bytes of stdout. LOUD.
  POSITIONAL `ParamArg(0, dt, 4)`       -> the value lands on the NEXT field, SILENTLY, and
           a type violation with it: `ParamArg.vmin_vmax` is declared
           `tuple[PyConst,PyConst]|None` and an int is neither. LOUD only when the call
           ALSO passes that field by keyword -- which is what made `realize`'s `_var` a
           `TypeError` while its `_buf_dev` was invisible.
  DELETE    dropping the value entirely -> `src=()`, and MEASURED: `_shape` raises
           `IndexError` AND `f(4) is f(6)`, ONE NODE FOR EVERY SIZE. So the delete is not a
           third option, it is the WORST one, and it is silent.

THE ZERO ROWS ARE THE POINT OF THE FILE. `shape_to_shape_arg(())` is `UOp(Ops.STACK)` whose
`as_shape` is `()`, and `shape_to_shape_arg((0,))` is `UOp(Ops.CONST, arg=0)` whose
`as_shape` is `(0,)`. **A ZERO SIZE IS A DIFFERENT SHAPE, NOT A ZERO.** A fix that defaulted
the size, or that treated `0` as `1`, is right on every other row and wrong on exactly this
one, so the zero is carried as rows on BOTH sides of every one of the three failures.

THE POSITIVE CONTROL IS THE GATE'S MOST IMPORTANT LINE. An instrument that cannot detect
anything reports a clean zero -- the `DEAD` of `gatekit.py:55` wearing a count. So the
classifier is run over PLANTED sites first: one that must FAIL and one that must PASS. A
control that fails is `REFUSED`, not `PASS`, because the gate measured nothing.

A SITE THIS FILE CANNOT JUDGE IS `UNDECIDED`, NOT `PASS`. `npos >= 3` says the call reaches
the vacated slot; whether the value it puts there is a size or a range needs the value. The
ones that are decidable statically are decided, the rest are named and left named.
`corpuslane-gate.py:42-47` records the rule: "A MISSING TOKEN IS NOT A VERDICT."
"""
from __future__ import annotations

import argparse
import ast
import dataclasses
import os
import pathlib
import subprocess
import sys
import warnings

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

# WHERE THE WALK STARTS. Not what it finds: see the header. `test/` is excluded on purpose
# and not by name-glob -- it is upstream tinygrad's own suite, so a `ParamArg(` in it is
# upstream's business and this project's port has no claim on it.
ROOTS = ("gates", "oracles", "checks")
SKIP_DIRS = frozenset({"artifacts", "__pycache__", ".git", ".venv", "references", "node_modules"})
PIN = "72f98ffe0^"          # the commit BEFORE the move; its ParamArg is the old field list


def live_fields() -> list[str]:
  """(1) THE CLASS'S OWN DECLARATION, at run time. Nothing below names a field."""
  from tinygrad.uop.ops import ParamArg
  return [f.name for f in dataclasses.fields(ParamArg)]


def pin_fields(pin: str) -> list[str]:
  """(2) THE VACATED SLOT, read out of the pin's source rather than remembered. A pin that
  does not resolve raises, and the caller turns that into `REFUSED`."""
  src = subprocess.run(["git", "show", f"{pin}:tinygrad/uop/ops.py"], cwd=ROOT,
                       capture_output=True, text=True, check=True).stdout
  body = src.split("class ParamArg:", 1)[1]
  fields = []
  for line in body.splitlines()[1:]:
    line = line.split("#")[0].strip()
    if not line or line.startswith("@") or line.startswith("def "):
      if line.startswith("def "):
        break
      continue
    fields.append(line.split(":")[0].strip())
  return fields


def walk_py(roots=ROOTS):
  """A DIRECTORY WALK, not a glob: `glob('*.py')` returned `[]` on a tree where the files
  existed and were tracked, which is why `AGENTS.md` doctrine 1 admits only os.walk."""
  for r in roots:
    base = ROOT / r
    if not base.is_dir():
      continue
    for dp, dn, fn in os.walk(base):
      dn[:] = sorted(d for d in dn if d not in SKIP_DIRS)
      for f in sorted(fn):
        if f.endswith(".py"):
          yield pathlib.Path(dp) / f


SELF = pathlib.Path(__file__).resolve()   # the instrument is not one of its own sites


def classify(node: ast.Call, live: list[str], vacated: dict[str, int]):
  """ONE `ParamArg(` CALL SITE -> (class, why).

  `vacated` maps each field the pin had and the class no longer has to the POSITIONAL INDEX
  it used to occupy. Both halves come from the two discovered lists above, so a field that
  moves a second time is caught here without an edit to this file."""
  dead_kw = sorted({k.arg for k in node.keywords if k.arg} & set(vacated))
  npos = len(node.args)
  # A call that passes MORE positionals than the vacated index reaches it: `npos > idx`
  # because `args[npos-1]` is the last one given.
  hit = sorted((idx, name) for name, idx in vacated.items() if npos > idx)
  if dead_kw:
    return "KEYWORD-DEAD", f"keyword {dead_kw[0]}= a field the class no longer has"
  if hit:
    idx, name = hit[0]
    return "POS-SHIFT", f"positional #{idx} is where {name} sat, now {live[idx] if idx < len(live) else 'PAST-END'}"
  return "SAFE", f"npos={npos} reaches no vacated slot"


def sites(fields_live: list[str], vacated: dict[str, int]):
  """EVERY SITE, one row each, from every parseable file under ROOTS. A file that does not
  parse is a row too: it is a file the census could not read, and counting it as absent
  would make the denominator smaller than the tree."""
  rows, unread = [], []
  for path in walk_py():
    if path.resolve() == SELF:
      continue                      # the zero rows below are DELIBERATE plants, not sites
    rel = path.relative_to(ROOT)
    try:
      with warnings.catch_warnings():  # a SyntaxWarning in ANOTHER file is that file's noise
        warnings.simplefilter("ignore")
        tree = ast.parse(path.read_text())
    except (SyntaxError, UnicodeDecodeError) as e:
      unread.append(f"{rel}=UNREADABLE:{type(e).__name__}")
      continue
    for node in ast.walk(tree):
      if not isinstance(node, ast.Call):
        continue
      name = getattr(node.func, "attr", None) or getattr(node.func, "id", None)
      if name != "ParamArg":
        continue
      cls, why = classify(node, fields_live, vacated)
      third = ast.unparse(node.args[2]) if len(node.args) > 2 else "-"
      rows.append((f"{rel}:{node.lineno}", cls, why, third))
  return rows, unread


def zero_rows() -> list[tuple[str, str, str]]:
  """THE ZERO AND THE THREE FAILURES, RE-DERIVED. Both lanes are CPython, so no `.bend` is
  involved and none is wanted: what is under test is a SPELLING."""
  from tinygrad.uop.ops import Ops, ParamArg, UOp, shape_to_shape_arg
  from tinygrad.dtype import dtypes
  out = []

  def row(name, fn):
    try:
      out.append((name, "PASS", str(fn())))
    except Exception as e:  # a refusal IS the answer for these three rows
      out.append((name, "RAISES", f"{type(e).__name__}: {e}"))

  # A ZERO SIZE IS A DIFFERENT SHAPE, NOT A ZERO.
  row("zeroshape_stack", lambda: shape_to_shape_arg(()).as_shape)
  row("zeroshape_zero", lambda: shape_to_shape_arg((0,)).as_shape)
  row("zeroshape_equal", lambda: shape_to_shape_arg(()) == shape_to_shape_arg((0,)))
  row("zeroshape_one", lambda: shape_to_shape_arg((0,)).as_shape == shape_to_shape_arg((1,)).as_shape)
  for n in (0, 1, 4):
    row(f"zerobuf_maxnumel_{n}", lambda n=n: UOp._buffer(n, dtypes.float, 0).max_numel())
    row(f"zerobuf_shape_{n}", lambda n=n: UOp._buffer(n, dtypes.float, 0)._shape)
  row("zerobuf_distinct_0_1", lambda: UOp._buffer(0, dtypes.float, 0) is UOp._buffer(1, dtypes.float, 0))
  row("zerobuf_distinct_4_6", lambda: UOp._buffer(4, dtypes.float, 0) is UOp._buffer(6, dtypes.float, 0))

  # FAILURE 1 -- KEYWORD. LOUD. size=0, so the row that fails LOUDLY is ALSO the zero row.
  row("fail_keyword_raises", lambda: ParamArg(0, dtypes.float, size=0))
  # FAILURE 2 -- POSITIONAL. SILENT, and a type violation: vmin_vmax is `tuple|None`.
  row("fail_pos_lands", lambda: repr(ParamArg(0, dtypes.int32, 0).vmin_vmax))
  row("fail_pos_is_tuple", lambda: isinstance(ParamArg(0, dtypes.int32, 0).vmin_vmax, tuple))
  # FAILURE 3 -- DELETE. The trap: one node for every size, and _shape raises.
  dropped = lambda n: UOp(Ops.BUFFER, src=(), arg=ParamArg(0, dtypes.float))  # noqa: E731
  row("fail_delete_same_node", lambda: dropped(4) is dropped(6))
  row("fail_delete_shape", lambda: dropped(0)._shape)
  return out


def control(fields_live, vacated) -> tuple[bool, str]:
  """THE POSITIVE CONTROL. The classifier MUST reject a planted dead keyword and MUST
  accept a planted clean call, or it has measured nothing and its zero is not a result."""
  dead = "def f():\n  return ParamArg(0, dtypes.int32, size=4)\n"
  clean = "def f():\n  return ParamArg(0, dtypes.int32, vmin_vmax=(0, 4), multiple_of=1)\n"
  got_dead = classify(ast.parse(dead).body[0].body[0].value, fields_live, vacated)[0]
  got_clean = classify(ast.parse(clean).body[0].body[0].value, fields_live, vacated)[0]
  if got_dead != "KEYWORD-DEAD" or got_clean != "SAFE":
    return False, f"control misfired: dead={got_dead} clean={got_clean}"
  return True, f"dead->{got_dead} clean->{got_clean}"


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--pin", default=PIN, help="the revision BEFORE the field was moved out")
  a = ap.parse_args()

  live = live_fields()
  try:
    pin = pin_fields(a.pin)
  except (subprocess.CalledProcessError, IndexError, FileNotFoundError) as e:
    print(f"== REFUSED, NOT A VERDICT: the pin {a.pin!r} does not resolve ({e}); this gate "
          f"will not guess which slot was vacated", file=sys.stderr)
    return REFUSED
  vacated = {f: i for i, f in enumerate(pin) if f not in live}

  ok, why = control(live, vacated)
  if not ok:
    print(f"== REFUSED, NOT A VERDICT: the control did not fire, so the census below is "
          f"over an instrument that cannot see anything: {why}", file=sys.stderr)
    return REFUSED

  print(f"live fields ({len(live)})={','.join(live)}")
  print(f"pin {a.pin} fields ({len(pin)})={','.join(pin)}")
  print(f"vacated={vacated}")
  print(f"control={why}")
  print()

  tally = {"KEYWORD-DEAD": 0, "POS-SHIFT": 0, "SAFE": 0}
  rows, unread = sites(live, vacated)
  for name, cls, why_, third in sorted(rows, key=lambda r: (r[1], r[0])):
    tally[cls] = tally.get(cls, 0) + 1
    print(f"{cls} {name} {why_} third={third}")
  for u in unread:
    print(f"UNREADABLE {u}")
  print()
  print(f"census_files={len(list(walk_py()))} sites={len(rows)} unreadable={len(unread)}")
  for k in sorted(tally):
    print(f"  {k}={tally[k]}")
  print()

  ztally = {"PASS": 0, "RAISES": 0}
  for name, verdict, val in zero_rows():
    ztally[verdict] = ztally.get(verdict, 0) + 1
    print(f"zero {name}={val}")
  print(f"  zero_rows_pass={ztally['PASS']} zero_rows_raise={ztally['RAISES']}")

  # `DEAD` IS NOT A ZERO AND NOT A PASS. A walk that finds no `ParamArg(` in three hundred
  # tracked files has stopped seeing its own population, and reporting that as a clean tree
  # is the `DEAD` of `gatekit.py:55` wearing a count. Same for a zero-row zero-case block:
  # every row above is a row that CAN raise, so a block of zero rows means the block did not
  # run. `differ.py`'s `artefacts_ok()` returned zero on a directory holding nothing.
  nfiles = len(list(walk_py()))
  if nfiles == 0 or not rows or not any(True for _ in zero_rows()):
    print(f"== {VERDICT[DEAD]}: files={nfiles} sites={len(rows)} -- the census is not looking "
          f"at a population, so its zero is not a result")
    return DEAD

  # THE VERDICT. A `POS-SHIFT` row is NOT counted as a failure here: `npos >= 3` reaches
  # the vacated slot, but whether the value is a SIZE or a RANGE is a property of the
  # value, and this file does not evaluate it. Claiming otherwise would be a number this
  # instrument did not measure -- which is the defect it exists to catch.
  bad = tally["KEYWORD-DEAD"]
  print(f"== {VERDICT[FAIL if bad else PASS]}: KEYWORD-DEAD={bad} "
        f"POS-SHIFT={tally['POS-SHIFT']} SAFE={tally['SAFE']} "
        f"(POS-SHIFT is UNDECIDED, not PASS)")
  return FAIL if bad else PASS


if __name__ == "__main__":
  sys.exit(main())