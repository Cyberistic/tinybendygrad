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

# The functional probe. Two programs, because the failures above land in different places:
# a matmul reaches codegen/opt and the renderer, and a strided slice + reduction reaches
# schedule/rangeify, which is where the arg-tuple swap detonates.
exercise() {
  ( cd "$TREE" && PYTHONPATH="$TREE" DEV=NULL python3 - <<'PY' 2>&1
from tinygrad import Tensor
(Tensor([64, 64]).realize() + Tensor([64, 64]).realize()).realize().tolist()
a = Tensor.arange(24).reshape(4, 6)
(a[:, 1:4].sum() + a.sum(axis=0).max()).item()
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
  printf 'MINIMAL batch %s -- %d files: %s\n' "$2" "$(( ${#FILES[@]} - ${#drop[@]} ))" \
    "$(short $(for f in "${FILES[@]}"; do for d in ${drop[@]+"${drop[@]}"}; do
        [ "$d" = "$f" ] || printf '%s\n' "$f"; done; done))"
  echo "REQUIRED -- another member fails without it:"
  printf '  %s\n' "${drop[@]}"
  ;;

*)
  probe="tinygrad.$(probe_of "$@")"
  try_batch "$(short "$@")" "$@"
  ;;
esac