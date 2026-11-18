import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/mixin/movement.bend"

EDITS = [
  # ---- `f_` (21 lines) -- the PREPEND BUG and the MEASUREMENT stay; the prose goes.
  (209, 229, """# `f_ = [smax(1, ceildiv(o*s - d, i)) for o,s,i,d in zip(o_,s_,i_,d_)]` (movement.py:605),
# with the SIGN of `o*s - d` folded into the walk rather than carried as a fifth parallel list:
# `mx_ofd` is a `Data` arithmetic helper, not a closure, so it is a CALL and a call cannot be a
# `match` scrutinee -- which is why the two reads of `e` are resolved by `mx_fs`.
#
# THE ACCUMULATOR IS APPENDED TO AT THE TAIL: `List.append(a, A, acc, [x])`. This def used to
# PREPEND on the reasoning that a walk which descends and accumulates on the way back up must cons
# at the head "to build forward order". That is the head/tail swap `agent-core.md` records:
# `List.append` is `xs ++ ys`, so prepending builds the list BACKWARDS, and the comment was the
# rationalisation rather than the defence. `mx_pool_out.go` and `mx_pool_kid.go`, twelve lines
# away, both write `acc, [x]`.
#
# `f_` is not cosmetic: it is an input to `mx_pool_kid` and `mx_pool_rep` ZIPPED against `i_`, so
# a reversed `f_` makes every per-axis repeat count wrong rather than merely reordered. MEASURED:
# `mx_pool_f([3,5],[1,2],[2,3],[1,1])` answered `3,1` where CPython answers `1,3`, and
# `mx_pool_f([9,2,7],[1,3,1],[4,5,2],[1,1,1])` answered `3,1,2` where CPython answers `2,1,3`.
# all six `f_*` gate rows are blind: every one of them feeds an ALL-EQUAL shape list, and
# reversing a constant list is the identity, so the fix left all 70 rows byte-identical. TWO
# READS OF `d` are resolved by a PARAMETER rather than by `+`, which is the general form of "a
# match may not scrutinise a call"."""),

  # ---- THE TWO WALKS (22 lines) -- the THREE SPELLINGS and their MEASUREMENT stay.
  (298, 319, """# THE TWO WALKS that make `[nn + i*2 + 1 for i in range(ni)]` and `[nn + i*2 for i in
# range(ni)]` (movement.py:616, the MIDDLE and LAST thirds), each with its own `Nat` countdown.
# the one-walk version was tried and refused: carrying both lists in one `Data` record needs
# `case 1n+q:` to pass `q` to the self-call AND read `k` for the two indices AND read `acc` for
# both prepends, and the checker then reports `expected : q / observed : q (consumed more than
# once)` AT THE PATTERN -- an error that sends you looking at `1n+q:` rather than at the body.
# `+q` makes it worse (a reusable binder stops counting as the decreasing subterm) and a `let` is
# affine. Two walks cost eight lines and each is the shape `mo_range.go` already has.
#
# the INDEX is a parameter, and that is the only spelling that checks. Three shapes were measured
# on this walk and two fail:
#   `List.append(..., [U32.from_nat(k)], g(p, nn))`                        REFUSED
#   `List.append(..., [U32.add(nn, 2*U32.from_nat(p))], g(p, nn))`        REFUSED
#   `List.append(..., [ix], g(p, nn, U32.add(ix, 1)))`             ALL PROOFS CHECK
# Both refusals report `expected : p / observed : p (consumed more than once)` AT THE `1n+p:`
# PATTERN, which reads like a pattern-syntax bug and is not one: the arm reads the SPENT and
# every spelling that needs the current index must recover it -- from `p` (two uses) or from `k`
# (spent). Threading the index as its own `U32` gives the arm nothing to recover, and `+ix` is
# needed because the value and the self-call both read it in one expression. The fuel occupies
# the FIRST slot because the decrease check reads the arguments left to right and each is passed
# unchanged until one shrinks."""),

  # ---- SECTION C (22 lines) -- the UPSTREAM SPELLING and the two halves that need
  # `uop/symbolic.bend` stay.
  (353, 374, """# SECTION C -- `marg` (ops.py:814) and `as_shape` (ops.py:812). THIS IS THE PART THAT CLOSES
# W1 AND W2, and the header states the measurement that makes it possible. The short version
# again, because the whole section rests on it:
#
#   `ssimplify(x)` is `x` when `x` is a python int, and `x` when `x.op` is CONST.
#   A movement op's shape arg is built from python ints (ops.py:106), so for a CONCRETE shape
#   `as_shape` is an UNWRAP and `marg` needs no rewrite engine.
#
# `as_shape` (ops.py:812-815), spelled:
#     if self.op is Ops.CONST: return (self.val,)
#     if self.op is not Ops.STACK: return (ssimplify(self),)
#     return tuple(s.val if s.op is Ops.CONST else ssimplify(s) for s in self.src)
#
# the concrete arm is all three of those, and the fold's refusal is exactly the
# `(ssimplify(self),)` and the `ssimplify(s)` halves -- the two that need `uop/symbolic.bend`.
# `mxm_as_shape` below walks a STACK of CONSTs and returns their values; a STACK element that is
# NOT a CONST answers `None{}`, and that is the symbolic wall, named rather than guessed.
# `self.val` for a CONST (ops.py:279) -- the `CInt` case, and the other three `Const`
# constructors cannot be a shape dim because ops.py:109 raises `shape must be int`. `CInt` holds
# an `H.I64` and `H.lo32` is exact on every value a shape dim takes."""),

  # ---- `shape_to_shape_arg` (28 lines) -- the CORPUS DISAGREEMENT is the fact (a BUG THAT WAS
  # FOUND) and the UPSTREAM SPELLING stays.
  (860, 887, """# `shape_to_shape_arg` (ops.py:108-112) FOR ANY LENGTH, WHICH IS THE PIECE UPSTREAM's `_mop`
# USES AND THE PORT WAS MISSING:
#
#   def shape_to_shape_arg(arg:tuple[sint, ...]) -> UOp:
#     src = tuple(x if isinstance(x, UOp) else UOp.const(x) for x in arg)
#     for x in src:
#
# SO A LENGTH-1 SHAPE IS A BARE CONST AND A LONGER ONE IS A `STACK` NODE -- AND THE PORT's
# `G.stk4` HARD-CODES THE LENGTH-4 CASE AND THE PERMUTE's ORDER IS ARBITRARY-LENGTH, SO THE
# PERMUTE HAD NOWHERE TO PUT ITS ORDER.
#
# AND THIS IS WHY THE PORT's PERMUTE CARRIED ITS ORDER IN `arg` AND NOT IN `src[1]` -- AND THAT IS
# WHY THE CORPUS DISAGREED: UPSTREAM's PERMUTE IS `(x, STACK(consts))` WITH `arg=None`, AND THE
# PORT's WAS `(x)` WITH `arg=ATuple{ys}` -- AND THE SHAPE IS THE DIFFERENCE, AND THE OP SET IS THE
# SAME (`OPS REACHED: py=6 bend=6`).
# THE RECURSIVE CALL IS READ LEFT TO RIGHT AND EACH PASSED ARGUMENT MUST BE SMALLER THAN THE
# MATCHED EXPRESSION ("a call smaller than ...") -- SO THE CONST INTERNING IS IN A `push` DEF
# (WHICH IS A SMALLER EXPRESSION THAN THE MATCH) AND THE RECURSION CARRIES THE TAIL AND THE NEW
# STATE -- EXACTLY THE IDIOM THE PORT ALREADY USES AT `tn_sarg.acc` (`tensor.bend:1566`).
#
# AND THE STATE IS A `Data` RECORD BECAUSE THE ARENA AND THE INDEX LIST AND THE TAIL ALL HAVE TO
# CROSS THE RECURSION AND THREE PARAMETERS WOULD NOT BE READ LEFT TO RIGHT THE WAY BEND READS THEM
# -- ONE RECORD, ONE ARGUMENT."""),

  # ---- THE MERGE POINT (17 lines) -- the MUTUAL-RECURSION refusal and the fold-cost fact stay.
  (1220, 1236, """# THE MERGE POINT. The shape of ANY node: `mxm_shape` for the six movement ops that
# `uop/fold.bend:1670 symbol=sym_dim.end` defers, and the fold for everything else. Every wrapper's
# identity test goes through here, and it is ONE def rather than six call sites because the six
# would each have to re-derive the op test and each of them is a chance to disagree about which ops
# are movement ops.
#
# the movement half, and it is one self-recursive DEF with a two-scrutinee match. the THREE-DEF
# SHAPE (`go` -> `at` -> `of`, each calling the one below) IS A MUTUAL RECURSION and Bend refuses
# it in every declaration order, with the misleading "a filled definition (an unfilled law is a
# dead claim)" naming the LAST def in the cycle. The working shape is ONE def matching `fuel mv`
# together, which is legal precisely because the `False` arm is a CALL and not a recursion -- so
# `mxw_fold_shape` is NOT evaluated on a movement node, which matters because it runs a whole
# Kahn fold and doing it wastefully on every movement node would cost a fold per wrapper step.
# `mv` is a parameter and not a `match` inside the arm because `mxw_mv(O.Arena.op(...))` is a CALL
# and a call cannot be a scrutinee."""),
]

apply(F, EDITS)
