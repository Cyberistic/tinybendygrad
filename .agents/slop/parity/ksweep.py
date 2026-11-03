#!/usr/bin/env python3
"""ksweep.py -- every kernel of a batch of REAL programs: our renderer against tinygrad's, byte for byte.

    .venv/bin/python .agents/slop/parity/ksweep.py

WHY THIS EXISTS: `opbattery.py` compares 31 single ops through the Bend lane, and `gates/ops_bend_exec-e2e.py`
compares 7. Both are SMALL surfaces compared with what a real program lowers to: one `conv2d` alone emits
several kernels, a `softmax` emits a reduce and a broadcast, a `threefry` emits the whole counter-based RNG.
This sweep runs real programs, captures EVERY kernel tinygrad's `ClangRenderer` produced for each, and
renders the same uop list through the PORT's `cstyle.bend`, comparing the C BYTE FOR BYTE.

WHAT A FAILURE MEANS: the port's renderer and upstream's disagree about the text of a kernel that a real
program actually used. That is a 1:1 defect even when both would compile, and it is the class the battery
found four of.

THE ORACLE IS `ClangRenderer`, captured from the same live uop list -- not a stored fixture, so the two
sides cannot drift apart.

**MEASURED LIMITATION, RECORDED RATHER THAN HIDDEN.** `softmax`, `layernorm`, `threefry` and `argmax` each
produce **ZERO kernels** in this harness: their values come out CORRECT (`softmax` to 5.6e-17 against
numpy, `argmax` exact), so the kernels run somewhere this hook does not see, and the cause was NOT
established. `CACHELEVEL=0` does not change it, and a control (`x*2`) captures one kernel in the same
context, so the hook itself works. **A PROGRAM THAT COMPILES NO KERNEL EXERCISES NOTHING HERE**, which is
why the count of covered programs is printed beside the kernel count.
"""
import os
import sys

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, ROOT)
sys.path.insert(0, ROOT + "/.agents/slop/cpuseam")
os.environ.pop("BEND_C", None)
os.environ.pop("BEND_PORT_C", None)
# **`PARALLEL=0` IS WHAT MAKES THIS INSTRUMENT ABLE TO SEE ITS OWN SUBJECT.**
# `tinygrad/engine/realize.py:239` compiles in FORKED WORKERS whenever more than one kernel is pending:
#     pool = None if len(todo) == 1 else get_worker_pool()
# and `get_worker_pool()` returns None when `PARALLEL == 0` (`engine/worker.py:43`). So a ONE-kernel
# program rendered in the parent and was captured, while a THREE-kernel program (`softmax`) compiled in
# children and every renderer hook in the parent stayed silent -- MEASURED `render=0` with
# `exec_kernel=3` and a CORRECT answer, which cost two sessions' worth of wrong hypotheses (disk cache,
# CACHELEVEL, program cache, the CALL shape). MEASURED after this line: `softmax` 0 -> 2 renders,
# `argmax` 0 -> 2.
os.environ["PARALLEL"] = "0"

import numpy as np  # noqa: E402
import ops_bend  # noqa: E402

sys.modules["tinygrad.runtime.ops_bend"] = ops_bend
from tinygrad import Context, Tensor  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.renderer.cstyle import ClangRenderer  # noqa: E402
import tinygrad.engine.realize as _RZ  # noqa: E402
import portc  # noqa: E402

# **A REALIZED BUFFER IS NOT CONSTANT-FOLDABLE.** Without `.realize()` the inputs are CONSTANT Tensors,
# so tinygrad folds the whole program at graph time and compiles NO kernel: MEASURED `softmax`,
# `layernorm`, `threefry` and `argmax` each produced zero kernels and would have counted as "covered".
F = lambda x: Tensor(np.array(x, dtype=np.float32)).realize()
I = lambda x: Tensor(np.array(x, dtype=np.int32)).realize()


