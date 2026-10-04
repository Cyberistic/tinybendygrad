#!/usr/bin/env python3
"""STAGE 1 ORACLE -- what does CPython's `create_schedule` answer, FIELD BY FIELD?

Every number below is produced by CALLING CPython. Nothing is transcribed.

HOW CPython IS CALLED. `create_schedule(sched_sink)` (schedule/__init__.py:32) is
the engine's FIRST consumer and its argument is the SINK-OF-AFTERS that
`get_kernel_graph(prepare_rangeify(function))` builds
(schedule/__init__.py:135). Rather than transcribe that three-stage pipeline,
this file SPIES: it replaces the module-global `create_schedule` that
`lower_sink_to_linear` looks up, then drives `Tensor.schedule_linear()` -- which
is the entry `create_linear_with_vars` sits behind (tensor.py:212). So the
`sink` recorded here is the REAL sched_sink tinygrad itself hands to
`create_schedule`, and the `lin` recorded is the REAL `UOp(Ops.LINEAR, ...)`.

MEASURED FIRST, AND IT CHANGES THE ORACLE: the short route
`create_schedule((Tensor.empty(4,5).realize().assign(t)).uop)` -- which is what
graphcmp-p14-sched.py:40 calls -- returns `UOp(Ops.LINEAR, src=())`, an EMPTY
schedule, WITH NO ERROR. That is because the assign's `.uop` is the AFTER itself,
not a SINK-OF-AFTERS: `_split_after` drops its STORE (schedule/__init__.py:26,
STORE is neither CALL/END nor AFTER), so `kernels` is empty, the Kahn queue has
no seed, and the loop never runs. **`create_schedule` validates nothing, so a
wrong argument is a silently empty LINEAR.** See the `WRONGINPUT` section.

FIELDS, per spec. Field NAMES and field ORDER, never a count alone -- the
agent-core rule, from cstyle's `sig=0 4 5`.

  sink_n       len(sink.toposort(gate_kernel_sink))   -- the walk's input size
  sink_op/nsrc the root's op and arity
  sink_ops     the op census of the gated walk, as sorted (name, count) pairs
  lin_op       lin.op. Must be LINEAR (:80)
  lin_nsrc     len(lin.src)   -- the kernel count
  lin_nnodes   len(lin.toposort())
  lin_ksrc     the per-kernel src op SEQUENCE, in LINEAR order. THE row that
               decides the linearization -- the port's `gate.ops` / `fx*_ops`.
  lin_knsrc    per kernel, len(k.src)
  lin_ktop     per kernel, the body's op
  lin_kmark    per kernel, the STORE's value CONST -- the port's `gate.mark`,
               which is what tells a schedule apart from a re-ordering
  lin_kinfo    per kernel, the body's KernelInfo.kname
  tree[i]      the gated walk, one line per node, so a disagreement is LOCATABLE
  k[i][j]      the same for each linearized kernel's own subgraph

DETERMINISM: `--twice` builds every spec TWICE in one process and prints both
sha256s. `create_schedule` is pure, but `UOpMetaClass.ucache` is global, so run
2 can see nodes interned by run 1. Measured rather than assumed.

RUN:
  env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/sched-oracle.py --twice
  ... > .agents/slop/sched-oracle.txt
"""
import os, sys, hashlib, collections, argparse

sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")

from tinygrad import Tensor
from tinygrad.uop.ops import UOp, Ops, gate_kernel_sink, KernelInfo
import tinygrad.schedule as SCHED
from tinygrad.dtype import dtypes

_ORIG = SCHED.create_schedule
_CAPTURED: list = []


def _spy(sink):
  lin = _ORIG(sink)
  _CAPTURED.append((sink, lin))
  return lin


SCHED.create_schedule = _spy


def _reset():
  """THE NONDETERMINISM, AND WHY IT IS NOT THE ORACLE'S FAULT. Measured, not
  guessed: the first `--twice` run of this file reported `DETERMINISTIC=False` on
  4 of 7 blocks, each diff being the ENTIRE run-1 block deleted in run 2. The
  cause is `schedule_cache` (`schedule/__init__.py:122`) -- a MODULE GLOBAL keyed
  by `function.key`, read at :130 BEFORE `create_schedule` is reached at :135. So
  the second identical spec in one process is a CACHE HIT, `create_schedule` is
  NEVER CALLED, and the spy records nothing.

  That is a property of the ENGINE, and it is worth its own line: **`create_schedule`
  is only reachable on a schedule-cache MISS.** A harness that runs a spec twice
  in one process measures the CACHE on the second call, not the function. Clearing
  it is the only way to make run 2 a measurement of `create_schedule` again."""
  SCHED.schedule_cache.clear()


