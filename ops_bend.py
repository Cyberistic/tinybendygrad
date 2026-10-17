# a bend port of the python uops emulator (the fork of ops_python.py, which is the oracle for this)
#
# tinygrad schedules onto Device['BEND'] exactly as it does PYTHON -- same Compiled device, same
# HostAllocator, same Renderer base, so the same kernels come out of the scheduler. The difference is
# where they RUN: ops_python base64-pickles the uops and walks them in this process, while BendRenderer
# writes the v1 wire packet and BendProgram hands it to tinybendygrad/runtime/ops_python.bend, one
# subprocess per launch.
#
# THE WIRE, v1.1 (ASCII text, one launch per packet). This is the executor's own format, taken from the
# header of tinybendygrad/runtime/ops_python.bend, which is authoritative for the spellings:
#
#   line 1      bendexec1 <nuops> <nbuffers>
#   uop lines   <idx>: <OP> <dtype|-> <arg|-> <src1> <src2> ...     1-based, in post-order
#   buffer ln   <nbytes> <hex-bytes>
#
# <idx> walks the renderer's own uop list in the order it arrives. That list is ALREADY in post-order:
# every uop's srcs sit at a lower index, except Ops.END and Ops.BACKEDGE, which point BACK at their
# Ops.RANGE by construction. encode() asserts the ordering rather than sorting, because a silent sort
# would hide a scheduler change that broke it, and the executor's decoder is written against post-order.
#
# <dtype> is the BARE dtype name -- "int", "uint", "float", "bool", "weakint", "void" -- which is what
# the executor's to_dtype already parses. Only the four it ports (i32 u32 f32 bool) have one; a dtype
# outside them is that executor's wall 1, and wire_dtype raises NotImplementedError naming it rather
# than emitting a name it would refuse or misread.
#
# <arg> is `-` for every op that does not need a payload, which is most of them: a RANGE's trip count is
# its src[0], a CAST's target is the line's own <dtype>, and STACK/AFTER/BITCAST carry their whole
# meaning in their srcs. Four ops carry one:
#
#   CONST   c:<decimal-int> for an int, f:<8 hex digits, the f32 bit pattern> for a float. The c:/f:
#           prefix is what tells the executor the two weak carriers apart.
#   PARAM   k:param:<nbytes>:<g|l|r|a>. There are no DEFINE_* ops in this tinygrad: ops_python.py:99,105
#           spells a PARAM plus an AddrSpace, so the addrspace rides here. g binds the next packet
#           buffer, r allocates zeros, a reads a `vals` entry. nbytes is max_numel()*dtype.itemsize, the
#           same extent ops_python gives its memoryview, so a bitcast wider than the buffer round-trips.
#   BUFFER  k:buffer:<nbytes>. Kernel-local scratch; allocates zeros and consumes NO packet buffer
#           (ops_python.py:104 allocates; only PARAM pops pbufs).
#   SPECIAL k:sp:<gidx0|gidx1|gidx2|lidx0|lidx1|lidx2>. u.arg is already that name.
#
# <nbuffers> counts the PARAMs of addrspace g or l -- one buffer line each, in uop order, because
# ops_python.py:104 pops pbufs in exactly that order. BendProgram hands them over in that same order.
#
# Two further <arg> payloads, both forced by a line of ops_python that this port has to answer:
#
#   k:vec:<max_numel>        on LOAD and STORE. ops_python.py:88,137 branch on u.max_numel()
#                             (`load_sz`, and `u.max_numel() > 1` on the store), and a real reduce DOES
#                             vectorize -- measured 4 on LOAD and STORE across a 42-kernel sweep -- so
#                             this cannot be left implicit. `-` means 1.
#   k:idx:<scale>            on INDEX and SHRINK. 0 is the ALU arm (ops_python.py:114 reindexes an ALU
#                             value); otherwise src[0].dtype.itemsize // src[0].src[0].dtype.itemsize, the
#                             BITCAST scale, and `-` is the plain 1. The image arm needs src[0]'s shape
#                             and is the executor's wall, so wire_arg raises on it.
#
# Two of its consequences reach this file:
#   - local_size is NOT a launch argument: the command line is `PACKET gx gy gz vals...`, because the
#     executor is warp 1 and reads every `lidxK` as 0. A local_size above 1 raises rather than
#     silently launching as if it were 1, and BendRenderer.has_local keeps the scheduler from making one.
#   - packet buffers are keyed by POSITION, not by an index the encoder writes, which is why WRITEBACK
#     below counts buffer PARAMs rather than reading an index out of the arg.
#
# PACKET.out is the same buffer block the input carried, one line per buffer in the same order, holding
# whatever the kernel left behind. BendProgram copies back the STORE-reachable ones and drops the rest
# (see WRITEBACK), so a read-only input is never written.
#
# The executor is compiled once into tinygrad's cache dir, keyed by ops_python.bend's mtime and size:
#   ./bin/bend tinybendygrad/runtime/ops_python.bend -o <cache>/bend-executor-<key>
# Missing ./bin/bend or ops_python.bend raises with the path it wanted. A launch is a subprocess, so the
# -o out.js lane is NOT used: bun's startup would be paid per kernel on top of the executor's own work.
#
# COST, stated rather than hidden: one subprocess per launch plus a hex round trip of every buffer. See
# the timing table in the agent report. tinygrad's runtime_cache means a program is only re-launched when
# its AST changes, so a steady-state loop pays this once per unique kernel, not once per iteration.

