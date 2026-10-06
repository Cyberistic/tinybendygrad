# `i64_shl` with a RUNTIME shift amount — VERDICT: **STALE, and its surviving half is a DIFFERENT WALL**

unit: one job. measured 2026-10-05. Bend 2.0.34. **no commit.**

---

## 1. VERDICT

**STALE.** The wall's premise is false, its named def exists and is pure, and its
consequence is settled *against itself* by its own bound — **but the shift wall that
survives is `i64_shr`, which is genuinely absent.** So: my job's wall is closed, and the
wall it was half of is still open on the other half.

| the wall's claim | measured 2026-10-05 | |
|---|---|---|
| "`i64_shl` takes a `Nat`, which a runtime shift amount cannot be" | `helpers.bend:1819` is `+k: Nat` and `fold.bend:3234` feeds it `U32.to_nat(U32.sub(bits, 1))` with `bits` a runtime `U32` parameter | **DEAD** (premise disproven) |
| `i64_shl` with a runtime amount is unavailable | **151 rows, 3 lanes byte-identical**, every amount reached both at a literal index and at an environment-derived index | **DEAD** |
| `magicgu` needs `2**s` for `s` up to `2*nbits = 64`, so 65 bits | **attained exactly:** `s = 62` at int32, `s = 64` at uint32 | **HALF DEAD** — see §4 |

## 2. ANCHOR / REOPEN / DATE — all three, and they are cheap

- **ANCHOR (a grep settles it).** `grep -n '^def i64_shl(' tinybendygrad/helpers.bend` →
  `1819:def i64_shl(+x: I64, +k: Nat) -> I64:`
  **Quoted, as asked:** `def i64_shl(+x: I64, +k: Nat) -> I64:` at
  `tinybendygrad/helpers.bend:1819` (body `:1820`). `helpers.bend` carries `import "` **0**
  times, so it is pure; `:1810`/`:1813`/`:1816` are its `.lo`/`.hi`/`.put` arms.
- **ANCHOR (the command that re-runs it).**
  `I64SHL_SEED=7 .venv/bin/python gates/i64-shl-gate.py` → rc 0, 151 rows.
- **REOPEN.** `i64-shl-gate` going red, **or** `helpers.bend:1819` ceasing to read
  `+k: Nat`. For the surviving `i64_shr` wall the reopen is `grep -c '^def i64_shr'
  tinybendygrad/helpers.bend` reaching 1 **and** rows over its boundary — see §5.
- **DATE.** 2026-10-05, of the measurement. Nothing here is dated by a read.

## 3. ROWS — and the UNIVERSE, which is the part that could have made them vacuous

**The universe question came first, and it changed the fixture set.** `i64_shl`'s only
real failure mode is which word supplies the high half for `k >= 32`
(`helpers.bend:1801-1804`). **A value with both words below 2^32 cannot see that**, so a
naive fixture set would have been a gate that cannot fail — the `bf16` failure in the
brief, reproduced in miniature. The three fixtures are each there to see something:

| fixture | pair | why it is in the set |
|---|---|---|
| `neg1` | `4294967295:4294967295` | the only value whose `k=63` answer is still nonzero, so **the row that separates 63 from 64** |
| `one` | `0:1` | `helpers.bend:1803-1804` names `1 << 63` verbatim as the high-arm case |
| `lowhi` | `1:2596069104` | **both words nonzero and different**; 33 bits, so its own signed-range edge is `k=31` |

**Amounts** (`nats()` at `shl.bend:55`): `0, 1, 31, 32, 33, 62, 63, 64, 65, 127` — every
boundary, not a sample. `0` and `32` are the two amounts where the low form and the high
form **meet** (`helpers.bend:1797-1799`); `31` is `U32.shln`'s saturation edge; `63` is
the widest a signed pair expresses; **`64` is the wall's**; `127` separates "wraps to 0"
from "clamped to a bit width", which `64`/`65` alone cannot.

