#!/bin/sh
# xb1/lanes.sh <outdir> <bend-file...>  -- capture ALL lanes for a set of bend files.
# every lane, no cache. rows are `name=value` lines counted with grep -c '='.
set -u
OUT="$1"; shift
mkdir -p "$OUT"
for f in "$@"; do
  b=$(basename "$f" .bend); d=$(dirname "$f" | tr '/' '_')
  n="$OUT/${d}_${b}"
  ./bin/bend "$f" > "$n.interp.txt" 2> "$n.interp.err"
  echo "interp rc=$? rows=$(grep -c '=' "$n.interp.txt")" > "$n.lanes"
  ./bin/bend "$f" --check-only > "$n.check.txt" 2>&1
  echo "check  first=[$(head -1 "$n.check.txt")] rc=$?" >> "$n.lanes"
  ./bin/bend "$f" -o "$n.bin" > "$n.build.err" 2>&1
  if [ -f "$n.bin" ]; then
    chmod 755 "$n.bin"
    "$n.bin" > "$n.native.txt" 2> "$n.native.err"
    echo "native rc=$? rows=$(grep -c '=' "$n.native.txt")" >> "$n.lanes"
  else
    echo "native BUILD-FAILED" >> "$n.lanes"
  fi
  if cmp -s "$n.interp.txt" "$n.native.txt"; then echo "LANES-BYTE-IDENTICAL" >> "$n.lanes"; else echo "LANES-DIFFER" >> "$n.lanes"; fi
  cat "$n.lanes"
done