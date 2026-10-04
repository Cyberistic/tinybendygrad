#!/bin/zsh
# SUBSTRATE CHECK. TWO HALVES, AND A FILE CAN PASS EITHER ONE ALONE.
#
# HALF 1 -- SIZE FIRST, VERDICT SECOND. EXISTS BECAUSE `bend --check-only` REPORTS
# **ALL PROOFS CHECK** FOR AN EMPTY FILE, MEASURED:
#     : > empty.bend ; bend empty.bend --check-only   ->  ALL PROOFS CHECK
#     printf '# nothing\n' > c.bend ; bend c.bend ...  ->  ALL PROOFS CHECK
#     printf 'def f(:\n'  > d.bend ; bend d.bend ...   ->  SOME PROOFS FAIL
# SO `ALL PROOFS CHECK` DOES NOT MEAN THE FILE HAS CONTENT. Every "the substrate is
# warm" statement this project has made was therefore compatible with a truncated
# file -- and `helpers.bend` WAS truncated to 0 bytes three times, each time by a unit
# that then ran --check-only, saw ALL PROOFS CHECK, and reported it fine.
#
# HALF 2 -- COLLECTIVE COMPLETENESS. HALF 1 ANSWERS "does this file parse?", WHICH
# IS A QUESTION ABOUT ONE FILE. THE REAL FAILURE TODAY WAS THE OTHER QUESTION:
#     tinybendygrad/uop/ops.bend --check-only  ->  ALL PROOFS CHECK   (6,305 lines)
#     tinybendygrad/runtime/ops_python.bend    ->  expected : a defined name
#                                                 observed : O.ParamArg.no_slot
# A FILE THAT COMPILES CAN STILL BE MISSING A NAME SOMETHING ELSE NEEDS. SO FOR EVERY
# FILE UNDER TEST, HALF 2 TAKES THE MODULES IT IMPORTS AND RESOLVES EVERY `<Mod>.<name>`
# IT REFERENCES AGAINST THE NAMES THOSE MODULES DECLARE.
#
# HALF 2 REPORTS ITS OWN COVERAGE, BECAUSE AN INSTRUMENT THAT SILENTLY SKIPS 90% OF ITS
# INPUT IS THE DEFECT THIS PROJECT HAS CATALOGUED TWENTY TIMES. MEASURED OVER ALL 136
# FILES OF tinybendygrad/ AT 2026-10-04 20:03:47 (THE TREE IS BEING EDITED CONCURRENTLY,
# SO RE-RUN TO GET YOUR OWN NUMBERS RATHER THAN TRUSTING THESE):
#     36,084 cross-file references   36,071 exact   0 suffix-only   13 UNRESOLVED
#     49,134 references UNSEEN -- an uppercase `Foo.bar` whose `Foo` is NOT an import
#             alias, i.e. the unaliased `import Base` stdlib surface (List., String.,
#             U32., ...). THIS CHECK IS **BLIND** TO ALL OF THEM, and they are 58% of
#             every qualified reference in the tree. It is a completeness check on the
#             IMPORT graph, not on the language.
#     37 unused imports -- an alias nothing references. REPORTED, NOT A FAILURE: a
#             half-written file imports its module before it calls into it.
#
# HALF 2 ALSO CATCHES THE `helpers.bend` TRUNCATION THAT HALF 1 WAS BUILT FOR. An EMPTY
# PROVIDER DECLARES NOTHING, SO EVERY CALL INTO IT GOES UNRESOLVED:
#     : > helpers.bend   ->   UNRESOLVED codegen/kernel.bend:1003: H.i64_of_i32
#
# USAGE:  substrate-check.sh [-n] <file>...      -n = HALF 2 ONLY (skip bend)
cd "$(dirname "$0")/../.." || exit 2
BEND=./bin/bend
[ -x "$BEND" ] || BEND=bend
names_only=0
if [ "$1" = "-n" ]; then names_only=1; shift; fi

fail=0

# ------------------------------------------------------------------ HALF 1
for f in "$@"; do
  [ -f "$f" ] || { print -r -- "MISSING   $f"; fail=$((fail+1)); continue }
  lines=$(wc -l < "$f" | tr -d ' ')
  bytes=$(wc -c < "$f" | tr -d ' ')
  if [ "$lines" -eq 0 ] || [ "$bytes" -eq 0 ]; then
    print -r -- "EMPTY     $f  ($lines lines, $bytes bytes)  <-- THE VERDICT IS MEANINGLESS"
    fail=$((fail+1)); continue
  fi
  if [ "$names_only" -eq 1 ]; then
    print -r -- "SKIP-VERDICT $f  ($lines lines, --check-only suppressed by -n)"
    continue
  fi
  v=$(perl -e 'alarm 300; exec @ARGV' "$BEND" "$f" --check-only 2>&1 | head -1)
  if [ "$v" = "ALL PROOFS CHECK" ]; then
    print -r -- "WARM      $f  ($lines lines)"
  else
    print -r -- "COLD      $f  ($lines lines)  :: $v"
    fail=$((fail+1))
  fi
done

