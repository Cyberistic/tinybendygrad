# crp_graph_census.bend -- A PROMOTION CENSUS over `tinybendygrad/mixin/creation.bend`.
#
#   .venv/bin/python gates/crp_graph_census-gate.py
#   .venv/bin/python gates/crp_graph_census-gate.py --refresh
#
# 287 ROWS, 3 LANES, 286 EXACT MATCHES AND 1 DECLARED DIVERGENCE (`el_weakint`, W3's
# missing vmin/vmax). THE `sz=` IN AN `ALLOC/0[...]` TOKEN IS `src[0]` ON BOTH SIDES.
#
# WHY A SECOND CENSUS AND NOT A WIDER `cr_graph_census`. The sibling EXISTS and is GREEN
# (MEASURED rc=0, 28 rows), which is not what this file's brief said. What it prints is
# `O.Rng.sig`: the node COUNT, the ROOT op, the ROOT's src COUNT and the ROOT's src op
# SEQUENCE. `realize_graph_census-oracle.py:38-44` names that instrument's own failure --
# "a 3-op PREFIX and no ARG, and `gr_10` printed identically on both sides until a deep
# printer was used" -- and `creation.bend`'s own header says the same of ITS gate: "THE
# FLOAT ARM IS THE SILENT ONE: there both consts cast, so the COUNT agrees and only the
# CONST's ARG differs, which `Rng.sig` did not print before this session."
#
# So this file prints the whole CONE and, inside it, the CONST's VALUE, the ALLOC's
# `ParamArg` and the CAST's TARGET. Four facts become visible that a prefix cannot hold:
#
#   * THE FOLD. `ops.py:634` is `UOp(CONST, arg=dt.const(b)).cast(dt)` and its comment
#     says ".cast folds away at exactly the dtypes a CONST derives". MEASURED over this
#     census's own 20-dtype axis: 9 nodes at `bool`/`weakint`/`weakfloat`, 10 everywhere
#     else, and the SAME 9/10 split for a bool, an int and a float fill value.
#   * THE ALLOC's DTYPE. `full`'s buffer dtype is `dt if dt not in weaks else
#     commit_dtype()` (creation.py:86), so `zeros(2,3,dtype=weakint)` stores an `i32`
#     buffer, not a `weakint` one, and so does `zeros(2,3,dtype=weakint,buffer=False)
#     .empty_like()`. `Rng.sig` prints no `ParamArg`, so `ALLOC/0` read alike for all 20.
#   * THE CONST's ARG. `DType.const` (dtype.py:79-84) is `ConstFloat(truncate[dt](v))`
#     for a float, `bool(v)` for a bool and `int(v)` otherwise, so ONE call holds `1.0` at
#     `f16` and `1` at `i32`. `Rng.sig` prints `CONST/0` for both.
#   * THE CAST's ARG. `cr_cast` (creation.bend:217) mints `OpsCAST` with `O.ADt{dt}` --
#     ops.py:640's `arg=dt` -- and `cr_const_of` hands it the `de` it also uses as the fold
#     test's right-hand side (creation.bend:245). MEASURED BEFORE `tok.arg` grew its `ADt`
#     arm: 118 `CAST/1` occurrences across this census's 207 rows and NOT ONE carried an
#     argument, on EITHER lane, so the target of every cast in the census was unreadable and
#     a wrong one could not move a row. IT IS `OP/NSRC[TARGET]` NOW, WHERE `[TARGET]` IS
#     `T.dt_name` -- `S.Dt{pri, bits, cls, nm}` PROJECTED ONTO `nm` -- WHICH IS CPYTHON'S OWN
#     `DType.name` WITH NO TABLE ON EITHER SIDE (`gates/crp_graph_census-oracle.py`'s `tok`
#     prints `u.arg.name` and `dtypes_hold` asserts the twenty `nm` fields against
#     `dir(dtypes)`). MEASURED AFTER: 118 argument-bearing casts on each lane, 22 at `f32`,
#     6 at each of the other sixteen dtypes, 0 bare.
#
# THE POPULATIONS ARE DISCOVERED, ON BOTH SIDES, AND THE GATE COMPARES THEM.
# `crp_graph_census-gate.py`'s `methods_hold`, `dtypes_hold`, `frompy_hold` and
# `opscast_hold` each re-derive a set and check it against the LANE'S OWN PRINTED ROW
# NAMES on every run. The dtype axis is `spec.bend`'s twenty `def <n>() -> Dt: Dt{...}`
# constructors (MEASURED 20) and `dir(dtypes)`'s twenty `DType`s (MEASURED 20), and
# `dts()` below is a MIRROR of the former, the way `realize_graph_census-oracle.py`'s `B`
# mirrors `main_arena` index for index.
#
# THE CONSTANTS IN THIS FIXTURE ARE NOT TYPED PER DTYPE. `zeros`/`ones`/`full_like` need
# `fill_value` ALREADY TRUNCATED (`creation.bend`'s fact 3, and its TODO(p3) on
# dtype.py:84), and a per-cell literal would be this file TRANSCRIBING `DType.const` --
# the `tn_bitwise_not` post-mortem, where an oracle that hand-built `cast.ne(True)` agreed
# with a port that was itself wrong. So the value comes from `cr_cval0`/`cr_cval1`, the
# PORT'S OWN `DType.const` arms (creation.bend:434-452), and the oracle asks `dt.const(1)`
# -- CPython's own method -- for its side. NEITHER SIDE GUESSES.
#
# ONE FOLD AND ONE DISPATCHER FOR THE EIGHT DTYPE FAMILIES, because Bend has no
# first-class function and refuses both a forward reference and a mutual recursion:
# `walk(0n, 20n, f)` does not typecheck and a `go`/`one` pair does not either. `fam.go`
# walks the axis and `fam.one` picks the `cr_*` call, which is the "one `*_go` per table"
# shape `rng_graph_census.bend` documents and one level out from its eleven.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/creation.bend as C

