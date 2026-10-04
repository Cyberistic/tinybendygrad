#!/bin/sh
# A SCRATCH ROOT holding a CLEAN HEAD port, so the oracle and the Python driver can be
# compared on a substrate that is actually warm. Two units are mid-edit in the live tree
# (ops.bend:715 is cold, graphcmp.py has lost load_tinygrad), and comparing two 0-row
# failures is the trap this project has already paid for twice.
#
# GCMP_REPO is exactly the hook the frozen oracle was given its one documented edit for,
# so the comparison uses the oracle as frozen.
set -eu
SRC=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
DST=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/differverdict/root
mkdir -p "$(dirname "$DST")"
rm -rf "$DST"
mkdir -p "$DST"
cd "$SRC"
# HEAD's tree, with no uncommitted edits: jj's committed state.
jj file list -r 'heads(::)' 2>/dev/null || true
git archive HEAD 2>/dev/null | tar -x -C "$DST" || {
  echo "no git archive; falling back to copying the tree and reverting .bend/.py edits" >&2
  exit 1
}
# The venv and bin/bend are untracked infrastructure, not source.
ln -s "$SRC/.venv" "$DST/.venv"
mkdir -p "$DST/bin"
ln -s "$SRC/bin/bend" "$DST/bin/bend"
echo "root ready: $DST"
cd "$DST" && ls | head -30