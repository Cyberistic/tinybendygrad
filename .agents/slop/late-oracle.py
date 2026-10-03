#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/codegen/late/{linearizer,regalloc,gater}.bend.

Drives tinygrad/codegen/late/{linearizer,regalloc,gater}.py over FIXED inputs and
prints the rows the Bend gate must reproduce byte for byte.

    python3 /tmp/opencode/late-oracle.py > /tmp/opencode/late-cpython.txt
    .agents/slop/late-gate.sh   # runs the three files and diffs their union

`TUPLE_ORDER=0` is used for every `linearize` row. That is a REAL supported
configuration (helpers.py:280, default 1) and it is the only one that ports:
`x.tuplize` is a recursive `(op.value, repr(arg), dtype, *src.tuplize)` tuple
compare, and `lin_ties` is the row that says how much of the order it decides.
"""
import sys
from dataclasses import replace
sys.path.insert(0, '.')

from tinygrad.uop.ops import UOp, Ops, KernelInfo, ParamArg, PatternMatcher, UPat
from tinygrad.dtype import dtypes, AddrSpace, Invalid
from tinygrad.helpers import Context, prod, dedup
from tinygrad.renderer.isa import Register, LinearContext, ISARenderer
from tinygrad.codegen.late.linearizer import (linearize, CFGContext, do_split_ends,
                                              pm_split_ends, pm_add_control_flow)
from tinygrad.codegen.late import regalloc as RA
from tinygrad.codegen.late.gater import move_where_load, pm_move_gates_from_index

LinearScanRegallocContext = RA.LinearScanRegallocContext
out = []
def row(k, v): out.append(f"{k}={v}")
def srow(k, v): out.append(f"{k}={v}")

F32, I32, BOOL = dtypes.f32, dtypes.i32, dtypes.bool

def parg(slot, dt, addr=AddrSpace.GLOBAL, name=""):
  return ParamArg(slot=slot, dtype=dt, name=name or None, addrspace=addr)

# ===========================================================================
# 1. THE LINEARIZER FIXTURE. Same nodes, same interning order, same indices as
# the Bend fixture. `vmax` works because a RANGE's end is a CONST int.
# ===========================================================================
def lin_fixture():
  ix, n = {}, [0]
  def put(name, u):
    n[0] += 1          # index 0 is the bottom, exactly as ops.bend's Arena.empty spends it
    ix[name] = n[0]
    return u
  # A CONST of int32 is a PAIR in CPython (`UOp.const(b, dt)` is `const.cast(dt)`,
  # ops.py:631) and ops.bend's `UOp.const` interns the BARE CONST only, so the
  # fixture builds the CAST explicitly. One node here is two there otherwise and
  # every index after it is off by one.
  c1a = put("C1a", UOp.const(1, I32))
  c1  = put("C1",  c1a)
  c4a = put("C4a", UOp.const(4, I32))
  c4  = put("C4",  c4a)
  c16a = put("C16a", UOp.const(16, I32))
  c16 = put("C16", c16a)
  # A SPECIAL WITH A SRC, like every real kernel (`SPECIAL ['CAST']`): a
  # src-less SPECIAL makes `_min_max` answer `self.src[0]-1` and raise.
  sp  = put("SP",   UOp(Ops.SPECIAL, (c1,), 0, I32))
  bufl = put("BUFL", UOp(Ops.BUFFER, (sp,), parg(7, F32, AddrSpace.LOCAL, "b")))
  prm = put("PRM",  UOp(Ops.PARAM, (), parg(0, F32)))
  r_u = put("R_U",  UOp(Ops.RANGE, (c4,), (0,)))
  ad  = put("ADD",  UOp(Ops.ADD, (prm, c1)))
  st  = put("ST",   UOp(Ops.STORE, (bufl, ad, sp)))
  al  = put("ALG",  UOp(Ops.ALLOC, (c1,), parg(0, F32, AddrSpace.GLOBAL, "a")))
  en  = put("EN",   UOp(Ops.END, (st, r_u)))
  # THE CFG SHAPE: R_B's second src IS `en`, so `deps[SK]` reaches `en` through
  # `r_b` and `nesting` gets BOTH ends under the SINK -- which is the only way
  # `zipped` (:77) has a pair to yield. A SINK with one END child yields none.
  r_b = put("R_B",  UOp(Ops.RANGE, (c16, en), (1,)))
  ad2 = put("ADD2", UOp(Ops.ADD, (prm, c16)))
  st2 = put("ST2",  UOp(Ops.STORE, (bufl, ad2, sp)))
  en2 = put("EN2",  UOp(Ops.END, (st2, r_b)))
  sk  = put("SK",   UOp(Ops.SINK, arg=KernelInfo(), src=(st, st2, en2, al)))
  cll = put("CALL", UOp(Ops.CALL, (st, ad), None))
  sk2 = put("SK2",  UOp(Ops.SINK, arg=KernelInfo(), src=(cll,)))
  return ix, sk, sk2, (r_u, r_b)

# ===========================================================================
# 2. linearize -- the per-uop table.
# ===========================================================================
def prio_of(u):
  rc = prod([int(r.vmax) + 1 for r in u.ranges])
  extra = None
  match u.op:
    case Ops.PARAM: p, extra = -20, u.arg.slot
    case Ops.BUFFER | Ops.ALLOC: p = -17 if u.addrspace == AddrSpace.LOCAL else -18
    case Ops.LOAD: p = -1
    case Ops.STORE: p = 1
    case Ops.RANGE: p = 5
    case Ops.END | Ops.BACKEDGE: p = -5
    case _: p = 0
  return rc, p, extra

def lin_rows(tag, sink):
  lst = list(sink.toposort(enter_calls=False).keys())
  # CPython has NO per-node index in this fork (ops.py:842 keeps only the
  # counter), so the node list is pinned by a LABEL that disambiguates the three
  # CONSTs and the two RANGEs: op name plus the one value that differs.
  # RANGE carries its axis id so the two RANGEs are told apart; the three
  # CONST/CAST PAIRS are told apart by their adjacency (each is CONST then CAST),
  # which is why a CONST needs no value here.
  def lab(u):
    return f"RANGE:{u.arg[0]}" if u.op is Ops.RANGE else u.op.name
  srow(f"{tag}_srcs", " ".join(lab(u) for u in lst))
  row(f"{tag}_n", len(lst))
  # W1's INPUT, one list per node: the `vmax` of every range in `u.ranges`, in
  # `ranges` (a dict) iteration order. The port's `lt_rc` is a fold over exactly
  # this list and `lin_u<i>` carries its answer, so the two rows together gate
  # the fold; what is NOT gated is `u.ranges` itself, which is W1.
  # the FLAT, LENGTH-PREFIXED spelling `lt_vm` reads: [n0, v0..., n1, v0...]
  flat = []
  for u in lst:
    flat.append(len(u.ranges))
    flat.extend(int(r.vmax) for r in u.ranges)
  srow(f"{tag}_vm", " ".join(str(x) for x in flat))
  # THE EDGE LIST, IN THE TOPOSORT'S OWN POSITIONS -- `{tag}_edg`. Every other
  # `{tag}_*` row reads this graph's nodes by OP and ARG only, and `linearize`
  # reads `src_without_body` only to COUNT occurrences, so a permutation of any
  # one node's srcs moves none of them: seven src-swaps of the fixture graph move
  # 0 of the 128 rows on the Bend side while moving 2, 0, 20, 6, 9, 3 and 10 on
  # this one (`.agents/slop/order-lin-sweep.sh`). This row is the edges.
  #
  # THE ALPHABET IS A POSITION, NOT AN ARENA INDEX, and that is what makes the two
  # lanes comparable: `pos` comes from CPython's own `toposort`, while the port
  # derives it from its own arena and its own literal node list. An arena-index
  # alphabet would not work -- `UOp.const(1, i32)` is ONE node here and TWO in
  # `ops.bend`, so the ports' index alphabets differ by construction.
  pos = {u: i for i, u in enumerate(lst)}
  srow(f"{tag}_edg", " ".join("%d:%s" % (pos[u], " ".join(str(pos[s]) for s in u.src_without_body))
                              for u in lst))
  prios = {u: prio_of(u) for u in lst}
  with Context(TUPLE_ORDER=0):
    nl = linearize(sink)
  order = sorted(lst, key=lambda x: prios[x])
  nkey = {u: i for i, u in enumerate(order)}
  srow(f"{tag}_nkey", " ".join(str(nkey[u]) for u in lst))
  # the SORTED list's own order, by label: this is the row that separates "the keys
  # are wrong" from "the TIE ORDER inside the sorted list is wrong", which is the
  # only thing `TUPLE_ORDER=0` has to get right.
  srow(f"{tag}_ord", " ".join(lab(u) for u in order))
  for i, u in enumerate(nl):
    rc, p, ex = prios[u]
    # `po` is the OFFSET: Bend has no signed `U32` and every priority in the
    # ladder is negative, so the port stores `priority + 20` and the offset is
    # order-isomorphic on 0..25. `lin_exmix` below is why `extra` needs no room.
    srow(f"{tag}_u{i}", f"{u.op.name} rc={rc} po={p + 20} nk={nkey[u]}")
  # THE TUPLE_ORDER=1 WALL: how many node PAIRS tie on (rc, pr), i.e. how much
  # of the ordering `x.tuplize` is actually deciding on this fixture.
  ties = sum(1 for a in range(len(order)) for b in range(a + 1, len(order))
             if prios[order[a]][:2] == prios[order[b]][:2])
  row(f"{tag}_ties", ties)
  # `extra` is the PARAM's slot and every OTHER extra is None. If two entries can
  # only reach `extra` when both are PARAMs, the ordering never compares it to a
  # None, and `None < int` would raise in Python -- so this row PINS the claim
  # that `extra` is never consulted across types.
  nmix = sum(1 for a in range(len(order)) for b in range(a + 1, len(order))
             if (prios[order[a]][0], prios[order[a]][1]) == (prios[order[b]][0], prios[order[b]][1])
             and (prios[order[a]][2] is None) != (prios[order[b]][2] is None))
  row(f"{tag}_exmix", nmix)
  return nl

def rc_rows():
  # `lt_rc` IS `helpers.prod` over the vmax list, and on `lin` it only ever sees
  # `[]`, `[3]` and `[15]` -- three cases that cannot tell a product from a sum.
  # These five are the ones that can, and the last is the MAX over the fixture.
  for k, xs in [("rc_nil", []), ("rc_1", [3]), ("rc_2", [3, 15]), ("rc_3", [1, 1, 4]),
                ("rc_max", [15, 15, 15, 15])]:
    row(k, prod([int(v) + 1 for v in xs]))
  row("rc_big", prod([64, 64, 64]))

# ===========================================================================
# 3. CFGContext + pm_add_control_flow.
# ===========================================================================
def cfg_rows(tag, sink, rngs):
  ctx = CFGContext(sink)
  srow(f"{tag}_edges", " ".join(f"{k.op.name}/{k.arg[0]}->{v.op.name}" for k, v in ctx.edges.items()))
  row(f"{tag}_edges_n", len(ctx.edges))
  # THE SINK-KEY / END-KEY DISPATCH at :77. `cfg2` has a SINK parent and yields a
  # pair; `cfgnil` would need an END or BACKEDGE parent, which the port names as
  # reachable only across a range cycle.
  bits = []
  for r in rngs:
    r2 = pm_add_control_flow.rewrite(r, ctx=ctx)
    bits.append("-" if r2 is None else f"{r.arg[0]}->[{','.join(u.op.name for u in r2.src)}]")
  srow(f"{tag}_hits", " ".join(bits))
  row(f"{tag}_tbl_len", len(pm_add_control_flow.patterns))
  srow(f"{tag}_tbl_ops", " ".join(o.name for o in pm_add_control_flow.patterns[0][0].op))

# ===========================================================================
# 4. do_split_ends / pm_split_ends. Every src[1:] IS a RANGE, so the
# `else s.ranges` half is never taken and this half is PORTED.
# ===========================================================================
def se_rows():
  r0 = UOp(Ops.RANGE, (UOp.const(4, I32),), (0,))
  r1 = UOp(Ops.RANGE, (UOp.const(8, I32),), (1,))
  r2 = UOp(Ops.RANGE, (UOp.const(4, I32),), (2,))
  e = UOp(Ops.END, (UOp.const(2.0, F32), r0, r1, r2))
  # `se_rngs` is the LOOP'S FUEL: `sorted(dedup(...), key=arg, reverse=True)` by
  # axis. The three axes ascend in the fixture so the reverse sort is a REORDER
  # and not the identity -- a port that dropped the sort would answer `0 1 2`.
  srt = sorted(dedup([r0, r1, r2]), key=lambda r: r.arg, reverse=True)
  srow("se_rngs", " ".join(str(r.arg[0]) for r in srt))
  ret = do_split_ends(e)
  topo = list(ret.toposort().keys())
  srow("se_ops", " ".join(f"{u.op.name}/{u.arg[0] if u.op is Ops.RANGE else '-'}" for u in topo))
  row("se_len", sum(1 for u in topo if u.op is Ops.END))
  row("se_nsrc", len(ret.src))
  row("se_tbl_len", len(pm_split_ends.patterns))
  srow("se_tbl_ops", " ".join(o.name for o in pm_split_ends.patterns[0][0].op))
  row("se_fired", 1 if pm_split_ends.rewrite(e) is not None else 0)
  row("se_miss", 1 if pm_split_ends.rewrite(r0) is not None else 0)

# ===========================================================================
# 5. regalloc. A hand-built uop list with Register tags. `ren.fill`/`ren.spill`
# and `ctx.assign_spill_slot` are `NotImplementedError` in tinygrad's OWN base
# class, so ANY oracle for this pass has to supply them.
# ===========================================================================
class FakeCtx(LinearContext):
  def __init__(self, ren): self.ren, self.stack_size, self.loop_label = ren, 0, {}
  def assign_spill_slot(self, r, u): return "slot:" + r.name

class FakeRen(ISARenderer):
  def __init__(self, two_addr): self.two = two_addr
  def is_two_address(self, x): return self.two
  def spill(self, slot, x): return UOp(Ops.CUSTOM, (x,), ("spill", str(slot)))
  def fill(self, slot, x, reg): return UOp(Ops.CUSTOM, (x,), ("fill", str(slot), str(reg)))

class Regs:
  def __init__(self): self.rs = []
  def reg(self, name, index, cons=(), size=8):
    r = Register(name, index, tuple(cons), size)
    if r not in self.rs: self.rs.append(r)
    return r
  def vreg(self, n, cons, size=8): return self.reg(f"v{n}", 0, cons, size)
  def ix(self, r): return self.rs.index(r)

def ra_fixture(R):
  """(op, defs, uses); `uses` are INDICES into this list. The shape is chosen so
  `alloc`'s tie at index 7 is decided by cons ORDER -- the only thing
  `is_two_address`'s `cons` reordering (:72-74) changes -- which is why the
  ra0/ra1 pair is a real two-row claim and not one row twice."""
  a0, a1, a2, a3 = R.reg("rax", 0), R.reg("rcx", 1), R.reg("rdx", 2), R.reg("rsi", 3)
  b0, b1 = R.reg("rbx", 4), R.reg("rbp", 5)
  v0, v1, v2, v3 = R.vreg(0, (a0, b0)), R.vreg(1, (a1, b1)), R.vreg(2, (a2, a3)), R.vreg(3, (b0, a0))
  v4 = R.vreg(4, (a1, a2))
  plan = [
    ("CONST", [], []),        # 0   a PSEUDO op: skipped at :56, and a legal src
    ("INS", [v0], [0]),       # 1   four definitions, each with a src so `uses[0]` exists
    ("INS", [v1], [0]),       # 2
    ("INS", [v2], [0]),       # 3
    ("INS", [v3], [0]),       # 4
    ("INS", [], [1]),         # 5   uses v0
    ("INS", [], [2]),         # 6   uses v1
    ("INS", [v4], [3, 4]),    # 7   DEFINES and USES: the two-address branch at :72-74
    ("CONST", [], []),        # 8   a second PSEUDO op
    ("INS", [], [1]),         # 9   v0 again
    ("INS", [], [2, 3]),      # 10  v1 AND v2 at the same index -- the TIE
    ("INS", [], [4]),         # 11  v3
  ]
  uops = []
  for op, defs, uses in plan:
    tag = tuple(defs) if defs else None
    uops.append(UOp(Ops.INS if op == "INS" else Ops.CONST, tuple(uops[i] for i in uses), None, tag=tag))
  return uops

def ra2_fixture(R):
  """(op, defs, uses) -- a SECOND fixture, built so the RANGE prologue and the
  END epilogue are REACHED: the first fixture has no RANGE and no END, so
  `loops` (:29), the loop-interval append (:28), `used_in_loop`/`sorted_uses`
  (:82-83), `live_ins` (:37, :90, :96) and the epilogue's `fill` (:97) are all
  dead code there. `v2`'s single-constraint cons STEALS rax from v0 so the
  epilogue's `v not in live` is TRUE and the refill is really emitted."""
  a0, a1, a3 = R.reg("rax", 0), R.reg("rcx", 1), R.reg("rbx", 3)
  v0, v5 = R.vreg(0, (a0,)), R.vreg(5, (a1,))
  v2 = R.vreg(2, (a0,))
  plan = [
    ("CONST", [], []),        # 0
    ("INS", [v0], [0]),       # 1   v0 -> rax
    ("INS", [v5], [0]),       # 2   v5 -> rcx
    ("RANGE", [], [0]),       # 3   the prologue: `loops[3] = 5`
    ("INS", [v2], [1, 2]),    # 4   uses v0 AND v5, defines v2 which takes rax
    ("END", [], [4, 3]),      # 5   the epilogue: v0 is no longer live
  ]
  uops = []
  for op, defs, uses in plan:
    tag = tuple(defs) if defs else None
    u = UOp(Ops.INS if op == "INS" else (Ops.RANGE if op == "RANGE" else
         (Ops.END if op == "END" else Ops.CONST)),
            tuple(uops[i] for i in uses), None, tag=tag)
    uops.append(u)
  return uops

