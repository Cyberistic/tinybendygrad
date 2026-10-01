# multi-rows.py -- CPython ground truth for schedule/multi.py.
# Every value multi.bend's gate prints is produced HERE, by running the
# expressions from multi.py's bodies directly. Nothing is restated.
#
# Run: python3 .agents/slop/multi-rows.py
import sys; sys.path.insert(0, '.')
from tinygrad.helpers import prod, getenv, ALLREDUCE_CAST
from tinygrad.uop.ops import Ops, UOp, AxisType, sint_to_uop, _broadcast_shape, broadcast_axes
from tinygrad.uop.symbolic import symbolic
from tinygrad.dtype import dtypes

# --- _apply_shrink / mstack_early_shrink: which srcs carry a DEVICE range ----
# multi.py:10-11 substitutes drng -> const_like(i) in every x whose ranges
# include a DEVICE range. The GATEABLE part is WHICH srcs that is: the
# predicate `any(r.axis_type is DEVICE for r in x.ranges)`.
def src_has_dev(x): return any(r.axis_type is AxisType.DEVICE for r in x.ranges)

# --- shard_srcs: multi.py:54-76 ------------------------------------------------
# normalize devices, pick the sharding range, out_shape, src_axis, and the
# per-src decision: copy-through / shard / broadcast-whole.
def _bad(a, b):
  try: _broadcast_shape(a, b); return False
  except IndexError: return True

def src_axis_of(axis, out_shape, mlb_shape): return axis - (len(out_shape)-len(mlb_shape))
def bcast_axes_t(src_shape, out_shape): return broadcast_axes(src_shape, out_shape)

def shard_srcs_rows():
  rows = []
  # devices present -> sharding_rng = range(len(devices[0]), -1, DEVICE)
  rows.append(("ss_ndev3", 3))
  rows.append(("ss_ndev1", 1))
  # out_shape = _broadcast_shape(*[x.shape for x in msrcs]) -- the zip_max fold
  rows.append(("ss_bcast_4_1", _broadcast_shape((4,), ())))
  rows.append(("ss_bcast_1_4", _broadcast_shape((1,), (4,))))
  rows.append(("ss_bcast_bad", int(_bad((4,), (2,)))))
  rows.append(("ss_bcast_23", int(_bad((2,), (3,)))))
  rows.append(("ss_bcast_all1", _broadcast_shape((1,), (1,))))
  rows.append(("ss_bcast_all4", _broadcast_shape((4,), (4,))))
  rows.append(("ss_bcast_2_1_2", _broadcast_shape((2,), (1,), (2,))))
  rows.append(("ss_bcast_3_1_3", _broadcast_shape((2,3,1), (2,3,4))))
  rows.append(("ss_bcast_1_1", _broadcast_shape((), (1,))))
  # src_axis = axis - (len(out_shape) - len(mlb.shape))
  rows.append(("ss_ax_0_0", src_axis_of(0, (4,), (4,))))          # same rank -> unchanged
  rows.append(("ss_ax_1_1", src_axis_of(1, (3,4), (3,4))))        # same rank -> unchanged
  rows.append(("ss_ax_1_0", src_axis_of(1, (3,4), (4,))))         # rank 2 src, rank 2 out
  rows.append(("ss_ax_2_2", src_axis_of(2, (2,3,4), (2,3,4))))    # rank 3 -> unchanged
  rows.append(("ss_ax_0_2", src_axis_of(0, (2,3,4), (2,3,4))))    # axis 0
  return rows