# --------------------------------------------------------------------------
# THE SPECS. Each drives `Tensor.schedule_linear()` and the spy collects the
# sched_sink and its LINEAR. Every schedule-producing spec is one that
# `create_schedule` actually sees at least one AFTER for.
# --------------------------------------------------------------------------
def s_matmul():
  """THE differ's subject: `(4,3)@(3,5)` assigned into a realized `Tensor.empty(4,5)`.
  `graphcmp.bend:859 g_lin` hand-writes the `full_rewrite_to_sink` of this
  schedule -- 46 nodes, measured off `runs/graphcmp/D/D1-graph-lin.txt`."""
  t = Tensor.empty(4, 3) @ Tensor.empty(3, 5)
  return Tensor.empty(4, 5).realize().assign(t).schedule_linear()


def s_matmul_sym():
  """A matmul over a SYMBOLIC bound. The fixture for a bound PARAM inside a
  kernel body, which is what `is_bound_var` (ops.py:1023) exists for and what
  `create_linear_with_vars`'s `var_vals` loop reads back out (:285-293).
  `Tensor.bind` does not exist -- the bind is on the UOp (ops.py:1032)."""
  from tinygrad.uop.ops import UOp
  # MEASURED, because it is the shape of bug this project keeps finding, and
  # both of these first attempts FAILED rather than being assumed away:
  #   `Tensor(v)` does not re-wrap a Variable, and `Variable('i',1,10)`
  #   (test/test_tiny.py:113) builds `UOp(op='i', src=1, arg=10)` -- a garbage
  #   node -- because `Variable = UOp` (ops.py:1918) is a bare alias with no
  #   constructor. `UOp.variable('K', 1, 10)` (llm/model.py:325) is the real one.
  #   And the symbol must be on BOTH operands: `mixin/op.py:389` evaluates
  #   `x.shape[-1] != w.shape[axis_w:...]`, which a one-sided symbol cannot fold.
  kv = UOp.variable("K", 1, 10).bind(3)
  a = Tensor.empty(4, kv).realize()
  b = Tensor.empty(kv, 5).realize()
  lin, vv = Tensor.empty(4, 5).realize().assign((a @ b).relu()).linear_with_vars()
  print(f"# matmul_sym var_vals={vv}")
  return lin


def s_conv():
  """A 3x3 CONV2D. The reduction axis makes the RAW edges between kernels real
  rather than incidental, and it is the spec with the most kernels."""
  x = Tensor.empty(1, 4, 8, 8, dtype=dtypes.half)
  w = Tensor.empty(8, 4, 3, 3, dtype=dtypes.half)
  return Tensor.empty(1, 8, 8, 8, dtype=dtypes.half).realize().assign(x.conv2d(w, padding=1)).schedule_linear()


def s_elementwise():
  """A three-link elementwise chain. The floor case: one kernel, no RAW edge,
  no WAR edge, so the Kahn queue has exactly one seed and the whole of
  __init__.py:66-80 is a single turn."""
  a, b, c = (Tensor.empty(4, 3) for _ in range(3))
  return Tensor.empty(4, 3).realize().assign(((a + b) * c).relu()).schedule_linear()


def s_multi():
  """TWO sinks realized in one call -- the first spec where the WAR pass
  (__init__.py:59-65) has two readers of the same state, which is the only
  place `k.backward_slice` is load-bearing."""
  a = Tensor.empty(4, 3).realize()
  b = Tensor.empty(3, 5)
  o1 = Tensor.empty(4, 5).realize().assign(a @ b)
  o2 = Tensor.empty(4, 3).realize().assign((a * 2).relu())
  return o1.schedule_linear(o2)


def s_chain():
  """A DEPENDENT CHAIN -- `b = a*2` then `c = b*3` -- so the second AFTER's
  `prev_state` is ITSELF an AFTER (`__init__.py:42-43`). This is the shape the
  port's `fx3` hand-builds."""
  a = Tensor.empty(4, 3).realize()
  b = a * 2
  return Tensor.empty(4, 3).realize().assign(b * 3).schedule_linear()


def s_wronginput():
  """THE SILENT-EMPTY MEASUREMENT. `create_schedule` on an AFTER (rather than a
  SINK-OF-AFTERS) answers an EMPTY LINEAR and raises nothing. Not a spec: a
  control, recorded so the stage-2 denominator cannot quietly include it."""
  t = Tensor.empty(4, 3) @ Tensor.empty(3, 5)
  aft = (Tensor.empty(4, 5).realize().assign(t)).uop
  return (aft, _ORIG(aft))


SPECS = [
  ("matmul", s_matmul),
  ("matmul_sym", s_matmul_sym),
  ("conv", s_conv),
  ("elementwise", s_elementwise),
  ("multi", s_multi),
  ("chain", s_chain),
]
CONTROLS = [("WRONGINPUT_after", s_wronginput)]


# --------------------------------------------------------------------------
def kname(k):
  """`k.src[0].arg.name` when the kernel body carries a `KernelInfo` (:1342).
  NOT `kname` -- CPython's field is `name`, and the port's gate spells a
  different thing entirely (`graphcmp.bend:921` writes `r_4_5_3` by hand, which
  is the FUNCTION name, not the KernelInfo name)."""
  a = k.src[0].arg
  return a.name if isinstance(a, KernelInfo) else ""


