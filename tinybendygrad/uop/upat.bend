# upat.bend -- tinygrad/uop/upat.py.
#
# WHAT THIS FILE IS. ops.bend builds the arena; this file is the COMPILER that
# turns a `UPat` into source text, and ops.bend's NOT PORTED block already names
# it: "the COMPILER is a separate file whose output is a def per rule, so the
# machinery here dispatches a tag rather than calling a compiled function
# pointer". The pipeline is three steps and no more:
#
#     UPat --_get_clause--> a predicate tree --do_process_and--> normalised
#         --pm_renderer--> a string tree     --_final_render--> Python source
#
# # **** UPat compiled ****
# # This file builds an IR of match predicates and compiles them to Python source.
# # Ops used: CUSTOM (format-string predicate over operands), CUSTOMI (inline string fragment),
# #           STORE (bind a matched UOp to a name), PYLITERAL (Python literal for CUSTOM operands),
# #           AND/OR (clause combininers).
#
# THE PREDICATE TREE IS A TREE, NOT AN ARENA. Python builds the IR out of
# `UOp(...)`, so it lands in the same `ucache` as the graph and two equal
# subtrees are ONE object -- which is what `dedup` and the duplicate-store test
# in `do_process_and` rely on. Here the node is `C{op, lit, ss}` and equality is
# `eq_c`, structural. Same answers. The ONE place sharing shows is a
# permutation `src` (`itertools.permutations`, ops.py:1469), where the same
# sub-pattern is visited once per alternative, and that is what the fuel below
# bounds. The clause IR is finite and acyclic by construction, so nothing here
# needs the arena's index-into-a-store.
#
# THE `(bool, dict)` BECOMES A `String`. `upat_compile` returns a Python closure
# built by `exec`ing the string this file renders. Bend has no `exec`, no `eval`
# and no way to build a function value, so the honest terminal value is the
# SOURCE, and the two consumers of the dict become parts of that string. So:
#
#   * `ctx` (the `dyn_lookup` dict) is a `List<&2, Bind>` THREADED through the
#     renderer. It is not a field of a record: a dict is mutable, a Bend list is
#     affine and has one owner, and a mutation is a new list. This is the second
#     store ops.bend's header predicts, and it travels as a parameter beside
#     the tree, not inside it.
#   * `_get_code`'s `(str, dict)` is a `Code` record and not a pair, because a
#     pair is a `Type` and every reader of one has to match a computed value --
#     which is the whole reason ops.bend's `Found` is a two-field record.
#   * `upat_compile` therefore returns the `Code` and `exec` is the WALL. The
#     phase that owns it is P3 with the rewrite engine, because a compiled rule
#     is a function value and rules become top-level defs.
#
# `# exec` IS THE ONE OMISSION and it is the LAST step, so everything this file
# knows is still checked: `_get_code` returns exactly the string Python builds
# and `main` prints rows built from it.
#
# A PYTHON `raise` BECOMES A NODE, uniformly, and it is one node: `marker()`.
# `_final_render`'s `else` arm refuses anything that is not OR, STORE or
# CUSTOMI, and a CONST is none of those, so a `UPatCompileError` and a fuel
# exhaustion are both "a CONST where a predicate belongs". `start_ss` therefore
# KEEPS a node that is not an AND instead of dropping it -- the port's `assert
# x.op is AND` -- and `rend.go`'s `case _` sets `bad`, which is the port's
# `raise`. The answer is then `None`, which is what `_get_code`'s `except`
# returns, and a truncated clause is IMPOSSIBLE, because the marker rides the
# same path as a real predicate. `bool` flags are the other option and they are
# worse: `found` is read in five places in `do_process_and` and a `Bool` in the
# accumulator would be threaded through all of them for a failure the tree can
# carry.
#
# THE FUEL is one unit per step and it is a BOUND, not an exact count: every
# `case 0n:` below yields `marker()`, so too small a fuel is a MISSED compile and
# never a wrong one. The bound is `8 * len(pat.upats)`: `__init__` builds a
# UPat's children before the UPat, so the pattern is a tree, a UPat contributes
# at most six predicate nodes of its own plus its `src`, and `_get_clause` visits
# a UPat once per alternative naming it -- which `itertools.permutations` can
# double, and ops.bend already records `permutations` at arity >= 3 as not
# ported. Four walks need it and no others do: `_get_clause` and `proc_fix`
# recurse on a pattern-arena INDEX or on a fuel of their own, and `flatands`,
# `wrap` and `rend.go` recurse on a field or a list tail.
#
# `pm_proc` IS A FIXPOINT AND THAT IS LOAD-BEARING. `do_process_and` splices ONE
# level of AND per application, so `AND[C, C, AND(OR..) x4]` needs a second
# round before `len(or_clause) >= 4` can see four ORs -- which is the only way
# `too big to compile` is reachable at all, and the row `too_big` in `main` is
# the proof. Measured against CPython, not guessed.
#
# THREE BEND RULES SHAPED THE SHAPE. (1) No mutual recursion: `A` may not call
# `B` if `B` calls `A`, whatever the order, and the error is the very unhelpful
# "an unfilled definition". So each recursive descent here is ONE self-recursive
# def -- `get_clause.go` for the clause walk, `rend.go` for the render, `proc`
# for the rewrite -- and every helper it needs is a leaf. (2) A self-call must
# be DECREASING, read left to right: the arguments before the one that shrinks
# are passed unchanged, so the `Nat` fuel is the FIRST parameter of every
# self-recursive def here, and an arm that needs the old fuel twice writes
# `+z: Nat = q` and calls itself with `z`. (3) A `match` kills every name bound
# earlier in the same body -- parameters AND pattern binders -- so the flags a
# def dispatches on are read in one order and never re-read after another
# `match`. `rend.go`'s `br` is inside all four op arms for exactly that reason.
#
# WHERE THE ORDER MOVED. Bend has no forward references, so the field readers
# and the equality helpers come first, then the three passes in Python's order.
# The straight line of `if`s in `_get_clause` is spelled as one `Bool` match
# per check, because a `Bool` match IS the whole of an `if` here.

import Base
import ./ops.bend as O
import ./../LAWS/spec.bend as S
type Lit is Data:
  LNone{}
  LText{s: String}
  LOps{ys: List<&2, O.Op>}
  LDt{ys: List<&2, S.Dt>}
  LTag{ys: List<&2, O.Tag>}
  LArg{a: O.Arg}
  LInt{n: U32}
# ===========================================================================
# The predicate IR. One constructor, because the renderer's rules are keyed on
# the op and the op IS the discriminant; a variant per op would be eight
# constructors the `match` below could not collapse.
#
# `lit` is Python's `arg`, and the two things Python puts there are a STRING
# (CUSTOM's format, CUSTOMI's text) and a PYTHON LITERAL (PYLITERAL, CONST's
# `val`). `LOps`/`LDt`/`LTag` hold a LIST because Python's payload is a tuple
# of length one or a `frozenset`, and `len(self.op) > 1` is the test that
# chooses between them -- so the length is the same information Python has.
# ===========================================================================
# `C{op, lit, ss}` is `UOp(Ops.X, src=..., arg=...)`. The tag is `None` on every
# node this file builds and no rule here reads it, so it is not a field.

type C is Data:
  C{op: O.Op, lit: Lit, ss: List<&2, C>}
# Python's `ctx`, the `dyn_lookup` the renderer fills: an `a{n}` NAME and the
# Python LITERAL it stands for. Python keeps the object; here the object is a
# `Lit` and turning a `Lit` into Python source is the P3 host's, because that
# is where `repr` of an `Ops` or a `DType` lives.

type Bind is Data:
  Bind{name: String, lit: Lit}
# `_get_code`'s pair.

type Code is Data:
  Code{s: String, dyn: List<&2, Bind>}
# `x.arg[0]`: the format string of a CUSTOM and the text of a CUSTOMI, and the
# only `arg` read anywhere in the file. `Maybe` because `LNone` has no text.

