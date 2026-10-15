# sym_graph_census.bend -- THE PORT LANE of a census over `tinybendygrad/uop/symbolic.bend`'s
# SYMBOLIC TABLES: `sym` (23 rules) and `pm_remove_invalid` (2 rules), driven over a CORPUS of
# s-expr fixtures, one row per case.
#
#     bin/bend gates/sym_graph_census.bend
#
# ============================ IT IS A PROBE, NOT A GATE ============================
# There is no `gates/sym_graph_census-gate.py` and there is no committed oracle. **THE OBSTACLE THIS
# PARAGRAPH NAMED WAS MEASURED AND IT WAS NOT WHAT IT SAID.** It claimed the walk's PRE-ORDER disagreed
# with CPython's, that `in=` agreed on `t_add`/`t_group` and DISAGREED on the three three-src roots
# "where this walk enters the node's LAST src first", and that a diff would therefore be a diff of two
# TRAVERSALS rather than of two rewriters. **ALL OF THAT WAS ONE BUG AND IT IS FIXED**: a new frame went
# to the BOTTOM (`fz_build.one`'s `THead` arm and `fz_deliver.at` both appending), so the arena's srcs
# came out reversed. `List.append([1,2],[3])` answers `1 2 3` -- IT APPENDS -- and
# `O.Arena.new([1,0]).srcs` answers `1 0`, so **THE ARENA PRESERVES SRC ORDER AND THERE WAS NEVER A
# TRAVERSAL DISAGREEMENT.** `in=` now agrees cell for cell. **"PINNING IT WOULD LAUNDER THE BUG" WAS
# THE RIGHT CAUTION APPLIED TO A CAUSE THAT DID NOT EXIST**, and a caution taken from a header rather
# than a measurement is a defect of the same family as a pin written from memory.
#
# SO THE THREE `sym=` DIVERGENCES BELOW ARE NOT FINDINGS YET, and this file does not claim them:
#   t_xor    port `norewrite`  where CPython answers the variable     `(x^c5)^c5 -> x` (:123)
#   t_xor0   port `norewrite`  where CPython answers `XOR(y, XOR(x,c5))`
#   t_sink   port `0:NOOP`     where CPython answers `SINK(x, c2)`    (:445, the SINK flatten)
# `t_sink` is the one to read first: a NOOP is a MINTED node, so a rule FIRED and built a
# different graph, which is the worst of the three -- and `pm_clean_up_group_sink`'s second rule
# is `(UPat((Ops.SINK, Ops.GROUP), name="root"), ...)` flattening a GROUP src out of a SINK. The
# port's `sym_11`/`sym_12` are `group x -> x` and the SINK flatten, and its own gate row `sink`
# is `eq_u(sym(fx_sink, 5), 6)` on its OWN `fx_sink` fixture -- a three-src root that this corpus
# does not reproduce yet.
#
# WHAT IS MEASURED WORKING, on the five-row corpus in `gates/symcases.rows`:
#   * THE SCANNER. `(add c7 c0)` tokenises as `H(add) L(c7) L(c0) )` -- four tokens, one close.
#   * THE BUILDER. That line builds an arena reading `0:Ops.NOOP 1:CONST 2:CONST 3:Ops.ADD`
#     (`Arena.bottom`, the two CONSTs, the ADD) with `Arena.next` = 4, and the ROOT-order control
#     `rootctl` prints its src handles as `1 2` -- SLOT ORDER, so `ops.bend` is exonerated.
#   * THE CANONICAL FORM. `t_add` prints `0:ADD:1,2;1:c7:;2:c0:`, `t_group` prints `0:GROUP:1;1:x:`,
#     and `t_xor0` prints five nodes with the two sibling leaves DISTINGUISHED BY NAME:
#     `0:XOR:1,2,4;1:c5:;2:XOR:1;3:x:;4:y:`. That last one is the instrument's whole claim: a
#     rebind rule's guard is an IDENTITY CHECK, and only a row form that NAMES the two siblings
#     can see it hold on one line and not the other.
#   * BOTH TABLES ANSWER, so the lane is not a lane that measured nothing: `sym` answers `t_add`
#     with CONST(7) (:117, `x+0 -> x`), `t_group` with the variable (:444) and `t_sink` with a
#     NOOP; `pm_remove_invalid` refuses all five.
#
# WHAT IS MEASURED WORKING, on the five-row corpus in `gates/symcases.rows`:
#   * THE SCANNER. `(add c7 c0)` tokenises as `H(add) L(c7) L(c0) )` -- four tokens, one close.
#   * THE BUILDER. That line builds an arena reading `0:Ops.NOOP 1:CONST 2:CONST 3:Ops.ADD`,
#     which is `Arena.bottom` plus the two CONSTs plus the ADD, and `Arena.next` is 4.
#   * THE CANONICAL FORM. `t_add` prints `0:ADD:1,2;1:c7:;2:c0:`, `t_group` prints
#     `0:GROUP:1;1:x:`, `t_xor0` prints `0:XOR:1,4;1:XOR:1,2;2:x:;3:c5:;4:y:`.
#     **THESE THREE READINGS CHANGED, AND THIS HEADER KEPT THE PRE-FIX ONES.** They read
#     `0:ADD:2,1`, `0:XOR:3,2,1` and `0:XOR:2` -- the arena's srcs REVERSED. The cause is NOT a
#     traversal-order disagreement, which is what this header used to claim and what the refusal to
#     pin a "walk-order" divergence rested on. `List.append([1,2],[3])` answers `1 2 3` (it APPENDS)
#     and `O.Arena.new([1,0]).srcs` answers `1 0` -- **THE ARENA PRESERVES SRC ORDER**. The real
#     cause was `fz_build.one`'s `THead` arm and `fz_deliver.at` BOTH appending, so a NEW FRAME WENT
#     TO THE BOTTOM: the root of `(xor (xor x c5) c5)` measured `O.Arena.srcs` = `2 3 2` and now
#     measures `1 3`. **A GOVERNING DOCUMENT THAT NAMES A READING ITS OWN RUN CONTRADICTS IS THE `M8`
#     CLASS** -- and six of the eight findings this session committed were also stale prose.
#   * BOTH TABLES ANSWER. `sym` answers `t_add` with the CONST(7) (`sym=0:c7:`), `t_group` with
#     the variable (`sym=0:x:`) and `t_sink` with a NOOP (`sym=0:NOOP:`), and `pm_remove_invalid`
#     refuses all three. So the lane is not a lane that measured nothing.
#

