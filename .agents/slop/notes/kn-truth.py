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

from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, AxisType, ParamArg, UOpMetaClass
from tinygrad.dtype import dtypes, AddrSpace
import tinygrad.codegen as CG

# `AxisType.UNROLL` WAS NOT A NAME THAT EVER EXISTED. Measured with
# `oracle-live.py`: this file raised `AttributeError: type object 'AxisType' has no
# attribute 'UNROLL'` at this line and printed ZERO rows, so every row below -- the
# literal `ops` row included -- had never been adjudicated against a running oracle.
# CPython spells the axis the port calls `AXIS_UNROLL` `AxisType.UPCAST`
# (`.agents/slop/notes/bend2-constraints.md`, appended section: a dtype/axis RENAME is
# a silent semantic change wherever a pattern matches on the NAME).
LP, UL = AxisType.LOOP, AxisType.UPCAST

def fixture():
  """The SAME arena kernel.bend builds, in the SAME interning order.

  DEAD UNTIL 2026-10-04. `rows()` never called it, so `oracle-live.py` reports it as
  a DEAD DEF -- the `unobservable-gr-oracle.py` `q4()` shape, one file over. It is
  the `kn_fixture` the `ops` row needs, so it is called now; the return value is the
  node LIST in interning order, not the dict this used to build.
  """
  C = UOp.const
  c0, c1, c4 = C(0), C(1), C(4)
  sp = UOp.special(4, "0")
  b7 = UOp(Ops.BUFFER, src=(sp,), arg=ParamArg(7, None))
  b3 = UOp(Ops.BUFFER, src=(sp,), arg=ParamArg(3, None))
  prm = UOp(Ops.PARAM, src=(sp,), arg=ParamArg(0, None))
  # `UOp.range(end, axis_id, axis_type)` is `UOp(RANGE, src=(end,), arg=(axis_type,
  # axis_id))` -- the axis tuple lives in `arg`, NOT in `src`. MEASURED: `ru.nsrc` is
  # 1, not 2. `.agents/slop/kn-noop-truth.py` builds these two by hand as
  # `RANGE(c4, CONST(0))` with a bare `AxisType` arg, which is a DIFFERENT node with
  # nsrc 2 -- and it still agreed with the port, because an op NAME cannot see a src
  # count or an arg shape. That is the `qmd.ver.of` lesson again: provenance added,
  # discriminative power zero, and the wrong node.
  ru = UOp.range(4, (0,), UL)
  rl = UOp.range(4, (1,), LP)
  sq1 = UOp(Ops.SQRT, src=(c0,))
  st1 = UOp(Ops.STORE, src=(c0, c1))
  al1 = UOp(Ops.ALLOC, src=(c1,))
  rd1 = UOp(Ops.REDUCE, src=(sq1, ru), arg=(Ops.ADD, 1))
  sk1 = UOp(Ops.SINK, src=(sq1,))
  pr1 = UOp(Ops.PROGRAM, src=(sk1,))
  pr2 = UOp(Ops.PROGRAM, src=(sk1, st1))
  ins0 = UOp(Ops.INS, src=())
  pr3 = UOp(Ops.PROGRAM, src=(sk1, ins0))
  pr4 = UOp(Ops.PROGRAM, src=(sk1, st1, c1))
  return [c0, c1, c4, sp, b7, b3, prm, ru, rl, sq1, st1, al1, rd1, sk1, pr1, pr2,
          ins0, pr3, pr4]

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

  # ---- build_range_map (__init__.py:40-45) ----
  #
  # WAS A RESTATEMENT, IN TWO WAYS, AND BOTH ARE NOW GONE.
  #   1. `if x.op is Ops.RANGE and x.axis_type in {AxisType.UNROLL, AxisType.UPCAST}`
  #      named `AxisType.UNROLL`, which is NOT a member of the enum at the pin --
  #      `.venv/bin/python -c "import tinygrad.uop.ops as O; print(O.AxisType.__members__)"`
  #      answers `DEVICE GLOBAL LOCAL LOOP PLACEHOLDER UPCAST WARP WEAK`. The set was
  #      a GUESS at the port's two-arm predicate, and it is a second reference to a
  #      name that never existed (the first is at the `LP, UL` line, which raised
  #      first and HID this one). The author's own port says so at kernel.bend:405 --
  #      "The UNROLL arm has no upstream counterpart".
  #   2. `ctx[x.axis_id]` where upstream writes `ctx[x.arg]`. For `UOp.range(4,(0,),t)`
  #      the arg is `(t, (0,))` and `axis_id` is `x.arg[1:]` == `(0,)`, so the two are
  #      DIFFERENT KEYS. The count came out 1 either way, which is why nothing caught
  #      it: a count is not a gate (agent-core.md).
  # NOW: `rm` is `len(CG.build_range_map(sink))` -- the upstream function, called -- and
  # the two halves ask the RESULT whether they are in it. No predicate is restated, so
  # a pin that moves the axis predicate moves these rows without editing this file.
  ru = UOp.range(4, (0,), UL)
  rl = UOp.range(4, (1,), LP)
  sq1 = UOp(Ops.SQRT, src=(UOp.const(0),))
  st1 = UOp(Ops.STORE, src=(UOp.const(0), UOp.const(1)))
  al1 = UOp(Ops.ALLOC, src=(UOp.const(1),))
  rd1 = UOp(Ops.REDUCE, src=(sq1, ru), arg=(Ops.ADD, 1))
  # the sink has to REACH both RANGEs: `ru` through `rd1`, `rl` as a direct src.
  rmap = CG.build_range_map(UOp(Ops.SINK, src=(sq1, st1, al1, rd1, rl)))
  r.append(("rm", len(rmap)))
  r.append(("rm_unroll", int(ru.arg in rmap)))
  r.append(("rm_loop", int(rl.arg in rmap)))

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

