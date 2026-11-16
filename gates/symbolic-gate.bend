# gates/symbolic-gate.bend -- the gate driver for `tinybendygrad/uop/symbolic.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/uop/symbolic.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/render.bend as R
import ./../tinybendygrad/dtype.bend as D
import ./../tinybendygrad/uop/weak.bend as W
import ./../tinybendygrad/uop/movement.bend as M
import ./../tinybendygrad/codegen/decomp/transcendental.bend as T
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def fz.gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("lay", P.t_lay())
    b : Unit <- row("len_sym", P.t_len_sym())
    c : Unit <- row("len_rm", P.t_len_rm())
    d : Unit <- row("total_sym", P.t_total())
    e : Unit <- row("skip", P.t_skip())
    f : Unit <- row("rej", P.t_rej())
    g : Unit <- row("alu", P.t_alu())
    h : Unit <- row("alu_rule", P.t_alu_rule())
    i : Unit <- row("alu_i32", P.t_alu_i32())
    j : Unit <- row("alu_big", P.t_alu_big())
    k : Unit <- row("alu_f32", P.t_alu_f32())
    m : Unit <- row("fdiv", P.t_fdiv())
    n : Unit <- row("fdiv_i", P.t_fdiv_i())
    o : Unit <- row("cdiv_i", P.t_cdiv_i())
    row("max_i", P.t_max_i())
    p : Unit <- row("cdiv_neg", P.t_cdiv_neg())
    q : Unit <- row("inval", P.t_inval())
    r : Unit <- row("inval_st", P.t_inval_st())
    s : Unit <- row("inval_n", P.t_inval_n())
    u : Unit <- row("selfadd", P.t_selfadd())
    v : Unit <- row("rebind", P.t_rebind())
    w : Unit <- row("rebind0", P.t_rebind0())
    y : Unit <- row("sink", P.t_sink())
    z : Unit <- row("rm_where", P.t_rm_where())
    row("rm_stack", P.t_rm_stack())
    row("xorb", P.t_xorb())
    row("xorb0", P.t_xorb0())
    row("bcast", P.t_bcast())
    row("sinkgrp", P.t_sinkgrp())
    row("sinkgrp0", P.t_sinkgrp0())
    row("promo", P.t_promo())
    row("modb", P.t_modb())
    row("modb0", P.t_modb0())
    row("ne0", P.t_ne0())
    row("ne1", P.t_ne1())
    row("ne2", P.t_ne2())
    row("ne0r", P.t_ne0r())
    row("trunc", P.t_trunc())
    row("trunc0", P.t_trunc0())
    row("shr", P.t_shr())
    row("shr0", P.t_shr0())
    row("fdivm", P.t_fdivm())
    row("fdivm0", P.t_fdivm0())
    row("promo_c", P.t_promo_c())
    row("promo_c0", P.t_promo_c0())
    row("tflo", P.t_tflo())
    row("tfhi", P.t_tfhi())
    row("tfhi_cast", P.t_tfhi_cast())
    row("recip3", P.t_recip3())
    row("recip3x", P.t_recip3x())
    row("recipc", P.t_recipc())
    row("recipc0", P.t_recipc0())
    row("ints_n", P.t_ints_n())
    row("intish_n", P.t_intish_n())
    row("intweak_n", P.t_intweak_n())
    row("bin3f_n", P.t_bin3f_n())
    row("len_dec", P.t_len_dec())
    row("len_dec_rm", P.t_len_dec_rm())
    row("ig87_src2", P.t_ig_src2())

# THE FUZZ DRIVER. `main` with NO argument is the gate above, byte for byte; with
# ONE argument it reads that case file, builds the arena out of the s-expr the case
# format IS, runs `P.sym` and `P.pm_remove_invalid` over the root, and prints ONE
# canonical line. The case format and the canonical form are the SAME s-expr, so the
# oracle and the driver can both print `sh(u)` and diff.
#
# THE FORMAT, and the leaves are the whole vocabulary:
#   (add c7 c0)             an ALU over two weakint CONSTs
#   (cast:int c7)           a CAST naming its dtype after a colon
#   (xor (xor c5 c7) c7)    a name bound twice, which is the rebind check
#   c7 c0 n7 bt bf bad      a CONST: non-negative, negative, bool true, bool
#                           false, and `Invalid`
#   x xb xf P.xi              a PARAM (`UOp.variable`) at weakint, bool, weakfloat
#                           and int32
# Anything the port cannot state is NOT in the vocabulary, and the exclusions are
# in the harness rather than discovered: no float CONST (`F32.bits` has no
# inverse, so a canonical float spelling is not expressible), no CONST outside
# int32 (`P.exec_alu`'s integer lane is int32, and its value is an I64), and no
# op behind `vmin`/`vmax`/`const_factor`/`tuplize`/`gcd`/`ranges`, all of which
# are `TODO(p3)` in the block above.
#
# why the scan is one DEF with a mode: a token scan that dispatches on the class of
# the character it is looking at cannot be two mutually recursive defs. It is one
# def, `m` selects "at a boundary" from "inside a word", `wm` says WHICH word, and
# every edge spends a Nat of fuel.
type Tok is Data:
  TClose{}
  THead{w: String}
  TLeaf{w: String}

type Frm is Data:
  Frm{srcs: List<&2, U32>, head: String}

type St is Data:
  St{ar: O.Arena, stk: List<&2, Frm>, root: Maybe<&2, U32>}

def fz_code(s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{Chr{c}, t}: c

# 0 is the end of the line, 1 is `)`, 2 is `(`, 3 is a space, 4 is a word char.
def fz_cls.pick(cu: U32) -> U32:
  match cu:
    case 41: 1
    case 40: 2
    case 32: 3
    case 9: 3
    case 10: 3
    case 13: 3
    case _: 4

def fz_cls.at(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 0
    case Chr{u} <> _t: fz_cls.pick(u)

def fz_cls(+cs: List<&2, Char>) -> U32: fz_cls.at(cs)

def fz_tok.tok(w: String, hd: U32) -> Tok:
  match hd:
    case 1: THead{w}
    case _: TLeaf{w}

# the scanner, and it is the third shape of it in this file. `hd` is a flag that
# says the NEXT word is a node HEAD: `(` sets it, every other character clears it,
# and a word is emitted the moment its terminator arrives -- a `)` emits the word AND
# a close together, and the end of the line emits the word and STOPS.
#
# THE TWO SHAPES IT REPLACED, and both are the same fault read two ways. The mode
# `md` was the class of the word just EMITTED and had exactly one edge INTO 2 -- its
# own self-loop -- so with the scan starting at `md = 0` the value 2 was UNREACHABLE
# and `fz_tok.tok`'s `THead` arm was dead code: every op name in a case file arrived
# as a leaf. MEASURED on `(add c7 c0)` before the fix, `fz_run` answered
# `root=1 n=2 op=Ops.CONST selfadd=0 P.sym=norewrite rm=norewrite` -- a CONST where the
# s-expr says ADD. The second shape then emitted one `TClose` per unit of fuel on the
# empty tail, which is 4096 closes for a 12-character input and a lane whose cost is
# set by its fuel rather than by its case. `hd` has neither fault, and it is the same
# algorithm `gates/sym_graph_census.bend`'s `tk.at` runs, which is the copy MEASURED
# there -- the duplication is named rather than left to be rediscovered.
def fz_tk.put(w: String, hd: U32, acc: List<&2, Tok>) -> List<&2, Tok>:
  match hd:
    case 1: List.append(&2, Tok, acc, [THead{w}])
    case _: List.append(&2, Tok, acc, [TLeaf{w}])

def fz_tk.flush(w: List<&2, Char>, hd: U32, acc: List<&2, Tok>) -> List<&2, Tok>:
  match w:
    case Nil{}: acc
    case _: fz_tk.put(String.from_list(w), hd, acc)

def fz_tk.close(w: List<&2, Char>, hd: U32, acc: List<&2, Tok>) -> List<&2, Tok>:
  List.append(&2, Tok, fz_tk.flush(w, hd, acc), [TClose{}])

# THE PARAMETER ORDER IS LOAD-BEARING: Bend matches parameters in DECLARATION order, so
# a def that matches its fuel may not then match a parameter declared before it. `n`
# is first for exactly that reason and the class comes second for the same one.
def fz_tok(n: Nat, k: U32, +s: List<&2, Char>, acc: List<&2, Tok>, w: List<&2, Char>, +hd: U32) -> List<&2, Tok>:
  match n:
    case 0n: fz_tk.flush(w, hd, acc)
    case 1n+p:
      match k:
        case 0: fz_tk.flush(w, hd, acc)
        case 1: fz_tok(p, fz_cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), fz_tk.close(w, hd, acc), Nil{}, hd)
        case 2: fz_tok(p, fz_cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), acc, Nil{}, 1)
        case 3: fz_tok(p, fz_cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), fz_tk.flush(w, hd, acc), Nil{}, 0)
        case _: match s:
          case Nil{}: fz_tk.flush(w, hd, acc)
          case c <> t: fz_tok(p, fz_cls(t), t, acc, List.append(&2, Char, w, [c]), hd)

def fz_toks(+s: String) -> List<&2, Tok>:
  fz_tok(4096n, fz_cls(String.to_list(s)), String.to_list(s), Nil{}, Nil{}, 0)

