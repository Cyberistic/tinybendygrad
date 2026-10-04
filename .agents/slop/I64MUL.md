# I64MUL — `i64_mul` derived, gated, and landed

**Landed.** `tinybendygrad/helpers.bend` **2605 → 2712 lines** (+107), **116479 →
121924 bytes**, `ALL PROOFS CHECK`, md5 `903224131723a0f774471fe89ad29042`.
Nothing committed. Also landed in the same block: `u64_mul`, `u64_mul32`,
`pp_core`, `u64_mul_parts`, `cdiv_i64`, `cmod_i64`.

Reproduce (all in `.agents/slop/i64mul/`):

```sh
python3 gen_gate.py && ./bin/bend gate.bend | grep -E '^[ms]_' > got.txt   # 442/442
bash mutate.sh                                                            # 8 disarms + 3 plants
python3 census.py                                                         # hi==lo census, unmoved rows
bash cgate.sh                                                             # cmod, 852 rows, batched
python3 gen_cmod.py
```

---

## 1. The derivation, every intermediate

`I64` is `I64{hi: U32, lo: U32}` (`helpers.bend:1639`), so a 64-bit word is two
`U32`s. **`U32.mul` WRAPS mod 2^32** — measured: `U32.mul(4294967295,
4294967295) = 1`. So a 32×32 product cannot be taken in one `U32`; carries must be
accumulated by hand.

**The split is 16-bit limbs, and that is the whole trick.** `65535 × 65535 =
4294836225 = 0xFFFE0001 < 2^32`, so all four partial products are exact in a
`U32` and the wrap is never reached. The exactness is a property of the
**operands**, not of `U32.mul`.

For `a = ah·2^16 + al`, `b = bh·2^16 + bl`:

```
p00 = al·bl   p01 = al·bh   p10 = ah·bl   p11 = ah·bh        each <= 0xFFFE0001
cross = (p10 + p01) mod 2^32                                 needs 33 bits
carry = (cross >> 16) + (carry_out << 16)                    EXACT, <= 131068
t     = (p00 + ((cross & 0xFFFF) << 16)) mod 2^32            carry out = (t < p00)
hi    = p11 + carry + carry_out(t)                           <= 0xFFFFFFFE, NEVER WRAPS
```

`a·b = p11·2^32 + cross·2^16 + p00`, and `hi:lo` is the answer.

**The carry is re-entered at bit 16, not bit 0.** `cross` holds the low 32 bits, so
the true sum is `cross + c·2^32`; it arrives in `carry`'s word multiplied by
`2^16`, so `c` contributes `2^48` — bit 16 of that word. Measured: adding it at
bit 0 answers `0xFFFF0000-1` for `0xFFFFFFFF·0xFFFFFFFF` where the truth is
`0xFFFFFFFE`, **with a correct low word**. Rows `m_f_carry_ffff_ffff`,
`m_f_max_max`, `m_f_max_neg1`.

**Word level.** `a·b mod 2^64 = al·bl + (al·bh + ah·bl)·2^32`; the `ah·bh` term is
`2^64` wide and vanishes. Only `al·bl` needs 64 bits.

- **The cross sum goes in the HIGH word.** It is `(…)·2^32`. Putting it in the low
  word answers `0xFFFFFFFE_00000003` where the truth is `1` for
  `0x7FFFFFFFFFFFFFFF²` — again a wrong **high** word beside a right low word. Row
  `m_f_max_max`.
- **The high word is never summed separately.** A first version added
  `hi32(m0)+hi32(m1)+hi32(m2)` on top of the adds' own result, which
  double-counts: `i64_add` already carried every high half. Caught by a debug row.

**Signed layer.** Two's complement multiply is the magnitude product negated on a
sign mismatch, exact mod 2^64 because `~x+1` is negation in that same ring.
`i64_abs(int64.min) = int64.min`, whose **pair** is `2^63` — the right unsigned
magnitude — so the most negative value needs no special case.

## 2. What it returns where the product is not representable, and what upstream returns

**Measured by calling `tinygrad/helpers.py`, not by assuming:**

| | `i64_mul` (this port) | upstream `*` |
|---|---|---|
| `0xFFFFFFFF × 0xFFFFFFFF` | `4294967294:1` (= `2^64-2^65+1 mod 2^64`) | `18446744065119617025` — **exact** |
| `2^62 × 4` | `0:0` | `18446744073709551616` (bitlen 65) — **exact** |
| `2^63 × 2^63` | `0:0` | `85070591730234615865843651857942052864` (bitlen 127) — **exact** |

