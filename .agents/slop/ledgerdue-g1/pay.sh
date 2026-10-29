#!/bin/sh
# Pay the ledger debt for the paths in g1.txt, ONE PATH PER INVOCATION.
#
# The tool is `gates/gates-pop.py --write-ledger --only PATH`. The brief mandates one
# invocation per path, and the tool's own rule (a write of the shared ledger without a
# pathspec is the central sweep, refused) is why: a pathspec is the boundary.
#
# The invocations are SEQUENTIAL on purpose. `gates/gates-pop.py` has no lock -- unlike
# `checks/differ.py`, which takes an `fcntl.flock` on `runs/graphcmp/.corpus.lock` -- so two
# concurrent writers on the shared ledger race read-modify-write and one loses. Sequential
# is the mitigation available to a caller that may not edit the tool.
#
# Every invocation's full output is kept, so the report can cite what each write said.
set -u
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad || exit 1
LIST=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/due/g1.txt
LOG=.agents/slop/ledgerdue-g1/writes
mkdir -p "$LOG"
n=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  n=$((n+1))
  out="$LOG/$(printf '%02d' "$n")-$(basename "$p").out"
  before=$(grep -c "^$p	" gates/gates-pop.ledger.tsv 2>/dev/null || true)
  .venv/bin/python gates/gates-pop.py --write-ledger --only "$p" >"$out" 2>&1
  rc=$?
  after=$(grep -c "^$p	" gates/gates-pop.ledger.tsv 2>/dev/null || true)
  absorbed=$(grep -o "IT ABSORBED [0-9]* new, [0-9]* changed, [0-9]* returned and RETIRED [0-9]*" "$out" | head -1)
  wrote=$(grep -c "III LEDGER WROTE" "$out")
  printf '%s\t%s\trc=%s\tbefore=%s\tafter=%s\twrote=%s\t%s\n' \
    "$n" "$p" "$rc" "${before:-0}" "${after:-0}" "$wrote" "$absorbed" \
    >> .agents/slop/ledgerdue-g1/pay.rows
done < "$LIST"
echo "PAY DONE $n path(s)"
