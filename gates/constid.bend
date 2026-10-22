# constid.bend -- THE PORT's SIDE of the two CONST-IDENTITY divergences.
#
#   .venv/bin/python gates/constid-gate.py
#
# THE MERGE.  Upstream keeps `0.1` (a DOUBLE) and `0.10000000149011612` (the f32 nearest
# 0.1) apart: two doubles, two `ConstFloat.bits` (`dtype.py:8-25`), two hashes, TWO KEYS in
# upstream's `ucache`.  The port holds an F32, and the f32 nearest 0.1 IS the f32 nearest
# 0.10000000149011612 -- so the port's arena holds ONE key for the pair.
#
# THE SECOND PAIR IS THE ONE WHOSE VALUE IS VISIBLE.  `0.1` and `0.10000000149011612`
# differ in the NINTH decimal, and the port's own `f32_fixed` walks the fraction in f32
# arithmetic, so the f32's precision eats the difference before it can be printed.  The
# smallest integer an f32 cannot hold is 2**24+1 = 16777217, and there the difference is
# ONE WHOLE UNIT -- visible in the integer part, in the port's own formatter.
#
# THE SPLIT.  Upstream's `ConstFloat.__eq__` says `nan == nan` for ANY two nans while its
# `__hash__` is `hash(self.bits)` (`dtype.py:16-21`), so upstream's OWN hash table keeps two
# nans with different payloads apart: `__eq__` and `__hash__` contradict each other.  The
# port's `eq_const.CFloat` compares the BITS, so it agrees with upstream's hash table.
#
# EVERY COUNT BELOW IS A COUNT OF KEYS IN ONE HASH TABLE.  Upstream's hash table is
# `UOpMetaClass.ucache` and its key is `(op, src, arg, tag, type(arg))` (`ops.py:201`); the
# port's is the ARENA, whose intern is `intern.find` -- a scan over the node list whose key
# comparison is `eq_node` -> `eq_arg` -> `eq_arg.APy` -> `eq_const` -> `eq_const.CFloat`.
# The oracle counts the entries in ONE dict keyed by upstream's OWN key tuple.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/base.bend as F

# THE NAN PAYLOADS, spelled as DECIMALS because Bend's `NUMBER` is
# `/(\d+)(n|\.\d+([eE][+-]?\d+)?)?/` and has no hex.  A NUMBER with no `n` suffix is a U32
# literal (`bend.ts:2216-2219`); a `Nat` literal is UNARY past 256 (`NAT_LITERAL_MAX = 256`,
# `bend.ts:1101`), so these are U32 literals on purpose.
def NAN_P1() -> U32: 2143289344   # 0x7FC00000
def NAN_P2() -> U32: 2143289345   # 0x7FC00001

# SIX DECIMAL PLACES, and the number is a PARAMETER both lanes agree on.
def VALUE_DP() -> Nat: 6n

def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# ---------------------------------------------------------------------------
# THE COMPARED ROWS.  These are the ones CPython can be asked the SAME question about.
# ---------------------------------------------------------------------------

# THE f32 of 0.1.  `struct.pack('<f', 0.1)` on the oracle side, `F32.bits(0.1)` here.
def merge_f32_bits() -> U32: F32.bits(0.1)

# THE CONTROL: two constants the port CAN tell apart, so a count that reads 1 for every
# pair is a count that measured nothing.
def merge_keys_control() -> U32:
  +ar0 = O.Arena.empty()
  +a = O.UOp.const(ar0, O.CFloat{0.1})
  +b = O.UOp.const(O.Found.ar(a), O.CFloat{0.5})
  U32.sub(O.Arena.next(O.Found.ar(b)), 1)

# TWO NANS OF THE SAME PAYLOAD: one key.  Upstream's dict says one entry, and the reason
# upstream says it is NOT `__eq__` -- it is `__hash__`, which is `hash(self.bits)`.
def split_keys_same() -> U32:
  +ar0 = O.Arena.empty()
  +a = O.UOp.const(ar0, O.CFloat{F.F32.from_bits(NAN_P1())})
  +b = O.UOp.const(O.Found.ar(a), O.CFloat{F.F32.from_bits(NAN_P1())})
  U32.sub(O.Arena.next(O.Found.ar(b)), 1)

