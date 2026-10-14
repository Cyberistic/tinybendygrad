#!/usr/bin/env python3
"""decomp_value-gate.py -- THE NUMERIC ORACLE for `decomp_graph_census`'s 11 PROMOTION rows.

    .venv/bin/python gates/decomp_value-gate.py
    .venv/bin/python gates/decomp_value-gate.py --refresh   # rewrites the pins file

THE QUESTION THIS ANSWERS, AND NOBODY ELSE IN THIS TREE DOES. `decomp_graph_census-gate.py`
compares op SEQUENCES and `ops_python_census` compares counts, and neither can see that a node
spelled the same way can MEAN something different. CPython's `ElementwiseMixin._broadcasted`
(`mixin/elementwise.py:24`) inserts a general `least_upper_dtype` PROMOTION CAST via its inner
`promote` (`:26`, `:32`); decomp's ALU path is `dd_add`/`dd_mul`/... -> `tx_alu2` ->
`O.UOp.alu` (`transcendental.bend:199`), a raw ALU that never calls it. So the port computes
intermediates NARROWER. The census's own block records `lg1` 3 of 13 kept nodes at a different
dtype, `lg5` 1 of 14 and `lgd` 1 of 12, and then says the question is unanswerable there. THIS
FILE IS THE ANSWER, and the answer is a value.

WHAT IT IS, IN ONE LINE: it EVALUATES both cones with `tinygrad.runtime.ops_python` --
`PythonProgram.__call__`, the real interpreter, whose ALU step is `exec_alu` (ops.py) -- and
compares the VALUES, over an operand fixture set chosen to make a narrower intermediate
OBSERVABLE.

## THE TRAP, AND HOW THIS FILE DOES NOT FALL IN IT.

`gates/tn_bitwise_not-oracle.py`'s docstring is the post-mortem for an oracle that hand-built
`cast.ne(true_)` instead of calling `Tensor.bitwise_not()`: an oracle that re-implements the
thing it is checking agrees with a port that is ITSELF wrong. Three facts, each MEASURED:

  1. **NOTHING HERE EVALUATES AN ARITHMETIC OP.** The cones are `tinygrad` `UOp`s and the
     evaluation is `PythonProgram` over them; `exec_alu`/`python_alu`/`bitcast`/`truncate` are
     `tinygrad`'s, reached through `ops_python`, not this file's.
  2. **THE PORT'S CONE IS NOT A TRANSCRIPTION OF A BEND ARENA.** It is CPython's own `UOp`
     graph with the census's own declared `CAST/1` nodes spliced out -- and WHICH nodes is not
     this file's guess: `port_cone()` walks CPython's cone against the port's SIGNATURE pinned
     in `decomp_graph_census-pins.rows` and takes the deletion the walk forces. That is the
     census's `deleted()` witness, lifted from tokens to node identity, and it is RE-VERIFIED on
     every run by `splice_is_the_port()`: the spliced cone's `sig` must equal the pinned port
     `sig` token for token, over the whole cone (2 431 tokens for `lgq`), and the count must
     equal the gate's declared `PROMOTION_CASTS` entry. If that fails this file exits 1 and says
     so -- it does not fall back to a weaker claim.
  3. **THE HARNESS IS CHECKED AGAINST SOMETHING THAT IS NOT ITSELF.** `truth_holds()` asks
     whether the CPython cone's VALUE equals a CLOSED FORM for every row where one exists --
     `lg1` is two's-complement negation, `lgq`/`lgs` are unsigned `//`, `lgr`/`lgt` are
     unsigned `%` -- over every family. A harness whose fixture plumbing or word packing is
     wrong fails there, before any disagreement it might report is worth reading. That is the
     `tn_bitwise_not` lesson applied to THIS instrument instead of to a past one.

## WHAT IT CANNOT SEE, NAMED BECAUSE A GREEN GATE THAT CANNOT DISTINGUISH "NOT TRIGGERED"
## FROM "NO SUCH THING" IS THE NINTH INSTRUMENT BUG OF THIS SESSION.

  * **IT EVALUATES THE PORT'S CONE AS "CPYTHON'S CONE MINUS THE DECLARED CASTS".** The census
    proves the two graphs agree node-for-node on the cone SIGNATURE; the signature carries no
    dtype and no constant value, so a port defect of some OTHER class that produced the same
    token sequence would not be visible here. The question asked -- does the MISSING PROMOTION
    change the value -- is inside the claim; a claim wider than the question is not.
  * **IT COMPARES WORD BIT PATTERNS, NOT SIGNED INTERPRETATIONS.** `l2i` answers a pair of
    32-bit words; both lanes are read through `from_storage_scalar` at each root's OWN dtype and
    packed `w0 | w1<<32`, so a lane whose words carry the same bits under a different signedness
    reads the same here. That is the right comparison for a WORD decomposition and the wrong one
    for a consumer that reinterprets; no consumer is in these cones.
  * **`SIG` DOES NOT PIN `src` ORDER FOR A COMMUTATIVE OP.** The census's token is `op/nsrc` and
    the DFS visits `src[0]` first, so `ADD(x,y)` and `ADD(y,x)` are the same token. A dropped
    CAST that sat at a consumer's `src[0]` therefore could in principle have moved. MEASURED:
    `src0_moves()` counts them per row and every op it lands on is commutative, so the VALUE is
    unaffected; the check runs on every run so that stays a measurement and not a hope.
  * **WITNESS AMBIGUITY IS COUNTED, NOT ASSUMED AWAY.** `alternatives()` enumerates the other
    size-`n` CAST deletions that reproduce the port's signature and reports whether any of them
    changes a verdict. `lg1` admits one alternative; the gate prints it.

EXIT STATUS, `gatekit`'s five: 0 every row evaluated on both graphs and every claim holds ·
1 a splice is not the port's cone, the harness disagrees with a closed form, the pins moved, or
a row disagrees in VALUE · 3 a precondition was absent (the census pins, or the census itself).

This gate has ONE lane and no `.bend` driver, which is why it does not use `gatekit.Gate`: that
class runs `bend --check-only`, the interpreter lane, the native lane and a three-way diff, and
a gate with no Bend driver would have to fake two of those four. The five EXIT CODES are the
same five, and they are read from `gatekit` rather than re-spelled.
"""

import importlib.util
import io
import contextlib
import mmap
import pickle
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import PASS, FAIL, REFUSED, VERDICT  # noqa: E402

from tinygrad.dtype import (dtypes, from_storage_scalar, least_upper_dtype,  # noqa: E402
                             storage_fmt_for_dtype, to_storage_scalar, truncate)
from tinygrad.helpers import Target, all_same, mv_address  # noqa: E402
from tinygrad.runtime.ops_python import PythonProgram  # noqa: E402
from tinygrad.uop.ops import (UOp, Ops, GroupOp, ParamArg, AddrSpace,  # noqa: E402
                             bitcast, exec_alu)
from tinygrad.uop.weak import commit_srcs_at, commit_weak_consts  # noqa: E402

