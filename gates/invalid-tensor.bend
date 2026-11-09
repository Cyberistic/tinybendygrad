import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O

# invalid-tensor.bend -- THE PORT SIDE of upstream `test/null/test_invalid_tensor.py`.
#
#   .venv/bin/python gates/invalid-tensor-gate.py
#
# WHAT UPSTREAM'S TEST ASSERTS, AND WHERE EACH ASSERTION LIVES AT THE PIN `f5ac54685074`:
#
#   cond = UOp.const(0) < UOp.const(1)      -> `ElementwiseMixin.__lt__` (mixin/elementwise.py)
#                                            -> `_binop(Ops.CMPLT, x, False)` -> `alu(CMPLT)`
#   idx  = UOp(Ops.STACK, src=(c0,c1,c2))    -> a RAW STACK, three CONST srcs
#   out  = cond.where(idx, UOp.invalid())    -> `ElementwiseMixin.where`
#                                            (mixin/elementwise.py:425) -> `self.alu(Ops.WHERE, x, y)`
#                                            -> `UOp(Ops.WHERE, src=(cond, idx, invalid))`
#
#   THE FIVE ASSERTIONS, AND THE PROPERTY EACH ONE IS ABOUT:
#     cond.op is Ops.CMPLT           the comparison is a CMPLT and NOT a folded CONST
#     idx.op  is Ops.STACK           the stack is a STACK
#     out.op  is Ops.WHERE           the select is a WHERE
#     out.src[2].op is Ops.CONST     THE INVALID IS **BARE** -- a CONST, and NOT a CAST
#                                    of one, and NOT an EXPAND of one
#     out.src[2].is_invalid          ... AND IT IS STILL INVALID AFTER THE WHERE
#
# ⇒ THE TEST'S NAME IS THE PROPERTY: `test_uop_where_keeps_invalid_bare`. THE WHERE DOES NOT
#   FOLD THE INVALID AWAY AND DOES NOT RE-SPELL IT AS SOMETHING ELSE.
#
# WHY THIS IS NOT `gates/ops-core`'s `valid_*` ROWS. THOSE ROWS ASK `cond.where(self,
# self.const_like(Invalid))` -- A CONST `self` -- AND ANSWER THE **ARG** CLASS OF EACH SRC
# (`sg_ctor`). THIS TEST ASKS A DIFFERENT QUESTION OF A DIFFERENT GRAPH: THE `x` IS A **STACK**
# WITH THREE SRCS, THE `y` IS A **BARE INVALID CONST** RATHER THAN A `const_like` OF A SHAPED
# NODE, AND THE CLAIM IS ABOUT **`out.src[2].op` AND `out.src[2].is_invalid`** -- THE OP OF THE
# THIRD SRC AND WHETHER IT IS STILL INVALID -- WHICH NO `sg_ctor` ROW CAN SEE, BECAUSE
# `sg_ctor` READS THE ARG AND NOT THE OP.
#
# THE ORACLE IS `gates/invalid-tensor-oracle.py`, WHICH BUILDS THE SAME GRAPH IN CPython's
# OWN `tinygrad` AND ANSWERS THE SAME QUESTIONS. NEITHER LANE READS A CONSTANT FROM THE OTHER.
#
# THE PORT's SIDE IS BUILT FROM THE PORT's OWN DEFS, AND EVERY ONE IS THE UPSTREAM RULE:
#   `O.UOp.alu`      -- ops.py:630 `UOp(op, src=(self, *src), **kwargs)`
#   `O.UOp.where`    -- mixin/elementwise.py:425 `self.alu(Ops.WHERE, x, y)`
#   `O.UOp.invalid`  -- ops.py:635 `UOp.const(Invalid)`
#   `O.UOp.is_invalid` -- ops.py:252 `self.op is Ops.CONST and self.val is Invalid`
#
# ⇒ AND THE ARENA DISCIPLINE IS LOAD-BEARING: EVERY MINT GROWS THE ARENA, SO EACH NODE IS BUILT
#   FROM THE **PREVIOUS NODE's** ARENA AND EVERY READ USES THE **LAST** NODE's. THREADED WRONGLY
#   THE READS COME BACK `ANone{}`, WHICH IS WHAT `gates/ops-core.bend`'s OWN COMMENT RECORDS AS
#   A WRONG DIAGNOSIS OF `where` ITSELF.