# ===========================================================================
# THE AXES.
# ===========================================================================
# THE DTYPE AXIS -- a MIRROR of `spec.bend`'s twenty `def <n>() -> Dt: Dt{...}`
# constructors, in PRIORITY order, which is the order those constructors are in, so the
# row order is the file's order and not a second one chosen here. `dtypes_hold()` checks
# this mirror against BOTH `spec.bend` and `dir(dtypes)` on every run.
def dts() -> List<&2, S.Dt>:
  [S.void(), S.weakint(), S.boolean(), S.int8(), S.uint8(), S.int16(), S.uint16(),
   S.int32(), S.uint32(), S.int64(), S.uint64(), S.weakfloat(),
   S.fp8e4m3(), S.fp8e4m3fnuz(), S.fp8e5m2(), S.fp8e5m2fnuz(),
   S.half(), S.bfloat16(), S.single(), S.double()]

# THE SHAPE AXIS -- `()`, `(4,)`, `(2,3)`, `(2,3,4)`: the four shapes `shape_to_shape_arg`
# (ops.py:105) has FOUR answers for. A 0-dim shape is `()`, a ONE-dim shape is the CONST
# ITSELF (`src[0]`, not a STACK) and a 2-or-more-dim shape is a STACK; and `empty`'s
# reshape identity test (creation.py:42) compares `max_shape == [prod]`, which is TRUE
# only for the one-dim shape.
def shp() -> List<&2, List<&2, U32>>: [[], [4], [2, 3], [2, 3, 4]]

# ===========================================================================
# THE DEEP SIGNATURE. ONE TOKEN PER NODE OVER THE WHOLE TOPOSORT -- the same
# post-order CPython's `UOp.toposort` (ops.py:588-601) returns and the port's
# `UOp.toposort` builds (ops.bend:3213) -- so a swapped operand, a node in the wrong cone
# and a wrong CONST value are all differences rather than coincidences. `O.Rng.sig` is a
# PREFIX; `realize_graph_census-oracle.py:249` is this repair and names the row (`gr_10`)
# that a prefix printed alike on both sides.
# ===========================================================================
def bstr(b: Bool) -> String:
  match b:
    case True{}:  "True"
    case False{}: "False"

# `APy{v}` is a CONST's arg (ops.bend's `Arg` arm) and `AParam{p}` an ALLOC's `ParamArg`.
# THE DERIVED DTYPE IS `cr_from_py(v)` -- `ops.py:183-189`'s `dtype_from_uop` answers bool
# for `InvalidType` and bool, weakint for int and weakfloat for float, and
# `dtypes.from_py` (dtype.py:100-106) answers exactly the same three -- so the port's own
# def is what prints it and the gate can check the two agree by diffing the lanes.
# A `match` may not read its OWN scrutinee, so each arm is its own leaf that rebuilds the
# `O.Const` and hands it to `cr_from_py` -- one use of `b`/`i`/`f` each, which is why the
# leaves take `+`.
#
# THE FLOAT ARM PRINTS ITS IEEE-754 BIT PATTERN, NOT A DECIMAL. `H.f32_show(0.0)` is `"0"`
# and Python's `repr(0.0)` is `"0.0"` -- MEASURED, and it moved thirty of this census's rows
# before the arm was changed. Those thirty were a PRINTER disagreement about how to SPELL a
# zero, in `helpers.bend` and not in `creation.bend`, and pinning them would have put
# thirty rows of noise in the pins file and told a reader the port holds the wrong value.
# `F32.bits` is a LAW (`base.bend:31`) and is exact in every lane including NaN payloads
# (`base.bend:34-48`), so it is TOTAL where a formatter is not, and `0.0` and `-0.0` and
# `nan` become three different tokens rather than one. The oracle prints
# `struct.unpack('<I', struct.pack('<f', x))[0]` and the two agree exactly.
def cval.b(+b: Bool) -> String:
  String.concat([bstr(b), ":", T.dt_name(C.cr_from_py(O.CBool{b}))])

