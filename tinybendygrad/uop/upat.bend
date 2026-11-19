# upat.bend -- tinygrad/uop/upat.py.
# WHAT THIS FILE IS. ops.bend builds the arena; this file is the COMPILER that
#     UPat --_get_clause--> a predicate tree --do_process_and--> normalised
# #  UPat compiled 
# the predicate tree is a tree, not an arena. Python builds the ir out of
# THE `(bool, dict)` BECOMES A `String`. `upat_compile` returns a Python closure
#   * `ctx` (the `dyn_lookup` dict) is a `List<&2, Bind>` THREADED through the
# `# exec` IS THE ONE OMISSION and it is the LAST step, so everything this file
# A PYTHON `raise` BECOMES A NODE, uniformly, and it is one node: `marker()`.
# THE FUEL is one unit per step and it is a BOUND, not an exact count: every
# `pm_proc` IS A FIXPOINT AND THAT IS LOAD-BEARING. `do_process_and` splices ONE
# THREE BEND RULES SHAPED THE SHAPE. (1) No mutual recursion: `A` may not call
# WHERE THE ORDER MOVED. Bend has no forward references, so the field readers

import Base
import ./../helpers.bend as H
import ./ops.bend as O
import ./../LAWS/spec.bend as S
type Lit is Data:
  LNone{}
  LText{s: String}
  LOps{ys: List<&2, O.Op>}
  LDt{ys: List<&2, S.Dt>}
  LArg{a: O.Arg}
  LInt{n: U32}


type C is Data:
  C{op: O.Op, lit: Lit, ss: List<&2, C>}

type Bind is Data:
  Bind{name: String, lit: Lit}

type Code is Data:
  Code{s: String, dyn: List<&2, Bind>}
# `x.arg[0]`: the format string of a CUSTOM and the text of a CUSTOMI, and the only `arg`
# read anywhere in the file. `Maybe` because `LNone` has no text.

def lit.text(l: Lit) -> Maybe<&2, String>:
  match l:
    case LText{s}: Some{s}
    case _ : None{}
# `text_of`, and CONST's `.val`, which `_get_clause` writes as an int and the INDEX rule
# reads back.

def text_of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: ""

def ctext(c: C) -> String:
  match c:
    case C{op, lit, k}: text_of(lit.text(lit))

def ctext.m(m: Maybe<&2, C>) -> String:
  match m:
    case Some{c}: ctext(c)
    case None{}: ""

def val_of(l: Lit) -> String:
  match l:
    case LInt{n}: U32.show(n)
    case _ : ""

def Bind.name(b: Bind) -> String:
  match b:
    case Bind{name, lit}: name

def Bind.lit(b: Bind) -> Lit:
  match b:
    case Bind{name, lit}: lit

def head1(ys: List<&2, U32>) -> Maybe<&2, U32>:
  match ys:
    case Nil{}: None{}
    case y <> t:
      match t:
        case Nil{}: Some{y}
        case _ <> _: None{}

def marker() -> C:
  C{O.OpsCONST{}, LInt{0}, Nil{}}


def fuel(pat: O.Pat) -> Nat:
  Nat.mul(List.length(&2, O.UPat, O.Pat.upats(pat)), 32n)

def base_clause() -> C:
  C{O.OpsCUSTOMI{}, LText{"uop"}, Nil{}}


def head1c(gs: List<&2, C>) -> C:
  match gs:
    case Nil{}: marker()
    case c <> _: c

# `frozenset` -- upat.py:25 and 36 both build `UOp(Ops.PYLITERAL,
#   * `wrap` (upat.py:121-126) is a `graph_rewrite` RULE, and a rule runs at most
#     (ops.py:1815), and ops.py:1774 says so in a comment. So one `a{n}` per
#     (upat.py:168-169) and the number is `len(ctx)` at first visit, so the scope
#   * UOps are HASH-CONSED on `(op, src, arg, tag, type(arg))` (ops.py:200;
#     ops.py:228-233: "structurally identical UOps are the same object and

def has_ops(+xs: List<&2, O.Op>, +ys: List<&2, O.Op>) -> Bool:
  match xs:
    case Nil{}: True{}
    case x <> t: Bool.and(List.contains(O.Op, O.eq_op, ys, x), has_ops(t, ys))

def has_dts(+xs: List<&2, S.Dt>, +ys: List<&2, S.Dt>) -> Bool:
  match xs:
    case Nil{}: True{}
    case x <> t: Bool.and(List.contains(S.Dt, O.eq_dt, ys, x), has_dts(t, ys))

def eq_lit(a: Lit, b: Lit) -> Bool:
  match a b:
    case LNone{} LNone{}: True{}
    case LText{x} LText{y}: String.eq(x, y)
    case LOps{+x} LOps{+y}: Bool.and(has_ops(x, y), has_ops(y, x))
    case LDt{+x} LDt{+y}: Bool.and(has_dts(x, y), has_dts(y, x))
    case LArg{x} LArg{y}: O.eq_arg(x, y)
    case LInt{x} LInt{n}: U32.is_eq(x, n)
    case _ _: False{}

def eq_csl(+xs: List<&2, C>, +ys: List<&2, C>, acc: Bool) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: acc
        case _ <> _: False{}
    case C{x, a, ss} <> t:
      match ys:
        case Nil{}: False{}
        case C{y, b, us} <> u: eq_csl(t, u,
          Bool.and(Bool.and(acc, Bool.and(O.eq_op(x, y), eq_lit(a, b))), eq_csl(ss, us, True{})))

def eq_c(x: C, y: C) -> Bool:
  eq_csl([x], [y], True{})

# flatands -- upat.py:12. `[x] if x.op is not AND else [y for s in x.src for y

def flatands.go(f: Nat, t: Maybe<&2, C>, +rest: List<&2, C>, acc: List<&2, C>) -> List<&2, C>:
  match f:
    case 0n: List.append(&2, C, acc, [marker()])
    case 1n+p:
      match t:
        case Some{c}:
          match c:
            case C{op, lit, ss}:
              match op:
                case O.OpsAND{}: flatands.go(p, None{}, ss, acc)
                case _ : List.append(&2, C, acc, [C{op, lit, ss}])
        case None{}:
          match rest:
            case Nil{}: acc
            case C{op, lit, k} <> more:
              +q = p
              a = List.concat(&2, C, [acc, flatands.go(q, Some{C{op, lit, k}}, Nil{}, Nil{})])
              flatands.go(q, None{}, more, a)

def flatands(t: C, f: Nat) -> List<&2, C>:
  flatands.go(f, Some{t}, Nil{}, Nil{})

# substitute -- ops.py:532 `UOp.substitute`, the one call in this file, in
# rest is rebuilt. `ops.py:532` is NOT PORTED as a UOp method (it is a

def substitute.put(hit: Bool, op: O.Op, lit: Lit, ss: List<&2, C>, rep: C) -> C:
  match hit:
    case True{}: rep
    case False{}: C{op, lit, ss}

def substitute.go(+ss: List<&2, C>, +it: C, +rep: C) -> List<&2, C>:
  match ss:
    case Nil{}: Nil{}
    case C{op, lit, k} <> t:
      a = substitute.go(t, it, rep)
      b = substitute.go(k, it, rep)
      List.append(&2, C, [substitute.put(eq_c(C{op, lit, k}, it), op, lit, b, rep)], a)

def substitute(t: C, +it: C, +rep: C) -> C:
  match t:
    case C{+op, +lit, +ss}: substitute.put(eq_c(C{op, lit, ss}, it), op, lit, substitute.go(ss, it, rep), rep)

def ge2(n: Nat) -> Bool:
  match n:
    case 2n+p: True{}
    case _ : False{}
# upat.py:79 -- the compiler refuses a clause with four OR branches, because

def ge4(n: Nat) -> Bool:
  match n:
    case 4n+p: True{}
    case _ : False{}

def op_clause.pick(two: Bool, ys: List<&2, O.Op>, base: C, many: String, one: String) -> List<&2, C>:
  match two:
    case True{}: [C{O.OpsCUSTOM{}, LText{many}, [base, C{O.OpsPYLITERAL{}, LOps{ys}, Nil{}}]}]
    case False{}: [C{O.OpsCUSTOM{}, LText{one}, [base, C{O.OpsPYLITERAL{}, LOps{ys}, Nil{}}]}]

def op_clause.of(ops: Maybe<&2, List<&2, O.Op>>, base: C) -> List<&2, C>:
  match ops:
    case Some{+ys}: op_clause.pick(ge2(List.length(&2, O.Op, ys)), ys, base, "{0}.op in {1}", "{0}.op is {1}")
    case None{}: Nil{}
# scalar, it is what `coalesce.py:105`'s `UPat(arg=4)` is, and it is disjoint

def arg_int(a: O.Arg) -> Maybe<&2, U32>:
  match a:
    case O.ANone{}: None{}
    case O.ADt{_}: None{}
    case O.APy{_}: None{}
    case O.AParam{_}: None{}
    case O.ACall{_}: None{}
    case O.ACustom{_}: None{}
    # `AOpLit` is the UNPAIRED `Op` -- the port's spelling of `upat.py:26`'s
    case O.AOpLit{_}: None{}
    case O.AKernel{_}: None{}
    case O.AProgram{_}: None{}
    case O.ARange{_, _}: None{}
    case O.AReduce{_, _}: None{}
    case O.AWmma{_, _, _, _}: None{}
    case O.ATuple{ys}: head1(ys)
    case O.ABoolList{_}: None{}
    case O.AStr{_}: None{}
    case O.AInk{_, _}: None{}
    case O.AAllred{_, _}: None{}
    case O.ADev{_}: None{}
    case O.ABlob{_}: None{}
    case O.AInt{i}: Some{i}
    case O.AFloat{_}: None{}
    case O.ABad{}: None{}

