import Base
import ./../base.bend as F
import ./../helpers.bend as H

# ===========================================================================
# llm/gguf.bend -- tinygrad/llm/gguf.py (272 lines): THE GGUF FILE FORMAT READER.
#
# PORTED, and gated against CPython over a real `.gguf` file: `_GGML_NATIVE`
# (:20-21), `_GGML_QUANT` (:24-27), the fifteen-entry `readers` table (:193-195),
# `_read_unpack` / `read_str` / `read_arr` (:187-191), and `gguf_parse`'s HEADER
# (:198-231) -- magic, version, every `kv` pair, every tensor's `(name, dims,
# ggml_type, offset)`, `general.alignment`, the `round_up(tell())` data section,
# and each tensor's `(byte start, byte length)`.
#
# NOT PORTED, each a named wall rather than a TODO-shaped hole:
#   * `ggml_data_to_tensor` (:29-185). Twenty-one quant decode ladders over a
#     `Tensor`, five of which index CONSTANT GRIDS that come from
#     `tinygrad.runtime.autogen.ggml_common` (`iq3xxs_grid`, `iq2xs_grid`,
#     `iq1s_grid`, `iq3s_grid`, `iq2s_grid`, `kvalues_iq4nl`). MEASURED: the
#     port's `runtime/autogen/` holds `libclang.bend` and nothing else.
#   * the TENSOR branch (:230 `tensor[start:start+nbytes]`) and
#     `gguf_load` / `gguf_shard` (:233-272). Slicing a `Tensor` is
#     `nn/state.bend`'s `TensorIO` wall, so this file answers a `TI` -- offset,
#     start and length -- which is the whole header and the only thing a caller
#     needs before a slice would be legal.
#   * a `Tensor` ARGUMENT (:204 `isinstance(file, Tensor)`). `gguf.parse` takes
#     BYTES, so the reader knows nothing about devices; the gate hands it
#     `File.read_bytes`.
#
# THREE BOUNDS A ROW CAN SEE, stated so a reader does not have to find them:
#   * `prod(dims)` and `nbytes` are `U32`, so this reader covers tensors up to
#     4 GiB. CPython is unbounded and the gate compares the two directly, so a
#     bigger tensor would DIVERGE rather than wrap quietly.
#   * an f64 metadata value carries its EIGHT BYTES, because Bend has no f64 and
#     the bits ARE the value (the oracle compares them to `struct.pack("<d", v)`).
#   * an array of arrays is refused. GGUF's own spec forbids it, and it is the
#     one recursion Bend's termination check will not accept: the tail of a
#     length-prefixed read is not a subterm of the list it came from.
#
# TWO SYNTAX FACTS THIS FILE HAD TO BE WRITTEN AROUND, both measured, because
# they decide its shape and not its meaning:
#   * a record literal's fields are POSITIONAL. `CS{a: x}` is `expected a term`.
#   * `(a, b) = f(x)` is REFUSED -- a destructuring let is a match, and a match
#     may not scrutinise a call. So every read answers a record and its fields
#     are projected by a def of their own (`Wd.v`, `Wd.rs`, ...).
# ===========================================================================

# one GGUF metadata value.
#
# `gguf_parse` answers a Python dict of `str`/`int`/`float`/`bool`/`bytes`/`list`,
# and THIS IS THE SAME OBSERVABLE VALUE -- which is why eight of the thirteen
# metadata types collapse into `GVInt`: `struct.unpack("<b")` and `"<B"` differ
# only in whether the byte is sign-extended, and after that a reader cannot tell
# -1 from -1. `GVF32` holds a real `F32` (`F.F32.from_bits`, the port's own
# bitcast), so the value is a float and not a word pretending to be one.
type GVal is Data:
  GVInt{v: U32}
  GVI64{v: H.I64}
  GVF32{v: F32}
  GVF64{v: H.I64}
  GVBool{v: Bool}
  GVStr{v: String}
  GVArr{vs: List<&2, GVal>}

# The port has no exception form, so `gguf_parse`'s two SPELLED raises become a
# value: :209 `ValueError("Invalid GGUF format!")` covers BOTH the magic and the
# version, and :228 spells `ValueError(f"GGML type '{typ}' is not supported!")`.
# :214's unknown METADATA type is an uncaught `KeyError` in CPython -- no message
# to mirror -- so `BadMeta` exists only so the port can say where it stopped.
type Bad is Data:
  BadMagic{}
  BadVersion{v: U32}
  BadMeta{typ: U32}
  BadBlk{typ: U32}

