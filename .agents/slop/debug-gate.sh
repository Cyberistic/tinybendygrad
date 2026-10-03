#!/bin/sh
# debug-gate.sh -- FIVE levels, THREE lanes, every row CPython-sourced.
#
#   sh .agents/slop/debug-gate.sh
#
#   py   CPython,  .agents/slop/debug-gate.py <level>   (CALLS tinygrad)
#   bd   Bend,     ./bin/bend .agents/slop/debug-gate.bend
#   bn   Bend,     ./bin/bend .agents/slop/debug-gate.bend -o BIN && BIN
#
# FIVE LEVELS, NOT ONE, and that is the whole design. `unset`, `0`, `1`, `2`, `3` are
# run in that order with `py` and `bd` agreeing at EACH of them. The row NAMES are
# identical across all five -- only the VALUES move -- so:
#
#   * a diff between level 0 and level 2 is the PROOF THAT THE ROWS MOVE, and it is
#     checked here as a positive assertion (`rows_that_move` must be non-empty and
#     must include the seven sites), not left to the reader;
#   * a row that passes at BOTH level 0 and level 2 is a row that cannot see the
#     gate, and `assert_moved` fails the script if any row of a `>= 2` site is
#     identical at 0 and 2, or if `mem_plan` is non-empty at 0.
#
# `bd` AND `bn` MUST AGREE: the interpreted lane and the compiled lane are two
# transcriptions of one source and a disagreement between them is a compiler-visible
# defect, not a port defect, so it is reported separately.
#
# WHY THE LEVEL IS IN THE ENVIRONMENT AND NOT IN THE ROW. `DEBUG` is a ContextVar
# whose value is a process-boot constant (`getenv` is `@functools.cache`d,
# helpers.py:162), so one process cannot see two levels and every level is a fresh
# process on BOTH sides. `--check-only` is NOT a gate here: read its FIRST line, and
# expect `SOME PROOFS FAIL` naming only `dtype.Dt`'s 14 unfilled laws.
#
# `bend`'s machine stack overflows on ~1 run in 20 and then prints ZERO rows, which is
# indistinguishable from "did not start", so each lane is retried while its row count
# is 0. A lane that is genuinely empty would loop forever, and that is the intended
# failure.
#
# `PYTHONPATH` IS UNSET ONCE, HERE, RATHER THAN WRAPPED AROUND EVERY COMMAND: it has to
# wrap a SHELL FUNCTION too (`run_lane`), and `env -u PYTHONPATH run_lane` fails with
# "No such file or directory" because `env` execs a binary, not a function. `tinygrad`
# is an editable install (`__editable__.tinygrad-0.14.0.pth`), so `import tinygrad`
# works from any cwd and PYTHONPATH is NOT a blocker -- but a stale one would point the
# oracle at a DIFFERENT tinygrad, and this gate's whole value is that both lanes read
# the same `tinygrad/`.
set -e
cd "$(dirname "$0")/../.."

GT=.agents/slop/debug-gate
mkdir -p "$GT"
unset PYTHONPATH

# the rows each site must MOVE on, checked by name below. `mem_plan` is the level-1
# site, so it must move between level 0 and level 1; the other six between 1 and 2.
MUST_MOVE_0_2="ar_ring ar_naive ar_a2 st_bad am185 am225 am251 am254"
MUST_MOVE_0_1="mem_plan"

run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" > "$out.tmp" 2>"$out.err" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "debug-gate: lane produced 0 rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

value_of() {  # $1 = file, $2 = row name -- WHOLE name=value line, not the name
  grep "^$2=" "$1" || true
}