def arg_clause.hit(m: Maybe<&2, U32>, a: O.Arg, base: C) -> List<&2, C>:
  match m:
    case Some{n}: [C{O.OpsCUSTOM{}, LText{String.concat(["{0}.arg == ", U32.show(n)])}, [base]}]
    case None{}: [C{O.OpsCUSTOM{}, LText{"{0}.arg == {1}"}, [base, C{O.OpsPYLITERAL{}, LArg{a}, Nil{}}]}]

def arg_clause.of(a: Maybe<&2, O.Arg>, base: C) -> List<&2, C>:
  match a:
    case Some{+x}: arg_clause.hit(arg_int(x), x, base)
    case None{}: Nil{}

def len_clause.mid(strict: Bool) -> String:
  match strict:
    case True{}: " == "
    case False{}: " >= "

def len_clause.of(want: Bool, strict: Bool, req: U32, base: C) -> List<&2, C>:
  match want:
    case True{}: [C{O.OpsCUSTOM{},
      LText{String.concat(["len({0}.src)", len_clause.mid(strict), U32.show(req)])}, [base]}]
    case False{}: Nil{}

def name_clause.of(n: Maybe<&2, String>, base: C) -> List<&2, C>:
  match n:
    case Some{s}: [C{O.OpsSTORE{}, LNone{}, [C{O.OpsCUSTOMI{}, LText{s}, Nil{}}, base]}]
    case None{}: Nil{}

def dt_clause.pick(two: Bool, ys: List<&2, S.Dt>, base: C, many: String, one: String) -> List<&2, C>:
  match two:
    case True{}: [C{O.OpsCUSTOM{}, LText{many}, [base, C{O.OpsPYLITERAL{}, LDt{ys}, Nil{}}]}]
    case False{}: [C{O.OpsCUSTOM{}, LText{one}, [base, C{O.OpsPYLITERAL{}, LDt{ys}, Nil{}}]}]

def dt_clause.of(md: Maybe<&2, List<&2, S.Dt>>, base: C) -> List<&2, C>:
  match md:
    case Some{+ys}: dt_clause.pick(ge2(List.length(&2, S.Dt, ys)), ys, base, "{0}.dtype in {1}", "{0}.dtype is {1}")
    case None{}: Nil{}

def pieces(u: O.UPat, +base: C) -> List<&2, C>:
  match u:
    case O.UPat{op, md, arg, name, _, _, _, +strict, +req, _}:
      List.concat(&2, C, [op_clause.of(op, base), arg_clause.of(arg, base),
        len_clause.of(Bool.or(strict, U32.is_gt(req, 0)), strict, req, base),
        name_clause.of(name, base),
        dt_clause.of(md, base)])
# `base.index(i)`: an INDEX over the base and a CONST carrying the index. The CONST's dtype
# is `dtypes.from_py(i)` and no rule here reads it.

def base_index(base: C, k: U32) -> C:
  C{O.OpsINDEX{}, LNone{}, [base, C{O.OpsCONST{}, LInt{k}, Nil{}}]}

def it(depth: U32) -> C:
  C{O.OpsCUSTOMI{}, LText{String.concat(["ituop", U32.show(depth)])}, Nil{}}


def nth.of(hit: Maybe<&2, O.UPat>) -> O.UPat:
  match hit:
    case Some{u}: u
    case None{}: O.UPat{None{}, None{}, None{}, None{}, O.SNone{}, Nil{}, False{}, False{}, 0, Nil{}}

def nth(pat: O.Pat, n: U32) -> O.UPat:
  nth.of(List.get(&2, O.UPat, O.Pat.upats(pat), U32.to_nat(n)))

def alt_ys(a: O.UpAlt) -> List<&2, U32>:
  match a:
    case O.UpFixed{ys}: ys
    case O.UpRepeat{x}: [x]


def is_rep(a: O.UpAlt) -> Bool:
  match a:
    case O.UpFixed{_}: False{}
    case O.UpRepeat{_}: True{}

def more_alts(alts: List<&2, O.UpAlt>) -> List<&2, O.UpAlt>:
  match alts:
    case Nil{}: Nil{}
    case _ <> rest: rest

def alts_of(u: O.UPat) -> List<&2, O.UpAlt>:
  O.UPat.src(u)

# _get_clause -- upat.py:15. `UPat` -> the predicate tree.
# THE AND CLAUSE IS THE ACCEPTANCE TEST. upat.py:21 -- the clause collects
# `_get_clause` therefore lost one `if` of its EIGHT -- MEASURED, the count of

def one_alt(alts: List<&2, O.UpAlt>) -> Bool:
  match alts:
    case Nil{}: False{}
    case _ <> rest: List.is_empty(&2, O.UpAlt, rest)


def forked_of(alts: List<&2, O.UpAlt>) -> Bool:
  Bool.not(List.is_empty(&2, O.UpAlt, more_alts(alts)))

type Rp is Data:
  Rp{pred: List<&2, C>, extra: List<&2, C>}


def no_repeat(alts: List<&2, O.UpAlt>) -> Bool:
  match alts:
    case Nil{}: True{}
    case O.UpRepeat{_} <> _: False{}
    case O.UpFixed{_} <> t: no_repeat(t)

def broken_of.of(alts: List<&2, O.UpAlt>, any: Bool) -> Bool:
  match alts:
    case Nil{}: any
    case O.UpRepeat{_} <> t: Bool.not(List.is_empty(&2, O.UpAlt, t))
    case O.UpFixed{_} <> t: Bool.not(no_repeat(t))

def broken_of.of2(alts: List<&2, O.UpAlt>, any: Bool) -> Bool:
  broken_of.of(alts, any)

def broken_of(+u: O.UPat) -> Bool:
  broken_of.of2(O.UPat.src(u), O.UPat.is_any(u))


def child_base(any: Bool, rep: Bool, base: C, depth: U32, k: U32) -> C:
  match any rep:
    case True{} _: base
    case False{} True{}: it(depth)
    case False{} False{}: base_index(base, k)

def child_depth(any: Bool, rep: Bool, depth: U32) -> U32:
  match any rep:
    case True{} _: depth
    case False{} True{}: U32.add(depth, 1)
    case False{} False{}: depth

def and_one(+cs: List<&2, C>) -> C:
  Bool.pick(C, List.is_empty(&2, C, cs), C{O.OpsCUSTOMI{}, LText{"True"}, Nil{}}, C{O.OpsAND{}, LNone{}, cs})

def flat(gs: List<&2, List<&2, C>>) -> List<&2, C>:
  List.concat(&2, C, gs)


def or_true.put(pse: Bool, +ps: List<&2, C>, +cs: List<&2, C>) -> C:
  Bool.pick(C, Bool.and(pse, List.is_empty(&2, C, cs)), C{O.OpsCUSTOMI{}, LText{"True"}, Nil{}},
    C{O.OpsAND{}, LNone{}, List.append(&2, C, ps, cs)})

def or_true(+ps: List<&2, C>, +cs: List<&2, C>) -> C:
  or_true.put(List.is_empty(&2, C, ps), ps, cs)


def Rp.pred(r: Rp) -> List<&2, C>:
  match r:
    case Rp{pred, extra}: pred

def Rp.extra(r: Rp) -> List<&2, C>:
  match r:
    case Rp{pred, extra}: extra

def is_store.of(op: O.Op) -> Bool:
  match op:
    case O.OpsSTORE{}: True{}
    case _ : False{}

def is_store(c: C) -> Bool:
  match c:
    case C{op, lit, ss}: is_store.of(op)


def part.put(hit: Bool, c: C, +r: Rp) -> Rp:
  match hit:
    case True{}: Rp{Rp.pred(r), List.append(&2, C, Rp.extra(r), [c])}
    case False{}: Rp{List.append(&2, C, Rp.pred(r), [c]), Rp.extra(r)}

def part.go(+xs: List<&2, C>, r: Rp) -> Rp:
  match xs:
    case Nil{}: r
    case +c <> t: part.go(t, part.put(is_store(c), c, r))

def ne(ss: List<&2, C>) -> Bool:
  Bool.not(List.is_empty(&2, C, ss))

def contains_c(ks: List<&2, C>, k: C) -> Bool:
  List.contains(C, eq_c, ks, k)

type Sp is Data:
  Sp{srcs: List<&2, C>, ors: List<&2, C>, flat: Bool}


def loop.put(v: C, k: C, +f: C, +r: Rp) -> Rp:
  +idn: C = C{O.OpsCUSTOM{}, LText{"{0} is {1}"}, [v, f]}
  Rp{List.append(&2, C, Rp.pred(r), [idn]),
     List.append(&2, C, Rp.extra(r), [C{O.OpsSTORE{}, LNone{}, [k, f]}])}

def loop.srcs(ss: List<&2, C>, i: C, first0: C, +r: Rp) -> Rp:
  match ss:
    case Nil{}: r
    case +k <> vs:
      match vs:
        case Nil{}: r
        case +v <> _: loop.put(v, k, substitute(v, i, first0), r)

def loop.step(st: C, i: C, first0: C, +r: Rp) -> Rp:
  match st:
    case C{_, _, ss}: loop.srcs(ss, i, first0, r)

def loop.go(+sts: List<&2, C>, +i: C, +first0: C, r: Rp) -> Rp:
  match sts:
    case Nil{}: r
    case st <> t: loop.go(t, i, first0, loop.step(st, i, first0, r))

def rep_len(has: Bool, base: C) -> List<&2, C>:
  Bool.pick(List<&2, C>, has, [C{O.OpsCUSTOM{}, LText{"len({0}.src) != 0"}, [base]}], Nil{})

def rep_all(base: C, i: C, d: Rp) -> List<&2, C>:
  [C{O.OpsCUSTOM{}, LText{"all([{0} for {1} in {2}.src])"},
    [C{O.OpsAND{}, LNone{}, Rp.pred(d)}, i, base]}]

def get_clause.rep.put(+u: O.UPat, +base: C, i: C, +d: Rp) -> C:
  or_true(pieces(u, base),
    List.concat(&2, C, [Rp.extra(d), rep_len(ne(Rp.extra(d)), base), rep_all(base, i, d)]))

