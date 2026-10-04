#!/bin/sh
# graphcmp-run.sh -- EVERY ARTIFACT FOR THE WIDENING, AND THE COMMAND FOR EACH.
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
ALL="matmul reduce buffer sink range rangeflat cast special binblob group commute indexed sym"
mkdir -p "$D"

run() { # run <outfile> <args...>
  out=$1; shift
  # shellcheck disable=SC2086
  $E $P .agents/slop/graphcmp.py "$@" > "$D/$out" 2>"$D/$out.err"
  echo "rc=$?" >> "$D/$out"
}

# --- 00 THE SELFCHECK, and the COMM and LEDGER assertions it grew -------------------
run D0-selfcheck.txt selfcheck

# --- 01 THE THIRTEEN GRAPHS. One command each, one verdict line each, and the
# ---    DENOMINATOR on the line above it so `AGREE` on 2 nodes never prints like `AGREE`
# ---    on 19. `sym` is SUPPOSED TO DISAGREE (three of its twelve nodes read `?` for
# ---    dtype and shape: fold.bend cannot `ssimplify` a non-CONST STACK element, so the
# ---    port cannot build a symbolic dim at all). Every other graph is AGREE, and this
# ---    script ASSERTS it rather than letting a reader check thirteen files by eye.
for g in $ALL; do
  run "D1-graph-$g.txt" diff --graph "$g"
done
{ bad=0
  for g in $ALL; do
    case $g in sym) want=DISAGREE ;; *) want=AGREE ;; esac
    got=$(grep -o 'VERDICT: [A-Z]*' "$D/D1-graph-$g.txt" | tail -1 | cut -d' ' -f2)
    if [ "$got" != "$want" ]; then
      echo "$g: VERDICT=$got EXPECTED=$want"; bad=1
    fi
  done
  [ "$bad" = 0 ] && echo "all 13 graphs: verdict as expected (12 AGREE + sym DISAGREE)" \
    || echo "AT LEAST ONE GRAPH'S VERDICT MOVED"
} > "$D/D1-verdicts.txt"

# --- 02 THE CANONICAL FILES ARE BYTE-IDENTICAL, which is the cheapest check in the file:
# ---    it fails first when an atom letter moves. rc=0 from `diff` IS the check.
#
# ---    THIS STEP WAS A VACUOUS PASS UNTIL 2026-10-04, and it is the reason it now
# ---    counts ROWS before comparing. It ran `emit py` / `emit bend`, which argparse
# ---    rejects (`--side` is a FLAG, not a positional): both children exited 2 on
# ---    `unrecognized arguments: py` and wrote ZERO BYTES, and `cmp -s` on two empty
# ---    files returns success. MEASURED: `runs/graphcmp/D/D2-cmp-*.txt` read
# ---    `BYTE-IDENTICAL` for four graphs having compared nothing, because a verdict line
# ---    cannot tell an empty comparison from a satisfied one -- the same defect class as
# ---    the `unchunks` separator bug, where "0 trace rows" was reported as a COUNT.
# ---    The row-count guard is the fix and the spelling is incidental.
for g in $ALL; do
  # shellcheck disable=SC2086
  $E $P .agents/slop/graphcmp.py emit --side py --graph "$g" > "$D/D2-canon-py-$g.txt" 2>/dev/null
  # shellcheck disable=SC2086
  $E $P .agents/slop/graphcmp.py emit --side bend --graph "$g" > "$D/D2-canon-bend-$g.txt" 2>/dev/null
  # PER-GRAPH FILE, THEN CONCATENATED ONCE. Both wrong shapes were tried: `>>` accumulates
  # the same four lines once per run until the file reads like a coverage table when it is
  # one line repeated, and `>` inside the loop leaves only the LAST graph's line. One file
  # per graph and one `cat` is the shape that is right for both reasons.
  a=$(wc -c < "$D/D2-canon-py-$g.txt" | tr -d ' ')
  b=$(wc -c < "$D/D2-canon-bend-$g.txt" | tr -d ' ')
  { if [ "$a" = 0 ] || [ "$b" = 0 ]; then
      echo "$g NOT COMPARED: py=$a bytes bend=$b bytes (a 0-byte side is a FAILURE, not a pass)"
    elif cmp -s "$D/D2-canon-py-$g.txt" "$D/D2-canon-bend-$g.txt"; then
      echo "$g BYTE-IDENTICAL ($a bytes both sides)"
    else
      echo "$g DIFFERS:"; diff "$D/D2-canon-py-$g.txt" "$D/D2-canon-bend-$g.txt" | head -20
    fi; } > "$D/D2-cmp-$g.txt"
done

cat "$D"/D2-cmp-*.txt > "$D/D2-bytediff.txt"

# --- 03 CONTROL: each side against ITSELF. A differ never seen to agree with itself is
# ---    not known to work. `group` is here because it is the first DAG, and a control over
# ---    a tree-only corpus is a control that has never met a two-parent node.
run D3-control-matmul.txt control --graph matmul
run D3-control-binblob.txt control --graph binblob
run D3-control-group.txt  control --graph group

# --- 04 CROSS: one graph against a DIFFERENT graph, on BOTH sides.
run D4-cross-range.txt cross --graph range

# --- 05 THE PLANTS. Every one must DISAGREE and NAME something; a plant that agrees is a
# ---    plant that is not load-bearing. `sym1` needs the `sym` graph and the others need
# ---    the matmul, so they are not one loop any more.
for pl in dtype srcswap shape bytes pyuop opt; do
  run "D5-plant-$pl.txt" diff --graph matmul --plant "$pl"
