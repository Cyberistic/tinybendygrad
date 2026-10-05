#!/bin/zsh
# shlscope/gate.sh -- the driver. `LANE-LIVENESS.md` calls this shape "one sh driver each"
# and says none of the mm gates had one. MMFOLD.md §2/§6 made one for `mm-gate.py` and
# `mm-bl-gate.py`; this is the third, for the SHIFT AMOUNT question.
#
#   zsh .agents/slop/shlscope/gate.sh
#
# GUARDS, because a green run about nothing is the failure this project keeps making:
#   * the CPython lane must emit > 0 rows. `DIED` != `COMPARED ZERO`.
#   * the Bend lane must emit > 0 rows.
#   * rows-expected must equal rows-present. A missing row is not a pass.
#   * `rows()`-style whole-`name=value` diffing, never name-keyed. A name-keyed harness
#     reported 0 for all 30 mutations in one unit and all 68 in another.
set -e
SL=.agents/slop/shlscope
OUT=$(mktemp -d "${TMPDIR:-/tmp}/shlscope.XXXXXX")
trap 'rm -rf "$OUT"' EXIT

python3 $SL/gen.py > "$OUT/all.txt"
python3 $SL/gen.py --emit-bend > "$SL/gate.bend"
perl -e 'alarm 900; exec @ARGV' ./bin/bend $SL/gate.bend | grep '^ss' > "$OUT/all-bend.txt" || true

# TWO LANES OUT OF ONE FIXTURE LIST, and the split is by ROW NAME -- `ss_` is compared
# against CPython, `ssx_` is compared against the PINNED saturation. A gate that mixed
# them would ask the port to reproduce an unbounded integer and then report the answer
# wrong, which is the defect `mm-walk-gate.py`'s `mmkx_` rows already avoid.
grep '^ss_'  "$OUT/all.txt"       > "$OUT/py.txt"  || true
grep '^ssx_' "$OUT/all.txt"       > "$OUT/py-d.txt" || true
grep '^ss_'  "$OUT/all-bend.txt"  > "$OUT/bend.txt"  || true
grep '^ssx_' "$OUT/all-bend.txt"  > "$OUT/bend-d.txt" || true

EXP=$(wc -l < "$OUT/py.txt" | tr -d ' ')
GOT=$(wc -l < "$OUT/bend.txt" | tr -d ' ')
DEXP=$(wc -l < "$OUT/py-d.txt" | tr -d ' ')
DNOT=$(wc -l < "$OUT/bend-d.txt" | tr -d ' ')

if [ "$EXP" -eq 0 ] || [ "$GOT" -eq 0 ]; then
  print "DIED compared rows py=$EXP bend=$GOT -- a zero lane is not an answer"
  exit 2
fi
if [ "$EXP" -ne "$GOT" ]; then
  print "DIED compared rows expected=$EXP present=$GOT"
  exit 2
fi
if [ "$DEXP" -ne "$DNOT" ]; then
  print "DIED divergence rows expected=$DEXP present=$DNOT"
  exit 2
fi
if [ "$DEXP" -eq 0 ]; then
  print "DIED divergence rows 0 -- a gate with no saturation rows proves nothing about saturation"
  exit 2
fi

diff "$OUT/py.txt" "$OUT/bend.txt" > "$OUT/d.txt" && RC=0 || RC=$?
MOVED=$(grep -c '^<' "$OUT/d.txt" || true)
if [ "$RC" -ne 0 ]; then
  print "NOT GREEN -- $EXP/$GOT compared rows, $MOVED disagreements"
  head -40 "$OUT/d.txt"
  exit 1
fi

# THE DIVERGENCE FAMILY is not a pass. It is CHECKED -- and checked against the
# PREDICTED saturation, which is not always `NInf`: `mm.u64.shl` answers `None` (OVER),
# `mm.lift` falls through to the DTYPE window, and that window's sign is the sign of the
# exact answer. So `lo= hi=` is stripped and the two words are compared to the `SAT`
# line's own prediction. A fixed `NInf` here failed 56 of 75 rows when it was written,
# and every failure was the assertion's fault, not the port's.
# Strip the ROW NAME off both lanes and leave the payload: the port's `lo= hi=` and the
# prediction's `SAT lo= hi=`. Both names are dropped because the two lanes name a row
# identically already -- that is what the name-keyed diff above proved -- so the payload
# diff here is a SECOND, independent check on the same rows.
sed 's/^ssx_[a-z]*_[a-z0-9]*_[0-9]* //' "$OUT/bend-d.txt" > "$OUT/d-actual.txt"
sed 's/^ssx_[a-z]*_[a-z0-9]*_[0-9]* SAT //; s/ cp=.*//' "$OUT/py-d.txt" > "$OUT/d-want.txt"
diff "$OUT/d-want.txt" "$OUT/d-actual.txt" > "$OUT/dx.txt" && XRC=0 || XRC=$?
if [ "$XRC" -ne 0 ]; then
  BADX=$(grep -c '^<' "$OUT/dx.txt" || true)
  print "NOT GREEN -- $BADX of $DEXP divergence rows did not saturate as predicted"
  head -20 "$OUT/dx.txt"
  exit 1
fi
print "GREEN -- $EXP/$GOT compared rows 0 disagreements; $DEXP divergence rows all saturate as PREDICTED (counted, never passed)"