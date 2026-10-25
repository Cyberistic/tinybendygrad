"""ORACLE -- upstream's `compute_gradient` ON A PERMUTE FIXTURE, and upstream's
`pm_gradient` rule table ON THE SAME PERMUTE NODE.

WHAT THIS SETTLES.  The previous unit wrote:

    "`gr_21` (PERMUTE) is not landable as its comment claims. ... Measured: on a
     scalar ctx, marg `(1,0)` -> `IndexError`, `(0,)` -> `RuntimeError`, and every
     fixture in the file is scalar, so there is no CPython answer to gate it against."

Two claims.  (A) upstream raises on a scalar ctx -- TRUE, and a raise on a scalar ctx
is a CORRECT ANSWER, not the absence of an answer.  (B) "there is no CPython answer to
gate it against" -- this follows only if every reachable ctx is scalar, and THIS FILE
IS THE REFUTATION: a 2-D ctx is reachable with NO RESHAPE, because upstream's `_shape`
for a STACK is `(len(self.src),) + self.src[0].shape` (ops.py:352-354), so a STACK of
two 1-D nodes is 2-D.

MEASURED, in `probe.py` (same directory):
    STACK(x, y)                     op=STACK  nsrc=2 shape=(2, 2)   ndim=2
    PERMUTE(st, (1,0))              op=PERMUTE nsrc=1 marg=(1, 0)    shape=(2, 2)
    ctx = STACK(p, q)               shape=(2, 2)  ndim=2
    ctx.permute((1,0))              op=PERMUTE nsrc=1 arg=(1, 0)    shape=(2, 2)
    x (1-D).permute(1,0)            RAISED IndexError: dim=1 out of range [-1, 0]

THE FIXTURES.  TWO of them, and the second is the CONTROL for the first:

  * `P2` -- the 2-D PERMUTE, order `(1, 0)`, a NON-IDENTITY permutation.  The target
    is the 2-D node `a` ITSELF, so the walk is EXACTLY `[per]` (upstream's
    `_deepwalk` puts a node in the path only if one of its SRCS is on the path or is a
    TARGET -- gradient.py:112 -- so the target itself is NOT in the walk, and the
    target's own rule is never needed).  **⇒ THE WHOLE BACKWARD GRAPH IS ONE RULE
    DEEP, AND IT IS `gr_21` ALONE.**
  * `P1` -- the 1-D PERMUTE, order `(0,)`, the IDENTITY permutation.  This is the arm
    where upstream's `permute()` returns `ctx` ITSELF (movement.py:231's
    `... if order_arg != tuple(range(self.ndim)) else self`), and it is the arm a
    hand-built graph can reach and upstream's own `permute()` never builds.

THE TOKEN SPELLING is the port's own `bw` format -- `OP/nsrc` plus the IDENT, then the
SORTED tokens of the srcs -- copied from `.agents/slop/backward2/oracle-gs.py`, so the
two sides' signatures are comparable as GRAPHS and not as counts.

Run:
    LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward4/oracle-pm.py
"""
import struct
import sys

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import compute_gradient, pm_gradient, _deepwalk


def f32bits(v) -> int:
  return struct.unpack('<I', struct.pack('<f', float(v)))[0]


def tok(u) -> str:
  """THE CLASS TOKEN: `OP/nsrc`."""
  return "%s/%d" % (u.op.name, len(u.src))


def ident(u) -> str:
  """WHAT TELLS TWO NODES OF THE SAME CLASS APART.  A CONST's VALUE and a BUFFER's
  PARAM SLOT.  THE SAME RULE as the port's `bw_ident.of` (gradient.bend:2622).

  *** THE INT CONST IS SPELLED IN THE PORT'S I64 FORM, AND THAT IS NOT A FUDGE: it is
  the corpus's OWN spelling. ***  `.agents/slop/graphcmp.py:388` `i64(x)` is
  `f"{x >> 32}:{x & 0xFFFFFFFF}"` -- "exactly `H.i64_text` = `i64_show(hi32, lo32)`"
  (helpers.bend:1709-1712) -- and `graphcmp.py:459` `konst()` NORMALISES CPython's int
  to it, saying so: "CPython's int is normalised to the port's I64 form so
  `UOp.const(4)` is `l0:4` on BOTH sides rather than `i4` here and `l0:4` there".
  **⇒ THE IDENT COLUMN IS A SPELLING LAYER, AND THE CORPUS ALREADY SPELLS IT THIS
  WAY.  THE PRIOR ART'S `ident()` (`.agents/slop/backward2/oracle-gs.py`) PRINTED
  `@i%d` -- A RAW PYTHON DECIMAL -- AND ITS FIXTURE HAD NO INT CONST, SO THE
  DIFFERENCE WAS NEVER VISIBLE.  IT IS VISIBLE NOW, AND IT IS NOT ABOUT `gr_21`.**
  """
  if u.op is Ops.CONST:
    v = u.arg
    if isinstance(v, bool): return "@b%d" % int(v)
    if isinstance(v, float): return "@f%d" % f32bits(v)
    if isinstance(v, int):
      u64 = v & 0xFFFFFFFFFFFFFFFF
      return "@i%d:%d" % (u64 >> 32, u64 & 0xFFFFFFFF)
    return ""
  if u.op in (Ops.BUFFER, Ops.ALLOC, Ops.PARAM) and getattr(u.arg, "slot", None) is not None:
    return "@s%d" % u.arg.slot
  return ""


def btok(u) -> str:
  return "%s%s" % (tok(u), ident(u))


def local_token(u) -> str:
  return "%s [%s]" % (btok(u), " ".join(sorted(btok(s) for s in u.src)))


def nodes_of(u):
  return list(u.toposort(enter_calls=True))


def bw_sig(roots):
  seen = {}
  for r in roots:
    for n in nodes_of(r):
      seen[id(n)] = n
  return " ".join(sorted(local_token(n) for n in seen.values()))


def bw_distinct(roots):
  seen = {}
  for r in roots:
    for n in nodes_of(r):
      seen[id(n)] = n
  return len({local_token(n) for n in seen.values()})


def leaf(slot, size):
  """A BUFFER whose shape src is a STACK of CONSTs -- a STATIC shape.

  WHY THE STACK: upstream's `_shape` for a BUFFER reads `self.src[0].as_shape`
  (ops.py:359) and ASSERTS `len(self.src[0].as_shape) <= 1`, so a BUFFER is at most
  1-D, and a SRC-LESS BUFFER raises `IndexError`.  `as_shape` of a STACK of CONSTs is
  the CONST values (ops.py:789), so `STACK(CONST 2)` is the shape `(2,)`.
  """
  return UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=size),)),),
             arg=ParamArg(slot, dtypes.float32))


def fixture_p2():
  """THE 3-D PERMUTE FIXTURE.

      l0 = BUFFER(0) shape (2,)   s01 = STACK(l0, l1)      shape (2, 2)
      l1 = BUFFER(1) shape (2,)   a   = STACK(s01, l2)     shape (2, 2, 2)  <- THE TARGET
      l2 = BUFFER(2) shape (2,)   per = PERMUTE(a, (1,2,0))                <- THE ROOT
      m0 = BUFFER(3) shape (2,)   n01 = STACK(m0, m1)      shape (2, 2)
      m1 = BUFFER(4) shape (2,)   ctx = STACK(n01, m2)     shape (2, 2, 2)  <- THE ROOT GRAD
      m2 = BUFFER(5) shape (2,)

  WHY IT IS 3-D AND NOT 2-D, AND IT IS NOT A TASTE: **A 2-ELEMENT PERMUTATION IS AN
  INVOLUTION, SO ITS ARGSORT IS ITSELF.**  `argsort((1,0))` is `(1,0)`, so on a 2-D
  fixture the rule's ORDER would read the same whether the rule ARGSORTED or merely
  copied the order -- and a row that cannot go red is a label.  With the order
  `(1, 2, 0)` the argsort is `(2, 0, 1)`, and the row tells them apart.

  WHY EVERY DIMENSION IS 2: `per`'s shape is `a`'s shape PERMUTED, and `ctx`'s shape
  must EQUAL it or the shaped-edge reduce at gradient.py:131 fires and upstream raises
  (it needs `broadcast_axes`, which is symbolic).  With every dimension equal, the
  permuted shape IS the shape.

  WHY THE TARGET IS `a` AND NOT `l0`: upstream's `_deepwalk` sets
  `in_target_path[u] = any(in_target_path[x] or x in targets for x in u.src)`
  (gradient.py:112), so a node is in the walk only if one of its SRCS reaches a
  target.  A TARGET IS NEVER ITSELF IN THE WALK, so the target's own rule is never
  needed -- and `a` is a STACK, whose rule (`ctx[i]`, gradient.py:91) the port cannot
  do (gr_22 is `GSkip`).  **⇒ MAKING `a` THE TARGET IS WHAT KEEPS THE FIXTURE INSIDE
  `gr_21` ALONE.**

  WHY `ctx` IS A STACK AND NOT A BUFFER: `ctx` must have `ndim == 3` for upstream's
  `permute()` to accept a 3-element order (`_resolve_dim` checks against
  `self.ndim`, movement.py:81-84), and a BUFFER is at most 1-D.
  """
  l0, l1, l2 = leaf(0, 2), leaf(1, 2), leaf(2, 2)
  s01 = UOp(Ops.STACK, src=(l0, l1))
  a = UOp(Ops.STACK, src=(s01, l2))
  per = UOp(Ops.PERMUTE, src=(a,), arg=(1, 2, 0))
  m0, m1, m2 = leaf(3, 2), leaf(4, 2), leaf(5, 2)
  n01 = UOp(Ops.STACK, src=(m0, m1))
  ctx = UOp(Ops.STACK, src=(n01, m2))
  return {"l0": l0, "l1": l1, "l2": l2, "s01": s01, "a": a, "per": per,
          "m0": m0, "m1": m1, "m2": m2, "n01": n01, "ctx": ctx}


