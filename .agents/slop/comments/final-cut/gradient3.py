import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/mixin/gradient.bend"

EDITS = [
  # rule 15 -- the FIRST paragraph is the fact; the TODO's third sentence repeats it.
  (676, 687, """# --- 15. CONTIGUOUS_BACKWARD -- gradient.py:82. `(ctx.contiguous(),)`
#
# `contiguous` (elementwise.py:59) is a real body, not an alias: it returns `self` for a
# weak dtype, for a STAGE, for `device is None` or for `has_buffer_identity()`, and otherwise
# `uop.alu(Ops.STAGE)`. `has_buffer_identity` (ops.py:943) walks BASE and is a fold read plus
# a walk.
# TODO(p3) mixin/gradient.py:82  symbol=pm_gradient  -- ctx.contiguous -- needs `has_buffer_identity`
#   (ops.py:943), a BASE walk with an `after_ok` argument that fold.bend does not carry.
#   The rule's OBSERVABLE effect for a non-weak, device-bearing, non-identity node is
#   exactly `alu(Ops.STAGE)`, and `stage_*` covers that node; the four early returns are
#   what is missing."""),

  # rule 17 RESHAPE -- a PYTHON BUG that was measured. KEEP IT WHOLE -- it is load-bearing.
  (695, 706, """# --- 17. RESHAPE -- gradient.py:85. `(ctx.reshape(ret.src[0].shape), None)`
#
# two slots for a one-SRC node, and that is a real python bug, measured: `pm_gradient` is a
# per-OP table with no arity check, so this rule answers 2 gradients for a node whose `src` has
# length 1, and `compute_gradient`'s own assert (gradient.py:128 `assert len(lgrads) ==
# len(t0.src)`) FIRES. Verified: `pm_gradient.rewrite(RESHAPE)` returns 2 for a 1-src RESHAPE
# and `compute_gradient` on the same node raises `AssertionError: got 2 gradient, expected 1`.
# The port REPRODUCES the arity, because reproducing it is what lets the gate row
# `reshape_arity` be 2 and say so.
#
# `ctx.reshape(shape)` is `_mop(Ops.RESHAPE, arg=shape)` (movement.py:164), and the shape is
# `ret.src[0].shape` -- a FOLD read, plus `prod` for the `-1` arm."""),

  # rule 19 PAD -- the TODO's LAST SENTENCE is a substrate limit and stays.
  (715, 726, """# --- 19. PAD -- gradient.py:87.
#   (ctx.shrink(tuple([(p[0], s+p[0]) for s,p in zip(ret.src[0].shape, ret.marg)])), None, None)
#
# THREE slots: a PAD has srcs (value, lo_shape, hi_shape) -- measured, a 1-D pad has
# `len(src) == 3`. `ret.marg` is `zip(src[1].as_shape, src[2].as_shape)` (ops.py:817), so both
# margins are CONST nodes read back as shapes, and `s + p[0]` is SINT ADDITION on the derived
# shape.
# TODO(p3) mixin/gradient.py:87  PAD -- `ret.marg` is `zip(src[1].as_shape,
#   src[2].as_shape)` and `s+p[0]` is `Sint` arithmetic. ops.bend's `Sint` is
#   `SI{i64} | SU{u32}` with an equality (`F.eq_sint`) but NO addition and NO `as_shape`
#   (reading a CONST node back out as a shape is `ops.py:809`). Phase P3 owns both."""),

  # rule 24 COPY -- a MEASURED PYTHON FAILURE. KEEP IT.
  (793, 807, """# --- 24. COPY -- gradient.py:90.
#   (ctx.copy_to_device(ret.src[0].device),) + (None,)*(len(ret.src)-1)
#
# `copy_to_device` (ops.py:738) raises for a DISK device, asserts `arg is None or
# isinstance(self.device, tuple)`, wraps in an MSELECT when `arg` is set, and RAISES for a weak
# dtype. `ret.src[0].device` is a FOLD read.
#
# It also RAISES in the gate: measured, `pm_gradient.rewrite` on a 1-src COPY raises
# `TypeError: 'NoneType' object is not iterable`, because `copy_to_device` returns a UOp whose
# `*` is not what the tuple concat expects at that arity. So this rule is a measured Python
# failure, and the port records it rather than reproducing a crash.
# TODO(p3) mixin/gradient.py:90  symbol=pm_gradient  -- COPY -- `copy_to_device` (ops.py:738) needs a device
#   fold plus the DISK and weak-dtype refusals; and the rule RAISES at 1 src in
#   Python (measured, `t_copy_raises`)."""),

  # rule 28 -- the FIRST paragraph is the fact.
  (841, 852, """# --- 28. AFTER, ordering-only -- gradient.py:96-97.
#   lambda ctx, dest, t: (ctx, None) if t.buf_uop is not dest.buf_uop else None
#
# This is a rule that MATCHES the pattern and then RETURNS `None`, so the scan continues -- a
# fourth state beyond `GSkip`/`GFired` from the pattern's side, and it is why `GSkip` means "no
# answer from this def" rather than "this pattern did not match". `t.buf_uop` is ops.py:911, a
# walk to the BUFFER/ALLOC/PARAM (or STAGE/MSTACK) underneath.
# TODO(p3) mixin/gradient.py:96  symbol=pm_gradient  -- ordering-only AFTER -- `buf_uop` (ops.py:911) walks
#   through `base` and stops at BUFFER/ALLOC/PARAM/STAGE/MSTACK, and `base` needs the
#   fold plus a second walk. fold.bend carries `fold.base` but not `buf_uop`."""),

  # the flag pass -- the FIRST paragraph is the fact, the SECOND is a substrate rule.
  (1136, 1145, """# THE FLAG IS THE HEAD, not `flags[i]`. The two lists are in LOCKSTEP, so walking them
# together makes the position implicit -- and that is the whole reason a `Data` pair beats a
# list of pairs here (notes, T-6: a tuple field must be `Data`, so a
# `List<&2, (U32, Bool)>` is refused outright).
#
# TWO SCRUTINEES because the two lists shrink TOGETHER and a self-call must shrink an argument
# (notes, position 612), and the parameter order must be the scrutinee order -- MEASURED here:
# `match ns fs:` over `(fs, ns, ...)` is refused with "a match on a parameter or field (this
# name is a def or a consumed binder)", which names the SECOND scrutinee and not the mismatch."""),

  # the flag pass, the OTHER block -- the SECOND paragraph is the substrate rule and the fact.
  (1183, 1191, """# the flag pass. one forward pass over the toposort, and the flag is computed on the
# evaluated before `dw_push` branches, which is notes rule 5 ("BEND IS STRICT: AN argument is
# evaluated before the callee branches") and is what makes the one-line arm legal.
#
# THE ACCUMULATOR IS THE LAST PARAMETER, and that is not taste. `dw_flags(ar, targets,
# dw_push(...), t)` is REFUSED with "expected : a decreasing self-call (arguments are read left
# to right: each passed unchanged until one shrinks)": a third argument that CHANGED reads as
# consumed, and the list only shrinks in the fourth."""),

  # THE ACCUMULATE -- the SECOND paragraph is the substrate rule and it is a MEASUREMENT.
  (1384, 1394, """# `if k in grads and grads[k].op is not Ops.NOOP: grads[k] = grads[k] + v
#  else: grads[k] = v` -- gradient.py:134-139. THE ACCUMULATE IS THE `Some{}` ARM and it is the
# only reason the fixture is a DAG: a node with two parents is written twice, and
# `oracle_dag_grad_a` answers `root=ADD/2` where a fresh insert would answer the MUL.
#
# * the order of this chain is not cosmetic. * `done -> grow -> noop -> add -> put` is the only
# order that compiles: a `case Some{sl}:` binder cannot call a def declared LATER in the file.
# MEASURED in six lines -- a `put.of` whose `Some{sl}` arm calls a following `add` is refused
# with "expected : a filled definition (an unfilled law is a dead claim: live code cannot use
# it)", which names the CALLER'S condition and not a recursion."""),

  # pm_gradient.rewrite -- the DIVERGENCE paragraph is a DIFFERENCE and stays whole.
  (1459, 1470, """# `pm_gradient.rewrite(t0, ctx=grads[t0])` -- gradient.py:126. THE ARENA IS HANDED ON
# TWICE: the rules GROW it and the `GRes` carries the grown one, which is the only way a rule
# that mints three nodes can be followed by one that reads them.
#
# * the one place the port diverges from upstream, and it is named. * gradient.py:127 is `if
# lgrads is None: raise RuntimeError(...)`. The port CANNOT raise, so a node no rule claims
# STOPS the walk: `cg_step` is not re-entered and the grads built so far stand. "No answer
# after this point" is the honest reading of both, and the alternative -- inserting nothing and
# carrying on -- would be a DIFFERENT function that silently under-counts. The fixtures below
# claim every node they walk, so no row here depends on which of the two it is; the divergence
# is recorded so nobody reads a short `walk_grads_n` as "the walk ran"."""),

  # the reversal -- the LAST SENTENCE is a COUNTERFACTUAL with a dead oracle; keep the fact.
  (1494, 1500, """# `for t0 in reversed(walk)` -- gradient.py:119. The REVERSAL IS NOT AN OPTIMISATION: it is
# what makes `gput`'s append-and-replace table behave like a dict, because upstream writes each
# key once per parent and the LAST write must be the one a later read sees (notes, T-6).
# `grads` is SEEDED AT THE ROOT -- gradient.py:118 -- and the root is the LAST node the
# toposort completes, so `reversed` reaches it first and a walk in forward order would skip
# every other node (`oracle_fwdwalk_n` is CPython's own number for the counterfactual, though
# the committed oracle dies before printing it)."""),
]

apply(F, EDITS)
