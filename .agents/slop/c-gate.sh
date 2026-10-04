#!/bin/zsh
# c-gate.sh -- THE GATE for `tinybendygrad/runtime/support/c.bend`.
#
# THIS IS NOT A SPLIT AND THE SCRIPT SAYS SO. The brief for this unit said
# `runtime/support/c.py`'s code "currently lives inside `renderer/nir.bend`".
# MEASURED, IT DOES NOT. `renderer/nir.bend` is a clean port of
# `tinygrad/renderer/nir.py` (its own header says so at line 1) and its only
# mention of `runtime/support/c.py` is a PROSE citation at line 18, about
# `c.DLL` being lazy. There is no `Struct`, `Field`, `register_fields`, `DLL`,
# `findlib`, `init_c_struct_t`, `init_c_var`, `POINTER`, `CFUNCTYPE` or `Array`
# def anywhere in the tree:
#
#     rg -c '^def (Struct|Field|DLL|findlib|init_c_struct_t|init_c_var|register_fields|_do_ioctl)\b' tinybendygrad
#       -> exactly ONE file, and it is this unit's own output:
#          tinybendygrad/runtime/support/c.bend
#
# `renderer/nir.bend` was NOT EDITED by this unit and does not need to be: it is a
# clean port of `tinygrad/renderer/nir.py`, its mtime is unchanged, and its two
# mentions of `c.py` are both PROSE (line 18, about `c.DLL` being lazy, and line 1).
#
# So this unit is a FRESH PORT, not a split, and there is therefore NO
# PRE-SPLIT SNAPSHOT TO BYTE-DIFF AGAINST. The invariant that replaces it is
# STRONGER in one way and WEAKER in another, and both halves are checked:
#
#   STRONGER: the expected side is not a transcription and not a snapshot of a
#     previous run of this same file. It is CPython, re-derived on demand, by
#     `.agents/slop/c-oracle.py`, and the script RUNS IT and diffs. A wrong
#     expectation cannot survive, because the expectation is not typed.
#   WEAKER: a split can prove it lost nothing by diffing the union against the
#     old file. Nothing here can do that, because there was no old file.
#
# WHAT THE SCRIPT CHECKS, IN ORDER
#   1. the ORACLE'S EXIT PATH AND ROW COUNT. `helpers.getenv` is
#      `@functools.cache`d, so the oracle clears it per call; an oracle that
#      raised partway would leave a short file, and `set -e` plus an explicit
#      `wc -l` is what catches it. An oracle has emitted 0 rows and exited 1
#      while the gate printed 432 green rows elsewhere in this project, so the
#      row count is ASSERTED against the checked-in snapshot, not assumed.
#   2. `--check-only`, reading the FIRST LINE only (it exits 1 even when clean).
#   3. the INTERPRETED lane, retried. bend 2.0.34 machine-stack-overflows about
#      one run in twenty and sometimes prints ZERO rows, which is
#      indistinguishable from "has not started". Retry AND assert the count.
#   4. a BYTE DIFF of the whole run against `.agents/slop/runs/base_c.bend.txt`,
#      which the oracle writes. WHOLE `name=value` LINES, never row NAMES: a
#      name-comparing harness reported 0 for all 30 mutations in one unit here.
#   5. `--fp` ALSO compiles and runs, and requires the two lanes byte-identical.
#   6. `--mut` RE-RUNS THE MUTATION TABLE, which is the only evidence the rows
#      bite. One mutation there REWRITES A CHARACTER INSIDE A STRING LITERAL --
#      the trap that shipped a corrupted `renderer/tc_ptx.bend` twice, where the
#      row COUNT stayed put and only a byte diff caught it.
#
#   .agents/slop/c-gate.sh            # rows + diff against the oracle
#   .agents/slop/c-gate.sh --fp       # and the compiled lane
#   .agents/slop/c-gate.sh --refresh  # re-derive the snapshot FROM CPYTHON
#   .agents/slop/c-gate.sh --mut      # the mutation table
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
SNAP=.agents/slop/runs/base_c.bend.txt
F=tinybendygrad/runtime/support/c.bend
WANT=$(grep -c '=' "$SNAP")

