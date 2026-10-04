#!/bin/zsh
# The renderer/{tc,tc_ptx} GATE, post-split. `tc_ptx.bend` held `renderer/tc.py` AND
# `renderer/ptx.py`; the 1:1 ruling separated them. 620 rows before, 620 after.
#
#   .agents/slop/tc-gate.sh
#
# bend 2.0.34 machine-stack-overflows about one run in twenty and sometimes prints
# ZERO rows, which is indistinguishable from "not started", so every file is retried.
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
for f in tc tc_ptx; do
  for i in 1 2 3 4 5; do
    ./bin/bend "tinybendygrad/renderer/$f.bend" > "$OUT/$f.txt" 2>/dev/null || true
    [ -s "$OUT/$f.txt" ] && break
  done
  echo "renderer/$f.bend  $(grep -c '=' "$OUT/$f.txt") rows"
done
cat "$OUT/tc.txt" "$OUT/tc_ptx.txt" | grep -v '^$' > "$OUT/all.txt"
echo "--------------------------------------------- union: $(grep -c '=' "$OUT/all.txt") rows"
# the old `main` printed both stages as ONE `IO.print`, so the two files' output has one
# frame line between the stages. `grep -v '^$'` drops that line and the snapshot's own
# trailing newline -- and ONLY those.
# TEMP FILES, NOT `<( ... )`: a BASHISM, so under `sh` this script did not parse, and a
# gate that cannot parse is a gate nobody reads. `grep -v '^$'` drops the one frame line
# the two stages leave between them and the snapshot's own trailing newline -- and ONLY
# those, which is why the filter is written out rather than folded into a sort.
grep -v '^$' .agents/slop/tc_ptx-pre-split.txt > "$OUT/snap.txt"
diff "$OUT/snap.txt" "$OUT/all.txt" \
  && echo "MATCHES the pre-split snapshot" \
  || { echo "DISAGREE with the pre-split snapshot" >&2; exit 1; }
rm -rf "$OUT"
