#!/bin/sh
# THE BODY-VERIFICATION INSTRUMENT, IN ONE COMMAND.
#
#   .agents/slop/sym92/symrules-verify.sh
#
# IT RUNS THE PORT's DRIVER OVER `gates/symrules-cases.rows` AND DIFFS THE ANSWERS AGAINST
# CPYTHON's. **BOTH HALVES WERE ABSENT OR BROKEN BEFORE 2026-11-06**: THE DRIVER DID NOT EXIST
# AND THE ORACLE REFUSED EVERY CASE ON A `KeyError: 'FLOORDIV'`.
#
# EXIT: 0 the two agree on every case · 1 they disagree · 3 the driver or the oracle failed.
set -e
cd "$(dirname "$0")/../../.."
OUT="$(mktemp "${TMPDIR:-/tmp}/symrules-driver.XXXXXX")"
trap 'rm -f "$OUT"' EXIT
./bin/bend gates/symrules-driver.bend > "$OUT"
exec .venv/bin/python gates/symrules-oracle.py --compare "$OUT"
