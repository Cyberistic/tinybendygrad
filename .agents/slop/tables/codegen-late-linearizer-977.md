<!-- FROM: tinybendygrad/codegen/late/linearizer.bend:977 -->
# BLOCK:
# the gate, part one: the linearizer. Every row is derived from python by
# /tmp/opencode/late-oracle.py, which drives tinygrad/codegen/late/linearizer.py
# over this exact fixture and prints its rows in THIS ORDER and with THIS
# SPELLING, so
#   diff <(.venv/bin/python gates/linearizer_census-oracle.py) <(./bin/bend tinybendygrad/codegen/late/linearizer.bend)
# is the acceptance test and NEITHER side can be nudged to match the other.
# both sides of that line were wrong and the oracle is now named. It read
# `python3 /tmp/opencode/late-oracle.py`, which has never existed, against
# `tinybendygrad/codegen/late.bend`, which the port moved INTO `late/` as this file --
# MEASURED 2026-10-16: `late-oracle.py` is absent at every path on every ref
# (`git rev-list --all --objects` names it zero times) and `tinybendygrad/codegen/late.bend`
# was `D` in this tree's history. The oracle that replaced it is
# `gates/linearizer_census-oracle.py`, which is 71 rows, RUNS (rc=0), and READS THIS FILE.
# `oracles/tinybendygrad_codegen_late.bend.rows` is ALSO in HEAD at 128 rows and is NOT in
# `differ.declared()` and has NO CODE READER -- a snapshot with neither a generator nor a
# consumer, reported rather than deleted, because deleting it is not this unit's call.
#
# THE PRINTERS, LEAF FIRST, and there are two because two row classes need two
# alphabets: a `U32` list (`ix`, `lin_nkey`) and a `String` list (`lin_srcs`). A
# shared printer is a shared FORMAT CONTRACT (the notes' rule 22) -- a mutation in
# one invalidates a quarter of the suite, which is the right trade, and it is why
# `lt_u32s` is written once and not three times.
# END BLOCK

# the gate, part one: the linearizer. Every row is derived from python by
# /tmp/opencode/late-oracle.py, which drives tinygrad/codegen/late/linearizer.py
# over this exact fixture and prints its rows in THIS ORDER and with THIS
# SPELLING, so
#   diff <(.venv/bin/python gates/linearizer_census-oracle.py) <(./bin/bend tinybendygrad/codegen/late/linearizer.bend)
# is the acceptance test and NEITHER side can be nudged to match the other.
# both sides of that line were wrong and the oracle is now named. It read
# `python3 /tmp/opencode/late-oracle.py`, which has never existed, against
# `tinybendygrad/codegen/late.bend`, which the port moved INTO `late/` as this file --
# MEASURED 2026-10-16: `late-oracle.py` is absent at every path on every ref
# (`git rev-list --all --objects` names it zero times) and `tinybendygrad/codegen/late.bend`
# was `D` in this tree's history. The oracle that replaced it is
# `gates/linearizer_census-oracle.py`, which is 71 rows, RUNS (rc=0), and READS THIS FILE.
# `oracles/tinybendygrad_codegen_late.bend.rows` is ALSO in HEAD at 128 rows and is NOT in
# `differ.declared()` and has NO CODE READER -- a snapshot with neither a generator nor a
# consumer, reported rather than deleted, because deleting it is not this unit's call.
#
# THE PRINTERS, LEAF FIRST, and there are two because two row classes need two
# alphabets: a `U32` list (`ix`, `lin_nkey`) and a `String` list (`lin_srcs`). A
# shared printer is a shared FORMAT CONTRACT (the notes' rule 22) -- a mutation in
# one invalidates a quarter of the suite, which is the right trade, and it is why
# `lt_u32s` is written once and not three times.