def lit.text(l: Lit) -> Maybe<&2, String>:
  match l:
    case LText{s}: Some{s}
    case _ : None{}
# `text_of`, and CONST's `.val`, which `_get_clause` writes as an int and the
# INDEX rule reads back.


# `y.arg[0]` for a src, the text of a CUSTOMI

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
# A one-element `List`, which is what `self.op[0]` and `self.match_dtype[0]`
# are: the head of a list Python already knows has one element.

def head1(ys: List<&2, U32>) -> Maybe<&2, U32>:
  match ys:
    case Nil{}: None{}
    case y <> t:
      match t:
        case Nil{}: Some{y}
        case _ <> _: None{}
# The marker, and the ONE `raise` channel. See the header.

def marker() -> C:
  C{O.OpsCONST{}, LInt{0}, Nil{}}

# `ret = _get_clause(self, UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))`
# `8 * len(pat.upats)`: the header's bound. A BOUND, not a count, and every
# `case 0n:` is `marker()`, so too small a fuel is a missed compile.

def fuel(pat: O.Pat) -> Nat:
  Nat.mul(List.length(&2, O.UPat, O.Pat.upats(pat)), 8n)

def base_clause() -> C:
  C{O.OpsCUSTOMI{}, LText{"uop"}, Nil{}}


# the one-element read, which is what a `List<&2, C>` fold over a single node
# answers and what the wrap pass hands back: the tree, not a group list

def head1c(gs: List<&2, C>) -> C:
  match gs:
    case Nil{}: marker()
    case c <> _: c

# `==` on a literal, which is what `dedup` and the duplicate-store test ask.
# Python gets it from `ucache` (two equal nodes are one object and `UOp.__eq__`
# is identity); here it is spelled out.

def eq_lit(a: Lit, b: Lit) -> Bool:
  match a b:
    case LNone{} LNone{}: True{}
    case LText{x} LText{y}: String.eq(x, y)
    case LOps{x} LOps{y}: O.eq_op_list(x, y)
    case LDt{x} LDt{y}: O.eq_dt_list(x, y)
    case LTag{x} LTag{y}: O.eq_tag_list(x, y)
    case LArg{x} LArg{y}: O.eq_arg(x, y)
    case LInt{x} LInt{n}: U32.is_eq(x, n)
    case _ _: False{}
# `==` on a node. The two-list fold IS the recursion and there is NO fuel: a
# `Data` node's own field is a subterm of a list of that type, so `eq_csl(ss, ..)`
# descends on `ss` -- a FIELD of the head binder of `xs` -- exactly as the tail
# does. `dedup` and `substitute` get this for free and `_get_clause` cannot,
# because its children are indices into the pattern arena.

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
# ===========================================================================
# flatands -- upat.py:12. `[x] if x.op is not AND else [y for s in x.src for y
# in flatands(s)]`, the top level of a tree walk, and the ONE walk in this file
# whose ORDER matters (it is the order the stores and preds are emitted in).
#
# The walk and the per-node dispatch are ONE def: a fold whose per-element work
# is the recursive function cannot be split from it, because that is mutual
# recursion. The `Maybe` is the walk's mode -- `Some` is "start at this node",
# `None` is "continue over the pending children" -- and the node's children
# become the pending list, so there is one pending list and no flag to disagree
# with it.
# ===========================================================================

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
# ===========================================================================
# substitute -- ops.py:532 `UOp.substitute`, the one call in this file, in
# `{it: base.index(0)}`: every node equal to `it` becomes the replacement, the
# rest is rebuilt. `ops.py:532` is NOT PORTED as a UOp method (it is a
# `graph_rewrite` with `_substitute`); this is the same rewrite over the clause
# tree, and it is the ONLY reason the clause tree needs a top-down map.
# ===========================================================================

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
      List.append(&2, C, a, [substitute.put(eq_c(C{op, lit, k}, it), op, lit, b, rep)])

def substitute(t: C, +it: C, +rep: C) -> C:
  match t:
    case C{+op, +lit, +ss}: substitute.put(eq_c(C{op, lit, ss}, it), op, lit, substitute.go(ss, it, rep), rep)

def ge2(n: Nat) -> Bool:
  match n:
    case 2n+p: True{}
    case _ : False{}
# `if len(or_clause) >= 4: raise UPatCompileError("too big to compile")`

def ge4(n: Nat) -> Bool:
  match n:
    case 4n+p: True{}
    case _ : False{}
# `f"{0}.op in {1}"` for a frozenset and `f"{0}.op is {1}"` for one op. The
# three `pick`s differ only in the fmt strings and the payload, and each is
# written out because the payloads are three different `Lit` variants.

def op_clause.pick(two: Bool, ys: List<&2, O.Op>, base: C, many: String, one: String) -> List<&2, C>:
  match two:
    case True{}: [C{O.OpsCUSTOM{}, LText{many}, [base, C{O.OpsPYLITERAL{}, LOps{ys}, Nil{}}]}]
    case False{}: [C{O.OpsCUSTOM{}, LText{one}, [base, C{O.OpsPYLITERAL{}, LOps{ys}, Nil{}}]}]

def op_clause.of(ops: Maybe<&2, List<&2, O.Op>>, base: C) -> List<&2, C>:
  match ops:
    case Some{+ys}: op_clause.pick(ge2(List.length(&2, O.Op, ys)), ys, base, "{0}.op in {1}", "{0}.op is {1}")
    case None{}: Nil{}
# `isinstance(self.arg, int)`. Python's `int` is a BARE scalar and `Arg` has no
# variant for one: `ATuple` is `tuple[int, ...]`, `APy` is a `PyConst` and
# `AFloat` is a float, so none of the eighteen is a Python `int`. The port reads
# a ONE-ELEMENT `ATuple` as the int -- it is the only shape that is a bare
# scalar, it is what `coalesce.py:105`'s `UPat(arg=4)` is, and it is disjoint
# from the multi-element tuple the other arm renders as a literal. P3 with `Arg`.

def arg_int(a: O.Arg) -> Maybe<&2, U32>:
  match a:
    case O.ANone{}: None{}
    case O.ADt{_}: None{}
    case O.APy{_}: None{}
    case O.AParam{_}: None{}
    case O.ACall{_}: None{}
    case O.AKernel{_}: None{}
    case O.AProgram{_}: None{}
    case O.ARange{_, _}: None{}
    case O.AReduce{_, _}: None{}
    case O.AWmma{_, _, _, _}: None{}
    case O.ATuple{ys}: head1(ys)
    case O.AStr{_}: None{}
    case O.AInk{_, _}: None{}
    case O.AAllred{_, _}: None{}
    case O.ADev{_}: None{}
    case O.ABlob{_}: None{}
    case O.AFloat{_}: None{}
    case O.ABad{}: None{}
# `"{0}.arg == "+str(int(self.arg))` is INLINED, so no `a{n}` is spent on it --
# which is why the oracle's `UPat(Ops.CALL, arg=4)` has one dyn entry and not two.

def arg_clause.hit(m: Maybe<&2, U32>, a: O.Arg, base: C) -> List<&2, C>:
  match m:
    case Some{n}: [C{O.OpsCUSTOM{}, LText{String.concat(["{0}.arg == ", U32.show(n)])}, [base]}]
    case None{}: [C{O.OpsCUSTOM{}, LText{"{0}.arg == {1}"}, [base, C{O.OpsPYLITERAL{}, LArg{a}, Nil{}}]}]

def arg_clause.of(a: Maybe<&2, O.Arg>, base: C) -> List<&2, C>:
  match a:
    case Some{+x}: arg_clause.hit(arg_int(x), x, base)
    case None{}: Nil{}
# `"len({0}.src)"+(" == " if self.strict_length else " >= ")+str(self.required_len)`

def len_clause.mid(strict: Bool) -> String:
  match strict:
    case True{}: " == "
    case False{}: " >= "

