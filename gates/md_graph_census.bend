# md_graph_census.bend -- A GRAPH CENSUS over the GRAPH-BUILDING methods of
# `tinybendygrad/mixin/dtype.bend`: each driven once, its toposort OP SEQUENCE printed.
#
#   .venv/bin/python gates/md_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED, AND THE RULE IS THE SIBLINGS'. A port def is a ROW iff
# CPython's `tinygrad/mixin/dtype.py` defines the method it mirrors. The port spells a
# method with a namespace prefix (`cast` -> `cast_at`, `float` -> `cast_float`), so the
# mapping is by the port's own spelling and it is stated in the gate, not listed here.
# CPython's `DTypeMixin` has SIXTEEN names; THREE are abstract declarations Python raises
# `NotImplementedError` from (`dtype`, `_uop`, `_wrap_uop`) and are NOT ports, leaving
# THIRTEEN methods. THREE of those are READERS -- `commit_dtype`, `element_size`,
# `is_floating_point` return a dtype / an int / a bool and build NO graph, so a graph
# census cannot print them and they FALL OUT. TEN build a graph and are the rows:
#
#     cast -> cast_at          bitcast -> bitcast_at
#     float -> cast_float      half  -> cast_half      int  -> cast_int
#     bool  -> cast_bool       bfloat16 -> cast_bfloat16
#     double -> cast_double    long  -> cast_long      short -> cast_short
#
# THE PRINTER IS THE PORT'S OWN `O.Rng.sig` (`uop/ops.bend:5897`) PLUS THE ROOT ARG.
# `Rng.sig` prints the toposort length, the root op and its src COUNT and the SRC OP
# SEQUENCE -- and it does NOT print an arg. A CAST's whole point is its arg (`ADt{dt}`),
# so `Rng.sig` ALONE cannot tell `cast_short` (i16) from `cast_int` (i32): both are
# `2 Ops.CAST/1 Ops.CONST`. This census therefore appends ` arg=<dtype name>` -- the port
# reads `Arena.arg` and prints `S.Dt.nm`, the oracle reads `uop.arg.name`. The two NAME
# tables are the same table: CPython's `dtypes.f16.name` is `"f16"` and `S.half()`'s `nm`
# is `"f16"`, measured. A root with no `ADt` arg prints `-` on both lanes.
#
# THE FIXTURE IS ONE ARENA HOLDING EVERY SOURCE DTYPE, handed out -- the safe shape the
# sibling `ew_graph_census` records. THIS LAYER HAS NO ARENA MERGE AT ALL: `cast_at.of`'s
# mint arm is `O.UOp.new(md_ar(fx), ...)`, an APPEND to the arena the fold was built on,
# never `O.Arena.merge` and never the `ew_newer` length rule. So there is no merge trap
# here; the sources differ only because a cast is only VISIBLE when the source dtype
# DIFFERS from the target (a same-dtype cast is the identity arm, one node).
#
# NOTHING IS EXECUTED. Every row is the signature of the LAZY graph, so no device is
# needed and the CPython lane is a `toposort()`.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/mixin/dtype.bend as D

# THE WORLD: five nodes in ONE arena, every dtype class the cast layer distinguishes.
#   c0 CONST(3)     -> weakint    (CInt folds to weakint, fold.bend:2173)
#   c1 CONST(1.0)   -> weakfloat  (CFloat folds to weakfloat, fold.bend:2174)
#   c2 CONST(True)  -> bool       (CBool)
#   c3 CAST(c0->i32) -> concrete int32 -- the only CONCRETE source; built by a CAST
#                      because `UOp.const` of an int is always weakint.
#   c4 CAST(c1->f16) -> concrete f16, the source the `cast_half` identity row needs.
# A CAST's fold dtype is its arg (`g_fix`'s own `f_wf` reads half, and `commit_wf_concrete`
# pins it), so `md_dt` on c3/c4 answers i32/f16 rather than the src's dtype.
type Mw is Data:
  Mw{fx: F.Folded, wi: U32, wf: U32, bl: U32, i32: U32, half: U32}