def get_clause.rep.of(+u: O.UPat, +base: C, depth: U32, +d: Rp) -> C:
  get_clause.rep.put(u, base, it(depth), d)

def get_clause.rep(+u: O.UPat, +base: C, +depth: U32, f: Nat, +gs: List<&2, List<&2, C>>) -> C:
  +d: Rp = part.go(flatands(and_one(flat(gs)), f), Rp{Nil{}, Nil{}})
  get_clause.rep.of(u, base, depth, loop.go(Rp.extra(d), it(depth), base_index(base, 0),
    Rp{Rp.pred(d), Nil{}}))

def Sp.srcs(s: Sp) -> List<&2, C>:
  match s:
    case Sp{srcs, ors, flat}: srcs

def Sp.ors(s: Sp) -> List<&2, C>:
  match s:
    case Sp{srcs, ors, flat}: ors

def Sp.flat(s: Sp) -> Bool:
  match s:
    case Sp{srcs, ors, flat}: flat

def split.step(op: O.Op, lit: Lit, k: List<&2, C>, +sp: Sp) -> Sp:
  match op:
    case O.OpsAND{}: Sp{List.concat(&2, C, [Sp.srcs(sp), k]), Sp.ors(sp), True{}}
    case O.OpsOR{}: Sp{Sp.srcs(sp), List.append(&2, C, Sp.ors(sp), [C{op, lit, k}]), Sp.flat(sp)}
    case _ : Sp{List.append(&2, C, Sp.srcs(sp), [C{op, lit, k}]), Sp.ors(sp), Sp.flat(sp)}

def split.go(+ss: List<&2, C>, sp: Sp) -> Sp:
  match ss:
    case Nil{}: sp
    case C{op, lit, k} <> t: split.go(t, split.step(op, lit, k, sp))

