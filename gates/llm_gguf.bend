# llm_gguf.bend -- the PORT lane of the GGUF reader gate.
#
#   .venv/bin/python gates/llm_gguf-gate.py
#
# 143 rows over three `.gguf` files built by `gates/llm_gguf-fixture.py`. The row set is
# every kv pair in FILE ORDER, every tensor's `(shape, typ, offset, start, nbytes)`, the
# four error spellings, and ALL 46 ggml type codes and all 16 metadata type codes.
#
# THE TABLE ROWS ARE NOT DECORATION: `rd.fmt`, `blk.native` and `blk.quant` are `U32`
# arm ladders, and bend's numeric arms are PREFIX matches, so an arm written in the
# wrong order answers a neighbouring code. Rows for 0..45 (and 0..15) are what make a
# mis-ordered ladder go red instead of answering plausibly.
#
# PRINTING, and both lanes say the same thing for each kind:
#   * an int of 32 bits or less prints as SIGNED DECIMAL (`-7`), which is CPython's
#     `int` and the port's `s32`.
#   * a 64-bit value prints as `hi:lo`, because 2^63 has no `U32` image and the port's
#     `H.i64_text` already chose that spelling (helpers.bend).
#   * an f32 prints as its BIT PATTERN, and an f64 as its eight bytes, because neither
#     lane can print a float exactly and the bits ARE the value.
#   * a `bytes` metadata value (type 0) prints as its single byte's value.

import Base
import ./../tinybendygrad/llm/gguf.bend as G
import ./../tinybendygrad/helpers.bend as H

def good() -> String: "gates/llm_gguf-fixture.gguf"
def badmeta() -> String: "gates/llm_gguf-badmeta.gguf"
def badtype() -> String: "gates/llm_gguf-badtype.gguf"

# ---------------------------------------------------------------------------
# the three files, as bytes. `File.read_bytes` is why this lane needs no Tensor:
# a `TensorIO` reader is the wall `nn/state.bend` names, and a PATH reader is not.
# ---------------------------------------------------------------------------
def rd.done(m: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, r) = m
  do IO<List<&2, U32>>:
    b : List<&2, U32> <- IO.pass(List<&2, U32>, r)
    u : Unit <- File.close(f)
    IO.pure(List<&2, U32>, b)

def rd.file(path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    m : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 1048576)
    rd.done(m)

# ---------------------------------------------------------------------------
# value and row printers
# ---------------------------------------------------------------------------
def s32(+v: U32) -> String:
  Bool.pick(String, H.i32_is_neg(v), String.append("-", U32.show(U32.sub(0, v))), U32.show(v))