def cval.i(+i: H.I64) -> String:
  String.concat([H.i64_dec(i), ":", T.dt_name(C.cr_from_py(O.CInt{i}))])

def cval.f(+f: F32) -> String:
  String.concat(["bits=", U32.show(F32.bits(f)), ":", T.dt_name(C.cr_from_py(O.CFloat{f}))])

def cval.v() -> String: String.concat(["Invalid:", T.dt_name(C.cr_from_py(O.CInvalid{}))])

def cval(v: O.Const) -> String:
  match v:
    case O.CBool{b}:  cval.b(b)
    case O.CInt{i}:   cval.i(i)
    case O.CFloat{f}: cval.f(f)
    case _:           cval.v()

def msu32(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: U32.show(v)
    case None{}:  "-"

def addrstr.of(g: Bool) -> String:
  match g:
    case True{}:  "GLOBAL"
    case False{}: "other"

def addrstr(a: S.Addr) -> String: addrstr.of(O.eq_addr(a, S.AGlobal{}))

# THE SIZE IS `src[0]`, AND IT IS NOT THE `ParamArg`'s. Upstream DROPPED the `size`
# FIELD from `ParamArg` (it is not among `tinygrad/uop/ops.py:25-42`'s thirteen) and
# moved the count into the ALLOC's `src[0]` -- `UOp.alloc` builds
# `src=(shape_to_shape_arg((prod(to_max_shape(shape)),)),)` (ops.py:1190). THE PORT
# FOLLOWED, at `1af4ba921` ("sizetosrc: size -> src[0]"), and `ops.bend`'s
# `ParamArg.size(+ar, +self)` READS `src[0]` OF THE OWNER -- so it takes the ARENA and
# the NODE INDEX and not the record. THIS CALLER WAS LEFT ON THE OLD SHAPE
# (`ParamArg.size(x: ParamArg)`, the field accessor) AND DID NOT COMPILE.
# `O.Arena` IS NOT MISSING AND `O.Arena` IS NOT WRONG: THE GATE'S CALL WAS.
def pval(+a: O.Arena, +u: U32, +p: O.ParamArg) -> String:
  String.concat([T.dt_name(O.ParamArg.dtype(p)), " sz=", msu32(O.ParamArg.size(a, u)), " ",
                 addrstr(O.ParamArg.addrspace(p)), " bind=", bstr(O.ParamArg.bind_on_realize(p))])

# THE BARE TOKEN, `OP/arity`, AND IT IS SPELLED ONCE HERE so the `ADt` arm below can put a
# TARGET inside it. `O.Ops.name.of` is the ONE place an op's name is spelled (ops.bend) and
# `T.dt_name` the ONE place a dtype's name is (tensor.bend:1272, `S.Dt{pri, bits, cls, nm}`
# projected onto `nm`) -- WHICH IS CPYTHON'S OWN `DType.name`, MEASURED: all twenty of
# `spec.bend`'s `nm` fields are `void weakint bool i8 u8 i16 u16 i32 u32 i64 u64 weakfloat
# fp8e4m3 fp8e4m3fnuz fp8e5m2 fp8e5m2fnuz f16 bf16 f32 f64` (spec.bend:719-742) and
# `dtypes_hold` asserts that field-by-field. SO THERE IS NO TRANSLATION TABLE ON EITHER SIDE.
def tok.plain(+a: O.Arena, +u: U32) -> String:
  String.concat([O.Ops.name.of(O.Arena.op(a, u)), "/", U32.show(O.Arena.nsrc(a, u))])

# `OP/arity`, OR THE STRING THE CALLER ALREADY BUILT. A `match` may not scrutinise a
# computed value, so the op test arrives as a `Bool` -- the `.of` that every other census
# uses for the same reason.
def tok.of(+a: O.Arena, +u: U32, c: Bool, s: String) -> String:
  match c:
    case True{}:  s
    case False{}: tok.plain(a, u)

# `Arena.arg` IS A CALL, AND `match` NEITHER SCRUTINISES A COMPUTED VALUE NOR A LOCAL
# BINDER -- so the ARG IS A PARAMETER of the arm-selecting def and the `match` heads that
# one. THE CONE WALK IS THE ONLY CALLER, so this is one def and not a two-step.
#
# `ADt` IS THE FOURTH ARM AND IT IS THE ONE THAT WAS MISSING. `cr_cast` (creation.bend:217)
# mints its CAST with `O.ADt{dt}` -- ops.py:640's `Ops.CAST, arg=dt` -- and before this arm
# the token was `CAST/1`: MEASURED ON THE BASE LANES, 118 `CAST/1` occurrences and NOT ONE
# carried an argument, on BOTH sides. So the `de` that `cr_const_of` hands to `.cast` as its
# TARGET (creation.bend:245, the third argument) was never in a token, a wrong `ADt` at
# every minted CAST could not move a row, and `gates/crp_graph_census-mutate.py`'s C5 said
# so as a prediction. The test is ON THE ARG and not on the op, so a fourth op that ever
# grows a `Dt` is printed by this and not by a list that would rot beside it.
def tok.arg(+a: O.Arena, +u: U32, g: O.Arg) -> String:
  match g:
    case O.APy{v}:    tok.of(a, u, True{}, String.concat(["CONST/0[", cval(v), "]"]))
    case O.AParam{p}: tok.of(a, u, True{}, String.concat(["ALLOC/0[", pval(a, u, p), "]"]))
    case O.ADt{d}:    tok.of(a, u, True{}, String.concat([tok.plain(a, u), "[", T.dt_name(d), "]"]))
    case _:           tok.of(a, u, False{}, "")

def tok(+a: O.Arena, +u: U32) -> String: tok.arg(a, u, O.Arena.arg(a, u))

def cgo(xs: List<&2, U32>, +ar: O.Arena, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:  acc
    case u <> t: cgo(t, ar, List.append(&2, String, acc, [tok(ar, u)]))

def cone(+t: T.Tensor) -> String:
  String.join(cgo(O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t)),
                  T.Tensor.ar(t), Nil{}), ",")