def prod.rows(+k: List<&2, C>, +s: List<&2, C>, out: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match k:
    case Nil{}: out
    case c <> t: List.append(&2, List<&2, C>, [List.append(&2, C, s, [c])], prod.rows(t, s, out))

def prod.step(+k: List<&2, C>, acc: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match acc:
    case Nil{}: Nil{}
    case s <> r: List.concat(&2, List<&2, C>, [prod.rows(k, s, Nil{}), prod.step(k, r)])

def prod.go(+ors: List<&2, C>, acc: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match ors:
    case Nil{}: acc
    case C{op, lit, k} <> t: prod.go(t, prod.step(k, acc))

def push.go(+xs: List<&2, C>, +stores: List<&2, C>, acc: List<&2, C>) -> List<&2, C>:
  match xs:
    case Nil{}: acc
    case C{op, lit, k} <> t:
      push.go(t, stores, List.append(&2, C, acc, [C{op, lit, List.append(&2, C, k, stores)}]))
# A DUPLICATE STORE IS AN IDENTITY CHECK. upat.py:101 -- the first store of a

type Ds is Data:
  Ds{ks: List<&2, C>, vs: List<&2, C>, out: List<&2, C>, dup: Bool}

def Ds.ks(d: Ds) -> List<&2, C>:
  match d:
    case Ds{ks, vs, out, dup}: ks

def Ds.vs(d: Ds) -> List<&2, C>:
  match d:
    case Ds{ks, vs, out, dup}: vs

def Ds.out(d: Ds) -> List<&2, C>:
  match d:
    case Ds{ks, vs, out, dup}: out

def Ds.dup(d: Ds) -> Bool:
  match d:
    case Ds{ks, vs, out, dup}: dup

def dup.first(+ks: List<&2, C>, +vs: List<&2, C>, +k: C) -> C:
  match ks:
    case Nil{}: marker()
    case j <> jt:
      match vs:
        case Nil{}: marker()
        case v <> vt: Bool.pick(C, eq_c(j, k), v, dup.first(jt, vt, k))

def dup.put(hit: Bool, k: C, v: C, +d: Ds) -> Ds:
  match hit:
    case True{}: Ds{Ds.ks(d), Ds.vs(d),
      List.append(&2, C, Ds.out(d), [C{O.OpsCUSTOM{}, LText{"{0} is {1}"}, [dup.first(Ds.ks(d), Ds.vs(d), k), v]}]), True{}}
    case False{}: Ds{List.append(&2, C, Ds.ks(d), [k]), List.append(&2, C, Ds.vs(d), [v]),
      Ds.out(d), Ds.dup(d)}

def dup.srcs(ss: List<&2, C>, +d: Ds) -> Ds:
  match ss:
    case Nil{}: d
    case +k <> vs:
      match vs:
        case Nil{}: d
        case v <> _: dup.put(contains_c(Ds.ks(d), k), k, v, d)

def dup.step(st: C, +d: Ds) -> Ds:
  match st:
    case C{_, _, ss}: dup.srcs(ss, d)

def dup.go(+sts: List<&2, C>, d: Ds) -> Ds:
  match sts:
    case Nil{}: d
    case st <> t: dup.go(t, dup.step(st, d))


def stores_of(+ks: List<&2, C>, +vs: List<&2, C>, out: List<&2, C>) -> List<&2, C>:
  match ks:
    case Nil{}: out
    case k <> kt:
      match vs:
        case Nil{}: out
        case v <> vt: List.append(&2, C, [C{O.OpsSTORE{}, LNone{}, [k, v]}], stores_of(kt, vt, out))
# `dedup` -- helpers.py:23, `list(dict.fromkeys(x))`, on clause nodes.

def dedup.put(hit: Bool, c: C, +acc: List<&2, C>) -> List<&2, C>:
  match hit:
    case True{}: acc
    case False{}: List.append(&2, C, acc, [c])

def dedup.go(+xs: List<&2, C>, +acc: List<&2, C>) -> List<&2, C>:
  match xs:
    case Nil{}: acc
    case +c <> t: dedup.go(t, dedup.put(contains_c(acc, c), c, acc))

type Rec is Data:
  Rec{ors: List<&2, C>, d: Ds, found: Bool}

def Rec.ors(r: Rec) -> List<&2, C>:
  match r:
    case Rec{ors, d, found}: ors

def Rec.d(r: Rec) -> Ds:
  match r:
    case Rec{ors, d, found}: d

def Rec.found(r: Rec) -> Bool:
  match r:
    case Rec{ors, d, found}: found

def empty_ds() -> Ds:
  Ds{Nil{}, Nil{}, Nil{}, False{}}

def new_or(ors: List<&2, C>, +stores: List<&2, C>) -> C:
  match ors:
    case Nil{}: marker()
    case C{op, lit, k} <> _: C{op, lit, push.go(k, stores, Nil{})}

def do_process_and.push(ors: List<&2, C>, +stores: List<&2, C>) -> Rec:
  Rec{[new_or(ors, stores)], empty_ds(), True{}}

def do_process_and.dup.of(ors: List<&2, C>, +d: Ds) -> Rec:
  Rec{ors, d, Ds.dup(d)}

def do_process_and.dup(ors: List<&2, C>, r: Rp) -> Rec:
  do_process_and.dup.of(ors, dup.go(Rp.extra(r), empty_ds()))

def map_and(+xs: List<&2, List<&2, C>>) -> List<&2, C>:
  match xs:
    case Nil{}: Nil{}
    case x <> t: List.append(&2, C, [and_one(x)], map_and(t))


def get_clause.assemble(any: Bool, forked: Bool, +gs: List<&2, List<&2, C>>, ps: List<&2, C>) -> C:
  match any forked:
    case True{} _: and_one([C{O.OpsOR{}, LNone{}, flat(gs)}])
    case False{} True{}: or_true(ps, [C{O.OpsOR{}, LNone{}, map_and(gs)}])
    case False{} False{}: or_true(ps, flat(gs))

def get_clause.of(+u: O.UPat, +base: C, forked: Bool, +gs: List<&2, List<&2, C>>) -> C:
  get_clause.assemble(O.UPat.is_any(u), forked, gs, pieces(u, base))
# partition -- helpers.py:90, for `is_store`. `Rp` is the pair it returns: `pred`

def get_clause.done(+u: O.UPat, +base: C, depth: U32, f: Nat, forked: Bool, nested: Bool, rep: Bool, gs: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match nested rep:
    case True{} _: gs
    case False{} False{}: [[get_clause.of(u, base, forked, gs)]]
    case False{} True{}: [[get_clause.rep(u, base, depth, f, gs)]]

def alt_group(one: Bool, +a: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match one:
    case True{}: a
    case False{}: [List.concat(&2, C, a)]

def get_clause.go(f: Nat, +u: O.UPat, +pat: O.Pat, +base: C, +depth: U32, +k: U32, +alts: List<&2, O.UpAlt>, +ys: List<&2, U32>, +any: Bool, forked: Bool, +one: Bool, +nested: Bool, +rep: Bool, gs: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match f:
    case 0n: List.append(&2, List<&2, C>, gs, [[marker()]])
    case 1n+p:
      match alts:
        case Nil{}:
          match ys:
            case Nil{}: get_clause.done(u, base, depth, f, forked, nested, rep, gs)
            case y <> yt:
              +q = p
              a = get_clause.go(q, nth(pat, y), pat, child_base(any, rep, base, depth, k),
                child_depth(any, rep, depth), 0, alts_of(nth(pat, y)), Nil{},
                O.UPat.is_any(nth(pat, y)), forked_of(O.UPat.src(nth(pat, y))),
                one_alt(O.UPat.src(nth(pat, y))), False{}, False{}, Nil{})
              get_clause.go(q, u, pat, base, depth, U32.add(k, 1), Nil{}, yt, any, forked, one, nested, rep,
                List.append(&2, List<&2, C>, gs, a))
        case alt <> at:
          +q = p
          +r: Bool = is_rep(alt)
          a = get_clause.go(q, u, pat, base, depth, 0, Nil{}, alt_ys(alt), any, False{}, one, True{}, r, Nil{})
          get_clause.go(q, u, pat, base, depth, 0, at, Nil{}, any, forked, one, nested, r,
            List.append(&2, List<&2, C>, gs, alt_group(one, a)))

def get_clause(pat: O.Pat, +u: O.UPat, base: C, depth: U32, f: Nat) -> List<&2, List<&2, C>>:
  get_clause.go(f, u, pat, base, depth, 0, alts_of(u), Nil{}, O.UPat.is_any(u),
    forked_of(O.UPat.src(u)), one_alt(O.UPat.src(u)), False{}, False{}, Nil{})

# ONE OR CLAUSE MAX. upat.py:82 -- several OR clauses are replaced by the
# do_process_and -- upat.py:51. The `pm_proc` rule: one rewrite per AND node,

def ors_of(two: Bool, ors: List<&2, C>) -> List<&2, C>:
  match two:
    case True{}: [C{O.OpsOR{}, LNone{}, map_and(prod.go(ors, [[]]))}]
    case False{}: ors

def do_process_and.of6(dd: List<&2, C>, found: Bool) -> Maybe<&2, C>:
  match found:
    case True{}: Some{and_one(dd)}
    case False{}: None{}

def do_process_and.of5(+all: List<&2, C>, found: Bool) -> Maybe<&2, C>:
  do_process_and.of6(dedup.go(all, Nil{}), Bool.or(found,
    U32.is_ne(U32.from_nat(List.length(&2, C, dedup.go(all, Nil{}))), U32.from_nat(List.length(&2, C, all)))))

def do_process_and.of4(ors: List<&2, C>, flat: Bool, found: Bool, pred: List<&2, C>, +r: Rec) -> Maybe<&2, C>:
  do_process_and.of5(List.concat(&2, C, [pred, Ds.out(Rec.d(r)),
    stores_of(Ds.ks(Rec.d(r)), Ds.vs(Rec.d(r)), Nil{}), Rec.ors(r)]),
    Bool.or(Bool.or(flat, found), Rec.found(r)))

def do_process_and.of3(ors: List<&2, C>, ored: Bool, +r: Rp) -> Rec:
  match ored:
    case True{}: do_process_and.push(ors, Rp.extra(r))
    case False{}: do_process_and.dup(ors, r)

def do_process_and.of1(+ors: List<&2, C>, +ored: Bool, flat: Bool, pred: List<&2, C>, +r: Rp) -> Maybe<&2, C>:
  do_process_and.of4(ors, flat, ored, pred, do_process_and.of3(ors, ored, r))

def do_process_and.of2(+ors: List<&2, C>, flat: Bool, ored: Bool, has: Bool, pred: List<&2, C>, +r: Rp) -> Maybe<&2, C>:
  match has:
    case True{}: do_process_and.of1(ors, ored, flat, pred, r)
    case False{}: do_process_and.of4(ors, flat, False{}, pred, Rec{ors, empty_ds(), False{}})

def do_process_and.of1.go(ors: List<&2, C>, flat: Bool, +two: Bool, ored: Bool, has: Bool, +r: Rp) -> Maybe<&2, C>:
  do_process_and.of2(ors_of(two, ors), Bool.or(flat, two), ored, has, Rp.pred(r), r)


def do_process_and.of0.hit(big: Bool, +ors: List<&2, C>, flat: Bool, +r: Rp) -> Maybe<&2, C>:
  match big:
    case True{}: Some{marker()}
    case False{}: do_process_and.of1.go(ors, flat, ge2(List.length(&2, C, ors)), ne(ors), ne(Rp.extra(r)), r)

def do_process_and.of0(+ors: List<&2, C>, flat: Bool, +r: Rp) -> Maybe<&2, C>:
  do_process_and.of0.hit(ge4(List.length(&2, C, ors)), ors, flat, r)

def do_process_and.of0.of(+ss: List<&2, C>, +sp: Sp) -> Maybe<&2, C>:
  do_process_and.of0(Sp.ors(sp), Sp.flat(sp), part.go(Sp.srcs(sp), Rp{Nil{}, Nil{}}))

def do_process_and.of2.of(+ss: List<&2, C>) -> Maybe<&2, C>:
  do_process_and.of0.of(ss, split.go(ss, Sp{Nil{}, Nil{}, False{}}))


def do_process_and(op: O.Op, lit: Lit, ss: List<&2, C>) -> Maybe<&2, C>:
  match op:
    case O.OpsAND{}: do_process_and.of2.of(ss)
    case _ : None{}


type W is Data:
  W{w: List<&2, C>, n: U32, d: List<&2, Bind>}

def W.w(x: W) -> List<&2, C>:
  match x:
    case W{w, n, d}: w

def W.n(x: W) -> U32:
  match x:
    case W{w, n, d}: n

def W.d(x: W) -> List<&2, Bind>:
  match x:
    case W{w, n, d}: d

# is WRONG: Python's `wrap` is a graph rewrite and `UOp(Ops.PYLITERAL, arg=x)` is

def wrap.found(+bs: List<&2, Bind>, ans: Maybe<&2, String>, +lit: Lit) -> Maybe<&2, String>:
  match bs:
    case Nil{}: ans
    case b <> t: Bool.pick(Maybe<&2, String>, eq_lit(Bind.lit(b), lit), Some{Bind.name(b)},
      wrap.found(t, ans, lit))

def wrap.fresh(+n: U32, lit: Lit, +d: List<&2, Bind>) -> W:
  +nm: String = String.concat(["a", U32.show(n)])
  W{[C{O.OpsCUSTOMI{}, LText{nm}, Nil{}}], U32.add(n, 1), List.append(&2, Bind, d, [Bind{nm, lit}])}

def wrap.node.hit(hit: Maybe<&2, String>, lit: Lit, n: U32, +d: List<&2, Bind>) -> W:
  match hit:
    case Some{nm}: W{[C{O.OpsCUSTOMI{}, LText{nm}, Nil{}}], n, d}
    case None{}: wrap.fresh(n, lit, d)

def wrap.node(op: O.Op, +lit: Lit, +n: U32, +d: List<&2, Bind>) -> W:
  match op:
    case O.OpsPYLITERAL{}: wrap.node.hit(wrap.found(d, None{}, lit), lit, n, d)
    case _ : W{[C{op, lit, Nil{}}], n, d}


def wrap.rebuild.put(op: O.Op, lit: Lit, +kids: List<&2, C>) -> C:
  match op:
    case O.OpsPYLITERAL{}: C{O.OpsCUSTOMI{}, lit, Nil{}}
    case _ : C{op, lit, kids}

def wrap.rebuild.of(x: C, +kids: List<&2, C>) -> C:
  match x:
    case C{op, lit, k}: wrap.rebuild.put(op, lit, kids)

def wrap.rebuild(x: C, +kids: List<&2, C>) -> C:
  wrap.rebuild.of(x, kids)


def wrap.go(+f: Nat, +ss: List<&2, C>, n: U32, +d: List<&2, Bind>, acc: List<&2, C>) -> W:
  match f:
    case 0n: W{acc, n, d}
    case 1n+p:
      match ss:
        case Nil{}: W{acc, n, d}
        case C{op, lit, k} <> t:
          +a: W = wrap.node(op, lit, n, d)
          +b: W = wrap.go(p, k, W.n(a), W.d(a), Nil{})
          wrap.go(f, t, W.n(b), W.d(b),
            List.append(&2, C, acc, [wrap.rebuild(head1c(W.w(a)), W.w(b))]))

def wrap(t: C, f: Nat) -> W:
  wrap.go(f, [t], 0, Nil{}, Nil{})


type Rend is Data:
  Rend{cond: List<&2, String>, sto: List<&2, String>, orp: List<&2, String>, bad: Bool}

def Rend.cond(r: Rend) -> List<&2, String>:
  match r:
    case Rend{cond, sto, orp, bad}: cond

def Rend.sto(r: Rend) -> List<&2, String>:
  match r:
    case Rend{cond, sto, orp, bad}: sto

def Rend.orp(r: Rend) -> List<&2, String>:
  match r:
    case Rend{cond, sto, orp, bad}: orp

def Rend.bad(r: Rend) -> Bool:
  match r:
    case Rend{cond, sto, orp, bad}: bad


def rend.sto(+r: Rend, +k: List<&2, C>) -> Rend:
  Rend{Rend.cond(r), List.append(&2, String, Rend.sto(r),
    [String.concat([ctext.m(List.get(&2, C, k, 0n)), "=", ctext.m(List.get(&2, C, k, 1n))])]),
    Rend.orp(r), Rend.bad(r)}

def rend.cond(+r: Rend, lit: Lit) -> Rend:
  Rend{List.append(&2, String, Rend.cond(r), [text_of(lit.text(lit))]), Rend.sto(r), Rend.orp(r),
    Rend.bad(r)}


def rend.put(+r: Rend, +a: Rend) -> Rend:
  Rend{Rend.cond(r), Rend.sto(r), List.append(&2, String, Rend.orp(r), Rend.orp(a)),
    Bool.or(Rend.bad(r), Rend.bad(a))}


def rend.end(+r: Rend, br: Bool) -> Rend:
  match br:
    case True{}: Rend{Nil{}, Nil{}, Rend.orp(r), Rend.bad(r)}
    case False{}: r

def branch_lines.of(m: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match m:
    case Some{ls}: ls
    case None{}: Nil{}


def indent(depth: U32) -> String:
  String.repeat("  ", U32.to_nat(depth))

def conds(+cs: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, cs), "True", String.join(cs, " and "))


def args_list(+r: Rend, +has_ctx: Bool) -> List<&2, String>:
  Bool.pick(List<&2, String>, has_ctx, List.append(&2, String, ["ctx=ctx"], Rend.sto(r)), Rend.sto(r))

def args(+r: Rend, +has_ctx: Bool) -> String:
  String.join(args_list(r, has_ctx), ", ")

# upat.py:153 -- without an OR, this is the final return: the function's answer

def ret_clause(+r: Rend, +has_ctx: Bool) -> String:
  String.join(List.append(&2, String, Rend.cond(r),
    [String.concat(["(_ret:=_fxn(", args(r, has_ctx), ")) is not None"])]), " and ")


def final_return(+r: Rend, +has_ctx: Bool, depth: U32) -> String:
  String.concat([indent(depth), "if ", ret_clause(r, has_ctx), ": return _ret"])

def if_line(+r: Rend, depth: U32) -> String:
  String.concat([indent(depth), "if ", conds(Rend.cond(r)), ":"])

# IF WE HAVE AN OR, RENDER IT. upat.py:148 -- the OR becomes nested `if`

def final_shape(no_or: Bool, +orp: List<&2, String>, +r: Rend, +has_ctx: Bool, depth: U32) -> Maybe<&2, List<&2, String>>:
  match no_or:
    case True{}: Some{[final_return(r, has_ctx, depth)]}
    case False{}: Some{List.append(&2, String, [if_line(r, depth)], orp)}

def final_shape.of(+orp: List<&2, String>, +r: Rend, +has_ctx: Bool, depth: U32) -> Maybe<&2, List<&2, String>>:
  final_shape(List.is_empty(&2, String, orp), orp, r, has_ctx, depth)


def final_lines(bad: Bool, +orp: List<&2, String>, +r: Rend, +has_ctx: Bool, depth: U32) -> Maybe<&2, List<&2, String>>:
  match bad:
    case True{}: None{}
    case False{}: final_shape.of(orp, r, has_ctx, depth)

def branch_lines(bad: Bool, +a: Rend, +has_ctx: Bool, depth: U32) -> List<&2, String>:
  branch_lines.of(final_lines(bad, Rend.orp(a), a, has_ctx, depth))


def rend.or(+r: Rend, +a: Rend, +has_ctx: Bool, depth: U32) -> Rend:
  rend.put(r, Rend{Nil{}, Nil{}, branch_lines(Rend.bad(a), a, has_ctx, depth), Rend.bad(a)})


def rend.go(f: Nat, +ss: List<&2, C>, +r: Rend, +has_ctx: Bool, +depth: U32, +br: Bool) -> Rend:
  match f:
    case 0n: Rend{Rend.cond(r), Rend.sto(r), Rend.orp(r), True{}}
    case 1n+q:
      match ss:
        case Nil{}: rend.end(r, br)
        case C{op, lit, k} <> t:
          match op:
            case O.OpsOR{}:
              +z: Nat = q
              +a: Rend = rend.go(z, k, Rend{Nil{}, Nil{}, Nil{}, False{}}, has_ctx, U32.add(depth, 1), True{})
              rend.go(z, t, rend.put(r, a), has_ctx, depth, False{})
            case O.OpsAND{}:
              +z: Nat = q
              rend.go(z, t, rend.or(r, rend.go(z, k, Rend{Nil{}, Nil{}, Nil{}, False{}}, has_ctx, depth, False{}), has_ctx, depth), has_ctx, depth, br)
            case O.OpsSTORE{}: rend.go(q, t, Bool.pick(Rend, br,
              rend.or(r, rend.sto(Rend{Nil{}, Nil{}, Nil{}, False{}}, k), has_ctx, depth), rend.sto(r, k)), has_ctx, depth, br)
            case O.OpsCUSTOMI{}: rend.go(q, t, Bool.pick(Rend, br,
              rend.or(r, rend.cond(Rend{Nil{}, Nil{}, Nil{}, False{}}, lit), has_ctx, depth), rend.cond(r, lit)), has_ctx, depth, br)
            case _ : Rend{Rend.cond(r), Rend.sto(r), Rend.orp(r), True{}}


def start_ss.of(+t: C, op: O.Op, k: List<&2, C>) -> List<&2, C>:
  match op:
    case O.OpsAND{}: k
    case _ : [t]

def start_ss(t: C) -> List<&2, C>:
  match t:
    case C{+op, lit, +k}: start_ss.of(t, op, k)

def final_render.of(+r: Rend, orp: List<&2, String>, bad: Bool, +has_ctx: Bool, depth: U32) -> Maybe<&2, List<&2, String>>:
  final_lines(bad, orp, r, has_ctx, depth)

def final_render(t: C, +has_ctx: Bool, f: Nat) -> Maybe<&2, List<&2, String>>:
  +r: Rend = rend.go(f, start_ss(t), Rend{Nil{}, Nil{}, Nil{}, False{}}, has_ctx, 1, False{})
  final_render.of(r, Rend.orp(r), Rend.bad(r), has_ctx, 1)

def is_ci(op: O.Op) -> Bool:
  match op:
    case O.OpsCUSTOMI{}: True{}
    case _ : False{}


def all_ci(ss: List<&2, C>) -> Bool:
  match ss:
    case Nil{}: True{}
    case C{op, lit, k} <> t: Bool.and(is_ci(op), all_ci(t))

def ci_texts(ss: List<&2, C>) -> List<&2, String>:
  match ss:
    case Nil{}: Nil{}
    case C{op, lit, k} <> t: List.append(&2, String, [ctext(C{op, lit, k})], ci_texts(t))


def idx.make(x: O.Op, l: Lit, y: O.Op, m: Lit) -> Maybe<&2, C>:
  match x y:
    case O.OpsCUSTOMI{} O.OpsCONST{}: Some{C{O.OpsCUSTOMI{},
      LText{String.concat([text_of(lit.text(l)), ".src[", val_of(m), "]"])}, Nil{}}}
    case _ _: None{}

def idx.hit(+a: C, +b: C) -> Maybe<&2, C>:
  match a b:
    case C{x, l, _} C{y, m, _}: idx.make(x, l, y, m)
    case _ _: None{}

def idx.two(+a: C, +b: C, more: Bool) -> Maybe<&2, C>:
  match more:
    case True{}: None{}
    case False{}: idx.hit(a, b)

def idx.of(+a: C, alts: List<&2, C>) -> Maybe<&2, C>:
  match alts:
    case Nil{}: None{}
    case +b <> t: idx.two(a, b, ne(t))

def idx.lit(alts: List<&2, C>) -> Maybe<&2, C>:
  match alts:
    case Nil{}: None{}
    case +a <> t: idx.of(a, t)

def idx(ss: List<&2, C>) -> Maybe<&2, C>:
  idx.lit(ss)


def head_or(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}: ""
    case p <> _: p


def fmt.lit(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}: ""
    case _ <> t: head_or(t)

def fmt.hole(ps: List<&2, String>, +args: List<&2, C>, k: U32, acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}: acc
    case _ <> rest: List.append(&2, String, List.append(&2, String, acc,
      [ctext.m(List.get(&2, C, args, U32.to_nat(k)))]), [fmt.lit(ps)])

def fmt.put(first: Bool, p: String, +args: List<&2, C>, k: U32, acc: List<&2, String>) -> List<&2, String>:
  match first:
    case True{}: List.append(&2, String, acc, [p])
    case False{}: fmt.hole(String.split(p, '}'), args, k, acc)

def fmt.go(+ps: List<&2, String>, +args: List<&2, C>, +k: U32, +first: Bool, acc: List<&2, String>) -> String:
  match ps:
    case Nil{}: String.concat(acc)
    case p <> t: fmt.go(t, args, Bool.pick(U32, first, k, U32.add(k, 1)), False{},
      fmt.put(first, p, args, k, acc))

def fmt.of(fmt: String, +args: List<&2, C>, acc: List<&2, String>) -> String:
  fmt.go(String.split(fmt, '{'), args, 0, True{}, acc)

def rule.of(op: O.Op, lit: Lit, +ns: List<&2, C>) -> C:
  match op:
    case O.OpsAND{}: C{O.OpsCUSTOMI{}, LText{String.concat(["(", String.join(ci_texts(ns), " and "), ")"])}, Nil{}}
    case O.OpsOR{}: C{O.OpsCUSTOMI{}, LText{String.concat(["(", String.join(ci_texts(ns), " or "), ")"])}, Nil{}}
    case O.OpsCUSTOM{}: C{O.OpsCUSTOMI{}, LText{fmt.of(text_of(lit.text(lit)), ns, Nil{})}, Nil{}}
    case _ : C{op, lit, ns}

def rule.join(ci: Bool, op: O.Op, lit: Lit, +ns: List<&2, C>) -> C:
  match ci:
    case True{}: rule.of(op, lit, ns)
    case False{}: C{op, lit, ns}


def rule.hit(hit: Maybe<&2, C>, ci: Bool, op: O.Op, lit: Lit, +ns: List<&2, C>) -> C:
  match hit:
    case Some{c}: c
    case None{}: rule.join(ci, op, lit, ns)

def rule(op: O.Op, lit: Lit, +ns: List<&2, C>) -> C:
  rule.hit(idx(ns), all_ci(ns), op, lit, ns)

def render.go(+ss: List<&2, C>) -> List<&2, C>:
  match ss:
    case Nil{}: Nil{}
    case C{op, lit, k} <> t:
      a = render.go(t)
      +b: List<&2, C> = render.go(k)
      List.append(&2, C, [rule(op, lit, b)], a)

def render(t: C) -> C:
  match t:
    case C{+op, +lit, +ss}: rule(op, lit, render.go(ss))


def proc.put(c: C, hit: Maybe<&2, C>) -> C:
  match hit:
    case Some{x}: x
    case None{}: c

# THE WAITLIST. `unified_rewrite` runs a node's rule at ops.py:1852, and the
# loop before it (ops.py:1843) is what makes the pass bottom-up-to-a-FIXPOINT
# a.src` (upat.py:76-81) splices an AND's children into `new_src` WITHOUT
# the store takes the `else` at upat.py:100-111 -- the duplicate path -- instead
# of the push at upat.py:95-99. The rebuilt node is re-queued, and on THAT

type Pg is Data:
  Pg{cs: List<&2, C>, ch: Bool}

def Pg.cs(p: Pg) -> List<&2, C>:
  match p:
    case Pg{cs, ch}: cs

def Pg.ch(p: Pg) -> Bool:
  match p:
    case Pg{cs, ch}: ch

def proc.step(+op: O.Op, +lit: Lit, +cs: List<&2, C>, a: Pg) -> Pg:
  +c: C = C{op, lit, cs}
  +d: C = proc.put(c, do_process_and(op, lit, cs))
  Pg{List.append(&2, C, [d], Pg.cs(a)), Bool.not(eq_c(c, d))}

def proc.node(+op: O.Op, +lit: Lit, b: Pg, a: Pg) -> Pg:
  match b:
    case Pg{+cs, ch}:
      match ch:
        case True{}: Pg{List.append(&2, C, [C{op, lit, cs}], Pg.cs(a)), True{}}
        case False{}: proc.step(op, lit, cs, a)


def proc.join(+a: Pg, +r: Pg) -> Pg:
  Pg{Pg.cs(r), Bool.or(Pg.ch(r), Pg.ch(a))}

def proc.go(+ss: List<&2, C>) -> Pg:
  match ss:
    case Nil{}: Pg{Nil{}, False{}}
    case C{+op, +lit, k} <> t:
      +b: Pg = proc.go(k)
      +a: Pg = proc.go(t)
      +r: Pg = proc.node(op, lit, b, a)
      proc.join(a, r)


def proc(t: C) -> Pg:
  +p: Pg = proc.go([t])
  Pg{[head1c(Pg.cs(p))], Pg.ch(p)}

def proc_fix(f: Nat, +t: C) -> C:
  match f:
    case 0n: t
    case 1n+p:
      +r: Pg = proc(t)
      +u: C = head1c(Pg.cs(r))
      Bool.pick(C, Pg.ch(r), proc_fix(p, u), u)

def group1.of(g: List<&2, C>) -> C:
  match g:
    case Nil{}: marker()
    case c <> _: c

def group1(gs: List<&2, List<&2, C>>) -> C:
  match gs:
    case Nil{}: marker()
    case g <> _: group1.of(g)

# _get_code -- upat.py:166. The three passes and the join.

def code_of(rendered: Maybe<&2, List<&2, String>>, +dyn: List<&2, Bind>) -> Maybe<&2, Code>:
  match rendered:
    case None{}: None{}
    case Some{ls}: Some{Code{String.join(List.append(&2, String,
      ["def compiled_match(uop, ctx):"], List.append(&2, String, ls, ["  return None"])), "\n"), dyn}}

def get_code.of6(rendered: Maybe<&2, List<&2, String>>, +dyn: List<&2, Bind>) -> Maybe<&2, Code>:
  code_of(rendered, dyn)

# _get_code -- upat.py:162. The three passes, in Python's order and with

def get_code.of5(+t: C, +w: W, has_ctx: Bool, f: Nat) -> Maybe<&2, Code>:
  get_code.of6(final_render(render(head1c(W.w(w))), has_ctx, f), W.d(w))

def get_code.of4(+t: C, has_ctx: Bool, +f: Nat) -> Maybe<&2, Code>:
  get_code.of5(t, wrap(t, f), has_ctx, f)

def get_code.of3(+gs: List<&2, List<&2, C>>, has_ctx: Bool, +f: Nat) -> Maybe<&2, Code>:
  get_code.of4(proc_fix(f, group1(gs)), has_ctx, f)

def get_code.of2(+pat: O.Pat, +u: O.UPat, +has_ctx: Bool, +f: Nat) -> Maybe<&2, Code>:
  get_code.of3(get_clause(pat, u, base_clause(), 0, f), has_ctx, f)


def get_code.broken(bad: Bool, +pat: O.Pat, +u: O.UPat, has_ctx: Bool, f: Nat) -> Maybe<&2, Code>:
  match bad:
    case True{}: None{}
    case False{}: get_code.of2(pat, u, has_ctx, f)

def get_code(+pat: O.Pat, +u: O.UPat, has_ctx: Bool) -> Maybe<&2, Code>:
  get_code.broken(broken_of(u), pat, u, has_ctx, fuel(pat))

# upat_compile -- upat.py:173. `@functools.cache` and the `exec` are the wall.
# TODO(p3) ops.py:1526 def upat_interpret -- `types.FunctionType(
# TODO(p3) ops.py:1398 def get_location -- `sys._getframe`, the
# TODO(p3) upat.py:181  upat_compile -- exec -- `namespace["compiled_match"]`. The rendered `Code`

def upat_compile(+pat: O.Pat, i: U32, has_ctx: Bool) -> Maybe<&2, Code>:
  get_code(pat, nth(pat, i), has_ctx)


def Code.s(c: Code) -> String:
  match c:
    case Code{s, dyn}: s

def Code.dyn(c: Code) -> List<&2, Bind>:
  match c:
    case Code{s, dyn}: dyn

def dyn_names(bs: List<&2, Bind>) -> List<&2, String>:
  match bs:
    case Nil{}: Nil{}
    case b <> t: List.append(&2, String, [Bind.name(b)], dyn_names(t))

def eq_strs(xs: List<&2, String>, ys: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: True{}
        case _ <> _: False{}
    case x <> t:
      match ys:
        case Nil{}: False{}
        case y <> u: Bool.and(String.eq(x, y), eq_strs(t, u))

def code_is.of(r: Maybe<&2, Code>, want: String) -> Bool:
  match r:
    case Some{c}: String.eq(Code.s(c), want)
    case None{}: False{}

def code_is(+f: O.PatFound, has_ctx: Bool, want: String) -> Bool:
  code_is.of(upat_compile(O.PatFound.pat(f), O.PatFound.i(f), has_ctx), want)

def dyn_is.of(r: Maybe<&2, Code>, want: List<&2, String>) -> Bool:
  match r:
    case Some{c}: eq_strs(dyn_names(Code.dyn(c)), want)
    case None{}: False{}

def dyn_is(+f: O.PatFound, has_ctx: Bool, want: List<&2, String>) -> Bool:
  dyn_is.of(upat_compile(O.PatFound.pat(f), O.PatFound.i(f), has_ctx), want)


def is_none.of(r: Maybe<&2, Code>) -> Bool:
  match r:
    case Some{c}: False{}
    case None{}: True{}

def is_none(+f: O.PatFound, has_ctx: Bool) -> Bool:
  is_none.of(upat_compile(O.PatFound.pat(f), O.PatFound.i(f), has_ctx))


def pat_var() -> O.PatFound:
  O.UPat.var(O.Pat{Nil{}}, Some{"x"}, None{})


def pat_add() -> O.PatFound:
  a = O.UPat.var(O.Pat{Nil{}}, Some{"a"}, None{})
  b = O.UPat.var(O.PatFound.pat(a), Some{"b"}, None{})
  O.UPat.of(O.PatFound.pat(b), Some{[O.OpsADD{}]}, None{}, O.STuple{[0, 1]}, None{}, None{}, False{}, None{}, False{})


def pat_repeat() -> O.PatFound:
  m = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsMUL{}]}, None{}, O.SNone{}, None{}, Some{"m"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(m), Some{[O.OpsADD{}]}, None{}, O.SOne{0}, None{}, None{}, False{}, None{}, False{})


def pat_any() -> O.PatFound:
  a = O.UPat.var(O.Pat{Nil{}}, Some{"a"}, None{})
  b = O.UPat.var(O.PatFound.pat(a), Some{"b"}, None{})
  O.UPat.of(O.PatFound.pat(b), None{}, None{}, O.STuple{[0, 1]}, None{}, None{}, False{}, None{}, True{})


def pat_rep_src() -> O.PatFound:
  m = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsMUL{}]}, None{}, O.SNone{}, None{}, Some{"m"}, False{}, None{}, False{})
  i = O.UPat.var(O.PatFound.pat(m), Some{"i"}, None{})
  a = O.UPat.of(O.PatFound.pat(i), Some{[O.OpsADD{}]}, None{}, O.SOne{0}, None{}, None{}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(a), Some{[O.OpsINDEX{}]}, None{}, O.STuple{[2, 1]}, None{}, None{}, False{}, None{}, False{})


def pat_rep_src_src() -> O.PatFound:
  p = O.UPat.var(O.Pat{Nil{}}, Some{"p"}, None{})
  m = O.UPat.of(O.PatFound.pat(p), Some{[O.OpsMUL{}]}, None{}, O.STuple{[0]}, None{}, Some{"m"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(m), Some{[O.OpsINDEX{}]}, None{}, O.SOne{1}, None{}, None{}, False{}, None{}, False{})


def pat_any_rep() -> O.PatFound:
  m = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsMUL{}]}, None{}, O.SNone{}, None{}, Some{"m"}, False{}, None{}, False{})
  a = O.UPat.of(O.PatFound.pat(m), Some{[O.OpsADD{}]}, None{}, O.SOne{0}, None{}, None{}, False{}, None{}, False{})
  s = O.UPat.of(O.PatFound.pat(a), Some{[O.OpsSUB{}]}, None{}, O.SNone{}, None{}, Some{"s"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(s), None{}, None{}, O.STuple{[1, 2]}, None{}, None{}, False{}, None{}, True{})


def pat_dup_store() -> O.PatFound:
  a = O.UPat.var(O.Pat{Nil{}}, Some{"a"}, None{})
  m = O.UPat.of(O.PatFound.pat(a), Some{[O.OpsADD{}]}, None{}, O.STuple{[0, 0]}, None{}, Some{"m"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(m), Some{[O.OpsMUL{}]}, None{}, O.SOne{1}, None{}, None{}, False{}, None{}, False{})


def pat_share() -> O.PatFound:
  m = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsMUL{}]}, None{}, O.SNone{}, None{}, Some{"m"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(m), Some{[O.OpsADD{}]}, None{}, O.STuple{[0, 0]}, None{}, None{}, False{}, None{}, False{})


