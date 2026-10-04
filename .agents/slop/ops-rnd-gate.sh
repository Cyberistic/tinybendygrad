#!/bin/sh
# ops-rnd-gate.sh -- the CPython gate for the LEAF arms of `renderer` (render.py:45).
#
#   sh .agents/slop/ops-rnd-gate.sh
#
# Ten rows, three lanes: CPython, bend interpreted, bend compiled. Nine are diffed
# byte for byte and ONE is expected to diverge, by name.
#
# WHY ONE ROW DIVERGES, since a gate that quietly tolerates a difference is a gate
# that will tolerate the next one too. `rnd_special`: upstream's SPECIAL arm is
# `lambda x: x.arg`, which returns the ARG; for a SPECIAL the arg is `None`, and
# `rewrite` reads `None` as "no rule fired" (ops.py:1618). So CPython never uses that
# arm -- it falls through to `(UPat(GroupOp.All), lambda x: str(x))` and prints a
# full `UOp(Ops.SPECIAL, arg=None, tag=AxisType.LOOP, src=())`.
#
# This port answers `none`, because it has no full-node repr. Answering a partial
# `UOp(...)` would be the same class of defect as falling back to `str(x)`: a
# plausible string that is not the answer. The divergence is named here, in the gate,
# and in the `render.py:45` marker -- so the next reader is told rather than surprised.
#
# `rnd_unclaimed` is the SECOND divergence and the more important of the two: an ADD,
# which none of the five arms claims, so CPython falls through to `str(x)` and this
# port refuses. It is the row that says the REFUSAL is real -- without it, an
# `rnd_leaf` that answered something for everything would pass every other row.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/ops-rnd-gate
mkdir -p "$GT"

check_line=$(./bin/bend tinybendygrad/uop/render.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ops-rnd-gate: --check-only says '$check_line'" >&2
  exit 1
fi

# a REGEX alternation and not a comma list: `grep -v "^a,b="` matches nothing
# and the gate silently diffs all eleven rows.
DIVERGES='rnd_special|rnd_unclaimed'

run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" 2> "$out.err" | grep '^rnd_' > "$out.tmp" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "ops-rnd-gate: lane produced 0 rnd_ rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

# THE ORACLE'S DIVERGENT ROWS ARE MULTI-LINE, and that is a second reason they
# cannot be diffed rather than merely DIFFER. `str(x)` for a node with a src is
# `UOp(Ops.GROUP, arg=(), src=\n  UOp(Ops.CONST, ...),\n))` -- CPython's own repr
# breaks on the srcs. A row file is one line per row, so a divergent row has to be
# excluded AT THE SOURCE, or the file keeps a continuation the port's `none` does not
# and the diff becomes a diff of line COUNTS.
.venv/bin/python .agents/slop/ops-render-oracle.py > "$GT-oracle.txt"
run_lane "$GT-bd.txt" ./bin/bend tinybendygrad/uop/render.bend
./bin/bend tinybendygrad/uop/render.bend -o "$GT.bin"
run_lane "$GT-bn.txt" "$GT.bin"

# DROP THE DIVERGENT ROWS AND THEIR CONTINUATIONS, by a separate file and not a
# heredoc: a `\n` inside `<< 'PY'` is mangled by two levels of shell quoting and the
# failure reads as a Python TypeError rather than a quoting bug. See ops-rnd-rows.py.
.venv/bin/python .agents/slop/ops-rnd-rows.py "$GT-oracle.txt" "$GT-py.sub" "$DIVERGES" \
  || { echo "ops-rnd-gate: the DIVERGES list does not match the oracle" >&2; exit 1; }

grep -vE "^($DIVERGES)=" "$GT-bd.txt" > "$GT-bd.sub"
grep -vE "^($DIVERGES)=" "$GT-bn.txt" > "$GT-bn.sub"

diff "$GT-py.sub" "$GT-bd.sub" || { echo "ops-rnd-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.sub" "$GT-bn.sub" || { echo "ops-rnd-gate: DISAGREE (native)" >&2; exit 1; }

# And the divergent row must be PRESENT and must be the port's `none` -- a row that
# went missing is not a divergence, it is a hole.
grep -qE "^($DIVERGES)=" "$GT-bd.txt" || { echo "ops-rnd-gate: $DIVERGES is MISSING from the port" >&2; exit 1; }
grep -qE "^($DIVERGES)=none$" "$GT-bd.txt" || {
  echo "ops-rnd-gate: $DIVERGES is the documented divergence, so the port must answer" >&2
  echo "  none -- it answered: $(grep -E "^($DIVERGES)=" "$GT-bd.txt")" >&2
  exit 1
}
grep -q "^rnd_unclaimed=none$" "$GT-bd.txt" || {
  echo "ops-rnd-gate: rnd_unclaimed must be none -- a node no arm claims is a refusal" >&2
  exit 1
}

echo "ops-rnd-gate: $(wc -l < "$GT-py.sub" | tr -d ' ') rows diffed, 3 lanes identical"
echo "ops-rnd-gate: $DIVERGES are the TWO documented divergences -- upstream falls through to str(x) for both, and the port has no full-node repr"
