import ./ops.bend as O
import ./../LAWS/spec.bend as S

# THE COMPILED MATCHER -- the shape `upat.py` emits, hand-written.
#
# The point of this file is ONE thing, and it is not the matching: a compiled
# rule is a TOP-LEVEL DEF named by a tag, so the rule table is a plain `Data`
# record. Every constraint the interpreter imposed is gone:
#
#   * a table of CLOSURES forces `Type`, so a table is linear and one walk
#     consumes it. A table of TAGS is `Data`, so it is COPYABLE and readable
#     twice -- and `CRules.rs` below is read by the scan AND by `early_reject`.
#   * a closure cannot take a shared argument, so no interpreter rule can receive
#     `+Arena`. A def can, so `Arena.op` takes `+ar` and a rule may read the
#     arena as often as it likes.
#   * a rule's captures are its own PARAMETERS, so there is no store, no
#     `setdefault`, and no cartesian product.
#
# What remains is `upat.py`'s actual output: straight-line code, with `is_any` as
# a disjunction. The dispatch is a `match` on the tag calling each def -- the
# "dispatch a tag rather than a compiled function pointer" the notes describe, and
# the price of not having first-class functions.

# the src pairs, as data rather than computed, so `srcs_of` is one `List.get`
def SRC_PAIRS() -> List<&2, List<&2, U32>>:
  [[0, 2], [0, 2], [0, 2], [0, 2], [0, 0], [0, 0]]

type Node is Data:
  Node{op: O.Op, dt: S.Dt, arg: O.Arg}

type Arena is Data:
  Arena{nodes: List<&2, Node>}

def Arena.nodes(ar: Arena) -> List<&2, Node>:
  match ar:
    case Arena{nodes}: nodes

def Arena.at(ar: Arena, i: U32) -> Maybe<&2, Node>:
  Arena.at.of(List.get(&2, Node, Arena.nodes(ar), U32.to_nat(i)))

def Arena.at.of(hit: Maybe<&2, Node>) -> Maybe<&2, Node>:
  hit

# the three reads a compiled rule can make. Each is two defs because a `match`
# may not scrutinise a call.
def Arena.op(+ar: Arena, i: U32) -> Maybe<&2, O.Op>:
  Arena.op.of(Arena.at(ar, i))

def Arena.op.of(hit: Maybe<&2, Node>) -> Maybe<&2, O.Op>:
  match hit:
    case Some{nd}: Arena.op.node(nd)
    case None{}: None{}

def Arena.op.node(nd: Node) -> Maybe<&2, O.Op>:
  match nd:
    case Node{op, dt, arg}: Some{op}

def Arena.dt(+ar: Arena, i: U32) -> Maybe<&2, S.Dt>:
  Arena.dt.of(Arena.at(ar, i))

def Arena.dt.of(hit: Maybe<&2, Node>) -> Maybe<&2, S.Dt>:
  match hit:
    case Some{nd}: Arena.dt.node(nd)
    case None{}: None{}

def Arena.dt.node(nd: Node) -> Maybe<&2, S.Dt>:
  match nd:
    case Node{op, dt, arg}: Some{dt}

# every node here has two srcs, which is also true in ops.py where `src` is a
# tuple on the node
def Arena.nsrc(ar: Arena, i: U32) -> U32:
  2

# `uop.src[n]`, a NODE INDEX -- the thing a capture reads
def Arena.src(ar: Arena, i: U32, n: U32) -> Maybe<&2, U32>:
  Arena.src.of(srcs_of(i), n)

def Arena.src.of(ss: List<&2, U32>, n: U32) -> Maybe<&2, U32>:
  Arena.src.of.get(List.get(&2, U32, ss, U32.to_nat(n)))

def Arena.src.of.get(hit: Maybe<&2, U32>) -> Maybe<&2, U32>:
  hit

# the first five nodes have srcs (CONST, BITCAST), so `ler` CONTAINS BITCAST and
# the fourth rule fires; the last has (CONST, CONST), so `ler` does NOT contain
# it and the rule is skipped. That is the whole of what the subset test decides.
def srcs_of(i: U32) -> List<&2, U32>:
  srcs_of.of(List.get(&2, List<&2, U32>, SRC_PAIRS(), U32.to_nat(i)))

