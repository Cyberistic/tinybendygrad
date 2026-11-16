# transcendental_f32.bend -- the COEFFICIENT AND VALUE half of
# tinygrad/codegen/decomp/transcendental.py (277 lines).
#
# ============================ READ THIS FIRST ==============================
#
# there is a second port of the same python file, at
# `tinybendygrad/codegen/transcendental.bend` (TODO.md, "Session 2026-10-01 round
# 4", 891 string rows, `--check-only` = all proofs check).  the two are
# complementary halves of one upstream file, not two ports of it, and this is the
# statement of which is which -- the one thing a reader must not have to guess:
#
#   transcendental.bend     the GRAPH.  It builds UOp nodes and the gate reads
#                           node counts, root ops and src op sequences.  Its own
#                           header says why: "transcendental.py BUILDS GRAPHS,
#                           it does not EVALUATE them ... every `*`, `//`, `&`,
#                           `<<` here is an `Ops` node".  Rows are `tx_*`.
#   transcendental_f32.bend THIS FILE.  It EVALUATES the decompositions in
#                           IEEE-754 binary32 and gates the ANSWER, so a wrong
#                           coefficient is a RED row instead of an invisible one.
#                           Rows are `xf_*`/`xv_*`/`cd_*`/`cu_*`/`cx_*`/`tx_dt.*`.
#
# THE NAME SAYS WHICH HALF, because a second file called `transcendental.bend`
# claiming the same 277 upstream lines is indistinguishable from a duplicate, and
# `codegen/decomp/` (the upstream path un-flattened) contradicted this repo's own
# mapping, which `codegen/kernel.bend:12` and `codegen/rewriter.bend:17` both
# write as `tinygrad/codegen/decomp/{op,transcendental}.py -> decomp.bend /
# transcendental.bend`.
#
# THEY ARE NOT MERGED, and the reasons are measured rather than aesthetic:
#   * TWO ORACLES.  The graph half is checked against `tx-arena.py` (CPython
#     UOp arenas); this half against `tc-value.py` (`DEV=PYTHON`,
#     `Tensor(tinygrad_fn(uop)).numpy()`) and `tc-audit.py`.  A diff that mixed
#     them would report a `tx_*` UOp-shape disagreement as if it were a value
#     disagreement.
#   * TWO MUTATION HARNESSES with very different costs.  This file's coefficient
#     lane is 0.17 s; its full value lane is 21 min.  The graph half has its own
#     (`tools/tx-mut.py`).  One merged file with one `main` would force every
#     coefficient mutation to pay for the value lane, which is the difference
#     between a table that gets run and one that does not.
#   * TWO INDEPENDENT LANES IS THE POINT.  A graph row cannot see a coefficient,
#     and a coefficient row cannot see a node.  TODO.md round 4 left exactly the
#     gap this half closes: "The float64 coefficient literals are written as full
#     decimals and are NOT independently verified" -- they are now `cd_*` rows
#     carrying CPython's own `repr`, plus `cx_*` rows carrying the 0x spelling.
#

# NO DIGIT IN THE GENERATED HALF IS MINE.  `sp.*` and `fx.*` are produced by
# `.agents/slop/tc-gen.py bend` and `.agents/slop/tc-rows.py {fixtures,pairs}`,
# which read `.agents/slop/tc-audit.txt` -- CPython's own output, 146 constants
# from THREE measured channels (a `polyN` spy, a `shr`/`shl` spy, and source
# `eval`).  `tc-build.py` reassembles head + generated + tail and the three
# parts reproduce this file byte for byte.
#
# the hex cross-check earned its keep, and this is why transcendental
# coefficients need both readings.  Two float64 constants share an f32 rounding
# with a float32 sibling, so EVERY f32 row is blind to the difference between
# them and only the `cd_` decimal row separates them:
#   `xlog2.neg_log2e_f64` = 0x1.71547652b82fep+1 vs `neg_log2e_f32` =
#   0x1.7154760000000p+1 -- both 1077455419 / 0x4038aa3b.
#   `xexp2.coeff64[10]` = 0.6931471805599453 vs `coeff32[5]` = 0.6931471825 --
#   both 1060205080 / 0x3f317218.
# That is the same shape as `bnxtdev`'s hex pass: reading a value as decimal and
# as hex is not two independent readings on a transposed digit PAIR, so a gate
# that only reads one of them is half-blind exactly where it matters.
#