PINS = HERE / "decomp_value-pins.rows"


def _load(name, path):
  """Load a `gates/` module BY PATH, with its module-scope printing captured.

  The census's oracle prints its 38 rows at import and has no `__main__` guard, so it is run
  with stdout captured rather than edited: `decomp_graph_census-oracle.py` and its pins are
  another unit's files, and a gate that re-declares its fixture pool is a second population.

  **`sys.argv` IS SCRUBBED, AND IT IS NOT DEFENSIVE.** `decomp_graph_census-gate.py:386` reads
  `if "--refresh" in sys.argv: sys.exit(refresh())` at MODULE SCOPE, so importing it from a
  process that was itself given `--refresh` RUNS THE CENSUS'S REFRESH and EXITS THE PROCESS
  from inside the import. MEASURED: `decomp_value-gate.py --refresh` returned rc=0, printed
  nothing and wrote no pins file, because the imported census took `--refresh` as its own.
  A gate that imports another gate has to own that gate's module scope, and "exit 0 having
  measured nothing" is the exact shape this tree records as the ninth instrument bug.
  """
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  argv, sys.argv = sys.argv, [str(HERE / Path(path).name)]
  try:
    with contextlib.redirect_stdout(io.StringIO()):
      spec.loader.exec_module(mod)
  finally:
    sys.argv = argv
  return mod


CENSUS = _load("decomp_graph_census", HERE / "decomp_graph_census-gate.py")
ORACLE = _load("decomp_graph_census_oracle", HERE / "decomp_graph_census-oracle.py")
if CENSUS.DIVERGES is None:
  print(f"decomp_value-gate: REFUSED, NOT A VERDICT: the census has no pins: {CENSUS.WHY}",
        file=sys.stderr)
  sys.exit(REFUSED)

PROMOTION = dict(CENSUS.PROMOTION_CASTS)
PORT_SIG = {r: v[1].split("=", 1)[1] for r, v in CENSUS.DIVERGES.items()}

# ================================================================= the population
# THE 11 DECLARED PROMOTION ROWS, LOADED BY PATH from the census gate's own
# `PROMOTION_CASTS` -- not re-listed here. A second copy of that tuple is a population that
# cannot be wrong, which is `AGENTS.md`'s first doctrine.


def answer(nm):
  """CPython's answer UOp(s) for a census row, rebuilt from the census's OWN fixtures.

  `ORACLE.L2I`/`ORACLE.F2F` are the census oracle's fixture tuples, index for index, and
  `ORACLE.ws`/`ORACLE.par` build the same 24 named PARAMs the census compares cones over.
  """
  for r, op, dt, xdt, base, nw in ORACLE.L2I:
    if r == nm:
      return ORACLE.DT.l2i(op, dt, *ORACLE.ws(base, nw))
  for r, fr, to in ORACLE.F2F:
    if r == nm:
      return ORACLE.DT.f2f(ORACLE.par(ORACLE.DT.f2f_dt[fr], r), fr, to, True)
  raise KeyError(nm)


def roots_of(ans):
  return tuple(ans) if isinstance(ans, tuple) else (ans,)


def sig_of(rts):
  return ",".join(ORACLE.s1(u) for u in ORACLE.cone(rts))


# ============================================================ the port's cone, by splice
def port_cone(rts, ptok):
  """CPython's cone with the census's declared `CAST/1` nodes spliced out, or `None`.

  THE WALK. CPython's cone is DFS pre-order (`ORACLE.cone`); the port's pinned row is the same
  walk over the port's arena (`dd_cone`/`dd_esig`). Both are `op/nsrc` token sequences, so
  walking one against the other LEFT-GREEDILY and dropping every cone node whose token does not
  match the port's next one yields a candidate deletion set -- and `j` reaching the end is what
  makes the candidate THE port's cone rather than a prefix of it. `deleted()` in the census gate
  does this over strings and throws the node identities away; here they are the answer, because
  a value oracle must delete a NODE, not a comma.
  """
  drop, j = set(), 0
  for u in ORACLE.cone(rts):
    if j < len(ptok) and ORACLE.s1(u) == ptok[j]:
      j += 1
    else:
      drop.add(id(u))
  if j != len(ptok) or any(True for _ in ()) or not drop:
    return None
  return drop


def splice(rts, drop):
  """Rebuild the cone replacing every dropped node BY ITS OWN SRC, not by removing the slot.

  THE FIRST DRAFT GOT THIS WRONG and it is the whole measurement: dropping the slot collapses
  `ADD(a, CAST(b))` to a one-armed `ADD/1`, so every row's cone fell to 4-13 tokens against the
  port's 13-2 431 and the gate read a hash-consing artefact as a defect. `_broadcasted` REPLACES
  the operand (`return promote(x), promote(y)`), so the consumer keeps its arity and reads one
  node further down. `UOp` interns on `(op, src, arg, tag)`, so the rebuild IS the port's
  identity rule and not an approximation of it.
  """
  memo = {}

  def go(v):
    if id(v) in memo:
      return memo[id(v)]
    srcs = tuple(go(s.src[0]) if id(s) in drop else go(s) for s in v.src)
    nv = UOp(v.op, srcs, v.arg, v.tag) if srcs != v.src else v
    memo[id(v)] = nv
    return nv

  return tuple(go(r) for r in rts)


