#!/bin/sh
# match-rule.sh -- THE MEASUREMENT BEHIND TWO SUBSTRATE CITATIONS.
#
# `tinybendygrad/nn/item.bend` SAYS A `match` MAY NOT SCRUTINISE A COMPUTED
# VALUE OR A LOCAL BINDER, AND `tinybendygrad/runtime/support/autogen.bend`
# SAYS `String.replace` DOES NOT EXIST IN Bend. BOTH CLAIMS NAME A COMPILER
# REVISION, **⇒ AND A CLAIM THAT NAMES A COMPILER IS A CLAIM THAT MOVES WHEN
# THE COMPILER MOVES.** THIS SCRIPT IS THE RE-MEASUREMENT.
#
#   sh .agents/slop/bendup39/match-rule.sh
#
# THE COST: THREE `bin/bend --check-only` PROCESSES, ONE AT A TIME, ~2 s EACH.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
D="$ROOT/.agents/slop/bendup39"
BEND="$ROOT/bin/bend"

fail=0

say() { printf '%s\n' "$*"; }

# 1. THE COMPILER'S OWN IDENTITY, READ THE WAY THE TREE READS IT.
ver=$("$BEND" version)
say "compiler: $ver"
say "pin:      $(sed -n 's/^REF=\${BEND_REF:-\(.*\)}/\1/p' "$ROOT/tools/get-bend.sh")"

# 2. A `match` ON A COMPUTED VALUE. THE PROBE MUST BE REFUSED.
out=$("$BEND" "$D/match-computed-call.bend" --check-only 2>&1 || true)
if printf '%s' "$out" | grep -q "a match cannot scrutinize a computed value"; then
  say "PASS  a match on a COMPUTED value is refused"
else
  say "FAIL  a match on a COMPUTED value is NOT refused -- the compiler moved"
  fail=1
fi

# 3. A `match` ON A LOCAL BINDER. THE PROBE MUST BE REFUSED.
out=$("$BEND" "$D/match-binder.bend" --check-only 2>&1 || true)
if printf '%s' "$out" | grep -q "a match cannot scrutinize a local binder"; then
  say "PASS  a match on a LOCAL BINDER is refused"
else
  say "FAIL  a match on a LOCAL BINDER is NOT refused -- the compiler moved"
  fail=1
fi

# 4. `String.replace` DOES NOT EXIST: base.bend HAS NO SUCH DEF, AND THE ONLY
#    `replace` IN THE COMPILER IS IN ITS OWN JAVASCRIPT.
n=$(grep -c "replace" "$ROOT/references/bend/bend2/base.bend" || true)
if [ "$n" -eq 0 ]; then
  say "PASS  base.bend has no 'replace' (0 lines)"
else
  say "FAIL  base.bend has $n lines with 'replace' -- the compiler moved"
  fail=1
fi

say "VERDICT $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
exit "$fail"
