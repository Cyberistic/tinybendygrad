#!/bin/bash
# MUTATION TABLE for the LANDED i64_mul, mutating the REAL tinybendygrad/helpers.bend
# and re-running the gate that reaches it through H. Every row is diffed as a whole
# `name=value` line. A mutation that moves nothing is a blind spot with a reason, not
# a row that encodes the bug.
#
# DISARMS FIRST: the ones that remove correctness must make the gate FAIL.
set -u
cd "$(dirname "$0")"
BEND=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
HELPERS=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinybendygrad/helpers.bend
# ⚠ THE BACKUP MUST BE TAKEN ONCE, BEFORE ANY MUTATION, AND THE BASELINE MUST BE
# RE-VERIFIED AFTER THE RESTORE. MEASURED THE HARD WAY: a harness that re-copied
# `$HELPERS` into its backup slot *inside* the loop backed up a MUTATED file, and the
# final restore left `, 1)` sitting in `pp_core`'s high word -- which the gate then
# reported as 442/442 green for one run and 884/884 disagreeing for the next. That is
# the worst shape for a restore bug: it survives a green gate.
PRISTINE=helpers.pristine.bend
if [ ! -f "$PRISTINE" ]; then cp "$HELPERS" "$PRISTINE"; fi
cp "$PRISTINE" helpers.orig.bak
PRISTINE_MD5=$(md5 -q "$PRISTINE")

run_mut () {
  name="$1"; kind="$2"; from="$3"; to="$4"
  python3 - "$from" "$to" <<'PY'
import sys
p="/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinybendygrad/helpers.bend"
s=open(p).read()
frm,to=sys.argv[1],sys.argv[2]
if frm not in s:
    open("/tmp/i64mul_nomatch","w").write(frm)
    sys.exit(3)
open(p,"w").write(s.replace(frm,to,1))
PY
  if [ $? -eq 3 ]; then
    echo "MUT $name [$kind]: PATTERN NOT FOUND -- this is a harness fault, not a result"
    cp "$PRISTINE" "$HELPERS"; return
  fi
  if cmp -s helpers.pristine.bend "$HELPERS"; then
    echo "MUT $name [$kind]: mutation was a NO-OP (not a result)"
    cp "$PRISTINE" "$HELPERS"; return
  fi
  python3 gen_gate.py >/dev/null 2>&1
  "$BEND" gate.bend 2>/dev/null | grep -E '^[ms]_' > got.mut.txt
  exp_n=$(wc -l < expected.txt | tr -d ' ')
  got_n=$(wc -l < got.mut.txt | tr -d ' ')
  if [ "$got_n" -eq 0 ]; then
    echo "MUT $name [$kind]: gate produced 0 rows (broke the build)"
  else
    moved=$(comm -3 <(sort expected.txt) <(sort got.mut.txt) | grep -c '^' || true)
    nmut=$(comm -3 <(sort expected.txt) <(sort got.mut.txt) | grep -c '^[^ \t]' || true)
    echo "MUT $name [$kind]: rows_present=$got_n/$exp_n lines_disagreeing=$moved rows_changed=$nmut"
    comm -3 <(sort expected.txt) <(sort got.mut.txt) | head -4 | sed 's/^/      /'
  fi
  cp "$PRISTINE" "$HELPERS"
}

echo "=== baseline (unmutated): the gate must be green for a mutation to mean anything ==="
python3 gen_gate.py >/dev/null 2>&1
"$BEND" gate.bend 2>/dev/null | grep -E '^[ms]_' > got.txt
echo "rows_present=$(wc -l < got.txt | tr -d ' ')/$(wc -l < expected.txt | tr -d ' ') disagree=$(comm -3 <(sort expected.txt) <(sort got.txt) | grep -c '^')"

echo
echo "===== DISARMS (must move rows / fail the gate) ====="
run_mut drop_carry            disarm "U32.shln(Bool.to_u32(U32.is_lt(cross, p10)), 16n)" "0"
run_mut carry_at_bit0         disarm "U32.shln(Bool.to_u32(U32.is_lt(cross, p10)), 16n)" "Bool.to_u32(U32.is_lt(cross, p10))"
run_mut cross_in_low_word     disarm "i64_of_hi_lo(U32.add(U32.mul(al, bh), U32.mul(ah, bl)), 0)" "i64_of_hi_lo(0, U32.add(U32.mul(al, bh), U32.mul(ah, bl)))"
run_mut no_carry_out_of_t     disarm "U32.add(U32.add(p11, carry), Bool.to_u32(U32.is_lt(t, p00)))" "U32.add(p11, carry)"
run_mut limbs_swapped         disarm "+al = U32.and(a, 65535)" "+al = U32.shrn(a, 16n)"
run_mut no_sign_flip          disarm "i64_neg(Bool.xor(i64_is_neg(a), i64_is_neg(b)), u64_mul(i64_abs(a), i64_abs(b)))" "u64_mul(i64_abs(a), i64_abs(b))"
run_mut i64_mul_is_zero       disarm "i64_neg(Bool.xor(i64_is_neg(a), i64_is_neg(b)), u64_mul(i64_abs(a), i64_abs(b)))" "i64_zero()"
run_mut u64_mul_is_zero       disarm "u64_mul_parts(lo32(a), hi32(a), lo32(b), hi32(b))" "u64_mul_parts(0, 0, 0, 0)"

echo
echo "===== PLANTS (a wrong answer that must move rows) ====="
run_mut plant_high_plus_one   plant  "U32.add(U32.add(p11, carry), Bool.to_u32(U32.is_lt(t, p00)))" "U32.add(U32.add(U32.add(p11, carry), Bool.to_u32(U32.is_lt(t, p00))), 1)"
run_mut plant_unsigned_in_signed plant "i64_neg(Bool.xor(i64_is_neg(a), i64_is_neg(b)), u64_mul(i64_abs(a), i64_abs(b)))" "u64_mul(a, b)"
run_mut plant_cross_plus_one  plant  "i64_of_hi_lo(U32.add(U32.mul(al, bh), U32.mul(ah, bl)), 0)" "i64_of_hi_lo(U32.add(U32.add(U32.mul(al, bh), U32.mul(ah, bl)), 1), 0)"

cp "$PRISTINE" "$HELPERS"
NOW_MD5=$(md5 -q "$HELPERS")
echo
echo "=== RESTORE VERIFIED ==="
echo "  pristine md5=$PRISTINE_MD5"
echo "  restored md5=$NOW_MD5"
[ "$PRISTINE_MD5" = "$NOW_MD5" ] && echo "  RESTORE OK" || { echo "  *** RESTORE FAILED -- helpers.bend IS NOT PRISTINE ***"; exit 1; }
python3 gen_gate.py >/dev/null 2>&1
"$BEND" gate.bend 2>/dev/null | grep -E '^[ms]_' > got.txt
echo "  post-restore gate: rows=$(wc -l < got.txt | tr -d ' ')/$(wc -l < expected.txt | tr -d ' ') disagree=$(comm -3 <(sort expected.txt) <(sort got.txt) | grep -c '^')"