#!/usr/bin/env python3
"""f64/oracle_f64.py -- THE EXPECTATION FOR THE f64 LANE.  Nothing here is typed.

    .venv/bin/python .agents/slop/f64/oracle_f64.py <workdir> <mm-rows.txt>

`build()` is also the entry point `run-f64.sh` plants into the copy of
`portexec/oracle.py`, because `run-kernel.sh mm` runs `oracle.py` itself and then
`gen_ffi.py` reads `oracle.json`.  Planted rather than bypassed: the committed
harness stays unmodified, and the lane therefore gets `run-kernel.sh`'s own seven
named steps, its own three mm-mode plants and its own `MISMATCH at N/64 words`
string, all of which work on this fixture VERBATIM -- see the header of
`emit-f64.bend` for why the body was spelled to make that true.

What happens here, none of it a transcription:

  1. **THE PORT'S OWN C TEXT** is read out from between the two markers in the
     port's stdout, and its signature line is asserted to contain
     `double* restrict data0_4`.  That assertion is the row that says the port
     rendered `S.double()` as a C `double*`, which is the thing under test.

  2. **CPython EMITS THE SAME KERNEL FROM THE SAME BODY.**  Upstream's own
     `ClangRenderer.render_kernel` is called with those body lines and four
     `UOp.param(..., dtypes.f64, ...)`, and its answer is written next to the
     port's for an EXTERNAL `diff`.  Two independently written sources -- the
     Bend file and this one -- that agree byte for byte are two witnesses.  A
     port that said `float*` here would be caught before `cc` is ever reached.

  3. **THE ANSWER IS COMPUTED TWICE IN CPYTHON** -- numpy `float64`, and the
     kernel actually EXECUTED on the real `Device["CPU"]` through tinygrad's own
     `CPUProgram` + `ctypes`, exactly as `portexec/oracle.py:100` does for f32,
     one dtype wider.  Both must agree before either is used.

  4. **THE FIXTURE'S `DELTA` LITERAL IS RE-DERIVED AND CHECKED.**  `emit-f64.bend`
     writes `9.094947017729282e-13`, which is `repr(2.0**-40)`, CPython's
     shortest round-tripping decimal.  This recomputes it and REFUSES to emit an
     oracle if the committed literal disagrees.  A hand-typed constant that
     silently stopped being `2**-40` would make the whole lane a self-comparison,
     and `agent-core.md` tabulates five separate times that a hand-typed number
     cost a unit its rows.

THE NUMBER THE LANE EXISTS FOR.  `out[0] = (A@B)@D[0][0] + DELTA`, with A@B =
diag(2,1,1,1) and D[0][0] = 0.5, so `out[0] = 1.0 + 2**-40`.  In f64 that is
`0x3FF0000000001000`.  In f32 it rounds to exactly `1.0`, `0x3F800000`.  Both are
computed here and carried in the oracle so the report can print them side by side
instead of asserting a difference.

`mm_A`/`mm_B`/`mm_C`/`mm_expect_words` are the four keys `gen_ffi.py` already
reads in `mm` mode.  They are re-used, not re-invented.  Each is 64 u32 words
because an f64 element IS two consecutive u32 words at the 4-byte stride
`fill.go`/`dump.go` already walk -- that is why no harness change is needed for
the wider dtype, and why the word count matches the f32 lane's 64/64 bar.
"""
import dataclasses
import json
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

import numpy as np
from tinygrad.renderer.cstyle import ClangRenderer
from tinygrad.device import Target
from tinygrad.uop.ops import UOp, dtypes

DELTA = 2.0 ** -40          # 9.094947017729282e-13 -- `repr` below must agree
DELTA_TEXT = "9.094947017729282e-13"

# A = data1_4, 4x8 = [T | 0] with T = diag(2,1,1,1);  B = data2_4, 8x4 = [I_4; 0];
# D = data3_4, 4x8.  Then (A@B) = T exactly, and out = (A@B)@D + DELTA.
# EVERY VALUE IS A SMALL INTEGER EXCEPT D[0][0] = 0.5, so the matmul is EXACT and
# the ONLY rounding anywhere in the kernel is the single `+ DELTA`.  That is
# deliberate and it is what makes the oracle robust: no summation order, no
# association and no FMA contraction can move the answer, so a red lane cannot be
# excused as "the oracle associated the sum differently".
A = [[2, 0, 0, 0, 0, 0, 0, 0],
     [0, 1, 0, 0, 0, 0, 0, 0],
     [0, 0, 1, 0, 0, 0, 0, 0],
     [0, 0, 0, 1, 0, 0, 0, 0]]
B = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1],
     [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
D = [[0.5, 3, 7, 11, 17, 23, 29, 31],
     [-1, -2, -3, -5, -8, -13, -21, -34],
     [41, -43, 47, -53, 59, -61, 67, -71],
     [73, -79, 83, -89, 97, -101, 103, -107]]


def flat(m):
  return [float(v) for row in m for v in row]


def words64(vals):
  """A float64 buffer as u32 words in **MEMORY ORDER**, which is what the lane
  writes and reads.

  That order is `(lo, hi)` and getting it backwards is a real, measured failure:
  the first version of this function returned `(hi, lo)` with a comment claiming
  "on this host the HIGH word is the even one", which is FALSE for little-endian.
  `struct.pack('<d', 1.0)` is the bytes `00 00 00 00 00 00 f0 3f`, so `unpack`
  yields `(0, 0x3ff00000)` -- the LOW word first.  Filling the buffer `(hi, lo)`
  made every operand a denormal (`A[0]` read back as `5.3e-315`), the products
  were zero, and the kernel dutifully returned exactly `DELTA` for all 32
  elements.  A lane that compares only the answer would have reported 64/64
  against a wrong oracle; it was caught because the answer was `DELTA` alone,
  which is a shape no correct matmul can have.

  `dump.go` walks the buffer at a 4-byte stride and `fill.go` fills it the same
  way, so an f64 element is simply two consecutive u32 words and NOTHING in
  `gen_ffi.py` has to know the dtype is 8 bytes wide.  Never typed --
  `struct.pack`, and the ROUND TRIP below is the check that would have caught
  the swap: re-packing the returned words must reproduce the input bit for bit,
  which `(hi, lo)` cannot do and `(lo, hi)` can."""
  u = struct.unpack(f"<{2 * len(vals)}I", struct.pack(f"<{len(vals)}d", *vals))
  out = [w for i in range(len(vals)) for w in (u[2 * i], u[2 * i + 1])]
  back = struct.unpack(f"<{len(vals)}d", struct.pack(f"<{2 * len(vals)}I", *out))
  assert list(back) == list(vals), "the (lo, hi) split does not round-trip"
  return out


def expect64():
  """`out = (A@B)@D + DELTA` in numpy float64.  The port computes it in C in this
  order and the summands are exact integers, so this is THE value, not an
  approximation of it."""
  a = np.array(flat(A), dtype=np.float64).reshape(4, 8)
  b = np.array(flat(B), dtype=np.float64).reshape(8, 4)
  d = np.array(flat(D), dtype=np.float64).reshape(4, 8)
  return [float(v) + DELTA for v in (a @ b @ d).reshape(-1)]


def bare(cls, arch="TEST"):
  """`oracle.py:46` `_bare`, reused in spirit: build the renderer with
  `__new__` and hand-set `target`, so `render_kernel` runs without a `ClangCompiler`
  being constructed.  `render_kernel` is a string-layer method; the compiler is
  the runtime layer and is not what is under test."""
  o = object.__new__(cls)
  o.target = dataclasses.replace(Target(f"TEST {arch}"), arch=arch)
  return o


def cpython_kernel(body):
  """UPSTREAM'S OWN `render_kernel`, on the PORT'S OWN body lines and four f64
  buffers.  A second, independent emission -- not a copy of the port's text."""
  bufs = [(f"data{i}_4", (UOp.param(i, dtypes.f64, ()), True)) for i in range(4)]
  return bare(ClangRenderer, "x86_64,znver2").render_kernel("mm", body, bufs, [], None)


def cpython_exec(body, a, b, d):
  """THE KERNEL RUNNING UNDER REAL tinygrad ON THE REAL CPU DEVICE, `dtypes.f64`,
  through `Compiled` + `CPUProgram` + `ctypes` -- the same reference shape
  `portexec/oracle.py:100` uses for f32, one dtype wider.

  THE ARGUMENT ORDER IS READ OFF THE SIGNATURE AND NOT GUESSED: the body's only
  store is `data0_4[...] = ...`, so `data0_4` is the OUT buffer and it is FIRST.
  `oracle.py:118` records the cost of getting this backwards."""
  import ctypes
  from tinygrad.device import Device, TinyELF
  src = cpython_kernel(body)
  dev = Device["CPU"]
  prog = dev.runtime(TinyELF(dev.compiler.compile(src), "mm", Target(dev.arch),
                             tuple((f"data{i}_4", 0, dtypes.f64, (32,)) for i in range(4))))
  dst = np.zeros(32, dtype=np.float64)
  # THE THREE INPUT ARRAYS ARE HELD IN A LIST AND NOT BUILT IN A GENERATOR, because
  # MEASURED HERE: with `(p(np.array(v, ...)) for v in ...)` the temporaries are
  # collected the moment the generator is exhausted, so `prog` is handed three
  # FREED addresses.  It did not raise -- it returned 32 plausible-looking garbage
  # floats (-308074.375, 392869.75, ...) and would have been a silent wrong answer
  # rather than a crash.  A reference that outlives the call is not a style choice.
  srcs = [np.array(v, dtype=np.float64) for v in (a, b, d)]
  p = lambda x: ctypes.addressof(ctypes.c_char.from_buffer(x))
  prog(p(dst), *(p(x) for x in srcs))
  return [float(v) for v in dst]


def check_fixture(work):
  """(4) THE CONSTANT, re-derived.  Refuses rather than warns."""
  if repr(DELTA) != DELTA_TEXT:
    sys.exit(f"FIXTURE CONSTANT MOVED: repr(2.0**-40) is {repr(DELTA)} but "
             f"emit-f64.bend says {DELTA_TEXT!r}. Refusing to emit an oracle.")
  src = (ROOT / ".agents/slop/f64/emit-f64.bend").read_text()
  if DELTA_TEXT not in src:
    sys.exit(f"FIXTURE CONSTANT ABSENT: {DELTA_TEXT!r} is not in emit-f64.bend.")
  return src


def build(mm_rows_path):
  """THE ORACLE, as the dict `oracle.json` holds.  Two files are written beside
  it for an EXTERNAL `diff`: `port-kernel.c` and `cpython-kernel.c`."""
  work = pathlib.Path(mm_rows_path).parent
  work.mkdir(parents=True, exist_ok=True)
  check_fixture(work)

  # (1) THE PORT'S OWN TEXT, from between the markers -- not retyped.
  t = pathlib.Path(mm_rows_path).read_text()
  raw = t[t.index("KERNEL_BEGIN") + 12:t.index("KERNEL_END")]
  port = raw.strip("\n")
  body = port.splitlines()[1:-1]        # drop `void mm(...) {` and the closing `}`
  assert "double* restrict data0_4" in port, "the port did not emit a double signature"

  # (2) CPython EMITS THE SAME KERNEL FROM THE SAME BODY.  BOTH SIDES STRIPPED,
  # because upstream's Clang override brackets the program with a newline on each
  # side (`cstyle.py:166`) and `gen_ffi.py:177` already strips the port's side
  # before handing the text to `cc`.  Comparing a stripped side against an
  # unstripped one manufactures a two-line "port bug" that is only a newline --
  # MEASURED HERE, once, before it could be reported as one.  Both raw forms are
  # printed so the reader can see the brackets rather than take it on trust.
  cp_raw = cpython_kernel(body)
  cp = cp_raw.strip("\n")
  (work / "port-kernel.c").write_text(port + "\n")
  (work / "cpython-kernel.c").write_text(cp + "\n")

  # (3) THE ANSWER, twice, in CPython.
  a, b, d = flat(A), flat(B), flat(D)
  want = expect64()
  assert cpython_exec(body, a, b, d) == want, "numpy float64 and tinygrad DEV=CPU DISAGREE"
  w = words64(want)
  f32_0 = float(np.float32(1.0 + np.float32(DELTA)))

  return {
      "mm_A": words64(a), "mm_B": words64(b), "mm_C": words64(d),
      "mm_expect_words": w,
      "mm_source": "f64/oracle_f64.py -- numpy float64 AND tinygrad DEV=CPU, agreeing",
      "vec4_typedef": "",                      # the f64 body uses no vector type
      "f64_delta": DELTA, "f64_delta_text": DELTA_TEXT,
      "f64_port_text_is_cpython_text": port == cp,
      "f64_raw_brackets": [raw[:1], raw[-1:], cp_raw[:1], cp_raw[-1:]],
      "f64_out0_words": w[:2],
      "f64_out0_value": want[0],
      "f32_out0_words": [int(v) for v in np.array([1.0], dtype=np.float32).view(np.uint32)],
      "f32_out0_value": f32_0,
      "f32_rounds_to_one": f32_0 == 1.0,
  }


def main():
  work, rows_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
  res = build(rows_path)
  (work / "oracle.json").write_text(json.dumps(res, indent=1))
  w = res["mm_expect_words"]
  sig = [l for l in pathlib.Path(rows_path).read_text().splitlines() if "double* restrict" in l]
  print("  port signature :", sig[0][:100] if sig else "*** NO double SIGNATURE ***")
  print(f"  port text == CPython text (stripped): {res['f64_port_text_is_cpython_text']}")
  print(f"  raw brackets   : port {res['f64_raw_brackets'][0]!r}..{res['f64_raw_brackets'][1]!r}"
        f"   cpython {res['f64_raw_brackets'][2]!r}..{res['f64_raw_brackets'][3]!r}")
  print("  words: in_A/in_B/in_C/expect =",
        len(res["mm_A"]), len(res["mm_B"]), len(res["mm_C"]), len(w))
  print(f"  out[0] f64 : hi=0x{w[0]:08x} lo=0x{w[1]:08x}  = 1.0 + 2**-40 = {res['f64_out0_value']!r}"
        f"  (CPython struct.pack: '0x{struct.unpack('<Q', struct.pack('<d', res['f64_out0_value']))[0]:016x}')")
  print(f"  out[0] f32 : 0x{res['f32_out0_words'][0]:08x}         = {res['f32_out0_value']!r}"
        f"  == 1.0 exactly: {res['f32_rounds_to_one']}")


if __name__ == "__main__":
  main()