# ------------------------------------------------------------------ HALF 2
# DECLARATIONS A MODULE EXPORTS. `def`/`type`/`law` ARE ALWAYS AT COLUMN 0 IN THIS
# TREE (MEASURED: 27,661/804/44 top-level `def`/`type`/`law`, 0 indented). A `type X is
# Data:` BLOCK'S VARIANTS ARE AT ARBITRARY INDENT (913 at 2, 101 at 5..14) AND ARE
# ADDRESSABLE BARE -- `def ParamArg.no_slot` SITS ALONGSIDE `ParamArg.of`, AND A
# CROSS-FILE `O.ParamArg.no_slot` RESOLVES TO THE DEF PATH, NOT TO `O.` + A PREFIX.
NAME_STATS=$(print -l -- "$@" | python3 -c '
import os, re, sys, collections

IMPORT = re.compile(r"^import\s+(?:\./)?([A-Za-z0-9_./-]*\.bend)\s+as\s+([A-Za-z_]\w*)\s*$")
DEF    = re.compile(r"^def\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)")
TYPE   = re.compile(r"^type\s+([A-Za-z_]\w*)")
LAW    = re.compile(r"^law\s+([A-Za-z_]\w*)")
VARIANT= re.compile(r"^[ \t]+([A-Za-z_]\w*)\s*[{(:=]")
REF    = re.compile(r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)")

_cache = {}
def decls(path):
    if path in _cache: return _cache[path]
    out = set()
    if os.path.isfile(path):
        inb = False
        for ln in open(path, errors="replace"):
            if inb:
                s = ln.strip()
                if not s or s.startswith("#"): continue
                if ln[:1] in (" ", "\t"):
                    m = VARIANT.match(ln)
                    if m: out.add(m.group(1))
                    continue
                inb = False
            m = DEF.match(ln) or TYPE.match(ln) or LAW.match(ln)
            if m:
                out.add(m.group(1))
                inb = bool(TYPE.match(ln))
    _cache[path] = out
    return out

def code_only(line):
    line = re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"", "\"\"", line)   # string literals
    i = line.find("#")                                        # then the comment
    return line[:i] if i >= 0 else line

T = collections.Counter()
problems = collections.Counter()   # (file, line, ref) -> note, deduped by SITE
def note(key, why):
    if key not in problems: problems[key] = why
for path in [l for l in sys.stdin.read().split("\n") if l]:
    if not os.path.isfile(path):
        note((path, 0, "<the file under test>"), "FILE UNDER TEST IS ABSENT")
        continue
    alias = {}
    for ln in open(path, errors="replace"):
        m = IMPORT.match(ln)
        if m: alias[m.group(2)] = os.path.normpath(os.path.join(os.path.dirname(path), m.group(1)))
    pool = collections.defaultdict(set)
    for a, t in alias.items():
        pool[a] |= decls(t)
        T["nomod"] += 0 if os.path.isfile(t) else 1
        if not os.path.isfile(t): note((path, 0, a + " -> " + t), "MODULE FILE IS ABSENT")
    used = collections.Counter(); unseen0 = T["unseen"]; k = 0; u = 0; refs = 0
    for n, raw in enumerate(open(path, errors="replace"), 1):
        for m in REF.finditer(code_only(raw)):
            al, dotted = m.group(1), m.group(2)
            if al not in alias:
                if al[:1].isupper(): T["unseen"] += 1   # UNALIASED: Base / stdlib
                continue
            used[al] += 1
            T["total"] += 1; refs += 1
            parts = dotted.split(".")
            d = pool[al]
            if ".".join(parts) in d: T["exact"] += 1
            elif any(".".join(parts[i:]) in d for i in range(1, len(parts))):
                k += 1; T["suffix"] += 1
                note((path, n, al + "." + dotted), "ONLY A SUFFIX MATCHES")
            else:
                u += 1; T["unres"] += 1
                note((path, n, al + "." + dotted), "NOT DECLARED IN " + alias[al])
    dead = sum(1 for a in alias if not used[a])
    T["deadimport"] += dead
    print("NAMES     %s  (%d modules, %d refs, %d exact, %d suffix-only, %d unresolved, %d unseen, %d unused-import)" %
          (path, len(alias), refs, refs - k - u, k, u, T["unseen"] - unseen0, dead))
print("---")
for (p, ln, ref), why in problems.items():
    print("UNRESOLVED  %s:%d: %s  :: %s" % (p, ln, ref, why))
print("TOTALS refs=%d exact=%d suffix=%d unresolved=%d unseen=%d missing_module=%d dead_import=%d" %
      (T["total"], T["exact"], T["suffix"], T["unres"], T["unseen"], T["nomod"], T["deadimport"]))
print("BAD %d" % len(problems))
')
print -r -- "$NAME_STATS"
nf=$(print -r -- "$NAME_STATS" | sed -n 's/^BAD //p')
nf=${nf:-1}
[ "$nf" -gt 0 ] && fail=$((fail+nf))

if [ "$fail" -gt 0 ]; then
  print -r -- ""
  print -r -- "SUBSTRATE NOT CLEAN: $fail finding(s) across $# file(s) -- empty, missing, cold, or collectively incomplete."
  print -r -- "ANY VERDICT TAKEN AGAINST THESE FILES IS **INCONCLUSIVE**, NOT A RESULT."
  exit 1
fi
print -r -- ""
if [ "$names_only" -eq 1 ]; then
  print -r -- "NAMES CLEAN: $# file(s), all non-empty, all cross-file names resolved. **VERDICT NOT TAKEN** (-n)."
else
  print -r -- "SUBSTRATE CLEAN: $# file(s), all non-empty, ALL PROOFS CHECK, all cross-file names resolved."
fi
print -r -- "(name check is scoped to the IMPORT graph. It cannot see the unaliased \`import Base\`"
print -r -- " surface -- List. String. U32. -- which is most qualified refs in the tree. Read the"
print -r -- " \`unseen=\` number, not just the verdict: an instrument that hides its own blind spot"
print -r -- " is the defect this project has catalogued twenty times.)"