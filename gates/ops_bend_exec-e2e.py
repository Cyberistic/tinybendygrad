#!/usr/bin/env python3
"""END TO END for tinygrad/runtime/ops_bend.py: build the Bend executor, run real
kernels on the BEND device, and compare against CPython's own answer.

THIS IS THE ARTEFACT. Every other oracle in this project drives CPython's pure
functions against a fake device; this one COMPILES AND RUNS.

    .venv/bin/python gates/ops_bend_exec-e2e.py

It prints, per case, the answer the BEND device produced, the answer CPython's
PYTHON device produced for the same expression, and the packet
`BendRenderer.render` emitted. The packets land in
`gates/artifacts/ops_bend_exec/packet-<case>.rows`, the same files the Bend gate
diffs its `bend_emit_<case>` row against, so the E2E and the gate read the SAME
artefact.

RESTORED 2026-10-16 from `.agents/slop/bend_e2e.py` (blob e853efc4b, 2851 B),
byte for byte, and TWO edits, both forced by a rule and neither touching the
comparison: `OUT` is `gates/artifacts/ops_bend_exec/` because that is where a gate
run writes (`gates/README.md`) and `gates/artifacts/` is `.gitignore`d, and the
packets are `.rows` because a `.txt` is a HARD row for `checks/no-txt.py`. It
lived at `__file__.parent` because `__file__` WAS `.agents/slop/`; moving it
without moving the output would have put untracked `.txt` inside `gates/`.
`main` still returns 0 only when every case MATCHES.
"""
import pathlib, sys
from tinygrad import Tensor, Context, Device
from tinygrad.dtype import dtypes

OUT = pathlib.Path(__file__).resolve().parent / 'artifacts' / 'ops_bend_exec'
CAP = []

# `ops_bend` LIVES AT THE REPO ROOT, NOT IN `tinygrad/`: it is this project's CPython-side
# emulator and `tinygrad/` IS THE ORACLE. `git log upstream --find-object` finds NO upstream
# commit carrying it, while every OTHER file under `tinygrad/` has its blob in upstream
# history -- so it was the ONE local edit inside the reference implementation. ROOT goes on the
# path here because this file had none, and `sys.path[0]` when a gate is run is `gates/`.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import ops_bend as OB
OB.executor  # the cached builder; reading it is what makes the import real

# **THE DEVICE NAME `BEND` MUST RESOLVE, AND IT STOPPED RESOLVING WHEN A FILE MOVED.**
# MEASURED 2026-10-25: THIS INSTRUMENT DIED WITH `ModuleNotFoundError: No module named
# 'tinygrad.runtime.ops_bend'`, BECAUSE TINYGRAD's LOADER (`tinygrad/device.py:39`) DOES
# `importlib.import_module(f'tinygrad.runtime.ops_{x}')` -- **AND `ops_bend.py` USED TO LIVE
# AT `tinygrad/runtime/ops_bend.py`, UNTIL `c2a66ea41` MOVED IT TO THE REPO ROOT** SO THAT
# `tinygrad/` WOULD HOLD NO FILE OF OURS AND STAY PRISTINE AS THE ORACLE. **⇒ THE MOVE WAS
# RIGHT AND IT BROKE THE DEVICE NAME, AND NOTHING RE-CHECKED IT.**
# `importlib.import_module` CHECKS `sys.modules` FIRST, SO REGISTERING THE MODULE UNDER THE
# NAME TINYGRAD LOOKS FOR MAKES THE DEVICE RESOLVE **WITHOUT PUTTING A FILE OF OURS BACK INTO
# `tinygrad/`** -- WHICH IS THE WHOLE POINT OF THE MOVE. `get_class` THEN FINDS `BendDevice`
# BY ITS NAME (`device.py:40`: `cname.lower() == x + "device"`), WHICH IS EXACTLY WHAT
# `ops_bend.py` NAMES ITS DEVICE.
sys.modules['tinygrad.runtime.ops_bend'] = OB
_orn = OB.BendRenderer.render
def _render(self, uops):
    CAP.append(uops)
    return _orn(self, uops)
OB.BendRenderer.render = _render
_oi = OB.BendProgram.__init__
def _init(self, dev, obj):
    _oi(self, dev, obj)
    CAP[-1] = (self, obj)
OB.BendProgram.__init__ = _init


