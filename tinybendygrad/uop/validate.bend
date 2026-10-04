# validate.bend -- tinygrad/uop/validate.py.
#
# WHAT THIS FILE IS, because the unit brief said otherwise and was wrong.
# The brief called `validate.py` "the SPEC gate: it is what turns 'the graph is
# well-formed' into a decidable predicate, and it is the only place a malformed
# UOp is caught before it reaches codegen". THAT IS `uop/spec.py`
# (`type_verify`, which raises `RuntimeError(f"UOp verification failed at {i} on
# {u.op} ...")`). `validate.py` is a different thing: it is the **z3 out-of-bounds
# index checker**, entered from `spec.py:27` as the LAST step of
# `validate_index`, and it is the only file in tinygrad that calls a solver.
# The port below is a bounds checker front end, and the report says so.
#
# ---------------------------------------------------------------------------
# VIOLATIONS AS A LIST, NOT A Bool. The brief asked which to choose and why. The
# answer is a LIST, and it is not a preference -- it is three MEASURED facts
# about what CPython does with its own `-> bool`:
#
#  1. `validate_index_with_z3` RETURNS `False` FOR BOTH `sat` AND `unknown`
#     (validate.py:97-100). The two branches print DIFFERENT text --
#     `# OUT OF BOUNDS ACCESS: at {model} ...` versus
#     `# UNKNOWN RESULT FROM Z3: {reason_unknown()} ...` -- and they want
#     opposite responses: `sat` is a bug in the kernel, `unknown` is a weaker
#     check. A `Bool` throws the distinction away; a list of two texts keeps it.
#     That is the whole argument and it needs no new machinery.
#  2. The third outcome is not a return at all. `uops_to_z3:87` does
#     `raise NotImplementedError(f"{u.op} is not supported by z3")`, and
#     `{u.op}` prints as `Ops.X` because `FastEnum.__str__` is preserved -- which
#     is `O.Ops.name`. MEASURED: `UOp(Ops.STACK, src=(const 2, const 3))` gives
#     exactly `NotImplementedError: Ops.STACK is not supported by z3`. A
#     violation list absorbs a raise; a `Bool` cannot.
#  3. The `sat` text is `# OUT OF BOUNDS ACCESS: at {solver.model()} ...`, and
#     `solver.model()` is a SOLVER OUTPUT. So the violation is only PARTIALLY
#     portable: the CONSTRAINT LIST, `idx=` and `mask=` are pure functions of
#     the renderer and are ported and string-diffed here; the model is not, and
#     `vd_go`'s `RErr` for it is a named TODO rather than a guess.
#
# The list is `List<&2, String>` and one violation is one message. CPython
# STOPS at the first unsupported op; this walks the whole list, so the FIRST
# element is the one CPython reports and the rest are extra. That is a
# deliberate strengthening, it is in the header of `vz_go`, and `n_unsup_two`
# is the count row that pins it.
#
# ---------------------------------------------------------------------------
# THE SOLVER IS NOT PORTED, and this is the wall rather than a TODO with a plan.
# `solver.check((z3_idx<0)|(sz<=z3_idx))` decides satisfiability over UNBOUNDED
# integer arithmetic, and `z3_bv` adds bit-blasting at a width chosen per node.
# Bend has `Nat` (unary, capped at 2^48-1), `U32` (wraps mod 2^32) and `F32`.
# There is no unbounded integer, no bit-vector sort, and no decision procedure;
# a satisfiability check is not a total function this port can write. The whole
# rest of the file -- the eight z3 term builders, the ten renderer rules, the
# gated toposort, and the constraint text -- IS a total function and IS
# ported. So the boundary is exactly: this file renders the problem and prints
# it, and answering it is `solver.check`. See `vd_go`'s RErr arm.
#
# ---------------------------------------------------------------------------
# WHAT `ctx` CARRIES HERE, which is the one structural deviation. Python's is
# `ctx = (solver, z3map)`. This file's `Sol` is `{cs, es, ms}`: the assertion
# list, the `z3map`, and a MIN/MAX TABLE. The third component is not in Python
# because Python reads `UOp.vmin` / `UOp.vmax`, and `_min_max` is P3 work owned
# by `uop/fold.bend` (fold.bend:2482, "the wall is arithmetic, not the fold").
# Passing it in the context is the honest spelling: the renderer needs the
# bounds, the bounds are not computable here yet, and a node whose bounds are
# absent gets a VIOLATION rather than a guessed bound. `vz_mm` answers CONST
# from its own arg, so only non-CONST bounds wait on `_min_max`.
#
# ---------------------------------------------------------------------------
# `_min_max` BLOCKS MORE THAN ITSELF. `spec.py:23` reads `idx.vmin` and
# `idx.vmax` for the fast path, and `z3_bv`/`z3_shift` need per-operand bounds
# for the BV width and the shift amount, so this file cannot render a gate with
# a `&` or a `<<` in it until `fold.bend` grows the fold. `dv_bitcast_21` is
# the row that shows the width (`1 + max bit length of the operands' bounds`)
# being read out of the table, and `n_dv_width_8` is the count that pins it.
#
# ---------------------------------------------------------------------------
# THE GATE IS z3's OWN `str()`, STRING-DIFFED. Not a boolean about a string:
# every row prints the constraint list verbatim, e.g.
# `[And(i >= 0, i <= 15), True]` and `[And(r0 >= 0, r0 <= 100 - 1), True]`,
# and the oracle is CPython's own `str(solver)` from `uops_to_z3`. Reproducing
# z3's pretty printer is three measured rules and they are in `Z.str`:
#   * `a <= b` with a NUMERAL on the RIGHT prints `b >= a`; with the numeral on
#     the left it is unchanged. So `0 <= i` is `i >= 0` and `-5 <= i` is
#     `-5 <= i`. `ZLe` implements exactly that.
#   * `a < b` with a numeral on the LEFT prints `b > a`. So `16 < r0` is
#     `r0 > 16` and `r0 < 16` is `r0 < 16`. `ZLt` implements that.
#   * arithmetic is infix with NO spaces for `* / %` and one space for `+ -`:
#     `i*2`, `i/4`, `r0%16`, `i + 5`, `r0 - r0%4`.
# A dropped literal is invisible in a `Bool` and visible in a byte diff, which
# is the reason the gate is text.
#
# ---------------------------------------------------------------------------
# KNOWN DIVERGENCES, each measured, none of them fitted away:
#   * `z3.FreshInt("invalid_shift", ctx)` prints as `invalid_shift!0`, `!1`, ...
#     -- z3 appends a GLOBAL counter. Bend has no such counter and
#     `ZFresh` prints the bare name. The COUNTER is the divergence, not the
#     name; `dv_shr2` still matches because its gate text has no fresh var.
#   * `z3.BV2Int(..., is_signed=True)` prints its own signed expansion, e.g.
#     `If(int_to_bv(a) ^ int_to_bv(b) < 0, BV2Int(...) - 32, BV2Int(...))`.
#     `ZBv` reproduces it; `dv_and21` is the row.
#   * `2 ** (8 * c.dtype.itemsize)` is `2**32` or larger for every integer
#     dtype, and Bend's `U32` is ALREADY mod 2^32, so the modulo is the
#     identity at itemsize 4 -- which is `dv_bitcast_i32`. At itemsize 8 z3
#     computes mod 2**64 and the port cannot, so rule 5 on a 64-bit target is a
#     VIOLATION (`vd_go`), not a wrong number.
#   * `Ops.DETACH` and `Ops.STACK` are int-dtype and no rule claims them, which
#     is the CPython `NotImplementedError` and the violation text
#     `Ops.STACK is not supported by z3`.
#   * `range_str` is `'_'.join(str(x) if x >= 0 else "m"+str(-x) for x in
#     u.axis_id)` (ops.py:97) -- it reads the axis ID and NOT the axis TYPE.
#     `UOp.range(42, 0, GLOBAL)` and `UOp.range(42, 0, LOOP)` both give `"0"`, so
#     both render the symbol `r0`. **The axis type is invisible at this layer**,
#     and `n_axis_type_invisible` is the row that says so instead of pretending
#     a bad axis type is caught here. The AXIS ID is visible, and
#     `dv_range_m1` is the row for `ids=(-1,)`.
#   * The toposort gate SILENTLY DROPS a float-valued sub-graph. An index
#     containing any float op (`sin`, `/`, a float cast) has every node gated
#     out, `lst` is empty, and `uops_to_z3:89`'s assert fires:
#     `AssertionError: UOp failed to rewrite to z3!`. MEASURED for
#     `UOp.variable("w",0,15).sin()`: the gated toposort is `[]`. So z3 is asked
#     about a bound it was never shown, and the answer is a hard failure rather
#     than a wrong bound. `dv_float_index_empty` is the row, and it is the
#     clearest reason the entry point returns a LIST: this is a fourth outcome,
#     neither `True`, nor the `sat` `False`, nor `NotImplementedError`.

import Base
import ./../helpers.bend as H
import ./ops.bend as O
import ./fold.bend as F
import ./../LAWS/spec.bend as S

# ===========================================================================
# `Z` -- A z3 TERM. Not a value: nothing in this file is ever evaluated, and
# that is the point. `ZLit.v` is TWO'S COMPLEMENT (`-4` is 4294967292) because
# `z3.IntVal` takes a Python int and `u.arg` carries negatives:
# `buf.index(r & -4)` is in tinygrad's own test, test_validate_oob.py:97.
# `is_b` is the z3 SORT, which is what `isinstance(a, z3.BoolRef)` asks in
# `z3_and`/`z3_or`/`z3_xor`; it is a field rather than a `Z.is_b` recursion
# because every constructor here knows its own sort except `ZIf`.
# ===========================================================================
# THE GATE IS RED. THIS IS THE MEASURED DEFECT LIST AND IT IS NOT FITTED AWAY.
#
# Both lanes are byte-identical and `ALL PROOFS CHECK`. The gate is red against
# CPython, and the rows name the defects. The renderer, the walk, the ten-rule
# tag ladder, the term IR, the violation list, and `O.Ops.name` as the
# `NotImplementedError` text all WORK; the PRINTER and two FIXTURES do not.
#
# defect | rows | what the port prints | what CPython prints (MEASURED)
# --------|------|---------------------|------------------------------
# D1 z3's `Le` printer orientation is UNRESOLVED and this port guessed wrong.
#    Two CPython measurements disagree with EACH OTHER: `0 <= i` printed
#    `i >= 0`, and `z3.IntVal(0, ctx) <= r0` printed `0 <= r0`. Same z3 build.
#    The port hoists iff the other side is a symbol, which gets the first right
#    and the second wrong.
#    | dv_var, dv_range_* | `And(v >= 0, v >= 15)` | `And(i >= 0, i <= 15)`
# D2 the same, on the RANGE's upper bound `ctx[1][src[0]] - 1`.
#    | dv_range_global | `And(r >= 0, 100 - 1 <= r)` | `And(r0 >= 0, r0 <= 100 - 1)`
# D3 `range_str` loses the axis id, so the symbol is `r` and not `r0`.
#    | dv_range_global, dv_range_loop, dv_range_m1 | `r` | `r0`, `rm1`
# D4 the `Sol` is written on a `Bool.pick` that also READS it, so entries and
#    assertions are duplicated.
#    | dv_var | `[, i]` | `[And(i >= 0, i <= 15), True]`
# D5 THE MASK IS NEVER ADDED. `uops_to_z3:95` does `solver.add(z3_mask)` and
#    nothing ported does, so no row can print the trailing `True` CPython always
#    prints. One line, and it is the first thing to fix.
#    | every row | `[]` / `[, i]` | `[..., True]`
# D6 `z3_and` takes the BIT-BLAST arm for `r & 15` AND for `r & -4`, so `pow2`
#    is not firing.
#    | dv_and15 | the `int_to_bv(...)` text | `(mod r0 16)`
#    | dv_and_neg4 | the `int_to_bv(...)` text | `r0 - r0%4`
# D7 `dv_unsup_two` and `dv_bad_dtype_bitcast` report ZERO violations. The
#    single-node `dv_unsup_stack` DOES report one, so the
#    `Ops.STACK is not supported by z3` TEXT is verified and the COUNT row and
#    the bitcast row are not.
# D8 `dv_rank_shr1` and `dv_unsup_stack` each report one violation and the
#    counts are right, but their MESSAGES are PORT-ADDED: CPython raises
#    `IndexError` on the first rather than returning a message. Marked as such.
#
# WHAT IS CONFIRMED AGAINST A CPython MEASUREMENT: `dv_const_ok` (`[] | 15 |
# | 0`), `dv_shr2`'s `If(0 > 2, invalid_shift, r/4)` shape,
# `dv_const_invalid`'s `Invalid`, and `n_z3_alu=11`. Those four, and nothing else.
#
# NEXT, in order, and none of it is a nice-to-have: D5 (one line -- the mask is
# the `CONST(True)` node and `uops_to_z3` must `Sol.add` it), D3 (one line --
# `rs_ids.go`'s separator test), D1/D2 (re-measure z3's `Le` printer in ONE
# process with ONE context and settle it; two measurements already disagree),
# D4 (find the `Bool.pick` that both reads and writes `Sol`), D6 (`pow2` on a
# literal held two's complement), D7 (the gate on `Ops.GROUP` and the BITCAST
# shape test).
# ===========================================================================

# ===========================================================================

type Z is Data:
  ZSym{nm: String, is_b: Bool}      # z3.Int(name) / z3.Bool(name)
  ZLit{v: U32, is_b: Bool}          # z3.IntVal(v) / z3.BoolVal(v)
  ZAdd{a: Z, b: Z}                  # a + b
  ZSub{a: Z, b: Z}                  # a - b
  ZMul{a: Z, b: Z}                  # a * b
  ZDiv{a: Z, b: Z}                  # a / b
  ZMod{a: Z, b: Z}                  # a % b
  ZNeg{a: Z}                        # -a
  ZIf{c: Z, a: Z, b: Z}             # z3.If(c, a, b)
  ZLt{a: Z, b: Z}                   # a < b
  ZLe{a: Z, b: Z}                   # a <= b
  ZGt{a: Z, b: Z}                   # a > b
  ZGe{a: Z, b: Z}                   # a >= b
  ZEq{a: Z, b: Z}                   # a == b
  ZNe{a: Z, b: Z}                   # a != b
  ZNeZ{a: Z}                        # a != 0
  ZAnd{a: Z, b: Z}                  # z3.And(a, b)
  ZOr{a: Z, b: Z}                   # z3.Or(a, b)
  ZXor{a: Z, b: Z}                  # z3.Xor(a, b)
  ZFresh{nm: String}                # z3.FreshInt(nm, ctx)
  ZBv{k: U32, w: U32, a: Z, b: Z}   # BV2Int(<k>(Int2BV(a,w), Int2BV(b,w)), is_signed=True)

