<!-- FROM: tinybendygrad/codegen/late/linearizer.bend:147 -->
# BLOCK:
# THE GATE. Every row is DERIVED FROM PYTHON by the oracle named at the foot; the
# interpreted lane, the native lane and CPython must print the same rows in the
# same order, so
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
# The per-UOP gate shape and the two identity rows are described here; regalloc's
# half of the same paragraph is in `regalloc.bend`'s header.
#
# END BLOCK

# THE GATE. Every row is DERIVED FROM PYTHON by the oracle named at the foot; the
# interpreted lane, the native lane and CPython must print the same rows in the
# same order, so
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
# The per-UOP gate shape and the two identity rows are described here; regalloc's
# half of the same paragraph is in `regalloc.bend`'s header.
#
