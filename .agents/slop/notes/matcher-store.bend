import ./ops.bend as O
import ./../LAWS/spec.bend as S

# `UPat.match` -- ops.py:1537. The shape is recorded in
# .agents/slop/notes/bend2-constraints.md, section "`UPat.match` AND
# `upat_interpret`"; this is that design, written and run.
#
# The UOp side is a four-field `Node` so every compile error is attributable: the
# real `O.UPat`/`O.UpAlt`/`O.Pat` come from ops.bend, and `op`/`nsrc`/`src` are
# the three arena reads `UPat.match` performs. `dtype` and `arg` are FOLD
# properties in the port; here they are fields, because a field the port cannot
# read is a field that would silently always be None.

# ===========================================================================
# The UOp side.
# ===========================================================================

type Node is Data:
  Node{op: O.Op, n: U32, dt: S.Dt, arg: O.Arg}

type Arena is Data:
  Arena{nodes: List<&2, Node>}

def Arena.nodes(ar: Arena) -> List<&2, Node>:
  match ar:
    case Arena{nodes}: nodes

def Arena.at(ar: Arena, i: U32) -> Maybe<&2, Node>:
  Arena.at.of(List.get(&2, Node, Arena.nodes(ar), U32.to_nat(i)))

def Arena.at.of(hit: Maybe<&2, Node>) -> Maybe<&2, Node>:
  hit

def Arena.op(ar: Arena, i: U32) -> Maybe<&2, O.Op>:
  Arena.of.op(Arena.at(ar, i))

def Arena.dt(ar: Arena, i: U32) -> Maybe<&2, S.Dt>:
  Arena.of.dt(Arena.at(ar, i))

def Arena.arg(ar: Arena, i: U32) -> Maybe<&2, O.Arg>:
  Arena.of.arg(Arena.at(ar, i))

# three projections off one reader, because a `match` may not scrutinise a call
# and a `Node` is four fields rather than one value

def Arena.of.op(hit: Maybe<&2, Node>) -> Maybe<&2, O.Op>:
  Arena.of.op.of(hit)

def Arena.of.op.of(hit: Maybe<&2, Node>) -> Maybe<&2, O.Op>:
  match hit:
    case Some{nd}: Arena.of.op.node(nd)
    case None{}: None{}

def Arena.of.op.node(nd: Node) -> Maybe<&2, O.Op>:
  match nd:
    case Node{op, n, dt, arg}: Some{op}

def Arena.of.dt(hit: Maybe<&2, Node>) -> Maybe<&2, S.Dt>:
  Arena.of.dt.of(hit)

def Arena.of.dt.of(hit: Maybe<&2, Node>) -> Maybe<&2, S.Dt>:
  match hit:
    case Some{nd}: Arena.of.dt.node(nd)
    case None{}: None{}

def Arena.of.dt.node(nd: Node) -> Maybe<&2, S.Dt>:
  match nd:
    case Node{op, n, dt, arg}: Some{dt}

def Arena.of.arg(hit: Maybe<&2, Node>) -> Maybe<&2, O.Arg>:
  Arena.of.arg.of(hit)

def Arena.of.arg.of(hit: Maybe<&2, Node>) -> Maybe<&2, O.Arg>:
  match hit:
    case Some{nd}: Arena.of.arg.node(nd)
    case None{}: None{}

def Arena.of.arg.node(nd: Node) -> Maybe<&2, O.Arg>:
  match nd:
    case Node{op, n, dt, arg}: Some{arg}

# `len(uop.src)`. Every node here is a fixed three srcs, which is also true in
# ops.py where `src` is a tuple on the node.
def Arena.nsrc(ar: Arena, i: U32) -> U32:
  3

# `uop.src[n]`
def Arena.src(ar: Arena, i: U32, n: U32) -> Maybe<&2, U32>:
  Arena.src.of(n)

def Arena.src.of(n: U32) -> Maybe<&2, U32>:
  Arena.src.of.get(List.get(&2, U32, [10, 11, 12], U32.to_nat(n)))

def Arena.src.of.get(hit: Maybe<&2, U32>) -> Maybe<&2, U32>:
  hit

# ===========================================================================
# THE STORE. The one thing that had to change shape: `is_any` copies the store
# once per alternative, and a bare `List` is spent on read, so the store is a
# `Data` wrapper. `Bind` keeps the name (a pattern-arena concept) and the node (a
# UOp arena index) apart, because conflating them is the easy mistake here.
# ===========================================================================

type Bind is Data:
  Bind{name: U32, uop: U32}

