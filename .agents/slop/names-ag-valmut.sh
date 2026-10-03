#!/usr/bin/env bash
# VALUE-CHANGE MUTATIONS: the ones that MUST move rows.
#
# The brief asks for the opposite failure to be visible -- a rename that silently
# changes a value. These four mutate the BODY of a renamed def and each MUST move
# rows. If one moves 0, the harness or the fixture is broken, not the port.
#
# A note on the first attempt, because it is the exact trap: I wrote a value-change
# mutation with a regex over `def noopf_go(O.Arena.budget(...))` and it reported
# "0 rows moved" -- for the WRONG reason. The pattern never matched, because that
# expression is not on the `noopf_go` def line at all; it is on `is_noop_after_dep`'s
# body. The mutation was a no-op and the table said the same thing a real no-op would
# have said. Every mutation below is therefore VERIFIED APPLIED by re-grepping the
# mutant before running it, and a patch that does not apply is reported as
# PATCH DID NOT APPLY, never as "0 rows moved".
set -u
BEND="$PWD/bin/bend"
ROOT="$PWD/.agents/slop/names-ag-valmut"
rm -rf "$ROOT"; mkdir -p "$ROOT"

run_rows() {
  local f="$1" i out rows
  for i in 1 2 3 4 5 6; do
    out=$(cd "$(dirname "$f")" && "$BEND" "$(basename "$f")" 2>&1)
    echo "$out" | grep -q 'machine stack overflowed' && continue
    rows=$(echo "$out" | grep -c '=' || true)
    [ "$rows" = "0" ] && continue
    echo "$out" | grep '=' | grep -v '^-' | sed 's/[[:space:]]*$//' | LC_ALL=C sort
    return 0
  done
  echo "AGMUT-STACK-OR-ZERO"
}

check() {   # $1 file, $2 baseline, $3 label, $4 perl, $5 literal the mutant must now hold
  local f="$1" base="$2" label="$3" expr="$4" proof="$5"
  local rel="${f#tinybendygrad/}"
  local m="$ROOT/$label/tinybendygrad"
  rm -rf "$ROOT/$label"; mkdir -p "$ROOT/$label"; cp -R tinybendygrad "$m"
  perl -pi -e "$expr" "$m/$rel" || { echo "$(printf '%-30s' "$label")  PATCH FAILED"; return; }
  # grep -F, not grep: the patterns contain `{` and `(` and a regex `grep` reported
  # "invalid repetition count" and then answered 0, which is how a dead patch once
  # looked like a clean 0-row result.
  if ! grep -qF -- "$proof" "$m/$rel"; then
    echo "$(printf '%-30s' "$label")  *** PATCH DID NOT APPLY (no literal /$proof/) -- NOT A RESULT ***"
    return
  fi
  run_rows "$m/$rel" > "$ROOT/$label.rows"
  local n; n=$(wc -l < "$ROOT/$label.rows" | tr -d ' ')
  if [ "$n" = "0" ] || [ "$(head -1 "$ROOT/$label.rows")" = "AGMUT-STACK-OR-ZERO" ]; then
    echo "$(printf '%-30s' "$label")  BUILD FAILED (0 rows / stack) -- INCONCLUSIVE"; return
  fi
  local changed verdict names
  changed=$(diff <(LC_ALL=C sort "$base") <(LC_ALL=C sort "$ROOT/$label.rows") | grep -c '^<' || true)
  names=$(diff <(LC_ALL=C sort "$base") <(LC_ALL=C sort "$ROOT/$label.rows") \
          | grep '^<' | sed 's/^< //; s/=.*//' | LC_ALL=C sort -u | tr '\n' ' ')
  verdict=$([ "$changed" -gt 0 ] && echo "OK  moved $changed" || echo "*** BLIND SPOT: 0 rows moved ***")
  echo "$(printf '%-30s' "$label")  rows=$n  $verdict"
  echo "      moved by name: $names"
}

RF=$PWD/.agents/slop/rf-base.txt
IX=$PWD/.agents/slop/ix-base.txt
echo "=== VALUE-CHANGE MUTATIONS inside the renamed defs: each MUST move rows ==="
echo

# is_noop_after_dep: invert the answer of the walk. The five noopf_* rows are its gate.
check tinybendygrad/schedule/rangeify.bend "$RF" vc-is_noop_after_dep \
  's/Nd\{self, noopf\.cont\(ar, self\)\}/Nd{self, Bool.not(noopf.cont(ar, self))}/' \
  'Nd{self, Bool.not(noopf.cont(ar, self))}'

# remove_noop_afters: the `one` branch. rows ab_* / raf_* / dg_* / nv_* depend on it.
check tinybendygrad/schedule/rangeify.bend "$RF" vc-remove_noop_afters \
  's/M\.Hop\{ar, M\.mp_src0\(ar, self\)\}/M.Hop{ar, M.mp_nsrc(ar, self)}/' \
  'M.Hop{ar, M.mp_nsrc(ar, self)}'

# strip_zero_offset_shrink: make the `zero` predicate always false so the arm never fires.
check tinybendygrad/schedule/rangeify.bend "$RF" vc-strip_zero_offset \
  's/Bool\.and\(M\.mp_is\(ar, self, O\.OpsSHRINK\{\}\), rf_zero_off\.go\(rf_offsets\(ar, self\)\)\)/Bool.and(M.mp_is(ar, self, O.OpsSHRINK{}), False{})/' \
  'Bool.and(M.mp_is(ar, self, O.OpsSHRINK{}), False{})'

# realize: upstream realize inserts (tr, None) -- one key, no axis list. Flip `islist`,
# the flag that says "this entry stands for a list"; any row reading it must move.
check tinybendygrad/schedule/indexing.bend "$IX" vc-realize \
  's/^def realize\(tr: U32\) -> IxReal: IxReal\{tr, False\{\}, Nil\{\}\}$/def realize(tr: U32) -> IxReal: IxReal{tr, True{}, Nil{}}/' \
  'def realize(tr: U32) -> IxReal: IxReal{tr, True{}, Nil{}}'

# no_indexing_calls: change the fold's seed from Nil{} to a one-element list, so every
# rebuilt node gains a phantom src. TWO earlier attempts at this mutation failed and
# both failures are the lesson: (1) swapping two ARGS of the rebuild stopped the file
# building, correctly, because `mp_replace`'s params are typed; (2) a `drop_last` call
# written with one `)` too few swallowed the NEXT LINE and the error pointed at an
# innocent `def`. In both cases the patch applied and the diff was over a broken file,
# which is exactly the shape that reads as "the mutation moved nothing".
check tinybendygrad/schedule/rangeify.bend "$RF" vc-no_indexing_calls-seed \
  's/nic\.go\(fuel, Bld\{ar, Nil\{\}\}, M\.mp_srcs\(ar, self\)\)/nic.go(fuel, Bld{ar, [0]}, M.mp_srcs(ar, self))/' \
  'Bld{ar, [0]}'

# realize and broadcast_rngs are reported separately below: both are defs NOTHING CALLS,
# so no body mutation of theirs can move a row. That is a pre-existing coverage gap and
# it is a finding, not a harness failure.
echo
echo "=== the two defs-nothing-calls findings, stated rather than papered over ==="
echo "  realize(tr)      2 callers (realize_srcs.one, ix_rcs_one); NEITHER has a caller."
echo "  broadcast_rngs   0 callers. Mutating its body moves 0 rows: there is no row."
echo "  Both predate this rename. Confirmed: the inverse-rename mutants of both also"
echo "  moved 0 rows, and so did a body mutation of each -- same answer, so the gap is"
echo "  reachability and not the rename."
