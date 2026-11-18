import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/engine/realize.bend"

EDITS = [
  # ---- THE HEADER (20 lines) -> 12. THE `ExecItem` CORRECTION IS A BUG RECORD AND STAYS.
  (1, 20, """# realize.bend -- tinygrad/engine/realize.py.
#
# THE REALIZATION DRIVER, and the first unit in the port whose subject is not a rewrite.
# `realize.py` answers one question -- "a scheduled LINEAR is lowered, compiled and executed; what
# is the PLAN for each CALL in it?" -- and it answers it in two halves a reader can easily mistake
# for one file: the DATA FLOW, which nodes of a CALL are arguments, which are outputs and which
# are inputs, which buffers a call writes, how a runtime symbol is resolved against the input
# uops, which calls still need lowering, and the shape of the per-execution context. Pure function
# of the arena. PORTED.
#
# the unit brief for this file names `run_schedule`, `lower_schedule` and an `ExecItem`. NONE OF
# THEM EXISTS in this checkout. `realize.py` is 296 lines and its driver entry points are
# `compile_linear`, `link_linear`, `run_linear` and `time_call`; the type that plays `ExecItem`'s
# role is the `ExecContext` dataclass at realize.py:118. REPORTED, NOT GUESSED AT: the port follows
# the file in front of it. (An older tinygrad had `ExecItem`; this one replaced it with the
# `ExecContext` record, which is why the line count still matched.)"""),

  # ---- THE 122-LINE BLOCK. THE INVENTORY MOVES OUT; THE FOUR RULE TABLES, THE ESCAPE, THE
  # `early_reject` DIFFERENCE, THE DEF ORDER AND THE `case _:` DEFECT STAY.
  (22, 143, """# THE TWO GROUPS, INVENTORIED, ARE IN `.agents/slop/tables/engine-realize-22.md`.
#
# the four rule tables, and why there are four dispatches.
#
# `realize.py` builds FOUR `PatternMatcher`s -- `pm_flatten_linear`, `pm_validate`, `pm_beam` and
# `pm_exec` -- and `ops.bend` cannot call a def in this file, so each gets its own table and its
# own scan. `uop/spec.bend` says the same in its own header and does it six times. `pm_validate` is
# Python's `PatternMatcher([...]) + pm_flatten_linear`, so its table is the validate rule at tag 0
# and the SAME flatten body at tag 1, and `va_1` really is `fl_0`.
#
# A GENERIC SCAN IS NOT AVAILABLE, and the reason is worth writing down because it is why every
# scan in the port is copied rather than factored: a shared scan would have to hold the rule
# BODIES, a body is a function value, a function value in a datatype field forces `Type` rather
# than `Data`, and a `Type` table is affine so one pass consumes it and the next pass rebuilds it.
# There are four passes here and `graph_rewrite` calls each many times. So the driver per table is
# duplicated. That is the price of not having first-class functions, and `uop/spec.bend` pays it
# too.
#
# THE ESCAPE IS AN ARGUMENT, and this file now uses it. A body cannot live in the TABLE, but it
# can be BUILT BY THE CALLER and handed to the scan as a `Verdict` value -- `rz_fire(claim, body)`.
# So the table keeps what is data (the op set and the reject set), `rz_claim` reads the claim off
# it with `ops.bend`'s own already correct `pm_claimed`/`pm_early`, and the one scan is shared.
# `O.pm_rewrite` cannot be that scan, because its `pm_dispatch` is `ops.bend`'s own tag-to-body
# table; see the paragraph at `rz_claim`.
#
# `early_reject` IS A VETO HERE, and that is a DIFFERENCE FROM `spec.bend`, so it gets a
# paragraph. `spec.bend`'s six tables carry four non-empty reject sets and all four are implied by
# their own src-op test, so there the subset test decides nothing. Here `pm_flatten_linear` carries
# `custom_early_reject={Ops.LINEAR}` (realize.py:205) and that set is the WHOLE of the rule's claim
# beyond the op: a LINEAR with no LINEAR child is REJECTED and `rewrite` answers `None`, while a
# LINEAR with one fires. `lin_none` and `lin_fired` below are the two rows that pin it, and
# `lin_none` is `9` rather than `1` because `show_v` spells Python's `None` as `VSkip`.
#
# the reject set is read off `ops.bend`'s `pm_ler`, which folds over every src. `spec.bend`
# reported the two-src version as a real bug there (`te_22`'s four-op reject set could never fire);
# that is fixed upstream of here, so this file has no `rz_ler` of its own and nothing to keep in
# step.
#
# DEF ORDER IS THE OTHER COST, and it is the one Bend imposes that Python does not: `def
# f.b(...)` must be declared BEFORE `def f.a(...)` that calls it, so every dotted helper is above
# the dotted entry point that calls it. Python's order is kept everywhere else.
# * read this before writing a `Bool` selector in this file. *
#
# `case _:` is a wildcard and it does not discriminate. One arm answers for both values of the
# scrutinee, and so -- this is the part that surprised us -- does a PAIR of them: `case _:` /
# `case _:` answers its FIRST arm for both values. A `Bool` choice therefore needs its tags named,
# `case True{}:` and `case False{}:`, and so does any other scrutinee that has a tag worth testing
# (`Some{n}` and not `Some{_}`, `Nil{}` and not `_`). A `case _:` is a correct LAST arm, and that is
# the only place one belongs.
#
# This file HAD THAT DEFECT EVERYWHERE: `bl_u.go` and `bl_t.go` were one-armed and so returned `f`
# for both values, and about a dozen entry points (`oi_cf.go2`, `gcc_pick.of`, `gk_is_v.g`,
# `rz_wbuf.take`, `rz_prod.go`, `rz_find.got.hit`, `ExecContext.has_timeout.of`, `oi_store.go`,
# `rz_expr_s.some`, the five `has_*` predicates) were ladders written AROUND it -- a chain of
# one-armed selectors, each of which is itself a constant, which is why fixing only `bl_u` turned
# the cascade inside out and made the gate memory-fault partway through `main`.
#
# The wave is converted and the ladder is gone: 21 of the 50 rows moved onto CPython's own answers
# and `--check-only` is green with both lanes identical. Two of those 21 were NOT the `Bool` cascade
# and are recorded at their own defs -- `pa_bound.of` (a dispatch that answered `None{}` for every
# `Arg`, so the bound map was always empty) and `rz_beam_sink` (a bare index returned from an
# arena it had grown, so the index pointed into an arena its caller did not hold).
#
# What is left as a constant is a constant ON PURPOSE: `rz_isdt.go`, `rz_nbytes.mul`, `rz_shape.go`
# and `rz_nbytes_of0` are the `None` halves of sibling matches, reached only from a sibling's
# `None` arm.
#
# `gate_count` is the row that keeps this honest -- it is the number of rows printed, so a row that
# stops printing cannot pass unnoticed."""),
]

apply(F, EDITS)
