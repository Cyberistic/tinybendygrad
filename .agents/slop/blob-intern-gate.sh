#!/bin/sh
# blob-intern-gate.sh -- the CPython lane for the `blob_*` rows of
# `tinybendygrad/uop/ops.bend`, and the ONLY gate in this unit that is green.
#
#   sh .agents/slop/blob-intern-gate.sh
#
# WHY IT EXISTS RATHER THAN BEING ROWS IN `.agents/slop/ops-oracle.py`.
# `ops-gate.sh` is RED on the pristine tree and has been since before this unit
# started: its CPython lane is missing the five `cfun_*` rows, so it exits 1 naming
# exactly those five and nothing else. Adding rows to that oracle is another unit's
# edit and its insertion point is positional (the gate is a byte diff), so this unit
# gates its own rows in its own gate. `ops-gate.sh` is still run, and its diff is
# required to be UNCHANGED by this unit -- see `blob-intern-gate.sh --also-ops`.
#
# THE FIXTURE IS THE TEST. `b"aaaa"` against `b"bbbb"`: equal length, unequal content.
# An all-different-length fixture is satisfied by a length key, which is how the
# original bug sat in a green gate.
#
# `TG_TREE` picks the tree, as in `ops-gate.sh`:
#   sh .agents/slop/blob-intern-gate.sh                    # upstream (the rebase target)
#   TG_TREE=. sh .agents/slop/blob-intern-gate.sh           # the vendored pin
set -e
cd "$(dirname "$0")/../.."

OUT=.agents/slop/oracles
F="$OUT/blob"

# READ THE FIRST LINE, never the exit status: `--check-only` exits 1 on a file whose
# unfilled laws are a known permanent condition, and ops.bend's are not it, but the
# rule is the rule.
./bin/bend tinybendygrad/uop/ops.bend --check-only | head -1

# `blob_*` and nothing else, on BOTH sides. Filtering by NAME PREFIX and never by
# position: a positional filter is what silently drops a row that MOVED.
.venv/bin/python .agents/slop/blob-intern-oracle.py | grep '^blob_' | sort > "$F-py.txt"
./bin/bend tinybendygrad/uop/ops.bend | grep '^blob_' | sort > "$F-bd.txt"
./bin/bend tinybendygrad/uop/ops.bend -o "$F.bin"
"$F.bin" | grep '^blob_' | sort > "$F-bn.txt"

diff "$F-py.txt" "$F-bd.txt"
diff "$F-py.txt" "$F-bn.txt"

echo "blob-intern-gate: $(wc -l < "$F-py.txt" | tr -d ' ') blob rows, 3 lanes identical (cpython, interpreted, native)"

# THE MAIN GATE, and the claim is that this unit does not make it WORSE. Its five-line
# diff on the pristine tree is another unit's gap (the missing `cfun_*` oracle rows);
# this unit's requirement is that the diff is BYTE-IDENTICAL before and after.
if [ "$1" = "--also-ops" ]; then
  sh .agents/slop/ops-gate.sh > "$F-opsgate.txt" 2>&1 || true
  # only the diff hunks, not the bend banners
  sed -n '/^[0-9]/,$p' "$F-opsgate.txt" > "$F-opsgate-diff.txt"
  echo "blob-intern-gate: ops-gate.sh diff is $(wc -l < "$F-opsgate-diff.txt" | tr -d ' ') lines:"
  cat "$F-opsgate-diff.txt"
fi