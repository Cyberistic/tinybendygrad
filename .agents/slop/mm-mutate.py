#!/usr/bin/env python
# mm-mutate.py -- the MUTATION TABLE for the `_min_max` arithmetic core.
#
# ONE ENTRY PER PORTED RULE, and the harness DIFFS WHOLE `name=value` LINES, not row
# names (agent-core.md: a name-comparing harness reported 0 for all 68 rows in one
# unit and 0 for all 30 in another). Rows are moved BY NAME, so the report can say
# which rule each mutation is testing.
#
# A `0` is reported with its reason and never closed with a row that encodes the bug:
#   * a REQUEST FOR A FIXTURE -- the mutation is right and the fixtures do not reach it
#   * a THEOREM               -- two spellings are the same function, so no fixture separates them
#   * GENUINELY UNFIXABLE      -- the predicate cannot fail over any possible answer
import re
import subprocess
import sys

SRC = "tinybendygrad/uop/probe-mmcore.bend"
BEND = "./bin/bend"
ORACLE = [".venv/bin/python", ".agents/slop/mm-gate.py"]

# (label, find, replace)
MUTATIONS = [
  # --- ADD: the overflow test is `result < a`, not `result <= a` and not `a < b`
  ("M1  u64.add: drop the carry into the high word",
   "U32.add(U32.add(ah, bh), u32c(al, bl))", "U32.add(ah, bh)"),
  ("M2  u64.add: overflow test `result < a` -> `result <= a`",
   "u64.of(Bool.not(u64.lt(hi, lo, ah, al)), hi, lo)\n\n# WRAPPING",
   "u64.of(Bool.not(u64.le(hi, lo, ah, al)), hi, lo)\n\n# WRAPPING"),
  # --- SUB: the underflow test is `a < b`, NOT `result < a`
  ("M3  u64.sub: underflow test `a < b` -> `result < a`",
   "u64.of(Bool.not(u64.lt(ah, al, bh, bl)), hi, lo)",
   "u64.of(Bool.not(u64.lt(hi, lo, ah, al)), hi, lo)"),
  ("M4  u64.sub: the borrow never reaches the high word",
   "def u64.sub(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<&2, H.I64>:\n  +lo = U32.sub(al, bl)\n  +hi = U32.sub(ah, U32.add(bh, u32c(bl, U32.sub(al, bl))))",
   "def u64.sub(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<&2, H.I64>:\n  +lo = U32.sub(al, bl)\n  +hi = U32.sub(ah, bh)"),
  # --- MUL: the overflow test is `u != 0 or t3.hi != 0`
  ("M5  u64.join: `is_zero` with `or` instead of `and`",
   "def u64.is_zero(+hi: U32, lo: U32) -> Bool:\n  Bool.and(U32.is_zero(lo), U32.is_zero(hi))",
   "def u64.is_zero(+hi: U32, lo: U32) -> Bool:\n  Bool.or(U32.is_zero(lo), U32.is_zero(hi))"),
  ("M6  u64.join: overflow test drops `t3.hi`",
   "Bool.and(u64.is_zero(H.hi32(t3), 0), u64.is_zero(u, 0))",
   "u64.is_zero(u, 0)"),
  ("M7  u64.join: the high word built by `u << 32` instead of by the limbs",
   "U32.or(U32.and(s, 4294967295), U32.shln(U32.and(u, 4294967295), 32n)),\n    H.lo32(t0)",
   "U32.shln(U32.and(u, 4294967295), 32n),\n    H.lo32(t0)"),
  ("M8  u32m.wide: the low word's limbs exchanged",
   "U32.or(u32lo16(p0), U32.shln(u32lo16(n1), 16n))",
   "U32.or(u32lo16(n1), U32.shln(u32lo16(p0), 16n))"),
  ("M9  u32m.wide: limb 3 contributes its LOW word instead of its HIGH word",
   "+n3 = U32.add(u32x16(p3), u32x16(n2))", "+n3 = U32.add(u32lo16(p3), u32x16(n2))"),
  # --- SHL: the overflow test, and the high word for k >= 32
  ("M10 u64.shl: the fit test with `or` instead of `and`",
   "def u64.shl.okhi(+ah: U32, al: U32, +k: Nat) -> Bool:\n  Bool.and(U32.is_zero(ah), U32.is_zero(U32.shrn(al, u64.shl.lost(k))))",
   "def u64.shl.okhi(+ah: U32, al: U32, +k: Nat) -> Bool:\n  Bool.or(U32.is_zero(ah), U32.is_zero(U32.shrn(al, u64.shl.lost(k))))"),
  ("M11 u64.shl: the high word for k >= 32 reads `ah` instead of `al`",
   "H.i64_of_hi_lo(U32.shln(al, Nat.sub(k, 32n)), 0)",
   "H.i64_of_hi_lo(U32.shln(ah, Nat.sub(k, 32n)), 0)"),
  ("M12 u64.shl: k = 0 counts as an overflow",
   "Bool.pick(Bool, U32.is_zero(U32.from_nat(k)), True{},\n    U32.is_zero(U32.shrn(ah, u64.shl.lost(k))))",
   "Bool.pick(Bool, U32.is_zero(U32.from_nat(k)), False{},\n    U32.is_zero(U32.shrn(ah, u64.shl.lost(k))))"),
  ("M13 u64.shl: the low/high word choice is `k >= 32` instead of `k < 32`",
   "def u64.shl.lo_half(+k: Nat) -> Bool:\n  U32.is_lt(U32.from_nat(k), 32)",
   "def u64.shl.lo_half(+k: Nat) -> Bool:\n  U32.is_ge(U32.from_nat(k), 32)"),
  # --- SHR: the bit that enters the bottom
  ("M14 u64.shr: the bit that enters the low word comes from `al` not `ah`",
   "U32.or(U32.shrn(al, 1n), U32.shln(U32.and(ah, 1), 31n))",
   "U32.or(U32.shrn(al, 1n), U32.shln(U32.and(al, 1), 31n))"),
  # --- DIVMOD: the four that decided the whole quotient
  ("M15 dm.fit: subtract when the remainder is merely BELOW the divisor (`le`)",
   "Bool.or(St.up(s), Bool.not(u64.lt(St.rh(s), St.rl(s), dh, dl)))",
   "Bool.or(St.up(s), u64.le(St.rh(s), St.rl(s), dh, dl))"),
  ("M16 dm.bit: the low word's shift is `63 - k` instead of `k`",
   "def dm.bit.lo(+bh: U32, +bl: U32, +k: Nat) -> U32:\n  U32.and(U32.shrn(bl, k), 1)",
   "def dm.bit.lo(+bh: U32, +bl: U32, +k: Nat) -> U32:\n  U32.and(U32.shrn(bl, Nat.sub(63n, k)), 1)"),
  ("M17 dm.bit: the word choice picks the low arm when the flag says high",
   "Bool.pick(U32, low, dm.bit.lo(bh, bl, k), dm.bit.hi(bh, bl, k))",
   "Bool.pick(U32, low, dm.bit.hi(bh, bl, k), dm.bit.lo(bh, bl, k))"),
  ("M18 dm.step: the quotient bit is set on every step",
   "dm.qbit.at(dm.low_half(k), k, St.qb(f), f)", "dm.qbit.at(dm.low_half(k), k, True{}, f)"),
  ("M19 dm.low_half: `k < 32` -> `k != 32`",
   "def dm.low_half(k: Nat) -> Bool:\n  U32.is_lt(U32.from_nat(k), 32)",
   "def dm.low_half(k: Nat) -> Bool:\n  U32.is_ne(U32.from_nat(k), 32)"),
  ("M20 dm.shift: the 65th bit is dropped instead of carried",
   "U32.is_eq(U32.shrn(St.rh(s), 31n), 1), False{}}", "False{}, False{}}"),
  ("M21 dm.step: 63 steps instead of 64",
   "dm.loop(64n, nh, nl, dh, dl,", "dm.loop(63n, nh, nl, dh, dl,"),
]


