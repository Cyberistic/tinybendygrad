#!/bin/zsh
# OPSPY DEDUP VERIFICATION.  Copy $T := ${TMPDIR}/opspy.  Run with zsh.
#
# THE QUESTION: does importing `../base.bend`'s `F32.from_bits` instead of the
# local `w32`/`f32_of` pair change ONE ANSWER?  Both spellings are the identity on
# `Word(32n)` -- a float's payload and an integer's payload are the same type, so
# the constructor `F32{..}` WAS already the bitcast -- so they must agree on every
# pattern, and the gate is the whole compiled device against CPython rather than a
# comparison of the two functions.
#
# TWO LANES, and both diff WHOLE LINES, never row names:
#   1. the file's OWN gate, `./bin/bend <file>` with no PACKET, which runs
#      `gate()` and prints 85 `name=value` rows;
#   2. `.agents/slop/nested/gate.py`, which runs the COMPILED executor as a
#      separate process over 10 packets written by the port's own encoder and
#      compares the WHOLE output buffer, word by word and bit by bit, against
#      `oracle-<case>.json` -- and those oracles were written by CALLING CPython's
#      `Device['PYTHON']`.
#
# The file cannot be relocated (its four imports are relative), so the
# pre-dedup spelling is put back IN PLACE, measured, and restored.  The trap and
# the closing `cmp` are the point: FROMBITS' first mutate.sh died to the tool
# timeout and left a plant in the live tree.

set -u
T=${TMPDIR%/}/opspy
F=tinybendygrad/runtime/ops_python.bend

cp "$F" "$T/dedup.bend"
restore() {
  cp "$T/dedup.bend" "$F"
  cmp -s "$T/dedup.bend" "$F" && print "RESTORE ok  $(md5 -q "$F")" \
                             || print "RESTORE **FAILED**"
}
trap restore EXIT INT TERM HUP

lanes() {
  local tag=$1
  rm -f "$T/$tag.exe"
  ./bin/bend "$F" -o "$T/$tag.exe" >/dev/null 2>&1 || { print "$tag: DID NOT BUILD"; return 1 }
  ./bin/bend "$F" > "$T/$tag.own" 2>/dev/null
  .venv/bin/python .agents/slop/nested/gate.py "$T/$tag.exe" > "$T/$tag.e2e" 2>&1
  print "  $tag  own rows=$(grep -c '=' "$T/$tag.own")  e2e $(grep -cE '^[a-z]+[0-9].*  True  ' "$T/$tag.e2e")/$(grep -cE '^[a-z]+[0-9]' "$T/$tag.e2e") cases"
}

print "== A. AFTER (the dedup: F.F32.from_bits at ops_python.bend:551 and :611)"
lanes after

# ---- put the pre-dedup spelling back ---------------------------------------
# The local `w32`/`f32_of` pair as ops_python.bend carried it, restored from the
# copy FROMBITS quoted, and the two call sites pointed at `f32_of` again.
#
# THE PAIR GOES BACK WHERE IT WAS, not at the end of the file: Bend refuses a
# forward reference, and appending it made the "BEFORE" build fail -- which the
# first run of this script reported as a DIFFERS rather than as a build that never
# happened.  It lived at ops_python.bend:274-278, above both of its callers.
perl -0pi -e 's{^import \.\./base\.bend as F\n}{}m' "$F"
perl -0pi -e 's{F\.F32\.from_bits\(b\)}{f32_of(b)}g' "$F"
perl -0pi -e 's{^(# ==========
(?:[^\n]*\n)*?# INVERSE)}
 {$1}ms' "$F" 2>/dev/null
perl -0pi -e 's{^(import \.\./uop/symbolic\.bend as SY\n)}{$1
def w32(+u: U32) -> Word(32n):
  match u:
    case U32{data}: data

def f32_of(+u: U32) -> F32: F32{w32(u)}
}m' "$F"
print ""
print "== B. BEFORE (the local w32/f32_of pair, exactly as FROMBITS quoted it)"
print "   pre-dedup call sites: $(grep -c 'f32_of(b)' "$F")   local pair: $(grep -c '^def f32_of' "$F") def"
lanes before

print ""
print "== C. THE COMPARISON"
# EVERY lane must EXIST before it is compared.  `diff` against a missing file
# prints to stderr and yields no output lines, so an earlier version of this
# script reported "BYTE-IDENTICAL, 10 cases" for a run that never happened.
for f in after.own after.e2e before.own before.e2e; do
  [[ -s "$T/$f" ]] || { print "  ** $f is absent or empty -- no verdict is possible"; restore; exit 1; }
done
cmp -s "$T/after.own" "$T/before.own" \
  && print "  own gate: BYTE-IDENTICAL, $(wc -l < "$T/after.own") rows" \
  || { print "  own gate: **DIFFERS**"; diff "$T/after.own" "$T/before.own" | head; }
if cmp -s <(grep -v '^executor ' "$T/after.e2e") <(grep -v '^executor ' "$T/before.e2e"); then
  print "  e2e gate: BYTE-IDENTICAL, $(grep -cE '^[a-z]+[0-9]' "$T/after.e2e") cases"
  print "           (line 1 is the exe's own path, which differs by construction and is not an answer)"
else
  print "  e2e gate: **DIFFERS**"; diff "$T/after.e2e" "$T/before.e2e"
fi
restore
print ""
print "the live file after the restore:"
./bin/bend "$F" --check-only 2>&1 | sed 's/^/  /'