def fixture_p1():
  """THE 1-D IDENTITY-PERMUTE FIXTURE -- the CONTROL for P2.

      leaf = BUFFER(0) shape (6,)   per = PERMUTE(leaf, (0,))   g = BUFFER(1) shape (6,)

  `(0,)` IS THE IDENTITY, so upstream's `permute()` (movement.py:231) returns `ctx`
  ITSELF -- no PERMUTE node is built.  **⇒ THE GRADIENT OF `per` IS `g` VERBATIM, AND
  THE `bw` GRAPH IS `g`'s NODE SET AND NOTHING ELSE.**
  """
  leaf0 = leaf(0, 6)
  per = UOp(Ops.PERMUTE, src=(leaf0,), arg=(0,))
  g = leaf(1, 6)
  return {"leaf": leaf0, "per": per, "g": g}


def emit(prefix, fx, root, root_grad, target):
  """THE ROWS.  Every row is a MEASUREMENT, and every row names its denominator."""
  targets = {target}
  walk, itp = _deepwalk(root, targets)
  print("%s_walk=%s" % (prefix, " ".join(tok(x) for x in walk)))
  print("%s_walk_n=%d" % (prefix, len(walk)))

  # THE RULE, MEASURED DIRECTLY: upstream's OWN table, on the SAME node, with the
  # SAME ctx.  This is the question the port's `rw` answers.
  rule = pm_gradient.rewrite(root, ctx=root_grad)
  print("%s_rule_len=%d" % (prefix, 0 if rule is None else len(rule)))
  if rule is not None:
    ans = rule[0]
    print("%s_rule_is_ctx=%d" % (prefix, 1 if ans is root_grad else 0))
    print("%s_rule_tok=%s" % (prefix, local_token(ans)))
    print("%s_rule_op=%s" % (prefix, tok(ans)))
    # THE ORDER, AS TEXT.  The `bw` token is `OP/nsrc` plus the IDENT, and a
    # PERMUTE's IDENT IS EMPTY -- so the SIGNATURE CANNOT SEE WHICH PERMUTATION WAS
    # BUILT, and the order is a row of its own.
    arg = ans.arg if isinstance(ans.arg, tuple) else ()
    # NEVER AN EMPTY STRING: "there is no order here" is a REAL value (the answer IS
    # the ctx, whose arg is a PARAM and not a tuple), and an empty expectation is the
    # gate's VACUITY class -- `UNCHECKABLE`, which is RED.
    print("%s_rule_arg=%s" % (prefix, ",".join(str(x) for x in arg) if arg else "none"))

  grads = compute_gradient(root, root_grad, targets)
  print("%s_grads_n=%d" % (prefix, len(grads)))
  print("%s_keys=%s" % (prefix, " ".join(tok(x) for x in grads)))

  # THE GRADIENT SET -- one slot per target, IN TARGET ORDER (mixin/op.py:471).
  slots = []
  for t in (target,):
    g = grads.get(t)
    if g is None:
      sub = t.const_like(0)
      slots.append(sub)
      print("%s_zero_n=1" % prefix)
    else:
      slots.append(g)
      print("%s_zero_n=0" % prefix)
  print("%s_set_n=%d" % (prefix, len(slots)))
  print("%s_set_sig=%s" % (prefix, " | ".join(
    "%s %d root=%s" % ("Z" if grads.get(t) is None else "G", len(nodes_of(s)), tok(s))
    for t, s in zip((target,), slots))))

  # THE `bw` GRAPH -- the union of the gradient values' node sets.
  print("%s_bw_nodes=%d" % (prefix, len({id(n) for s in slots for n in nodes_of(s)})))
  print("%s_bw_sig=%s" % (prefix, bw_sig(slots)))
  print("%s_bw_distinct=%d" % (prefix, bw_distinct(slots)))


def main():
  fx2 = fixture_p2()
  print("=== P2: the 2-D PERMUTE, order (1,0)")
  emit("oracle_pm", fx2, fx2["per"], fx2["ctx"], fx2["a"])

  fx1 = fixture_p1()
  print("=== P1: the 1-D IDENTITY PERMUTE, order (0,)")
  emit("oracle_pm1", fx1, fx1["per"], fx1["g"], fx1["leaf"])

  # THE ARGSORT, measured on the port's own terms -- upstream's `argsort` sorts BY
  # VALUE and returns INDICES (helpers.py:28).
  from tinygrad.helpers import argsort
  for xs in [(0, 2, 1), (1, 2, 0), (2, 1, 0), (1, 0, 2), (2, 0, 1), (1, 0)]:
    print("oracle_pm_argsort_%s=%s" % ("_".join(str(x) for x in xs), ",".join(str(x) for x in argsort(xs))))


main()