def len_clause.of(want: Bool, strict: Bool, req: U32, base: C) -> List<&2, C>:
  match want:
    case True{}: [C{O.OpsCUSTOM{},
      LText{String.concat(["len({0}.src)", len_clause.mid(strict), U32.show(req)])}, [base]}]
    case False{}: Nil{}
# `UOp(Ops.STORE, src=(UOp(Ops.CUSTOMI, arg=(self.name, dtypes.void)), base))`

def name_clause.of(n: Maybe<&2, String>, base: C) -> List<&2, C>:
  match n:
    case Some{s}: [C{O.OpsSTORE{}, LNone{}, [C{O.OpsCUSTOMI{}, LText{s}, Nil{}}, base]}]
    case None{}: Nil{}
# `"{0}.dtype in {1}"` / `"{0}.dtype is {1}"`

def dt_clause.pick(two: Bool, ys: List<&2, S.Dt>, base: C, many: String, one: String) -> List<&2, C>:
  match two:
    case True{}: [C{O.OpsCUSTOM{}, LText{many}, [base, C{O.OpsPYLITERAL{}, LDt{ys}, Nil{}}]}]
    case False{}: [C{O.OpsCUSTOM{}, LText{one}, [base, C{O.OpsPYLITERAL{}, LDt{ys}, Nil{}}]}]

def dt_clause.of(md: Maybe<&2, List<&2, S.Dt>>, base: C) -> List<&2, C>:
  match md:
    case Some{+ys}: dt_clause.pick(ge2(List.length(&2, S.Dt, ys)), ys, base, "{0}.dtype in {1}", "{0}.dtype is {1}")
    case None{}: Nil{}
# `"{0}.tag in {1}"` / `"{0}.tag == {1}"` -- note `==` and not `is` for one tag.

def tag_clause.pick(two: Bool, ys: List<&2, O.Tag>, base: C, many: String, one: String) -> List<&2, C>:
  match two:
    case True{}: [C{O.OpsCUSTOM{}, LText{many}, [base, C{O.OpsPYLITERAL{}, LTag{ys}, Nil{}}]}]
    case False{}: [C{O.OpsCUSTOM{}, LText{one}, [base, C{O.OpsPYLITERAL{}, LTag{ys}, Nil{}}]}]

def tag_clause.of(mt: Maybe<&2, List<&2, O.Tag>>, base: C) -> List<&2, C>:
  match mt:
    case Some{+ys}: tag_clause.pick(ge2(List.length(&2, O.Tag, ys)), ys, base, "{0}.tag in {1}", "{0}.tag == {1}")
    case None{}: Nil{}
# the seven `if`s, in Python's order

def pieces(u: O.UPat, +base: C) -> List<&2, C>:
  match u:
    case O.UPat{op, md, mt, arg, name, _, _, _, +strict, +req, _}:
      List.concat(&2, C, [op_clause.of(op, base), arg_clause.of(arg, base),
        len_clause.of(Bool.or(strict, U32.is_gt(req, 0)), strict, req, base),
        name_clause.of(name, base),
        dt_clause.of(md, base), tag_clause.of(mt, base)])
# `base.index(i)`: an INDEX over the base and a CONST carrying the index. The
# CONST's dtype is `dtypes.from_py(i)` and no rule here reads it.

def base_index(base: C, k: U32) -> C:
  C{O.OpsINDEX{}, LNone{}, [base, C{O.OpsCONST{}, LInt{k}, Nil{}}]}
# `it = UOp(Ops.CUSTOMI, arg=(f"ituop{depth}", dtypes.void))`

def it(depth: U32) -> C:
  C{O.OpsCUSTOMI{}, LText{String.concat(["ituop", U32.show(depth)])}, Nil{}}
# ===========================================================================
# The src arm, and the fold that carries it.
#
# `Groups` is `List<&2, List<&2, C>>`: one group per ALTERNATIVE, and a group is
# that alternative's predicate pieces. The three src arms differ only in how they
# fill it, and the assembly at the end is the only place that knows which:
#   * one fixed alternative, not `is_any` -- the children's pieces are APPENDED
#     to the node's own seven, so a group per child and a group per alternative
#     give the same AND.
#   * one fixed alternative, `is_any` -- `AND(OR(child for child in children))`,
#     so each child is its own group and its own AND.
#   * more than one alternative (the `permutations` path) -- the OR's children
#     are ANDs of one alternative each, so a group per alternative.
# So `ys` and `alts` never both have to be live, and which one is live is `rep`
# and `forked` at the base case.
#
# The FUEL is here and nowhere else in the file, because a child's UPat is an
# INDEX into the pattern arena, and `ys_of(child)` is a computed value: there is
# no field to descend on. The walk, the per-child build and the alternative walk
# are therefore ONE def -- splitting them is mutual recursion, which is refused.
# `nested` is the fork's inner walk: it returns its groups without assembling a
# node, because the OR wants the pieces and not an AND.
# ===========================================================================

def nth.of(hit: Maybe<&2, O.UPat>) -> O.UPat:
  match hit:
    case Some{u}: u
    # the arena's bottom, the same shape `O.pat_nth.of` answers `None` with
    case None{}: O.UPat{None{}, None{}, None{}, None{}, None{}, O.SNone{}, Nil{}, False{}, False{}, 0, Nil{}}

def nth(pat: O.Pat, n: U32) -> O.UPat:
  nth.of(List.get(&2, O.UPat, O.Pat.upats(pat), U32.to_nat(n)))
# the children of ONE alternative, and the alternatives themselves. `UpRepeat`
# holds the ONE index `next(self.src[0])` names, so it reads as a one-child
# alternative; the `RuntimeError("broken")` is `broken_of` below.

def alt_ys(a: O.UpAlt) -> List<&2, U32>:
  match a:
    case O.UpFixed{ys}: ys
    case O.UpRepeat{x}: [x]

# the ONE alternative that is a repeat, which is the only arm that recurses on
# `next(self.src[0])` instead of enumerating

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

# ===========================================================================
# _get_clause -- upat.py:15. `UPat` -> the predicate tree.
#
# The seven `if`s of the and_clause are seven defs here, because a `Bool` match
# IS an `if` and there is no other spelling. Each returns an empty list or a
# one-element list, and `pieces` concatenates them in Python's order: op, arg,
# len, name, dtype, tag.
#
# A PYLITERAL always carries the WHOLE list, never just its head: at length one
# `LOps{ys}` and `LOps{[ys[0]]}` are the same value, so the singular arm costs
# nothing to spell as the plural arm's list, and the only difference between the
# two forms -- the FORMAT STRING -- is chosen by `ge2`.
# ===========================================================================
# `len(self.op) > 1`, the one test that picks a frozenset over a single value.
# A `match` may not scrutinise `List.length(..)`, so the length is a parameter
# and this is the whole of the test.

def one_alt(alts: List<&2, O.UpAlt>) -> Bool:
  match alts:
    case Nil{}: False{}
    case _ <> rest: List.is_empty(&2, O.UpAlt, rest)


# `len(self.src) > 1`: no alternative is not a fork, one is a single match

def forked_of(alts: List<&2, O.UpAlt>) -> Bool:
  Bool.not(List.is_empty(&2, O.UpAlt, more_alts(alts)))

type Rp is Data:
  Rp{pred: List<&2, C>, extra: List<&2, C>}

# `assert len(self.src) == 1` and `raise RuntimeError("broken")`, the two ways
# `_get_clause` can fail before it builds anything. NEITHER is reachable from the
# ported constructors: ops.bend's `UPat.or_any` always wraps ONE tuple, and
# `__init__` makes a `repeat` alternative only for a UPat `src`, which is never a
# list. This is a guard on the DATATYPE, and it exists because `SrcArg` can
# spell a shape `__init__` cannot build.

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
# the child's base and depth. A repeat's child is built against `it` at
# `depth+1`; a fixed child's against `base.index(i)` at `depth`.