# two defects this file found, both in other people's code, both left loud.
#
# 1. the reverse lookup was answering "not found" for everything, and it was one
#    bug worth 45 rows, not 45.  `tc.vi`/`tc.uvi` search a table for a bit
#    pattern and every `xv_*` row answered 4294967295 while every `xf_*` row for
#    the same table agreed -- which is what made it look like a coefficient bug.
#    a human can read it, and the reverse lookup re-splits THAT string, so every
#    element but the LAST arrived with a leading and a trailing space --
#    MEASURED, `F32.read("0.0001535920892 ")` is `None` -- and only the last
#    element is not followed by a space.  `String.trim` in `tc.f`/`tc.u` removes
#    all 45.  The trim is at the READER because that is the one place a decimal
#    becomes a number.
#
# 2. `F32.read` MISPARSES `3.1415926218032837`, and `xf_pi_a` is RED because of
#    it.  `PI_A` is transcendental.py:125's `3.1415926218032836914`; CPython says
#    the f32 is 1078530010 (0x40490fda) for BOTH spellings, and Bend says
#    1078530011.  This is NOT a deliberate over-approximation and NOT this port's
#    bug: `F32.read` is a `law` in `base.bend:1829 symbol=F32.read` and a primitive of the Bend
#    compiler, not a def, so nothing here can fix it.  REPRO, one line, with a
#    23-of-24 control sweep in which every other string agrees:
#         F32.read("3.1415926218032837")     -> 0x40490fdb   WRONG
#         F32.read("3.14159262180328369")    -> 0x40490fda   right
#         F32.read("3.1415926218032836914")   -> 0x40490fda   right
#         F32.read("3.1415926222801208")     -> 0x40490fdb   right (and 0x40490fda
#                                                is the f32 BELOW pi, so a correct
#                                                parse must round DOWN here)
#    The 17-significant-digit spelling is the one that fails; the 16- and
#    18-digit spellings of the same float are right.  THE ROW STAYS RED ON
#    PURPOSE: the oracle is CPython's answer and an expectation must never be
#    edited to make a row pass.  It turns GREEN by itself the moment the compiler
#    is fixed, which is the shape a real regression row should have.
#

# WHY A VALUE LAYER IS POSSIBLE AT ALL.  Two measurements:
#
#   1. `base.bend`'s F32 arithmetic is BIT-EXACT with CPython/numpy.  Probe:
#      add, sub, mul, div, neg, abs, floor, trunc, is_lt, is_ge on
#      (-3.7, 0.5, 0.0) -- all twelve answers equal
#      `struct.unpack('<I', struct.pack('<f', np.float32(...)))`, and
#      `F32.div(0.0, 0.0)` is the canonical NaN 0x7fc00000.
#   2. `F32.read` (base.bend:1829 symbol=F32.read) parses a DECIMAL STRING into an F32 and
#      agrees with CPython on 145 of the 146 constants audited -- see defect 2
#      for the one.  It accepts "inf", "-inf" and "nan", which is how the
#      specials get CONSTRUCTED (there is no inf literal), and answers `None`
#      for a string with whitespace in it, which is defect 1.
#
# `F32.show` is lossy (seven digits) and appears in no gate; `F32.bits` is the
# gate.
#

# NO float64 EVALUATION, and the float64 coefficients are still verified.  Bend
# has no `F64` (MEASURED: `grep -n F64 references/bend/bend2/base.bend` is
# empty).  A float64 coefficient cannot be a VALUE here, so it is a STRING
# instead: CPython's `repr()` of the float, the shortest decimal that
# round-trips, gated by `cd_*` with `float.hex()` on the record in
# `tc-audit.txt` col 3.
#

