#!/usr/bin/env python3
"""ns-revert.py -- RECONSTRUCT the pre-fix `fold.bend` by reversing this unit's THREE
edits, and PROVE the reconstruction exact by md5 against the pin CSHAPE recorded
(`e372ca226461fe2295b49a9990db0165`) and by the md5 recorded at this unit's first read.

Reverse-the-edit plus an md5 is the honest way to take a baseline out of a file you have
already changed: it fails loudly if a sixth edit crept in, and it needs no VCS checkout of
a file six other units are reading. The pin is the proof; without it this is a claim.

    env -u PYTHONPATH .venv/bin/python .agents/slop/noneshape/ns-revert.py fold.bend
"""
from __future__ import annotations

import hashlib
import sys

PIN = "e372ca226461fe2295b49a9990db0165"

# each entry: (name, the text this unit INSERTED, the text that was there before)
EDITS = [
  ("some_shapes", '''# `input_shapes = [x._shape for x in self.src if x._shape is not None]` -- ops.py:372,
# the FILTER, where `all_shapes` above is the `assert` that refuses the same list for the
# Broadcastable arm. One line's difference between the two walks and the whole arm:
# `shapes_of.acc` turns a shapeless src into the OUTER `None` (no `Derived` at all), and
# this one KEEPS the accumulator and carries on. A CUSTOM over a shapeless src and a
# shaped one is `(2,)` upstream, and `all_shapes` would refuse it.
def some_shapes.put(+ds: List<&2, O.Sint>, +acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  match acc:
    case None{}: None{}
    case Some{sh}: Some{shapes_of.put(sized(ds), sh)}

def some_shapes.acc2(+acc: Maybe<&2, Shapes>, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, Shapes>:
  match m:
    case None{}: acc
    case Some{ds}: some_shapes.put(ds, acc)

def some_shapes.go(ss: List<&2, Derived>, +acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  match ss:
    case Nil{}: acc
    case d <> t: some_shapes.go(t, some_shapes.acc2(acc, Derived.shape(d)))

def some_shapes(+ss: List<&2, Derived>) -> Maybe<&2, Shapes>:
  some_shapes.go(ss, Some{Shapes{Nil{}, 0n}})

''', ""),
  ("custom_ds", '''
# CUSTOM | CUSTOMI -- ops.py:136-138 for the dtype and ops.py:370-372 for the shape:
#   if self.dtype is dtypes.void: return None
#   input_shapes = [x._shape for x in self.src if x._shape is not None]
#   return _broadcast_shape(*input_shapes) if input_shapes else None
# BOTH `None`s mean THE SAME THING -- "NO SHAPE" -- and they are TWO PROOFS of it, which
# is why the arm has two lines and not one. Measured on CPython, `_agents/slop/noneshape/
# pyarg-run0.txt` §E, all five rows settled=True there:
#   void,  no srcs        -> None        line 1
#   u32,   no srcs        -> None        line 3 (`input_shapes` is empty)
#   u32,   1 shaped src   -> (2,)        line 2, the broadcast
#   u32,   shapeless+shaped -> (2,)      line 2 FILTERS the shapeless src
#   void,  1 shaped src   -> None        line 1 runs FIRST; the srcs are never read
# So the void arm is `cfun_ds.shape`'s void arm (ops.py:374 is the same test, and ops.py:371
# is the same line), and it is `late()` again; and the else arm is `bcast_shape` over
# `some_shapes`, whose empty answer is the line-3 `None`.
#
# WHAT THIS IS NOT, and it is the defect this arm carried until 2026-10-05: the outer
# `None` is the PORT-ONLY "the fold produced no `Derived`", which the differ spells `?`
# (`graphcmp.bend`'s `shape_str`), while "no shape" is `Some{None{}}` -> `R`. Answering
# the outer `None` here made a node upstream is HAPPY to describe read as a node the port
# knows nothing about, which is the `?`/`R` conflation one level down in the ladder.
def custom_ds.of(+dt: S.Dt, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match dt:
    case S.Dt{_, _, S.CVoid{}, _}: late()
    case _: Some{DtShape{dt, bcast_shape(some_shapes(ss))}}

def custom_ds.pick(m: Maybe<&1, S.Dt>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: custom_ds.of(dt, ss)
    # `assert isinstance(arg, tuple) and len(arg) == 2 and isinstance(arg[1], DType)`
    # (ops.py:137) -- a WRONG FIXTURE rather than a shapeless op, so this stays a refusal
    # and does not join the void/broadcast answer. `uop/spec.bend` gates CUSTOM and
    # CUSTOMI on `AInk` for the same reason.
    case None{}: None{}

def custom_ds(arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  custom_ds.pick(ins_dt(arg), ss)
''', ""),
  ("ladder", '''# THE DEFERRED OPS, and there are now only TWO of them -- the five movement arms
    # this unit added are `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`, `flip_ds`
    # above, and CUSTOM/CUSTOMI left on 2026-10-05 (see `custom_ds`). Each is an arm
    # `dtype_from_uop` or `_shape` reaches through a rule this
    # file does not port, so the fold does not answer the node. The list is closed:
    # every other op has an arm above, which is what makes the match total without
    # Python's closing `raise RuntimeError(f"no dtype for {op} with arg {arg}")`.
    # THE BLOCKER RECORDED ON THE NEXT TWO ARMS WAS WRONG TWICE. Corrected 2026-10-03,
    # and the second correction is 2026-10-05. The first said "the arena's CUSTOM arg is
    # a str (ops.bend's `Arg`), not the `(str, DType)` pair. P3: that is a change to
    # `Arg`." BOTH halves are false:
    #   * ops.py:137 ASSERTS the pair -- `isinstance(arg, tuple) and len(arg) == 2 and
    #     isinstance(arg[1], DType), "CUSTOM/CUSTOMI arg must be (str, DType)"` -- and
    #     the assert FIRES on a bare string. Every real construction site is a pair
    #     (`tinygrad/uop/upat.py:33`, `tinygrad/llm/kernels/amd.py:108`), and
    #     `tinygrad/renderer/cstyle.py:76` reads `x.arg[0].format(...)`, which is only
    #     meaningful on index 0 OF A 2-TUPLE.
    #   * NO change to `Arg` is needed. `AInk{ins: String, dt: S.Dt}` (ops.bend:940,
    #     mapped to the INS arg at :910) IS that pair, and `uop/spec.bend:1043-1047`
    #     already gates CUSTOM and CUSTOMI on it: "`AInk` IS that pair, and it is the
    #     only constructor that is".
    # The second correction: the note below claimed the arm needed "its own
    # `_broadcast_shape` oracle and its own rows" and left BOTH HALVES parked for it. The
    # void half needs neither -- it is ops.py:371, `if self.dtype is dtypes.void: return
    # None`, which is `cfun_ds.shape`'s void arm verbatim, and `_broadcast_shape` was
    # already here as `where_ds` and `alu_ds` use it. The claim also called the shape half
    # "`all_shapes` + `bcast_shape`", and THAT is the half that was wrong: ops.py:372
    # FILTERS the shapeless srcs out (`[x._shape for x in self.src if x._shape is not
    # None]`) where `all_shapes` is the Broadcastable arm's `assert`. So the arm wanted a
    # second walk, not a second oracle, and it now has one: `some_shapes`.
    case O.OpsCUSTOM{}: custom_ds(arg, ss)
    case O.OpsCUSTOMI{}: custom_ds(arg, ss)
    case O.OpsSTAGE{}: None{}''', '''# THE DEFERRED OPS, and there are now only THREE of them -- the five movement arms
    # this unit added are `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`, `flip_ds`
    # above. Each is an arm `dtype_from_uop` or `_shape` reaches through a rule this
    # file does not port, so the fold does not answer the node. The list is closed:
    # every other op has an arm above, which is what makes the match total without
    # Python's closing `raise RuntimeError(f"no dtype for {op} with arg {arg}")`.
    # THE BLOCKER RECORDED ON THE NEXT TWO ARMS WAS WRONG, CORRECTED 2026-10-03. It
    # said "the arena's CUSTOM arg is a str (ops.bend's `Arg`), not the `(str, DType)`
    # pair. P3: that is a change to `Arg`." BOTH halves are false:
    #   * ops.py:137 ASSERTS the pair -- `isinstance(arg, tuple) and len(arg) == 2 and
    #     isinstance(arg[1], DType), "CUSTOM/CUSTOMI arg must be (str, DType)"` -- and
    #     the assert FIRES on a bare string. Every real construction site is a pair
    #     (`tinygrad/uop/upat.py:33`, `tinygrad/llm/kernels/amd.py:108`), and
    #     `tinygrad/renderer/cstyle.py:76` reads `x.arg[0].format(...)`, which is only
    #     meaningful on index 0 OF A 2-TUPLE.
    #   * NO change to `Arg` is needed. `AInk{ins: String, dt: S.Dt}` (ops.bend:940,
    #     mapped to the INS arg at :910) IS that pair, and `uop/spec.bend:1043-1047`
    #     already gates CUSTOM and CUSTOMI on it: "`AInk` IS that pair, and it is the
    #     only constructor that is".
    # So the dtype half is `adt_dt`'s pattern on `AInk` and the shape half is
    # `all_shapes` + `bcast_shape`, both already here as `where_ds` uses them. NOT
    # PORTED, deliberately: it needs its own `_broadcast_shape` oracle and its own
    # rows, and porting an unoracled shape rule is the plausible-wrong-answer class.
    # What was wrong was the REASON, and the reason is what kept the arm parked.
    case O.OpsCUSTOM{}: None{}        # `arg[1]`, then `if void: None` else the
    case O.OpsCUSTOMI{}: None{}       #   broadcast of the srcs' non-None shapes
    case O.OpsSTAGE{}: None{}'''),
]


def main() -> int:
  src = open(sys.argv[1]).read()
  for name, new, old in EDITS:
    if src.count(new) != 1:
      print(f"FAIL edit {name}: inserted text found {src.count(new)}x, need exactly 1")
      return 1
    src = src.replace(new, old, 1)
  got = hashlib.md5(src.encode()).hexdigest()
  print(f"reconstructed md5 {got}   pin {PIN}   EXACT={got == PIN}")
  if got == PIN:
    open(sys.argv[2], "w").write(src)
    print(f"wrote {sys.argv[2]}")
  return 0 if got == PIN else 1


if __name__ == "__main__":
  sys.exit(main())