def ra_rows_of(t, ctx, R, uops):
  out.append(f"ra{t}_n={len(uops)}")
  out.append("ra%d_uops=%s" % (t, " ".join(u.op.name for u in uops)))
  out.append("ra%d_vregs=%s" % (t, " ".join(f"{r.name}>{R.ix(r)}" for r in R.rs)))
  # THE LIVE RANGES: `lr[v][0]` is the definition and `lr[v][-1]` the last use.
  out.append("ra%d_lr=%s" % (t, " ".join("%s>%d:%s" % (v.name, R.ix(v), ",".join(map(str, lr)))
                                            for v, lr in sorted(ctx.live_range.items(), key=lambda kv: R.ix(kv[0])))))
  for i in sorted(ctx.reals):
    parts = sorted("%s>%d->%s>%d" % (v.name, R.ix(v), r.name, R.ix(r)) for v, r in ctx.reals[i].items())
    out.append(f"ra{t}_a{i}=" + " ".join(parts))
  out.append("ra%d_spills=%s" % (t, " ".join(sorted("%s>%d:%s" % (v.name, R.ix(v), s) for v, s in ctx.spills.items()))))
  out.append("ra%d_before=%s" % (t, " ".join(
    "%d:%s" % (i, " ".join("%s>%d->%s>%d" % (v.name, R.ix(v), r.name, R.ix(r)) for v, r in pairs))
    for i, pairs in sorted(ctx.insert_before.items()))))
  row(f"ra{t}_loop", sum(1 for i, u in enumerate(uops) if u.op is Ops.RANGE))
  return ctx

