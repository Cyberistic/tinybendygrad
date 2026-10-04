#!/usr/bin/env python3
"""al-transcription.py -- IS EVERY CLAIM IN `ops.bend`'s `Arg` TABLE TRUE OF UPSTREAM?

The defect: `ops.bend`'s table read `tuple[int, ...]  ATuple  PERMUTE/FLIP arg, UNSHARD arg,
MSELECT arg, PYLITERAL arg`, and THREE of those four ops do not have a tuple-of-ints arg:
`FLIP`'s is `tuple[bool, ...]` (`movement.py:253`), `MSELECT`'s is a bare `int`
(`ops.py:769`), and `PYLITERAL`'s is "a Python literal" (`uop/__init__.py:101`) -- one `Ops`,
a `DType`, a `str` or `self.arg`. ONE LINE, THREE FALSE CLAIMS, and `graphcmp.py` QUOTED it
as the warrant for its own `--plant bool` refusal, so the lie was load-bearing twice over.

THE ORACLE IS UPSTREAM'S OWN CODE, AND EVERY VALUE IS BUILT BY CALLING IT. **This is the
whole design and it is the correction of a defect in my own first draft of this file:** the
first version constructed each node itself -- `UOp(Ops.FLIP, src=(), arg=(0,2,1))` -- and
asked whether that arg was a tuple of ints, which it is BY CONSTRUCTION. **The plant
survived it and printed `ATuple FLIP TRUE`.** A check that feeds the code under test its own
input cannot fail, and `agent-core.md`'s "generate every expectation BY CALLING CPYTHON" is
the same rule: the FLIP row now comes from `Tensor.flip`, and it prints `(True, False)`.

WHAT IS CHECKED, per op the TABLE NAMES (read off the file, so planting a row fires this):
  * the op is REACHED in a real upstream graph, and
  * its arg's shape is the shape the constructor's row claims.
An op the table names that no real graph reaches is printed `UNREACHED` and is NOT counted
as a pass -- an unreachable row cannot fail, so it is reported as what it is.
`AStr`/SPECIAL is deliberately ABSENT: no graph here builds a SPECIAL, so a row for it
would be exactly that.

PLANTED AND MEASURED, in `al-transcription-run0.txt`:
  corrected table -> 0 false claims, 0 unreached;  planted table -> 3, and it names FLIP.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/arglit/al-transcription.py
    ... al-transcription.py .agents/slop/arglit/ops-PLANT.bend    # the plant
"""
from __future__ import annotations

import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
TABLE = os.path.join(REPO, "tinybendygrad/uop/ops.bend")
if len(sys.argv) > 1:
  TABLE = sys.argv[1]  # the PLANT points this at a COPY, never at the live file
sys.path.insert(0, REPO)
os.environ["DEV"] = "CPU"

import re  # noqa: E402

from tinygrad import Tensor, dtypes  # noqa: E402
from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402

ROW = re.compile(r"^#\s+(\S.*?)\s{2,}(A\w+)\s{2,}(.*)$")


def table_claims() -> dict[str, list[str]]:
  """`{constructor: [ops the table names under it]}`, read OFF the file under test."""
  out: dict[str, list[str]] = {}
  inblock = False
  for ln in open(TABLE).read().splitlines():
    if ln.startswith("# `Any` is Python's way"):
      inblock = True
      continue
    if inblock and ln.startswith("# WHAT WE GAIN"):
      break
    if not inblock:
      continue
    m = ROW.match(ln)
    if m:
      out.setdefault(m.group(2), []).extend(re.findall(r"[A-Z][A-Z_]{2,}", m.group(3)))
  return out


def is_op(name: str) -> bool:
  """A name in the ops column counts as an op only if it IS an `Ops` member. The column is
  free prose -- `ABlob`'s row reads "BINARY arg; the BYTES themselves, as a list of", and
  `BYTES` is emphatically not an op. Resolving against `Ops` is also what makes a MISSPELLED
  op visible instead of silently unmatched."""
  return hasattr(Ops, name)


