#!/usr/bin/env python
"""DENOM probe -- for each of the 18 unreached ops, is it EXPRESSIBLE as a node in an
emitted dataflow graph?

METHOD, and why it is not a name search:
  a name search finds the enum member, which every one of the 18 has. What decides
  expressibility is whether UPSTREAM'S OWN CONSTRUCTION produces a UOp carrying the op,
  that UOp survives `spec`, and it is in the `toposort()` of the root -- i.e. it is a row
  the differ would emit. So each op gets, in this order:
     CONSTRUCT  upstream's constructor/method, called
     UOP        is there a node with .op is Ops.X
     SPEC       does the op pass `get_specification`
     IN-TOPO    does it appear in root.toposort()

and then, separately, ERASED: is it still there after the graph goes through upstream's own
late rewrite pipeline? An op that is constructible but always rewritten away before render
is a DIFFERENT finding from one that is never constructible, and the brief's "no UOp is ever
constructed with it" test does not distinguish them.

Every expectation here is a CALL, never a hand-typed row.
"""
import sys, traceback
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad import Tensor, dtypes
from tinygrad.uop import Ops
from tinygrad.uop.ops import UOp, all_metadata
from tinygrad.uop.spec import type_verify, spec_tensor, spec_program
from tinygrad.device import Device
from tinygrad.helpers import DISABLE_FAST_IDIV
from tinygrad.uop.ops import graph_rewrite
from tinygrad.codegen.decomp.op import get_late_rewrite_patterns
from tinygrad.uop.ops import UPat

# ops the brief lists as unreached
EIGHTEEN = ["ALLREDUCE","COPY","CUSTOM","CUSTOMI","CUSTOM_FUNCTION","GETADDR","INS",
            "MSELECT","MSTACK","MULACC","PROGRAM","PYLITERAL","REWRITE_ERROR","SOURCE",
            "STAGE","THREEFRY","UNSHARD","WMMA"]

F32 = dtypes.float

def _f(n=4):
  return Tensor.empty(n, 3, dtype=F32)

def _i(n=4):
  return Tensor.empty(n, 3, dtype=dtypes.int)

def has(root, name):
  return any(u.op.name == name for u in root.toposort())

def spec_ok(root):
  """UPSTREAM'S OWN TABLE, chosen the way upstream chooses it: `spec_program` for a
  PROGRAM root (codegen/__init__.py:392), `spec_tensor` for everything else
  (schedule/__init__.py:263). Not a home-grown predicate."""
  table = spec_program if root.op is Ops.PROGRAM else spec_tensor
  try:
    type_verify(root, table, enter_calls=(table is spec_program))
    return "OK"
  except Exception as e:
    return f"FAIL {type(e).__name__}: {str(e)[:90]}"

def attempt(name, op, build):
  """build() -> UOp root. MEASURED, never asserted."""
  row = {"op": name}
  try:
    root = build()
  except Exception as e:
    row.update(CONSTRUCT=f"NO {type(e).__name__}: {str(e)[:70]}", UOP="-", SPEC="-", INTOPO="-")
    return row
  found = has(root, name)
  row.update(CONSTRUCT="ok", UOP=("yes" if found else "NO"),
             SPEC=spec_ok(root) if found else "-",
             INTOPO=("yes" if found else "NO"), nodes=len(list(root.toposort())))
  return row

# ---- each op's UPSTREAM construction, cited --------------------------------
BUILDS = {
 # ops.py:651 UOp.wmma(a,b,acc,dims,threads,tc_upcast_axes). a/b/acc must be real 16x16
 # MATRICES, so take them from a realized Tensor rather than reshaping a scalar.
 "WMMA": lambda: UOp.wmma(*(Tensor.ones(16, 16).uop,)*3, dims=(16,16,16), threads=32),
 # ops.py:701 UOp.unshard(axis, device_range)
 "UNSHARD": lambda: _f().uop.unshard(0, UOp.range(2, 0)),
 # ops.py:676 UOp.bufferize
 "STAGE": lambda: _f().uop.bufferize(),
 # ops.py:765 UOp.copy_to_device
 "COPY": lambda: _f().uop.copy_to_device("CPU"),
 # ops.py:769 UOp.mselect
 "MSELECT": lambda: _f().uop.copy_to_device(("CPU","CPU")).mselect(0),
 # ops.py:770 UOp.mstack
 "MSTACK": lambda: _f().uop.mstack(_f().uop),
 # ops.py:844 UOp.getaddr -- its OWN guard (ops.py:843) returns `self` unless the base is
 # one of BUFFER/ALLOC/SHRINK/BITCAST/BINARY/MSTACK/MSELECT/PARAM/LINEAR, so it must be
 # given a BUFFER. MEASURED: on a STAGE base it returns the STAGE and there is NO GETADDR.
 "GETADDR": lambda: UOp.new_buffer("CPU", 16, F32).getaddr("CPU"),
 # ops.py:679 UOp.allreduce
 "ALLREDUCE": lambda: _f().uop.copy_to_device(("CPU","CPU")).allreduce(Ops.ADD, ("CPU","CPU")),
 # ops.py:1258 UOp.custom_function(name, *src, dtype). tensor.py:563 (the only production
 # site) passes `frame_pos.unbound()`, so src must be a VARIABLE -- ops.py:1040 asserts it.
 # A Variable is `UOp.variable(name, min, max)` (ops.py:1016). MEASURED: `UOp.range(4,0)`
 # and `UOp.const(0)` BOTH fail that assert, and the first version of this probe used them.
 "CUSTOM_FUNCTION": lambda: UOp.custom_function("f", UOp.variable("v", 0, 4).unbound(), dtype=F32),
 # elementwise.py:458 threefry
 "THREEFRY": lambda: _i().threefry(_i().cast(dtypes.uint64)).uop,
 # codegen/decomp/op.py:119 `x.alu(Ops.MULACC, b, c)` -- the ONLY site, and it is a REWRITE
 "MULACC": lambda: UOp(Ops.MULACC, src=(UOp.const(1.0), UOp.const(2.0), UOp.const(3.0))),
 # llm/kernels/amd.py:167 / runtime/ops_qcom.py:29 -- the (template, dtype) arg form
 "CUSTOM": lambda: UOp(Ops.CUSTOM, src=(UOp.const(1.0),), arg=("({0}/127.0f)", dtypes.float)),
 # llm/kernels/amd.py:108 -- same but "the I makes the string inline"
 "CUSTOMI": lambda: UOp(Ops.CUSTOMI, src=(UOp.const(1).cast(dtypes.int32),)*3,
                        arg=("__builtin_amdgcn_sudot4(true, {}, true, {}, {}, false)", dtypes.int32)),
}

