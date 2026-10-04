#!/bin/sh
# blobrows-sweep.sh <outdir> -- run the 72-file ops.bend dependency closure and record
# per-file row counts and sha256s. READ-ONLY on the tree; never writes into tinybendygrad/.
#
#   sh .agents/slop/blobrows-sweep.sh .agents/slop/blobrows/CURRENT
#
# WHY IT REUSES runrows.sh: bend's machine stack overflows ~1 run in 20 and prints ZERO
# rows, which is indistinguishable from "never started". runrows.sh retries both.
#
# WHY hashes, not just counts: gater/regalloc/codegen__init__ kept the SAME row count
# across the blob-fix window while their CONTENT changed, so a count-only comparison
# reports "no delta" for a real change. `_srchash.txt` is what makes that visible.
set -u
cd "$(dirname "$0")/../.."
OUT="$1"
mkdir -p "$OUT"

# The closure: every file that transitively depends on tinybendygrad/uop/ops.bend,
# plus ops.bend itself. Reconciled against the recorded 72-file baseline: 59 direct
# importers + 12 transitive + ops.bend.
FILES=$( (grep -rlE '^import .*(^|/)ops\.bend' tinybendygrad --include='*.bend';
          echo tinybendygrad/__init__.bend
          echo tinybendygrad/codegen/decomp/transcendental_f32.bend
          echo tinybendygrad/device.bend
          echo tinybendygrad/engine/worker.bend
          echo tinybendygrad/renderer/amd/elf.bend
          echo tinybendygrad/renderer/isa/x86.bend
          echo tinybendygrad/runtime/ops_amd.bend
          echo tinybendygrad/runtime/ops_metal.bend
          echo tinybendygrad/runtime/ops_nv.bend
          echo tinybendygrad/runtime/ops_webgpu.bend
          echo tinybendygrad/runtime/support/hcq2.bend
          echo tinybendygrad/runtime/support/nv/ip.bend
          echo tinybendygrad/uop/ops.bend ) | sort -u )

: > "$OUT/_counts.tsv"
for f in $FILES; do
  name=$(printf '%s' "$f" | sed 's|/|__|g')
  if sh .agents/slop/runrows.sh "$f" "$OUT/$name.txt" 2>"$OUT/$name.log"; then
    printf '%s\t%s\n' "$(grep -c . "$OUT/$name.txt")" "$f" >> "$OUT/_counts.tsv"
  else
    # NO-ROWS is a real, distinct outcome (a file whose main prints nothing, or a
    # cold-compile failure). Record it as 0 with an explicit marker, never silently.
    printf '0\t%s\tRUNROWS-FAILED\n' "$f" >> "$OUT/_counts.tsv"
  fi
done
awk -F'\t' '$1!~/RUNROWS/ {s+=$1} END {print "TOTAL\t"s}' "$OUT/_counts.tsv" >> "$OUT/_counts.tsv"
shasum -a 256 $FILES > "$OUT/_srchash.txt" 2>/dev/null
echo "sweep done: $(grep -vc TOTAL "$OUT/_counts.tsv") files"
