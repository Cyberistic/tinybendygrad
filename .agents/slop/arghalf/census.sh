#!/bin/sh
# census.sh -- run EVERY corpus graph through ONE renderer, on the frozen tree.
#
# `bend` runs are SERIAL on purpose: AGENTS.md's precondition for running bend processes
# together is the SUM of their measured peak RSS under 60% of hw.memsize, and these
# builds sit at 0.4-0.7 GB each. The verdict TOKEN is what is checked, never the exit
# code, because `bend --check-only` answers SOME PROOFS FAIL and a refusal alike on rc 1.
#
# USAGE: census.sh <driver-dir> <out-dir>
set -u
drv="$1"; out="$2"
mkdir -p "$out"
for g in allred alu binblob bit buffer bw cast cdiv commute flip gate group indexed \
         late lin loop matmul move range rangeflat reduce sink special sym where; do
  .venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- \
    ./bin/bend "$drv/gcmp.bend" "$g" > "$out/$g.rows" 2> "$out/$g.err"
  tok=$(sed -n 's/.*said=\(.*\)$/\1/p' "$out/$g.err" | head -1)
  case "$tok" in
    *KILLED-ON-MEMORY*|*TIMED-OUT*) echo "$g	REFUSED $tok"; continue;;
  esac
  # A 0-byte row file is NOT a pass and NOT a zero: it is a DEAD lane. Counted separately.
  if [ ! -s "$out/$g.rows" ]; then echo "$g	DEAD	0 bytes"; continue; fi
  echo "$g	OK	$(grep -c '' "$out/$g.rows") rows"
done