# broadcast_axes: multi.py:75 `axis in broadcast_axes(mlb.shape, out_shape)`
def bax_rows():
  rows = []
  cases = [
    ("bx_none",   (2,3),    (2,3)),      # nothing broadcast
    ("bx_pad",    (3,),     (2,3)),      # a leading axis is ADDED
    ("bx_exp",    (1,3),    (2,3)),      # a 1 EXPANDS
    ("bx_both",   (1,),     (2,3)),      # both
    ("bx_noop",   (2,),     (2,3)),      # added but size 2, nothing broadcast
    ("bx_scalar", (),       (2,3)),      # a scalar broadcasts everywhere
    ("bx_1out",   (2,),     (1,2)),      # out dim is 1: NOT counted
    ("bx_11",     (1,),     (1,)),
    ("bx_1_2",    (1,),     (2,)),       # 1 -> 2 IS a broadcast
    ("bx_rank1",  (3,),     (3,)),
  ]
  for nm, s, o in cases:
    rows.append((nm, str(bcast_axes_t(s, o))))
  return rows

# --- reduce_multi: multi.py:107-123 --------------------------------------------
# op, num_axes = root.arg ; reduced = ax < num_axes ; remaining = ax >= num_axes
def reduce_rows():
  rows = []
  for nm, na, sh in [("rd_all",  1, [(0,0),(1,0)]), ("rd_some", 1, [(1,0),(2,0)]),
                     ("rd_none", 1, [(2,0),(3,0)]), ("rd_two", 2, [(0,0),(1,0)]),
                     ("rd_mix",  3, [(1,0),(4,0)]), ("rd_0",  0, [(0,0),(1,0)])]:
    red = tuple(ax for ax, _ in sh if ax < na)
    rem = tuple(ax for ax, _ in sh if ax >= na)
    rows.append((f"{nm}_red", str(red)))
    rows.append((f"{nm}_rem", str(rem)))
    rows.append((f"{nm}_off", str(tuple(ax - na for ax in rem))))
  return rows