# ---- THE ROW PRINTERS -------------------------------------------------------------------

# AN OP NAME, SO A ROW READS THE **OP** AND NOT A BOOLEAN ABOUT IT. A BOOLEAN ROW (`=1`) CANNOT
# TELL "CMPLT" FROM "CMPEQ" FROM "CMPNE" -- THREE WRONG ANSWERS THAT ALL PASS -- SO THE ROWS
# SPELL THE NAME AND THE ORACLE SPELLS THE SAME NAME.
def opname(ar: O.Arena, i: U32) -> String:
  O.Ops.name.of(O.Arena.op(ar, i))

def opname_row(nm: String, ar: O.Arena, i: U32) -> IO(Unit):
  O.srow(nm, opname(ar, i))

def bool_row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# A COUNT, AS THE ORACLE SPELLS IT: THE NUMBER OF SRCS. `U32.show` IS THE PORT's OWN SPELLING
# OF AN UNSIGNED INTEGER.
def nsrc_row(nm: String, ar: O.Arena, i: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(O.Arena.nsrc(ar, i))]))

# ---- THE GRAPH --------------------------------------------------------------------------

# `cond` -- `UOp.const(0) < UOp.const(1)`. UPSTREAM's SPELLING IS `__lt__` -> `_binop(CMPLT)`,
# AND AT THE PIN `_binop` PROMOTES BOTH SIDES AND THEN CALLS `alu(CMPLT)`. THE PORT SPELLS THE
# PROMOTED RESULT DIRECTLY: TWO CONST SRCS AND A CMPLT, WHICH IS EXACTLY THE GRAPH CPython BUILDS
# (MEASURED: `cond.src == (CONST 0, CONST 1)`, `cond.dtype == dtypes.bool`).
#
# ⇒ AND THE ORDER IS CPython's: `_binop(Ops.CMPLT, x, False)` PUTS `self` AT `src[0]` AND `x` AT
#   `src[1]`, SO THE **CONST 0 IS src[0]**. A SWAPPED PAIR IS A DIFFERENT GRAPH.
# ⇒ THE WHOLE GRAPH IS BUILT IN **ONE** ARENA, AND THE THREADING IS LOAD-BEARING. MEASURED
#   2026-11-10: THE FIRST VERSION OF THIS FILE GAVE `cond`, `idx` AND `out` THEIR **OWN**
#   ARENAS -- `g_cond()` AND `g_idx()` EACH STARTED WITH `O.Arena.empty()` -- AND THE PORT THEN
#   PRINTED `out_src0_op=CONST` WHERE CPython PRINTS `CMPLT`. THE REASON IS NOT A WRONG BUILD:
#   IT IS THAT `O.Arena.src(ar, i, 0)` READS SLOT `0` **OF THE ARENA YOU PASS**, AND `cond`'s
#   INDEX BELONGS TO **A DIFFERENT ARENA**, SO THE READ ANSWERED A DIFFERENT NODE. THE PORT's
#   OWN `gates/ops-core.bend` RECORDS THE SAME HAZARD IN ITS OWN WORDS: "ARENA DISCIPLINE IS
#   LOAD-BEARING HERE ... threaded wrongly the three srcs all read `ANone{}`".
#   ⇒ SO ONE ARENA, AND EVERY NODE BUILT FROM THE **PREVIOUS** NODE's ARENA.
def g_cond(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  O.UOp.alu(O.Found.ar(c1), O.OpsCMPLT{}, [O.Found.i(c0), O.Found.i(c1)])

# `idx` -- `UOp(Ops.STACK, src=tuple(UOp.const(x) for x in range(3)))`. A **RAW** STACK WITH
# THREE SRCS, NOT UPSTREAM's `UOp.group` -- `group` IS `UOp(Ops.STACK).after(*srcs)`, WHICH IS
# AN `AFTER` OVER THE STACK, AND THE PIN HAS NO `UOp.stack` AT ALL. THE TEST SPELLS THE STACK
# DIRECTLY, SO THE PORT SPELLS IT DIRECTLY: `O.UOp.new(ar, OpsSTACK{}, [c0,c1,c2], ANone{}, TNone{})`.
def g_idx(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c2), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1), O.Found.i(c2)],
            O.ANone{}, O.TNone{})