def broken_of(+u: O.UPat) -> Bool:
  broken_of.of2(O.UPat.src(u), O.UPat.is_any(u))


# `is_any` matches every alternative against the SAME base and a repeat against
# the fresh `it`, so the two cases that do not read `base.index(i)` come first

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
# `UOp(Ops.AND, src=tuple(and_clause)) if and_clause else UOp(Ops.CUSTOMI,
# arg=("True", dtypes.void))` -- the two shapes a clause can end in, and
# `_final_render`'s `f"...if {and_clause if len(and_clause) else 'True'}..."`.

def and_one(+cs: List<&2, C>) -> C:
  Bool.pick(C, List.is_empty(&2, C, cs), C{O.OpsCUSTOMI{}, LText{"True"}, Nil{}}, C{O.OpsAND{}, LNone{}, cs})

def flat(gs: List<&2, List<&2, C>>) -> List<&2, C>:
  List.concat(&2, C, gs)


# `UOp(Ops.AND, src=tuple(and_clause)) if and_clause else UOp(Ops.CUSTOMI,
# arg=("True", dtypes.void))` -- and the test is on the WHOLE and_clause, which is
# the node's own pieces ++ the src arm's, not on the second half alone.

def or_true.put(pse: Bool, +ps: List<&2, C>, +cs: List<&2, C>) -> C:
  Bool.pick(C, Bool.and(pse, List.is_empty(&2, C, cs)), C{O.OpsCUSTOMI{}, LText{"True"}, Nil{}},
    C{O.OpsAND{}, LNone{}, List.append(&2, C, ps, cs)})

def or_true(+ps: List<&2, C>, +cs: List<&2, C>) -> C:
  or_true.put(List.is_empty(&2, C, ps), ps, cs)


# `is_any` returns before the pieces exist, and both `is_any` and the fork arm
# end in ONE OR whose branches are the per-alternative ANDs, so they share the
# shape and only `or_true` (which keeps the pieces) tells them apart

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

# the assembly: the ONE place that knows which src arm filled the groups

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

# ===========================================================================
# The repeat arm -- `elif len(self.src) == 1 and isinstance(self.src[0],
# itertools.repeat)`. It is the only src arm that does not concatenate, and the
# one place a named bind inside a repeated pattern is lifted to the OUTER clause.
# Python's comment is the reason, and it is the rule the whole arm exists for:
#
#   # lift named binds out of the repeat: they bind the first src, and every
#   # element must be identical to it
#
# `it` is the loop variable `ituop{depth}`, `first0` is `base.index(0)`, and the
# `all([...])` predicate's three operands are the predicate AND, the loop
# variable and the base -- in that order, because that is the format string's.
# ===========================================================================
# `for st in stores:` -- `pred.append(CUSTOM(st.src[1], first, "{0} is {1}"))`
# then `and_clause.append(STORE(st.src[0], first))`, so the identity compares the
# ORIGINAL and the SUBSTITUTED and the store keeps the substituted.

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
# `if len(stores): and_clause.append(CUSTOM(base, "len({0}.src) != 0"))`

def rep_len(has: Bool, base: C) -> List<&2, C>:
  Bool.pick(List<&2, C>, has, [C{O.OpsCUSTOM{}, LText{"len({0}.src) != 0"}, [base]}], Nil{})
# `CUSTOM(AND(pred), it, base, "all([{0} for {1} in {2}.src])")`. The AND is bare
# even when `pred` is empty, which is what Python writes.

def rep_all(base: C, i: C, d: Rp) -> List<&2, C>:
  [C{O.OpsCUSTOM{}, LText{"all([{0} for {1} in {2}.src])"},
    [C{O.OpsAND{}, LNone{}, Rp.pred(d)}, i, base]}]

def get_clause.rep.put(+u: O.UPat, +base: C, i: C, +d: Rp) -> C:
  or_true(pieces(u, base),
    List.concat(&2, C, [Rp.extra(d), rep_len(ne(Rp.extra(d)), base), rep_all(base, i, d)]))

def get_clause.rep.of(+u: O.UPat, +base: C, depth: U32, +d: Rp) -> C:
  get_clause.rep.put(u, base, it(depth), d)
# `match = _get_clause(next(self.src[0]), it, depth+1)` is the group already in
# `gs`, and `flatands(match)` of it is that group flattened.

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
# `for x in a.src: if x.op is AND: new_src.extend(x.src) elif x.op is OR:
# or_clause.append(x) else: new_src.append(x)`

def split.step(op: O.Op, lit: Lit, k: List<&2, C>, +sp: Sp) -> Sp:
  match op:
    case O.OpsAND{}: Sp{List.concat(&2, C, [Sp.srcs(sp), k]), Sp.ors(sp), True{}}
    case O.OpsOR{}: Sp{Sp.srcs(sp), List.append(&2, C, Sp.ors(sp), [C{op, lit, k}]), Sp.flat(sp)}
    case _ : Sp{List.append(&2, C, Sp.srcs(sp), [C{op, lit, k}]), Sp.ors(sp), Sp.flat(sp)}

def split.go(+ss: List<&2, C>, sp: Sp) -> Sp:
  match ss:
    case Nil{}: sp
    case C{op, lit, k} <> t: split.go(t, split.step(op, lit, k, sp))
# `itertools.product(*[x.src for x in or_clause])`: the LAST list varies fastest,
# so each new OR's children are appended to each combination made so far.

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
# `x.replace(src=x.src+tuple(stores))` for each alternative of the single OR.
# The `assert all(x.op is AND ...)` is stated, not checked: `do_process_and` only
# ever builds an OR of ANDs, and a repeat's `all([...])` is its own CUSTOM.

def push.go(+xs: List<&2, C>, +stores: List<&2, C>, acc: List<&2, C>) -> List<&2, C>:
  match xs:
    case Nil{}: acc
    case C{op, lit, k} <> t:
      push.go(t, stores, List.append(&2, C, acc, [C{op, lit, List.append(&2, C, k, stores)}]))
# `dict_stores`: the first STORE of a name wins, and a repeat of it becomes the
# identity `CUSTOM(first, second, "{0} is {1}")` with `found = True`.

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

def dup.put(hit: Bool, k: C, v: C, +d: Ds) -> Ds:
  match hit:
    case True{}: Ds{Ds.ks(d), Ds.vs(d),
      List.append(&2, C, Ds.out(d), [C{O.OpsCUSTOM{}, LText{"{0} is {1}"}, [k, v]}]), True{}}
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

# `for k,v in dict_stores.items(): new_src.append(STORE(k,v))`

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
# the OR list, the duplicate stores and the `found` flag. `Rec` is the tuple
# Python's three locals spell, and the store branch is the only thing that
# changes any of them.

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
# `dict_stores` then `for k,v in dict_stores.items(): new_src.append(STORE(k,v))`

def do_process_and.dup.of(ors: List<&2, C>, +d: Ds) -> Rec:
  Rec{ors, d, Ds.dup(d)}

def do_process_and.dup(ors: List<&2, C>, r: Rp) -> Rec:
  do_process_and.dup.of(ors, dup.go(Rp.extra(r), empty_ds()))
# `if len(stores)`: the OR takes them, otherwise the duplicates become identities
# `itertools.product(*[x.src for x in or_clause])`: the LAST list varies fastest,
# `x.replace(src=x.src+tuple(stores))` for each alternative of the single OR.
# The `assert all(x.op is AND ...)` is stated, not checked: `do_process_and` only
# ever builds an OR of ANDs, and a repeat's `all([...])` is its own CUSTOM.
# `itertools.product(*[x.src for x in or_clause])`, one AND per combination

def map_and(+xs: List<&2, List<&2, C>>) -> List<&2, C>:
  match xs:
    case Nil{}: Nil{}
    case x <> t: List.append(&2, C, [and_one(x)], map_and(t))