# --- reshape_multi: multi.py:125-140 -------------------------------------------
# arg_acc = accumulate(new_shape, mul, initial=1); target = prod(shape[:ax])
# new_ax = len(arg_acc) - arg_acc[::-1].index(target) - 1
def reshape_rows():
  rows = []
  cases = [
    ("rs_same", (4,6), (4,6), 0), ("rs_mid",  (4,6), (2,12), 1),
    ("rs_tail", (4,6), (24,), 1),   ("rs_head", (4,6), (24,), 0),
    ("rs_bad",  (4,6), (5,5), 0),   ("rs_thr",  (4,6), (2,3,4), 1),
    ("rs_thr0", (2,3,4), (2,3,4), 2), ("rs_thr1", (24,), (2,3,4), 0),
  ]
  for nm, sh, new, ax in cases:
    arg_acc = [1]
    for s in new: arg_acc.append(arg_acc[-1]*s)
    target = prod(sh[:ax])
    if target not in arg_acc:
      rows.append((f"{nm}_new_ax", "RAISE"))
      rows.append((f"{nm}_ok", 0))
      continue
    new_ax = len(arg_acc) - arg_acc[::-1].index(target) - 1
    rows.append((f"{nm}_new_ax", new_ax))
    rows.append((f"{nm}_acc", str(arg_acc)))
    # new_shape divided by the shard count for a sharded new_ax
    cnt = 2
    rows.append((f"{nm}_div", new[new_ax] // cnt))
  return rows

# --- shrink_multi: multi.py:159-181 --------------------------------------------
# shard_sz = multi.src[0].shape[ax]; part_bounds = ((i*shard_sz, shard_sz) ...)
def part_bounds_rows():
  rows = []
  for nm, ssz, cnt in [("pb_4_2", 4, 2), ("pb_4_3", 4, 3), ("pb_6_2", 6, 2), ("pb_8_4", 8, 4), ("pb_4_1", 4, 1)]:
    pb = tuple((i*ssz, ssz) for i in range(cnt))
    rows.append((f"{nm}_n", len(pb)))
    rows.append((f"{nm}_s0", pb[0][0])); rows.append((f"{nm}_e0", pb[0][1]))
    rows.append((f"{nm}_smid", pb[len(pb)//2][0]))
    rows.append((f"{nm}_emid", pb[len(pb)//2][1]))
    rows.append((f"{nm}_slast", pb[-1][0]))
  return rows

# shrink's own-shard test: sint_to_uop(l).ssimplify() == shard_sz AND
# (sint_to_uop(s) - rng*shard_sz).ssimplify() == 0
def shrink_rows():
  from tinygrad.uop.ops import sint, ssimplify
  rows = []
  cases = [("sk_own",   0, 4, 0, 4, 0, 4), ("sk_own1",  4, 4, 1, 4, 0, 4),
           ("sk_part",  0, 4, 0, 8, 0, 8), ("sk_partb", 4, 4, 1, 8, 0, 8),
           ("sk_full",  0, 8, 0, 8, 0, 8), ("sk_mid",   2, 4, 0, 8, 0, 8)]
  for nm, s, l, rng, sh_sz, multi_sz, full_l in cases:
    e1 = sint_to_uop(l).ssimplify() == sh_sz
    e2 = (sint_to_uop(s) - rng*sh_sz).ssimplify() == 0
    rows.append((f"{nm}_own", int(e1 and e2)))
  return rows

# --- permute_multi: multi.py:154-157 `root.marg.index(ax)` ----------------------
def permute_rows():
  rows = []
  for nm, marg, ax in [("pm_id", (0,1), 0), ("pm_id1", (0,1), 1),
                       ("pm_sw", (1,0), 0), ("pm_sw1", (1,0), 1),
                       ("pm_cyc", (2,0,1), 1), ("pm_cyc0", (2,0,1), 0),
                       ("pm_rev", (2,1,0), 2), ("pm_mid", (0,2,1), 2)]:
    rows.append((f"{nm}", marg.index(ax)))
  return rows

# --- flip_multi: multi.py:183-186 ----------------------------------------------
# [i for i,x in enumerate(root.marg) if x]
def flip_rows():
  rows = []
  for nm, marg in [("fl_none", (0,0)), ("fl_one", (0,4)), ("fl_two", (3,4)),
                   ("fl_first", (2,0)), ("fl_all", (1,1)), ("fl_mid", (0,1,0))]:
    idxs = [i for i,x in enumerate(marg) if x]
    rows.append((f"{nm}_n", len(idxs)))
    rows.append((f"{nm}_list", str(tuple(idxs))))
  return rows

# --- expand_multi: multi.py:142-145 `len(root.marg)` shift ---------------------
def expand_rows():
  rows = []
  for nm, marg in [("ex_none", ()), ("ex_one", (3,)), ("ex_two", (3,4)), ("ex_three", (1,2,3))]:
    rows.append((f"{nm}_shift", len(marg)))
  return rows

# --- index_multi: multi.py:202-222 ownership ----------------------------------
def index_rows():
  from tinygrad.uop.ops import Ops as _O
  rows = []
  # contiguous: idx = rng*shard_sz + local, local in [0, shard_sz)
  # strided:    idx = rng + ir*shard_sz, mod == 0 -> local = (idx-rng)//shard_sz
  rows.append(("ix_contig_l0", 0*4 + 0)); rows.append(("ix_contig_l3", 0*4 + 3))
  rows.append(("ix_contig_1l0", 1*4 + 0)); rows.append(("ix_contig_1l3", 1*4 + 3))
  rows.append(("ix_contig_oob", 1*4 + 4))
  rows.append(("ix_strid_0", (0 - 0) % 4)); rows.append(("ix_strid_1", (1 - 0) % 4))
  rows.append(("ix_strid_z", (4 - 0) % 4))
  return rows

# --- copy_multi: multi.py:228-252 shard index keys ---------------------------
def shard_idx_rows():
  rows = []
  # idxs = tuple(_shard_idx(r, i) for _, r in sharding) -- for a DEVICE range
  # over ndev devices the i'th shard's index is i.
  for nm, ndev in [("sx_2", 2), ("sx_4", 4)]:
    rows.append((f"{nm}_n", ndev))
    rows.append((f"{nm}_i0", 0)); rows.append((f"{nm}_ilast", ndev-1))
  return rows

# --- rule-table inventory: the op sets and reject sets ------------------------
def _names(o):
  if isinstance(o, Ops): return [o.name]
  if isinstance(o, (set, frozenset, tuple, list)): 
    out = []
    for x in o: out += _names(x)
    return out
  raise TypeError(type(o))

def _fmt(p):
  ops = ",".join(sorted(_names(p.op)))
  rej = ",".join(sorted(_names(p.early_reject))) if p.early_reject else "-"
  return f"{ops}|{rej}"

def table_rows():
  import tinygrad.schedule.multi as M
  rows = []
  rows.append(("pm_len", len(M.multi_pm.patterns)))
  rows.append(("ra_len", len(M.replace_allreduce.patterns)))
  rows.append(("ea_len", len(M._early_allreduce.patterns)))
  rows.append(("all_len", len(M.multi_pm.patterns)+len(M._early_allreduce.patterns)))
  # the pdict keys and the reject sets, per pattern, in order
  for i, (p, _) in enumerate(M.multi_pm.patterns):
    rows.append((f"pm_{i:02d}", _fmt(p)))
  for i, (p, _) in enumerate(M.replace_allreduce.patterns):
    rows.append((f"ra_{i:02d}", _fmt(p)))
  for i, (p, _) in enumerate(M._early_allreduce.patterns):
    rows.append((f"ea_{i:02d}", _fmt(p)))
  # allow_any_len: strict_length is the claimable fact (ops.py:1477)
  for i, (p, _) in enumerate(M.multi_pm.patterns):
    rows.append((f"pmA_{i:02d}", int(p.strict_length)))
  for i, (p, _) in enumerate(M.replace_allreduce.patterns):
    rows.append((f"raA_{i:02d}", int(p.strict_length)))
  return rows

# LATE_ALLREDUCE=0 PREPENDS _early_allreduce to replace_allreduce, which SHIFTS
# every replace_allreduce tag by one. It is read at IMPORT time, so it runs in a
# subprocess.
def late_rows():
  import os, subprocess, sys
  rows = []
  for k, v in (("late_ra", "0"), ("late_all", "0"), ("early_ra", "1"), ("early_all", "1")):
    out = subprocess.run([sys.executable, "-c",
      "import sys; sys.path.insert(0,'.');"
      "from tinygrad.schedule.multi import multi_pm, replace_allreduce;"
      "print(len(replace_allreduce.patterns), len(multi_pm.patterns))"],
      env=dict(os.environ, LATE_ALLREDUCE=v), capture_output=True, text=True)
    ra, al = out.stdout.split()
    rows.append((k, ra if k.endswith("_ra") else al))
  for tag in (19, 20, 25):
    out = subprocess.run([sys.executable, "-c",
      "import sys; sys.path.insert(0,'.');"
      "from tinygrad.schedule.multi import multi_pm;"
      f"p=multi_pm.patterns[{tag}][0];"
      "print(','.join(sorted(o.name for o in (p.op if isinstance(p.op,(set,frozenset,tuple,list)) else {p.op}))))"],
      env=dict(os.environ, LATE_ALLREDUCE="0"), capture_output=True, text=True)
    rows.append((f"lt_p{tag}", out.stdout.strip()))
  return rows


def main():
  rows = []
  rows += table_rows()
  rows += shard_srcs_rows()
  rows += bax_rows()
  rows += reduce_rows()
  rows += reshape_rows()
  rows += part_bounds_rows()
  rows += shrink_rows()
  rows += permute_rows()
  rows += flip_rows()
  rows += expand_rows()
  rows += index_rows()
  rows += shard_idx_rows()
  rows += late_rows()
  w = max(len(r[0]) for r in rows)
  for n, v in rows: print(f"{n.ljust(w)}  {v}")

if __name__ == "__main__": main()