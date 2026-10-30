# alloc_slot.bend -- the PORT lane of the ALLOCATION-SLOT parity gate.
#
#   .venv/bin/python gates/alloc_slot-gate.py
#
# WHAT IT MEASURES. `ParamArg.slot` -- the ALLOCATION IDENTITY -- as the port mints it
# against `next(UOp.unique_num)`, upstream's MONOTONE counter of allocations
# (`tinygrad/uop/ops.py:1191`, `UOp.unique_num = itertools.count(0)` at ops.py:820).
#
# THE DEFECT THIS GATE EXISTS FOR. The port minted the slot from `O.Arena.next(ar)` --
# the arena's LENGTH -- on the argument that `uop/ops.bend:1359`'s comment says "the
# arena's length IS that counter". THE ARGUMENT IS FALSE: upstream's counter is spent
# at exactly three sites (ops.py:839 `UOp.new_buffer`, :1191 `UOp.alloc`, :1199
# `UOp.placeholder`) and counts ALLOCATIONS, while an arena's length counts EVERY node.
# MEASURED, `Tensor.empty(4,3)`:
#
#     CPython   ALLOC slot 0
#     the port  ALLOC slot 1      <- the arena's BOTTOM, counted as an allocation
#
# and the port gave a SECOND `empty` in a fresh arena slot 1 as well, because each
# arena counts its own.
#
# THE ROW IS THE SLOT'S VALUE. A row that printed the OP would read `ALLOC` on both
# sides for the wrong slot and would not move, so it could not see this defect at all.
#
# EVERY SCENARIO IS ONE SCOPE. Upstream's counter is process-global and the port's is
# scoped to its arena, so the two are comparable only where the allocations share a
# scope -- and the oracle resets `UOp.unique_num` before each scenario, which is
# upstream's way of saying "count from zero" and the port's fresh `O.Arena.empty()`
# is the same question. `alloc_two_scopes` is the WALL and it is PORT-ONLY: two
# allocations in SEPARATE scopes are 0 and 1 upstream and 0 and 0 in the port, and the
# port cannot be asked upstream's question, so that row is excluded from the diff.
#
# THE PORT LANE ANSWERS THE SAME QUESTION CPYTHON DOES: build the allocations, then
# READ THE SLOTS BACK OFF THE GRAPH. It does not ask `cr_slot` what it would mint --
# that would be the implementation answering its own exam -- it walks the arena and
# reads the `ParamArg` of every ALLOC/BUFFER node, in arena order, exactly as the
# oracle walks its toposort.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/creation.bend as CR
import ./../tinybendygrad/mixin/op.bend as MO

# THE SLOT, read off a node's `ParamArg`. The `AParam` arm is the only one that has a
# slot at all, and a node that is not an allocation has none -- which is why the walk
# below filters on the OP before it asks.
def as_slot.of(a: O.Arg) -> U32:
  match a:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: 4294967295

def as_slot(a: O.Arg) -> U32: as_slot.of(a)

# AN ALLOCATION IS AN ALLOC OR A BUFFER -- the two ops upstream spends `unique_num` on.
# PARAM IS NOT ONE: upstream's `UOp.param` takes an EXPLICIT slot (ops.py:1218) and
# spends no counter.
def is_alloc(op: O.Op) -> Bool:
  match op:
    case O.OpsALLOC{}: True{}
    case O.OpsBUFFER{}: True{}
    case _: False{}

# THE SLOT OF ONE NODE, or `None` when the node is not an allocation.
def slot_one.of(alloc: Bool, n: O.Node) -> Maybe<&2, String>:
  match alloc:
    case True{}: Some{U32.show(as_slot(O.Node.arg(n)))}
    case _: None{}

def slot_one(alloc: Bool, n: O.Node) -> Maybe<&2, String>: slot_one.of(alloc, n)

# THE SLOTS OF THE ARENA'S ALLOCATIONS, in ARENA ORDER, comma-joined. The arena order
# IS the toposort order -- `ops.bend:2754` says every node's srcs are appended before
# it -- so this is the same list the oracle's `toposort()` gives, and the two lanes
# print the same thing for the same reason.
#
# `slot_step` IS ITS OWN DEF because a `match` heads a DEF BODY and not a term, and
# `slot_one(is_alloc(O.Node.op(n)), n)` is a term. So the computed answer is BOUND
# first and the match heads the next def.
def slot_step.of(s: Maybe<&2, String>, +t: List<&2, O.Node>, acc: List<&2, String>) -> List<&2, String>:
  match s:
    case Some{v}: List.append(&2, String, acc, [v])
    case None{}: acc

