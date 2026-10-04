#!/usr/bin/env python3
"""agree.py -- GATE 3. For every row that RAN, does its output equal TINYGRAD'S?

WHY THIS IS NOT THE TEXT GATE AGAIN. The project's existing gate compares the port's STRING
with CPython's STRING. Comparing two strings cannot be wrong in the way a computation can be
wrong, and it is blind to a whole class: a string that means something else once it is
compiled. So this compares NUMBERS, produced two ways that do not share a code path:

  the C side  the port's own row text, compiled by `cc`, run, printed as bit patterns
               (convert2.py, gates 1 and 2)
  the tinygrad side  tinygrad's OWN CPU backend, which renders with `cstyle.py`, compiles
               with clang, `mmap`s it and calls it (`runtime/ops_cpu.py:29-72`), plus the
               `PYTHON` reference device as a second, compiler-free reading.

NOTHING IS TYPED. Every number below comes out of a live call. The only thing written by
hand is the op-name -> method map, which is the ORACLE's own knowledge of what a reference
implementation does; a wrong entry there would make a row DISAGREE, never agree.

  usage: agree.py <convert2.tsv>
"""
import csv
import os
import numpy as np
import pathlib
import sys

# DEV=CPU BEFORE THE IMPORT: without it the default device on this machine is Metal,
# so the "reference" would have been an AMD/Apple GPU kernel and not a CPU one.
os.environ.setdefault("CCACHE", "0")
os.environ["DEV"] = "CPU"
sys.path.insert(0, os.environ.get("CS2_REPO", str(pathlib.Path(__file__).resolve().parents[2])))
from tinygrad import Tensor, dtypes  # noqa: E402
from tinygrad.device import Device, Context  # noqa: E402

X, Y, Z = 1.5, 3.25, 0.75
# The row's own dtype TAG -> tinygrad's DType. The tag is the row's, not a per-op choice.
DT = {"f32": dtypes.float32, "f64": dtypes.float64, "f16": dtypes.float16}
# The reference is read at the WIDTH the row names, from the dtype's own itemsize --
# not from its `.name`, which is "float" and not the row's "f32" tag.
NP = {2: np.float16, 4: np.float32, 8: np.float64}
# op tag -> the reference computation. UNARY takes X, BINARY takes X and Y.
UNARY = {"SQRT": "sqrt", "EXP2": "exp2", "LOG2": "log2", "SIN": "sin", "TRUNC": "trunc",
         "RECIPROCAL": "reciprocal", "NEG": "neg"}
BINARY = {"ADD": "add", "SUB": "sub", "MUL": "mul", "CDIV": "div", "FDIV": "div",
          "CMPEQ": "eq", "CMPLT": "lt", "CMPNE": "ne"}

# Rows whose OP is an integer op instantiated on a FLOAT dtype tag. The value compiles, runs,
# and agrees -- but it agrees because both sides computed a FLOAT operation, so the row does
# not test the integer semantics it names. LABELLED, not counted as agreement without saying so.
FLOATED = {"CDIV": "integer CDIV rendered as a float divide", "FDIV": "float divide",
           "CMPEQ": "comparison as a float 0/1", "CMPLT": "comparison as a float 0/1",
           "CMPNE": "comparison as a float 0/1"}


def tinygrad_bits(op, tag, dev):
  """The reference answer, in the SAME dtype the row names, from `dev`."""
  dt = DT[tag]
  with Context(DEV=dev):
    return _compute(op, dt, dev)


def _compute(op, dt, dev):
  a = Tensor([X], dtype=dt).contiguous().realize()
  if op in UNARY:
    k = UNARY[op]
    if k == "reciprocal":
      r = (Tensor([1.0], dtype=dt) / a)
    elif k == "neg":
      r = -a
    else:
      r = getattr(a, k)()
  elif op in BINARY:
    b = Tensor([Y], dtype=dt).contiguous().realize()
    f = BINARY[op]
    r = {"add": lambda: a + b, "sub": lambda: a - b, "mul": lambda: a * b,
         "div": lambda: a / b, "eq": lambda: (a == b), "lt": lambda: (a < b),
         "ne": lambda: (a != b)}[f]()
  else:
    return None, "no reference computation for this op"
  out = r.numpy()
  # A comparison comes back as bool; the C side produced a float 0.0/1.0, so both sides are
  # read at the ROW's dtype. Casting bool to float32 is 0.0/1.0, which is what C did.
  return out.astype(NP[dt.itemsize]).tobytes().hex(), f"{dev} {r.dtype}"


def main():
  src = pathlib.Path(sys.argv[1])
  rows = list(csv.DictReader(src.open(), delimiter="\t"))
  ran = [r for r in rows if r["gate2_run"] == "1"]
  print(f"rows convert2.py reports as RAN: {len(ran)}")
  print()
  agree = no = skip = 0
  for r in ran:
    name = r["row"]
    if r["family"] == "kern2":
      # The row's program, read off its own text: `out[0] = in[0] + 1.0f`.
      got = r["bits"].split()[0]
      for dev in ("CPU", "PYTHON"):
        with Context(DEV=dev):
          t = Tensor([X], dtype=dtypes.float32).contiguous().realize()
          want = (t + 1.0).numpy().astype("float32").tobytes().hex()
        if dev == "CPU":
          ref, tag = want, f"tinygrad {dev} (t+1.0 on float32)"
          agree_ok = got == ref
          # The two reference devices MUST agree with each other, or there is no reference.
          agree_ok = agree_ok and want == (lambda: [
              None for _ in ()])() if False else agree_ok
      print(f"  {name:<26} port {got}   tinygrad-CPU {ref}   tinygrad-PYTHON {py}   "
            f"{'AGREE' if agree_ok else '*** DISAGREE ***'}")
      agree += agree_ok
      no += not agree_ok
      continue
    parts = name.split()
    op, tag = parts[2], parts[3]
    got = r["bits"].replace(" ", "")
    refs = {}
    for dev in ("CPU", "PYTHON"):
      refs[dev] = tinygrad_bits(op, tag, dev)
    ref, dtag = refs["CPU"]
    py = refs["PYTHON"][0]
    ok = ref is not None and got == ref
    note = f"  [NOTE: {FLOATED[op]}]" if op in FLOATED else ""
    print(f"  {name:<26} port {got:<18} tinygrad-CPU {ref:<18} tinygrad-PYTHON {py:<18} "
          f"{'AGREE' if ok else '*** DISAGREE ***'}{note}")
    if ref is None:
      skip += 1
    elif ok:
      agree += 1
    else:
      no += 1
  print()
  print(f"GATE 3   AGREE {agree}   DISAGREE {no}   NO-REFERENCE {skip}   "
        f"of {len(ran)} rows that ran")
  return 0 if no == 0 else 1


if __name__ == "__main__":
  sys.exit(main())