# THE TWO WALLS, both named, neither worked around in silence.
#
# W1. NO UINT64 ARITHMETIC, so `payne_hanek_reduction`'s product is NOT
#     evaluated.  The three Python lines that need one, verbatim:
#         :103  def _hp_mul(x, y): return x.cast(dtypes.uint64) * y.cast(dtypes.uint64)
#         :105  p = shl(_hp_mul(ia, hi), 32) + _hp_mul(ia, mi) + shr(_hp_mul(ia, lo), 32)
#         :108  q = shr(p, 62).cast(dtypes.int32)
#     CONSEQUENCE, and it is a real gap in the gate rather than a claim:
#     `xsin(fast=False)` reaches `payne_hanek_reduction` at :182/:187 whenever
#     `x_abs >= switch_over` (30.0), so the VALUE rows stop at 29.999998 and
#     the BOUNDARY IS GATED BY THE CHOICE, `xg_xsin_below_*`, not by the answer.
#     Everything else in the function IS gated: the 190-bit 2/pi table (:77)
#     exactly as seven u32s with their hex spellings, `4.294967296e9` (:82),
#     `3.4061215800865545e-19` (:110), `2**62` (:108), the mask at :109, the
#     `i = shr(e,5)` / `e & 31` / `offset = 32 - e` derivation (:84-86) and the
#     `_take` window arithmetic (:88-92) -- see `tc.take_*` and `xf_sp.topi_len`.
#
# W2. `xpow` (:257-265) CALLS THE NATIVE OPS.  `base.log2().mul(exponent)
#     .exp2()` are `Ops.LOG2` and `Ops.EXP2`, not `xlog2`/`xexp2`, so this file
#     does NOT claim their values: `F32.log2` exists but there is no
#     `F32.exp2`, and substituting this file's own `xexp2` would be claiming a
#     DIFFERENT function than the one `xpow` calls.  What IS gated is the half
#     that is pure -- `non_int` (:261), `is_odd` (:262), the `exponent.eq(0)`
#     short circuit (:265) and the `-base` at :259: `xp_xpow_*`, plus
#     `xf_xpow_*` for the fixtures the source answers WITHOUT evaluating a
#     transcendental (`e == 0`, `base == 0`).
#     MEASURED, and worth knowing: `xpow` with an INFINITE exponent is not
#     realisable at all on the interpreter backend, because :261 casts the
#     exponent to int32 and `int(inf)` raises.  `(-1)inf` therefore has no
#     value anywhere -- on hardware `(int)inf` is undefined too.  It gets a
#     predicate row and no value row, which is the honest shape.
#
# `U32 -> F32` bitcast -- absent.  `pow2if` (:27), `frexp`'s mantissa (:52)
# and `ldexp3k`'s exponent add (:39) are integer fields written into a float;
# each is computed ARITHMETICALLY and the pattern recovered with `F32.bits`, so
# the gate compares against the bitcast tinygrad performs.  `xf_pow2if_*`,
# `xf_frexp_*` and `xf_ldexp3k_*` are those claims.
#

