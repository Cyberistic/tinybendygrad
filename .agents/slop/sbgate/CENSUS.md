DENOMINATOR: 18 shell files under checks/

file                   cd lands       exit  clm  verdict
--------------------------------------------------------
bounded-selftest.sh    INSIDE         0     8    green, 8 claim(s)
classify.sh            OUTSIDE-REPO   1     0    red on exit 1 (NOT a false pass)
demo.sh                OUTSIDE-REPO   0     0    LIES: exit 0, ZERO verdict lines
disarm.sh              OUTSIDE-REPO   0     26   green, 26 claim(s) -- but cwd is OUTSIDE-REPO
e2e.sh                 OUTSIDE-REPO   -     -1   ?
gate.sh                no-cd          2     0    red on exit 2 (NOT a false pass)
gen.sh                 OUTSIDE-REPO   0     9    LIES: exit 0, 9 claims, every one FALSE (GEN_EVIDENCE)
lint_demo.sh           no-cd          1     2    red on exit 1 (NOT a false pass)
lintable-gate.sh       OUTSIDE-REPO   1     0    red on exit 1 (NOT a false pass)
mutate.sh              INSIDE         -     -1   ?
plant.sh               INSIDE         1     1    red on exit 1 (NOT a false pass)
run-all.sh             OUTSIDE-REPO   1     0    red on exit 1 (NOT a false pass)
run-f64.sh             OUTSIDE-REPO   1     3    red on exit 1 (NOT a false pass)
run-port-mm.sh         OUTSIDE-REPO   3     1    red on exit 3 (NOT a false pass)
sb-gate.sh             INSIDE         3     1    red on exit 3 (NOT a false pass)
substrate-check.sh     OUTSIDE-REPO   127   0    red on exit 127 (NOT a false pass)
walk-mutate.sh         no-cd          -     -1   ?
wt-sync.sh             OUTSIDE-REPO   1     0    red on exit 1 (NOT a false pass)

== FINDINGS ==

-- classify.sh
   classify.sh:17  [S3 guarded-absent]
       src: if [ ! -e "$live" ]; then printf 'NOREF\t%s\n' "$f"; continue; fi
       why: no else arm: a MISSING input skips the comparison entirely and the script continues to a clean exit
   classify.sh:12  [S1 cd-outside-repo]
       src: cd "$(dirname "$0")/../../.." || exit 1
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- demo.sh
   demo.sh:16  [S1 cd-outside-repo]
       src: cd "$(dirname "$0")/../../.." || exit 2
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- disarm.sh
   disarm.sh:15  [S1 cd-outside-repo]
       src: cd "$(dirname "$0")/../../.." || exit 2
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- e2e.sh
   e2e.sh:57  [S2 ||-swallow]
       src: head -3 "$RUN/e2e-mm-bend.err" >&2 2>/dev/null || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   e2e.sh:100  [S2 set +e]
       src: set +e; node .agents/slop/e2e_mm_run.mjs; nsrc=$?; set -e
       why: errexit is off from here to the next `set -e`; any command in that window may fail silently
   e2e.sh:112  [S2 set +e]
       src: set +e
       why: errexit is off from here to the next `set -e`; any command in that window may fail silently
   e2e.sh:147  [S2 set +e]
       src: set +e
       why: errexit is off from here to the next `set -e`; any command in that window may fail silently
   e2e.sh:187  [S2 set +e]
       src: set +e
       why: errexit is off from here to the next `set -e`; any command in that window may fail silently
   e2e.sh:224  [S2 set +e]
       src: set +e
       why: errexit is off from here to the next `set -e`; any command in that window may fail silently
   e2e.sh:289  [S5 exit 0]
       src: exit 0
       why: unconditional success; check what guarded the line above it
   e2e.sh:292  [S5 exit 0]
       src: exit 0
       why: unconditional success; check what guarded the line above it
   e2e.sh:33  [S1 cd-outside-repo]
       src: ROOT=$(cd "$(dirname "$0")/../.." && pwd)
       why: resolves to /Users/cyberistic/src/tries, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- gate.sh
   gate.sh:17  [R2 trap-EXIT]
       src: trap 'rm -rf "$OUT"' EXIT
       why: an EXIT trap's last command becomes the script's
   gate.sh:21  [S2 ||-swallow]
       src: perl -e 'alarm 900; exec @ARGV' ./bin/bend $SL/gate.bend | grep '^ss' > "$OUT/all-bend.txt" || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   gate.sh:27  [S2 ||-swallow]
       src: grep '^ss_'  "$OUT/all.txt"       > "$OUT/py.txt"  || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   gate.sh:28  [S2 ||-swallow]
       src: grep '^ssx_' "$OUT/all.txt"       > "$OUT/py-d.txt" || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   gate.sh:29  [S2 ||-swallow]
       src: grep '^ss_'  "$OUT/all-bend.txt"  > "$OUT/bend.txt"  || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   gate.sh:30  [S2 ||-swallow]
       src: grep '^ssx_' "$OUT/all-bend.txt"  > "$OUT/bend-d.txt" || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying

-- gen.sh
   gen.sh:36  [S1 cd-outside-repo]
       src: cd "$(dirname "$0")/../../.." || exit 1
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- lint_demo.sh
   lint_demo.sh:19  [R2 trap-EXIT]
       src: trap 'rm -rf "$WORK"' EXIT
       why: an EXIT trap's last command becomes the script's
   lint_demo.sh:58  [S5 exit 0]
       src: exit 0
       why: unconditional success; check what guarded the line above it

-- lintable-gate.sh
   lintable-gate.sh:28  [S1 cd-outside-repo]
       src: cd "$(dirname "$0")/../../.."
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- plant.sh
   plant.sh:29  [S3 guarded-absent]
       src: if [ ! -f "$SNAP" ]; then
       why: no else arm: a MISSING input skips the comparison entirely and the script continues to a clean exit
   plant.sh:41  [S2 ||-swallow]
       src: > "$W/derive.$label.txt" 2>&1 || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   plant.sh:43  [S2 ||-swallow]
       src: --tsv "$W/four-col.$label.tsv" > "$W/four-col.$label.txt" 2>&1 || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   plant.sh:47  [S2 ||-swallow]
       src: > "$W/agree.$label.txt" 2> "$W/agree.$label.err" || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying

-- run-all.sh
   run-all.sh:56  [S2 ||-swallow]
       src: CS2_REPO="$REPO" python3 "$HERE/agree.py" "$W/convert2.tsv" | tee "$W/agree.txt" || true
       why: the producer's status is discarded; the comparison below sees whatever it got and cannot report the producer dying
   run-all.sh:12  [S1 cd-outside-repo]
       src: REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
       why: resolves to /Users/cyberistic/src/tries, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- run-f64.sh
   run-f64.sh:97  [S4 read-missing]
       src: say "   quoted cstyle-live/run-all.log:5  sha256 $(grep -m1 'live    cstyle.bend' "$ROOT/.agents/slop/cstyle-live/run-all.log" | awk '{print $NF}')"
       why: cstyle-live/run-all.log exists nowhere under the repo: an input the comparison names but the tree does not hold
   run-f64.sh:97  [S4 read-missing]
       src: say "   quoted cstyle-live/run-all.log:5  sha256 $(grep -m1 'live    cstyle.bend' "$ROOT/.agents/slop/cstyle-live/run-all.log" | awk '{print $NF}')"
       why: cstyle.bend exists nowhere under the repo: an input the comparison names but the tree does not hold
   run-f64.sh:207  [R3 process-sub]
       src: awk '{print $3}' <(grep '^WORD ' "$W/a/run1.txt") > "$W/port-words.txt"
       why: bashism <( )
   run-f64.sh:64  [S1 cd-outside-repo]
       src: ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing
   run-f64.sh:148  [S1 cd-outside-repo]
       src: ed2_new='ROOT=$(cd "$(dirname "$0")/../../.." && pwd)'
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- run-port-mm.sh
   run-port-mm.sh:50  [R2 trap-EXIT]
       src: trap cleanup EXIT
       why: an EXIT trap's last command becomes the script's
   run-port-mm.sh:123  [R3 process-sub]
       src: awk '{print $3}' <(grep '^WORD ' "$W/b/run1.txt") > "$W/port-words.txt"
       why: bashism <( )
   run-port-mm.sh:37  [S1 cd-outside-repo]
       src: ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing
   run-port-mm.sh:157  [S1 cd-outside-repo]
       src: "ROOT=$ROOT" 'ROOT=$(cd "$(dirname "$0")/../../.." && pwd)' > /dev/null || return 1
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- sb-gate.sh
   sb-gate.sh:93  [S2 set +e]
       src: set +e
       why: errexit is off from here to the next `set -e`; any command in that window may fail silently

-- substrate-check.sh
   substrate-check.sh:31  [S1 cd-outside-repo]
       src: cd "$_d/../.." || exit 2
       why: resolves to /Users/cyberistic/src/tries, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

-- walk-mutate.sh
   walk-mutate.sh:118  [S5 exit 0]
       src: exit 0
       why: unconditional success; check what guarded the line above it

-- wt-sync.sh
   wt-sync.sh:16  [S1 cd-outside-repo]
       src: R="$(cd "$(dirname "$0")/../../.." && pwd)"
       why: resolves to /Users/cyberistic/src, which is not under the repo root /Users/cyberistic/src/tries/2026-09-30-tinybendygrad; every relative path after this line names nothing

CAN EXIT 0 WITHOUT HAVING RUN (dynamic, SAFE set): 2/18
cd RESOLVES OUTSIDE THE REPO (static, all files): 11/18