def programs():
  """real programs, not single ops: each lowers to one or more kernels."""
  a16 = F(np.arange(256).reshape(16, 16) / 16.0)
  b16 = F(np.arange(256).reshape(16, 16) / 32.0)
  a4 = F([[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]])
  x3 = F(np.arange(24).reshape(2, 3, 4) / 4.0)
  img = F(np.arange(1 * 1 * 8 * 8).reshape(1, 1, 8, 8) / 8.0)
  cw = F(np.arange(1 * 1 * 3 * 3).reshape(1, 1, 3, 3) / 9.0)
  ii = I(np.arange(16).reshape(4, 4))
  return [
    ("matmul16", lambda: (a16 @ b16) @ b16),
    ("matmul32", lambda: F(np.random.rand(32, 32).astype(np.float32)) @ F(np.random.rand(32, 32).astype(np.float32))),
    ("conv2d", lambda: img.conv2d(cw, padding=1)),
    ("reduce_sum", lambda: x3.sum(axis=2)),
    ("reduce_max", lambda: x3.max(axis=1)),
    ("softmax", lambda: x3.softmax(axis=2)),
    ("layernorm", lambda: (x3 - x3.mean(axis=2, keepdim=True)) / (x3.var(axis=2, keepdim=True) + 1e-5).sqrt()),
    ("threefry", lambda: Tensor.rand(8, 8)),
    ("permute", lambda: x3.permute(2, 0, 1)),
    ("reshape_expand", lambda: x3.reshape(4, 6).expand(3, 4, 6)),
    ("pad_cat", lambda: a4.pad(((1, 1), (1, 1))).cat(a4, dim=0)),
    ("where_cmp", lambda: Tensor.where(a4 > 8, a4, a4 * -1)),
    ("relu_abs_neg", lambda: (a4 - 8).relu() + (a4 - 8).abs() + (-a4)),
    ("transcend", lambda: a4.exp() + a4.log2() + a4.sin() + a4.sqrt() + a4.reciprocal() + a4.trunc()),
    ("pow_max", lambda: a4.pow(2) + a4.maximum(a4.flip(0))),
    ("cast_half", lambda: a4.cast(dtypes.half).cast(dtypes.float32)),
    ("cast_bf16", lambda: a4.cast(dtypes.bfloat16).cast(dtypes.float32)),
    ("cast_int", lambda: a4.cast(dtypes.int32) + 3),
    ("cast_bool", lambda: (a4 > 8).cast(dtypes.float32)),
    ("int_ops", lambda: (ii * 3 + ii // 2 + ii % 5 + (ii << 1) + (ii >> 1)).cast(dtypes.float32)),
    ("bitops", lambda: (ii & 7 | ii ^ 3).cast(dtypes.float32)),
    ("argmax", lambda: a4.argmax(axis=1).cast(dtypes.float32)),
    ("embedding", lambda: F(np.random.rand(10, 4).astype(np.float32))[I([[1, 3], [5, 7]])]),
    ("cumsum", lambda: a4.cumsum(axis=1)),
    ("chained", lambda: ((a16 @ b16).relu().sum(axis=1) - (a16 @ b16).max(axis=0)).exp()),
  ]


def main() -> int:
  cap = []
  orig = ClangRenderer.render

  def grab(self, uops):
    src = orig(self, uops)
    cap.append((list(uops), src))
    return src

  # **COUNT EXECUTED KERNELS TOO, SO COVERAGE IS MEASURED AND NOT IMPLIED.** For four programs
  # (`softmax`, `layernorm`, `threefry`, `argmax`) `ClangRenderer.render` never fires while the program
  # computes the CORRECT answer: MEASURED `exec_kernel` fires 3x for `softmax` and its CALL carries a
  # `CallInfo` with 3-5 srcs, but `render`, `Compiler.compile` AND `linearize` are all silent -- so those
  # kernels reach the device with their compiled form already attached, and WHICH PATH ATTACHED IT WAS
  # NOT ESTABLISHED. They are reported as EXECUTED-NOT-COMPARED rather than counted as covered.
  executed = {"n": 0}
  _orig_exec = _RZ.exec_kernel

  def _count_exec(device, ast, *a, **k):
    executed["n"] += 1
    return _orig_exec(device, ast, *a, **k)

  _RZ.exec_kernel = _count_exec
  ClangRenderer.render = grab
  ran, failed_runs = [], []
  # **THE TENSORS MUST BE BUILT INSIDE THE CPU CONTEXT.** `programs()` constructs them eagerly, so
  # calling it outside meant every program belonged to the DEFAULT device (METAL here) and the CPU
  # renderer was never asked for a kernel: MEASURED `kernels captured: 2` for 23 programs.
  with Context(DEV="CPU"):
    progs = programs()
    for name, mk in progs:
      start, start_ex = len(cap), executed["n"]
      try:
        _ = mk().realize().numpy()
        ran.append((name, start, len(cap), executed["n"] - start_ex))
      except Exception as e:
        failed_runs.append((name, f"{type(e).__name__}: {str(e)[:90]}"))
  ClangRenderer.render = orig

  print(f"# programs that ran: {len(ran)}; kernels captured: {len(cap)}")
  # A PROGRAM WHOSE KERNELS WERE NEVER RENDERED HERE EXERCISES NOTHING IN *THIS* INSTRUMENT: name it,
  # with its executed-kernel count, instead of folding it into a coverage claim.
  blind = [(n, ex) for n, a, b, ex in ran if b == a and ex > 0]
  none = [(n, ex) for n, a, b, ex in ran if b == a and ex == 0]
  if blind:
    print(f"# EXECUTED-NOT-COMPARED (kernels ran, the C was never rendered here): {len(blind)} -- "
          + ", ".join(f"{n}(exec={ex})" for n, ex in blind))
  if none:
    print(f"# NO kernel at all (folded away): {len(none)} -- " + ", ".join(n for n, _ in none))
  compared_programs = sum(1 for _n, a, b, _ex in ran if b > a)
  print(f"# programs whose kernels were COMPARED: {compared_programs} of {len(ran)}")
  for n, why in failed_runs:
    print(f"# ORACLE REFUSED {n}: {why}")

  same = diff = 0
  first = None
  for idx, (uops, theirs) in enumerate(cap):
    try:
      ours = portc.render(uops)
    except Exception as e:
      diff += 1
      if first is None:
        first = (idx, f"PORT FAILED {type(e).__name__}: {str(e)[:200]}")
      continue
    if ours == theirs:
      same += 1
    else:
      diff += 1
      if first is None:
        import difflib
        d = [l for l in difflib.unified_diff(theirs.splitlines(), ours.splitlines(), "theirs", "ours", lineterm="", n=0)
             if l.startswith(("-", "+")) and not l.startswith(("---", "+++"))][:4]
        first = (idx, "\n    ".join(d))
  print(f"# kernels: {same} byte-identical, {diff} differ")
  if first:
    print(f"# first divergence at kernel {first[0]}:\n    {first[1]}")
  return 0 if diff == 0 else 1


if __name__ == "__main__":
  sys.exit(main())
