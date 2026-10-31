# llm_ggml.bend -- the PORT lane of the `ggml_data_to_tensor` DECODE gate.
#
#   .venv/bin/python gates/llm_ggml-gate.py
#
# 57 rows, and the interesting part is what feeds them: the fixture is a REAL `.gguf`, so
# this lane finds each block the way `gguf_load` would -- the reader gives the offset and
# the length, the slice gives the bytes -- and THEN decodes them with
# `tinybendygrad/llm/ggml.bend`, which constructs no `Tensor` at all.
#
# `kvalues_iq4nl` AND THE GRID WORDS ARE LITERALS HERE. That is the whole design: the port
# takes them as ARGUMENTS, so the `ggml_common` constants live at this call site -- and not
# in the port -- until a caller that can hold them exists. `lut` is transcribed from
# ggml-common.h and `iqs` is not: `M.iq.signs()` COMPUTES its 128 bytes, because CPython
# computes them too (`gguf.py:17`).
#
# EVERY VALUE PRINTS AS AN `f32` BIT PATTERN, on both lanes, because neither can print a
# float exactly and the bits ARE the value.

import Base
import ./../tinybendygrad/llm/gguf.bend as G
import ./../tinybendygrad/llm/ggml.bend as M
import ./../tinybendygrad/helpers.bend as H

def fx() -> String: "gates/llm_ggml-fixture.gguf"

# `kvalues_iq4nl` (ggml-common.h) as 32-bit two's complement, because the port has no i8.
def lut() -> List<&2, U32>:
  [4294967169, 4294967192, 4294967213, 4294967231, 4294967247, 4294967261, 4294967274,
   4294967286, 1, 13, 25, 38, 53, 69, 89, 113]

# FOUR entries of eight bytes, two 32-bit words each -- `gguf.py:13`'s split, and the
# reason a `U32` cannot hold one grid entry.
def gridw() -> List<&2, U32>:
  [67305985, 134678021, 202050057, 269422093, 336794129, 404166165, 471538201, 538910237]

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

# the `Tensor` view `gguf.py:230` takes, spelled as the slice it is
def bsl(+bs: List<&2, U32>, at: U32, n: U32) -> List<&2, U32>:
  List.take(&2, U32, List.drop(&2, U32, bs, U32.to_nat(at)), U32.to_nat(n))

def tprod(xs: List<&2, H.I64>) -> U32:
  match xs:
    case Nil{}: 1
    case h <> t: U32.mul(H.lo32(h), tprod(t))

def vals.show(xs: List<&2, F32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case +h <> t: vals.show(t, U32.show(F32.bits(h)) <> acc)

def row.of(nm: String, m: Maybe<&1, List<&2, F32>>) -> String:
  match m:
    case None{}: String.concat(["v_", nm, "=none"])
    case Some{vs}: String.concat(["v_", nm, "=", String.join(vals.show(vs, Nil{}), ",")])

def pad2(+c: U32) -> String:
  Bool.pick(String, U32.is_lt(c, 10), String.append("0", U32.show(c)), U32.show(c))

def tir(ts: List<&2, G.TI>, +bs: List<&2, U32>, +lut: List<&2, U32>,
         acc: List<&2, String>) -> List<&2, String>:
  match ts:
    case Nil{}: List.reverse(&2, String, acc)
    case +h <> t:
      tir(t, bs, lut,
        row.of(G.TI.nm(h),
          M.ggml.dec(G.TI.typ(h), tprod(G.TI.shape(h)),
            bsl(bs, H.lo32(G.TI.start(h)), G.TI.nbytes(h)), lut)) <> acc)

def bytes.show(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: bytes.show(t, U32.show(h) <> acc)

def bshow(nm: String, xs: List<&2, U32>) -> String:
  String.concat([nm, "=", String.join(bytes.show(xs, Nil{}), ",")])

# the port's SUPPORTED SET, stated here so the gate can see a `ggml_type` that silently
# stopped being decoded. The oracle states the same set independently.
def ty.one(t: M.Typ) -> String:
  match t:
    case M.TF32{}: "f32"
    case M.TF16{}: "f16"
    case M.TBF16{}: "bf16"
    case M.TQ4_0{}: "Q4_0"
    case M.TQ8_0{}: "Q8_0"
    case M.TQ4K{}: "Q4_K"
    case M.TIQ4NL{}: "IQ4_NL"

def ty.name(m: Maybe<&1, M.Typ>) -> String:
  match m:
    case None{}: "-"
    case Some{+t}: ty.one(t)

def ty.row(+c: U32) -> String:
  String.concat(["ty_", pad2(c), "=", ty.name(M.typ.of(c))])

def up(k: Nat, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p: up(p, U32.add(i, 1), i <> acc)

def ty.rows(cs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: ty.rows(t, ty.row(h) <> acc)

# the refusal, in `gguf.py:185`'s own words, or `none` when the type IS decoded
def err.of(typ: U32, m: Maybe<&1, List<&2, F32>>) -> String:
  match m:
    case None{}: String.concat(["GGML type '", U32.show(typ), "' is not supported!"])
    case Some{_}: "none"

def rows.all(+a: List<&2, U32>) -> List<&2, String>:
  +p = G.gguf.bytes(a)
  List.concat(&2, String, [
    tir(G.Parsed.ts(p), a, lut(), Nil{}),
    [bshow("iqs", M.iq.signs()),
     bshow("grid", M.iq.grid(4, gridw())),
     bshow("lut", lut()),
     String.concat(["err=", err.of(99, M.ggml.dec(99, 1, bsl(a, 0, 2), lut()))])],
    ty.rows(up(46n, 0, Nil{}), Nil{})])

def main() -> IO(Unit):
  do IO<Unit>:
    a : List<&2, U32> <- rd.file(fx())
    IO.print(String.join(rows.all(a), "\n"))