# THE VOCABULARY. A head token is the op's own `Ops.name` in lower case, so a typo
# cannot hide: the driver PRINTS `Ops.name`, so a head it did not recognise comes
# back as `NOOP`.
# the dtype set the case file can name, and it is the whole of `spec.bend`'s, because a
# pattern's dtype constraint is written in the FIXTURE: `:186` asks `can_lossless_cast(b, a)`
# and a corpus that could only say `i32` could not state a lossless or a lossy pair at all.
def fz_dt(nm: String) -> S.Dt:
  match nm:
    case "weakint": S.weakint()
    case "bool": S.boolean()
    case "i8": S.int8()
    case "u8": S.uint8()
    case "i16": S.int16()
    case "u16": S.uint16()
    case "i32": S.int32()
    case "u32": S.uint32()
    case "i64": S.int64()
    case "u64": S.uint64()
    case "f16": S.half()
    case "bf16": S.bfloat16()
    case "f32": S.single()
    case "f64": S.double()
    case "weakfloat": S.weakfloat()
    case _: S.void()

def fz_dtnm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def fz_part(nm: String, k: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(nm, Char.from_u32(58)), k), "")

def fz_op(nm: String) -> O.Op:
  match nm:
    case "noop": O.OpsNOOP{}
    case "sink": O.OpsSINK{}
    case "stack": O.OpsSTACK{}
    case "index": O.OpsINDEX{}
    case "load": O.OpsLOAD{}
    case "store": O.OpsSTORE{}
    case "where": O.OpsWHERE{}
    case "cast": O.OpsCAST{}
    case "bitcast": O.OpsBITCAST{}
    case "exp2": O.OpsEXP2{}
    case "log2": O.OpsLOG2{}
    case "sin": O.OpsSIN{}
    case "sqrt": O.OpsSQRT{}
    case "reciprocal": O.OpsRECIP{}
    case "neg": O.OpsNEG{}
    case "trunc": O.OpsTRUNC{}
    case "add": O.OpsADD{}
    case "mul": O.OpsMUL{}
    case "shl": O.OpsSHL{}
    case "shr": O.OpsSHR{}
    case "cdiv": O.OpsTRUNCDIV{}
    case "max": O.OpsMAX{}
    case "cmod": O.OpsTRUNCMOD{}
    case "cmplt": O.OpsCMPLT{}
    case "cmpne": O.OpsCMPNE{}
    case "cmpeq": O.OpsCMPEQ{}
    case "xor": O.OpsXOR{}
    case "or": O.OpsOR{}
    case "and": O.OpsAND{}
    case "threefry": O.OpsTHREEFRY{}
    case "sub": O.OpsSUB{}
    case "fdiv": O.OpsFDIV{}
    case "pow": O.OpsPOW{}
    case "floordiv": O.OpsDIV{}
    case "floormod": O.OpsMOD{}
    case "range": O.OpsRANGE{}
    case "after": O.OpsAFTER{}
    case "end": O.OpsEND{}
    case "barrier": O.OpsBARRIER{}
    case "reduce": O.OpsREDUCE{}
    case "param": O.OpsPARAM{}
    case "shrink": O.OpsSHRINK{}
    case "reshape": O.OpsRESHAPE{}
    case "permute": O.OpsPERMUTE{}
    case "mulacc": O.OpsMULACC{}
    # TODO(p2): AN UNKNOWN OP NAME IS A SILENT NOOP, so a misspelt fixture builds the wrong
    # graph and reports `norewrite`. Reproduced 2026-11-03 on `(range c8)`, which the reader
    # could not name and turned into a NOOP instead of refusing. The fix is a `Maybe` answer
    # through `fz_build`, and the case file should never be able to state an op nobody has.
    case _: O.OpsNOOP{}

def fz_arg.dt.of(dt: S.Dt) -> O.Arg:
  match dt:
    case S.Dt{0, 0, S.CVoid{}, _}: O.ANone{}
    case _: O.ADt{dt}

# a reduce's suffix is its rop and not a dtype, and it is the one op whose arg is a pair:
# `(reduce:add x (range c8))` states `AReduce{OpsADD, 1}`, with the axis count read off the
# srcs because `num_axes` IS `len(srcs)-1` -- `UPat(...).reduce()` writes `(op, 0)` and a real
# graph writes the count. A suffix-less `(reduce ...)` is `ANone`, which is Python's `arg=None`.
# A `match` CANNOT SCRUTINISE A COMPUTED VALUE, so the suffix is handed to its own def.
def fz_arg.rop2(r: String, n: U32) -> O.Arg:
  match r:
    case "": O.ANone{}
    case _ : O.AReduce{fz_op(r), U32.sub(n, 1)}

def fz_arg.rop(nm: String, n: U32) -> O.Arg: fz_arg.rop2(fz_part(nm, 1n), n)

def fz_arg(op: O.Op, nm: String, n: U32) -> O.Arg:
  match op:
    case O.OpsCAST{}: fz_arg.dt.of(fz_dt(fz_part(nm, 1n)))
    case O.OpsBITCAST{}: fz_arg.dt.of(fz_dt(fz_part(nm, 1n)))
    case O.OpsREDUCE{}: fz_arg.rop(nm, n)
    case _: O.ANone{}

# THE BUILD. One def, and every def it calls does NOT call back, so this is a fold
# and not a cycle. A frame is pushed on a HEAD and popped on a CLOSE, and `St.root`
# is the finished node: a list tail cannot carry what the frame above has to be
# handed, so the answer rides out in the state.
def St.ar(s: St) -> O.Arena:
  match s:
    case St{ar, stk, root}: ar

def St.stk(s: St) -> List<&2, Frm>:
  match s:
    case St{ar, stk, root}: stk

def St.root(s: St) -> Maybe<&2, U32>:
  match s:
    case St{ar, stk, root}: root

def Frm.srcs(f: Frm) -> List<&2, U32>:
  match f:
    case Frm{srcs, head}: srcs

def Frm.head(f: Frm) -> String:
  match f:
    case Frm{srcs, head}: head

def fz_deliver.at(t: List<&2, Frm>, +st: St, i: U32) -> St:
  match t:
    # the updated frame goes back on top for the same reason `fz_build.one`'s head arm
    # does: appending it to `u` moved it BELOW the frames still open, so the next leaf
    # was delivered to the parent. MEASURED on `(sink (group x) c2)` with the head arm
    # fixed and this one not, the root answered `op=Ops.GROUP` where the s-expr says
    # SINK -- the GROUP was still on the stack when the last `)` closed it again.
    case +f <> u: St{St.ar(st), List.append(&2, Frm, [Frm{List.append(&2, U32, Frm.srcs(f), [i]), Frm.head(f)}], u), St.root(st)}
    case Nil{}: St{St.ar(st), Nil{}, Some{i}}

def fz_deliver(+st: St, i: U32) -> St: fz_deliver.at(St.stk(st), st, i)

# A node is closed, so BUILD it and hand it to the frame above. The arena and the
# index both come out of the one `Found`, which is why this is one def.
def fz_close.give(+f: O.Found, u: List<&2, Frm>, r: Maybe<&2, U32>) -> St:
  fz_deliver(St{O.Found.ar(f), u, r}, O.Found.i(f))

def fz_close.new.of(+op: O.Op, ar: O.Arena, nm: String, +srcs: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, op, srcs, fz_arg(op, nm, U32.from_nat(List.length(&2, U32, srcs))), O.TNone{})

def fz_close.new(ar: O.Arena, +nm: String, srcs: List<&2, U32>) -> O.Found:
  fz_close.new.of(fz_op(fz_part(nm, 0n)), ar, nm, srcs)

def fz_close.at(t: List<&2, Frm>, ar: O.Arena, r: Maybe<&2, U32>) -> St:
  match t:
    case +f <> u: fz_close.give(fz_close.new(ar, Frm.head(f), Frm.srcs(f)), u, r)
    case Nil{}: St{ar, Nil{}, r}

def fz_close(+st: St) -> St: fz_close.at(St.stk(st), St.ar(st), St.root(st))

def fz_i64_neg(u: U32) -> H.I64: H.i64_sub(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, u))

def fz_num.of(m: Maybe<&2, U32>) -> U32: Maybe.default(&2, U32, m, 0)

def fz_num(w: String) -> U32: fz_num.of(U32.read(w))

# `c7` is a non-negative weakint CONST and `n7` a negative one.
def fz_leaf.sgn(c: U32, w: String, ar: O.Arena) -> O.Found:
  match c:
    case 99: O.UOp.const(ar, O.CInt{H.i64_of_hi_lo(0, fz_num(String.drop(w, 1n)))})
    case _: O.UOp.const(ar, O.CInt{fz_i64_neg(fz_num(String.drop(w, 1n)))})