# The three ways a clause can end. `is_any` returns before the pieces exist and
# wraps one OR of the alternatives; the fork keeps the pieces and appends ONE OR
# of per-permutation ANDs; a single match keeps the pieces and appends the
# children as the SIBLINGS Python's `and_clause +=` puts them in. The two OR
# arms read the same shape -- `map_and` because a fork branch is the AND of a
# whole permutation, `flat` because an `is_any` branch is a clause already.

def get_clause.assemble(any: Bool, forked: Bool, +gs: List<&2, List<&2, C>>, ps: List<&2, C>) -> C:
  match any forked:
    case True{} _: and_one([C{O.OpsOR{}, LNone{}, flat(gs)}])
    case False{} True{}: or_true(ps, [C{O.OpsOR{}, LNone{}, map_and(gs)}])
    case False{} False{}: or_true(ps, flat(gs))

def get_clause.of(+u: O.UPat, +base: C, forked: Bool, +gs: List<&2, List<&2, C>>) -> C:
  get_clause.assemble(O.UPat.is_any(u), forked, gs, pieces(u, base))
# the base case. `nested` returns the groups untouched; `rep` runs the repeat's
# store lifting, which is the one arm that does NOT just concatenate.
# ===========================================================================
# partition -- helpers.py:90, for `is_store`. `Rp` is the pair it returns: `pred`
# is what the predicate keeps and `extra` is what is set aside.
# ===========================================================================

def get_clause.done(+u: O.UPat, +base: C, depth: U32, f: Nat, forked: Bool, nested: Bool, rep: Bool, gs: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match nested rep:
    case True{} _: gs
    case False{} False{}: [[get_clause.of(u, base, forked, gs)]]
    case False{} True{}: [[get_clause.rep(u, base, depth, f, gs)]]
# `alts` is DECLARED BEFORE `ys` because the two `match`es below are in that
# order, and a match on a later parameter makes every earlier name unmatchable
# ("this name is a def or a consumed binder"). Measured, and the least obvious
# rule in `.agents/slop/notes/bend2-constraints.md` #5: the def works if the two
# parameters are swapped, with the body untouched.


# `len(self.src) == 1` is a single match -- `is_any` included, and both are
# `and_clause += [clause(s), ...]` with the children SIBLINGS, so the groups go
# in as they are. Anything longer is the fork, whose OR branch is the AND of one
# permutation's children, so the whole alternative is ONE group.

def alt_group(one: Bool, +a: List<&2, List<&2, C>>) -> List<&2, List<&2, C>>:
  match one:
    case True{}: a
    case False{}: [List.concat(&2, C, a)]
# `if len(or_clause) > 1: or_clause = [OR(...)]`

# A CHILD'S GROUPS GO IN AS THEY ARE: `get_clause.done` already answered
# `[[clause]]` -- one group holding the clause node Python would have put in
# `and_clause` directly -- so re-wrapping it is what put a second AND level
# under every `is_any` branch.

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
                True{}, False{}, False{}, Nil{})
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
# ===========================================================================
# do_process_and -- upat.py:51. The `pm_proc` rule: one rewrite per AND node,
# applied bottom up, which flattens the nested ANDs `_get_clause` builds and
# hoists the stores above the OR. `found` is Python's flag and it is spelled as
# the three Bools that produce it, OR'd once at the end, because a fold cannot
# thread a flag it does not otherwise need.
#
# The pass is `pm_proc` plus `graph_rewrite(ret, pm_proc, bottom_up=True)`, and
# `graph_rewrite` is a FIXPOINT, not one application per node -- see
# `proc_fix` and the header. A nested AND is spliced one level per round, so a
# node whose children are all ANDs is spliced again on the next one, and only
# then does `len(or_clause) >= 4` see four ORs.
# ===========================================================================

def ors_of(two: Bool, ors: List<&2, C>) -> List<&2, C>:
  match two:
    case True{}: [C{O.OpsOR{}, LNone{}, map_and(prod.go(ors, [[]]))}]
    case False{}: ors
# `new_src + or_clause`, deduped, and the AND the rule returns

def do_process_and.of6(dd: List<&2, C>, found: Bool) -> Maybe<&2, C>:
  match found:
    case True{}: Some{and_one(dd)}
    case False{}: None{}

def do_process_and.of5(+all: List<&2, C>, found: Bool) -> Maybe<&2, C>:
  do_process_and.of6(dedup.go(all, Nil{}), Bool.or(found,
    U32.is_ne(U32.from_nat(List.length(&2, C, dedup.go(all, Nil{}))), U32.from_nat(List.length(&2, C, all)))))

def do_process_and.of4(ors: List<&2, C>, flat: Bool, found: Bool, srcs: List<&2, C>, +r: Rec) -> Maybe<&2, C>:
  do_process_and.of5(List.concat(&2, C, [srcs, stores_of(Ds.ks(Rec.d(r)), Ds.vs(Rec.d(r)), Nil{}), Rec.ors(r)]),
    Bool.or(Bool.or(flat, found), Rec.found(r)))
# `if len(stores)`: the OR takes them, otherwise the duplicates become identities

def do_process_and.of3(ors: List<&2, C>, ored: Bool, r: Rp) -> Rec:
  match ored:
    case True{}: do_process_and.push(ors, Rp.extra(r))
    case False{}: do_process_and.dup(ors, r)

def do_process_and.of1(+ors: List<&2, C>, +ored: Bool, flat: Bool, srcs: List<&2, C>, r: Rp) -> Maybe<&2, C>:
  do_process_and.of4(ors, flat, ored, srcs, do_process_and.of3(ors, ored, r))

def do_process_and.of2(+ors: List<&2, C>, flat: Bool, ored: Bool, has: Bool, srcs: List<&2, C>, r: Rp) -> Maybe<&2, C>:
  match has:
    case True{}: do_process_and.of1(ors, ored, flat, srcs, r)
    case False{}: do_process_and.of4(ors, flat, False{}, srcs, Rec{ors, empty_ds(), False{}})

def do_process_and.of1.go(ors: List<&2, C>, flat: Bool, +two: Bool, ored: Bool, has: Bool, srcs: List<&2, C>, r: Rp) -> Maybe<&2, C>:
  do_process_and.of2(ors_of(two, ors), Bool.or(flat, two), ored, has, srcs, r)

# `if len(or_clause): or_clause = [OR(x.replace(src=x.src+tuple(stores)))]`

def do_process_and.of0.hit(big: Bool, +ors: List<&2, C>, flat: Bool, srcs: List<&2, C>, +r: Rp) -> Maybe<&2, C>:
  match big:
    case True{}: Some{marker()}
    case False{}: do_process_and.of1.go(ors, flat, ge2(List.length(&2, C, ors)), ne(ors), ne(Rp.extra(r)), srcs, r)

def do_process_and.of0(+ors: List<&2, C>, flat: Bool, srcs: List<&2, C>, +r: Rp) -> Maybe<&2, C>:
  do_process_and.of0.hit(ge4(List.length(&2, C, ors)), ors, flat, srcs, r)

def do_process_and.of0.of(+ss: List<&2, C>, +sp: Sp) -> Maybe<&2, C>:
  do_process_and.of0(Sp.ors(sp), Sp.flat(sp), Sp.srcs(sp), part.go(Sp.srcs(sp), Rp{Nil{}, Nil{}}))

def do_process_and.of2.of(+ss: List<&2, C>) -> Maybe<&2, C>:
  do_process_and.of0.of(ss, split.go(ss, Sp{Nil{}, Nil{}, False{}}))

# the rule itself: `do_process_and(a) -> UOp|None`

def do_process_and(op: O.Op, lit: Lit, ss: List<&2, C>) -> Maybe<&2, C>:
  match op:
    case O.OpsAND{}: do_process_and.of2.of(ss)
    case _ : None{}
# ===========================================================================
# The `pm_proc` PASS. Bottom up, one application per node, which is the p3 shape:
# the fold over the children and the per-node rule are ONE def, because the rule
# reads the grandchildren and the fold reads the children.
# ===========================================================================

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