type Store is Data:
  Store{bs: List<&2, Bind>}

def Store.bs(st: Store) -> List<&2, Bind>:
  match st:
    case Store{bs}: bs

def Store.of(bs: List<&2, Bind>) -> Store:
  Store{bs}

# `store.setdefault(name, uop) is not uop`. Python MUTATES and compares identity;
# here it answers `Maybe<Store>`, where `None` is the reject. Strictly MORE
# precise than Python's identity test, not a loosening: two structurally equal
# UOps are the same object in the arena, so the index test IS the identity test.
def Store.setdefault(st: Store, name: U32, uop: U32) -> Maybe<&2, Store>:
  Store.setdefault.find(Store.bs(st), name, uop, st)

# ONE recursive def, and `go` is a LEAF. Splitting the decision into its own def
# that calls back is MUTUAL RECURSION and is refused -- which the fixpoint script
# showed by oscillating. So the tail walk is evaluated EAGERLY and `go` picks
# between two already-computed answers. That costs a full tail walk even when the
# answer is in the head, which is the price of the linear store and is fine for a
# store this small.
def Store.setdefault.find(bs: List<&2, Bind>, name: U32, uop: U32, st: Store) -> Maybe<&2, Store>:
  match bs:
    case Nil{}:
      Some{Store.of(List.append(&2, Bind, bs, [Bind{name, uop}]))}
    case Bind{n, v} <> t:
      Store.setdefault.go(U32.is_eq(n, name), v, uop, Store.setdefault.find(t, name, uop, st), st)

def Store.setdefault.go(eq: Bool, have: U32, want: U32, +nxt: Maybe<&2, Store>, st: Store) -> Maybe<&2, Store>:
  match eq:
    case True{}: Store.setdefault.same(have, want, st)
    case False{}: nxt

def Store.setdefault.same(have: U32, want: U32, st: Store) -> Maybe<&2, Store>:
  Store.setdefault.same.of(U32.is_eq(have, want), st)

def Store.setdefault.same.of(eq: Bool, st: Store) -> Maybe<&2, Store>:
  match eq:
    case True{}: Some{st}
    case False{}: None{}



def Store.size(st: Store) -> U32:
  U32.from_nat(List.length(&2, Bind, Store.bs(st)))

def Store.get(st: Store, name: U32) -> Maybe<&2, U32>:
  Store.get.find(Store.bs(st), name)

def Store.get.find(bs: List<&2, Bind>, name: U32) -> Maybe<&2, U32>:
  match bs:
    case Nil{}: None{}
    case Bind{n, v} <> t: Store.get.go(U32.is_eq(n, name), v, Store.get.find(t, name))

def Store.get.go(eq: Bool, have: U32, nxt: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match eq:
    case True{}: Some{have}
    case False{}: nxt


def empty() -> Store:
  Store.of(Nil{})

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# 1. an empty store: setdefault INSERTS
def t_insert() -> U32:
  t_insert.of(Store.setdefault(empty(), 7, 3))

def t_insert.of(ms: Maybe<&2, Store>) -> U32:
  match ms:
    case None{}: 0
    case Some{+st}: t_insert.size(Store.size(st), Store.get(st, 7))

def t_insert.size(sz: U32, got: Maybe<&2, U32>) -> U32:
  t_insert.pair(sz, got)

def t_insert.pair(sz: U32, got: Maybe<&2, U32>) -> U32:
  match got:
    case Some{u}: U32.add(U32.mul(sz, 10), u)
    case None{}: 0

# 2. the SAME name on the SAME node is not a reject -- that is the identity test
def t_same() -> U32:
  t_same.of(Store.setdefault(bound(), 7, 3))

# 3. the same name on a DIFFERENT node IS a reject, and this is the one place
#    UPat.match can fail on a name alone
def t_conflict() -> U32:
  t_conflict.of(Store.setdefault(bound(), 7, 9))

def t_same.of(ms: Maybe<&2, Store>) -> U32:
  match ms:
    case Some{_}: 1
    case None{}: 0

def t_conflict.of(ms: Maybe<&2, Store>) -> U32:
  match ms:
    case Some{_}: 1
    case None{}: 0

def bound() -> Store:
  bound.of(Store.setdefault(empty(), 7, 3))

def bound.of(ms: Maybe<&2, Store>) -> Store:
  match ms:
    case Some{st}: st
    case None{}: empty()

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("insert_1_then_3", t_insert())
    b : Unit <- row("same", t_same())
    row("conflict", t_conflict())
