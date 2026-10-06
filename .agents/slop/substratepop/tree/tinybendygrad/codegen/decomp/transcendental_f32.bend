# transcendental_f32.bend -- the COEFFICIENT AND VALUE half of
# tinygrad/codegen/decomp/transcendental.py (277 lines).
#
# ============================ READ THIS FIRST ==============================
#
# THERE IS A SECOND PORT OF THE SAME PYTHON FILE, at
# `tinybendygrad/codegen/transcendental.bend` (TODO.md, "Session 2026-10-01 round
# 4", 891 STRING rows, `--check-only` = ALL PROOFS CHECK).  THE TWO ARE
# COMPLEMENTARY HALVES OF ONE UPSTREAM FILE, NOT TWO PORTS OF IT, and this is the
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
# ---------------------------------------------------------------------------
# NO DIGIT IN THE GENERATED HALF IS MINE.  `sp.*` and `fx.*` are produced by
# `.agents/slop/tc-gen.py bend` and `.agents/slop/tc-rows.py {fixtures,pairs}`,
# which read `.agents/slop/tc-audit.txt` -- CPython's own output, 146 constants
# from THREE measured channels (a `polyN` spy, a `shr`/`shl` spy, and source
# `eval`).  `tc-build.py` reassembles head + generated + tail and the three
# parts reproduce this file byte for byte.
#
# THE HEX CROSS-CHECK EARNED ITS KEEP, and this is why transcendental
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
# ---------------------------------------------------------------------------
# TWO DEFECTS THIS FILE FOUND, both in OTHER people's code, both left loud.
#
# 1. THE REVERSE LOOKUP WAS ANSWERING "NOT FOUND" FOR EVERYTHING, and it was one
#    bug worth 45 rows, not 45.  `tc.vi`/`tc.uvi` search a table for a bit
#    pattern and every `xv_*` row answered 4294967295 while every `xf_*` row for
#    the same table agreed -- which is what made it look like a coefficient bug.
#    It was not: `sp.*_raw()` renders a table with `" | "` between the elements so
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
#    bug: `F32.read` is a `law` in `base.bend:1705` and a primitive of the Bend
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
# ---------------------------------------------------------------------------
# WHY A VALUE LAYER IS POSSIBLE AT ALL.  Two measurements:
#
#   1. `base.bend`'s F32 arithmetic is BIT-EXACT with CPython/numpy.  Probe:
#      add, sub, mul, div, neg, abs, floor, trunc, is_lt, is_ge on
#      (-3.7, 0.5, 0.0) -- all twelve answers equal
#      `struct.unpack('<I', struct.pack('<f', np.float32(...)))`, and
#      `F32.div(0.0, 0.0)` is the canonical NaN 0x7fc00000.
#   2. `F32.read` (base.bend:1705) parses a DECIMAL STRING into an F32 and
#      agrees with CPython on 145 of the 146 constants audited -- see defect 2
#      for the one.  It accepts "inf", "-inf" and "nan", which is how the
#      specials get CONSTRUCTED (there is no inf literal), and answers `None`
#      for a string with whitespace in it, which is defect 1.
#
# `F32.show` is lossy (seven digits) and appears in no gate; `F32.bits` is the
# gate.
#
# ---------------------------------------------------------------------------
# NO float64 EVALUATION, and the float64 coefficients are still verified.  Bend
# has no `F64` (MEASURED: `grep -n F64 references/bend/bend2/base.bend` is
# empty).  A float64 coefficient cannot be a VALUE here, so it is a STRING
# instead: CPython's `repr()` of the float, the shortest decimal that
# round-trips, gated by `cd_*` with `float.hex()` on the record in
# `tc-audit.txt` col 3.
#
# ---------------------------------------------------------------------------
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
#     exponent to int32 and `int(inf)` raises.  `(-1)**inf` therefore has no
#     value anywhere -- on hardware `(int)inf` is undefined too.  It gets a
#     predicate row and no value row, which is the honest shape.
#
# **`U32 -> F32` bitcast** -- absent.  `pow2if` (:30), `frexp`'s mantissa (:61)
# and `ldexp3k`'s exponent add (:45) are integer fields written into a float;
# each is computed ARITHMETICALLY and the pattern recovered with `F32.bits`, so
# the gate compares against the bitcast tinygrad performs.  `xf_pow2if_*`,
# `xf_frexp_*` and `xf_ldexp3k_*` are those claims.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, in upstream's order.  PORTED = the float32 lane is evaluated and
# gated.  GATES = only the predicate is gated.  W1/W2 as above.
#
#   :7    TRANSCENDENTAL_DTYPES   PORTED  `tx_dt.transcendental`
#   :9-11 _lazy_map_numbers       PORTED  `xf_lazy0_*`, `xf_lazy1_*`
#   :14   mantissa_bits           PORTED  `cu_mb_*`, `cx_mb_*`, `cu_mant64.*`
#   :15   exponent_bias           PORTED  `cu_eb_*`, `cx_eb_*`, `cu_eb64.*`
#   :16   exponent_mask           PORTED  `cu_em_*`, `cx_em_*`, `cu_em64.*`
#   :19   shr                     PORTED  `xf_shr23_*`
#   :20   shl                     PORTED  `xf_shl23_*`
#   :22   rintk                   PORTED  `xf_rintk_*`
#   :27   pow2if                  PORTED  `xf_pow2if_*` (see THE BITCAST)
#   :32   ilogb2k                 PORTED  `xf_ilogb2k_*`
#   :39   ldexp3k                 PORTED  `xf_ldexp3k_*`
#   :47   ldexp2k                 PORTED  `xf_ldexp2k_*`
#   :52   frexp                   PORTED  `xf_frexp_*`
#   :66   payne_hanek_reduction   W1 for the uint64 product; its CONSTANTS and
#                                         its window arithmetic are PORTED
#   :115  cody_waite_reduction    PORTED  `xf_cody_waite_*`
#   :150  trig_poly               PORTED (float32 table); the float64 table is
#                                         gated as exact DECIMALS
#   :152  sin_poly                PORTED  `xf_sin_poly_*`
#   :158  _ifand                  PORTED  `xf_sps_*`, `xf_spl_*`
#   :160  sin_poly_small          PORTED  `xf_sps_*`
#   :164  sin_poly_large          PORTED  `xf_spl_*`
#   :170  xsin                    PORTED for fast=True; W1 past 30.0
#   :193  xexp2                   PORTED  `xf_xexp2_*`, `xf_xexp2_sp_*`
#   :219  xlog2                   PORTED  `xf_xlog2_*`, `xf_xlog2_sp_*`
#   :257  xpow                    GATES   `xp_xpow_*`
#   :267  get_transcendental_patterns
#         GRAPH, so `transcendental.bend`'s subject; the tables it selects
#         between ARE gated here.
#
# Oracles, all in `.agents/slop/`: `tc-audit.py` (+ `.txt`, the 146-constant
# table with repr / float.hex / f32 bits / f32 hex), `tc-value.py` (+
# `tc-rows-value.txt`, the 564-row `DEV=PYTHON` value oracle), `tc-gen.py`
# (+ `tc-rows-coef.txt`), `tc-rows.py`, `tc-diff.py`, `tc-build.py`,
# `tc-mutate.py`.
#
# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
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