def put(nm: String, +t: T.Tensor) -> IO(Unit):
  IO.print(String.concat([nm, "=", cone(t)]))

def row(pfx: String, +d: S.Dt, +t: T.Tensor) -> IO(Unit):
  put(String.concat([pfx, "_", T.dt_name(d)]), t)

# `UOp.const(1, dt)` and `UOp.const(0, dt)` AS `DType.const`'s three arms spell them: a
# bool for a bool dtype, a float for a float dtype and an int otherwise. `cr_cval1`/
# `cr_cval0` ARE that rule (creation.bend:434-452) and are CALLED rather than re-spelled.
def cv1(+d: S.Dt) -> O.Const: C.cr_cval1(S.Dt.is_bool(d), S.Dt.is_float(d))

def cv0(+d: S.Dt) -> O.Const: C.cr_cval0(S.Dt.is_bool(d), S.Dt.is_float(d))

# ===========================================================================
# THE EIGHT DTYPE FAMILIES. ONE PER PORTED `cr_*` DEF THAT TAKES A DTYPE, and each is
# reached the way `creation.py` reaches it. `fam` is the family id and it is ALSO the
# prefix, so the row NAME and the dispatch arm cannot drift apart.
#
#   0 zl   cr_zeros_like   creation.py:124   rx(dt).zeros_like()
#   1 ol   cr_ones_like    creation.py:154   rx(dt).ones_like()
#   2 fl   cr_full_like    creation.py:89    rx(dt).full_like(1)
#   3 el   cr_empty_like   creation.py:45    rx(dt).empty_like()          [dtype=None]
#   4 cl   cr_const_like   creation.py:14    rx(dt).const_like(1)
#   5 f    cr_full         creation.py:64    Tensor.full(shape, dt.const(1), dtype=dt)
#   6 iv   cr_full         creation.py:53    Tensor.invalids(shape, dtype=dt)
#   7 z    cr_zeros        creation.py:108   Tensor.zeros(shape, dtype=dt)
#   8 eb   cr_empty_like   creation.py:45    rx(dt).empty_like()   [WITH the bounds]
#
# `eb` IS `el` PLUS THE BOUNDS, and it exists to tell TWO THINGS APART. `el` passes
# `None{}` for `vmin`/`vmax` -- `creation.bend`'s W3, because Python's `commit_dtype`
# reads `self._uop.vmin` (dtype.py:16) off the RECEIVER and this port cannot. `eb` passes
# `Some{0}` for both, which is what `UOp._min_max`'s CONST arm (ops.py:1160) returns for
# the receiver's `0`. CPython's two rows are the SAME call, so `eb_weakint` agreeing with
# CPython while `el_weakint` does not IS the measurement that the missing bounds -- and not
# `D.commit_dtype` itself -- are what move the ALLOC's width. A pair, because either row
# alone cannot say which of the two it is looking at.
#
# `rx(dt)` -- the RECEIVER -- is `Tensor.zeros(shape, dtype=dt, buffer=False)` on the
# oracle side and MEASURED to carry `.dtype == dt` for ALL TWENTY, which a buffered
# `Tensor.zeros(shape, dtype=dt)` does NOT (its dtype is `commit_dtype()`'s answer, i32
# at weakint). That is `realize_graph_census-oracle.py`'s "a fixture dtype is a named,
# argued field of the oracle rather than a convenience", and it is why this axis has a
# receiver at all.
#
# `f` AND `iv` ARE BOTH `cr_full`, over two DIFFERENT values: `iv` is `Invalid`, which is
# the ONE value whose `DType.const` is the value UNCHANGED (dtype.py:80 returns `val`),
# and it is the only value on which the fold predicate disagrees. See the gate's footer.
# ===========================================================================
def fam.of(fam: Nat, pfx: String, d: S.Dt) -> String:
  match fam:
    case 0n: "zl"
    case 1n: "ol"
    case 2n: "fl"
    case 3n: "el"
    case 4n: "cl"
    case 5n: "f"
    case 6n: "iv"
    case 7n: "z"
    case _:  "eb"