def ra_rows(two_addr):
  R = Regs()
  uops = ra_fixture(R)
  ren = FakeRen(two_addr)
  ctx = LinearScanRegallocContext(FakeCtx(ren), uops, ren)
  return ra_rows_of(int(two_addr), ctx, R, uops)

def ra2_rows():
  R = Regs()
  uops = ra2_fixture(R)
  ren = FakeRen(False)
  ctx = LinearScanRegallocContext(FakeCtx(ren), uops, ren)
  return ra_rows_of(2, ctx, R, uops)

# ===========================================================================
# 6. regalloc_rewrite / pm_regalloc_rewrite.
# ===========================================================================
def rw_rows():
  R = Regs()
  uops = ra_fixture(R)
  ren = FakeRen(False)
  ctx = LinearScanRegallocContext(FakeCtx(ren), uops, ren)
  got = []
  for x in uops:
    r = RA.regalloc_rewrite(ctx, x)
    got.append("-" if r is None else x.op.name + "->" + ",".join(
      u.op.name + ("/" + str(u.arg) if u.op is Ops.CUSTOM else "") for u in r[1]))
  out.append("rw_none=" + " ".join(got))
  row("rw_tbl_len", len(RA.pm_regalloc_rewrite.patterns))
  srow("rw_tbl_ops", " ".join(sorted(o.name for o in RA.pm_regalloc_rewrite.patterns[0][0].op)))
  row("rw_pseudo_n", len(RA.PSEUDO_OPS))