def pat_set_ord() -> O.PatFound:
  c = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsADD{}, O.OpsMUL{}]}, Some{[S.half(), S.int32()]}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(c), Some{[O.OpsMUL{}, O.OpsADD{}]}, Some{[S.int32(), S.half()]}, O.STuple{[0]}, None{}, None{}, False{}, None{}, False{})


def pat_argint() -> O.PatFound:
  O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsCALL{}]}, None{}, O.SNone{}, Some{O.ATuple{[4]}}, None{}, False{}, None{}, False{})


def pat_bigor() -> O.PatFound:
  c0 = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsADD{}]}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  c1 = O.UPat.of(O.PatFound.pat(c0), Some{[O.OpsSUB{}]}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  c2 = O.UPat.of(O.PatFound.pat(c1), Some{[O.OpsMUL{}]}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  c3 = O.UPat.of(O.PatFound.pat(c2), Some{[O.OpsMAX{}]}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  q = O.UPat.of(O.PatFound.pat(c3), None{}, None{}, O.STuple{[0, 1, 2, 3]}, None{}, None{}, False{}, None{}, True{})
  O.UPat.of(O.PatFound.pat(q), Some{[O.OpsBINARY{}]}, None{}, O.STuple{[4, 4, 4, 4]}, None{}, None{}, False{}, None{}, False{})


def want_var() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if (_ret:=_fxn(ctx=ctx, x=uop)) is not None: return _ret", "  return None"], "\n")

def want_add() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if uop.op is a0 and len(uop.src) == 2 and (_ret:=_fxn(ctx=ctx, a=uop.src[0], b=uop.src[1])) is not None: return _ret",
    "  return None"], "\n")

def want_repeat() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if uop.op is a0 and len(uop.src) != 0 and all([(ituop0.op is a1 and ituop0 is uop.src[0]) for ituop0 in uop.src]) and (_ret:=_fxn(ctx=ctx, m=uop.src[0])) is not None: return _ret",
    "  return None"], "\n")