def commit(rts):
  """`commit_weak_consts` at each node's OWN dtype, to fixpoint, and how many nodes it touched.

  ## WHY THE EVALUATOR NEEDS THIS, MEASURED, AND IT IS NOT A CONVENIENCE.

  `ops_python.py:153` asserts `all_same([u.dtype] + src_dtypes)` on every ALU. `l2i`'s OWN
  output violates it: MEASURED on `lg1`, CPython's cone carries **three** `MUL(i64,
  [i64, weakint])` nodes -- `a0 * (-1)` where `-1` is a bare `UOp.const(-1)`, whose dtype is
  `weakint` because a negative int derives one. So `PythonProgram` cannot execute CPython's own
  `lg1` cone, let alone the port's, and the honest reading of that is "the instrument must
  normalise first", not "the interpreter is wrong".

  ## WHY `pm_commit_weak` IS NOT ENOUGH, AND IT IS NOT A MATTER OF PASSES.

  MEASURED: four `graph_rewrite(..., pm_commit_weak, bottom_up=True)` passes over `lg1` change
  **0** nodes. The reason is in `tinygrad/uop/weak.py:14`: `commit_srcs_at` rebuilds a committed
  CONST as `UOp.const(dt.const(s.val))`, and `UOp.const(-1)` is the SAME bare `weakint` CONST it
  started from, so `u.replace(src=src) is u` and the rule returns `None`. A negative int cannot
  be committed by the width route at all.

  ## WHAT THIS CALLS, AND WHY IT IS NOT A REIMPLEMENTATION.

  `commit_weak_consts` (weak.py:10) and `commit_weak_srcs` (weak.py:26) are tinygrad's own
  functions; only the DTYPE argument of the first is chosen here, and it is chosen by a rule this
  file states rather than guesses: **the node's own derived dtype**, which is what the node will
  use the const at. It is applied bottom-up, to fixpoint, and IDENTICALLY TO BOTH LANES, so it
  cannot manufacture a disagreement between them. `ccast` of a CONST is a CONST at the target
  dtype (`UOp.const(b, dt)` is `UOp.const(b).cast(dt)`, ops.py:634), so **it adds no nodes and
  moves no value** -- it names the width a value will be read at, which is the whole content of
  "commit".

  THE TWO ARE NOT INTERCHANGEABLE, and `commit_weak_srcs(u) or commit_weak_consts(u, u.dtype)`
  is WRONG -- the `or` evaluates its left operand, because `UOp` defines `__bool__` (ops.py:527)
  as "evaluate me". MEASURED: `AssertionError: eval with wrong dtype UOp(Ops.MUL, ...)`. It is
  an `is None` test.
  """
  n = 0
  for _ in range(8):
    memo = {}

    def go(v):
      nonlocal n
      if id(v) in memo:
        return memo[id(v)]
      srcs = tuple(go(s) for s in v.src)
      u = UOp(v.op, srcs, v.arg, v.tag) if srcs != v.src else v
      if any(s.dtype in dtypes.weaks for s in u.src):
        # THE DTYPE IS `least_upper_dtype` OF THE OTHER SRCS, AND NOT `u.dtype`. MEASURED, and
        # the measurement is the whole difference between an oracle and a saboteur: committing at
        # `u.dtype` turns `CONST(32, weakint)` into `CONST(True, bool)` on a `Ops.CMPLT` --
        # `DType.bool.const(32)` is `bool(val)` (dtype.py:84) -- and then `l2i(Ops.SHR, ...)`'s
        # `b0 >= 32` reads `1 < True`, which is False, so the shift arm takes its `>= 32` branch
        # for a count of 1. MEASURED downstream: `l2i(CDIV, uint32, 7, 2)` answered 0 instead of
        # 3, `CMOD(100, 7)` answered 0 instead of 2, and the gate's OWN closed-form check caught
        # it. Had this file shipped without `claims()`'s closed form, it would have reported 198
        # green rows computed on a graph it had corrupted.
        #
        # `commit_srcs_at` FIRST (weak.py:19) and `commit_weak_consts` (weak.py:10) SECOND,
        # because each covers a case the other does not. MEASURED, both directions: the const
        # route alone leaves `lg5`'s `MUL(f32, [f32, RECIPROCAL(weakfloat)])` and `q5`'s
        # `ADD(u32, [u32, <a non-CONST weakint>])` uncommitted, because `commit_weak_consts`
        # commits only CONST srcs; the general route alone leaves `lg1`'s three
        # `MUL(i64, [i64, CONST(-1)])`, because `commit_srcs_at` rebuilds a committed const as
        # `UOp.const(dt.const(-1))`, which IS the bare `weakint` it started from, so it returns
        # `None`. Both are tinygrad's own functions and neither is re-implemented here.
        c = commit_srcs_at(u, least_upper_dtype(*(s.dtype for s in u.src)))
        if c is None:
          c = commit_weak_consts(u, least_upper_dtype(*(s.dtype for s in u.src)))
        n += c is not u
        u = c
      memo[id(v)] = u
      return u

    nxt = tuple(go(r) for r in rts)
    if nxt == rts:
      return rts, n
    rts = nxt
  return rts, n


def witnesses(rts, ptok, n):
  """`(greedy indices, every alternative index-set, capped)` for one row's CAST deletions.

  ## WHY THIS IS AN ENUMERATION AND NOT A GREEDY WALK.

  `CAST/1` is ONE TOKEN, so two adjacent casts are interchangeable to a left-greedy walk and it
  keeps the earlier one. `gates/decomp_graph_census-gate.py` counts the alternatives under a
  200-token cap and REPORTS `lg1` admitting exactly one -- and the first draft of this gate took
  the greedy walk's answer for granted, exactly as the census warns against. MEASURED what that
  cost: on `lgq` the greedy witness splices out 198 `CAST/1` nodes where the census declares 69,
  and the resulting graph contains **132** ALU nodes whose srcs are not at a common width, so
  `PythonProgram` refuses to execute it. A value oracle that reports "the values differ" from a
  graph it guessed is the `tn_bitwise_not` failure wearing a different hat.

  So the alignments are ENUMERATED: a DFS over (cone index, port index) whose only branch is
  "is this cone node a CAST that may be deleted", memoised on `(i, j)`, with a hard cap so a row
  with astronomically many witnesses says SO instead of running forever. `more` is `True` when
  the cap was hit, and the gate then reports the row's witness set as UNPROVEN rather than
  pretending the greedy one is the port's.

  ## THE TWO SHAPES A SOLUTION HAS, AND WHY ONLY ONE IS USABLE.

  `UOp.replace(src=...)` re-derives the node's dtype from its srcs, so a splice that deletes
  `CAST(u32->i64)` at `src[1]` of an `i64` `ADD` leaves an `i64` `ADD` holding a `u32` -- a node
  `ops_python.py:153` refuses, because that assert IS tinygrad's statement that a binop's two
  operands have already been promoted. Deleting a CAST at `src[0]` instead re-derives the node at
  the NARROWER width and stays executable. Which of the two a witness does is the whole answer,
  and it is reported per row rather than assumed.
  """
  cone = ORACLE.cone(rts)
  ct = [ORACLE.s1(u) for u in cone]
  m, p = len(ct), len(ptok)
  cast = [i for i, u in enumerate(cone) if u.op is Ops.CAST]
  solutions, overflow = [], [False]

  def go(i, j, acc):
    if overflow[0]:
      return
    if j == p:
      if i == m:
        solutions.append(tuple(sorted(acc)))
      elif len(acc) <= n and all(k in cast for k in range(i, m)):
        solutions.append(tuple(sorted(acc + list(range(i, m)))))
      return
    if len(acc) > n or i >= m:
      return
    if ct[i] == ptok[j]:
      go(i + 1, j + 1, acc)
    if i in cast and len(acc) < n:
      go(i + 1, j, acc + [i])

  go(0, 0, [])
  if not solutions:
    return None, [], False
  return list(solutions[0]), solutions[1:], overflow[0]


def src0_moves(rts, drop):
  """`(op, commutative)` for every node whose `src[0]` is a dropped node.

  THE HOLE THIS NAMES. The census's token is `op/nsrc` and the DFS reads `src[0]` first, so a
  commutative node reads the same with its two srcs exchanged; a splice that deleted a node
  sitting at `src[0]` could therefore land on a graph the signature cannot distinguish from the
  port's. Whether that matters is a property of the OP, so it is measured here and reported by
  name, not assumed.
  """
  out = []
  for u in ORACLE.cone(rts):
    if len(u.src) >= 2 and id(u.src[0]) in drop:
      out.append((u.op.name, u.op in GroupOp.ALU and _commutative(u.op)))
  return out


