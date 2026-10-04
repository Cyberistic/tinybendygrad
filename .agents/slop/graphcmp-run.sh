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
ALL="matmul reduce buffer sink range rangeflat cast special binblob group commute indexed sym lin loop gate"
# THE VERDICT EACH GRAPH MUST PRINT. A default is not available here and the reason is
# LIMITS.md's own lesson: a claim with no denominator, or an expectation that reads a
# variable, is a claim nobody can check.
#   `sym` USED TO BE HERE. It DISAGREED on 3 of its 12 nodes because the port could not mint
#     a symbolic dim at all (`fold.bend`'s `ssimplify` wall), and it was the corpus's one
#     DISAGREE-on-purpose graph. MEASURED 2026-10-04 late in the day: that wall is CLOSED --
#     `fold.bend`'s `sym_dim.pa` (`fold.bend:1296`, the `AParam` arm of `sym_dim.of`) landed
#     from the `fold` unit -- `sym` now reads `?=0` and `VERDICT: AGREE` at 12 of 12 nodes,
#     and the symbolic-dim half of LIMITS.md section 3 is rewritten from RESOLVED-by-other
#     rather than left claiming a limit that no longer exists.
#   `lin` DISAGREES on ONE node of 46 -- its SINK's `applied_opts`, which the port can only
#     answer with one `q` per option (`ops.bend:978` types them `List<U32>`; upstream's are
#     `Opt` dataclasses).
#   `loop` DISAGREES on ONE node of 25 -- its CALL, whose dtype the port reads from
#     `CallInfo.cdtype`, a field CPython's `CallInfo` does not have (`ops.py:130-131` reads
#     `src[0].dtype`).
# Both are MEASURED causes, not tolerances.
WANT="matmul:AGREE reduce:AGREE buffer:AGREE sink:AGREE range:AGREE rangeflat:AGREE cast:AGREE special:AGREE binblob:AGREE group:AGREE commute:AGREE indexed:AGREE sym:AGREE lin:DISAGREE loop:DISAGREE gate:AGREE"
mkdir -p "$D"

run() { # run <outfile> <args...>
  out=$1; shift
  # shellcheck disable=SC2086
  $E $P .agents/slop/graphcmp.py "$@" > "$D/$out" 2>"$D/$out.err"
  echo "rc=$?" >> "$D/$out"
}

# --- 00 THE SELFCHECK, and the COMM and LEDGER assertions it grew -------------------
run D0-selfcheck.txt selfcheck

# --- 01 THE SIXTEEN GRAPHS. One command each, one verdict line each, and the
# ---    DENOMINATOR on the line above it so `AGREE` on 2 nodes never prints like `AGREE`
# ---    on 19. THREE graphs DISAGREE and every one of them is accounted for by a name in
# ---    `WANT` above; the script ASSERTS each rather than letting a reader check sixteen
# ---    files by eye.
for g in $ALL; do
  run "D1-graph-$g.txt" diff --graph "$g"
