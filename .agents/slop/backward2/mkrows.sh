#!/bin/sh
# THE ORACLE -> THE EXPECTED ROWS.  Transcribed BY SCRIPT, never by hand.
#
#   sh .agents/slop/backward2/mkrows.sh
#
# `oracle-gs.py` prints `oracle_<name>=<value>`; the port prints `<name>=<value>`.  The
# MAP is the prefix `oracle_` and nothing else, and the map is applied by the script --
# a hand-typed expectation is a copy of the port's own output, which is a VACUITY with
# more steps.
#
# THE EXPECTATIONS ARE CPYTHON'S.  If the port's row and CPython's row disagree, the
# diff says so and names the row.
set -u
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/../../.." || exit 2
ROOT=$PWD
OUT=".agents/slop/backward2"
export LC_ALL=C DEV=NULL
unset PYTHONPATH
"$ROOT/.venv/bin/python" "$OUT/oracle-gs.py" > "$OUT/oracle-gs.rows" || { echo "ORACLE FAILED"; exit 1; }
"$ROOT/.venv/bin/python" - "$OUT/oracle-gs.rows" "$OUT/rows.rows" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
rows = []
for line in open(src):
  line = line.rstrip("\n")
  if not line.startswith("oracle_"): continue
  name, _, val = line[len("oracle_"):].partition("=")
  # THE PORT'S ROW NAMES.  `gs_set_order` has no port row: it is CPython's own
  # diagnostic and it is not gated (the target order is visible in `gs_set_sig`).
  if name == "gs_set_order": continue
  # `bw_ops` IS NOT GATED: `bw_sig` already names every node and every op in the
  # backward graph, and a per-op COUNT is a second reading of the same row.
  if name == "bw_ops": continue
  rows.append("%s=%s" % (name, val))
open(dst, "w").write("\n".join(rows) + "\n")
print("wrote %d rows to %s" % (len(rows), dst))
PY