def _commutative(op):
  # `Ops.LOGICAL_AND`/`Ops.LOGICAL_OR` are NOT here: tinygrad lowers them, and `l2i`'s cones
  # carry `Ops.AND`/`Ops.OR` from `logical_not` (`mixin/elementwise.py:57`). An op missing
  # from this set is reported NON-commutative, which is the conservative direction: a false
  # "commutative" weakens a claim, a false "not commutative" fails the gate loudly.
  return op in {Ops.ADD, Ops.MUL, Ops.MAX, Ops.AND, Ops.OR, Ops.XOR, Ops.CMPEQ, Ops.CMPNE}


# ================================================== the evaluator: `PythonProgram`, real
class _Elf:
  """The two fields `PythonProgram.__init__` reads off a `TinyELF`: `lib` and `target`.

  `obj.lib` is the pickled uop list and `obj.target` is handed to `PythonRenderer` for its
  tensor cores -- which no ALU cone has a use for, so a real `Target` is passed rather than a
  fabricated one.
  """

  def __init__(self, uops):
    self.lib = pickle.dumps(uops)
    self.target = Target(renderer="PYTHON")


def _topo(roots):
  """Post-order, so every node's srcs precede it -- what `PythonProgram`'s `values` dict needs."""
  out, seen = [], set()

  def go(v):
    if id(v) in seen:
      return
    seen.add(id(v))
    for s in v.src:
      go(s)
    out.append(v)

  for r in roots:
    go(r)
  return out


class Program:
  """One `PythonProgram` over one cone, with a private mmap per root to read the answer back.

  THE READ-OUT IS CASTS-FREE ON PURPOSE. Every root gets its OWN `Ops.PARAM` at the ROOT'S OWN
  dtype and its own `Ops.STORE` at index 0, and the word is read back with
  `from_storage_scalar` at that dtype. An earlier shape wrote one `uint32` out-buffer and
  `.cast(uint32)` every root into it, which would have TRUNCATED each `i64` root -- and on
  these rows the `i64`/`i32` roots are exactly what is under test.

  **EACH ROOT NEEDS A DISTINCT OUT-PARAM, AND THE FIRST DRAFT GOT IT WRONG.** MEASURED: two
  `ParamArg(-1, i64, 1, name="out", addrspace=GLOBAL)` args are EQUAL, and `UOp` interns on them,
  so both roots' `Ops.INDEX` read ONE PARAM. `PythonProgram` popped one buffer for it, both
  `Ops.STORE`s landed in the same 8-byte mmap -- the second at element 1, which `_store`'s
  bounds check passes because `to_mv(addr, max_numel*itemsize)` bounds the VIEW, not the
  mapping -- and the read-back saw the second root's value twice: MEASURED `lg1` answering
  `[-2, -2]` where the truth is `[-1, -2]`. Distinct `slot`s, and ONE call with all the buffers,
  are the fix; `PythonProgram` pops one `bufs` entry per GLOBAL PARAM in list order.
  """

  def __init__(self, rts):
    self.roots = rts
    tails, self.mms, self.views = [], [], []
    for i, r in enumerate(rts):
      out = UOp(Ops.PARAM, src=(), arg=ParamArg(-1 - i, r.dtype, 1, name=f"out{i}",
                                                 addrspace=AddrSpace.GLOBAL, device=None))
      tails.append(UOp(Ops.STORE, src=(out.index(UOp(Ops.CONST, src=(), arg=0)), r)))
      mm = mmap.mmap(-1, r.dtype.itemsize, access=mmap.ACCESS_WRITE)
      self.mms.append(mm)
      self.views.append(memoryview(mm).cast(storage_fmt_for_dtype(r.dtype)))
    uops = _topo(tuple(tails))
    self.prog = PythonProgram(None, _Elf(uops))
    # `PythonProgram.__call__` feeds ALU PARAMs by `vals.pop(0)` IN THE ORDER THEY APPEAR in its
    # uop list, so the order here IS the wire order and it is read off the list rather than
    # sorted: sorting by slot would be a second, silent ordering rule. The out PARAMs are GLOBAL
    # and are excluded for the same reason `PythonProgram` excludes them -- they arrive as `bufs`.
    self.alu = [u for u in uops if u.op is Ops.PARAM and u.addrspace is AddrSpace.ALU]

  def words(self, vals):
    """`(word, ...)` -- each root's OWN value at its OWN dtype -- and `lo | hi<<32` packed."""
    self.prog(*[mv_address(m) for m in self.mms], vals=tuple(vals(u.arg.name) for u in self.alu))
    packed, out = 0, []
    for i, r in enumerate(self.roots):
      w = from_storage_scalar(self.views[i][0], r.dtype)
      out.append(w)
      packed |= (int(w) & 0xFFFFFFFF) << (32 * i)
    return out, packed