# ===========================================================================
# 7. gater.
# ===========================================================================
def gater_rows():
  row("gt_tbl_len", len(pm_move_gates_from_index.patterns))
  for k, (pat, fn) in enumerate(pm_move_gates_from_index.patterns):
    ops = pat.op if isinstance(pat.op, tuple) else ((pat.op,) if pat.op is not None else ())
    srow(f"gt_ops{k}", " ".join(sorted(o.name for o in ops)))
  # `move_where_load`'s FOUR arms, one per link of the ternary chain at :6-7.
  l = UOp(Ops.LOAD, (UOp(Ops.PARAM, (), parg(1, F32)), UOp.const(0, I32), UOp.const(True, BOOL)))
  assert l.shape == (), l.shape
  gate = UOp.const(True, BOOL)
  def leaf(x):                       # the CONST under any CAST run
    return x.arg if x.op is Ops.CONST else leaf(x.src[0]) if x.op is Ops.CAST else "?"
  def depth(x):                      # how many CASTs the port BUILT over the leaf
    return 0 if x.op is Ops.CONST else 1 + depth(x.src[0]) if x.op is Ops.CAST else -1
  def wl(a):
    # gater.py's `w = gate.where(<l'>.or_casted(), a)` -- w.src[0] is the GATE.
    w = UOp(Ops.WHERE, (gate, l, a))
    r = move_where_load(gate, l, a, w)
    alt = r.src[1]
    return "%s alt=%s d=%d leaf=%s nsrc=%d" % (r.op.name, alt.op.name, depth(alt), leaf(alt), len(r.src))
  srow("gt_mwl_invalid",  wl(UOp.const(Invalid, F32)))
  srow("gt_mwl_const",    wl(UOp.const(2.0, F32)))
  srow("gt_mwl_cast_same",wl(UOp(Ops.CAST, (UOp.const(5.0, F32),), F32)))
  srow("gt_mwl_cast_diff",wl(UOp(Ops.CAST, (UOp.const(7, I32),), I32)))

