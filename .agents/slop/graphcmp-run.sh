#!/bin/sh
# graphcmp-run.sh -- EVERY ARTIFACT FOR THE 2026-10-04 WIDENING, AND THE COMMAND FOR EACH.
#
# env -u PYTHONPATH is REQUIRED (it contaminates a control) and LC_ALL=C is REQUIRED (a
# locale-colated sort fabricates diffs). DEV=NULL is the rebase gate's own setting; the
# differ overrides it to the `--dev` value it is given, and every run below says which.
#
# ONE LINE OF SUBSTANCE PER GRAPH: `diff --graph NAME` prints exactly one `# VERDICT:`
# line and its `# DENOMINATOR:` line, and `NAME` is the only argument. That is the
# artifact; everything else here is the evidence that the artifact is worth reading.
set -u
cd "$(dirname "$0")/../.." || exit 2
D=runs/graphcmp/D
E="env -u PYTHONPATH LC_ALL=C DEV=NULL"
P=.venv/bin/python
mkdir -p "$D"

run() { # run <outfile> <args...>
  out=$1; shift
  # shellcheck disable=SC2086
  $E $P .agents/slop/graphcmp.py "$@" > "$D/$out" 2>"$D/$out.err"
  echo "rc=$?" >> "$D/$out"
}

# --- 00 THE SELFCHECK, and the COMM assertions it grew -----------------------------
run D0-selfcheck.txt selfcheck

# --- 01 THE NINE GRAPHS. One command each, one verdict line each, and the DENOMINATOR
# ---    on the line above it so `AGREE` on 2 nodes never prints like `AGREE` on 19.
for g in matmul reduce buffer sink range rangeflat cast special binblob; do
  run "D1-graph-$g.txt" diff --graph "$g"
done

# --- 02 THE CANONICAL FILES ARE BYTE-IDENTICAL, which is the cheapest check in the file:
# ---    it fails first when an atom letter moves. rc=0 from `diff` IS the check.
for g in matmul range cast binblob; do
  # shellcheck disable=SC2086
  $E $P .agents/slop/graphcmp.py emit py --graph "$g" > "$D/D2-canon-py-$g.txt" 2>/dev/null
  # shellcheck disable=SC2086
  $E $P .agents/slop/graphcmp.py emit bend --graph "$g" > "$D/D2-canon-bend-$g.txt" 2>/dev/null
  # PER-GRAPH FILE, THEN CONCATENATED ONCE. Both wrong shapes were tried: `>>` accumulates
  # the same four lines once per run until the file reads like a coverage table when it is
  # one line repeated, and `>` inside the loop leaves only the LAST graph's line. One file
  # per graph and one `cat` is the shape that is right for both reasons.
  { cmp -s "$D/D2-canon-py-$g.txt" "$D/D2-canon-bend-$g.txt" \
      && echo "$g BYTE-IDENTICAL" || { echo "$g DIFFERS:"; \
           diff "$D/D2-canon-py-$g.txt" "$D/D2-canon-bend-$g.txt" | head -20; }; } \
    > "$D/D2-cmp-$g.txt"
done

cat "$D"/D2-cmp-*.txt > "$D/D2-bytediff.txt"

# --- 03 CONTROL: each side against ITSELF. A differ never seen to agree with itself is
# ---    not known to work.
run D3-control-matmul.txt control --graph matmul
run D3-control-binblob.txt control --graph binblob

# --- 04 CROSS: one graph against a DIFFERENT graph, on BOTH sides.
run D4-cross-range.txt cross --graph range

# --- 05 THE PLANTS. Every one must DISAGREE and NAME something; a plant that agrees is a
# ---    plant that is not load-bearing.
for pl in dtype srcswap shape bytes pyuop opt; do
  run "D5-plant-$pl.txt" diff --graph matmul --plant "$pl"
done

# --- 06 THE ORDERED / EQUIV SPLIT on the same reordered pair. Same fixture, two answers,
# ---    and both are results.
run D6-srcswap-ordered.txt diff --graph matmul --plant srcswap
run D6-srcswap-equiv.txt   diff --graph matmul --plant srcswap --equiv

# --- 07 THE THREE CONFLATIONS.
run D7-conf.txt conf

# --- 08 THE DEBUG-LEVEL COMPARISON, graph held fixed and the level varied alone.
run D8-dbg-012.txt dbg --levels 0,1,2
run D8-dbg-03.txt   dbg --levels 0,3

# --- 09 REPRODUCIBILITY. Two clean runs, byte-for-byte. A differ whose output moves on
# ---    its own cannot be used to detect that the port moved.
run D9-stability-a.txt diff --graph binblob
run D9-stability-b.txt diff --graph binblob
cmp -s "$D/D9-stability-a.txt" "$D/D9-stability-b.txt" \
  && echo "binblob: 2 runs BYTE-IDENTICAL" > "$D/D9-stability.txt" \
  || { echo "binblob: 2 runs DIFFER" > "$D/D9-stability.txt"; \
       diff "$D/D9-stability-a.txt" "$D/D9-stability-b.txt" | head -20 >> "$D/D9-stability.txt"; }

# --- 10 THE 0-ROW GUARD, FIRED ON PURPOSE. `graphcmp-empty.bend` prints nothing, so
# ---     `emit bend` must RAISE rather than answer.
run D10-zerorow-guard.txt emit --side bend --bend-probe .agents/slop/graphcmp-empty.bend

# --- 11 THE COVERAGE DENOMINATOR, tabulated. Emits BOTH sides so an op or atom the py side
# ---     never produces shows up as a per-side difference rather than an absorbed AGREE.
$E $P .agents/slop/graphcmp-oracle.py > "$D/D0-coverage-census.txt" 2>&1

# --- 12 WHETHER CPYTHON's OWN `DEBUG >= 1` SITE CAN BE REACHED HERE. It cannot, on 8 real
# ---     graphs, which is why `dbg` is port-vs-port and says so in its own output.
$E $P .agents/slop/graphcmp-dbg-oracle.py > "$D/D8b-cpython-dbg1-reachability.txt" 2>&1

echo "wrote $D"