#!/bin/sh
# ops-pu-mutate.sh -- the MUTATION TABLE for `print_uops` (render.bend), whose gate is
# ops-pu-gate.sh. Nine mutations and one control.
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
# FIXED-NAME BACKUPS, and this is a fix for a hazard that actually happened. `trap ... EXIT`
# covers every ordinary failure -- a red lane, a compile error -- and it covered NONE of
# what occurred: this script was KILLED mid-run, so the trap never fired and `render.bend`
# stayed mutated with P04's edit. The gate caught it (it went red, which is the only reason
# it was noticed at all), but a harness that can leave the tree dirty is a hazard to the
# next person who runs it.
#
# With `mktemp` the backup is unrecoverable, because nobody knows the name. With a fixed
# name it is on disk, and startup REFUSES to run if a stale one is there -- saying the
# restore command -- rather than overwriting a good backup with a mutated file.
BAK=.agents/slop/ops-pu-mutate.rb.bak
BAKH=.agents/slop/ops-pu-mutate.h.bak
if [ -e "$BAK" ] || [ -e "$BAKH" ]; then
  echo "ops-pu-mutate: a STALE BACKUP is present, so a previous run was killed mid-flight." >&2
  echo "  it left the tree mutated. restore with:" >&2
  echo "    cp $BAK $RB; cp $BAKH tinybendygrad/helpers.bend" >&2
  echo "  and if the files are already correct, just remove them and re-run." >&2
  exit 1
fi
cp "$RB" "$BAK"
cp tinybendygrad/helpers.bend "$BAKH"
trap 'cp "$BAK" "$RB"; cp "$BAKH" tinybendygrad/helpers.bend; rm -f "$BAK" "$BAKH"' EXIT

ROWS=14

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

mutate() {  # $1 = file, $2 = id, $3 = from, $4 = to, $5 = what it should move, $6 = "ctl"
  RF=$1; id=$2; from=$3; to=$4; want=$5; kind=${6:-mut}
  if ! grep -qF "$from" "$RF"; then
    echo "$id  MUTATION TARGET NOT FOUND in $RF -- $from"
    VERDICT="$VERDICT $id:target-not-found"
    return 0
  fi
  perl -0pi -e "s/\Q$from\E/$to/" "$RF"
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
  cp "$BAKH" tinybendygrad/helpers.bend
}

echo "=== the four PADS, which were ALL INVERTED when the gate was written ==="
# CPython's `f"{x:20s}"` pads a STRING ON THE RIGHT and `f"{i:4d}"` pads a NUMBER ON THE
# LEFT. Every pad below is the INVERSION, so each is a bug that was actually there.
mutate $RB P01 "H.pad_left(Nat.show(U32.to_nat(i)), 4)" "H.pad_right(Nat.show(U32.to_nat(i)), 4)" \
          "the COUNTER, padded right instead of left: every row, because the counter is the first field and a whole-line diff cannot miss a shifted line. The op, dtype and srcs fields then all sit three columns further right."
mutate $RB P02 "H.pad_right(O.Ops.name(O.Arena.op(ar, u)), 20)" "H.pad_left(O.Ops.name(O.Arena.op(ar, u)), 20)" \
          "the OP NAME, padded left instead of right: every row whose op name is shorter than 20, which is all of them -- Ops.BUFFER is 10, Ops.CONST is 9. The trailing ':' moves and so does everything after it."
mutate $RB P03 "H.pad_right(pu_dtype(tb, ar, u), 40)" "H.pad_left(pu_dtype(tb, ar, u), 40)" \
          "the DTYPE, padded left instead of right: every row. dtypes.i32 is 10 and dtypes.weakint is 14, both well under 40."
mutate $RB P04 "H.pad_right(pu_srcs(ar, uops, u), 32)" "H.pad_left(pu_srcs(ar, uops, u), 32)" \
          "the SRCS, padded left instead of right: every row. A src list is at most 13 characters here, well under 32."

