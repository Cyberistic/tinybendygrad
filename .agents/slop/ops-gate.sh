#!/bin/sh
# ops-gate.sh -- run BOTH lanes of tinybendygrad/uop/ops.bend and diff them against the
# CPython oracle. Every step is `set -e`, so the script fails loudly.
#
#   sh .agents/slop/ops-gate.sh
#
# THREE LANES and they must agree byte for byte:
#
#   py    CPython, .venv/bin/python .agents/slop/ops-oracle.py
#   bd    the interpreted lane, ./bin/bend tinybendygrad/uop/ops.bend
#   bn    the NATIVE lane, compiled with -o and then run
#
# `--check-only` is run first: it is the fastest way to find a proof failure and it needs
# no device either. READ THE FIRST LINE, NOT THE EXIT STATUS -- `--check-only` exits 1 on
# a file with no unfilled laws too, which is why `set -e` is NOT applied to it.
#
# WHY THIS FILE HAD NO CPYTHON LANE AND NOW HAS ONE. `tinybendygrad/uop/ops.bend` shipped
# with 22 rows and `cpython=0`, and the thing `78d482262` changed -- `AxisType` -- was not
# read by any of them. Four of the eight surviving `AxisType.value`s were wrong against
# the new tree, `axis_id`/`axis_type` were the wrong way round, and `axis_to_pos` no
# longer existed. This script is the gate that sees all three.
#
# WHICH TREE. `TG_TREE` picks it, and it is the whole point:
#
#   sh .agents/slop/ops-gate.sh                  # upstream (the rebase target)
#   TG_TREE=. sh .agents/slop/ops-gate.sh         # the vendored pin
#
# so the same script diffs the port against both, and the two answers differ in exactly
# the rows upstream moved. `.agents/slop/opstree/` is a `git archive upstream/master
# tinygrad` snapshot, because the vendored `tinygrad/` is the PIN and the pin is the thing
# that drifted.
#
# THE BEND-ONLY ROWS ARE FILTERED BY NAME, NEVER BY POSITION, and every one of them has a
# `#bend_only_<name>=<reason>` line in the oracle. Filtering by position is what silently
# drops a row that MOVED; filtering by name cannot. The list is:
#
#   rngarg_*        the ARange FIELD ORDER -- the pin's (ids, at) vs upstream's (at, ids).
#                   Eleven committed files destructure `ARange` positionally, so the
#                   field order cannot move in this file alone. See the block above
#                   `UOp.range_end`.
#   axv_/axn_/axl_/axc_REDUCE and _UNROLL
#                   AxisType.REDUCE and .UNROLL are DELETED upstream and six committed
#                   files still construct them, three of them under `codegen/opt/*`.
#   rngspec_*       `tinygrad/uop/spec.py`'s matcher, which is P3 and not ported. The
#                   oracle prints it because the PREDICATE moved with the flip.
#   axlt_le/ge      CPython raises TypeError; upstream added `__lt__` and not `__le__`.
#   axlt_dunder     introspection of a Python class body.
#   xpos/xpos_names hasattr on a Python MODULE.
#   the 9 old Booleans -- float_zeros_differ, float_nan_interns, cycle, cycle_terminates,
#                   ler_len, early_reject, broadcast_repeats, required_len, alu_permutes.
#                   Each names a thing CPython cannot be asked for (F32 bits, the arena's
#                   fuel, a UPat, a PatternMatcher rule) and the oracle says which.
#
# AND ONE CHECK THAT IS NOT A ROW. `axis_to_pos` was DELETED from the port, and a def
# Bend cannot print as "absent" is exactly the case where a comment is not a gate -- so the
# script greps the source for the symbol and fails if it is still there. That is the only
# way a DELETION is checked here.
set -e
cd "$(dirname "$0")/../.."

OUT=.agents/slop/oracles
F="$OUT/ops"

# `--check-only` exits 1 even on a clean file (dtype.bend's 14 unfilled laws). Read the
# FIRST line, never the status: `SOME PROOFS FAIL` naming anything but those 14 is the
# failure and `set -e` is deliberately not applied here.
./bin/bend tinybendygrad/uop/ops.bend --check-only | head -1

# A deleted symbol that a comment claims is deleted. `--` ends the option list so a path
# beginning with `-` cannot become a flag.
if grep -q -- 'axis_to_pos' tinybendygrad/uop/ops.bend; then
  # The header NAMES the symbol when it explains the deletion, so the check is for a
  # DEFINITION, not for the word: `def axis_to_pos` or `type Pos` are what must be gone.
  if grep -qE '^(def axis_to_pos|type Pos)' tinybendygrad/uop/ops.bend; then
    echo "ops-gate: axis_to_pos is DELETED upstream but is still DEFINED here" >&2
    exit 1
  fi
fi

# BEND_ONLY is derived from the oracle's own `#bend_only_*` reasons, so the two cannot
# drift: a row that gains a reason gains a filter entry without anyone editing this file.
# It is joined with `|` and NOT left newline-separated -- a newline inside a `grep -E`
# pattern makes grep read the rest as a filename, which is a silent no-filter. The match
# is a PREFIX, not `name=`, because two families are prefixes (`rngarg_*`, `rngspec_*`)
# and one is a prefix of another (`cycle` of `cycle_terminates`). Both are bend-only and
# both are listed, so prefix matching cannot hide a row that is not already accounted for.
BEND_ONLY_NAMES=$(.venv/bin/python .agents/slop/ops-oracle.py | sed -n 's/^#bend_only_\([a-zA-Z_]*\)=.*/\1/p' | sort -u)
BEND_ONLY=$(echo "$BEND_ONLY_NAMES" | awk '{printf "%s^%s", (n++ ? "|" : ""), $0}')

# WHAT IS FILTERED AND WHY. `BEND_ONLY` is the bend-only ROW FAMILIES. The two explicit
# prefixes are oracle-only COMMENT lines: `#shared_tree` names the tree the oracle read,
# and the `#bend_only_*` lines are the reasons themselves. NOTHING ELSE is filtered --
# in particular the `#shared_axis_*` rows are NOT comments but GATED rows, because they
# are the member list, the value sequence, the count and the sort, and a lane that
# dropped them would agree about the wrong number of axis types.
filter() { grep -vE "^#shared_tree|^#bend_only|$BEND_ONLY"; }

.venv/bin/python .agents/slop/ops-oracle.py | filter > "$F-py.txt"
./bin/bend tinybendygrad/uop/ops.bend | filter > "$F-bd.txt"
./bin/bend tinybendygrad/uop/ops.bend -o "$F.bin"
"$F.bin" | filter > "$F-bn.txt"

diff "$F-py.txt" "$F-bd.txt"
diff "$F-py.txt" "$F-bn.txt"

echo "ops-gate: $(wc -l < "$F-py.txt" | tr -d ' ') shared rows, 3 lanes identical"
echo "ops-gate: $(echo "$BEND_ONLY_NAMES" | wc -l | tr -d ' ') bend-only row families, each with a #bend_only_ reason in the oracle"
echo "ops-gate: total bend rows = $(./bin/bend tinybendygrad/uop/ops.bend | grep -vc '^#')"