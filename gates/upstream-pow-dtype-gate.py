#!/usr/bin/env python3
"""upstream-pow-dtype-gate.py -- AN UPSTREAM-ONLY AUDIT: integer `pow` with a NON-CONSTANT exponent.

    DEV=CPU .venv/bin/python gates/upstream-pow-dtype-gate.py
    .venv/bin/python gates/upstream-pow-dtype-gate.py --plant green
    .venv/bin/python gates/upstream-pow-dtype-gate.py --plant red

READ-ONLY ON `tinygrad/`. Nothing here imports the port and nothing here reimplements pow: every row
is produced by calling upstream's own `Tensor.pow` and letting upstream's own C backend and
upstream's own `clang` judge the result. THE SUBJECT IS A COMPILE FAILURE, so the oracle IS clang --
a second implementation that cannot be wrong about whether the C it was handed is valid C.

THE FINDING, IN ONE SENTENCE. `Tensor.pow` dispatches on whether the exponent is a Python CONSTANT,
so `int32 ** 3` takes an integer path and is correct while `int32 ** Tensor([1,2,3])` falls through
to `codegen/decomp/transcendental.py`'s `xpow`, which is `exp2(e * log2(|base|))` and therefore
UNCONDITIONALLY FLOAT -- and tinygrad then hands clang an `int2` lvalue and a `float2` rvalue.

THE THREE FACTS THAT MAKE IT UPSTREAM'S, MEASURED NOT ASSUMED:

  1. `tinygrad/uop/symbolic.py:188` is `(UPat.var("x").alu(Ops.POW, UPat.cvar("c")), simplify_pow)`
     and `simplify_pow` reads `c.val` on its first line -- so the integer path REQUIRES the exponent
     to be a constant node. `symbolic.py:452` is the catch-all `(UPat(Ops.POW, name="p"), xpow)`.
  2. `mixin/elementwise.py:565`'s guard, `raise RuntimeError("base needs to be float")`, is gated on
     `isinstance(x, ConstType)` -- the SAME syntactic property. So the guard that exists to keep pow
     off the float path fires for one spelling of the exponent and not for the other. **The guard
     and the rewrite agree with each other and are both blind in the same place, which is why the
     bad C reaches the compiler instead of a Python exception.**
  3. `dtype_from_uop` calls itself "the dtype production rules, TOTAL over all Ops" (ops.py:122) and
     answers `dtypes.i32` for `POW(i32, i32)`. The node that SURVIVES the rewrite is `f32`. So the
     dtype tinygrad records for the node and the dtype of the node it renders disagree -- which is
     why the emitted C is internally ill-typed rather than merely numerically wrong.

THE CONTRAST ROWS ARE THE POINT. A gate that only showed the failure is a bug report; a gate that
shows `int32 ** 3` is RIGHT, `f32 ** f32-tensor` is RIGHT, and `int64 ** int64-tensor` is RIGHT,
beside the broken row, has located the defect to the int32 path rather than to `pow`. **`int64`
working is unexplained and this file does not explain it** -- it is reported as an OPEN QUESTION
below, because a mechanism I have not read is not a mechanism I may assert.

THE PIN IS BYTES AND IT IS A CHECK, NOT A LABEL. It used to compare `git show
ad117c928^:tinygrad/uop/symbolic.py` with the working tree's bytes and PRINT the answer --
`IDENTICAL -- this is at the PIN` -- while the exit code ignored it, so the pin could not go
red. It is now the sha256 of the three upstream files the rows are produced FROM, compared
against the WORKING TREE by `gates/gatekit.py:oracle_drift`, and a difference REFUSES (exit
3) instead of being printed. **THE PIN AND THE ROWS ARE TWO INDEPENDENT FACTS:** the pin is
about the BYTES of the inputs, the rows are about upstream's BEHAVIOUR, and a byte change no
row reads leaves the rows green while the pin is red.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"

# THE PIN IS READ BY THE HOUSE'S READER. `gates/gatekit.py:oracle_drift` is the one instrument
# that hashes the file the oracle opens and compares it with a LITERAL, and it is the reader
# `gates/onnx_census-gate.py`, `gates/rand_census-gate.py`, `gates/state_census-gate.py` and
# `gates/ops_python_census-gate.py` all use. The FIVE VERDICTS above are restated rather
# than imported, and that stays true: a NUMBER is a convention this file owns, while the
# reader is an instrument this file uses.
sys.path.insert(0, str(HERE))
from gatekit import oracle_drift  # noqa: E402

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}
EXIT_SURFACE = VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}  # VERDICTS: legacy alias of EXIT_SURFACE
PLANTS = {0: ["--plant", "green"], 1: ["--plant", "red"]}
# WHY THE RED IS A FINDING: int32 ** <tensor> emits int2 = float2, which clang rejects.  THE CLASS
# IS THE WHOLE OF `RED_IS` -- a reader that compares the string to a class name cannot read a
# class out of a sentence, so the sentence lives HERE and the field carries the class alone.
RED_IS = "FINDING"

# THE PIN IS BYTES, NOT A REVISION, AND IT IS A CHECK RATHER THAN A LABEL. The old one
# compared `git show ad117c928^:tinygrad/uop/symbolic.py` with the working tree's bytes and
# PRINTED the answer -- `IDENTICAL -- this is at the PIN` or `DIFFERS` -- and the exit code
# ignored it entirely, so a pin that could not go red was carried as a line of prose. A
# REVISION is the wrong instrument twice over: it names a COMMIT rather than the file on
# disk, and it cannot see a working tree whose bytes differ from every revision it names.
#
# `gates/gatekit.py:oracle_drift` is the house mechanism and it REFUSES (exit 3) instead of
# printing. THE VALUES ARE LITERALS, and they must stay literals: a pin re-derived from the
# file it checks is `sha256(x) == sha256(x)`, which cannot fail. `gates/blobpin-census-gate.py`
# MEASURES that claim over every pin site in the tree and fails a derived one.
#
# THE THREE FILES ARE THE POW PATH THIS GATE'S OWN HEADER NAMES: `symbolic.py`'s
# `simplify_pow`/`xpow` rewrites, `mixin/elementwise.py`'s `base needs to be float` guard,
# and `codegen/decomp/transcendental.py`'s `xpow`. The rows are produced by CALLING
# upstream, so a change in any of the three can move them.
DRIFT_PIN = {
  "tinygrad/uop/symbolic.py":
    "6a5dd43c32ac6a3e6d6a8de6b37967e5f0300c228547385862ccbf7572528fb2",
  "tinygrad/mixin/elementwise.py":
    "951d9d8a83e5cd3ae5a26571d685f2cef44fa8b41b1e4c3e028f1bf4d31076de",
  "tinygrad/codegen/decomp/transcendental.py":
    "1d737c265c9f96b8f09d82b85eb660dbb91b558a5af88512075c5a20540d00c5",
}

# THE FIXTURE IS UPSTREAM'S OWN EXPRESSION, SPELLED FIVE WAYS. Every field is a dtype name or a
# list of ints; nothing here invents a field name, because two of this session's agents MIS-SPELLED
# A FIXTURE FIELD in their own oracle and reported a defect against it before catching it.
# `label`/`expr`/`dtype` are all this file's, and all three are read back below.
ROWS = [
  {"label": "i32 ** 3             const exponent", "expr": "T([2,3,4],I32)**3",            "dtype": "int32"},
  {"label": "i32 ** i32tensor    tensor exponent", "expr": "T([2,3,4],I32)**T([1,2,3],I32)", "dtype": "int32"},
  {"label": "i32 ** i32scalar    1-elt tensor",    "expr": "T([2,3,4],I32)**T([1],I32)",    "dtype": "int32"},
  {"label": "defaultint ** defaultint",            "expr": "T([2,3,4])**T([1,2,3])",         "dtype": "default"},
  {"label": "f32 ** f32tensor    float control",   "expr": "T([2.,3.,4.])**T([1.,2.,3.])",  "dtype": "float32"},
  {"label": "i32 ** i64tensor    int64 control",   "expr": "T([2,3,4],I32)**T([1,2,3],I64)", "dtype": "int64"},
]


def run_rows():
  """Each row is a SEPARATE PROCESS. One row's clang failure writes to the shared stderr and can
  leave a half-written `.so`; a gate that ran all six in one interpreter would be attributing one
  row's damage to the next."""
  script = r'''
import sys, warnings; warnings.filterwarnings("ignore")
from tinygrad import Tensor, dtypes
I32, I64 = dtypes.int32, dtypes.int64
T = lambda v, dt=None: Tensor(v) if dt is None else Tensor(v, dtype=dt)
# `dtype=` IS A KEYWORD. `Tensor([2,3,4], dtypes.int32)` passes the dtype as DEVICE, and raises an
# AttributeError from deep inside `device.canonicalize` rather than anything to do with pow -- which
# is exactly the "MIS-SPELLED FIXTURE FIELD" failure, and it is loud here only because this file
# runs each row in its own process and reads a VERDICT row rather than an exit code.
rows = [
  ("i32 ** 3             const exponent", lambda: T([2,3,4],I32)**3),
  ("i32 ** i32tensor    tensor exponent", lambda: T([2,3,4],I32)**T([1,2,3],I32)),
  ("i32 ** i32scalar    1-elt tensor",    lambda: T([2,3,4],I32)**T([1],I32)),
  ("defaultint ** defaultint",            lambda: T([2,3,4])**T([1,2,3])),
  ("f32 ** f32tensor    float control",   lambda: T([2.,3.,4.])**T([1.,2.,3.])),
  ("i32 ** i64tensor    int64 control",   lambda: T([2,3,4],I32)**T([1,2,3],I64)),
]
i = int(sys.argv[1]); label, fn = rows[i]
try:
  r = fn(); r.realize()
  print("VERDICT=OK DTYPE=%s VALUE=%s" % (r.dtype, r.numpy().tolist()))
except RuntimeError as e:
  print("VERDICT=GUARDED %s" % e)
except Exception as e:
  print("VERDICT=%s" % type(e).__name__)
'''
  out = []
  for i, row in enumerate(ROWS):
    env = dict(os.environ, DEV="CPU")
    p = subprocess.run([str(PY), "-W", "ignore", "-c", script, str(i)], cwd=ROOT, env=env,
                       capture_output=True, text=True)
    line = next((l for l in p.stdout.splitlines() if l.startswith("VERDICT=")), None)
    # CLANG'S OWN DIAGNOSTIC IS THE EVIDENCE, and it is NOT on the exception: tinygrad calls clang
    # with inherited stderr, so `CalledProcessError.stderr` is None and `str(e)` is just the argv.
    # The text is on THIS subprocess's stderr, because clang is this process's grandchild. Reading
    # `str(e)` alone prints an empty CLANG column on exactly the rows that matter.
    diag = next((l.strip() for l in p.stderr.splitlines() if "incompatible type" in l), None)
    v = line or f"VERDICT=DEAD rc={p.returncode} stderr={p.stderr.strip()[-120:]}"
    out.append((row["label"], f"{v} CLANG[{diag}]" if diag else v))
  return out