echo "=== the two bugs that were NOT about padding ==="
mutate $RB P05 "U32.show(pu_pos(uops, x, 0))" "U32.show(x)" \
          "the INDEX, back to the src's ARENA SLOT: pu_index AND pu_radd, and both for the same reason -- in each, the row's list is not the arena's own order. pu_index's list is [BUFFER, ADD, CONST] and pu_radd's is [BUFFER, ADD, CONST, RANGE]. It must NOT move pu_const or pu_missing, whose lists ARE in arena order, so the slot and the position agree there and this mutation is invisible on them -- which is the reason those two rows exist in the fixture at all. (An earlier draft of this line claimed pu_index alone; the run says otherwise and the run wins.)"
mutate "$RB" P06 'Bool.pick(String, first, "[]", "]")' 'Bool.pick(String, first, "[", "]")' \
          "the EMPTY LIST, which then does not open its own bracket: every row whose list contains a node with NO SRCS, and those are the CONSTs -- so pu_const, pu_constarg, pu_index and pu_radd. It must NOT move pu_range or pu_rrange, whose lists are a BUFFER and a RANGE, and that asymmetry is the claim: the bug is only reachable through the Nil arm, so a list with no bare CONST in it cannot see it. (An earlier draft said three rows; pu_radd contains C1, so it fires too.)"

echo "=== the RANGE COLUMN, which is where the deepest bug in this unit lives ==="
# The fold's range sweep ALREADY answered both rows, so none of these is a fold
# mutation: the sweep was never the problem. The problem was everything the sweep's
# ANSWER went through on the way to the page.
mutate "$RB" P07 "H.colored(f, s, H.color_of(O.axis_colors(at)), False{})" \
          "H.colored(f, s, H.color_of(O.axis_letters(at)), False{})" \
          "the COLOUR LOOKUP, reading the axis LETTER instead of its COLOUR name: pu_rrange and both ranged lines of pu_radd, and NOT pu_radd's BUFFER or CONST line -- those two have no range, so the column is empty on them and the lookup is never reached. That asymmetry is the claim: the bug is only observable where a range is printed."
mutate "$RB" P08 "String.length(H.ansistrip(s))" "String.length(s)" \
          "the PAD, measured on the RAW length instead of the visible one: the same three lines, and for the same reason -- only a node with a range has escape codes in that field. CPython pads with ansilen, so counting the codes shortens the column by eight on every ranged line."
mutate tinybendygrad/helpers.bend P09 \
          'String.concat([String.from_list([Char.from_u32(27), Char.from_u32(91)]), U32.show(u), "m"])' \
          'String.concat([String.from_list([Char.from_u32(27), Char.from_u32(91), Char.from_u32(u)]), "m"])' \
          "THE COLOUR CODE AS ONE CHARACTER, which is the bug this unit actually found: the same three lines, because the escape is written but the CODE is missing from it. A colour code is 30-37 or 90-97 -- TWO digits -- so Char.from_u32(31) is the control character U+001F and not the string \"31\". It was the only caller of esc, and colored is what every colour in the tree goes through, so a range's colour and a device's colour were both writing a control character. MEASURED at the byte level: the port emitted 033 [ 037 m where CPython emits 033 [ 3 1 m."

echo "=== CONTROLS (must move NOTHING) ==="
# A no-op rewrite of the same value: `String.concat` of one element is that element, so
# the line is longer and the output is identical. A control that moved rows would mean the
# diff is reading something other than the rendered text.
mutate $RB C01 "H.pad_left(Nat.show(U32.to_nat(i)), 4)" \
          "H.pad_left(String.concat([Nat.show(U32.to_nat(i))]), 4)" \
          "nothing -- concat of one element is that element" ctl

rm -f "$BD.base"
echo
echo "=== TALLY ==="
for v in $VERDICT; do echo "  $v"; done
bad=$(echo "$VERDICT" | tr ' ' '\n' | grep -cE "BLIND|LEAKED|lane-red|target-not-found|lanes-disagree" || true)
good=$(echo "$VERDICT" | tr ' ' '\n' | grep -c ":ok" || true)
echo "ops-pu-mutate: $good of 10 as expected, $bad not"
[ "$bad" -eq 0 ] || exit 1
echo "ops-pu-mutate: done"