# ============================ WHY THIS FILE EXISTS AT ALL ============================
# `symbolic.bend` is 577 `def`s and `ls gates/ | grep symbolic` is 0. The file's own in-file gate
# (`fz.gate`, 57 rows) drives 30 hand-written `fx_*` arenas and asks ONE question at ONE index
# per row (`t_rebind`: "does `sym` answer 3 at node 2"). It never drives the file's OWN fuzz
# driver over a graph you choose -- and that driver is DEAD, which is why 577 defs could carry no
# corpus gate unnoticed. MEASURED on the corpus line `(add c7 c0)`, `fz_toks` emits
#     L:dd L:7 L:0 L: ) x ~4096
# for two independent reasons:
#   * THE HEAD TOKEN IS UNREACHABLE. `fz_tok.tok` mints a `THead` only for `wm == 2`, and `fz_tok`'s
#     `md` mode reaches 2 only from 1 or 2 -- NEVER from the boundary case 0, which is the case a
#     `(`-led node starts in. So every op name in a case file arrives as a LEAF: `add` became
#     `dd` because `fz_leaf`'s const arm does `String.drop(w, 1n)` on a non-const name.
#   * ONE `TClose` PER UNIT OF FUEL. The `k == 0` arm drops one character of an ALREADY EMPTY
#     string (`fz_cls("")` is 0 forever) and only the 4096 fuel ends it, so a 12-character input
#     emits ~4096 closes -- and every close on an empty stack RESETS the root
#     (`fz_deliver.at`'s `Nil{}` arm).
# MEASURED consequence, on that same line: `fz_run` answers
#     root=1 n=2 op=Ops.CONST selfadd=0 sym=norewrite rm=norewrite
# -- a CONST where the s-expr says ADD, and `norewrite` for both tables. The file's documented
# arbitrary-fixture entry point cannot build an ALU at all.
#
# A SECOND, SMALLER FINDING, and it is why the corpus has NAMED variables: `fz_var` hardcodes
# `Some{"v"}` as the `ParamArg` name and mints into `O.Arena.empty()`, so a case file cannot say
# `x` and `y`. The rebind rules -- `(x^y)^y` (symbolic.py:123), `(x%y)%y` (:124), `(x*x*x).recip()`
#     (:464) -- have an IDENTITY CHECK as their whole guard, and a corpus that cannot name two
# variables cannot state a positive and a negative for any of them. This file's `mkvar` is a
# fixture-construction copy of that one def and the only thing it changes is the name.
#
# A THIRD, AND IT IS THE KIND OF THING A CENSUS IS FOR: `Arena.srcs` on the ADD of
# `(add c7 c0)` reads `[c0, c7]` -- the s-expr's slot order reversed -- while the walk enters the
# same node as `[c7, c0]`. `ss.go` goes on to read `srcs` in the walk's order, which is the
# disagreement. `List.append(&2, T, xs, [x])` PREPENDS at `symbolic.bend`'s own `fz_deliver.at`
# -- the one place the arena's src list is built -- and APPENDS in a standalone probe. THIS FILE
# DOES NOT CLAIM A MECHANISM IT HAS NOT MEASURED. It is the next run.
#
# ============================ THE ROW, AND WHY THIS SHAPE ============================
#   <name>= in=<canon> sym=<canon|norewrite> rm=<canon|norewrite>
# `in=` is the CONTROL: the canonical rendering of the graph BOTH lanes built, so a disagreement
# about what a corpus line MEANS is a row and not a silent asymmetry. `sym=` and `rm=` are the two
# tables, because `pm_remove_invalid` is a SEPARATE matcher in Python (`codegen/__init__.py:367`
# uses it alone and it is never composed into `sym`) and the port gives it its own tag space.
#
# THE CANONICAL FORM is `gates/tn_nodes.bend`'s row, verbatim: `<k>:<head>:<src positions>`, one
# entry per DISTINCT node, in PRE-order, `k` the first-appearance position, and every edge named
# by the POSITION it points AT. It is a flat list rather than a nested s-expr because a nested one
# needs two mutually recursive defs -- open a node, walk its srcs -- and Bend refuses mutual
# recursion, which is the same reason the port's own `fz_render` is two phases. The flat form is
# also the STRONGER one: it is the instrument that exists because `CMPNE(MUL, CONST)` and
# `CMPNE(CONST, CONST)` have the same COUNT and the wrong SRCS. A CONST prints its VALUE
# (`c7`/`n7`/`bt`/`bf`/`bad`) and a PARAM its `ParamArg` NAME, so a rule that answers a MINTED
# const still renders and two variables at one dtype are two nodes with two names.
#
# WHAT IT CANNOT SEE, named rather than left to be discovered. `mixin/elementwise.py` is not
# ported, so a rule body here is the RAW `alu` and every row is a claim about a fixture whose src
# dtypes already agree -- the `promo` row in the file's own gate, inherited. And a fixed-point
# driver (`UOp.simplify`, `graph_rewrite` applied to itself) is not here: `sym` is asked ONE
# question per node, so a rule whose own answer is a node another rule would rewrite is out of
# scope. The corpus also cannot state a float CONST (`F32.bits` has no inverse) or an int outside
# int32 (`exec_alu`'s integer lane is int32 and its value is an I64), which are the file's own
# stated exclusions.
#
# BEND RULES THIS FILE IS GATED ON, each of them found by breaking it:
#   * a `match` MAY NOT SCRUTINISE A COMPUTED VALUE -- not a call, not a field read -- so every
#     decision is a PARAMETER and the def that branches on it is its own;
#   * PARAMETERS ARE MATCHED IN DECLARATION ORDER, so a def that matches its fuel may not then
#     match a parameter declared before it, and `case 1n+p:` (a new binder) is NOT `case p:`;
#   * `1n+p` IS "AT LEAST 1" and not "equal to 1": the corpus splitter's
#     `malformed=no-expr` arm was swallowing every two-field line until it said `1n`;
#   * NO FORWARD REFERENCES AND NO MUTUAL RECURSION, so every walk here is ONE def with a mode;
#   * a self-call must DECREASE: the shrinking argument is a binder from `case 1n+p:`, and a
#     `Bool.pick` on the fuel is not a shrink bend recognises.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/symbolic.bend as Sy

