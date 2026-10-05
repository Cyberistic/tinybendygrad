#!/bin/sh
# THE EXPERIMENT. Rename the artifact set's EXTENSION in ONE place -- nothing else -- and show
# the sha256 pin still reports INTACT while the guards stop looking at anything.
#
#     usage: sh .agents/slop/difftxt/rename-experiment.sh
#
# THREE POPULATIONS, ONE SET OF GUARDS:
#   live   the tree as it is
#   rows   the same files with `*.txt` -> `*.rows`: EXACTLY the one-place rename under debate
#   empty  what a guard that matches nothing is left looking at
#
# THE QUESTION IS NOT "does the rename break". It is "WHICH GUARD NOTICES, AND WHICH ONE IS
# STILL SILENT WHEN IT DOES NOT".
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd) || exit 2
cd "$ROOT" || exit 2
G=.agents/slop/difftxt
# INSIDE ROOT, because `artefacts_ok()` calls `p.relative_to(ROOT)` and a population outside the
# tree -- or addressed relatively -- makes it raise ValueError instead of answering. That is a
# harness artifact, not a finding, so the path is absolute and under ROOT.
S=$ROOT/$G/scratch

rm -rf "$S"; mkdir -p "$S/empty"
cp -R runs/graphcmp/D "$S/live"
cp -R runs/graphcmp/D "$S/rows"
for f in "$S"/rows/*.txt; do mv "$f" "${f%.txt}.rows"; done

echo "== 1. THE PIN. Renaming the artifact set touches no oracle byte. =="
.venv/bin/python - <<'EOF'
import importlib.util
spec = importlib.util.spec_from_file_location("d", "checks/differ.py")
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
drift = d.check_oracle()
print("   check_oracle() ->", drift if drift else "[] -- PIN INTACT")
EOF

echo
echo "== 2. THE ORACLE'S GUARDS, verbatim, against three populations =="
printf "   %-6s %6s %8s %9s %9s %11s\n" pop files '*.txt' '*.rows' healthy artefacts_ok
for pop in live rows empty; do
  p="$S/$pop"
  a=$(sh "$G/oracle-probe.sh" "$p" artefacts_ok 2>/dev/null | grep -c . | tr -d ' ')
  h=$(sh "$G/oracle-probe.sh" "$p" healthy 2>/dev/null | sed 's/rc=//')
  printf "   %-6s %6s %8s %9s %9s %11s\n" "$pop" \
    "$(find "$p" -type f ! -name '.*' | wc -l | tr -d ' ')" \
    "$(find "$p" -name '*.txt' ! -name '*.err' | wc -l | tr -d ' ')" \
    "$(find "$p" -name '*.rows' | wc -l | tr -d ' ')" \
    "$([ "$h" = 0 ] && echo TRUE || echo FALSE)" "$a"
done

echo
echo "== 3. THE ONE LINE A READER SEES: clean_run's verdict per population =="
for pop in live rows empty; do
  printf "   %-6s %s\n" "$pop" "$(sh "$G/oracle-probe.sh" "$S/$pop" verdict 2>/dev/null)"
done

echo
echo "== 4. differ.py's OWN guards, run against the same populations =="
.venv/bin/python - "$S" <<'EOF'
import importlib.util, pathlib, sys
scratch = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("d", "checks/differ.py")
d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)


def show(f, *a):
    try:
        r = f(*a)
    except Exception as e:
        return f"RAISED {type(e).__name__}: {e}"
    kinds = Counter(x.split()[0] for x in r)
    return f"{len(r):>3} finding(s) {dict(kinds)} first: {r[0] if r else '-- NONE --'}"


from collections import Counter
for pop in ("live", "rows", "empty"):
    d.D = scratch / pop
    print(f"   {pop:<6} artefacts_ok -> {show(d.artefacts_ok)}")
    print(f"   {pop:<6} unhealthy    -> {show(d.unhealthy)}")
EOF

echo
echo "== 5. checks/corpus-figure.py, which reads the summary BY NAME and is NOT mine =="
grep -n 'D0-run-summary' checks/corpus-figure.py | sed 's/^/   /'
echo "   its guard is 'if not summary.exists()', which is LOUD, not silent:"
echo "   live  D0-run-summary.txt present? $([ -e runs/graphcmp/D/D0-run-summary.txt ] && echo YES || echo NO)"
echo "   rows  D0-run-summary.txt present? $([ -e "$S/rows/D0-run-summary.txt" ] && echo YES || echo 'NO -> it prints NO RUN SUMMARY and main() returns 1')"