import os, time, struct, hashlib, functools, subprocess, tempfile, pathlib
from dataclasses import dataclass
from tinygrad.dtype import DType, AddrSpace, dtypes
from tinygrad.helpers import cache_dir, is_image_shape, to_mv
from tinygrad.device import HostAllocator, Compiled, Compiler, Program, TinyELF
from tinygrad.uop.ops import Ops, UOp
from tinygrad.runtime.ops_python import PythonRenderer

BEND = pathlib.Path(__file__).resolve().parents[2]                  # the repo root: ./bin and tinybendygrad resolve from here
BEND_SRC = BEND/"tinybendygrad"/"runtime"/"ops_python.bend"   # ONE .bend per upstream .py: the port of ops_python.py IS the executor
BEND_BIN = BEND/"bin"/"bend"

# **************** encoding ****************

# the four lanes the executor ports. Anything else -- half, bfloat16, the fp8s, float64, the narrow
# ints, int64 -- is its wall 1, and wire_dtype raises rather than emitting a name it would misread.
LANES: frozenset[DType] = frozenset({dtypes.int, dtypes.uint, dtypes.float, dtypes.bool})

def wire_dtype(u:UOp) -> str:
  # `to_dtype` is dtype.py's `getattr(dtypes, name.lower())`, so it wants the ATTRIBUTE name.
  # This used to be `INVERSE_DTYPES_DICT[u.dtype.name]`, and that map is DELETED upstream as of
  # 793abbb1 ("modernize tinygrad's dtype to match rust"), so `import tinygrad.dtype` raised
  # ImportError and the whole BEND device was dead. `u.dtype.name` is now correct on its own:
  # the rename made `DType.name` EQUAL the attribute -- uint32's name went from "unsigned int"
  # (which needed the inverse map to become "uint") to "u32", which `getattr(dtypes, "u32")`
  # resolves directly. The old comment below is what the rename invalidated.
  if u.dtype in LANES or u.dtype in (dtypes.void, dtypes.weakint, dtypes.weakfloat): return u.dtype.name
  raise NotImplementedError(f"BEND v1 has no lane for {u.dtype} (on {u.op.name}); it has {sorted(LANES, key=str)}")

def wire_width(u:UOp) -> int:
  """u.max_numel(), the element count of a vector-valued uop. ops_python's LOAD and STORE both branch
  on it (`load_sz := u.max_numel()`, `u.max_numel() > 1`), and a real reduce DOES vectorize: measured
  max_numel 4 on LOAD/STORE across 42 kernels, so this is not a shape the wire may leave implicit."""
  try: return u.max_numel()
  except RuntimeError: return 1                                   # BARRIER and friends have no shape