def want_any() -> String:
  String.join(["def compiled_match(uop, ctx):", "  if True:",
    "    if (_ret:=_fxn(ctx=ctx, a=uop)) is not None: return _ret",
    "    if (_ret:=_fxn(ctx=ctx, b=uop)) is not None: return _ret", "  return None"], "\n")

def want_rep_src() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if uop.op is a0 and len(uop.src) == 2 and uop.src[0].op is a1 and len(uop.src[0].src) != 0 and all([(ituop0.op is a2 and ituop0 is uop.src[0].src[0]) for ituop0 in uop.src[0].src]) and (_ret:=_fxn(ctx=ctx, m=uop.src[0].src[0], i=uop.src[1])) is not None: return _ret",
    "  return None"], "\n")

def want_rep_src_src() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if uop.op is a0 and len(uop.src) != 0 and all([(ituop0.op is a1 and len(ituop0.src) == 1 and ituop0 is uop.src[0] and ituop0.src[0] is uop.src[0].src[0]) for ituop0 in uop.src]) and (_ret:=_fxn(ctx=ctx, m=uop.src[0], p=uop.src[0].src[0])) is not None: return _ret",
    "  return None"], "\n")

def want_any_rep() -> String:
  String.join(["def compiled_match(uop, ctx):", "  if True:",
    "    if uop.op is a0 and len(uop.src) != 0 and all([(ituop0.op is a1 and ituop0 is uop.src[0]) for ituop0 in uop.src]) and (_ret:=_fxn(ctx=ctx, m=uop.src[0])) is not None: return _ret",
    "    if uop.op is a2 and (_ret:=_fxn(ctx=ctx, s=uop)) is not None: return _ret", "  return None"], "\n")

