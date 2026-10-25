"""ORACLE -- `grad_set` and the `bw` graph, measured by CALLING CPython.

WHAT THIS IS.  The gradient SET is upstream's `tinygrad/mixin/op.py:471`:

    return [self._wrap_uop(grads[x] if x in grads else x.const_like(0)) for x in target_uops]

-- one slot per target, IN TARGET ORDER, and a target with no entry in `grads` gets the
`const_like(0)` SUBSTITUTE rather than a hole.  The port's `tensor.bend` implements the
SELECTION (`tn_bwd_slot`) but answers the substitute with the arena's reserved index 0,
which is a NAMED DIVERGENCE.  `mixin/gradient.bend` CAN build the real substitute (it
owns `gconst`), so the substitute belongs there.

THE `bw` GRAPH is the backward UOp GRAPH that `compute_gradient` builds: the union of the
node sets of the gradient values.  It is read out of the ARENA (the port's arena is
hash-consed, so a node IS its own key) and it is compared to CPython's by a canonical,
index-free signature -- because the port's arena indices and CPython's construction
order are not comparable, and the corpus's own answer to that problem
(`.agents/slop/graphcmp.py:940` `row_of` + the differ's structural pairing) is not
available from inside a `.bend` file.

THE FIXTURE, and WHY IT IS THIS ONE.  The prior art's fixture
(`.agents/slop/backward/oracle-cg.py`) uses `UOp(Ops.BUFFER, arg=ParamArg(0, ...))` -- a
BUFFER with NO src -- and that NO LONGER RUNS: `compute_gradient` reads `k._shape`
(gradient.py:130) and upstream's `_shape` for a BUFFER reads `self.src[0].as_shape`
(ops.py:359), so a src-less BUFFER raises `IndexError`.  MEASURED 2026-10-25 by running
it: `.agents/slop/backward/oracle-cg.py` dies at `oracle-cg.py:83`.

So the leaf here is a BUFFER whose src is an EMPTY STACK: `as_shape` of an empty STACK
is `()` (ops.py:786-789), so the leaf's `_shape` is `()` -- SCALAR -- and the shaped-edge
reduce at gradient.py:131 never fires.  The EXPAND's shape src is the SAME kind of node,
so the EXPAND's `marg` is `()` (ops.py:794) and the EXPAND's `_shape` is `()` too.

WHY AN EXPAND: upstream's EXPAND rule is `(ctx, None)` (gradient.py:86), so its SECOND
src receives NO gradient -- that is a real HOLE (gradient.py:130's `if v is None:
continue`), and if that src is a TARGET then `grads[target]` is ABSENT, which is exactly
the `const_like(0)` case.  The prior art's `walk_hole_n=0` was a fact about its fixture
and NOT a coverage statement; this fixture is the one that makes it non-zero.

Run:
    LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward2/oracle-gs.py
"""
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import compute_gradient, pm_gradient, _deepwalk


def leaf(slot):
  """A BUFFER with an EMPTY-STACK src: dtype f32, `_shape` () -- MEASURED by
  `.agents/slop/backward2/probe2.py` (`L1`), which is the only leaf kind that makes
  CPython's `compute_gradient` return instead of raising."""
  return UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=()),), arg=ParamArg(slot, dtypes.float32))


