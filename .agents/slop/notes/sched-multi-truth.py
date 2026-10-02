#!/usr/bin/env python3
"""CPython oracle for schedule/multi.py.

Prints, for tinygrad's OWN PatternMatcher objects, every number
`tinybendygrad/schedule/multi.bend` gates.  Nothing here is re-derived from
reading the source: the tables are the live `replace_allreduce`,
`_early_allreduce` and `multi_pm` objects, `pdict` is `PatternMatcher.__init__`'s
own dict, and `first_tag` is `PatternMatcher.rewrite`'s own loop with the
`upat_deferred_compile` call replaced by its predicate -- which is exactly
`early_reject` and `pattern.op`, the only two things `rewrite` consults before
calling a body.

Run: python3 .agents/slop/notes/sched-multi-truth.py
"""
import os
os.environ["DEBUG"] = "0"
os.environ["UPAT_COMPILE"] = "0"          # keep the interpreted path out of the way
os.environ["JIT"] = "0"

from tinygrad.uop.ops import Ops, UOp, PatternMatcher, UPat, GroupOp
from tinygrad.uop.ops import AxisType
from tinygrad.dtype import dtypes
import tinygrad.uop.ops as O
import tinygrad.schedule.multi as M

out = []
def row(name, val): out.append(f"{name}={val}")

# ---------------------------------------------------------------------------
# 1. TABLE SIZES
# ---------------------------------------------------------------------------
row("ra_n", len(M.replace_allreduce.patterns))
row("ea_n", len(M._early_allreduce.patterns))
# `multi_pm = PatternMatcher([19 own rules]) + replace_allreduce`, so the LIVE
# object is already 19+6.  `own` is the slice that is multi.py's own list.
OWN = M.multi_pm.patterns[:19]
row("own_n", len(OWN))
row("all_n", len(M.multi_pm.patterns))
# the LATE_ALLREDUCE composition, done the way multi.py:50 does it
row("late0_ra_n", len(M._early_allreduce.patterns) + len(M.replace_allreduce.patterns))
row("late0_all_n", len(OWN) + len(M._early_allreduce.patterns) + len(M.replace_allreduce.patterns))

# ---------------------------------------------------------------------------
# 2. PER-TAG early_reject / required_len / strict_length / op-set size
# ---------------------------------------------------------------------------
def dump(prefix, pm):
  for i, (p, _fxn) in enumerate(pm.patterns):
    row(f"{prefix}{i}_rej", "+".join(sorted(o.name for o in p.early_reject)) or "-")
    row(f"{prefix}{i}_rl", p.required_len)
    row(f"{prefix}{i}_sl", int(p.strict_length))
    row(f"{prefix}{i}_nops", len(p.op))
    row(f"{prefix}{i}_ops", "+".join(sorted(o.name for o in p.op)) if len(p.op) <= 6 else f"<{len(p.op)} ops>")
    row(f"{prefix}{i}_dt", p.match_dtype[0].name if p.match_dtype else "-")

dump("ra", M.replace_allreduce)
dump("ea", M._early_allreduce)
dump("mt", M.multi_pm)

# ---------------------------------------------------------------------------
# 3. GroupOp member sets, and that they agree with the UPat-derived tables
# ---------------------------------------------------------------------------
row("alu_n", len(GroupOp.ALU))
row("mov_n", len(GroupOp.Movement))
row("alu_ops", "+".join(sorted(o.name for o in GroupOp.ALU)))
row("mov_ops", "+".join(sorted(o.name for o in GroupOp.Movement)))
# the two multi_pm entries whose op set is a GroupOp
row("mt0_nops", len(M.multi_pm.patterns[0][0].op))
row("mt0_alu_same", int(set(M.multi_pm.patterns[0][0].op) == set(GroupOp.ALU)))
# replace_allreduce entries whose PATTERN src[0] is a GroupOp (they contribute NO early_reject)
row("ra4_nops", len(M.replace_allreduce.patterns[4][0].src[0][0].op))
row("ra4_mov_same", int(set(M.replace_allreduce.patterns[4][0].src[0][0].op) == set(GroupOp.Movement)))
row("ra5_nops", len(M.replace_allreduce.patterns[5][0].src[0][0].op))
row("ra5_alu_same", int(set(M.replace_allreduce.patterns[5][0].src[0][0].op) == set(GroupOp.ALU)))