def cases():
  """THE CASES, AND **EACH ONE IS A MAKER**: IT BUILDS ITS OWN INPUTS **ON THE CURRENT DEVICE**.

  **⇒ THE ORACLE MUST NOT BE THE SUBJECT.** MEASURED 2026-10-25: THE FIRST VERSION BUILT THE
  INPUTS ONCE, UNDER `Context(DEV='BEND')`, AND THE REFERENCE RE-USED THEM -- SO
  `ref(thunk)` RE-COMPUTED THE SAME THING **ON THE SAME BEND BUFFERS**, AND THE INSTRUMENT
  COMPARED THE WRONG ANSWER WITH ITSELF AND SAID `MATCH`. **THE THREE DEFECTS BELOW WERE ALL
  IN ONE INSTRUMENT, AND THEY COMPOUNDED:** THE DEVICE NAME DID NOT RESOLVE; THE `dot` CASE'S
  INPUTS WERE CONSTANT-FOLDED SO IT LAUNCHED NO KERNEL; AND THE REFERENCE RE-USED THE SUBJECT's
  BUFFERS. **⇒ SO EACH CASE IS A MAKER, AND THE ORACLE BUILDS ITS OWN INPUTS.**

  **AND THE MATMUL's INPUTS MUST NOT BE CONSTANT-FOLDABLE.** `T.arange(16, dtype=f32) + 1` IS
  A **CONSTANT** TENSOR -- upstream's `Tensor.arange` CALLS `r.const()` UNLESS IT NEEDS
  REALIZATION -- SO `xs @ ys` WAS CONSTANT-FOLDED **IN PYTHON** AND LAUNCHED NO KERNEL ON ANY
  DEVICE. A REALIZED BUFFER IS NOT CONSTANT-FOLDABLE, SO THE INPUTS ARE LISTS.
  """
  T = Tensor

  def add4():
    a = T([1.0, 2.0, 3.0, 4.0]).realize()
    b = T([10.0, 20.0, 30.0, 40.0]).realize()
    return lambda: a + b

  def sum4():
    a = T([1.0, 2.0, 3.0, 4.0]).realize()
    return lambda: a[:4].sum(axis=0)

  def addi32():
    i = T([1, 2, 3, 4], dtype=dtypes.int32).realize()
    return lambda: i + i

  def addu32():
    j = T([7, 8, 9, 10], dtype=dtypes.uint32).realize()
    return lambda: j + 1

  def cast():
    i = T([1, 2, 3, 4], dtype=dtypes.int32).realize()
    return lambda: (i + 1).cast(dtypes.float32)

  def cmp():
    a = T([1.0, 2.0, 3.0, 4.0]).realize()
    return lambda: a > 2.0

  def dot():
    xs = T([float(i + 1) for i in range(16)]).realize().reshape(4, 4)
    ys = T([float(2 * i + 2) for i in range(16)]).realize().reshape(4, 4)
    return lambda: xs @ ys

  return [('add4', add4), ('sum4', sum4), ('addi32', addi32), ('addu32', addu32),
          ('cast', cast), ('cmp', cmp), ('dot', dot)]


def ref(mk):
  """CPython's own answer, from the PYTHON device -- the emulator ops_bend.py
  was forked from, and the oracle for this file.

  **THE MAKER RUNS HERE, SO THE ORACLE BUILDS ITS OWN INPUTS ON THE PYTHON DEVICE.** THE
  SUBJECT's BUFFERS ARE NOT RE-USED: SEE `cases()`."""
  with Context(DEV='PYTHON'):
    return mk()().tolist()


def main():
  exe = OB.executor()
  print('# executor built once, keyed by executor.bend mtime+size:')
  print('#   ', exe)
  ok = bad = 0
  for name, mk in cases():
    CAP.clear()
    try:
      # **THE CASE MUST RUN ON THE BEND DEVICE, AND NOT ON WHATEVER THE DEFAULT IS.**
      # MEASURED 2026-10-25: THE FIRST VERSION REALIZED THE INPUTS INSIDE
      # `with Context(DEV='BEND')` BUT RAN THE `thunk` OUTSIDE IT -- **AND `Device.DEFAULT`
      # IS `METAL` ON THIS MACHINE** -- SO A CASE COULD RUN ON THE GPU AND STILL BE REPORTED.
      with Context(DEV='BEND'):
        got = mk()().tolist()
    except Exception as e:
      print(f'== {name}: FAILED {type(e).__name__}: {e}'); bad += 1; continue
    try:
      want = ref(mk)
    except Exception as e:
      print(f'== {name}: REFUSED -- the oracle failed: {type(e).__name__}: {e}')
      bad += 1
      continue
    same = repr(got) == repr(want)
    # **AND A CASE THAT RENDERED NO PACKET DID NOT RUN ON THE DEVICE AT ALL.** THAT IS A
    # REFUSAL, NOT A MATCH: THE COMPARISON WAS AGAINST A NUMBER THIS DEVICE NEVER PRODUCED.
    if not CAP:
      print(f'== {name}: REFUSED -- no packet was rendered, so this case did not run on BEND; '
            f'the answer {got} came from somewhere else')
      bad += 1
      continue
    ok, bad = (ok + 1, bad) if same else (ok, bad + 1)
    print(f'== {name}: bend={got} python={want} {"MATCH" if same else "MISMATCH"}')
    if CAP:
      OUT.mkdir(parents=True, exist_ok=True)
      (OUT / f'packet-{name}.rows').write_text(CAP[-1][1].lib.decode())
  print(f'# {ok} match, {bad} mismatch-or-refused')
  return 0 if bad == 0 else 1


if __name__ == '__main__':
  sys.exit(main())