def srcs_of.of(hit: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match hit:
    case Some{ss}: ss
    case None{}: Nil{}

# ===========================================================================
# THE TABLE -- the thing being demonstrated. `CRules` is `Data`, so `rs` is
# COPYABLE and the scan and `early_reject` both read it in one pass. In the
# interpreter this was the central constraint and there was no way around it.
# ===========================================================================

type CRule is Data:
  # `tag` names the top-level def; `ops` is the op set, which is `pdict`'s key
  # in tinygrad; `rej` is `early_reject`.
  CRule{tag: U32, ops: List<&2, O.Op>, rej: List<&2, O.Op>}

type CRules is Data:
  CRules{rs: List<&2, CRule>}

def CRules.rs(rs: CRules) -> List<&2, CRule>:
  match rs:
    case CRules{rs}: rs

def CRule.tag(r: CRule) -> U32:
  match r:
    case CRule{tag, ops, rej}: tag

def CRule.ops(r: CRule) -> List<&2, O.Op>:
  match r:
    case CRule{tag, ops, rej}: ops

def CRule.rej(r: CRule) -> List<&2, O.Op>:
  match r:
    case CRule{tag, ops, rej}: rej

# ===========================================================================
# The verdict. `PatternMatcher.rewrite` returns the FIRST non-None, so this is a
# fold with first-wins and `keep` is a leaf -- the same question as the
# classifier, so the same answer.
# ===========================================================================

type Verdict is Data:
  VTrue{}
  VFalse{}
  VSkip{}

def keep.take(v: Verdict) -> Verdict:
  match v:
    case VSkip{}: VSkip{}
    case VTrue{}: VTrue{}
    case VFalse{}: VFalse{}

def keep(acc: Verdict, v: Verdict) -> Verdict:
  keep.go(acc, v)

def keep.go(acc: Verdict, v: Verdict) -> Verdict:
  match acc:
    case VSkip{}: keep.take(v)
    case VTrue{}: VTrue{}
    case VFalse{}: VFalse{}

# `if cond: v else None` -- the shape of most of spec.py's rule bodies
def when(b: Bool, v: Verdict) -> Verdict:
  when.of(b, v)

def when.of(b: Bool, v: Verdict) -> Verdict:
  match b:
    case True{}: v
    case False{}: VSkip{}

# ===========================================================================
# THE PASS. `pdict.get(uop.op, [])` as a scan: a flat list in insertion order,
# filtered by op set. `Ops.value` gives a number and `Map` is string-keyed, so a
# linear scan is both the faithful order and the honest structure.
# ===========================================================================

def cr_rewrite(rs: CRules, ar: Arena, i: U32) -> Verdict:
  cr_scan(rs, ar, i, CRules.rs(rs), VSkip{})

def cr_scan(rs: CRules, ar: Arena, i: U32, todo: List<&2, CRule>, acc: Verdict) -> Verdict:
  match todo:
    case Nil{}: acc
    case r <> t: cr_scan(rs, ar, i, t, keep(acc, cr_try(rs, ar, i, r)))

# one rule: does it claim this op, and does `early_reject` pass?
def cr_try(rs: CRules, ar: Arena, i: U32, r: CRule) -> Verdict:
  cr_try.of(op_claimed(CRule.ops(r), ar, i), cr_reject(rs, ar, i, CRule.rej(r)), CRule.tag(r), ar, i)

def cr_try.of(claimed: Bool, passed: Bool, tag: U32, ar: Arena, i: U32) -> Verdict:
  cr_try.go(Bool.and(claimed, passed), tag, ar, i)

def cr_try.go(ok: Bool, tag: U32, ar: Arena, i: U32) -> Verdict:
  match ok:
    case True{}: dispatch(tag, ar, i)
    case False{}: VSkip{}

# --- the op-set membership tests -------------------------------------------

# `uop.op in self.op`
def op_claimed(ops: List<&2, O.Op>, ar: Arena, i: U32) -> Bool:
  op_claimed.of(ops, Arena.op(ar, i))

def op_claimed.of(ops: List<&2, O.Op>, got: Maybe<&2, O.Op>) -> Bool:
  match got:
    case Some{o}: op_in(ops, o)
    case None{}: False{}

def op_in(ops: List<&2, O.Op>, want: O.Op) -> Bool:
  match ops:
    case Nil{}: False{}
    case x <> t: Bool.or(O.eq_op(x, want), op_in(t, want))

def op_eq.of(got: Maybe<&2, O.Op>, want: O.Op) -> Bool:
  match got:
    case Some{o}: O.eq_op(o, want)
    case None{}: False{}

def op_eq(ar: Arena, i: U32, want: O.Op) -> Bool:
  op_eq.of(Arena.op(ar, i), want)

# `uop.op is not None and uop.op in [other]`
def src_op(ar: Arena, i: U32, n: U32, want: O.Op) -> Bool:
  src_op.of(Arena.src(ar, i, n), ar, want)

def src_op.of(m: Maybe<&2, U32>, ar: Arena, want: O.Op) -> Bool:
  match m:
    case Some{j}: op_eq(ar, j, want)
    case None{}: False{}

# ===========================================================================
# `early_reject`, and THE NAME IS A MISLEADER. Python is
#   if not early_reject.issubset(ler): continue
# so the rule FIRES when the op set IS a subset of `ler`, and is SKIPPED when it
# is not. An empty set is a subset of everything, which is why the many rules
# with an empty `early_reject` always fire.
#
# It reads as a REJECT set and computes as a NECESSARY CONDITION. It is built
# from the ops of the pattern's first src (`{pp.op[0] for pp in upat_match ...}`),
# so for `UPat(Ops.ADD, src=(UPat(Ops.CONST),))` it is `{CONST}` and the rule
# fires exactly when a CONST is among the node's srcs -- which is a precondition,
# not a veto.
#
# `ler` is CACHED ON THE UOP in Python (`uop.__dict__['_src_ops']`). There is no
# mutable uop here, so it is recomputed per rule, and that cache is the one place
# this port is slower than the thing it ports.
# ===========================================================================

def cr_reject(rs: CRules, ar: Arena, i: U32, rej: List<&2, O.Op>) -> Bool:
  cr_reject.go(ler(ar, i), rej)

def cr_reject.go(have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: Bool.and(op_in(have, o), cr_reject.go(have, t))

# `ler`: the ops among the node's srcs, as a flat list
def ler(ar: Arena, i: U32) -> List<&2, O.Op>:
  ler.go(ops_of(Arena.src(ar, i, 0), ar), ops_of(Arena.src(ar, i, 1), ar))

def ler.go(a: List<&2, O.Op>, b: List<&2, O.Op>) -> List<&2, O.Op>:
  ler.put(List.append(&2, O.Op, a, b))

def ler.put(x: List<&2, O.Op>) -> List<&2, O.Op>:
  x

def ops_of(m: Maybe<&2, U32>, ar: Arena) -> List<&2, O.Op>:
  ops_of.of(m, ar)

def ops_of.of(m: Maybe<&2, U32>, ar: Arena) -> List<&2, O.Op>:
  match m:
    case Some{j}: op_list(Arena.op(ar, j))
    case None{}: Nil{}

def op_list(m: Maybe<&2, O.Op>) -> List<&2, O.Op>:
  op_list.of(m)

def op_list.of(m: Maybe<&2, O.Op>) -> List<&2, O.Op>:
  match m:
    case Some{o}: [o]
    case None{}: Nil{}

# ===========================================================================
# THE DISPATCH. `upat.py` emits a closure; Bend has no first-class functions, so
# the tag selects a TOP-LEVEL DEF. This is the whole mechanism, and it is why the
# table is `Data` rather than a list of closures.
# ===========================================================================

def dispatch(tag: U32, ar: Arena, i: U32) -> Verdict:
  dispatch.go(tag, ar, i)

def dispatch.go(tag: U32, ar: Arena, i: U32) -> Verdict:
  match tag:
    case 0: r_const(ar, i)
    case 1: r_stack(ar, i)
    case 2: r_cast(ar, i)
    case 3: r_add(ar, i)
    case _: VSkip{}

# --- the rules, in spec.py's order -----------------------------------------

# `UPat(Ops.CONST, src=(), name="x")` -- a leaf, no captures
def r_const(ar: Arena, i: U32) -> Verdict:
  when(op_eq(ar, i, O.OpsCONST{}), VTrue{})

# `UPat(Ops.STACK, src=(UPat(),), allow_any_len=True{}, name="s")` -- one capture.
# In the interpreter that capture went into the store; here it is a direct arena
# read, and the rule may read `ar` as many times as it wants because it is a def
# and can take `+ar`.
def r_stack(ar: Arena, i: U32) -> Verdict:
  r_stack.go(src_op(ar, i, 0, O.OpsCONST{}), ar, i)

def r_stack.go(ok: Bool, ar: Arena, i: U32) -> Verdict:
  when(ok, VTrue{})

# `is_any`: a DISJUNCTION, which is what `upat.py:18` compiles it to. The
# interpreter FLATTENED the alternatives and recursed over the pattern's own src;
# here it is straight-line code, so that recursion -- the entire wall -- is not
# there at all.
def r_cast(ar: Arena, i: U32) -> Verdict:
  when(Bool.or(op_eq(ar, i, O.OpsCAST{}), op_eq(ar, i, O.OpsBITCAST{})), VTrue{})

# a fourth rule that CLAIMS the op but carries an `early_reject`, so the subset
# test decides it. It fires when a BITCAST IS among the node's srcs, because the
# set being a SUBSET of `ler` is what lets the rule through.
def r_add(ar: Arena, i: U32) -> Verdict:
  when(op_eq(ar, i, O.OpsADD{}), VTrue{})

# ===========================================================================
# THE GATE. Both lanes must print these rows. A `9` is a Skip, which is a real
# answer and not a failure.
#
# node 0 = CONST, node 1 = STACK(const, cast), node 2 = BITCAST, node 3 = ADD
# where every src is a CONST. So the ops among the srcs are CONST, CONST, ADD.
# ===========================================================================

# 0 CONST  1 STACK  2 BITCAST  3 ADD(ler has BITCAST)  4 ADD(ler does not)
# 5 MUL, which no rule claims
def arena() -> Arena:
  arena.of(Arena{[
    Node{O.OpsCONST{}, S.void(), O.ANone{}},
    Node{O.OpsSTACK{}, S.void(), O.ANone{}},
    Node{O.OpsBITCAST{}, S.void(), O.ANone{}},
    Node{O.OpsADD{}, S.void(), O.ANone{}},
    Node{O.OpsADD{}, S.void(), O.ANone{}},
    Node{O.OpsMUL{}, S.void(), O.ANone{}}]})

def arena.of(ar: Arena) -> Arena:
  ar

# rule 0 claims CONST, rule 1 claims STACK, rule 2 is the is_any disjunction
def rules() -> CRules:
  rules.of(CRules{[
    CRule{0, [O.OpsCONST{}], Nil{}},
    CRule{1, [O.OpsSTACK{}], Nil{}},
    CRule{2, [O.OpsCAST{}, O.OpsBITCAST{}], Nil{}},
    CRule{3, [O.OpsADD{}], [O.OpsBITCAST{}]}]})

def rules.of(rs: CRules) -> CRules:
  rs

def show(v: Verdict) -> U32:
  show.of(v)

def show.of(v: Verdict) -> U32:
  match v:
    case VTrue{}: 1
    case VFalse{}: 0
    case VSkip{}: 9

def t_const() -> U32: show(cr_rewrite(rules(), arena(), 0))
def t_stack() -> U32: show(cr_rewrite(rules(), arena(), 1))
# the is_any rule claims BITCAST, which rule 0 and rule 1 do not
def t_cast() -> U32: show(cr_rewrite(rules(), arena(), 2))
# ADD is claimed by NO rule, so the pass runs off the end and skips
# the op set IS a subset of `ler`, so rule 3 fires
def t_early_yes() -> U32: show(cr_rewrite(rules(), arena(), 3))
# the same op and the same rule, but BITCAST is NOT among the srcs, so the
# subset test fails and the rule is SKIPPED -- the pass runs on and skips
def t_early_no() -> U32: show(cr_rewrite(rules(), arena(), 4))
def t_unclaimed() -> U32: show(cr_rewrite(rules(), arena(), 5))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("const", t_const())
    b : Unit <- row("stack", t_stack())
    c : Unit <- row("cast", t_cast())
    d : Unit <- row("early_yes", t_early_yes())
    e : Unit <- row("early_no", t_early_no())
    row("unclaimed", t_unclaimed())

# THE GATE, and what each row is FOR. A `9` is a Skip, which is a real answer and
# not a failure -- it is what a rule says when the pattern does not apply.
#
#   const=1       rule 0 claims CONST and answers. The plain case.
#   stack=1       rule 1 claims STACK and reads a CAPTURE -- src[0] -- straight
#                 out of the arena. In the interpreter that capture went into the
#                 store; here it is one arena read and the rule may take `+ar`.
#   cast=1        rule 2 is the `is_any` DISJUNCTION, `upat.py:18`. It claims
#                 BITCAST. The interpreter flattened the alternatives and
#                 recursed over the pattern's own src; this is straight-line
#                 code, so that wall is not present.
#   early_yes=1   the op set IS a subset of `ler`, so rule 3 fires.
#   early_no=9    BITCAST is NOT among the srcs, the subset test fails, rule 3 is
#                 skipped and the pass runs off the end. Same op, same rule.
#   unclaimed=9   no rule claims MUL, so nothing fires.
#
# MUTATIONS, both re-run 2026-09-30 against this file:
#
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | `cr_reject` uses `Bool.or` instead of `Bool.and` | `early_no` | 1 |
# | `keep` keys on `v`, so LAST non-skip wins instead of first | `const`, `stack`, `cast` | 3 |
#
# BOTH ROWS ARE CORRECTIONS. The first draft of this table claimed the reject
# mutation moved two rows and the `keep` mutation moved the two `early_` rows.
# Measured, it is one and three, and neither guess was right.
#
# The three-row result is the interesting one and is worth understanding rather
# than just recording. With last-wins, a rule that SKIPS overwrites the
# accumulator with Skip, so every rule that does not claim a node erases the
# verdict of every rule before it. Three of the four rules skip on any given
# node, so most verdicts are destroyed before the pass ends. That is why
# first-wins is not a detail here: last-wins is not "slightly different", it is
# a matcher that almost never answers.
#
# And it is why the table is not one-row-per-bug. A row that only one mutation
# moves is a LOCALISED row; the rest are load-bearing together, which is the
# honest description of a six-row gate.