# THE INVENTORY, in upstream's order.  PORTED = the float32 lane is evaluated and
# gated.  GATES = only the predicate is gated.  W1/W2 as above.
#
# the left column is upstream's own name, backticked, and the cited line is
# UPSTREAM'S.  The right column is THIS PORT's row name, and it is NOT in upstream --
# `xf_lazy0_*` and `cu_mb_*` are the port's own gate-row prefixes.  So the port
# symbol is written as the port's and the upstream construct is named beside it:
# a citation that names the construct does not rot when the lines move.
#
#   :7    `TRANSCENDENTAL_DTYPES` PORTED  `tx_dt.transcendental`
#   tinygrad/codegen/decomp/transcendental.py:9-11 `_lazy_map_numbers` PORTED  `xf_lazy0_*`, `xf_lazy1_*`
#   tinygrad/codegen/decomp/transcendental.py:14 `mantissa_bits` PORTED  `cu_mb_*`, `cx_mb_*`, `cu_mant64.*`
#   tinygrad/codegen/decomp/transcendental.py:15 `exponent_bias` PORTED  `cu_eb_*`, `cx_eb_*`, `cu_eb64.*`
#   tinygrad/codegen/decomp/transcendental.py:16 `exponent_mask` PORTED  `cu_em_*`, `cx_em_*`, `cu_em64.*`
#   tinygrad/codegen/decomp/transcendental.py:19 `shr` PORTED  `xf_shr23_*`
#   tinygrad/codegen/decomp/transcendental.py:20 `shl` PORTED  `xf_shl23_*`
#   tinygrad/codegen/decomp/transcendental.py:22 `rintk` PORTED  `xf_rintk_*`
#   tinygrad/codegen/decomp/transcendental.py:27 `pow2if` PORTED  `xf_pow2if_*` (see THE BITCAST)
#   tinygrad/codegen/decomp/transcendental.py:32 `ilogb2k` PORTED  `xf_ilogb2k_*`
#   tinygrad/codegen/decomp/transcendental.py:39 `ldexp3k` PORTED  `xf_ldexp3k_*`
#   tinygrad/codegen/decomp/transcendental.py:47 `ldexp2k` PORTED  `xf_ldexp2k_*`
#   tinygrad/codegen/decomp/transcendental.py:52 `frexp` PORTED  `xf_frexp_*`
#   :66   `payne_hanek_reduction`   W1 for the uint64 product; its CONSTANTS and
#                                         its window arithmetic are PORTED
#   tinygrad/codegen/decomp/transcendental.py:115 `cody_waite_reduction` PORTED  `xf_cody_waite_*`
#   :150  `trig_poly`               PORTED (float32 table); the float64 table is
#                                         gated as exact DECIMALS
#   tinygrad/codegen/decomp/transcendental.py:152 `sin_poly` PORTED  `xf_sin_poly_*`
#   tinygrad/codegen/decomp/transcendental.py:158 `_ifand` PORTED  `xf_sps_*`, `xf_spl_*`
#   tinygrad/codegen/decomp/transcendental.py:160 `sin_poly_small` PORTED  `xf_sps_*`
#   tinygrad/codegen/decomp/transcendental.py:164 `sin_poly_large` PORTED  `xf_spl_*`
#   :170  `xsin`                    PORTED for fast=True; W1 past 30.0
#   tinygrad/codegen/decomp/transcendental.py:193 `xexp2` PORTED  `xf_xexp2_*`, `xf_xexp2_sp_*`
#   tinygrad/codegen/decomp/transcendental.py:219 `xlog2` PORTED  `xf_xlog2_*`, `xf_xlog2_sp_*`
#   tinygrad/codegen/decomp/transcendental.py:257 `xpow` GATES   `xp_xpow_*`
#   :267  `get_transcendental_patterns`
#         GRAPH, so `transcendental.bend`'s subject; the tables it selects
#         between ARE gated here.
#
# Oracles, all in `.agents/slop/`: `tc-audit.py` (+ `.txt`, the 146-constant
# table with repr / float.hex / f32 bits / f32 hex), `tc-value.py` (+
# `tc-rows-value.txt`, the 564-row `DEV=PYTHON` value oracle), `tc-gen.py`
# (+ `tc-rows-coef.txt`), `tc-rows.py`, `tc-diff.py`, `tc-build.py`,
# `tc-mutate.py`.
#

# THE GATE, AS IT STANDS: 834 oracle rows, 878 printed, 801 AGREE, 24 disagree,
# 9 MISSING, 53 extra.  The 24 are not 24 findings; they are THREE, and the
# expectations are CPython's in every case and are NOT edited.
#
# 1. `xf_pi_a` -- the `F32.read` compiler bug above.  ONE row, and it turns green
#    by itself the moment the compiler is fixed.
# 2. `xg_xexp2_ge_up_nan` -- IEEE says `NaN >= 128` is FALSE and this file says
#    FALSE; tinygrad's interpreter says TRUE.  ONE row, and it is tinygrad's
#    IEEE that is the outlier, so it is recorded and not "corrected".
# 3. TWENTY-TWO rows in `xf_cody_waite_*`, `xf_xsin_*`, `xf_spl_*` and
#    `xf_xlog2_3.0` -- a Cody-Waite remainder that is 1 to 3 ULP out for every
#    `|d| >= 3`, plus the quadrant at `d = 1.5707963`.  ONE mechanism is MEASURED
#    and it is a TIE: `d * m_1_pi` is exactly `0.4999999701976776` there, so
#    `+ 0.5` is the exact binary32 midpoint `0.9999999701976776`; this file's
#    correctly-rounded `F32.add` resolves it to `1.0` (round-half-even) and
#    tinygrad's interpreter resolves it to `0.9999999403953552`, so `rintk`
#    answers 1 where tinygrad answers 0.  Reproduced OUTSIDE the interpreter:
#    a float64 model of `_reduce_d` with a round-half-DOWN `rintk` takes the
#    quadrant from 7/9 to 8/9 exact.  The REMAINDER is a SECOND effect I have
#    NOT isolated: four rounding models (f32 each step, f64 multiply, f64 whole,
#    f32 multiply) all give the SAME wrong answer at 3.0/30.0/100.0/39800.0, so
#    it is not a rounding convention and it is still open.
#    Two of the twenty-two (`xf_xsin_*_3.1415927` and `_*_6.2831855`) are the
#    quadrant tie propagating, not a separate fault.
#
# THE NINE MISSING ROWS ARE W2, not an oversight: they are the `xf_xpow_*`
# fixtures whose value needs a transcendental (`2.0**0.5` and friends), and
# `xpow` calls the NATIVE `Ops.LOG2`/`Ops.EXP2`.  Substituting this file's own
# `xexp2` would be claiming a different function than the one `xpow` calls.
#