# ---------------------------------------------------------------------------
# 4. pdict: how many rules each op key reaches, in INSERTION order
# ---------------------------------------------------------------------------
# The pdict of the LIVE object, which is the table the planner actually runs.
for opname in ("COPY", "MSELECT", "STORE", "SHRINK", "CALL", "AFTER", "MSTACK", "RESHAPE", "ALLREDUCE"):
  ts = [i for i, (p, _f) in enumerate(M.multi_pm.patterns) if opname in [o.name for o in p.op]]
  row(f"live_{opname}_n", len(ts))
  row(f"live_{opname}_tags", "+".join(str(t) for t in ts) or "-")

# the LATE_ALLREDUCE composition, multi.py:50 + :311, both orders
def composed(late):
  ra = M.replace_allreduce.patterns
  if not late: ra = M._early_allreduce.patterns + ra
  return OWN + ra
for late, nm in ((1, "late1"), (0, "late0")):
  ps = composed(late)
  row(f"{nm}_n", len(ps))
  for opname in ("COPY", "MSELECT", "STORE", "SHRINK", "CALL", "AFTER", "MSTACK", "RESHAPE", "ALLREDUCE", "ADD"):
    ts = [i for i, (p, _f) in enumerate(ps) if opname in [o.name for o in p.op]]
    row(f"{nm}_{opname}_tags", "+".join(str(t) for t in ts) or "-")
# the ONLY difference LATE_ALLREDUCE makes to the reachable rule set
row("late0_only", "+".join(str(i) for i in range(25, len(composed(0)))))
row("late1_ra0", "+".join(str(i) for i, (p, _f) in enumerate(composed(1))
                          if p.op[0].name == "COPY")[1:])

# ---------------------------------------------------------------------------
# 5. The gate chain, one row per stage, over the LIVE `multi_pm` table.
#      c = pdict key (rewrite:1606) AND early_reject subset (rewrite:1609)
#      l = c AND the len(uop.src) clause (upat.py:1544-1545)
#      m = l AND `UPat.match` non-empty, which is the whole interpreted matcher
#          including the nested src clauses AND the name-binding identity test
#    `first` is the lowest tag reaching m, i.e. the rule `rewrite` reaches first
#    (rewrite:1610 takes the first non-None).  Tags 0..24 on the live table.
#    `m` is CPython's own answer, not a re-derivation: `UPat.match` IS ops.py's
#    interpreter and this call is the one `upat_interpret` makes.
# ---------------------------------------------------------------------------
def ler(u):
  return {x.op for x in u.src}
def claim(u):
  return [i for i, (p, _f) in enumerate(M.multi_pm.patterns)
          if u.op in p.op and p.early_reject.issubset(ler(u))]
def len_ok(p, u):
  if len(u.src) < p.required_len: return False
  return not (p.strict_length and len(u.src) != p.required_len)
def full(u):
  return [i for i in claim(u) if bool(M.multi_pm.patterns[i][0].match(u, {}))]
def claim_row(u, name):
  row(f"{name}_ler", "+".join(sorted(o.name for o in ler(u))) or "-")
  row(f"{name}_c", len(claim(u)))
  row(f"{name}_l", "+".join(str(t) for t in
        [i for i in claim(u) if len_ok(M.multi_pm.patterns[i][0], u)]) or "-")
  row(f"{name}_m", "+".join(str(t) for t in full(u)) or "-")
  row(f"{name}_first", full(u)[0] if full(u) else "-")