# `wrap(ctx, x) -> UOp`: `ctx[ret:=f"a{len(ctx)}"] = x.arg` and a CUSTOMI naming it.
# The value is a `Lit` and not a Python object, because rendering a `Lit` back to
# Python source is the P3 host's `repr`.

def wrap.node(op: O.Op, lit: Lit, +n: U32, d: List<&2, Bind>) -> W:
  match op:
    case O.OpsPYLITERAL{}:
      +nm: String = String.concat(["a", U32.show(n)])
      W{[C{O.OpsCUSTOMI{}, LText{nm}, Nil{}}], U32.add(n, 1), List.append(&2, Bind, d, [Bind{nm, lit}])}
    case _ : W{[C{op, lit, Nil{}}], n, d}

# The node the fold put its own wrap into, with the WRAPPED CHILDREN attached. A
# PYLITERAL is the one op that loses them, because `_get_clause` gives it none.

def wrap.rebuild.put(op: O.Op, lit: Lit, +kids: List<&2, C>) -> C:
  match op:
    case O.OpsPYLITERAL{}: C{O.OpsCUSTOMI{}, lit, Nil{}}
    case _ : C{op, lit, kids}

def wrap.rebuild.of(x: C, +kids: List<&2, C>) -> C:
  match x:
    case C{op, lit, k}: wrap.rebuild.put(op, lit, kids)

def wrap.rebuild(x: C, +kids: List<&2, C>) -> C:
  wrap.rebuild.of(x, kids)

# PRE-ORDER, so the node comes before its children, and the fuel is the same
# `Nat` the rest of the file carries. The accumulator IS the child list: a
# nested `wrap.go` over the node's own srcs answers the rebuilt children and
# nothing else, which is why `wrap.rebuild` needs both and why the flat
# accumulation of `proc.go` would NOT work here.

def wrap.go(+f: Nat, +ss: List<&2, C>, n: U32, +d: List<&2, Bind>, acc: List<&2, C>) -> W:
  match f:
    case 0n: W{acc, n, d}
    case 1n+p:
      match ss:
        case Nil{}: W{acc, n, d}
        # the child call SPENDS the fuel and the tail call does not, because the
        # tail call descends on the tail and needs no decrement to be a descent
        case C{op, lit, k} <> t:
          +a: W = wrap.node(op, lit, n, d)
          +b: W = wrap.go(p, k, W.n(a), W.d(a), Nil{})
          wrap.go(f, t, W.n(b), W.d(b),
            List.append(&2, C, acc, [wrap.rebuild(head1c(W.w(a)), W.w(b))]))

def wrap(t: C, f: Nat) -> W:
  wrap.go(f, [t], 0, Nil{}, Nil{})

# ===========================================================================
# The other four rules, and the `format` they need.
# ===========================================================================

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


# `store_pieces.append(f"{s.src[0].arg[0]}={s.src[1].arg[0]}")`

def rend.sto(+r: Rend, +k: List<&2, C>) -> Rend:
  Rend{Rend.cond(r), List.append(&2, String, Rend.sto(r),
    [String.concat([ctext.m(List.get(&2, C, k, 0n)), "=", ctext.m(List.get(&2, C, k, 1n))])]),
    Rend.orp(r), Rend.bad(r)}

def rend.cond(+r: Rend, lit: Lit) -> Rend:
  Rend{List.append(&2, String, Rend.cond(r), [text_of(lit.text(lit))]), Rend.sto(r), Rend.orp(r),
    Rend.bad(r)}


# `rend.cond` + `rend.sto` + `rend.orp` carried up, and one `Bool` OR'd, because
# a `Rend` has no `fold`

def rend.put(+r: Rend, +a: Rend) -> Rend:
  Rend{Rend.cond(r), Rend.sto(r), List.append(&2, String, Rend.orp(r), Rend.orp(a)),
    Bool.or(Rend.bad(r), Rend.bad(a))}

# a branch that ends has no pieces left: each of its own nodes was rendered and
# appended to `orp` when it was seen, so the end of the list only drops the two
# fields nothing wrote to

def rend.end(+r: Rend, br: Bool) -> Rend:
  match br:
    case True{}: Rend{Nil{}, Nil{}, Rend.orp(r), Rend.bad(r)}
    case False{}: r

def branch_lines.of(m: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match m:
    case Some{ls}: ls
    case None{}: Nil{}


# `if x.op is Ops.CUSTOMI: x = UOp(Ops.AND, (x,))` then `assert x.op is Ops.AND`.
# The `else` arm KEEPS the node, so `rend.go` meets an op it cannot render and
# `bad` is set -- which is the port's `assert`.

def indent(depth: U32) -> String:
  String.repeat("  ", U32.to_nat(depth))

def conds(+cs: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, cs), "True", String.join(cs, " and "))

# `', '.join((["ctx=ctx"] if has_ctx else []) + store_pieces)`

def args_list(+r: Rend, +has_ctx: Bool) -> List<&2, String>:
  Bool.pick(List<&2, String>, has_ctx, List.append(&2, String, ["ctx=ctx"], Rend.sto(r)), Rend.sto(r))

def args(+r: Rend, +has_ctx: Bool) -> String:
  String.join(args_list(r, has_ctx), ", ")

# `f"(_ret:=_fxn({store_clause})) is not None"`

def ret_clause(+r: Rend, +has_ctx: Bool) -> String:
  String.join(List.append(&2, String, Rend.cond(r),
    [String.concat(["(_ret:=_fxn(", args(r, has_ctx), ")) is not None"])]), " and ")

# `f"{'  '*depth}if {and_clause}: return _ret"`

def final_return(+r: Rend, +has_ctx: Bool, depth: U32) -> String:
  String.concat([indent(depth), "if ", ret_clause(r, has_ctx), ": return _ret"])

def if_line(+r: Rend, depth: U32) -> String:
  String.concat([indent(depth), "if ", conds(Rend.cond(r)), ":"])

# if we have an or, render it

def final_shape(no_or: Bool, +orp: List<&2, String>, +r: Rend, +has_ctx: Bool, depth: U32) -> Maybe<&2, List<&2, String>>:
  match no_or:
    case True{}: Some{[final_return(r, has_ctx, depth)]}
    case False{}: Some{List.append(&2, String, [if_line(r, depth)], orp)}

def final_shape.of(+orp: List<&2, String>, +r: Rend, +has_ctx: Bool, depth: U32) -> Maybe<&2, List<&2, String>>:
  final_shape(List.is_empty(&2, String, orp), orp, r, has_ctx, depth)

# `raise UPatCompileError(f"can't compile this {s}")` -- the only failure a clause
# can have at this point, and a `Maybe`, so `_get_code`'s `except` is the same
# `None`

def final_lines(bad: Bool, +orp: List<&2, String>, +r: Rend, +has_ctx: Bool, depth: U32) -> Maybe<&2, List<&2, String>>:
  match bad:
    case True{}: None{}
    case False{}: final_shape.of(orp, r, has_ctx, depth)

def branch_lines(bad: Bool, +a: Rend, +has_ctx: Bool, depth: U32) -> List<&2, String>:
  branch_lines.of(final_lines(bad, Rend.orp(a), a, has_ctx, depth))

# `or_pieces.extend(_final_render(ss, has_ctx, depth+1))` RETURNS lines, so a
# branch is RENDERED where it is found and only its lines travel up: `Rend`
# collects pieces, and `orp` is the one field that already holds finished lines.

def rend.or(+r: Rend, +a: Rend, +has_ctx: Bool, depth: U32) -> Rend:
  rend.put(r, Rend{Nil{}, Nil{}, branch_lines(Rend.bad(a), a, has_ctx, depth), Rend.bad(a)})

