#!/usr/bin/env bash
# I64DIV-9: THE IMPORT CLOSURE OF helpers.bend, BEFORE AND AFTER, IN A MIRROR.
#
# WHY A MIRROR AND NOT A SWAP: `helpers.bend` has been truncated to 0 bytes three
# times today, and swapping it in place to measure a baseline risks losing it. So
# the tree is COPIED to $TMPDIR with its structure intact -- relative imports
# resolve, which is the `$TMPDIR` trap in agent-core.md -- and the verdict for
# every `.bend` that transitively reaches `helpers.bend` is read in the mirror,
# once with the PRISTINE helpers.bend and once with the current one.
#
# `--check-only` reports `ALL PROOFS CHECK` FOR AN EMPTY FILE and also passes a
# COLLECTIVELY-INCOMPLETE file, so a row is the STDERR TEXT and not the exit
# status, and every row is compared as whole text.
set -u
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
BEND=$REPO/bin/bend
WORK="$TMPDIR/i64div-closure"
PRISTINE=$REPO/.agents/slop/i64mul/helpers.pristine.bend
LIVE=$REPO/tinybendygrad/helpers.bend

echo "pristine md5=$(md5 -q "$PRISTINE")  lines=$(wc -l < "$PRISTINE" | tr -d ' ')"
echo "live     md5=$(md5 -q "$LIVE")  lines=$(wc -l < "$LIVE" | tr -d ' ')"
echo

rm -rf "$WORK"; mkdir -p "$WORK"
cp -R "$REPO/tinybendygrad" "$WORK/tinybendygrad"
for f in Base.bend; do
  [ -e "$REPO/$f" ] && cp "$REPO/$f" "$WORK/" 2>/dev/null
done

# the closure: every .bend whose transitive imports reach tinybendygrad/helpers.bend
python3 - "$WORK" > closure.txt <<'PY'
import os, re, sys
root = sys.argv[1]
def imports(path):
    out = []
    try:
        for ln in open(path, encoding="utf-8", errors="replace"):
            m = re.match(r'\s*import\s+\.{0,2}([\w./-]+)\.bend', ln)
            if m:
                out.append(os.path.normpath(os.path.join(os.path.dirname(path), m.group(1) + ".bend")))
    except OSError:
        pass
    return out
TARGET = os.path.join(root, "tinybendygrad", "helpers.bend")
seen, stack, reach = set(), [TARGET], set()
while stack:
    p = stack.pop()
    if p in seen or not os.path.exists(p):
        continue
    seen.add(p)
    for q in imports(p):
        if q not in seen:
            stack.append(q)
    if p != TARGET:
        reach.add(p)
allb = set()
for d, _, fs in os.walk(os.path.join(root, "tinybendygrad")):
    for f in fs:
        if f.endswith(".bend"):
            allb.add(os.path.join(d, f))
for p in sorted(allb - reach):
    reach.add(p)  # control group: files that do NOT reach helpers.bend
for p in sorted(reach):
    print(p)
PY
n=$(grep -c 'tinybendygrad/helpers.bend' closure.txt)
echo "closure: $(wc -l < closure.txt | tr -d ' ') files examined, $n reference helpers.bend directly"
echo

run_all () {
  : > "$2"
  while read -r f; do
    out=$(perl -e 'alarm 240; exec @ARGV' "$BEND" "$f" --check-only 2>&1 | grep -v 'bend 2.0.35 is available' | tr '\n' '~')
    echo "$f|$out" >> "$2"
  done < closure.txt
}

cp "$PRISTINE" "$WORK/tinybendygrad/helpers.bend"
run_all x before.txt
cp "$LIVE" "$WORK/tinybendygrad/helpers.bend"
run_all x after.txt

echo "=== verdict changes (whole stderr text per file) ==="
n=0
while IFS='|' read -r f rest; do
  a=$(grep -F "$f|" before.txt | cut -d'|' -f2-)
  b=$(grep -F "$f|" after.txt  | cut -d'|' -f2-)
  if [ "$a" != "$b" ]; then
    n=$((n+1))
    echo "CHANGED $f"
    echo "   before: $a"
    echo "   after : $b"
  fi
done < closure.txt
echo "files whose verdict changed = $n"
echo
echo "=== how many are COLD in the after state, and do they name a def I touched? ==="
grep -c 'ALL PROOFS CHECK' after.txt | sed 's/^/  ALL PROOFS CHECK rows: /'
echo "  non-green files:"
grep -v 'ALL PROOFS CHECK' after.txt | cut -d'|' -f1 | sed 's/^/    /'
echo "  ...and do any of them name u64_divmod / cdiv_i64 / gcd / i64_dec / i64_divmod?"
grep -v 'ALL PROOFS CHECK' after.txt | grep -c -E 'u64_divmod|cdiv_i64|i64_dec|divmod' | sed 's/^/    matches: /'