def mark_of(k):
  """The STORE's value CONST -- the port's `gate.mark`. Walks to the first STORE
  under the kernel and reads its src[1]. '' when there is none, so absence is
  reported rather than defaulted to 0."""
  for u in k.toposort():
    if u.op is Ops.STORE:
      v = u.src[1]
      return str(v.arg.val) if v.op is Ops.CONST else "<" + v.op.name + ">"
  return ""


def block(name, sink, lin):
  out = []
  ts = list(sink.toposort(gate_kernel_sink))
  out.append(f"sink_n={len(ts)}")
  out.append(f"sink_op={sink.op.name}")
  out.append(f"sink_nsrc={len(sink.src)}")
  out.append(f"sink_ops={sorted(collections.Counter(u.op.name for u in ts).items())}")
  out.append(f"lin_op={lin.op.name}")
  out.append(f"lin_nsrc={len(lin.src)}")
  out.append(f"lin_nnodes={len(lin.toposort())}")
  out.append(f"lin_ksrc={[u.op.name for k in lin.src for u in k.src]}")
  out.append(f"lin_knsrc={[len(k.src) for k in lin.src]}")
  out.append(f"lin_ktop={[k.src[0].op.name for k in lin.src]}")
  out.append(f"lin_kmark={[mark_of(k) for k in lin.src]}")
  out.append(f"lin_kinfo={[kname(k) for k in lin.src]}")
  for i, u in enumerate(ts):
    out.append(f"tree[{i:3d}]={u.op.name} nsrc={len(u.src)} srcs={[s.op.name for s in u.src]}")
  for i, k in enumerate(lin.src):
    for j, u in enumerate(k.toposort()):
      out.append(f"k[{i}][{j:3d}]={u.op.name} nsrc={len(u.src)} srcs={[s.op.name for s in u.src]}")
  return "\n".join(f"{name} {ln}" for ln in out)


def h(s):
  return hashlib.sha256("\n".join(l for l in s.split("\n") if l.strip()).encode()).hexdigest()[:16]


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--twice", action="store_true")
  ap.add_argument("--only", default=None)
  a = ap.parse_args()
  runs = 2 if a.twice else 1
  allspecs = SPECS + CONTROLS
  if a.only:
    allspecs = [s for s in allspecs if s[0] == a.only]
  got = []
  for _ in range(runs):
    per = {}
    for name, fn in allspecs:
      _reset()
      _CAPTURED.clear()
      try:
        if name == "WRONGINPUT_after":
          aft_lin = fn()
          per[name] = block_from(name, (aft_lin[0], aft_lin[1]))
          continue
        fn()
        if not _CAPTURED:
          per[name] = f"{name} NO_SCHEDULE_CALL"
        else:
          # MORE THAN ONE `create_schedule` CALL is not an error: `multi` and
          # `chain` legitimately raise several kernels, and the spy sees each.
          # Each is recorded under its own prefix so the denominator counts
          # CALLS, not specs, and a two-call spec cannot hide behind one hash.
          for i, (s, l) in enumerate(_CAPTURED):
            nm = name if len(_CAPTURED) == 1 else f"{name}#{i}"
            per[nm] = block(nm, s, l)
          per[f"{name}__calls"] = str(len(_CAPTURED))
      except Exception as e:
        per[name] = f"{name} RAISED {type(e).__name__}: {e}"
    got.append(per)
  names = [n for n, _ in allspecs]
  for r in range(runs):
    names += [k for k in got[r] if k not in names]
  print(f"# specs_attempted={len(SPECS)} controls={len(CONTROLS)} scheduled_calls={sum(1 for k in names if not k.endswith('RAISED'))}")
  print("# ==== determinism ====")
  for name in names:
    if name not in got[0] or name not in got[1]:
      continue
    if runs == 2:
      print(f"# {name:18s} run1={h(got[0][name])} run2={h(got[1][name])} DETERMINISTIC={got[0][name] == got[1][name]}")
      if got[0][name] != got[1][name]:
        a1 = got[0][name].split("\n")
        a2 = got[1][name].split("\n")
        import difflib
        d = [l for l in difflib.unified_diff(a1, a2, "run1", "run2", lineterm="", n=0)]
        print("#   DIFF " + str(len(d)) + " lines, first 8:")
        for l in d[:8]:
          print("#   " + l)
    else:
      print(f"# {name:18s} sha={h(got[0][name])}")
  print("# ==== blocks (run 1) ====")
  for name in names:
    if name in got[0]:
      print(got[0][name])


def block_from(name, cap):
  """The control has no spy capture -- `_spy` is never called -- so it is built
  from the pair `s_wronginput` returns."""
  return block(name, cap[0], cap[1])


if __name__ == "__main__":
  main()