# ================================================================ the operand families
# WORD FAMILIES. The census's fixture pool is 24 NAMED PARAMs -- four `w` words (u8,u16,u32,u64)
# then five each of i32, u32, bool and f32 (`dtype.bend:2549-2597`'s `dd_wpool`, mirrored at
# `decomp_graph_census-oracle.py:59`). MEASURED on this run, the 11 PROMOTION rows read slots
# `w9 w10 w11 w12` (u32 words), `w19` (f32, `lg5` only) and one PARAM named after its row
# (`q5`, at `f2f_dt[float32]`). `params_of` reports them per row and the gate FAILS on a PARAM
# `vals_for` does not fill, so this table cannot quietly stop covering the population.
#
# WHAT EACH FAMILY IS FOR, AND THE ONE THING IT CANNOT DISTINGUISH. "A value oracle with one
# operand pair is a green gate that proves nothing": `o` below is precisely the family on which
# a narrower intermediate AGREES with a wider one, and it is here as a control, not as evidence.
#
#   z     every word 0. THE NO-OPERATION BASELINE. Cannot detect a result that is wrong only away
#         from zero, and it makes every CDIV/CMOD a 0/0.
#   o     every word 1 -- a = b = 0x0000_0001_0000_0001. THE CONTROL: the smallest non-trivial
#         64-bit pattern, and the case where a 32-bit intermediate and a 64-bit one AGREE.
#   M     every word 0xFFFFFFFF -- a = b = 2^64-1. THE WIDTH-SATURATION CASE: a00*b00 = 0xFFFE0001
#         still fits in 32 bits while a01*b01 does not, and CDIV(2^64-1, 2^64-1) borrows at every
#         step. Cannot separate lanes that differ only just below saturation.
#   H     every word 0x80000000 -- a = b = 2^63, every word's sign bit set. The case where a
#         signed and an unsigned reading of the same bits diverge most. Cannot reach a defect that
#         needs an odd high word.
#   L     every word 1 -- a = b = 0x0000_0001_0000_0001, the same 64-bit values as `o` but built
#         from high words of 1, i.e. a product of 0x1_0000_0001 that OVERFLOWS 32 bits by one
#         bit. `o` and `L` together are the pair that separates a lane `o` alone cannot.
#   Asym  a = b = 0xFFFFFFFF built ASYMMETRICALLY (low words max, high words zero): the same
#         64-bit values as `M`, different WORDS. Cannot separate a defect that needs the two
#         operands to carry different word values AND a full high word.
#   Near  a = 0x0000_0001_FFFF_FFFF, b = 0x0000_0002_0000_0000 -- a 32-bit-overflowing product
#         beside a 33-bit one that still fits in 64. Cannot reach anything above 2^64, which is
#         unreachable for these rows by construction.
#   Dvd   a = 0xFFFF_FFFF_FFFF_FFFF, b = 1. THE QUOTIENT-IS-WIDE CASE: a // 1 has every bit set,
#         so a lane that carried only a0 into the high word returns 0xFFFFFFFF.
#   Shift a = 0x9ABCDEF0_12345678, b0 = 0xFFFFFFFF. `lga`/`lg9`'s THIRD operand is a shift count
#         and the arms read `b0 & 31` AND `b0 >= 32` (dtype.py:43-44, :48-49), so this is the only
#         family that reaches the `>= 32` branch. Cannot reach a count that is neither small nor
#         saturated -- and that gap is named rather than papered over.
#   Rnd   fixed-seed 64-bit words, no `random`, so a pin is reproducible. A backstop, not a head:
#         a random draw cannot distinguish a defect that needs a STRUCTURED operand.
WORD = {
  "z":     (0x00000000, 0x00000000, 0x00000000, 0x00000000),
  "o":     (0x00000001, 0x00000001, 0x00000001, 0x00000001),
  "M":     (0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF),
  "H":     (0x80000000, 0x80000000, 0x80000000, 0x80000000),
  "L":     (0x00000001, 0x00000001, 0x00000001, 0x00000001),
  "Asym":  (0xFFFFFFFF, 0x00000000, 0xFFFFFFFF, 0x00000000),
  "Near":  (0xFFFFFFFF, 0x00000001, 0x00000002, 0x00000000),
  "Dvd":   (0xFFFFFFFF, 0xFFFFFFFF, 0x00000001, 0x00000000),
  "Shift": (0x12345678, 0x9ABCDEF0, 0xFFFFFFFF, 0x00000000),
  "Rnd":   (0xDEADBEEF, 0xFEEDFACE, 0x0BADC0DE, 0x00C0FFEE),
}
# THE f32 SLOT (w19) FOR EACH WORD FAMILY, as a BIT PATTERN, so one family drives `lg5` and `q5`
# alike. `M`'s is a NaN, `H`'s is -0.0, `L`'s the smallest denormal, `Shift`'s another NaN --
# deliberately non-finite values on a row whose cone has a RECIPROCAL.
FLOAT_OF = {
  "z": 0x00000000, "o": 0x3F800000, "M": 0xFFFFFFFF, "H": 0x80000000, "L": 0x00000001,
  "Asym": 0x7F800000, "Near": 0x3FC00000, "Dvd": 0x4B800000, "Shift": 0x7FC00000,
  "Rnd": 0xBF800000,
}
# EXTRA f32 BIT PATTERNS, for the rows whose PARAM is a float BIT PATTERN. `q5`'s PARAM is at
# `f2f_dt[float32]`, a UINT (dtype.py:97), and `f2f`'s narrowing arm reads it through `v.bitcast(fr)`
# -- so its operand IS a word and these families are WORDS over the whole pool. They are the
# families that reach the rounding and saturation branches, which the pattern SELECTS: a normal,
# a NaN, an infinity, FLT_MAX, the smallest denormal, 2^24 (the last exactly representable float),
# 2^24+1 (the first that is not, so `rne`'s tie rule fires) and -2^24-1.
BITPAT = {
  "bp_norm": 0x3F800000, "bp_nan": 0x7FC00000, "bp_inf": 0x7F800000, "bp_max": 0x7F7FFFFF,
  "bp_tiny": 0x00000001, "bp_2p24": 0x4B800000, "bp_tie": 0x4B800001, "bp_ntie": 0xCB800001,
}
FAMILIES = tuple(WORD) + tuple(BITPAT)
WORD_NAMES = ("w9", "w10", "w11", "w12")


def _f32(bits):
  """`bits` as the f32 it names -- the inverse of `struct.pack('<I', ...)`."""
  return struct.unpack("<f", struct.pack("<I", bits))[0]


def pattern_of(fam):
  """The family's four 32-bit words. `bp_*` families hold every word at their bit pattern."""
  if fam in BITPAT:
    return tuple([BITPAT[fam]] * 4)
  return WORD[fam]


def vals_for(row, fam):
  """`{ALU PARAM name -> value}` for one row at one family, covering EVERY param it reads.

  A `bp_*` family's words are the float bit patterns it names; a `WORD` family's four words go to
  `w9..w12`, its float to `w19` as a REAL, and any other PARAM -- `q5` -- gets the family's
  PRIMARY word, which for `q5` is the whole operand. Anything left over is a hole, and `claims()`
  fails on it rather than defaulting.
  """
  words = pattern_of(fam)
  base = {**dict(zip(WORD_NAMES, words))}
  if "w19" in params_of(row):
    base["w19"] = _f32(FLOAT_OF[fam] if fam in WORD else BITPAT[fam])
  for nm in params_of(row):
    base.setdefault(nm, words[WORD_NAMES.index(nm)] if nm in WORD_NAMES else words[0])
  return base


# ==================================================== the second evaluator, and its licence
def executable(rts):
  """The ALU nodes `ops_python.py:153` refuses: `all_same([u.dtype] + src_dtypes)` false.

  THE REFERENCE INTERPRETER'S OWN STATEMENT OF AN INVARIANT, read as an invariant. `PythonProgram`
  asserts that a binop's two operands already share a width, because in tinygrad they ALWAYS do:
  `ElementwiseMixin._broadcasted` (mixin/elementwise.py:24-32) promotes both operands before the
  op is built, so no rule anywhere in the tree has to insert one. MEASURED: **CPython's own cones
  have ZERO such nodes on all 11 rows**, so this is not a strictness artefact -- it is exactly
  the property whose absence the PROMOTION class is about.
  """
  return [(u.op.name, str(u.dtype), [str(s.dtype) for s in u.src])
          for u in ORACLE.cone(rts)
          if u.op in GroupOp.ALU
          and not (all_same([u.dtype] + [s.dtype for s in u.src])
                   or u.op in {*GroupOp.Comparison, Ops.WHERE, Ops.SHL, Ops.SHR})]


