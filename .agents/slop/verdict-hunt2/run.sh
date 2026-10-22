#!/bin/sh
# run.sh <file.bend> -- run the pinned bend at the pinned revision on <file.bend>,
# with --check-only and --verdict, capturing both streams and exit codes.
#
# BENDTT points at the kernel built from references/bend/bend2/bendtt.lean with
# Lean v4.34.0 (the version safe.ts pins).  The kernel is COPIED into this
# workspace, so no other unit's cache is touched.
set -u
W=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/verdicthunt2
ART=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/verdict-hunt2
BEND=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
export BENDTT="$ART/kernel/bendtt"
f="$1"
b=$(basename "$f" .bend)
out="$ART/receipts/$b"
mkdir -p "$out"
"$BEND" "$f" --check-only >"$out/check.out" 2>"$out/check.err"; echo $? >"$out/check.rc"
"$BEND" "$f" --verdict   >"$out/verdict.out" 2>"$out/verdict.err"; echo $? >"$out/verdict.rc"
printf '%s\n' "== $f"
printf 'check-only : rc=%s | stdout=%s | stderr=%s\n' \
  "$(cat "$out/check.rc")" "$(head -c 300 "$out/check.out" | tr '\n' ' ')" "$(head -c 300 "$out/check.err" | tr '\n' ' ')"
printf 'verdict    : rc=%s | stdout=%s | stderr=%s\n' \
  "$(cat "$out/verdict.rc")" "$(head -c 300 "$out/verdict.out" | tr '\n' ' ')" "$(head -c 300 "$out/verdict.err" | tr '\n' ' ')"