**What the implementation does at each boundary** (from the gate's own rows):

| `k` | pair reads signed | CPython / upstream | |
|---|---|---|---|
| `0` | `x` | `x` | identity; both pick arms agree |
| `31` | `x << 31` | `x << 31` | for `neg1`/`one`; `lowhi` has left signed range |
| `32` | `x << 32` | `x << 32` | the `k <= 32` edge |
| `63` | `x << 63` | `x << 63` **when `x < 0`** | `neg1 << 63 = 2147483648:0`, the int64 sign bit |
| `63` | **negative** | **positive** for `x > 0` | `one << 63`: CPython `9223372036854775808`, pair `-9223372036854775808` |
| `64`, `65`, `127` | `0:0` | `x << k` ≠ 0 | `2**64` does not fit a 64-bit pair |

**THE BOUNDARY IS NOT A CONSTANT AMOUNT, AND THAT IS THE FINDING.** `i64_shl` returns a
**SIGNED** pair, so its range is `[-2^63, 2^63-1]` and the predicate is

> `i64_shl` answers `x << k` **exactly iff `x << k` fits a signed 64-bit word**, i.e. iff
> `k + bit_length(x) <= 63`.

There is **no amount at which the carrier is 64 bits unsigned** — the first loss is at
`63` for any positive `x`, one row *before* the wall's `64`, and it is invisible to a
fixture set that only tests `k = 64`. The gate asserts both directions (`neg1@63` fits,
`one@63` does not), so `63` is a boundary and not a cliff.

## 4. `magicgu` — the wall's own reason, settled against itself at int32

The wall asks for `i64_shl` because `tinygrad/codegen/decomp/op.py:15` materialises
`2**s` over `for s in range(0, 2*nbits + 1)` (`op.py:14`). **That quotes the loop's
RANGE, not what the loop RETURNS.** Exact bound, derived in the probe:
`s > log2(nc*(d-1))`, `nc <= vmax`, `d <= vmax` (`op.py:22` returns early below `d`), so

    s <= bit_length(vmax * (vmax-1)) <= 2*nbits

| dtype | bound on `s` | bits in `2**s` | a signed 64-bit pair holds it? | measured max |
|---|---|---|---|---|
| int8 / uint8 | 14 / 16 | 15 / 17 | yes | 14 / 16 |
| int16 / uint16 | 30 / 32 | 31 / 33 | yes | 30 / 32 |
| **int32** | **62** | **63** | **YES — one bit spare** | **62, attained** |
| **uint32** | **64** | **65** | **NO** | **64, attained** |
| int64 / uint64 | 126 / 128 | 127 / 129 | no | 126 / 128 |

**So: at int32 — the dtype the wall names — NO 65-bit carrier is needed, and the wall is
off by two.** At **uint32 the bound is attained, `s = 64` really happens, and the wall is
right.** The measured maxima are corroborated by the analytic bound agreeing, not by the
sweep: the sweep is exhaustive over `d < 2**20` plus a power-of-two ladder to the domain
edge and every measured maximum is a **lower bound** — `s` was still climbing at the
sweep edge in an earlier `2**22` run, which is why the conclusion rests on the bound.
`.agents/slop/i64shl/magicgu.txt`.

## 5. THE WALL THAT SURVIVES IS `i64_shr`, NOT `i64_shl`

`mixin/dtype.bend:57` lists the two shifts **as one row**: `SHL/SHR → i64 shift →
NOWHERE`. Measured: `i64_shl` exists (`helpers.bend:1819`); **`def i64_shr` exists
nowhere** in the tree — only `U32.shr`/`U32.shrn` (`base.bend:1394`/`:1406`) and a local
`dtype.bend:983 fp8_enc.shr`. So that row is **half dead and the surviving half is a
different wall**: a genuinely absent def, not a `Nat`-vs-runtime question. It wants a
right shift of a 64-bit **pair**, where `lo` supplies the high word for `k < 32` — the
mirror of `helpers.bend:1801-1804`.

**Still carrying the dead half, uncorrected — NOT MINE, REPORTED NOT TOUCHED:**
`mixin/dtype.bend:52-53` (`i64_mul` "NOWHERE" — it is `helpers.bend:2206`), `:57`
(`SHL` "NOWHERE"), `:60` ("`i64_mul` and a shift are missing outright"), `:54-57`/`:58-59`
(the `IO(..)` seams, dead since `tinybendygrad/dtype.bend` carries `IO(` 0 times).
`uop/fold.bend:2671-2701` and `uop/weak.bend:16` have already been corrected.
`helpers.bend:1737-1741` repeats the seam claim and is off limits to me.

**And on the brief's side-finding about a checked op: I could not confirm it applies
here, and I think it does not.** `mm.u64.mul`'s `None` is an overflow signal because
`m*vmax` can exceed `2^64`; a **shift cannot overflow** — it discards high bits, and
two's complement `<<` discarding them is the defined answer, not a lost one. The gate
proves the pair still *holds* the low 64 bits whenever the signed reading loses it
(`unpair_u(got) == exact & M64`), which is the difference between "re-signed" and "lost".
**So for `i64_shl` the right answer is a WIDER carrier, not a `Maybe`-returning one.**
The checked-op argument stands for `i64_mul` and I am not contradicting it there.

## 6. PLANT AND DISARM — whole `name=value` line diffs, three plants, all disarmed

Instrument: `diff` of full lines against a pre-plant baseline (`base.bd.txt`), **not**
row names — the recorded failure is a name-comparing harness reporting 0.

| plant | change | rows moved, BY NAME | gate |
|---|---|---|---|
| **P1** | runtime index `mod 10` → `mod 9` | **46**, all `_rt_amt`/`_rt`, slots 2–9; `_x`/`_amt`/`_lc` untouched | FAIL |
| **P2** | runtime amount clamped `& 63` | **17** — 9 `_rt_amt` + 8 `_rt`; exactly amounts 64/65/127 × 3 values | FAIL |
| **P3** | runtime table's `127n` → `126n` | **3**, all `_rt_amt`. `sh_lowhi_2_rt` did **not** move: 126 and 127 both answer `0:0` for `lowhi` | FAIL + `main` claim fired |

**P3 is why `_amt` is a row.** With the amount printed, a plant that changes only the
input still moves 3 rows; without it this plant would have moved **zero** and looked like
a blind spot.

**P2 is the one that matters for the wall.** The classic "shift amount is masked to the
word width" bug is caught by 17 rows, **and only because the runtime route is a separate
column** — the plant was on the runtime route alone and the 17 literal rows did not move.

**The gate's own claim fired on P3**, naming the pairs: `the runtime route never reached
('lowhi', '127')`, `('neg1', '127')`, `('one', '127')`.

**ALL THREE DISARMED**, and `diff base.bd.txt bd.txt` is **byte-identical** to the
pre-plant baseline — the same instrument that armed them.

**OUT-OF-MECHANISM ASSERTIONS, because a row that cannot fail is not a row.** The gate
refuses to answer from a file that is not exactly 151 rows (a failed run leaves the
**previous** run's `bd.txt` in place — I hit this and it briefly showed me P1's rows under
P3's heading); it asserts every expected row NAME present, not just the count; it asserts
every compared value **non-empty** before comparing, since `"" == ""` is the recorded
failure; and it asserts the `seed` **value** on all three lanes, not merely its presence,
so a lane that silently fell back to the default fails.

**LANES.** `py` = CPython, `bd` = `bend` interpreting the driver, `bn` = the **native**
compile (`gate.bin`, a Mach-O arm64 executable, confirmed with `file`). All three md5
`2defe56c…`, 151 rows. `bn` equalling `bd` is the anti-constant-folding check on the
runtime amount.

## 7. WHAT I COULD NOT SETTLE

- **I did not plant in `helpers.bend`, so the rows have never been shown to move from a
  mutation of the def under test.** Off limits (root of a 33-file closure, truncated to
  0 bytes four times today; verified **125,668 bytes, `import "` × 0, untouched**).
  The three plants are all in the driver, so they prove the *harness* sees wrong answers
  — not that `i64_shl` is covered against its own mutation. That gap is real and named.
- **`uint32`'s 65-bit carrier is still OPEN**, and I did not resolve it: the bound is
  attained at `d = 4294967294`, so the requirement is real, and nothing here implements a
  65-bit carrier.
- **The `d` domain above `2**20` is unswept.** The analytic bound covers it and agrees at
  the sampled edge, but no exhaustive measurement does.
- **Whether the runtime amount is genuinely unfolded** is settled only by `bd == bn`
  agreeing, not by inspection. The amount is read from a table at an index computed from
  `H.getenv_int` → `IO.get_env`, so it is not in the driver's text, and it is printed as
  a row so it cannot drift silently.
- **I did not correct `mixin/dtype.bend` or `.agents/TODO.md:11697-11701`** (LL-12 still
  says "`i64_shl` … takes a `Nat`, which a runtime shift amount cannot be"). Both are
  shared with live units and six are running; §5 is the correction, for whoever owns those
  files. **`TODO(fold-bitcast-u32)` in `uop/fold.bend` was not mine and is untouched.**

## 8. TWO TOOLING FINDINGS, REPORTED NOT FIXED

1. **`gates/gatekit.py`'s stack-flake guard misreports a real compile error.** A plant
   with a genuine type error (`amt_clamp` calling a def defined below it) was reported as
   `bend produced no --check-only output in 25 tries (the stack flake)` — 9 s of retries
   on a deterministic failure, and the wrong cause. The guard is
   `if not stdout.strip() and rc != 0: continue` (`gatekit.py:130`), which cannot tell
   "bend crashed" from "bend died before printing".
2. **A failed gate run leaves the previous run's `bd.txt` in `gates/artifacts/i64-shl/`.**
   `gatekit.run()` returns before writing, so a diff of that path after a red run is a
   diff of the *last green* run. Mine now refuses to answer from a file that is not
   exactly `ROWS` rows; **`gatekit` itself has no such guard**, and `gates/README.md`'s
   "artifacts are regenerated by every run" is not true of a failed one.

## 9. FILES

| path | |
|---|---|
| `gates/i64-shl-gate.py` | **mine.** 151 rows, 3 lanes, holds only this gate's rows and claims |
| `.agents/slop/i64shl/shl.bend` | driver. imports `helpers.bend` as `H`; defines no `I64` arithmetic of its own |
| `.agents/slop/i64shl/shl-oracle.py` | CPython oracle; expectations from `(x << k) & 2**64`, decomposed — not the port's word-wise route |
| `.agents/slop/i64shl/magicgu-probe.py` · `.txt` | the `s`-reachability probe and its output |
| `.agents/slop/i64shl/base.bd.txt` | pre-plant baseline, 151 rows |
| `gates/artifacts/i64-shl/` | `py/bd/bn.txt`, `.sub`, `gate.bin` |

Peak RSS, all bounded, **one `bend` at a time**, none in the background: `--check-only`
209 MB; gate runs 380–411 MB; magicgu probe (CPython only) 4.6 min at the `2**22` sweep
and 58 s as it now stands. **No run was killed and none timed out.** No other `bend`
process was started.