def walk(rts, vals):
  """`exec_alu` over the cone: `PythonProgram` WITHOUT its ALU-dtype assert.

  ## WHY IT EXISTS. MEASURED: the spliced (i.e. the port's) cone on **10 of the 11** PROMOTION
  rows carries between 1 and 67 ALU nodes whose two srcs disagree in width, so
  `PythonProgram.__call__` raises `AssertionError: dtype mismatch on Ops.ADD` and the value
  question cannot be put to the reference interpreter on those rows at all. Reporting "the
  oracle cannot run" for ten of eleven rows would be a SKIP dressed as a verdict.

  ## WHY IT IS NOT THE `tn_bitwise_not` TRAP. The trap is re-implementing the thing being
  checked. Every SEMANTIC here is tinygrad's own function, called and not written:
  `exec_alu` for the ALU (which is `python_alu` + `truncate[u.dtype]`, ops.py:228-234),
  `bitcast` for `Ops.BITCAST`, `truncate`/`dt.const` for `Ops.CAST`, `dt.const` for a weak CONST,
  and the PARAM's own value. What is written here is the TRAVERSAL -- about ten lines, and
  `PythonProgram`'s ALU branch is two of them.

  ## AND IT IS CHECKED, ON THIS RUN, AGAINST THE REFERENCE. `claims()` requires `walk` and
  `PythonProgram` to return the SAME value on the CPython lane for every row and every family --
  11 x {len(FAMILIES)} comparisons, all of them on a cone the reference interpreter accepts. One
  disagreement and the gate fails and the extension is not used. That is the "check your oracle
  before you trust a disagreement it reports" rule, discharged rather than promised, and it is the
  only reason this function is allowed to produce a number.
  """
  env, out = {}, []
  for u in _topo(rts):
    sv = [env[id(s)] for s in u.src]
    if u.op is Ops.CONST:
      v = u.arg
    elif u.op is Ops.PARAM:
      v = vals[u.arg.name]
    elif u.op is Ops.BITCAST:
      v = bitcast(sv[0], u.src[0].dtype, u.dtype)
    elif u.op is Ops.CAST:
      v = truncate.get(u.dtype, lambda dt: dt)(u.dtype.const(sv[0]))
    elif u.op in GroupOp.ALU:
      v = exec_alu(u.op, u.dtype, sv)
    else:
      raise NotImplementedError(f"the walk has no rule for {u.op.name} ({u.dtype})")
    env[id(u)] = v
  for i, r in enumerate(rts):
    # `to_storage_scalar` then `from_storage_scalar` is EXACTLY what `_store` and its read-back
    # do (ops_python.py:39), and it is the identity for every dtype in these cones -- it is only
    # non-trivial for `bfloat16` and the fp8s, and `q5`'s root is `uint8`. Packing the value
    # through `struct` instead -- the first draft -- is wrong for those dtypes and MEASURED:
    # `ValueError: invalid literal for int() with base 10: b'\x00...'`.
    out.append(from_storage_scalar(to_storage_scalar(env[id(r)], r.dtype), r.dtype))
  packed = 0
  for i, w in enumerate(out):
    packed |= (int(w) & 0xFFFFFFFF) << (32 * i)
  return out, packed


# ================================================================ the independent check
# A CLOSED FORM, NOT A SECOND EVALUATOR. `l2i` is documented "long as 2 ints" and these five rows
# have a mathematical meaning neither graph can drift from without one of them being wrong: NEG of
# a 64-bit input is two's-complement negation, and CDIV/CMOD at `dtypes.uint` are unsigned `//`
# and `%`. Nothing here re-implements a decomposition -- these are `int` operators on Python
# ints, the same operators the language has, and `lgq`'s CDIV is TAOCP 4.3.1D's job precisely
# because the answer is the true quotient.
TRUTH = {"lg1": "neg", "lgq": "div", "lgs": "div", "lgr": "mod", "lgt": "mod"}


