#!/bin/sh
# helpers-i64-mutate.sh -- the MUTATION TABLE for the six 64-bit helpers this unit
# added to tinybendygrad/helpers.bend: i64_or, i64_and, i64_shl, i64_div, i64_mod,
# gcd. Twelve mutations, two per helper, plus two controls.
#
#   sh .agents/slop/helpers-i64-mutate.sh
#
# A mutation is only evidence if it MOVES a row, and a row is only evidence if the
# FIXTURE REACHES THE BRANCH. So this script prints, for every mutation, the names of
# the rows whose value changed -- not a count -- because "which rows" and "what they
# became" have different answers and only the second one tells a mutation from its
# twin. The two CONTROLS are mutations that are arithmetically no-ops (OR and AND are
# commutative, so swapping the operands changes nothing): a control that moved rows
# would mean the diff is reading something other than the value.
#
# IT RUNS THE LANES ITSELF AND NOT `helpers-tc-gate.sh`, because that script exits
# non-zero ON A DIFF: the first run of this harness called it and reported all twelve
# mutations as "the lane is red", which is the one reading a mutation must never get.
# A mutation that moves rows and a mutation that breaks the file are different
# findings and the exit code cannot tell them apart.
#
# `pm_gf` is a Fibonacci pair ON PURPOSE. It is the only row whose operands are both
# below 2**32, and it is there for the OTHER reason -- it is the row that reaches the
# `gcd` fuel bound rather than the 64-bit branches -- so M12 below moves it and the
# width mutations leave it alone. A table where every mutation moves every row cannot
# tell those two apart.
set -e
cd "$(dirname "$0")/../.."

HB=tinybendygrad/helpers.bend
BD=.agents/slop/helpers-tc-gate.bd
BN=.agents/slop/helpers-tc-gate.bn
BIN=.agents/slop/helpers-tc-gate.bin
BAK=$(mktemp)
cp "$HB" "$BAK"
trap 'cp "$BAK" "$HB"; rm -f "$BAK"' EXIT

run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" > "$out.tmp" 2> "$out.err" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  return 1
}

lanes() {
  DEFAULT_FLOAT=f16 DEFAULT_INT=i64 NO_COLOR=1 run_lane "$BD" \
    ./bin/bend .agents/slop/helpers-tc.bend &&
  DEFAULT_FLOAT=f16 DEFAULT_INT=i64 NO_COLOR=1 ./bin/bend \
    .agents/slop/helpers-tc.bend -o "$BIN" &&
  DEFAULT_FLOAT=f16 DEFAULT_INT=i64 NO_COLOR=1 run_lane "$BN" "$BIN"
}

lanes || { echo "baseline lane red -- fix that first"; exit 1; }
cp "$BD" "$BD.base"

mutate() {  # $1 = id, $2 = from, $3 = to, $4 = what it should move, $5 = "ctl"
  id=$1; from=$2; to=$3; want=$4; kind=${5:-mut}
  if ! grep -qF "$from" "$HB"; then
    echo "$id  MUTATION TARGET NOT FOUND -- $from"
    VERDICT="$VERDICT $id:target-not-found"
    return 0
  fi
  perl -0pi -e "s/\Q$from\E/$to/" "$HB"
  if lanes; then
    if diff -q "$BN" "$BD" > /dev/null; then
      moved=$(diff "$BD.base" "$BD" | grep '^<' | sed 's/^< //' | cut -d= -f1 | tr '\n' ' ')
      if [ -z "$moved" ]; then
        echo "$id  MOVES NOTHING (blind)  want: $want"
        if [ "$kind" = ctl ]; then
          VERDICT="$VERDICT $id:ok(control-blind)"
        else
          VERDICT="$VERDICT $id:BLIND"
        fi
      else
        first=$(echo "$moved" | cut -d' ' -f1)
        before=$(grep "^$first=" "$BD.base" || true)
        after=$(grep "^$first=" "$BD" || true)
        n=$(echo "$moved" | wc -w | tr -d ' ')
        echo "$id  $n rows  want: $want"
        echo "     $moved"
        echo "     $first's VALUE: $before -> $after"
        if [ "$kind" = ctl ]; then
          VERDICT="$VERDICT $id:CONTROL-LEAKED($n)"
        else
          VERDICT="$VERDICT $id:ok($n)"
        fi
      fi
    else
      echo "$id  INTERPRETED AND COMPILED LANES DISAGREE"
      VERDICT="$VERDICT $id:lanes-disagree"
    fi
  else
    echo "$id  LANE RED (did not compile or run)"
    VERDICT="$VERDICT $id:lane-red"
  fi
  cp "$BAK" "$HB"
}

VERDICT=

echo "=== i64_or ==="
mutate M01 "U32.or(hi32(a), hi32(b)), U32.or(lo32(a), lo32(b))" \
          "U32.and(hi32(a), hi32(b)), U32.or(lo32(a), lo32(b))" \
          "the HIGH word: pm_wide_or 4294967295:4294967295 -> 0:4294967295, pm_zerod_or, pm_nepo_or"
mutate M02 "U32.or(hi32(a), hi32(b)), U32.or(lo32(a), lo32(b))" \
          "U32.or(hi32(a), hi32(b)), U32.xor(lo32(a), lo32(b))" \
          "the LOW word: pm_small_or 0:7 -> 0:6, pm_big_or, pm_nege_or, pm_gf_or"

