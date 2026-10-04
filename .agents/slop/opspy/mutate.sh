#!/bin/zsh
# OPSPY PLANT AND DISARM.  Copy $T := ${TMPDIR}/opspy.  Run with zsh.
#
# WHY THIS SCRIPT MUTATES THE LIVE FILE AND NOT A $TMPDIR COPY.  `ops_python.bend`
# resolves `../base.bend`, `../dtype.bend`, `../uop/ops.bend` and
# `../uop/symbolic.bend` RELATIVE TO ITS OWN PATH, and a scratch copy cannot
# resolve a relative import -- MEASURED in this tree, where it produced 22 phantom
# blind spots in another unit.  So the copy cannot be relocated: it is mutated in
# place and restored from a backup, with a trap on every signal and a `cmp`
# assertion at the end that the restore actually happened.  FROMBITS recorded a run
# killed by the tool timeout leaving plant P1 SITTING IN THE LIVE TREE, compiling
# clean and answering a plausible float for 214016 rows.
#
# ---------------------------------------------------------------------------
# TWO WAYS THIS HARNESS LIED ON ITS FIRST RUN, BOTH FIXED HERE.  Both are the
# "a result that contradicts the tool's own error message is a suspect result"
# trap wearing a different hat, and both printed a NUMBER while the file did not
# compile.
#
#  1. THE E2E LANE RAN A STALE BINARY.  `bend -o` on a file that does not compile
#     leaves the PREVIOUS exe in place, so `gate.py` was handed the BASE build and
#     reported "rows=6" for a mutation that never ran.  `rm -f` before every build,
#     and the build's OWN exit status decides whether the lane runs at all.
#  2. A COMPILE ERROR REPORTED AS A ROW MOVEMENT.  D1's first spelling,
#     `F32{U32{b}}`, is not Bend -- `U32`'s field is `data` -- and `--check-only`
#     named 4 red defs instead of the 8 inherited ones.  The harness counted that
#     as "moved=85 of 85", i.e. a whole-file failure read as 85 changed answers.
#     So EVERY step below must first show EXACTLY the 8 inherited laws, or it
#     prints DID-NOT-COMPILE and reports no row counts at all.
#
# The harness diffs WHOLE `name=value` LINES, NEVER ROW NAMES.  A name-comparing
# harness reported 0 for all 30 mutations in one unit and 0 for all 68 in another.

set -u
T=${TMPDIR%/}/opspy
F=tinybendygrad/runtime/ops_python.bend

cp "$F" "$T/orig.bend"
restore() {
  cp "$T/orig.bend" "$F"
  cmp -s "$T/orig.bend" "$F" && print "RESTORE ok  $(md5 -q "$F")" \
                             || print "RESTORE **FAILED** -- the live file differs from its backup"
}
trap restore EXIT INT TERM HUP

# THE BASELINE RED SET IS NOW **ZERO**, and that is a fact about the tree, not a
# weakening of the gate.  `dtype.bend`'s eight laws were ALL inherited -- this file
# never declared one -- and the unit that owns `dtype.bend` filled them while this
# unit was measuring, so `dtype.bend --check-only` and `ops_python.bend
# --check-only` both read ALL PROOFS CHECK and `substrate-check.sh` reads WARM.
# THE ZERO IS DERIVED, never typed: it is the red count of the file as it stands,
# so the next substrate change moves the baseline instead of silently blinding it.
BASE_RED=$(./bin/bend "$F" --check-only 2>&1 | grep -c '^- ')
print "baseline red defs in this file: $BASE_RED  (all inherited from ../dtype.bend; 0 own)"

red() { ./bin/bend "$F" --check-only 2>&1 | grep -c '^- '; }

run() {
  print -- "----- $1 -----"
  local r=$(red)
  if [[ $r -ne $BASE_RED ]]; then
    print "  DID NOT COMPILE (--check-only names $r red defs, the baseline is $BASE_RED)."
    print "  no row count is reported: a compile error is not a movement."
    ./bin/bend "$F" --check-only 2>&1 | grep -E '^(Error|- |bend:|expected|observed)' | head -5 | sed 's/^/    /'
    return
  fi
  rm -f "$T/m.exe"
  ./bin/bend "$F" -o "$T/m.exe" >/dev/null 2>&1
  if [[ ! -x "$T/m.exe" ]]; then print "  DID NOT BUILD; no row count."; return; fi

  ./bin/bend "$F" > "$T/m.txt" 2>/dev/null
  local own=$(diff "$T/gate-new.txt" "$T/m.txt" | grep -c '^[<>]')
  print "  own-gate    moved=$own of $(grep -c '=' "$T/gate-new.txt") rows"

  .venv/bin/python .agents/slop/nested/gate.py "$T/m.exe" > "$T/n.txt" 2>&1
  local tot=$(grep -cE '^[a-z]+[0-9]' "$T/n.txt")
  local ok=$(grep -cE '^[a-z]+[0-9].*  True  ' "$T/n.txt")
  print "  e2e         rows=$ok of $tot cases all-words-bit-identical vs CPython"
  diff <(grep -v '^executor ' "$T/nested-new.txt") <(grep -v '^executor ' "$T/n.txt") \
    | grep -E '^[<>][[:space:]]*[a-z]+[0-9]' | sed 's/^/    /'
}

cp "$T/exec-new" "$T/exec-ref.exe"
run "BASE (the dedup: F.F32.from_bits at both sites)"

# ---- DISARM D1.  THE SAME FUNCTION BY A DIFFERENT EXPRESSION ---------------
# `F32.from_bits` is ONE destructuring plus ONE constructor -- both payloads are
# the same type `Word(32n)`, so the constructor was already the bitcast -- so
# writing that destructuring out in full, in place, is the same function spelled
# longhand.  The pair goes in ABOVE both of its callers, because Bend refuses a
# forward reference and appending it made this disarm fail to BUILD on an earlier
# run -- which the harness then reported as a movement.
# A disarm is only a disarm if it is the same FUNCTION; both of FROMBITS' failed
# disarms turned "the same test" into "the other test" and each moved tens of
# thousands of rows.
perl -0pi -e 's{^import \.\./base\.bend as F\n}{}m' "$F"
perl -0pi -e 's{F\.F32\.from_bits\(b\)}{F32{w32b(b)}}g' "$F"
perl -0pi -e 's{^(import \.\./uop/symbolic\.bend as SY\n)}{$1
def w32b(+u: U32) -> Word(32n):
  match u:
    case U32{data}: data
}m' "$F"
run "DISARM D1  from_bits(b) -> the inline destructuring + constructor (SAME FUNCTION)"
restore

# ---- PLANT P1.  THE DOCUMENTED WRONG PRIMITIVE ---------------------------
# `U32.to_f32` is the NUMERIC conversion, not the bitcast: `U32.to_f32(3)` is 3.0.
# FROMBITS measured this exact substitution moving 214016 of 463360 rows in
# dtype.bend's census and COMPILING CLEAN.  This is the same plant aimed at this
# file's two sites, and the point of it here is the COMPILE: a device that answers
# a plausible float for the wrong reason is the failure this project pays for.
perl -0pi -e 's{F\.F32\.from_bits\(b\)}{U32.to_f32(b)}g' "$F"
run "PLANT  P1  F32.from_bits -> U32.to_f32  (the numeric conversion, not the bitcast)"

restore
print ""
print "the live file's own --check-only, after the restore:"
./bin/bend "$F" --check-only 2>&1 | sed 's/^/  /'