type Bind is Data: Bind{u: U32, t: Z}

type MRng is Data: MRng{u: U32, lo: U32, hi: U32}

type Sol is Data:
  Sol{cs: List<&2, Z>, es: List<&2, Bind>, ms: List<&2, MRng>}

# `x.vmin` / `x.vmax`, two's complement, as a `Data` pair because a `U32` read
# twice in one expression needs a record (the notes' device.bend rule 3).
#
# TWO HAND-WRITTEN READERS. A LOCALLY-DECLARED record has no projection syntax
# at all -- neither `m.lo` nor `MM.lo(m)` is a compiler feature -- so rule 27 is
# the whole cost: two lines per field, written out by hand.
type MM is Data: MM{lo: U32, hi: U32}

type ZAt is Data: ZAt{hit: Bool, t: Z, v: String}

type Ren is Data: Ren{s: Sol, a: ZAt}

# `S.Dt.min` is a `Maybe` (no U32 limit past 32 bits) and `itemsize` is a
# `U32`, and both are read more than once, so they travel as one record.
type DtMin is Data: DtMin{got: Bool, v: U32, isz: U32}

# THE TABLE, IN RULE ORDER. First-wins IS the list order, so the order is
# visible rather than implied -- and the tag is a field rather than a ladder
# index, so a rule cannot be renumbered by accident. Tag 10 is the catch-all:
# no rule matched, which `uops_to_z3:87` turns into
# `NotImplementedError(f"{u.op} is not supported by z3")`.
type RTag is Data: RTag{hit: Bool, tag: U32}

type VFr is Data: VFr{n: U32, seen: Bool}

type VTopo is Data: VTopo{cache: List<&2, U32>, stack: List<&2, VFr>}

type Vz is Data: Vz{s: Sol, vs: List<&2, String>}

# `z3_xor`: a Bool XOR wins, then `b == -1`, then `a == -1`, then the
# bit-blast. The ORDER is load-bearing: `b` is tested before `a`, and `-1` is
# 4294967295 in a U32. MEASURED: `r ^ -1` is `-(r+1)`.
# `w` is read TWICE -- once for each bit-blast attempt -- and `+` is REFUSED on
# a `Maybe`, so it becomes a `Bool` plus the value. That is the notes' rule 7
# and it is why `z3_xor` has a `.m2` at all.
type Wv is Data: Wv{got: Bool, w: U32}

type Rep is Data: Rep{sz: U32, vs: List<&2, String>, cs: String, term: String}

# `k` in `ZBv` is which of the three bit-blasted ops it is. Python passes a
# `lambda u,v: u^v` / `u&v` / `u|v`, and a closure in a `Data` field is not
# writable, so the tag is the honest transliteration of the lambda.
def bv_xor() -> U32: 2

def bv_and() -> U32: 0

def bv_or() -> U32: 1

# `int.bit_length()` of a two's-complement value, i.e. of its ABSOLUTE value.
# `U32.log2` is floor and answers a `Nat`, so `bit_length(v) = log2(v) + 1` and
# `bit_length(0) = 0` is the one special case. This is `z3_bv`'s width and
# `z3_shift`'s loop count.
def bit_len(+v: U32) -> U32:
  Bool.pick(U32, U32.is_eq(v, 0), 0, U32.from_nat(Nat.add(U32.log2(v), 1n)))

# a signed decimal, because a z3 literal prints signed and a `U32` row that
# prints 4294967292 where the oracle prints -4 is a gate that needs mental
# arithmetic to read (the notes' rule 4 on `U32.show`).
def z_i(+v: U32) -> String:
  Bool.pick(String, U32.is_eq(U32.and(v, 2147483648), 0), U32.show(v),
            String.concat(["-", U32.show(U32.sub(0, v))]))

# `x.dtype == dtypes.bool` -- whether a node's value is a Bool rather than an
# Int. Only `ZIf` has to look at a child.
def Z.is_b(t: Z) -> Bool:
  match t:
    case ZSym{nm, b}: b
    case ZLit{v, b}: b
    case ZIf{c, a, b}: Z.is_b(a)
    case ZAnd{a, b}: True{}
    case ZOr{a, b}: True{}
    case ZXor{a, b}: True{}
    case ZLt{a, b}: True{}
    case ZLe{a, b}: True{}
    case ZGt{a, b}: True{}
    case ZGe{a, b}: True{}
    case ZEq{a, b}: True{}
    case ZNe{a, b}: True{}
    case ZNeZ{a}: True{}
    case _: False{}

# `isinstance(t, z3.IntNumRef)`, and `t.as_long()`. `Maybe` because a `Data`
# record cannot hold one and `+` is refused on it, so this is a DEF and not a
# field -- the same shape `Sol.find` has.
def Z.num(t: Z) -> Maybe<&1, U32>:
  match t:
    case ZLit{v, b}: Some{v}
    case _: None{}

# `isinstance(t, z3.IntNumRef)`, as the Bool the three `z3_*` helpers branch on.
def Z.is_num(t: Z) -> Bool:
  match t:
    case ZLit{v, b}: Bool.not(b)
    case _: False{}

# `BoolVal`'s text is `True` / `False`, and `v` is 1 / 0.
def z_b(+v: U32) -> String:
  Bool.pick(String, U32.is_eq(v, 0), "False", "True")

def ZLit.str(+v: U32, is_b: Bool) -> String:
  Bool.pick(String, is_b, z_b(v), z_i(v))

# z3's signed `BV2Int`, as `str()` prints it. The `<< 0` is `w`: MEASURED,
# width 5 gives the offset 32, so it is `2**w` and not `2**(w-1)`.
# `k` is a `U32`, and a `U32` has no constructors for a `match` to cover --
# `case 0:` on a `U32` is "a declared constructor (unknown: U32)". So the
# three-way choice is TWO `Bool`s, the shape `ren_5.why.str` uses too.
def bv_op(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, bv_and()), "&", Bool.pick(String, U32.is_eq(k, bv_or()), "|", "^"))

def ZBv.str(k: U32, w: U32, a: String, b: String) -> String:
  +base = String.concat(["int_to_bv(", a, ") ", bv_op(k), " int_to_bv(", b, ")"])
  +core = String.concat(["BV2Int(", base, ")"])
  String.concat(["If(", base, " < 0, ", core, " - ", U32.show(U32.shln(1, U32.to_nat(w))), ", ", core, ")"])

# ---------------------------------------------------------------------------
# THE COMPARISON PRINTER IS THE IDENTITY, AND THAT IS THE WHOLE OF D1 AND D2.
#
#   z3's `str()` prints a comparison IN SOURCE ORDER. Every one of 128 measured pairs does,
#   and the sexprs confirm it: `(>= 5 i)` prints `5 >= i`, `(<= i 0)` prints `i <= 0`,
#   `(<= i (- 100 1))` prints `i <= 100 - 1`. There is NO hoist and NO reorientation.
#
# ⚠ SO WHERE DID `i >= 0` COME FROM? From Python's REFLECTED OPERATOR, not from z3. A
# Python `int` on the LEFT of a comparison tries `int.__le__(ArithRef)`, gets
# NotImplemented, and evaluates the reflected `ArithRef.__ge__`, which builds `GE(right,
# left)`. So validate.py:51's `(vmin <= s)`, with `vmin` a Python `int`, is `s >= vmin` in
# the AST before z3 ever sees it. MEASURED, one process, one context:
#     str(0 <= i) = 'i >= 0'    sexpr (>= i 0)
#     str(i <= 0) = 'i <= 0'    sexpr (<= i 0)
#     str(IntVal(0) <= i) = '0 <= i'   sexpr (<= 0 i)     <- NOT what validate.py evaluates
# The third line is why this took a session to settle: the two "disagreeing measurements"
# this header used to record are the SAME rule under two different operand spellings. Rows
# `refl_*` and `cmpP_*` / `cmpZ_*` in `.agents/slop/validate-oracle.py`.
#
# CONSEQUENCE, and it is a real modelling requirement rather than a style note: every
# `ZLt`/`ZLe` this file builds must be the AST CPython builds, so a comparison with a
# PYTHON-int left operand is spelled `ZGe`/`ZGt` here. `z3_cdiv`'s `0<b` and `z3_floordiv`'s
# `b > 0` are the two such places and both are corrected below.
# ---------------------------------------------------------------------------

# THE PRINTER. `str(z3_expr)`, which is what `solver`'s own `__str__` and
# validate.py's f-strings print.
def Z.str(t: Z) -> String:
  match t:
    case ZSym{nm, b}: nm
    case ZLit{v, b}: ZLit.str(v, b)
    case ZAdd{a, b}: String.concat([Z.str(a), " + ", Z.str(b)])
    case ZSub{a, b}: String.concat([Z.str(a), " - ", Z.str(b)])
    case ZMul{a, b}: String.concat([Z.str(a), "*", Z.str(b)])
    case ZDiv{a, b}: String.concat([Z.str(a), "/", Z.str(b)])
    case ZMod{a, b}: String.concat([Z.str(a), "%", Z.str(b)])
    case ZNeg{a}: String.concat(["-", Z.str(a)])
    case ZIf{c, a, b}: String.concat(["If(", Z.str(c), ", ", Z.str(a), ", ", Z.str(b), ")"])
    case ZLe{a, b}: String.concat([Z.str(a), " <= ", Z.str(b)])
    case ZGe{a, b}: String.concat([Z.str(a), " >= ", Z.str(b)])
    case ZLt{a, b}: String.concat([Z.str(a), " < ", Z.str(b)])
    case ZGt{a, b}: String.concat([Z.str(a), " > ", Z.str(b)])
    case ZEq{a, b}: String.concat([Z.str(a), " == ", Z.str(b)])
    case ZNe{a, b}: String.concat([Z.str(a), " != ", Z.str(b)])
    case ZNeZ{a}: String.concat([Z.str(a), " != 0"])
    case ZAnd{a, b}: String.concat(["And(", Z.str(a), ", ", Z.str(b), ")"])
    case ZOr{a, b}: String.concat(["Or(", Z.str(a), ", ", Z.str(b), ")"])
    case ZXor{a, b}: String.concat(["Xor(", Z.str(a), ", ", Z.str(b), ")"])
    case ZFresh{nm}: nm
    case ZBv{k, w, a, b}: ZBv.str(k, w, Z.str(a), Z.str(b))

# `str(solver)` -- the assertion list, which is the PORTABLE half of validate.py's
# sat message. `[And(i >= 0, i <= 15), True]` is a real measured row.
#
# `sep` IS THE WHOLE FIX and it replaced a `Bool` flag that was reading the list it was
# building: the flag made the FIRST element take the `acc` arm, so the head of every
# assertion list was DROPPED (`dv_var` printed `[, i]`, `dv_const_ok` printed `[]` where
# CPython prints `[True]`). A separator cannot drop an element, and it is one parameter
# shorter. MEASURED against CPython's `str(solver)` for all 16 fixtures; see
# `.agents/slop/validate-oracle.py`.
def cs_str.go(+cs: List<&2, Z>, +acc: String, sep: String) -> String:
  match cs:
    case Nil{}: String.concat(["[", acc, "]"])
    case h <> t: cs_str.go(t, String.concat([acc, sep, Z.str(h)]), ", ")

def cs_str(cs: List<&2, Z>) -> String:
  cs_str.go(cs, "", "")

def Sol.empty() -> Sol:
  Sol{Nil{}, Nil{}, Nil{}}

# THE THREE FIELD READERS COME FIRST. Rule 27: a field is read
# `Type.field(value)` and `def Type.field(x) -> T: match x: case Type{f1, f2,
# ...}: fi` is written out BY HAND for every field -- there is no generated
# projection at all, and `Sol.es(s)` is not a compiler intrinsic. A def may only
# call defs above it, so the readers precede every user, including `Sol.n`.
def Sol.es(+s: Sol) -> List<&2, Bind>:
  match s:
    case Sol{cs, es, ms}: es

def Sol.cs(+s: Sol) -> List<&2, Z>:
  match s:
    case Sol{cs, es, ms}: cs

def Sol.ms(+s: Sol) -> List<&2, MRng>:
  match s:
    case Sol{cs, es, ms}: ms

# `len(ctx[1])` -- the counter in `f"{x.op.name.lower()}{len(ctx[1])}"`, which is
# what names an INDEX or a LOAD's z3 symbol (`index2`, `load3`).
def Sol.n(+s: Sol) -> U32:
  U32.from_nat(List.length(&2, Bind, Sol.es(s)))

# the parameter is `k` and not `u` because a pattern binder may not shadow it --
# the error names the CONSTRUCTOR and says "a declared constructor (unknown:
# Bind)", which reads like an undeclared type (the notes' device.bend rule 2).
def Sol.find.go(+es: List<&2, Bind>, +k: U32) -> Maybe<&1, Z>:
  match es:
    case Nil{}: None{}
    case Bind{u, t} <> rest:
      Bool.pick(Maybe<&1, Z>, U32.is_eq(u, k), Some{t},
                Sol.find.go(rest, k))

def Sol.find(+s: Sol, u: U32) -> Maybe<&1, Z>:
  Sol.find.go(Sol.es(s), u)

# `z3map[u] = z3_rewritten` -- validate.py:88. THE MAP ONLY: CPython's `z3map` is a
# `dict[UOp, ExprRef]` and NOTHING in it is ever added to the solver. This used to append the
# term to `cs` as well, which put every rewritten node's VALUE into the assertion list; that
# was defect D4, and MEASURED against CPython it is the whole of `dv_var`'s `[, i]` field --
# the `i` in there is a term, not an assertion.
def Sol.put(+s: Sol, u: U32, +t: Z) -> Sol:
  Sol{Sol.cs(s), List.append(&2, Bind, Sol.es(s), [Bind{u, t}]), Sol.ms(s)}