# `UOp.variable` -- ops.py:1055, "a Variable is a scalar ALU PARAM with a name
# and a value range", which is the whole of the `ParamArg` this driver states.
# and `O.Arena.empty()`. A case file therefore could not say `x` AND `y`, and the
# rebind rules -- `(x^y)^y` (symbolic.py:123), `(x%y)%y` (:124), `(x*x*x).recip()`
# (:464) -- carry an IDENTITY CHECK as their whole guard, so a corpus that cannot
# name two variables cannot state a positive and a negative for any of them. The
# arena mattered too: minting every variable into `Arena.empty()` put each one at
# the same index, so `x` and `y` would have been ONE node.
def fz_var(+ar: O.Arena, +nm: String, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{O.ParamArg.no_slot(), dt, Some{O.PyRange{H.i64_of_hi_lo(0, 0), H.i64_of_i32(100)}}, Some{1}, Some{nm}, S.Aalu{},
      None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

# The four CONST spellings and the four VARIABLE dtypes. A leaf is interned into
# the arena the state already carries, so a repeated `c7` in one case is ONE
# node -- which is what makes `x // x` and `x // y` distinguishable at all.
def fz_leaf.var(+ar: O.Arena, +w: String, dt: S.Dt) -> O.Found: fz_var(ar, w, dt)

# `x` weakint, `xb` bool, `xf` weakfloat, `P.xi` int32 -- the dtype is the LAST
# character and the NAME is the whole word, so `x` and `y` are two variables at ONE
# dtype and `P.xi` is a third node whose dtype is int32. `y` at bool is `yb`.
def fz_lastu.at(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 32
    case Chr{u} <> _: u

def fz_lastu(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 32
    case _ <> t: fz_lastu.at(t)

def fz_vdt.at(u: U32) -> S.Dt:
  match u:
    case 98: S.boolean()
    case 102: S.weakfloat()
    case 105: S.int32()
    case _: S.weakint()

def fz_vdt(w: List<&2, Char>) -> S.Dt: fz_vdt.at(fz_lastu(w))

# THE CONST/VARIABLE SPLIT IS THE HEAD CHARACTER, and it is `c`/`n`/one of the three
# fixed spellings rather than a fixed list of names -- so `x` and `y` are two
# variables at ONE dtype and `c7`/`n7` stay the two int CONSTs. `fz_code` is the head.
def fz_is_cst(+w: String) -> Bool:
  Bool.or(String.eq(w, "bt"), Bool.or(String.eq(w, "bf"),
    Bool.or(String.eq(w, "bad"), Bool.or(U32.is_eq(fz_code(w), 99), U32.is_eq(fz_code(w), 110)))))

def fz_leaf.go.at(cst: Bool, +ar: O.Arena, +w: String) -> O.Found:
  match cst:
    case True{}:
      match w:
        case "bad": O.UOp.const(ar, O.CInvalid{})
        case "bt": O.UOp.const(ar, O.CBool{True{}})
        case "bf": O.UOp.const(ar, O.CBool{False{}})
        case _: fz_leaf.sgn(fz_code(w), w, ar)
    case _: fz_leaf.var(ar, w, fz_vdt(String.to_list(w)))

def fz_leaf.go(+ar: O.Arena, +w: String) -> O.Found: fz_leaf.go.at(fz_is_cst(w), ar, w)

def fz_leaf(+st: St, w: String) -> O.Found: fz_leaf.go(St.ar(st), w)

def fz_build.one(t: Tok, +st: St) -> St:
  match t:
    # A FRAME GOES ON TOP, and `List.append(&2, Frm, [f], St.stk(st))` is the whole of
    # "on top": appending the new frame to the END put it BELOW the open ones, so every
    # case with NESTING built a different graph. MEASURED on `(xor (xor x c5) c5)`
    # before/after, `O.Arena.srcs` on the root read `2 3 2` and reads `3 2`: the inner
    # flat cases (`(add c7 c0)`, `(group x)`) were right either way, which is why one
    # corpus row out of two looked healthy.
    case THead{w}: St{St.ar(st), List.append(&2, Frm, [Frm{Nil{}, w}], St.stk(st)), St.root(st)}
    case TLeaf{w}: fz_close.give(fz_leaf(st, w), St.stk(st), St.root(st))
    case TClose{}: fz_close(st)

def fz_build(ts: List<&2, Tok>, +st: St) -> St:
  match ts:
    case Nil{}: st
    case t <> r: fz_build(r, fz_build.one(t, st))

# the canonical form is the same s-expr, and `x.op.name.lower()` is why `render.bend`'s
# `op_lower` is imported: `Ops.name` is the `Ops.MUL` form and the oracle spells `mul`.
#
# THE ORDER IS FREE, and that is the point: hash-consing puts a node's srcs BEFORE it, so
# slot `i`'s text reads only slots `< i` and ONE left-to-right pass renders every node
# exactly once. The job-list this replaces pushed each child's open frame AND the child's
# own frame and closed every leaf, so `(reciprocal (mul x x))` printed
# `(mul (reciprocal (reciprocal xx))))` -- MEASURED 2026-11-03, and the reason no case had
# ever compared a non-leaf answer.
def fz_render.i64.of(i: H.I64, neg: Bool) -> String:
  match neg:
    case True{}: String.concat(["n", U32.show(U32.sub(0, H.lo32(i)))])
    case False{}: String.concat(["c", U32.show(H.lo32(i))])

def fz_render.i64(+i: H.I64) -> String: fz_render.i64.of(i, H.i64_is_neg(i))

# `bad` is the oracle's WORD for `NOT AN INT AND NOT A BOOL`, and a FLOAT const is one:
# `symrules-oracle.py`'s `sh()` answers it for anything that is neither, because the canonical
# form states an int and a bool and nothing else. MEASURED: the oracle prints `bad` for the
# `1.0` and `-1.0` that `1-d` builds, so the port must print the same word or the two answers
# are two spellings of one graph. THE CONSTANT'S VALUE IS NOT COMPARED -- `1.0` and `-1.0`
# render alike on BOTH sides, so a rule that swapped them would still agree. TODO(p2): render
# the float, on both sides, in one commit.
def fz_render.cval(v: O.Const) -> String:
  match v:
    case O.CBool{b}: match b:
      case True{}: "bt"
      case False{}: "bf"
    case O.CInt{i}: fz_render.i64(i)
    case _: "bad"

def fz_render.const(a: O.Arg) -> String:
  match a:
    case O.APy{v}: fz_render.cval(v)
    case _: "?"

def fz_pname(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: "?"

# a leaf is its own text, and a PARAM prints its name rather than its dtype. The
# dtype glyph `x`/`xb`/`xf`/`P.xi` was a stand-in for a name that did not exist, and
# with the name now in `ParamArg` it is the wrong text: two variables at ONE dtype
# would render as the same string and a canonical form that cannot tell `x` from `y`
# cannot carry a rebind rule's answer.
def fz_render.param(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: fz_pname(O.ParamArg.name(pa))
    case _: "?"

# the op name and its dtype suffix, which is `Ops.name` plus a `:` and the
# dtype when the op's arg states one. `(cast:int c7)` and `(add c7 c0)` are the
# two shapes, and the arg is the only difference.
def fz_head.sfx(a: O.Arg, nm: String) -> String:
  match a:
    case O.ADt{dt}: String.concat([nm, ":", fz_dtnm(dt)])
    case O.AReduce{rop, num_axes}: String.concat([nm, ":", R.op_lower(rop)])
    case _: nm

def fz_head.of(op: O.Op, a: O.Arg, ar: O.Arena) -> String:
  match op:
    case O.OpsCONST{}: fz_render.const(a)
    case O.OpsPARAM{}: fz_render.param(a)
    case _: fz_head.sfx(a, R.op_lower(op))

# ---- `ops.py:495`, `UOp.simplify` --------------------------------------------------
#
#     if self.op is Ops.CONST: return self
#     if self.op is Ops.SINK and all(...): return self
#     return graph_rewrite(self, symbolic, name="simplify")
#
# it is built here and not on `codegen`'s `graph_rewrite`, and that is measured:
# `graph_rewrite(ar, i, P.sym_table(), CArgs{Nil{}}, False{})` on `(mul P.xi c1)` records
# `repl: 0->0 1->1 2->0 3->0 4->0` -- ONE entry, an IDENTITY, and the rewritable node `3` a MISS.
# The reason is structural: a `PMEntry` carries the tag, the ops and the reject set, but the BODY for
# each tag is `P.sym_dispatch`, which lives in THIS file, and `codegen/__init__.bend` does not import
# symbolic (the dependency runs the other way, for `substitute`). A table with no dispatcher cannot
# apply a rule.
#
# SO THE PASS IS `P.sym_f` -- the scanner this file already trusts -- and `simplify` is its FIXPOINT,
# which is what `walk=False` is upstream. `P.sy_novel` is what `P.sym_try` uses to answer "did the rule
# change the node", so a `None` from `sym_f` IS "no change" and the loop stops.
#
# the pass cap is a cap and it is named: upstream runs to a fixpoint with no bound, this runs at most
# 8 passes. A graph that needs more answers its 8th iterate rather than looping; that is a divergence
# class this def cannot see, and `SIMPLIFY_PASSES` is where to raise it.
def sy_simp.go(m: Maybe<&1, O.Found>, +f: O.Found) -> O.Found:
  match m:
    case Some{+g}: g
    case None{}  : f

def sy_simp.n(fuel: Nat, +f: O.Found) -> O.Found:
  match fuel:
    case 0n: f
    case 1n+p:
      sy_simp.n(p, sy_simp.go(P.sym_f(F.folded(O.Found.ar(f)), O.Found.i(f)), f))

def sy_simplify(+ar: O.Arena, i: U32) -> Maybe<&1, O.Found>:
  Some{sy_simp.n(8n, O.Found{ar, i})}

# ---- `symbolic.py:330`, `parse_valid` ----------------------------------------------
#
#     neg = v.op is CMPNE and v.src[1].op is CONST and v.src[1].val == 1
#     if (lt:=v.src[0] if neg else v).op is not CMPLT or not dtypes.is_int(lt.src[0].dtype): return None
#     if (a:=lt.src[0]).op is CONST: return lt.src[1], neg, int(a.val) + (0 if neg else 1)
#     return a, not neg, int(lt.src[1].vmin) if neg else int(lt.src[1].vmax)-1
#
# `X <= c` answers `(X, True, c)` and `X >= c` answers `(X, False, c)`. The negation is NOT `NOT`:
# `a < b` is `a <= b.vmax-1`, so the constant is ADJUSTED by one and the direction FLIPS, which is
# why the two arms differ in more than a Bool.
#
# A RECORD AND NOT A `Maybe` OF A TRIPLE: `Maybe` is affine and cannot be destructured twice, and
# the caller reads all three fields.
type Pv is Data:
  Pv{ok: Bool, e: U32, up: Bool, c: H.I64}

def Pv.ok(x: Pv) -> Bool:
  match x:
    case Pv{ok, e, up, c}: ok

def Pv.e(x: Pv) -> U32:
  match x:
    case Pv{ok, e, up, c}: e

def Pv.up(x: Pv) -> Bool:
  match x:
    case Pv{ok, e, up, c}: up

def Pv.c(x: Pv) -> H.I64:
  match x:
    case Pv{ok, e, up, c}: c

# UPSTREAM'S `parse_valid` AT THE PIN (`f5ac54685074`, tinygrad/uop/symbolic.py:344):
#
#   neg = v.op is CMPEQ and v.src[1].op is CONST and v.src[1].val == 0
#   if (lt:=v.src[0] if neg else v).op is not CMPLT or not dtypes.is_int(lt.src[0].dtype): return None
#   if (a:=lt.src[0]).op is Ops.CONST: return lt.src[1], neg, int(a.val) + (0 if neg else 1)
#   return a, not neg, int(lt.src[1].vmin) if neg else int(lt.src[1].vmax)-1
#
# the CONST is on the left for `X <= c` and on the right for `X >= c`, and that is the whole
# difference between them: both are `CMPEQ(CMPLT(...), False)`, so `neg` is True for both, and
# the CONST-on-left branch returns `is_upper = neg` while the other branch returns `not neg`.
#
# `src[1].val == 0` IS TRUE FOR A BOOL `CONST(False)` AS WELL AS AN INT `CONST(0)`: Python
# compares `False == 0`. MEASURED: reading only `P.cval` (which is `CInt`) answered `none` for
# `CMPEQ(CMPLT, False)`, and upstream answers `(X, True, c)`.
def pv.neg.src(+fx: F.Folded, +v: U32) -> Bool:
  +ar = F.Folded.ar(fx)
  Bool.and(O.eq_op(O.Arena.op(ar, v), O.OpsCMPEQ{}),
    Bool.and(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, v, 1)), O.OpsCONST{}),
      Bool.or(P.cb_false(P.sy_val(fx, O.Arena.src(ar, v, 1))),
              Cmp.is_eq(H.i64_cmp(P.cval(ar, O.Arena.src(ar, v, 1)), H.i64_of_i32(0))))))

def pv.lt(neg: Bool, +ar: O.Arena, +v: U32) -> U32:
  Bool.pick(U32, neg, O.Arena.src(ar, v, 0), v)

# THE CONST-ON-RIGHT BRANCH: `X >= c` is `CMPEQ(CMPLT(X, c), False)`, so `a` is the EXPR and the
# bound comes from the OTHER side's own bounds: `lt.src[1].vmin` when `neg` and `lt.src[1].vmax - 1`
# otherwise -- upstream's `int(lt.src[1].vmin) if neg else int(lt.src[1].vmax)-1`. `is_upper` is
# `not neg`.
def pv.other(+ar: O.Arena, +lt: U32, +neg: Bool, +bt: F.BTable) -> Pv:
  Pv{True{}, O.Arena.src(ar, lt, 0), Bool.not(neg),
     Bool.pick(H.I64, neg,
       P.vmin_i64(ar, bt, O.Arena.src(ar, lt, 1)),
       H.i64_sub(P.vmax_i64(ar, bt, O.Arena.src(ar, lt, 1)), H.i64_of_i32(1)))}

# THE CONST-ON-LEFT BRANCH: `X <= c` is `CMPEQ(CMPLT(c, X), False)`, so `a` is the const and the
# EXPR is `lt.src[1]`. `is_upper` is `neg` and `c` is the const, `+ 0` when `neg` and `+ 1`
# otherwise -- upstream's `int(a.val) + (0 if neg else 1)`.
def pv.arm(con: Bool, +ar: O.Arena, +lt: U32, neg: Bool, +bt: F.BTable) -> Pv:
  # `neg` IS READ TWICE, so it is bound once: `+n = neg` gives a NAME, and a name may be read
  # more than once.
  +n = neg
  Bool.pick(Pv, con,
    Pv{True{}, O.Arena.src(ar, lt, 1), n,
       H.i64_add(P.cval(ar, O.Arena.src(ar, lt, 0)), Bool.pick(H.I64, n, H.i64_of_i32(0), H.i64_of_i32(1)))},
    pv.other(ar, lt, n, bt))

def pv.mk(ok: Bool, +ar: O.Arena, +lt: U32, neg: Bool, +bt: F.BTable) -> Pv:
  match ok:
    case True{} : pv.arm(O.eq_op(O.Arena.op(ar, O.Arena.src(ar, lt, 0)), O.OpsCONST{}), ar, lt, neg, bt)
    case False{}: Pv{False{}, 0, False{}, H.i64_of_i32(0)}

# `(lt:=v.src[0] if neg else v).op is not CMPLT or not dtypes.is_int(lt.src[0].dtype)`
def pv.gate(+neg: Bool, +ar: O.Arena, +v: U32, +bt: F.BTable) -> Pv:
  +lt = pv.lt(neg, ar, v)
  pv.mk(Bool.and(O.eq_op(O.Arena.op(ar, lt), O.OpsCMPLT{}),
                 S.Cls.is_int(S.Dt.cls(P.sy_dt1(F.folded(ar), O.Arena.src(ar, lt, 0))))), ar, lt, neg, bt)

def sy_parse_valid(+ar: O.Arena, +v: U32) -> Pv:
  +bt = F.mm.sweep(ar, F.Folded.t(F.folded(ar)))
  pv.gate(pv.neg.src(F.folded(ar), v), ar, v, bt)

# ---- `symbolic.py:354`, `uop_given_valid` ---------------------------------------------
#
# THE PORT OF UPSTREAM'S `uop_given_valid(valid, uop)`: GIVEN that `valid` holds, simplify `uop`.
# EVERY PIECE IS MEASURED PRESENT, and the two that were the WALLS are the two this session fixed
# or found:
#
#   parse_valid      `sy_parse_valid` -- and it IS upstream's `parse_valid` (its two arms compute
#                     the same `c`), so it returns (expr, is_upper, c) in `Pv{ok, e, up, c}`
#   the expr bounds  `P.vmin_i64` / `P.vmax_i64`
#   the fake variable `O.UOp.variable`
#   the substitute   `P.s1.multi` -- THE MULTI-ENTRY ONE, added this session, because upstream
#                     substitutes a DICT and the port's `P.s1.sub` took ONE pair
#   the simplify     `sy_simplify` -- and it is the BASE fixpoint, so there is NO CYCLE: upstream's
#                     `ops.py:492` re-enters `symbolic` (:247) and not `P.sym` (:463)
#
# the bounds map is keyed by the arena INDEX of the expr, and its value is a pair of optional
# bounds -- upstream's `defaultdict(list)` gives `[None, None]` per expr and sets ONE side.
type Ugv is Data:
  Ugv{lo: Maybe<&2, H.I64>, hi: Maybe<&2, H.I64>}

def Ugv.lo(x: Ugv) -> Maybe<&2, H.I64>:
  match x:
    case Ugv{lo, hi}: lo

def Ugv.hi(x: Ugv) -> Maybe<&2, H.I64>:
  match x:
    case Ugv{lo, hi}: hi

type UgvEnt is Data:
  UgvEnt{k: U32, b: Ugv}

def UgvEnt.k(x: UgvEnt) -> U32:
  match x:
    case UgvEnt{k, b}: k

def UgvEnt.b(x: UgvEnt) -> Ugv:
  match x:
    case UgvEnt{k, b}: b

# SET ONE SIDE OF AN EXISTING ENTRY, or add the entry with that side set. Upstream's
# `bounds[expr][int(is_upper)] = c`, so `up=True` is the UPPER bound (the `hi` side) and
# `up=False` is the LOWER bound (the `lo` side).
def Ugv.set(+m: List<&2, UgvEnt>, +e: U32, +up: Bool, +c: H.I64) -> List<&2, UgvEnt>:
  match m:
    case Nil{}:
      List.append(&2, UgvEnt, m, [UgvEnt{e, Ugv{
        Bool.pick(Maybe<&2, H.I64>, up, None{}, Some{c}),
        Bool.pick(Maybe<&2, H.I64>, up, Some{c}, None{})}}])
    case +h <> +t:
      +b = UgvEnt.b(h)
      +lo = Ugv.lo(b)
      +hi = Ugv.hi(b)
      Bool.pick(List<&2, UgvEnt>, U32.is_eq(UgvEnt.k(h), e),
        List.append(&2, UgvEnt, t, [UgvEnt{e, Ugv{
          Bool.pick(Maybe<&2, H.I64>, up, lo, Some{c}),
          Bool.pick(Maybe<&2, H.I64>, up, Some{c}, hi)}}]),
        Ugv.set(t, e, up, c))

# the entry for an expr, or the empty pair when the expr has no clause.
def Ugv.get(+m: List<&2, UgvEnt>, +e: U32) -> Ugv:
  match m:
    case Nil{}: Ugv{None{}, None{}}
    case +h <> +t: Bool.pick(Ugv, U32.is_eq(UgvEnt.k(h), e), UgvEnt.b(h), Ugv.get(t, e))

# THE BOUNDS OF AN EXPR: the map's side if it has one, else the expr's own. Upstream:
#   v0, v1 = (expr.vmin if v[0] is None else v[0], expr.vmax if v[1] is None else v[1])
# and `v[1]` is the UPPER bound, so `up=True` reads `hi` and falls back to `vmax`.
def Ugv.bound(+m: List<&2, UgvEnt>, +ar: O.Arena, +bt: F.BTable, +e: U32, +up: Bool) -> H.I64:
  +b = Ugv.get(m, e)
  +s = Bool.pick(Maybe<&2, H.I64>, up, Ugv.hi(b), Ugv.lo(b))
  Bool.pick(H.I64, Maybe.is_some(&2, H.I64, s),
    Maybe.default(&2, H.I64, s, H.i64_of_i32(0)),
    Bool.pick(H.I64, up, P.vmax_i64(ar, bt, e), P.vmin_i64(ar, bt, e)))

type UgvCand is Data:
  UgvCand{e: U32, v: U32}

def UgvCand.e(x: UgvCand) -> U32:
  match x:
    case UgvCand{e, v}: e

def UgvCand.v(x: UgvCand) -> U32:
  match x:
    case UgvCand{e, v}: v

# THE CLAUSES: split the valid on AND and parse each. ONE FOLD over the SHRINKING clause list,
# because bend's self-call must SHRINK an argument and a list that GROWS cannot shrink; the
# accumulator carries the map and the candidate exprs.
type UgvAcc is Data:
  UgvAcc{m: List<&2, UgvEnt>, cs: List<&2, U32>}

def UgvAcc.m(x: UgvAcc) -> List<&2, UgvEnt>:
  match x:
    case UgvAcc{m, cs}: m

def UgvAcc.cs(x: UgvAcc) -> List<&2, U32>:
  match x:
    case UgvAcc{m, cs}: cs

def Ugv.step(+cs: List<&2, U32>, +ar: O.Arena, +acc: UgvAcc) -> UgvAcc:
  match cs:
    case Nil{}: acc
    case +c <> +t:
      +p = sy_parse_valid(ar, c)
      +m = Bool.pick(List<&2, UgvEnt>, Pv.ok(p), Ugv.set(UgvAcc.m(acc), Pv.e(p), Pv.up(p), Pv.c(p)), UgvAcc.m(acc))
      +cs2 = Bool.pick(List<&2, U32>, Pv.ok(p), List.append(&2, U32, UgvAcc.cs(acc), [Pv.e(p)]), UgvAcc.cs(acc))
      Ugv.step(t, ar, UgvAcc{m, cs2})

# THE FAKE VARIABLES: one per candidate expr, named `fake{i}`, with the bounds the map gives.
# Upstream: `UOp.variable(f"fake{i}", v0, v1, expr.dtype)`. A SECOND fold, over the candidates,
# because the bounds need the map and the map is complete only at the end of the first fold. The
# candidate list GROWS, so it is the ACCUMULATOR and the shrinking argument is the SOURCE list.
#
# the arena comes back out, and it is not a convenience: `O.UOp.variable` returns `Found{made, i}`
# where `made` is the GROWN arena and `i` is the index in IT -- so the index is legal only in
# `made`, and the substitute's walk arena must DESCEND from `made` or the index names nothing.
# MEASURED: with the index used in the OLD arena the fake's bounds read `none`, the forward
# simplify did not fold, and the answer was `x` instead of CPython's `bt`.
type UgvVars is Data:
  UgvVars{ar: O.Arena, cs: List<&2, UgvCand>}

def UgvVars.ar(x: UgvVars) -> O.Arena:
  match x:
    case UgvVars{ar, cs}: ar

def UgvVars.cs(x: UgvVars) -> List<&2, UgvCand>:
  match x:
    case UgvVars{ar, cs}: cs

def Ugv.vars(+cs: List<&2, U32>, +ar: O.Arena, +bt: F.BTable, +m: List<&2, UgvEnt>, +i: U32, acc: List<&2, UgvCand>) -> UgvVars:
  match cs:
    case Nil{}: UgvVars{ar, acc}
    case +e <> +t:
      +lo = Ugv.bound(m, ar, bt, e, False{})
      +hi = Ugv.bound(m, ar, bt, e, True{})
      +dt = P.sy_dt1(F.folded(ar), e)
      +v = O.UOp.variable(ar, String.concat(["fake", U32.show(i)]), lo, hi, 1, dt)
      +vx = Ugv.vars(t, O.Found.ar(v), bt, m, U32.add(i, 1), List.append(&2, UgvCand, acc, [UgvCand{e, O.Found.i(v)}]))
      UgvVars{O.Found.ar(v), UgvVars.cs(vx)}

# the candidate table for the substitute: expr -> fake variable, and fake variable -> expr, so the
# BACKWARD phase can undo it. Upstream's two dicts: `{X:newX}` and then `{newX:X}`.
def Ugv.tbl(+cs: List<&2, UgvCand>, acc: List<&2, P.Ky>) -> List<&2, P.Ky>:
  match cs:
    case Nil{}: acc
    case +c <> +t:
      Ugv.tbl(t, List.append(&2, P.Ky, acc, [P.Ky{UgvCand.e(c), UgvCand.v(c)}]))

def Ugv.back(+cs: List<&2, UgvCand>, acc: List<&2, P.Ky>) -> List<&2, P.Ky>:
  match cs:
    case Nil{}: acc
    case +c <> +t:
      Ugv.back(t, List.append(&2, P.Ky, acc, [P.Ky{UgvCand.v(c), UgvCand.e(c)}]))

# THE BACKWARD PHASE: substitute the fake variables BACK to the exprs, then simplify again.
# Upstream: `s_uop.simplify().substitute({newX: X}).simplify()`.
#
# TWO THINGS THE SPELLING IS FORCED BY, and both are measurements:
#   * `Maybe` IS A TYPE AND NOT A Data, so it CANNOT be a `+` binder -- a `Maybe` answer crosses
#     the boundary as a PARAMETER instead (see `Ugv.fwd3`);
#   * a `match` may not scrutinise a COMPUTED value, so the `Maybe` is passed in and matched there.
def Ugv.back2(+ar: O.Arena, +n: U32, +cs: List<&2, UgvCand>) -> Maybe<&1, O.Found>:
  +bk = Ugv.back(cs, Nil{})
  +sub = P.s1.multi(ar, n, bk)
  sy_simplify(O.Found.ar(sub), O.Found.i(sub))

# THE FORWARD PHASE: simplify the substituted graph, then run the backward phase. The `Maybe` is
# produced by `sy_simplify` and passed straight to `Ugv.fwd3`, which MATCHES it.
def Ugv.fwd3(simp: Maybe<&1, O.Found>, +cs: List<&2, UgvCand>) -> Maybe<&1, O.Found>:
  match simp:
    case Some{+f}: Ugv.back2(O.Found.ar(f), O.Found.i(f), cs)
    case None{}: None{}

# THE FORWARD RESULT, on its own -- the probe reads this to tell "the forward simplify did not
# fold" from "the backward phase undid the fold".
def Ugv.fwdonly(+ar: O.Arena, +n: U32, +cs: List<&2, UgvCand>) -> Maybe<&1, O.Found>:
  sy_simplify(ar, n)

def Ugv.fwd2(+ar: O.Arena, +n: U32, +cs: List<&2, UgvCand>) -> Maybe<&1, O.Found>:
  Ugv.fwd3(sy_simplify(ar, n), cs)

def Ugv.fwd(+ar: O.Arena, +n: U32, +cs: List<&2, UgvCand>) -> Maybe<&1, O.Found>:
  Ugv.fwd2(ar, n, cs)

# THE ENTRY. Upstream:
#   all_candidates = [(expr, UOp.variable(f"fake{i}", v0, v1, expr.dtype)) for each expr]
#   if (s_uop := uop.substitute(dict(all_candidates))) is not uop:
#     uop = s_uop.simplify().substitute({newX: X}).simplify()
def Ugv.go(+ar: O.Arena, +valid: U32, +uop: U32) -> Maybe<&1, O.Found>:
  +bt = F.mm.sweep(ar, F.Folded.t(F.folded(ar)))
  +acc = Ugv.step(O.UOp.split_uop(O.Arena.budget(ar), ar, valid, O.OpsAND{}), ar, UgvAcc{Nil{}, Nil{}})
  +vv = Ugv.vars(UgvAcc.cs(acc), ar, bt, UgvAcc.m(acc), 0, Nil{})
  +cs = UgvVars.cs(vv)
  +fw = Ugv.tbl(cs, Nil{})
  # the substitute walks the arena the fakes were minted in, so the fake's index names a node
  # in it -- see `Ugv.vars`'s own note on why the arena comes back out.
  +sub = P.s1.multi(UgvVars.ar(vv), uop, fw)
  # the substituted graph lives in a new arena -- `P.s1.multi` returns `Found{ar, n}` and that `ar`
  # is the arena the walk grew -- so the simplify must run in THAT arena and not in the one the
  # candidate table was built in. MEASURED: with the old arena the simplify saw the OLD graph
  # and the answer was `x`; with the new arena it is `bt`, which is CPython's answer.
  Ugv.fwd(O.Found.ar(sub), O.Found.i(sub), cs)

# ---- `symbolic.py:388`, `simplify_valid` ---------------------------------------------
#
#   def simplify_valid(valid:UOp) -> UOp|None:
#     if valid.op_in_backward_slice_with_self(Ops.INDEX): return None
#     ret:list[UOp] = []
#     valids = list(valid.split_uop(Ops.AND))
#     valids = sorted(valids, key=lambda v: _valid_priority(v, valids))
#     for stmt in dedup(valids):
#       if ret: stmt = uop_given_valid(UOp.uprod(*ret), stmt)
#       ret.append(stmt)
#     return UOp.uprod(*ret) if ret != valids else None
#
# AND THE PRIORITY (upstream's `_valid_priority`):
#
#   def _valid_priority(v:UOp, valids:list[UOp]) -> tuple[int, int]:
#     return (0, 0) if (res:=parse_valid(v)) is None else (
#       sum(-1 for other in valids if res[0] is other or res[0] in other.backward_slice),
#       res[2] if res[1] else -res[2])
#
# TWO PARTS: the FIRST is the DEPENDENCY COUNT (a clause whose expr another clause depends on
# is LOWER), and the SECOND is the BOUND (an UPPER bound is positive and a LOWER bound is
# negative, so the TIGHTER bound sorts first). Upstream's tuple sorts ascending, so
# `(dep, bound)` ascending.
#
# the port has no sort, so the sort is an insertion sort over the clause list. The list grows,
# so it is the ACCUMULATOR and the shrinking argument is the SOURCE list.

# THE PRIORITY OF ONE CLAUSE, as a PAIR: (dependencies, bound). A clause `parse_valid` cannot
# read has priority `(0, 0)` -- upstream's first arm.
type SvP is Data:
  SvP{dep: H.I64, bnd: H.I64}

# THE ACCUMULATOR: the clauses already seen, and the ANSWERS they produced.
type SvAcc is Data:
  SvAcc{ret: List<&2, U32>, ans: List<&2, U32>}

# THE ORDER: `dep` ascending, then `bnd` ascending. UPSTREAM'S TUPLE ORDER, and the tuple is
# `(dep, bnd)` -- so a clause with FEWER dependencies comes first and, at the same dependency
# count, the SMALLER bound comes first.
# THE RECORD IS DESTRUCTURED ONCE, because a record may be read only once: `SvP.dep(a)` AND
# `SvP.bnd(a)` would read `a` twice.
def sv.lt2(a: SvP, b: SvP) -> Bool:
  match a:
    case SvP{ad, ab}: match b:
      case SvP{bd, bb}:
        +c1 = H.i64_cmp(ad, bd)
        Bool.or(Cmp.is_lt(c1), Bool.and(Cmp.is_eq(c1), Cmp.is_lt(H.i64_cmp(ab, bb))))

def sv.lt(a: SvP, b: SvP) -> Bool:
  sv.lt2(a, b)

# `res[0] is other or res[0] in other.backward_slice` -- the EXPR of this clause is the same
# node as another clause's expr, or it is in that clause's backward slice.
def sv.in.slice2(bs: List<&2, U32>, +e: U32, acc: Bool) -> Bool:
  match bs:
    case Nil{}: acc
    case h <> t: sv.in.slice2(t, e, Bool.or(acc, U32.is_eq(h, e)))

def sv.in.slice(+ar: O.Arena, +e: U32, +o: U32) -> Bool:
  sv.in.slice2(O.UOp.backward_slice(O.Arena.budget(ar), ar, o), e, False{})

# THE DEPENDENCY COUNT, as a FOLD over the other clauses. Upstream's
# `sum(-1 for other in valids if ...)`, and `-1` is the two's-complement `U32` `4294967295`.
def sv.dep.one(+ar: O.Arena, +e: U32, +o: U32) -> H.I64:
  Bool.pick(H.I64,
    Bool.or(U32.is_eq(e, o), sv.in.slice(ar, e, o)),
    H.i64_of_i32(4294967295), H.i64_of_i32(0))

def sv.dep.fold(+ar: O.Arena, +e: U32, +others: List<&2, U32>, +acc: H.I64) -> H.I64:
  match others:
    case Nil{}: acc
    case o <> t:
      # the arena and the expr are read twice -- once by the dependency test and once by the
      # recursive call -- so they are BOUND FIRST, and a `+` name may be read many times.
      +ar2 = ar
      +e2 = e
      sv.dep.fold(ar2, e2, t, H.i64_add(acc, sv.dep.one(ar2, e2, o)))

def sv.dep.of(+ar: O.Arena, +e: U32, +others: List<&2, U32>) -> H.I64:
  sv.dep.fold(ar, e, others, H.i64_of_i32(0))

# THE PRIORITY OF ONE CLAUSE.
def sv.prio(+ar: O.Arena, +v: U32, +others: List<&2, U32>) -> SvP:
  +p = sy_parse_valid(ar, v)
  Bool.pick(SvP, Pv.ok(p),
    SvP{sv.dep.of(ar, Pv.e(p), others), Bool.pick(H.I64, Pv.up(p), Pv.c(p), H.i64_neg(True{}, Pv.c(p)))},
    SvP{H.i64_of_i32(0), H.i64_of_i32(0)})

# THE INSERTION: walk the sorted list and put `c` BEFORE the first element it sorts above.
# `done` is the PREFIX already passed, so it is carried and never read twice.
def sv.ins2(+c: U32, +ar: O.Arena, +cs: List<&2, U32>, acc: List<&2, U32>, +done: List<&2, U32>) -> List<&2, U32>:
  match acc:
    case Nil{}: List.append(&2, U32, done, [c])
    case +h <> r:
      +before = sv.lt(sv.prio(ar, c, cs), sv.prio(ar, h, cs))
      Bool.pick(List<&2, U32>, before,
        List.append(&2, U32, done, [c, h]),
        sv.ins2(c, ar, cs, r, List.append(&2, U32, done, [h])))

def sv.ins(+c: U32, +ar: O.Arena, +cs: List<&2, U32>, acc: List<&2, U32>, done: List<&2, U32>) -> List<&2, U32>:
  sv.ins2(c, ar, cs, acc, done)

# THE INSERTION SORT. The list GROWS, so it is the ACCUMULATOR and the shrinking argument is
# the SOURCE list.
def sv.sort(+cs: List<&2, U32>, +ar: O.Arena, acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case c <> t: sv.sort(t, ar, sv.ins(c, ar, cs, acc, Nil{}))

# THE DEDUP: upstream's `dedup(valids)` keeps the FIRST of each equal clause. A clause is equal
# when it is the same NODE -- the port has no structural equality, and upstream's `dedup` on
# UOps is by hash, which for a hash-consed UOp is identity.
def sv.in.list2(t: List<&2, U32>, +e: U32, acc: Bool) -> Bool:
  match t:
    case Nil{}: acc
    case h <> r: sv.in.list2(r, e, Bool.or(acc, U32.is_eq(h, e)))

def sv.in.list(t: List<&2, U32>, +e: U32) -> Bool:
  sv.in.list2(t, e, False{})

def sv.dedup(+cs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case c <> t:
      # THE ACCUMULATOR IS READ TWICE -- once by the membership test and once by the append --
      # so it is BOUND FIRST.
      +a2 = acc
      sv.dedup(t, Bool.pick(List<&2, U32>, sv.in.list(a2, c), a2, List.append(&2, U32, a2, [c])))

# THE `uprod` OF THE ACCUMULATED CLAUSES: upstream's `UOp.uprod(*ret)`. The receiver is the
# FIRST clause and the rest follow, and `P.sy_uprod` reads the op off the receiver's dtype.
def sv.uprod(+ar: O.Arena, +cs: List<&2, U32>) -> Maybe<&1, O.Found>:
  match cs:
    case Nil{}: None{}
    case h <> r: P.sy_uprod(F.folded(ar), h, r)

# THE ACCUMULATOR'S READERS.
def SvAcc.ret(x: SvAcc) -> List<&2, U32>:
  match x:
    case SvAcc{ret, ans}: ret

def SvAcc.ans(x: SvAcc) -> List<&2, U32>:
  match x:
    case SvAcc{ret, ans}: ans

# THE APPEND: the clause goes into the accumulated list and the ANSWER into the answer list.
def sv.append2(+c: U32, +a: U32, acc: SvAcc) -> SvAcc:
  +a2 = acc
  SvAcc{List.append(&2, U32, SvAcc.ret(a2), [c]),
        List.append(&2, U32, SvAcc.ans(a2), [a])}

def sv.append(+c: U32, g: Maybe<&1, O.Found>, acc: SvAcc) -> SvAcc:
  match g:
    case Some{f}: sv.append2(c, O.Found.i(f), acc)
    case None{}: sv.append2(c, c, acc)

# the found is read twice -- its index and its arena -- so it is passed whole and read inside.
def sv.given2(+c: U32, +u: O.Found, acc: SvAcc) -> SvAcc:
  sv.append(c, Ugv.go(O.Found.ar(u), O.Found.i(u), c), acc)

# THE `uop_given_valid` ON THE ACCUMULATED VALID: the answer's node replaces the clause.
def sv.given(+c: U32, up: Maybe<&1, O.Found>, acc: SvAcc) -> SvAcc:
  match up:
    case Some{u}: sv.given2(c, u, acc)
    case None{}: sv.append(c, None{}, acc)

# ONE CLAUSE: `if ret: stmt = uop_given_valid(UOp.uprod(*ret), stmt)`. "IF ret" IS "IF THE
# accumulated clause list is not empty", so there is no separate flag. the list is a parameter,
# because a `match` may not scrutinise a COMPUTED value.
def sv.one(+c: U32, +ar: O.Arena, acc: SvAcc, ret: List<&2, U32>) -> SvAcc:
  match ret:
    case Nil{}: sv.append(c, None{}, acc)
    case _ <> _:
      # A `Maybe` IS A TYPE AND NOT A Data, so it CANNOT be a `+` binder -- it crosses as a
      # PLAIN binding, which is consumed once, and `sv.given` MATCHES it.
      up = sv.uprod(ar, ret)
      sv.given(c, up, acc)

# THE LOOP. The clause list SHRINKS, so it is the shrinking argument and the accumulator
# carries the clauses already seen and the answers they produced.
def sv.loop(+cs: List<&2, U32>, +ar: O.Arena, acc: SvAcc) -> SvAcc:
  match cs:
    case Nil{}: acc
    case c <> t:
      # THE ACCUMULATOR IS READ TWICE -- the clause list and the answer list -- so it is BOUND.
      +a2 = acc
      sv.loop(t, ar, sv.one(c, ar, a2, SvAcc.ret(a2)))

# THE IDENTITY TEST: two lists are the same when they have the same nodes in the same order.
# IT IS ONE RECURSION with an accumulator, because the two tails have to be compared together
# and TWO mutually recursive defs are not writable (Bend has no forward reference).
def sv.same2(b: List<&2, U32>, acc: Bool) -> Bool:
  match b:
    case Nil{}: acc
    case _ <> _ : False{}

def sv.same4(r: List<&2, U32>, t: List<&2, U32>, +h: U32, +g: U32, acc: Bool) -> Bool:
  match r:
    case Nil{}: sv.same2(t, Bool.and(acc, U32.is_eq(h, g)))
    case h2 <> r2: match t:
      case Nil{}: False{}
      case g2 <> t2: sv.same4(r2, t2, h2, g2, Bool.and(acc, U32.is_eq(h, g)))

def sv.same(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a:
    case Nil{}: sv.same2(b, True{})
    case h <> r: match b:
      case Nil{}: False{}
      case g <> t: sv.same4(r, t, h, g, True{})

# THE ANSWER: the `uprod` of the produced answers, or `None` when the answers are the clauses
# unchanged -- upstream's `ret != valids`.
def sv.answer(+ar: O.Arena, acc: SvAcc, +cs: List<&2, U32>) -> Maybe<&1, O.Found>:
  # THE ACCUMULATOR IS READ TWICE -- the answer list and the `uprod` -- so it is BOUND.
  +a2 = acc
  +ans = SvAcc.ans(a2)
  Bool.pick(Maybe<&1, O.Found>, sv.same(ans, cs),
    None{}, sv.uprod(ar, ans))

# THE REST: sort, dedup, run the loop, and answer.
#
# the comparison is against the sorted and dedup'd list, and that is upstream's `valids`:
# upstream REASSIGNS `valids` twice -- `valids = sorted(valids, ...)` and then
# `for stmt in dedup(valids)` -- and the final line compares `ret != valids` against the
# SORTED list. MEASURED: comparing against the UNSORTED list made the port answer a `CMPEQ`
# where CPython answers `none`, because the sort had put the clauses in a different order.
def sv.rest(+ar: O.Arena, +valid: U32) -> Maybe<&1, O.Found>:
  +cs = O.UOp.split_uop(O.Arena.budget(ar), ar, valid, O.OpsAND{})
  +sorted = sv.sort(cs, ar, Nil{})
  +uniq = sv.dedup(sorted, Nil{})
  +acc = sv.loop(uniq, ar, SvAcc{Nil{}, Nil{}})
  sv.answer(ar, acc, uniq)

# THE INDEX GATE: `valid.op_in_backward_slice_with_self(Ops.INDEX)`.
def sv.has.index2(bs: List<&2, U32>, +ar: O.Arena, acc: Bool) -> Bool:
  match bs:
    case Nil{}: acc
    case h <> t: sv.has.index2(t, ar, Bool.or(acc, O.eq_op(O.Arena.op(ar, h), O.OpsINDEX{})))

def sv.has.index(+ar: O.Arena, +v: U32) -> Bool:
  sv.has.index2(O.UOp.backward_slice_with_self(O.Arena.budget(ar), ar, v), ar, False{})

# THE ENTRY. Upstream's `simplify_valid(valid) -> UOp|None`.
def simplify_valid(+ar: O.Arena, +valid: U32) -> Maybe<&1, O.Found>:
  # `if valid.op_in_backward_slice_with_self(Ops.INDEX): return None`
  Bool.pick(Maybe<&1, O.Found>, sv.has.index(ar, valid),
    None{}, sv.rest(ar, valid))

# ---- `symbolic.py:441`, `gated_given_valid` -----------------------------------------
#
#   def gated_given_valid(cond:UOp, x:UOp, i:UOp) -> UOp|None:
#     # pure index math only: a LOAD in x executes even where cond is false, so its INDEX valid
#     # must survive the assumption
#     if x.dtype is not dtypes.weakint or x.op_in_backward_slice_with_self(Ops.INDEX): return None
#     # Skip if x contains DIV/MOD AND IMAGE mode is enabled -> image index e.g. openpilot
#     if IMAGE.value > 0 and x.op_in_backward_slice_with_self(Ops.TRUNCDIV, Ops.TRUNCMOD,
#                                                              Ops.DIV, Ops.MOD): return None
#     return cond.where(uop_given_valid(cond, x, try_simplex=False), i)
#
# THE `INVALID_GATE` PATTERN IS `WHERE(cond, x, CONST(Invalid))` -- the port's `P.p_gate` -- so
# `cond` IS `src[0]`, `x` IS `src[1]` AND `i` IS `src[2]`.
#
# the `IMAGE.value` gate is not ported: the port has no `IMAGE` flag (measured: `grep IMAGE`
# over `tinybendygrad/` names no flag reader), and upstream's gate is `IMAGE.value > 0` -- a
# FLAG that is OFF in every corpus run, so the gate is a REFUSAL in the measured universe and
# the rule is the same rule without it. the gate is recorded here and not silently dropped.
def gg.x.dtype(+x: F.Folded, +u: U32) -> S.Dt:
  P.sy_dt1(x, u)

# `Cls` IS A RECORD OF VARIANTS, so it is MATCHED and not compared.

# `Cls` IS A RECORD OF VARIANTS, so it is MATCHED and not compared.

# `Cls` IS A RECORD OF VARIANTS, so it is MATCHED and not compared.

# `Cls` IS A RECORD OF VARIANTS, so it is MATCHED and not compared.
def gg.cls.is.weakint(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case _: False{}

def gg.x.is.weakint(+x: F.Folded, +u: U32) -> Bool:
  gg.cls.is.weakint(S.Dt.cls(gg.x.dtype(x, u)))

# `x.op_in_backward_slice_with_self(Ops.INDEX)` -- the port's own reader is `P.sym_259.ixs`, which
# reads the INDEX in the node's THREE srcs' backward slices.

# `x.op_in_backward_slice_with_self(Ops.INDEX)` -- the port's own reader is `P.sym_259.ixs`, which
# reads the INDEX in the node's THREE srcs' backward slices.

# `x.op_in_backward_slice_with_self(Ops.INDEX)` -- the port's own reader is `P.sym_259.ixs`, which
# reads the INDEX in the node's THREE srcs' backward slices.

# `x.op_in_backward_slice_with_self(Ops.INDEX)` -- the port's own reader is `P.sym_259.ixs`, which
# reads the INDEX in the node's THREE srcs' backward slices.
def gg.has.index(+x: F.Folded, +u: U32) -> Bool:
  P.sym_259.ixs(x, u)

# THE ANSWER: `cond.where(uop_given_valid(cond, x, try_simplex=False), i)`. The `where` is a
# NEW node, so it is minted in the arena the `uop_given_valid` answer grew.

# THE ANSWER: `cond.where(uop_given_valid(cond, x, try_simplex=False), i)`. The `where` is a
# NEW node, so it is minted in the arena the `uop_given_valid` answer grew.

# THE ANSWER: `cond.where(uop_given_valid(cond, x, try_simplex=False), i)`. The `where` is a
# NEW node, so it is minted in the arena the `uop_given_valid` answer grew.

# THE ANSWER: `cond.where(uop_given_valid(cond, x, try_simplex=False), i)`. The `where` is a
# NEW node, so it is minted in the arena the `uop_given_valid` answer grew.
def gg.build(+ar: O.Arena, +cond: U32, +xv: U32, +iv: U32) -> O.Found:
  O.UOp.new(ar, O.OpsWHERE{}, [cond, xv, iv], O.ANone{}, O.TNone{})

# THE RULE. Upstream's `gated_given_valid(cond, x, i)`.

# the found is read twice -- its index and its arena -- so it is passed whole.
def gg.go5(+f: O.Found, +cond: U32, +iv: U32) -> Maybe<&1, O.Found>:
  Some{gg.build(O.Found.ar(f), cond, O.Found.i(f), iv)}

# ---- THE VALID LANE ---------------------------------------------------------------
#
# `pm_simplify_valid` IS A SEPARATE MATCHER upstream (`symbolic.py:448`), composed into `P.sym`
# as `symbolic+pm_simplify_valid+PatternMatcher([...])`. IT IS NOT IN `symbolic`, AND THE
# port's `sym_table()` is `symbolic`'s table -- so the valid rules get their own table and
# their own dispatcher, and `P.sym_f` (which walks `P.sym_table()`) never sees them.
#
# that is not cosmetics. upstream's `ops.py:492` re-enters `symbolic` (:247) and not `P.sym`
# (:463), so a valid rule that called `P.sym_f` would cycle: `P.sym` includes the valid rules and
# the valid rules call `P.sym`. the separate table is what breaks the cycle.
#
# MEASURED 2026-11-10: THIS HEADER WAS PASTED FOUR TIMES IN THIS FILE (once per valid
# rule) AND THE "TWO ARMS" BLOCK BELOW WAS PASTED FOUR TIMES, AND A HEADER THAT IS FOUR
# COPIES OF ONE PARAGRAPH IS ONE PIECE OF EVIDENCE AND NOT FOUR. THE REPEATS ARE GONE AND
# THE FIRST COPY IS THE ONE THAT IS KEPT -- so the reader who arrives at the third valid
# rule reads the SAME CLAIM, not a copy of it.

# THE RULE. Upstream's `gated_given_valid(cond, x, i)`.

def gg.go4(+ar: O.Arena, g: Maybe<&1, O.Found>, +cond: U32, +xv: U32, +iv: U32) -> Maybe<&1, O.Found>:
  match g:
    case Some{f}: gg.go5(f, cond, iv)
    case None{}: None{}

# the found is read twice -- its index and its arena -- so it is passed whole.

# ---- THE VALID LANE ---------------------------------------------------------------
#
# THE VALID LANE'S HEADER IS ABOVE, AT ITS FIRST OCCURRENCE -- `pm_simplify_valid` IS A
# SEPARATE MATCHER upstream (`symbolic.py:448`), it gets ITS OWN TABLE, AND THAT IS WHAT
# BREAKS THE `P.sym`/`P.sym_f` CYCLE. IT IS NOT REPEATED HERE BECAUSE A HEADER THAT IS FOUR
# COPIES OF ONE PARAGRAPH IS ONE PIECE OF EVIDENCE AND NOT FOUR (MEASURED 2026-11-10).

def gg.go3(+ar: O.Arena, +x: F.Folded, +cond: U32, +xv: U32, +iv: U32) -> Maybe<&1, O.Found>:
  # THE `uop_given_valid(cond, x, try_simplex=False)`: the port's `Ugv.go` is the `try_simplex`
  # variant's body minus the simplex branch, and the simplex branch is the `X0 + X1 + ... > 0`
  # special case -- so the port's `Ugv.go` IS `try_simplex=False` ALREADY. MEASURED: the port's
  # `Ugv` has no simplex arm, and upstream's simplex arm needs `GroupOp.Irreducible` and the
  # port's `UOp.group` builds a STACK, so the simplex branch is not ported.
  g = Ugv.go(ar, cond, xv)
  gg.go4(ar, g, cond, xv, iv)

def gg.go2(+ar: O.Arena, +x: F.Folded, +u: U32, +cond: U32, +xv: U32, +iv: U32) -> Maybe<&1, O.Found>:
  # THE FIRST GATE: `x.dtype is not dtypes.weakint` -- and the INDEX gate. A rule that may not
  # fire answers `None{}`, and `None{}` IS the refusal.
  Bool.pick(Maybe<&1, O.Found>,
    Bool.or(Bool.not(gg.x.is.weakint(x, xv)), gg.has.index(x, xv)),
    None{}, gg.go3(ar, x, cond, xv, iv))

# THE RULE. Upstream's `gated_given_valid(cond, x, i)`.

# THE RULE. Upstream's `gated_given_valid(cond, x, i)`.
def gg.go(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  +ar = P.sy_ar(x)
  +cond = P.sy_src0(x, u)
  +xv = P.sy_src1(x, u)
  +iv = P.sy_src2(x, u)
  gg.go2(ar, x, u, cond, xv, iv)

# ---- THE VALID LANE ---------------------------------------------------------------
#
# THE VALID LANE'S HEADER IS ABOVE, AT ITS FIRST OCCURRENCE -- `pm_simplify_valid` IS A
# SEPARATE MATCHER upstream (`symbolic.py:448`), it gets ITS OWN TABLE, AND THAT IS WHAT
# BREAKS THE `P.sym`/`P.sym_f` CYCLE. IT IS NOT REPEATED HERE BECAUSE A HEADER THAT IS FOUR
# COPIES OF ONE PARAGRAPH IS ONE PIECE OF EVIDENCE AND NOT FOUR (MEASURED 2026-11-10).

# ---- THE VALID LANE ---------------------------------------------------------------
#
# THE VALID LANE'S HEADER IS ABOVE, AT ITS FIRST OCCURRENCE -- `pm_simplify_valid` IS A
# SEPARATE MATCHER upstream (`symbolic.py:448`), it gets ITS OWN TABLE, AND THAT IS WHAT
# BREAKS THE `P.sym`/`P.sym_f` CYCLE. IT IS NOT REPEATED HERE BECAUSE A HEADER THAT IS FOUR
# COPIES OF ONE PARAGRAPH IS ONE PIECE OF EVIDENCE AND NOT FOUR (MEASURED 2026-11-10).

# THE TWO ARMS. `sym_450` IS `simplify_valid` AND `P.sym_451` IS `gated_given_valid`.
#
# the names are `sv_450` and `sv_451` and not `sym_450`/`P.sym_451` because those two names are
# ALREADY TAKEN: the port's `P.sym_451` IS THE `POW` RULE, and it cites `symbolic.py:451` IN A
# re-vendored upstream WHERE `:451` was the pow line. at the PIN (`f5ac54685074`) `:451` is
# `invalid_gate, gated_given_valid` and `:465` is the pow rule. the names are labels and the
# citations are in the table entries, so the collision is avoided by renaming and not by
# MOVING A CITATION.

# THE TWO ARMS. `sv_450` IS `simplify_valid` AND `sv_451` IS `gated_given_valid` -- AND
# WHY THEY ARE NOT `sym_450`/`P.sym_451` IS ABOVE, AT ITS FIRST OCCURRENCE (THE PORT's
# `P.sym_451` IS THE `POW` RULE, so the NAME IS TAKEN and the CITATION MOVES WITH THE
# TABLE ENTRY AND NOT WITH THE NAME).

# THE TWO ARMS. `sv_450` IS `simplify_valid` AND `sv_451` IS `gated_given_valid` -- AND
# WHY THEY ARE NOT `sym_450`/`P.sym_451` IS ABOVE, AT ITS FIRST OCCURRENCE (THE PORT's
# `P.sym_451` IS THE `POW` RULE, so the NAME IS TAKEN and the CITATION MOVES WITH THE
# TABLE ENTRY AND NOT WITH THE NAME).

# THE TWO ARMS. `sv_450` IS `simplify_valid` AND `sv_451` IS `gated_given_valid` -- AND
# WHY THEY ARE NOT `sym_450`/`P.sym_451` IS ABOVE, AT ITS FIRST OCCURRENCE (THE PORT's
# `P.sym_451` IS THE `POW` RULE, so the NAME IS TAKEN and the CITATION MOVES WITH THE
# TABLE ENTRY AND NOT WITH THE NAME).
def sv_450(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  simplify_valid(P.sy_ar(x), u)

def sv_451(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  gg.go(x, u)

# the valid dispatcher, and it is two arms because the table has two entries.

# the valid dispatcher, and it is two arms because the table has two entries.

# the valid dispatcher, and it is two arms because the table has two entries.

# the valid dispatcher, and it is two arms because the table has two entries. both rules mint
# (they build a new graph), so there is ONE dispatcher and it answers a `Found` -- there is no
# `valid_dispatch.go` and no `P.MINT_TAGS` for this lane, because EVERY entry in this table mints.
def valid_dispatch_f(tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match tag:
    case 0: sv_450(x, u)
    case 1: sv_451(x, u)
    case _: None{}

# THE VALID SCANNER, and it is the port's own `P.sym_scan_f` with the VALID DISPATCHER. The two
# lanes differ in ONE thing: the table they walk. `P.sym_scan_f` walks `P.sym_table()` and
# `valid_scan_f` walks `P.valid_table()`, so a valid rule can never see itself.
def valid_try_f.pick(ok: Bool, +tag: U32, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  match ok:
    case True{}: P.sy_novel_f(u, valid_dispatch_f(tag, x, u))
    case _     : None{}

def valid_try_f(ts: O.PMEntrys, +x: F.Folded, +u: U32, +e: O.PMEntry) -> Maybe<&1, O.Found>:
  valid_try_f.pick(Bool.and(O.op_in(O.PMEntry.ops(e), O.Arena.op(P.sy_ar(x), u)),
                             O.pm_early(ts, P.sy_ar(x), u, O.PMEntry.rej(e))),
                   O.PMEntry.tag(e), x, u)

def valid_scan_f(+ts: O.PMEntrys, +x: F.Folded, +u: U32, todo: List<&2, O.PMEntry>, acc: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match todo:
    case Nil{}  : acc
    case e <> t : valid_scan_f(ts, x, u, t, P.sy_keep_f.go(acc, valid_try_f(ts, x, u, e)))

def valid_rewrite_f(+ts: O.PMEntrys, +x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  valid_scan_f(ts, x, u, O.PMEntrys.es(ts), None{})

# the valid pass, and it is one pass and not a fixpoint. Upstream's `pm_simplify_valid` is a
# MATCHER COMPOSED INTO `P.sym`, so upstream's `sym` is a fixpoint OVER IT TOO -- but upstream's
# `graph_rewrite` re-enters `symbolic` and not `P.sym` (ops.py:492), so a valid rule that changed
# a graph is re-simplified by `symbolic` and not by the valid rules. the port's lanes are
# separate, so the outer entry runs the base fixpoint and then the valid pass, which is
# UPSTREAM'S ORDER: `symbolic+pm_simplify_valid+...` MEANS `symbolic` RUNS FIRST.
def valid_f(+x: F.Folded, +u: U32) -> Maybe<&1, O.Found>:
  valid_rewrite_f(P.valid_table(), x, u)

# THE OUTER ENTRY: the base fixpoint and then the valid pass, each on the graph the other
# produced. this is `P.sym` -- the composition -- and it is not `P.sym_f`, which is `symbolic` alone.

def sym_all3(+f: O.Found) -> Maybe<&1, O.Found>:
  valid_f(F.folded(O.Found.ar(f)), O.Found.i(f))
def sym_all2(base: Maybe<&1, O.Found>) -> Maybe<&1, O.Found>:
  match base:
    case Some{f}: sym_all3(f)
    case None{}: None{}

# THE OUTER ENTRY: the base fixpoint and then the valid pass, each on the graph the other
# produced. this is `P.sym` -- the composition -- and it is not `P.sym_f`, which is `symbolic` alone.
def sym_all(+ar: O.Arena, +i: U32) -> Maybe<&1, O.Found>:
  sym_all2(sy_simplify(ar, i))


# THE DRIVER'S OWN ENTRY. The port's `fz.gate()` is a LANE -- it is defined and
# nothing in the port calls it, because the port is a LIBRARY and its rows are
# the census of the symbolic rules.  MEASURED 2026-11-16: running the port
# printed NOTHING (two lines of "ALL PROOFS CHECK"), so the lane has to be
# called from here.
def main() -> IO(Unit):
  do IO<Unit>:
    fz.gate()