echo "=== i64_and ==="
mutate M03 "U32.and(hi32(a), hi32(b)), U32.and(lo32(a), lo32(b))" \
          "U32.or(hi32(a), hi32(b)), U32.and(lo32(a), lo32(b))" \
          "the HIGH word: pm_wide_and 0:0 -> 4294967295:0, pm_ovf_and, pm_zero_and"
mutate M04 "U32.and(hi32(a), hi32(b)), U32.and(lo32(a), lo32(b))" \
          "U32.and(hi32(a), hi32(b)), U32.and(lo32(a), 4294967295)" \
          "the LOW word's mask, on every row whose two low words differ: pm_zerod_and 0:0 -> 0:7, pm_small_and, pm_gf_and"

echo "=== i64_shl ==="
# M05 and M06 ALSO MOVE THE `pm_*_div` ROWS, and that is not a leak: the restoring
# divider builds its quotient bit as `i64_or(q, i64_shl(bit, k))`, so the shift and
# the or are load-bearing FOR THE DIVISION. A mutation's moved-row list is a claim
# about which defs it reached, not only about the one it was aimed at.
mutate M05 "i64_shl.hi(lo, k))" "i64_shl.hi(hi, k))" \
          "the k >= 32 high word read from hi: sh_k63_shl 2147483648:0 -> 0:0, sh_k33_shl, sh_neg33_shl"
mutate M06 "U32.shrn(lo, Nat.sub(32n, k))), U32.shln(lo, k))" \
          "U32.shrn(hi, Nat.sub(32n, k))), U32.shln(lo, k))" \
          "the low word's carry, for k < 32: sh_k1_shl 610839793:897170912 -> 610839792:897170912, sh_k31_shl"

echo "=== i64_div ==="
mutate M07 "i64_bit(Bool.to_u32(i64_divmod.up(flip, r)))" "i64_bit(0)" \
          "the FLOOR CORRECTION, i.e. truncated division: pm_nepo_div 4294967295:4294967292 -> 4294967295:4294967295"
mutate M08 "+flip = Bool.xor(an, bn)" "+flip = Bool.not(Bool.xor(an, bn))" \
          "WHICH pairs are opposite-sign: pm_small_div 0:1 -> 4294967295:4294967294, pm_big_div, pm_nege_div"

echo "=== i64_mod ==="
mutate M09 "  i64_neg(bn, Bool.pick(I64, i64_divmod.up(flip, r), i64_sub(mb, r), r))" \
          "  Bool.pick(I64, i64_divmod.up(flip, r), i64_sub(mb, r), r)" \
          "the remainder's SIGN: pm_nege_mod 4294967295:4294967292 -> 0:4, pm_pone_mod, pm_nepo_mod"
mutate M10 "i64_sub(mb, r), r))" "r, r))" \
          "the inexact opposite-sign MAGNITUDE: pm_nepo_mod 0:1 -> 0:3, pm_mini_mod, pm_pone_mod"

echo "=== gcd ==="
mutate M11 "gcd.go(128n, i64_abs(a), i64_abs(b))" "gcd.go(128n, a, b)" \
          "dropping the MAGNITUDES: pm_nege_gcd 0:1 -> 4294967295:4294967295, pm_pone_gcd, pm_maxi_gcd, pm_ovf_gcd"
mutate M12 "gcd.go(128n, i64_abs(a), i64_abs(b))" "gcd.go(1n, i64_abs(a), i64_abs(b))" \
          "the FUEL: one step answers the DIVISOR (not the dividend), so the ten rows whose gcd is not the divisor move -- pm_small_gcd 0:1 -> 0:3, pm_gf_gcd -> 0:472537396, pm_gneg_gcd. The five it does NOT move are pm_zero, pm_zerod, pm_maxi, pm_ovf and pm_gbig, and each of those has the DIVISOR ALREADY EQUAL TO THE GCD, so one Euclid step suffices and the fuel is not what answers them. A mutation whose blind set is explained is a different thing from one whose blind set is not."

echo "=== CONTROLS (must move NOTHING) ==="
mutate C01 "U32.or(hi32(a), hi32(b)), U32.or(lo32(a), lo32(b))" \
          "U32.or(hi32(b), hi32(a)), U32.or(lo32(b), lo32(a))" \
          "nothing -- OR is commutative" ctl
mutate C02 "U32.and(hi32(a), hi32(b)), U32.and(lo32(a), lo32(b))" \
          "U32.and(hi32(b), hi32(a)), U32.and(lo32(b), lo32(a))" \
          "nothing -- AND is commutative" ctl

rm -f "$BD.base" "$BN.err"
# The tally is the point of the script. A table that only prints a moved-row list
# reads the same whether 12 mutations are load-bearing or 0, which is exactly how
# this harness managed to report 14/14 BLIND for a month: the list was empty every
# time and nothing said so. Exit non-zero on any blind mutation, any control that
# leaked, and any lane that went red.
echo
echo "=== TALLY ==="
for v in $VERDICT; do echo "  $v"; done
bad=$(echo "$VERDICT" | tr ' ' '\n' | grep -cE "BLIND|LEAKED|lane-red|target-not-found|lanes-disagree" || true)
good=$(echo "$VERDICT" | tr ' ' '\n' | grep -c ":ok" || true)
echo "helpers-i64-mutate: $good of 14 as expected, $bad not"
[ "$bad" -eq 0 ] || exit 1
echo "helpers-i64-mutate: done"
