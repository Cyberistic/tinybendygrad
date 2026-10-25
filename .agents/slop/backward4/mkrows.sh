#!/bin/sh
# THE ORACLE -> THE EXPECTATIONS.  Transcribed BY SCRIPT, never by hand.
#
#   sh .agents/slop/backward4/mkrows.sh
#
# `oracle-pm.py` prints `oracle_<the port's row name>=<value>`; the port prints
# `<the port's row name>=<value>`.  The map is ONE RULE -- strip the `oracle_` prefix --
# and it lives in `mkrows.py`; the VALUES are CPython's own bytes.
#
# THE EXPECTATIONS ARE CPYTHON'S.  If the port's row and CPython's row disagree, the
# gate says so and names the row.
set -u
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/../../.." || exit 2
ROOT=$PWD
OUT=".agents/slop/backward4"
export LC_ALL=C DEV=NULL
unset PYTHONPATH
"$ROOT/.venv/bin/python" "$OUT/oracle-pm.py" > "$OUT/oracle-pm.rows" || {
  echo "ORACLE FAILED"; exit 1; }
"$ROOT/.venv/bin/python" "$OUT/mkrows.py" "$OUT/oracle-pm.rows" "$OUT/perm.rows" || exit 1
echo "--- the oracle's rows that are NOT transcribed (named, not dropped):"
grep -v '^oracle_' "$OUT/oracle-pm.rows" | sed 's/^/    /'