def wire_arg(u:UOp) -> str:
  # A1: PARAM and BUFFER plus an addrspace letter. g binds the next packet buffer, r allocates zeros,
  # a reads a vals entry. There is no `l` PARAM in practice -- ops_python gives LOCAL to BUFFER --
  # but the executor parses it, so it is spelled rather than refused.
  if u.op is Ops.BUFFER: return f"k:buffer:{u.max_numel()*u.dtype.itemsize}"
  if u.op is Ops.PARAM:
    letter = "a" if u.addrspace is AddrSpace.ALU else {"GLOBAL": "g", "REG": "r"}[u.addrspace.name]
    return f"k:param:{u.max_numel()*u.dtype.itemsize}:{letter}"
  if u.op is Ops.CONST: return f"c:{u.arg:d}" if isinstance(u.arg, int) else f"f:{struct.pack('<f', u.arg).hex()}"
  if u.op is Ops.SPECIAL: return f"k:sp:{u.arg}"
  # A3: INDEX/SHRINK carry the PRECOMPUTED scale. 0 is the ALU arm (ops_python.py:114 reindexes an
  # ALU value), otherwise src[0].dtype.itemsize // src[0].src[0].dtype.itemsize; `-` is the plain 1.
  # The image arm is unreachable without a shape, which is the executor's wall.
  if u.op in (Ops.INDEX, Ops.SHRINK):
    s = u.src[0]
    if s.addrspace is AddrSpace.ALU: return "k:idx:0"
    if is_image_shape(s._shape): raise NotImplementedError(f"BEND v1 has no image addressing for INDEX over {s._shape}")
    if s.op is Ops.BITCAST: return f"k:idx:{s.dtype.itemsize // s.src[0].dtype.itemsize}"
    return "-"
  # A2: LOAD/STORE vector width, `-` when it is 1.
  if u.op in (Ops.LOAD, Ops.STORE): return "-" if (n:=wire_width(u)) == 1 else f"k:vec:{n}"
  return "-"

def encode(uops:list[UOp]) -> str:
  """the uop half of the packet: header plus one line per uop. No buffers -- those are per-launch."""
  idx: dict[UOp, int] = {u:i for i,u in enumerate(uops)}
  # A1: <nbuffers> counts the PARAMs that bind a packet buffer, which is ops_python's pbufs order:
  # the PARAMs of addrspace g or l, in uop order. A PARAM of addrspace a reads `vals` instead.
  for u in uops:
    for s in u.src: assert s in idx, f"{u.op.name} reads {s.op.name}, which is not in the uop list"
  nbufs = sum(u.op is Ops.PARAM and u.addrspace is not AddrSpace.ALU for u in uops)
  lines = [f"bendexec1 {len(uops)} {nbufs}"]
  for i, u in enumerate(uops):
    for s in u.src: assert idx[s] < i, f"{u.op.name} at {i} reads {s.op.name} at {idx[s]}: not post-order"
    lines.append(f"{i+1}: {u.op.name} {wire_dtype(u)} {wire_arg(u)} {' '.join(str(idx[s]+1) for s in u.src)}".rstrip())
  return "\n".join(lines) + "\n"

# **************** the executor ****************

@functools.cache
def executor() -> pathlib.Path:
  """the compiled executor, built once per ops_python.bend (mtime+size keyed) and cached beside tinygrad's"""
  for p in (BEND_BIN, BEND_SRC):
    if not p.exists(): raise RuntimeError(f"BEND needs {p}, which is not there")
  st = BEND_SRC.stat()
  out = pathlib.Path(cache_dir)/f"bend-executor-{hashlib.sha256(f'{st.st_mtime_ns}:{st.st_size}'.encode()).hexdigest()[:16]}"
  if not out.exists():
    with tempfile.TemporaryDirectory() as td:
      tmp = pathlib.Path(td)/out.name
      r = subprocess.run([str(BEND_BIN), str(BEND_SRC), "-o", str(tmp)], capture_output=True, text=True)
      if r.returncode != 0:
        raise RuntimeError(f"{BEND_BIN} could not build {BEND_SRC} (exit {r.returncode}):\n{(r.stdout + r.stderr).strip()}")
      out.parent.mkdir(parents=True, exist_ok=True)
      os.replace(tmp, out)                                         # atomic: a killed build is never a stale binary
  return out

# **************** the packet, read back ****************

@dataclass(frozen=True)
class UOpLine:
  op: str
  dtype: str
  arg: str
  srcs: tuple[int, ...]

def is_buf(arg:str) -> bool:
  """A1: a PARAM that binds a packet buffer is addrspace g (or l); a is a vals entry, r is scratch."""
  return arg.startswith("k:param:") and arg.rsplit(":", 1)[1] in ("g", "l")
def buf_extent(arg:str) -> int: return int(arg.split(":")[2])      # k:param:<nbytes>:<letter>