# ===========================================================================
def po_rows():
  # ONE ROW PER LADDER ARM (linearizer.py:27-35), offset by +20 because the
  # value is stored in a U32. `local` is a DATA-LAST extra so the BUFFER/ALLOC arm
  # can be split into its two addrspace answers the way the port splits it.
  def prio(op, local=False):
    match op:
      case Ops.PARAM:  return -20
      case Ops.BUFFER | Ops.ALLOC: return -17 if local else -18
      case Ops.LOAD:   return -1
      case Ops.STORE:  return 1
      case Ops.RANGE:  return 5
      case Ops.END | Ops.BACKEDGE: return -5
      case _: return 0
  row("po_param",   prio(Ops.PARAM) + 20)
  row("po_bufl",    prio(Ops.BUFFER, True) + 20)
  row("po_bufg",    prio(Ops.BUFFER, False) + 20)
  row("po_load",    prio(Ops.LOAD) + 20)
  row("po_store",   prio(Ops.STORE) + 20)
  row("po_range",   prio(Ops.RANGE) + 20)
  row("po_end",     prio(Ops.END) + 20)
  row("po_backedge",prio(Ops.BACKEDGE) + 20)
  row("po_add",     prio(Ops.ADD) + 20)


if __name__ == "__main__":
  ix, sk, sk2, rngs = lin_fixture()
  row("ix_len", len(ix) + 1)
  srow("ix", " ".join(str(i) for i in range(len(ix) + 1)))
  po_rows()
  rc_rows()
  lin_rows("lin", sk)
  lin_rows("linc", sk2)
  cfg_rows("cfg", sk, rngs)
  se_rows()
  ra_rows(False)
  ra_rows(True)
  ra2_rows()
  rw_rows()
  gater_rows()
  print("\n".join(out))
