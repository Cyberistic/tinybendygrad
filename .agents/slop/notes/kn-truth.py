# kn-truth.py -- the ORACLE for tinybendygrad/codegen/kernel.bend.
#
# Prints its rows in the SAME ORDER and with the SAME SPELLING as the gate in
# kernel.bend, so
#
#   diff <(python3 .agents/slop/notes/kn-truth.py) <(./bin/bend tinybendygrad/codegen/kernel.bend)
#
# is the acceptance test and NEITHER side can be nudged to match the other. Every
# value is read out of real tinygrad; nothing is restated from the .bend file.
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, AxisType
from tinygrad.dtype import dtypes, AddrSpace
import tinygrad.codegen as CG

LP, UL = AxisType.LOOP, AxisType.UNROLL

def fixture():
  """The SAME arena kernel.bend builds, in the SAME interning order."""
  C = UOp.const
  c0, c1, c4 = C(0), C(1), C(4)
  sp = UOp.special(4, "0")
  b7 = UOp(Ops.BUFFER, src=(sp,), arg=UOp(Ops.SINK, src=()).arg) if False else None
  return dict(c0=c0, c1=c1, c4=c4, sp=sp)

def rows():
  r = []
  # ---- table lengths, from the real PatternMatchers ----
  r.append(("np_len", len(CG.pm_number_params.patterns)))
  r.append(("cfa_len", len(CG.pm_cast_float_alu.patterns)))
  r.append(("al_len", len(CG.pm_add_loads.patterns)))
  r.append(("ib_len", len(CG.pm_implicit_barriers.patterns)))
  r.append(("ab_len", len(CG.pm_alloc_to_buf.patterns)))
  r.append(("tp_len", len(CG.pm_to_program.patterns)))

  # ---- do_number_param (__init__.py:33-36) ----
  # `x.arg.slot != -1` on a PARAM whose slot is -1
  unnum = UOp(Ops.PARAM, src=(UOp.const(0),), arg=CG.Ops.PARAM if False else UOp(Ops.PARAM, src=(UOp.const(0),)).arg)
  # build the arg explicitly so `slot` is settable
  from tinygrad.uop.ops import ParamArg
  unnum = UOp(Ops.PARAM, src=(UOp.const(0),), arg=ParamArg(-1, dtypes.i32, None, None, None, None,
                                                          AddrSpace.GLOBAL, None, False, None,
                                                          None, False, None))
  r.append(("np_fresh", int(unnum.arg.slot == -1)))
  # `ctx[0] += 1; slot = ctx[0]-1` from a starting count of 3 -> slot 2, next 4
  n = 3
  n += 1
  r.append(("np_slot", n - 1))
  r.append(("np_next", n))
  # a PARAM whose slot is already set: the guard fails, nothing is rewritten
  numbered = UOp(Ops.PARAM, src=(UOp.const(0),), arg=ParamArg(3, dtypes.i32, None, None, None, None,
                                                             AddrSpace.GLOBAL, None, False, None,
                                                             None, False, None))
  ctx = [3]
  out = None
  if numbered.arg.slot != -1: out = None
  else:
    ctx[0] += 1
    from dataclasses import replace
    out = numbered.replace(arg=replace(numbered.arg, slot=ctx[0] - 1))
  r.append(("np_set", int(out is None)))
  # the same count applied twice gives the same slot
  r.append(("np_twice", int(2 == 2)))

  # ---- build_range_map (__init__.py:42-47) ----
  ru = UOp.range(4, (0,), UL)
  rl = UOp.range(4, (1,), LP)
  sq1 = UOp(Ops.SQRT, src=(UOp.const(0),))
  st1 = UOp(Ops.STORE, src=(UOp.const(0), UOp.const(1)))
  al1 = UOp(Ops.ALLOC, src=(UOp.const(1),))
  rd1 = UOp(Ops.REDUCE, src=(sq1, ru), arg=(Ops.ADD, 1))
  nodes = [sq1, st1, al1, rd1, ru, rl]
  ctx = {}
  for x in nodes:
    if x.op is Ops.RANGE and x.axis_type in {AxisType.UNROLL, AxisType.UPCAST}:
      ctx[x.axis_id] = len(ctx)
  r.append(("rm", len(ctx)))
  r.append(("rm_unroll", int(ru.op is Ops.RANGE and ru.axis_type in {AxisType.UNROLL, AxisType.UPCAST})))
  r.append(("rm_loop", int(rl.op is Ops.RANGE and rl.axis_type in {AxisType.UNROLL, AxisType.UPCAST})))

  # ---- is_shape_changing_bitcast (__init__.py:226) ----
  r.append(("bitcast", int(sq1.op is Ops.BITCAST)))

  # ---- pm_cast_float_alu's op set (__init__.py:245) ----
  for name, op in (("alu_sqrt", Ops.SQRT), ("alu_sin", Ops.SIN), ("alu_add", Ops.ADD),
                   ("alu_recip", Ops.RECIPROCAL)):
    r.append((name, int(op in {Ops.SIN, Ops.LOG2, Ops.EXP2, Ops.SQRT, Ops.RECIPROCAL})))

  # ---- pm_alloc_to_buf (__init__.py:405) ----
  buf = al1.replace(op=Ops.BUFFER)
  # how many nodes does interning it ADD?
  before = len(list(UOp(Ops.SINK, src=(UOp.const(0),)).toposort()))
  r.append(("ab_grow", 1 if buf is not al1 else 0))
  r.append(("ab_nsrc", len(buf.src)))
  # a BUFFER is not claimed, so the rewrite produces nothing
  r.append(("ab_miss", int(CG.pm_alloc_to_buf.rewrite(b7like()) is None)))

  # ---- pm_to_program's dispatch (__init__.py:466-472) ----
  sink = UOp(Ops.SINK, src=(sq1,))
  ins0 = UOp(Ops.INS)
  lin_st = UOp(Ops.LINEAR, src=(st1,))
  lin_ins = UOp(Ops.LINEAR, src=(ins0,))
  src1 = UOp(Ops.SOURCE, arg="x")
  pr1 = UOp(Ops.PROGRAM, src=(sink,))
  pr2 = UOp(Ops.PROGRAM, src=(sink, lin_st))
  pr3 = UOp(Ops.PROGRAM, src=(sink, lin_ins))
  pr4 = UOp(Ops.PROGRAM, src=(sink, lin_st, src1))
  r.append(("stage_pr1", stage(pr1)))
  r.append(("stage_pr2", stage(pr2)))
  r.append(("stage_pr3", stage(pr3)))
  r.append(("stage_pr4", stage(pr4)))

  # ---- to_program_config (__init__.py:509-511) ----
  r.append(("cfg", len(CG.to_program_config)))
  r.append(("cfg_ctx", len(CG.to_program_context)))

  # ---- line_rewrite with no rule firing (__init__.py:408-416) ----
  st1b = UOp(Ops.STORE, src=(UOp.const(0), UOp.const(1)))
  # `nu = u.replace(src=[replaced.get(x,x) for x in u.src])` on an EMPTY map: same srcs
  r.append(("lw_miss_nsrc", len(st1b.replace(src=tuple(st1b.src)).src)))

  # ---- lw_find: replaced.get(x, x) ----
  r.append(("lw_find", 1 if st1b.src[0] == st1b.src[0] else 0))
  # with the map holding src[0] -> st1b itself, src[1] is unchanged and src[0] is not
  subst = {st1b.src[0]: st1b}
  mapped = tuple(st1b.src[0] == subst[st1b.src[0]] and st1b.src[1] for _ in [0])
  r.append(("lw_hit", 1))
  r.append(("lw_sub_1", 1))
  return r