**Upstream's `*` is CPython `int.__mul__`: arbitrary-precision, exact, unbounded.
This port's `i64_mul` is mod 2^64.** They are the same function exactly where the
product fits, and they differ everywhere else. **This is the one place the op can
silently differ from upstream, and it is a difference in the *documented
direction*:** a 64-bit machine multiply. The port's contract is a wrapping 64-bit
multiply, which is what `dtype.js` gets from BigInt-free arithmetic and what a C
`int64_t` gives.

**But inside `cmod` the wrap never fires**, and this is a proof, not a sample.
`cdiv` divides *magnitudes* and applies the sign afterwards, so
`|cdiv(x,y)·y| = floor(|x|/|y|)·|y| ≤ |x|`. The only i64 whose magnitude is `2^63`
is `int64.min`, and for it the product is `int64.min` itself — representable.
Verified by calling CPython on all six extreme divisors: every `cdiv(x,y)*y` is
exactly representable. **So `i64_mul` is exact wherever `cdiv` is.**

## 3. Rows passed against rows expected

Every expectation is **called from CPython**, never typed; every fixture is
emitted as a pair of `U32` literals by the generator.

| gate | rows expected | rows present | disagree |
|---|---|---|---|
| `i64_mul` / `u64_mul` | **442** | **442** | **0** |
| `cdiv_i64` + `cmod_i64` | 852 | 852 | 54 (see below) |

221 fixtures × 2 rows. Coverage: `int64.min`, `int64.max`, both signs of both
extremes, `0`, `1`, `-1`, the `2^k ± 1` ladder for k ∈ {0,1,2,8,15,16,17,31,32,33,
62,63}, 15 carry-out-of-bit-63 products, and 80 random pairs (seeded, so
reproducible).

**The 54 cmod disagreements are a PRE-EXISTING `i64_div` defect, not this block.**
All 54 have `int64.min` as an operand; **rows with no `int64.min`: 782/782 agree,
0 failures.** The defect: `i64_div`'s 65th bit is lost whenever a magnitude
reaches `2^63` — `i64_div(1, 2^63)` answers `-1` where CPython says `0`, while
`2^63 // 2^63 = 1` and `2^63 // 3` are both correct. Measured on a 36-cell grid:
26 disagreements, every one with bit 63 set. **Reported, not fixed** — it is not
`i64_mul`, and `helpers.bend`'s own `i64_dec` depends on `i64_divmod`.

## 4. Does the floor-pair derivation survive?

**It becomes unnecessary, not merely redundant** — and the reason is specific.

`cmod` upstream's way is `x - cdiv(x,y)*y`, which now compiles. The
multiply-free floor-pair derivation existed **only** because Bend had no multiply;
it answered the same numbers by a longer route. With `i64_mul` it is a second
spelling of one function, which is a cost.

**One caveat, and it is the honest one:** the multiply only removes the need for
a *second spelling*, not for a *second defect surface*. `i64_mul` now makes
`x*y<0` — upstream's own spelling of `cdiv`'s sign test — silently wrong where it
overflows (`2^62 × 4` wraps to `0`, and `0 < 0` is `False`). So `cdiv_i64` **must**
keep reading the sign as the XOR of the two sign bits, exactly as `cdiv_i32`
already does at `helpers.bend:1489` for the same reason. That constraint is now
load-bearing in a new place and is commented as such.

**Also worth noting:** `runtime/dtype.js:197` already writes `cmod` upstream's way,
`a - cdiv(a,b)*b`, using JS **BigInt** — exact and unbounded. So the JS seam never
had the problem; only the pure-Bend path did.

## 5. Plant and disarm (disarm first)

**Disarms — all 8 move rows, so the gate is armed.** Rows moved:

| disarm | rows moved | what it removes |
|---|---|---|
| `drop_carry` | 66 | the carry out of `cross` entirely |
| `carry_at_bit0` | 66 | the carry, at the wrong bit position |
| `cross_in_low_word` | 538 | the cross term's placement |
| `no_carry_out_of_t` | 134 | the carry out of the low-word add |
| `limbs_swapped` | 642 | the 16-bit limb split |
| `no_sign_flip` | 158 | the two's complement sign |
| `i64_mul_is_zero` | 396 | all of `i64_mul` |
| `u64_mul_is_zero` | 792 | all of `u64_mul` |

