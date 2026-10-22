# gates/opname-census-fragment.bend -- THE FRAGMENT FIXTURE for `gates/opname-census-gate.py --plant`.
#
# IT IS A FRAGMENT ON PURPOSE, AND A FRAGMENT IS A SHAPE AND NOT A FILENAME.  Its statements are
# bare and at TOP LEVEL, where a `def`, a `type` or a `law` belongs, so the compiler refuses it
# at its first statement with
#
#     - expected : 'def', 'type' or 'law'
#     - observed : 'f'
#
# and that refusal is the file's OWN STANDING CONDITION.  `oracles/lift-rows.bend` is a REAL
# fragment in this tree with this shape; this one is the gate's OWN, so the plant does not read
# a file another unit may be editing.
#
# ⇒ AND THE SHAPE IS WHY THE CLASS EXISTS.  A FRAGMENT CANNOT BE COMPILED, so the compiler
# never reaches the row that names a deleted op -- and a stale name in a fragment is therefore
# INVISIBLE to every compile check in this tree.  It is LATENT: it is one fix of the fragment's
# own standing condition away from being the thing that breaks it.  A census that reported the
# name without saying that would be a census of names.
#
# THE ROW BELOW IS THE ANCHOR, and it names a DECLARED member, so this file is not a finding.
# The plant replaces it with `O.OpsFLIP{}` -- the op upstream DELETED in
# `900880433 remove Ops.FLIP [pr] (#18729)` (2026-10-11) -- and the census must report the
# planted file as COMPILE-LATENT-STALE, because the fragment's own standing condition is what
# the compiler reports.
frag_row("add_int32_3_4", O.OpsADD{})
