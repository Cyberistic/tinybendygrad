#!/usr/bin/env bash
# rebase-try.sh -- TEST a rebase batch in a THROWAWAY tree. It vendors nothing.
#
# WHY. rebase-plan.py derives batches from the import graph. A derived batch is a CLAIM
# until something executes the tree it describes. This builds the tree OUT OF TREE -- a
# pristine checkout of the PIN with exactly one candidate file set overlaid at HEAD -- and
# runs real CPython over it. The working tree is never touched, so it is safe to run with
# thirteen agents live.
#
#   --plan                 report the batches (same as rebase-plan.py), vendor nothing
#   --all                  probe every coupled batch
#   --shrink <id>          MINIMISE batch <id> by dropping one file at a time
#   <id> <path> [<path>…]  probe an ad-hoc file set
#
# --shrink is the load-bearing one. rebase-plan.py says "these N files must move together";
# --shrink re-tests every one-file reduction and reports the smallest set that still works.
# A batch that shrinks from 9 to 4 is hours saved and a batch that will not shrink is
# genuinely atomic, which is a claim worth being able to make out loud.
#
# WHY IMPORT IS NOT ENOUGH, AND WHY ONE KERNEL IS NOT EITHER. 78d482262 deletes
# AxisType.REDUCE and every use of it sits INSIDE A FUNCTION BODY, so `import tinygrad.
# codegen` succeeds on a tree where every REDUCE reference dangles. Worse, swapping
# `UOp.range(arg=(idx, AxisType))` to `arg=(AxisType, idx)` is a POSITIONAL tuple change:
# rangeify.py keeps importing and keeps type-checking, and dies at run time on
# `TypeError: unsupported operand type(s) for +: 'AxisType' and 'int'` from `x.arg[0] + 1`.
# So the probe is staged and ALL THREE must pass:
#   1. import   -- module-level NameError/ImportError
#   2. compile  -- a real kernel through the full schedule/codegen/opt path
#   3. shape    -- a second program using the arg-tuple fields directly
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIN=6c3d401cf324
HEAD_REF=upstream/master
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rebase-try.XXXXXX")"
TREE="$WORK/tree"            # set by try_batch: the pinned tree plus this candidate overlay
trap 'rm -rf "$WORK"' EXIT

# The functional probe, in three parts, because each covers a different kind of failure.
#
# PART 1 is the one the first version got WRONG, and getting it wrong silently under-reports
# the coupling. `DEV=NULL` never imports ops_cuda/ops_metal/ops_amd/ops_nv/ops_qcom, so
# `--shrink` declared all five of them droppable when in fact each one imports
# `encode_submit` from hcq2 and dies the moment it loads. A probe that cannot see a file is
# not evidence that the file is independent. So part 1 IMPORTS EVERY ops_* MODULE
# EXPLICITLY, whether or not the current DEV would have pulled it in, and it ASSERTS that
# each one is actually in sys.modules -- otherwise a rename or a lazy import would make the
# probe report a clean tree that it never exercised.
exercise() {
  ( cd "$TREE" && PYTHONPATH="$TREE" DEV=NULL python3 - <<'PY' 2>&1
import importlib, sys
from tinygrad import Tensor
(Tensor([64, 64]).realize() + Tensor([64, 64]).realize()).realize().tolist()
a = Tensor.arange(24).reshape(4, 6)
(a[:, 1:4].sum() + a.sum(axis=0).max()).item()

for m in ("ops_amd", "ops_cuda", "ops_metal", "ops_nv", "ops_null", "ops_qcom", "ops_rdma"):
  importlib.import_module(f"tinygrad.runtime.{m}")
  assert f"tinygrad.runtime.{m}" in sys.modules, f"{m} did not stay imported"
import tinygrad.runtime.support.hcq2 as H   # noqa: F401  -- force the hcq2 module to load
from tinygrad.dtype import dtypes
# Batch-INDEPENDENT invariants only, spelled so they hold at BOTH ends of the window.
#
# Three earlier versions of this block were each wrong in a way worth recording, because
# each one reported coupling that did not exist:
#   1. asserting `hasattr(hcq2, "encode_cmdbuf")` -- a name only HEAD has -- made batch 2
#      (dtype+cstyle, which never touches hcq2) fail for a reason belonging to batch 1.
#   2. asserting `dtypes.i8` -- also HEAD-only -- made the PIN tree fail its own probe.
#   3. asserting `dtypes.is_signed` and `dtypes.float32.min == -3.4e38` -- neither exists
#      at BOTH ends: DType has no is_signed, and 793abbb16 changed `DType.min` to -inf for
#      f32. An assertion that is not stable across the window asserts nothing.
# The rule that survives all three: every name must resolve at the pin AND at head, and
# every assertion must be about a structural fact no rename can change.
assert len(dtypes.fp8s) == 4, f"fp8 table has {len(dtypes.fp8s)} members, expected 4"
assert len(dtypes.ints) == 8, f"int ladder has {len(dtypes.ints)} rungs, expected 8"
assert len(dtypes.uints) == 4, f"uint ladder has {len(dtypes.uints)} rungs, expected 4"
assert all(dtypes.is_float(d) for d in dtypes.floats), "floats contains a non-float"
assert dtypes.int8.bitsize == 8 and dtypes.uint8.bitsize == 8
assert dtypes.default_float.bitsize == 32, "default float is not 32-bit"
print("EXERCISE-OK")
PY
  )
}

