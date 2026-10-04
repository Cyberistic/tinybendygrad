# dtype.bend -- tinygrad/dtype.py.
#
# ONE DATATYPE. `Dt` and its `Cls` tag live in ./LAWS/spec.bend, which is where
# the spec IR needs them, and this file imports them. dtype.py does not get a
# second, competing dtype; if the shape of `Dt` is wrong it is fixed there, in
# one place, and both readers see the fix.
#
# THE LATTICE IS A BITMASK, NOT A MATCH LADDER. dtype.py spells least_upper_dtype
# as `min(set.intersection(*recursive_parents(d) for d in ds))`, with the parent
# relation as a table of tuples and the closure over it. Bend has no sets and no
# sets-of-sets, and a 19-way ladder of pairs is 361 cases that would need a
# checked-in proof that they agree with Python. The twenty dtypes are totally
# ordered by dtype.py's own `__lt__` (priority, bitsize, name, fmt), so bit i of
# a mask stands for "rank i is a recursive parent". Then
#
#     least_upper(a, b) = the lowest set bit of mask(a) & mask(b)
#
# which is dtype.py's `min` over the intersection, because the rank order IS
# `__lt__`. The masks in `promo_mask` are `DType._get_recursive_parents` written
# down: rank i's bit is set iff rank i is in that set. `void` is rank 19 with an
# empty mask, so any pair naming it answers `void`, which is the one totalization
# this file makes -- dtype.py raises KeyError there, because `void` is not in its
# lattice at all. See NOT PORTED.
#
# VARIADIC. dtype.py's least_upper_dtype takes *ds. Bend has no variadics, so
# there are two defs: `least_upper` is the binary one and `least_upper_dtypes`
# folds a list left to right. Python's `min` over an intersection is associative,
# so the fold and the n-ary call agree exactly -- checked over all 361 pairs and
# 5000 random 4-ary cases.
#
# NOT PORTED, one line each. The bottom of this file says why.

import Base
import ./LAWS/spec.bend as S
import ./helpers.bend as H

# ===========================================================================
# The twenty dtypes, under tinygrad's ATTRIBUTE names.
#
# spec.bend already holds all twenty; these are the names dtype.py code writes
# (`dtypes.f32`, `dtypes.f16`, ...), which are not always the names the spec IR
# uses (`single`, `half`). One value, twenty names, no second value.
#
# THE ATTRIBUTE NAMES ARE THE RUST NAMES. tinygrad 793abbb renamed them, keeping
# the old ones only in a block it labels `# legacy dtype aliases` -- so this list
# spells `i8`..`u64`, `f16`, `bf16`, `f32`, `f64` and carries NO legacy accessor.
# `dtypes.f16()`, `dtypes.f32()` and their kin were removed from the port on
# the same day for the same reason; a def nothing calls is invisible to every
# check, so keeping them would be a name the port can still spell but nothing
# gates.
#
# `spec.bend`'s own heads (`half`, `bfloat16`, `single`, `double`) are tinyspec's
# IR words and stay: they are not dtype.py attribute names and never were.
# ===========================================================================

def dtypes.void() -> S.Dt: S.void()
def dtypes.weakint() -> S.Dt: S.weakint()
def dtypes.index() -> S.Dt: S.weakint()
def dtypes.bool() -> S.Dt: S.boolean()
def dtypes.i8() -> S.Dt: S.int8()
def dtypes.u8() -> S.Dt: S.uint8()
def dtypes.i16() -> S.Dt: S.int16()
def dtypes.u16() -> S.Dt: S.uint16()
def dtypes.i32() -> S.Dt: S.int32()
def dtypes.u32() -> S.Dt: S.uint32()
def dtypes.i64() -> S.Dt: S.int64()
def dtypes.u64() -> S.Dt: S.uint64()
def dtypes.weakfloat() -> S.Dt: S.weakfloat()
def dtypes.fp8e4m3() -> S.Dt: S.fp8e4m3()
def dtypes.fp8e4m3fnuz() -> S.Dt: S.fp8e4m3fnuz()
def dtypes.fp8e5m2() -> S.Dt: S.fp8e5m2()
def dtypes.fp8e5m2fnuz() -> S.Dt: S.fp8e5m2fnuz()
def dtypes.f16() -> S.Dt: S.half()
def dtypes.bf16() -> S.Dt: S.bfloat16()
def dtypes.f32() -> S.Dt: S.single()
def dtypes.f64() -> S.Dt: S.double()

# the fp8 group, as dtype.py's `dtypes.fp8s`
def dtypes.fp8s() -> List<&2, S.Dt>:
  [S.fp8e4m3(), S.fp8e5m2(), S.fp8e4m3fnuz(), S.fp8e5m2fnuz()]

def dtypes.floats() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, dtypes.fp8s(), [S.half(), S.bfloat16(), S.single(), S.double()])

def dtypes.uints() -> List<&2, S.Dt>:
  [S.uint8(), S.uint16(), S.uint32(), S.uint64()]

def dtypes.sints() -> List<&2, S.Dt>:
  [S.int8(), S.int16(), S.int32(), S.int64()]

def dtypes.ints() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, dtypes.uints(), dtypes.sints())

# dtype.py's `dtypes.all`: every dtype a value can have.
def dtypes.all() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, List.append(&2, S.Dt, dtypes.floats(), dtypes.ints()),
    [S.boolean()])