# A cursor: the bytes NOT YET READ, and how many HAVE BEEN -- `r.tell()`, which
# :224 rounds up to the alignment to find where the data section starts.
type Cur is Data:
  Cur{bs: List<&2, U32>, at: U32}

type KV is Data:
  KV{k: String, v: GVal}

# `gguf_parse`'s tensor tuple, `(data, shape, ggml_type)`, with the `data` view
# replaced by the integers that define it. `shape` is ALREADY REVERSED: :230 is
# `tuple(reversed(dims))`, and the reversal happens where the dims are read so no
# caller has to remember it.
type TIE is Data:
  TIE{nm: String, shape: List<&2, H.I64>, typ: U32, off: H.I64}

type TI is Data:
  TI{nm: String, shape: List<&2, H.I64>, typ: U32, off: H.I64, start: H.I64, nbytes: U32}

type Parsed is Data:
  Parsed{kv: List<&2, KV>, ts: List<&2, TI>, ds: U32, bad: Maybe<&2, Bad>}

type KOut is Data:
  KOut{kv: List<&2, KV>, cur: Cur, bad: U32}

type TOut is Data:
  TOut{ts: List<&2, TIE>, cur: Cur, bad: U32}

type VOut is Data:
  VOut{cur: Cur, v: GVal, bad: U32}

type Blk is Data:
  Blk{el: U32, by: U32}

type Wd is Data:
  Wd{v: U32, rest: List<&2, U32>}

type W8 is Data:
  W8{v: H.I64, rest: List<&2, U32>}

type Nx is Data:
  Nx{got: List<&2, U32>, rest: List<&2, U32>}

type CS is Data:
  CS{cur: Cur, v: String}

type DI is Data:
  DI{cur: Cur, dims: List<&2, H.I64>}

type MV is Data:
  MV{mg: U32, ver: U32, cur: Cur}

# EVERY record's fields are read through a def of this kind: bend generates no
# field projection at all (bend2-constraints rule 27), and a record literal's
# fields are positional (rule 43's neighbour), so this block IS the interface.
def VOut.cur(x: VOut) -> Cur:
  match x:
    case VOut{cur, _, _}: cur

def VOut.v(x: VOut) -> GVal:
  match x:
    case VOut{_, v, _}: v

def VOut.bad(x: VOut) -> U32:
  match x:
    case VOut{_, _, bad}: bad

def KOut.kv(x: KOut) -> List<&2, KV>:
  match x:
    case KOut{kv, _, _}: kv

def KOut.cur(x: KOut) -> Cur:
  match x:
    case KOut{_, cur, _}: cur

def KOut.bad(x: KOut) -> U32:
  match x:
    case KOut{_, _, bad}: bad

def TOut.ts(x: TOut) -> List<&2, TIE>:
  match x:
    case TOut{ts, _, _}: ts

def TOut.cur(x: TOut) -> Cur:
  match x:
    case TOut{_, cur, _}: cur

def TOut.bad(x: TOut) -> U32:
  match x:
    case TOut{_, _, bad}: bad

def TIE.nm(x: TIE) -> String:
  match x:
    case TIE{nm, _, _, _}: nm

def TIE.shape(x: TIE) -> List<&2, H.I64>:
  match x:
    case TIE{_, shape, _, _}: shape

def TIE.typ(x: TIE) -> U32:
  match x:
    case TIE{_, _, typ, _}: typ

def TIE.off(x: TIE) -> H.I64:
  match x:
    case TIE{_, _, _, off}: off

def KV.v(x: KV) -> GVal:
  match x:
    case KV{_, v}: v

def Parsed.kv(x: Parsed) -> List<&2, KV>:
  match x:
    case Parsed{kv, _, _, _}: kv

def Parsed.ts(x: Parsed) -> List<&2, TI>:
  match x:
    case Parsed{_, ts, _, _}: ts

def Parsed.ds(x: Parsed) -> U32:
  match x:
    case Parsed{_, _, ds, _}: ds

def Parsed.bad(x: Parsed) -> Maybe<&2, Bad>:
  match x:
    case Parsed{_, _, _, bad}: bad