def want_dup_store() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if uop.op is a0 and len(uop.src) != 0 and all([(ituop0.op is a1 and len(ituop0.src) == 2 and ituop0 is uop.src[0] and ituop0.src[0] is uop.src[0].src[0] and ituop0.src[1] is uop.src[0].src[1]) for ituop0 in uop.src]) and uop.src[0].src[0] is uop.src[0].src[1] and (_ret:=_fxn(ctx=ctx, m=uop.src[0], a=uop.src[0].src[0])) is not None: return _ret",
    "  return None"], "\n")

def want_share() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if uop.op is a0 and len(uop.src) == 2 and uop.src[0].op is a1 and uop.src[1].op is a1 and uop.src[0] is uop.src[1] and (_ret:=_fxn(ctx=ctx, m=uop.src[0])) is not None: return _ret",
    "  return None"], "\n")

def want_set_ord() -> String:
  String.join([
    "def compiled_match(uop, ctx):",
    "  if (uop.op in a0 and len(uop.src) == 1 and uop.dtype in a1 and uop.src[0].op in a0 and uop.src[0].dtype in a1) and (_ret:=_fxn(ctx=ctx)) is not None: return _ret",
    "  return None"
  ], "\n")
# p2's own AND, so `do_process_and`'s `for x in a.src` (upat.py:76) splices p3's
# unresolved (ops.py:1843-1846), so p3 pushes `x` into the branches FIRST and p4's