def rows(text):
  out = {}
  for line in text.splitlines():
    m = re.match(r"^(mm_\S+) (.*)$", line)
    if m:
      out[m.group(1)] = m.group(2)
  return out


def bend_run(path):
  r = subprocess.run([BEND, path], capture_output=True, text=True)
  return r.stdout + r.stderr


def main():
  src = open(SRC).read()
  base = rows(bend_run(SRC))
  py = rows(subprocess.run(ORACLE, capture_output=True, text=True).stdout)
  print(f"baseline: {len(base)} bend rows, {len(py)} cpython rows, "
        f"{'IDENTICAL' if base == py else 'DIVERGENT'}")
  if base != py:
    for k in sorted(set(base) | set(py)):
      if base.get(k) != py.get(k):
        print(f"  BASE DIVERGES {k}: bend={base.get(k)} py={py.get(k)}")
    sys.exit(1)
  print()
  print("| mutation | rows that MOVED | verdict |")
  print("| --- | --- | --- |")
  zeros = 0
  for label, find, repl in MUTATIONS:
    if src.count(find) != 1:
      print(f"| {label} | -- | ANCHOR NOT UNIQUE ({src.count(find)} matches): not run |")
      zeros += 1
      continue
    open(SRC + ".mut", "w").write(src.replace(find, repl))
    got = rows(bend_run(SRC + ".mut"))
    moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
    verdict = f"{len(moved)} moved" if moved else "ZERO -- blind spot, see the report"
    if not moved:
      zeros += 1
    print(f"| {label} | {' '.join(m.split('_', 1)[1] for m in moved) or '(none)'} | {verdict} |")
  print(f"\n{zeros} of {len(MUTATIONS)} mutations moved nothing.")


if __name__ == "__main__":
  main()