def fam.one(+fam: Nat, +pfx: String, +d: S.Dt) -> IO(Unit):
  match fam:
    case 0n: row(pfx, d, C.cr_zeros_like(O.Arena.empty(), d, [2, 3], S.D1{0}))
    case 1n: row(pfx, d, C.cr_ones_like(O.Arena.empty(), d, [2, 3], S.D1{0}))
    case 2n: row(pfx, d, C.cr_full_like(O.Arena.empty(), cv1(d), d, True{}, [2, 3], S.D1{0}))
    # `given=False{}` is `dtype is None`, so `dt` is ignored and `commit_dtype(self_dt)`
    # runs -- which is the point of this family. `None{}` bounds are `empty_like`'s own
    # default, and the wall they hit is `creation.bend`'s W3.
    case 3n: row(pfx, d, C.cr_empty_like(O.Arena.empty(), False{}, S.half(), d, None{}, None{}, [2, 3], S.D1{0}))
    case 4n: row(pfx, d, C.cr_const_like(True{}, O.Arena.empty(), cv1(d), d, [2, 3]))
    case 5n: row(pfx, d, C.cr_full(True{}, O.Arena.empty(), cv1(d), d, [2, 3], S.D1{0}))
    case 6n: row(pfx, d, C.cr_full(True{}, O.Arena.empty(), O.CInvalid{}, d, [2, 3], S.D1{0}))
    case 7n: row(pfx, d, C.cr_zeros(O.Arena.empty(), cv0(d), d, [2, 3], S.D1{0}))
    case _:  row(pfx, d, C.cr_empty_like(O.Arena.empty(), False{}, S.half(), d,
                                        Some{H.i64_of_i32(0)}, Some{H.i64_of_i32(0)}, [2, 3], S.D1{0}))

def fam.go(+fam: Nat, +pfx: String, dts: List<&2, S.Dt>) -> IO(Unit):
  match dts:
    case Nil{}: IO.print("")
    case d <> t:
      do IO<Unit>:
        a : Unit <- fam.one(fam, pfx, d)
        b : Unit <- fam.go(fam, pfx, t)
        return Unit{}