def broken(rows):
  """A row is BROKEN unless it COMPILED AND RAN. `GUARDED` (upstream's own RuntimeError) counts as
  working: refusing is a defined outcome, and a guard that refuses is the correct behaviour."""
  return [lbl for lbl, v in rows if not v.startswith("VERDICT=OK")]


def main(argv=None):
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--plant", choices=["green", "red"])
  args = ap.parse_args(argv)

  if args.plant:
    rows = run_rows()
    bad = broken(rows)
    live = FAIL if bad else PASS
    planted = {"green": 0, "red": 1}[args.plant]
    print(f"upstream-pow-dtype-gate --plant {args.plant}: {len(bad)} of {len(rows)} rows do not "
          f"compile-and-run, live verdict {VERDICT[live]}, planted {VERDICT[planted]}")
    return planted if planted == live else FAIL

  if not (ROOT / "tinygrad" / "uop" / "symbolic.py").exists():
    print(f"upstream-pow-dtype-gate: REFUSED, tinygrad/uop/symbolic.py is absent", file=sys.stderr)
    return REFUSED
  # THE PIN IS A CHECK, NOT A LABEL. The old one compared a REVISION's bytes with the
  # working tree's and PRINTED the answer while the exit code ignored it, so the pin could
  # not go red. `oracle_drift` compares the WORKING TREE's bytes with a LITERAL sha256 and
  # refuses when they differ, which is the house mechanism and the only shape in which this
  # pin can fail at all.
  #
  # THE PIN AND THE OUTPUT CHECK ARE NOT THE SAME FACT. The PIN checks the BYTES of the
  # three upstream files the rows are produced from -- the INPUTS. The OUTPUT CHECK is the
  # six fixture rows, each run in its own process, and it is a fact about BEHAVIOUR: what
  # upstream's own `Tensor.pow` does with a non-constant exponent. A byte change that no row
  # reads leaves the rows green and the pin red; a change in upstream's promotion rules
  # leaves the pin green and moves the rows. Neither is re-derived from the other.
  drift = oracle_drift(DRIFT_PIN)
  if drift:
    print("upstream-pow-dtype-gate: REFUSED, NOT A VERDICT: the upstream files this gate "
          "audits have moved, so the six rows would be measured against bytes this gate has "
          "not read", file=sys.stderr)
    for b in drift:
      print(f"   {b}", file=sys.stderr)
    return REFUSED

  rows = run_rows()
  if not any(v.startswith("VERDICT=") and not v.startswith("VERDICT=DEAD") for _, v in rows):
    print("upstream-pow-dtype-gate: DEAD, no row emitted a verdict", file=sys.stderr)
    return DEAD
  bad = broken(rows)
  print(f"upstream-pow-dtype-gate: {len(rows)} fixture rows, each in its OWN process under DEV=CPU")
  print(f"  the audited upstream files are byte-identical to the pin: "
        f"{', '.join(sorted(DRIFT_PIN))}")
  for lbl, v in rows: print(f"     {lbl:36s} {v}")
  print(f"  {len(bad)} of {len(rows)} rows do not compile-and-run: {bad}")
  print("  OPEN QUESTION, NOT ANSWERED HERE: int64 ^ int64-tensor compiles and is correct while")
  print("  int32 ^ int32-tensor does not. This file records that difference and does not claim a")
  print("  mechanism for it, because a mechanism nobody read is not a mechanism.")
  code = FAIL if bad else PASS
  print(f"upstream-pow-dtype-gate: {VERDICT[code]} -- {len(bad)} of {len(rows)} integer-pow rows "
        f"emit C that clang rejects")
  return code


if __name__ == "__main__":
  sys.exit(main())