def Sol.add(+s: Sol, +c: Z) -> Sol:
  Sol{List.append(&2, Z, Sol.cs(s), [c]), Sol.es(s), Sol.ms(s)}

def Sol.mm.go(+ms: List<&2, MRng>, +k: U32) -> Maybe<&1, MRng>:
  match ms:
    case Nil{}: None{}
    case MRng{u, lo, hi} <> rest:
      Bool.pick(Maybe<&1, MRng>, U32.is_eq(u, k), Some{MRng{u, lo, hi}},
                Sol.mm.go(rest, k))

def Sol.mm(+s: Sol, u: U32) -> Maybe<&1, MRng>:
  Sol.mm.go(Sol.ms(s), u)

def Sol.put_mm(+s: Sol, u: U32, lo: U32, hi: U32) -> Sol:
  Sol{Sol.cs(s), Sol.es(s), List.append(&2, MRng, Sol.ms(s), [MRng{u, lo, hi}])}

# `MRng.lo` / `MRng.hi`, two reads each, so they are defs and not fields.
def MM.lo(m: MM) -> U32:
  match m:
    case MM{lo, hi}: lo

def MM.hi(m: MM) -> U32:
  match m:
    case MM{lo, hi}: hi

def MRng.lo(m: MRng) -> U32:
  match m:
    case MRng{u, lo, hi}: lo

def MRng.hi(m: MRng) -> U32:
  match m:
    case MRng{u, lo, hi}: hi

# `H.I64` has no field reader (rule 27), so this is one of the two.
def vz_lo(i: H.I64) -> U32:
  match i:
    case H.I64{hi, lo}: lo

def vz_cint(c: O.Const) -> Maybe<&1, U32>:
  match c:
    case O.CInt{i}: Some{vz_lo(i)}
    case _: None{}

def vz_cval.go(a: O.Arg) -> Maybe<&1, U32>:
  match a:
    case O.APy{v}: vz_cint(v)
    case _: None{}

# `x.val` for `Ops.CONST` -- `z3.IntVal(x.val)`. `APy` is the only Arg that
# carries a value; the low 32 bits of the I64 are read and the narrowing is in
# the header (`Ops.long` has no `U32` bound anyway).
#
# THE `.go` SPLIT IS NOT OPTIONAL AND NOT A STYLE CHOICE: `match O.Arena.arg(ar,
# i):` is `a match cannot scrutinize a computed value`. It is the same rule as
# for a projection, and it fires on every arena read that a `match` wants, so
# every one of them is a two-def pair. The wrapper is the caller.
def vz_cval(ar: O.Arena, i: U32) -> Maybe<&1, U32>:
  vz_cval.go(O.Arena.arg(ar, i))

# `vmin`/`vmax` of a CONST is `(x.val, x.val)` and that needs NO fold, so this
# arm is real today. Everything else reads the table, and its absence is the
# `_min_max` wall.
def vz_mm.put(cval: Maybe<&1, U32>, m: Maybe<&1, MRng>) -> Maybe<&1, MM>:
  match cval:
    case Some{+v}: Some{MM{v, v}}
    case None{}:
      match m:
        case Some{+r}: Some{MM{MRng.lo(r), MRng.hi(r)}}
        case None{}: None{}

def vz_mm.of(cval: Maybe<&1, U32>, m: Maybe<&1, MRng>) -> Maybe<&1, MM>:
  vz_mm.put(cval, m)

def vz_mm(ar: O.Arena, s: Sol, +i: U32) -> Maybe<&1, MM>:
  vz_mm.of(vz_cval(ar, i), Sol.mm(s, i))

# `int(x.src[1].vmin)` clamped at zero, which is `lo` in `z3_shift`.
def vz_max0(+v: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.and(v, 2147483648), 0), v, 0)

# `range_str` (ops.py:95): the axis IDS joined by `_`, negatives as `m<n>`.
# NOT the axis type -- see the header, and `n_axis_type_invisible`.
#
# ONE SEPARATOR, AND NO FLAG, for the reason `cs_str.go` gives: the flag form took the `acc`
# arm on the first id and so DROPPED it, which is why every `dv_range_*` row printed the
# symbol `r` where CPython prints `r0` (defect D3). MEASURED against `range_str` itself:
# axis id `0` -> `0`, `-1` -> `m1`, `(0, 1)` -> `0_1`, and the axis TYPE is invisible.
def rs_one(+v: U32) -> String:
  Bool.pick(String, U32.is_eq(U32.and(v, 2147483648), 0), U32.show(v),
            String.concat(["m", U32.show(U32.sub(0, v))]))

def rs_ids.go(+ids: List<&2, U32>, +acc: String, sep: String) -> String:
  match ids:
    case Nil{}: acc
    case h <> t: rs_ids.go(t, String.concat([acc, sep, rs_one(h)]), "_")

def zat.miss(v: String) -> ZAt:
  # a `Some{v}` with an unused binder is REFUSED, so a miss carries `ZLit` zero
  # rather than a named dummy (rule 14, re-measured on `Maybe`).
  ZAt{False{}, ZLit{0, False{}}, v}

def zat.hit(t: Z) -> ZAt:
  ZAt{True{}, t, ""}

def zat.of(m: Maybe<&1, Z>, miss: String) -> ZAt:
  match m:
    case Some{t}: zat.hit(t)
    case None{}: zat.miss(miss)

# the `Maybe`-returning helpers (`z3_bv`, `z3_shift`'s bounds) unwrap here.
def zm(m: Maybe<&1, Z>, miss: String) -> ZAt:
  match m:
    case Some{t}: zat.hit(t)
    case None{}: zat.miss(miss)

def ZAt.t(a: ZAt) -> Z:
  match a:
    case ZAt{hit, t, v}: t

def ZAt.hit(a: ZAt) -> Bool:
  match a:
    case ZAt{hit, t, v}: hit

def ZAt.v(a: ZAt) -> String:
  match a:
    case ZAt{hit, t, v}: v

# `x.src[n]`, WITH A RANK CHECK. `Arena.src` on an out-of-range `n` does not
# raise: it answers a `U32` read out of the node's src list, which is a number
# that is not a node index, and the lookup then misses. CPython raises
# `IndexError: tuple index out of range` here, so the rank check is a PORT-ADDED
# violation -- and its text is built from `O.Ops.name`, the same string the
# `NotImplementedError` rows diff, so half of `dv_rank_shr1` is still
# CPython-derived. `Bool.pick` is STRICT, so both messages are built either way.
def zat.rank(+ar: O.Arena, +self: U32, n: U32, rule: String) -> String:
  String.concat([rule, ": ", O.Ops.name(O.Arena.op(ar, self)), " has ",
                 U32.show(O.Arena.nsrc(ar, self)), " srcs, needs ", U32.show(U32.add(n, 1))])

def zat.src(+ar: O.Arena, +s: Sol, +self: U32, +n: U32, +rule: String) -> ZAt:
  Bool.pick(ZAt, U32.is_ge(n, O.Arena.nsrc(ar, self)),
            zat.miss(zat.rank(ar, self, n, rule)),
            zat.of(Sol.find(s, O.Arena.src(ar, self, n)), zat.rank(ar, self, n, rule)))

# `both answers present`, and `the first message` -- the two combines a rule
# needs when it reads two srcs.
def zall(+a: ZAt, +b: ZAt) -> Bool:
  Bool.and(ZAt.hit(a), ZAt.hit(b))

def zwhy(+a: ZAt, +b: ZAt) -> String:
  Bool.pick(String, ZAt.hit(a), ZAt.v(b), ZAt.v(a))

# `z3_cdiv(a,b) = If(a<0, If(0<b, (a+(b-1))/b, (a-(b+1))/b), a/b)`
#
# `0 < b` IS `ZGt{b, 0}`, NOT `ZLt{0, b}`: the `0` is a Python `int` on the left, so Python
# reflects and z3 receives `b > 0`. MEASURED: `str(IntVal(0) < i)` is `i > 0`. `a < 0` needs
# no such change -- a z3 term on the left does not reflect.
def z3_cdiv(+a: Z, +b: Z) -> Z:
  ZIf{ZLt{a, ZLit{0, False{}}},
       ZIf{ZGt{b, ZLit{0, False{}}}, ZDiv{ZAdd{a, ZSub{b, ZLit{1, False{}}}}, b},
                                                 ZDiv{ZSub{a, ZAdd{b, ZLit{1, False{}}}}, b}},
       ZDiv{a, b}}

# `z3_floordiv(a,b) = If(b>0, a/b, (-a)/(-b))` -- `b > 0` is written `0 < b` upstream, so
# the same reflection applies and it is `ZGt` for the same measured reason.
def z3_floordiv(+a: Z, +b: Z) -> Z:
  ZIf{ZGt{b, ZLit{0, False{}}}, ZDiv{a, b}, ZDiv{ZNeg{a}, ZNeg{b}}}

# `m > 0 and m & (m-1) == 0` -- "m is a power of two", the test `z3_and` uses twice.
# Bitwise is DOTTED, hence `U32.and`.
#
# ⚠ `m > 0` IS `m != 0` OVER EVERY INTEGER, and this is a THEOREM rather than a re-reading:
# `m & (m-1) == 0` says every bit of m but its lowest is clear, so m is a power of two, so
# m is positive; m = 0 is the single value the bit test admits and `m > 0` rejects. The port
# wrote the sign BIT where Python has `m > 0`, which is False for every positive m, so
# `pow2` answered False for all eight positive powers of two in the oracle's window and the
# bit-blast arm fired for `r & 15` and `r & -4` (defect D6). The theorem is checked as
# `pow2_fn_agree` over the 22-value window in `.agents/slop/validate-oracle.py`.
def pow2(+m: U32) -> Bool:
  Bool.and(Bool.not(U32.is_zero(m)), U32.is_eq(U32.and(m, U32.sub(m, 1)), 0))

def bv_max(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), a, b)

# `1 << k`, saturating past 31 -- which is the right answer here because `1 << 32`
# IS 0 in a U32.
def z3_pow(k: U32) -> U32:
  U32.shln(1, U32.to_nat(k))

def bv_one(+v: U32) -> U32:
  bit_len(Bool.pick(U32, U32.is_eq(U32.and(v, 2147483648), 0), v, U32.sub(0, v)))

def z3_bv.put(k: U32, w: Maybe<&1, U32>, a: Z, b: Z) -> Maybe<&1, Z>:
  match w:
    case Some{n}: Some{ZBv{k, n, a, b}}
    case None{}: None{}

def z3_xor.m1(n: Maybe<&1, U32>, t: Z, rest: Maybe<&1, Z>) -> Maybe<&1, Z>:
  match n:
    case Some{v}: Bool.pick(Maybe<&1, Z>, U32.is_eq(v, 4294967295), Some{ZNeg{ZAdd{t, ZLit{1, False{}}}}}, rest)
    case None{}: rest

def z3_xor.m2(ab: Bool, first: Maybe<&1, Z>, na: Maybe<&1, U32>, rest: Maybe<&1, Z>, +a: Z, +b: Z, w: Wv) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, ab, Some{ZXor{a, b}}, z3_xor.m1(na, b, first))

# `a / f if x.op is SHR else a * f`
def z3_scale(is_shr: Bool, +a: Z, +f: U32) -> Z:
  Bool.pick(Z, is_shr, ZDiv{a, ZLit{f, False{}}}, ZMul{a, ZLit{f, False{}}})

def z3_shift.cond(b: Z, lo: U32, i: U32) -> Z:
  ZEq{ZMod{ZDiv{ZSub{b, ZLit{lo, False{}}}, ZLit{z3_pow(i), False{}}}, ZLit{1, False{}}},
      ZLit{1, False{}}}

# `factor = 1 << (1 << i)`
def z3_shift.factor(i: U32) -> U32:
  z3_pow(z3_pow(i))

# `z3.If(b < 0, z3.FreshInt("invalid_shift", ctx), a)` -- the tail does not
# depend on the loop, so the `0n` arm is the whole finish.
def z3_shift.fin(a: Z, b: Z) -> Z:
  ZIf{ZLt{b, ZLit{0, False{}}}, ZFresh{"invalid_shift"}, a}

# `range(max(0, int(vmax) - lo).bit_length())`
def z3_shift.steps(+hi: U32, +lo: U32) -> U32:
  Bool.pick(U32, U32.is_le(hi, lo), 0, bit_len(U32.sub(hi, lo)))

def dt_in_ints.go(c: S.Cls) -> Bool:
  match c:
    case S.CUint{}: True{}
    case S.CSint{}: True{}
    case _: False{}

