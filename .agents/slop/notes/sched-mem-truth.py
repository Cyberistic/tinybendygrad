"""Truth for schedule/memory.py -- lifetimes, lane keys, nbytes, event order, arenas."""
import sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.helpers import round_up
from tinygrad.schedule.memory import _collect_bufs, _can_plan, memory_plan_rewrite
from tinygrad.runtime.support.memory import TLSFAllocator

def buf(slot, size, dev="CPU", name="b", dt=dtypes.int32):
  return UOp(Ops.BUFFER, src=(UOp(Ops.SPECIAL, arg=name, src=(UOp.const(1),)),),
             arg=ParamArg(slot=slot, dtype=dt, size=size, name=name, device=dev))

def opname(u): return u.op.name
def dkey(d): return d if isinstance(d, str) else tuple(d)
def store(dest, val): return UOp(Ops.STORE, src=(dest, val))

# ===========================================================================
# A: the collect walk. BUFFER -> itself. MSELECT/MSTACK recurse. else [].
# ===========================================================================
A = buf(0, 16, "CPU", "A")
MS = A.mselect(0)
MT = UOp(Ops.MSTACK, src=(MS, A.mselect(1)))
ST = store(A, UOp.const(1))

print("== collect ==")
print("collect_BUFFER", [opname(x) for x in _collect_bufs(A)])
print("collect_MSELECT", [x.arg.name for x in _collect_bufs(MS)])
print("collect_MSTACK", [x.arg.name for x in _collect_bufs(MT)])
print("collect_STORE", [opname(x) for x in _collect_bufs(ST)])
print("collect_CONST", [opname(x) for x in _collect_bufs(UOp.const(3))])

# ===========================================================================
# B: _can_plan. held bufs excluded; DISK/CL/WEBGPU excluded (PREFIX match).
# ===========================================================================
D = buf(2, 8, "DISK", "D"); CL = buf(3, 8, "CL:1", "C"); W = buf(4, 8, "WEBGPU", "W")
MD = buf(5, 32, ("CPU", "METAL"), "M")    # tuple device, both fine
MCL = buf(6, 32, ("CPU", "CL:1"), "MC")  # tuple whose SECOND member is CL

print("== can_plan ==")
for nm, b in (("plain", A), ("held", A), ("disk", D), ("cl", CL), ("webgpu", W), ("mdev", MD), ("mdev_cl", MCL)):
  print(f"cp_{nm}", _can_plan(b, {A} if nm == "held" else set()))

# ===========================================================================
# C: the plan internals, recomputed with tinygrad's own primitives so every
#    number is CPython-derived. A kernel's SINK carries the kernel body at
#    src[0] and the kernel ARGS at src[1:], so only the args are collectable.
# ===========================================================================
A2 = buf(10, 1024, "CPU", "A2")     # k0 store dest, never collected
B2 = buf(11, 2048, "CPU", "B2")     # k0 arg  -> copy lane
C2 = buf(12, 512,  "CPU", "C2")     # k1 arg  -> copy lane
D2 = buf(13, 256,  "CPU", "D2")     # k2 arg  -> compute lane
E2 = buf(14, 128,  "CPU", "E2")     # k2 arg  -> compute lane
F2 = buf(15, 64,   "CPU", "F2")     # k3 arg  -> compute lane, LATER so D2 free by then
DK = buf(16, 4096, "DISK", "DK")    # not plannable
KERNELS = (
  UOp(Ops.SINK, src=(store(A2, B2), B2)),                          # 0
  UOp(Ops.SINK, src=(store(A2, C2), C2)),                          # 1
  UOp(Ops.SINK, src=(UOp(Ops.ADD, src=(D2, E2)), D2, E2)),          # 2
  UOp(Ops.SINK, src=(UOp(Ops.MUL, src=(D2, F2)), D2, F2)),          # 3
)
LIN = UOp(Ops.LINEAR, src=KERNELS)

first_appearance, last_appearance, copy_bufs = {}, {}, set()
for i, si in enumerate(LIN.src):
  si_bufs = [b for src in si.src[1:] for b in _collect_bufs(src) if _can_plan(b, set())]
  for b in si_bufs:
    if b not in first_appearance: first_appearance[b] = i
    last_appearance[b] = i
  if si.src[0].op is Ops.STORE: copy_bufs.update(si_bufs)

print("== lifetimes ==")
print("n_first", len(first_appearance), "n_copy", len(copy_bufs))
order = sorted(first_appearance, key=lambda b: first_appearance[b])
for b in order:
  print(f"  {b.arg.name} first={first_appearance[b]} last={last_appearance[b]} copy={b in copy_bufs}"
        f" raw={b.max_numel()*b.dtype.itemsize} nbytes={round_up(b.max_numel()*b.dtype.itemsize,256)}"
        f" dev={dkey(b.device)}")
