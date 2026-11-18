import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/schedule/rangeify.bend"

EDITS = [
  # ---- THE HEADER (60 lines) -> 48: what the file is, the STATUS and the MARKER FORM (a bug
  # record: the header named a spelling the file does not use), the ELEVEN TABLES, the
  # root-not-child WALL, the early_reject MEASUREMENT, the identity-check note and the THREE
  # WALLS.
  (1, 60, """# rangeify.bend -- tinygrad/schedule/rangeify.py. The rangeification pass: 3.5 cleanups,
# bufferize/store conversion, kernel split -- eleven rule tables and the rewrites that run them.
#
# STATUS: the port is COMPLETE and `--check-only` passes. `main` 125 rows are derived from
# Python by `.agents/slop/rf-rows.py` and `rf-ct-oracle.py`, never restated from this file. A
# rule body that is not ported is one `# WALL(p3)` line at the foot naming the Python line it
# stands in for, so `rg 'WALL\\(p3\\)'` is the whole outstanding list.
# - and this header used to say `# TODO(p3)` and `rg 'TODO\\(p3\\)'`, which is FALSE: measured
# 2026-11-10, `grep -c 'TODO(p3)'` in this file answers 3 and all three are this paragraph and
# its two siblings, while `grep -c 'WALL(p3)'` answers 30 and those are the markers. - so the
# header named a spelling the file does not use, and a reader who believed it was reading a list
# of three prose lines as IF it were the outstanding work. the marker form here is `# WALL(p3)`
# and it is distinct from `# TODO(p3)` on purpose: a wall is a python fact and a TODO is a
# decision, and `checks/marker-audit.py` READS BOTH (SEE `.agents/TOOLS.md`'s ENTRY).
# The long form of this header -- the staged-delivery record, the 41-mutation table and its five
# proofs -- is appended to `.agents/slop/notes/bend2-constraints.md`.
#
# ELEVEN TABLES, ELEVEN DISPATCHES, and deliberately no generic one: `ops.bend` cannot call into
# this file and a rule table must be a top-level `Data` value (there are no closures), so every
# table gets its own `rf_<x>_table`/`_dispatch`/`_try`/`_scan`. The duplication IS the port.
# `pm_mops`/`pm_flatten_range` are OTHER files' tables; their foreign tags stay IN the table
# because the length and the tag space are Python facts the gate checks, and each dispatches to
# `rf_foreign`, which answers "no node" and names the owning file.
#
# wall: the root, not the child. `.f()` rebuilds the pattern with the op passed to `f` at the
# ROOT and the receiver as the CHILD, and `pdict` is keyed on `p.op` (ops.py:1587, 1607) -- so a
# `.f()` entry's op set is the one handed to `f`, and the RECEIVER's op belongs in the rule BODY
# test. The wrong op makes the rule unfireable rather than wrong: the engine never looks the
# node up.
#
# MEASURED: `early_reject` IS A NECESSARY CONDITION, not a veto (ops.py:1604 is `if not
# early_reject.issubset(ler): continue`). Every reject set in these tables is empty or a singleton
# (`max(len) == 1`) and every `.f()` rule re-checks its own pattern, so mutating the subset test
# moves NOTHING (M3, M36).
#
# a name bound twice must emit an identity check (`upat.py:100-105` builds it as a literal
# `"{0} is {1}"`). The ONE place it happens here is `rb_1` (tinygrad/schedule/rangeify.py:126,
# `pm_remove_bufferize`); without it every two-src STORE would rewrite to a NOOP.
# `uop/spec.bend`'s wall list cites this note by its first line, so that line is kept verbatim:
# 2. a name bound twice must emit an identity check (`upat.py:100-105` builds it
#
# `Hop` is `uop/movement.bend`'s, reused rather than copied: a rule answers a NEW node or `None`,
# and `None` is arena index 0, so the ARENA ITSELF separates "the rule fired" from "the rule
# rebuilt" -- a rule that does not fire interns nothing and does not grow it.
#
# THE THREE WALLS, each a `# WALL(p3)` at the foot. (a) `UOp.ranges` is a memoised
# recursive_property Bend refuses; `rf_ranges_miss` names it in one constant and
# `rg rf_ranges_miss` lists every dependent. (b) the rules MUTATE a Python `ctx` -- an
# `itertools.count` and two dataclass caches -- and Bend has no mutable state, so a counter is a
# PARAMETER and a dict is an assoc list; that is why `get_kernel_graph` is a STAGE ORDER and not
# a driver. (c) `BufferizeOpts.removable`/`addrspace` are not in `ops.bend`'s `Arg`, so every
# read of a STAGE's own `removable`/`addrspace`/`device` is a wall, and three rules turn on it."""),

  # ---- `UOp.ranges` -- the WALL. The LIST OF SIX READERS IS A TABLE.
  (196, 205, """# `UOp.ranges` -- ops.py:497, and the set algebra behind it (`_ranges`, ops.py:483).
# THE WALL, and the single biggest one in this unit. `_ranges` is `union(s.ranges for s in
# self.src)` MINUS every range an ended range carries; it is a memoised `recursive_property` and
# Bend refuses the mutual recursion.
#
# Six rules read it -- `cleanup_dead_axes` (36), `gate_substitute` (46), `after_all_invalid`
# (112), `bufferize_to_store` (211), `split_store` (337) and `_limit_bufs` (194) -- and
# `rf_ranges_miss` is the honest spelling: the port cannot compute the set, so each answers the
# SAFE branch. It is `False` for "I have the set" and is a single named constant rather than six
# silent omissions."""),

  # ---- the `shrank`/`one` ORDER -- a BUG THAT WAS FOUND. KEEP IT WHOLE.
  (312, 322, """# `shrank` is asked first and that order is the whole rule. Upstream's line is `if len(src)
# != len(x.src): return src[0] if len(src) == 1 else x.replace(src=src)` and the `return None` is
# the ELSE of that test -- so a ONE-SRC AFTER that LOST NOTHING is not rewritten at all. Asking
# `one` first answers `src[0]` for every one-src AFTER, which COLLAPSES an untouched
# `AFTER(CONST)` into `CONST`. MEASURED 2026-11-03 by `gates/gkg-oracle.py`, stage 3 on fx_a: the
# port answered `SINK:none:CONST,...` where CPython answers `SINK:none:AFTER,...`, and 8 of 16
# engine rows disagreed BECAUSE OF THIS ONE LINE. The `raf_*` rows could not see it: every one of
# them that reaches `one` also SHRANK, so `one` and `one AND shrank` answered the same on all of
# them.
# THE INNER LADDER IS ITS OWN DEF because a `match` may not scrutinise a binder that a previous
# arm already passed -- Bend refuses `match shrank: ... match one: ...` in place."""),

  # ---- TABLE 7 -- the RULE TABLE (nine rules) is DATA, and the rest is the fact.
  (993, 1022, """# TABLE 7: `pm_const_buffer_folding` -- rangeify.py:115-129. NINE RULES: the three `pm_mops`
# rules (foreign, tags 0-2) and SIX OWN -- `cleanup_dead_axes`, `remove_noop_bufferize`,
# `const_like`, `index-a-const`, `after_all_invalid`, and the deviceless-MSTACK unwrap.
#
# the reject sets are the interesting part and they are three of the file's six: `ct_4` is
# `{INDEX}`, `ct_7` is `{AFTER}`, `ct_8` is `{MSTACK}`. Each is the op of the pattern's FIRST src
# and each is already implied by the rule's own op test, so `early_reject` decides no verdict
# here. `rej_ct4` is the row that catches a MISSPELLED set, which is the failure mode that is
# real.
#
# two of the six are fully ported and they are the two a reader checks first, because they are
# the ones with no `ranges` and no `BufferizeOpts`: `ct_6` ("indexing a const is the const") and
# `ct_4`'s `remove_noop_bufferize`. `ct_5` needs `const_like` (ops.py:603, a `DType` method, P3)
# and `ct_7` needs `after_all_invalid`'s `resolve(...eq(...))`, which is `_min_max`.
#
# ct_6's answer is a node ALREADY IN THE ARENA, so nothing is interned. `or_casted` is an
# `is_any` of two alternatives, so there are TWO arms and `c` is bound in each; they never meet,
# so no identity check is emitted.
#
# UPSTREAM'S COMMENT IS THE RULE'S WHOLE BODY: "indexing a const is the const" (116). A CONST is a
# value, not a buffer, so there is nothing to index into: the INDEX and its src are the same
# value and the INDEX collapses. That is why this rule needs no movement op and no builder -- it
# answers a node ALREADY IN THE ARENA.
#
# THE PATTERN IS THE CLAIM, and giving the body an ELSE arm makes the rule a catch-all.
# MEASURED: with an else arm the answer's src op sequence was ".58.58" (the MSTACK) and
# `ct8d_srcops` was 0; with the claim in place it is ".58" and `ct8d_srcops` is 1.
# `UPat.cvar().or_casted()` -- the op is CONST for the bare arm and CAST for the wrapped one,
# and the CAST arm requires EXACTLY one src."""),

  # ---- rb_0 -- the UPSTREAM QUOTES are the RULE'S REASON and they stay. The COST paragraph is
  # the fact. Let me see the rest of the block first.
  (631, 670, """# rb_0: `remove_bufferize` -- rangeify.py:48-102, and it is NOT PORTED. The wall is spelled
# out at the foot; what is here is the CLAIM, so the table length and the claim count are right
# even though the body is absent.
#
# UPSTREAM'S TWO COMMENTS ARE THE RULE'S REASON, and they are kept here because the port's
# answer is "no node" and a reader needs to know what the rule would have decided:
#
#   "if a buffer is being stored just for permutes or something, remove it" (46)
#   "we want to reexpress the indexes of idx2 in terms of the implied b1" (47)
#
# so `remove_bufferize` is not a simplification -- it REMOVES A BUFFERIZE by rewriting the INDEX
# that reads it into an index into the buffer the bufferize was standing in for. That is why the
# rule is `src.f(STAGE).f(INDEX)` and not the other way round: the STAGE is the bufferize to
# remove and the INDEX is the reader whose index gets reexpressed.
#
# AND THE COST IS THE POINT. Upstream computes it and the port does not:
#
#   "*** here is where we compute the cost ***" (56)
#   "if we return None, the bufferize is kept" (57)
#
# so `remove_bufferize` is a COST-FUNCTION rule, not a pattern rule: it walks the src and answers
# `None` -- KEEP the bufferize -- unless the cost says the bufferize is free to drop. The cost is
# the number of buffers the src touches, and the three cutoffs are upstream's and each has a
# reason:
#
#   "don't look inside stores, this doesn't count toward buffer accesses" (69)
#       a STORE's own payload is not an ACCESS OF A BUFFER by the kernel; only the STORE's
#       destination counts.
#   "if this is generated from multiple buffers, don't remove this buffer" (80)
#       more than three accessed buffers and the bufferize is load-bearing.
#   "if any reduces access a buffer, don't remove this buffer" (82)
#       a REDUCE that reads a buffer cannot have that buffer's index reexpressed.
#
# THE PORT HAS NONE OF THIS, and that is the wall rather than an omission: the cost function
# needs a `toposort` with a GATE (a `red_gate` that answers whether to descend into a node) and
# a mutable `accessed_buffers` list, and `rb_0` is the rule whose body is absent. `rb_0` therefore
# INTERNS NOTHING and the arena does not grow -- `rb_arena` is the row that says so."""),
]

apply(F, EDITS)
