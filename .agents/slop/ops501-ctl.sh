#!/bin/sh
# ops501-ctl.sh -- the three lane comparison, against a REVISION of ops.bend rather
# than the live file, so a RED state is measurable while another unit is fixing it.
#
#   sh .agents/slop/ops501-ctl.sh @-    # AT REST  -> expect DISAGREE (rows), rc 1
#   sh .agents/slop/ops501-ctl.sh @     # WORKING  -> expect AGREE, rc 0
#
# IT CALLS rebase-gate.py's rows() for the name/denominator report, so there is ONE row
# reader in this repo. It does NOT reuse ops-501-gate.sh's shell diffs: those compare
# two files and can only say "different", while the report below has to print the
# DENOMINATOR on each side and NAME every row that exists on one side only -- "101 vs
# 82" is not a coverage statement.
#
# WHY THE REVISION IS MATERIALISED IN PLACE. ops.bend:166-168 imports ./../helpers.bend
# and ./../LAWS/spec.bend; a copy in $TMPDIR cannot resolve them and prints a phantom
# 0 rows. Same directory, different filename, digest asserted, deleted in a trap. The
# LIVE ops.bend is never written.
set -e
cd "$(dirname "$0")/../.."

REV=${1:-@-}
TG=${2:-.agents/slop/opstree}
F=.agents/slop/oracles/ops501
STAGE=tinybendygrad/uop/ops-CTL-$$.bend
trap 'rm -f "$STAGE"' EXIT INT TERM

jj file show -r "$REV" tinybendygrad/uop/ops.bend > "$STAGE"
expect=$(jj file show -r "$REV" tinybendygrad/uop/ops.bend | md5 -q)
got=$(md5 -q "$STAGE")
[ "$expect" = "$got" ] || { echo "ctl: staged digest $got != revision $expect" >&2; exit 1; }

check_line=$(./bin/bend "$STAGE" --check-only 2>/dev/null | head -1)
echo "rev=$REV  staged=$(basename $STAGE)  md5=$got"
echo "check-only: $check_line"

TG_TREE="$TG" .venv/bin/python .agents/slop/ops-501-oracle.py | grep '^s5_' > "$F-ctl-py.txt"
./bin/bend "$STAGE" | grep '^s5_' > "$F-ctl-bd.txt"
./bin/bend "$STAGE" -o "$F-ctl.bin"
"$F-ctl.bin" | grep '^s5_' > "$F-ctl-bn.txt"

rc=0
.venv/bin/python .agents/slop/ops501-names.py "$F-ctl-py.txt" "$F-ctl-bd.txt" || rc=1
if diff -q "$F-ctl-py.txt" "$F-ctl-bn.txt" >/dev/null; then
  echo "native lane: identical to CPython"
else
  echo "native lane: DISAGREE"; diff "$F-ctl-py.txt" "$F-ctl-bn.txt" | head -40; rc=1
fi
.venv/bin/python .agents/slop/ops501-agree.py "$F-ctl-py.txt" "$F-ctl-bd.txt" "$F-ctl-bn.txt" || rc=1
exit $rc