def real_graphs() -> dict[str, list]:
  """Every graph below is BUILT BY UPSTREAM, never assembled here. This dict is the only
  source of `py=` values in this file."""
  g: dict[str, list] = {}
  # `upat.py`'s own pattern IR: the source of the CUSTOM/CUSTOMI/PYLITERAL rows.
  g["pattern"] = list(_get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))
                      .toposort())
  # `movement.py`'s own movement builders: the source of the PERMUTE/FLIP rows.
  g["movement"] = list(Tensor.rand(4, 4).flip(0).uop.toposort())
  # `ops.py:622`'s own `ins` builder: the source of the INS row.
  g["ins"] = list(Tensor.empty(4).uop.ins("nop", dtype=dtypes.void).toposort())
  # `ops.py:769`'s own copy builder: the source of the COPY row.
  g["copy"] = list(Tensor.empty(4).uop.copy_to_device("CPU").toposort())
  return g


def shape_matches(ctor: str, arg) -> bool | None:
  """What each constructor's TABLE ROW claims about its arg, or `None` when this file has
  no rule for that constructor. `None` is NOT a failure and NOT a pass: it is printed
  `no rule` and counted apart, because a check that fires by accident is worse than one
  that does not exist. The claim is the table's own left column, not my memory of it."""
  isint = lambda e: isinstance(e, int) and not isinstance(e, bool)  # noqa: E731
  if ctor == "AInk":  # (str, DType)
    return (isinstance(arg, tuple) and len(arg) == 2 and isinstance(arg[0], str)
            and isinstance(arg[1], type(dtypes.void)))
  if ctor == "ATuple":  # tuple[int, ...]
    return isinstance(arg, tuple) and bool(arg) and all(map(isint, arg))
  if ctor == "AOpLit":  # a bare Ops
    return isinstance(arg, Ops)
  if ctor == "ADev":  # str|tuple
    return isinstance(arg, (str, tuple))
  if ctor == "AStr":  # str
    return isinstance(arg, str)
  return None


def main() -> int:
  claims = table_claims()
  graphs = real_graphs()
  print(f"# table claims, read off {TABLE}")
  for ctor, ops in claims.items():
    print(f"#   {ctor:<9} {sorted(set(ops))}")
  print(f"#\n# real upstream graphs built: {sum(len(v) for v in graphs.values())} nodes"
        f" over {len(graphs)} graphs")
  print(f"#\n# {'ctor':<9} {'op':<10} {'measured arg':<28} verdict")
  bad = unreached = norule = 0
  for ctor, ops in claims.items():
    for opname in sorted(set(ops)):
      if not is_op(opname):
        # PROSE, not a claim. `ABlob`'s row says "the BYTES themselves"; that is not an op
        # and its absence from `Ops` is the proof. Counting it FALSE would be a gate that
        # cries wolf on a correct table.
        norule += 1
        continue
      op = getattr(Ops, opname)
      args = [n.arg for g in graphs.values() for n in g if n.op is op]
      if not args:
        print(f"  {ctor:<9} {opname:<10} {'-':<28} UNREACHED  (a row that cannot fire)")
        unreached += 1
        continue
      verdicts = {shape_matches(ctor, a) for a in args}
      if verdicts == {None}:
        print(f"  {ctor:<9} {opname:<10} {repr(args[0])[:28]:<28} no rule  (not judged)")
        norule += len(args)
        continue
      for a in args:
        ok = shape_matches(ctor, a)
        shown = repr(a) if len(repr(a)) < 28 else repr(a)[:25] + "..."
        print(f"  {ctor:<9} {opname:<10} {shown:<28} {'TRUE ' if ok else 'FALSE'}")
        bad += 0 if ok else 1
  print(f"# {bad} false claim(s), {unreached} unreached, {norule} judged by no rule")
  # THE PLANT FIRES HERE: the planted table gives >= 1, measured in al-transcription-run0.txt.
  return 0 if bad == 0 else 1


if __name__ == "__main__":
  sys.exit(main())
