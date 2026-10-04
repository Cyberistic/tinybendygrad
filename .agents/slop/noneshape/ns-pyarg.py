#!/usr/bin/env python3
"""ns-pyarg.py -- WHAT A BARE `Op` AND A `(str, DType)` PAIR PRINT, ON THE PY SIDE.

The question `Arg` raises, asked of CPython rather than of the port:

  A. `carg` has ELEVEN per-op arms and NONE of them is CUSTOM/CUSTOMI, so
     `arg=("{0}.op is {1}", dtypes.void)` falls to the GENERIC `_carg` tuple grammar
     `n(...)`. `graphcmp.bend`'s `argstr` prints the SAME value as `in(...)`, under INS's
     prefix, because the port's `AInk{ins, dt}` IS the pair (uop/spec.bend:1043-1047).
     Both sides are self-consistent and they disagree, so one of them is wrong and the
     question is WHICH.

  B. A bare `Ops` -- `upat.py:26`'s `UOp(Ops.PYLITERAL, arg=self.op[0])` -- is the py
     side's own atom `OADD`. The port has NO `Arg` constructor that holds an unpaired
     `Op`, so the cshape probe spelled it `AReduce{OpsADD, 0}` and got `rd(OADD,i0)`.
     Measured here: what CPython prints, for all FOUR literals `upat.py` actually builds.

  C. `frozenset(...)` -- `upat.py:25/36/43`, the multi-op / multi-dtype / multi-tag arm.
     Measured because it is the case a bare-`Op` variant would ALSO have to cover, and
     because a `frozenset` is neither `tuple` nor `list`.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/noneshape/ns-pyarg.py
"""
from __future__ import annotations

import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
sys.path.insert(0, REPO)
sys.path.insert(0, SLOP)
os.environ["DEV"] = "CPU"

import graphcmp as G  # noqa: E402

G.load_tinygrad()

from tinygrad.uop.ops import UOp, UPat, Ops, AxisType  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad import dtypes  # noqa: E402


def pl(arg, name):
  u = UOp(Ops.PYLITERAL, src=(), arg=arg)
  return f"  PYLITERAL {name:<34} arg_str={G.carg(Ops.PYLITERAL, arg):<28} _shape={u._shape!r}"


def custom(arg, src=(), name=""):
  u = UOp(Ops.CUSTOM, src=src, arg=arg)
  return (f"  CUSTOM    {name:<34} arg_str={G.carg(Ops.CUSTOM, arg):<28} "
          f"dtype={u.dtype.name:<8} _shape={u._shape!r}")


