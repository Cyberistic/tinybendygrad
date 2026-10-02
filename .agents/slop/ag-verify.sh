#!/bin/sh
# FULL REPRODUCIBLE VERIFICATION for runtime/support/autogen.bend.
# Every oracle is produced by CALLING CPython. Run from the repo root.
set -e
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
B=tinybendygrad/runtime/support/autogen.bend
echo "== check-only (read the FIRST LINE; --check-only exits 1 on dtype.bend's 14 red laws)"
./bin/bend $B --check-only 2>&1 | head -1
echo "== lane 1: interpreted"
./bin/bend $B > .agents/slop/ag-interp.txt
echo "== lane 2: native"
./bin/bend $B -o .agents/slop/ag-native.bin >/dev/null
.agents/slop/ag-native.bin > .agents/slop/ag-native.txt
diff .agents/slop/ag-interp.txt .agents/slop/ag-native.txt && echo "   both lanes BYTE-IDENTICAL ($(wc -l < .agents/slop/ag-interp.txt) rows)"
echo "== regenerate every oracle by CALLING CPython"
python3 .agents/slop/ag-oracle.py .agents/slop/ag-fixture.h > .agents/slop/ag-oracle.re.txt
diff .agents/slop/ag-oracle.txt .agents/slop/ag-oracle.re.txt && echo "   ag-oracle.txt REPRODUCES byte-identically"
python3 .agents/slop/ag-emit-oracle.py > .agents/slop/ag-emit-oracle.re.txt
diff .agents/slop/ag-emit-oracle.txt .agents/slop/ag-emit-oracle.re.txt && echo "   ag-emit-oracle.txt REPRODUCES byte-identically"
python3 .agents/slop/ag-abi-oracle.py > .agents/slop/ag-abi-oracle.re.txt
diff .agents/slop/ag-abi-oracle.txt .agents/slop/ag-abi-oracle.re.txt && echo "   ag-abi-oracle.txt REPRODUCES byte-identically"
echo "== diff the gate against CPython"
python3 .agents/slop/ag-diff.py  .agents/slop/ag-interp.txt .agents/slop/ag-oracle.txt
python3 .agents/slop/ag-diff2.py .agents/slop/ag-interp.txt .agents/slop/ag-emit-oracle.txt
python3 .agents/slop/ag-diff3.py .agents/slop/ag-interp.txt .agents/slop/ag-abi-oracle.txt
echo "== mutation table"
cp .agents/slop/ag-interp.txt .agents/slop/ag-base.txt
python3 .agents/slop/ag-mutate.py | tail -5
