#!/bin/sh
# dd-mut-base.sh -- the BASELINE for dd-mutate.py, built so it CANNOT be a mutant.
#
# WHY THIS IS A SCRIPT AND NOT A COMMAND LINE.  It was one command line, once,
# and it produced a baseline that was the M09 MUTANT: the hand-built mirror it
# pointed at had been left holding a mutated `dtype.bend` by an earlier probe, so
# `hi42` read `OR(SHR(SHR,ADD),SHL(BITCAST,CAST))` in the BASELINE.  Every
# mutation then moved 6 rows and all three controls read MOVED, so dd-mutate.py
# aborted and wrote no table -- which is the only reason it was caught, and the
# abort is RULE C doing its job on a defect it was not written for.
#
# The lesson is that a mirror is a mutable thing and a baseline is a claim about
# it, so the claim has to be made about a mirror built HERE, from the frozen
# snapshot, with the digest asserted on both sides.  Nothing here reads the live
# tree and nothing here is reused between runs.
#
# usage: dd-mut-base.sh OUT.txt
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/.agents/slop
FROZEN=$HERE/dd-mutations.frozen.bend
TREE_REV=e17d3f7dd48cf84c7a101b3d6aee11c0284a165e
BEND=$ROOT/bin/bend
OUT=$1
[ -n "$OUT" ] || { echo "usage: dd-mut-base.sh OUT.txt" >&2; exit 2; }

WANT=$(shasum "$FROZEN" | cut -d' ' -f1)
GOT=$(shasum "$ROOT/tinybendygrad/codegen/decomp/dtype.bend" | cut -d' ' -f1)
if [ "$WANT" != "$GOT" ]; then
  # A WARNING, not a refusal, and the change is deliberate.  The property this
  # script exists to protect is "the baseline is the UNMUTATED PINNED snapshot",
  # and freezing is what delivers it: a baseline built from the LIVE file would
  # be a claim about a file a concurrent unit is rewriting, which is the failure
  # this script was written after.  `dtype.bend` moved four times while this
  # table was being built, so a hard `frozen == live` assertion makes the script
  # unrunnable exactly when it is most needed.
  #
  # What IS asserted, and what the table's validity rests on: the frozen file
  # still hashes to FROZEN_SHA1 (dd-mutate.py RULE I) and the mirror below is
  # byte-identical to the frozen file.  The table therefore measures ONE file,
  # named and digested, whatever the live tree is doing.  This warning IS the
  # report's "against the snapshot, not against what is on disk" line.
  echo "WARNING: the live dtype.bend is $GOT and the PINNED snapshot is $WANT." >&2
  echo "  The baseline below is the PINNED snapshot.  The table is NOT against" >&2
  echo "  what is on disk; it is against $WANT, and its header says so." >&2
fi

# A FRESH directory every time, named for the digest so two runs cannot share one.
TOP=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/dd-base-$(echo "$WANT" | cut -c1-12)
rm -rf "$TOP"
mkdir -p "$TOP"
git -C "$ROOT" archive "$TREE_REV" tinybendygrad | tar -x -C "$TOP"
cp "$FROZEN" "$TOP/tinybendygrad/codegen/decomp/dtype.bend"

# The mirror IS the frozen file, asserted, not assumed.
test "$(shasum "$TOP/tinybendygrad/codegen/decomp/dtype.bend" | cut -d' ' -f1)" = "$WANT" \
  || { echo "REFUSING: the mirror is not the frozen snapshot" >&2; exit 1; }

# bend prints NOTHING on a stack overflow (~1 run in 20 here) and that is
# indistinguishable from "never started", so the guard is TWO CONSECUTIVE runs
# that agree on the line count with a full row set -- not the exit code, which is
# 1 on a clean file, and not a comparison against a previous OUT (which may not
# exist yet, and reading it made this loop spin for 24 tries on its own error).
i=0
prev=-1
while [ $i -lt 12 ]; do
  "$BEND" "$TOP/tinybendygrad/codegen/decomp/dtype.bend" > "$TOP/out.txt" 2>/dev/null || true
  rows=$(grep -c '=' "$TOP/out.txt" 2>/dev/null || echo 0)
  lines=$(wc -l < "$TOP/out.txt" | tr -d ' ')
  if [ "$rows" -ge 150 ] && [ "$lines" = "$prev" ]; then
    cp "$TOP/out.txt" "$OUT"
    echo "baseline $OUT: $rows rows / $lines lines, sha1 $(shasum "$OUT" | cut -d' ' -f1), target $WANT"
    exit 0
  fi
  prev=$lines
  i=$((i + 1))
done
echo "REFUSING: the unmutated mirror never produced two consecutive stable 150+ row" >&2
echo "  outputs in 12 tries -- bend's stack overflow, or a substrate that stopped" >&2
echo "  compiling.  No verdict is evidence until this passes (dd-mutate.py RULE E)." >&2
exit 1