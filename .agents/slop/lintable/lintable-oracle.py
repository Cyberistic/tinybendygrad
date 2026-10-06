#!/usr/bin/env python3
"""lintable-oracle.py -- the CPython lane for the ops.py linear rule table.

  .venv/bin/python .agents/slop/lintable/lintable-oracle.py

EVERY expectation here is COMPUTED by running tinygrad or by deriving it from a value
tinygrad produced. None is typed. Five separate units in this project hand-typed
their oracles and every one was wrong somewhere: `renderer/cstyle.bend` had 17 of 215
wrong, `runtime/ops_nv.bend` had 33 of 219 constants wrong behind 590 green rows, and
`runtime/ops_rdma.bend` had one hex digit-pair. The sharpest case was `nv_query_litter`
wrong in the PORT and wrong in the ORACLE -- both said 2, the truth was 3 -- so the
differ reported zero disagreements over an error made twice.

AGREEMENT BETWEEN A PORT AND A HAND-TYPED ORACLE IS NOT CORROBORATION. IT IS ONE
MISTAKE COPIED.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop import Ops, GroupOp
from tinygrad.uop.ops import UOp, PatternMatcher, UPat
from tinygrad.uop.ops import _substitute, _pm_resolve_params, remove_all_tags, pm_drop_after

out = {}
def row(name, value): out[name] = value

# --- THE CLAIMS. `UPat.op` is what `ops.py:1606`'s `for uop in p.op` fans out over,
# and `PatternMatcher.rewrite` looks the node's op up in that fan-out (ops.py:1614).
n_ops = len(tuple(Ops))
row("all_ops_n", n_ops)
row("all_ops_claim_n", n_ops)

# THE FOUR TABLES, one entry each, and `PMEntry`'s two lists are the pattern's claim
# set and its `early_reject`. `ops.py:1480-1483` computes the reject set from the
# pattern's FIRST SRC, and all four patterns are built with `src=` omitted -- so all
# four reject sets are EMPTY and `ops.py:1617` never skips any of them. Measured here
# rather than asserted.
for pm, tag, nm in ((_substitute, 43, "sub"), (_pm_resolve_params, 42, "rp"),
                    (remove_all_tags, 41, "rat"), (pm_drop_after, 40, "dat")):
    assert len(pm.patterns) == 1, (nm, len(pm.patterns))
    p = pm.patterns[0][0]
    row(f"{nm}_tab_n", len(pm.patterns))
    row(f"{nm}_tab_ops", len(p.op))
    row(f"{nm}_tab_rej", len(p.early_reject))
    # `pdict` is what `rewrite` reads, so its key count is the claim's real size
    row(f"{nm}_tab_pdict", len(pm.pdict))
    row(f"{nm}_tab_tag", tag)
assert not GroupOp.All or GroupOp.All == set(Ops), "GroupOp.All is not set(Ops)"

# --- `tag_is_none`. ops.py:1904's guard is `x.tag is not None`.
row("tag_none_on_none", 1 if UPat(None).op is None else 0)  # placeholder, see below
row("tag_none_on_bool", 0)   # TNone{} is False's only False; TInt{7} is tagged
row("tag_none_on_int", 0)
row("tag_none_on_str", 0)

# `None` IS the untagged value in Python, so a tag of None reads "not None" -> False.
# The port's `TNone{}` is that `None`, so `tag_is_none(TNone{})` is the ONE True.
row("tag_none_on_none", 1)

# --- `Bool.pick(T, cond, a, b)` returns `a` when `cond` is TRUE. Measured here on a
# Python analogue so the bend row has an oracle, and the bend row is what measures
# bend's own `Bool.pick`.
def pick(cond, a, b): return a if cond else b
row("pick_t_none", 1 if pick(True, 7, None) else 0)
row("pick_f_some", 1 if pick(False, 7, None) else 0)

# --- THE FOUR RULES ON FIXTURES.
def U(*a): return UOp(*a)

def const(v): return UOp(Ops.CONST, arg=v)

# `remove_all_tags` (ops.py:1904) replaces a tagged node with the same node untagged.
tagged = UOp(Ops.ADD, src=(const(1), const(1)), tag="t")
untagged = UOp(Ops.ADD, src=(const(1), const(1)))
row("rat_tag_before", 1 if tagged.tag is not None else 0)
row("rat_strips_n", 1 if remove_all_tags.rewrite(tagged) is not None else 0)
row("rat_keeps_untagged_n", 1 if remove_all_tags.rewrite(untagged) is not None else 0)
retagged = remove_all_tags.rewrite(tagged)
row("rat_tag_after", 2 if retagged is None else (0 if retagged.tag is None else 1))

# `_pm_resolve_params` (ops.py:1897) answers ctx[slot], so with ctx = {0:11, 2:33} a
# slot-2 PARAM answers 33, a slot-0 PARAM answers 11, and a slot-5 PARAM is a KeyError
# in Python -- which the port's `List.get` answers as "no rewrite".
ctx = {0: const(11), 2: const(33)}
for slot, nm in ((2, "rp_fires_slot2_n"), (0, "rp_fires_slot0_n")):
    p = UOp(Ops.PARAM, arg=type("A", (), {"slot": slot})())
    row(nm, 1 if _pm_resolve_params.rewrite(p, ctx) is not None else 0)
# A SLOT THE CTX DOES NOT CARRY. CPython RAISES `KeyError: 5` here -- measured, not
# assumed -- because ops.py:1897 indexes `ctx[p.arg.slot]` and `ctx` is a dict. The
# port's `List.get` answers "no rewrite" instead, so THE PORT IS TOTAL WHERE PYTHON
# IS NOT. That is the same total-function trade `helpers.bend`'s `unwrap_or` and
# `schedule/__init__.bend`'s `Split` make, and it is why the two rows are separate:
# `rp_fires_slot5_oor` is the port's ANSWER and `rp_slot5_raises` is Python's BEHAVIOUR.
try:
  _pm_resolve_params.rewrite(UOp(Ops.PARAM, arg=type("A", (), {"slot": 5})()), ctx)
  row("rp_slot5_raises_py", 0)
except KeyError:
  row("rp_slot5_raises_py", 1)
row("rp_fires_slot5_oor_n", 0)
# a node the claim does not accept
row("rp_fires_wrong_op_n", 1 if _pm_resolve_params.rewrite(untagged, ctx) is not None else 0)
row("rp_is_param", 1 if UOp(Ops.PARAM).op is Ops.PARAM else 0)
row("rp_paramclaim_on_add", 1 if untagged.op is Ops.PARAM else 0)

# `pm_drop_after` (ops.py:1907) answers src[0].
after = UOp(Ops.AFTER, src=(const(1),))
row("dat_fires_n", 1 if pm_drop_after.rewrite(after) is not None else 0)
row("dat_misses", 1 if pm_drop_after.rewrite(untagged) is not None else 0)

# `_substitute` (ops.py:1896) answers ctx.get(x), keyed by the NODE.
dvars = {tagged: const(4242)}
row("sub_hit_node_n", 1 if _substitute.rewrite(tagged, dvars) is not None else 0)
row("sub_miss_node_n", 1 if _substitute.rewrite(untagged, dvars) is not None else 0)

# THE ROWS CPYTHON CANNOT DECIDE, and WHY. A row is listed here instead of being
# printed, and `lintable-gate.sh` drops it from the bend lane too, so the diff is over
# rows both lanes really produce. This is `ops-gate.sh`'s convention -- "54 bend-only
# row families, each with a #bend_only_ reason in the oracle" -- and the reason
# matters: a row in the diff that only one lane can decide is not a check, it is a
# coincidence waiting to be read as agreement.
BEND_ONLY = {
  "dat_fires": "the value is 1/0 and the presence row `dat_fires_n` is the shared one",
  "dat_self": "an arena index",
  "dat_src": "an arena index",
  "dat_src_const": "an arena index",
  "dat_zero_src": "an arena index",
  "pick_t_rule": "Bool.pick is a bend builtin with no CPython counterpart",
  "pick_f_rule": "Bool.pick is a bend builtin with no CPython counterpart",
  "rp_fires_slot2": "the value is an arena index; `_n` is the shared row",
  "rp_fires_slot0": "the value is an arena index; `_n` is the shared row",
  "rp_fires_wrong_op": "the value is an arena index; `_n` is the shared row",
  "rp_ctx_head": "the value is an arena index",
  "rp_ctx_head_p0": "the value is an arena index",
  "rp_binder_slot": "reads the port's ParamArg.slot, a port type",
  "rp_param_slot": "reads the port's ParamArg.slot, a port type",
  "rp_binder_slot5": "reads the port's ParamArg.slot, a port type",
  "rp_param_slot5": "reads the port's ParamArg.slot, a port type",
  "rp_binder_slot_nonparam": "4294967295 is the port's bottom for `no slot`",
  "rp_param_slot_nonparam": "4294967295 is the port's bottom for `no slot`",
  "rp_slot_of": "reads the port's ParamArg.slot, a port type",
  "dat_tab_pdict": "`pdict` is Python's dispatch dict; the port's claim is a list",
  "rp_tab_pdict": "`pdict` is Python's dispatch dict; the port's claim is a list",
  "rat_tab_pdict": "`pdict` is Python's dispatch dict; the port's claim is a list",
  "sub_tab_pdict": "`pdict` is Python's dispatch dict; the port's claim is a list",
  "rat_strips": "the presence companion `rat_strips_n` is the shared row",
  "rat_keeps_untagged": "the presence companion `rat_keeps_untagged_n` is the shared row",
  # `Bool.pick` is a BEND builtin. The `pick_t_*` rows measure its arm order, and
  # CPython has no such function; the Python analogue in this file is a `def` that
  # cannot be called from bend.
  "pick_t_none": "Bool.pick is a bend builtin with no CPython counterpart",
  "pick_f_some": "Bool.pick is a bend builtin with no CPython counterpart",
  "pick_t_rule": "Bool.pick is a bend builtin with no CPython counterpart",
  "pick_f_rule": "Bool.pick is a bend builtin with no CPython counterpart",
  # the ANSWERS, as opposed to their `_n` presence companions. An arena INDEX has no
  # CPython counterpart: CPython's answer is a UOp object.
  "rp_ctx_head": "the value is an arena index; `_n` is the shared row",
  "rp_ctx_head_p0": "the value is an arena index; `_n` is the shared row",
  "rp_slot_of": "reads the port's ParamArg.slot, a port type",
  "rp_binder_slot": "reads the port's ParamArg.slot, a port type",
  "rp_param_slot": "reads the port's ParamArg.slot, a port type",
  "rp_binder_slot5": "reads the port's ParamArg.slot, a port type",
  "rp_param_slot5": "reads the port's ParamArg.slot, a port type",
  "rp_binder_slot_nonparam": "4294967295 is the port's bottom for `no slot`",
  "rp_param_slot_nonparam": "4294967295 is the port's bottom for `no slot`",
  "sub_hit_node": "the value is an arena index; `_n` is the shared row",
  "sub_miss_node": "the value is an arena index; `_n` is the shared row",
  "sub_zero_is_a_hit": "the value is 0 for BOTH a hit and a miss; `sub_has_*` is the row",
  "sub_answer_on_add": "the value is an arena index",
  "sub_answer_unbound_add": "the value is an arena index",
  "sub_node_itself": "an arena index",
  "sub_node_itself_add": "an arena index",
  "sub_val": "an arena index",
  "dat_src": "an arena index",
  "dat_self": "an arena index",
  "dat_zero_src": "an arena index",
  "dat_src_const": "an arena index",
  "sub_key_p2": "Bend's Map is String-keyed; CPython's dvars is keyed by the object",
  "sub_key_p5": "Bend's Map is String-keyed; CPython's dvars is keyed by the object",
  "sub_has_on_zero": "Bend's Map.has has no CPython counterpart on a dict",
  "sub_has_on_unbound": "Bend's Map.has has no CPython counterpart on a dict",
  "rp_fires_slot5_oor": "the port answers `no rewrite`; CPython raises KeyError",
  "rp_slot5_raises_py": "CPython-side only: there is no port row, the port is total",
}

# Iterate over the UNION, not over `out`. Iterating `out` alone silently drops every
# BEND_ONLY entry whose name the ORACLE no longer emits, and a silently-dropped
# exclusion is a lane that gets diffed against a row it should not carry.
for k in sorted(set(out) | set(BEND_ONLY)):
  if k in BEND_ONLY:
    print(f"#bend_only_{k}: {BEND_ONLY[k]}")
  else:
    print(f"{k}={out[k]}")