def parse(packet:str) -> tuple[list[UOpLine], int]:
  """the uop lines back out of a packet. The executor decodes the SEMANTICS; this only recovers the
  shape BendProgram needs to marshal buffers, which is why it stops at op names and index lists."""
  head, *body = packet.splitlines()
  if not head.startswith("bendexec1 "): raise ValueError(f"BEND packet must start with bendexec1, got {head!r}")
  _, nuops, nbufs = head.split()
  lines = []
  for raw in body[:int(nuops)]:
    _, op, dtype, arg, *srcs = raw.split()
    lines.append(UOpLine(op, dtype, arg, tuple(int(s) for s in srcs)))
  return lines, int(nbufs)

# **************** runtime ****************

class BendProgram(Program['BendDevice']):
  def __init__(self, dev:'BendDevice', obj:TinyELF):
    self.src = obj.lib.decode()
    self.uops, self.nbufs = parse(self.src)
    # A1: the packet's buffers, in the order ops_python pops them: the PARAMs of addrspace g or l, by
    # uop order. Each entry is how many bytes that buffer spans.
    self.in_bufs: list[int] = [buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]
    # WRITEBACK: ops_python mutates buffers in place, and only ever through a STORE, so the set it can
    # change is exactly the PARAMs a STORE reaches through INDEX/SHRINK/BITCAST/AFTER/STACK. Only those
    # come back out of PACKET.out; a read-only input is never written.
    self.out_bufs: set[int] = set()
    for u in self.uops:
      if u.op != "STORE": continue
      b = u.srcs[0]-1
      while self.uops[b].op in {"INDEX", "SHRINK", "BITCAST", "AFTER", "STACK"}: b = self.uops[b].srcs[0]-1
      if is_buf(self.uops[b].arg): self.out_bufs.add(sum(is_buf(x.arg) for x in self.uops[:b]))

  def __call__(self, *bufs, global_size:tuple[int,int,int]=(1,1,1), local_size:tuple[int,int,int]=(1,1,1),
               vals:tuple[int, ...]=(), wait=False, **kw) -> float:
    exe, st = executor(), time.perf_counter()
    views = [to_mv(b, nb) for b, nb in zip(bufs, self.in_bufs)]
    with tempfile.TemporaryDirectory() as td:
      pkt = pathlib.Path(td)/"PACKET.in"
      pkt.write_text(self.src + "".join(f"{len(v)} {bytes(v).hex()}\n" for v in views))
      # v1.1's command line is `PACKET gx gy gz vals...`: local_size is NOT an argument, because the
      # executor is warp 1 and reads every `lidxK` as 0. See its header, "LOCAL SIZE IS NOT A v1
      # ARGUMENT". A local_size above 1 would silently change nothing, so say so instead.
      if local_size != (1, 1, 1): raise NotImplementedError(f"BEND v1 is warp 1, so it cannot launch with local_size={local_size}")
      r = subprocess.run([str(exe), str(pkt), *map(str, (*global_size, *vals))], capture_output=True, text=True)
      if r.returncode != 0:
        raise RuntimeError(f"the Bend executor exited {r.returncode} on:\n{pkt.read_text()}\n{r.stdout}{r.stderr}")
      out = (pathlib.Path(td)/"PACKET.out").read_text().splitlines()
    if len(out) != self.nbufs: raise RuntimeError(f"BEND executor wrote {len(out)} buffers, the packet had {self.nbufs}")
    for i, ln in enumerate(out):
      if i in self.out_bufs: views[i][:] = bytes.fromhex(ln.split()[1])
    return time.perf_counter() - st

class BendCompiler(Compiler):
  def compile(self, src:str) -> bytes: return src.encode()      # pass-through: the source IS the packet

class BendRenderer(PythonRenderer):
  """same schedules, same supported_dtypes, same tensor cores as ops_python; only the render differs"""
  compiler = BendCompiler()
  # v1.1 is warp 1: local_size is not a launch argument and every lidxK reads as 0, so no axis may be
  # split to LOCAL. `has_local` is the lever the scheduler actually consults (opt/heuristic.py:163) --
  # local_max only groups dims that are already local, and does not stop the split.
  has_local = False
  def render(self, uops:list[UOp]) -> str: return encode(uops)

class BendDevice(Compiled):
  def __init__(self, device:str):
    super().__init__(device, HostAllocator(self), [BendRenderer], BendProgram)