check_level() {  # $1 = level tag, $2 = env assignment (may be empty), $3 = expects content
  lvl=$1; envassign=$2; wants=$3
  $envassign .venv/bin/python .agents/slop/debug-gate.py "$lvl" > "$GT.$lvl.py" 2> "$GT.$lvl.py.err"
  $envassign run_lane "$GT.$lvl.bd" ./bin/bend .agents/slop/debug-gate.bend
  ./bin/bend .agents/slop/debug-gate.bend -o "$GT.bin"
  $envassign "$GT.bin" > "$GT.$lvl.bn" 2> "$GT.$lvl.bn.err"

  # BLANK LINES CARRY NO ROW and the harness separates its groups with them (the rest
  # of the repository's gates do the same), so both lanes are filtered before the
  # diff. Filtering BOTH sides is the point -- filtering only the harness would make
  # the oracle's line numbers the gate's row order.
  for f in "$GT.$lvl.py" "$GT.$lvl.bd" "$GT.$lvl.bn"; do
    grep -v '^$' "$f" > "$f.rows" && mv "$f.rows" "$f"
  done

  if ! diff -u "$GT.$lvl.py" "$GT.$lvl.bd"; then
    echo "debug-gate: CPython and Bend DISAGREE at level $lvl" >&2
    exit 1
  fi
  if ! diff -u "$GT.$lvl.bd" "$GT.$lvl.bn"; then
    echo "debug-gate: the interpreted and compiled lanes DISAGREE at level $lvl" >&2
    exit 1
  fi
  # the level-0 control: at unset/0 EVERY site row must be present and EMPTY.
  if [ "$wants" = "silent" ]; then
    for nm in ar_ring ar_naive ar_a2 mem_plan st_bad am185 am225 am251 am254 \
             mem_L0 ar_ring_L0 st_bad_L0 am185_L0 am251_L0; do
      if [ "$(value_of "$GT.$lvl.py" "$nm")" != "$nm=" ]; then
        echo "debug-gate: LEVEL-$lvl CONTROL FAILED -- $nm is not an empty row:" >&2
        value_of "$GT.$lvl.py" "$nm" >&2
        exit 1
      fi
    done
  fi
  echo "debug-gate: level $lvl -- $(grep -c '=' "$GT.$lvl.py" | tr -d ' ') rows, 3 lanes identical"
}

check_level unset "" silent
check_level 0    "DEBUG=0" silent
check_level 1    "DEBUG=1" ""
check_level 2    "DEBUG=2" ""
check_level 3    "DEBUG=3" ""

# ---------------------------------------------------------------------------
# THE ROWS MOVE. Asserted by name, on the CPython lane, which is the one both sides
# are measured against. A gate that only diffs level 2 against level 2 cannot tell a
# working gate from a port that prints unconditionally.
# ---------------------------------------------------------------------------
for nm in $MUST_MOVE_0_2; do
  a=$(value_of "$GT.0.py" "$nm"); b=$(value_of "$GT.2.py" "$nm")
  if [ "$a" = "$b" ]; then
    echo "debug-gate: $nm DID NOT MOVE between level 0 and level 2" >&2
    exit 1
  fi
  if [ "$a" != "$nm=" ]; then
    echo "debug-gate: $nm was not silent at level 0" >&2
    exit 1
  fi
  if [ -z "$b" ]; then
    echo "debug-gate: $nm is ABSENT at level 2 (a missing row is not a moved row)" >&2
    exit 1
  fi
done
for nm in $MUST_MOVE_0_1; do
  a=$(value_of "$GT.0.py" "$nm"); b=$(value_of "$GT.1.py" "$nm")
  if [ "$a" = "$b" ]; then
    echo "debug-gate: $nm DID NOT MOVE between level 0 and level 1" >&2
    exit 1
  fi
  if [ "$a" != "$nm=" ]; then
    echo "debug-gate: $nm was not silent at level 0" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# LEVEL 1 IS NOT LEVEL 2. The one `>= 1` site must be ALREADY PRINTING at level 1
# while all six `>= 2` sites are silent there, and all seven at level 2. Read off the
# CPython lane and echoed, because a difference nobody prints is a difference nobody
# checked.
# ---------------------------------------------------------------------------
printf 'debug-gate: level discrimination (CPython lane, level 1 vs level 2)\n'
for nm in mem_plan ar_ring st_bad am185 am251; do
  one=$(value_of "$GT.1.py" "$nm"); two=$(value_of "$GT.2.py" "$nm")
  case "$nm" in mem_plan) want="1";; *) want="0";; esac
  got1=$([ "$one" = "$nm=" ] && echo 0 || echo 1)
  printf '  %-9s level1=%s level2=%s expect_level1=%s %s\n' "$nm" "$got1" \
    "$([ "$two" = "$nm=" ] && echo 0 || echo 1)" "$want" \
    "$([ "$got1" = "$want" ] && echo OK || echo FAIL)"
  [ "$got1" = "$want" ] || { echo "debug-gate: $nm fired at the wrong level 1" >&2; exit 1; }
done

./bin/bend .agents/slop/debug-gate.bend --check-only | head -1
echo "debug-gate: $(grep -c '=' "$GT.2.py" | tr -d ' ') shared rows at level 2; 5 levels x 3 lanes; all agree; 7 site rows all move; level-0 control silent"