def slot_step(s: Maybe<&2, String>, +t: List<&2, O.Node>, acc: List<&2, String>) -> List<&2, String>:
  slot_step.of(s, t, acc)

def slot_str.go(+ns: List<&2, O.Node>, acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      slot_str.go(t, slot_step(slot_one(is_alloc(O.Node.op(n)), n), t, acc))

def slot_str.of(+ar: O.Arena) -> String:
  String.join(slot_str.go(O.Arena.nodes(ar), Nil{}), ",")

def row(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# --- the scenarios -------------------------------------------------------

# ONE `empty` IN A FRESH SCOPE. Upstream: slot 0.
def one_empty() -> String:
  +ar = O.Arena.empty()
  +a = CR.cr_empty(ar, Some{S.single()}, [4, 3], S.D1{0})
  slot_str.of(T.Tensor.ar(a))

# TWO `empty`s IN ONE SCOPE. The arena is THREADED -- `O.Found.ar(previous)` -- because
# `O.UOp.new` APPENDS and answers a `Found` carrying the GROWN arena, so a fixture that
# built the second off the FIRST arena would build the first node twice.
def two_same_scope() -> String:
  +ar = O.Arena.empty()
  +a = CR.cr_empty(ar, Some{S.single()}, [4, 3], S.D1{0})
  +b = CR.cr_empty(T.Tensor.ar(a), Some{S.single()}, [4, 3], S.D1{0})
  slot_str.of(T.Tensor.ar(b))

# THREE, for a counter that advanced by TWO would still be caught by the second row.
def three_same_scope() -> String:
  +ar = O.Arena.empty()
  +a = CR.cr_empty(ar, Some{S.single()}, [4, 3], S.D1{0})
  +b = CR.cr_empty(T.Tensor.ar(a), Some{S.single()}, [4, 3], S.D1{0})
  +c = CR.cr_empty(T.Tensor.ar(b), Some{S.single()}, [4, 3], S.D1{0})
  slot_str.of(T.Tensor.ar(c))

# A `full` AND THEN AN `empty`. `full` builds a CONST, an EXPAND, an ALLOC, a RESHAPE,
# a STORE and an AFTER -- SIX nodes and ONE allocation -- so the second allocation's slot
# is 1 and not 7. A counter that counted NODES would say 7, and that is the whole
# defect in one row.
def full_then_empty() -> String:
  +ar = O.Arena.empty()
  +f = CR.cr_full(True{}, ar, MO.mo_ki(42), S.weakint(), [2, 3], S.D1{0})
  +e = CR.cr_empty(T.Tensor.ar(f), Some{S.single()}, [4, 3], S.D1{0})
  slot_str.of(T.Tensor.ar(e))

# THE OTHER ORDER, because `full` puts its ALLOC in the arena of the CONST it built
# (`creation.bend`'s "the arena rule") and an `empty` puts its own in the arena it was
# given. The ORDER of the two allocations is what the counter sees.
def empty_then_full() -> String:
  +ar = O.Arena.empty()
  +e = CR.cr_empty(ar, Some{S.single()}, [4, 3], S.D1{0})
  +f = CR.cr_full(True{}, T.Tensor.ar(e), MO.mo_ki(42), S.weakint(), [2, 3], S.D1{0})
  slot_str.of(T.Tensor.ar(f))

# THE WALL: TWO ALLOCATIONS IN TWO SEPARATE SCOPES. Upstream's counter is process-global
# and answers 0 and 1; the port's is arena-scoped and answers 0 and 0. THE PORT LANE
# PRINTS IT AND THE ORACLE DOES NOT, so it is excluded from the diff -- see
# `gates/alloc_slot-gate.py`'s `port_only`.
def two_scopes() -> String:
  +ar = O.Arena.empty()
  +a = CR.cr_empty(ar, Some{S.single()}, [4, 3], S.D1{0})
  +b = CR.cr_empty(O.Arena.empty(), Some{S.single()}, [4, 3], S.D1{0})
  String.concat([slot_str.of(T.Tensor.ar(a)), ",", slot_str.of(T.Tensor.ar(b))])

def main() -> IO(Unit):
  do IO<Unit>:
    row("alloc_one_empty", one_empty())
    row("alloc_two_same_scope", two_same_scope())
    row("alloc_three_same_scope", three_same_scope())
    row("alloc_full_then_empty", full_then_empty())
    row("alloc_empty_then_full", empty_then_full())
    row("alloc_two_scopes", two_scopes())