# `inv` -- `UOp.invalid()` -- ops.py:635 `UOp.const(Invalid)`: A CONST WHOSE PAYLOAD IS THE
# `Invalid` SINGLETON. THE PORT's SPELLING IS `O.UOp.invalid`, WHICH IS `UOp.const(CInvalid{})`.
def g_inv(ar: O.Arena) -> O.Found:
  O.UOp.invalid(ar)

# `out` -- `cond.where(idx, UOp.invalid())` -- mixin/elementwise.py:425: `x, y =
# self.ufix(x)._broadcasted(y); return self.alu(Ops.WHERE, x, y)`. SO THE WHERE's SRCS ARE
# `(cond, x, y)` **IN THAT ORDER** -- THE CONDITION FIRST -- AND THE PORT's `O.UOp.where` IS
# SPELLED THE SAME WAY.
#
# ⇒ AND UPSTREAM's `_broadcasted` PROMOTES BOTH SIDES TO `least_upper_dtype`, WHICH AT THE PIN
#   LEAVES **BOTH** UNCHANGED HERE: `idx` IS ALREADY `weakint` AND THE INVALID'S
#   `base.is_invalid` SHORT-CIRCUITS ITS PROMOTION (elementwise.py:30). MEASURED ON CPYTHON:
#   `out.src[1] is idx` AND `out.src[2] is inv` ARE BOTH **True** -- THE SRCS SURVIVE **BY
#   IDENTITY**, SO NOTHING IS CAST AND NOTHING IS REPLACED. THE PORT's `O.UOp.where` SPELLS THE
#   SAME THREE SRCS, AND THESE ROWS ARE WHAT SAY SO.
def g_out(ar: O.Arena, +cond: O.Found, +idx: O.Found) -> O.Found:
  +inv = O.UOp.invalid(ar)
  O.UOp.where(O.Found.ar(inv), O.Found.i(cond), O.Found.i(idx), O.Found.i(inv))

# ---- THE ROWS ---------------------------------------------------------------------------