# THE MUTATION TABLE, RUN: 35 entries, 35 move rows, ZERO zeros.
#
# It is worth what it cost, because the zeros were the point and all five of the
# zeros the first run produced were real:
#   * `sp.topi_scale`, `sp.neg_half_pi_over_2`, `sp.nlog2e64`, `sp.pi_a`,
#     `sp.pi_b/c/d`, `sp.flmin_16` had NO CALL SITE -- eight defs that nothing
#     calls, invisible to every other check, four of which were mutations that
#     "moved nothing".  DELETED, and `tc-gen.py` now emits only the sixteen
#     scalars that are live.
#   * `xg_xlog2_nezero_*` read `F32.is_eq` directly, so the `tc.xlog2_nezero`
#     def the row is NAMED for was gated by nothing.  The row now calls it.
#   * The reverse-lookup SENTINEL was unobservable: every `xv_*` row was a hit.
#     Two `*_miss` rows now ask for a bit pattern no table holds.
#   * `_lazy_map_numbers` had no inf or NaN fixture, so its three arms were
#     indistinguishable.  Asking for one found TWO real bugs: `:11`'s three
#     tests compare against `math.inf`/`-math.inf` LITERALS and this file compared
#     against the PARAMETERS, and the NaN arm was on the wrong side of its pick.
#   * One mutation is a THEOREM and is reported as one: the two spellings of
#     Cody-Waite's second pi term are the SAME binary32 (3102560256, MEASURED),
#     so only the `cd_` DECIMAL row can see it -- which is the whole reason that
#     row exists.
#
# `.agents/slop/tc-mutate.py` runs each edit on a lane holding the coefficient
# rows plus the value TAGS that edit can reach, and diffs whole `name=value`
# lines.  Per-lane is not a shortcut: the full lane is 878 rows and this file's
# coefficient-only lane is 0.17 s, and `F32.pow` replaced a doubling loop that
# made the full lane cost 21 minutes on an idle box (measured twice, under load:
# hours).

import Base

# THE GENERATED HALF.  Every literal below came out of CPython:
#   sp.*  the coefficient tables, from `tc-audit.py` via `tc-gen.py`
#   fx.*  the FIXTURE strings, taken from the ORACLE'S OWN ROW NAMES
# Neither is mine.  See `.agents/slop/tc-audit.py`, `tc-gen.py`, `tc-rows.py`.

def sp.sin32() -> List<&2, String>:
  String.split("2.6083159809786594e-06|-0.00019810690719168633|0.00833307858556509|-0.16666659712791443|1.0", '|')
def sp.sin32_raw() -> String: "2.6083159809786594e-06 | -0.00019810690719168633 | 0.00833307858556509 | -0.16666659712791443 | 1.0"
def sp.sin64() -> List<&2, String>:
  String.split("-7.972559550090379e-18|2.810099727108632e-15|-7.647122191181588e-13|1.605904306056645e-10|-2.5052108376350205e-08|2.7557319223919875e-06|-0.00019841269841269616|0.00833333333333333|-0.16666666666666666|1.0", '|')
def sp.sin64_raw() -> String: "-7.972559550090379e-18 | 2.810099727108632e-15 | -7.647122191181588e-13 | 1.605904306056645e-10 | -2.5052108376350205e-08 | 2.7557319223919875e-06 | -0.00019841269841269616 | 0.00833333333333333 | -0.16666666666666666 | 1.0"
def sp.exp32() -> List<&2, String>:
  String.split("0.0001535920892|0.001339262701|0.009618384764|0.05550347269|0.2402264476|0.6931471825|1.0", '|')