def build():
  """THE FIXTURE.

      a = BUFFER(0)      p = MUL(a, b)
      b = BUFFER(1)      e = EXPAND(p, sh)     <- sh is the HOLE's src
      z = BUFFER(9)      q = ADD(a, e)
      sh = STACK()      r = ADD(p, q)          <- the root

  TWO different reasons for a target to have no gradient, and they are DIFFERENT reasons:

  * `z` is a DETACHED target -- it is on no path at all, so `_deepwalk` never puts it in
    the walk and `grads` has no entry for it.  **THIS is the `const_like(0)` case.**
  * `sh` is the EXPAND's second src.  upstream's EXPAND rule answers `(ctx, None)`
    (gradient.py:86), so `sh` receives a HOLE (gradient.py:130's `if v is None:
    continue`) -- a REAL hole, counted by `oracle_gs_hole_n`.  `sh` is NOT a target, so
    it does not also drive the substitute.

  WHY `sh` IS AN EMPTY STACK AND NOT A CONST: the EXPAND's shape is
  `tuple(self.marg) + ps` (ops.py:414) and `marg` is `src[1].as_shape` (ops.py:794).
  `as_shape` of a CONST is `(val,)` (ops.py:787) and of a non-STACK is `(ssimplify(self),)`
  (ops.py:788) -- both ONE-tuples -- so the EXPAND's `_shape` would be a 1-tuple, the
  shaped-edge reduce at gradient.py:131 would fire, and CPython would raise
  `RuntimeError: cannot broadcast (1,) into ()`.  MEASURED: that is exactly what a
  CONST-1 shape src does.  `as_shape` of an EMPTY STACK is `()` (ops.py:789), so the
  EXPAND's `_shape` is `()` and the reduce never fires.

  `p` and `a` are each written TWICE (the ACCUMULATE at gradient.py:138): `p` by the root
  and by the EXPAND, `a` by `q` and by `p`.
  """
  a, b, z = leaf(0), leaf(1), leaf(9)
  sh = UOp(Ops.STACK, src=())
  p = UOp(Ops.MUL, src=(a, b))
  e = UOp(Ops.EXPAND, src=(p, sh))
  q = UOp(Ops.ADD, src=(a, e))
  r = UOp(Ops.ADD, src=(p, q))
  return a, b, z, sh, p, e, q, r


def f32bits(v) -> int:
  import struct
  return struct.unpack('<I', struct.pack('<f', float(v)))[0]


def ident(u) -> str:
  """WHAT TELLS TWO NODES OF THE SAME CLASS APART.  A CONST's VALUE and a BUFFER's
  PARAM SLOT.  WITHOUT IT `a` and `b` are both `BUFFER/1` and the signature cannot
  see a swap of the MUL rule's two operands -- which is THE bug this row exists for
  (upstream gradient.py:80 crosses them).  NAMED LIMIT: an op whose arg carries no
  identity (an ADD, a CAST) gets an empty ident and is told apart by its srcs."""
  if u.op is Ops.CONST:
    v = u.arg
    if isinstance(v, bool): return "@b%d" % int(v)
    if isinstance(v, float): return "@f%d" % f32bits(v)
    if isinstance(v, int): return "@i%d" % v
    return ""
  if u.op in (Ops.BUFFER, Ops.ALLOC, Ops.PARAM) and getattr(u.arg, "slot", None) is not None:
    return "@s%d" % u.arg.slot
  return ""


def tok(u) -> str:
  """THE CLASS TOKEN: `OP/nsrc`.  This is what the walk and the grads-key rows read,
  and it is what the port's `dag_one` prints."""
  return "%s/%d" % (u.op.name, len(u.src))


def btok(u) -> str:
  """THE CLASS TOKEN PLUS THE IDENT -- the `bw` graph's token.  The walk and the key
  rows use the CLASS token and the `bw` signature uses this one; they are different
  rows and they were once the same function, which is how `gs_keys` came to disagree
  with the port for one build."""
  return "%s%s" % (tok(u), ident(u))


def nodes_of(u):
  return list(u.toposort(enter_calls=True))


def local_token(u) -> str:
  """THE ONE-HOP TOKEN: the node's own class AND IDENT, and the SORTED tokens of its
  srcs.  Order-free and index-free on purpose: the port's arena indices and CPython's
  construction order are not comparable, so a signature that keyed on them would be
  comparing two different things."""
  return "%s [%s]" % (btok(u), " ".join(sorted(btok(s) for s in u.src)))


def bw_sig(roots):
  """THE `bw` GRAPH SIGNATURE: the sorted list of per-node tokens over the union of the
  roots' node sets."""
  seen = {}
  for r in roots:
    for n in nodes_of(r):
      seen[id(n)] = n
  return " ".join(sorted(local_token(n) for n in seen.values()))


