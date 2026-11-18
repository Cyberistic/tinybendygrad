<!-- FROM: tinybendygrad/engine/realize.bend:1554 -->
# BLOCK:
# `call` and `ctx` are each read twice -- once to find the sink and once to
# rebuild the node -- and a parameter Bend allows to be read twice is a `+`.
#
# and the clause is inside `bm_new` rather than around it, because in realize.bend
# `beam_rewrite` is a JUDGE (`realize.bend:2131` symbol=beam_rewrite) and `bm_new` is
# the BODY (`realize.bend:1595` symbol=bm_new), so `bm_new` is
# the `rewrite` this table's driver would otherwise be. THE DEFECT THIS FIXES IS
# MEASURED: `pm_beam`'s body is `call.replace(src=(sink.replace(arg=replace(sink.arg,
# beam=ctx)), *call.src[1:]))`, and at `ctx == 0` over a SINK whose `beam` is already 0
# EVERY replacement is the identity, `UOp.new` HASH-CONSES, and the answer IS the input
# node -- which `ops.py:1618` drops and this file did not. `gates/realize_graph_census`
# drove `pm_beam` at ctx 0 AND ctx 7 precisely so the clause has a row; before the fix
# CPython answered `0` and the port answered `1:<the input's own cone>`.
# END BLOCK

# `call` and `ctx` are each read twice -- once to find the sink and once to
# rebuild the node -- and a parameter Bend allows to be read twice is a `+`.
#
# and the clause is inside `bm_new` rather than around it, because in realize.bend
# `beam_rewrite` is a JUDGE (`realize.bend:2131` symbol=beam_rewrite) and `bm_new` is
# the BODY (`realize.bend:1595` symbol=bm_new), so `bm_new` is
# the `rewrite` this table's driver would otherwise be. THE DEFECT THIS FIXES IS
# MEASURED: `pm_beam`'s body is `call.replace(src=(sink.replace(arg=replace(sink.arg,
# beam=ctx)), *call.src[1:]))`, and at `ctx == 0` over a SINK whose `beam` is already 0
# EVERY replacement is the identity, `UOp.new` HASH-CONSES, and the answer IS the input
# node -- which `ops.py:1618` drops and this file did not. `gates/realize_graph_census`
# drove `pm_beam` at ctx 0 AND ctx 7 precisely so the clause has a row; before the fix
# CPython answered `0` and the port answered `1:<the input's own cone>`.