# ===========================================================================
# THE VALUE-REACH AXIS: `O.Const`'s FOUR CONSTRUCTORS TIMES TWENTY `Dt`s -- `cr_const_of`'s
# WHOLE INPUT SPACE, every cell a ROW rather than a count, and the family that exists because
# the other 207 rows could not see `de`.
#
# WHY IT HAD TO BE BUILT, AND IT IS NOT "MORE ROWS". Every other dtype family in this file
# takes its value from `cv1(dt)`/`cv0(dt)` -- `DType.const`'s three arms over the literal 1 --
# so the value axis was a FUNCTION of the dtype axis: `CBool` at `bool`, `CFloat` at the nine
# float dtypes, `CInt` at the other ten. `CInvalid` appeared at twenty dtypes and NOWHERE
# else, so the "eighty cells" the gate's footer quotes were never eighty CELLS -- they were
# eighty CONSTRUCTOR/DTYPE PAIRS of which the fixture could reach 41. THIS FAMILY PLACES ALL
# FOUR CONSTRUCTORS AT EVERY DTYPE.
#
# THE RAW VALUE AXIS LIVES ON THE ORACLE AND ONLY THERE, because `DType.const` is
# CPython's. The oracle hands `UOp.const` the RAW (`Invalid`, `True`, `7`, `2.5`) and lets
# dtype.py:79-84 do the narrowing; the port is handed the ALREADY-NARROWED value, because
# `cr_full`'s `fill_value` arrives after `dtype.const` (creation.bend's fact 3, its
# `TODO(p3)`). SO THE FIXTURE BELOW SPELLS dtype.py's THREE ARMS AND NO TRUNCATION -- and the
# no-truncation half is MEASURED rather than hoped for: on `.venv/bin/python`, `dt.const(x)`
# at all twenty dtypes returns `True`, `1`, `7` and `2` and the float spellings of `1`, `7`
# and `2.5` EXACTLY, so these four raws meet no `truncate` and a fourth arm cannot exist at
# them. `cr_cval1` IS the raw-`True` column -- `DType.const`'s arms over the literal 1 IS
# `dt.const(True)` -- and it is CALLED rather than re-spelled.
#
# THE PAYLOADS ARE CHOSEN AGAINST `cv1`, NOT AGAINST EACH OTHER: `1` is `cv1(dt)`'s, so `7`
# and `2.5` are the two this axis adds, and at `bool` all three raws COLLAPSE to `True`
# (`bool(1)`, `bool(7)`, `bool(2.5)` are all `True`) -- the one dtype where the payload axis
# is degenerate, and the reason this family is EIGHTY rows and not two hundred and forty.
# A fourth payload would add rows that cannot move the claim, because `cr_cast_dt` and
# `cr_from_py` both read the CONSTRUCTOR and neither reads the payload: MEASURED on
# CPython's side, the `(derived, minted, cast-target, de!=dt)` tuple is identical for three
# payloads at 60 of 60 cells.
# ===========================================================================
# THE VALUE-REACH AXIS, `vr_`, AND WHY IT IS EIGHTY ROWS RATHER THAN A FLOOR. See its own
# section below; the short form is that the other 207 rows take their value from `cv1(dt)`, so
# their value axis IS their dtype axis, and `cr_const_of`'s whole input space -- `O.Const`'s
# four constructors times `spec.bend`'s twenty `Dt`s -- is what the claim about `de` is about.
# `cr_const_dt`'s own `iv_` rows are the twenty `CInvalid` cells of that grid and the ONLY
# cells at which `de != dt`, and they mint nothing.
def vr.of(k: Nat) -> String:
  match k:
    case 0n: "CInvalid"
    case 1n: "CBool"
    case 2n: "CInt"
    case _:  "CFloat"

# `dt.const(v)` FOR A RAW THAT IS NOT THE LITERAL 1: `bool(v)` for a bool dtype,
# `ConstFloat(v)` for a float one and `int(v)` otherwise (dtype.py:79-84). THE BOOL ARM
# FIRST, because `bool` is an `int` subclass and dtype.py tests `isinstance(val, bool)`
# before `isinstance(val, int)` for exactly that reason. TWO LEAVES, because `O.CFloat` and
# `O.CInt` hold different types and a `match` may not scrutinise a computed value.
def vp.of2(if_: Bool, f: F32, n: H.I64) -> O.Const:
  match if_:
    case True{}: O.CFloat{f}
    case _:      O.CInt{n}

def vp.of(ib: Bool, if_: Bool, f: F32, n: H.I64) -> O.Const:
  match ib:
    case True{}: O.CBool{True{}}
    case _:      vp.of2(if_, f, n)

# THE VALUE THE PORT IS HANDED. `k` IS THE RAW'S CONSTRUCTOR AND THE ROW PREFIX, so the row
# NAME and the value cannot drift apart -- `fam.of`/`fam.one`'s argument, one level out.
def vv(k: Nat, +d: S.Dt) -> O.Const:
  match k:
    case 0n: O.CInvalid{}                                              # dtype.py:80, unchanged
    case 1n: C.cr_cval1(S.Dt.is_bool(d), S.Dt.is_float(d))              # `dt.const(True)`
    case 2n: vp.of(S.Dt.is_bool(d), S.Dt.is_float(d), 7.0, H.i64_of_i32(7))
    case _:  vp.of(S.Dt.is_bool(d), S.Dt.is_float(d), 2.5, H.i64_of_i32(2))

def vr.one(+k: Nat, +d: S.Dt) -> IO(Unit):
  put(String.concat(["vr_", vr.of(k), "_", T.dt_name(d)]),
      C.cr_const_of(O.Arena.empty(), vv(k, d), d))

