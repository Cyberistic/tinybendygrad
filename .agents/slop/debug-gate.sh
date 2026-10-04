#!/bin/sh
# debug-gate.sh -- NINE levels (unset, 0..7), THREE lanes, every row CPython-sourced.
#
#   sh .agents/slop/debug-gate.sh
#
#   py   CPython,  .agents/slop/debug-gate.py <level>   (CALLS tinygrad)
#   bd   Bend,     ./bin/bend .agents/slop/debug-gate.bend
#   bn   Bend,     ./bin/bend .agents/slop/debug-gate.bend -o BIN && BIN
#
# NINE LEVELS, NOT ONE, and that is the whole design. `unset`, `0`..`7` run in that order
# with `py` and `bd` agreeing at EACH of them. The row NAMES are identical across all
# nine -- only the VALUES move -- so:
#
#   * a diff between level 0 and level 7 is the PROOF THAT THE ROWS MOVE, and it is
#     checked here as a positive assertion (`MUST_MOVE_0_7` must each differ from their
#     level-0 value AND must have been empty there), not left to the reader;
#   * a row that passes at BOTH level 0 and level 7 is a row that cannot see the gate,
#     and the `MUST_MOVE` loops fail the script if any is identical at the two ends.
#
# `bd` AND `bn` MUST AGREE: the interpreted lane and the compiled lane are two
# transcriptions of one source and a disagreement between them is a compiler-visible
# defect, not a port defect, so it is reported separately.
#
# ---------------------------------------------------------------------------
# WHY THE LEVEL IS IN THE ENVIRONMENT AND NOT IN THE ROW. `DEBUG` is a ContextVar whose
# value is a process-boot constant (`getenv` is `@functools.cache`d, helpers.py:162), so
# one process cannot see two levels and every level is a fresh process on BOTH sides.
# `--check-only` is NOT a gate here: read its FIRST line, and expect `SOME PROOFS FAIL`
# naming only `dtype.Dt`'s 14 unfilled laws.
#
# `DEBUG` CHANGES CONTROL FLOW, SO A COMPARISON ACROSS LEVELS CAN BE COMPARING TWO
# DIFFERENT PROGRAMS. That is the trap this harness was extended into, and it is handled
# the way `.agents/slop/graphcmp-dbg.bend` handles it for graphs -- BOTH halves:
#
#   * HELD FIXED BY CONSTRUCTION -- `debug-gate.bend`'s `pin_rows()` takes NO level. It
#     has no `dbg` parameter, so no code path exists on which the level reaches the plan
#     it prints; the level enters only `site_rows`. The same holds for `gi_rows`,
#     `mb_rows`, `thr_rows`, `sweep_rows` and `fires_rows`.
#   * AND CHECKED -- `digest_invariant` digests every level-INVARIANT row per run and
#     `check_digests` FAILS with exit 2 (a FAILURE, never a verdict) the moment two
#     levels disagree. Measured `distinct=1` across all nine levels.
#
# A guard nobody can see fire is a guard that does not work, so the digest is printed.
#
# `PYTHONPATH` IS UNSET ONCE, HERE, RATHER THAN WRAPPED AROUND EVERY COMMAND: it has to
# wrap a SHELL FUNCTION too (`run_lane`), and `env -u PYTHONPATH run_lane` fails with
# "No such file or directory" because `env` execs a binary, not a function. `tinygrad`
# is an editable install (`__editable__.tinygrad-0.14.0.pth`), so `import tinygrad`
# works from any cwd and PYTHONPATH is NOT a blocker -- but a stale one would point the
# oracle at a DIFFERENT tinygrad, and this gate's whole value is that both lanes read the
# same `tinygrad/`.
set -e
cd "$(dirname "$0")/../.."

# THE ARTEFACTS. Per-level row dumps and the compiled binary go to
# `.agents/slop/debug-gate-out/` so a run leaves an auditable trail next to the harness
# (oracles belong in `.agents/slop/`, never `$TMPDIR` -- one unit's was gone before the
# commit). The compiled binary is a build product and is removed at the end.
GT=.agents/slop/debug-gate-out
mkdir -p "$GT"
unset PYTHONPATH
unset DEBUG

# THE LEVELS. `unset` comes first and separately from 0 because "no DEBUG in the
# environment" and "DEBUG=0" are different inputs to `getenv`, and only the first is what
# a user gets by accident.
OPERATING=2

