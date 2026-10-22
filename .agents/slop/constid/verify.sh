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
# EVERY `bend` RUN GOES THROUGH `checks/bendlock.sh`, which is the tree's own lock: it
# records the owner's PID, checks whether the COMPILER is alive, reclaims a DEAD owner's
# lock and NEVER steals a LIVE owner's.  The wait is REPORTED, because a wait that is not
# reported reads as a hang.
set -eu
cd "$(dirname "$0")/../../.."
LOCK=./checks/bendlock.sh
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