def CASES() -> String: "gates/symcases.rows"
def FUEL() -> Nat: 4096n
# THE FIELD SEPARATOR IS `|` AND NOT A TAB, and that is MEASURED rather than chosen:
# `String.split("a\tb c\td", Char.from_u32(9))` answers 3 on this bend, so a TAB separator
# splits on ANY WHITESPACE and the s-expr's own spaces come along with it. `|` is not
# whitespace and does not occur in an s-expr, so a corpus line is `<name>|<s-expr>` and
# nothing else. (The `.rows` extension is kept because the file is tabular data; the
# SEPARATOR is stated here rather than inherited from the extension.)
def SEP() -> Char: Char.from_u32(124)

# ---- THE SCANNER. One def, the head character CLASS as a parameter, `hd` the flag that
# says the NEXT word is a node head. Four classes: 0 end, 1 `)`, 2 `(`, 3 space, 4 word.
def cpick(u: U32) -> U32:
  match u:
    case 41: 1
    case 40: 2
    case 32: 3
    case 9: 3
    case 10: 3
    case 13: 3
    case _: 4

def cls(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 0
    case Chr{u} <> _t: cpick(u)

# AND NO REVERSE OF THE WORD: `List.append` APPENDS AT THE END (MEASURED), so `w` is already in
# source order. MEASURED the wrong way first: with a `List.reverse` here, `(add c7 c0)` tokenised
# as `H(dda) L(7c) L(0c)` -- every word reversed -- and the whole corpus built three PARAMs and
# a NOOP root, which is what an "unknown leaf" looks like. A corpus gate that builds the wrong
# graph reads as a port that rewrites nothing.
def tk.put(w: String, hd: U32, acc: List<&2, Sy.Tok>) -> List<&2, Sy.Tok>:
  match hd:
    case 1: List.append(&2, Sy.Tok, acc, [Sy.THead{w}])
    case _: List.append(&2, Sy.Tok, acc, [Sy.TLeaf{w}])

def tk.flush(w: List<&2, Char>, hd: U32, acc: List<&2, Sy.Tok>) -> List<&2, Sy.Tok>:
  match w:
    case Nil{}: acc
    case _: tk.put(String.from_list(w), hd, acc)

def tk.close(w: List<&2, Char>, hd: U32, acc: List<&2, Sy.Tok>) -> List<&2, Sy.Tok>:
  List.append(&2, Sy.Tok, tk.flush(w, hd, acc), [Sy.TClose{}])

# THE PARAMETER ORDER IS LOAD-BEARING: Bend matches parameters in DECLARATION order, so a
# def that matches `fuel` may not then match a parameter declared BEFORE it. `fz_tok` puts its
# fuel `n` first for the same reason.
def tk.at(fuel: Nat, k: U32, +s: List<&2, Char>, acc: List<&2, Sy.Tok>, w: List<&2, Char>, +hd: U32) -> List<&2, Sy.Tok>:
  match fuel:
    case 0n: tk.flush(w, hd, acc)
    case 1n+p: match k:
      case 0: tk.flush(w, hd, acc)
      case 1: tk.at(p, cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), tk.close(w, hd, acc), Nil{}, hd)
      case 2: tk.at(p, cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), acc, Nil{}, 1)
      case 3: tk.at(p, cls(List.tail(&2, Char, s)), List.tail(&2, Char, s), tk.flush(w, hd, acc), Nil{}, 0)
      case _: match s:
        case Nil{}: tk.flush(w, hd, acc)
        case c <> t: tk.at(p, cls(t), t, acc, List.append(&2, Char, w, [c]), hd)