def Mw.fx(x: Mw) -> F.Folded:
  match x:
    case Mw{fx, wi, wf, bl, i32, half}: fx

def Mw.wi(x: Mw) -> U32:
  match x:
    case Mw{fx, wi, wf, bl, i32, half}: wi

def Mw.wf(x: Mw) -> U32:
  match x:
    case Mw{fx, wi, wf, bl, i32, half}: wf

def Mw.bl(x: Mw) -> U32:
  match x:
    case Mw{fx, wi, wf, bl, i32, half}: bl

def Mw.i32(x: Mw) -> U32:
  match x:
    case Mw{fx, wi, wf, bl, i32, half}: i32

def Mw.half(x: Mw) -> U32:
  match x:
    case Mw{fx, wi, wf, bl, i32, half}: half

def world() -> Mw:
  +c0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CFloat{1.0})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CBool{True{}})
  +c3 = O.UOp.new(O.Found.ar(c2), O.OpsCAST{}, [O.Found.i(c0)], O.ADt{S.int32()}, O.TNone{})
  +c4 = O.UOp.new(O.Found.ar(c3), O.OpsCAST{}, [O.Found.i(c1)], O.ADt{S.half()}, O.TNone{})
  +ar = O.Found.ar(c4)
  Mw{F.folded(ar), O.Found.i(c0), O.Found.i(c1), O.Found.i(c2), O.Found.i(c3), O.Found.i(c4)}

# THE ARG, AS A DTYPE NAME. `Arena.arg` is total, so a non-`ADt` arg prints `-`. The
# match takes the ARG as a parameter rather than scrutinising `O.Arena.arg(...)` -- a
# `match` cannot scrutinise a computed value (Bend refuses it by name).
def md_arg_of(arg: O.Arg) -> String:
  match arg:
    case O.ADt{dt}: F.dt_nm(dt)
    case _: "-"

def md_arg(ar: O.Arena, self: U32) -> String:
  md_arg_of(O.Arena.arg(ar, self))