def bw_tokens(roots):
  seen = {}
  for r in roots:
    for n in nodes_of(r):
      seen[id(n)] = n
  return sorted(local_token(n) for n in seen.values())


def bw_ops(roots):
  """THE OP CENSUS: a count per op over the same node set.  A count WITH a denominator
  (the node count), so it is not a bare number."""
  seen = {}
  for r in roots:
    for n in nodes_of(r):
      seen[id(n)] = n
  counts = {}
  for n in seen.values():
    counts[n.op.name] = counts.get(n.op.name, 0) + 1
  return " ".join("%s=%d" % (k, counts[k]) for k in sorted(counts))


def main():
  a, b, z, sh, p, e, q, r = build()
  targets = [a, b, z]
  names = {"a": a, "b": b, "z": z, "p": p, "e": e, "q": q, "r": r}

  walk, itp = _deepwalk(r, set(targets))
  print("oracle_gs_walk=%s" % " ".join(tok(x) for x in walk))
  print("oracle_gs_walk_n=%d" % len(walk))
  print("oracle_gs_n_inpath=%d" % sum(1 for x in r.toposort() if itp.get(x, False)))
  print("oracle_gs_inpath=%s" % " ".join("1" if itp.get(x, False) else "0" for x in r.toposort()))

  grads = compute_gradient(r, UOp.const(1.0, dtypes.float32), set(targets))
  print("oracle_gs_grads_n=%d" % len(grads))
  print("oracle_gs_keys=%s" % " ".join(tok(x) for x in grads))

  # THE SKIP AND THE HOLE, counted through upstream's OWN loop -- not a second
  # transcription of it.
  skipped, holes = 0, 0
  g2 = {r: UOp.const(1.0, dtypes.float32)}
  for t0 in reversed(walk):
    if t0 not in g2:
      skipped += 1
      continue
    lg = pm_gradient.rewrite(t0, ctx=g2[t0])
    if lg is None:
      continue
    holes += sum(1 for v in lg if v is None)
    for k, v in zip(t0.src, lg):
      if v is None:
        continue
      g2[k] = g2[k] + v if k in g2 else v
  print("oracle_gs_skip_n=%d" % skipped)
  print("oracle_gs_hole_n=%d" % holes)

  # THE GRADIENT SET -- mixin/op.py:471, one slot per target, IN TARGET ORDER.
  slots, zeros, sig = [], 0, []
  for t in targets:
    g = grads.get(t)
    if g is None:
      zeros += 1
      sub = t.const_like(0)
      slots.append(sub)
      sig.append("Z %d root=%s" % (len(nodes_of(sub)), tok(sub)))
    else:
      slots.append(g)
      sig.append("G %d root=%s" % (len(nodes_of(g)), tok(g)))
  print("oracle_gs_set_n=%d" % len(slots))
  print("oracle_gs_zero_n=%d" % zeros)
  print("oracle_gs_set_sig=%s" % " | ".join(sig))
  # THE TARGET ORDER, so a permutation of the answer list is visible on its own.
  print("oracle_gs_set_order=%s" % " ".join(tok(t) for t in targets))

  # THE `bw` GRAPH -- over the gradient SET, so the ZERO substitute is IN it.
  print("oracle_bw_nodes=%d" % len({id(n) for s in slots for n in nodes_of(s)}))
  print("oracle_bw_sig=%s" % bw_sig(slots))
  print("oracle_bw_ops=%s" % bw_ops(slots))
  # THE INJECTIVITY ROW.  `bw_sig` is a COMPLETE description of this graph only if no
  # two nodes share a token; if two did, the signature would be a lossy encoding and
  # the claim would be false.  So the row MEASURES it rather than asserting it.
  toks = bw_tokens(slots)
  print("oracle_bw_distinct=%d" % len(set(toks)))


main()
