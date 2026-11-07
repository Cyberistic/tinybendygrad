#!/bin/sh
# THE DELETED-RULES SWEEP, IN ONE COMMAND.
#
#   .agents/slop/sym92/deadrules-sweep.sh
#
# **IT ASKS EACH CANDIDATE'S SHAPE WHETHER THE PORT REWRITES IT AND WHETHER UPSTREAM DOES,
# AND IT IS THE BEHAVIOURAL TEST -- THE ONLY TEST THAT SETTLES "DELETED vs REWORDED".**
#
# **AND IT USES THE SAME 2,397-LINE DRIVER AS THE MAIN INSTRUMENT, WITH ITS CASES PATH
# OVERRIDED BY `IO.args()`** -- MEASURED 2026-11-08, `IO.args()` WORKS WITH `bin/bend` AND
# INDEX 0 IS THE PROGRAM, SO THE PATH IS INDEX **1** -- **SO THERE IS NO SECOND COPY OF THE
# DRIVER AND NO SECOND TRUTH ABOUT HOW THE PORT REWRITES.**
#
# EXIT: 0 the two agree on every case · 1 they disagree · 3 the driver or the oracle failed.
set -e
cd "$(dirname "$0")/../../.."
CASES=".agents/slop/sym92/deadrules-candidates.rows"
OUT="$(mktemp "${TMPDIR:-/tmp}/deadrules-driver.XXXXXX")"
trap 'rm -f "$OUT"' EXIT
./bin/bend gates/symrules-driver.bend "$CASES" > "$OUT"
exec .venv/bin/python gates/symrules-oracle.py --cases "$CASES" --compare "$OUT"
