#!/bin/zsh
# Mutate spec.bend, re-run the gate, and report which rows moved.
# usage: mutate.sh <name> <sed-expr> [<sed-expr> ...]
set -e
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
F=tinybendygrad/uop/spec.bend
NAME=$1; shift
cp "$F" /tmp/spec.gate.bak
for e in "$@"; do
  sed -i '' "$e" "$F"
done
if ! ./bin/bend "$F" --check-only >/dev/null 2>&1; then
  echo "$NAME: DOES NOT CHECK"
  cp /tmp/spec.gate.bak "$F"; exit 0
fi
./bin/bend "$F" > /tmp/spec.mut.out 2>&1
./bin/bend "$F" -o /tmp/specmut >/dev/null 2>&1 && /tmp/specmut > /tmp/spec.mut.bin 2>&1
if ! diff -q /tmp/spec.mut.out /tmp/spec.mut.bin >/dev/null; then echo "$NAME: LANES DISAGREE"; fi
echo "== $NAME"
./bin/bend "$F" | diff /tmp/spec.gate.base - | grep -E '^[<>]' | sed 's/^</-/' | sort -u
echo "-- moved: $(./bin/bend "$F" | diff /tmp/spec.gate.base - | grep -cE '^[<>]') half-rows"
cp /tmp/spec.gate.bak "$F"