def rows() -> IO(Unit):
  # THE GRAPH IS BOUND **BEFORE** THE `do` BLOCK, because a `do` BLOCK'S LET IS
  # `name : T <- expr` AND NOT A `+name = expr` BINDING -- MEASURED 2026-11-10: THE FIRST
  # VERSION OF THIS FILE PUT `+cond = g_cond()` INSIDE THE BLOCK AND `bend` ANSWERED
  # "expected : a do-block let with its type (write \"x : T = ...\")".
  +ar0 = O.Arena.empty()
  +cond = g_cond(ar0)
  +idx = g_idx(O.Found.ar(cond))
  +inv = g_inv(O.Found.ar(idx))
  +out = g_out(O.Found.ar(inv), cond, idx)
  do IO<Unit>:
    # THE CONDITION. `CMPLT` AND NOT A FOLDED CONST AND NOT `CMPEQ`.
    a : Unit <- opname_row("cond_op", O.Found.ar(cond), O.Found.i(cond))
    b : Unit <- nsrc_row("cond_nsrc", O.Found.ar(cond), O.Found.i(cond))
    c : Unit <- opname_row("cond_src0_op", O.Found.ar(cond), O.Arena.src(O.Found.ar(cond), O.Found.i(cond), 0))
    d : Unit <- opname_row("cond_src1_op", O.Found.ar(cond), O.Arena.src(O.Found.ar(cond), O.Found.i(cond), 1))
    # THE STACK. A RAW STACK WITH THREE CONST SRCS.
    e : Unit <- opname_row("idx_op", O.Found.ar(idx), O.Found.i(idx))
    f : Unit <- nsrc_row("idx_nsrc", O.Found.ar(idx), O.Found.i(idx))
    g : Unit <- opname_row("idx_src0_op", O.Found.ar(idx), O.Arena.src(O.Found.ar(idx), O.Found.i(idx), 0))
    h : Unit <- opname_row("idx_src1_op", O.Found.ar(idx), O.Arena.src(O.Found.ar(idx), O.Found.i(idx), 1))
    i : Unit <- opname_row("idx_src2_op", O.Found.ar(idx), O.Arena.src(O.Found.ar(idx), O.Found.i(idx), 2))
    # THE INVALID, BEFORE ANY WHERE TOUCHES IT: A CONST, AND INVALID.
    j : Unit <- opname_row("inv_op", O.Found.ar(inv), O.Found.i(inv))
    k : Unit <- bool_row("inv_is_invalid", O.UOp.is_invalid(O.Found.ar(inv), O.Found.i(inv)))
    # THE WHERE, AND ITS THREE SRCS. THE ORDER IS THE CLAIM: `(cond, x, y)`.
    l : Unit <- opname_row("out_op", O.Found.ar(out), O.Found.i(out))
    m : Unit <- nsrc_row("out_nsrc", O.Found.ar(out), O.Found.i(out))
    n : Unit <- opname_row("out_src0_op", O.Found.ar(out), O.Arena.src(O.Found.ar(out), O.Found.i(out), 0))
    o : Unit <- opname_row("out_src1_op", O.Found.ar(out), O.Arena.src(O.Found.ar(out), O.Found.i(out), 1))
    p : Unit <- opname_row("out_src2_op", O.Found.ar(out), O.Arena.src(O.Found.ar(out), O.Found.i(out), 2))
    # ⇒ THE PROPERTY THE TEST IS NAMED FOR: THE THIRD SRC IS **BARE** -- A CONST -- AND IT IS
    #   **STILL INVALID** AFTER THE WHERE. A WHERE THAT CAST IT, EXPANDED IT, OR DROPPED IT
    #   FAILS ONE OF THESE TWO ROWS.
    q : Unit <- bool_row("out_src2_is_invalid", O.UOp.is_invalid(O.Found.ar(out), O.Arena.src(O.Found.ar(out), O.Found.i(out), 2)))
    # AND THE THREE **WHOLE** NODES SURVIVE BY IDENTITY, WHICH IS WHAT CPython's `_broadcasted`
    # MEASURED: THE WHERE DOES NOT RE-SPELL ITS SRCS.
    r : Unit <- bool_row("out_src0_is_cond", U32.is_eq(O.Arena.src(O.Found.ar(out), O.Found.i(out), 0), O.Found.i(cond)))
    s : Unit <- bool_row("out_src1_is_idx", U32.is_eq(O.Arena.src(O.Found.ar(out), O.Found.i(out), 1), O.Found.i(idx)))
  # ⇒ AND THE `return Unit{}` IS LOAD-BEARING, NOT DECORATION. MEASURED 2026-11-10: A `do`
  # BLOCK THAT IS THE WHOLE BODY OF A DEF NEEDS IT -- WITHOUT IT `bend` ANSWERS "expected : a
  # term (the keyword 'def' cannot head one)" AND POINTS AT **THE NEXT `def`**, WHICH IS A
  # CONFUSING PLACE TO LOOK. (`gates/constid.bend`'s `rows()` HAS NO SUCH `return`, SO THE RULE
  # IS NOT "A `do` BLOCK ALWAYS NEEDS ONE" -- IT IS THAT THE BLOCK'S SHAPE DECIDES IT, AND THE
  # FAILING CASE IS THE ONE THAT READS AS A PARSE ERROR SOMEWHERE ELSE.)
  return Unit{}

def main() -> IO(Unit): rows()
