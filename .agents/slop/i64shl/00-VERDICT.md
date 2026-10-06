# `i64_shl` with a RUNTIME shift amount — verdict

unit: one job. establish OPEN / STALE / RETIRED for the `i64_shl` runtime-amount wall.

**STATUS: DONE. VERDICT: STALE — and the wall that survives is `i64_shr`, a different
def. FULL REPORT, ROWS, PLANTS AND THE `magicgu` REACHABILITY MEASUREMENT:
[`REPORT.md`](REPORT.md). Measured 2026-10-05.**

The three-line version:

1. `tinybendygrad/helpers.bend:1819` — `def i64_shl(+x: I64, +k: Nat) -> I64:` — exists,
   is pure (`import "` × 0), and **already takes a `Nat`**. So the premise handed to me
   ("a runtime shift amount cannot be a `Nat`") is **false in the tree today**, and
   `uop/fold.bend:3234` proves it: `bnd.pw2` feeds it `U32.to_nat(U32.sub(bits, 1))` with
   `bits` a runtime `U32` parameter. **Do not reuse that premise.**
2. **151 rows, 3 lanes byte-identical** (`I64SHL_SEED=7 .venv/bin/python
   gates/i64-shl-gate.py`, md5 `2defe56c…` on py/bd/bn, `gate.bin` a Mach-O arm64
   binary). Every amount is reached both at a literal index and at an
   environment-derived index, and the two agree at all 30 (value, amount) pairs. Three
   plants moved **46 / 17 / 3** rows by name and all three disarmed byte-identically.
3. The wall's *reason* is settled against itself **at int32** (`magicgu`'s `s` peaks at
   **62**, so `2**s` is 63 bits and a signed 64-bit pair holds it — the wall is off by
   two) and confirmed **at uint32** (`s` peaks at exactly **64**, so there the 65-bit
   carrier really is needed). Open, not closed.