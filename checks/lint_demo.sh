#!/bin/zsh
# lint_demo.sh -- show BOTH branches of lint_norm.py's exit status, as measurements.
#
#   zsh checks/lint_demo.sh
#
# A lint pinned to a constant is the fifth instance of the family it exists to
# stop, and so is a lint nobody has watched fail.  So: the live tree is COPIED to
# $TMPDIR, the lint is run on the copy as it stands, ONE `repr(float(` is then
# planted in a gate that is already on the baseline for a DIFFERENT line, and the
# lint is run again.  NOTHING IS PLANTED IN THE LIVE TREE.
#
# THE COPY CARRIES THE WHOLE `slop/` TREE because `agent-core.md:218` records that
# a $TMPDIR scratch copy cannot resolve a relative import, and 22 phantom blind
# spots in one unit came from exactly that.

HERE="${0:A:h}"
REPO="$HERE/../../.."
WORK="$(mktemp -d "${TMPDIR:-/tmp}/normdemo.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cp -R "$REPO/.agents/slop" "$WORK/slop"
rm -f "$WORK/slop/norm/lint_demo.sh" "$WORK/slop/norm/census.txt"

run() {
  python3 "$WORK/slop/norm/lint_norm.py" > "$WORK/$1.txt" 2>&1
  print -r -- "$?"
}

report() {
  grep -E '^!! ' "$WORK/$1.txt" 2>/dev/null
  grep -E 'baseline present' "$WORK/$1.txt" 2>/dev/null
}

base=$(run base)
print -r -- "RUN 1 -- the copy as it stands:"
print -r -- "  exit $base"
report base

print -r -- ""
print -r -- "PLANTING one non-round-tripping normaliser in mm-dt-gate.py."
print -r -- "That file is ALREADY on the baseline, for :60 -- so the new site is NEW,"
print -r -- "and the lint has to say so rather than absorb it into the baseline."
python3 - "$WORK/slop/mm-dt-gate.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text() + "\n\ndef norm_added_later(s):\n  return repr(float(s))\n")
PY

planted=$(run planted)
print -r -- ""
print -r -- "RUN 2 -- the same copy WITH the plant:"
print -r -- "  exit $planted"
report planted

print -r -- ""
if [[ "$base" == "0" && "$planted" == "1" ]]; then
  print -r -- "BOTH BRANCHES MEASURED: green on the tree, red on a new site."
  exit 0
fi
print -r -- "THE LINT DID NOT FLIP -- one of the two numbers is a constant."
exit 1