# ===========================================================================
# The promotion lattice.
#
# The rank order is dtype.py's own `__lt__`, which sorts on
# (priority, bitsize, name, fmt). Both fp8 ties at priority 10 and 11 are broken
# by name, so the order below is forced and there is no choice to make -- and
# THE RENAME DID NOT MOVE IT: "fp8e4m3" < "fp8e4m3fnuz" and "float8_e4m3" <
# "float8_e4m3fnuz" are the same two comparisons, because the new names are the
# old ones with "float8_" replaced by "fp8". So every mask below is unchanged.
#
#   0 bool       5 uint16    10 weakfloat  15 float16
#   1 weakint    6 int32     11 fp8e4m3    16 bfloat16
#   2 int8       7 uint32    12 fp8e4m3fnuz 17 float32
#   3 uint8      8 int64     13 fp8e5m2     18 float64
#   4 int16      9 uint64    14 fp8e5m2fnuz 19 void (empty mask)
#
# The masks are `_get_recursive_parents` in rank order; see the header for why
# that is the whole lattice.
# ===========================================================================

def promo_mask.void(nm: String) -> U32:
  match nm:
    case "void": 0
    case _: 0

def promo_mask(nm: String) -> U32:
  match nm:
    case "bool": 524287
    case "weakint": 524286
    case "i8": 523604
    case "u8": 524280
    case "i16": 523600
    case "u16": 524256
    case "i32": 523584
    case "u32": 524160
    case "i64": 523520
    case "u64": 523776
    case "weakfloat": 523264
    case "fp8e4m3": 493568
    case "fp8e4m3fnuz": 495616
    case "fp8e5m2": 499712
    case "fp8e5m2fnuz": 507904
    case "f16": 425984
    case "bf16": 458752
    case "f32": 393216
    case "f64": 262144
    case _: 0

def dt_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# the rank -> dtype half of the same order
def dt_by_rank(r: Nat) -> S.Dt:
  match r:
    case 0n: S.boolean()
    case 1n: S.weakint()
    case 2n: S.int8()
    case 3n: S.uint8()
    case 4n: S.int16()
    case 5n: S.uint16()
    case 6n: S.int32()
    case 7n: S.uint32()
    case 8n: S.int64()
    case 9n: S.uint64()
    case 10n: S.weakfloat()
    case 11n: S.fp8e4m3()
    case 12n: S.fp8e4m3fnuz()
    case 13n: S.fp8e5m2()
    case 14n: S.fp8e5m2fnuz()
    case 15n: S.half()
    case 16n: S.bfloat16()
    case 17n: S.single()
    case _: S.double()

def lowest(+m: U32) -> Nat:
  # the index of the lowest set bit. m is never 0, because `bool` is a recursive
  # parent of every dtype, so every non-void mask has bit 0 set.
  U32.log2(U32.and(m, U32.sub(0, m)))

# dtype.py least_upper_dtype(a, b), over the two masks. `None` is dtype.py's
# KeyError, which is what any pair naming `void` gives: void is not in the
# lattice it closes over.
def least_upper.pick(ok: Bool, m: U32) -> Maybe<&1, S.Dt>:
  match ok:
    case True{}: None{}
    case False{}: Some{dt_by_rank(lowest(m))}

def least_upper(+ma: U32, mb: U32) -> Maybe<&1, S.Dt>:
  least_upper.pick(U32.is_zero(ma), U32.and(ma, mb))