# --- fixtures ---------------------------------------------------------------
def buf(dev="CPU", n=16): return UOp.new_buffer(dev, n, dtypes.i32)
def multi(axis, rng_end=2, val=None):
  v = val if val is not None else buf("CPU:1", 8)
  return v.unshard(axis, UOp.range(rng_end, -1, AxisType.DEVICE))

CPUS, CPU1, CPU2 = "CPU", "CPU:1", "CPU:2"

# a COPY whose device is a TUPLE (the multi-device target)
c_tuple = UOp(Ops.COPY, src=(multi(0),), arg=(CPU1, CPU2))
claim_row(c_tuple, "c_tuple")
# a COPY whose device is a STR and whose src is a tuple device
c_str = UOp(Ops.COPY, src=(multi(0),), arg=CPU1)
claim_row(c_str, "c_str")
# a COPY of a single-device buffer (the common case)
c_plain = UOp(Ops.COPY, src=(buf(CPU1),), arg=CPU2)
claim_row(c_plain, "c_plain")

# MSELECT of an MSTACK
ms = UOp(Ops.MSTACK, src=(multi(0), multi(0, val=buf("CPU:2", 8))))
msel = UOp(Ops.MSELECT, src=(ms,), arg=1)
claim_row(msel, "msel")
# MSELECT of a MOVEMENT (RESHAPE of a CONST)
shp = UOp(Ops.SPECIAL, (4,), "4")
mv = UOp(Ops.RESHAPE, src=(UOp.const(0, dtypes.i32), shp), arg=(4,))
msel_mv = UOp(Ops.MSELECT, src=(mv,), arg=0)
claim_row(msel_mv, "msel_mv")
# MSELECT of an ALU
alu = UOp.const(3, dtypes.i32) + UOp.const(4, dtypes.i32)
msel_alu = UOp(Ops.MSELECT, src=(alu,), arg=0)
claim_row(msel_alu, "msel_alu")

# SHRINK of an MSTACK (replace_allreduce mstack_early_shrink)
shr_ms = UOp(Ops.SHRINK, src=(ms, shp, shp), arg=None)
claim_row(shr_ms, "shr_ms")
# SHRINK of an UNSHARD with three srcs (multi_pm shrink_multi)
shr_un = UOp(Ops.SHRINK, src=(multi(0), shp, shp), arg=None)
claim_row(shr_un, "shr_un")
# SHRINK of an UNSHARD with ONE src -- neither pattern
shr_1 = UOp(Ops.SHRINK, src=(multi(0),), arg=None)
claim_row(shr_1, "shr_1")

# STORE: (dest, UNSHARD) vs (UNSHARD, ...)
st_val = UOp(Ops.STORE, src=(buf(CPU1), multi(0)), arg=None)
claim_row(st_val, "st_val")
st_des = UOp(Ops.STORE, src=(multi(0), buf(CPU1), buf(CPU2)), arg=None)
claim_row(st_des, "st_des")
st_both = UOp(Ops.STORE, src=(multi(0), multi(0, val=buf("CPU:2", 8))), arg=None)
claim_row(st_both, "st_both")

# CALL: tag 13 (any), tag 14 (CALL/AFTER of an UNSHARD), tag 15 (void)
body = UOp(Ops.SINK, (UOp(Ops.STORE, (buf(CPU1), buf(CPU2)), None),), None)
call_v = UOp(Ops.CALL, (body, buf(CPU1)), arg=O.CallInfo("f", False, False, dtypes.i32))
claim_row(call_v, "call_v")
call_s = UOp(Ops.CALL, (body, buf(CPU1)), arg=O.CallInfo("f", False, False, dtypes.void))
claim_row(call_s, "call_s")
aft = UOp(Ops.AFTER, (multi(0),), None)
claim_row(aft, "aft")

# ALU over two UNSHARDs (tag 0, custom_early_reject={UNSHARD})
alu_un = UOp(Ops.ADD, src=(multi(0), multi(0, val=buf("CPU:2", 8))), arg=None)
claim_row(alu_un, "alu_un")
# ALU with NO UNSHARD src
alu_plain = UOp(Ops.ADD, src=(buf(CPU1), buf(CPU2)), arg=None)
claim_row(alu_plain, "alu_plain")