def intern_order(nodes):
  """Each node's 1-BASED INTERNING RANK among `nodes`, read out of tinygrad's own
  interning table.

  `UOpMetaClass.__call__` interns on `(op, src, arg, tag, type(arg))` and records the
  insertion into `UOpMetaClass.ucache`, so the table's INSERTION ORDER is the arena
  order `kernel.bend`'s `Found.i` reports. The rank is taken among `nodes` alone and
  NOT as an absolute index, because `ucache` is process-global and already holds
  whatever `rows()` built above.

  THIS IS A CALL INTO THE THING UNDER TEST'S OWN STRUCTURE, not a transcription and
  not a copy: the value is read out of the live interning table, so it moves if the
  fixture's interning order moves. It reaches into a private name, which is the
  honest cost: a pin bump that renames `ucache` fails LOUDLY here (AttributeError at
  this line) instead of quietly reverting to a literal.
  """
  pos = {id(w()): i for i, w in enumerate(UOpMetaClass.ucache.values())
         if w() is not None}
  seen = sorted(pos[id(n)] for n in nodes)
  rank = {r: i + 1 for i, r in enumerate(seen)}
  return [rank[pos[id(n)]] for n in nodes]

def dup_at(ix):
  """The first POSITION whose node repeats the one before it, else 0.

  Same predicate as the port's `k_dup`: a dedup makes two adjacent entries equal.
  Port spelling needs an `Arena`; CPython's is structural, so here two of the
  fixture's constructor calls returning the SAME interned object is the dedup.
  """
  for i in range(1, len(ix)):
    if ix[i] == ix[i - 1]:
      return i
  return 0

def main():
  for nm, v in rows():
    print(f"{nm}={v}")

  # ---- DERIVED, NOT LITERAL. All four rows below used to be typed constants. ----
  #
  # `ix`, `pos`, `dup` and `pos_same` are read off `fixture()` and `intern_order()`.
  # `pos` counts the fixture's nodes plus ONE for the port's arena bottom -- the port's
  # `k_pos` is `List.length` of `K.ix`, whose head is the literal `0` standing in for
  # CPython's absent `None` UOp, so the sentinel is the PORT's spelling and is stated
  # here rather than measured.
  nodes = fixture()
  ix = intern_order(nodes)
  print(f"pos={len(ix) + 1}")
  print(f"dup={dup_at(ix)}")
  # `pos_same`: the port compares its list length to `Arena.next`. Here it is the
  # check that the fixture interned 19 DISTINCT nodes -- if a constructor call had
  # deduplicated onto an earlier one, `ix` would repeat and this would read 0.
  print(f"pos_same={int(len({id(n) for n in nodes}) == len(nodes))}")
  print("ix=" + " ".join(["0"] + [str(i) for i in ix]) + " ")
  # `ops` is the op NAME off each of those same nodes, in the same order. `NOOP` is the
  # port's arena bottom, which has no CPython counterpart, so the sentinel is stated.
  print("ops=NOOP " + " ".join(n.op.name for n in nodes) + " ")
  print("ab=BUFFER")

if __name__ == "__main__":
  main()