def md_line(nm: String, +ar: O.Arena, +self: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", O.Rng.sig(ar, self), " arg=", md_arg(ar, self)]))

def md_found(nm: String, +f: O.Found) -> IO(Unit):
  md_line(nm, O.Found.ar(f), O.Found.i(f))

# `bitcast_at` answers `Maybe<Found>`: the `None` arm is the refusal, and it prints `None`
# (the CPython lane prints the exception's name -- pinned, see the gate).
def md_maybe(nm: String, m: Maybe<&2, O.Found>) -> IO(Unit):
  match m:
    case Some{f}: md_found(nm, f)
    case None{}: IO.print(String.concat([nm, "=None"]))

# --- `cast` (dtype.py:19 -> cast_at) -------------------------------------
def r_cast_weak_to_f32() -> IO(Unit):
  +w = world()
  md_found("cast_weak_to_f32", D.cast_at(Mw.fx(w), Mw.wi(w), S.single()))

def r_cast_same_weakint() -> IO(Unit):
  +w = world()
  md_found("cast_same_weakint", D.cast_at(Mw.fx(w), Mw.wi(w), S.weakint()))

def r_cast_weakfloat_to_i32() -> IO(Unit):
  +w = world()
  md_found("cast_weakfloat_to_i32", D.cast_at(Mw.fx(w), Mw.wf(w), S.int32()))

def r_cast_wf_same() -> IO(Unit):
  +w = world()
  md_found("cast_wf_same", D.cast_at(Mw.fx(w), Mw.wf(w), S.weakfloat()))

def r_cast_bool_to_i32() -> IO(Unit):
  +w = world()
  md_found("cast_bool_to_i32", D.cast_at(Mw.fx(w), Mw.bl(w), S.int32()))

def r_cast_concrete_to_f32() -> IO(Unit):
  +w = world()
  md_found("cast_concrete_to_f32", D.cast_at(Mw.fx(w), Mw.i32(w), S.single()))

def r_cast_concrete_same() -> IO(Unit):
  +w = world()
  md_found("cast_concrete_same", D.cast_at(Mw.fx(w), Mw.i32(w), S.int32()))

def r_cast_weak_to_weakfloat() -> IO(Unit):
  +w = world()
  md_found("cast_weak_to_weakfloat", D.cast_at(Mw.fx(w), Mw.wi(w), S.weakfloat()))

# --- `bitcast` (dtype.py:38 -> bitcast_at) -------------------------------
def r_bitcast_concrete_to_u32() -> IO(Unit):
  +w = world()
  md_maybe("bitcast_concrete_to_u32", D.bitcast_at(Mw.fx(w), Mw.i32(w), S.uint32()))

def r_bitcast_concrete_same() -> IO(Unit):
  +w = world()
  md_maybe("bitcast_concrete_same", D.bitcast_at(Mw.fx(w), Mw.i32(w), S.int32()))

def r_bitcast_weak_src() -> IO(Unit):
  +w = world()
  md_maybe("bitcast_weak_src", D.bitcast_at(Mw.fx(w), Mw.wi(w), S.int32()))

def r_bitcast_weak_dst() -> IO(Unit):
  +w = world()
  md_maybe("bitcast_weak_dst", D.bitcast_at(Mw.fx(w), Mw.i32(w), S.weakfloat()))

# --- the eight named casts (dtype.py:79-142) -----------------------------
def r_cast_float() -> IO(Unit):
  +w = world()
  md_found("cast_float", D.cast_float(Mw.fx(w), Mw.wi(w)))

def r_cast_half() -> IO(Unit):
  +w = world()
  md_found("cast_half", D.cast_half(Mw.fx(w), Mw.wi(w)))

def r_cast_int() -> IO(Unit):
  +w = world()
  md_found("cast_int", D.cast_int(Mw.fx(w), Mw.wi(w)))

def r_cast_bool() -> IO(Unit):
  +w = world()
  md_found("cast_bool", D.cast_bool(Mw.fx(w), Mw.wi(w)))

def r_cast_bfloat16() -> IO(Unit):
  +w = world()
  md_found("cast_bfloat16", D.cast_bfloat16(Mw.fx(w), Mw.wi(w)))

def r_cast_double() -> IO(Unit):
  +w = world()
  md_found("cast_double", D.cast_double(Mw.fx(w), Mw.wi(w)))

def r_cast_long() -> IO(Unit):
  +w = world()
  md_found("cast_long", D.cast_long(Mw.fx(w), Mw.wi(w)))

def r_cast_short() -> IO(Unit):
  +w = world()
  md_found("cast_short", D.cast_short(Mw.fx(w), Mw.wi(w)))

# Two named casts AT their own dtype: the identity arm travels through all eight, and
# these are the rows that separate "the target is right" from "the target is ignored".
def r_cast_half_same() -> IO(Unit):
  +w = world()
  md_found("cast_half_same", D.cast_half(Mw.fx(w), Mw.half(w)))

def r_cast_bool_same() -> IO(Unit):
  +w = world()
  md_found("cast_bool_same", D.cast_bool(Mw.fx(w), Mw.bl(w)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- r_cast_weak_to_f32()
    b : Unit <- r_cast_same_weakint()
    c : Unit <- r_cast_weakfloat_to_i32()
    d : Unit <- r_cast_wf_same()
    e : Unit <- r_cast_bool_to_i32()
    f : Unit <- r_cast_concrete_to_f32()
    g : Unit <- r_cast_concrete_same()
    h : Unit <- r_cast_weak_to_weakfloat()
    i : Unit <- r_bitcast_concrete_to_u32()
    j : Unit <- r_bitcast_concrete_same()
    k : Unit <- r_bitcast_weak_src()
    l : Unit <- r_bitcast_weak_dst()
    m : Unit <- r_cast_float()
    n : Unit <- r_cast_half()
    o : Unit <- r_cast_int()
    p : Unit <- r_cast_bool()
    q : Unit <- r_cast_bfloat16()
    r : Unit <- r_cast_double()
    s : Unit <- r_cast_long()
    t : Unit <- r_cast_short()
    u : Unit <- r_cast_half_same()
    v : Unit <- r_cast_bool_same()
    return Unit{}