def TI.nm(x: TI) -> String:
  match x:
    case TI{nm, _, _, _, _, _}: nm

def TI.shape(x: TI) -> List<&2, H.I64>:
  match x:
    case TI{_, shape, _, _, _, _}: shape

def TI.typ(x: TI) -> U32:
  match x:
    case TI{_, _, typ, _, _, _}: typ

def TI.off(x: TI) -> H.I64:
  match x:
    case TI{_, _, _, off, _, _}: off

def TI.start(x: TI) -> H.I64:
  match x:
    case TI{_, _, _, _, start, _}: start

def TI.nbytes(x: TI) -> U32:
  match x:
    case TI{_, _, _, _, _, nbytes}: nbytes

def Blk.el(x: Blk) -> U32:
  match x:
    case Blk{el, _}: el

def Blk.by(x: Blk) -> U32:
  match x:
    case Blk{_, by}: by

def KV.k(x: KV) -> String:
  match x:
    case KV{k, _}: k

def MV.mg(x: MV) -> U32:
  match x:
    case MV{mg, _, _}: mg

def MV.ver(x: MV) -> U32:
  match x:
    case MV{_, ver, _}: ver

def MV.cur(x: MV) -> Cur:
  match x:
    case MV{_, _, cur}: cur


def Wd.v(x: Wd) -> U32:
  match x:
    case Wd{v, _}: v

def Wd.rs(x: Wd) -> List<&2, U32>:
  match x:
    case Wd{_, rest}: rest

def W8.v(x: W8) -> H.I64:
  match x:
    case W8{v, _}: v

def W8.rs(x: W8) -> List<&2, U32>:
  match x:
    case W8{_, rest}: rest

def Nx.gt(x: Nx) -> List<&2, U32>:
  match x:
    case Nx{got, _}: got

def Nx.rs(x: Nx) -> List<&2, U32>:
  match x:
    case Nx{_, rest}: rest

def CS.v(x: CS) -> String:
  match x:
    case CS{_, v}: v

def CS.cur(x: CS) -> Cur:
  match x:
    case CS{cur, _}: cur

def DI.dims(x: DI) -> List<&2, H.I64>:
  match x:
    case DI{_, dims}: dims

def DI.cur(x: DI) -> Cur:
  match x:
    case DI{cur, _}: cur

def Cur.bs(c: Cur) -> List<&2, U32>:
  match c:
    case Cur{bs, _}: bs

def Cur.at(c: Cur) -> U32:
  match c:
    case Cur{_, at}: at

def cr.next(c: Cur, n: U32, rest: List<&2, U32>) -> Cur:
  match c:
    case Cur{_, at}: Cur{rest, U32.add(at, n)}

# "no unsupported type was read yet": a ggml type code is at most 41 (:24-27 and
# :20-21 together), so 0xffffffff is outside the key space and `is_eq(_, nobad())`
# is the only test that belongs here.
def nobad() -> U32: 4294967295

# b"GGUF" read little-endian: 0x47 'G', 0x47 'G', 0x55 'U', 0x46 'F'.
def magic() -> U32: 1179993927

def blk.bad(t: U32, +prev: U32) -> U32:
  Bool.pick(U32, U32.is_eq(prev, nobad()), t, prev)

