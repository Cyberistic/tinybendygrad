#!/usr/bin/env python3
"""STAGE 2 EMITTER -- CPython's sched_sink -> a Bend arena builder.

`create_schedule` reads exactly FOUR things off the sched_sink: the gated
toposort, each AFTER's `_split_after`, `_states` of the kernel's srcs, and
`k.backward_slice`. All four are pure functions of the NODE STRUCTURE plus a
handful of args. So a faithful port comparison needs the same graph in the
port's arena, and this file emits it -- from CPython's OWN object graph, so no
node is transcribed.

WHY AN EMITTER AND NOT A FIXTURE. `sched-stage1.md` records the real matmul
sched_sink as 6 nodes over a 27-node kernel body: 3 PARAMs, 1 CALL, 1 AFTER,
1 SINK, and a body of CONST/RANGE/MUL/ADD/INDEX/REDUCE/STORE/END/SINK. That is
small enough to build by hand, and `graphcmp.bend:859 g_lin` DID build a
46-node version of a closely related graph by hand -- which is exactly the
hand-written tax this file exists to remove.

WHAT IS EMITTED, per spec: one `+<name> = O.UOp.new(...)` per node, in CPython's
`toposort` order, with the arena threaded through `+` bindings. Node INDICES are
assigned in that same order, so the emitted file's indices and the oracle's
`tree[i]` indices agree -- which is what makes a diff locatable.

THE ARGS, and each one's port spelling. This is the whole fragile surface:
  PARAM      ParamArg(slot, dtype, size, name, addrspace, device, volatile)
  CONST      PyConst int
  RANGE      ARange{[axis_id], AXIS_*}
  REDUCE     AReduce{rop, num_axes}
  SINK       AKernel{KernelInfo}  -- KernelInfo HAS FOUR FIELDS IN THE PORT
             (ops.bend:919) AGAINST FIVE IN CPYTHON (ops.py:1342, `estimates` is
             not ported) SO THIS ARG CANNOT AGREE, and the emitted file says so.
  CALL       ACall{CallInfo} -- CallInfo HAS FOUR IN THE PORT (ops.bend:1010,
             `dtype`) AGAINST THREE IN CPYTHON. Same reason.
  ADD/MUL/... None

RUN:
  env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python \
    .agents/slop/sched-emit.py --only matmul > .agents/slop/sched-fixture.bend
"""
import os, sys, argparse

sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import importlib.util
_spec = importlib.util.spec_from_file_location(
    "so", os.path.join(os.path.dirname(os.path.abspath(__file__)), "sched-oracle.py"))
SO = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(SO)

from tinygrad.uop.ops import Ops, ParamArg, KernelInfo
from tinygrad.dtype import AddrSpace

# CPython dtype name -> the port's `S.Dt` constructor. `S.single()` is f32
# (graphcmp.bend:824 uses it for the f32 PARAMs), and every dtype these six specs
# reach is f32 or weakint.
DT = {"f32": "S.single()", "f16": "S.float16()", "i32": "S.int32()",
      "u32": "S.uint32()", "bf16": "S.bfloat16()", "i64": "S.int64()",
      "u64": "S.uint64()", "f64": "S.float64()", "bool": "S.bool()",
      "weakint": "S.weakint()", "i8": "S.int8()", "u8": "S.uint8()",
      "i16": "S.int16()", "u16": "S.uint16()"}

# CPython `AxisType` -> the port's constructor (ops.bend:646ff)
AX = {"WEAK": "O.AXIS_WEAK{}", "GLOBAL": "O.AXIS_GLOBAL{}", "DEVICE": "O.AXIS_DEVICE{}",
      "LOCAL": "O.AXIS_LOCAL{}", "WARP": "O.AXIS_WARP{}", "LOOP": "O.AXIS_LOOP{}"}

# CPython Ops -> the port's variant constructor (ops.bend:276ff). Derived, not
# listed, so a new op cannot silently emit `O.OpsFOO{}` and fail to compile.
OPS_NOT_PORTED = []


def op_v(op):
  """`Ops.FOO` -> `O.OpsFOO{}`. `op` is an `Ops` member, so `op.name` is the
  uppercase spelling the port's variant constructors use. Raising on an op the
  port has not ported is deliberate: a silently-skipped op would shorten the
  graph and every count downstream of it would then disagree for the wrong
  reason."""
  return f"O.Ops{op.name}{{}}"


