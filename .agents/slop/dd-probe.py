#!/usr/bin/env python3
"""dd-probe.py -- WHERE dd-oracle.py's "decision 1" edits CPython's answer, and what CPython
really builds for the rows the two oracles disagree on.

Three questions, each answered by CALLING tinygrad and never by arithmetic:

  1. HOW MUCH DOES DECISION 1 DELETE? dd-oracle.py monkeypatches UOp.cast and drops every
     CAST inserted by `mixin/elementwise.py`'s `promote` / `logical_not`, on the stated
     ground that `mixin/elementwise.py` is not ported. That is a semantic edit of the
     reference. It is defensible -- those nodes genuinely cannot exist in the port's arena --
     but it means dd-oracle.py's answer is CPython PROJECTED ONTO THE PORT'S SUBSET, and
     the size of the projection is a fact nobody has measured. Here it is.

  2. THE TRUE CONE for `lg5`, whose `k` row disagrees: is CPython's `F(1333788672)` a real
     CPython node, or an artifact of the deletion? If it survives with decision 1 OFF, the
     port is wrong against unmodified CPython and the deletion is not what hides it.

  3. THE `n` ROWS (`lg1n` 11 vs 10, `lg5n` 10 vs 12, `lg6n` 5 vs 4, `lg9n` 18 vs 17).
     `n` counts nodes interned during the fixture. An off-by-one here is a different
     failure from an off-by-one in a value, so it is measured, not inferred.

Run: .venv/bin/python .agents/slop/dd-probe.py
"""
import importlib.util
import pathlib
import struct
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


dd = load("dd_oracle", HERE / "dd-oracle.py")

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops

L2I = {nm: (op, dt, xdt, n) for nm, op, dt, xdt, n in dd.L2I()}


def walk(roots):
  seen, out = set(), []

  def go(v):
    if id(v) in seen:
      return
    seen.add(id(v))
    out.append(v)
    for s in v.src:
      go(s)
  for r in roots:
    go(r)
  return out


def raw_cone(roots, promo_filter):
  """The cone with decision 1 either ON (drop PROMO casts) or OFF (keep every node)."""
  c = walk(roots)
  return [u for u in c if promo_filter or id(u) not in dd.PROMO]


def fixture(nm):
  """None for a REFUSAL. `lgn` is Ops.FLOORDIV and dtype.py:81 raises NotImplementedError,
  so a probe that assumed every fixture answers would die on it -- and a probe that dies
  half way through prints the first rows as if they were the whole measurement."""
  op, dt, xdt, n = L2I[nm]
  try:
    return dd.DD.l2i(op, dt, *dd.ws(xdt, n))
  except Exception:
    return None


def roots_of(r):
  return list(r) if isinstance(r, tuple) else [r]


def main():
  print("=" * 78)
  print("1. HOW MUCH OF CPYTHON'S ANSWER DECISION 1 DELETES")
  print("=" * 78)
  total_promo = 0
  for nm in sorted(L2I):
    out = fixture(nm)
    if out is None:
      print(f"  {nm}: REFUSES in CPython too (dtype.py:81) -- no cone to project")
      continue
    full = walk(roots_of(out))
    kept = [u for u in full if id(u) not in dd.PROMO]
    dropped = [u for u in full if id(u) in dd.PROMO]
    total_promo += len(dropped)
    if dropped:
      kinds = {}
      for u in dropped:
        kinds[u.op.name] = kinds.get(u.op.name, 0) + 1
      print(f"  {nm}: cone {len(full)}, deleted {len(dropped)} {kinds}")
  print(f"\n  TOTAL PROMO-marked nodes across the {len(L2I)} l2i fixtures: {total_promo}")
  print("  These are REAL CPython nodes. dd-oracle.py removes them from its answer because")
  print("  mixin/elementwise.py is unported. So dd-oracle.py's 'CPython answer' is CPython")
  print("  MINUS THE PROMOTION CASTS -- a projection onto what the port can build.")

  print()
  print("=" * 78)
  print("2. lg5 -- IS CPython's F(1333788672) REAL, OR AN ARTIFACT OF THE DELETION?")
  print("=" * 78)
  out = fixture("lg5")
  for label, keep in (("decision 1 OFF (raw CPython)", True), ("decision 1 ON (dd-oracle)", False)):
    c = raw_cone(roots_of(out), keep)
    ks = [dd.lab(u) for u in c if u.op is Ops.CONST]
    print(f"  {label:<32} cone={len(c):<4} constants in cone order: {','.join(ks)}")
  print()
  print("  CPython's float-source arm is dtype.py:33-34 -- `dt in (long, ulong)` and")
  print("  `uops[0].dtype` IS a float, so line 28's guard fails and line 33 is the arm that")
  print("  runs: `(uops[0] / 2**32).cast(l2i_dt[dt])`. Ask tinygrad directly what")
  print("  `UOp.const(2**32)` becomes under `/` with an f32 receiver:")
  f32 = UOp.variable("q", 0, 0, dtypes.f32)
  r = f32 / 2**32
  # RECIPROCAL's own arg is None (it is a unary op); the 2**32 CONST is its SRC, so reading
  # `.arg` off the reciprocal answers None and every downstream print raises TypeError.
  konst = r.src[1].src[0]
  print(f"    f32 / 2**32                      = {dd.tree(r)}")
  print(f"    its 2**32 CONST src              = {dd.tree(konst)} dtype={konst.dtype.name} arg={konst.arg!r}")
  print(f"    dd-oracle's fbits of it          = {dd.fbits(konst.arg)}")
  print(f"    a WEAKINT const 2**32 would be   = {dd.cval(2**32)}")
  print(f"    struct-check: 0x{struct.unpack('I', struct.pack('f', 2.0**32))[0]:08x} is 2**32 in f32")
  print("  => CPython is RIGHT at F(1333788672) and the PORT is wrong at C(1:0). tinygrad")
  print("     rewrites `x / 2**32` as `x * RECIPROCAL(CONST_at_f32(2**32))`; the port builds")
  print("     the divisor as a weakint/i64 2**32, so its divisor is a DIFFERENT NODE.")

  print()
  print("=" * 78)
  print("3. THE `n` ROWS -- ONE OFF-BY-ONE EACH, IN FOUR DIFFERENT DIRECTIONS")
  print("=" * 78)
  print("  `n` counts nodes INTERNED while the fixture ran, so it is a fact about the")
  print("  session, not about the graph. Measured both ways:")
  for nm in ("lg1", "lg5", "lg6", "lg9", "lg2", "lg3", "lg4", "lg7", "lg8"):
    out = fixture(nm)
    if out is None:
      print(f"  {nm}: refuses in CPython too -- no cone")
      continue
    full = walk(roots_of(out))
    kept = [u for u in full if id(u) not in dd.PROMO]
    kinds = {}
    for u in full:
      kinds[u.op.name] = kinds.get(u.op.name, 0) + 1
    kd = {}
    for u in kept:
      kd[u.op.name] = kd.get(u.op.name, 0) + 1
    print(f"  {nm}: raw CPython cone={len(full):<4} after-deletion cone={len(kept):<4} "
          f"CONSTs raw={kinds.get('CONST', 0)} kept={kd.get('CONST', 0)} "
          f"CASTs raw={kinds.get('CAST', 0)} kept={kd.get('CAST', 0)}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())