# ---------------------------------------------------------------------------
# bytes: the four fixed widths, and a length-prefixed run.
#
# A truncated file answers short here; CPython raises `struct.error`. The
# alignment the parser computes is exact on any file that would have parsed.
# ---------------------------------------------------------------------------
# `struct.unpack("<I")` and `"<Q"` are little-endian, so the LOW word of an
# eight-byte field is bytes 0..3 and its HIGH word is bytes 4..7.
def le4(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.add(a, U32.add(U32.mul(b, 256), U32.add(U32.mul(c, 65536), U32.mul(d, 16777216))))

def by.t1(bs: List<&2, U32>) -> Wd:
  match bs:
    case h <> t: Wd{h, t}
    case Nil{}: Wd{0, Nil{}}

def by.t2(bs: List<&2, U32>) -> Wd:
  match bs:
    case a <> b <> t: Wd{U32.add(a, U32.mul(b, 256)), t}
    case _: Wd{0, Nil{}}

def by.t4(bs: List<&2, U32>) -> Wd:
  match bs:
    case a <> b <> c <> d <> t: Wd{le4(a, b, c, d), t}
    case _: Wd{0, Nil{}}

def by.t8(bs: List<&2, U32>) -> W8:
  match bs:
    case a <> b <> c <> d <> e <> f <> g <> h <> t:
      W8{H.i64_of_hi_lo(le4(e, f, g, h), le4(a, b, c, d)), t}
    case _: W8{H.i64_of_hi_lo(0, 0), Nil{}}

def by.n(k: Nat, bs: List<&2, U32>, acc: List<&2, U32>) -> Nx:
  match k bs:
    case 0n rest: Nx{List.reverse(&2, U32, acc), rest}
    case 1n+p Nil{}: Nx{List.reverse(&2, U32, acc), Nil{}}
    case 1n+p h <> t: by.n(p, t, h <> acc)

# ---------------------------------------------------------------------------
# `read_str` (:188): a u64 length, then that many bytes, decoded as UTF-8.
#
# THE FUEL IS THE BYTE COUNT, and it is not decoration: a multi-byte sequence
# consumes a PREFIX of the tail, and a prefix taken by a length-prefixed read is
# not a subterm of the list it came from -- the one shape Bend's termination
# check refuses outright.
# ---------------------------------------------------------------------------
def u32get(xs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, n), 0)

# continuation bytes wanted, 0..3
def utf8.want(+b: U32) -> Nat:
  Bool.pick(Nat, U32.is_lt(b, 128), 0n,
    Bool.pick(Nat, U32.is_lt(b, 224), 1n,
      Bool.pick(Nat, U32.is_lt(b, 240), 2n, 3n)))

def utf8.cp(+b: U32, +c1: U32, +c2: U32, c3: U32) -> U32:
  Bool.pick(U32, U32.is_lt(b, 128), b,
    Bool.pick(U32, U32.is_lt(b, 224),
      U32.add(U32.shln(U32.and(b, 31), 6n), U32.and(c1, 63)),
      Bool.pick(U32, U32.is_lt(b, 240),
        U32.add(U32.shln(U32.and(b, 15), 12n), U32.add(U32.shln(U32.and(c1, 63), 6n), U32.and(c2, 63))),
        U32.add(U32.shln(U32.and(b, 7), 18n),
          U32.add(U32.shln(U32.and(c1, 63), 12n),
            U32.add(U32.shln(U32.and(c2, 63), 6n), U32.and(c3, 63)))))))

def s.cons(h: Char, t: String) -> String:
  SCon{h, t}

def utf8.go(k: Nat, bs: List<&2, U32>, acc: String) -> String:
  match k bs:
    case 0n _: acc
    case 1n+p Nil{}: acc
    case 1n+p +b <> t:
      +x = by.n(utf8.want(b), t, Nil{})
      utf8.go(p, Nx.rs(x),
        s.cons(Char.from_u32(utf8.cp(b, u32get(Nx.gt(x), 0n), u32get(Nx.gt(x), 1n), u32get(Nx.gt(x), 2n))), acc))

