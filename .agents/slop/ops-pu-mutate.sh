#!/bin/sh
# ops-pu-mutate.sh -- the MUTATION TABLE for `print_uops` (render.bend), whose gate is
# ops-pu-gate.sh. Six mutations and one control.
#
#   sh .agents/slop/ops-pu-mutate.sh
#
# WHY THIS TABLE EXISTS WHEN THE GATE IS ALREADY GREEN. Every bug the gate found while it
# was being written was a FORMATTING bug, and a formatting bug is invisible to a gate that
# compares values: an inverted pad, a quoted integer, a bracket nobody opened. A
# name-to-value table would have been green through all of them. So each one is pinned
# here as a mutation, and the table is the argument for the line diff.
#
# IT RUNS THE LANES ITSELF and not `ops-pu-gate.sh`, because that script exits non-zero ON
# A DIFF: a harness that called it would report every mutation as "the gate is red", which
# is the one reading a mutation must never get. A mutation that moves rows and a mutation
# that breaks the file are different findings and an exit code cannot tell them apart.
#
# `bend`'s machine stack overflows on ~1 run in 20 and then prints ZERO rows, which is
# indistinguishable from "did not start", so every lane is retried while its row count is
# not 9. A lane that is genuinely empty would loop forever, and that is the intended
# failure.
set -e
cd "$(dirname "$0")/../.."

RB=tinybendygrad/uop/render.bend
GT=.agents/slop/ops-pu-gate
BD=$GT-bd.txt
BN=$GT-bn.txt
BIN=$GT.bin
BAK=$(mktemp)
cp "$RB" "$BAK"
trap 'cp "$BAK" "$RB"; rm -f "$BAK"' EXIT

ROWS=9

run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" 2> "$out.err" | grep '^pu_' > "$out.tmp"; then
      if [ "$(wc -l < "$out.tmp" | tr -d ' ')" = "$ROWS" ]; then
        mv "$out.tmp" "$out"
        return 0
      fi
    fi
  done
  return 1
}

lanes() {
  run_lane "$BD" ./bin/bend "$RB" &&
  ./bin/bend "$RB" -o "$BIN" &&
  run_lane "$BN" "$BIN"
}

lanes || { echo "baseline lane red -- fix that first"; exit 1; }
cp "$BD" "$BD.base"

mutate() {  # $1 = id, $2 = from, $3 = to, $4 = what it should move, $5 = "ctl"
  id=$1; from=$2; to=$3; want=$4; kind=${5:-mut}
  if ! grep -qF "$from" "$RB"; then
    echo "$id  MUTATION TARGET NOT FOUND -- $from"
    VERDICT="$VERDICT $id:target-not-found"
    return 0
  fi
  perl -0pi -e "s/\Q$from\E/$to/" "$RB"
  if lanes; then
    if diff -q "$BN" "$BD" > /dev/null; then
      moved=$(diff "$BD.base" "$BD" | grep '^<' | sed 's/^< //' | cut -d'|' -f1 | sort -u | tr '\n' ' ')
      if [ -z "$moved" ]; then
        echo "$id  MOVES NOTHING (blind)  want: $want"
        if [ "$kind" = ctl ]; then
          VERDICT="$VERDICT $id:ok(control-blind)"
        else
          VERDICT="$VERDICT $id:BLIND"
        fi
      else
        echo "$id  moves: $moved"
        echo "     want: $want"
        if [ "$kind" = ctl ]; then
          VERDICT="$VERDICT $id:LEAKED"
        else
          VERDICT="$VERDICT $id:ok"
        fi
      fi
    else
      echo "$id  the two lanes DISAGREE with each other -- the diff cannot be read"
      VERDICT="$VERDICT $id:lanes-disagree"
    fi
  else
    echo "$id  lane red -- the mutation does not compile or prints the wrong row count"
    VERDICT="$VERDICT $id:lane-red"
  fi
  cp "$BAK" "$RB"
}

echo "=== the four PADS, which were ALL INVERTED when the gate was written ==="
# CPython's `f"{x:20s}"` pads a STRING ON THE RIGHT and `f"{i:4d}"` pads a NUMBER ON THE
# LEFT. Every pad below is the INVERSION, so each is a bug that was actually there.
mutate P01 "H.pad_left(Nat.show(U32.to_nat(i)), 4)" "H.pad_right(Nat.show(U32.to_nat(i)), 4)" \
          "the COUNTER, padded right instead of left: every row, because the counter is the first field and a whole-line diff cannot miss a shifted line. The op, dtype and srcs fields then all sit three columns further right."
mutate P02 "H.pad_right(O.Ops.name(O.Arena.op(ar, u)), 20)" "H.pad_left(O.Ops.name(O.Arena.op(ar, u)), 20)" \
          "the OP NAME, padded left instead of right: every row whose op name is shorter than 20, which is all of them -- Ops.BUFFER is 10, Ops.CONST is 9. The trailing ':' moves and so does everything after it."
mutate P03 "H.pad_right(pu_dtype(tb, ar, u), 40)" "H.pad_left(pu_dtype(tb, ar, u), 40)" \
          "the DTYPE, padded left instead of right: every row. dtypes.i32 is 10 and dtypes.weakint is 14, both well under 40."
mutate P04 "H.pad_right(pu_srcs(ar, uops, u), 32)" "H.pad_left(pu_srcs(ar, uops, u), 32)" \
          "the SRCS, padded left instead of right: every row. A src list is at most 13 characters here, well under 32."

echo "=== the two bugs that were NOT about padding ==="
mutate P05 "U32.show(pu_pos(uops, x, 0))" "U32.show(x)" \
          "the INDEX, back to the src's ARENA SLOT: pu_index only, and ONLY that row, because it is the only one whose row list is not the arena's own order. pu_const's list IS in arena order, so the slot and the position agree there and this mutation is invisible on it -- which is the reason pu_index is in the table at all."
mutate P06 'Bool.pick(String, first, "[]", "]")' 'Bool.pick(String, first, "[", "]")' \
          "the EMPTY LIST, which then does not open its own bracket: every row that holds a CONST with no srcs, so pu_const, pu_index and pu_constarg. The BUFFER and ADD rows are untouched, and that asymmetry is the claim -- the bug is only reachable through the Nil arm."

echo "=== CONTROLS (must move NOTHING) ==="
# A no-op rewrite of the same value: `String.concat` of one element is that element, so
# the line is longer and the output is identical. A control that moved rows would mean the
# diff is reading something other than the rendered text.
mutate C01 "H.pad_left(Nat.show(U32.to_nat(i)), 4)" \
          "H.pad_left(String.concat([Nat.show(U32.to_nat(i))]), 4)" \
          "nothing -- concat of one element is that element" ctl

rm -f "$BD.base"
echo
echo "=== TALLY ==="
for v in $VERDICT; do echo "  $v"; done
bad=$(echo "$VERDICT" | tr ' ' '\n' | grep -cE "BLIND|LEAKED|lane-red|target-not-found|lanes-disagree" || true)
good=$(echo "$VERDICT" | tr ' ' '\n' | grep -c ":ok" || true)
echo "ops-pu-mutate: $good of 7 as expected, $bad not"
[ "$bad" -eq 0 ] || exit 1
echo "ops-pu-mutate: done"