def pat_store_ord() -> O.PatFound:
  p0 = O.UPat.of(O.Pat{Nil{}}, None{}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  p1 = O.UPat.of(O.PatFound.pat(p0), Some{[O.OpsCONST{}]}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  p2 = O.UPat.of(O.PatFound.pat(p1), None{}, None{}, O.SList{[0, 1]}, None{}, None{}, False{}, None{}, False{})
  p3 = O.UPat.of(O.PatFound.pat(p2), None{}, None{}, O.STuple{[2, 0]}, None{}, Some{"x"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(p3), None{}, None{}, O.STuple{[0, 3]}, None{}, Some{"b"}, False{}, None{}, False{})

def want_store_ord() -> String:
  String.join([
    "def compiled_match(uop, ctx):",
    "  if len(uop.src) == 2 and True and len(uop.src[1].src) == 2 and len(uop.src[1].src[0].src) == 2:",
    "    if True and uop.src[1].src[0].src[1].op is a0 and (_ret:=_fxn(ctx=ctx, x=uop.src[1], b=uop)) is not None: return _ret",
    "    if uop.src[1].src[0].src[0].op is a0 and True and (_ret:=_fxn(ctx=ctx, x=uop.src[1], b=uop)) is not None: return _ret",
    "  return None"
  ], "\n")

def pat_deep() -> O.PatFound:
  p0 = O.UPat.of(O.Pat{Nil{}}, None{}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  p1 = O.UPat.of(O.PatFound.pat(p0), None{}, Some{[S.single(), S.half()]}, O.SList{[0]}, None{}, Some{"b"}, False{}, None{}, False{})
  p2 = O.UPat.of(O.PatFound.pat(p1), None{}, None{}, O.SList{[0, 1]}, Some{O.ATuple{[5]}}, None{}, False{}, None{}, False{})
  p3 = O.UPat.of(O.PatFound.pat(p2), Some{[O.OpsCONST{}]}, Some{[S.half(), S.single()]}, O.STuple{[2, 1]}, None{}, Some{"a"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(p3), Some{[O.OpsNEG{}]}, Some{[S.int32()]}, O.STuple{[3, 3, 1]}, None{}, None{}, False{}, None{}, False{})

def want_deep() -> String:
  String.join([
    "def compiled_match(uop, ctx):",
    "  if uop.op is a0 and len(uop.src) == 3 and uop.dtype is a1 and uop.src[0].op is a2 and len(uop.src[0].src) == 2 and uop.src[0].dtype in a3 and uop.src[0].src[0].arg == 5 and len(uop.src[0].src[0].src) == 2 and len(uop.src[0].src[1].src) == 1 and uop.src[0].src[1].dtype in a3 and True and uop.src[1].op is a2 and len(uop.src[1].src) == 2 and uop.src[1].dtype in a3 and uop.src[1].src[0].arg == 5 and len(uop.src[1].src[0].src) == 2 and len(uop.src[1].src[1].src) == 1 and uop.src[1].src[1].dtype in a3 and len(uop.src[2].src) == 1 and uop.src[2].dtype in a3:",
    "    if True and len(uop.src[0].src[0].src[1].src) == 1 and uop.src[0].src[0].src[1].dtype in a3 and uop.src[0].src[0].src[1] is uop.src[0].src[1] and len(uop.src[1].src[0].src[1].src) == 1 and uop.src[1].src[0].src[1].dtype in a3 and uop.src[1].src[0].src[1] is uop.src[1].src[1] and uop.src[0].src[0].src[1] is uop.src[1].src[0].src[1] and uop.src[0] is uop.src[1] and uop.src[0].src[0].src[1] is uop.src[2] and (_ret:=_fxn(ctx=ctx, b=uop.src[0].src[0].src[1], a=uop.src[0])) is not None: return _ret",
    "    if True and len(uop.src[0].src[0].src[1].src) == 1 and uop.src[0].src[0].src[1].dtype in a3 and uop.src[0].src[0].src[1] is uop.src[0].src[1] and len(uop.src[1].src[0].src[0].src) == 1 and uop.src[1].src[0].src[0].dtype in a3 and uop.src[1].src[0].src[0] is uop.src[1].src[1] and uop.src[0].src[0].src[1] is uop.src[1].src[0].src[0] and uop.src[0] is uop.src[1] and uop.src[0].src[0].src[1] is uop.src[2] and (_ret:=_fxn(ctx=ctx, b=uop.src[0].src[0].src[1], a=uop.src[0])) is not None: return _ret",
    "    if len(uop.src[0].src[0].src[0].src) == 1 and uop.src[0].src[0].src[0].dtype in a3 and True and uop.src[0].src[0].src[0] is uop.src[0].src[1] and len(uop.src[1].src[0].src[1].src) == 1 and uop.src[1].src[0].src[1].dtype in a3 and uop.src[1].src[0].src[1] is uop.src[1].src[1] and uop.src[0].src[0].src[0] is uop.src[1].src[0].src[1] and uop.src[0] is uop.src[1] and uop.src[0].src[0].src[0] is uop.src[2] and (_ret:=_fxn(ctx=ctx, b=uop.src[0].src[0].src[0], a=uop.src[0])) is not None: return _ret",
    "    if len(uop.src[0].src[0].src[0].src) == 1 and uop.src[0].src[0].src[0].dtype in a3 and True and uop.src[0].src[0].src[0] is uop.src[0].src[1] and len(uop.src[1].src[0].src[0].src) == 1 and uop.src[1].src[0].src[0].dtype in a3 and uop.src[1].src[0].src[0] is uop.src[1].src[1] and uop.src[0].src[0].src[0] is uop.src[1].src[0].src[0] and uop.src[0] is uop.src[1] and uop.src[0].src[0].src[0] is uop.src[2] and (_ret:=_fxn(ctx=ctx, b=uop.src[0].src[0].src[0], a=uop.src[0])) is not None: return _ret",
    "  return None"
  ], "\n")

def want_noctx() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if (_ret:=_fxn(x=uop)) is not None: return _ret", "  return None"], "\n")

def want_argint() -> String:
  String.join(["def compiled_match(uop, ctx):",
    "  if (uop.op is a0 and uop.arg == 4) and (_ret:=_fxn(ctx=ctx)) is not None: return _ret", "  return None"], "\n")

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def show.of(r: Maybe<&2, Code>) -> String:
  match r:
    case Some{c}: String.concat(["--- ", Code.s(c)])
    case None{}: "--- None"

def show(+f: O.PatFound, has_ctx: Bool) -> IO(Unit):
  IO.print(show.of(upat_compile(O.PatFound.pat(f), O.PatFound.i(f), has_ctx)))


def drv.num(cs: List<&2, Char>, acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case c <> t: drv.num(t, U32.add(U32.mul(acc, 10), U32.sub(Char.to_u32(c), 48)))

def drv.num.of(s: String) -> U32:
  drv.num(String.to_list(s), 0)

def drv.nth(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{n}: n
    case None{}: 0

def drv.one(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def drv.field(ns: List<&2, String>, k: U32) -> String:
  drv.one(List.get(&2, String, ns, U32.to_nat(k)))


def drv.ids.go(ks: List<&2, String>, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}: acc
    case k <> t: drv.ids.go(t, List.append(&2, U32, acc, [drv.num.of(k)]))

def drv.ids(s: String) -> List<&2, U32>:
  drv.ids.go(String.split(s, ','), Nil{})

def drv.first(s: String) -> U32:
  drv.nth(List.get(&2, U32, drv.ids(s), 0n))

# the three literal lists. `+` joins because it is `ge2` that picks the arm, and a
# two-element list must be reachable.

def drv.op1(s: String) -> O.Op:
  match s:
    case "ADD": O.OpsADD{}
    case "MUL": O.OpsMUL{}
    case "SUB": O.OpsSUB{}
    case "MAX": O.OpsMAX{}
    case "INDEX": O.OpsINDEX{}
    case "CONST": O.OpsCONST{}
    case "NEG": O.OpsNEG{}
    case "CALL": O.OpsCALL{}
    case _: O.OpsADD{}

def drv.ops.go(ks: List<&2, String>, acc: List<&2, O.Op>) -> List<&2, O.Op>:
  match ks:
    case Nil{}: acc
    case k <> t: drv.ops.go(t, List.append(&2, O.Op, acc, [drv.op1(k)]))

def drv.opm.of(s: String) -> Maybe<&2, List<&2, O.Op>>:
  match s:
    case "-": None{}
    case _: Some{drv.ops.go(String.split(s, '+'), Nil{})}

def drv.dt1(s: String) -> S.Dt:
  match s:
    case "i32": S.int32()
    case "h": S.half()
    case _: S.single()

def drv.dts.go(ks: List<&2, String>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ks:
    case Nil{}: acc
    case k <> t: drv.dts.go(t, List.append(&2, S.Dt, acc, [drv.dt1(k)]))

def drv.dtm.of(s: String) -> Maybe<&2, List<&2, S.Dt>>:
  match s:
    case "-": None{}
    case _: Some{drv.dts.go(String.split(s, '+'), Nil{})}

def drv.nm.of(s: String) -> Maybe<&2, String>:
  match s:
    case "-": None{}
    case _: Some{s}

# first two nodes were equal silently reads the WRONG child, and the fuzzer

def drv.at(xs: List<&2, U32>, k: U32) -> U32:
  drv.nth(List.get(&2, U32, xs, U32.to_nat(k)))

def drv.pick.go(ks: List<&2, U32>, +xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}: acc
    case k <> t: drv.pick.go(t, xs, List.append(&2, U32, acc, [drv.at(xs, k)]))

def drv.pick(ks: List<&2, U32>, +xs: List<&2, U32>) -> List<&2, U32>:
  drv.pick.go(ks, xs, Nil{})

def drv.src.of(tag: String, rest: String, +xs: List<&2, U32>) -> O.SrcArg:
  match tag:
    case "-": O.SNone{}
    case "r": O.SOne{drv.at(xs, drv.first(rest))}
    case "t": O.STuple{drv.pick(drv.ids(rest), xs)}
    case _: O.SList{drv.pick(drv.ids(rest), xs)}

def drv.src.of2(+s: String, +xs: List<&2, U32>) -> O.SrcArg:
  drv.src.of(String.take(s, 1n), String.drop(s, 1n), xs)

def drv.am.of(tag: String, rest: String) -> Maybe<&2, O.Arg>:
  match tag:
    case "-": None{}
    case "i": Some{O.ATuple{[drv.first(rest)]}}
    case "s": Some{O.AStr{"z"}}
    case _: Some{O.ATuple{drv.ids(rest)}}

def drv.am.of2(+s: String) -> Maybe<&2, O.Arg>:
  drv.am.of(String.take(s, 1n), String.drop(s, 1n))

def drv.bit.of(s: String) -> Bool:
  String.eq(s, "1")

# ONE node, and the fold that threads the arena. `UPat.of` is the whole construction API
# the input's field 4 is the tag, and it is accepted and ignored. The driver's input format

def drv.build(+ns: List<&2, String>, +pat: O.Pat, +xs: List<&2, U32>) -> O.PatFound:
  +s: O.SrcArg = drv.src.of2(drv.field(ns, 5), xs)
  O.UPat.of(pat, drv.opm.of(drv.field(ns, 0)), drv.dtm.of(drv.field(ns, 3)), s, drv.am.of2(drv.field(ns, 2)),
    drv.nm.of(drv.field(ns, 1)), drv.bit.of(drv.field(ns, 7)), None{},
    drv.bit.of(drv.field(ns, 6)))


def drv.go(+ns: List<&2, String>, +pat: O.Pat, +xs: List<&2, U32>, +i: U32) -> O.PatFound:
  match ns:
    case Nil{}: O.PatFound{pat, i}
    case n <> t:
      +f: O.PatFound = drv.build(String.split(n, ';'), pat, xs)
      drv.go(t, O.PatFound.pat(f), List.append(&2, U32, xs, [O.PatFound.i(f)]),
        O.PatFound.i(f))


def drv.head(ps: List<&2, String>) -> String:
  drv.one(List.get(&2, String, ps, 0n))

def drv.rest(ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}: Nil{}
    case _ <> t: t

def drv.rest1(ps: List<&1, String>) -> List<&1, String>:
  match ps:
    case Nil{}: Nil{}
    case _ <> t: t

def drv.ctx(s: String) -> Bool:
  match s:
    case "noctx": False{}
    case _: True{}


def drv.out.of(r: Maybe<&2, Code>) -> String:
  match r:
    case Some{+c}: String.concat([String.join(String.split(Code.s(c), '\n'), "\\n"),
      " | ", String.join(dyn_names(Code.dyn(c)), ",")])
    case None{}: "NONE"

def drv.run(p: String) -> IO(Unit):
  do IO<Unit>:
    line : String <- H.printable(p, 1)
    +ps : List<&2, String> <- IO.pure(List<&2, String>, String.split(line, '|'))
    +f : O.PatFound <- IO.pure(O.PatFound, drv.go(drv.rest(ps), O.Pat{Nil{}}, Nil{}, 0))
    IO.print(drv.out.of(upat_compile(O.PatFound.pat(f), O.PatFound.i(f),
      drv.ctx(drv.head(ps)))))

def gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("var", code_is(pat_var(), True{}, want_var()))
    b : Unit <- row("add", code_is(pat_add(), True{}, want_add()))
    c : Unit <- row("add_dyn", dyn_is(pat_add(), True{}, ["a0"]))
    d : Unit <- row("repeat", code_is(pat_repeat(), True{}, want_repeat()))
    e : Unit <- row("repeat_dyn", dyn_is(pat_repeat(), True{}, ["a0", "a1"]))
    f : Unit <- row("any", code_is(pat_any(), True{}, want_any()))
    g : Unit <- row("noctx", code_is(pat_var(), False{}, want_noctx()))
    h : Unit <- row("argint", code_is(pat_argint(), True{}, want_argint()))
    i : Unit <- row("too_big", is_none(pat_bigor(), True{}))
    j : Unit <- row("rep_src", code_is(pat_rep_src(), True{}, want_rep_src()))
    k : Unit <- row("rep_src_src", code_is(pat_rep_src_src(), True{}, want_rep_src_src()))
    l : Unit <- row("any_rep", code_is(pat_any_rep(), True{}, want_any_rep()))
    m : Unit <- row("dup_store", code_is(pat_dup_store(), True{}, want_dup_store()))
    n : Unit <- row("share", code_is(pat_share(), True{}, want_share()))
    o : Unit <- row("rep_src_dyn", dyn_is(pat_rep_src(), True{}, ["a0", "a1", "a2"]))
    p : Unit <- row("set_ord", code_is(pat_set_ord(), True{}, want_set_ord()))
    q : Unit <- row("store_ord", code_is(pat_store_ord(), True{}, want_store_ord()))
    r : Unit <- row("deep", code_is(pat_deep(), True{}, want_deep()))
    show(pat_add(), True{})


def dispatch(ps: List<&1, String>) -> IO(Unit):
  match ps:
    case Nil{}: gate()
    case p <> _: drv.run(p)

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    u : Unit <- dispatch(drv.rest1(as))
    IO.pure(Unit, u)