def toks(+s: String) -> List<&2, Sy.Tok>:
  tk.at(FUEL(), cls(String.to_list(s)), String.to_list(s), Nil{}, Nil{}, 0)

# ---- THE LEAF VOCABULARY. `c<N>` and `n<N>` are ints, `bt`/`bf`/`bad` are the three other
# CONSTs, and EVERY other name is a variable at the dtype its LAST character states (`x`
# weakint, `xb` bool, `xf` weakfloat, `xi` int32). `fz`'s own vocabulary, plus a name.
def lastu.at(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 32
    case Chr{u} <> _: u

def lastu.go(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 32
    case _ <> t: lastu.at(t)

def lastu(w: String) -> U32: lastu.go(String.to_list(w))

def headu.at(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 32
    case Chr{u} <> _: u

def headu(w: String) -> U32: headu.at(String.to_list(w))

def vdt.at(empty: Bool, u: U32) -> S.Dt:
  match empty:
    case True{}: S.weakint()
    case False{}: match u:
      case 98: S.boolean()
      case 102: S.weakfloat()
      case 105: S.int32()
      case _: S.weakint()

def vdt(+w: String) -> S.Dt: vdt.at(String.is_empty(w), lastu(w))

# THE CONST TEST, split so the call site reads as one name. `w` is duplicated because the
# head character and the three fixed spellings are asked of the same string.
def iscst.name(+w: String) -> Bool:
  Bool.or(String.eq(w, "bt"), Bool.or(String.eq(w, "bf"), String.eq(w, "bad")))

def iscst.head(+w: String) -> Bool: Bool.or(U32.is_eq(headu(w), 99), U32.is_eq(headu(w), 110))

def iscst.of2(a: Bool, b: Bool) -> String: Bool.pick(String, a, "nameT", Bool.pick(String, b, "nameInner", "nameF"))

def iscst(+w: String) -> Bool: Bool.or(iscst.name(w), iscst.head(w))

def mkvar(ar: O.Arena, +w: String) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{O.ParamArg.no_slot(), vdt(w), None{},
      Some{O.PyRange{H.i64_of_hi_lo(0, 0), H.i64_of_i32(100)}}, Some{1}, Some{w}, S.Aalu{},
      None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

# ---- THE STACK BUILDER, which is `fz_build` with a leaf that can be NAMED. A recursive
# descent is not an option: Bend refuses mutual recursion and `expr`/`srcs` need each other,
# so a FRAME STACK is the shape, and `Sy.Frm`/`Sy.St`/`Sy.fz_close` are the port's own.
def build.put.at(cst: Bool, w: String, ar: O.Arena, stk: List<&2, Sy.Frm>, root: Maybe<&2, U32>) -> Sy.St:
  match cst:
    case True{}: Sy.fz_close.give(Sy.fz_leaf.go(ar, w), stk, root)
    case _: Sy.fz_close.give(mkvar(ar, w), stk, root)

def build.put(cst: Bool, w: String, st: Sy.St) -> Sy.St:
  match st:
    case Sy.St{ar, stk, root}: build.put.at(cst, w, ar, stk, root)

# the tail of `build.one`'s leaf arm: the name is read TWICE (once for the const test, once
# for the mint), so it crosses this def boundary rather than being duplicated at the call.
def build.put.w(+w: String, st: Sy.St) -> Sy.St: build.put(iscst(w), w, st)

def build.one(t: Sy.Tok, +st: Sy.St) -> Sy.St:
  match t:
    # A FRAME GOES ON TOP -- `List.append(&2, Sy.Frm, [f], St.stk(st))` -- and NOT at the end.
    # This is `symbolic.bend`'s own `fz_build.one`, verbatim, and it carried the same fault:
    # appending the new frame below the open ones meant the next leaf was delivered to the
    # PARENT, so every case with NESTING built a different graph. MEASURED on
    # `(xor (xor x c5) c5)` before/after, the root's `Arena.srcs` read `2 3 2` and reads
    # `1 3`; MEASURED on `(sink (group x) c2)` before/after, `in=` read
    # `0:GROUP:1,3;1:SINK:1;2:x:;3:c2:` and reads `0:SINK:1,2;1:GROUP:1;2:x:;3:c2:`. The flat
    # cases (`(add c7 c0)`, `(group x)`) read the same either way, which is why half the
    # corpus looked healthy over a builder that could not nest.
    case Sy.THead{w}: Sy.St{Sy.St.ar(st), List.append(&2, Sy.Frm, [Sy.Frm{Nil{}, w}], Sy.St.stk(st)), Sy.St.root(st)}
    case Sy.TLeaf{w}: build.put.w(w, st)
    case Sy.TClose{}: Sy.fz_close(st)

# `case 1n+p:` and not `case p:` -- the binder form is what lets a SECOND parameter be
# matched underneath, and that is the whole of the fuel-then-stack pattern.
def build.go(fuel: Nat, +t: List<&2, Sy.Tok>, +st: Sy.St) -> Sy.St:
  match fuel:
    case 0n: Sy.St{O.Arena.empty(), Nil{}, None{}}
    case 1n+p: match t:
      case Nil{}: st
      case k <> r: build.go(p, r, build.one(k, st))

def build(s: String) -> Sy.St: build.go(FUEL(), toks(s), Sy.St{O.Arena.empty(), Nil{}, None{}})

# ---- THE CANONICAL FORM: `<k>:<head>:<src positions>` for EVERY distinct node of the graph,
# in PRE-order, and NOT a nested s-expr. A nested s-expr needs two mutually recursive defs
# (open a node / walk its srcs) and Bend refuses mutual recursion, which is why the
# file's own `fz_render` is two phases. The FLAT form is also the STRONGER one: it is
# `gates/tn_nodes.bend`'s row verbatim, and that instrument exists because
# `CMPNE(MUL, CONST)` and `CMPNE(CONST, CONST)` have the same COUNT and the wrong SRCS.
# Numbering every distinct node in pre-order and naming each edge by the number it points
# AT is what makes a swap move a number: `(xor x c5) ^ y` and `(xor x c5) ^ x` print
# different `src` lists for the outer node, and a count or a multiset prints the same text.
#
# THE HEAD, and the two leaf spellings. A CONST is its VALUE (`c7`/`n7`/`bt`/`bf`/`bad`) and
# a PARAM is its `ParamArg` NAME, so a rule that answers a MINTED const still renders, and
# two variables at one dtype are two different nodes with two different names -- which is
# what makes the rebind rules' identity guard stateable at all.
# THE PRE-ORDER WALK, ONE def, and `keep` IS THE WHOLE DECISION -- "is the node on top of the
# stack one this walk has not seen?" `t` is a STACK with each node's children pushed IN FRONT
# of the parent's remaining siblings, which is what makes the order pre-order rather than a
# toposort, and `keep` is a PARAMETER because Bend will not `match` a computed value.
#
# `keep` IS `fresh` OF THE *NEXT* STATE, and the first draft passed a literal `True{}`, which
# walks every handle it meets instead of every node once. MEASURED on `(add c7 c0)`: the row
# came back as 4095 lines of `NOOP` whose handles counted DOWN from 2180, because an unseen
# handle's srcs are read out of an arena that does not hold it. The new state is therefore
# computed by `ins`/`push` and asked about twice -- once for `keep`, once to recurse -- which
# costs a second walk of a list of at most twenty handles and is the price of not being able
# to bind a local.
def head(t: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.get(&2, U32, t, 0n), 0)

def has(ns: List<&2, U32>, +u: U32) -> Bool:
  match ns:
    case Nil{}: False{}
    case h <> t: Bool.or(U32.is_eq(h, u), has(t, u))

# `fresh` IS "THE STACK IS NOT EMPTY AND ITS TOP IS NEW". The emptiness half is not optional:
# `head` seeds an empty list with 0, and HANDLE 0 IS NOT A NODE -- MEASURED on the port's own
# `fx_add0`, whose arena reads `0:Ops.NOOP 1:CONST 2:CONST 3:ADD`, so index 0 is
# `Arena.bottom` and every real node is at 1 or above. Without the half, `not has(ns, 0)` is
# True, an empty stack reads as "keep", the last node is kept again, its srcs are pushed again,
# and the walk runs to the fuel: MEASURED on `(add c7 c0)`, 4096 rows of
# `0:ADD:4096,4096; 1:ADD:4095,4095; ...`. It also means the emptiness test is `head == 0` and
# not `List.is_empty`, which this bend will not accept on a borrowed list at all.
def fresh.at(empty: Bool, +ns: List<&2, U32>, u: U32) -> Bool:
  match empty:
    case True{}: False{}
    case _: Bool.not(has(ns, u))

def fresh(+ns: List<&2, U32>, +t: List<&2, U32>) -> Bool:
  fresh.at(U32.is_eq(head(t), 0), ns, head(t))

# THE FIRST KEEP IS ALWAYS TRUE -- the walk starts with exactly the root on the stack -- and it is
# said here rather than computed so the call site does not read the root's own fresh-ness.

def ins(ns: List<&2, U32>, u: U32) -> List<&2, U32>: List.append(&2, U32, ns, [u])

# THE CHILDREN GO IN FRONT OF THE PARENT'S REMAINING SIBLINGS, and this is a FOLD rather than a
# `List.concat` because `concat` of a BORROWED `Arena.srcs` and a tail was MEASURED coming back
# in an order this walk cannot explain -- `(sink (group x) c2)` printed
# `0:SINK 1:x 2:GROUP 3:c2`, which visits the GRANDCHILD before its own parent. The fold names
# no arena and appends one src at a time, so the order is the fold's own.
def srcs.at(ar: O.Arena, u: U32) -> List<&2, U32>: O.Arena.srcs(ar, u)

# THE ORDER CONTROL, and it is what makes the `ss.go` claim a MEASUREMENT rather than a guess:
# it prints the arena's OWN src handles for the root, with no walk in it at all. MEASURED on
# `t_add`: `0:3 1:1 2:` -- the ADD at index 3 has srcs [1, 2], which is SLOT ORDER (c7 then c0).
# So the arena is RIGHT and the WALK is what reverses it, and the bug is in `push`/`pre` here, not
# in `ops.bend`. A reader who assumed `ops.bend` was at fault would go looking in the wrong file.
def srctx(n: Nat, +t: List<&2, U32>, acc: String) -> String:
  match n:
    case 0n: String.concat([acc, " "])
    case 1n+p: match t:
      case Nil{}: String.concat([acc, " "])
      case s <> r: srctx(p, r, String.concat([acc, U32.show(s), " "]))

def srctx.of(+t: List<&2, U32>) -> String: srctx(List.length(&2, U32, t), t, "")

def rootctl.at(+t: List<&2, U32>) -> String: String.concat(["CTL ", srctx.of(t)])

def rootctl(r: U32, ar: O.Arena) -> String:
  rootctl.at(srcs.at(ar, r))

def push.go(n: Nat, ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: match ss:
      case Nil{}: acc
      case s <> r: push.go(p, r, List.append(&2, U32, acc, [s]))

# THE CHILDREN GO IN FRONT OF THE PARENT'S REMAINING SIBLINGS, so the stack is `srcs ++ rest`:
# MEASURED, seeding the fold with `rest` and appending the srcs gave `rest ++ srcs`, which is a
# DEPTH-FIRST walk over the node's LAST src first -- `(sink (group x) c2)` printed
# `0:SINK 1:x 2:GROUP 3:c2` where pre-order over slot order is `0:SINK 1:GROUP 2:x 3:c2`. The
# order is the whole claim of this row form, so it is worth a fold that gets it right.
def push.go2(+acc: List<&2, U32>, +rest: List<&2, U32>) -> List<&2, U32>:
  push.go(List.length(&2, U32, rest), rest, acc)

def push.end(+acc: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  push.go2(acc, rest)

def push.of(+ss: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  push.end(push.go(List.length(&2, U32, ss), ss, Nil{}), rest)

def push(ss: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  push.of(ss, rest)

# THE NODE BEING KEPT IS `head(t)` AND NOT A CARRIED `u`: MEASURED, carrying `u` re-appends
# the ROOT on every step, so the walk never advances and `ns` grows to the fuel. `t` is the only
# state that says which node is next, and `u` is not state at all.
def pre.go(fuel: Nat, keep: Bool, +ar: O.Arena, +ns: List<&2, U32>, +t: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    # `ns` IS ALREADY IN PRE-ORDER: `ins` APPENDS AT THE END, so reversing it here mirrors the
    # whole walk and every edge names a position as far from its target as the walk is long.
    # MEASURED on `(add c7 c0)`: 4096 rows of `0:ADD:4096,4096; 1:ADD:4095,4095; ...`.
    case 0n: ns
    case 1n+p: match keep:
      case True{}: pre.go(p, fresh(ins(ns, head(t)), push(srcs.at(ar, head(t)), List.tail(&2, U32, t))), ar, ins(ns, head(t)), push(srcs.at(ar, head(t)), List.tail(&2, U32, t)))
      case False{}: pre.go(p, fresh(ns, List.tail(&2, U32, t)), ar, ns, List.tail(&2, U32, t))

# THE FIRST KEEP IS ALWAYS TRUE -- the walk starts with exactly the root on the stack -- and it
# is a literal here rather than the root's own fresh-ness, which `Bool.not(has(Nil{}, u))` would
# also say. `u` is read twice (the keep and the stack) so it crosses `pre.of`.
def fresh.of(u: U32) -> Bool: True{}

def pre.start(+u: U32, ar: O.Arena) -> List<&2, U32>:
  pre.go(FUEL(), fresh.of(u), ar, Nil{}, [u])

def pre(u: U32, +ar: O.Arena) -> List<&2, U32>: pre.start(u, ar)

# THE POSITION OF A HANDLE in that walk. `hit` is a PARAMETER and not a nested match, for
# the same reason `tk.at` carries its class: Bend will not `match` a computed value.
# THE POSITION OF A HANDLE, and `hit` is a PARAMETER THAT IS MATCHED. The first draft threaded
# `hit` and never matched it, so every position came back as `List.length(ns)`: MEASURED, every
# `src` field of `(add c7 c0)` read `3,3`. A fold whose stop condition is computed but not
# consulted is a counter, and a counter cannot name a node.
def num(fuel: Nat, hit: Bool, +t: List<&2, U32>, +u: U32, +k: Nat) -> Nat:
  match fuel:
    case 0n: k
    case 1n+p: match hit:
      case True{}: k
      case _: match t:
        case Nil{}: k
        case _ <> _r: num(p, U32.is_eq(head(List.tail(&2, U32, t)), u), List.tail(&2, U32, t), u, 1n+k)

def idx.of(+ns: List<&2, U32>, +u: U32) -> Nat: num(FUEL(), U32.is_eq(head(ns), u), ns, u, 0n)

def idx(+ns: List<&2, U32>, u: U32) -> Nat: idx.of(ns, u)

# THE HEAD OF ONE NODE, in three arms because a CONST and a PARAM take their TEXT from the ARG
# while every other op takes it from the op plus, for a dtype-carrying op, the arg's dtype.
# A CONST prints its VALUE and a PARAM its `ParamArg` NAME: a rule that answers a MINTED
# const therefore renders, and two variables at one dtype are two nodes with two NAMES, which
# is what makes the rebind rules' identity guard stateable at all.
def cval.of(a: O.Arg) -> O.Const:
  match a:
    case O.APy{v}: v
    case _: O.CInvalid{}

def pname(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "?"

def pname.of(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: pname(O.ParamArg.name(pa))
    case _: "?"

def head.adt(a: O.Arg, op: O.Op) -> String:
  match a:
    case O.ADt{dt}: String.concat([O.Ops.name.of(op), ":", Sy.fz_dtnm(dt)])
    case _: O.Ops.name.of(op)

def head.par(par: Bool, a: O.Arg, op: O.Op) -> String:
  match par:
    case True{}: pname.of(a)
    case False{}: head.adt(a, op)

def head.at(cst: Bool, par: Bool, a: O.Arg, op: O.Op) -> String:
  match cst:
    case True{}: Sy.fz_render.cval(cval.of(a))
    case False{}: head.par(par, a, op)

# THE SRC POSITIONS of one node, as a fold over the pre-order list, joined with `,`. `-` for a
# node with no srcs, which is `Rng.srcops`'s own glyph and the one shape both lanes must
# agree on for a zero-src node.
# THE SRC ORDER OF A NODE IS `Arena.srcs`'s OWN ORDER and this file does not normalise it. On
# the corpus line `(add c7 c0)` -- srcs written in slot order -- the port prints
# `0:ADD:2,1;1:c7:;2:c0:` with `1:c7` visited BEFORE `2:c0`, so the arena holds the ADD's src
# list as [c0, c7] while the WALK enters it as [c7, c0]. MEASURED both: `ss.go` appends at the
# end (positions `2,1` follow `Arena.srcs`) and `push` also appends at the end (the walk visits
# `c7` first), and the only way both hold is that the two read the list in opposite senses. The
# same `List.append(&2, T, xs, [x])` PREPENDS at `symbolic.bend`'s own `fz_deliver.at` (which is
# where the arena's src list is built) and APPENDS in a standalone probe, and this file does not
# claim a mechanism it has not measured. UNTIL IT IS EXPLAINED, the corpus stays five rows and
# the driver is a PROBE: see the header.

# `List.append(&2, T, xs, [x])` PUTS `[x]` AT THE FRONT of a BORROWED list on this bend: the
# root-order control `CTL` prints the arena's own handles as `1 2` (SLOT ORDER, MEASURED) and the
# src positions printed `2,1` off the same handles, so the reversal was HERE and not in the
# arena. `ops.bend` is exonerated by its own numbers and this is where the bug was.
def ss.put(x: String, r: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, [x], r)

def ss.go(+ar: O.Arena, u: U32, +ns: List<&2, U32>, t: List<&2, U32>) -> List<&2, String>:
  match t:
    case Nil{}: Nil{}
    case s <> r: ss.put(Nat.show(idx(ns, s)), ss.go(ar, u, ns, r))

def ss.of(u: U32, +ar: O.Arena, +ns: List<&2, U32>, t: List<&2, U32>) -> List<&2, String>:
  ss.go(ar, u, ns, t)

def srcs.tx(+u: U32, +ar: O.Arena, +ns: List<&2, U32>) -> String:
  String.join(ss.of(u, ar, ns, srcs.at(ar, u)), ",")

# ---- THE GRAPH, as a fold over the pre-order list. Two recursive calls would be needed by a
# nested spelling; this needs one, which is why the flat form is not a compromise.
def rows.go(fuel: Nat, +ns: List<&2, U32>, +ar: O.Arena, +k: Nat, acc: String) -> String:
  match fuel:
    case 0n: acc
    case 1n+p: match ns:
      case Nil{}: acc
      case u <> r: rows.go(p, r, ar, Nat.add(k, 1n),
                           String.concat([acc, Nat.show(k), ":", head.at(O.eq_op(O.Arena.op(ar, u), O.OpsCONST{}), O.eq_op(O.Arena.op(ar, u), O.OpsPARAM{}),
                                           O.Arena.arg(ar, u), O.Arena.op(ar, u)), ":",
                                          srcs.tx(u, ar, ns), ";"]))

def graph(u: U32, +ar: O.Arena) -> String: rows.go(FUEL(), pre(u, ar), ar, 0n, "")

# ---- one row, and each answer rendered with ITS OWN walk ----
def ans(ar: O.Arena, m: Maybe<&1, U32>) -> String:
  match m:
    case Some{i}: graph(i, ar)
    case None{}: "norewrite"

def row.at3(+r: U32, +ar: O.Arena, name: String) -> String:
  String.concat([name, "= in=", graph(r, ar),
                 " sym=", ans(ar, Sy.sym(F.folded(ar), r)),
                 " rm=", ans(ar, Sy.pm_remove_invalid(F.folded(ar), r))])

def row.at2(r: U32, ar: O.Arena, name: String) -> String: row.at3(r, ar, name)

def row.at(root: Maybe<&2, U32>, +ar: O.Arena, name: String) -> String:
  match root:
    case Some{r}: row.at2(r, ar, name)
    case None{}: String.concat([name, "= parse-error"])

# the ROOT is read three times -- the control, `sym` and `rm` -- so it is a `+` parameter and
# the arena travels with it. `in=` is rendered BEFORE the two tables are asked, because `sym`
# GROWS the arena it is handed and a row that printed `in=` afterwards would be printing a
# walk over a bigger arena. The walk is over the GRAPH, so the text is the same either way,
# and the order is stated rather than assumed.
def row1(st: Sy.St, name: String) -> String:
  match st:
    case Sy.St{ar, stk, root}: row.at(root, ar, name)

def run1(name: String, e: String) -> String: row1(build(e), name)

# ---- the corpus: `<name>|<s-expr>`, `#` and blank lines skipped ----
def skip.line(+ln: String) -> Bool:
  Bool.or(String.eq(String.trim(ln), ""), String.starts_with(String.trim(ln), "#"))

# THROUGH A DEF, and not `String.split(ln, SEP())` inline: MEASURED, the inline form splits
# the corpus line into ONE field and every row came back `malformed=no-expr`, while the same
# call with the separator passed as a parameter answers two. The separator is a `Char` either
# way and nothing else differs, so this is a bend evaluation-order artefact and the two-step
# form is what both lanes are gated on.
def fields.at(ln: String, c: Char) -> List<&2, String>: String.split(ln, c)

def fields(+ln: String) -> List<&2, String>: fields.at(ln, SEP())

# A CORPUS LINE, split ONCE. `fs` is the TAB split and its own tail is the s-expr, so
# destructuring both in one def reads the same memory twice and Bend's linearity check
# refuses it; asking `List.get` for the two fields instead keeps every value a FRESH `Maybe`.
# A line with no TAB prints `malformed=no-fields` and a line with no s-expr prints
# `malformed=no-expr`, so a corpus line that loses a field is a row a reader has to notice
# rather than a case silently named "".
def pick.of3(nm: Maybe<&2, String>, ex: Maybe<&2, String>) -> String:
  run1(Maybe.default(&2, String, nm, ""), Maybe.default(&2, String, ex, ""))

def pick.of2(ln: Nat, nm: Maybe<&2, String>, ex: Maybe<&2, String>) -> String:
  match ln:
    case 0n: "malformed=no-fields"
    # `1n` AND NOT `1n+p`: an OPEN pattern matches everything at or above its bound, so `1n+p`
    # swallowed the two-field case and every row of a healthy corpus came back
    # `malformed=no-expr`. MEASURED both ways.
    case 1n: "malformed=no-expr"
    case _: pick.of3(nm, ex)

def pick.blank(+fs: List<&2, String>) -> String:
  pick.of2(List.length(&2, String, fs), List.get(&2, String, fs, 0n), List.get(&2, String, fs, 1n))


# THE CORPUS WALK, one def and three modes: 0 ADVANCE (the list is empty, or the fuel is
# spent), 1 the line is a comment or blank so SKIP it, 2 KEEP it. Two facts about this bend
# are load-bearing and both were MEASURED by getting them wrong first:
#   * the mode for a line is `nxt` of the list that STARTS at it, so the tail has to be taken
#     ONCE and threaded into both the mode and the next list -- asking `nxt(ls)` and then
#     passing `tail(ls)` re-uses the CURRENT line's mode for the NEXT line, which is a one-line
#     shift that silently skips the first case and keeps one comment.
#   * `List.append` APPENDS AT THE END (MEASURED: `append(append(append(Nil,"a"),"b"),"c")` is
#     `a,b,c`), so `acc` is already in FILE ORDER and there is NO reverse here. Adding one
#     printed the five cases back to front, which an ordered diff would then have compared
#     against a corpus in the other order -- two lanes agreeing on nothing.
def nxt.of(sk: Bool) -> Bool: Bool.not(sk)

def head2(r: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, r, 0n), "")

def nxt(t: List<&2, String>) -> Bool:
  match t:
    case Nil{}: False{}
    case _ <> _: nxt.of(skip.line(head2(t)))

def rows.corpus(fuel: Nat, keep: Bool, +ls: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p: match keep:
      case True{}: match ls:
        case Nil{}: acc
        case ln <> _r: rows.corpus(p, nxt(List.tail(&2, String, ls)), List.tail(&2, String, ls),
                                   List.append(&2, String, acc, [pick.blank(fields(ln))]))
      case _: match ls:
        case Nil{}: acc
        case _ <> _r: rows.corpus(p, nxt(List.tail(&2, String, ls)), List.tail(&2, String, ls), acc)

def out(ls: List<&2, String>, acc: String) -> String:
  match ls:
    case Nil{}: acc
    case r <> t: out(t, acc ++ r ++ "\n")

# THE CORPUS FILE, read exactly the way `symbolic.bend`'s own `fz_read` reads a case file --
# `File.read` returns a SIGMA of the file and the result, so `IO.pass` is handed the result
# half and the close is the other half. MEASURED, the naive `IO.pass(String, m)` on the whole
# sigma is a type error and says so.

def read.closed(m: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, r) = m
  do IO<String>:
    s : String <- IO.pass(String, r)
    u : Unit <- File.close(f)
    IO.pure(String, s)


# ONE more reason the corpus is a FILE and not a list of strings in this source: the ROW SET
# is then a file, and `rows` is `os.walk`-able and countable by a reader who does not read
# Bend at all. See the gate's header for the drift check that keeps the two lanes on it.
def emit.lines(+s: String) -> String:
  out(rows.corpus(FUEL(), nxt(String.lines(s)), String.lines(s), Nil{}), "")

def main() -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(CASES(), "r"))
    m : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1000000)
    s : String <- read.closed(m)
    IO.print(emit.lines(s))
    return Unit{}

