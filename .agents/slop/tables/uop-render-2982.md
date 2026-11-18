<!-- FROM: tinybendygrad/uop/render.bend:2982 -->
# BLOCK:
# `pu_range`   one BUFFER with a RANGE: the baseline, and the `--` src arm.
# `pu_missing` an ADD whose CONST src is NOT in the list: `--` and not its value.
#              A def that dropped the OUTER membership test answers `4` here.
# `pu_const`   the same ADD with the CONST IN THE LIST: its VALUE, and not its index.
#              A def that dropped the INNER op test answers `1`.
# `pu_index`   BOTH srcs in the list: the INDEX arm, which only this row exercises.
# `pu_constarg` two CONSTs: the last column is a PyConst and not a ParamArg.
# ONE RECURSIVE DEF, and the shape is the point. The first draft was THREE --
# pu_row -> pu_row.go -> pu_row.line -> pu_row.go -- which is MUTUALLY recursive,
# and Bend refuses that: `bend-toposort` reported the cycle and declined to write,
# the fourth time this session that refusal has caught a real defect rather than an
# inconvenience.
#
# The way out is the file's own: recurse into YOURSELF and let a PURE helper take
# the head. `pu_row.tail` and `pu_row.one` never call back, so there is no cycle,
# and the print is a `do IO<Unit>` arm rather than a sibling def.
# `s5.seps.go`'s EXACT shape (ops.bend): one `+` arg, then the LIST as a plain
# binder, then the shrinking tail. The first attempt had `line: String` between
# them, and a String is not a list so the binder was read as "nothing shrinks" --
# "expected : a decreasing self-call", not a type error, which is the unhelpful way
# to say it.
# ONE DEF. There were three -- `step` -> `line` -> `head` -- and every arrangement
# of them was either MUTUALLY recursive (Bend refuses) or an R-3 ordering problem
# (whichever called the other had to be declared first). This is `s5.seps.go`'s
# shape verbatim (ops.bend): one `+` arg, the list as a plain binder, the shrinking
# tail, and the accumulator threaded through.
# ONE FOLD AND ONE EMITTER, in that order because the fold CALLS the emitter and
# R-3 wants the callee first. There were three defs before this and every
# arrangement was either mutually recursive (Bend refuses) or an ordering problem.
# The shape is `s5.seps.go` (ops.bend) with the print lifted into its own def only
# because a `do IO<Unit>` block cannot be an expression.
# the FOLD returns a string and the print happens once, which is `Bsl.row`'s shape
# (ops.bend) and the reason none of the previous four arrangements worked.
#
# A printing fold cannot be written as one def here. `s5.seps.go` recurses fine
# because it RETURNS a String; putting `IO.print` in the match arm needs a `do
# IO<Unit>` block, and the recursion then has to leave that block for a def that
# returns IO, and THAT def has no shrinking argument left. Five attempts:
# three mutually-recursive defs, one self-call with nothing shrinking, and one with
# a String where the binder had to be a list.
#
# So: fold to a String, join, print once. The fold is `s5.seps.go` with a newline
# instead of a space, and `IO.print` is one call at the end.
# the row name goes on every line, not once on the first. It went on the first as a
# `String.concat([nm, "|", ...])` wrapped around the WHOLE fold, which reads the same for
# a one-node row and is wrong for every row after it: `pu_constarg` printed its first
# CONST named and its second CONST bare, so the diff had one line to compare and one it
# could not name. The prefix is inside the fold for that reason, and `nm` is a `+`
# parameter because the fold reads it once per line.
# END BLOCK

# `pu_range`   one BUFFER with a RANGE: the baseline, and the `--` src arm.
# `pu_missing` an ADD whose CONST src is NOT in the list: `--` and not its value.
#              A def that dropped the OUTER membership test answers `4` here.
# `pu_const`   the same ADD with the CONST IN THE LIST: its VALUE, and not its index.
#              A def that dropped the INNER op test answers `1`.
# `pu_index`   BOTH srcs in the list: the INDEX arm, which only this row exercises.
# `pu_constarg` two CONSTs: the last column is a PyConst and not a ParamArg.
# ONE RECURSIVE DEF, and the shape is the point. The first draft was THREE --
# pu_row -> pu_row.go -> pu_row.line -> pu_row.go -- which is MUTUALLY recursive,
# and Bend refuses that: `bend-toposort` reported the cycle and declined to write,
# the fourth time this session that refusal has caught a real defect rather than an
# inconvenience.
#
# The way out is the file's own: recurse into YOURSELF and let a PURE helper take
# the head. `pu_row.tail` and `pu_row.one` never call back, so there is no cycle,
# and the print is a `do IO<Unit>` arm rather than a sibling def.
# `s5.seps.go`'s EXACT shape (ops.bend): one `+` arg, then the LIST as a plain
# binder, then the shrinking tail. The first attempt had `line: String` between
# them, and a String is not a list so the binder was read as "nothing shrinks" --
# "expected : a decreasing self-call", not a type error, which is the unhelpful way
# to say it.
# ONE DEF. There were three -- `step` -> `line` -> `head` -- and every arrangement
# of them was either MUTUALLY recursive (Bend refuses) or an R-3 ordering problem
# (whichever called the other had to be declared first). This is `s5.seps.go`'s
# shape verbatim (ops.bend): one `+` arg, the list as a plain binder, the shrinking
# tail, and the accumulator threaded through.
# ONE FOLD AND ONE EMITTER, in that order because the fold CALLS the emitter and
# R-3 wants the callee first. There were three defs before this and every
# arrangement was either mutually recursive (Bend refuses) or an ordering problem.
# The shape is `s5.seps.go` (ops.bend) with the print lifted into its own def only
# because a `do IO<Unit>` block cannot be an expression.
# the FOLD returns a string and the print happens once, which is `Bsl.row`'s shape
# (ops.bend) and the reason none of the previous four arrangements worked.
#
# A printing fold cannot be written as one def here. `s5.seps.go` recurses fine
# because it RETURNS a String; putting `IO.print` in the match arm needs a `do
# IO<Unit>` block, and the recursion then has to leave that block for a def that
# returns IO, and THAT def has no shrinking argument left. Five attempts:
# three mutually-recursive defs, one self-call with nothing shrinking, and one with
# a String where the binder had to be a list.
#
# So: fold to a String, join, print once. The fold is `s5.seps.go` with a newline
# instead of a space, and `IO.print` is one call at the end.
# the row name goes on every line, not once on the first. It went on the first as a
# `String.concat([nm, "|", ...])` wrapped around the WHOLE fold, which reads the same for
# a one-node row and is wrong for every row after it: `pu_constarg` printed its first
# CONST named and its second CONST bare, so the diff had one line to compare and one it
# could not name. The prefix is inside the fold for that reason, and `nm` is a `+`
# parameter because the fold reads it once per line.
