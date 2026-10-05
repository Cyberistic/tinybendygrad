#!/bin/sh
# ops-501-gate.sh -- the CPython lane for the ops.py:501-1928 unit of
# `tinybendygrad/uop/ops.bend`: the base family, the movers, `split_uop`.
#
#   sh .agents/slop/ops-501-gate.sh
#
# THREE LANES and they must agree byte for byte:
#
#   py    CPython, .venv/bin/python .agents/slop/ops-501-oracle.py
#   bd    the interpreted lane, ./bin/bend tinybendygrad/uop/ops.bend
#   bn    the NATIVE lane, compiled with -o and then run
#
# `--check-only` runs first and its FIRST NON-BLANK LINE is read, never its status: it
# exits 1 on a file with no unfilled laws too. `set -e` is deliberately not applied to
# it, and the failure is a first non-blank line that is not `ALL PROOFS CHECK`.
#
# `TG_TREE` picks the tree, so the same script diffs the port against the vendored
# pin and against upstream, and the two answers differ in exactly the rows upstream
# moved:
#
#   sh .agents/slop/ops-501-gate.sh
#   TG_TREE=. sh .agents/slop/ops-501-gate.sh
#
# THE FILTER IS BY PREFIX, NEVER BY POSITION. Every row of this unit starts `s5_`,
# so `grep '^s5_'` selects the block and nothing else. Filtering by position is
# what silently drops a row that MOVED, and a row that moved is the whole signal.
#
# `OPS501_PORT` overrides the PORT PATH and defaults to the live file. It exists so
# the gate's OWN red path can be exercised while the live file is green: `ops.bend` is
# shared with another unit, so a red state is only measurable against a STAGED revision
# (see `.agents/slop/ops501-ctl.sh`, which stages `jj file show -r @-` beside the real
# file because ops.bend:166-168 imports ./../helpers.bend and a copy outside
# tinybendygrad/uop/ cannot resolve them). A gate never seen red is not known to work,
# and this gate was red at rest for its whole life.
set -e
cd "$(dirname "$0")/../.."

F=oracles/ops501
P=${OPS501_PORT:-tinybendygrad/uop/ops.bend}

# ⚠ THE DIAGNOSTICS ARE ON STDERR. Measured: `--check-only` on a file that does not
# check writes NOTHING to stdout and puts `SOME PROOFS FAIL`, `Error:` and the
# offending source line on stderr. So the original `... | head -1` read an EMPTY stdout
# and every failure printed `--check-only says ''` -- the gate named no reason for any
# failure it ever reported, which is the same as reporting no failure. `2>&1` is
# required, and `grep -m1 .` rather than `head -1` because a leading blank line was
# measured once during a concurrent edit.
check_line=$(./bin/bend "$P" --check-only 2>&1 | grep -m1 -v -e '^bend 2\.0\.' -e '^$' || true)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ops-501-gate: --check-only says '${check_line:-<no output at all>}'" >&2
  exit 1
fi

# `lane NAME OUT CMD...` -- run one lane, keep only `s5_`, and REFUSE ZERO ROWS BY NAME.
#
# ⚠ `CMD | grep '^s5_' > OUT` UNDER `set -e` IS A SILENT FAILURE. grep exits 1 on no
# match, `set -e` kills the script, and the reader sees a bare rc=1 with nothing on
# stderr -- so a crashed lane, a stack-overflow and a real disagreement are the same
# three characters. A 0-row result is indistinguishable from "not started", and bend
# stack-overflows about one run in twenty. So the count is checked HERE, against the
# lane's own name, and never inferred from an exit status.
lane() {
  name=$1; out=$2; shift 2
  "$@" > "$out.all"
  grep '^s5_' "$out.all" > "$out" || true
  n=$(grep -c . "$out" || true)
  rm -f "$out.all"
  if [ "$n" -eq 0 ]; then
    echo "ops-501-gate: lane $name printed ZERO s5_ rows" >&2
    exit 1
  fi
  echo "ops-501-gate: lane $name printed $n s5_ rows" >&2
}

lane py "$F-py.txt" .venv/bin/python .agents/slop/ops-501-oracle.py
lane bd "$F-bd.txt" ./bin/bend "$P"
./bin/bend "$P" -o "$F.bin"
lane bn "$F-bn.txt" "$F.bin"

# A BYTE diff, not a per-name comparison, because the ORDER is part of the contract:
# `ops-501-oracle.py` groups the nine `after_ok=False` rows then the nine `True` ones
# so the one that differs is visible, and a name-keyed reader cannot see a reorder.
# `diff` prints the offending `name=value` lines, so this names the rows it disagrees
# about rather than saying "different".
for l in py bd bn; do
  sed 's/=.*//' "$F-$l.txt" | sort > "$F-$l.names"
done

# The row NAMES must agree before the values do, and separately: a row that exists
# on one side only is a different failure from a row whose value differs, and a
# value-only diff hides the first inside the second.
if ! diff "$F-py.names" "$F-bd.names"; then
  echo "ops-501-gate: the two lanes disagree on WHICH ROWS exist. py=$(grep -c . "$F-py.names")" \
       "bd=$(grep -c . "$F-bd.names") shared=$(comm -12 "$F-py.names" "$F-bd.names" | grep -c .)" >&2
  exit 1
fi

if ! diff "$F-py.txt" "$F-bd.txt"; then
  echo "ops-501-gate: DISAGREE (interpreted)" >&2
  exit 1
fi
if ! diff "$F-py.txt" "$F-bn.txt"; then
  echo "ops-501-gate: DISAGREE (native)" >&2
  exit 1
fi

echo "ops-501-gate: $(grep -c . "$F-py.txt") rows, $(grep -c . "$F-py.names") shared row names, 3 lanes identical"
