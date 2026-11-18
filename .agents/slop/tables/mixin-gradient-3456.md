<!-- FROM: tinybendygrad/mixin/gradient.bend:3456 -->
# BLOCK:
# ---- the gate ----------------------------------------------------------------
# THE GATE MOVED TO `gates/gradient-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the driver
# defines nothing this file needs, which is the line `gates/README.md:173` draws.
#
# Their 142 expectations are CPython's own bytes, and the harness that compares
# them is `.agents/slop/backward4/run.sh check`: the `pm_*`/`pm1_*` rows against
# `perm.rows`, the `walk_*` rows against `backward3/walk.rows` and the
# `gs_*`/`bw_*` rows against `backward2/rows.rows`. Every expectation is
# transcribed BY SCRIPT from an oracle that calls upstream, and the plant sweep
# proves every row can go red.
# END BLOCK

# ---- the gate ----------------------------------------------------------------
# THE GATE MOVED TO `gates/gradient-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the driver
# defines nothing this file needs, which is the line `gates/README.md:173` draws.
#
# Their 142 expectations are CPython's own bytes, and the harness that compares
# them is `.agents/slop/backward4/run.sh check`: the `pm_*`/`pm1_*` rows against
# `perm.rows`, the `walk_*` rows against `backward3/walk.rows` and the
# `gs_*`/`bw_*` rows against `backward2/rows.rows`. Every expectation is
# transcribed BY SCRIPT from an oracle that calls upstream, and the plant sweep
# proves every row can go red.