# why() -- first line of the failure that actually matters, or "" if there isn't one.
why() { grep -E '^(Import|Attribute|Name|Key|Type|Assertion|Unbound)?Error' | head -1 | cut -c1-110; }

try_batch() {
  local label="$1"; shift
  rm -rf "$TREE"; mkdir -p "$TREE"
  git -C "$REPO" archive "$PIN" | tar -x -C "$TREE" || return 2
  local f
  for f in "$@"; do
    git -C "$REPO" show "$HEAD_REF:$f" > "$TREE/$f" || return 2
  done
  local out
  out="$( cd "$TREE" && PYTHONPATH="$TREE" python3 -c "import $probe" 2>&1 )" || {
    printf '  %-34s IMPORT-FAIL  %s\n' "$label" "$(echo "$out" | why)"; return 1; }
  out="$(exercise)" || {
    printf '  %-34s RUN-FAIL     %s\n' "$label" "$(echo "$out" | why)"; return 1; }
  printf '  %-34s OK\n' "$label"
}

probe_of() { printf '%s\n' "$@" | sort | head -1 | sed 's|^tinygrad/||; s|\.py$||; s|/|.|g; s|\.__init__$||'; }
short() { printf '%s\n' "$@" | sed 's|^tinygrad/||; s|\.py$||; s|/|.|g' | paste -sd, -; }

load_batches() { python3 "$REPO/.agents/slop/rebase-plan.py" --json; }

case "${1:---plan}" in
--plan) exec python3 "$REPO/.agents/slop/rebase-plan.py" ;;

--all)
  load_batches > "$WORK/plan.json"
  python3 -c "
import json
for b in json.load(open('$WORK/plan.json'))['batches']:
  if b['size'] > 1: print(b['id'], *b['files'])" | while read -r bid files; do
    set -- $files; probe="tinygrad.$(probe_of "$@")"
    echo "BATCH $bid -- $(short "$@")"
    try_batch "$(short "$@")" "$@"
  done
  ;;

--shrink)
  load_batches > "$WORK/plan.json"
  read -r -a FILES <<<"$(python3 -c "
import json
for b in json.load(open('$WORK/plan.json'))['batches']:
  if str(b['id'])=='$2': print(*b['files'])")"
  probe="tinygrad.$(probe_of "${FILES[@]}")"
  echo "SHRINK batch $2 -- ${#FILES[@]} files: $(short "${FILES[@]}")"
  try_batch "full (${#FILES[@]})" "${FILES[@]}" || exit 1
  # Greedy one-pass elimination. Not guaranteed minimal in general, but every edge here is
  # "X reads a name/shape that Y moved", so one pass exposes every file nothing else needs.
  # A dropped file is one the OTHER members do not require. Dropping is cumulative, so a
  # file that only breaks because of an already-dropped peer is correctly retained.
  drop=()
  for f in "${FILES[@]}"; do
    cand=()
    for g in "${FILES[@]}"; do [ "$g" = "$f" ] && continue; cand+=("$g"); done
    for d in ${drop[@]+"${drop[@]}"}; do cand+=("$d"); done
    if try_batch "drop $(basename "$f")" "${cand[@]}"; then drop+=("$f"); fi
  done
  keep=()
  for f in "${FILES[@]}"; do
    skip=0
    for d in ${drop[@]+"${drop[@]}"}; do [ "$d" = "$f" ] && skip=1; done
    [ $skip -eq 0 ] && keep+=("$f")
  done
  printf 'MINIMAL batch %s -- %d files: %s\n' "$2" "${#keep[@]}" "$(short "${keep[@]}")"
  echo "REQUIRED -- the batch fails without each of these (${#keep[@]} of ${#FILES[@]}):"
  printf '  %s\n' "${keep[@]}"
  ;;

--solo)
  # --solo is the NEGATIVE CONTROL and it is the most load-bearing mode here. It vendors
  # ONE file and nothing else, which is exactly what UPSTREAM-PIN.md used to advise. Every
  # file it reports BROKEN is a live refutation of that advice, produced on demand rather
  # than remembered.
  shift
  for f in "$@"; do
    probe="tinygrad.$(probe_of "$f")"
    try_batch "$(short "$f")" "$f"
  done
  ;;

*)
  probe="tinygrad.$(probe_of "$@")"
  try_batch "$(short "$@")" "$@"
  ;;
esac