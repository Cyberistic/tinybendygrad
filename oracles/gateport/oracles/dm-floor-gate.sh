#!/bin/sh
# The gate for the `helpers.bend` div/mod block: run `.agents/slop/dm.bend` in
# BOTH lanes, run the CPython oracle, and diff the `ok_` rows.
#
#   .agents/slop/tools/dm-floor-gate.sh
#
# Green means the Bend answers and `tinygrad.helpers` agree, in the interpreted
# lane AND the compiled one, on every `ok_` row. The `bad_` rows are reported and
# excluded, because they are the known-wrong `ceildiv_i32`; if one of them ever
# starts AGREEING with the oracle, that is reported too, because it means the
# hole closed and the row should be promoted to `ok_`.
set -e
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$REPO" || exit 1

BEND="$REPO/bin/bend"
SRC=.agents/slop/dm.bend
PY=.agents/slop/dm-floor-probe.py
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$BEND" "$SRC" > "$TMP/interp.txt"
"$BEND" "$SRC" -o "$TMP/native" > /dev/null
"$TMP/native" > "$TMP/nat.txt"
if ! diff -q "$TMP/interp.txt" "$TMP/nat.txt" > /dev/null; then
  echo "FAIL: the two lanes disagree"
  diff "$TMP/interp.txt" "$TMP/nat.txt"
  exit 1
fi
.venv/bin/python "$PY" > "$TMP/py.txt"

status=0

# every ok_ row must match
grep '^ok_' "$TMP/interp.txt" > "$TMP/a.txt" || true
grep '^ok_' "$TMP/py.txt"    > "$TMP/b.txt" || true
if diff -u "$TMP/b.txt" "$TMP/a.txt" > "$TMP/ok.diff"; then
  echo "ok_ rows: $(wc -l < "$TMP/a.txt" | tr -d ' ') match tinygrad.helpers"
else
  echo "FAIL: the ok_ rows disagree with tinygrad.helpers"
  cat "$TMP/ok.diff"
  status=1
fi

# the bad_ rows are expected to disagree; say so, and say when one stops
grep '^bad_' "$TMP/interp.txt" > "$TMP/c.txt" || true
grep '^bad_' "$TMP/py.txt"    > "$TMP/d.txt" || true
if diff -q "$TMP/c.txt" "$TMP/d.txt" > /dev/null; then
  echo "NOTE: the bad_ceildiv rows now AGREE with the oracle -- ceildiv_i32 is"
  echo "      fixed. Promote them to ok_ in $SRC and $PY."
else
  echo "known-wrong (excluded, ceildiv_i32 negates both operands):"
  diff "$TMP/d.txt" "$TMP/c.txt" | sed 's/^/  /' || true
fi

echo "lanes: identical"
exit $status