def s.rev(s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{h, t}: s.rev(t, s.cons(h, acc))

def utf8.of(+bs: List<&2, U32>) -> String:
  s.rev(utf8.go(List.length(&2, U32, bs), bs, SNil{}), SNil{})

def cr.str(+c: Cur) -> CS:
  +k = by.t8(Cur.bs(c))
  +x = by.n(U32.to_nat(H.lo32(W8.v(k))), W8.rs(k), Nil{})
  +s = utf8.of(Nx.gt(x))
  n = cr.next(c, U32.add(8, H.lo32(W8.v(k))), Nx.rs(x))
  CS{n, s}

# ---------------------------------------------------------------------------
# `readers` (:193-195) as thirteen constructors. :193 spells 8 -> `read_str` and
# 9 -> `read_arr`; the other eleven are `functools.partial(_read_unpack, "<"+f,
# nb)` for f in {c,b,H,h,I,i,f,?,Q,q,d} (:194-195), so the format IS the table.
# ---------------------------------------------------------------------------
type Fmt is Data:
  FChr{}
  FI8{}
  FU16{}
  FI16{}
  FU32{}
  FI32{}
  FF32{}
  FBool{}
  FStr{}
  FArr{}
  FU64{}
  FI64{}
  FF64{}

# The arms are in DESCENDING order and the gate carries a row for every code
# 0..15, because a `U32` literal arm is a PREFIX match over the successor
# relation (bend2-constraints' `mixin/rand` rule 2): listed high-to-low, no arm
# claims a value a later arm wants.
def rd.fmt(typ: U32) -> Maybe<&1, Fmt>:
  match typ:
    case 12: Some{FF64{}}
    case 11: Some{FI64{}}
    case 10: Some{FU64{}}
    case 9: Some{FArr{}}
    case 8: Some{FStr{}}
    case 7: Some{FBool{}}
    case 6: Some{FF32{}}
    case 5: Some{FI32{}}
    case 4: Some{FU32{}}
    case 3: Some{FI16{}}
    case 2: Some{FU16{}}
    case 1: Some{FI8{}}
    case 0: Some{FChr{}}
    case _: None{}

# `struct.unpack("<b", b)` and `"<h"` sign-extend; `"<B"`, `"<H"`, `"<I"` do not.
def sc.sx8(+b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(b, 128), U32.or(b, 4294967040), b)

def sc.sx16(+w: U32) -> U32:
  Bool.pick(U32, U32.is_ge(w, 32768), U32.or(w, 4294901760), w)

def sc.read(+c: Cur, f: Fmt) -> VOut:
  match f:
    case FChr{}:
      +w = by.t1(Cur.bs(c))
      VOut{cr.next(c, 1, Wd.rs(w)), GVInt{Wd.v(w)}, nobad()}
    case FI8{}:
      +w = by.t1(Cur.bs(c))
      VOut{cr.next(c, 1, Wd.rs(w)), GVInt{sc.sx8(Wd.v(w))}, nobad()}
    case FU16{}:
      +w = by.t2(Cur.bs(c))
      VOut{cr.next(c, 2, Wd.rs(w)), GVInt{Wd.v(w)}, nobad()}
    case FI16{}:
      +w = by.t2(Cur.bs(c))
      VOut{cr.next(c, 2, Wd.rs(w)), GVInt{sc.sx16(Wd.v(w))}, nobad()}
    case FU32{}:
      +w = by.t4(Cur.bs(c))
      VOut{cr.next(c, 4, Wd.rs(w)), GVInt{Wd.v(w)}, nobad()}
    case FI32{}:
      +w = by.t4(Cur.bs(c))
      VOut{cr.next(c, 4, Wd.rs(w)), GVInt{Wd.v(w)}, nobad()}
    case FF32{}:
      +w = by.t4(Cur.bs(c))
      VOut{cr.next(c, 4, Wd.rs(w)), GVF32{F.F32.from_bits(Wd.v(w))}, nobad()}
    case FBool{}:
      +w = by.t1(Cur.bs(c))
      VOut{cr.next(c, 1, Wd.rs(w)), GVBool{U32.is_ne(Wd.v(w), 0)}, nobad()}
    case FStr{}:
      +s = cr.str(c)
      VOut{CS.cur(s), GVStr{CS.v(s)}, nobad()}
    case FU64{}:
      +w = by.t8(Cur.bs(c))
      VOut{cr.next(c, 8, W8.rs(w)), GVI64{W8.v(w)}, nobad()}
    case FI64{}:
      +w = by.t8(Cur.bs(c))
      VOut{cr.next(c, 8, W8.rs(w)), GVI64{W8.v(w)}, nobad()}
    case FF64{}:
      +w = by.t8(Cur.bs(c))
      VOut{cr.next(c, 8, W8.rs(w)), GVF64{W8.v(w)}, nobad()}
    case FArr{}:
      VOut{c, GVArr{Nil{}}, 9}

# `read_arr` (:189-191): an int32 ELEMENT TYPE, a u64 count, then the items.
# An item that failed to read is not appended, which is the one thing CPython
# cannot show here: it raises, and this answers a shorter list beside `bad`.
def arr.put(ok: Bool, v: GVal, acc: List<&2, GVal>) -> List<&2, GVal>:
  match ok:
    case True{}: v <> acc
    case False{}: acc

def arr.items(k: Nat, +g: Fmt, c: Cur, acc: List<&2, GVal>, bad: U32) -> VOut:
  match k:
    case 0n: VOut{c, GVArr{List.reverse(&2, GVal, acc)}, bad}
    case 1n+p:
      +o = sc.read(c, g)
      arr.items(p, g, VOut.cur(o),
        arr.put(U32.is_eq(VOut.bad(o), nobad()), VOut.v(o), acc),
        blk.bad(VOut.bad(o), bad))

def rd.arrgo(f: Maybe<&1, Fmt>, ityp: U32, k: Nat, c: Cur) -> VOut:
  match f:
    case None{}: VOut{c, GVArr{Nil{}}, ityp}
    case Some{+g}: arr.items(k, g, c, Nil{}, nobad())

def rd.arr(+c: Cur) -> VOut:
  +i = by.t4(Cur.bs(c))
  +c1 = cr.next(c, 4, Wd.rs(i))
  +n = by.t8(Cur.bs(c1))
  rd.arrgo(rd.fmt(Wd.v(i)), Wd.v(i), U32.to_nat(H.lo32(W8.v(n))), cr.next(c1, 8, W8.rs(n)))

def rd.vsome(g: Fmt, c: Cur) -> VOut:
  match g:
    case FArr{}: rd.arr(c)
    case _: sc.read(c, g)

def rd.vgo(f: Maybe<&1, Fmt>, typ: U32, c: Cur) -> VOut:
  match f:
    case None{}: VOut{c, GVInt{0}, typ}
    case Some{+g}: rd.vsome(g, c)

def rd.val(+typ: U32, c: Cur) -> VOut:
  rd.vgo(rd.fmt(typ), typ, c)

# ---------------------------------------------------------------------------
# `_GGML_NATIVE` (:20-21) as an ITEMSIZE, and `_GGML_QUANT` (:24-27) as a block.
# :226-227 reads the first as `(block, size) = (1, itemsize)` and the second as
# `(block, size) = _GGML_QUANT[typ]`.
# ---------------------------------------------------------------------------
def blk.native(t: U32) -> Maybe<&1, U32>:
  match t:
    case 30: Some{2}
    case 28: Some{8}
    case 27: Some{8}
    case 26: Some{4}
    case 25: Some{2}
    case 24: Some{1}
    case 1: Some{2}
    case 0: Some{4}
    case _: None{}

def blk.quant(t: U32) -> Maybe<&1, Blk>:
  match t:
    case 41: Some{Blk{128, 18}}
    case 39: Some{Blk{32, 17}}
    case 29: Some{Blk{256, 56}}
    case 23: Some{Blk{256, 136}}
    case 22: Some{Blk{256, 82}}
    case 21: Some{Blk{256, 110}}
    case 20: Some{Blk{32, 18}}
    case 19: Some{Blk{256, 50}}
    case 18: Some{Blk{256, 98}}
    case 17: Some{Blk{256, 74}}
    case 16: Some{Blk{256, 66}}
    case 14: Some{Blk{256, 210}}
    case 13: Some{Blk{256, 176}}
    case 12: Some{Blk{256, 144}}
    case 11: Some{Blk{256, 110}}
    case 10: Some{Blk{256, 84}}
    case 8: Some{Blk{32, 34}}
    case 7: Some{Blk{32, 24}}
    case 6: Some{Blk{32, 22}}
    case 3: Some{Blk{32, 20}}
    case 2: Some{Blk{32, 18}}
    case _: None{}

def blk.ofn(sz: U32) -> Maybe<&1, Blk>:
  Some{Blk{1, sz}}

def blk.mof(q: Maybe<&1, Blk>) -> Maybe<&1, Blk>:
  match q:
    case Some{+b}: Some{b}
    case None{}: None{}

def blk.of(m: Maybe<&1, U32>, t: U32) -> Maybe<&1, Blk>:
  match m:
    case Some{sz}: blk.ofn(sz)
    case None{}: blk.mof(blk.quant(t))

def blk.ofb(m: Maybe<&1, Blk>, t: U32) -> U32:
  match m:
    case Some{_}: nobad()
    case None{}: t

# ---------------------------------------------------------------------------
# the `kv` table (:211-214), one pair per step
# ---------------------------------------------------------------------------
def kv.put(ok: Bool, x: KV, acc: List<&2, KV>) -> List<&2, KV>:
  match ok:
    case True{}: x <> acc
    case False{}: acc

def kv_loop(n: Nat, c: Cur, acc: List<&2, KV>, bad: U32) -> KOut:
  match n:
    case 0n: KOut{List.reverse(&2, KV, acc), c, bad}
    case 1n+p:
      +s = cr.str(c)
      +w = by.t4(Cur.bs(CS.cur(s)))
      +o = rd.val(Wd.v(w), cr.next(CS.cur(s), 4, Wd.rs(w)))
      k = CS.v(s)
      v = VOut.v(o)
      kv_loop(p, VOut.cur(o), kv.put(U32.is_eq(VOut.bad(o), nobad()), KV{k, v}, acc),
        blk.bad(VOut.bad(o), bad))

# ---------------------------------------------------------------------------
# the tensor_info table (:223), one entry per step. `shape` is REVERSED here
# (:230 `tuple(reversed(dims))`) because `ti.dims` prepends, so `TIE.shape` is
# the tuple CPython hands to `state_dict` and needs no second reversal.
# ---------------------------------------------------------------------------
def ti.dims(k: Nat, +c: Cur, acc: List<&2, H.I64>) -> DI:
  match k:
    case 0n: DI{c, acc}
    case 1n+p:
      +w = by.t8(Cur.bs(c))
      ti.dims(p, cr.next(c, 8, W8.rs(w)), W8.v(w) <> acc)

def ti.put2(ok: Bool, x: TIE, acc: List<&2, TIE>) -> List<&2, TIE>:
  match ok:
    case True{}: x <> acc
    case False{}: acc

def ti_loop(n: Nat, c: Cur, acc: List<&2, TIE>, bad: U32) -> TOut:
  match n:
    case 0n: TOut{List.reverse(&2, TIE, acc), c, bad}
    case 1n+p:
      +s = cr.str(c)
      +d = by.t4(Cur.bs(CS.cur(s)))
      +m = ti.dims(U32.to_nat(Wd.v(d)), cr.next(CS.cur(s), 4, Wd.rs(d)), Nil{})
      +t = by.t4(Cur.bs(DI.cur(m)))
      +c4 = cr.next(DI.cur(m), 4, Wd.rs(t))
      +f = by.t8(Cur.bs(c4))
      +z = blk.ofb(blk.of(blk.native(Wd.v(t)), Wd.v(t)), Wd.v(t))
      nm = CS.v(s)
      sh = DI.dims(m)
      ty = Wd.v(t)
      of = W8.v(f)
      ti_loop(p, cr.next(c4, 8, W8.rs(f)),
        ti.put2(U32.is_eq(z, nobad()), TIE{nm, sh, ty, of}, acc),
        blk.bad(z, bad))

# ---------------------------------------------------------------------------
# `kv.get("general.alignment", 32)` (:224) and the second pass that turns an
# offset into `(start, nbytes)` (:229-230).
# ---------------------------------------------------------------------------
def kv.align.gv(v: GVal, acc: U32) -> U32:
  match v:
    case GVInt{x}: x
    case _: acc

def kv.align.one(k: String, v: GVal, +acc: U32) -> U32:
  Bool.pick(U32, String.eq(k, "general.alignment"), kv.align.gv(v, acc), acc)

def kv.align.go(xs: List<&2, KV>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case KV{k, v} <> t: kv.align.go(t, kv.align.one(k, v, acc))

def kv.align(kvs: List<&2, KV>) -> U32:
  kv.align.go(kvs, 32)

# `prod(dims)` (:229) over 64-bit dims. `H.prod_u32` is the same fold over
# `U32`, and `List.map` cannot reach it: its `xs` is `List<&1, A>`, and a shape
# arrive as `List<&2, H.I64>`. A dimension past 2^32 is not a tensor.
def ti.prod(shape: List<&2, H.I64>) -> U32:
  match shape:
    case Nil{}: 1
    case h <> t: U32.mul(H.lo32(h), ti.prod(t))

def ti.sz1(b: Maybe<&1, Blk>, +e: TIE, ds: U32) -> Maybe<&1, TI>:
  match b:
    case None{}: None{}
    case Some{+k}:
      Some{TI{TIE.nm(e), TIE.shape(e), TIE.typ(e), TIE.off(e),
              H.i64_add(H.i64_of_i32(ds), TIE.off(e)),
              U32.mul(U32.div(ti.prod(TIE.shape(e)), Blk.el(k)), Blk.by(k))}}

def ti.sz0(+e: TIE, ds: U32) -> Maybe<&1, TI>:
  ti.sz1(blk.of(blk.native(TIE.typ(e)), TIE.typ(e)), e, ds)

def ti.put(m: Maybe<&1, TI>, acc: List<&2, TI>) -> List<&2, TI>:
  match m:
    case None{}: acc
    case Some{x}: x <> acc

def ti.sz(es: List<&2, TIE>, +ds: U32, acc: List<&2, TI>) -> List<&2, TI>:
  match es:
    case Nil{}: List.reverse(&2, TI, acc)
    case e <> t: ti.sz(t, ds, ti.put(ti.sz0(e, ds), acc))

# ---------------------------------------------------------------------------
# `gguf_parse` (:198-231), one step per def. `n_tensors` is read BEFORE `n_kv`
# (:208) and that order is the one `tell()` observes.
# ---------------------------------------------------------------------------
def gguf.fail(c: Cur, bad: Bad) -> Parsed:
  match c:
    case Cur{_, at}: Parsed{Nil{}, Nil{}, at, Some{bad}}

def gguf.finb(ok: Bool, kvs: List<&2, KV>, ties: List<&2, TIE>, +ds: U32, tbad: U32) -> Parsed:
  match ok:
    case True{}: Parsed{kvs, ti.sz(ties, ds, Nil{}), ds, None{}}
    case False{}: Parsed{kvs, Nil{}, ds, Some{BadBlk{tbad}}}

def gguf.fin(+kvs: List<&2, KV>, ties: List<&2, TIE>, c: Cur, +tbad: U32) -> Parsed:
  ds = H.round_up_i32(Cur.at(c), kv.align(kvs))
  gguf.finb(U32.is_eq(tbad, nobad()), kvs, ties, ds, tbad)

def gguf.tbody(kvs: List<&2, KV>, c: Cur, n: Nat) -> Parsed:
  +t = ti_loop(n, c, Nil{}, nobad())
  gguf.fin(kvs, TOut.ts(t), TOut.cur(t), TOut.bad(t))

def gguf.tsb(dead: Bool, kvs: List<&2, KV>, kbad: U32, c: Cur, n: Nat) -> Parsed:
  match dead:
    case True{}: Parsed{kvs, Nil{}, Cur.at(c), Some{BadMeta{kbad}}}
    case False{}: gguf.tbody(kvs, c, n)

def gguf.body(+c: Cur) -> Parsed:
  +t = by.t8(Cur.bs(c))
  +c1 = cr.next(c, 8, W8.rs(t))
  +k = by.t8(Cur.bs(c1))
  c2 = cr.next(c1, 8, W8.rs(k))
  +q = kv_loop(U32.to_nat(H.lo32(W8.v(k))), c2, Nil{}, nobad())
  gguf.tsb(Bool.not(U32.is_eq(KOut.bad(q), nobad())), KOut.kv(q), KOut.bad(q), KOut.cur(q),
    U32.to_nat(H.lo32(W8.v(t))))

def gguf.ver(ok: Bool, ver: U32, c: Cur) -> Parsed:
  match ok:
    case False{}: gguf.fail(c, BadVersion{ver})
    case True{}: gguf.body(c)

def gguf.hdr(okm: Bool, +ver: U32, c: Cur) -> Parsed:
  match okm:
    case False{}: gguf.fail(c, BadMagic{})
    case True{}: gguf.ver(Bool.or(U32.is_eq(ver, 2), U32.is_eq(ver, 3)), ver, c)

def gguf.mv(+c: Cur) -> MV:
  +m = by.t4(Cur.bs(c))
  +c1 = cr.next(c, 4, Wd.rs(m))
  +v = by.t4(Cur.bs(c1))
  MV{Wd.v(m), Wd.v(v), cr.next(c1, 4, Wd.rs(v))}

def gguf.mvg(+m: MV) -> Parsed:
  gguf.hdr(U32.is_eq(MV.mg(m), magic()), MV.ver(m), MV.cur(m))

def gguf.parse(c: Cur) -> Parsed:
  gguf.mvg(gguf.mv(c))

def gguf.bytes(bs: List<&2, U32>) -> Parsed:
  gguf.parse(Cur{bs, 0})
