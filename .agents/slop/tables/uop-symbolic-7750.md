<!-- FROM: tinybendygrad/uop/symbolic.bend:7750 -->
# BLOCK:
# ---- THE FIXTURES FOR TAGS 13..22, one per rule and a NEGATIVE one per rule whose
# ---- identity check or guard is load-bearing. Every index is stated so a row that
# ---- reads a wrong one says so.
#
# `f_bin` is the fixture-half of a trap this file's header names and that bit three
# of the fixtures below before it was written down. A node must be interned in an
# arena that ALREADY HOLDS every src it names: `f_alu2(+f, op, b)` builds in
# `Found.ar(f)`, so `f_alu2(c, op, f_i(d))` with `d` minted after `c` puts the node
# on the slot `d` was about to take and gives it a SELF-EDGE -- the node count comes
# out one short, the last node answers `nsrc = 0`, and the row silently asks about
# a node that does not exist. `f_bin` takes the arena, so the last construction in
# every fixture names it explicitly.
# END BLOCK

# ---- THE FIXTURES FOR TAGS 13..22, one per rule and a NEGATIVE one per rule whose
# ---- identity check or guard is load-bearing. Every index is stated so a row that
# ---- reads a wrong one says so.
#
# `f_bin` is the fixture-half of a trap this file's header names and that bit three
# of the fixtures below before it was written down. A node must be interned in an
# arena that ALREADY HOLDS every src it names: `f_alu2(+f, op, b)` builds in
# `Found.ar(f)`, so `f_alu2(c, op, f_i(d))` with `d` minted after `c` puts the node
# on the slot `d` was about to take and gives it a SELF-EDGE -- the node count comes
# out one short, the last node answers `nsrc = 0`, and the row silently asks about
# a node that does not exist. `f_bin` takes the arena, so the last construction in
# every fixture names it explicitly.