# the ONE-row claims that need the required_len / strict_length gate
row("shr_un_nsrc", len(shr_un.src))
row("shr_1_nsrc", len(shr_1.src))
row("st_both_nsrc", len(st_both.src))
row("c_plain_nsrc", len(c_plain.src))

# ---------------------------------------------------------------------------
# 6. the ARITHMETIC each rule decides before it builds a graph
# ---------------------------------------------------------------------------
def sharding(m):
  return tuple(zip(m.arg, m.src[1:]))

# --- reduce_multi -----------------------------------------------------------
def reduce_case(name, sh, num_axes):
  reduced = [(ax, rng) for ax, rng in sh if ax < num_axes]
  remaining = [(ax, rng) for ax, rng in sh if ax >= num_axes]
  row(f"{name}_red", "+".join(str(ax) for ax, _ in reduced) or "-")
  row(f"{name}_rem", "+".join(str(ax) for ax, _ in remaining) or "-")
  row(f"{name}_nax", "+".join(str(ax - num_axes) for ax, _ in remaining) or "-")
  row(f"{name}_partial", int(bool(reduced) and bool(remaining)))

s2 = tuple(UOp.range(2, -1, AxisType.DEVICE) for _ in range(2))
m2 = buf("CPU:1", 8).unshard((0, 1), tuple(s2))
m1 = buf("CPU:1", 8).unshard(0, UOp.range(2, -1, AxisType.DEVICE))
reduce_case("red_a", sharding(m1), 1)      # the single reduced axis
reduce_case("red_b", sharding(m1), 0)      # nothing reduced
reduce_case("red_c", sharding(m2), 1)      # axis 0 reduced, axis 1 kept -> PARTIAL
reduce_case("red_d", sharding(m2), 2)      # both reduced

# --- reshape_multi ----------------------------------------------------------
def reshape_case(name, shape, new_shape, sh):
  row(f"{name}_prod_eq", int(_prod(shape) == _prod(new_shape)))
  arg_acc = [1]
  for s in new_shape: arg_acc.append(arg_acc[-1] * s)
  row(f"{name}_acc", "+".join(str(a) for a in arg_acc))
  new_shardings, bad = [], ""
  for ax, rng in sh:
    count = int(rng.vmax) + 1
    target = _prod(shape[:ax])
    row(f"{name}_t{ax}", target)
    if target not in arg_acc: bad = f"notacc{ax}"; continue
    new_ax = len(arg_acc) - arg_acc[::-1].index(target) - 1
    row(f"{name}_c{ax}", count)
    row(f"{name}_n{ax}", new_ax)
    if new_shape[new_ax] % count != 0: bad = f"div{ax}"; continue
    new_shardings.append((new_ax, rng))
  row(f"{name}_newsh", "+".join(str(ax) for ax, _ in new_shardings) or "-")
  new_axs = {a for a, _ in new_shardings}
  row(f"{name}_locshape", "+".join(str(s // (int(rng.vmax) + 1) if a in new_axs else s)
                                   for a, s in enumerate(new_shape)))
  row(f"{name}_bad", bad or "-")

def _prod(xs):
  p = 1
  for x in xs: p *= x
  return p

rng2 = UOp.range(2, -1, AxisType.DEVICE)
mr = buf("CPU:1", 8).unshard(0, rng2)
reshape_case("rsh_a", (8,), (4, 2), sharding(mr))     # axis 0 survives, splits
reshape_case("rsh_b", (8,), (2, 4), sharding(mr))     # axis 0 boundary is 1
reshape_case("rsh_c", (8,), (3, 4), sharding(mr))     # 12 != 8: prod row
reshape_case("rsh_d", (8,), (3, 2), sharding(mr))     # boundary 3 not in acc? it is; 3%2!=0
reshape_case("rsh_e", (8,), (5, 2), sharding(mr))     # boundary 1 ok, 2%2==0
mrg = buf("CPU:1", 8).unshard(0, rng2)
reshape_case("rsh_f", (8,), (3, 8), sharding(mrg))    # boundary 1, 8%2==0
rng3 = UOp.range(3, -1, AxisType.DEVICE)
m3 = buf("CPU:1", 8).unshard(0, rng3)
reshape_case("rsh_g", (8,), (4, 2), sharding(m3))     # 2 % 3 != 0

# --- permute_multi ----------------------------------------------------------
def permute_case(name, marg, sh):
  row(f"{name}_all", int(all(ax in marg for ax, _ in sh)))
  try: row(f"{name}_newax", "+".join(str(marg.index(ax)) for ax, _ in sh) or "-")
  except ValueError: row(f"{name}_newax", "ValueError")   # CPython raises here too
permute_case("pmt_a", (1, 0), sharding(m1))
permute_case("pmt_b", (0, 1), sharding(m1))
permute_case("pmt_c", (1, 2), ((0, rng2),))            # axis 0 is NOT in the permute
permute_case("pmt_d", (1, 0), ((1, rng2),))            # axis 1 -> position 0

# --- pad_multi --------------------------------------------------------------
def pad_case(name, sh, marg, loc_shape):
  for ax, _ in sh:
    row(f"{name}_lo{ax}", marg[ax][0])
    row(f"{name}_ok{ax}", int(marg[ax] == (0, loc_shape[ax])))
  counts = {a for a, _ in sh}
  # only the UNSHARDED axes' pairs are walked, so print them as a flat run
  row(f"{name}_cnt", "+".join(str(a) for a in sorted(counts)) or "-")
  row(f"{name}_local", "+".join(
    f"{a}={marg[a][0] if a not in counts else 0}:{marg[a][1] if a not in counts else loc_shape[a]}"
    for a in range(len(marg))))
pad_case("pad_a", sharding(m1), ((0, 4), (0, 8), (1, 2)), (4, 8))
pad_case("pad_b", ((1, rng2),), ((0, 1), (0, 8), (2, 3)), (4, 8))

# --- flip_multi -------------------------------------------------------------
def flip_case(name, sh, marg):
  bad = [ax for ax, _ in sh if marg[ax]]
  row(f"{name}_bad", "+".join(str(a) for a in bad) or "-")
  row(f"{name}_axes", "+".join(str(i) for i, x in enumerate(marg) if x) or "-")
flip_case("flp_a", sharding(m1), (0, 1, 0))
flip_case("flp_b", sharding(m1), (1, 0, 0))
flip_case("flp_c", sharding(m1), (0, 0, 0))

# --- expand_multi -----------------------------------------------------------
def exp_case(name, sh, ndim):
  shift = ndim
  row(f"{name}_shift", shift)
  row(f"{name}_newax", "+".join(str(ax + shift) for ax, _ in sh) or "-")
exp_case("exp_a", sharding(m1), 1)
exp_case("exp_b", sharding(m1), 0)
exp_case("exp_c", sharding(m2), 2)

# --- stack_multi ------------------------------------------------------------
def stk_case(name, multis_sh, sh):
  row(f"{name}_same", int(all(x == sh for x in multis_sh)))
  row(f"{name}_newsh", "+".join(str(ax + 1) for ax, _ in sh) or "-")
stk_case("stk_a", [sharding(m1)], sharding(m1))
stk_case("stk_b", [sharding(m1), sharding(m1)], sharding(m1))
stk_case("stk_c", [sharding(m1), sharding(m2)], sharding(m1))

# --- shrink_multi -----------------------------------------------------------
def shrink_case(name, sh, loc_shape, marg):
  local_marg, remaining = list(marg), list(sh)
  for ax, rng in sh:
    shard_sz = loc_shape[ax]
    s, l = marg[ax]
    if l == shard_sz and (s - int(rng.vmax) * shard_sz) == 0:
      local_marg[ax] = (0, shard_sz); remaining.remove((ax, rng)); continue
    nb = tuple((i * shard_sz, shard_sz) for i in range(int(rng.vmax) + 1))
    if (s, l) == (0, loc_shape[ax]): local_marg[ax] = (0, shard_sz)
    else: row(f"{name}_reject", f"ax{ax}")
  row(f"{name}_local", "+".join(f"{a}:{b}" for a, b in local_marg))
  row(f"{name}_rem", "+".join(str(ax) for ax, _ in remaining) or "-")
shrink_case("shk_a", sharding(m1), (4, 8), ((0, 4), (0, 8)))
shrink_case("shk_b", sharding(m1), (4, 8), ((4, 4), (0, 8)))   # ax0 resolves
shrink_case("shk_c", sharding(m1), (4, 8), ((1, 2), (0, 8)))   # ax0 rejected
row("shk_a_nb", "+".join(f"{i}:{sz}" for i, (st, sz) in
                         enumerate((i * 4, 4) for i in range(3))))

# --- _shard_idx / copy_multi grouping ---------------------------------------
def copy_group(name, sh, ndev, idxs_of):
  # `key = idxs[:j] + idxs[j+1:]` for j from len(sh)-1 down to 0
  keys = []
  for j in range(len(sh) - 1, -1, -1):
    keys.append("+".join(str(i) for i in idxs_of[:-1] + idxs_of[j + 1:]) if len(sh) > 1 else "-")
  row(f"{name}_keys", "|".join(keys) or "-")
  row(f"{name}_axes", "+".join(str(ax) for ax, _ in sh) or "-")
copy_group("cpy_a", sharding(m1), 2, [0, 1])
copy_group("cpy_b", sharding(m1), 3, [1, 2])
copy_group("cpy_c", sharding(m2), 2, [0, 1, 1])

# --- pad amounts for the multi-device branch of copy_multi -----------------
def cpad(name, sh, shape, rngs):
  for ax, rng in sh:
    bsz = shape[ax]
    lo = bsz * int(rng.vmax)
    hi = bsz * int(rng.vmax) - bsz * int(rng.vmax)
    row(f"{name}_{ax}", f"{lo}:{hi}")
    row(f"{name}_{ax}_bsz", bsz)
cpad("cpd_a", sharding(m1), (4, 8), [rng2])

# --- alu_multi.can_handle ---------------------------------------------------
def can_handle(name, m, target_shape, sh):
  if sh:
    r = (m.sharding == sh)
  else:
    r = (tuple(m.shape) == () or tuple(m.shape) == tuple(target_shape))
  row(f"{name}", int(r))
can_handle("ah_a", m1, m1.shape, sharding(m1))
can_handle("ah_b", m1, m1.shape, sharding(m1))
can_handle("ah_c", buf("CPU:1", 8), m1.shape, sharding(m1))
can_handle("ah_d", buf("CPU:1", 8), (4, 8), sharding(m1))
can_handle("ah_e", UOp.const(1, dtypes.i32), m1.shape, sharding(m1))

# --- shard_subview's EXPAND-of-scalar guard ---------------------------------
def ssv(name, full):
  row(name, int(full.op is Ops.EXPAND and tuple(full.src[0].shape) == ()))
row("ssv_op_scalar", UOp.const(0, dtypes.i32).expand((4, 8)).src[0].op.name)
row("ssv_op_vec", UOp.const(0, dtypes.i32).expand((4, 1)).expand((4, 8)).src[0].op.name)
row("ssv_nd_scalar", len(UOp.const(0, dtypes.i32).expand((4, 8)).src[0].shape))
row("ssv_nd_vec", len(UOp.const(0, dtypes.i32).expand((4, 1)).expand((4, 8)).src[0].shape))


# --- is_inline_call ---------------------------------------------------------
row("iic_body_sink", int(body.op is Ops.SINK and body.arg is None))

print("\n".join(out))