done
{ bad=0
  for g in $ALL; do
    want=$(echo "$WANT" | tr ' ' '\n' | grep "^$g:" | cut -d: -f2)
    got=$(grep -o 'VERDICT: [A-Z]*' "$D/D1-graph-$g.txt" | tail -1 | cut -d' ' -f2)
    if [ "$got" != "$want" ]; then
      echo "$g: VERDICT=$got EXPECTED=$want"; bad=1
    fi
  done
  [ "$bad" = 0 ] && echo "all 16 graphs: verdict as expected (14 AGREE; lin and loop DISAGREE, each with a named cause in the \$WANT comment above)" \
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
# ---    a tree-only corpus is a control that has never met a two-parent node. `gate` and
# ---    `loop` are here because they are the widest-fan-in and the disagreeing graphs, and a
# ---    control that only ever runs on AGREEing fixtures is a control that has never had to
# ---    agree with itself WHILE disagreeing.
run D3-control-matmul.txt control --graph matmul
run D3-control-binblob.txt control --graph binblob
run D3-control-group.txt  control --graph group
run D3-control-gate.txt   control --graph gate
run D3-control-loop.txt   control --graph loop

# --- 04 CROSS: one graph against a DIFFERENT graph, on BOTH sides.
run D4-cross-range.txt cross --graph range

# --- 05 THE PLANTS. Every one must DISAGREE and NAME something; a plant that agrees is a
# ---    plant that is not load-bearing. `sym1` needs the `sym` graph and the others need
# ---    the matmul, so they are not one loop any more.
for pl in dtype srcswap shape bytes pyuop opt; do
  run "D5-plant-$pl.txt" diff --graph matmul --plant "$pl"
done
run D5-plant-sym1.txt diff --graph sym --plant sym1
#     NOT the attributable measurement for the symbolic dim: a plant edits the PY side only
#     (planting the bend side is six DAG rewrites in Bend -- the reason `--plant-side` was
#     removed), so this file carries the plant's effect AND `sym`'s pre-existing `?`
#     disagreements together. `conf`'s CONFLATION 4 is the attributable one: py vs py, with
#     nothing else moving.

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
# ---    its own cannot be used to detect that the port moved. FIVE cases, because the
# ---    interesting shapes are different: `group` is the first DAG, `sym` and `loop` are
# ---    graphs that DISAGREE (so a report whose disagreements moved would be the one that
# ---    matters, and only one of them used to be in the pair at all), `gate` is the widest
# ---    fan-in in the corpus, and `commute:--plant srcswap` is a PLANT -- a run that was
# ---    killed mid-write once left three `D5-plant-*.txt` files that were byte-identical to
# ---    EACH OTHER, which no plant can produce, and the only thing that told them apart from
# ---    a real result was that they had been truncated.
STAB_A="group sym loop gate"
STAB_PLANT="commute:--plant srcswap"
for g in $STAB_A; do
  run "D9-stability-$g-a.txt" diff --graph "$g"
  run "D9-stability-$g-b.txt" diff --graph "$g"
done
# QUOTED, or `for c in $STAB` splits on the space in `--plant srcswap` and produces a
# SIXTH pair named `srcswap`, which is not a graph. MEASURED: the unquoted list did
# exactly that and `D9-stability-srcswap-a.txt` was an argparse error file -- which is why
# `stable-pairs` printed 6 for 5 pairs.
for c in $STAB_PLANT; do
  g=${c%%:*}
  pl=${c#*:}
  # shellcheck disable=SC2086
  run "D9-stability-$g-a.txt" diff --graph "$g" $pl
  # shellcheck disable=SC2086
  run "D9-stability-$g-b.txt" diff --graph "$g" $pl
done
{ for g in $STAB_A commute; do
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
# ---     THE RC IS CAPTURED. It was not, and that is how a substrate break reads as a
# ---     census: `graphcmp-oracle.py` calls `emit_bend`, so when a concurrent edit to
# ---     `tinybendygrad/uop/ops.bend` made every bend emission 0 rows, the oracle DIED at
# ---     `rangeflat` -- printing a nine-row census and nothing about the seven graphs after
# ---     it, and the file it wrote was a plausible-looking table. MEASURED: `rc=1` and the
# ---     file ends mid-table. A step whose output is a table must say whether the table is
# ---     finished.
$E $P .agents/slop/graphcmp-oracle.py > "$D/D0-coverage-census.txt" 2>&1
echo "rc=$?" >> "$D/D0-coverage-census.txt"

# --- 12 WHETHER CPYTHON's OWN `DEBUG >= 1` SITE CAN BE REACHED HERE. It cannot, on 13 real
# ---     graphs, which is why `dbg` is port-vs-port and says so in its own output.
$E $P .agents/slop/graphcmp-dbg-oracle.py > "$D/D8b-cpython-dbg1-reachability.txt" 2>&1

# --- 13 THE OPS PROBE: the raw CPython measurements every coverage claim rests on. It is a
# ---     separate file rather than more `diff` output because it asks CPython DIRECTLY --
# ---     does GROUP carry a `params` list, which Tensor op emits which NODE op, can two
# ---     different symbolic dims be separated, what is a variable PARAM's slot -- and those
# ---     questions have no answer that a port-vs-port diff can produce.
$E $P .agents/slop/graphcmp-p13-ops.py > "$D/D0-ops-probe.txt" 2>&1

# --- 14 REMOVE THE STALE FOUR-GRAPH FILES. The byte-identity step used to run four graphs
# ---     and its `BYTE-IDENTICAL` verdicts were vacuous (step 02's comment); the old
# ---     `D9-stability-{a,b}.txt` were the binblob pair. Leaving them would leave a
# ---     PASS-shaped file in the directory that no command in this script produces.
rm -f "$D/D9-stability-a.txt" "$D/D9-stability-b.txt"

# --- 15 WHAT A CLEAN RUN OF THIS SCRIPT ESTABLISHES, IN ONE PLACE, because every other
# ---     statement about it is somewhere else.
# ---
# ---     REPRODUCIBILITY, and the command that checks it. The old claim here read "two
# ---     consecutive clean runs of this script leave every file under `$D` byte-identical
# ---     (`find | md5 -q`, both sides)" and THAT COMMAND IS WRONG: macOS `md5 -q` takes
# ---     exactly ONE file and PRINTS NOTHING given several, so `find | md5 -q` is not a
# ---     digest of anything. The claim survived because the file it produced looked like a
# ---     digest. The check that works, and the only one used since:
# ---
# ---       sh .agents/slop/graphcmp-run.sh
# ---       find runs/graphcmp/D -type f | sort | while read f; do
# ---         printf '%s  %s\n' "$(grep -v '^[[:space:]]*$' "$f" | shasum -a 256 | cut -d' ' -f1)" "$f"
# ---       done > /tmp/A
# ---       sh .agents/slop/graphcmp-run.sh
# ---       ... same ... > /tmp/B ; diff /tmp/A /tmp/B
# ---
# ---     `grep -v '^[[:space:]]*$'` is load-bearing rather than fussy: a trailing BLANK LINE
# ---     is a real difference that this project has already paid for -- a count-based diff
# ---     reported 16 apparent deltas on a run where 16 were blank lines -- while a
# ---     hash-of-the-whole-file would call a blank line a difference too. This form asks
# ---     the question "did any CONTENT move", which is the question.
# ---     MEASURED 2026-10-04: **158 of 158 files identical**, and the first time it was run
# ---     it found exactly ONE file that was not (`D0-coverage-census.txt`, a `dict` printed
# ---     in set-iteration order -- now defect 20 in graphcmp-oracle.py). That is the whole
# ---     argument for the check existing: the defect it found was invisible to `selfcheck`,
# ---     to `control`, to every verdict and to every DENOMINATOR line in the directory.
{ echo "graphs=$(ls "$D"/D1-graph-*.txt | wc -l | tr -d ' ')"
  echo "graphs-agree=$(grep -l 'VERDICT: AGREE' "$D"/D1-graph-*.txt | wc -l | tr -d ' ')"
  echo "graphs-disagree=$(grep -l 'VERDICT: DISAGREE' "$D"/D1-graph-*.txt | wc -l | tr -d ' ')"
  echo "byte-identical=$(grep -c 'BYTE-IDENTICAL' "$D/D2-bytediff.txt" | tr -d ' ')"
  echo "not-comparable=$(grep -c 'NOT COMPARED' "$D/D2-bytediff.txt" | tr -d ' ')"
  echo "stable-pairs=$(grep -c 'BYTE-IDENTICAL' "$D/D9-stability.txt" | tr -d ' ')"
  echo "selfcheck=$(sed -n '1p' "$D/D0-selfcheck.txt")"
  echo "conflations=$(grep -c 'VERDICT: OK' "$D/D7-conf.txt") of 4"
  # `grep -c` over a GLOB prints ONE COUNT PER FILE; it does not total them. MEASURED: it
  # printed five `filename:1` lines and then `of 5`, so the summary's own total line was
  # five lines long. `-l | wc -l` is the counting form.
  echo "controls=$(grep -l 'CONTROL VERDICT: OK' "$D"/D3-control-*.txt | wc -l | tr -d ' ') of 5"
  # The oracle's own three assertions -- the two `atoms()` rows of defect 21 and the
  # unmapped-atom-letter row -- ride in the same summary as the differ's, because a
  # coverage claim whose printer is broken is a coverage claim about the printer.
  echo "oracle-selfcheck=$(grep 'ORACLE SELFCHECK' "$D/D0-coverage-census.txt")"
  echo "census-rc=$(tail -1 "$D/D0-coverage-census.txt")"
} > "$D/D0-run-summary.txt"

echo "wrote $D"