def truth(row, vals):
  """The row's closed form at these operands, or `None` when there is no division by zero."""
  a = (vals["w9"] | vals["w10"] << 32) & (2**64 - 1)
  b = (vals["w11"] | vals["w12"] << 32) & (2**64 - 1)
  if TRUTH[row] == "neg":
    return (-a) & (2**64 - 1)
  if not b:
    return None
  return (a // b if TRUTH[row] == "div" else a % b) & (2**64 - 1)


# ========================================================================= the instrument
def build(row):
  """Everything the gate asserts about one row, measured on this run.

  THE ORDER IS LOAD-BEARING AND IT IS THE ORDER THE CLAIM IS. `sig_ok` is measured on the RAW
  spliced cone, because that is the census's claim and the census's token carries no dtype. The
  `commit` normalisation runs after it and is applied to BOTH lanes, because it is a property of
  the EVALUATOR and not of either graph. Checking the signature after the commit would be checking
  a different thing, and it would fail for a reason that says nothing about the port.
  """
  ans = answer(row)
  rts = roots_of(ans)
  ptok = PORT_SIG[row].split(",")
  sols, alts, more = witnesses(rts, ptok, PROMOTION[row])
  if sols is None:
    return None
  cone = ORACLE.cone(rts)
  # EVERY WITNESS IS BUILT AND ITS EXECUTABILITY MEASURED, not just the first: a value oracle
  # that reads one alignment and calls it THE port's is the greedy mistake this file's own
  # header records having already made once.
  drop = {id(cone[i]) for i in sols}
  port = splice(rts, drop)
  crts, cn = commit(rts)
  prts, pn = commit(port)
  alt_bad = sorted({len(executable(commit(splice(rts, {id(cone[i]) for i in s}))[0]))
                    for s in ([sols] + alts)})
  ref_prog = Program(crts)
  muts = []
  for kind, s in mutations(row, sols):
    # NO SIGNATURE FILTER HERE, and its absence is the point: a mutant's token sequence is
    # SUPPOSED to differ from the port's, because a graph one cast away from the port's is
    # exactly what "one CAST moved" means. The first draft filtered on `sig_of(g) ==
    # PORT_SIG[row]` and produced 0 of 0 mutants on every row -- a coverage check that can
    # never fire is indistinguishable from one that found nothing, which is the ninth
    # instrument bug wearing a fourth hat.
    gr, _ = commit(splice(rts, {id(cone[i]) for i in s}))
    flips = 0
    for fam in FAMILIES:
      v = vals_for(row, fam)
      try:
        ref = ref_prog.words(v.__getitem__)[1]
        mv = walk(gr, v)[1]
      except (ValueError, TypeError, OverflowError, AssertionError):
        flips += 1
        continue
      flips += ref != mv
    muts.append((kind, flips))
  return {"cpy": Program(crts), "cpy_rts": crts, "port_rts": prts, "drop": len(drop),
          "alts": len(alts), "more": more, "src0": src0_moves(rts, drop), "commit": (cn, pn),
          "sig_ok": sig_of(port) == PORT_SIG[row], "alt_bad": alt_bad,
          "cpy_bad": executable(crts), "port_bad": executable(prts), "muts": muts}


def params_of(row):
  return sorted({u.arg.name for u in ORACLE.cone(roots_of(answer(row))) if u.op is Ops.PARAM})


def mutations(row, sol, cap=8):
  """Every one-cast move of the deletion set: `N-1` (a promotion left in) and `N+1` (one more gone).

  ## WHY THIS IS IN THE GATE AND NOT A NOTE. "A green gate cannot distinguish `not triggered`
  ## from `no such thing`" is this session's ninth instrument bug, and a value oracle that
  ## reports `same` on all 198 cells is exactly the shape that could hide it: if the operand
  ## families never reach a width-sensitive branch, `same` means nothing. A mutation MEASURES
  ## whether they do -- one CAST deleted more or less is a strictly different graph, and if the
  ## 18 families cannot tell it from the port's, they cannot tell the port from CPython either.

  ## THE CAP, AND IT IS A CAP AND NOT A SAMPLE. `lgq`'s cone has 198 `CAST/1` nodes, so its
  ## one-more mutants alone are 129 and each is an 18-family walk over a 2 431-token cone:
  ## MEASURED 4 min 26 s uncapped and 6 min 29 s at `cap=24` on a loaded machine. `cap=8`
  ## takes 16 per big row. `cap` takes the first `cap` of each KIND
  ## and the printed count says how many there were, so a row's coverage claim carries the number
  ## it rests on. A cap is a stated limit; silently sampling is not.
  """
  cone = ORACLE.cone(roots_of(answer(row)))
  casts = [i for i, u in enumerate(cone) if u.op is Ops.CAST]
  keep = [i for i in casts if i not in sol]
  out = [("one-fewer", tuple(sorted(set(sol) - {i}))) for i in sol[:cap]]
  out += [("one-more", tuple(sorted(set(sol) | {i}))) for i in keep[:cap]]
  return [(k, s) for k, s in out if s]


def measure():
  """One pass: every row, every family, both lanes, plus the two cross-checks."""
  res = {}
  for row in PROMOTION:
    b = build(row)
    if b is None:
      return None, f"{row}: CPython's cone does not walk onto the port's pinned row"
    res[row] = b
    for fam in FAMILIES:
      v = vals_for(row, fam)
      # AN OPERAND NEITHER LANE ACCEPTS IS A ROW, NOT A CRASH. MEASURED: `lg5`'s cone carries
      # `MUL f32 [RECIPROCAL(2^32)]` and dtype.py's float->int arm reaches `DType.const`,
      # which does `int(val)` (dtype.py:84) -- so a NaN operand raises `ValueError: cannot
      # convert float NaN to integer` INSIDE `PythonProgram`, before any port value exists. The
      # verdict is `BOTH-RAISE` when the two lanes raise the same way and a FAILURE when only one
      # does, because one lane refusing an operand the other accepts IS a difference in value.
      try:
        ref = b["cpy"].words(v.__getitem__)[1]
        rexc = None
      except (ValueError, TypeError, OverflowError) as e:
        ref, rexc = None, type(e).__name__
      try:
        ext = walk(b["cpy_rts"], v)[1]
        eexc = None
      except (ValueError, TypeError, OverflowError) as e:
        ext, eexc = None, type(e).__name__
      if rexc or eexc:
        if rexc != eexc:
          return None, (f"{row}/{fam}: the two evaluators disagree about the OPERAND: "
                        f"`PythonProgram` raised {rexc}, `walk` raised {eexc}")
        b.setdefault("vals", {})[fam] = (f"BOTH-RAISE:{rexc}", None, None)
        continue
      if ref != ext:
        return None, (f"{row}/{fam}: `walk` says {ext:#018x} and `PythonProgram` says "
                      f"{ref:#018x} on CPython's OWN cone -- the extension is not the reference")
      try:
        port = walk(b["port_rts"], v)[1]
        pexc = None
      except (ValueError, TypeError, OverflowError, AssertionError) as e:
        port, pexc = None, type(e).__name__
      if pexc is not None:
        # THE PORT'S GRAPH IS NOT A VALID TINYGRAPH UOP GRAPH, and the thing that says so is
        # tinygrad's own `dtype.bitcast` (`assert in_dtype.itemsize == out_dtype.itemsize`,
        # dtype.py:302) -- the SAME assertion the reference interpreter's `ops_python.py:153`
        # makes about operand widths. It is a VERDICT, not a skip: the CPython lane evaluated this
        # operand fine, so one side has a graph the other cannot even name.
        b.setdefault("vals", {})[fam] = (f"PORT-REFUSES:{pexc}", ref, None)
        continue
      b.setdefault("vals", {})[fam] = ("same" if ref == port else "DIFFER", ref, port)
  return res, ""


HEADER = """# decomp_value-pins.rows -- GENERATED by `decomp_value-gate.py --refresh`, its ONLY writer.
# One TAB-separated triple per (PROMOTION row, operand family):
# `<row>/<fam>\t<same|DIFFER>\t<cpython 64-bit value as hex>`.
#
# {n} ROWS OVER {r} PROMOTION ROWS x {f} OPERAND FAMILIES, {d} OF THEM `DIFFER`.
#
# Git-resident and BESIDE THE GATE because `gates/artifacts/` is `.gitignore`d, emptied by
# `gatekit` before every run, and unlinked of whatever it staged on a red run.
#
# WHAT A PIN HERE IS NOT. It is not "the port is right" and not "the port is wrong": it is the
# answer to ONE question -- does `ElementwiseMixin._broadcasted`'s missing promotion CAST change
# the VALUE of the answer at these operands -- scoped to the spliced cone this gate builds, which
# the census proves is the port's cone node-for-node and which this gate re-proves on every run.
# The CPython value is pinned too, so a pin that moves is visible as a MOVEMENT rather than as a
# verdict that silently changed its mind.
"""


def pins_text(res):
  d = sum(1 for b in res.values() for v in b["vals"].values() if v[0] == "DIFFER")
  n = sum(len(b["vals"]) for b in res.values())
  lines = [HEADER.format(n=n, r=len(PROMOTION), f=len(FAMILIES), d=d, s=n - d)]
  for row in PROMOTION:
    for fam in FAMILIES:
      verdict, cpy, _ = res[row]["vals"][fam]
      lines.append(f"{row}/{fam}\t{verdict}\t{'n/a' if cpy is None else format(cpy, '#018x')}")
  return "\n".join(lines) + "\n", n, d


def read_pins():
  if not PINS.is_file():
    return None
  d = {}
  for ln in PINS.read_text().splitlines():
    if ln.strip() and not ln.startswith("#"):
      k, v, cpy = ln.split("\t")
      d[k] = (v, cpy)
  return d


def claims(res, pins):
  """Every claim this gate makes, each checked against what THIS RUN measured."""
  ok = True
  LIVE = []
  if pins is None:
    print("  the pins file is absent -- run --refresh")
    return False
  for row in PROMOTION:
    b = res[row]
    if not b["sig_ok"]:
      print(f"  {row}: the spliced cone is NOT the port's pinned row -- the walk is wrong")
      ok = False
    if b["drop"] != PROMOTION[row]:
      print(f"  {row}: spliced out {b['drop']} CASTs, the census declares {PROMOTION[row]}")
      ok = False
    if b["more"] or len(b["alt_bad"]) > 1:
      print(f"  {row}: the deletion set is NOT unique ({len(b['alt_bad'])} distinct "
            f"executability answers over its witnesses) -- this row's verdict is a COUNT's, "
            f"not an identity's")
      ok = False
    if b["src0"] and not all(c for _, c in b["src0"]):
      print(f"  {row}: LIMITATION, not a failure -- {len(b['src0'])} deleted node(s) sat at a "
            f"src[0] whose op is order-sensitive and not commutative "
            f"{sorted({o for o, _ in b['src0']})}. The census's token is `op/nsrc` with src[0] "
            f"read first, so it cannot pin src ORDER; this gate's splice replaces a node IN PLACE "
            f"and never reorders, so the ORDER it evaluates is CPython's. A port that had "
            f"reordered would be invisible here and to the census.")
    live = [m for m in b["muts"] if m[1]]
    print(f"  {row}: one-cast mutants {len(b['muts'])}"
          + (f", LIVE on {len(live)}, up to {max(m[1] for m in live)}/{len(FAMILIES)} "
             f"families moved" if live else
             (" -- NO MUTANT EXISTS: the cone's only CAST/1 IS the promotion, so this row's "
              "coverage rests on the population, not on itself" if not b["muts"] else
              " -- NOT TRIGGERED: one more or one fewer CAST moves no family at these "
              "operands, so this row is robustly value-inert HERE")))
    if live:
      LIVE.append(row)
    if b["cpy_bad"]:
      print(f"  {row}: CPython's OWN cone has {len(b['cpy_bad'])} nodes `PythonProgram` refuses "
            f"({b['cpy_bad'][0]}) -- the invariant this gate measures is not CPython's")
      ok = False
    unfilled = [p for p in params_of(row) if p not in vals_for(row, "Rnd")]
    if unfilled:
      print(f"  {row}: reads PARAMs {unfilled}, which no family fills -- UNEXERCISED")
      ok = False
  # THE HARNESS AGAINST A CLOSED FORM, on the CPython lane, before any disagreement is read.
  for row, kind in TRUTH.items():
    n = 0
    for fam in FAMILIES:
      want = truth(row, vals_for(row, fam))
      if want is None:
        continue
      n += 1
      if res[row]["vals"][fam][1] != want:
        print(f"  {row}/{fam}: CPython's own cone says {res[row]['vals'][fam][1]:#018x}, the "
              f"{kind} closed form says {want:#018x} -- THE HARNESS IS WRONG, and every "
              f"disagreement it reports is void")
        ok = False
    print(f"  {row}: CPython's cone == {kind} on {n} of {len(FAMILIES)} families")
    if not n:
      print(f"  {row}: no family could exercise its closed form")
      ok = False
  # THE EXTENSION AGAINST THE REFERENCE. `measure()` already refused to continue if `walk` and
  # `PythonProgram` ever disagreed; this is where the COUNT of that agreement is printed, because
  # a claim of "the extension is checked" with no number beside it is a claim and not a check.
  # THE COVERAGE CLAIM IS POPULATION-LEVEL, and saying so is the whole point. A value oracle
  # that reports `same` everywhere must be shown to be capable of reporting otherwise SOMEWHERE,
  # or `same` means nothing. It can: `lg1` moves 18 of 18 families on a one-cast mutant. A row
  # that is not itself live is REPORTED with its number rather than failed, because "this row's
  # narrowing is inert at these 18 operand families, and here is the mutant count that says so"
  # is a measurement, and a gate that fails on it teaches nothing.
  print(f"  walk == PythonProgram on {len(PROMOTION)} CPython cones x {len(FAMILIES)} families "
        f"= {len(PROMOTION) * len(FAMILIES)} comparisons, or `measure()` would have refused")
  if not LIVE:
    print("  NO ROW'S OPERAND FAMILIES CAN TELL THE PORT'S GRAPH FROM A ONE-CAST MUTANT -- every "
          "`same` below is indistinguishable from a fixture set that never reaches a "
          "width-sensitive branch. This gate is not trustworthy and says so.")
    return False
  for row in PROMOTION:
    for fam in FAMILIES:
      k = f"{row}/{fam}"
      want = pins.get(k)
      if want is None:
        print(f"  {k} is not pinned")
        ok = False
      elif want != (res[row]["vals"][fam][0],
                    'n/a' if res[row]["vals"][fam][1] is None
                    else format(res[row]["vals"][fam][1], "#018x")):
        print(f"  {k} is {res[row]['vals'][fam]}, the pin says {want}")
        ok = False
  return ok


def refresh() -> int:
  res, why = measure()
  if res is None:
    print(f"--refresh: {why}", file=sys.stderr)
    return 1
  text, n, d = pins_text(res)
  PINS.write_text(text)
  print(f"--refresh: {PINS.name} rewritten -- {n} rows, {d} DIFFER, {n - d} same")
  return 0


if __name__ == "__main__":
  if "--refresh" in sys.argv:
    sys.exit(refresh())
  res, why = measure()
  if res is None:
    print(f"decomp_value-gate: REFUSED, NOT A VERDICT: {why}", file=sys.stderr)
    sys.exit(REFUSED)
  diff = sorted({r for r in PROMOTION if any(v[0] == "DIFFER" for v in res[r]["vals"].values())})
  refu = sorted({r for r in PROMOTION if any(v[0].startswith("PORT-REFUSES") for v in res[r]["vals"].values())})
  both = sorted({r for r in PROMOTION if any(v[0].startswith("BOTH-RAISE") for v in res[r]["vals"].values())})
  code = PASS if claims(res, read_pins()) else FAIL
  dead = sorted(r for r in PROMOTION if res[r]["port_bad"])
  print(f"decomp_value-gate: {VERDICT[code]} -- {len(PROMOTION)} PROMOTION rows x "
        f"{len(FAMILIES)} operand families = {len(PROMOTION) * len(FAMILIES)} value comparisons; "
        f"{sum(1 for r in PROMOTION for v in res[r]['vals'].values() if v[0] == 'DIFFER')} DIFFER"
        + (f", on rows {diff}" if diff else ", on no row"))
  print(f"  SAME value at every evaluable operand: "
        f"{sorted({r for r in PROMOTION if all(v[0] == 'same' for v in res[r]['vals'].values())})}")
  print(f"  NOT EVALUABLE, the port's graph is not a tinygrad UOp graph: "
        f"{len(refu)} of {len(PROMOTION)} rows ({', '.join(refu) or 'none'})")
  print(f"  OPERAND neither lane accepts: {len(both)} rows ({', '.join(both) or 'none'})")
  print(f"  NOT EXECUTABLE by PythonProgram because of a missing promotion: "
        f"{len(dead)} of {len(PROMOTION)} rows ({', '.join(dead)})")
  for row in PROMOTION:
    b = res[row]
    print(f"  {row}: splice {b['drop']} CAST -> the port's pinned cone ({b['sig_ok']}), "
          f"{b['alts']} alternative witness(es), {len(b['src0'])} dropped-at-src[0] "
          f"(all commutative: {all(c for _, c in b['src0'])}), "
          f"PythonProgram refuses {len(b['port_bad'])} of its nodes")
  sys.exit(code)
