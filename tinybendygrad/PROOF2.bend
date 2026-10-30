# PROOF2.bend -- the ALU/dtype half of the proof set.
#
# PROOF.bend holds the shape half (LAWS.bend sections I, II, III, VI, VII and
# VIII -- sixteen laws); this file holds the elementwise-decomposition half (IV)
# and the dtype half (V) -- eighteen laws. LAWS/PROOF-ALL.bend imports both and
# is the aggregate gate: 34 of 34 discharged, `ALL PROOFS CHECK`.
#
# ALL EIGHTEEN ARE PROVEN -- nine in section IV and nine in section V, every one
# `{==}` -- and the reason the dtype half went green is that the dtype fold is
# total. `Sp.dtype` reads at most one operand per arm, so no arm
# has to case-split on another node's result -- the shape half's one remaining
# obstacle does not arise here. See PROOF.bend for the full statement of that
# obstacle and of the two fuel defects it replaced.
#
# THE BOOK IS GREEN, AND THIS FILE IS NOT THE REASON IT IS NOT: `./bin/bend
# tinybendygrad/PROOF2.bend --check-only` reports SIXTEEN TODOs, and every one
# of the sixteen is a law of the OTHER half -- this file's own eighteen are
# proved, and the aggregate's thirty-four are proved. A TODO count is a
# property of the BOOK, and a book's population is its import closure
# (`references/bend/bend2/bend.ts:3859` counts a law open iff its body is still
# empty, and a body is set by a `def` of that name anywhere in the closure), so
# a HALF reports the other half's laws as open. `LAWS/PROOF-ALL.bend` is the
# book whose closure holds all thirty-four, and it is the one command that must
# pass. The census that says so is `.agents/slop/laws17/laws.py`: it reads
# `PROOF2.bend` 16 open / 18 filled, `PROOF.bend` 18 open / 16 filled,
# `PROOF-ALL.bend` 0 open / 34 filled.
#
# THE SIXTEEN CANNOT BE DISCHARGED HERE, AND THE REASON IS A CONSTRAINT, NOT A
# BACKLOG. Bend discharges a law by a def of that name, and allows ONE such def
# per book: `bend.ts:2437` takes the law's own qualified name only while the
# law has no body (`law ? q : parse_fresh`), so a second `def L.<name>` for a
# law another file has proved is refused with `expected : a fresh name (L is
# an import's alias)`. Moving a proof here means deleting it there -- and the
# shape group's ten laws and this half's neighbour's six share 22 of their 27
# helper defs, so a move duplicates them, which is the regression `98721d492`
# repaired.
#
# AND MAKING THIS FILE COMPLETE IS REFUSED BY A PINNED GATE. A second complete
# book in the proof population joins `LAWS/PROOF-ALL.bend` in
# `gates/verdict-lane-gate.py`'s PLANT-TARGETED-KERNEL disagreement set,
# whose `want_disagree` is exactly `{LAWS/alu.bend, LAWS/PROOF-ALL.bend}`.
# Measured: importing `./PROOF.bend` here -- which does make this file complete
# -- gives PLANT-TARGETED-KERNEL and PLANT-BLANKET-KERNEL `NOT AS EXPECTED`,
# the disagree set growing from 2 to 3 of 7 files. The population holds
# exactly three complete files -- `LAWS/alu.bend`, `LAWS/spec.bend` and
# `LAWS/PROOF-ALL.bend` -- and a fourth breaks the anchor.
#
# SO THE TWO HALVES STAY TWO HALVES, and this file's sixteen TODOs are the
# boundary between them, not work.

import Base
import ./LAWS.bend as L

# ---------------------------------------------------------------------------
# IV. tinyspec.tex "Decomposed elementwise ops" (lines 188-208): each op is
# DEFINED in terms of the primitives above it, so each is reflexive. No depth
# binder, then or now: none of these laws mentions shape_of, dtype_of or
# numel_of.
# ---------------------------------------------------------------------------

# tinyspec.tex:192  Neg = Mul(A, -1)
def L.neg_is_mul_by_minus_one(a):
  {==}

# tinyspec.tex:193  Sub = Add(A, Neg(B))
def L.sub_is_add_of_neg(a, b):
  {==}

# tinyspec.tex:194  Div = Mul(A, Recip(B))
def L.div_is_mul_by_recip(a, b):
  {==}

# tinyspec.tex:195  CmpGt = CmpLt(B, A)
def L.cmp_gt_is_cmp_lt_swapped(a, b):
  {==}

# tinyspec.tex:196  CmpGe = CmpNe(CmpLt(A, B), 1)
def L.cmp_ge_is_ne_of_cmp_lt(a, b):
  {==}

# tinyspec.tex:197  CmpLe = CmpNe(CmpLt(B, A), 1)
def L.cmp_le_is_ne_of_cmp_lt_swapped(a, b):
  {==}

# tinyspec.tex:198  CmpEq = CmpNe(CmpNe(A, B), 1)
def L.cmp_eq_is_double_neg(a, b):
  {==}

# tinyspec.tex:199  Not = CmpNe(A, 1)
def L.not_is_ne_one(a):
  {==}

# tinyspec.tex:205  Mulacc = Add(Mul(A, B), C)
def L.mulacc_is_add_of_mul(a, b, c):
  {==}

# ---------------------------------------------------------------------------
# V. tinyspec.tex "Derived Properties" dtype column: the arms of Sp.dtype that
# do not simply read src[0].
#
# All eight were OPEN and all eight are REFLEXIVE now. Before, the fold matched
# on a fuel it had computed as `2*depth+1` and its `case 2n+p:` arm was dead
# behind `case 1n+p:`, so every one of these compared None with Some{bool} or
# with None. The fold now reaches its own arm on the first call.
# ---------------------------------------------------------------------------

# tinyspec.tex:269  CmpLt, CmpNe: bool
def L.comparison_is_bool(a, b):
  {==}

def L.comparison_ne_is_bool(a, b):
  {==}

# tinyspec.tex:271  Where: src[1].dtype. The arm is `Sp.dtype(b)`, so both
# sides are literally the same term.
def L.where_takes_the_second_operand_dtype(p, a, b):
  {==}

# tinyspec.tex:274  Store: void. "Output is void" is the arm `None{}`.
def L.store_is_void(buf, val, gate):
  {==}

# tinyspec.tex "A value Call is void" -- the arm is `None{}` again.
def L.call_is_void(body, args):
  {==}

# tinyspec.tex:275  Range: index
def L.range_is_index(bound):
  {==}

# tinyspec.tex "Binary: has dtype uint8"
def L.binary_is_uint8(size):
  {==}

# The marker ops are "identity on data": the arm is a tail call on the operand,
# so the subject and the premise normalise to one term.
def L.detach_preserves_dtype(a):
  {==}

def L.detach_preserves_numel(a):
  {==}
