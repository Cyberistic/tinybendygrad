import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/helpers.bend"

EDITS = [
  # ansistrip -- the THREE MEASURED substrate limits and the RESIDUAL DIVERGENCE. The state
  # table and the "three ways a run ends" enumeration are the code's own shape.
  (1065, 1121, """# ansistrip -- `re.sub('\\x1b\\[(K|.*?m)', '', s)` (helpers.py:48).
#
# the regex matches a run of arbitrary length, so nothing may decide before the RUN'S END IS
# SEEN. `.*?m` is non-greedy and unbounded: a walker that emits as it goes has already emitted
# too much by the time it learns whether the sequence was `K` or `31m`. Bend 2.0.34 offers no
# way to look ahead, and all three of these are MEASURED:
#
#   * forward references are rejected outright -- "expected : a filled definition (an unfilled
#     law is a dead claim: live code cannot use it)". So a state machine may NOT be split into
#     a driver and a stepper: that is mutual recursion and it does not compile. ONE def, ONE
#     recursion, ONE table.
#   * a `case`-bound list TAIL IS LINEAR -- "expected : t, observed : t (consumed more than
#     once)" -- so a look-ahead over the rest of the input and a walk over the rest of the input
#     cannot both live in one arm.
#   * a self-call argument must be a SYNTACTIC TAIL -- "expected : a decreasing self-call" --
#     so neither `String.drop(s, n)` nor `List.append(t, [h])` may step the cursor by more than
#     one character.
#
# so the run is emitted optimistically and un-emitted on a match. `acc` is REVERSED, so
# prepending is O(1) and a run's characters are already on TOP of `acc` when its terminator
# arrives: dropping the run is `List.drop(acc, n)` for the count `n` of characters put there.
# One pass, no look-ahead, no flush, no re-scan, no rollback.
#
# The state is two def PARAMETERS and not a record, because `Nat` and `List` are both linear and
# a `case`-bound name may be used ONCE: a record pattern that binds `n` cannot also name `n` in
# the arm ("expected : n, observed : n (consumed more than once)"). So `acc`, `n` and `q` are
# passed through and never matched:
#
#   q = 0n  normal
#   q = 1n  an ESC is pending and has emitted nothing yet
#   q = 2n  inside a run whose body is still empty
#   q = 3n  inside a run with at least one body character
#
# `q` is a match position, and the char code is folded into the LIST pattern as `Chr{27}`,
# because a Bend `match` may only scrutinise a def parameter or a record FIELD -- never
# `Char.to_u32(h)` ("a match cannot scrutinize a computed value") and never a `case`-bound
# binder ("this name is a def or a consumed binder"). A `Nat` in a multi-scrutinee position is
# also checked for exhaustiveness while a `Nat` inside a record pattern is not, which is the
# whole of why the state is parameters.
#
# MEASURED against CPython on a 43-fixture corpus (`.agents/slop/ansi_oracle.py` vs
# `.agents/slop/ansi_probe.bend`, gate `.agents/slop/ansi_gate.py`): 28 of 43 rows were red
# before this rewrite.
#
# THE ONE RESIDUAL DIVERGENCE, and it is a wall rather than an oversight. A run that FAILS
# (newline before the terminator, or end of input) must be re-read by `re.sub` from its '[' --
# and a body can itself contain a complete `ESC[K`, which that re-read strips. This walk
# cannot re-read: the body has already been emitted and would have to be read a second time,
# and a list tail is linear. So the body is emitted verbatim."""),

  # i64_shr -- the FOUR TERMS and the MEASURED PLANTS. The LAST paragraph is the difference
  # from i64_shl and it is the fact.
  (1693, 1752, """# the right shift, and it is arithmetic. `tinygrad/uop/ops.py:1429` binds `Ops.SHR` to
# `operator.rshift`, which on a CPython int IS the sign-extending (floor) shift, and
# `tinygrad/codegen/decomp/dtype.py:48` says it twice -- "vacated high word: sign bits when
# signed, else 0" and `fill = a1 >> 31 if dt == dtypes.int else zero`. So SHR of an `int64`
# extends the sign and SHR of a `uint64` does not, and the two differ on exactly one bit
# pattern: the sign. `i64_shr` IS the arithmetic one, because the pair is signed (`i64_is_neg`
# reads bit 63 of the high word) -- a logical `int64` shift does not exist upstream, and the
# unsigned reading is a `BITCAST` away rather than a second def.
#
# THE FOUR TERMS, for `k <= 32`, and each one is necessary:
#     lo' = (lo >> k) | (hi << (32-k))    the low word keeps lo's top bits and receives
#                                         hi's low `k` bits, which is the ONLY place the
#                                         high word reaches the low one
#     hi' = (hi >> k) | (fill << (32-k))  the high word keeps hi's top bits and receives
#                                         the SIGN repeated, which is what makes the shift
#                                         arithmetic
#
# the fill is invisible on every non-negative value, which is half the fixture set and the
# reason half of it cannot see a deleted fill: the fill is `0` when the high word's bit 31 is
# clear, so dropping it changes nothing for `zero`, `one` or `max` and everything for `neg1`,
# `signmin` or `spill`. Planted and MEASURED: 18 of 301 rows move, all six on those three
# values, `.agents/slop/ishr/plant.py` P1. `spill` is what makes the remaining four terms
# load-bearing -- its high word is negative AND not all ones AND its bit 0 is set, so at
# `k = 1` all four terms are individually necessary.
#
# the sign fill is needed in both words for `k > 32`, and omitted for `k <= 32`. This is the
# whole asymmetry with `i64_shl` and it is a property of the BIT INDEXES, not a choice. Bit `j`
# of the result is bit `j+k` of `x` while `j+k <= 63`, and the sign after that. The HIGH word
# is bits 32..63, so for every `k` it is past the top of `x` and is ALL fill. The LOW word is
# bits 0..31: for `k <= 32` all of `j+k` is at most 63, so the low word holds REAL bits and no
# fill at all; for `k > 32` its top `k-32` bits are past the top of `x` and are fill too.
# Writing the fill into the high word only is the plausible version and it is WRONG for every
# amount above 32 -- `i64_shr(-1, 33)` comes out `0xFFFFFFFF:0x00000000` where the answer is
# `0xFFFFFFFF:0xFFFFFFFF`. Gate row `sr_neg1_3`, amount 33; planted as P2, and 36 of 301 rows
# move, NOT ONE of them at an amount at or below 32 -- which is the 60 cells that
# implementation still gets right.
#
# `k == 0` and `k == 32` are the two amounts WHERE the two forms meet, and both are answered by
# the SAME arm, so the test is `k <= 32` and not `k < 32`: at 32 the low word is `hi >> 0 |
# hi << 0 = hi` and the high word is the fill alone.
#
# FOR `k > 32` NOTHING OF `lo` SURVIVES -- `lo` supplies only the bits that land in the high
# word's bottom `k-32` positions -- so this is the mirror of `i64_shl`'s "FOR `k >= 32` the
# high WORD comes from `lo` and only from `lo`", and, as there, `Nat.sub` TRUNCATES so the
# eagerly-evaluated other arm of the `Bool.pick` is harmless.
#
# the fill amount past 64 is `Nat.sub` truncation, not a clamp, and it is right by the WIDTH
# LAW: for every `k >= 64` the answer is the fill, and `Nat.sub(32n, k-32)` is 0 there, so
# `U32.shln(fill, 0n)` is the fill -- the saturation `U32.shln` would have done is never
# reached, and both agree anyway.
#
# there is no width boundary, which is WHERE this differs from `i64_shl`. `x >> k` is
# `floor(x / 2k)`, so `|x >> k| <= |x| <= 2**63` for every `k <= 63` and for every `k >= 64` it
# is `-1` (x < 0) or `0` (x >= 0) -- ALL IN RANGE. So this def is EXACT AT EVERY `Nat` AMOUNT
# for every `int64`, the answer is always representable as the pair, and there is nothing to
# check: no `Maybe`, no wider carrier, no `u1`. `i64_shl` grows in magnitude and loses the top
# bit past `k + bit_length(x) <= 63`; a right shift cannot. `U32.shrn` SATURATES to 0 past 31,
# which is what supplies the `0` in `lo' >= 64` and the whole of the `k >= 64` answer for a
# non-negative `x`, and `match_hi` supplies the `-1`."""),

  # `Target` -- the IMPORT CYCLE and the ORDER. The FIRST paragraph is a restatement.
  (2630, 2669, """# `Target` -- tinygrad/helpers.py:197-220. the dev target, and upstream puts IT HERE.
#
# why this file, and not the two that wanted it. the import graph decides, and IT IS A CYCLE,
# AND IT IS MEASURED:
#
#   * upstream's `helpers.py:198` DEFINES `Target`, and upstream's `uop/ops.py:13` and
#     `runtime/ops_python.py:9` both IMPORT it from there. The port mirrors upstream's
#     directory layout, so the port's `helpers.bend` is the mirror of the file upstream defines
#     it in, and `uop/ops.bend` and `runtime/ops_python.bend` -- which BOTH already import this
#     file as `H` -- are the two consumers.
#   * `runtime/ops_python.bend` imports `../uop/ops.bend`, so `uop/ops.bend` CANNOT import
#     `runtime/ops_python.bend`: the edge would close a cycle and the compiler refuses it.
#     MEASURED, not remembered -- `.agents/slop/programinfo/a.bend` imports `b.bend` and
#     `b.bend` imports `a.bend`, and the compiler answers "an import cycle through ...".
#   * THIS FILE IS A LEAF -- it imports `Base` and nothing else -- so both consumers can
#     import it without closing an edge. THAT IS THE WHOLE reason it is here and not in either
#     of them.
#
# two copies is the defect this file closes. `runtime/ops_python.bend` held one `Target` (the
# record, its accessors and the DEV parser) and `uop/ops.bend` held another (the record and
# `Target.of()`), and the two were DIFFERENT TYPES with the same five fields: a parsed target
# could not go into a `ProgramInfo`, and the two could drift apart with nothing noticing. There
# is ONE record now, and there is NO CONVERSION between them, because there is nothing to
# convert: upstream's order is `device, renderer, arch, interface, indices` and the port's is
# `device, renderer, arch, iface, indices` -- ONE NAME differs (`interface` is spelled `iface`
# here) and the ORDER IS UPSTREAM'S. A conversion between two records with the same field names
# in the same order is a no-op that can only ever be wrong SILENTLY, so there is not one.
#
# the order is the arm that matters, and it is a silent one. Two records with the same five
# field NAMES in a different order are not interchangeable: a positional construction puts the
# values in the wrong slots, a positional pattern (`eq_target`, `uop/ops.bend`) compares the
# wrong pairs, and nothing complains. The order is therefore stated once, HERE, and every
# construction and every pattern in the port uses this one."""),

  # trange -- the U32 wall and the `disable` DEFAULT.
  (2551, 2579, """# trange -- `def trange(n:int, kwargs) -> tqdm[int]`, helpers.py:619
#
# The entire body is `return tqdm(range(n), total=n, kwargs)`, so a `trange` IS its `range(n)`
# with a total attached, and there are no `kwargs` to pass: every call site in tinygrad is a
# bare `trange(k)` (`examples/beautiful_mnist.py:39` is the one this block was added for).
# `Tqdm` therefore holds exactly what `trange` supplies: the sequence and the total.
#
# `Tqdm.t` IS THE TOTAL, and the name is upstream's: `tqdm.__init__` (:587) does `self.st,
# self.i, self.n, self.skip, self.t = ..., total`. There is no `total` ATTRIBUTE -- the first
# draft of the oracle hand-typed `t.total` and CPython answered `AttributeError: 'tqdm' object
# has no attribute 'total'`, which is why every row here is generated by calling the def
# instead of by reading it.
#
# The parameter is `U32`, which is the wall. CPython's `n` is an `int` and `trange(-3)` answers
# `t.t == -3` with an EMPTY sequence, because `range(-3)` is empty while `total=-3` is a real,
# negative integer; `base.bend` declares `Nat`, `U32` and `F32` and no signed type, so the port
# does not have a way to hold that and `trange(-3)` is a TYPE ERROR rather than a silent
# 4294967293. Strengthening the argument is the same answer `head :: NonEmpty a -> a` gives,
# and the cost is that one upstream input is unrepresentable rather than wrong.
#
# `tqdm`'s presentation state -- `disable`, `desc`, `unit`, `rate`, `n`, `i` and the bar itself
# -- is NOT PORTED, and `trange` does not invent it. One measured consequence is worth
# recording because it is counter-intuitive: `tqdm.__init__`'s `disable` DEFAULT is `False`,
# not `None` (:585), so the `sys.stderr.isatty()` arm is never taken by `trange` and the bar IS
# drawn into a pipe. That is why `.agents/slop/helpers-tc-gate.sh` compares stdout only, and why
# the oracle's `disable` / `desc` / `unit` / `rate` rows go to stderr."""),

  # get_shape -- the THREE OUTCOMES.
  (571, 583, """# get_shape -- `def get_shape(x) -> tuple[int, ...]`
#
# DEVIATION, stated: Python walks any object with `__len__` and `__getitem__`, and NOTE `str` is
# special because iterating it still yields strs. Bend has no duck typing, so the input is the
# `Nest` tree below: `Ns` is a scalar, `Nl` is a sequence -- the same information Python reads
# off the object, made explicit at the boundary.
#
# Python returns () for a scalar, for a string, and for an object whose `.shape` is (); it
# raises ValueError for an inhomogeneous shape. Those are three outcomes, so they are three
# constructors and none of them is a silent None. A sequence of scalars is NOT (): get_shape([1,2])
# is (2,) and get_shape([]) is (0,)."""),
]

apply(F, EDITS)
