#!/bin/sh
# bnxtdev.bend -- THE GATE DIFF. Compares whole `name=value` LINES, not row
# names, because a name-comparing harness reported 0 moved rows for every
# mutation in two separate units.
#
#   sh .agents/slop/bnxt_gate.sh
#
# Three lanes: the CPython oracle, the interpreted Bend lane, and the NATIVE
# Bend lane. It reports, per lane pair, the rows only one side has and the rows
# both have with DIFFERENT values.
set -e
cd "$(dirname "$0")/../.."
F=tinybendygrad/runtime/support/rdma/bnxtdev.bend
S=.agents/slop

echo "== regenerating the CPython oracle =="
python3 -c "import sys; sys.path.insert(0,'.'); exec(open('$S/bnxt_oracle.py').read())" \
  > "$S/bnxt_oracle.txt"
echo "== interpreted lane =="
./bin/bend "$F" > "$S/bnxt_interp.txt"
echo "== native lane =="
./bin/bend "$F" -o "$S/bnxtdev_native" >/dev/null 2>&1
"$S/bnxtdev_native" > "$S/bnxt_native.txt"

for a in oracle interp native; do
  for b in oracle interp native; do
    [ "$a" = "$b" ] && continue
    echo
    echo "== $a  vs  $b =="
    python3 .agents/slop/bnxt_cmp.py "$S/bnxt_$a.txt" "$S/bnxt_$b.txt" | sed "s/^/   /"
  done
done