def vr.go(+k: Nat, dts: List<&2, S.Dt>) -> IO(Unit):
  match dts:
    case Nil{}: IO.print("")
    case d <> t:
      do IO<Unit>:
        a : Unit <- vr.one(k, d)
        b : Unit <- vr.go(k, t)
        return Unit{}

# ===========================================================================
# THE FIVE SHAPE FAMILIES, over `shp()`. `dt` is `single()` (f32) because `empty` REFUSES a
# weak dtype (creation.py:37) and `weakint`/`weakfloat` would make every `ne` row a raise
# rather than a graph.
#
#   0 ne   cr_empty   creation.py:23
#   1 fs   cr_full    creation.py:64, buffer=True
#   2 nb   cr_full    creation.py:64, buffer=False          [the EXPAND root]
#   3 z    cr_zeros   creation.py:108
#   4 o    cr_ones    creation.py:138
# ===========================================================================
def sh.of(n: Nat) -> String:
  match n:
    case 0n: "ne"
    case 1n: "fs"
    case 2n: "nb"
    case 3n: "z"
    case _:  "o"

def sh.one(+fam: Nat, +pfx: String, +n: Nat, +ds: List<&2, U32>) -> IO(Unit):
  match fam:
    case 0n: put(String.concat([pfx, "_", U32.show(U32.from_nat(n))]),
                 C.cr_empty(O.Arena.empty(), Some{S.single()}, ds, S.D1{0}))
    # `cv1(S.single())` AND NOT `O.CInt{1}`, AND THIS IS THE VALUE AXIS EARNING ITS KEEP.
    # `Tensor.full(shape, 1, dtype=float32)` hands `DType.const` an INT and dtype.py:84
    # wraps it: `ConstFloat(truncate[f32](1.0))`. So CPython's CONST holds the FLOAT `1.0`
    # and this port's must too -- `cr_full`'s `fill_value` is the ALREADY-TRUNCATED value
    # (creation.bend's fact 3). MEASURED, handing it `O.CInt{1}` moved all EIGHT `fs`/`nb`
    # rows, and `O.Rng.sig` CANNOT SEE IT: both sides then print `CONST/0` followed by a
    # `CAST/1`, and nothing about the CONST's ARG is in that signature. The deep printer
    # found it in one run; a prefix would have declared the two sides equal.
    case 1n: put(String.concat([pfx, "_", U32.show(U32.from_nat(n))]),
                 C.cr_full(True{}, O.Arena.empty(), cv1(S.single()), S.single(), ds, S.D1{0}))
    case 2n: put(String.concat([pfx, "_", U32.show(U32.from_nat(n))]),
                 C.cr_full(False{}, O.Arena.empty(), cv1(S.single()), S.single(), ds, S.D1{0}))
    case 3n: put(String.concat([pfx, "_", U32.show(U32.from_nat(n))]),
                 C.cr_zeros(O.Arena.empty(), O.CFloat{0.0}, S.single(), ds, S.D1{0}))
    case _:  put(String.concat([pfx, "_", U32.show(U32.from_nat(n))]),
                 C.cr_ones(O.Arena.empty(), O.CFloat{1.0}, S.single(), ds, S.D1{0}))

# THE COUNTER IS THE LAST PARAMETER AND NOT THE SECOND. Bend's decreasing self-call rule
# is "arguments are read left to right: each passed unchanged until one shrinks", so a
# shrinking argument in the MIDDLE strands every argument after it -- MEASURED, this body
# with `n` second is `expected : a decreasing self-call / observed : sh.go`.
def sh.go(+fam: Nat, +pfx: String, shs: List<&2, List<&2, U32>>, +n: Nat) -> IO(Unit):
  match shs:
    case Nil{}: IO.print("")
    case ds <> t:
      do IO<Unit>:
        a : Unit <- sh.one(fam, pfx, n, ds)
        b : Unit <- sh.go(fam, pfx, t, Nat.add(n, 1n))
        return Unit{}

# ===========================================================================
# THE INTERNING AND SELF-REFERENCE ROWS. `full` builds CONST and EXPAND into the SAME
# arena as its ALLOC, so a SECOND equal `full` must re-use them and mint only the four
# nodes whose `ParamArg.slot` moved -- which is `Arena.next` standing in for
# `next(UOp.unique_num)` (creation.py:41, ops.py:1208).
#
# `selfref` IS THE STALE-ARENA SELF-LOOP DETECTOR, defect class (a), and it is a row
# rather than a claim: `cr_after` interns the STORE into a `let` FIRST (creation.bend:252)
# because an argument is evaluated before the callee branches, so spelling the STORE inline
# makes the AFTER name the node the STORE is about to occupy and `Arena.srcs(after)`
# answers `after`. `mixin/op.bend`'s `mo_bin` and `tensor.bend`'s `tn_binop` were both
# fixed for exactly this. `NOOP` is the OTHER half and the gate's `no_noop_bottom` reads
# it off the lane's own output.
# ===========================================================================
# `full`'s root is `AFTER(ret, STORE(ret, val))` (creation.py:87), so the STORED value --
# the CONST and its EXPAND -- is `AFTER.src[1].src[1]`, and THAT is the node two equal
# `full`s must SHARE. `in_expand` asks the question directly instead of inferring it from
# a node count. `cr_store_val` in `creation.bend` is the same descent and is spelled here
# because its `CU` record is that file's own printer's, not a published vocabulary.
def sval(+ar: O.Arena, u: U32) -> U32: O.Arena.src(ar, O.Arena.src(ar, u, 1), 1)