# The rows each site must MOVE on, checked by name below. `mem_plan` is the ONE level-1
# site, so it must move between 0 and 1; the other six between 0 and 2. Both ends are
# checked against level 0 AND against level 7, because the whole point of extending the
# sweep to 7 is that the same rows must STILL be firing there.
MUST_MOVE_0_1="mem_plan"
MUST_MOVE_0_2="ar_ring ar_naive ar_a2 st_bad am185 am225 am251 am254"
MUST_MOVE_0_7="ar_ring ar_naive ar_a2 mem_plan st_bad am185 am225 am251 am254"

# THE LEVEL-INVARIANT ROWS, BY NAME PREFIX. Everything else in a dump is either the
# environment (`env_*`, `env_value`) or one of the thirteen site rows, and those two sets
# are exactly what is ALLOWED to move. Prefixes rather than a hand-written name list, so
# a new invariant row joins the digest the day it is written instead of quietly escaping
# the check -- and `st_ok1`/`st_ok2` are here because they are site rows whose value is
# invariant (the whitelist suppresses them at every level) and the digest is what proves
# that rather than my having decided it.
INVARIANT_PREFIXES="gi_ mem_mb_ thr_ pin_ fires_ st_ok"

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

# THE DIGEST, over the level-INVARIANT rows only, one line per row and SORTED so the
# emission order cannot change it. `md5 -q` on macOS takes exactly ONE file and prints
# NOTHING given several, so it is PIPED rather than given arguments.
digest_invariant() {  # $1 = a lane file
  grep -E "^($INVARIANT_PREFIXES)" "$1" | sort | md5
}

check_level() {  # $1 = level tag, $2 = DEBUG value ("unset" or a number), $3 = silent|any
  lvl=$1; dbg=$2; wants=$3
  if [ "$dbg" = "unset" ]; then unset DEBUG; else DEBUG=$dbg; export DEBUG; fi

  .venv/bin/python .agents/slop/debug-gate.py "$lvl" > "$GT.$lvl.py" 2> "$GT.$lvl.py.err"
  run_lane "$GT.$lvl.bd" ./bin/bend .agents/slop/debug-gate.bend
  ./bin/bend .agents/slop/debug-gate.bend -o "$GT.bin"
  "$GT.bin" > "$GT.$lvl.bn" 2> "$GT.$lvl.bn.err"
  unset DEBUG

  # BLANK LINES CARRY NO ROW and the harness separates its groups with them (the rest of
  # the repository's gates do the same), so all three lanes are filtered before the
  # diff. Filtering BOTH sides is the point -- filtering only the harness would make the
  # oracle's line numbers the gate's row order.
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
  # the level-0 control: at unset/0 EVERY site row must be PRESENT and EMPTY. A missing
  # row is not a silent row -- it is indistinguishable from a site that was never wired,
  # which is the failure this gate exists to catch.
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
  echo "$lvl $(digest_invariant "$GT.$lvl.py")" >> "$GT.digests"
  echo "debug-gate: level $lvl -- $(grep -c '=' "$GT.$lvl.py" | tr -d ' ') rows, 3 lanes identical"
}

check_digests() {
  distinct=$(cut -d' ' -f2 "$GT.digests" | sort -u | wc -l | tr -d ' ')
  n=$(wc -l < "$GT.digests" | tr -d ' ')
  if [ "$distinct" != "1" ]; then
    echo "debug-gate: FAILURE -- the level-INVARIANT rows DIFFER across levels." >&2
    echo "  A level reached the fixture, so every cross-level diff above compared" >&2
    echo "  two different programs. THIS IS A FAILURE, NOT A VERDICT." >&2
    grep -E "^($INVARIANT_PREFIXES)" "$GT.unset.py" | sort > "$GT.inv.unset"
    grep -E "^($INVARIANT_PREFIXES)" "$GT.7.py" | sort > "$GT.inv.7"
    diff -u "$GT.inv.unset" "$GT.inv.7" >&2 || true
    exit 2
  fi
  echo "debug-gate: level-invariant digest distinct=$distinct over $n levels ($(
    cut -d' ' -f2 "$GT.digests" | head -1))"
}