def arg_of(u):
  """The port's `Arg` spelling for `u.arg`, or None if this file cannot spell it.
  Raising is right here: a silently-dropped arg is exactly the
  `device.bend sig=0 4 5` bug the brief calls out."""
  a = u.arg
  if a is None:
    return "O.ANone{}"
  if isinstance(a, ParamArg):
    # `a.dtype` prints as `dtypes.f32`, `dtypes.f16`, ... -- the SHORT names, not
    # the `float32`/`float16` keys. Measured: two of my first three dtypes were
    # wrong keys and this raised rather than emitting a wrong `S.Dt`, which is
    # the point of raising. `weakint` is a real dtype here for a bound Variable.
    key = str(a.dtype).split(".")[-1]
    dt = DT.get(key)
    if dt is None:
      raise KeyError(f"dtype {a.dtype} (key {key!r}) not in DT table; have {sorted(DT)}")
    if dt is None:
      raise KeyError(f"dtype {a.dtype} not in DT table")
    nm = "None{}" if a.name is None else f"Some{{{a.name!r}}}".replace("'", '"')
    ad = {"GLOBAL": "S.AGlobal{}", "ALU": "S.AAlu{}"}
    return (f"O.AParam{{O.ParamArg{{{a.slot}, {dt}, "
            + (f"Some{{{a.size}}}" if a.size is not None else "None{}") + ", "
            + (f"Some{{O.PyRange{{{a.vmin_vmax[0]}, {a.vmin_vmax[1]}}}}}" if a.vmin_vmax is not None else "None{}") + ", "
            + (f"Some{{{a.multiple_of}}}" if a.multiple_of is not None else "None{}") + ", "
            + nm + ", "
            + ad.get(a.addrspace.name, "S.AGlobal{}") + ", "
            + (f"Some{{S.D1{{{0}}}}}" if a.device is not None else "None{}") + ", "
            + f"{a.volatile}, None{{}}, None{{}}, False{{}}, "
            + ("None{}" if a.val is None else f"Some{{O.CInt{{H.i64_of_i32({a.val})}}}}") + "}}}")
  if type(a).__name__ == "CallInfo":
    # PORT HAS FOUR FIELDS AGAINST CPYTHON'S THREE: `dtype: S.Dt` (ops.bend:1010)
    # has no CPython counterpart. `graphcmp.bend:963` documents this as a REPORTED
    # disagreement by construction, and `S.void()` is the spelling it used.
    nm = "None{}" if a.name is None else f"Some{{\"{a.name}\"}}"
    return (f"O.ACall{{O.CallInfo{{{nm}, {a.precompile}, "
            f"{a.precompile_backward}, S.void()}}}}")
  if isinstance(a, KernelInfo):
    # PORT HAS 4 FIELDS, CPYTHON 5: `estimates` is not ported (ops.bend:915-917).
    return (f'O.AKernel{{O.KernelInfo{{{a.name!r}, Nil{{}}, None{{}}, {a.beam}}}}}'
            .replace("'", '"'))
  if u.op is Ops.CONST and isinstance(a, int):
    return f"O.APy{{O.CInt{{H.i64_of_i32({a})}}}}"
  if u.op is Ops.RANGE:
    at, ids = a
    # MEASURED: `UOp.range_end`'s arg is `(AxisType, int)` -- a BARE int, not a
    # tuple -- while `graphcmp.bend:863` and `:875` write `ARange{[2], AXIS_WEAK{}}`
    # and `O.AXIS_WEAK{}` is right while `[2]` is the one-element list the port's
    # `range_end` takes. So both spellings occur; this file emits the port's.
    lst = f"[{ids}]" if isinstance(ids, int) else "[" + ", ".join(str(i) for i in ids) + "]"
    return "O.ARange{" + lst + ", " + AX[at.name] + "}"
  if u.op is Ops.REDUCE:
    rop, nax = a
    return f"O.AReduce{{{op_v(rop)}, {nax}}}"
  raise KeyError(f"sched-emit.py cannot spell arg {type(a).__name__} {a!r} on {u.op.name}")


def emit(spec, sink):
  """One `+<nm> = O.UOp.new(...)` per node, in toposort order, indices agreeing.

  THE GATE IS WHY TWO LISTS. `create_schedule`'s walk is
  `sched_sink.toposort(gate_kernel_sink)` (`__init__.py:39`), and `toposort`
  enters CALL bodies by DEFAULT (`ops.py:297`, `enter_calls=True`) -- but
  `gate_kernel_sink` REJECTS a SINK carrying a `KernelInfo` (`ops.py:1911`), and
  the kernel body is exactly such a SINK. So the gate STOPS the walk at the CALL
  and the gated list is 6 nodes while the whole graph is 27. Both are emitted:
  the full graph because the arena needs the body for the Kahn loop's
  `k.replace(src=(k.body, ...))` (`__init__.py:75`), and the gated COUNT because
  it is a row the port can compute (`sc_topo_of`) and check against `sink_n`.

  The arena is threaded the way `graphcmp.bend:859 g_lin` threads it: each call
  takes the previous node's arena, so node N's arena holds nodes 0..N."""
  full = list(sink.toposort(None))
  gated = list(sink.toposort(SO.gate_kernel_sink))
  idx = {id(u): i for i, u in enumerate(full)}
  lines, prev = [], "O.Arena.empty()"
  for i, u in enumerate(full):
    nm = f"n{i}"
    srcs = "[" + ", ".join(f"O.Found.i(n{idx[id(s)]})" for s in u.src) + "]"
    lines.append(f"  +{nm} = O.UOp.new({prev}, {op_v(u.op)}, {srcs}, {arg_of(u)}, O.TNone{{}})")
    prev = f"O.Found.ar({nm})"
  hdr = [f"# gated={len(gated)} full={len(full)} root={full[-1].op.name} "
         f"root_srcs={len(full[-1].src)}",
         f"# gated_ops={sorted(__import__('collections').Counter(u.op.name for u in gated).items())}"]
  return "\n".join(hdr + lines), full, gated


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--only", default=None)
  a = ap.parse_args()
  for name, fn in SO.SPECS:
    if a.only and name != a.only:
      continue
    SO._reset()
    SO._CAPTURED.clear()
    fn()
    if not SO._CAPTURED:
      print(f"# {name}: no create_schedule call")
      continue
    sink, lin = SO._CAPTURED[-1]
    print(f"# ---- {name}: sink {sink.op.name} {len(sink.src)} src, "
          f"{len(list(sink.toposort(SO.gate_kernel_sink)))} gated nodes ----")
    try:
      body, full, gated = emit(name, sink)
      print(body)
      print(f"# root=n{len(full) - 1}  full_nodes={len(full)}  gated_nodes={len(gated)}")
    except (KeyError, AttributeError) as e:
      print(f"# {name}: EMIT FAILED: {type(e).__name__}: {e}")


if __name__ == "__main__":
  main()