#!/usr/bin/env python3
"""cstyle-oracle.py -- take the REAL C text tinygrad's own CPU backend hands to clang, for
a program chosen to match `cstyle.bend`'s `kern2 CLANG` fixture, and print it.

WHY THIS IS NEEDED AT ALL. Every one of `cstyle.bend`'s 227 rows is a STRING comparison on
newline-escaped text (`esc_row`, cstyle.bend:1808). Nothing downstream has ever undone the
escape and asked a compiler. Worse, the `kern2` FIXTURE uses `emit_min()` -- an EMPTY
`_render_defines` list -- while its body reads and writes a `float4`, and `float4` is not a
C type at all: `ClangRenderer.float4 == "(float4)"` (cstyle.py:279) is a tinygrad pseudo-type
that only ever becomes a real type via `ClangRenderer._render_defines` ->
`render_vector_prefix` (cstyle.py:303-309), i.e. the `vecs` field of the port's `Emit_`.
So the fixture's emitted text CANNOT compile, and the honest question is whether that is a
PORT defect or a FIXTURE gap. This script answers it from the other side: it captures what
tinygrad itself emits for a real program, so (a) the port's `vecs` can be set to the line
CPython actually produces, and (b) the compile invocation used for Stage 1 is proved sound
against a kernel CPython compiled for real.

  usage: cstyle-oracle.py           # print the source CPython emitted
         cstyle-oracle.py --json    # {"src": ..., "nbuf": ..., "n": ...}
"""
import json, os, subprocess, sys

# CCACHE=0 is LOAD-BEARING, not hygiene: `Compiler.compile_cached` (device.py:339-344) is a
# DISKCACHE lookup keyed on (cachekey, src). On a warm cache `compile` is never called, the
# spy below stays empty, and the assertion fires. Measured: with the default CCACHE=1 the
# first run of this script died on its own guard -- which is the guard working, not a bug in it.
os.environ.setdefault("DEV", "CPU")
os.environ["CCACHE"] = "0"

from tinygrad import Tensor, Device  # noqa: E402
from tinygrad.runtime.support.compiler_cpu import ClangCompiler  # noqa: E402

CAPTURED = []
_real = ClangCompiler.compile


def spy(self, src):
  CAPTURED.append(src)
  return _real(self, src)


ClangCompiler.compile = spy

# `a` is 4 contiguous f32, `b` is the constant 1.0f, `c = a + b`. With ALIGNED=1 (the
# default) tinygrad's vectorizer widens this to a single 4-wide f32 load/store, which is
# the shape `cstyle.bend`'s fixture body spells by hand.
N = 4
a = Tensor([1.0, 2.0, 3.0, 4.0]).contiguous().realize()
out = (a + 1.0).contiguous().realize()
out.numpy().tolist()

assert CAPTURED, "nothing reached the compiler -- CAPTURED is empty and the rest would be a lie"
src = CAPTURED[-1]

if "--json" in sys.argv:
  print(json.dumps({"src": src, "n": N, "compiler": "ClangCompiler"}))
else:
  # `sys.stdout.write`, NOT `print`. `print` appends a newline, and the thing being
  # captured already ENDS in one (`ClangRenderer.render_kernel` is
  # `defines + "\n" + body + "\n" + _render_entry(...)` with `_render_entry` returning `""`,
  # cstyle.py:313-315). So `print(src)` manufactures a second trailing newline and the byte
  # comparison against the port then reports a difference that is the HARNESS's, not the
  # port's. MEASURED: `print` gave `...}\n\n` against the port's `...}\n` and a `diff` that
  # looked like a missing newline in the port.
  sys.stdout.write(src)