def sp.exp32_raw() -> String: "0.0001535920892 | 0.001339262701 | 0.009618384764 | 0.05550347269 | 0.2402264476 | 0.6931471825 | 1.0"
def sp.exp64() -> List<&2, String>:
  String.split("4.4343590829265295e-10|7.0731645980857074e-09|1.0178192609217605e-07|1.3215438725113276e-06|1.5252733535175847e-05|0.00015403530451011478|0.001333355814670499|0.0096181291075976|0.055504108664820466|0.24022650695910122|0.6931471805599453|1.0", '|')
def sp.exp64_raw() -> String: "4.4343590829265295e-10 | 7.0731645980857074e-09 | 1.0178192609217605e-07 | 1.3215438725113276e-06 | 1.5252733535175847e-05 | 0.00015403530451011478 | 0.001333355814670499 | 0.0096181291075976 | 0.055504108664820466 | 0.24022650695910122 | 0.6931471805599453 | 1.0"
def sp.log32() -> List<&2, String>:
  String.split("0.4374550283|0.5764790177|0.961801290512", '|')
def sp.log32_raw() -> String: "0.4374550283 | 0.5764790177 | 0.961801290512"
def sp.log64() -> List<&2, String>:
  String.split("0.22119417504560815|0.22007686931522777|0.26237080574885147|0.32059774779444955|0.41219859454853247|0.5770780162997059|0.9617966939260809", '|')
def sp.log64_raw() -> String: "0.22119417504560815 | 0.22007686931522777 | 0.26237080574885147 | 0.32059774779444955 | 0.41219859454853247 | 0.5770780162997059 | 0.9617966939260809"
def sp.topi() -> List<&2, String>:
  String.split("0|0x00000000|683565275|0x28be60db|2475754826|0x9391054a|2131351028|0x7f09d5f4|2102212464|0x7d4d3770|920167782|0x36d8a566|1326507024|0x4f10e410", '|')
def sp.topi_raw() -> String: "0 | 683565275 | 2475754826 | 2131351028 | 2102212464 | 920167782 | 1326507024"
def sp.fscal() -> List<&2, String>:
  String.split("m_1_pi|0.3183098861837907|two_24|16777216.0|topi_scale|4294967296.0|neg_half_pi_over_2|3.4061215800865545e-19|nlog2e64|2.8853900817779268|nlog2e32|2.885390043258667|s_lo32|3.273447448356849e-08|one_over_075|1.3333333333333333|switch_over|30.0|pi_over_2|1.5707963267948966|cw0|-3.1414794921875|cw1|-0.0001131594181060791|cw2|-1.984187258941006e-09|cw3|-1.215420125655342e-10|pi_a|3.1415926218032837|pi_b|3.1786509424591713e-08|pi_c|1.2246467864107189e-16|pi_d|1.27366343270219e-24|xexp2_lo_32|-150|xexp2_up_32|128|flmin_16|6.1e-05|flmin_32|0.0001|denorm_scale|1.8446744073709552e+19|two_m24|5.960464477539063e-08", '|')
