remint moves down to uop/weak.bend and tn_isfinite's pin drops

THE LAST `tn_*` DIVERGENCE WAS AN IMPORT CYCLE, NOT A DECISION. `remint`
(elementwise.py:12) was ported as `ew_remint` in `tinybendygrad/mixin/elementwise.bend`,
and that file IMPORTS `tinybendygrad/tensor.bend`, so `tensor.bend` could not call it.
What it needed it for is `_broadcasted`'s promote half (elementwise.py:29-31): `self.eq(inf)`
REMINTS a weakint `self` to weakfloat, `self != self` does not, the two hash-cons APART, and
CPython's graph holds `CONST weakfloat 4.0` AND `CONST weakint 4`. MEASURED, `.venv/bin/python`
on `Tensor(UOp(Ops.CONST, src=(), arg=4)).isfinite()`: 15 nodes, FIVE distinct CONST leaves.

uop/weak.bend IS THE LOWEST MODULE THAT CAN HOLD IT, and that is a measurement:
`wk_dt_const`, `wk_const_of` and `replace_in` are its three callees' callees and all three
are there, while `helpers.bend`, `LAWS/spec.bend`, `uop/ops.bend` and `uop/fold.bend` are all
BELOW `weak.bend` in the import order (weak.bend imports every one of them). Six defs moved --
`ew_remint{,.put,.go}`, `ew_ccast{,.go}`, `ew_ccast_at`, `ew_const_bare`, `ew_const_val`,
`ew_src0`, `ew_is_c0` -> `wk_remint{,.put,.go,.cast,.mkconst,.folds,.isc}` -- and
`ew_const_val` was DROPPED rather than carried: `wk_ccast.val` is that function under
another name. `mixin/elementwise.bend` keeps a one-line forwarder at the old name, because
`mixin/op.bend:468` calls `E.ew_remint` and that file is not this move's to rename; it is
the only external call site (measured with grep over tinybendygrad/ and gates/).

`tensor.bend` gains `tn_isfinite.promote` -- `_broadcasted`'s promote for `self` ALONE against
the weakfloat `inf`, all four arms, every conjunct borrowed (`O.UOp.is_invalid`,
`W.wk_is_weak_const`, `F.least_upper.of`, `W.weak_dtype`, `W.wk_remint`) -- and
`isinf_part` now compares BOTH eq halves against the promoted `self`. The old spelling
compared the positive arm's bool MUL against `-inf`, which was `CMPNE(MUL, CONST)` where
CPython has `CMPNE(CONST, CONST)`: one node, wrong srcs, right count, and invisible to every
row in both gates because every row reads the TOP node or the TOP's srcs. The only thing that
saw it is the 15-line dump committed at `.agents/slop/tnisf/dump2.bend`, and the fix moved
the count from 18 (a first attempt that merged `ew_is_c0` with `ew_src0` and so ran the
recursion arm on a CONST) to 15.

THE PIN DROPS RATHER THAN MOVES, and both directions are measured:
  rc=1  bd's tn_isfinite is not 'tn_isfinite=14 Ops.CMPNE/2 Ops.OR Ops.CONST' -- if the
        divergence is fixed, drop it from DIVERGES; if it moved, update the pin
  rc=0  51 rows, 3 lanes, ZERO declared divergences, all three lanes byte-identical
gates/tn_isfinite.bend's header recorded the 14-vs-15 as unfixed; it does not any more, and a
document that restates a stale reading is one witness propagating a lie.

SWEEP. All 61 `gates/*-gate.py`, serially, one `bend` process at a time:
  gates/tn_graph_census-gate.py rc=0, gates/ew_graph_census-gate.py rc=0 (the remint rows),
  gates/ew-explog-gate.py rc=0, gates/mixin-op-gate.py rc=0 (E.ew_remint through the
  forwarder), gates/ew-consts-gate.py rc=0.
  First pass 57/61 rc=0; the four that read rc=1 were `amd_dsl_census`, `ops_python_census`
  and `wgsl_render_census` -- all three rc=0 on re-run, so they were concurrent edits by
  other units, not this one -- and `indexread`, which is a git-INDEX hygiene gate whose
  7 NEW offenders are `.agents/slop/orcdecide/`, `.agents/slop/whyarms/` and
  `checks/index-arm-gate.py`, none of them in this commit.