# ===========================================================================
# THE GENERATED HALF.  Every literal below came out of CPython:
#   sp.*  the coefficient tables, from `tc-audit.py` via `tc-gen.py`
#   fx.*  the FIXTURE strings, taken from the ORACLE'S OWN ROW NAMES
# Neither is mine.  See `.agents/slop/tc-audit.py`, `tc-gen.py`, `tc-rows.py`.
# ===========================================================================
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
# ===========================================================================
def urow(+nm: String, +v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(+nm: String, +v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# ===========================================================================
# THE ACCESSORS.  A `Maybe` is unwrapped EXPLICITLY and a miss answers a
# sentinel the gate SHOWS, never a default that would hide it.
# ===========================================================================

def tc.rdf(+m: Maybe<&2, F32>) -> F32:
  match m:
    case Some{v}: v
    case None{}: F32.mul(2.0, 0.0)

def tc.rds(+m: Maybe<&2, String>) -> String:
  match m:
    case Some{v}: v
    case None{}: "MISSING"

def tc.rdu(+m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 4294967295

# a decimal STRING to the binary32 it denotes.  This is `UOp.const`'s weak
# float, and it is why a coefficient can be carried as text at all.
#
# THE TRIM IS LOAD-BEARING, and it is the whole of one bug worth 45 rows.
# `sp.*_raw()` renders a table with `" | "` between the elements so a human can
# read it, and the reverse lookup re-splits THAT string -- so every element but
# the last arrives with a leading and a trailing space, and `F32.read`/`U32.read`
# answer `None` for any string with whitespace in it.  MEASURED: `F32.read
# ("0.0001535920892 ")` is `None` while `F32.read("0.0001535920892")` is 958467472,
# and the symptom was exactly that only the LAST element of every table was
# findable, because only the last one is not followed by a space.  Trimming in
# the READER is where it belongs: it is the one place a decimal becomes a number.
def tc.f(+s: String) -> F32: tc.rdf(F32.read(String.trim(s)))

def tc.b(+s: String) -> U32: F32.bits(tc.f(s))

# the INTEGER sibling, for the fixtures that are really u32 operands.
def tc.u(+s: String) -> U32: tc.rdu(U32.read(String.trim(s)))

def tc.nat(+i: U32) -> Nat: U32.to_nat(i)

def tc.nth(+xs: List<&2, String>, +i: U32) -> String:
  tc.rds(List.get(&2, String, xs, tc.nat(i)))

# `List.length` is the plain way and the gate needs a U32 count, so this is the
# one U32-shaped length in the file.
def tc.ilen(+xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

# a fixture `"d_q"` splits at its ONLY underscore: neither the bases nor the
# exponents written in this file contain one, so there is no last-underscore
# problem here and no reason to solve one.
def tc.dq0(+s: String) -> String:
  tc.rds(List.get(&2, String, String.split(s, '_'), 0n))

def tc.dq1(+s: String) -> String:
  tc.rds(List.get(&2, String, String.split(s, '_'), 1n))

# ---------------------------------------------------------------------------
# INDEX -> VALUE and VALUE -> INDEX, and they are independent on purpose.  The
# fixture of the second is the BIT PATTERN, not the position: a mutated
# coefficient leaves the old pattern unfindable and the row answers 4294967295.
# Without that, one row wearing two hats would move for a single edit and read
# like two checks.  The third row is the element as TEXT, which is the only
# handle on a float64 coefficient -- there is no F64 to hold one.
# ---------------------------------------------------------------------------
def tc.fv(+xs: List<&2, String>, +i: U32) -> U32: tc.b(tc.nth(xs, i))

def tc.vi(+xs: List<&2, String>, +b: U32, +i: U32) -> U32:
  match xs:
    case Nil{}: 4294967295
    case x <> t:
      Bool.pick(U32, U32.is_eq(tc.b(x), b), i, tc.vi(t, b, U32.inc(i)))

def tc.pow2u(+y: U32) -> U32: U32.shln(1, tc.nat(y))

# :20 `x * (2**y)`, wrapped -- `U32.mul` already wraps, and a y >= 32 gives 0,
# which is exactly what `x * 2**32 mod 2**32` is.
def tc.shr_u(+x: U32, +y: U32) -> U32: U32.div(x, tc.pow2u(y))

# :19 on a SIGNED operand: FLOOR, not a truncating shift, so the
# `-1 <= ilog2bk(d) <= 128` claim at :36 survives a negative `dint`.
# `floor(x / 2**y)` is `-( (-x) // 2**y)` for a negative x and the plain
# division otherwise; that is what makes it FLOOR and not truncate-toward-zero.
def tc.isneg(+x: U32) -> Bool: U32.is_ge(x, 2147483648)

def tc.neg(+a: U32, +b: U32) -> U32: U32.sub(0, b)

# :19 `x // (2**y)` on an UNSIGNED operand.
# :19 `x // (2**y)` on an UNSIGNED operand.  ONE division, not `y` of them: a
# y >= 32 divides by 2**32 and answers 0, which `U32.shln` already gives.
def tc.shr_i(+x: U32, +y: U32) -> U32:
  Bool.pick(U32, tc.isneg(x), tc.neg(0, tc.shr_u(tc.neg(0, x), y)),
            tc.shr_u(x, y))

# signed 32-bit add, kept in the U32 domain so the row is a bit pattern.
def tc.uvi(+xs: List<&2, String>, +b: U32, +i: U32) -> U32:
  match xs:
    case Nil{}: 4294967295
    case x <> t:
      Bool.pick(U32, U32.is_eq(tc.u(x), b), i, tc.uvi(t, b, U32.inc(i)))

# ===========================================================================
# THE INTEGER RULES.  MEASURED by a spy on `shr`/`shl` in the audit oracle
# (`.agents/slop/tc-audit.txt` rows `shr[0].y` .. `shr[16].y`): ALL SEVENTEEN
# shift amounts tinygrad asks for in this file are PYTHON INTS, and every one of
# them is an INTEGER shift -- there is no float `shr` or `shl` anywhere.  So
# `tc.shr_u` is unsigned floor division and `tc.shr_i` is the signed FLOOR one
# that `ilogb2k` needs.
#
# A self-call passes its arguments UNCHANGED up to the first one that shrinks,
# so every recursion here takes a `Nat` fuel LAST (the shape of
# `U32.log2.go` in base.bend).
# ===========================================================================

# `U32.shl` is a ONE-BIT shift and `U32.shln(a, n)` is the n-bit one, so a shift
# AMOUNT has to be a `Nat` built from a runtime value.
def tc.shl(+x: U32, +y: U32) -> U32: U32.mul(x, tc.pow2u(y))

def tc.iadd(+a: U32, +b: U32) -> U32: U32.add(a, b)

# ===========================================================================
# THE FLOAT RULES.
# ===========================================================================
def tc.pick(+c: Bool, +a: F32, +b: F32) -> F32: Bool.pick(F32, c, a, b)

def tc.zero() -> F32: F32.mul(2.0, 0.0)
def tc.pinf() -> F32: tc.rdf(F32.read("inf"))
def tc.ninf() -> F32: tc.rdf(F32.read("-inf"))
def tc.qnan() -> F32: tc.rdf(F32.read("nan"))

def tc.bit(+b: Bool) -> U32: Bool.to_u32(b)

# The six guard rows whose oracle is a `.ne(...)` are the NEGATIVE of the
# "is this value" predicate.  MEASURED: reading `x.ne(math.inf)` as `is inf`
# inverts every one of them, and all 18 fixtures of each family went red at once.
def tc.nebit(+a: F32, +b: F32) -> U32: Bool.to_u32(Bool.not(F32.is_eq(a, b)))

# :25 `.cast(int32)`, which is C truncation TOWARD ZERO.  `F32.to_u32` refuses a
# negative, so the sign is carried out of the magnitude and put back on.
def tc.f2i(+x: F32) -> U32:
  Bool.pick(U32, F32.is_lt(x, tc.zero()),
            U32.sub(0, F32.to_u32(F32.trunc(F32.abs(x)))),
            F32.to_u32(F32.trunc(F32.abs(x))))

# the inverse, for the places `xexp2`/`xlog2` read a computed integer back as a
# float.  `U32.to_f32` is exact below 2**24 and every call site here is.
def tc.i2f(+b: U32) -> F32:
  +m = U32.to_f32(Bool.pick(U32, tc.isneg(b), tc.neg(0, b), b))
  Bool.pick(F32, tc.isneg(b), F32.neg(m), m)

# `2**n` for a signed n held as a u32 bit pattern, as `F32.pow(2.0, n)`.
#
# THIS IS A MEASURED PERFORMANCE FIX, and it is the difference between a mutation
# table that gets run and one that does not.  The doubling loop it replaced cost
# one interpreted step per unit of |n|, so `xexp2(100000.0)` -- a fixture at :209's
# clamp boundary -- ran it 100000 times and the `xf_xexp2_*` family alone took
# MINUTES per run; MEASURED, a 35-mutation table over the full lane was projected
# at hours on a loaded 12-core box.
#
# `F32.pow(2.0, n)` is the EXACT spelling for a base of exactly 2.0, and it is
# bit-exact with CPython's `struct.pack('<f', 2.0**n)` over the whole range this
# file uses, including the two saturations the loop also produced -- MEASURED, 11
# probes, `n` in {0, 1, 10, 126, 127, -1, -10, -126, 150, -150, 50000}, every
# answer equal to CPython's, with 150 and 50000 both 0x7f7fffff (FLT_MAX) and -150
# both 0.  `xf_pow2if_*` compares the result against CPython's bit pattern for
# `q` in {-126, -10, -1, 0, 1, 10, 126}, so an ULP anywhere in that range would go
# red.  The claim is therefore not "F32.pow is right" but "either spelling is
# right, and the rows say which".
#
# `|n|` is `0 - n` in TWO'S COMPLEMENT, not `n & 0x7fffffff`: masking bit 31 off
# `-10` gives 2147483638 rather than 10.  MEASURED, that made every negative
# `pow2if` answer 0, and the same mask was in `tc.i2f` and `tc.ldexp3k`.
def tc.pow2f(+n: U32) -> F32: F32.pow(2.0, tc.i2f(n))

# ===========================================================================
# THE POLYNOMIALS.
# ===========================================================================

# `polyN(x, p) = reduce(lambda acc, c: acc*x + c, p, 0.0)` -- helpers.py:153.
# The SEED is the Python float `0.0`, so the first step really is `0.0*x + p[0]`
# and not `p[0]`.  At f32 with a finite x the two are the same number; the
# fixture that WOULD separate them is `x = inf`, which `F32.read` builds.

def tc.polyn.go(+xs: List<&2, String>, +acc: F32, +x: F32) -> F32:
  match xs:
    case Nil{}: acc
    case y <> t: tc.polyn.go(t, F32.add(F32.mul(acc, x), tc.f(y)), x)

def tc.polyn(+xs: List<&2, String>, +x: F32) -> F32: tc.polyn.go(xs, tc.zero(), x)

# :150 `trig_poly`, :152 `sin_poly` -- `d * polyN(d*d, coeff)`.
def tc.sin_poly(+d: F32) -> F32: F32.mul(d, tc.polyn(sp.sin32(), F32.mul(d, d)))

# :158 `(q & n).ne(0)`
def tc.ifand(+q: U32, +n: U32) -> Bool: Bool.not(U32.is_zero(U32.and(q, n)))

def tc.sign(+c: Bool) -> F32: Bool.pick(F32, c, F32.neg(1.0), 1.0)

# :160-162 `sin_poly_small(d, q)`
def tc.sps(+d: F32, +q: U32) -> F32:
  F32.mul(tc.sin_poly(d), tc.sign(tc.ifand(q, 1)))

# :164-166 `sin_poly_large(d, q)`
def tc.spl(+d: F32, +q: U32) -> F32:
  F32.mul(tc.sin_poly(tc.pick(tc.ifand(q, 1), F32.add(d, tc.f(sp.pi_over_2())), d)),
          tc.sign(tc.ifand(q, 2)))

# ===========================================================================
# THE RANGE REDUCTION, :52-63 and :115-147.
# ===========================================================================

# :59 `shr(bits, mantissa_bits) & exponent_mask`
def tc.fe(+v: F32) -> U32: U32.and(tc.shr_u(F32.bits(v), sp.mb_32()), sp.em_32())

# :62 `exponent - exponent_bias + 1`
# :62 `exponent - exponent_bias(v.dtype) + 1`, and `exponent_bias[f32]` is 127,
# so the whole tail is `- 126`.  MEASURED: without it every `xf_frexp_e_*` row
# came back as the raw exponent field -- 127 for frexp(0.5) where CPython says 0.
def tc.fexp(+v: F32) -> U32: U32.sub(tc.fe(v), U32.sub(sp.eb_32(), 1))

# `ldexp3k`'s `d * 2**e`: the exponent of the PRODUCT is the exponent of `d`
# plus `e`, and `fe` is one below the stored field, so the field is
# `fe + 23 - bias + 1`.
# the STORED exponent field of `v`, `(bits >> mb) & em` with no bias applied.
# `tc.fexp` above is that field MINUS ONE, because :62 wants `field - bias + 1`.
def tc.fexp2(+v: F32) -> U32: U32.and(tc.shr_u(F32.bits(v), sp.mb_32()), sp.em_32())

# :61 `((bits & m1) | m2).bitcast(v.dtype)`, rebuilt from the fraction field.
def tc.frexp_word(+v: F32) -> U32:
  U32.or(U32.and(F32.bits(v), sp.fm1_32()), sp.fm2_32())

def tc.frexp_mant(+v: F32) -> F32:
  Bool.pick(F32, tc.isneg(F32.bits(v)),
            F32.neg(F32.add(0.5, F32.mul(U32.to_f32(U32.and(F32.bits(v), sp.frac_mask())),
                                         tc.f(sp.two_m24())))),
            F32.add(0.5, F32.mul(U32.to_f32(U32.and(F32.bits(v), sp.frac_mask())),
                                 tc.f(sp.two_m24()))))

# :32-37 `(shr(dint, mantissa_bits) & exponent_mask) - exponent_bias`
def tc.ilogb2k(+d: F32) -> U32:
  U32.sub(U32.and(tc.shr_i(F32.bits(d), sp.mb_32()), sp.em_32()), sp.eb_32())

# :27-30 `pow2if`.  The value is 2**q by doubling; the gate compares its bit
# pattern against CPython's, which IS the `(q + bias) << 23` field.
def tc.pow2if(+q: U32) -> F32: tc.pow2f(q)

def tc.pow2if_word(+q: U32) -> U32: tc.shl(tc.iadd(q, sp.eb_32()), sp.mb_32())

# :47-50 `(d * pow2if(shr(e, 1))) * pow2if(e - shr(e, 1))`
def tc.ldexp2k(+d: F32, +e: U32) -> F32:
  F32.mul(F32.mul(d, tc.pow2if(tc.shr_i(e, 1))), tc.pow2if(U32.sub(e, tc.shr_i(e, 1))))

# :39-45 `(m1 + (e << mantissa_bits)).bitcast(d.dtype)`; :43 is the field add.
def tc.ldexp3k_word(+d: U32, +e: U32) -> U32:
  U32.add(d, tc.shl(U32.and(e, 255), sp.mb_32()))

# :45 `m1 + (e << mantissa_bits)`, evaluated as `d * 2**e`.  Exact while the
# result stays in the NORMAL range, which is the case at the one call site
# (:232), where `a` has already been scaled out of the denormal band at :229.
def tc.ldexp3k.up(+i: Nat, +d: F32) -> F32:
  match i:
    case 0n: d
    case 1n+p: tc.ldexp3k.up(p, F32.mul(d, 2.0))

def tc.ldexp3k.dn(+i: Nat, +d: F32) -> F32:
  match i:
    case 0n: d
    case 1n+p: tc.ldexp3k.dn(p, F32.div(d, 2.0))

# A PAIR travels in one record because Bend will not destructure a computed
# product.  Same idiom as `Made` in `ops_webgpu.bend`.
def tc.ldexp3k(+d: F32, +e: F32) -> F32:
  +n = Bool.pick(U32, tc.isneg(tc.f2i(e)), tc.neg(0, tc.f2i(e)), tc.f2i(e))
  Bool.pick(F32, tc.isneg(tc.f2i(e)), tc.ldexp3k.dn(tc.nat(n), d), tc.ldexp3k.up(tc.nat(n), d))

# the fuel is a Nat LAST, the shape `U32.log2.go` uses.
type Red is Data:
  Red{r: F32, q: U32}

def Red.r(+r: Red) -> F32:
  match r:
    case Red{a, b}: a

def Red.q(+r: Red) -> U32:
  match r:
    case Red{a, b}: b

# :22-25 `(d + (d<0 ? -0.5 : 0.5)).cast(int32)` -- round AWAY from zero.
def tc.rintk(+d: F32) -> U32:
  tc.f2i(tc.pick(F32.is_lt(d, tc.zero()), F32.sub(d, 0.5), F32.add(d, 0.5)))

# :138-141 the float32 arm of `_reduce_d`, left-associated, four times.
def tc.cw_step(+qf: F32, +c: String, +acc: F32) -> F32:
  F32.add(F32.mul(qf, tc.f(c)), acc)

def tc.cw_reduce(+x: F32, +q: U32) -> F32:
  +qf = tc.i2f(q)
  +r0 = tc.cw_step(qf, sp.cw0(), x)
  +r1 = tc.cw_step(qf, sp.cw1(), r0)
  +r2 = tc.cw_step(qf, sp.cw2(), r1)
  tc.cw_step(qf, sp.cw3(), r2)

# :145 `qdh`, DEAD for float32 and float16 -- only the float64 arm of
# `_reduce_d` reads it -- but BUILT unconditionally.  At f32 the int64 cast
# truncates it to zero for every fixture, so the value is 0.0.
def tc.qdh_scale() -> F32: F32.div(tc.f(sp.m_1_pi()), tc.f(sp.two_24()))

def tc.cw_qdh(+x: F32) -> F32:
  Bool.pick(F32, F32.is_lt(x, tc.zero()),
            F32.neg(U32.to_f32(F32.to_u32(F32.trunc(F32.abs(F32.mul(x, tc.qdh_scale())))))),
            U32.to_f32(F32.to_u32(F32.trunc(F32.abs(F32.mul(x, tc.qdh_scale()))))))

# :146 `rintk(d * m_1_pi)` -- the float32 arm, since `d.dtype != float64`.
def tc.cw_quadrant(+x: F32) -> U32: tc.rintk(F32.mul(x, tc.f(sp.m_1_pi())))

# :115-147 `cody_waite_reduction`
# BITWISE equality, which is NOT IEEE equality: `tc.beq(NaN, NaN)` is TRUE here
# and FALSE for `F32.is_eq`, and `tc.beq(+0.0, -0.0)` is FALSE and TRUE for it.
# The ±inf tests below are the same either way -- `+-0.0` is `!= +-inf` under both
# readings -- but `x.ne(x)` at :11 is NOT, and MEASURED using `tc.beq` there made
# `mask0(NaN)` return NaN where tinygrad returns 0: two rows, and both of them
# only exist because the mutation table asked for a NaN fixture.
def tc.beq(+a: F32, +b: F32) -> Bool: U32.is_eq(F32.bits(a), F32.bits(b))

# :11 is `x.ne(math.inf).where(x.ne(x).where(nan, x.ne(-math.inf).where(ratio,
# _inf)), inf)`, and there are FIVE names in that line with two different jobs: the
# `inf`/`_inf`/`nan` PARAMETERS are what the three arms RETURN, while `math.inf`
# and `-math.inf` are the LITERALS the three tests use.  MEASURED: testing against
# the parameters made `mask0(+inf)` return +inf where tinygrad returns 0, and
# flipping the NaN arm's polarity was needed for the same reason -- `x.ne(x)` is
# TRUE for a NaN, so the NaN arm is the TRUE arm.  Four rows, and none of them
# existed before the mutation table asked for an inf fixture.
def tc.lazy(+x: F32, +inf: F32, +_inf: F32, +nan: F32, +ratio: F32) -> F32:
  Bool.pick(F32, tc.beq(x, tc.pinf()), inf,
            Bool.pick(F32, Bool.not(F32.is_eq(x, x)), nan,
                      Bool.pick(F32, tc.beq(x, tc.ninf()), _inf, ratio)))

# ===========================================================================
# THE EXPANSIONS, float32 lane.
# ===========================================================================

# :178 mask +-inf/nan to 0.0 -- the SAME `_lazy_map_numbers` call as :200 and
# :191, with three zero replacements.
def tc.mask0(+d: F32) -> F32: tc.lazy(d, tc.zero(), tc.zero(), tc.zero(), d)

# :180 `x_sign`
def tc.cody_waite(+x: F32) -> Red:
  +q = tc.cw_quadrant(x)
  Red{tc.cw_reduce(x, q), q}

# ===========================================================================
# THE SPECIAL CASES.  Each guard is its own row, and each BOUNDARY appears in
# TWO rows -- the value and the value next to it -- because one fixture cannot
# see both: `128.0`/`127.99999`, `-150.0`/`-149.99999`, `FLT_MIN` and
# `FLT_MIN*(1-1e-5)`, `30.0`/`29.999998`.
# ===========================================================================

# :9-11 `x.ne(inf).where(x.ne(x).where(nan, x.ne(-inf).where(ratio, _inf)), inf)`
# NOTE the middle arm: `x.ne(x)` is FALSE for every non-NaN, so `where` picks
# the RATIO arm there, and `nan` is chosen only when `x != x`.  Reading it as
# `is_eq(x, x) -> nan` inverts the whole table and makes every finite input NaN;
# MEASURED, that is exactly what it did.
# `x.ne(k).where(A, B)` picks A when `x != k`, so every arm reads
# `Bool.pick(is_eq(x, k), B, A)`.  Getting one of the three the other way round
# is MEASURED and loud: with the OUTER arm inverted, `tc.mask0` sends every
# finite input to the `inf` replacement and all three expansions answer NaN.
# `x.ne(inf)` is a BITWISE test, not an IEEE one.  MEASURED: tinygrad's
# `eq_const.CFloat` compares the packed bits (ops.bend:1406, and commit
# 65b585e1 for the same reason), so `-0.0 != 0.0` is TRUE there while IEEE says
# FALSE -- and `xf_lazy0_-0.0` is `-0.0`, not `+0.0`.  Reading it with `F32.is_eq`
# loses the sign of zero, and `xf_lazy0_-0.0` is the row that says so.
def tc.x_sign(+x: F32) -> F32:
  Bool.pick(F32, F32.is_eq(x, tc.zero()), tc.zero(),
            Bool.pick(F32, F32.is_lt(x, tc.zero()), tc.sign(True{}), 1.0))

# `x_abs >= switch_over` picks `payne_hanek_reduction` over
# `cody_waite_reduction` at :187.  This is the row that carries the 30.0
# boundary, because the VALUE past it is the W1 wall.
def tc.xsin_nan(+d: F32) -> F32:
  tc.lazy(d, tc.qnan(), tc.qnan(), tc.qnan(), tc.qnan())

# `xexp2` (:193-217): :200 mask, :201 `rintk`, :203 `s = x - q`, :209 the
# polynomial, :210 `ldexp2k`, :213/:215 the two clamps, :217 the NaN guard.
def tc.xsin_below(+x_abs: F32) -> Bool: F32.is_lt(x_abs, tc.f(sp.switch_over()))

# `xsin(d, fast=True)`: :181 `x_abs`, :182/:183 cody_waite + sin_poly_small,
# :189 restore the sign.  :191's NaN mask is `tc.xsin_nan` below.
def tc.xsin_fast(+d: F32) -> F32:
  +x = tc.mask0(d)
  +s = tc.x_sign(x)
  +a = F32.mul(x, s)
  F32.mul(tc.sps(Red.r(tc.cody_waite(a)), tc.cw_quadrant(a)), s)

# :191 `_lazy_map_numbers(d, nan, nan, nan, result)`
def tc.xexp2_up(+d: F32) -> Bool: F32.is_ge(d, tc.f(sp.xexp2_up_32()))
def tc.xexp2_lo(+d: F32) -> Bool: F32.is_lt(d, tc.f(sp.xexp2_lo_32()))
def tc.xexp2_nan(+d: F32) -> Bool: F32.is_eq(d, d)

# `xlog2` (:219-255).  MEASURED on a float32 UOp: EVERY node in the graph is
# float32, because `UOp.const`'s `weakfloat` (ops.py:1893) lets the consumer's
# dtype win -- so `d * (2.0 ** 64)` at :229 is a binary32 multiply and the
# denormal arm is NOT a float64 detour.
def tc.xexp2(+d: F32) -> F32:
  +x = tc.mask0(d)
  +q = tc.rintk(x)
  +u = tc.ldexp2k(tc.polyn(sp.exp32(), F32.sub(x, tc.i2f(q))), q)
  Bool.pick(F32, tc.xexp2_up(d), tc.pinf(),
            Bool.pick(F32, tc.xexp2_lo(d), tc.zero(),
                      Bool.pick(F32, tc.xexp2_nan(d), u, tc.qnan())))

# :213 `d >= upper`, :215 `d < lower`, :217 `d.ne(d)`
def tc.is_denorm(+d: F32) -> Bool: F32.is_lt(d, tc.f(sp.flmin_32()))

# :229 `a = is_denormal.where(d * (2.0 ** denormal_exp), d)`
def tc.xlog2_a(+d: F32, +den: Bool) -> F32:
  Bool.pick(F32, den, F32.mul(d, tc.f(sp.denorm_scale())), d)

# :231 `e = ilogb2k(a * (1.0 / 0.75))`
def tc.xlog2_e0(+a: F32) -> U32: tc.ilogb2k(F32.mul(a, tc.f(sp.one_over_075())))

# :232 `m = ldexp3k(a, -e)`.  `-e` is the TWO'S-COMPLEMENT negation of `e0` read
# back as a signed float, which is what `tc.i2f` then hands to `tc.ldexp3k`; and
# `tc.ldexp3k` takes the DIRECTION off that sign itself, so negating here and again
# in there is the one thing that must not happen.  MEASURED, passing `e0` unnegated
# gave `m = a * 2**e` and every `log2` came out a factor of two wrong.
def tc.xlog2_m(+a: F32, +e0: U32) -> F32: tc.ldexp3k(a, tc.i2f(tc.neg(0, e0)))

# :233 `e = is_denormal.where(e - denormal_exp, e)`
def tc.xlog2_e(+den: Bool, +e0: U32) -> F32:
  Bool.pick(F32, den, tc.i2f(tc.iadd(e0, tc.neg(0, sp.de_32()))), tc.i2f(e0))

# :235-236 `x = (m - 1)/(m + 1)`, `x2 = x*x`
def tc.xlog2_x(+m: F32) -> F32: F32.div(F32.sub(m, 1.0), F32.add(m, 1.0))

# :244 `r = t*(x*x2) + e + x*log2(e) + x*s_lo`.  LEFT-associated, because the
# two trailing terms share one `+` and f32 addition is not associative.
def tc.xlog2_r(+x: F32, +e: F32) -> F32:
  F32.add(F32.add(F32.mul(tc.polyn(sp.log32(), F32.mul(x, x)), F32.mul(x, F32.mul(x, x))), e),
          F32.add(F32.mul(x, tc.f(sp.nlog2e32())), F32.mul(x, tc.f(sp.s_lo32()))))

# :247-:255 the five guards, applied in source order.
def tc.xlog2.last(+rec: Bool, +r0: F32) -> F32:
  Bool.pick(F32, rec, tc.ninf(), r0)

# :247, :249, :251, :253, :255 as five separate predicates
def tc.xlog2_neinf(+d: F32) -> Bool: F32.is_eq(d, tc.pinf())
def tc.xlog2_nezero(+d: F32) -> Bool: F32.is_eq(d, tc.zero())
def tc.xlog2_neg(+d: F32) -> Bool: F32.is_lt(d, tc.zero())
def tc.xlog2_nan(+d: F32) -> Bool: Bool.not(F32.is_eq(d, d))
def tc.xlog2_recip(+d: F32) -> Bool: F32.is_eq(F32.div(1.0, d), tc.ninf())

# ===========================================================================
# `xpow` (:257-265).  W2: the `.log2()`/`.exp2()` in the middle are NATIVE ops,
# so only the pure half is claimed -- `non_int` (:261), `is_odd` (:262), the
# `exponent.eq(0)` short circuit (:265) and the `-base` at :259.
# ===========================================================================

# :261 `exponent != exponent.cast(int32).cast(exponent.dtype)`
# :255 `d.reciprocal().ne(-math.inf).where(r, r.const_like(-math.inf))` is
# `tc.xlog2.last` above.

def tc.xlog2(+d: F32) -> F32:
  +den = tc.is_denorm(d)
  +a = tc.xlog2_a(d, den)
  +e0 = tc.xlog2_e0(a)
  +r0 = tc.xlog2_r(tc.xlog2_x(tc.xlog2_m(a, e0)), tc.xlog2_e(den, e0))
  # :247-:255 as FIVE steps in SOURCE ORDER, each written the way the source
  # reads: `p.ne(X).where(a, b)` is `pick(not (p == X), a, b)`, so what the source
  # names FIRST is the TRUE arm.  :253 was spelled the other way round and `xlog2`
  # answered NaN for every finite argument -- MEASURED, `r0` for `d = 1.0` is 0
  # (0x00000000) and the answer was 0x7fc00000, so the fault is in the pick and
  # not in the polynomial.
  +r1 = tc.xlog2.last(tc.xlog2_recip(d), r0)
  +r2 = Bool.pick(F32, tc.xlog2_nan(d), tc.qnan(), r1)
  +r3 = Bool.pick(F32, tc.xlog2_neg(d), tc.qnan(), r2)
  +r4 = Bool.pick(F32, tc.xlog2_nezero(d), tc.ninf(), r3)
  Bool.pick(F32, Bool.not(tc.xlog2_neinf(d)), r4, tc.pinf())


def tc.xpow_non_int(+e: F32) -> Bool: Bool.not(F32.is_eq(e, tc.i2f(tc.f2i(e))))

# :262 `(exponent < 0).where(-exponent, exponent).cast(int32).mod(2).cast(bool)`
def tc.xpow_is_odd(+e: F32) -> Bool:
  U32.is_eq(U32.and(tc.f2i(tc.pick(F32.is_lt(e, tc.zero()), F32.neg(e), e)), 1), 1)

# :265 `exponent.eq(0)`
def tc.xpow_e_zero(+e: F32) -> Bool: F32.is_eq(e, tc.zero())

# :259 `(base < 0).where(-base, base)` and the :265 `(base < 0)` re-test
def tc.xpow_neg_base(+b: F32) -> Bool: F32.is_lt(b, tc.zero())
def tc.xpow_abs(+b: F32) -> F32: Bool.pick(F32, F32.is_lt(b, tc.zero()), F32.neg(b), b)

# The `xpow` fixtures the source answers WITHOUT evaluating a transcendental:
# `e == 0` gives `ret.const_like(1)` at :265, and `base == 0` gives
# `log2(0) = -Inf` times `e`, so `e > 0` underflows to 0 and `e < 0` overflows
# to +Inf.
def tc.xpow_special(+b: F32, +e: F32) -> F32:
  Bool.pick(F32, tc.xpow_e_zero(e), 1.0,
            Bool.pick(F32, F32.is_eq(b, tc.zero()),
                      Bool.pick(F32, F32.is_lt(e, tc.zero()), tc.pinf(), tc.zero()),
                      tc.qnan()))

# ===========================================================================
# `payne_hanek_reduction` (:66-113).  W1: the uint64 product at :103/:105 is
# NOT evaluated.  What IS here is every CONSTANT it reads and the u32 window
# arithmetic of `_take` (:88-92), a pure function of (i, e).
# ===========================================================================

# :84-86 `i = shr(e.cast(uint64), 5)`, `e = e & 31`, `offset = 32 - e`
def tc.ph_i(+e0: U32) -> U32: tc.shr_u(e0, 5)
def tc.ph_e31(+e0: U32) -> U32: U32.and(e0, 31)
def tc.ph_off(+e0: U32) -> U32: tc.neg(0, tc.ph_e31(e0))

# :88-92 `_take`: `count + offset < len(two_over_pi_f) - 1` is a COMPILE-TIME
# test over two Python ints, so the chain is `take_window - offset` deep and
# each level asks `i.ne(count)`.  The word chosen is `two_over_pi_f[k + offset]`
# for the FIRST `k` with `i == k`; when the chain is empty the seed
# `UOp.const(0, uint32)` survives untouched, which the 4294967295 answer says.
def tc.take_len(+off: U32) -> U32: U32.sub(sp.take_window(), off)

def tc.take_pick(+i: U32, +len: U32, +k: U32) -> U32:
  Bool.pick(U32, U32.is_ge(len, U32.inc(k)), k,
            Bool.pick(U32, U32.is_eq(i, k), k, 4294967295))

# ===========================================================================
# THE GATE.  One tag-dispatch over the rule being evaluated, then ONE list
# walker per row family, so no family is a copy of another with one line
# changed.
# ===========================================================================

# `tag` picks the rule; the fixture `s` is whatever that family's row names
# carry, so the walker needs no knowledge of the rule.
def tc.eval(+tag: U32, +s: String) -> U32:
  match tag:
    case 0: F32.bits(tc.sin_poly(tc.f(s)))
    case 1: F32.bits(tc.sin_poly(tc.f(s)))
    case 2: tc.shr_u(tc.u(s), 23)
    case 3: tc.shl(tc.u(s), 23)
    case 4: tc.rintk(tc.f(s))
    case 5: tc.ilogb2k(tc.f(s))
    case 6: F32.bits(tc.frexp_mant(tc.f(s)))
    case 7: tc.fexp(tc.f(s))
    case 8: F32.bits(Red.r(tc.cody_waite(tc.f(s))))
    case 9: Red.q(tc.cody_waite(tc.f(s)))
    case 10: F32.bits(tc.cw_qdh(tc.f(s)))
    case 11: F32.bits(tc.sps(tc.f(tc.dq0(s)), tc.f2i(tc.f(tc.dq1(s)))))
    case 12: F32.bits(tc.spl(tc.f(tc.dq0(s)), tc.f2i(tc.f(tc.dq1(s)))))
    case 13: F32.bits(tc.xsin_fast(tc.f(s)))
    case 14: F32.bits(tc.xexp2(tc.f(s)))
    case 15: F32.bits(tc.xlog2(tc.f(s)))
    case 16: F32.bits(tc.mask0(tc.f(s)))
    case 17: F32.bits(tc.lazy(tc.f(s), 7.0, F32.neg(7.0), 9.0, 3.0))
    case 18: F32.bits(tc.pow2if(tc.f2i(tc.f(s))))
    case 19: F32.bits(tc.ldexp2k(tc.f(tc.dq0(s)), tc.f2i(tc.f(tc.dq1(s)))))
    case 20: F32.bits(tc.ldexp3k(tc.f(tc.dq0(s)), tc.f(tc.dq1(s))))
    case 21: tc.fexp2(tc.f(s))
    case 22: tc.pow2if_word(tc.f2i(tc.f(s)))
    case 23: F32.bits(tc.xpow_special(tc.f(tc.dq0(s)), tc.f(tc.dq1(s))))
    case 24: tc.bit(tc.xpow_non_int(tc.f(tc.dq1(s))))
    case 25: tc.bit(tc.xpow_is_odd(tc.f(tc.dq1(s))))
    case 26: tc.bit(tc.xpow_e_zero(tc.f(tc.dq1(s))))
    case 27: tc.bit(tc.xpow_neg_base(tc.f(tc.dq0(s))))
    case 28: tc.bit(tc.xexp2_up(tc.f(s)))
    case 29: tc.bit(tc.xexp2_lo(tc.f(s)))
    case 30: tc.nebit(tc.f(s), tc.f(s))
    case 31: tc.bit(tc.is_denorm(tc.f(s)))
    case 32: tc.nebit(tc.f(s), tc.pinf())
    case 33: tc.bit(Bool.not(tc.xlog2_nezero(tc.f(s))))
    case 34: tc.bit(tc.xlog2_neg(tc.f(s)))
    case 35: tc.nebit(tc.f(s), tc.f(s))
    case 36: tc.bit(Bool.not(tc.xlog2_recip(tc.f(s))))
    case 37: tc.bit(tc.xsin_below(F32.abs(tc.f(s))))
    case 38: tc.nebit(tc.f(s), tc.pinf())
    case 39: tc.nebit(tc.f(s), tc.ninf())
    case 40: tc.nebit(tc.f(s), tc.f(s))
    case 41: tc.nebit(tc.f(s), tc.zero())
    case 42: tc.bit(F32.is_lt(tc.f(s), tc.zero()))
    case _: 4294967295
    case _: 4294967295

def t_of.go(+xs: List<&2, String>, +tag: U32, +pref: String) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("")
    case s <> t:
      do IO<Unit>:
        urow(String.concat([pref, s]), tc.eval(tag, s))
        t_of.go(t, tag, pref)

def t_of(+tag: U32, +pref: String, +xs: List<&2, String>) -> IO(Unit):
  t_of.go(xs, tag, pref)

# the coefficient tables: index -> value AND value -> index, plus the exact
# decimal as TEXT (`cd_*`).
# The element comes from the PATTERN (`y`), not from `List.get(xs, i)`.  That is
# measured, not stylistic: `List.get` CONSUMES one level of the list, so reading
# element i and then searching the same list in the same body walks a list that
# has already been partly consumed -- MEASURED, it answers element 2i and then
# `None`.  `raw` is re-split for the reverse lookup so that search gets a FRESH
# list, which is the only way a linear list supports two readers.
def t_tab.walk(+xs: List<&2, String>, +raw: String, +nm: String, +pref: String, +i: U32) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("")
    case y <> t:
      +b = F32.bits(tc.f(y))
      do IO<Unit>:
        urow(String.concat([pref, nm, "_", U32.show(i)]), b)
        urow(String.concat(["xv_", nm, "_", U32.show(b)]),
             tc.vi(String.split(raw, '|'), b, 0))
        srow(String.concat(["cd_", nm, "_", U32.show(i)]), y)
        t_tab.walk(t, raw, nm, pref, U32.inc(i))

def t_tab(+xs: List<&2, String>, +raw: String, +nm: String) -> IO(Unit):
  t_tab.walk(xs, raw, nm, "xf_", 0)

# `two_over_pi_f` is an INTEGER table, and it is the one table tinygrad writes in
# HEX (transcendental.py:77), so each element carries BOTH readings and the row
# prints both: `xf_`/`cu_` the value and `cx_` the 0x SPELLING as generated text.
# The hex is generated rather than printed from the value on purpose -- deriving
# it here would make it a change-detector of `cu_`, and reading a digit PAIR in
# decimal is exactly the reading that is NOT independent.
def t_u.pair(+p: List<&2, String>, +raw: String, +nm: String, +i: U32) -> IO(Unit):
  match p:
    case Nil{}: IO.print("")
    case d <> rest:
      match rest:
        case Nil{}: IO.print("")
        case h <> rest2:
          +b = tc.u(d)
          do IO<Unit>:
            urow(String.concat(["xf_", nm, "_", U32.show(i)]), b)
            urow(String.concat(["cu_", nm, "_", U32.show(i)]), b)
            srow(String.concat(["cx_", nm, "_", U32.show(i)]), h)
            urow(String.concat(["xv_", nm, "_", U32.show(b)]),
                 tc.uvi(String.split(raw, '|'), b, 0))
            t_u.pair(rest2, raw, nm, U32.inc(i))

# `_len` is the ELEMENT count, and it is a row because `xf_sp.topi_len` IS the
# `count+offset < len(two_over_pi_f)-1` window test at :90 in its only readable
# form.  `nm` is the raw table, split FRESH here: a `List<&2, A>` supports TWO
# reads (MEASURED -- a third answers `None`), and the walk above spends both on
# the pair, so the reverse lookup needs a list of its own.
def t_u(+xs: List<&2, String>, +raw: String, +nm: String) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["xf_", nm, "_len"]), U32.div(tc.ilen(xs), 2))
    t_u.pair(xs, raw, nm, 0)


# THE FLOAT SCALARS, ONE ROW PAIR EACH: `xf_` is the binary32 the lane uses and
# `cd_` is the exact float64 DECIMAL, and they are printed out of ONE pair of
# elements of `sp.fscal()` so the two readings cannot drift apart -- a missing
# one would be a missing PAIR, which a name-only diff cannot see.  Bend has no
# `F64`, so for every float64 coefficient in transcendental.py the `cd_` text IS
# the strongest handle there is, and this is the row that closes TODO.md round
# 4's "the float64 coefficient literals are NOT independently verified".
#
# THE SHAPE IS MEASURED, not chosen.  `sp.fscal()` is a FLAT list of
# `name|decimal|name|decimal|...` and it is walked TWO AT A TIME, because a
# `List<&2, A>` supports exactly TWO reads: MEASURED, a third read of one list
# answers `None`.  A scalar needs three -- the name, the decimal as TEXT, and
# `F32.bits` of it -- so a list of `name|decimal` ELEMENTS is impossible (the
# split spends both reads on the element) and the only shape that fits is one
# split of the whole table walked in pairs.  Getting this wrong is silent: every
# `cd_` row came out with the VALUE as its name and every `xf_` row 0.
def t_fscal.pair(+p: List<&2, String>) -> IO(Unit):
  match p:
    case Nil{}: IO.print("")
    case nm <> rest:
      match rest:
        case Nil{}: IO.print("")
        case v <> rest2:
          do IO<Unit>:
            srow(String.concat(["cd_", nm]), v)
            urow(String.concat(["xf_", nm]), tc.b(v))
            t_fscal.pair(rest2)

# THE INTEGER SCALARS, likewise paired with their 0x SPELLING, and the dtype
# tables each `rintk`/`pow2if`/`ilogb2k`/`ldexp3k`/`frexp` selects, which are
# TEXT because the answer is a `dtypes.X` in Python and there is no dtype to hold
# one here.  `xf_ph_*`/`xf_take_len_*`/`xf_*_word_*` are not constants: they are
# the computed claims (the :88-92 window, the :61 bitfield, the :45 exponent
# field) and they are listed explicitly for that reason.
def t_scalars() -> IO(Unit):
  do IO<Unit>:
    t_fscal.pair(sp.fscal())
    # THE MISS.  `tc.vi`/`tc.uvi` answer the sentinel only when the bit pattern is
    # NOT in the table, and every other `xv_*` row is a hit, so the sentinel was
    # unreachable and unobservable: M35 (sentinel -> 0) moved nothing.  12345 is
    # not a bit pattern of any element of either table, which is the fixture's
    # whole content.
    urow("xv_sp.sin32_miss", tc.vi(sp.sin32(), 12345, 0))
    urow("xv_sp.topi_miss", tc.uvi(sp.topi(), 12345, 0))
    urow("xf_qdh_scale", F32.bits(tc.qdh_scale()))
    urow("xf_frexp_word_1.5", tc.frexp_word(tc.f("1.5")))
    urow("xf_ldexp3k_word_1.5_3", tc.ldexp3k_word(F32.bits(tc.f("1.5")), 3))
    urow("xf_ph_i_127", tc.ph_i(127))
    urow("xf_ph_e31_127", tc.ph_e31(127))
    urow("xf_ph_off_127", tc.ph_off(127))
    urow("xf_take_len_6", tc.take_len(6))
    urow("xf_xsin_nan_inf", F32.bits(tc.xsin_nan(tc.pinf())))
    urow("xf_xsin_nan_1.0", F32.bits(tc.xsin_nan(tc.f("1.0"))))
    urow("cu_q_shift", sp.q_shift())
    srow("cx_q_shift", sp.q_shift_hex())
    urow("cu_take_window", sp.take_window())
    srow("cx_take_window", sp.take_window_hex())
    urow("cu_mb_32", sp.mb_32())
    srow("cx_mb_32", sp.mb_32_hex())
    urow("cu_eb_32", sp.eb_32())
    srow("cx_eb_32", sp.eb_32_hex())
    urow("cu_em_32", sp.em_32())
    srow("cx_em_32", sp.em_32_hex())
    urow("cu_mb_16", sp.mb_16())
    srow("cx_mb_16", sp.mb_16_hex())
    urow("cu_eb_16", sp.eb_16())
    srow("cx_eb_16", sp.eb_16_hex())
    urow("cu_em_16", sp.em_16())
    srow("cx_em_16", sp.em_16_hex())
    urow("cu_de_32", sp.de_32())
    srow("cx_de_32", sp.de_32_hex())
    urow("cu_frac_mask", sp.frac_mask())
    srow("cx_frac_mask", sp.frac_mask_hex())
    urow("cu_fm1_32", sp.fm1_32())
    srow("cx_fm1_32", sp.fm1_32_hex())
    urow("cu_fm2_32", sp.fm2_32())
    srow("cx_fm2_32", sp.fm2_32_hex())
    urow("cu_fm1_16", sp.fm1_16())
    srow("cx_fm1_16", sp.fm1_16_hex())
    urow("cu_fm2_16", sp.fm2_16())
    srow("cx_fm2_16", sp.fm2_16_hex())
    urow("cu_mb_64", sp.mb_64())
    srow("cx_mb_64", sp.mb_64_hex())
    # the SIXTY-FOUR-BIT words are carried hi/lo because `1 << 34` saturates to
    # zero, and only the halves that a u32 can hold are rows -- the full word is
    # the audit file's column 2 and column 4.
    urow("cu_p_mask.hi", sp.p_mask_hi())
    urow("cu_p_mask.lo", sp.p_mask_lo())
    urow("cu_fm1_64.hi", sp.fm1_64_hi())
    urow("cu_fm1_64.lo", sp.fm1_64_lo())
    urow("cu_fm2_64.hi", sp.fm2_64_hi())
    urow("cu_fm2_64.lo", sp.fm2_64_lo())
    urow("cu_mant64.hi", sp.mant64_hi())
    urow("cu_mant64.lo", sp.mant64_lo())
    urow("cu_eb64.hi", sp.eb64_hi())
    urow("cu_eb64.lo", sp.eb64_lo())
    urow("cu_em64.hi", sp.em64_hi())
    urow("cu_em64.lo", sp.em64_lo())
    srow("tx_dt.transcendental", tx_dt.transcendental_t())
    srow("tx_dt.rintk_f64", tx_dt.rintk_f64_t())
    srow("tx_dt.rintk_f32", tx_dt.rintk_f32_t())
    srow("tx_dt.rintk_f16", tx_dt.rintk_f16_t())
    srow("tx_dt.pow2if_i64", tx_dt.pow2if_i64_t())
    srow("tx_dt.pow2if_i32", tx_dt.pow2if_i32_t())
    srow("tx_dt.pow2if_i16", tx_dt.pow2if_i16_t())
    srow("tx_dt.ilogb2k_f64", tx_dt.ilogb2k_f64_t())
    srow("tx_dt.ilogb2k_f32", tx_dt.ilogb2k_f32_t())
    srow("tx_dt.ilogb2k_f16", tx_dt.ilogb2k_f16_t())
    srow("tx_dt.ldexp3k_f64", tx_dt.ldexp3k_f64_t())
    srow("tx_dt.ldexp3k_f32", tx_dt.ldexp3k_f32_t())
    srow("tx_dt.ldexp3k_f16", tx_dt.ldexp3k_f16_t())
    srow("tx_dt.frexp_u_f64", tx_dt.frexp_u_f64_t())
    srow("tx_dt.frexp_u_f32", tx_dt.frexp_u_f32_t())
    srow("tx_dt.frexp_u_f16", tx_dt.frexp_u_f16_t())
    srow("tx_dt.pow2if_param", tx_dt.pow2if_param_t())

def main() -> IO(Unit):
  do IO<Unit>:
    t_tab(sp.sin32(), sp.sin32_raw(), "sp.sin32")
    t_tab(sp.sin64(), sp.sin64_raw(), "sp.sin64")
    t_tab(sp.exp32(), sp.exp32_raw(), "sp.exp32")
    t_tab(sp.exp64(), sp.exp64_raw(), "sp.exp64")
    t_tab(sp.log32(), sp.log32_raw(), "sp.log32")
    t_tab(sp.log64(), sp.log64_raw(), "sp.log64")
    t_u(sp.topi(), sp.topi_raw(), "sp.topi")
    t_scalars()
    # ONE `t_of` PER ROW-NAME PREFIX, and the fixture list is named after the
    # prefix it came from.  `main` used to pass ONE list per TAG, so the
    # `m_`/`e_`/`r_`/`q_`/`sp_` sub-prefix rode along inside the fixture and the
    # row came out `xf_frexp_m_m_0.5`: 22 real rows MISSING and 22 mangled ones
    # EXTRA, which a name-only diff cannot tell from a right answer.
    t_of(0, "xf_sin_poly_", fx.sinpoly())
    t_of(1, "xf_polyn32_", fx.sinpoly())
    t_of(2, "xf_shr23_", fx.shr())
    t_of(3, "xf_shl23_", fx.shl())
    t_of(4, "xf_rintk_", fx.rintk())
    t_of(5, "xf_ilogb2k_", fx.ilogb())
    t_of(6, "xf_frexp_m_", fx.frexp_m())
    t_of(7, "xf_frexp_e_", fx.frexp_e())
    t_of(8, "xf_cody_waite_r_", fx.cw_r())
    t_of(9, "xf_cody_waite_q_", fx.cw_q())
    t_of(10, "xf_cw_qdh_", fx.cw_q())
    t_of(11, "xf_sps_", fx.sps())
    t_of(12, "xf_spl_", fx.spl())
    t_of(13, "xf_xsin_fast_", fx.xsinfast())
    # `xsin(fast=False)` below `switch_over` computes exactly `sin_poly_small` of
    # the SAME cody_waite reduction as `fast=True`, so the row set is tag 13 and
    # these 11 rows pin the two branches together rather than W1.
    t_of(13, "xf_xsin_slow_small_", fx.xsinslow())
    t_of(14, "xf_xexp2_", fx.xexp2())
    t_of(14, "xf_xexp2_sp_", fx.xexp2sp())
    t_of(15, "xf_xlog2_", fx.xlog2())
    t_of(15, "xf_xlog2_sp_", fx.xlog2sp())
    t_of(16, "xf_lazy0_", fx.lazy())
    t_of(17, "xf_lazy1_", fx.inf())
    t_of(18, "xf_pow2if_", fx.pow2if())
    t_of(19, "xf_ldexp2k_", fx.ldexp())
    t_of(20, "xf_ldexp3k_", fx.ldexp())
    t_of(21, "xf_fexp2_", fx.special())
    t_of(22, "xf_pow2if_word_", fx.pow2if())
    t_of(23, "xf_xpow_", fx.xpowval())
    t_of(24, "xp_xpow_non_int_", fx.xpowp())
    t_of(25, "xp_xpow_is_odd_", fx.xpowp())
    t_of(26, "xp_xpow_e_zero_", fx.xpowp())
    t_of(27, "xp_xpow_neg_base_", fx.xpowp())
    t_of(28, "xg_xexp2_ge_up_", fx.g())
    t_of(29, "xg_xexp2_lt_lo_", fx.g())
    t_of(30, "xg_xexp2_nan_", fx.g())
    t_of(31, "xg_xlog2_denorm_", fx.g())
    t_of(32, "xg_xlog2_neinf_", fx.g())
    t_of(33, "xg_xlog2_nezero_", fx.g())
    t_of(34, "xg_xlog2_neg_", fx.g())
    t_of(35, "xg_xlog2_nan_", fx.g())
    t_of(36, "xg_xlog2_recip_", fx.g())
    t_of(37, "xg_xsin_below_", fx.g())
    t_of(38, "xg_lazy_ne_inf_", fx.g())
    t_of(39, "xg_lazy_ne_ninf_", fx.g())
    t_of(40, "xg_lazy_ne_self_", fx.g())
    t_of(41, "xg_lazy_nz_", fx.g())
    t_of(42, "xg_lazy_lt0_", fx.g())
    IO.print("ts-done=1")