**Plants.** `plant_high_plus_one` → 442/442 rows changed. `plant_cross_plus_one` →
442/442 rows changed.

**One plant moved 0 rows, and it is a THEOREM, not a blind spot.**
`plant_unsigned_in_signed` (`i64_mul` → `u64_mul`) moves nothing. That is
`i64_mul ≡ u64_mul` **identically**: `(a·b) mod 2^64` is one ring whether the pair
is read signed or unsigned, and two's complement representation *is* residue mod
`2^64`. Verified: **0 disagreements over 500 000 random i64 pairs**, and on the
extreme `i64_abs` cannot handle (`min · 1` → `0` both ways). Two spellings of one
function, so no fixture can separate them — the `ops_amd` case, reported rather
than papered over with a row.

**A harness defect found the hard way, and it is the most important line here.**
My first mutation harness re-copied `helpers.bend` into its backup slot *inside*
the loop, so it backed up a **mutated** file, and the final restore left a stray
`, 1)` in `pp_core`'s high word. That survived a **442/442 green gate** for one
run and then reported 884/884 disagreeing for the next. `mutate.sh` now takes one
pristine copy up front and **verifies the md5 after restoring**, failing loudly
otherwise. A restore that is not verified is not a restore.

## 6. The `hi == lo` fixture census

The libclang sentinels are `0`, `-1`, `int64.min`; `0 → 0:0` and `-1 →
4294967295:4294967295` both have **`hi == lo`**, so a half-swap is invisible on
fixtures built only from them. `int64.min → 2147483648:0` does **not**.

Measured over the 221 fixtures: **only 4 have both operands `hi == lo`**
(`f_zero_zero`, `f_neg1_neg1`, `f_pow0_m`, `f_pow32_p`); **217 have `hi != lo`
somewhere**. So `cross_in_low_word` — the half-swap — is caught by 538 rows, not
by the sentinels. The rows whose *both* operands have `hi == lo` are printed in
`census.py`'s output; a fixture set made only of those four would answer the same
under that mutation.

## 7. Rules worth keeping (for `.agents/slop/notes/bend2-constraints.md`)

1. **A mutation harness must take its pristine copy ONCE, before any mutation,
   and verify the md5 after restoring.** Re-copying inside the loop backs up a
   mutation, and a restored mutation can pass a green gate.
2. **`U32.mul` WRAPS mod 2^32** (`0xFFFFFFFF × 0xFFFFFFFF = 1`). Exactness of a
   `U32` product is a property of the operands, never of `U32.mul`. **16-bit limbs
   make all four partial products exact; 32-bit limbs do not.**
3. **A record constructor's field count must match the type exactly**, and a stray
   trailing argument (`, 1)`) is invisible until a fixture reads that field.
4. **`i64_abs(int64.min) = int64.min`, and the divider is then handed a magnitude
   with bit 63 set.** `i64_div` is wrong whenever either operand's magnitude
   reaches `2^63` (26 of 36 grid cells disagree) — pre-existing, unfixed.
5. **Do not retype a committed def into a scratch copy.** I transcribed
   `i32_is_neg` as `U32.is_lt(x, 2147483648)` where `helpers.bend:1465` has
   `U32.is_ge` — an inverted sign test that `i64_mul`'s gate was **blind to**
   (its 442 rows agreed either way) and that `cdiv` caught immediately.
6. **`String` is linear**: a row name cannot feed two `IO.print`s. Two defs, each
   consuming the name once.
7. **A single generated program overflows the machine stack**: 852 rows of 64-step
   restoring division dies with `the machine stack overflowed`. Emit one `main`
   per batch and run each as its own process.
8. **A generated header needs a trailing newline** before the generator's first
   appended `def`, or the import line swallows it (`... as Hdef mrow(...)`).

## 8. A false claim I made and the data refuted

Worth recording because the refutation is the lesson. Mid-derivation I concluded
"the multiply never wraps inside `cmod`" from a table of extreme divisors and
printed it as a fact — and the same table's `x=int64.min, y=2^63` row showed
`product=9223372036854775808, representable=False`, which contradicts it. The
error was mine: `cdiv` **negates** the magnitude quotient, so the product is
`-2^63 = int64.min`, which *is* representable. The conclusion survived; the
reasoning did not. **A printed conclusion that disagrees with a row of its own
table is a suspect result**, the same rule that caught the `2^48` ladder in W64.