# THE REACHABLE NAN: `F32.div(0.0, 0.0)`, which is how `t_float_nan_interns` makes one.
# Upstream's `DType.const` CANONICALISES a nan to `math.nan` (`dtype.py:81-82`), so the
# reachable upstream const nan is exactly ONE payload and one key -- and so is this one.
def split_keys_reachable() -> U32:
  +ar0 = O.Arena.empty()
  +a = O.UOp.const(ar0, O.CFloat{F32.div(0.0, 0.0)})
  +b = O.UOp.const(O.Found.ar(a), O.CFloat{F32.div(0.0, 0.0)})
  U32.sub(O.Arena.next(O.Found.ar(b)), 1)

# ---------------------------------------------------------------------------
# THE DECLARED DIVERGENCE.  Three rows, and ALL of them are pinned on both sides.
# ---------------------------------------------------------------------------

# THE COUNT OF KEYS IN ONE ARENA for the two upstream constants.  `Arena.empty()` parks a
# BOTTOM sentinel at index 0, so `Arena.next` is the key count plus one.
def merge_keys() -> U32:
  +ar0 = O.Arena.empty()
  +a = O.UOp.const(ar0, O.CFloat{0.1})
  +b = O.UOp.const(O.Found.ar(a), O.CFloat{0.10000000149011612})
  U32.sub(O.Arena.next(O.Found.ar(b)), 1)

# THE SAME COUNT FOR THE PAIR WHOSE VALUE IS VISIBLE.  `16777217.0` and `16777216.0` are
# TWO DIFFERENT DOUBLES upstream -- `0x4170000010000000` and `0x4170000000000000` -- and
# ONE f32 here: `0x4B800000` for both.
def merge_keys_int() -> U32:
  +ar0 = O.Arena.empty()
  +a = O.UOp.const(ar0, O.CFloat{16777217.0})
  +b = O.UOp.const(O.Found.ar(a), O.CFloat{16777216.0})
  U32.sub(O.Arena.next(O.Found.ar(b)), 1)

# THE VALUE the constant HOLDS, at six decimal places.  Upstream holds the double
# 16777217.0; the port holds the f32 of it, which is 16777216.0.
def merge_value_text() -> String: H.f32_fixed.body(16777217.0, VALUE_DP())

# ---------------------------------------------------------------------------
# THE LANE-SPLIT ROWS.  These three are PORT-ONLY: the oracle is not asked, because the
# oracle has ONE float width and the port has TWO LANES.  See the gate's own header.
# ---------------------------------------------------------------------------

# TWO NAN PAYLOADS.  The C lane keeps the payload and answers 2 keys; the JS lane hands
# the float to JavaScript, whose `NaN` is a single value, and answers 1.
def split_keys_distinct() -> U32:
  +ar0 = O.Arena.empty()
  +a = O.UOp.const(ar0, O.CFloat{F.F32.from_bits(NAN_P1())})
  +b = O.UOp.const(O.Found.ar(a), O.CFloat{F.F32.from_bits(NAN_P2())})
  U32.sub(O.Arena.next(O.Found.ar(b)), 1)

# WHAT THE PORT'S KEY COMPARATOR ANSWERS for the two payloads.
def split_eq_distinct() -> Bool:
  O.eq_const.CFloat(O.CFloat{F.F32.from_bits(NAN_P1())}, F.F32.from_bits(NAN_P2()))

# THE BITS OF THE SECOND PAYLOAD AFTER THE ROUND TRIP.  The C lane keeps 0x7FC00001; the
# JS lane collapses it onto 0x7FC00000.
def split_bits_p2() -> U32: F32.bits(F.F32.from_bits(NAN_P2()))

def rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- urow("merge_f32_bits", merge_f32_bits())
    b : Unit <- urow("merge_keys_control", merge_keys_control())
    c : Unit <- urow("split_keys_same", split_keys_same())
    d : Unit <- urow("split_keys_reachable", split_keys_reachable())
    e : Unit <- urow("merge_keys", merge_keys())
    f : Unit <- urow("merge_keys_int", merge_keys_int())
    g : Unit <- srow("merge_value_text", merge_value_text())
    h : Unit <- urow("split_keys_distinct", split_keys_distinct())
    i : Unit <- row("split_eq_distinct", split_eq_distinct())
    urow("split_bits_p2", split_bits_p2())

def main() -> IO(Unit): rows()
