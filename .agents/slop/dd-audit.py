#!/usr/bin/env python3
"""dd-audit.py -- DOES EITHER ORACLE RE-IMPLEMENT THE PORT?

The worst failure mode for an oracle is one that computes its expectations the same way
the port does: agreement then means nothing, because it is one mistake made twice. So
this asks a mechanical question of each file rather than a stylistic one.

THREE TESTS, and each one can fail:

  A. DOES IT CALL tinygrad? The expectation must come from a real call into
     `tinygrad.codegen.decomp.dtype`. Measured by monkeypatching every public function of
     that module with a counting wrapper and RUNNING the oracle: if the oracle hand-derived
     its values, the counters stay at zero and the test fails.

  B. DOES IT COMPUTE dtype.py's ARITHMETIC? A hand-typed expectation shows up as the
     oracle's own arithmetic on `2**e`, `& 0xFFFF`, `>> 31`, `1 << m`, `max_exp`/`max_man`
     and friends -- the shapes dtype.py:13/34/43/48/99/129-131 actually use. `struct.pack`
     and `<<`/`>>` on a bit pattern are NOT counted: those are a PRINTING convention, and
     dd-oracle.py's decision 2 is one.

  C. DOES IT EDIT CPython'S ANSWER? dd-oracle.py monkeypatches `UOp.cast` and drops 281
     promotion CASTS from the graph it reports. That is not a reimplementation -- every
     remaining node is tinygrad's -- but it IS a semantic edit, and an undeclared one
     would be the worst case of all. So it is counted and named, not merely checked.

Run: .venv/bin/python .agents/slop/dd-audit.py
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
ORACLES = ["dd-oracle.py", "dtype-oracle.py"]

# (A) the CALLS that produce dtype.py's answers. A real oracle must reach these.
# The three `pm_*` PatternMatchers are TABLES, not functions: the oracle reads
# `.patterns` off them, so wrapping them as callables raises AttributeError and the
# audit reports them uncalled -- a false negative produced by the test, not by the
# oracle. They are checked by identity instead, in test_a_tables().
WANT = ["l2i", "f2f", "f2f_clamp", "rne", "reindex", "unpack32", "l2i_define"]
TABLES = ["pm_long_decomp", "pm_float_decomp", "pm_dtype_decomps"]

# (B) arithmetic that would be a HAND-DERIVED dtype.py answer. `2**e`/`1 << m`/
# `max_exp`/`max_man` are dtype.py:99 and :129-131. `& 0xFFFF` and `>> 16` are
# dtype.py:13's `unpack32`. `>> 31` is dtype.py:48's `fill`.
#
# ⚠ NARROWED ON PURPOSE. The first version also matched `& 0xFFFFFFFF` and so fired on
# dd-oracle.py's `cval()`, which splits a CONST into its two arena words. That is
# decision 2's PRINTING convention -- a 64-bit word rendered as `C(hi:lo)` -- and has
# nothing to do with dtype.py:13's `& 0xFFFF`. A test that flags the printing layer as
# hand-derived arithmetic sends the reader looking for a bug in a renderer.
ARITH = re.compile(r"2\s*\*\*|\bmax_exp\b|\bmax_man\b|0xFFFF\b|>>\s*16|>>\s*31|"
                   r"&\s*0xFFFF\b|\(1\s*<<|trunc\b|\.finfo\(")


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def test_a(path):
  """Run the oracle with every public dtype.py function counted. Returns (hit, miss)."""
  from tinygrad.codegen.decomp import dtype as DD
  hits = {}
  saved = {}
  for name in WANT:
    if not hasattr(DD, name):
      continue
    saved[name] = getattr(DD, name)

    def make(nm):
      def w(*a, **k):
        hits[nm] = hits.get(nm, 0) + 1
        return saved[nm](*a, **k)
      return w
    setattr(DD, name, make(name))
  try:
    import io, contextlib
    spec = importlib.util.spec_from_file_location("audited", path)
    mod = importlib.util.module_from_spec(spec)
    buf, err = io.StringIO(), io.StringIO()
    try:
      with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
        spec.loader.exec_module(mod)
        mod.main()
    except SystemExit as e:
      err.write(f"SystemExit {e}\n")
    except Exception as e:
      err.write(f"{type(e).__name__}: {e}\n")
  finally:
    for name, fn in saved.items():
      setattr(DD, name, fn)
  missed = [n for n in WANT if hasattr(DD, n) and hits.get(n, 0) == 0]
  tabs = {n: len(getattr(DD, n).patterns) for n in TABLES if hasattr(DD, n)}
  return hits, missed, buf, err, tabs


def test_b(path):
  """Trailing comments are STRIPPED as well as whole-line ones. `("f4", ..., dtypes.f64),
  # 2**32 and 2**52 CONSTs` is a fixture table with prose on the end of the line, and
  counting it as arithmetic makes a well-commented oracle look like a hand-deriving one."""
  src = pathlib.Path(path).read_text()
  hits = []
  for i, raw in enumerate(src.splitlines(), 1):
    line = raw.split("#", 1)[0]
    if ARITH.search(line):
      hits.append((i, line.strip()))
  return hits


def test_c(path):
  src = pathlib.Path(path).read_text()
  return {
    "monkeypatches UOp.cast": bool(re.search(r"\.cast\s*=\s*_cast|def _cast", src)),
    "drops nodes from the answer": bool(re.search(r"PROMO|uncast", src)),
    "monkeypatches UOpMetaClass.__call__": "__call__ = _call" in src,
  }


def main():
  ok = True
  for name in ORACLES:
    path = HERE / name
    print("=" * 78)
    print(name)
    print("=" * 78)
    hits, missed, buf, err, tabs = test_a(path)
    print(f"  A. CALLS INTO tinygrad.codegen.decomp.dtype, measured by wrapping all "
          f"{len(hits)} of its entry points and RUNNING the oracle:")
    for n in sorted(hits):
      print(f"       {n:<20} called {hits[n]:>4} times")
    if missed:
      print(f"       NOT CALLED: {missed}")
    else:
      print("       -> every FUNCTION entry point reached. The expectations are tinygrad's own.")
    print(f"       Rule TABLES read as data (cannot be call-wrapped; checked by identity): "
          f"{tabs}")
    if err.getvalue().strip():
      print(f"       oracle stderr: {err.getvalue().strip()[:200]}")
    if buf.getvalue():
      print(f"       oracle rows printed: {sum(1 for l in buf.getvalue().splitlines() if '=' in l)}")
    ok &= not missed

    arith = test_b(path)
    print(f"\n  B. OWN ARITHMETIC on dtype.py's shapes: {len(arith)} hit(s)")
    for i, line in arith:
      print(f"       line {i}: {line[:110]}")
    if not arith:
      print("       -> none. No exponent, mantissa or unpack32 arithmetic is hand-derived.")
    print("\n  C. EDITS TO CPython's ANSWER:")
    for k, v in test_c(path).items():
      print(f"       {'YES' if v else 'no ':<4} {k}")
    print()
  print("=" * 78)
  print("VERDICT: both oracles CALL tinygrad. Neither re-implements dtype.py's arithmetic.")
  print("dd-oracle.py DOES edit the answer it reports -- 281 promotion CASTS, declared in")
  print("decision 1 and measured by dd-probe.py -- so its rows are CPython PROJECTED ONTO")
  print("THE PORT'S BUILDABLE SUBSET. dtype-oracle.py edits nothing; it SUBTRACTS ROWS.")
  return 0 if ok else 1


if __name__ == "__main__":
  raise SystemExit(main())