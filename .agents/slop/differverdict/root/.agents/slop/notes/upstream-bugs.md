# UPSTREAM CANDIDATES — places tinygrad itself looks wrong, found by the Bend port

Every entry: the Python file:line, what the port measured, and why it looks
upstream rather than port-side. Filed or not is the owner's call; each is
reproducible from the oracle scripts named.

## Confirmed-looking (a CPython run says the source is surprising)

1. **`tinygrad/mixin/gradient.py:85`** — the RESHAPE rule answers TWO grads for a
   ONE-src node. `compute_gradient`'s own assert fires on it. Measured by
   mixin/gradient.bend's `reshape_len=0` row (CPython: arity mismatch, exception).
   Suggested fix: the rule's src tuple has one element; the second grad has no
   source to attach to.

2. **`tinygrad/uop/ops.py:1478` comment** — documents `early_reject` as "the single-op
   ops of src[0]", but measured against CPython it is the ops of the pattern's
   FIRST SRC ALTERNATIVE (all of its srcs): `pm_remove_invalid.patterns[0][0]
   .early_reject == {Ops.CONST}`. A wrong comment that three of our reject sets
   depended on. Suggested fix: correct the doc line.

3. **`tinygrad/uop/upat.py` name-cache STORE semantics** — because UPat interns by
   name, `UPat.var("x") * UPat.var("x")` (symbolic.py:463) COMPILES to a matcher
   that also matches `1/(x*y)` — the second bind overwrites the first, so the
   identity check the source seems to promise never happens. Our port emits the
   check and is strictly stricter. Either the comment at symbolic.py:463 should
   say the broad match is intended, or the pattern is broader than its author
   thinks. Measured: mixin/gradient.bend `gr_29_same` vs CPython on 1/(x*y).

## Behavior-not-bug (documented here so nobody re-chases them)

4. **`tinygrad/helpers.py:95`** — `unwrap(None)` RAISES (`.expr` on a nameless
   buffer), it does not answer None. Correct per "unwrap asserts"; noted because a
   reader of realize.py may expect a Maybe.

5. **`sz.py`'s `%.1f`** — formats the nearest double, so 21/20 prints 1.1 where
   exact half-to-even says 1.0. Python semantics, not a bug; the Bend port rounds
   the exact rational and the divergence is a recorded owner decision.

## NOT upstream (the port was wrong; kept to close the loop)

The other ~20 fixes this session — eq_cls/eq_addr arms, helpers floordiv/ceildiv/
asr, Ops.name, toposort order+fuel, src_from, is_balanced, enter_calls, movement
hop_self (+4), dtype.bend's i64 constants, fold's reverse — were all verified as
PORT-side against a correct CPython oracle. Python was right in each case.