def sp.m_1_pi() -> String: "0.3183098861837907"
def sp.two_24() -> String: "16777216.0"
def sp.nlog2e32() -> String: "2.885390043258667"
def sp.s_lo32() -> String: "3.273447448356849e-08"
def sp.one_over_075() -> String: "1.3333333333333333"
def sp.switch_over() -> String: "30.0"
def sp.pi_over_2() -> String: "1.5707963267948966"
def sp.cw0() -> String: "-3.1414794921875"
def sp.cw1() -> String: "-0.0001131594181060791"
def sp.cw2() -> String: "-1.984187258941006e-09"
def sp.cw3() -> String: "-1.215420125655342e-10"
def sp.xexp2_lo_32() -> String: "-150"
def sp.xexp2_up_32() -> String: "128"
def sp.flmin_32() -> String: "0.0001"
def sp.denorm_scale() -> String: "1.8446744073709552e+19"
def sp.two_m24() -> String: "5.960464477539063e-08"
def sp.fm1_32() -> U32: 2155872255
def sp.fm1_32_hex() -> String: "0x807fffff"
def sp.fm2_32() -> U32: 1056964608
def sp.fm2_32_hex() -> String: "0x3f000000"
def sp.fm1_16() -> U32: 33791
def sp.fm1_16_hex() -> String: "0x000083ff"
def sp.fm2_16() -> U32: 14336
def sp.fm2_16_hex() -> String: "0x00003800"
def sp.frac_mask() -> U32: 8388607
def sp.frac_mask_hex() -> String: "0x007fffff"
def sp.de_32() -> U32: 64
def sp.de_32_hex() -> String: "0x00000040"
def sp.q_shift() -> U32: 62
def sp.q_shift_hex() -> String: "0x0000003e"
def sp.take_window() -> U32: 6
def sp.take_window_hex() -> String: "0x00000006"
def sp.mb_32() -> U32: 23
def sp.mb_32_hex() -> String: "0x00000017"
def sp.eb_32() -> U32: 127
def sp.eb_32_hex() -> String: "0x0000007f"
def sp.em_32() -> U32: 255
def sp.em_32_hex() -> String: "0x000000ff"
def sp.mb_16() -> U32: 10
def sp.mb_16_hex() -> String: "0x0000000a"
def sp.eb_16() -> U32: 15
def sp.eb_16_hex() -> String: "0x0000000f"
def sp.em_16() -> U32: 31
def sp.em_16_hex() -> String: "0x0000001f"
def sp.p_mask_hi() -> U32: 1073741823
def sp.p_mask_lo() -> U32: 4294967295
def sp.fm1_64_hi() -> U32: 1048575
def sp.fm1_64_lo() -> U32: 4294967295
def sp.fm2_64_hi() -> U32: 1071644672
def sp.fm2_64_lo() -> U32: 0
def sp.mant64_hi() -> U32: 0
def sp.mant64_lo() -> U32: 52
def sp.eb64_hi() -> U32: 0
def sp.eb64_lo() -> U32: 1023
def sp.em64_hi() -> U32: 0
def sp.em64_lo() -> U32: 2047
def sp.mb_64() -> U32: 52
def sp.mb_64_hex() -> String: "0x00000034"
def tx_dt.transcendental_t() -> String: "f16 f32 f64"
def tx_dt.rintk_f64_t() -> String: "dtypes.i64"
def tx_dt.rintk_f32_t() -> String: "dtypes.i32"
def tx_dt.rintk_f16_t() -> String: "dtypes.i16"
def tx_dt.pow2if_i64_t() -> String: "dtypes.f64"
def tx_dt.pow2if_i32_t() -> String: "dtypes.f32"
def tx_dt.pow2if_i16_t() -> String: "<param>"
def tx_dt.ilogb2k_f64_t() -> String: "dtypes.i64"
def tx_dt.ilogb2k_f32_t() -> String: "dtypes.i32"
def tx_dt.ilogb2k_f16_t() -> String: "dtypes.i16"
def tx_dt.ldexp3k_f64_t() -> String: "dtypes.i64"
def tx_dt.ldexp3k_f32_t() -> String: "dtypes.i32"
def tx_dt.ldexp3k_f16_t() -> String: "dtypes.i16"
def tx_dt.frexp_u_f64_t() -> String: "dtypes.u64"
def tx_dt.frexp_u_f32_t() -> String: "dtypes.u32"
def tx_dt.frexp_u_f16_t() -> String: "dtypes.u16"
def tx_dt.pow2if_param_t() -> String: "float_dtype"

def fx.sinpoly() -> List<&2, String>:
  String.split("0.0|0.5|-0.5|1.0|-1.0|1.5707963|0.25|-0.75", '|')
def fx.shr() -> List<&2, String>:
  String.split("1|2|255|256|2147483647|4294967295", '|')
def fx.shl() -> List<&2, String>:
  String.split("1|2|255|256|2147483647|4294967295", '|')
def fx.rintk() -> List<&2, String>:
  String.split("0.0|-0.0|0.4|-0.4|0.5|-0.5|2.5|-2.5|10000000.0|-10000000.0", '|')
def fx.ilogb() -> List<&2, String>:
  String.split("0.5|0.75|1.0|1.5|3.0|1024.0|0.0001|8388608.0", '|')