def bsum(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case h <> t: bsum(t, U32.add(acc, h))

def pad2(+c: U32) -> String:
  Bool.pick(String, U32.is_lt(c, 10), String.append("0", U32.show(c)), U32.show(c))

# A value prints through a TOKEN WORKLIST and not through a recursive printer,
# because a printer is `show` calling `items` calling `show`: mutual recursion, which
# bend refuses. `Tok` is the worklist's alphabet and one def expands it, so the depth
# of an `array` costs nothing and there is no second printer to keep in step.
type Tok is Data:
  TLit{s: String}
  TVal{g: G.GVal}

def gv.sep(first: Bool, t: List<&2, Tok>) -> List<&2, Tok>:
  match first:
    case True{}: t
    case False{}: TLit{","} <> t

def gv.exp2(vs: List<&2, G.GVal>, first: Bool, t: List<&2, Tok>) -> List<&2, Tok>:
  match vs:
    case Nil{}: TLit{"]"} <> t
    case h <> rest: gv.sep(first, TVal{h} <> gv.exp2(rest, False{}, t))

def gv.exp(g: G.GVal, t: List<&2, Tok>) -> List<&2, Tok>:
  match g:
    case G.GVArr{vs}: TLit{"["} <> gv.exp2(vs, True{}, t)
    case G.GVInt{v}: TLit{s32(v)} <> t
    case G.GVI64{v}: TLit{H.i64_text(v)} <> t
    case G.GVF32{v}: TLit{U32.show(F32.bits(v))} <> t
    case G.GVF64{v}: TLit{H.i64_text(v)} <> t
    case G.GVBool{v}: TLit{Bool.pick(String, v, "True", "False")} <> t
    case G.GVStr{v}: TLit{v} <> t

def gv.walk(k: Nat, ws: List<&2, Tok>, acc: List<&2, String>) -> List<&2, String>:
  match k ws:
    case 0n _: List.reverse(&2, String, acc)
    case 1n+p Nil{}: List.reverse(&2, String, acc)
    case 1n+p TLit{s} <> t: gv.walk(p, t, s <> acc)
    case 1n+p TVal{g} <> t: gv.walk(p, gv.exp(g, t), acc)

# 4096 tokens is far past any metadata value in a GGUF header; past it the port
# answers a SHORT string rather than a wrong one.
def gv.show(g: G.GVal) -> String:
  String.concat(gv.walk(4096n, gv.exp(g, Nil{}), Nil{}))

def kv.rows(xs: List<&2, G.KV>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case +h <> t: kv.rows(t, String.concat(["kv.", G.KV.k(h), "=", gv.show(G.KV.v(h))]) <> acc)

def kv.keys(xs: List<&2, G.KV>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: kv.keys(t, G.KV.k(h) <> acc)

def dims.items(xs: List<&2, H.I64>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: dims.items(t, H.i64_text(h) <> acc)

def dims.show(xs: List<&2, H.I64>) -> String:
  String.join(dims.items(xs, Nil{}), ",")

def ti.rows(xs: List<&2, G.TI>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case +h <> t: ti.rows(t, String.concat(["t.", G.TI.nm(h), "=", dims.show(G.TI.shape(h)), "|",
      U32.show(G.TI.typ(h)), "|", H.i64_text(G.TI.off(h)), "|", H.i64_text(G.TI.start(h)), "|",
      U32.show(G.TI.nbytes(h))]) <> acc)

def ti.names(xs: List<&2, G.TI>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: ti.names(t, G.TI.nm(h) <> acc)

# ---------------------------------------------------------------------------
# the four error spellings `gguf_parse` has, as the strings CPython prints
# ---------------------------------------------------------------------------
def bad.one(b: G.Bad) -> String:
  match b:
    case G.BadMagic{}: "Invalid GGUF format!"
    case G.BadVersion{v}: "Invalid GGUF format!"
    case G.BadMeta{typ}: "none"
    case G.BadBlk{typ}: String.concat(["GGML type '", U32.show(typ), "' is not supported!"])

def bad.show(m: Maybe<&2, G.Bad>) -> String:
  match m:
    case None{}: "none"
    case Some{+b}: bad.one(b)

def mut.magic(bs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [0, 0, 0, 0], List.drop(&2, U32, bs, 4n))

def mut.ver(+bs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32,
    List.append(&2, U32, List.take(&2, U32, bs, 4n), [7, 0, 0, 0]),
    List.drop(&2, U32, bs, 8n))

def err.rows(+a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>) -> List<&2, String>:
  [String.concat(["err_good=", bad.show(G.Parsed.bad(G.gguf.bytes(a)))]),
   String.concat(["err_magic=", bad.show(G.Parsed.bad(G.gguf.bytes(mut.magic(a))))]),
   String.concat(["err_ver=", bad.show(G.Parsed.bad(G.gguf.bytes(mut.ver(a))))]),
   String.concat(["err_blk=", bad.show(G.Parsed.bad(G.gguf.bytes(c)))]),
   String.concat(["err_meta=", bad.show(G.Parsed.bad(G.gguf.bytes(b)))])]

# ---------------------------------------------------------------------------
# the type tables. `up` is 0..n-1 because a `U32` literal ladder is only as good as
# the numbers a row reads it at, and these rows read EVERY number in the key space.
# ---------------------------------------------------------------------------
def up(k: Nat, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p: up(p, U32.add(i, 1), i <> acc)

def fmt.name(f: G.Fmt) -> String:
  match f:
    case G.FChr{}: "c"
    case G.FI8{}: "b"
    case G.FU16{}: "H"
    case G.FI16{}: "h"
    case G.FU32{}: "I"
    case G.FI32{}: "i"
    case G.FF32{}: "f"
    case G.FBool{}: "?"
    case G.FStr{}: "str"
    case G.FArr{}: "arr"
    case G.FU64{}: "Q"
    case G.FI64{}: "q"
    case G.FF64{}: "d"

def fmt.of(m: Maybe<&1, G.Fmt>) -> String:
  match m:
    case None{}: "-"
    case Some{+f}: fmt.name(f)

def fmt.row(+c: U32) -> String:
  String.concat(["fmt_", pad2(c), "=", fmt.of(G.rd.fmt(c))])

def fmt.rows(cs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: fmt.rows(t, fmt.row(h) <> acc)

def nat.of(m: Maybe<&1, U32>) -> String:
  match m:
    case None{}: "-"
    case Some{sz}: U32.show(sz)

def nat.row(+c: U32) -> String:
  String.concat(["nat_", pad2(c), "=", nat.of(G.blk.native(c))])

def nat.rows(cs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: nat.rows(t, nat.row(h) <> acc)

def qnt.of(m: Maybe<&1, G.Blk>) -> String:
  match m:
    case None{}: "-"
    case Some{+b}: String.concat([U32.show(G.Blk.el(b)), "x", U32.show(G.Blk.by(b))])

def qnt.row(+c: U32) -> String:
  String.concat(["qnt_", pad2(c), "=", qnt.of(G.blk.quant(c))])

def qnt.rows(cs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: qnt.rows(t, qnt.row(h) <> acc)

# ---------------------------------------------------------------------------
def rows.all(+a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>) -> List<&2, String>:
  +p = G.gguf.bytes(a)
  +kvs = G.Parsed.kv(p)
  +ts = G.Parsed.ts(p)
  List.concat(&2, String, [
    [String.concat(["fx_len=", U32.show(U32.from_nat(List.length(&2, U32, a)))]),
     String.concat(["fx_sum=", U32.show(bsum(a, 0))]),
     String.concat(["n_kv=", U32.show(U32.from_nat(List.length(&2, G.KV, kvs)))]),
     String.concat(["n_ts=", U32.show(U32.from_nat(List.length(&2, G.TI, ts)))]),
     String.concat(["ds=", U32.show(G.Parsed.ds(p))]),
     String.concat(["kvseq=", String.join(kv.keys(kvs, Nil{}), ",")])],
    kv.rows(kvs, Nil{}),
    [String.concat(["align=", U32.show(G.kv.align(kvs))]),
     String.concat(["align_none=", U32.show(G.kv.align(Nil{}))]),
     String.concat(["align_one=", U32.show(G.kv.align([G.KV{"general.alignment", G.GVInt{16}}]))]),
     String.concat(["tseq=", String.join(ti.names(ts, Nil{}), ",")])],
    ti.rows(ts, Nil{}),
    err.rows(a, b, c),
    fmt.rows(up(16n, 0, Nil{}), Nil{}),
    nat.rows(up(46n, 0, Nil{}), Nil{}),
    qnt.rows(up(46n, 0, Nil{}), Nil{})])

def main() -> IO(Unit):
  do IO<Unit>:
    a : List<&2, U32> <- rd.file(good())
    b : List<&2, U32> <- rd.file(badmeta())
    c : List<&2, U32> <- rd.file(badtype())
    IO.print(String.join(rows.all(a, b, c), "\n"))
