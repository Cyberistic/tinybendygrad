#!/bin/sh
# verify.sh -- THE CHECKS THIS UNIT OWNS, run under the tree's bend lock, in order.
#
#   .agents/slop/constid/verify.sh
#
# 1  the two `.bend` files this unit edited still COMPILE (they are comment-only, and a
#    comment that does not compile is a broken tree)
# 2  the gate's driver compiles
# 3  the GATE runs and is GREEN
# 4  the PLANT runs and answers its three states
#
# EVERY `bend` RUN GOES THROUGH `checks/bendlock.sh`, and THE LOCK SCRIPT IS TAKEN AS A
# STABLE COPY, ONCE, FOR THE REASON `gates/constid-plant.py`'s docstring gives at length:
# MEASURED 2026-10-22, `checks/bendlock.sh` was EDITED IN FLIGHT by another unit (mtime
# 10:35) while a shell was READING it, and a shell reads a script INCREMENTALLY BY BYTE
# OFFSET -- so it resumed mid-line and executed the wrong bytes
# (`checks/bendlock.sh: line 102: st.: command not found`), and this file's FIRST RUN DIED
# WITH EXIT 127 ON THAT ALONE.  **A REFUSAL CAUSED BY ANOTHER UNIT'S EDIT IS A REFUSAL, NOT
# A MEASUREMENT.**  The lock DIRECTORY is still the tree's shared one, so the serialisation
# is unchanged and only the FILE the shell reads is pinned.
set -eu
cd "$(dirname "$0")/../../.."
LOCKDIR_TMP=$(mktemp -d)
trap 'rm -rf "$LOCKDIR_TMP"' EXIT
cp ./checks/bendlock.sh "$LOCKDIR_TMP/bendlock.sh"
chmod +x "$LOCKDIR_TMP/bendlock.sh"
LOCK="$LOCKDIR_TMP/bendlock.sh"
say() { echo "== $*"; }

say "1: dtype.bend --check-only"
$LOCK -- ./bin/bend tinybendygrad/dtype.bend --check-only
say "2: mixin/creation.bend --check-only"
$LOCK -- ./bin/bend tinybendygrad/mixin/creation.bend --check-only
say "3: gates/constid.bend --check-only"
$LOCK -- ./bin/bend gates/constid.bend --check-only
say "4: the gate"
.venv/bin/python gates/constid-gate.py
say "5: the plant"
.venv/bin/python gates/constid-plant.py
say "DONE"