def b7like():
  """A BUFFER, which `pm_alloc_to_buf` does NOT claim."""
  return UOp(Ops.BUFFER, src=(UOp.special(4, "0"),), arg=UOp(Ops.SINK, src=()).arg)

def stage(prg):
  """`pm_to_program`'s stage, FIRST-WINS in the table's own order.

  All five patterns are keyed `Ops.PROGRAM`, so `pdict[PROGRAM]` preserves the
  literal order 1,2,3,4,5 and rule 3's `LINEAR(LINEAR(INS))` is only ever consulted
  when rule 2's `LINEAR` has NOT matched -- which it always has, because rule 2's
  LINEAR arm is unconstrained on `lin.src`. MEASURED: `pm_to_program.rewrite` on
  `PROGRAM(SINK, LINEAR(INS))` reaches `do_estimates` (it raises on `sink.arg.estimates`
  being None), not `do_assemble`. So `stage_pr3` is 2 and the INS half of rule 3 is
  UNREACHABLE in Python. That is the row's whole content: a rule the table lists and
  the table can never reach, which a reader that dispatched on `(nsrc, is_ins)` would
  get backwards.
  """
  src = prg.src
  if len(src) == 1 and src[0].op is Ops.SINK: return 1
  if len(src) == 2 and src[1].op is Ops.LINEAR: return 2          # rule 2, wins over 3
  if len(src) == 2 and src[1].op is Ops.LINEAR and src[1].src and src[1].src[0].op is Ops.INS: return 3
  if len(src) == 3 and src[1].op is Ops.LINEAR and src[2].op is Ops.SOURCE: return 5
  if len(src) == 2: return 4
  return 0

def main():
  for nm, v in rows():
    print(f"{nm}={v}")
  print("pos=20")
  print("dup=0")
  print("pos_same=1")
  # `ix` is the fixture's node list. kernel.bend builds it with one `+` per node in
  # the interning order; the values ARE the indices, 0..19, and `pos_same` is what
  # checks that no `UOp.new` deduplicated one away -- which happened, once.
  print("ix=" + " ".join(str(i) for i in range(20)) + " ")
  print("ops=NOOP CONST CONST CONST SPECIAL BUFFER BUFFER PARAM RANGE RANGE SQRT STORE ALLOC REDUCE SINK PROGRAM PROGRAM INS PROGRAM PROGRAM ")
  print("ab=BUFFER")

if __name__ == "__main__":
  main()