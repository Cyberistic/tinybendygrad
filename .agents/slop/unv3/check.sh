#!/usr/bin/env bash
# check.sh -- MEASURE THE SLICE ON A FROZEN COPY OF THE LIVE TREE.
#
#   .agents/slop/unv3/check.sh <name>
#
# THE TREE IS SHARED AND IT MOVES. Another unit edits files I do not own WHILE I
# measure, so a copy of the LIVE tree measures THEIR work too and a before/after
# reading taken at two different moments compares two different trees.
#
# ⇒ SO THE COPY IS TAKEN ONCE, AT THE START OF THE MEASUREMENT, AND THEN FROZEN.
# ⇒ AND THE COPY IS THE LIVE TREE, NOT THE BASE: the files I DO NOT OWN have
#   MOVED (another unit added lines to `nn/layers.bend` while I worked), and a
#   pointer into a file I do not own must name the line that file has NOW. A
#   frozen BASE would measure a tree that no longer exists, and the gate would
#   report a stale pointer that is NOT stale in the tree the port actually ships.
#
# ⇒ THE BASE IS KEPT FOR THE "BEFORE" READING ONLY, and it is read ONCE, at the
#   start, so the two readings are of two trees and each is named.
set -u
cd "$(dirname "$0")/../../.." || exit 3
NAME="${1:-run}"
ROOT="$PWD"
WORK=".agents/slop/unv3/work-$NAME"
rm -rf "$WORK"
mkdir -p "$WORK"
# THE BASE IS A COPY OF HEAD WITH THE PORT OVER IT; IT IS A CONVENIENCE, NOT A
# REQUIREMENT, AND IT IS NOT COMMITTED (479 MB).
if [ -d "$ROOT/.agents/slop/unv3/base" ]; then cp -R "$ROOT/.agents/slop/unv3/base/." "$WORK/"; fi
# THE LIVE PORT, OVER THE BASE: every file's CURRENT bytes, in one frozen copy.
rsync -a --delete "$ROOT/tinybendygrad/" "$WORK/tinybendygrad/"
# THE COMPILER's OWN TREE. `references/` IS GITIGNORED (`.gitignore:2`), so the
# `git archive` of HEAD does NOT carry it, and a copy without it resolves every
# `base.bend` pointer into the PORT's 56-LINE `base.bend` -- which is how a
# CORRECT pointer to the COMPILER's 3,191-line `base.bend` reads as DANGLING.
if [ -d "$ROOT/references" ]; then rsync -a --delete "$ROOT/references/" "$WORK/references/"; fi
.venv/bin/python gates/pin-cite-gate.py --tree "$WORK" --rows "$WORK/pin.rows" --no-report >"$WORK/pin.out" 2>&1
PINRC=$?
.venv/bin/python gates/bendcite-gate.py --tree "$WORK" --rows "$WORK/bend.rows" >"$WORK/bend.out" 2>&1
BENDRC=$?
echo "== pin-cite rc=$PINRC  bendcite rc=$BENDRC  ($NAME)"
.venv/bin/python .agents/slop/unv3/mine.py pin "$WORK/pin.rows"
.venv/bin/python .agents/slop/unv3/mine.py bend "$WORK/bend.rows"