done
run D5-plant-sym1.txt diff --graph sym --plant sym1

# --- 06 THE ORDERED / EQUIV SPLIT on the same reordered pair. Same fixture, two answers,
# ---    and both are results. It runs on `commute` as well, and that is the point of this
# ---    round: `--equiv` used to be measured on ONE of the eight commutative ops (a MUL),
# ---    and on `commute` it is measured on six of them in one graph.
run D6-srcswap-ordered.txt  diff --graph matmul  --plant srcswap
run D6-srcswap-equiv.txt    diff --graph matmul  --plant srcswap --equiv
run D6-commute-ordered.txt  diff --graph commute --plant srcswap
run D6-commute-equiv.txt    diff --graph commute --plant srcswap --equiv

# --- 07 THE FOUR CONFLATIONS.
run D7-conf.txt conf

# --- 08 THE DEBUG-LEVEL COMPARISON, graph held fixed and the level varied alone.
run D8-dbg-012.txt dbg --levels 0,1,2
run D8-dbg-03.txt   dbg --levels 0,3

# --- 09 REPRODUCIBILITY. Two clean runs, byte-for-byte. A differ whose output moves on
# ---    its own cannot be used to detect that the port moved. THREE cases, because the
# ---    three interesting shapes are different: `group` is the first DAG, `sym` is the one
# ---    graph that DISAGREES (so a report whose DISAGREEMENTS moved would be the one that
# ---    matters, and it used not to be in the pair at all), and the third is a PLANT -- a
# ---    run that was killed mid-write once left three `D5-plant-*.txt` files that were
# ---    byte-identical to EACH OTHER, which no plant can produce, and the only thing that
# ---    told them apart from a real result was that they had been truncated.
for c in "group:" "sym:" "commute:--plant srcswap"; do
  g=${c%%:*}
  pl=${c#*:}
  # shellcheck disable=SC2086
  run "D9-stability-$g-a.txt" diff --graph "$g" $pl
  # shellcheck disable=SC2086
  run "D9-stability-$g-b.txt" diff --graph "$g" $pl
done
{ for g in group sym commute; do
    if cmp -s "$D/D9-stability-$g-a.txt" "$D/D9-stability-$g-b.txt"; then
      echo "$g: 2 runs BYTE-IDENTICAL"
    else
      echo "$g: 2 runs DIFFER"; diff "$D/D9-stability-$g-a.txt" "$D/D9-stability-$g-b.txt" | head -20
    fi
  done; } > "$D/D9-stability.txt"

# --- 10 THE 0-ROW GUARD, FIRED ON PURPOSE. `graphcmp-empty.bend` prints nothing, so
# ---     `emit --side bend` must RAISE rather than answer.
run D10-zerorow-guard.txt emit --side bend --bend-probe .agents/slop/graphcmp-empty.bend

# --- 11 THE COVERAGE DENOMINATOR, tabulated. Emits BOTH sides so an op or atom the py side
# ---     never produces shows up as a per-side difference rather than an absorbed AGREE.
$E $P .agents/slop/graphcmp-oracle.py > "$D/D0-coverage-census.txt" 2>&1

# --- 12 WHETHER CPYTHON's OWN `DEBUG >= 1` SITE CAN BE REACHED HERE. It cannot, on 13 real
# ---     graphs, which is why `dbg` is port-vs-port and says so in its own output.
$E $P .agents/slop/graphcmp-dbg-oracle.py > "$D/D8b-cpython-dbg1-reachability.txt" 2>&1

# --- 13 REMOVE THE STALE FOUR-GRAPH FILES. The byte-identity step used to run four graphs
# ---     and its `BYTE-IDENTICAL` verdicts were vacuous (step 02's comment); the old
# ---     `D9-stability-{a,b}.txt` were the binblob pair. Leaving them would leave a
# ---     PASS-shaped file in the directory that no command in this script produces.
rm -f "$D/D9-stability-a.txt" "$D/D9-stability-b.txt"

# --- 14 WHAT A CLEAN RUN OF THIS SCRIPT ESTABLISHES, IN ONE PLACE, because every other
# ---     statement about it is somewhere else. MEASURED: two consecutive clean runs of this
# ---     script leave all 121 files under `$D` byte-identical (`find | md5 -q`, both sides).
# ---     It is written here rather than claimed in the prose because a claim about
# ---     reproducibility that is not printed by the script is the same kind of sentence
# ---     that the symbolic-dim entry used to be.
{ echo "graphs=$(ls "$D"/D1-graph-*.txt | wc -l | tr -d ' ')"
  echo "graphs-agree=$(grep -l 'VERDICT: AGREE' "$D"/D1-graph-*.txt | wc -l | tr -d ' ')"
  echo "graphs-disagree=$(grep -l 'VERDICT: DISAGREE' "$D"/D1-graph-*.txt | wc -l | tr -d ' ')"
  echo "byte-identical=$(grep -c 'BYTE-IDENTICAL' "$D/D2-bytediff.txt" | tr -d ' ')"
  echo "not-comparable=$(grep -c 'NOT COMPARED' "$D/D2-bytediff.txt" | tr -d ' ')"
  echo "stable-pairs=$(grep -c 'BYTE-IDENTICAL' "$D/D9-stability.txt" | tr -d ' ')"
  echo "selfcheck=$(sed -n '1p' "$D/D0-selfcheck.txt")"
  echo "conflations=$(grep -c 'VERDICT: OK' "$D/D7-conf.txt") of 4"
} > "$D/D0-run-summary.txt"

echo "wrote $D"