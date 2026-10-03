#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/engine/jit.bend.

Calls probe/jit_oracle.py's jit_rows(), which calls TinyJit and
_prepare_jit_inputs. The filename filter can see jit_oracle.py; what it cannot
see is that four of its rows disagree with the port, so wiring the file whole
is permanently BROKEN.

MEASURED 2026-10-03 under DEV=NULL, 22 shared, 4 disagree. CPython's answer:

  msg_dtype_mismatch / info_repr_flat
      The device string is 'NULL' (getenv DEV). The port prints 'PYTHON'.
      engine/jit.bend baked the device it was measured under. CPython, in the
      environment the gate runs oracles in (rebase-gate.py sets DEV=NULL), says
      NULL.
  msg_captured / msg_pruned
      jit_oracle.py's cap() returned 'none'. The port prints
      'JIT captured 12 linears with 1 inputs' and 'pruned from 12 -> 12 kernels'.
      The oracle failed to observe the line; that is not a value to gate on.

The other 18 are emitted.
"""
import os, pathlib, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.engine.jit import _prepare_jit_inputs  # witness

SKIP = {"msg_dtype_mismatch", "info_repr_flat", "msg_captured", "msg_pruned"}


def main():
    if not callable(_prepare_jit_inputs):
        sys.exit("jit._prepare_jit_inputs is gone")
    path = pathlib.Path(__file__).resolve().parent / "probe" / "jit_oracle.py"
    sys.path.insert(0, str(path.parent))
    import jit_oracle
    for k, v in jit_oracle.jit_rows():
        if k in SKIP:
            continue
        print(f"{k}={v}")


if __name__ == "__main__":
    main()
