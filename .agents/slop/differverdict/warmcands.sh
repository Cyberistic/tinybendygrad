#!/bin/sh
# Find the most recent COMMIT whose graphcmp.bend + ops.bend agree, by checking each of
# HEAD's predecessors. The live tree is cold in one direction (graphcmp.bend has the
# AOpLit arm, ops.bend lost the variant) and HEAD is cold in the other (ops.bend has the
# variant, graphcmp.bend never got the arm). The oracle needs a WARM substrate, because two
# identical 0-row failures compare equal -- which is the trap this comparison exists to avoid.
set -u
SRC=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
cd "$SRC"
for c in $(jj log -r 'all()' --no-graph -T 'commit_id ++ "\n"' 2>/dev/null | head -60); do
  has=$(jj file show -r "$c" .agents/slop/graphcmp.bend 2>/dev/null | grep -c 'O\.AOpLit')
  ops=$(jj file show -r "$c" tinybendygrad/uop/ops.bend 2>/dev/null | grep -c 'AOpLit{op: Op}')
  printf '%s  graphcmp-arm=%s  ops-variant=%s  %s\n' "$(echo "$c" | cut -c1-12)" "$has" "$ops" \
    "$(jj log -r "$c" --no-graph -T 'description.first_line()' 2>/dev/null)"
done