def fx.frexp_m() -> List<&2, String>:
  String.split("0.5|1.0|1.5|3.0|-2.5|1024.0", '|')
def fx.frexp_e() -> List<&2, String>:
  String.split("0.5|1.0|1.5|3.0|-2.5|1024.0", '|')
def fx.cw_r() -> List<&2, String>:
  String.split("0.0|0.5|1.0|1.5707963|3.0|30.0|100.0|-100.0|39800.0", '|')
def fx.cw_q() -> List<&2, String>:
  String.split("0.0|0.5|1.0|1.5707963|3.0|30.0|100.0|-100.0|39800.0", '|')
def fx.sps() -> List<&2, String>:
  String.split("0.5_0|0.5_1|0.5_2|0.5_3|0.5_4|-0.5_1|1.0_2|1.5707963_2|1.5707963_1", '|')
def fx.xsinfast() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|1.5707963|3.1415927|6.2831855|29.999998|30.0|30.000002|0.25|100.0|-100.0", '|')
def fx.xsinslow() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|1.5707963|3.1415927|6.2831855|29.999998|0.25", '|')
def fx.xexp2() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|2.0|-2.0|30.0|126.99999|127.0|127.99999|128.0|128.00001|200.0|-149.99999|-150.0|-150.00001|-200.0|100000.0|-100000.0", '|')
def fx.xexp2sp() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|2.0|-2.0|30.0|126.99999|127.0|127.99999|128.0|128.00001|200.0|-149.99999|-150.0|-150.00001|-200.0|100000.0|-100000.0|inf|-inf", '|')
def fx.xlog2() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|0.75|1.0|1.5|2.0|3.0|5e-05|9.999e-05|0.00010001|1e-30|3e-40|-1.0|1024.0|0.25|8.0", '|')
def fx.xlog2sp() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|0.75|1.0|1.5|2.0|3.0|5e-05|9.999e-05|0.00010001|1e-30|3e-40|-1.0|1024.0|0.25|8.0|inf|-inf", '|')
def fx.inf() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|inf|-inf|nan", '|')
def fx.g() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|2.0|-2.0|30.0|127.99999|128.0|128.00001|-149.99999|-150.0|-150.00001|inf|-inf|nan", '|')
def fx.special() -> List<&2, String>:
  String.split("0.0|-0.0|0.5|-0.5|1.0|-1.0|inf|-inf|nan", '|')
def fx.xpowval() -> List<&2, String>:
  String.split("0.0_0.0|0.0_5.0|inf_0.0|4.0_0.0|-4.0_0.0|-0.0_3.0|-0.0_2.5|2.0_0.0|0.0_-1.0|-0.0_-3.0", '|')

# ldexp2k / ldexp3k: "d_e"
def fx.ldexp() -> List<&2, String>:
  String.split("0.75_5|1.0_3|1.5_-2|3.0_0", '|')
# pow2if: plain integers
def fx.pow2if() -> List<&2, String>:
  String.split("-1|-10|-126|0|1|10|126", '|')
# spl: "d_q", the LARGE sibling of the sps fixtures
def fx.spl() -> List<&2, String>:
  String.split("-0.5_1|0.5_0|0.5_1|0.5_2|0.5_3|0.5_4|1.0_2|1.5707963_1|1.5707963_2", '|')
# the four xpow predicate families
def fx.xpowp() -> List<&2, String>:
  String.split("-0.0_2.5|-0.0_3.0|-2.0_-3.0|-2.0_2.0|-2.0_2.5|-2.0_3.0|-4.0_0.0|0.0_-1.0|0.0_0.0|0.0_5.0|0.5_2.0|2.0_0.0|2.0_0.5|4.0_0.0|inf_0.0", '|')
# xpow: "base_exponent"
# (the fixture lists themselves live in `fixtures` mode)
def fx.lazy() -> List<&2, String>:
  String.split("-0.0|-0.5|-1.0|-inf|0.0|0.5|1.0|inf|nan", '|')
# THE ROW PRINTERS.

# THE GATE MOVED TO `gates/transcendental_f32-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its 932 rows are the f32 half of the same census -- the same op/dtype pairs
# in one dtype -- and `gates/transcendental_f32-gate.bend` is the driver that
# prints them.
