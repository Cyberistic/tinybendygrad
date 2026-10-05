# THE PLANT / DISARM TRANSCRIPT -- `compute_gradient`'s walk
# ==============================================================================
# PORT    tinybendygrad/mixin/gradient.bend
# HARNESS sh checks/walk-mutate.sh <arm>
#          arms: base plant_reverse plant_noguard disarm_comment disarm_name
#
# EVERY ARM RUNS IN `$TMPDIR/walkplant` OVER A REAL `cp -R` OF THE WHOLE TREE (notes T-2:
# a symlink mirror breaks hub detection and then refuses an ordinary
# `import ./helpers.bend` with the mirror's error).  **THE LIVE TREE IS NEVER PATCHED**,
# and that is checked, not asserted: the sha256 below is the live file AFTER all five arms
# and it equals the base's.
#
#   live tinybendygrad/mixin/gradient.bend
#     sha256 2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49
#   ...identical to the `base` arm's working copy, and
#   `diff <base run> <live run>` is empty (88 rows both, byte for byte).
#
# ------------------------------------------------------------------------------
# THE DIFFER: WHOLE `name=value` LINES, NEVER ROW NAMES
# ------------------------------------------------------------------------------
# agent-core records that a name-comparing harness "reported 0 for all 30 mutations in one
# unit and 0 for all 68 in another".  This one `diff`s two whole runs and prints the
# changed lines.  And it has been SHOWN TO FAIL: both plants below move it, and before
# them `disarm_name` reported "0 rows moved" for a mutant that had not applied at all --
# which is what the next section is about.
#
################ ARM base
=== arm=base  live tree NOT touched; working copy sha256=2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49
=== arm=base  check-only: ALL PROOFS CHECK
=== arm=base  run rc=0  rows=88
walk_row=MUL/2 ADD/2 ADD/2 | grads_n=6
walk_sig=MUL/2 ADD/2 ADD/2
walk_inpath=0 0 1 0 1 1
walk_keys=ADD/2 MUL/2 ADD/2 BUFFER/0 BUFFER/0 BUFFER/0
walk_grad_a=5 root=ADD/2
walk_grad_b=4 root=MUL/2
walk_grad_c=2 root=CAST/1
walk_grad_p=2 root=CAST/1
walk_grad_q=2 root=CAST/1
walk_grad_r=2 root=CAST/1
walk_n_toposort=6
walk_walk_n=3
walk_n_inpath=3
walk_grads_n=6
walk_skip_n=0
walk_hole_n=0
=== DIFFER vs base (whole name=value lines, NOT row names):
    (this IS the base; persisted at /var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T//walkbase.txt)

################ ARM plant_reverse
=== arm=plant_reverse  live tree NOT touched; working copy sha256=2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49
    plant_reverse: reversed(walk) -> walk: applied and VERIFIED (the file on disk differs and contains the new text)
=== arm=plant_reverse  check-only: ALL PROOFS CHECK
=== arm=plant_reverse  run rc=0  rows=88
walk_row=MUL/2 ADD/2 ADD/2 | grads_n=3
walk_sig=MUL/2 ADD/2 ADD/2
walk_inpath=0 0 1 0 1 1
walk_keys=ADD/2 MUL/2 ADD/2
walk_grad_a=NONE
walk_grad_b=NONE
walk_grad_c=NONE
walk_grad_p=2 root=CAST/1
walk_grad_q=2 root=CAST/1
walk_grad_r=2 root=CAST/1
walk_n_toposort=6
walk_walk_n=3
walk_n_inpath=3
walk_grads_n=3
walk_skip_n=2
walk_hole_n=0
=== DIFFER vs base (whole name=value lines, NOT row names):
    sha256 of the planted file: 3af788f3aa2ec68093abe898211b02280032a225ec2babe98ab6d09636b9cbf0  (base was 2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49)
    sha256 of the port's OUTPUT: 134decef6204f7399e9dd17a0789b69ac95284300ac9038ebb42f7c6d04e275f
    sha256 of the BASE OUTPUT : 8df45cb71916a63f8f550e1027183b96e7be771f492c641fee816265a31244de
    rows that MOVED: 7
    < walk_row=MUL/2 ADD/2 ADD/2 | grads_n=6
    > walk_row=MUL/2 ADD/2 ADD/2 | grads_n=3
    < walk_keys=ADD/2 MUL/2 ADD/2 BUFFER/0 BUFFER/0 BUFFER/0
    < walk_grad_a=5 root=ADD/2
    < walk_grad_b=4 root=MUL/2
    < walk_grad_c=2 root=CAST/1
    > walk_keys=ADD/2 MUL/2 ADD/2
    > walk_grad_a=NONE
    > walk_grad_b=NONE
    > walk_grad_c=NONE
    < walk_grads_n=6
    < walk_skip_n=0
    > walk_grads_n=3
    > walk_skip_n=2

################ ARM plant_noguard
=== arm=plant_noguard  live tree NOT touched; working copy sha256=2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49
    plant_noguard: in_target_path[node] -> True{}: applied and VERIFIED (the file on disk differs and contains the new text)
=== arm=plant_noguard  check-only: ALL PROOFS CHECK
=== arm=plant_noguard  run rc=0  rows=88
walk_row=BUFFER/0 BUFFER/0 MUL/2 BUFFER/0 ADD/2 ADD/2 | grads_n=6
walk_sig=BUFFER/0 BUFFER/0 MUL/2 BUFFER/0 ADD/2 ADD/2
walk_inpath=0 0 1 0 1 1
walk_keys=ADD/2 MUL/2 ADD/2 BUFFER/0 BUFFER/0 BUFFER/0
walk_grad_a=5 root=ADD/2
walk_grad_b=4 root=MUL/2
walk_grad_c=2 root=CAST/1
walk_grad_p=2 root=CAST/1
walk_grad_q=2 root=CAST/1
walk_grad_r=2 root=CAST/1
walk_n_toposort=6
walk_walk_n=6
walk_n_inpath=3
walk_grads_n=6
walk_skip_n=0
walk_hole_n=0
=== DIFFER vs base (whole name=value lines, NOT row names):
    sha256 of the planted file: 89c7f60d0aac26d130e273544d96a528c6126be7198827beda424e13f8b11830  (base was 2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49)
    sha256 of the port's OUTPUT: 3a61b7e4133f08d02262c0f5b876d241bc4a1a9f41ddbdd40ee706a1048379c3
    sha256 of the BASE OUTPUT : 8df45cb71916a63f8f550e1027183b96e7be771f492c641fee816265a31244de
    rows that MOVED: 3
    < walk_row=MUL/2 ADD/2 ADD/2 | grads_n=6
    < walk_sig=MUL/2 ADD/2 ADD/2
    > walk_row=BUFFER/0 BUFFER/0 MUL/2 BUFFER/0 ADD/2 ADD/2 | grads_n=6
    > walk_sig=BUFFER/0 BUFFER/0 MUL/2 BUFFER/0 ADD/2 ADD/2
    < walk_walk_n=3
    > walk_walk_n=6

################ ARM disarm_comment
=== arm=disarm_comment  live tree NOT touched; working copy sha256=2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49
    disarm_comment: comment text: applied and VERIFIED (the file on disk differs and contains the new text)
=== arm=disarm_comment  check-only: ALL PROOFS CHECK
=== arm=disarm_comment  run rc=0  rows=88
walk_row=MUL/2 ADD/2 ADD/2 | grads_n=6
walk_sig=MUL/2 ADD/2 ADD/2
walk_inpath=0 0 1 0 1 1
walk_keys=ADD/2 MUL/2 ADD/2 BUFFER/0 BUFFER/0 BUFFER/0
walk_grad_a=5 root=ADD/2
walk_grad_b=4 root=MUL/2
walk_grad_c=2 root=CAST/1
walk_grad_p=2 root=CAST/1
walk_grad_q=2 root=CAST/1
walk_grad_r=2 root=CAST/1
walk_n_toposort=6
walk_walk_n=3
walk_n_inpath=3
walk_grads_n=6
walk_skip_n=0
walk_hole_n=0
=== DIFFER vs base (whole name=value lines, NOT row names):
    sha256 of the planted file: b9a14fa05697cb56fe9d70c4fdf3ac9c378464939851f35d64ece45bb0ad9e57  (base was 2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49)
    sha256 of the port's OUTPUT: 8df45cb71916a63f8f550e1027183b96e7be771f492c641fee816265a31244de
    sha256 of the BASE OUTPUT : 8df45cb71916a63f8f550e1027183b96e7be771f492c641fee816265a31244de
    rows that MOVED: 0

################ ARM disarm_name
=== arm=disarm_name  live tree NOT touched; working copy sha256=2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49
    disarm_name: parameter tok -> tok_renamed_for_disarm (signature): applied and VERIFIED (the file on disk differs and contains the new text)
    disarm_name: parameter tok -> tok_renamed_for_disarm (body): applied and VERIFIED (the file on disk differs and contains the new text)
=== arm=disarm_name  check-only: ALL PROOFS CHECK
=== arm=disarm_name  run rc=0  rows=88
walk_row=MUL/2 ADD/2 ADD/2 | grads_n=6
walk_sig=MUL/2 ADD/2 ADD/2
walk_inpath=0 0 1 0 1 1
walk_keys=ADD/2 MUL/2 ADD/2 BUFFER/0 BUFFER/0 BUFFER/0
walk_grad_a=5 root=ADD/2
walk_grad_b=4 root=MUL/2
walk_grad_c=2 root=CAST/1
walk_grad_p=2 root=CAST/1
walk_grad_q=2 root=CAST/1
walk_grad_r=2 root=CAST/1
walk_n_toposort=6
walk_walk_n=3
walk_n_inpath=3
walk_grads_n=6
walk_skip_n=0
walk_hole_n=0
=== DIFFER vs base (whole name=value lines, NOT row names):
    sha256 of the planted file: 3116769b4cdbedc4fc65aa756e361d1bb2e829fd09be5ba5c37bc2015ad800ce  (base was 2ca4578675b4196168edf89ea331ffd989eb50f01d18a5048b7a57619702df49)
    sha256 of the port's OUTPUT: 8df45cb71916a63f8f550e1027183b96e7be771f492c641fee816265a31244de
    sha256 of the BASE OUTPUT : 8df45cb71916a63f8f550e1027183b96e7be771f492c641fee816265a31244de
    rows that MOVED: 0


# ------------------------------------------------------------------------------
# THE SUMMARY, AND THE ONE NUMBER THAT MATTERS
# ------------------------------------------------------------------------------
# | arm            | port file sha256 changed | rows moved | `walk_row` moved |
# |----------------|--------------------------|------------|-------------------|
# | base           | --                       | --         | --                |
# | plant_reverse  | YES (3af788f3 vs 2ca45786)| **7**      | YES, names itself|
# | plant_noguard  | YES (89c7f60d vs 2ca45786)| **3**      | YES, names itself|
# | disarm_comment | YES (b9a14fa0 vs 2ca45786)| 0          | no (correct)      |
# | disarm_name    | YES (3116769b vs 2ca45786)| 0          | no (correct)      |
#
# *** PLANT 2 IS WHY THE ROW IS A SIGNATURE AND NOT A COUNT. *** `plant_noguard` drops
# `in_target_path[node]` from gradient.py:114's filter and `walk_grads_n` **STAYS AT 6** --
# the count is genuinely right, because every target does receive a gradient either way.
# Only `walk_sig` moves (`MUL/2 ADD/2 ADD/2` -> `BUFFER/0 BUFFER/0 MUL/2 BUFFER/0 ADD/2
# ADD/2`) and `walk_walk_n` moves 3 -> 6.  A gate carrying only the count would have
# reported this mutant as GREEN.  That is the whole argument for the signature half, and it
# is measured here rather than asserted.
#
# PLANT 1 is the opposite and is the argument for the COUNT half: `walk_sig` stays green
# under it (`_deepwalk` is untouched by `reversed`, correctly), and only the loop's own
# rows move -- `grads_n` 6 -> 3, `skip_n` 0 -> 2, and `walk_grad_a/b/c` -> `NONE`.
# So neither half alone would do: the signature is blind to a reversed walk and the count is
# blind to a dropped inpath guard.  `walk_row` carries BOTH and moves under both.
#
# ------------------------------------------------------------------------------
# THE DISARMS, AND WHY THEY ARE NOT VACUOUS
# ------------------------------------------------------------------------------
# `disarm_comment` appends text to one comment line; `disarm_name` renames the parameter
# `tok` to `tok_renamed_for_disarm` in `dag_join`'s signature AND in its body.  Both leave
# the port's OUTPUT sha256 byte-identical to the base's
# (`8df45cb71916a63f8f550e1027183b96e7be771f492c641fee816265a31244de`) while the port's FILE
# sha256 changes -- which is the difference between "nothing moved" and "nothing moved
# because nothing was done", and the project's own history says assuming the latter is how
# six lanes once looked armed and one was not.
#
# ------------------------------------------------------------------------------
# MY HARNESS WAS VACUOUS TWICE, AND THE ASSERTION IS WHAT CAUGHT IT
# ------------------------------------------------------------------------------
# 1. **THE FIRST VERSION NEVER CALLED `s.replace`.**  It computed `n = s.count(old)`,
#    printed `1 occurrence(s) replaced (expect 1)` and exited 0 -- and the file was
#    UNCHANGED.  `plant_reverse` and `plant_noguard` both reported "rows that MOVED: 0" for a
#    mutant that had never applied.  **That is the exact failure this unit's brief warns
#    about** ("two units this session published a green mutation for a mutant that never
#    applied"), and I produced it in my own harness.  Counting is not editing.
# 2. **THE ASSERTION `old in back` IS TRUE FOR ANY `new` THAT EXTENDS `old`**, so the
#    re-read check rejected a perfectly good comment edit.  The assertion is now THE BYTES:
#    the file on disk must DIFFER from the file that was read and must CONTAIN the new text.
# 3. **A THIRD, DIFFERENT ONE: A CONCURRENT EDIT.**  The first `disarm_comment` run printed
#    `INCONCLUSIVE (T-1): the substrate failed, not the code` with
#    `ops.bend:3972 case _ <: t: pm_try_f(...)` -- `uop/ops.bend` is ANOTHER UNIT'S FILE and
#    was mid-edit (the live `ops.bend` at that moment did not even compile: `expected : Bool,
#    observed : Sigma<..., Map<&2, U32>, _ => Bool>`).  Reading that as a wall would have
#    been the fourth false obstruction of this session, so the harness prints stderr and says
#    INCONCLUSIVE instead of reporting a verdict.  All five arms above were re-run after the
#    substrate settled.
#
# ------------------------------------------------------------------------------
# WHAT A PLANT WITH NO DISARM COULD NOT HAVE PROVEN HERE
# ------------------------------------------------------------------------------
# `plant_noguard` moves `walk_sig`, `walk_walk_n` and `walk_row`, and moves NOTHING in the
# 72 pre-existing rows.  So "the gate went red" on its own would not have said the walk is
# what moved -- `walk_sig` is a new row, so of course it is the thing that moves.  The
# disarms are what say the differ is looking at the walk and not at something incidental,
# and `walk_grads_n`-under-`plant_noguard` is what says the count is not the whole story.