def shared_expand(+a: T.Tensor, +b: T.Tensor) -> Bool:
  U32.is_eq(sval(T.Tensor.ar(b), T.Tensor.u(b)), sval(T.Tensor.ar(a), T.Tensor.u(a)))

def selfref(+ar: O.Arena, +u: U32) -> Bool: C.cr_in(ar, u, O.Arena.srcs(ar, u))

# THE WHOLE TAIL IN ONE ARENA AND IN ONE DEF, and the five `in_*` prints are in `sorted`
# ORDER so `expected_rows()` in the gate can name them with `sorted(...)` and need not
# reason about SOURCE order. MEASURED: the first draft read them out of the file, and the
# file's definition order (`t_intern_empty` before `t_intern`) is not the EMISSION order
# (`main` calls `t_intern`), so the discovery said 187 rows where the lanes emitted 207.
# A population discovered in an order no lane emits is a population nobody can check.
def t_intern() -> IO(Unit):
  +ar = O.Arena.empty()
  +a = C.cr_full(True{}, ar, cv1(S.single()), S.single(), [2, 3], S.D1{0})
  +b = C.cr_full(True{}, T.Tensor.ar(a), cv1(S.single()), S.single(), [2, 3], S.D1{0})
  +e = C.cr_empty(ar, Some{S.single()}, [2, 3], S.D1{0})
  +f = C.cr_empty(T.Tensor.ar(e), Some{S.single()}, [2, 3], S.D1{0})
  +g = C.cr_ones(T.Tensor.ar(f), O.CFloat{1.0}, S.single(), [2, 3], S.D1{0})
  do IO<Unit>:
    p1 : Unit <- IO.print(String.concat(["in_diff=", U32.show(C.cr_new(T.Tensor.ar(g), g, e))]))
    p2 : Unit <- IO.print(String.concat(["in_empty=", U32.show(C.cr_new(T.Tensor.ar(f), f, e))]))
    p3 : Unit <- IO.print(String.concat(["in_expand=", bstr(shared_expand(a, b))]))
    p4 : Unit <- IO.print(String.concat(["in_full=", U32.show(C.cr_new(T.Tensor.ar(b), b, a))]))
    p5 : Unit <- IO.print(String.concat(["in_selfref=",
                  bstr(selfref(T.Tensor.ar(b), T.Tensor.u(b)))]))
    p6 : Unit <- IO.print(String.concat(["in_selfref_a=",
                  bstr(selfref(T.Tensor.ar(a), T.Tensor.u(a)))]))
    return Unit{}

# THE CONTROL. THE SAME FIXTURE BUILT A SECOND TIME, which must be byte-identical to the
# first -- that is what makes a lane diff a diff and not a comparison.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- fam.go(0n, "zl", dts())
    b : Unit <- fam.go(1n, "ol", dts())
    c : Unit <- fam.go(2n, "fl", dts())
    d : Unit <- fam.go(3n, "el", dts())
    e : Unit <- fam.go(4n, "cl", dts())
    f : Unit <- fam.go(5n, "f", dts())
    g : Unit <- fam.go(6n, "iv", dts())
    h : Unit <- fam.go(7n, "z", dts())
    h2 : Unit <- fam.go(8n, "eb", dts())
    v0 : Unit <- vr.go(0n, dts())
    v1 : Unit <- vr.go(1n, dts())
    v2 : Unit <- vr.go(2n, dts())
    v3 : Unit <- vr.go(3n, dts())
    i : Unit <- sh.go(0n, "ne", shp(), 0n)
    j : Unit <- sh.go(1n, "fs", shp(), 0n)
    k : Unit <- sh.go(2n, "nb", shp(), 0n)
    l : Unit <- sh.go(3n, "z", shp(), 0n)
    m : Unit <- sh.go(4n, "o", shp(), 0n)
    n : Unit <- t_intern()
    o : Unit <- sh.one(0n, "ctl", 2n, [2, 3])
    return Unit{}