# `_final_render(ss, has_ctx, depth+1)` OPENS with `assert x.op is Ops.AND` and
# then iterates `x.src`, so an OR branch is an AND and it is TRANSPARENT: the AND
# arm below splices it, and a branch that is neither leaves `bad` set.
#
# `br` is the one thing Python's recursion and this fold disagree about -- Python
# calls `_final_render` once per branch and a fold cannot recurse into a sibling,
# so `br` says whether the list being walked is the pieces of ONE clause (`False`)
# or the branches of an OR (`True`). It is read inside every arm rather than
# before the `match op`, because a `match` kills every name bound earlier in the
# same body -- measured, and the reason the two are not one dispatch.

def rend.go(f: Nat, +ss: List<&2, C>, +r: Rend, +has_ctx: Bool, +depth: U32, +br: Bool) -> Rend:
  match f:
    case 0n: Rend{Rend.cond(r), Rend.sto(r), Rend.orp(r), True{}}
    case 1n+q:
      match ss:
        case Nil{}: rend.end(r, br)
        case C{op, lit, k} <> t:
          match op:
            # a branch that is an OR is the `assert` failing, and an AND beside a
            # sibling is the same: both leave `bad` set and nothing else
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

# `if x.op is Ops.CUSTOMI: x = UOp(Ops.AND, (x,))` then `assert x.op is Ops.AND`.
# The `else` arm KEEPS the node, so `rend.go` meets an op it cannot render and
# `bad` is set -- which is the port's `assert`.

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

# `src=UPat(Ops.CUSTOMI)`: EVERY src is a CUSTOMI, and an empty src list
# satisfies that vacuously

def all_ci(ss: List<&2, C>) -> Bool:
  match ss:
    case Nil{}: True{}
    case C{op, lit, k} <> t: Bool.and(is_ci(op), all_ci(t))

def ci_texts(ss: List<&2, C>) -> List<&2, String>:
  match ss:
    case Nil{}: Nil{}
    case C{op, lit, k} <> t: List.append(&2, String, [ctext(C{op, lit, k})], ci_texts(t))

# `x.replace(arg=(x.arg[0]+f".src[{c.val}]", dtypes.void))` -- the result is a
# CUSTOMI, because `x` is the CUSTOMI in src[0], not the INDEX. The UPat is
# `src=(UPat(CUSTOMI), UPat(CONST))`, so exactly two srcs, or no rule.

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

# `'(' + ' and '.join(...) + ')'` and the same with `or`, and the format

def head_or(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}: ""
    case p <> _: p

# `String.split` always answers with at least one piece, so the `Nil{}` arm is
# unreachable; it is here because a `match` has to be total. It answers the piece
# AFTER the placeholder index, which is why `fmt.hole` hands it the WHOLE split
# and not the tail.

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
    # the FIRST piece is the text before the first `{`, so it is a literal and
    # the counter only moves for the pieces that carry a placeholder
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

# the INDEX rule is tried first, because an INDEX's src[1] is a CONST and so
# `all_ci` is false for it

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


# ===========================================================================
# The `pm_proc` PASS. Bottom up, one application per node, which is the p3 shape:
# the fold over the children and the per-node rule are ONE def, because the rule
# reads the grandchildren and the fold reads the children.
# ===========================================================================

def proc.put(c: C, hit: Maybe<&2, C>) -> C:
  match hit:
    case Some{x}: x
    case None{}: c

def proc.go(+ss: List<&2, C>) -> List<&2, C>:
  match ss:
    case Nil{}: Nil{}
    case C{op, lit, k} <> t:
      a = proc.go(t)
      +b: List<&2, C> = proc.go(k)
      List.append(&2, C, [proc.put(C{op, lit, b}, do_process_and(op, lit, b))], a)


# `graph_rewrite` is a FIXPOINT and `do_process_and` splices ONE level of AND per
# application, so a node whose children are all ANDs is spliced again on the next
# round -- and only then does `len(or_clause) >= 4` see four ORs. One pass is
# therefore not a fixpoint, which is the whole reason `too big to compile` is
# reachable at all.
# The FUEL comes first because a self-call must be DECREASING and Bend reads the
# arguments left to right: everything before the one that shrinks has to be
# passed unchanged, and the fuel is what shrinks. `proc` is pure, so spelling it
# three times is three walks of the tree and no state.

def proc(t: C) -> C:
  match t:
    case C{+op, +lit, +ss}: proc.put(C{op, lit, proc.go(ss)}, do_process_and(op, lit, proc.go(ss)))

def proc_fix(f: Nat, +t: C) -> C:
  match f:
    case 0n: t
    case 1n+p: Bool.pick(C, eq_c(t, proc(t)), proc(t), proc_fix(p, proc(t)))

def group1.of(g: List<&2, C>) -> C:
  match g:
    case Nil{}: marker()
    case c <> _: c

def group1(gs: List<&2, List<&2, C>>) -> C:
  match gs:
    case Nil{}: marker()
    case g <> _: group1.of(g)


# ===========================================================================
# _get_code -- upat.py:166. The three passes and the join.
#
# The `# match for {self.location}` header line is NOT PORTED, because
# `UPat.location` is frame introspection and ops.bend already records it as P3
# (see the `upat_compile` comment at the bottom). `Context(TRACK_MATCH_STATS=0)`
# is not a def either: it is the profiler's, and ops.bend's NOT PORTED block
# carries `TRACK_MATCH_STATS` with the P8 clock.
# ===========================================================================

# `\'\n\'.join([..., "def compiled_match(uop, ctx):"] + rendered + ["  return None"])`


# `\n'.join([..., "def compiled_match(uop, ctx):"] + rendered + ["  return None"])`

def code_of(rendered: Maybe<&2, List<&2, String>>, +dyn: List<&2, Bind>) -> Maybe<&2, Code>:
  match rendered:
    case None{}: None{}
    case Some{ls}: Some{Code{String.join(List.append(&2, String,
      ["def compiled_match(uop, ctx):"], List.append(&2, String, ls, ["  return None"])), "\n"), dyn}}

def get_code.of6(rendered: Maybe<&2, List<&2, String>>, +dyn: List<&2, Bind>) -> Maybe<&2, Code>:
  code_of(rendered, dyn)

# ===========================================================================
# _get_code -- upat.py:162. The three passes, in Python's order and with
# Python's names: `get_clause`, then `pm_proc` (a fixpoint -- see `proc_fix`),
# then `pm_renderer` (`wrap` for the `a{n}` numbering, `render` for the other four
# rules), then `_final_render`. The three omissions are listed once, on
# `upat_compile`.
# ===========================================================================

def get_code.of5(+t: C, +w: W, has_ctx: Bool, f: Nat) -> Maybe<&2, Code>:
  get_code.of6(final_render(render(head1c(W.w(w))), has_ctx, f), W.d(w))

def get_code.of4(+t: C, has_ctx: Bool, +f: Nat) -> Maybe<&2, Code>:
  get_code.of5(t, wrap(t, f), has_ctx, f)

def get_code.of3(+gs: List<&2, List<&2, C>>, has_ctx: Bool, +f: Nat) -> Maybe<&2, Code>:
  get_code.of4(proc_fix(f, group1(gs)), has_ctx, f)

def get_code.of2(+pat: O.Pat, +u: O.UPat, +has_ctx: Bool, +f: Nat) -> Maybe<&2, Code>:
  get_code.of3(get_clause(pat, u, base_clause(), 0, f), has_ctx, f)

# `broken_of` is the `assert len(self.src) == 1` and the `raise
# RuntimeError("broken")`; neither is reachable from the ported constructors.

def get_code.broken(bad: Bool, +pat: O.Pat, +u: O.UPat, has_ctx: Bool, f: Nat) -> Maybe<&2, Code>:
  match bad:
    case True{}: None{}
    case False{}: get_code.of2(pat, u, has_ctx, f)

def get_code(+pat: O.Pat, +u: O.UPat, has_ctx: Bool) -> Maybe<&2, Code>:
  get_code.broken(broken_of(u), pat, u, has_ctx, fuel(pat))

