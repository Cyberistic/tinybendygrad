#!/usr/bin/env python3
"""bf16 gate -- drives the LIVE tinybendygrad/runtime/dtype.c under cc and
compares against CPython's float_to_bf16, i.e. dtype.py:229-233.

THE ROWS ARE BUILT FROM THE FORMAT, NOT FROM dtype.c. JFP-1: a sweep centre read
out of the code under test is a transcript, not a fixture. fp8fix caught the C
defect by sweeping around dtype.c's own OVF, which works by luck. Here:

  B  the FULL bf16 code space, 65536 patterns, bf16 BEING the top half of an
     f32 pattern, so the input is `code << 16`. Both signs: the sign is bit 15,
     so the 65536 ALREADY carry both. Not a sample -- 65536 is the whole space.
  N  every one of the bf16 NON-FINITE encodings (dtype.bend's note and the brief
     both insist: 8 exponent bits all ones x 127 mantissas x 2 signs = 254 plus
     the two infinities = 256), each as an f32 pattern.

EVERY expectation is CALLED, never typed. And the two spellings of the f32 input
are both sent, because the seam takes the pattern and dtype.py takes a float:
  in_pattern = `code << 16`  (what bf16_run receives)
  in_float   = struct.unpack of that (what dtype.py receives)
A row that passes only one of the two is a row that does not exist.

The non-finite f32 space is 16777214 patterns and `class`/census in bf16_gate.c
walks all 2^32 exhaustively against an INDEPENDENT model (decode to float,
frexp/ldexp, re-encode -- no bit add, so it cannot inherit the port's formula).
gate.py adjudicates every pattern that census flags, against CPython.
"""
import os, struct, subprocess, sys, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
# HERE is .agents/slop/bf16 -- THREE levels deep. MEASURED, not guessed: with
# `..`/`..` this resolved DTYPE_C to `.agents/tinybendygrad/runtime/dtype.c`,
# which does not exist, and the only symptom was clang saying `dtype.c` was not
# found -- a complaint about a file that plainly exists, three hops away.
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
DTYPE_C = os.path.join(ROOT, "tinybendygrad", "runtime", "dtype.c")
EXE = os.path.join(os.environ.get("TMPDIR", "/tmp"), "bf16")

sys.path.insert(0, ROOT)
from tinygrad.dtype import float_to_bf16  # dtype.py:229
from tinygrad import Device, dtypes


def build(dtype_c=DTYPE_C, exe=EXE):
    r = subprocess.run(
        # dtype_c is an ABSOLUTE path but `#include "dtype.c"` resolves against
        # the includer's dir then -I, so the dir must be on -I. Measured, not
        # guessed: dropping it is the whole of the failure above.
        ["cc", "-O2", "-I", HERE, "-I", os.path.dirname(dtype_c), "-o", exe,
         os.path.join(HERE, "bf16_gate.c"), "-lm"],
        capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("BUILD FAILED\n" + r.stderr)
    return exe


def md5(path):
    return hashlib.md5(open(path, "rb").read()).hexdigest()


def bf16_rows():
    """Every bf16 code as an f32 pattern. 65536 rows, both signs."""
    for code in range(1 << 16):
        yield (f"B[{code:04x}]", code << 16)


def nonfinite_rows():
    """Every bf16 non-finite encoding. 256 rows: 2 inf + 254 NaN."""
    for code in range(0xFF80, 0x10000):
        yield (f"N[{code:04x}]", code << 16)


def oracle(pattern):
    """dtype.py:229-233 on an f32 pattern, returning the f32 pattern back."""
    x = struct.unpack("<f", struct.pack("<I", pattern))[0]
    r = float_to_bf16(x)
    return struct.unpack("<I", struct.pack("<f", r))[0]


def drive(rows, exe=EXE):
    inp = "".join(f"{n}\t{p:08x}\n" for n, p in rows)
    r = subprocess.run([exe, "rows"], input=inp, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("GATE FAILED\n" + r.stderr)
    out = {}
    for line in r.stdout.splitlines():
        if not line.strip():
            continue
        n, _, v = line.partition("=")
        assert n not in out, f"duplicate row name {n} -- fixture defect"
        out[n] = int(v, 16)
    return out


def check(rows, exe=EXE, label=""):
    got = drive(rows, exe)
    mismatch, names = [], []
    for n, p in rows:
        want, have = oracle(p), got[n]
        if want != have:
            mismatch.append((n, p, want, have))
            names.append(f"{n}={have:08x}")
    return len(rows), len(got), mismatch


def main():
    exe = build()
    print(f"dtype.c md5 {md5(DTYPE_C)}")
    for label, rows in (("B bf16 code space", list(bf16_rows())),
                        ("N bf16 non-finite", list(nonfinite_rows()))):
        n_exp, n_got, mm = check(rows, exe)
        print(f"{label}: expected={n_exp} present={n_got} MISMATCH={len(mm)}")
        for n, p, w, h in mm[:8]:
            print(f"  {n} in={p:08x} cpython={w:08x} dtype.c={h:08x}")
        if len(mm) > 8:
            print(f"  ... {len(mm)-8} more")
        if mm:
            print("NAMES " + " ".join(names))


if __name__ == "__main__":
    main()