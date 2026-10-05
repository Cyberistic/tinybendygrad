#!/bin/sh
# checks/bounded.py selftest. Four cases, and the point of each is named below.
#
# WHY A SELFTEST AND NOT A DEMONSTRATION: this guard exists because two unbounded builds
# crashed the machine. A guard that has never been shown to FIRE is the project's seventeenth
# instrument defect, so both bounds are shown firing here, and the grandchild case is shown
# firing because the original runaway was a spawned child, not the process we launched.
#
# Run: sh checks/bounded-selftest.sh
set -u
cd "$(dirname "$0")/.." || exit 2
P=.venv/bin/python
G="env -u PYTHONPATH $P checks/bounded.py"
fail=0

note() { printf '\n--- %s\n' "$1"; }
verdict() { printf '   %s\n' "$1"; }

note "1. PASS-THROUGH: a real bend --check-only, and the peak RSS is the fact reported"
$G --seconds 540 --mb 4096 -- ./bin/bend tinybendygrad/helpers.bend --check-only 2>&1 | tail -2
$G --seconds 540 --mb 4096 -- ./bin/bend tinybendygrad/helpers.bend --check-only >/dev/null 2>&1
[ $? -le 1 ] || { echo "   FAIL: a healthy run did not exit cleanly"; fail=1; }

note "2. THE MEMORY BOUND MUST FIRE (ceiling 300 MB, allocator with no bound)"
cat > "$TMPDIR/bomb.pl" <<'EOF'
my @a; while (1) { push @a, ("x" x 1_000_000) }
EOF
$G --seconds 120 --mb 300 -- perl "$TMPDIR/bomb.pl" 2>&1 | tail -2
$G --seconds 120 --mb 300 -- perl "$TMPDIR/bomb.pl" >/dev/null 2>&1
rc=$?
[ "$rc" = 3 ] || { echo "   FAIL: expected exit 3 (KILLED-ON-MEMORY), got $rc"; fail=1; }
verdict "exit $rc == 3, as documented"

note "3. THE TIME BOUND MUST FIRE, and be DISTINGUISHABLE from the memory bound"
$G --seconds 5 --mb 4096 -- sleep 60 2>&1 | tail -2
$G --seconds 5 --mb 4096 -- sleep 60 >/dev/null 2>&1
rc=$?
[ "$rc" = 4 ] || { echo "   FAIL: expected exit 4 (TIMED-OUT), got $rc"; fail=1; }
verdict "exit $rc == 4, and the message says rc=142 would be SIGALRM"

note "4. THE GRANDCHILD CASE -- the one that crashed the machine"
# THE ABSOLUTE PATH IS THE POINT, AND IT WAS MISSED ONCE. The first version of this case
# passed a BARE FILENAME to `system`, which resolves against the WORKING DIRECTORY, so the
# grandchild never started and the guard reported WITHIN-LIMITS -- a PASS produced by a bomb
# that never exploded. A test that cannot fail has told me nothing about the thing it names,
# and this is the seventeenth instance of that shape with a new name on it.
cat > "$TMPDIR/bomb-child.pl" <<'EOF'
my @a; while (1) { push @a, ("y" x 1_000_000) }
EOF
[ -s "$TMPDIR/bomb-child.pl" ] || { echo "   SETUP FAIL: the grandchild script is absent"; fail=1; }
$G --seconds 60 --mb 250 -- perl -e 'system($^X, $ARGV[0])' "$TMPDIR/bomb-child.pl" 2>&1 | tail -2
$G --seconds 60 --mb 250 -- perl -e 'system($^X, $ARGV[0])' "$TMPDIR/bomb-child.pl" >/dev/null 2>&1
rc=$?
if [ "$rc" = 3 ]; then
  verdict "exit 3 -- the watchdog saw the GRANDCHILD's RSS, not just the child's"
else
  echo "   FAIL: a bomb inside a spawned child was not caught (exit $rc)"
  echo "   NOTE: that is the failure mode that cost the machine, and it must not regress."
  fail=1
fi

note "5. A CHILD THAT EXITS CLEANLY IS NOT REPORTED AS A BOUND"
$G --seconds 30 --mb 4096 -- /bin/echo ok >/dev/null 2>&1
[ $? = 0 ] || { echo "   FAIL: a clean child did not exit 0"; fail=1; }

rm -f "$TMPDIR/bomb.pl" "$TMPDIR/bomb-child.pl" 2>/dev/null
printf '\n=== selftest %s ===\n' "$([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail