#!/usr/bin/env python3
"""prepare-oracle.py -- the CPython oracle for tinygrad/schedule/prepare.py.

EVERY row here is produced by CALLING tinygrad.  Nothing is transcribed from
reading the source and nothing is typed by hand: the tables are tinygrad's own
`PatternMatcher` objects, the decisions are the module's own functions, and the
pipeline rows are `prepare_rangeify`'s own output.

Run:  python3 .agents/slop/prepare-oracle.py
"""
import os, sys
os.environ["DEBUG"] = "0"
os.environ["JIT"] = "0"
os.environ["OPENPILOT_HACKS"] = "0"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, ParamArg, AxisType, GroupOp
from tinygrad.dtype import dtypes, AddrSpace, to_dtype
from tinygrad.helpers import prod, argsort
import tinygrad.schedule.prepare as P
from tinygrad.uop.movement import mop_cleanup

I32 = dtypes.int32
I64 = dtypes.int64

# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------
def C(n, dt=I32): return UOp.const(n, dt)
def Cz(n): return UOp(Ops.CONST, src=(), arg=I32.const(n))

def shp(xs, bare=True):
  """the `as_shape` STACK, which is what RESHAPE/EXPAND read at ops.py:816."""
  m = Cz if bare else C
  return UOp(Ops.STACK, tuple(m(x) for x in xs))

def buf(shape=(4,), slot=0, dev="CPU", dt=I32, name="b"):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=prod(shape), name=name, device=dev))

def rng(n, ax=0): return UOp.range(n, ax)

def W(n, at=None): return rng(n, at if at is not None else AxisType.WEAK)

def rs(x): return UOp(Ops.RESHAPE, (x, shp(x.shape if False else ())))

def reshape(x, new): return UOp(Ops.RESHAPE, (x, shp(new)))
def expand(x, new): return UOp(Ops.EXPAND, (x, shp(new)))
def permute(x, arg): return UOp(Ops.PERMUTE, (x,), arg=tuple(arg))
def flip(x, arg): return UOp(Ops.FLIP, (x,), arg=tuple(arg))
def pad(x, o, s): return UOp(Ops.PAD, (x, shp(o), shp(s)))
def shrink(x, o, s): return UOp(Ops.SHRINK, (x, shp(o), shp(s)))
def store(d, v): return UOp(Ops.STORE, (d, v))
def after(self, *ss): return UOp(Ops.AFTER, (self,)+ss)
def end(self): return UOp(Ops.END, (self,))
def stg(x, dev="CPU"): return UOp(Ops.STAGE, (x,), arg=type("B", (), {"device": dev})())
def copy(x, *ss, dev=None):
  return UOp(Ops.COPY, (x,)+ss, arg=ParamArg(slot=0, dtype=x.dtype, size=prod(x.shape), device=dev or "CPU"))
def where(c, a, b): return UOp(Ops.WHERE, (c, a, b))
def cast(x, dt): return UOp(Ops.CAST, (x,), arg=dt)
def bitcast(x, dt): return UOp(Ops.BITCAST, (x,), arg=dt)
def reduce(x, op, ax): return UOp(Ops.REDUCE, (x,), arg=(op, ax))

# ---------------------------------------------------------------------------
# print rows
# ---------------------------------------------------------------------------
def row(nm, val): print(f"{nm}={val}")

def opn(o):
  if isinstance(o, (set, frozenset)): return "{" + ",".join(sorted(x.name for x in o)) + "}"
  if o is None: return "-"
  return o.name

def opns(os_):
  """`pat.op` is a TUPLE in the UPat's declared order and `early_reject` is a SET
  (ops.py:1477), so the two render differently and both renderings are what the
  compiled table carries."""
  if not os_: return "{}" if isinstance(os_, (set, frozenset)) else "-"
  if isinstance(os_, (set, frozenset)): return "{" + ",".join(sorted(x.name for x in os_)) + "}"
  return ",".join(x.name for x in os_)

def pat_alts(p): return 0 if p.src is None else len(p.src)

def src_repr(p):
  if p.src is None: return "-"
  out = []
  for s in p.src:
    if isinstance(s, (list, tuple)): out.append("[" + "|".join(repr(x) for x in s) + "]")
    else: out.append(repr(s))
  return "/".join(out)

def tsq(u):
  """toposort op sequence -- the ORDERED row.  never a count."""
  return ",".join(x.op.name for x in u.toposort())

def sops(u): return ",".join(x.op.name for x in u.src)
def try_shape(u):
  try: return "x".join(str(s) for s in u.shape)
  except Exception as e: return "ERR"

def ident4(u):
  """THE FOUR FACTS PLUS THE ANSWER AS ONE STRING."""
  try: sh = "x".join(str(s) for s in u.shape)
  except Exception: sh = "ERR"
  try: dt = u.dtype.name
  except Exception: dt = "ERR"
  return f"{len(u.toposort())}|{u.op.name}|{len(u.src)}|{sops(u)}|{sh}|{dt}"

# ---------------------------------------------------------------------------
# A. TABLE DATA.  `pdict`'s key is `pat.op` (ops.py:1598); `early_reject` is
#    ops.py:1477.  `strict_length`/`required_len`/`name`/`src` are upat.py.
# ---------------------------------------------------------------------------
TABLES = [("fma", P.pm_fold_moved_after), ("mop", P.pm_mops), ("inl", P.pm_inline_calls),
          ("dsk", P.pm_disk_copy), ("ear", P.earliest_rewrites), ("mcl", mop_cleanup)]

def table_rows(nm, pm):
  row(f"{nm}_n", len(pm.patterns))
  keys = sorted(pm.pdict.keys(), key=lambda o: o.name)
  row(f"{nm}_keys", len(keys))
  row(f"{nm}_keynames", ",".join(o.name for o in keys))
  # `.index(e)` would answer a position WITHIN the pdict list, not a rule index:
  # `pdict[ADD]` holds ONE entry and `.index` answers 0 for every op with one
  # claiming rule.  The rule index is the position of the entry's PATTERN in
  # `pm.patterns`, found by IDENTITY.
  for o in keys:
    row(f"{nm}_pd_{o.name}", ",".join(str(next(i for i, (pp, _) in enumerate(pm.patterns) if pp is e[0]))
                                     for e in pm.pdict[o]))
  for k, (pat, f) in enumerate(pm.patterns):
    t = f"{nm}_{k}"
    row(f"{t}_fn", getattr(f, "__name__", "?"))
    row(f"{t}_ops", opns(pat.op))
    row(f"{t}_rej", opns(pat.early_reject))
    row(f"{t}_slen", int(bool(pat.strict_length)))
    row(f"{t}_rlen", pat.required_len)
    row(f"{t}_isany", int(bool(pat.is_any)))
    row(f"{t}_nalts", pat_alts(pat))
    row(f"{t}_name", pat.name if pat.name is not None else "-")
    row(f"{t}_dt", "-" if pat.match_dtype is None else ",".join(x.name for x in pat.match_dtype))
    row(f"{t}_src", src_repr(pat))

print("== A: TABLES ==")
for _nm, _pm in TABLES: table_rows(_nm, _pm)

# ===========================================================================
# C. `walk_mop` -- prepare.py:40-43
#     if u.op in Movement or in {INDEX,UNSHARD,BITCAST}: return walk_mop(u.src[0])
#     if u.op is AFTER and walk_mop(u.src[0]) is not u.src[0]: return b.after(*u.src[1:])
#     return u
#    The identity `is not u.src[0]` is the whole of the AFTER arm, so the rows
#    name it: `wmx_<nm>` is `result is u.src[0]`.
# ===========================================================================
print("== C: walk_mop ==")
# THE FIXTURES, in the ORDER `prepare.bend`'s `wm_fix` builds them, so the arena
# layout agrees and the toposort sizes are comparable.  One arena: `sig4`'s first
# field is the size of a node's OWN reachable set, which is graph-intrinsic, so two
# arenas would make every fixture a different graph.
A4 = buf((4,), 0, name="a4")
A8 = buf((8,), 1, name="a8")
SH22 = shp((2, 2))
SH4 = shp((4,))
SH41 = shp((4, 1))
# the shape src is `UOp(Ops.STACK, (CONST(2), CONST(2)))` with BARE CONSTs: `as_shape`
# reads `s.val` off each element (ops.py:811) and a CAST element has no `.val`.
RS22 = reshape(A4, (2, 2))
RS41 = reshape(A4, (4, 1))
RS4 = reshape(A4, (4,))
PM22 = permute(RS22, (1, 0))
FL22 = flip(RS22, (True, False))
C0 = shp((0,))
PD = pad(A4, (0,), (4,))
PE = expand(A4, (4,))
R0 = rng(4, 0)
IX = UOp(Ops.INDEX, (A4, R0))
BC = bitcast(A4, dtypes.float32)
CF = cast(A4, dtypes.float32)
AL = UOp(Ops.ADD, (A4, A4))
E4 = end(A4)
AF = after(A4, E4)
AFM = after(RS22, E4)
AFM2 = after(PM22, E4)
AFI = after(IX, E4)
NEST = reshape(PM22, (4,))
ST = store(A4, A4)
MOM = permute(RS22, (0, 1))

WM = {}
WM["buf"] = A4
WM["reshape"] = RS22
WM["rs41"] = RS41
WM["rs4"] = RS4
WM["permute"] = PM22
WM["flip"] = FL22
WM["pad"] = PD
WM["expand"] = PE
WM["index"] = IX
WM["bitcast"] = BC
WM["cast"] = CF
WM["alu"] = AL
WM["after_plain"] = AF
WM["after_mov"] = AFM
WM["after_mov2"] = AFM2
WM["after_idx"] = AFI
WM["nested_mov"] = NEST
WM["store"] = ST
WM["mov_of_mov"] = MOM

for nm, u in sorted(WM.items()):
  b = P.walk_mop(u)
  row(f"wm_{nm}_in", ident4(u))
  row(f"wm_{nm}_out", ident4(b) if b is not None else "None")
  row(f"wm_{nm}_wmx", int(b is u.src[0]) if (u.op is Ops.AFTER and len(u.src) > 0) else -1)
  row(f"wm_{nm}_same", int(b is u))
  row(f"wm_{nm}_topo", tsq(b) if b is not None else "None")

# ===========================================================================
# D. `_mop_index` -- prepare.py:65-74.  THE SHAPE ARITHMETIC: three index
#    counts, `src_prefix`, a shape EQUALITY, and `ret.shape == idx.shape`.
# ===========================================================================
print("== D: _mop_index ==")
def mi_row(nm, r, idx):
  idxs = idx.src[1:]
  n_i, n_r = len(idxs), len(r.shape)
  row(f"mi_{nm}_nidx", n_i)
  row(f"mi_{nm}_nrsh", n_r)
  row(f"mi_{nm}_full", int(n_i == n_r))
  row(f"mi_{nm}_prefix", len(r.src[0].shape) - len(r.shape[n_i:]))
  row(f"mi_{nm}_isrs", int(r.op is Ops.RESHAPE))
  row(f"mi_{nm}_in", ident4(r))
  row(f"mi_{nm}_idxin", ident4(idx))
  try:
    ret = P._mop_index(r, idx)
  except Exception as e:
    row(f"mi_{nm}_ret", f"RAISE:{type(e).__name__}:{e}")
    return
  if ret is None: row(f"mi_{nm}_ret", "None")
  else: row(f"mi_{nm}_ret", ident4(ret))

B4 = buf((4,), 0, name="a4")
B8 = buf((8,), 1, name="a8")
B16 = buf((16,), 2, name="a16")
# a 2-D BASE: a PARAM-shaped node, because a BUFFER's shape is always flat.
# a 2-D BASE.  A BUFFER's and a PARAM's shape are BOTH flat (ops.py:457), so the
# only 2-d node in this tree is a RESHAPE of a flat one.
Q44 = reshape(buf((16,), 3, name="a16b"), (4, 4))
r0, r1, r2 = rng(2, 0), rng(2, 1), rng(4, 2)

# full-index arm: len(idxs) == len(r.shape)
mi_row("rs22x2", reshape(B4, (2, 2)), UOp(Ops.INDEX, (reshape(B4, (2, 2)), r0, r1)))
mi_row("rs41x1", reshape(B4, (4, 1)), UOp(Ops.INDEX, (reshape(B4, (4, 1)), rng(4, 0))))
mi_row("rs44x4", reshape(B16, (4, 4)), UOp(Ops.INDEX, (reshape(B16, (4, 4)), rng(4, 0), rng(4, 1))))
mi_row("pd44x4", pad(Q44, (0, 0), (4, 4)), UOp(Ops.INDEX, (pad(Q44, (0, 0), (4, 4)), rng(4, 0), rng(4, 1))))
mi_row("pd88x8", pad(Q44, (2, 2), (8, 8)), UOp(Ops.INDEX, (pad(Q44, (2, 2), (8, 8)), rng(4, 0), rng(4, 1))))
mi_row("pm44x4", permute(reshape(B4, (2, 2)), (1, 0)), UOp(Ops.INDEX, (permute(reshape(B4, (2, 2)), (1, 0)), r0, r1)))
mi_row("fl44x4", flip(reshape(B4, (2, 2)), (True, False)), UOp(Ops.INDEX, (flip(reshape(B4, (2, 2)), (True, False)), r0, r1)))
mi_row("sh42x2", shrink(Q44, (0, 0), (4, 2)), UOp(Ops.INDEX, (shrink(Q44, (0, 0), (4, 2)), rng(4, 0), r1)))
mi_row("ex44x8", expand(Q44, (4, 8)), UOp(Ops.INDEX, (expand(Q44, (4, 8)), rng(4, 0), rng(4, 1))))
# prefix arm: RESHAPE with len(idxs) < len(r.shape)
mi_row("px_221_1", reshape(B4, (2, 2, 1)), UOp(Ops.INDEX, (reshape(B4, (2, 2, 1)), r0)))
mi_row("px_222_2", reshape(B8, (2, 2, 2)), UOp(Ops.INDEX, (reshape(B8, (2, 2, 2)), r0, r1)))
mi_row("px_222_0", reshape(B8, (2, 2, 2)), UOp(Ops.INDEX, (reshape(B8, (2, 2, 2)), rng(4, 0))))
mi_row("px_222_3", reshape(B8, (2, 2, 2)), UOp(Ops.INDEX, (reshape(B8, (2, 2, 2)), r0, r1, rng(2, 2))))
mi_row("px_241_1", reshape(B8, (2, 4, 1)), UOp(Ops.INDEX, (reshape(B8, (2, 4, 1)), r0)))
mi_row("px_241_2", reshape(B8, (2, 4, 1)), UOp(Ops.INDEX, (reshape(B8, (2, 4, 1)), r0, rng(4, 1))))
mi_row("px_14_1", reshape(B4, (1, 4)), UOp(Ops.INDEX, (reshape(B4, (1, 4)), r0)))
mi_row("px_11_1", reshape(B4, (1, 1, 4)), UOp(Ops.INDEX, (reshape(B4, (1, 1, 4)), r0)))
mi_row("px_411_2", reshape(B4, (4, 1, 1)), UOp(Ops.INDEX, (reshape(B4, (4, 1, 1)), rng(4, 0), rng(2, 1))))
# non-RESHAPE with a short index count: the prefix arm cannot fire
mi_row("nx_pd", pad(Q44, (0, 0), (4, 8)), UOp(Ops.INDEX, (pad(Q44, (0, 0), (4, 8)), r0, rng(4, 1))))
mi_row("nx_pm", permute(reshape(B4, (2, 2)), (1, 0)), UOp(Ops.INDEX, (permute(reshape(B4, (2, 2)), (1, 0)), r0)))
mi_row("nx_fl", flip(reshape(B4, (2, 2)), (True, False)), UOp(Ops.INDEX, (flip(reshape(B4, (2, 2)), (True, False)), r0)))
mi_row("nx_sh", shrink(Q44, (0, 0), (4, 2)), UOp(Ops.INDEX, (shrink(Q44, (0, 0), (4, 2)), r0)))
mi_row("nx_ex", expand(Q44, (4, 8)), UOp(Ops.INDEX, (expand(Q44, (4, 8)), r0)))
# zero index count: idxs is empty
mi_row("zx_rs22", reshape(B4, (2, 2)), UOp(Ops.INDEX, (reshape(B4, (2, 2)),)))
mi_row("zx_rs221", reshape(B4, (2, 2, 1)), UOp(Ops.INDEX, (reshape(B4, (2, 2, 1)),)))
mi_row("zx_pd44", pad(Q44, (0, 0), (4, 4)), UOp(Ops.INDEX, (pad(Q44, (0, 0), (4, 4)),)))

print("== E: store_hazard_boundary + fix_store_hazard ==")
def shb(nm, s):
  row(f"shb_{nm}", int(P.store_hazard_boundary(s)))
  row(f"shb_{nm}_in", ident4(s))

HB = buf((4,), 0, name="hb")
HB2 = buf((4,), 1, name="hb2")
HC = C(7)
shb("buffer", HB)
shb("const", HC)
shb("copy", UOp(Ops.COPY, (HB,), arg=ParamArg(slot=0, dtype=I32, size=4, device="CPU")))
shb("after_no_store", after(HB, E4))
shb("after_store_same", after(HB, end(store(HB, HC))))
shb("after_store_diff", after(HB, end(store(HB2, HC))))
shb("after_store_two", after(HB, end(store(HB2, HC)), end(store(HB, HC))))
shb("after_store_last", after(HB, end(store(HB, HC)), end(store(HB2, HC))))
shb("stage", UOp(Ops.STAGE, (HB,), arg=type("B", (), {"device": "CPU"})()))
shb("store", store(HB, HC))

def fsh(nm, tgt, src):
  row(f"fsh_{nm}_target", ident4(tgt))
  row(f"fsh_{nm}_src", ident4(src))
  row(f"fsh_{nm}_base_in", int(tgt.base in src.toposort(enter_calls=False)))
  try:
    ret = P.fix_store_hazard(tgt, src)
  except Exception as e:
    row(f"fsh_{nm}_ret", f"RAISE:{type(e).__name__}:{e}")
    return
  row(f"fsh_{nm}_ret", "None" if ret is None else ident4(ret))

fsh("nomatch", HB, HB2)
fsh("plain", HB, HC)
fsh("selfstore", HB, store(HB, HC))
fsh("perm_in_src", HB, permute(reshape(HB, (2, 2)), (1, 0)))
fsh("flip_in_src", HB, flip(reshape(HB, (2, 2)), (True, False)))
fsh("pad_in_src", HB, pad(HB, (0,), (4,)))
fsh("expand_in_src", HB, expand(HB, (4, 4)))
fsh("shr_tgt_plain", shrink(HB, (0,), (2,)), HC)
fsh("shr_tgt_shrsrc", shrink(HB, (0,), (2,)), shrink(HB, (0,), (2,)))
fsh("perm_tgt_plain", permute(HB, (0,)), HC)
fsh("big", buf((8,), 2, name="bb"), UOp(Ops.ADD, (buf((8,), 2, name="bb"), buf((8,), 3, name="bc"))))
# ===========================================================================
# F. `found_after` -- prepare.py:45-53.  A `ctx[x] = after` WRITE, so the row is
#    the pair: the node it wrote (`x`) and the node it wrote FOR (`after`).
#    `argsort` is the permutation and the WHERE arm's shrink marg is the tuple
#    `(o, s+o)` -- both are the arithmetic.
# ===========================================================================
print("== F: found_after ==")
def marg_s(u):
  if u.op not in GroupOp.Movement: return "-"
  out = []
  for m in u.marg:
    out.append(str(tuple(m)) if isinstance(m, (tuple, list)) else str(m))
  return ",".join(out)

def fa_row(nm, src, after0):
  ctx = {}
  try:
    P.found_after(ctx, after0, src)
  except Exception as e:
    row(f"fa_{nm}_ret", f"RAISE:{type(e).__name__}:{e}")
    return
  ks = list(ctx.keys())
  row(f"fa_{nm}_nk", len(ks))
  if not ks: row(f"fa_{nm}_ret", "EMPTY"); return
  k = ks[0]
  row(f"fa_{nm}_x", ident4(k))
  row(f"fa_{nm}_a", ident4(ctx[k]))
  row(f"fa_{nm}_marg", marg_s(src))
  row(f"fa_{nm}_argsort", ",".join(str(a) for a in argsort(src.marg)) if src.op is Ops.PERMUTE else "-")

FA_B = buf((4,), 0, name="fab")
FA_B8 = buf((8,), 2, name="fab8")
FA_Q = reshape(buf((16,), 1, name="faq"), (4, 4))
FA_AF = after(FA_B, end(FA_B))
FA_AF2 = after(FA_Q, end(FA_Q))
FA_AF3 = after(reshape(FA_B8, (2, 2, 2)), end(FA_B8))
fa_row("perm", permute(reshape(FA_B, (2, 2)), (1, 0)), after(reshape(FA_B, (2, 2)), end(FA_B)))
fa_row("perm2", permute(FA_Q, (1, 0)), FA_AF2)
fa_row("perm3", permute(reshape(FA_Q, (4, 4, 1)), (2, 0, 1)), after(reshape(FA_Q, (4, 4, 1)), end(FA_Q)))
fa_row("rs", reshape(FA_B, (2, 2)), FA_AF)
fa_row("rs3", reshape(FA_B8, (2, 2, 2)), FA_AF3)
fa_row("cast_half", cast(FA_B, dtypes.half), FA_AF)
fa_row("cast_int", cast(FA_B, I32), FA_AF)
fa_row("plain", FA_B, FA_AF)
# the WHERE arm needs `x.src[2].base.is_invalid` and `x.src[1].op is PAD`
def invalid_const():
  from tinygrad.dtype import Invalid
  return UOp(Ops.CONST, arg=Invalid, src=())
PADV = pad(FA_Q, (0, 0), (4, 4))
fa_row("where", where(C(1), PADV, invalid_const()), FA_AF2)
fa_row("where_nopad", where(C(1), FA_Q, invalid_const()), FA_AF2)
fa_row("where_off", where(C(1), pad(FA_Q, (1, 1), (4, 4)), invalid_const()), FA_AF2)
fa_row("where_valid", where(C(1), PADV, FA_Q), FA_AF2)

# ===========================================================================
# G. `split_reduceop` -- prepare.py:103-125.  PURE ARITHMETIC: two prods, a
#    threshold, a candidate search with a `range(...)` and a `%`, the split
#    shape, the PERMUTE tuple that moves the split axis LAST, and the two
#    `_rop` shapes.
# ===========================================================================
print("== G: split_reduceop ==")
def sr_read(ret):
  """the SPLIT AXIS and the SPLIT SHAPE, read off the graph CPython returned:
     the PERMUTE that moves the split axis LAST, and the RESHAPE under it."""
  for u in ret.toposort():
    if u.op is Ops.PERMUTE:
      rs = u.src[0]
      shp = tuple(int(s.val) for s in rs.src[1].src)
      last = list(u.arg)[-1]
      return shp, tuple(u.arg), last, shp.index(shp[0])
  return None

def sr_row(nm, red, x):
  row(f"sr_{nm}_red", ident4(red))
  row(f"sr_{nm}_x", ident4(x))
  row(f"sr_{nm}_nax", red.arg[1])
  row(f"sr_{nm}_prodx", prod(x.shape))
  row(f"sr_{nm}_prodred", prod(red.shape))
  row(f"sr_{nm}_ratio", prod(x.shape)//prod(red.shape))
  row(f"sr_{nm}_thr", prod(x.shape)//prod(red.shape) >= 32768)
  try:
    ret = P.split_reduceop(red, x)
  except Exception as e:
    row(f"sr_{nm}_ret", f"RAISE:{type(e).__name__}:{e}")
    return
  if ret is None:
    row(f"sr_{nm}_ret", "None"); return
  row(f"sr_{nm}_ret", ident4(ret))
  row(f"sr_{nm}_ret_topo", tsq(ret))
  got = sr_read(ret)
  if got is None: row(f"sr_{nm}_split", "NOPERM"); return
  shp, arg, last, dim = got
  row(f"sr_{nm}_split", "x".join(str(v) for v in shp))
  row(f"sr_{nm}_perm", ",".join(str(v) for v in arg))
  row(f"sr_{nm}_last", last)
  row(f"sr_{nm}_dim", dim)
  row(f"sr_{nm}_div", shp[0])

SR_1M = buf((1 << 20,), 0, name="sr1m")
SR_4M = buf((1 << 22,), 1, name="sr4m")
SR_Q = reshape(buf((1 << 22,), 2, name="sr4mb"), (2048, 2048))
SR_T = reshape(buf((1 << 25,), 3, name="sr32m"), (8, 4, 1 << 20))
sr_row("ratio_small", reduce(SR_1M, Ops.ADD, 1), reshape(SR_1M, (1024, 1024)))
sr_row("full1", reduce(SR_1M, Ops.ADD, 1), SR_1M)
sr_row("full2", reduce(SR_4M, Ops.ADD, 1), SR_4M)
sr_row("q", reduce(SR_Q, Ops.ADD, 1), SR_Q)
sr_row("q2", reduce(reshape(SR_Q, (64, 32, 2048)), Ops.ADD, 2), reshape(SR_Q, (64, 32, 2048)))
sr_row("t", reduce(reshape(SR_T, (8, 4, 1 << 20)), Ops.ADD, 1), reshape(SR_T, (8, 4, 1 << 20)))
sr_row("t2", reduce(reshape(SR_T, (8, 4, 1 << 20)), Ops.ADD, 3), reshape(SR_T, (8, 4, 1 << 20)))
sr_row("q3", reduce(reshape(SR_Q, (64, 32, 2048)), Ops.ADD, 1), reshape(SR_Q, (64, 32, 2048)))
sr_row("zero", reduce(buf((0,), 4, name="sr0"), Ops.ADD, 1), buf((0,), 4, name="sr0"))

# ===========================================================================
# H. `resolve_function` -- prepare.py:127-150.  ITS RAISES are the refusals and
#    they are the rows: three `TypeError`s with a slot, a size and a dtype.
# ===========================================================================
print("== H: resolve_function ==")
def body(*xs): return UOp(Ops.SINK, tuple(xs))
def alloc0(slot=9, size=4, dt=I32):
  return UOp(Ops.ALLOC, arg=ParamArg(slot=slot, dtype=dt, size=size, addrspace=AddrSpace.GLOBAL))
def param(slot, size=None, dt=I32):
  kw = {"slot": slot, "dtype": dt}
  if size is not None: kw["size"] = size
  return UOp(Ops.PARAM, arg=ParamArg(**kw))
from tinygrad.uop.ops import CallInfo
def call(bdy, *args, precompile=False):
  return UOp(Ops.CALL, (bdy,)+args, arg=CallInfo(precompile=precompile))

def rf_row(nm, c):
  row(f"rfn_{nm}_in", ident4(c))
  try:
    ret = P.resolve_function(c)
  except TypeError as e:
    row(f"rfn_{nm}_ret", f"TypeError: {e}")
    return
  except Exception as e:
    row(f"rfn_{nm}_ret", f"{type(e).__name__}: {e}")
    return
  if ret is None: row(f"rfn_{nm}_ret", "None")
  else: row(f"rfn_{nm}_ret", ident4(ret))

PA = buf((4,), 0, name="pa")
PB = buf((4,), 1, name="pb")
rf_row("notcall", PA)
rf_row("inline0", call(body(C(0), C(3)), PA))
rf_row("ok", call(body(store(param(0, 4), C(1))), PA))
rf_row("ok3", call(body(store(param(0, 4), C(1)), store(param(1, 4), C(2))), PA, PB))
rf_row("sizesmall", call(body(store(param(0, 3), C(1))), PA))
rf_row("sizebig", call(body(store(param(0, 5), C(1))), PA))
rf_row("scalargiven", call(body(store(param(0, None), C(1))), PA))
rf_row("dtypemismatch", call(body(store(param(0, 4, dtypes.float32), C(1))), PA))
rf_row("negslot", call(body(store(param(0, 4), C(1)), store(param(-1, 4), C(2))), PA, PB))
rf_row("missingarg", call(body(store(param(0, 4), C(1)), store(param(1, 4), C(2))), PA))
rf_row("precompiled", call(body(store(param(0, 4), C(1))), PA, precompile=True))
rf_row("alloc", call(body(store(alloc0(), C(1))), PA))
rf_row("moved", call(body(store(param(0, 4), C(1))), reshape(PA, (2, 2))))

# ===========================================================================
# I. `expand_bitcast` -- prepare.py:153-162.  THE ITEMSIZE ARITHMETIC: two
#    itemsizes, `rate = ns//os`, a reshape that appends `(last//rate, rate)`,
#    and the shift amounts `8*i*os` / `8*i*ns`.
# ===========================================================================
print("== I: expand_bitcast ==")
def eb_row(nm, bc):
  x = bc.src[0]
  row(f"eb_{nm}_in", ident4(bc))
  row(f"eb_{nm}_ns", bc.dtype.itemsize)
  row(f"eb_{nm}_os", x.dtype.itemsize)
  try:
    ret = P.expand_bitcast(bc)
  except Exception as e:
    row(f"eb_{nm}_ret", f"RAISE:{type(e).__name__}:{e}")
    return
  if ret is None: row(f"eb_{nm}_ret", "None"); return
  row(f"eb_{nm}_ret", ident4(ret))
  row(f"eb_{nm}_ret_topo", tsq(ret))

def bcast(x, dt): return UOp(Ops.BITCAST, (x,), arg=dt)
def dbuf(n, dt, slot):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=n*dt.itemsize, name=f"d{slot}", device="CPU"))
eb_row("same", bcast(dbuf(4, I32, 0), I32))
eb_row("same_f", bcast(dbuf(4, dtypes.float32, 1), dtypes.float32))
eb_row("i32f16", bcast(dbuf(4, I32, 2), dtypes.float16))
eb_row("f16i32", bcast(dbuf(4, dtypes.float16, 3), I32))
eb_row("i8i32", bcast(dbuf(4, dtypes.int8, 4), I32))
eb_row("i32i8", bcast(dbuf(4, I32, 5), dtypes.int8))
eb_row("f32f16", bcast(dbuf(4, dtypes.float32, 6), dtypes.float16))
eb_row("i64i32", bcast(dbuf(4, I64, 7), I32))
eb_row("i32i64", bcast(dbuf(4, I32, 8), I64))
eb_row("i16i32", bcast(dbuf(4, dtypes.int16, 9), I32))

# ===========================================================================
# J. `copy_to_anon_store` / `stage_to_anon_store` / `materialize_cross_device_src`
#    -- prepare.py:164-182.  `prod(x.max_shape)` and `shrink_to(copy.shape)`.
# ===========================================================================
print("== J: anon store / cross device ==")
def cas_row(nm, x, cp):
  row(f"cas_{nm}_x", ident4(x))
  row(f"cas_{nm}_copy", ident4(cp))
  try: ret = P.copy_to_anon_store(x, cp)
  except Exception as e: row(f"cas_{nm}_ret", f"RAISE:{type(e).__name__}:{e}"); return
  row(f"cas_{nm}_ret", "None" if ret is None else ident4(ret))
  row(f"cas_{nm}_ret_topo", tsq(ret) if ret is not None else "None")

def sas_row(nm, x, stg):
  row(f"sas_{nm}_x", ident4(x))
  row(f"sas_{nm}_stg", ident4(stg))
  try: ret = P.stage_to_anon_store(x, stg)
  except Exception as e: row(f"sas_{nm}_ret", f"RAISE:{type(e).__name__}:{e}"); return
  row(f"sas_{nm}_ret", "None" if ret is None else ident4(ret))
  row(f"sas_{nm}_ret_topo", tsq(ret) if ret is not None else "None")

def mcd_row(nm, dest, src):
  row(f"mcd_{nm}_dest", ident4(dest))
  row(f"mcd_{nm}_src", ident4(src))
  row(f"mcd_{nm}_srcev", src.device)
  row(f"mcd_{nm}_desteq", int(dest.device == src.device))
  try: ret = P.materialize_cross_device_src(dest, src)
  except Exception as e: row(f"mcd_{nm}_ret", f"RAISE:{type(e).__name__}:{e}"); return
  row(f"mcd_{nm}_ret", "None" if ret is None else ident4(ret))

def bufd(shape=(4,), slot=0, dev="CPU", dt=I32, name="x"):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=prod(shape), name=name, device=dev))
J_C = bufd((4,), 0, "CPU", I32, "cpu")
J_G = bufd((4,), 1, "GPU", I32, "gpu")
J_M = reshape(bufd((8,), 2, "CPU", I32, "cpu2"), (2, 4))
J_CP = UOp(Ops.COPY, (J_C,), arg=ParamArg(slot=0, dtype=I32, size=4, device="CPU"))
J_CP2 = UOp(Ops.COPY, (J_M,), arg=ParamArg(slot=0, dtype=I32, size=8, device="CPU"))
J_STG = UOp(Ops.STAGE, (J_C,), arg=type("B", (), {"device": "CPU"})())
cas_row("flat", J_C, J_CP)
cas_row("moved", J_M, J_CP2)
sas_row("flat", J_C, J_STG)
sas_row("moved", J_M, J_STG)
mcd_row("same", J_C, J_C)
mcd_row("cross", J_C, J_G)
mcd_row("srcnone", J_C, C(1))
mcd_row("crossm", J_C, reshape(bufd((8,), 3, "GPU", I32, "gpu2"), (2, 4)))
# a cross-device src with NO buffer identity: `has_buffer_identity` (ops.py:952)
# is False for an INDEX, and `device` is the first device over its srcs.
GP = UOp(Ops.PARAM, arg=ParamArg(slot=7, dtype=I32, size=4, addrspace=AddrSpace.GLOBAL))
GP.name = "gp"
GPIX = UOp(Ops.INDEX, (GP, rng(4, 0)))
mcd_row("alu_cross", J_C, GPIX)
mcd_row("alu_same", J_C, UOp(Ops.INDEX, (PA, rng(4, 0))))
mcd_row("moved_cross", J_C, UOp(Ops.INDEX, (reshape(bufd((8,), 8, "GPU", I32, "gpu3"), (2, 4)), rng(4, 0))))

# ===========================================================================
# K. `forward_call_outputs` -- prepare.py:11-38.  A WALK over `sink.src` with
#    FOUR branches and a `placed` substitution map.  The rows are the walk ORDER
#    (which item became which sink src) plus the four facts.
# ===========================================================================
print("== K: forward_call_outputs ==")
def fco_row(nm, sink):
  row(f"fco_{nm}_in", ident4(sink))
  row(f"fco_{nm}_nin", len(sink.src))
  try: ret = P.forward_call_outputs(sink)
  except Exception as e:
    row(f"fco_{nm}_ret", f"RAISE:{type(e).__name__}:{e}")
    return
  row(f"fco_{nm}_ret", ident4(ret))
  row(f"fco_{nm}_topo", tsq(ret))
  row(f"fco_{nm}_nout", len(ret.src))
  for k, s in enumerate(ret.src):
    row(f"fco_{nm}_o{k}", s.op.name)
  row(f"fco_{nm}_ids", ",".join("1" if s is None else "0" for s in ret.src))
  # the placed map's SIZE, read by re-running forward_call_outputs under a dict
  # probe is NOT possible (it is local), so the size is read from the RESULT:
  # every `placed` hit replaced `st.src[1]` in an item slot.
  row(f"fco_{nm}_after", sum(1 for s in ret.src if s.op is Ops.AFTER))
  row(f"fco_{nm}_store", sum(1 for s in ret.src if s.op is Ops.STORE))

K_A = bufd((4,), 0, "CPU", I32, "ka")
K_B = bufd((4,), 1, "CPU", I32, "kb")
K_G = bufd((4,), 2, "GPU", I32, "kg")
K_C = C(3)
def storef(d, v): return UOp(Ops.STORE, (d, v))
def endf(x): return UOp(Ops.END, (x,))
fco_row("empty", UOp(Ops.SINK, ()))
fco_row("const", UOp(Ops.SINK, (K_C,)))
fco_row("after", UOp(Ops.SINK, (after(K_A, endf(storef(K_A, K_C))),)))
fco_row("after_k", UOp(Ops.SINK, (after(K_A, endf(K_A)),)))
fco_row("plain_store", UOp(Ops.SINK, (storef(K_A, K_B),)))
fco_row("two_after", UOp(Ops.SINK, (after(K_A, endf(storef(K_A, K_C))), after(K_B, endf(storef(K_B, K_C))))))
# `item is AFTER(nsrc 2) and item.src[1].op is STORE` -> `st = item.src[1]`
fco_row("after_store2", UOp(Ops.SINK, (after(K_A, storef(K_A, K_C)),)))
# a STAGE src: the `src.op is Ops.STAGE` arm of the placement
K_STG = UOp(Ops.STAGE, (K_B,), arg=type("B", (), {"device": "CPU"})())
fco_row("stage_src", UOp(Ops.SINK, (after(K_A, endf(storef(K_A, K_STG))),)))
fco_row("stage_and_buf", UOp(Ops.SINK, (after(K_A, endf(storef(K_A, K_STG))), after(K_B, endf(storef(K_B, K_C))))))
# a COPY src
K_CPY = UOp(Ops.COPY, (K_A,), arg=ParamArg(slot=0, dtype=I32, size=4, device="CPU"))
fco_row("copy_src", UOp(Ops.SINK, (after(K_G, endf(storef(K_G, K_CPY))),)))
# the same base twice: `key not in placed` is the gate
fco_row("dup_base", UOp(Ops.SINK, (after(K_A, endf(storef(K_A, K_C))), after(K_A, endf(storef(K_A, K_B))))))
fco_row("mismatch_target", UOp(Ops.SINK, (after(K_A, endf(storef(K_B, K_C))),)))

# ===========================================================================
# L. `prepare_rangeify` -- prepare.py:271-278.  THE FOUR STEPS, and the gate is
#    four facts plus the src op sequence AT EVERY STEP, because a scheduling pass
#    can leave the node count and the root untouched while reordering srcs.
# ===========================================================================
print("== L: prepare_rangeify ==")
from tinygrad.uop.ops import graph_rewrite
from tinygrad.schedule.multi import multi_pm

def pipe(nm, sink):
  row(f"pr_{nm}_in", ident4(sink))
  try:
    t0 = P.forward_call_outputs(sink)
    t1 = graph_rewrite(t0, multi_pm, name="multi_pm")
    t2 = graph_rewrite(t1, P.pm_mops+P.pm_inline_calls+P.pm_disk_copy, name="inline calls")
    t3 = graph_rewrite(t2, P.pm_mops+P.earliest_rewrites, bottom_up=True, name="earliest rewrites")
  except Exception as e:
    row(f"pr_{nm}_err", f"{type(e).__name__}: {e}")
    return
  for k, t in enumerate((t0, t1, t2, t3)):
    row(f"pr_{nm}_s{k}", ident4(t))
    row(f"pr_{nm}_s{k}_topo", tsq(t))
  # the composed identity, which is what `prepare_rangeify` returns
  try: ret = P.prepare_rangeify(sink)
  except Exception as e:
    row(f"pr_{nm}_ret", f"RAISE:{type(e).__name__}:{e}"); return
  row(f"pr_{nm}_ret", ident4(ret))
  row(f"pr_{nm}_ret_topo", tsq(ret))

P_A = bufd((4,), 0, "CPU", I32, "pa")
P_B = bufd((4,), 1, "CPU", I32, "pb")
P_G = bufd((4,), 2, "GPU", I32, "pg")
P_C1 = C(1)
P_ALU = UOp(Ops.ADD, (P_A, P_B))
P_ST = UOp(Ops.STORE, (P_A, P_ALU))
P_SNK = UOp(Ops.SINK, (P_ST,))
pipe("store", P_SNK)
pipe("after", UOp(Ops.SINK, (after(P_A, endf(P_ST)),)))
pipe("const", UOp(Ops.SINK, (P_C1,)))
pipe("after2", UOp(Ops.SINK, (after(P_A, endf(storef(P_A, P_ALU))), after(P_B, endf(storef(P_B, P_ALU))))))
pipe("copy", UOp(Ops.SINK, (storef(P_G, P_A),)))
pipe("mov", UOp(Ops.SINK, (storef(P_A, reshape(P_B, (2, 2))),)))
pipe("index", UOp(Ops.SINK, (storef(P_A, UOp(Ops.INDEX, (P_B, rng(4, 0)))),)))
pipe("empty", UOp(Ops.SINK, ()))

# ===========================================================================
# M. PER-RULE FIRING.  For every table and every fixture node: how many rules
#    CLAIM it (the pattern matches), which ones, and what `rewrite` -- CPython's
#    OWN first-wins scan at ops.py:1605 -- returns.  `claim` is the row that can
#    separate a first-wins fold from a conjunction, so a fixture with a COUNT
#    above one is the only fixture that can.
# ===========================================================================
print("== M: per-rule firing ==")
def claims(pm, u):
  out = []
  for i, (pat, f) in enumerate(pm.patterns):
    try:
      if pat.match(u, {}): out.append(i)
    except Exception: out.append(-1 - i)
  return out

def fire_row(tn, pm, u, nm):
  cl = claims(pm, u)
  row(f"cl_{tn}_{nm}", ",".join(str(i) for i in cl) if cl else "-")
  row(f"cl_{tn}_{nm}_n", len(cl))
  try:
    ret = pm.rewrite(u, {})
  except Exception as e:
    row(f"cl_{tn}_{nm}_rw", f"RAISE:{type(e).__name__}:{e}")
    return
  if ret is None: row(f"cl_{tn}_{nm}_rw", "None")
  else: row(f"cl_{tn}_{nm}_rw", ident4(ret))

# fixture nodes for the rule scan
FIX = {}
FIX["const"] = C(1)
FIX["buffer"] = P_A
FIX["alu"] = UOp(Ops.ADD, (P_A, P_B))
FIX["store"] = P_ST
FIX["after"] = after(P_A, endf(P_ST))
FIX["sink"] = P_SNK
FIX["sink_mov"] = UOp(Ops.SINK, (reshape(P_A, (2, 2)), P_B))
FIX["after_mov"] = after(reshape(P_A, (2, 2)), endf(P_A))
FIX["index"] = UOp(Ops.INDEX, (P_B, rng(4, 0)))
FIX["index_mov"] = UOp(Ops.INDEX, (reshape(P_B, (2, 2)), rng(2, 0), rng(2, 1)))
FIX["index_after"] = UOp(Ops.INDEX, (after(P_B, endf(P_B)), rng(4, 0)))
FIX["mop_after"] = reshape(after(P_B, endf(P_B)), (2, 2))
FIX["copy"] = UOp(Ops.COPY, (P_A,), arg=ParamArg(slot=0, dtype=I32, size=4, device="CPU"))
FIX["stage"] = UOp(Ops.STAGE, (P_B,), arg=type("B", (), {"device": "CPU"})())
FIX["stage_buf"] = UOp(Ops.STAGE, (P_A,), arg=type("B", (), {"device": "CPU"})())
FIX["xstore"] = UOp(Ops.STORE, (P_G, P_A))
FIX["copystore"] = UOp(Ops.STORE, (P_A, UOp(Ops.COPY, (P_B,), arg=ParamArg(slot=0, dtype=I32, size=4, device="CPU"))))
FIX["rsstore"] = UOp(Ops.STORE, (reshape(P_A, (2, 2)), reshape(P_B, (2, 2))))
FIX["hazard"] = storef(P_A, permute(P_A, (0,)))
FIX["dedup"] = UOp(Ops.SINK, (after(P_A, endf(storef(P_A, P_B)), after(P_A, endf(storef(P_A, P_B)))),))
FIX["bitcast"] = bcast(dbuf(4, I32, 0), dtypes.float16)
FIX["zero"] = UOp(Ops.SINK, (buf((0,), 11, name="pz"),))
FIX["red0"] = reduce(buf((0,), 12, name="pz2"), Ops.ADD, 1)
FIX["detach"] = UOp(Ops.DETACH, (P_A,))
FIX["contigbwd"] = UOp(Ops.CONTIGUOUS_BACKWARD, (P_A,))
FIX["allred"] = UOp(Ops.ALLREDUCE, (P_A,), arg=(Ops.ADD, P_A.device))
FIX["reduce"] = reduce(reshape(buf((1 << 20,), 13, name="prm"), (1024, 1024)), Ops.ADD, 1)
FIX["call"] = call(body(storef(param(0, 4), C(1))), P_A)
FIX["after_sink"] = after(P_A, P_SNK)
FIX["store_after"] = storef(P_A, after(P_B, endf(P_B)))
FIX["store_copy_src"] = UOp(Ops.STORE, (P_A, UOp(Ops.COPY, (P_B,), arg=ParamArg(slot=0, dtype=I32, size=4, device="GPU"))))
FIX["bitstore"] = UOp(Ops.STORE, (bcast(P_A, dtypes.float32), P_B))
FIX["stage_disk_x"] = UOp(Ops.SINK, (UOp(Ops.STAGE, (UOp(Ops.COPY, (P_A,), arg=ParamArg(slot=0, dtype=I32, size=4, device="DISK:1"))), arg=type("B", (), {"device": "CPU"})()),))

for _tn, _pm in TABLES:
  for _fn, _fu in sorted(FIX.items()):
    fire_row(_tn, _pm, _fu, _fn)

# ===========================================================================
# N. THE SPLIT SEARCH, AS A PURE FUNCTION.  prepare.py:117-122 is
#      split_candidates = [(i,d) for i in range(reduce.arg[1])
#                          for d in range(min(256, 2**22//prod(reduce.shape)), 8-1, -1)
#                          if x.shape[i]%d==0 and not is_expanded[i]]
#      dim_to_split, divisor = split_candidates[0]
#      splitted_shape = x.shape[:dim] + (divisor,) + (x.shape[dim]//divisor,) + x.shape[dim+1:]
#      permute(tuple([d for d in range(len) if d!=dim] + [dim]))
#    `is_expanded` is W4: it needs `x.index(...)` + `substitute(extra_pm=pm_mops)`,
#    which is ops.py:1273 and the pm_mops rewrite.  It is a PARAMETER here and it
#    is supplied by tinygrad's OWN call (the `exp_vec` rows), never typed.
# ===========================================================================
print("== N: the split search, pure ==")
def exp_vec(x):
  """`is_expanded` from prepare.py:113-115, verbatim, through tinygrad's own
     `UOp.index` and `UOp.substitute`.  W4 says the BEND side cannot compute it;
     this is the measurement of what it IS."""
  indexed = x.index(*[UOp.range(s, i) if (sx := UOp.const(s)).simplify().vmin == s else 0 for i, s in enumerate(x.shape)])
  rn = [y.arg[0] for y in indexed.substitute({x.base: UOp(Ops.NOOP)}, extra_pm=P.pm_mops).ranges]
  return [i not in rn for i in range(len(x.shape))]

def srp_row(nm, nax, prodred, xs, expanded):
  row(f"srp_{nm}_in", f"nax={nax} prodred={prodred} xs={'x'.join(str(v) for v in xs)} exp={','.join('1' if v else '0' for v in expanded)}")
  if prodred == 0:
    row(f"srp_{nm}_cap", 0); row(f"srp_{nm}_n", 0); row(f"srp_{nm}_cand", "-"); return
  cap = min(256, (1 << 22)//prodred)
  row(f"srp_{nm}_cap", cap)
  cands = [(i, d) for i in range(nax)
                     for d in range(cap, 8-1, -1)
                     if xs[i] % d == 0 and not expanded[i]]
  row(f"srp_{nm}_n", len(cands))
  row(f"srp_{nm}_all", ",".join(f"{i}:{d}" for i, d in cands[:8]) if cands else "-")
  if not cands:
    row(f"srp_{nm}_cand", "-"); row(f"srp_{nm}_split", "-"); row(f"srp_{nm}_perm", "-")
    row(f"srp_{nm}_dim", "-"); row(f"srp_{nm}_div", "-"); return
  dim, dv = cands[0]
  row(f"srp_{nm}_cand", f"{dim}:{dv}")
  sp = list(xs[:dim]) + [dv, xs[dim]//dv] + list(xs[dim+1:])
  row(f"srp_{nm}_split", "x".join(str(v) for v in sp))
  row(f"srp_{nm}_perm", ",".join(str(v) for v in [d for d in range(len(sp)) if d != dim] + [dim]))
  row(f"srp_{nm}_dim", dim)
  row(f"srp_{nm}_div", dv)

def srp_live(nm, nax, red, x):
  srp_row(nm, nax, prod(red.shape), list(x.shape), exp_vec(x))

srp_row("t_1m", 1, 1, [1 << 20], [True])
srp_row("t_cap", 1, 16, [1 << 20], [True])
srp_row("t_ne", 1, 1, [1 << 20], [False])
srp_row("t_64", 2, 1, [64, 32], [False, False])
srp_row("t_64e", 2, 1, [64, 32], [True, False])
srp_row("t_64b", 2, 1, [64, 32], [False, True])
srp_row("t_zero", 1, 0, [1024], [True])
srp_row("t_7", 1, 1, [7], [True])
srp_row("t_8", 1, 1, [8], [True])
srp_row("t_9", 1, 1, [9], [True])
srp_row("t_256", 1, 1, [256], [True])
srp_row("t_12", 1, 1, [12], [True])
srp_row("t_3d", 3, 1, [8, 4, 1 << 20], [True, True, True])
srp_row("t_3dm", 3, 1, [8, 4, 1 << 20], [False, False, False])
srp_row("t_2d", 2, 4096, [2048, 2048], [True, True])
srp_row("t_big", 1, 1, [1 << 26], [True])
srp_live("L_1m", 1, reduce(buf((1 << 20,), 20, name="L1"), Ops.ADD, 1), buf((1 << 20,), 20, name="L1"))
srp_live("L_2d", 1, reduce(reshape(buf((1 << 22,), 21, name="L2"), (2048, 2048)), Ops.ADD, 1),
         reshape(buf((1 << 22,), 21, name="L2"), (2048, 2048)))
srp_live("L_3d", 2, reduce(reshape(buf((1 << 25,), 22, name="L3"), (8, 4, 1 << 20)), Ops.ADD, 2),
         reshape(buf((1 << 25,), 22, name="L3"), (8, 4, 1 << 20)))

# ===========================================================================
# O. `expand_bitcast`'s ARITHMETIC, as a pure function of (ns, os, last, disk).
#    prepare.py:155-162.  `rate = ns//os`, the reshape appends
#    `(x.shape[-1]//rate, rate)`, the UP shifts are `8*i*os` and the DOWN shifts
#    are `8*i*ns`, and the answer is the two branches or None.
# ===========================================================================
print("== O: expand_bitcast arithmetic, pure ==")
def ebp_row(nm, ns, os, last, disk):
  row(f"ebp_{nm}_in", f"ns={ns} os={os} last={last} disk={1 if disk else 0}")
  row(f"ebp_{nm}_same", int(ns == os))
  row(f"ebp_{nm}_disk", int(bool(disk)))
  if ns == os: tag = "NONE"
  elif disk: tag = "NONE"
  elif ns > os:
    rate = ns // os
    tag = "UP"
  else:
    rate = os // ns
    tag = "DOWN"
  row(f"ebp_{nm}_tag", tag)
  if tag == "NONE": return
  row(f"ebp_{nm}_rate", rate)
  row(f"ebp_{nm}_nparts", rate)
  row(f"ebp_{nm}_lastdiv", last // rate)
  row(f"ebp_{nm}_resh", f"{last//rate}x{rate}")
  # the shift ladder: UP is `<<8*i*os`, DOWN is `>>8*i*ns`
  step = 8 * (os if tag == "UP" else ns)
  row(f"ebp_{nm}_shstep", step)
  row(f"ebp_{nm}_sh0", 0)
  row(f"ebp_{nm}_shlast", step * (rate - 1))

for _ns, _os in ((4, 4), (2, 4), (4, 2), (1, 4), (4, 1), (8, 4), (4, 8), (2, 1), (1, 2), (8, 8)):
  for _last, _disk in ((16, False), (4, False), (3, False), (16, True)):
    ebp_row(f"{_ns}_{_os}_{_last}_{1 if _disk else 0}", _ns, _os, _last, _disk)