# ===========================================================================
# upat_compile -- upat.py:176. `@functools.cache` and the `exec` are the wall.
#
# `has_ctx` is a PARAMETER here and not `inspect.signature(real_fxn)`: a Bend
# rule is a top-level def with a fixed arity, and ops.py's `PatternMatcher`
# dispatch (P3) is what knows it.
#
# TODO(p3) ops.py:1590 def upat_interpret -- `types.FunctionType(
# deconstruct_function(fxn))` and `inspect.signature(real_fxn).parameters` are
# Python reflection over a function object, and they and `upat_compile`'s copy of
# the same two lines are the SAME omission: a rule is a def.
# TODO(p3) ops.py:1459 def get_location -- `sys._getframe`, the
# `# match for {...}` header line of `_get_code`, and `UPat.location`.
# TODO(p3) upat.py:186 exec -- `namespace["compiled_match"]`. The rendered `Code`
# IS the artifact; running it is the rewrite engine's phase.
# ===========================================================================

def upat_compile(+pat: O.Pat, i: U32, has_ctx: Bool) -> Maybe<&2, Code>:
  get_code(pat, nth(pat, i), has_ctx)

# ===========================================================================
# THE GATE. Bend has no assertion form, so `main` PRINTS a row per claim and the
# gate is that both lanes print the same rows and every one of them is `True`.
# The strings are what `tinygrad`'s `_get_code` returns for these seven patterns,
# read out of the Python file, so a row is not "does it look right" -- it is
# "is it the text CPython compiles a rule to".
# ===========================================================================

def Code.s(c: Code) -> String:
  match c:
    case Code{s, dyn}: s

def Code.dyn(c: Code) -> List<&2, Bind>:
  match c:
    case Code{s, dyn}: dyn

def Bind.name(b: Bind) -> String:
  match b:
    case Bind{name, lit}: name

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

# `raise UPatCompileError` -- `_get_code` answers `None`, and so must this

def is_none.of(r: Maybe<&2, Code>) -> Bool:
  match r:
    case Some{c}: False{}
    case None{}: True{}

def is_none(+f: O.PatFound, has_ctx: Bool) -> Bool:
  is_none.of(upat_compile(O.PatFound.pat(f), O.PatFound.i(f), has_ctx))

# `UPat(name="x")`

def pat_var() -> O.PatFound:
  O.UPat.var(O.Pat{Nil{}}, Some{"x"}, None{})

# `UPat(Ops.ADD, src=(UPat(name="a"), UPat(name="b")))`

def pat_add() -> O.PatFound:
  a = O.UPat.var(O.Pat{Nil{}}, Some{"a"}, None{})
  b = O.UPat.var(O.PatFound.pat(a), Some{"b"}, None{})
  O.UPat.of(O.PatFound.pat(b), Some{[O.OpsADD{}]}, None{}, None{}, O.STuple{[0, 1]}, None{}, None{}, False{}, None{}, False{})

# `UPat(Ops.ADD, src=UPat(Ops.MUL, name="m"))` -- the repeat arm, with the store
# lifted to the outer clause and the identity compare inside the loop

def pat_repeat() -> O.PatFound:
  m = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsMUL{}]}, None{}, None{}, O.SNone{}, None{}, Some{"m"}, False{}, None{}, False{})
  O.UPat.of(O.PatFound.pat(m), Some{[O.OpsADD{}]}, None{}, None{}, O.SOne{0}, None{}, None{}, False{}, None{}, False{})

# `UPat.any(UPat(name="a"), UPat(name="b"))` -- the `is_any` arm and a nested
# `_final_render` at depth 2

def pat_any() -> O.PatFound:
  a = O.UPat.var(O.Pat{Nil{}}, Some{"a"}, None{})
  b = O.UPat.var(O.PatFound.pat(a), Some{"b"}, None{})
  O.UPat.of(O.PatFound.pat(b), None{}, None{}, None{}, O.STuple{[0, 1]}, None{}, None{}, False{}, None{}, True{})

# `UPat(Ops.CALL, arg=4)` -- the inline int arm, which spends NO `a{n}`

def pat_argint() -> O.PatFound:
  O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsCALL{}]}, None{}, None{}, O.SNone{}, Some{O.ATuple{[4]}}, None{}, False{}, None{}, False{})

# `UPat(Ops.BINARY, src=(q, q, q, q))` with
# `q = UPat.any(UPat(Ops.ADD), UPat(Ops.SUB), UPat(Ops.MUL), UPat(Ops.MAX))`:
# four OR children of one AND, which is `raise UPatCompileError("too big")`

def pat_bigor() -> O.PatFound:
  c0 = O.UPat.of(O.Pat{Nil{}}, Some{[O.OpsADD{}]}, None{}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  c1 = O.UPat.of(O.PatFound.pat(c0), Some{[O.OpsSUB{}]}, None{}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  c2 = O.UPat.of(O.PatFound.pat(c1), Some{[O.OpsMUL{}]}, None{}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  c3 = O.UPat.of(O.PatFound.pat(c2), Some{[O.OpsMAX{}]}, None{}, None{}, O.SNone{}, None{}, None{}, False{}, None{}, False{})
  q = O.UPat.of(O.PatFound.pat(c3), None{}, None{}, None{}, O.STuple{[0, 1, 2, 3]}, None{}, None{}, False{}, None{}, True{})
  O.UPat.of(O.PatFound.pat(q), Some{[O.OpsBINARY{}]}, None{}, None{}, O.STuple{[4, 4, 4, 4]}, None{}, None{}, False{}, None{}, False{})

# THE ORACLE. Every `want_*` below is CPython's own `_get_code` output for the
# pattern above it, printed by `uv run` against `tinygrad/uop/upat.py` -- except
# the `# match for {self.location}` first line, which is `get_location`'s and is
# NOT PORTED. `row` prints one `name=True/False` per claim because Bend has no
# assertion: a `False` here is a row that disagrees with CPython, and hiding it
# would make this file worth less than an empty one.

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

def main() -> IO(Unit):
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
    show(pat_add(), True{})


# ===========================================================================
# THE MUTATION TABLE. Seventeen single edits to THIS file, each run through the
# nine rows above. The claim is not "it compiles" but "each of these is the only
# thing standing between a row and `False`", and the honest entry is M2, which
# moves nothing.
#
#  #   edit                                                  rows that move
#  M1  `ge4` 4 -> 8, the `too big to compile` threshold        too_big
#  M2  `alt_group` swaps its single/fork arms                  (none -- see below)
#  M3  `loop.put` drops the hoisted STORE from `extra`         repeat
#  M4  `dedup` becomes a pass-through                          add, add_dyn
#  M5  `fmt`'s `{k}` counter never advances                    add, repeat, argint
#  M6  `final_shape` swaps its two arms                        var add repeat any
#                                                             noctx argint
#  M7  `rep_len` drops the `len({0}.src) != 0` guard           repeat
#  M8  `is_any` children read `base.index(0)`                  any
#  M9  `wrap` never numbers a PYLITERAL                        add add_dyn repeat
#                                                             repeat_dyn argint
#  M10 `proc_fix` runs the rewrite once                        too_big
#  M11 `is_rep` is always False: the repeat arm is dead        repeat
#  M12 the store lift skips `substitute`                      repeat
#  M13 `or_true`: an empty clause is an AND, not `"True"`      all nine
#  M14 the code header is emitted last                         var add repeat any
#                                                             noctx argint
#  M15 `found` drops the nested-AND splice (`flat`)            too_big
#  M16 `rend.or` does not render a branch into lines           any
#  M17 `pieces` is the op check alone                          var add repeat any
#                                                             noctx argint
#
# M2 IS THE INTERESTING ONE. Nesting a single match's children in one AND is
# what the fork arm does and the single arm does not, and the nine rows cannot
# tell the difference -- because `proc_fix` splices the extra level away again.
# The rows are right about the RENDERED SOURCE and blind to the shape, so M2 is
# reported rather than hidden, and `alt_group` keeps the distinction because
# Python's `and_clause` really is a list of siblings and the port should say so.
# ===========================================================================