key_of = lambda b: (dkey(b.device), 1 if b in copy_bufs else 0)
buf_hold = {b: last_appearance[b]-first_appearance[b]+1 for b in first_appearance if b in copy_bufs}
print("buf_hold", {b.arg.name: v for b, v in buf_hold.items()})
nbytes = {b: round_up(b.max_numel()*b.dtype.itemsize, 256) for b in first_appearance}
events = sorted([(first_appearance[b], True, b) for b in first_appearance] +
                [(last_appearance[b]+1+buf_hold.get(b,0), False, b) for b in first_appearance], key=lambda x: (x[0], x[1]))
print("events", [(i, o, b.arg.name) for i, o, b in events])
print("lanes", sorted(set(key_of(b) for b in first_appearance)))
total_memory = sum(nbytes.values())*2
print("sum_nbytes", sum(nbytes.values()), "total_memory", total_memory)

offsets, peaks = {}, {}
for ln in sorted(set(key_of(b) for b in first_appearance)):
  peaks[ln] = (0, TLSFAllocator(total_memory, block_size=256, lv2_cnt=32))
for _, is_open, b in events:
  k = key_of(b)
  if is_open: offsets[b] = peaks[k][1].alloc(nbytes[b])
  else: peaks[k][1].free(offsets[b])
  peaks[k] = (max(peaks[k][0], offsets[b] + b.max_numel()*b.dtype.itemsize), peaks[k][1])
arena_sizes = {k: round_up(p, 256) for k, (p, _) in peaks.items()}
print("offsets", {b.arg.name: offsets[b] for b in order})
print("peaks", {str(k): p for k, (p, _) in peaks.items()})
print("arena_sizes", {str(k): v for k, v in arena_sizes.items()}, "n_arenas", len(arena_sizes))

# ===========================================================================
# D: what the rewrite actually produced. This is the ROW source.
# ===========================================================================
OUT = memory_plan_rewrite(LIN)
print("== rewrite ==")
print("out_op", opname(OUT), "nkernels", len(OUT.src))
seen = {}
def walk(u):
  if u in seen: return
  seen[u] = 1
  for s in u.src: walk(s)
walk(OUT)
newbs = [u for u in seen if u.op is Ops.BITCAST]
arens = [u for u in seen if u.op is Ops.BUFFER and len(u.src) == 0 and u.dtype is dtypes.int8]
print("n_nodes", len(seen), "n_bitcast", len(newbs), "n_arena", len(arens))
for u in sorted(newbs, key=lambda x: x.nbytes()):
  print(f"  bitcast nbytes={u.nbytes()} src0_nbytes={u.src[0].nbytes()} src0_shape={u.src[0].shape} src0_dtype={u.src[0].dtype}")
for u in arens: print(f"  arena nbytes={u.nbytes()} dtype={u.dtype} shape={u.shape}")
for i, k in enumerate(OUT.src):
  print(f"  k{i}", opname(k), [opname(s) for s in k.src])

# ===========================================================================
# E: a tuple-device lane, so the lane COUNT is 2 and there is a second arena.
# ===========================================================================
M1 = buf(20, 4096, ("CPU", "METAL"), "M1")
M2 = buf(21, 4096, ("CPU", "METAL"), "M2")
LIN2 = UOp(Ops.LINEAR, src=(UOp(Ops.SINK, src=(store(M1, M2), M2)),))
f2, l2, c2 = {}, {}, set()
for i, si in enumerate(LIN2.src):
  sb = [b for src in si.src[1:] for b in _collect_bufs(src) if _can_plan(b, set())]
  for b in sb:
    if b not in f2: f2[b] = i
    l2[b] = i
  if si.src[0].op is Ops.STORE: c2.update(sb)
k2_of = lambda b: (dkey(b.device), 1 if b in c2 else 0)
print("mdev_nbufs", len(f2), "mdev_lanes", sorted(set(k2_of(b) for b in f2)))
print("mdev_copy", sorted(b.arg.name for b in c2), "mdev_nbytes", [round_up(b.max_numel()*4,256) for b in f2])

# ===========================================================================
# F: a fixture with NO plannable buffers at all -> `if not first_appearance`
# ===========================================================================
LIN3 = UOp(Ops.LINEAR, src=(UOp(Ops.SINK, src=(UOp(Ops.CUSTOMI, src=(), arg="x"),)),))
f3 = {}
for i, si in enumerate(LIN3.src):
  for b in [b for src in si.src[1:] for b in _collect_bufs(src) if _can_plan(b, set())]:
    f3[b] = i
print("empty_n_first", len(f3), "is_identity", memory_plan_rewrite(LIN3) is LIN3)