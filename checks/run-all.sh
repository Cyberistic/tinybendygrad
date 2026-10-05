#!/bin/zsh
# run-all.sh -- EVERY number in CSTYLE2.md, from a clean $TMPDIR, with one command.
#
#   zsh checks/run-all.sh
#
# THE TREE IS SNAPSHOTTED, NOT PATCHED. `tinybendygrad/` is copied whole into $TMPDIR and
# every bend run in this unit executes against the COPY, because a `$TMPDIR` single-file
# scratch copy cannot resolve a relative import and `renderer/cstyle.bend` imports half the
# tree. The live tree's hash is printed before and after and asserted equal, so "nothing was
# planted in the live tree" is a measurement and not a promise.
set -euo pipefail
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
export REPO
W=${W:-${TMPDIR:-/tmp}/cstyle2}
export W
HERE=$(cd "$(dirname "$0")" && pwd)
SNAP_CSTYLE=tinybendygrad/renderer/cstyle.bend

echo "=== repo $REPO"
echo "=== work $W"
rm -rf "$W"; mkdir -p "$W/tree"
cp -R "$REPO/tinybendygrad" "$W/tree/"
[ -f "$W/tree/$SNAP_CSTYLE" ] || { echo "snapshot incomplete: $SNAP_CSTYLE missing. REFUSING."; exit 2; }
live=$(shasum -a 256 "$REPO/$SNAP_CSTYLE" | cut -d' ' -f1)
snap=$(shasum -a 256 "$W/tree/$SNAP_CSTYLE" | cut -d' ' -f1)
echo "=== live  $SNAP_CSTYLE $live"
echo "=== snap  $SNAP_CSTYLE $snap"
[ "$live" = "$snap" ] || { echo "the copy is not byte-identical to the live file. REFUSING."; exit 2; }

step () { echo; echo "######## $1"; }

step "0  the tree runs at all"
( cd "$REPO" && ./bin/bend "$W/tree/$SNAP_CSTYLE" > "$W/port.txt" 2> "$W/port.err" )
echo "bend rc=$?  rows on stdout: $(wc -l < "$W/port.txt" | tr -d ' ')"
cat "$W/port.err"

step "1  the DENOMINATOR, derived from main() and not transcribed"
python3 "$HERE/derive.py" "$W/tree/$SNAP_CSTYLE" "$W/port.txt" | tee "$W/derive.txt"

step "2  the FOUR COLUMNS + the CAUSE of every non-C row"
python3 "$HERE/measure.py" "$W/tree/$SNAP_CSTYLE" "$W/port.txt" --tsv "$W/four-col.tsv" \
  | tee "$W/four-col.txt"

step "3  are the SEVEN EMPTY rows refusals?  live CPython, no py= literal consulted"
( cd "$REPO" && CCACHE=0 python3 "$HERE/empty-probe.py" ) | tee "$W/empty-probe.txt"

step "4  the one declaration the kern2 fixture withholds, captured live"
( cd "$REPO" && CCACHE=0 python3 "$HERE/preamble-oracle.py" > "$W/preamble.txt" )
echo "  $(cat "$W/preamble.txt")"

step "5  the CONVERSION, three gates"
python3 "$HERE/convert2.py" "$W/port.txt" --preamble "$W/preamble.txt" \
  --decl-from hipocml --tsv "$W/convert2.tsv" | tee "$W/convert2.txt"

step "6  GATE 3 -- do the numbers equal TINYGRAD's?"
CS2_REPO="$REPO" python3 "$HERE/agree.py" "$W/convert2.tsv" | tee "$W/agree.txt" || true

step "7  PLANT and DISARM, twice"
zsh "$HERE/plant.sh"

live_after=$(shasum -a 256 "$REPO/$SNAP_CSTYLE" | cut -d' ' -f1)
echo
echo "=== live $SNAP_CSTYLE after everything: $live_after"
[ "$live" = "$live_after" ] && echo "=== UNTOUCHED" || { echo "=== *** THE LIVE TREE CHANGED ***"; exit 3; }
echo "=== nothing committed by this unit."