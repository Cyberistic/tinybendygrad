#!/bin/bash
# grw-gate.sh -- compare the PORT's `graph_rewrite` rows to CPython's.
#
# The port prints four repl strings and four map sizes (two fixtures x two
# dispatcher arms) and every one of them comes from running CPython's own
# `RewriteContext.walk_rewrite` / `.unified_rewrite` on the same fixture
# (`.agents/slop/grw-oracle.py`).  Nothing here is transcribed.
#
# THE SINK ROWS ARE NOT COMPARED.  The port prints an arena INDEX and CPython
# prints an op NAME, and an index is a numbering only this file knows, so
# diffing one against the other is a diff of two unrelated values -- the
# mistake `gr-diff.sh` records in its own header.  `n` (the repl map's size) and
# `repl` (the mapping, printed as op names on both sides) are the two
# comparable facts, and the denominator is printed with the count.
#
# ONE ARM IS A DECLARED DIVERGENCE and the gate says so rather than passing it:
# `f1_fix`.  CPython's `unified_rewrite` RAISES IndexError on F1 at
# tinygrad/schedule/__init__.py:98, because after the first pass the graph holds
# the dummy PARAM(99) and the rule reads `ctx[1][x.arg.slot]` with slot 99 into a
# two-entry ctx.  The port's `pm_r_param_m` answers `None{}` for a slot it does
# not name, so the port CONVERGES.  That is a divergence in a RULE BODY, in
# `uop/ops.bend`, which this unit does not own -- so it is REPORTED, and the
# gate prints NO ORACLE for that arm rather than inventing one.
#
# A THIRD ROW IS A SECOND DECLARED DIVERGENCE: `mapn`.  Upstream's worklist keys
# `replace` with every node it touched, intermediate rebuilds included, so it
# records 4 nodes for F2's fixpoint where the port's LAST PASS -- which starts
# from an empty map -- records 2, on the same final graph whose repl string the
# two sides print byte-identically.  The row is printed by both sides and the
# gate REPORTS the disagreement rather than comparing it.
#
# `passes` AND `capped` HAVE NO CPYTHON COUNTERPART AT ALL: upstream's driver is
# one worklist and has no notion of a pass, so `passes` is a PORT-ONLY
# observable.  It is gated by mutation (`grw-mut.py`) and not by an oracle, and
# the two rows it needs are counted in that harness, not here.
#
# DENOMINATOR: 8 = 2 fixtures x 2 arms x 3 facts.  Two of the eight have no
# oracle (CPython raises on f1_fix) and two are a declared divergence (mapn), so
# FOUR are compared.  A green run that compared zero rows exits 2 -- the count is
# printed so that a zero cannot read as a pass.
set -u
cd "$(dirname "$0")/../.."

py=$(env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/grw-oracle.py)
bend=$(./bin/bend tinybendygrad/codegen/__init__.bend 2>/dev/null)

py_n=$(printf '%s\n' "$py" | grep -c '^grw_')
bend_n=$(printf '%s\n' "$bend" | grep -c '^grw_')
echo "grw-gate: oracle rows=$py_n  port rows=$bend_n"

status=0
compared=0
nooracle=0
for fx in f1 f2; do
  for arm in walk fix; do
    for key in n repl; do
      row="grw_${fx}_${arm}_${key}"
      a=$(printf '%s\n' "$py" | grep "^${row}=" || true)
      b=$(printf '%s\n' "$bend" | grep "^${row}=" || true)
      if [ -z "$a" ]; then
        echo "grw-gate: NO ORACLE ${row} -- CPython raised on this arm (see the divergence note below)"
        nooracle=$((nooracle + 1))
        continue
      fi
      if [ -z "$b" ]; then
        echo "grw-gate: NO PORT ROW ${row}"
        status=1
        continue
      fi
      av=$(printf '%s' "$a" | sed -e 's/, /,/g')
      bv=$(printf '%s' "$b" | sed -e 's/, /,/g')
      compared=$((compared + 1))
      if [ "$av" = "$bv" ]; then
        echo "grw-gate: AGREE ${row}  ${av}"
      else
        echo "grw-gate: DISAGREE ${row}"
        echo "    CPython: $a"
        echo "    Port:    $b"
        status=1
      fi
    done
  done
done
echo "grw-gate: compared ${compared}/8 rows against CPython; ${nooracle} have no oracle; 2 (mapn) are a declared divergence"

# THE SECOND DIVERGENCE, printed rather than compared.
for fx in f1 f2; do
  for arm in walk fix; do
    row="grw_${fx}_${arm}_mapn"
    a=$(printf '%s\n' "$py" | grep "^${row}=" || true)
    b=$(printf '%s\n' "$bend" | grep "^${row}=" || true)
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then
      echo "grw-gate: DECLARED DIVERGENCE ${row} -- CPython ${a#*=}, port ${b#*=}. Upstream's worklist keys replace with every node it touched; the port's last pass starts from an empty map."
    fi
  done
done

# The divergence, ASSERTED as a divergence: CPython must raise on f1's fixpoint
# arm.  If CPython ever stops raising, this line says so instead of the gate
# quietly going green.
if printf '%s\n' "$py" | grep -q '^grw_f1_fix=RAISED:'; then
  echo "grw-gate: DECLARED DIVERGENCE f1_fix -- CPython RAISES ($(printf '%s\n' "$py" | grep '^grw_f1_fix=')), port converges. Cause: pm_r_param_m (uop/ops.bend) answers None{} for a slot it does not name, where schedule/__init__.py:98 reads ctx[1][x.arg.slot] and raises."
else
  echo "grw-gate: NOTE f1_fix -- CPython no longer raises; re-read the rule before trusting the port here."
fi

if [ "$compared" -eq 0 ]; then
  echo "grw-gate: FATAL -- zero rows compared, so this green means nothing."
  exit 2
fi
exit $status