def main() -> int:
  print("# ==== A. THE `(str, DType)` PAIR: `carg`'s arms vs `argstr`'s ====")
  print(f"  carg has an arm for CUSTOM/CUSTOMI: "
        f"{'CUSTOM' in G.carg.__code__.co_names or 'CUSTOMI' in G.carg.__code__.co_consts}")
  print(f"  carg's op arms: {[n for n in G.carg.__code__.co_names if n.startswith('Ops')]}")
  ins = ("ins+[rd_idx=0]", dtypes.uint32)
  print(custom(("{0}.op is {1}", dtypes.void), name="arg=('{0}.op is {1}', void)"))
  print(custom(("tu0", dtypes.uint32), name="arg=('tu0', uint32)"))
  print(f"  the SAME value, printed by three writers:")
  print(f"    graphcmp.py  carg(CUSTOM, ('{{0}}.op is {{1}}', void)) = "
        f"{G.carg(Ops.CUSTOM, ('{0}.op is {1}', dtypes.void))}")
  print(f"    graphcmp.py  carg(INS,     ('{{0}}.op is {{1}}', void)) = "
        f"{G.carg(Ops.INS, ('{0}.op is {1}', dtypes.void))}")
  print(f"    graphcmp.bend argstr(AInk)   is the literal  in({G.bstr('{0}.op is {1}')},Dvoid)")
  print(f"  so one value has THREE py-side spellings and ONE bend-side spelling, and the")
  print(f"  bend side's own docstring for `carg` says it \"mirrors `argstr` in")
  print(f"  graphcmp.bend character for character\". MEASURED: it does not.")

  print("\n# ==== B. A BARE `Op`, ALL FOUR LITERALS `upat.py` BUILDS ====")
  print(pl(Ops.ADD, "upat.py:26  self.op[0]"))
  print(pl(dtypes.f32, "upat.py:39  self.match_dtype[0]"))
  print(pl("WEAK", "upat.py:44  self.match_tag[0]  (a str, NOT a Tag class)"))
  print(pl(AxisType.GLOBAL, "an AxisType, for the enum arm's reach"))
  print(pl(("a", dtypes.void), "upat.py:29  self.arg (a tuple)"))

  print("\n# ==== C. THE MULTI-ARM LITERALS, `frozenset(...)` ====")
  for arg, name in ((frozenset([Ops.ADD, Ops.MUL]), "upat.py:25  frozenset(self.op)"),
                    (frozenset([dtypes.f32]), "upat.py:36  frozenset(self.match_dtype)")):
    try:
      s = G.carg(Ops.PYLITERAL, arg)
    except Exception as e:  # noqa: BLE001 -- the refusal IS the measurement
      s = f"!! DIED {type(e).__name__}: {e}"
    print(f"  PYLITERAL {name:<34} arg_str={s}")

  print("\n# ==== D. THE FULL UPSTREAM PATTERN IR, `_get_clause` AT upat.py:66 ====")
  for label, pat in (("cshape's graph: UPat(Ops.ADD) + a name", UPat(Ops.ADD, name="x")),
                     ("richer: UPat(Ops.ADD, src=UPat(Ops.MUL), name='x')",
                      UPat(Ops.ADD, src=UPat(Ops.MUL), name="x"))):
    print(f"  -- {label}")
    ir = _get_clause(pat, UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))
    for i, u in enumerate(ir.toposort()):
      print(f"  {i+1}:{u.op.name:<10} nsrc={len(u.src)} dtype={u.dtype.name:<8} "
            f"arg={G.carg(u.op, u.arg):<30} _shape={_shape_of(u)}")
  print("  NOTE the last row's `_shape` is upstream REFUSING at ops.py:444 (the AND), not")
  print("  answering -- the third blocker, which is upstream's assert and NOT widened here.")

  print("\n# ==== E. `_shape` FOR A void AND A NON-VOID CUSTOM, THE ops.py:370-372 SPLIT ====")
  v = UOp(Ops.CUSTOM, src=(), arg=("x", dtypes.void))
  print(f"  CUSTOM dtype=void        : arg_str={G.carg(Ops.CUSTOM, v.arg):<26} "
        f"_shape={v._shape!r}  shape-raises={_raises(v)}")
  n = UOp(Ops.CUSTOM, src=(), arg=("x", dtypes.uint32))
  print(f"  CUSTOM dtype=uint32, 0src: arg_str={G.carg(Ops.CUSTOM, n.arg):<26} "
        f"_shape={n._shape!r}  shape-raises={_raises(n)}")
  c = UOp.const((4, 3))
  s1 = UOp(Ops.CUSTOM, src=(c,), arg=("x", dtypes.uint32))
  print(f"  CUSTOM dtype=uint32, 1 SRC: arg_str={G.carg(Ops.CUSTOM, s1.arg):<26} "
        f"_shape={s1._shape!r}  shape-raises={_raises(s1)}")
  v2 = UOp(Ops.CUSTOM, src=(c,), arg=("x", dtypes.void))
  print(f"  CUSTOM dtype=void,   1 SRC: arg_str={G.carg(Ops.CUSTOM, v2.arg):<26} "
        f"_shape={v2._shape!r}  shape-raises={_raises(v2)}")
  sh = UOp(Ops.CUSTOM, src=(UOp(Ops.CUSTOMI, arg=("y", dtypes.void)), c), arg=("x", dtypes.uint32))
  print(f"  CUSTOM uint32, SHAPELESS+shaped src (upstream FILTERS at ops.py:372): "
        f"_shape={sh._shape!r}")
  return 0


def _shape_of(u):
  try:
    return repr(u._shape)
  except AssertionError as e:
    return f"!! REFUSED ops.py:444 {e}"


def _raises(u) -> bool:
  try:
    u.shape
    return False
  except Exception:  # noqa: BLE001
    return True


if __name__ == "__main__":
  sys.exit(main())