def least_upper.picked(m: Maybe<&1, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

# The same meet as a value rather than an outcome. `void` is the bottom of this
# lattice -- least_upper(void, x) is void -- so it also serves as the fold's
# identity, and it is what a Python exception would have left behind.
def least_upper.of(a: S.Dt, b: S.Dt) -> S.Dt:
  least_upper.picked(least_upper(promo_mask(dt_name(a)), promo_mask(dt_name(b))))

def least_upper_mask(a: S.Dt, b: S.Dt) -> Maybe<&1, S.Dt>:
  least_upper(promo_mask(dt_name(a)), promo_mask(dt_name(b)))

# The variadic form: dtype.py's least_upper_dtype(*ds), folded left to right.
# `min` over an intersection is associative, so the fold and the n-ary call
# agree exactly, which is what the self-test checks on every pair.
def least_upper_dtypes.go(ds: List<&2, S.Dt>, a: S.Dt) -> S.Dt:
  match ds:
    case Nil{}: a
    case h <> t: least_upper_dtypes.go(t, least_upper.of(a, h))

def least_upper_dtypes.head(ds: List<&2, S.Dt>) -> S.Dt:
  match ds:
    case Nil{}: S.void()
    case h <> t: least_upper_dtypes.go(t, h)

def least_upper_dtypes(ds: List<&2, S.Dt>) -> S.Dt:
  least_upper_dtypes.head(ds)

# least_upper_float -- dtype.py: `weakfloat if dt is weakint else dt if is_float(dt)
# else least_upper_dtype(dt, default_float)`. Three arms, one Bool each.
def least_upper_float.cls(cls: S.Cls, dt: S.Dt, dflt: S.Dt) -> Maybe<&1, S.Dt>:
  match cls:
    case S.CWeakInt{}: Some{S.weakfloat()}
    case S.CFloat{}: Some{dt}
    case _: least_upper_mask(dt, dflt)

def least_upper_float(+dt: S.Dt, dflt: S.Dt) -> Maybe<&1, S.Dt>:
  least_upper_float.cls(S.Dt.cls(dt), dt, dflt)

# ===========================================================================
# strong_dtype / weak_dtype
# ===========================================================================

def strong_dtype.cls(cls: S.Cls, di: S.Dt, df: S.Dt, d: S.Dt) -> S.Dt:
  match cls:
    case S.CWeakInt{}: di
    case S.CWeakFloat{}: df
    case _: d

def strong_dtype(+d: S.Dt, di: S.Dt, df: S.Dt) -> S.Dt:
  strong_dtype.cls(S.Dt.cls(d), di, df, d)

def weak_dtype.cls(cls: S.Cls, dt: S.Dt) -> S.Dt:
  match cls:
    case S.CWeakFloat{}: S.weakfloat()
    case S.CWeakInt{}: S.weakint()
    case _: dt

def weak_dtype(+d: S.Dt) -> S.Dt:
  weak_dtype.cls(S.Dt.cls(d), d)

# ===========================================================================
# can_lossless_cast -- "does dt1 preserve every value of dt0".
#
# Its own table, NOT the lattice: a mask of the recursive parents is wrong here.
# int32 is a parent of float32 through int64 -> weakfloat, yet int32 -> float32
# is lossy and int32 -> float64 is not, because float32 has 24 bits of mantissa
# and int32 needs 31. So the row is `dt0` and the mask is over the ranks that
# accept it, taken from dtype.py's `match dt1` arms one case at a time.
# ===========================================================================

def can_lossless_cast.row(nm: String) -> U32:
  match nm:
    case "bool": 524287
    case "i8": 426326
    case "u8": 427002
    case "i16": 393554
    case "u16": 394210
    case "i32": 262466
    case "u32": 263042
    case "i64": 258
    case "u64": 514
    case "fp8e4m3": 428032
    case "fp8e4m3fnuz": 430080
    case "fp8e5m2": 434176
    case "fp8e5m2fnuz": 442368
    case "f16": 425984
    case "bf16": 458752
    case "f32": 393216
    case "f64": 262144
    # weakint and weakfloat are placeholders, not storages: they preserve
    # themselves and nothing else
    case "weakint": 2
    case "weakfloat": 1024
    case _: 0

def rank_of(nm: String) -> Nat:
  match nm:
    case "bool": 0n
    case "weakint": 1n
    case "i8": 2n
    case "u8": 3n
    case "i16": 4n
    case "u16": 5n
    case "i32": 6n
    case "u32": 7n
    case "i64": 8n
    case "u64": 9n
    case "weakfloat": 10n
    case "fp8e4m3": 11n
    case "fp8e4m3fnuz": 12n
    case "fp8e5m2": 13n
    case "fp8e5m2fnuz": 14n
    case "f16": 15n
    case "bf16": 16n
    case "f32": 17n
    case _: 18n

def can_lossless_cast.hit(row: U32, +bit: U32) -> Bool:
  U32.is_eq(U32.and(row, bit), bit)

def can_lossless_cast.pair(row: U32, r: Nat) -> Bool:
  can_lossless_cast.hit(row, U32.shln(1, r))

def can_lossless_cast(d0: S.Dt, d1: S.Dt) -> Bool:
  can_lossless_cast.pair(can_lossless_cast.row(dt_name(d0)), rank_of(dt_name(d1)))


# ===========================================================================
# sum_acc_dtype -- the dtype a reduction accumulates in.
#
# dtype.py reads SUM_DTYPE out of the environment. Bend has no process-wide
# store, so it is a parameter here and the caller threads it, which is what
# helpers.bend's `Flags` record exists for.
# ===========================================================================

def sum_acc_dtype.cls(cls: S.Cls, dt: S.Dt, sum: S.Dt) -> S.Dt:
  match cls:
    case S.CUint{}: least_upper.of(dt, S.uint32())
    case S.CSint{}: least_upper.of(dt, S.int32())
    case S.CWeakInt{}: least_upper.of(dt, S.int32())
    case S.CBool{}: least_upper.of(dt, S.int32())
    case _: least_upper.of(dt, sum)

def sum_acc_dtype(+dt: S.Dt, sum: S.Dt) -> S.Dt:
  sum_acc_dtype.cls(S.Dt.cls(dt), dt, sum)

# ===========================================================================
# finfo -- (exponent, mantissa) bit widths. dtype.py's is a dict lookup that
# raises for a non-float; None is that raise.
# ===========================================================================

# A `Maybe` holds one field, so the answer is a record rather than a pair.
type Finfo is Data:
  Finfo{e: U32, m: U32}

def finfo.of(nm: String) -> Maybe<&1, Finfo>:
  match nm:
    case "f16": Some{Finfo{5, 10}}
    case "bf16": Some{Finfo{8, 7}}
    case "f32": Some{Finfo{8, 23}}
    case "f64": Some{Finfo{11, 52}}
    case "fp8e4m3": Some{Finfo{4, 3}}
    case "fp8e5m2": Some{Finfo{5, 2}}
    case "fp8e4m3fnuz": Some{Finfo{4, 3}}
    case "fp8e5m2fnuz": Some{Finfo{5, 2}}
    case _: None{}

def finfo.cls(cls: S.Cls, nm: String) -> Maybe<&1, Finfo>:
  match cls:
    case S.CWeakFloat{}: None{}
    case _: finfo.of(nm)

def finfo(+d: S.Dt) -> Maybe<&1, Finfo>:
  finfo.cls(S.Dt.cls(d), dt_name(d))


# ===========================================================================
# The integer range, as an I64.
#
# spec.bend's Dt.min / Dt.max answer this for the widths a U32 holds and None
# above that; these two finish it. dtype.py's min/max are Python ints of unbounded
# width, which is why the pair is the honest encoding and a U32 is not. The four
# widths are tinygrad's, and 2^64-1 is the only one of the four limits with no
# U32 image, so it is written as the two words it is.
# ===========================================================================

def i64_max_u(bits: U32) -> H.I64:
  match bits:
    case 8: H.i64_of_hi_lo(0, 255)
    case 16: H.i64_of_hi_lo(0, 65535)
    case 32: H.i64_of_hi_lo(0, 4294967295)
    # uint64's max is 2^64-1 and an I64 is a SIGNED pair, so it has no image:
    # (0xFFFFFFFF, 0xFFFFFFFF) is -1. The bound is only read as `hi <= max` and
    # every I64 hi is <= int64's max, so int64's max answers that test correctly
    # on the whole domain. Found by mixin/dtype.bend's gate (u64_at_* rows),
    # fixed here 2026-10-01; the old value made the uint64 rung unhittable.
    case _: H.i64_of_hi_lo(2147483647, 4294967295)

def i64_min_s(bits: U32) -> H.I64:
  match bits:
    case 8: H.i64_of_hi_lo(4294967295, 4294967168)
    case 16: H.i64_of_hi_lo(4294967295, 4294934528)
    case 32: H.i64_of_hi_lo(4294967295, 2147483648)
    case _: H.i64_of_hi_lo(2147483648, 0)

def i64_max_s(bits: U32) -> H.I64:
  match bits:
    case 8: H.i64_of_hi_lo(0, 127)
    case 16: H.i64_of_hi_lo(0, 32767)
    case 32: H.i64_of_hi_lo(0, 2147483647)
    case _: H.i64_of_hi_lo(2147483647, 4294967295)

def dt_range.umag(top: Bool, bits: U32) -> H.I64:
  match top:
    case True{}: H.i64_of_hi_lo(0, 0)
    case False{}: i64_max_u(bits)

def dt_range.smag(top: Bool, bits: U32) -> H.I64:
  match top:
    case True{}: i64_min_s(bits)
    case False{}: i64_max_s(bits)

def dt_range.sgn(neg: Bool, top: Bool, bits: U32) -> H.I64:
  match neg:
    case True{}: dt_range.smag(top, bits)
    case False{}: dt_range.umag(top, bits)

def dt_range.cls(sgn: Maybe<&1, Bool>, top: Bool, bits: U32) -> Maybe<&1, H.I64>:
  match sgn:
    case None{}: None{}
    case Some{neg}: Some{dt_range.sgn(neg, top, bits)}

def dt_min(d: S.Dt) -> Maybe<&1, H.I64>:
  match d:
    case S.Dt{pri, bits, cls, nm}: dt_range.cls(S.Cls.sgn(cls), True{}, bits)

def dt_max(d: S.Dt) -> Maybe<&1, H.I64>:
  match d:
    case S.Dt{pri, bits, cls, nm}: dt_range.cls(S.Cls.sgn(cls), False{}, bits)

# ===========================================================================
# The float range.
#
# dtype.py's DType.max for a float is +inf, except that e4m3 and the fnuz fp8s
# have no inf and end at their largest normal. `None` is the float case of the
# spec.bend range: Bend cannot name an infinity in a U32, and here the fp8
# answer is an ordinary F32, so it is spelled out.
# ===========================================================================

def fmax.of(nm: String) -> Maybe<&1, F32>:
  match nm:
    case "fp8e4m3": Some{448.0}
    case "fp8e4m3fnuz": Some{240.0}
    case "fp8e5m2fnuz": Some{57344.0}
    case _: None{}

def fmax.cls(cls: S.Cls, nm: String) -> Maybe<&1, F32>:
  match cls:
    case S.CFloat{}: fmax.of(nm)
    case _: None{}

def fmax(+d: S.Dt) -> Maybe<&1, F32>:
  fmax.cls(S.Dt.cls(d), dt_name(d))

# ===========================================================================
# to_dtype -- dtype.py's `getattr(dtypes, name.lower())`, so the keys are the
# ATTRIBUTE names, not the `name` field. `void`, `weakint` and `weakfloat` are
# reachable here too, even though DTYPES_DICT skips them.
#
# EVERY SPELLING IS HERE, CANONICAL FIRST. The canonical attribute names are the
# RUST names (i8 .. u64, f16, bf16, f32, f64); upstream keeps the old ones in a
# block it labels `# legacy dtype aliases`, so `to_dtype("half")` still answers
# and this table must not drop it -- but the canonical arm comes first because
# that is the spelling everything else in the port now uses.
# ===========================================================================

def to_dtype_of(nm: String) -> Maybe<&1, S.Dt>:
  match nm:
    case "void": Some{S.void()}
    case "weakint": Some{S.weakint()}
    case "weakfloat": Some{S.weakfloat()}
    case "bool": Some{S.boolean()}
    case "i8": Some{S.int8()}
    case "u8": Some{S.uint8()}
    case "i16": Some{S.int16()}
    case "u16": Some{S.uint16()}
    case "i32": Some{S.int32()}
    case "u32": Some{S.uint32()}
    case "i64": Some{S.int64()}
    case "u64": Some{S.uint64()}
    case "f16": Some{S.half()}
    case "bf16": Some{S.bfloat16()}
    case "f32": Some{S.single()}
    case "f64": Some{S.double()}
    case "fp8e4m3": Some{S.fp8e4m3()}
    case "fp8e4m3fnuz": Some{S.fp8e4m3fnuz()}
    case "fp8e5m2": Some{S.fp8e5m2()}
    case "fp8e5m2fnuz": Some{S.fp8e5m2fnuz()}
    # the block upstream labels `# legacy dtype aliases`
    case "float16": Some{S.half()}
    case "half": Some{S.half()}
    case "bfloat16": Some{S.bfloat16()}
    case "float32": Some{S.single()}
    case "float": Some{S.single()}
    case "float64": Some{S.double()}
    case "double": Some{S.double()}
    case "int8": Some{S.int8()}
    case "char": Some{S.int8()}
    case "uint8": Some{S.uint8()}
    case "uchar": Some{S.uint8()}
    case "int16": Some{S.int16()}
    case "short": Some{S.int16()}
    case "uint16": Some{S.uint16()}
    case "ushort": Some{S.uint16()}
    case "int32": Some{S.int32()}
    case "int": Some{S.int32()}
    case "uint32": Some{S.uint32()}
    case "uint": Some{S.uint32()}
    case "int64": Some{S.int64()}
    case "long": Some{S.int64()}
    case "uint64": Some{S.uint64()}
    case "ulong": Some{S.uint64()}
    case _: None{}

def to_dtype(nm: String) -> Maybe<&1, S.Dt>:
  to_dtype_of(nm)

# ===========================================================================
# commit_int -- the smallest dtype on the ladder that holds [lo, hi].
#
# The bounds are I64 because dtype.py takes Python ints and the ladder's top rung
# is uint64, whose max has no U32 image. Two consequences, both facts rather than
# simplifications:
#
#   * every I64 is inside int64's range, so the ladder's int64 rung always fits
#     and its uint64 rung can never be reached. dtype.py returns `long` when it
#     runs off the end anyway, so the answer is the same either way; the uint64
#     rung is unreachable here and the fallback IS dtype.py's fallback.
#   * the ladder starts at default_int, which may already be int32, so the int32
#     test runs twice in that case. That is dtype.py's behaviour, kept.
def i64_min_s32() -> H.I64: H.i64_of_hi_lo(4294967295, 2147483648)
def i64_max_s31() -> H.I64: H.i64_of_hi_lo(0, 2147483647)

def commit_int.i32fit(lo: H.I64, hi: H.I64) -> Bool:
  Bool.and(H.i64_le(i64_min_s32(), lo), H.i64_le(hi, i64_max_s31()))

def commit_int.i32(fit: Bool) -> Maybe<&1, S.Dt>:
  match fit:
    case True{}: Some{S.int32()}
    case False{}: Some{S.int64()}

def commit_int.hit(ok: Bool, di: S.Dt, fit: Bool) -> Maybe<&1, S.Dt>:
  match ok:
    case True{}: Some{di}
    case False{}: commit_int.i32(fit)

def commit_int.pick(m: Maybe<&1, Bool>, di: S.Dt, fit: Bool) -> Maybe<&1, S.Dt>:
  match m:
    case Some{ok}: commit_int.hit(ok, di, fit)
    case None{}: commit_int.hit(False{}, di, fit)

def commit_int.bounds(mn: Maybe<&1, H.I64>, mx: Maybe<&1, H.I64>, lo: H.I64,
  hi: H.I64) -> Maybe<&1, Bool>:
  match mn:
    case Some{a}:
      match mx:
        case Some{b}: Some{Bool.and(H.i64_le(a, lo), H.i64_le(hi, b))}
        case None{}: None{}
    case None{}: None{}

def commit_int(+lo: H.I64, +hi: H.I64, +di: S.Dt) -> Maybe<&1, S.Dt>:
  commit_int.pick(commit_int.bounds(dt_min(di), dt_max(di), lo, hi), di,
    commit_int.i32fit(lo, hi))


# ===========================================================================
# The 64-bit conversions, and why they are NOT seams.
#
# These six were `IO(..)` foreign defs -- a signature and two `import` lines and
# no body -- and they were six of this file's fourteen "defs rely on unsafe or
# foreign code". THE TYPE WAS NEVER THE WALL: `H.I64` is `I64{hi: U32, lo: U32}`
# (helpers.bend:1639) and helpers.bend already carries the whole 64-bit ALU
# (`i64_divmod`, `i64_add`, `i64_sub`, `i64_neg`, `i64_is_neg`, `i64_is_zero`,
# `i64_zero`, `i64_bit`). What blocked them was being effects.
#
# WHY BEING AN EFFECT WAS THE WALL, against the CALL GRAPH and not taste.
# `UOp._min_max` is a pure fold that `uop/fold.bend` computes in a Kahn worklist
# (`mixin/dtype.bend:38-60` is the standing record), and a fold cannot run an
# effect. There are exactly two ways out and only one of them is this file's:
#
#   (a) make the fold effectful -- that changes `fold.bend`'s `Folded`/`Table`
#       data type from a value to an `IO` value, propagates through every
#       consumer of the fold, and is `uop/fold.bend`'s call, not this file's;
#   (b) remove the effect from the LEAF, so the arithmetic stays exactly where
#       it is and the fold keeps calling a pure function.
#
# This file takes (b). The arithmetic does not move and the fold does not change
# type: what moved is the EFFECT BOUNDARY, out of the callee and nowhere. That is
# the opposite of making a fold effectful to make a gate pass -- the fold is
# still pure, and it is still `fold.bend`'s.
#
# THE DERIVATION IS NOT UPSTREAM'S SPELLING, and one op is the reason.
# helpers.py:75 is `cmod(x,y) = x - cdiv(x,y)*y`, and `i64_mul` does not exist
# anywhere in the tree -- `mixin/dtype.bend:56` records that and helpers.bend is
# not this file's to edit. So cdiv/cmod are derived from the FLOOR pair, which is
# total and multiply-free. With `q` the floor quotient, `r` the floor remainder
# and `fix = sign(a) != sign(b) and r != 0`:
#
#     cdiv = 0 if b == 0 else q + fix      (truncation is one above a floor)
#     cmod = r - (b if fix else 0)         (and NO zero guard: floormod(x,0) is x)
#     ceil = cdiv + (r != 0 and sign(a) == sign(b))    -- see Dt.i64_ceildiv
#
# `i64_abs` is deliberately NOT used: helpers.bend:1786 records that `i64_abs`
# answers `int64.min` for `int64.min`, so a magnitude route double-counts the sign
# on that one input, and both int64 edges are in the fixture set for that reason.
#
# `i64_trunc` is the identity because dtype.py's `truncate` of an already-integral
# value is, and `H.I64 -> H.I64` is the only thing this signature can express: an
# F32-sourced i64 cast has no signature here. See the note below the def.
#
# GATED against CPython -- `tinygrad/helpers.py` CALLED, never transcribed -- over
# 96 rows of 16 fixtures x 6 defs, with a plant and a disarm. See
# `.agents/slop/dtypeb/DTYPEB.md`.
# ===========================================================================

def Dt.i64_cdiv.fix(+an: Bool, +bn: Bool, +d: H.DivMod) -> Bool:
  Bool.and(Bool.xor(an, bn), Bool.not(H.i64_is_zero(H.divmod_r(d))))

def Dt.i64_cdiv.of(zero: Bool, +an: Bool, +bn: Bool, +d: H.DivMod) -> H.I64:
  Bool.pick(H.I64, zero, H.i64_zero(), H.i64_add(H.divmod_q(d), H.i64_bit(Bool.to_u32(Dt.i64_cdiv.fix(an, bn, d)))))

def Dt.i64_cdiv(+a: H.I64, +b: H.I64) -> H.I64:
  Dt.i64_cdiv.of(H.i64_is_zero(b), H.i64_is_neg(a), H.i64_is_neg(b), H.i64_divmod(a, b))

def Dt.i64_cmod.put(fix: Bool, +b: H.I64, +d: H.DivMod) -> H.I64:
  Bool.pick(H.I64, fix, H.i64_sub(H.divmod_r(d), b), H.divmod_r(d))

def Dt.i64_cmod.of(+an: Bool, +bn: Bool, +b: H.I64, +d: H.DivMod) -> H.I64:
  Dt.i64_cmod.put(Dt.i64_cdiv.fix(an, bn, d), b, d)

def Dt.i64_cmod(+a: H.I64, +b: H.I64) -> H.I64:
  Dt.i64_cmod.of(H.i64_is_neg(a), H.i64_is_neg(b), b, H.i64_divmod(a, b))

def Dt.i64_trunc(x: H.I64) -> H.I64:
  x

def Dt.i64_floor_div(a: H.I64, b: H.I64) -> H.I64:
  H.i64_div(a, b)

def Dt.i64_floor_mod(a: H.I64, b: H.I64) -> H.I64:
  H.i64_mod(a, b)

# The ceiling is `cdiv` plus one exactly when the division did not come out even
# and the operands shared a sign -- which is what dtype.c:240-242 computes, and it
# is what makes the def TOTAL where the spelling above is not. helpers.py:66-69 is
# `-((-x)//y)`, and `-x` is not representable when x is int64.min: for
# `ceildiv(int64.min, int64.min)` CPython answers 1 and the negation answers -1,
# because `-b` wraps back to int64.min and the def computes 1 // 1 and negates it.
# The fixture `min_min` is that row. An earlier spelling of this def did the
# negation and disagreed with CPython there; it is the second gate finding of this
# unit, after the fp8 one.
def Dt.i64_ceildiv.above(+an: Bool, +bn: Bool, +d: H.DivMod) -> Bool:
  Bool.and(Bool.not(Bool.xor(an, bn)), Bool.not(H.i64_is_zero(H.divmod_r(d))))

def Dt.i64_ceildiv.of(+zero: Bool, +an: Bool, +bn: Bool, +d: H.DivMod) -> H.I64:
  Bool.pick(H.I64, zero, H.i64_zero(), H.i64_add(Dt.i64_cdiv.of(zero, an, bn, d), H.i64_bit(Bool.to_u32(Dt.i64_ceildiv.above(an, bn, d)))))

def Dt.i64_ceildiv(+a: H.I64, +b: H.I64) -> H.I64:
  Dt.i64_ceildiv.of(H.i64_is_zero(b), H.i64_is_neg(a), H.i64_is_neg(b), H.i64_divmod(a, b))

# KNOWN DIVERGENCE, in these six and not in the ones they replace: helpers.py:66-69
# has NO zero guard on `ceildiv`, so CPython raises ZeroDivisionError for
# `ceildiv(x, 0)` while `i64_div` answers 0 here. runtime/dtype.c:239 and
# runtime/dtype.js:171 totalise it to 0 as well, so the answer is unchanged from
# the lanes this replaces. The gate counts those rows as `diverge` against the
# port's own 0 and NEVER as a pass.

# ===========================================================================
# float_to_fp8, and WHY IT IS PURE WHILE THE THREE BELOW IT ARE NOT.
#
# `float_to_fp8` was `-> IO(U32)` and its whole body was one call to
# `Dt.fp8_from`, which was a seam. It was red only because of that call: its own
# arithmetic is `F32.bits` (pure, and the one float direction Bend has) and
# `fp8_kind`. Both are pure here, because EVERY step of the encoder is U32
# arithmetic on a bit pattern -- no F32 is ever BUILT, and building one is the
# only thing this file cannot do.
#
# dtype.c:44-87 `fp8_encode` is that algorithm and this is it, arm for arm.
# GATED against CPython -- `tinygrad/dtype.py:float_to_fp8` CALLED, never
# transcribed -- over 384 rows. See `.agents/slop/dtypeb/DTYPEB.md`.
# ===========================================================================

type Fp8 is Data:
  Fp8{bias: U32, sig: U32, mant: U32, denorm: U32, ovf: U32, max_norm: U32, min_norm: U32}

# dtype.py's `_fp8_cfg` (dtype.py:236-241), four rows, in decimal.
#
# `ovf` IS NOT dtype.py's `ovf_threshold`. It is the LAST f32 MAGNITUDE dtype.py
# still sends to the normal branch, and the difference is load-bearing on three of
# the four formats: dtype.py writes three of those thresholds with a trailing `-1`,
# i.e. one f64 ULP BELOW the value, so `absx > threshold` is already true at exactly
# that value. runtime/dtype.c:40 restates all four as the f32 pattern of the value
# itself -- 0x47700000, 0x43780000, 0x47700000 -- and dtype.c:70 then compares with
# `>`, which loses the `-1`. Measured: at absx == 0x47700000 dtype.py answers 123
# for fp8e5m2 and 127 for fp8e4m3fnuz (both `max_norm`) and the C's comparison
# answers 124 and 128. `ovf` here is the threshold with the `-1` already applied, so
# the `>` below is dtype.py's `>` and not a restatement of it. REPORTED, not fixed:
# runtime/dtype.c is not this file's.
def fp8_cfg(kind: U32) -> Fp8:
  match kind:
    case 0: Fp8{7, 4, 7, 981467136, 1139277824, 126, 1015021568}
    case 1: Fp8{15, 3, 3, 922746880, 1198522367, 123, 947912704}
    case 2: Fp8{8, 4, 7, 973078528, 1131937791, 127, 1006632960}
    case _: Fp8{16, 3, 3, 914358272, 1198522367, 127, 939524096}

# THE ONE READER. Bend has no `cfg.field` accessor -- `cfg.denorm` is
# "expected : a defined name", measured -- so a record field is reachable only by
# destructuring. This destructures once and indexes, so seven constants cost one
# def instead of seven, and the index is the field's position in the record.
def Fp8.at(+cfg: Fp8, i: U32) -> U32:
  match cfg:
    case Fp8{bias, sig, mant, denorm, ovf, max_norm, min_norm}:
      match i:
        case 0: bias        # the exponent bias
        case 1: sig         # the fp8 significand width, 4 or 3
        case 2: mant        # the significand mask, 7 or 3
        case 3: denorm      # at or below this the answer is zero
        case 4: ovf         # above this the answer is max_norm; see fp8_cfg
        case 5: max_norm
        case _: min_norm    # at or above this the value is a normal

# A shift by a RUNTIME amount. `U32.shl`/`U32.shr` are one-bit and
# `U32.shln`/`U32.shrn` take a `Nat`, so without these a shaper whose shift amount
# is computed could not be written at all -- which is why dtype.c computes `sh`.
# The amount is `U32.to_nat` of a SMALL U32 on every path (1..4, or 19/20/21/23/31),
# never of a wrapped one: a Nat is Peano and `U32.to_nat(4294967295)` would ask it
# for 2^32 cells.
def fp8_enc.shl(a: U32, n: U32) -> U32: U32.shln(a, U32.to_nat(n))
def fp8_enc.shr(a: U32, n: U32) -> U32: U32.shrn(a, U32.to_nat(n))

def fp8_enc.is_fnuz(kind: U32) -> Bool: U32.is_ge(kind, 2)

# the tie bit: where the fp8 significand's rounding bit sits inside the f32
# pattern, `1 << (23 - sig)`
def fp8_enc.hu(+cfg: Fp8) -> U32: fp8_enc.shl(1, U32.sub(23, Fp8.at(cfg, 1)))

# the exponent field, and the mantissa field as the fp8 significand keeps it
def fp8_enc.exp_field(xb: U32) -> U32: U32.and(fp8_enc.shr(xb, 23), 255)
def fp8_enc.absx(xb: U32) -> U32: U32.and(xb, 2147483647)
def fp8_enc.exp(+cfg: Fp8, xb: U32) -> U32: U32.add(U32.sub(fp8_enc.exp_field(xb), 127), Fp8.at(cfg, 0))
def fp8_enc.mant(+cfg: Fp8, xb: U32) -> U32: U32.and(fp8_enc.shr(xb, U32.sub(24, Fp8.at(cfg, 1))), Fp8.at(cfg, 2))

# ROUND-HALF-TO-EVEN ON A DROPPED REMAINDER, one function for both rounding sites,
# because dtype.c:76 and dtype.c:88 differ only in which remainder and which tie
# they hand it: up when the dropped bits exceed the tie, or equal it and the kept
# value is odd.
def fp8_enc.round(+rb: U32, +tie: U32, +res: U32) -> U32:
  Bool.pick(U32, U32.is_gt(rb, tie), U32.add(res, 1),
    Bool.pick(U32, U32.is_eq(rb, tie), U32.add(res, Bool.to_u32(U32.is_eq(U32.and(res, 1), 1))), res))

# dtype.py's three non-finite cases, in its order (dtype.c:59-67). fnuz has neither
# inf nor nan and answers 0x80; e4m3 has no inf and answers jax's 0x7f/0xff; e5m2
# has a full nan and inf.
def fp8_enc.nonfinite(+kind: U32, +xb: U32, +sgn: U32) -> U32:
  Bool.pick(U32, fp8_enc.is_fnuz(kind), 128,
    Bool.pick(U32, U32.is_eq(kind, 0), Bool.pick(U32, U32.is_zero(sgn), 127, 255),
      U32.or(Bool.pick(U32, U32.is_zero(U32.and(xb, 8388607)), 124, 127), sgn)))

# The normal branch (dtype.c:73-77). The parity test rides on `res` rather than on
# `mant` because `sig - 1 >= 2`, so the exponent field contributes no low bit.
def fp8_enc.norm(+cfg: Fp8, +xb: U32, +exp: U32, +mant: U32) -> U32:
  +hu = fp8_enc.hu(cfg)
  fp8_enc.round(U32.and(xb, U32.sub(fp8_enc.shl(hu, 1), 1)), hu, U32.or(fp8_enc.shl(exp, U32.sub(Fp8.at(cfg, 1), 1)), mant))

# `1 - exp` where `exp` is `exp_field - 127 + bias` in WRAPPING U32 arithmetic, so
# the subnormal rungs are 1, 2, 3, 4 and the negative exps are 4294967295,
# 4294967294 and 4294967293. THE WINDOW IS FOUR EXPONENTS WIDE, not three:
# `absx > denorm` compares the whole magnitude, so the denorm threshold's OWN
# exponent field is in the branch whenever its mantissa is above zero. exp = -3 is
# reached on e4m3 and on fnuz-e4m3 -- and a three-rung ladder answers 1 there, which
# is the second gate finding of this unit. The catch-all is the exp == 0 rung, and
# it is exhaustive: the branch is entered with absx strictly below min_norm and
# strictly above denorm, so exp is one of exactly these four.
def fp8_enc.sh(exp: U32) -> U32:
  match exp:
    case 4294967293: 4
    case 4294967294: 3
    case 4294967295: 2
    case _: 1

def fp8_enc.sub(+cfg: Fp8, +xb: U32, +exp: U32, +mant: U32) -> U32:
  +sh = fp8_enc.sh(exp)
  +half = fp8_enc.shl(fp8_enc.hu(cfg), sh)
  +res = fp8_enc.shr(U32.or(mant, fp8_enc.shl(1, U32.sub(Fp8.at(cfg, 1), 1))), sh)
  fp8_enc.round(U32.and(U32.or(xb, 8388608), U32.sub(fp8_enc.shl(half, 1), 1)), half, res)

# The magnitude ladder (dtype.c:70-72). Zero at or below the denormal line, the
# largest normal above the overflow line, and the two rounding branches between.
def fp8_enc.res(+cfg: Fp8, +absx: U32, +exp: U32, +mant: U32) -> U32:
  Bool.pick(U32, U32.is_le(absx, Fp8.at(cfg, 3)), 0,
    Bool.pick(U32, U32.is_gt(absx, Fp8.at(cfg, 4)), Fp8.at(cfg, 5),
      Bool.pick(U32, U32.is_ge(absx, Fp8.at(cfg, 6)), fp8_enc.norm(cfg, absx, exp, mant),
        fp8_enc.sub(cfg, absx, exp, mant))))

def fp8_enc.put(+kind: U32, +res: U32, +sgn: U32) -> U32:
  # fnuz has no negative zero, so a zero result carries no sign (dtype.c:86)
  Bool.pick(U32, fp8_enc.is_fnuz(kind), Bool.pick(U32, U32.is_zero(res), 0, U32.or(res, sgn)), U32.or(res, sgn))

def fp8_enc(+cfg: Fp8, +kind: U32, +xb: U32) -> U32:
  +sgn = fp8_enc.shl(U32.and(fp8_enc.shr(xb, 31), 1), 7)
  +exp = fp8_enc.exp(cfg, xb)
  +res = fp8_enc.res(cfg, fp8_enc.absx(xb), exp, fp8_enc.mant(cfg, xb))
  Bool.pick(U32, U32.is_eq(fp8_enc.exp_field(xb), 255), fp8_enc.nonfinite(kind, xb, sgn),
    fp8_enc.put(kind, res, sgn))

def Dt.fp8_from(bits: U32, +kind: U32) -> U32: fp8_enc(fp8_cfg(kind), kind, bits)

# ===========================================================================
# THE SEAM THAT IS LEFT: three laws, and they are three because of ONE missing
# primitive, not three missing ones.
#
# MEASURED on Bend 2.0.34 (`./bin/bend`): `F32.bits` exists and is a bitcast --
# `F32.bits(1.0)` = 1065353216 = 0x3F800000. `F32.from_bits` does NOT exist
# ("expected : a defined name / observed : F32.from_bits"). And the near miss is
# not a near miss: `U32.to_f32` is the NUMERIC conversion, not a bitcast --
# `U32.to_f32(3)` = 3 and `U32.to_f32(1065353216)` = 1065353216. So Bend can take
# a float apart and cannot put one back together.
#
# All three of these end in exactly that step:
#     Dt.bf16      f32 bits -> bf16 bits -> F32       (dtype.c:168-176)
#     Dt.fp16      f32 -> half bits -> F32              (dtype.c:156-158, via fp16_f32)
#     Dt.fp8_to    fp8 code -> f32 bits -> F32          (dtype.c:160-162, via fp8_decode)
# and the three pure wrappers below them are red only because of these three --
# `float_to_bf16`, `float_to_fp16` and `fp8_to_float` have no arithmetic of their
# own at all. Six red laws, one missing primitive.
#
# WHAT WOULD CLOSE IT: a `F32.from_bits(bits: U32) -> F32` in base.bend. Every one
# of the three bodies is already written in U32 in runtime/dtype.c and is a port
# away -- `fp16_encode`, `fp16_f32` and `fp8_decode` are pure U32 except for
# dtype.c:105-110's `f32_rewrap`, which IS that bitcast. This is a LANGUAGE wall
# and base.bend is not this file's.
# ===========================================================================

def Dt.bf16(bits: U32) -> IO(F32):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

def Dt.fp16(x: F32) -> IO(F32):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

def Dt.fp8_to(bits: U32, kind: U32) -> IO(F32):
  import "./runtime/dtype.c"
  import "./runtime/dtype.js"

# The fp8 id, as the C and the JS agree on it.
def fp8_kind(nm: String) -> U32:
  match nm:
    case "fp8e4m3": 0
    case "fp8e5m2": 1
    case "fp8e4m3fnuz": 2
    case _: 3

# dtype.py's float_to_bf16, through the seam. `bf16` takes the pattern because
# dtype.py's first step is `struct.pack('f', truncate[float](x))` and Bend's F32
# is already that pattern; the round is the whole of dtype.py's function.
def float_to_bf16(x: F32) -> IO(F32):
  Dt.bf16(F32.bits(x))

# dtype.py's float_to_fp16.
def float_to_fp16(x: F32) -> IO(F32):
  Dt.fp16(x)

# dtype.py's float_to_fp8 / fp8_to_float. The first is pure: see the header.
def float_to_fp8(x: F32, dtype: S.Dt) -> U32:
  Dt.fp8_from(F32.bits(x), fp8_kind(dt_name(dtype)))

def fp8_to_float(x: U32, dtype: S.Dt) -> IO(F32):
  Dt.fp8_to(x, fp8_kind(dt_name(dtype)))