def dt_in_floats.go(c: S.Cls) -> Bool:
  match c:
    case S.CFloat{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def vz_dt.of(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

# `solver.add((vmin <= s) & (s <= vmax))`, answer `s`. ONE add of an `And`, and
# the symbol comes back BARE -- which is why the row for `UOp.param(0, int, 16)`
# prints `null` in the constraint list and not a bounded expression.
#
# ⚠ IT IS `ZGe` AND NOT `ZLe` ON THE LEFT, and that is the ROOT CAUSE of the old D1 and D2.
# `vmin` at both call sites is a PYTHON `int`, so `vmin <= s` REFLECTS: Python tries
# `int.__le__(ArithRef)`, gets NotImplemented, and evaluates `ArithRef.__ge__` instead, so the
# AST holds `s >= vmin`. MEASURED in one process, one context: `str(0 <= i)` is `i >= 0` and
# `str(i <= 0)` is `i <= 0`. The right conjunct is `s <= vmax` with a z3 operand and needs no
# reflection. So the port's old `ZLe{vmin, sym}` built an AST CPython never builds, and the
# printer was then asked to paper over the difference -- which it did in the wrong direction
# for `r0 <= 100 - 1`. Rows `refl_*` in the oracle.
def create_bounded(+s: Sol, +nm: String, vmin: Z, vmax: Z) -> Ren:
  +sym: Z = ZSym{nm, False{}}
  Ren{Sol.add(s, ZAnd{ZGe{sym, vmin}, ZLe{sym, vmax}}), zat.hit(sym)}

def create_var.bound(+s: Sol, m: Maybe<&1, MM>, nm: String, miss: String) -> Ren:
  match m:
    case Some{+r}: create_bounded(s, nm, ZLit{MM.lo(r), False{}}, ZLit{MM.hi(r), False{}})
    case None{}: Ren{s, zat.miss(miss)}

# `f"{x.op.name.lower()}{len(ctx[1])}"`. `O.Ops.name.of` is the BARE member name
# (it is `AxisType.name` too) and `String.to_lower` does the rest, so this is
# the whole expression rather than a ladder over the ops that reach it.
def cv_name(op: O.Op, n: U32) -> String:
  String.concat([String.to_lower(O.Ops.name.of(op)), U32.show(n)])

def pa_name(a: O.Arg) -> Maybe<&2, String>:
  match a:
    case O.AParam{pa}: O.ParamArg.name(pa)
    case _: None{}

def cv_arg_name.put(m: Maybe<&2, String>) -> String:
  match m:
    case Some{n}: n
    case None{}: "null"

# `z3_cast` -- line 57. "z3 does not model widths: a cast only converts between
# bool and int", so a float cast is the IDENTITY. MEASURED: the CAST in
# `dv_cast_float` contributes no text of its own.
def z3_cast(+sb: Bool, +db: Bool, +t: Z) -> Z:
  Bool.pick(Z, Bool.pick(Bool, sb, db, Bool.not(db)), t, ZNeZ{t})

def ren_1.put(+c: ZAt, +x: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(c, x), Ren{Sol.add(s, ZAt.t(c)), x}, Ren{s, zat.miss(zwhy(c, x))})

def ren_2.put(+hi: ZAt, nm: String, +s: Sol) -> Ren:
  Bool.pick(Ren, ZAt.hit(hi),
            create_bounded(s, nm, ZLit{0, False{}}, ZSub{ZAt.t(hi), ZLit{1, False{}}}),
            Ren{s, hi})

def ren_3_defines.go(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case _: False{}

def ren_5.dmin.go(m: Maybe<&2, U32>, +isz: U32) -> DtMin:
  match m:
    case Some{v}: DtMin{Bool.not(U32.is_gt(isz, 4)), v, isz}
    case None{}: DtMin{False{}, 0, isz}

# `m.v` and `m.isz` are READERS, not projections -- rule 27, and this is the
# second record in the file to need them.
def DtMin.v(m: DtMin) -> U32:
  match m:
    case DtMin{got, v, isz}: v

def DtMin.isz(m: DtMin) -> U32:
  match m:
    case DtMin{got, v, isz}: isz

def ren_5.mod(+x: ZAt, +m: DtMin) -> Z:
  ZAdd{ZMod{ZSub{ZAt.t(x), ZLit{DtMin.v(m), False{}}},
             ZLit{z3_pow(U32.mul(8, DtMin.isz(m))), False{}}},
       ZLit{DtMin.v(m), False{}}}

def DtMin.got(m: DtMin) -> Bool:
  match m:
    case DtMin{got, v, isz}: got

def ren_5.why.str(+m: DtMin, +xv: String) -> String:
  Bool.pick(String, DtMin.got(m),
    String.concat(["rule 5: a ", U32.show(DtMin.isz(m)), "-byte dtype wraps mod 2^64, U32 cannot; ", xv]),
    String.concat(["rule 5: a ", U32.show(DtMin.isz(m)), "-byte dtype has no U32 min; ", xv]))

# rule 6 -- `UPat(Ops.CONST, arg=Invalid)` -> `z3.Int("Invalid")`. A FREE symbol
# and NOT added to the solver: `Invalid` is a value with no constraint.
def ren_6(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  Ren{s, zat.hit(ZSym{"Invalid", False{}})}

def ren_7.put(m: Maybe<&1, U32>, is_bool: Bool, +s: Sol) -> Ren:
  match m:
    case Some{v}: Ren{s, zat.hit(ZLit{v, is_bool})}
    case None{}: Ren{s, zat.miss("rule 7: a CONST with no value")}

def ren_8.put(+x: ZAt, +sb: Bool, +db: Bool, +s: Sol) -> Ren:
  Bool.pick(Ren, ZAt.hit(x), Ren{s, zat.hit(z3_cast(sb, db, ZAt.t(x)))}, Ren{s, x})

def ren_9.b2.mk(+k: U32, +a: Z, +b: Z) -> Z:
  Bool.pick(Z, U32.is_eq(k, 2), z3_floordiv(a, b),
    Bool.pick(Z, U32.is_eq(k, 1), ZSub{a, ZMul{z3_cdiv(a, b), b}},
                                   ZSub{a, ZMul{z3_floordiv(a, b), b}}))

def z3why(+a: ZAt, w: String) -> String:
  Bool.pick(String, ZAt.hit(a), w, ZAt.v(a))

def t_invalid.c(c: O.Const) -> Bool:
  match c:
    case O.CInvalid{}: True{}
    case _: False{}

def ren_t2.put(+op: O.Op) -> Bool:
  Bool.or(O.eq_op(op, O.OpsSPECIAL{}), O.eq_op(op, O.OpsRANGE{}))

def ren_t3.put2(is_load: Bool, rest: Bool) -> Bool:
  Bool.or(is_load, rest)

def ren_t4_op(+op: O.Op) -> Bool:
  Bool.or(Bool.or(O.eq_op(op, O.OpsCAST{}), O.eq_op(op, O.OpsBITCAST{})),
          Bool.or(O.eq_op(op, O.OpsCMPLT{}),
                  Bool.or(O.eq_op(op, O.OpsCMPNE{}), O.eq_op(op, O.OpsCMPEQ{}))))

# rule 7 -- `UPat(Ops.CONST, name="x")`
def ren_t7(+ar: O.Arena, +self: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, self), O.OpsCONST{})

# rule 8 -- `UPat(Ops.CAST, src=(UPat.var("x"),), name="c")`
def ren_t8(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(O.eq_op(O.Arena.op(ar, self), O.OpsCAST{}), U32.is_eq(O.Arena.nsrc(ar, self), 1))

# `tuple(z3_alu)` -- the ELEVEN keys of validate.py:45-48. A list is the honest
# spelling: a closure value in a `Data` field would force `Type` and make the
# table linear (the notes' "CLOSURE IN A DATATYPE FIELD" section), and the KEYS
# are all this rule reads. `n_z3_alu` is the COUNT row that pins the membership.
def z3_alu_ops() -> List<&2, O.Op>:
  [O.OpsCMOD{}, O.OpsCDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsWHERE{},
   O.OpsMAX{}, O.OpsAND{}, O.OpsOR{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}]

# the four text the integer `python_alu` arms produce. `k` is 1 ADD, 2 SUB,
# 3 MUL, 4 CMPLT, 5 CMPNE, 6 CMPEQ.
def ren_10.mk(+k: U32, +a: Z, +b: Z) -> Z:
  Bool.pick(Z, U32.is_eq(k, 1), ZAdd{a, b},
    Bool.pick(Z, U32.is_eq(k, 2), ZSub{a, b},
      Bool.pick(Z, U32.is_eq(k, 3), ZMul{a, b},
        Bool.pick(Z, U32.is_eq(k, 4), ZLt{a, b},
          Bool.pick(Z, U32.is_eq(k, 5), ZNe{a, b}, ZEq{a, b})))))

def ren_10.b2.put(+k: U32, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(a, b), Ren{s, zat.hit(ren_10.mk(k, ZAt.t(a), ZAt.t(b)))}, Ren{s, zat.miss(zwhy(a, b))})

def ren_10.b1.put(+a: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, ZAt.hit(a), Ren{s, zat.hit(ZNeg{ZAt.t(a)})}, Ren{s, a})

def ren_10.b3.put(+a: ZAt, +b: ZAt, +c: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, Bool.and(zall(a, b), ZAt.hit(c)),
            Ren{s, zat.hit(ZAdd{ZMul{ZAt.t(a), ZAt.t(b)}, ZAt.t(c)})},
            Ren{s, zat.miss(z3why(c, zwhy(a, b)))})

def ren_10.why(op: String) -> String:
  String.concat([op, " is not supported by z3"])

def rt(hit: Bool, tag: U32) -> RTag: RTag{hit, tag}

# ONE self-recursive def. A `rt_pick` helper for the `Bool.pick` would be a
# SECOND member of the recursion and Bend refuses mutual recursion outright, so
# the choice sits in the arm. `+hit` because `Bool.pick` reads it twice, and
# `Bool.pick` is STRICT, so the TAIL is walked even on a hit -- which is why
# this is "first-wins over the whole table" and not "first-hit, then exit".
# rule 10 -- `UPat(GroupOp.ALU, name="x")`
def ren_t10(+ar: O.Arena, +self: U32) -> Bool:
  O.GroupOp.alu(O.Arena.op(ar, self))

def rt_first(+ts: List<&2, RTag>) -> U32:
  match ts:
    case Nil{}: 10
    case RTag{+hit, tag} <> rest: Bool.pick(U32, hit, tag, rt_first(rest))

# `NotImplementedError(f"{u.op} is not supported by z3")` -- the ONE place
# validate.py raises with a message, and the reason this file returns a list.
# `{u.op}` prints as `Ops.X` because `FastEnum.__str__` is preserved, which is
# `O.Ops.name` -- so the text is CPython's, byte for byte.
def ren_unsup(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  Ren{s, zat.miss(String.concat([O.Ops.name(O.Arena.op(ar, self)), " is not supported by z3"]))}

def VTopo.empty() -> VTopo:
  VTopo{Nil{}, Nil{}}

def vz_keep.put(not_mem: Bool, dt_ok: Bool, op: O.Op) -> Bool:
  Bool.and(not_mem, Bool.or(dt_ok, O.eq_op(op, O.OpsSINK{})))

def vz_not_mem.go(op: O.Op) -> Bool:
  match op:
    case O.OpsAFTER{}: False{}
    case O.OpsSHRINK{}: False{}
    case O.OpsALLOC{}: False{}
    case O.OpsBUFFER{}: False{}
    case _: True{}

def vz_push_srcs.go(+srcs: List<&2, U32>, st: List<&2, VFr>) -> List<&2, VFr>:
  match srcs:
    case Nil{}: st
    case s <> t: vz_push_srcs.go(t, VFr{s, False{}} <> st)

def vz_cache_add(n: U32, t: VTopo) -> VTopo:
  match t:
    case VTopo{cache, stack}: VTopo{List.append(&2, U32, cache, [n]), stack}

def vz_cache_of(t: VTopo) -> List<&2, U32>:
  match t:
    case VTopo{cache, stack}: cache

# `[:-1]` -- validate.py:37 drops the LAST element and says "assume it is the
# sink". Dropping every `Ops.SINK` is the same answer for a one-sink graph and
# is the honest reading, because the gate KEEPS a SINK by dtype (`x.op is
# Ops.SINK`) and so the drop is a separate step.
def vz_drop_sink(+xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case u <> t:
      vz_drop_sink(t, ar, Bool.pick(List<&2, U32>, O.eq_op(O.Arena.op(ar, u), O.OpsSINK{}),
                                    acc, List.append(&2, U32, acc, [u])))

def vz_vs.go(acc: Vz) -> List<&2, String>:
  match acc:
    case Vz{s, vs}: vs

def vz_cs.go(acc: Vz) -> List<&2, Z>:
  match acc:
    case Vz{s, vs}: Sol.cs(s)

def vz_s.go(acc: Vz) -> Sol:
  match acc:
    case Vz{s, vs}: s

def vz_term.of(m: Maybe<&1, Z>) -> String:
  match m:
    case Some{t}: Z.str(t)
    case None{}: ""

# `solver.model()` -- NOT PORTED. It is a solver output and the header calls the
# solver the wall; a model cannot be rendered without solving.
# TODO(p3) validate.py:99  the `{solver.model()}` tail of the sat message.
def vd_model() -> String:
  "solver.model() is not ported"

# `solver.reason_unknown()` -- the same shape, the other non-unsat branch.
# TODO(p3) validate.py:100  the `{solver.reason_unknown()}` tail.
def vd_reason() -> String:
  "solver.reason_unknown() is not ported"

# `assert all(u in z3map for u in uops), "UOp failed to rewrite to z3!"` --
# line 89. Reachable whenever the GATE emptied the list, which is what a float
# index does: MEASURED, `UOp.variable("w",0,15).sin()` has a gated toposort of
# `[]`, so the loop never runs and the assert fires. This is the FOURTH outcome
# and it is why the answer is a list.
def vz_rewrite_failed(idx: U32, gate: U32, +acc: Vz) -> Bool:
  Bool.or(U32.is_zero(idx), U32.is_zero(gate))

def bv_max4(+p: MM, +q: MM) -> U32:
  bv_max(bv_max(bv_one(MM.hi(p)), bv_one(MM.hi(q))), bv_max(bv_one(MM.lo(p)), bv_one(MM.lo(q))))

# `z3_bv(x, op, a, b) = BV2Int(op(Int2BV(a,w), Int2BV(b,w)), is_signed=True)`.
# A `Maybe` because the width needs `_min_max`, and a node whose bounds are
# unknown is a VIOLATION rather than a guessed width.
def z3_bv(k: U32, w: Maybe<&1, U32>, a: Z, b: Z) -> Maybe<&1, Z>:
  z3_bv.put(k, w, a, b)

def wv(m: Maybe<&1, U32>) -> Wv:
  match m:
    case Some{w}: Wv{True{}, w}
    case None{}: Wv{False{}, 0}

def Wv.got(w: Wv) -> Bool:
  match w:
    case Wv{got, w}: got

def Wv.w(w: Wv) -> U32:
  match w:
    case Wv{got, w}: w

def z3_xor.wb(k: U32, w: U32, a: Z, b: Z) -> Maybe<&1, Z>:
  z3_bv.put(k, Some{w}, a, b)

def z3_xor.wv(+w: Wv, +a: Z, +b: Z, k: U32) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, Wv.got(w), z3_xor.wb(k, Wv.w(w), a, b), None{})

# `z3_or`: a Bool OR wins, else the bit-blast. There is NO constant case in
# Python either, which is why `r | (r << 1)` in test_validate_oob.py:113 is a
# BV expression and not a simplification.
def z3_or(w: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, Z.is_b(a), Some{ZOr{a, b}}, z3_bv(bv_or(), w, a, b))

# `a = z3.If(((b-lo) / (1 << i)) % 2 == 1, a / factor if SHR else a * factor, a)`
# -- a LEAF, and the whole reason the step is not a second def: `go` and `step`
# would be MUTUAL RECURSION, which Bend refuses outright (the notes' rule 1).
def z3_shift.armed(is_shr: Bool, +a: Z, b: Z, lo: U32, +i: U32) -> Z:
  ZIf{z3_shift.cond(b, lo, i), z3_scale(is_shr, a, z3_shift.factor(i)), a}

# `x.dtype in dtypes.ints + (dtypes.bool, dtypes.weakint)` -- the TOPOSORT
# GATE's dtype half, validate.py:83-84. It is `Dt.is_int or Dt.is_bool` and NOT
# `dt_in_ints`: `Cls.is_int` covers CUint, CSint AND CWeakInt, and `weakint` is
# the one member of `dtypes.ints + (...)` that `dtypes.ints` leaves out. So the
# gate is WIDER than `dt_in_ints` by exactly weakint, and a gate written as
# `dt_in_ints` would drop every weakint node -- which is most of them.
def dt_kept(+d: S.Dt) -> Bool:
  Bool.or(S.Dt.is_int(d), S.Dt.is_bool(d))

def dt_in_ints(d: S.Dt) -> Bool:
  dt_in_ints.go(S.Dt.cls(d))

def dt_in_floats(d: S.Dt) -> Bool:
  dt_in_floats.go(S.Dt.cls(d))

# `x.dtype` through the fold. `S.void()` for an unanswerable node, whose class
# is CVoid -- so an unanswerable node is DROPPED by the gate, which is the
# conservative reading and the one the `sin` measurement shows CPython's own
# gate producing.
#
# `fx` is matched ONCE and its two fields become two binders. `F.fold.dt(
# F.Folded.ar(fx), F.Folded.t(fx), i)` is the shape the notes call out: the
# first accessor CONSUMES, so a second read is a type error even with `+fx` on
# the parameter.
def vz_dt(fx: F.Folded, i: U32) -> S.Dt:
  match fx:
    case F.Folded{ar, tb}: vz_dt.of(F.fold.dt(ar, tb, i))

# `z3.Bool(name)` is NOT added to the solver: a bool is unconstrained.
def create_var.of(is_bool: Bool, +s: Sol, m: Maybe<&1, MM>, +nm: String, miss: String) -> Ren:
  Bool.pick(Ren, is_bool, Ren{s, zat.hit(ZSym{nm, True{}})}, create_var.bound(s, m, nm, miss))

def cv_arg_name.of(a: O.Arg) -> String:
  cv_arg_name.put(pa_name(a))

# rule 1 -- `cond.where(x, CONST(Invalid))` is a CONSTRAINT, and the node's own
# VALUE is `x`, the SECOND src: `ctx[0].add(ctx[1][cond]) or ctx[1][x]`, and
# `Solver.add` returns None so the `or` answers `x`. MEASURED: `valid` is a
# 3-src WHERE.
def ren_1(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_1.put(zat.src(ar, s, self, 0, "rule 1 cond"), zat.src(ar, s, self, 1, "rule 1 x"), s)

# `x.op in {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}` -- the OP half of the name test.
def ren_3_defines(op: O.Op) -> Bool:
  ren_3_defines.go(op)

def ren_5.dmin(m: Maybe<&2, U32>, isz: U32) -> DtMin:
  ren_5.dmin.go(m, isz)

# `(ctx[1][x] - c.dtype.min) % 2**(8*c.dtype.itemsize) + c.dtype.min`
def ren_5.ok(+x: ZAt, m: DtMin, +s: Sol) -> Ren:
  Ren{s, zat.hit(ren_5.mod(x, m))}

# the two failure messages are different FACTS -- no U32 min at all, or a
# 64-bit wrap -- so they are different strings, and `Bool.pick` chooses. The
# src's own message is kept beside whichever applies.
def ren_5.why(+x: ZAt, m: DtMin, +s: Sol) -> Ren:
  Ren{s, zat.miss(ren_5.why.str(m, ZAt.v(x)))}

# rule 7 -- `z3.BoolVal(x.val)` if the dtype is bool else `z3.IntVal(x.val)`.
def ren_7(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_7.put(vz_cval(ar, self), S.Dt.is_bool(vz_dt(fx, self)), s)

# rule 8 -- a one-src CAST. `z3_cast` collapses to the identity unless the
# bool-ness changes, so this arm contributes no text of its own for a float.
def ren_8(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_8.put(zat.src(ar, s, self, 0, "rule 8 x"),
            S.Dt.is_bool(vz_dt(fx, O.Arena.src(ar, self, 0))), S.Dt.is_bool(vz_dt(fx, self)), s)

def ren_9.b2.put(+k: U32, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(a, b), Ren{s, zat.hit(ren_9.b2.mk(k, ZAt.t(a), ZAt.t(b)))}, Ren{s, zat.miss(zwhy(a, b))})

# `z3.If(a<b, b, a)`
def ren_9.mx(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.b2.put(0, zat.src(ar, s, self, 0, "rule 9 src0"), zat.src(ar, s, self, 1, "rule 9 src1"), s)

def ren_9.w3.go(+c: ZAt, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  Bool.pick(Ren, Bool.and(ZAt.hit(c), zall(a, b)), Ren{s, zat.hit(ZIf{ZAt.t(c), ZAt.t(a), ZAt.t(b)})},
            Ren{s, zat.miss(z3why(c, zwhy(a, b)))})

def t_invalid.arg(a: O.Arg) -> Bool:
  match a:
    case O.APy{v}: t_invalid.c(v)
    case _: False{}

# rule 2 -- `UPat((Ops.SPECIAL, Ops.RANGE), name="x")`
def ren_t2(+ar: O.Arena, +self: U32) -> Bool:
  ren_t2.put(O.Arena.op(ar, self))

def ren_t3.put3(op: O.Op) -> Bool:
  ren_3_defines(op)

def ren_t4.put2(is_op: Bool, has_src: Bool, +ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(is_op, has_src), dt_in_floats(vz_dt(fx, O.Arena.src(ar, self, 0))))

def ren_t5_x(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  dt_in_ints(vz_dt(fx, O.Arena.src(ar, self, 0)))

def t_invalid_arg(a: O.Arg) -> Bool:
  t_invalid.arg(a)

# rule 9 -- `UPat(tuple(z3_alu), name="x")`. `z3_alu` is a `dict[Ops,
# Callable]` and its KEYS are what the UPat matches, so the key set is the whole
# rule and `List.contains` with `O.eq_op` is the same lookup a dict does.
def ren_t9(+ar: O.Arena, +self: U32) -> Bool:
  List.contains(O.Op, O.eq_op, z3_alu_ops(), O.Arena.op(ar, self))

def ren_10.b2(k: U32, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.b2.put(k, zat.src(ar, s, self, 0, "rule 10 src0"), zat.src(ar, s, self, 1, "rule 10 src1"), s)

def ren_10.b1(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.b1.put(zat.src(ar, s, self, 0, "rule 10 src0"), s)

# `lambda x,y,z: (x*y)+z`
def ren_10.b3(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.b3.put(zat.src(ar, s, self, 0, "rule 10 src0"), zat.src(ar, s, self, 1, "rule 10 src1"),
                zat.src(ar, s, self, 2, "rule 10 src2"), s)

def vz_not_mem(op: O.Op) -> Bool:
  vz_not_mem.go(op)

# THE STACK IS LIFO: `reversed` and consed, so the pop-head visits src[0] first.
def vz_push_srcs(+srcs: List<&2, U32>, st: List<&2, VFr>) -> List<&2, VFr>:
  vz_push_srcs.go(List.reverse(&2, U32, srcs), st)

def vz_push(ar: O.Arena, +n: U32, +t: VTopo) -> VTopo:
  match t:
    case VTopo{cache, stack}: VTopo{cache, vz_push_srcs(O.Arena.srcs(ar, n), VFr{n, True{}} <> stack)}

# `if not visited: if gate(node): push (node, True) and the srcs` /
# `else: cache.append(node)` -- and `if node in cache: continue` is checked
# FIRST, so an already-visited node is never re-EXPANDED. That membership test
# is what makes the fuel (`Arena.budget`) sufficient for a DAG.
def vz_step.keep(seen: Bool, keep: Bool, ar: O.Arena, +n: U32, +rest: List<&2, VFr>, +cache: List<&2, U32>) -> VTopo:
  match seen:
    case True{}: vz_push(ar, n, VTopo{cache, rest})
    case False{}: Bool.pick(VTopo, keep, vz_push(ar, n, VTopo{cache, rest}), VTopo{cache, rest})

def vz_vs(acc: Vz) -> List<&2, String>:
  vz_vs.go(acc)

def vz_cs(acc: Vz) -> List<&2, Z>:
  vz_cs.go(acc)

def vz_s(acc: Vz) -> Sol:
  vz_s.go(acc)

# `z3map[idx]` -- the root's own term, which is the second half of the gate: the
# constraint list alone cannot see `AND`, `SHL` or `BITCAST` at all, because
# those contribute no assertion.
def vz_term(+acc: Vz, i: U32) -> String:
  vz_term.of(Sol.find(vz_s(acc), i))

# `z3_bv`'s width: `1 + max(bit_length(vmax(src0)), bit_length(vmax(src1)),
# bit_length(-vmin(src0)), bit_length(-vmin(src1)))`, and `bit_length` is of the
# ABSOLUTE value. MEASURED twice: `r & 21` over a RANGE(100) gives 8, and
# `v ^ u` over two variables in 0..15 gives 5.
def bv_w.tail(p: MM, b: Maybe<&1, MM>) -> Maybe<&1, U32>:
  match b:
    case Some{q}: Some{U32.add(1, bv_max4(p, q))}
    case None{}: None{}

def bv_w.go(a: Maybe<&1, MM>, b: Maybe<&1, MM>) -> Maybe<&1, U32>:
  match a:
    case Some{p}: bv_w.tail(p, b)
    case None{}: None{}

def bv_w.put(a: Maybe<&1, MM>, b: Maybe<&1, MM>) -> Maybe<&1, U32>:
  bv_w.go(a, b)

def bv_w(+ar: O.Arena, +s: Sol, +self: U32) -> Maybe<&1, U32>:
  bv_w.put(vz_mm(ar, s, O.Arena.src(ar, self, 0)), vz_mm(ar, s, O.Arena.src(ar, self, 1)))

# ONE self-call, fuel FIRST, and the term AFTER everything that shrinks.
def z3_shift.go(k: Nat, +is_shr: Bool, +a: Z, +b: Z, +lo: U32, +i: U32) -> Z:
  match k:
    case 0n: z3_shift.fin(a, b)
    case 1n+p: z3_shift.go(p, is_shr, z3_shift.armed(is_shr, a, b, lo, i), b, lo, U32.add(i, 1))

# `create_var` -- line 53. The name is `x.arg.name` for a PARAM/BUFFER/ALLOC and
# `f"{op.name.lower()}{len(ctx[1])}"` otherwise, and `len(ctx[1])` is the map
# size BEFORE this node goes in -- which is what names it `index2` / `load3`.
def create_var(+s: Sol, m: Maybe<&1, MM>, is_bool: Bool, nm: String, miss: String) -> Ren:
  create_var.of(is_bool, s, m, nm, miss)

# `x.arg.name` -- a `Maybe`, and CPython passes the `None` straight to
# `z3.Int(None)`, which prints `null`. That is the MEASURED text for
# `UOp.param(0, dtypes.i32, 16)`, so the default is `"null"` and not `""`.
def cv_arg_name(ar: O.Arena, i: U32) -> String:
  cv_arg_name.of(O.Arena.arg(ar, i))

def ren_3_name(+ar: O.Arena, +self: U32, n: U32) -> String:
  Bool.pick(String, ren_3_defines(O.Arena.op(ar, self)), cv_arg_name(ar, self),
            cv_name(O.Arena.op(ar, self), n))

# rule 4 -- `(CAST, BITCAST) + Comparison` with a FLOAT `src[0]`, "unknown
# values are variables bounded by their vmin/vmax: ... and anything from floats".
def ren_4(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  create_var(s, vz_mm(ar, s, self), S.Dt.is_bool(vz_dt(fx, self)),
             cv_name(O.Arena.op(ar, self), Sol.n(s)), "rule 4 create_var: unknown bounds")

def ren_5.put(+x: ZAt, +m: DtMin, +s: Sol) -> Ren:
  Bool.pick(Ren, Bool.and(DtMin.got(m), ZAt.hit(x)), ren_5.ok(x, m, s), ren_5.why(x, m, s))

# `k` is 1 for `a - cdiv(a,b)*b`, 2 for `floordiv(a,b)`, 3 for
# `a - floordiv(a,b)*b`. `Bool.pick` rather than a `case k:` ladder because a
# `U32` literal pattern's successor behaviour is exactly the trap this port has
# already paid for three times.
def ren_9.b2(+k: U32, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.b2.put(k, zat.src(ar, s, self, 0, "rule 9 src0"), zat.src(ar, s, self, 1, "rule 9 src1"), s)

def ren_9.w3.put(+c: ZAt, +a: ZAt, +b: ZAt, +s: Sol) -> Ren:
  ren_9.w3.go(c, a, b, s)

def t_invalid.go(op: O.Op, a: O.Arg) -> Bool:
  match op:
    case O.OpsCONST{}: t_invalid.arg(a)
    case _: False{}

def ren_t3.put(+op: O.Op) -> Bool:
  ren_t3.put2(O.eq_op(op, O.OpsLOAD{}), ren_t3.put3(op))

def ren_t4.put(is_op: Bool, nsrc: U32, +ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  ren_t4.put2(is_op, U32.is_ge(nsrc, 1), ar, fx, self)

# BOTH ends must be int dtypes, and they are two questions, so they are two defs
# with the conjunction between them -- `&&` is not an operator here.
def ren_t5.put(is_op: Bool, nsrc: U32, +ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  Bool.and(Bool.and(Bool.and(is_op, U32.is_eq(nsrc, 1)), dt_in_ints(vz_dt(fx, self))), ren_t5_x(ar, fx, self))

# rule 6 -- `UPat(Ops.CONST, arg=Invalid)`
def ren_t6(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(O.eq_op(O.Arena.op(ar, self), O.OpsCONST{}), t_invalid_arg(O.Arena.arg(ar, self)))

def ren_10.go(op: O.Op, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  match op:
    case O.OpsADD{}: ren_10.b2(1, ar, s, self)
    case O.OpsSUB{}: ren_10.b2(2, ar, s, self)
    case O.OpsMUL{}: ren_10.b2(3, ar, s, self)
    case O.OpsCMPLT{}: ren_10.b2(4, ar, s, self)
    case O.OpsCMPNE{}: ren_10.b2(5, ar, s, self)
    case O.OpsCMPEQ{}: ren_10.b2(6, ar, s, self)
    case O.OpsNEG{}: ren_10.b1(ar, s, self)
    case O.OpsMULACC{}: ren_10.b3(ar, s, self)
    case _: Ren{s, zat.miss(ren_10.why(O.Ops.name(O.Arena.op(ar, self))))}

# `x.op not in {AFTER, SHRINK, ALLOC, BUFFER} and (x.dtype in dtypes.ints +
# (bool, weakint) or x.op is Ops.SINK)`
def vz_keep(+op: O.Op, dt: S.Dt) -> Bool:
  vz_keep.put(vz_not_mem(op), dt_kept(dt), op)

def vz_step.hit(seen: Bool, +ar: O.Arena, +fx: F.Folded, +n: U32, rest: List<&2, VFr>, +cache: List<&2, U32>) -> VTopo:
  vz_step.keep(seen, vz_keep(O.Arena.op(ar, n), vz_dt(fx, n)), ar, n, rest, cache)

def vz_step.fresh(ar: O.Arena, +fx: F.Folded, +n: U32, rest: List<&2, VFr>, +cache: List<&2, U32>) -> VTopo:
  vz_step.hit(List.contains(U32, U32.is_eq, cache, n), ar, fx, n, rest, cache)

def vz_step.vis(ar: O.Arena, +fx: F.Folded, +n: U32, visited: Bool, rest: List<&2, VFr>, +cache: List<&2, U32>) -> VTopo:
  match visited:
    case True{}: vz_cache_add(n, VTopo{cache, rest})
    case False{}: vz_step.fresh(ar, fx, n, rest, cache)

def vz_step(ar: O.Arena, +fx: F.Folded, t: VTopo) -> VTopo:
  match t:
    case VTopo{cache, stack}:
      match stack:
        case Nil{}: t
        case VFr{n, seen} <> rest: vz_step.vis(ar, fx, n, seen, rest, cache)

def vz_topo.go(fuel: Nat, +ar: O.Arena, +fx: F.Folded, t: VTopo) -> List<&2, U32>:
  match fuel:
    case 0n: vz_cache_of(t)
    case 1n+p: vz_topo.go(p, ar, fx, vz_step(ar, fx, t))

def vz_one.hit(+acc: Vz, +s: Sol, +a: ZAt, u: U32) -> Vz:
  Bool.pick(Vz, ZAt.hit(a),
            Vz{Sol.put(s, u, ZAt.t(a)), vz_vs(acc)},
            Vz{s, List.append(&2, String, vz_vs(acc), [ZAt.v(a)])})

def validate_index_with_z3(sz: U32, +acc: Vz, idx: U32) -> Rep:
  Rep{sz, vz_vs(acc), cs_str(vz_cs(acc)), vz_term(acc, idx)}

# `z3_shift`. `lo = max(0, src[1].vmin)`; divide or multiply by `1<<lo`; then
# ONE `If` per bit of `max(0, src[1].vmax - lo)`; then
# `If(b < 0, FreshInt("invalid_shift"), a)`.
#
# The Python `for i in range(...)` is a `Nat` COUNTDOWN and it is the FIRST
# parameter with `case 0n:` listed FIRST, so the `1n+p` prefix cannot swallow
# the base case (the notes' correction section). `i` is a separate `U32`
# parameter because `case 1n+p:` SPENDS the scrutinee.
# `ar`, `s` and `self` are NOT parameters: Python passes `x` only because
# `z3_alu`'s signature is uniform, and nothing in the body reads it.
def z3_shift(+is_shr: Bool, a: Z, b: Z, +lo: U32, steps: U32) -> Z:
  z3_shift.go(U32.to_nat(steps), is_shr, z3_scale(is_shr, a, z3_pow(lo)), b, lo, 0)

# rule 3 -- `(PARAM, BUFFER, ALLOC, LOAD, INDEX)` -> `create_var`.
def ren_3(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  create_var(s, vz_mm(ar, s, self), S.Dt.is_bool(vz_dt(fx, self)),
             ren_3_name(ar, self, Sol.n(s)), "rule 3 create_var: unknown bounds")

# rule 5 -- a BITCAST between INT dtypes wraps into the target range. The
# modulo is `2**(8*itemsize)`, which for every integer dtype is `2**32` or
# more, and Bend's `U32` is ALREADY mod `2**32`: `z3_pow(32) = 0` and
# `U32.mod(x, 0) = x`, which is the same value. At itemsize 8 z3 computes mod
# `2**64` and the port cannot, so that is a VIOLATION and not a wrong number.
def ren_5(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_5.put(zat.src(ar, s, self, 0, "rule 5 x"),
            ren_5.dmin(S.Dt.min(vz_dt(fx, self)), S.Dt.itemsize(vz_dt(fx, self))), s)

# `z3.If(c, a, b)` -- three srcs, in `(cond, a, b)` order.
def ren_9.w3(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.w3.put(zat.src(ar, s, self, 0, "rule 9 cond"), zat.src(ar, s, self, 1, "rule 9 a"),
               zat.src(ar, s, self, 2, "rule 9 b"), s)

def ren_9.sh.z(is_shr: Bool, a: ZAt, b: ZAt, +r: MM) -> Z:
  z3_shift(is_shr, ZAt.t(a), ZAt.t(b), vz_max0(MM.lo(r)), z3_shift.steps(MM.hi(r), vz_max0(MM.lo(r))))

# `arg=Invalid` -- `O.CInvalid` inside `O.APy`.
def t_invalid(+ar: O.Arena, +i: U32) -> Bool:
  t_invalid.go(O.Arena.op(ar, i), O.Arena.arg(ar, i))

# rule 3 -- `UPat((Ops.PARAM, Ops.BUFFER, Ops.ALLOC, Ops.LOAD, Ops.INDEX), name="x")`
def ren_t3(+ar: O.Arena, +self: U32) -> Bool:
  ren_t3.put(O.Arena.op(ar, self))

# rule 4 -- `UPat((Ops.CAST, Ops.BITCAST) + tuple(GroupOp.Comparison),
# src=UPat(dtype=dtypes.floats), name="x")`
def ren_t4(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  ren_t4.put(ren_t4_op(O.Arena.op(ar, self)), O.Arena.nsrc(ar, self), ar, fx, self)

# rule 5 -- `UPat(Ops.BITCAST, dtypes.ints, src=(UPat.var("x", dtypes.ints),), name="c")`
def ren_t5(+ar: O.Arena, +fx: F.Folded, +self: U32) -> Bool:
  ren_t5.put(ren_t4_op(O.Arena.op(ar, self)), O.Arena.nsrc(ar, self), ar, fx, self)

# rule 10 -- `GroupOp.ALU` minus `z3_alu`, i.e. `python_alu`. The integer ops
# are `operator.*` and are one `Z` constructor each. The FLOAT ops
# (LOG2/EXP2/SQRT/RECIPROCAL/SIN/POW/TRUNC) and FDIV are NOT PORTED: they are
# `math.*` on a SYMBOLIC z3 value, which CPython itself cannot do -- MEASURED,
# `python_alu[TRUNC]` on a z3 int is `TypeError: must be real number, not
# ArithRef` and `python_alu[FDIV]` is a `KeyError`. They are also UNREACHABLE
# from `validate_index_with_z3`, because the toposort gate drops every
# float-dtype node and every one of those ops has a float dtype. So the arm is
# a violation rather than a missing answer.
def ren_10(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_10.go(O.Arena.op(ar, self), ar, s, self)

def vz_topo(fuel: Nat, ar: O.Arena, +fx: F.Folded, t: VTopo) -> List<&2, U32>:
  vz_topo.go(fuel, ar, fx, t)

def vz_one.put(+acc: Vz, r: Ren, u: U32) -> Vz:
  match r:
    case Ren{s, a}: vz_one.hit(acc, s, a, u)

def z3_and.bv2(w: U32, a: Z, b: Z) -> Maybe<&1, Z>:
  z3_bv.put(bv_and(), Some{w}, a, b)

def ren_9.sh.hit(is_shr: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  Ren{s, zat.hit(ren_9.sh.z(is_shr, a, b, r))}

def ren_t1.put2(is_where: Bool, nsrc: U32, +ar: O.Arena, +self: U32) -> Bool:
  Bool.and(is_where, Bool.and(U32.is_eq(nsrc, 3), t_invalid(ar, O.Arena.src(ar, self, 2))))

# `lo = max(0, int(vmax_of(src[1]).vmin))` and `steps = bit_len(vmax - lo)`.
def ren_9.sh.term(is_shr: Bool, ok: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  Bool.pick(Ren, ok, ren_9.sh.hit(is_shr, a, b, r, s), Ren{s, zat.miss(zwhy(a, b))})

def ren_t1.put(op: O.Op, nsrc: U32, +ar: O.Arena, +self: U32) -> Bool:
  ren_t1.put2(O.eq_op(op, O.OpsWHERE{}), nsrc, ar, self)

def ren_9.sh.ok2(is_shr: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  ren_9.sh.term(is_shr, zall(a, b), a, b, r, s)

# rule 1's shape -- `UPat.var("cond").where(UPat.var("x"), UPat(Ops.CONST,
# arg=Invalid))`. A WHERE is 3-src, so the third src is the `Invalid` CONST.
def ren_t1(+ar: O.Arena, +self: U32) -> Bool:
  ren_t1.put(O.Arena.op(ar, self), O.Arena.nsrc(ar, self), ar, self)

def ren_tag(+ar: O.Arena, +fx: F.Folded, +self: U32) -> U32:
  rt_first([rt(ren_t1(ar, self), 0), rt(ren_t2(ar, self), 1), rt(ren_t3(ar, self), 2),
            rt(ren_t4(ar, fx, self), 3), rt(ren_t5(ar, fx, self), 4), rt(ren_t6(ar, self), 5),
            rt(ren_t7(ar, self), 6), rt(ren_t8(ar, self), 7), rt(ren_t9(ar, self), 8),
            rt(ren_t10(ar, self), 9)])

def ren_9.sh.ok(is_shr: Bool, +a: ZAt, +b: ZAt, r: MM, +s: Sol) -> Ren:
  ren_9.sh.ok2(is_shr, a, b, r, s)

# `lo` and the loop count both come from `src[1]`, so the `Maybe` is matched
# ONCE and its two fields become two binders.
def ren_9.sh.go(is_shr: Bool, +a: ZAt, +b: ZAt, m: Maybe<&1, MM>, +s: Sol) -> Ren:
  match m:
    case Some{+r}: ren_9.sh.ok(is_shr, a, b, r, s)
    case None{}: Ren{s, zat.miss("rule 9 z3_shift: unknown bounds for src[1]")}

def ren_9.sh.put(is_shr: Bool, +a: ZAt, +b: ZAt, m: Maybe<&1, MM>, +s: Sol) -> Ren:
  ren_9.sh.go(is_shr, a, b, m, s)

# `z3_shift`: `lo` and the loop count both come from `src[1]`, and one missing
# bound is one violation.
def ren_9.sh(is_shr: Bool, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.sh.put(is_shr, zat.src(ar, s, self, 0, "rule 9 a"), zat.src(ar, s, self, 1, "rule 9 b"),
               vz_mm(ar, s, O.Arena.src(ar, self, 1)), s)

# Two bit-blast attempts, so two reads of the one `Maybe` -- hence the `Wv`
# pair, bound ONCE, which is the whole reason `Wv` exists. `+bv` on a `Maybe` is
# refused ("+bv can be used many times, so its type must be Data"), so the pair
# is the answer and not a choice.
def z3_xor(+k: U32, +w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_xor.m2(Z.is_b(a), z3_xor.m1(Z.num(b), a, z3_xor.wv(w, a, b, k)),
            Z.num(a), z3_xor.wv(w, a, b, k), a, b, w)

# the bit-blast arm is a LEAF so the one `Maybe` read it needs is its own.
def z3_and.bv(+w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, Wv.got(w), z3_and.bv2(Wv.w(w), a, b), None{})

def wv0.go(w: Wv) -> Maybe<&1, U32>:
  match w:
    case Wv{got, w}: Some{w}
    case _: None{}

def z3_and.pw8(+v: U32, +w: Wv, +a: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, pow2(U32.sub(0, v)),
            Some{ZSub{a, ZMod{a, ZLit{U32.sub(0, v), False{}}}}},
            z3_and.bv(w, a, ZLit{v, False{}}))

# `(m := b+1) > 0 and m&(m-1) == 0` then `(m := -b) > 0 and ...`. `b+1 > 0` is
# `b >= 0` and `-b > 0` is `b < 0`, so the two cases are told apart by the sign
# of the literal, and each needs its own magnitude.
def z3_and.pw7(+v: U32, +w: Wv, +a: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, pow2(U32.add(v, 1)),
            Some{ZMod{a, ZLit{U32.add(v, 1), False{}}}}, z3_and.pw8(v, w, a))

def z3_and.pw6(n: Maybe<&1, U32>, +w: Wv, +a: Z) -> Maybe<&1, Z>:
  match n:
    case Some{v}: z3_and.pw7(v, w, a)
    case None{}: z3_and.bv(w, a, ZLit{0, False{}})

def z3_and.pw5(nb: Bool, +w: Wv, n: Maybe<&1, U32>, +a: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, nb, z3_and.pw6(n, w, a), z3_and.bv(w, a, ZLit{0, False{}}))

def z3_and.pw9(nb: Bool, m: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_and.pw5(nb, wv(m), Z.num(b), a)

# `if isinstance(a, z3.IntNumRef): a, b = b, a` -- then `b` is the literal.
# a `Wv` back to a `Maybe`, so the two swapped arms can each read it once
def wv0(w: Wv) -> Maybe<&1, U32>:
  wv0.go(w)

def z3_and.sw(na: Bool, +nb: Bool, +w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, na, z3_and.pw9(nb, wv0(w), b, a), z3_and.pw9(nb, wv0(w), a, b))

def z3_and.of(ab: Bool, na: Bool, nb: Bool, m: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, ab, Some{ZAnd{a, b}}, z3_and.sw(na, nb, wv(m), a, b))

# `z3_and`: a Bool AND wins, then SWAP so that `b` is the literal, then
# `x & (2^k-1) = x % 2^k` and `x & -(2^k) = x - x % 2^k`.
def z3_and(m: Maybe<&1, U32>, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_and.of(Z.is_b(a), Z.is_num(a), Z.is_num(b), m, a, b)

# `w` is read in BOTH arms of the `Bool.pick` and `+` is REFUSED on a `Maybe`,
# so it travels as the `Wv` pair. The second reason for the pair is the
# `.pw2` call: `Maybe` is a `Type` and is read once, so one read cannot be
# shared between two branches.
# `+bv` is a SHARED REFERENCE, not a copy: `m` is a `Maybe` (a `Type`), it
# cannot take a `+`, and `Bool.pick` evaluates both arms -- so the one read the
# bit-blast arm needs is bound to a `let` once. That is the notes' rule 1.5 and
# the "FIRE more rules" rule 2: a `let` is shared where a pattern binder is not.
# THE `Wv` IS BUILT ONCE, HERE, and everything below takes it. A `Maybe` is a
# `Type`, it cannot take a `+`, and `Bool.pick` evaluates both arms -- so a
# `Maybe` both arms need has to be decomposed at the TOP and not re-derived.
def z3_and.pw4(nb: Bool, +w: Wv, +a: Z, +b: Z) -> Maybe<&1, Z>:
  z3_and.pw5(nb, w, Z.num(a), ZLit{0, False{}})

def ren_9.bv.xq(a: ZAt, b: ZAt, w: Wv) -> Maybe<&1, Z>:
  z3_xor(bv_xor(), w, ZAt.t(a), ZAt.t(b))

def ren_9.bv.aa(a: ZAt, b: ZAt, w: Wv) -> Maybe<&1, Z>:
  z3_and(wv0(w), ZAt.t(a), ZAt.t(b))

def ren_9.bv.oo(a: ZAt, b: ZAt, w: Wv) -> Maybe<&1, Z>:
  z3_or(wv0(w), ZAt.t(a), ZAt.t(b))

# THE WIDTH IS A `Wv` HERE -- a Bool plus the value -- and each arm reads it
# once. That is the whole answer to "`Maybe` both arms need": decompose it at
# the top, never re-derive it per arm.
def ren_9.bv.z(zero: Bool, one: Bool, +a: ZAt, +b: ZAt, +w: Wv) -> Maybe<&1, Z>:
  Bool.pick(Maybe<&1, Z>, zero, ren_9.bv.aa(a, b, w),
    Bool.pick(Maybe<&1, Z>, one, ren_9.bv.oo(a, b, w), ren_9.bv.xq(a, b, w)))

def ren_9.bv.y(zero: Bool, one: Bool, a: ZAt, b: ZAt, m: Maybe<&1, U32>) -> Maybe<&1, Z>:
  ren_9.bv.z(zero, one, a, b, wv(m))

# the three arms each read the ONE `Maybe` width, so each is its own def; the
# width is rebuilt per arm rather than shared, which is the price of a `Maybe`
# being unreadable twice.
# ONE read of the width per def. `Maybe` is a `Type` and unreadable twice, so
# the choice is made by TWO `Bool`s computed by the CALLER and each arm takes
# the width as its OWN parameter. This is the notes' rule 3 in its last form:
# a `Maybe` both arms need must be decomposed at the top and not re-derived.
def ren_9.bv.k(+k: U32, a: ZAt, b: ZAt, m: Maybe<&1, U32>) -> Maybe<&1, Z>:
  ren_9.bv.y(U32.is_eq(k, bv_and()), U32.is_eq(k, bv_or()), a, b, m)

def ren_9.bv.ok(k: U32, +a: ZAt, +b: ZAt, w: Maybe<&1, U32>, +s: Sol) -> Ren:
  Ren{s, zm(ren_9.bv.k(k, a, b, w), "rule 9: unknown bounds for the bit-blast width")}

def ren_9.bv.put(k: U32, +a: ZAt, +b: ZAt, w: Maybe<&1, U32>, +s: Sol) -> Ren:
  Bool.pick(Ren, zall(a, b), ren_9.bv.ok(k, a, b, w, s), Ren{s, zat.miss(zwhy(a, b))})

# `z3_and` / `z3_or` / `z3_xor`: a `Maybe`, because the bit-blast needs the width.
def ren_9.bv(k: U32, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.bv.put(k, zat.src(ar, s, self, 0, "rule 9 src0"), zat.src(ar, s, self, 1, "rule 9 src1"),
               bv_w(ar, s, self), s)

def ren_9.go(op: O.Op, +ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  match op:
    case O.OpsCMOD{}: ren_9.b2(1, ar, s, self)
    case O.OpsCDIV{}: ren_9.b2(2, ar, s, self)
    case O.OpsFLOORDIV{}: ren_9.b2(2, ar, s, self)
    case O.OpsFLOORMOD{}: ren_9.b2(3, ar, s, self)
    case O.OpsMAX{}: ren_9.mx(ar, s, self)
    case O.OpsWHERE{}: ren_9.w3(ar, s, self)
    case O.OpsAND{}: ren_9.bv(bv_and(), ar, s, self)
    case O.OpsOR{}: ren_9.bv(bv_or(), ar, s, self)
    case O.OpsXOR{}: ren_9.bv(bv_xor(), ar, s, self)
    case O.OpsSHL{}: ren_9.sh(False{}, ar, s, self)
    case O.OpsSHR{}: ren_9.sh(True{}, ar, s, self)
    # the arm is reachable only for an op the tag ladder sent to rule 9, and a
    # `Data` match must name every remaining constructor -- so the LAST is `case _:`
    # and it is `ren_9.w3`, which is the right answer for any WHERE arity.
    case _: ren_9.w3(ar, s, self)

# rule 9 -- `z3_alu[x.op]`, the eleven bound-aware ops. ONE `match` on the op
# with eleven arms is the whole table, and each arm names the shape it reads:
# two srcs, three srcs, or a `Maybe`-returning builder.
def ren_9(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_9.go(O.Arena.op(ar, self), ar, s, self)

def Rep.sz(r: Rep) -> U32:
  match r:
    case Rep{sz, vs, cs, term}: sz

def Rep.vs(r: Rep) -> List<&2, String>:
  match r:
    case Rep{sz, vs, cs, term}: vs

def Rep.cs(r: Rep) -> String:
  match r:
    case Rep{sz, vs, cs, term}: cs

def Rep.term(r: Rep) -> String:
  match r:
    case Rep{sz, vs, cs, term}: term

def vs_str.go(+vs: List<&2, String>, +acc: String) -> String:
  match vs:
    case Nil{}: acc
    case h <> t: vs_str.go(t, Bool.pick(String, U32.is_eq(U32.from_nat(List.length(&2, String, vs)), 1),
                                         acc, String.concat([acc, "; ", h])))

def vs_str(vs: List<&2, String>) -> String:
  vs_str.go(vs, "")

def n_vs(vs: List<&2, String>) -> U32:
  U32.from_nat(List.length(&2, String, vs))

# `str(solver)` | `str(z3map[idx])` | violations | violation COUNT
def row(+r: Rep) -> String:
  String.concat([Rep.cs(r), " | ", Rep.term(r), " | ", vs_str(Rep.vs(r)), " | ",
                 U32.show(n_vs(Rep.vs(r)))])

def dv.of(nm: String, +acc: Vz, idx: U32) -> String:
  String.concat([nm, " | ", row(validate_index_with_z3(16, acc, idx))])

# `UOp.variable(name, vmin, vmax)` -- ops.py:669. The node is a PARAM, so
# `create_var` takes its name from `x.arg.name` and NOT from the counter, which
# is what makes the row `And(i >= 0, i <= 15)` and not `And(param2 >= ...)`.
#
# `ParamArg` HAS THIRTEEN FIELDS and a record literal must name every one of
# them, so this is one long line rather than a builder nobody else would read.
def fx_var(ar: O.Arena, slot: U32, nm: String, dtype: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{slot, dtype, None{}, None{}, None{}, Some{nm}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}},
    O.TNone{})

# the `_min_max` entry for a fixture variable
def mm_i(n: U32, lo: U32, hi: U32) -> List<&2, MRng>:
  [MRng{n, lo, hi}]

def fx_const(ar: O.Arena, v: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_hi_lo(0, v)})

def fx_const_bool(ar: O.Arena, b: Bool) -> O.Found:
  O.UOp.const(ar, O.CBool{b})

def fx_const_invalid(ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInvalid{})

# `UOp.range(n, 0, AxisType)` -- the end is a CONST and `ids` is the axis-id
# tuple `range_str` reads. CPython's `range_str` is the AXIS IDS and NOT the axis
# type (ops.py:97), which is why `dv_range_global` and `dv_range_loop` must print
# the SAME text and `dv_range_m1` must not.
def fx_range(+ar: O.Arena, n: U32, ids: List<&2, U32>, at: O.AxisType) -> O.Found:
  +e = fx_const(ar, n)
  O.UOp.range_end(O.Found.ar(e), O.Found.i(e), ids, at)

# --- "a RANGE(hi) `op` CONST(k)", the builder every ALU row shares.
def dv_bin(+ar: O.Arena, op: O.Op, hi: U32, k: U32) -> O.Found:
  +r = fx_range(ar, hi, [0], O.AXIS_GLOBAL{})
  +c = fx_const(O.Found.ar(r), k)
  O.UOp.new(O.Found.ar(c), op, [O.Found.i(r), O.Found.i(c)], O.ANone{}, O.TNone{})

def dv_and.mm2(+ar: O.Arena, +t: O.Found) -> List<&2, MRng>:
  mm_i(O.Arena.src(ar, O.Found.i(t), 0), 0, 99)

# --- `n_z3_alu`: the ELEVEN keys of `z3_alu`, which is `tuple(z3_alu)`'s whole
# content. A COUNT, because the membership is what a dropped key breaks and a
# boolean cannot see a dropped key.
def n_z3_alu() -> U32:
  U32.from_nat(List.length(&2, O.Op, z3_alu_ops()))

# the RANGE's `_min_max` is `(0, hi - 1)` -- `range_str`'s bound is
# `ctx[1][src[0]] - 1` and this table is the only place the SAME fact appears as
# a number, so a wrong `hi` here moves `dv_and21` and nothing else.
def dv_and.mm(+ar: O.Arena, +t: O.Found) -> List<&2, MRng>:
  dv_and.mm2(ar, t)

def rs_ids.acc(ids: List<&2, U32>) -> String:
  rs_ids.go(ids, "", "")

def range_str.go(a: O.Arg) -> String:
  match a:
    case O.ARange{ids, at}: rs_ids.acc(ids)
    case _: ""

def range_str(ar: O.Arena, i: U32) -> String:
  range_str.go(O.Arena.arg(ar, i))

def ren_2_name.go(op: O.Op, +ar: O.Arena, i: U32) -> String:
  match op:
    case O.OpsSPECIAL{}: range_str.go(O.Arena.arg(ar, i))
    case _: String.concat(["r", range_str(ar, i)])

def ren_2_name(+ar: O.Arena, +i: U32) -> String:
  ren_2_name.go(O.Arena.op(ar, i), ar, i)

# rule 2 -- `(SPECIAL, RANGE)`: `x.arg` for a SPECIAL, `f"r{range_str(x)}"` for a
# RANGE, bounded by `[0, ctx[1][src[0]] - 1]`. The bound is a z3 EXPRESSION and
# not a number, which is why a symbolic RANGE bound needs the solver and a
# constant one does not.
def ren_2(+ar: O.Arena, +s: Sol, +self: U32) -> Ren:
  ren_2.put(zat.src(ar, s, self, 0, "rule 2 vmax"), ren_2_name(ar, self), s)

def ren_dispatch.go(tag: U32, +ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  match tag:
    case 0: ren_1(ar, s, self)
    case 1: ren_2(ar, s, self)
    case 2: ren_3(ar, fx, s, self)
    case 3: ren_4(ar, fx, s, self)
    case 4: ren_5(ar, fx, s, self)
    case 5: ren_6(ar, s, self)
    case 6: ren_7(ar, fx, s, self)
    case 7: ren_8(ar, fx, s, self)
    case 8: ren_9(ar, s, self)
    case 9: ren_10(ar, s, self)
    case _: ren_unsup(ar, s, self)

def ren_dispatch(tag: U32, +ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_dispatch.go(tag, ar, fx, s, self)

def ren(+ar: O.Arena, +fx: F.Folded, +s: Sol, +self: U32) -> Ren:
  ren_dispatch(ren_tag(ar, fx, self), ar, fx, s, self)

def vz_one(+ar: O.Arena, +fx: F.Folded, +acc: Vz, +u: U32) -> Vz:
  vz_one.put(acc, ren(ar, fx, vz_s(acc), u), u)

def vz_walk(todo: List<&2, U32>, +ar: O.Arena, +fx: F.Folded, +acc: Vz) -> Vz:
  match todo:
    case Nil{}: acc
    case u <> t: vz_walk(t, ar, fx, vz_one(ar, fx, acc, u))

def uops_to_z3.of(+ar: O.Arena, ms: List<&2, MRng>, snk: O.Found) -> Vz:
  vz_walk(vz_drop_sink(vz_topo(O.Arena.budget(ar), ar, F.folded(ar),
                                VTopo{Nil{}, [VFr{O.Found.i(snk), False{}}]}), ar, Nil{}),
         ar, F.folded(ar), Vz{Sol{Nil{}, Nil{}, ms}, Nil{}})

def uops_to_z3.sink(+ar: O.Arena, ms: List<&2, MRng>, +snk: O.Found) -> Vz:
  uops_to_z3.of(O.Found.ar(snk), ms, snk)

# `UOp.sink(*uops)` GROWS the arena, so the fold is taken AFTER it -- a `Folded`
# of the pre-sink arena is a fold of a store that does not contain the node the
# walk starts from, which is the "sibling arena" trap `mixin/rand.bend` measured.
#
# `ms` is `UOp._min_max`, which `fold.bend` does not have (P3). It is a
# PARAMETER here and the fixture supplies it; CPython's `UOp.variable(name, lo,
# hi)` sets `_min_max` explicitly, so both sides carry the same literals -- and
# they are CHECKED, because the bounds appear in the constraint text.
# THE SINK IS BOUND TO A `let` AND THE ARENA IS READ OFF IT. `O.UOp.sink` GROWS
# the arena, so `uops_to_z3.of(ar, ms, O.UOp.sink(ar, [idx, gate]))` hands `.of`
# the PRE-SINK store and a SINK index that is not in it -- and the whole toposort
# comes back empty. MEASURED: that spelling prints `[] |  |  | 0` on every row,
# with no error anywhere. `+snk = ...` then `O.Found.ar(snk)` is the same shape
# every growing fixture in this port uses.
def uops_to_z3(+ar: O.Arena, +ms: List<&2, MRng>, idx: U32, gate: U32) -> Vz:
  uops_to_z3.sink(ar, ms, O.UOp.sink(ar, [idx, gate]))

def dv2(nm: String, +t: O.Found, g: O.Found, ms: List<&2, MRng>) -> String:
  dv.of(nm, uops_to_z3(O.Found.ar(t), ms, O.Found.i(t), O.Found.i(g)), O.Found.i(t))

def dv_const_ok.of(+ar: O.Arena, nm: String) -> String:
  +t = fx_const(ar, 15)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_var.of(+ar: O.Arena, nm: String, lo: U32, hi: U32) -> String:
  +v = fx_var(ar, 0, "i", S.int32())
  +g = fx_const_bool(O.Found.ar(v), True{})
  dv2(nm, v, g, mm_i(O.Found.i(v), lo, hi))

def dv_range.of(+ar: O.Arena, at: O.AxisType, ids: List<&2, U32>, nm: String) -> String:
  +t = fx_range(ar, 100, ids, at)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

# `O.Found.ar(t)`, NOT `ar`. `dv_bin` MINTS, so `t` was interned into the arena it RETURNED
# and `ar` is the one that went in; `dv_and.mm2` then read `Arena.src(ar, Found.i(t), 0)`,
# an index the arena never interned. MEASURED by `.agents/slop/arena-validate-probe.bend`:
# `idx=4 in_pre_mint_arena=None in_found_arena=Some pre_src0=0 found_src0=2`, and the range
# it builds came out `u=0:0:99` instead of `u=2:0:99` -- built from the arena BOTTOM.
# `Arena.node` is total, so that read answered `0` and nothing anywhere reported it.
#
# ⚠ NO COMMITTED ROW MOVES. The `dv_shr2` row's fourth field is empty both before and after,
# because an empty z3 range list and a wrong z3 range list print the same. So this fix is
# argued by the `at`-based probe above and NOT by a gate row, and `dv_shr2` has no CPython
# oracle in `.agents/slop/` at all. Reported as a COVERAGE GAP, not as a gated fix.
def dv_shr2.of(+ar: O.Arena, nm: String) -> String:
  +t = dv_bin(ar, O.OpsSHR{}, 64, 2)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, dv_and.mm2(O.Found.ar(t), t))

def dv_where.of(+ar: O.Arena, nm: String) -> String:
  +v = fx_var(ar, 0, "v", S.int32())
  +c8 = fx_const(O.Found.ar(v), 8)
  +cm = O.UOp.new(O.Found.ar(c8), O.OpsCMPLT{}, [O.Found.i(v), O.Found.i(c8)], O.ANone{}, O.TNone{})
  +inv = fx_const_invalid(O.Found.ar(cm))
  +t = O.UOp.new(O.Found.ar(inv), O.OpsWHERE{}, [O.Found.i(cm), O.Found.i(v), O.Found.i(inv)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, mm_i(O.Found.i(v), 0, 15))

def dv_const_invalid.of(+ar: O.Arena, nm: String) -> String:
  +t = fx_const_invalid(ar)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_unsup_stack.of(+ar: O.Arena, nm: String) -> String:
  +c2 = fx_const(ar, 2)
  +c3 = fx_const(O.Found.ar(c2), 3)
  +t = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c2), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_unsup_two.of(+ar: O.Arena, nm: String) -> String:
  +c2 = fx_const(ar, 2)
  +c3 = fx_const(O.Found.ar(c2), 3)
  +c5 = fx_const(O.Found.ar(c3), 5)
  +c7 = fx_const(O.Found.ar(c5), 7)
  +s1 = O.UOp.new(O.Found.ar(c7), O.OpsSTACK{}, [O.Found.i(c2), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +s2 = O.UOp.new(O.Found.ar(s1), O.OpsSTACK{}, [O.Found.i(c5), O.Found.i(c7)], O.ANone{}, O.TNone{})
  +t = O.UOp.new(O.Found.ar(s2), O.OpsGROUP{}, [O.Found.i(s1), O.Found.i(s2)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_rank_shr1.of(+ar: O.Arena, nm: String) -> String:
  +r = fx_range(ar, 8, [0], O.AXIS_GLOBAL{})
  +t = O.UOp.new(O.Found.ar(r), O.OpsSHL{}, [O.Found.i(r)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

def dv_bad_dtype_bitcast.of(+ar: O.Arena, nm: String) -> String:
  +r = fx_range(ar, 16, [0], O.AXIS_GLOBAL{})
  +t = O.UOp.new(O.Found.ar(r), O.OpsBITCAST{}, [O.Found.i(r), O.Found.i(r)], O.ANone{}, O.TNone{})
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, Nil{})

# --- THE POSITIVE ROW, and the shortest legal index there is: `UOp.const(15)`
# with the `UOp.const(True)` mask. CPython answers `[True]` -- the mask alone,
# because a CONST contributes no assertion -- and the term is `15`. A validator
# gate with no positive row is a gate that cannot pass.
def dv_const_ok() -> String:
  dv_const_ok.of(O.Arena.empty(), "dv_const_ok")

# --- A BOUNDED VARIABLE. `create_var`'s name is `x.arg.name`, so the symbol is
# `i` and NOT `param2` -- which is what makes the counter arm (`index2`, `load3`)
# and the `arg.name` arm two DIFFERENT rows rather than one.
def dv_var() -> String:
  dv_var.of(O.Arena.empty(), "dv_var", 0, 15)

# --- A NEGATIVE LOWER BOUND, `UOp.variable("i", -5, 10)`. `z_i` prints `-5` and
# not `4294967291`, and a negative lower bound is where a two's-complement literal
# meets z3's numeral-hoisting printer: MEASURED, `And(i >= -5, i <= 10)`.
def dv_var_neg() -> String:
  dv_var.of(O.Arena.empty(), "dv_var_neg", 4294967291, 10)

def dv_range(at: O.AxisType, ids: List<&2, U32>, nm: String) -> String:
  dv_range.of(O.Arena.empty(), at, ids, nm)

# --- `z3_shift` with a CONSTANT count. `lo = max(0, vmin(src[1])) = 2`, the loop
# count is `bit_len(vmax - lo) = bit_len(0) = 0` -- SO NO `If` IS BUILT -- and the
# tail is `If(b < 0, invalid_shift, a)`. The term is `If(0 > 2, invalid_shift,
# r0/4)`, and `0 > 2` is z3's numeral-hoisting rule and not a typo.
def dv_shr2() -> String:
  dv_shr2.of(O.Arena.empty(), "dv_shr2")

# --- THE CONSTRAINT ROW. `r.valid(r < 16)` is a three-src WHERE whose third src
# is `CONST(Invalid)`, so rule 1 fires: the CONDITION goes into the solver and the
# node's own value is `x`, the SECOND src. It is the only row where `cs` grows
# past `[True]`, and so the only row that sees rule 1 at all.
def dv_where() -> String:
  dv_where.of(O.Arena.empty(), "dv_where")

# --- THE `Invalid` CONST. Rules 6 and 7 BOTH claim `Ops.CONST` and give
# DIFFERENT answers -- a free `Invalid` symbol against the value as a literal --
# so this is a FIRST-WINS row, and the term `Invalid` says which rule won.
def dv_const_invalid() -> String:
  dv_const_invalid.of(O.Arena.empty(), "dv_const_invalid")

# --- THE VIOLATION TEXT. `Ops.STACK` is int-typed so the toposort gate KEEPS it
# and NO rule claims it, which is the one shape that reaches `uops_to_z3:87`.
# MEASURED: `NotImplementedError: Ops.STACK is not supported by z3`, and
# `O.Ops.name` is `str(Ops.STACK)` byte for byte.
def dv_unsup_stack() -> String:
  dv_unsup_stack.of(O.Arena.empty(), "dv_unsup_stack")

# --- THE COUNT ROW. CPython STOPS at the first unsupported op; this collects
# BOTH, so `n=2` is the strengthening the file header declares and this row pins
# it. Two STACKs over the SAME constants is the fixture: hash-consing makes them
# the SAME node, so a two-node graph needs two DISTINCT masks.
def dv_unsup_two() -> String:
  dv_unsup_two.of(O.Arena.empty(), "dv_unsup_two")

# --- A MISSING ARG. `Ops.SHL` with ONE src: `z3_shift` reads `x.src[1]` and
# CPython raises `IndexError: tuple index out of range`. The port cannot raise,
# so it is a violation, and its text BEGINS with `O.Ops.name` -- the half that
# CPython's own message shape agrees on.
def dv_rank_shr1() -> String:
  dv_rank_shr1.of(O.Arena.empty(), "dv_rank_shr1")

# --- A WRONG ARITY AND DTYPE ON AN ARG. `Ops.BITCAST` with TWO srcs and an int
# dtype: `src=(UPat.var("x", dtypes.ints),)` is a ONE-tuple, so rule 5's shape
# test fails on arity, rules 9 and 10 do not claim BITCAST, and the op is
# unsupported -- a DIFFERENT text from `dv_rank_shr1` for a different op.
def dv_bad_dtype_bitcast() -> String:
  dv_bad_dtype_bitcast.of(O.Arena.empty(), "dv_bad_dtype_bitcast")

# THE SAME STALE ARENA AS `dv_shr2.of`, and this one sits behind the `dv_and*` rows.
# `dv_bin` MINTS, so `t` lives in the arena it returned and `ar` is the one that went in;
# `dv_and.mm(ar, t)` then read an index `ar` never interned. PROVEN by
# `.agents/slop/arena-validate-probe.bend`: `in_pre_mint_arena=None`.
#
# ⚠⚠ THIS CHANGES THREE ROWS AND **THE DIRECTION IS NOT YET ADJUDICATED**. `dv_and15`,
# `dv_and21` and `dv_and_neg4` moved from `... BV2Int(...) - 1 ...` to `... - 256 ...`, and
# that `1` is `2**(w-1)` for the bit width `validate.py:16` computes from `vmin`/`vmax` --
# so the stale read was supplying the arena BOTTOM's bounds (all zero, hence `w=1`) and the
# fix supplies the real node's. **`z3` IS NOT INSTALLED IN THIS ENVIRONMENT**, so CPython's
# `uops_to_z3` could not be CALLED, and `dv_and*` has no oracle anywhere in `.agents/slop/`.
# A hand-derivation of `validate.py:16` gives `w=8` -> bound 128, which matches NEITHER 1 NOR
# 256, so it settles nothing.
#
# SO: THE ALIASING IS PROVEN AND THE FIX IS RIGHT BY THAT PROOF; WHETHER `- 256` IS WHAT
# CPython ANSWERS IS **NOT ESTABLISHED**, and this row must not be called green until an
# oracle exists. Recorded as an OPEN QUESTION, not as a gated fix. `dv_shr2.of` above moves
# NO row and has no such question.
def dv_and.put(+ar: O.Arena, nm: String, k: U32) -> String:
  +t = dv_bin(ar, O.OpsAND{}, 100, k)
  +g = fx_const_bool(O.Found.ar(t), True{})
  dv2(nm, t, g, dv_and.mm(O.Found.ar(t), t))

def dv_and.of(+ar: O.Arena, nm: String, k: U32) -> String:
  dv_and.put(ar, nm, k)

# --- `z3_and`'s FIRST constant case, `x & (2^k-1) = x % 2^k`. MEASURED, `r & 15`
# renders `(mod r0 16)` and contributes NO ASSERTION -- so the constraint list is
# unchanged and this row is visible only in the TERM column.
def dv_and15() -> String:
  dv_and.of(O.Arena.empty(), "dv_and15", 15)

# --- `z3_and`'s SECOND constant case, `x & -(2^k) = x - x % 2^k`, which is the
# only shape where the mask is NEGATIVE and the only row that puts a
# two's-complement literal through `z3_and`'s own arithmetic.
def dv_and_neg4() -> String:
  dv_and.of(O.Arena.empty(), "dv_and_neg4", 4294967292)

# --- `z3_and`'s BIT-BLAST fallback, the ONLY path through `z3_bv` and so the only
# row that sees the WIDTH. MEASURED: `r & 21` over a RANGE(100) picks width 8,
# from `1 + max(bit_length(99), bit_length(21), bit_length(-99),
# bit_length(-21))`. The `_min_max` table supplies the RANGE's `0..99`.
def dv_and21() -> String:
  dv_and.of(O.Arena.empty(), "dv_and21", 21)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(dv_const_ok())
    IO.print(dv_var())
    IO.print(dv_var_neg())
    IO.print(dv_range(O.AXIS_GLOBAL{}, [0], "dv_range_global"))
    IO.print(dv_range(O.AXIS_LOOP{}, [0], "dv_range_loop"))
    IO.print(dv_range(O.AXIS_GLOBAL{}, [4294967295], "dv_range_m1"))
    IO.print(dv_and15())
    IO.print(dv_and_neg4())
    IO.print(dv_and21())
    IO.print(dv_shr2())
    IO.print(dv_where())
    IO.print(dv_const_invalid())
    IO.print(dv_unsup_stack())
    IO.print(dv_unsup_two())
    IO.print(dv_rank_shr1())
    IO.print(dv_bad_dtype_bitcast())
    IO.print(String.concat(["n_z3_alu=", U32.show(n_z3_alu())]))
    IO.print("done")