if [ "$1" = --refresh ]; then
  DEV=NULL .venv/bin/python .agents/slop/c-oracle.py > "$SNAP"
  echo "snapshot re-derived FROM CPYTHON: $(grep -c '=' "$SNAP") rows"
  exit 0
fi

echo "--- 1. the ORACLE, re-derived by CALLING CPYTHON"
DEV=NULL .venv/bin/python .agents/slop/c-oracle.py > "$OUT/cpy.txt"
ORC=$(grep -c '=' "$OUT/cpy.txt")
echo "    c-oracle.py   exit 0   $ORC rows"
[ "$ORC" = "$WANT" ] || { echo "FAIL: oracle emitted $ORC rows, the snapshot has $WANT"; exit 1; }
diff "$SNAP" "$OUT/cpy.txt" > /dev/null \
  || { echo "FAIL: the oracle is no longer reproducible against its own snapshot"; diff "$SNAP" "$OUT/cpy.txt" | head; exit 1; }
echo "    and it is byte-identical to $SNAP on this run (it is REPRODUCIBLE, not a recording)"

echo "--- 2. --check-only, FIRST LINE only (it exits 1 even on a clean file)"
./bin/bend "$F" --check-only 2>&1 | head -1

echo "--- 3. the INTERPRETED lane, retried against the stack overflow"
for i in 1 2 3 4 5; do
  ./bin/bend "$F" > "$OUT/int.txt" 2> "$OUT/int.err" || true
  [ -s "$OUT/int.txt" ] && break
done
GOT=$(grep -c '=' "$OUT/int.txt" || true)
echo "    $F   $GOT rows after $i attempt(s)"
[ "$GOT" -gt 0 ] || { echo "FAIL: the interpreted lane emitted 0 rows -- bend did not run"; cat "$OUT/int.err"; exit 1; }
[ "$GOT" = "$WANT" ] || { echo "FAIL: $GOT rows, the oracle has $WANT"; exit 1; }

echo "--- 4. BYTE DIFF, whole name=value lines, against the CPYTHON snapshot"
diff "$SNAP" "$OUT/int.txt" && echo "    MATCHES CPython, all $WANT rows, byte for byte" || { echo "    DISAGREE with the CPython snapshot" >&2; exit 1; }

if [ "$1" = --fp ]; then
  echo "--- 5. the COMPILED lane"
  for i in 1 2 3; do ./bin/bend "$F" -o "$OUT/c.bin" > /dev/null 2>&1 && break; done
  [ -x "$OUT/c.bin" ] || { echo "FAIL: no binary"; exit 1; }
  for i in 1 2 3 4 5; do "$OUT/c.bin" > "$OUT/fp.txt" 2>/dev/null; [ -s "$OUT/fp.txt" ] && break; done
  FPR=$(grep -c '=' "$OUT/fp.txt" || true)
  echo "    compiled   $FPR rows"
  [ "$FPR" = "$WANT" ] || { echo "FAIL: compiled lane has $FPR rows, the oracle has $WANT"; exit 1; }
  diff "$OUT/int.txt" "$OUT/fp.txt" && echo "    BOTH LANES BYTE-IDENTICAL" || { echo "    THE TWO LANES DIFFER" >&2; exit 1; }
  diff "$SNAP" "$OUT/fp.txt" > /dev/null && echo "    and the COMPILED lane matches CPython too" || { echo "    THE COMPILED LANE DISAGREES" >&2; exit 1; }
fi

if [ "$1" = --mut ]; then
  echo "--- 6. THE MUTATION TABLE (rows moved, by name)"
  DEV=NULL .venv/bin/python .agents/slop/c-mutate.py | tee "$OUT/mut.txt"
  grep -q 'ROWS MOVED: 0 over all mutations' "$OUT/mut.txt" \
    && { echo "FAIL: the mutation table is all zeros -- that is a blind gate, not a green one"; exit 1; }
  # c-mutate.py restores the file in a `finally`, so re-running the gate after
  # `--mut` is what proves it. THAT is the restoration check: a second green run
  # on the restored file, not a diff against a copy the mutator never made.
  ./bin/bend "$F" > "$OUT/after.txt" 2>/dev/null || true
  diff "$SNAP" "$OUT/after.txt" > /dev/null \
    && echo "    the file was restored: the gate is GREEN AGAIN on it"
fi
echo "c-gate: DONE"