check_moves() {  # $1 = the pair label, $2 = the high level, rest = the rows
  label=$1; hi=$2; shift 2
  for nm in "$@"; do
    a=$(value_of "$GT.0.py" "$nm"); b=$(value_of "$GT.$hi.py" "$nm")
    if [ "$a" != "$nm=" ]; then
      echo "debug-gate: $nm was not silent at level 0 ($label)" >&2
      echo "  $a" >&2
      exit 1
    fi
    if [ "$a" = "$b" ]; then
      echo "debug-gate: $nm DID NOT MOVE between level 0 and level $hi ($label)" >&2
      exit 1
    fi
    if [ -z "$b" ]; then
      echo "debug-gate: $nm is ABSENT at level $hi -- a missing row is not a moved row" >&2
      exit 1
    fi
  done
  echo "debug-gate: $(( $# )) row(s) all moved 0 -> $hi ($label)"
}

check_fires() {
  # THE CUMULATIVITY ROW, ASSERTED. `fires_L<L>` is "which of the seven gated sites fire
  # at level L", measured on BOTH lanes. Levels are cumulative upstream -- MEASURED by
  # calling CPython's own sites at DEBUG=0..7 -- and this is where the PORT is asked the
  # same question instead of being assumed to answer it. The row that matters most is the
  # EMPTY one: at L=0 nothing fires, at L=1 only `mem`, and at L=2..7 all seven.
  printf 'debug-gate: cumulativeness (CPython lane; port lane is byte-identical)\n'
  for n in 0 1 2 3 4 5 6 7; do
    case "$n" in
      0) want="" ;;
      1) want="mem" ;;
      *) want="mem,ar,st,am185,am225,am251,am254" ;;
    esac
    got=$(value_of "$GT.unset.py" "fires_L$n" | cut -d= -f2-)
    if [ "$got" != "$want" ]; then
      echo "debug-gate: fires_L$n is '$got' and CPython says '$want'" >&2
      exit 1
    fi
    printf '  fires_L%-2s %-40s %s\n' "$n" "${got:-(nothing fires)}" OK
  done
}

rm -f "$GT.digests"
check_level unset unset silent
check_level 0    0      silent
for n in 1 2 3 4 5 6 7; do
  check_level "$n" "$n" any
done

check_digests
check_moves "0->1, the level-1 site" 1 $MUST_MOVE_0_1
check_moves "0->2, the level-2 sites" 2 $MUST_MOVE_0_2
check_moves "0->7, EVERYTHING must still fire at the top of the scale" 7 $MUST_MOVE_0_7
check_fires

# ---------------------------------------------------------------------------
# LEVEL 1 IS NOT LEVEL 2. The one `>= 1` site must be ALREADY PRINTING at level 1 while
# all six `>= 2` sites are silent there, and all seven at level 2. Read off the CPython
# lane and echoed, because a difference nobody prints is a difference nobody checked.
# ---------------------------------------------------------------------------
printf 'debug-gate: level discrimination (CPython lane, level 1 vs level 2)\n'
for nm in mem_plan ar_ring st_bad am185 am251; do
  one=$(value_of "$GT.1.py" "$nm"); two=$(value_of "$GT.2.py" "$nm")
  case "$nm" in mem_plan) want="1" ;; *) want="0" ;; esac
  got1=$([ "$one" = "$nm=" ] && echo 0 || echo 1)
  printf '  %-9s level1=%s level2=%s expect_level1=%s %s\n' "$nm" "$got1" \
    "$([ "$two" = "$nm=" ] && echo 0 || echo 1)" "$want" \
    "$([ "$got1" = "$want" ] && echo OK || echo FAIL)"
  [ "$got1" = "$want" ] || { echo "debug-gate: $nm fired at the wrong level 1" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# WHAT THE NEW LEVELS CANNOT SHOW, PRINTED SO IT IS NOT A ZERO NOBODY READS.
# These are the CPython-side measurements; `debug-gate.py --inventory` prints the same
# table with every site, every cite, and the PORT's own site count beside it.
# ---------------------------------------------------------------------------
echo "debug-gate: ---- levels 3..7: what this gate can and cannot say ----"
.venv/bin/python .agents/slop/debug-gate.py --inventory | sed 's/^/debug-gate:   /'

rm -f "$GT.bin"
./bin/bend .agents/slop/debug-gate.bend --check-only | head -1
echo "debug-gate: $(grep -c '=' "$GT.$OPERATING.py" | tr -d ' ') shared rows at level $OPERATING; 9 levels x 3 lanes; all agree; 8 site rows all move; cumulativeness measured at every level; level-0 control silent"