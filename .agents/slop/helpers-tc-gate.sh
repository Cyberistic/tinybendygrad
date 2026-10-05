#!/bin/sh
# helpers-tc-gate.sh -- THREE LANES for `trange` / `GlobalCounters` / `Context` in
# tinybendygrad/helpers.bend. Every step is `set -e`, so the script fails loudly.
#
#   sh .agents/slop/helpers-tc-gate.sh
#
#   py    CPython,   .agents/slop/helpers-oracle.py   (CALLS tinygrad.helpers)
#         -> $GT.rows, the EXPECTED VALUES the other two lanes are diffed against
#   bd    Bend,      ./bin/bend .agents/slop/helpers-tc.bend                 -> $GT.bd
#   bn    Bend,      ./bin/bend .agents/slop/helpers-tc.bend -o BIN && BIN   -> $GT.bn
#
# `py` and `bd` MUST agree, and `bn` MUST equal `bd`. STDOUT only: `tqdm` draws its
# bar on stderr and that is measured, not gated (see the oracle's header).
#
# WALL 2 IS THE REASON FOR THE `env` LINES. `getenv` is `@functools.cache`d
# (helpers.py:162), so a ContextVar's value is a PROCESS-BOOT constant: one process
# cannot see two environments. Both lanes therefore run with the SAME non-default
# env, and every `ctx_*` row's expected value is that environment's value --
# `ctx_exit_df` answers `f16`, the ENV value, where a port that hard-coded the class
# default "float32" would answer that and fail. Every configuration gets a FRESH
# process on both sides; nothing here is cached across runs.
#
# `bend`'s machine stack overflows on ~1 run in 20 and then prints ZERO rows, which
# is indistinguishable from "did not start", so each lane is retried while its row
# count is 0. A lane that is genuinely empty would loop forever, and that is the
# intended failure: a non-empty row set is the gate.
set -e
cd "$(dirname "$0")/../.."

# ONE PREFIX, THREE LANES, AND THEY ARE FILES. The `mkdir -p "$GT"` this line used to carry
# created a DIRECTORY named `helpers-tc-gate` while every lane wrote a FILE whose name started
# with that same string, and nothing anywhere read the directory -- so a sweep of this prefix saw
# two unrelated objects and could not say which one was the evidence.
GT=.agents/slop/helpers-tc-gate
env DEFAULT_FLOAT=f16 DEFAULT_INT=i64 NO_COLOR=1 "$@" true
export DEFAULT_FLOAT=f16 DEFAULT_INT=i64 NO_COLOR=1

# `.rows`, and it was `.py` until 2026-10-06. `REVIVE.md:217`, `.agents/TODO.md:320` and
# `bend2-constraints.md:24437` ALL THREE already recorded this rename, and all three were wrong
# about the only thing that matters: the driver. A renamed file whose generator still writes the
# old name is not a rename, and it survived three documents that agreed with each other.
.venv/bin/python .agents/slop/helpers-oracle.py > "$GT.rows" 2> "$GT.rows.err"

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
  echo "helpers-tc-gate: lane produced 0 rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

run_lane "$GT.bd" ./bin/bend .agents/slop/helpers-tc.bend
./bin/bend .agents/slop/helpers-tc.bend --check-only | head -1
./bin/bend .agents/slop/helpers-tc.bend -o "$GT.bin"
run_lane "$GT.bn" "$GT.bin"

diff "$GT.rows" "$GT.bd"
diff "$GT.bd" "$GT.bn"
echo "helpers-tc-gate: $(wc -l < "$GT.rows" | tr -d ' ') shared rows, 3 lanes identical"