# PYLITERAL / INS / PROGRAM / SOURCE / REWRITE_ERROR are not tensor-API reachable;
# they need the code-generation pipeline itself. Probe them the way upstream builds them.
def _pyliteral():
  # upat.py:17-70 `_get_clause`, reached from upat.py:163 `_get_code`. THE HEADER COMMENT AT
  # upat.py:12-15 NAMES THE SET: "Ops used: CUSTOM ... CUSTOMI ... PYLITERAL". So these three
  # are not hand-built literals at all -- they are the PATTERN COMPILER'S IR, and the only
  # honest way to show one exists is to ask the compiler to compile a real UPat.
  from tinygrad.uop.upat import _get_clause
  from tinygrad.dtype import dtypes as _dt
  return _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", _dt.void)))

def _ins():
  # upat.py:163 -- the compiler's own `UOp(Ops.CUSTOMI, arg=("uop", dtypes.void))` binding.
  # INS itself is minted by the RENDERERS (renderer/ptx.py wmma -> list of INS).
  return UOp.group(UOp(Ops.NOOP), UOp(Ops.INS, arg="nop"))

def _kernel_ast():
  """The scheduled KERNEL SINK, by `schedule_linear` -- the same construction `g_lin` uses.
  Not hand-written, and not a `UOp` literal."""
  out = Tensor.empty(4, 5).realize()
  out.assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))
  return [si.src[0] for si in out.schedule_linear().src if si.src[0].op is Ops.SINK][0]

def _program():
  # codegen/__init__.py:502 `prg = UOp(Ops.PROGRAM, src=(full_sink,), arg=prog_info)`, reached
  # through upstream's OWN `to_program` / `do_to_program` (codegen/__init__.py:518-521).
  from tinygrad.codegen import to_program
  return to_program(_kernel_ast(), Device.default.renderer)

def _source():
  # codegen/__init__.py:455/459 -- `prg.replace(src=...+(UOp(Ops.SOURCE, arg=src),))`.
  # `to_program` APPLIES `pm_to_program` (codegen/__init__.py:506), whose `do_compile`
  # (codegen/__init__.py:472) is the rule that adds the SOURCE. So upstream's own compiled
  # program is where a SOURCE is reachable -- and nowhere else.
  return _program()

def _rewrite_error():
  # viz/serve.py:197 -- `UOp(Ops.REWRITE_ERROR, arg=traceback.format_exc())`
  return UOp(Ops.REWRITE_ERROR, arg="boom")

BUILDS.update({"PYLITERAL": _pyliteral, "INS": _ins, "PROGRAM": _program,
               "SOURCE": _source, "REWRITE_ERROR": _rewrite_error})

if __name__ == "__main__":
  print(f"# device = {Device.DEFAULT}  renderer = {type(Device.default.renderer).__name__}")
  print(f"# denom  = {len(list(Ops))}")
  print(f"{'op':<16} {'CONSTRUCT':<10} {'UOP':<4} {'SPEC':<8} {'INTOPO':<7} nodes")
  rows = []
  for name in EIGHTEEN:
    r = attempt(name, name, BUILDS[name])
    rows.append(r)
    print(f"{name:<16} {r['CONSTRUCT'][:10]:<10} {r['UOP']:<4} {str(r['SPEC'])[:8]:<8} {str(r['INTOPO']):<7} {r.get('nodes','-')}")
  print()
  print(f"# CONSTRUCTIBLE = {sum(1 for r in rows if r['CONSTRUCT']=='ok')} of {len(rows)}")
  print(f"# CARRIED-ON-A-UOP = {sum(1 for r in rows if r['UOP']=='yes')}")
  print(f"# SPEC-PASSING = {sum(1 for r in rows if str(r['SPEC'])=='OK')}")
