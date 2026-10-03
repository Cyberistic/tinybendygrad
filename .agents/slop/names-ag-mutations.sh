#!/usr/bin/env bash
# MUTATION TABLE over the seven renames.
#
# TRAP, HIT AND FIXED: the first version mirrored into $TMPDIR and every mutation
# reported BUILD FAILED -- INCLUDING THE NO-OP CONTROL, which is how the mirror was
# caught being broken rather than the mutants. A $TMPDIR copy cannot resolve Bend's
# RELATIVE imports. The mirror now lives INSIDE the repo, so `./helpers.bend` and
# friends resolve. If a mirror is ever moved out, the control is the check that fails.
#
# The diff is over whole `name=value` LINES, never row names: a name-comparing harness
# reported 0 for all 30 mutations in one unit and all 68 in another.
#
# A rename is not EXPECTED to move rows. What is looked for is the opposite failure --
# a mutant that changes a VALUE. The script reports rows moved and rows only-in-mutant,
# and flags the latter.
set -u
BEND="$PWD/bin/bend"
ROOT="$PWD/.agents/slop/names-ag-mutwork"
rm -rf "$ROOT"; mkdir -p "$ROOT"

run_rows() {   # $1 = absolute bend path
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

check() {      # $1 live file, $2 baseline rows, $3 label, $4 perl-expr
  local f="$1" base="$2" label="$3" expr="$4"
  local rel="${f#tinybendygrad/}"
  local m="$ROOT/$label/tinybendygrad"
  rm -rf "$ROOT/$label"; mkdir -p "$ROOT/$label"
  cp -R tinybendygrad "$m"
  cp -R LAWS "$ROOT/$label/LAWS" 2>/dev/null
  perl -pi -e "$expr" "$m/$rel" || { echo "$(printf '%-32s' "$label")  PATCH FAILED"; return; }
  run_rows "$m/$rel" > "$ROOT/$label.rows"
  local n; n=$(wc -l < "$ROOT/$label.rows" | tr -d ' ')
  if [ "$n" = "0" ] || [ "$(head -1 "$ROOT/$label.rows")" = "AGMUT-STACK-OR-ZERO" ]; then
    echo "$(printf '%-32s' "$label")  BUILD FAILED (0 rows / stack) -- INCONCLUSIVE"; return
  fi
  local moved new shared verdict
  # LC_ALL=C on BOTH sides: the first version used bare `comm`, which is locale
  # collating, and reported 6 spurious differences -- including on the NO-OP CONTROL,
  # which is the only reason the control was worth having. `diff` over two
  # LC_ALL=C-sorted files compares MULTISETS, so duplicate row names cannot fool it.
  verdict=$(diff <(LC_ALL=C sort "$base") <(LC_ALL=C sort "$ROOT/$label.rows") >/dev/null \
            && echo "OK  0 rows moved" || echo "*** ROWS DIFFER ***")
  moved=$(diff <(LC_ALL=C sort "$base") <(LC_ALL=C sort "$ROOT/$label.rows") \
          | grep -c '^<' || true)
  new=$(comm -13 <(LC_ALL=C sort "$base") <(LC_ALL=C sort "$ROOT/$label.rows") | wc -l | tr -d ' ')
  shared=$(comm -23 <(LC_ALL=C sort "$base") <(LC_ALL=C sort "$ROOT/$label.rows") | wc -l | tr -d ' ')
  echo "$(printf '%-32s' "$label")  rows=$n  changed=$moved  only-in-mutant=$new  lost=$shared  $verdict"
}

IX=$PWD/.agents/slop/ix-base.txt
RF=$PWD/.agents/slop/rf-base.txt
echo "=== MUTATION TABLE: inverse-rename each of the 7, in an in-repo mirror ==="
echo "    0 rows moved is the EXPECTED and CORRECT result for a pure rename."
echo
check tinybendygrad/schedule/indexing.bend "$IX" CONTROL-no-mutation      's/\bZZZ_NOT_PRESENT\b/QQQ/g'
check tinybendygrad/schedule/indexing.bend "$IX" invert-realize_realize_srcs 's/\brealize_srcs\b/ix_realize_srcs/g; s/\brealize\b/ix_realize/g'
check tinybendygrad/schedule/indexing.bend "$IX" invert-broadcast_rngs   's/\bbroadcast_rngs\b/ix_broadcast_rngs/g'
check tinybendygrad/schedule/rangeify.bend  "$RF" invert-is_noop_after_dep 's/\bis_noop_after_dep\b/rf_is_noop_after_dep/g'
check tinybendygrad/schedule/rangeify.bend  "$RF" invert-no_indexing_calls 's/\bno_indexing_calls\b/rf_no_indexing_calls/g'
check tinybendygrad/schedule/rangeify.bend  "$RF" invert-remove_noop_afters 's/\bremove_noop_afters\b/rf_remove_noop_afters/g'
check tinybendygrad/schedule/rangeify.bend  "$RF" invert-strip_zero_offset 's/\bstrip_zero_offset_shrink\b/rf_strip_zero_offset_shrink/g'
echo
echo "=== a rename that SHOULD be caught: change the VALUE inside one renamed def ==="
check tinybendygrad/schedule/rangeify.bend  "$RF" value-change-is_noop_after_dep 's/\bis_noop_after_dep\b/rf_is_noop_after_dep/g; s/def noopf_go\(O\.Arena\.budget\(ar\), ar, Nd\{self, noopf\.cont\(ar, self\)\}\)/def noopf_go(O.Arena.budget(ar), ar, Nd{self, U32.add(noopf.cont(ar, self), 1)})/'