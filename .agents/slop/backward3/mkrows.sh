#!/bin/sh
# THE ORACLE -> THE EXPECTATIONS.  Transcribed BY SCRIPT, never by hand.
#
#   sh .agents/slop/backward3/mkrows.sh
#
# `../backward/oracle-cg.py` prints `oracle_dag_<x>=<value>`; the port prints
# `walk_<x>=<value>`.  The map is a RULE plus ONE named exception and it lives in
# `mkrows.py`; the VALUES are CPython's own bytes.
#
# THE EXPECTATIONS ARE CPYTHON'S.  If the port's row and CPython's row disagree, the
# gate says so and names the row.
set -u
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/../../.." || exit 2
ROOT=$PWD
OUT=".agents/slop/backward3"
export LC_ALL=C DEV=NULL
unset PYTHONPATH
"$ROOT/.venv/bin/python" "$OUT/../backward/oracle-cg.py" > "$OUT/oracle-cg.rows" || {
  echo "ORACLE FAILED"; exit 1; }
"$ROOT/.venv/bin/python" "$OUT/mkrows.py" "$OUT/oracle-cg.rows" "$OUT/walk.rows" || exit 1
echo "--- the oracle's rows that are NOT gated (named, not dropped):"
grep -v '^oracle_dag_' "$OUT/oracle-cg.rows" | sed 's/^/    /'
