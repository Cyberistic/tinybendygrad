#!/bin/zsh
# SUBSTRATE CHECK. TWO HALVES, AND A FILE CAN PASS EITHER ONE ALONE.
#
# HALF 1 -- SIZE FIRST, VERDICT SECOND, AND THEN **ROUTE BY WHAT THE FILE IS**.
# EXISTS BECAUSE `bend --check-only` REPORTS **ALL PROOFS CHECK** FOR AN EMPTY
# FILE, MEASURED:
#     : > empty.bend ; bend empty.bend --check-only   ->  ALL PROOFS CHECK
#     printf '# nothing\n' > c.bend ; bend c.bend ...  ->  ALL PROOFS CHECK
#     printf 'def f(:\n'  > d.bend ; bend d.bend ...   ->  SOME PROOFS FAIL
# SO `ALL PROOFS CHECK` DOES NOT MEAN THE FILE HAS CONTENT. Every "the substrate is
# warm" statement this project has made was therefore compatible with a truncated
# file -- and `helpers.bend` WAS truncated to 0 bytes three times, each time by a unit
# that then ran --check-only, saw ALL PROOFS CHECK, and reported it fine.
#
# THE ROUTER, AND WHY IT IS FOUR VERDICTS AND NOT THREE. HALF 1 USED TO RUN
# `bend --check-only` ON EVERY FILE, WHICH SENT `runtime/dtype.c` (297 lines) AND
# `runtime/dtype.js` (193 lines) DOWN THE BEND INSTRUMENT. **THAT IS A CATEGORY
# ERROR**, the same one agent-core.md warns about when it says `-o` success does
# not contradict `--check-only` failure: neither instrument is the other. MEASURED
# OVER EVERY NON-`.bend` FILE IN tinybendygrad/ (6 OF THEM), ALL SIX READ `SOME
# PROOFS FAIL` UNDER `--check-only`, AND NOT ONE OF THEM IS A BEND FILE. A GUARD
# THAT IS ALWAYS RED ON A CLASS OF FILES IS A GUARD WHOSE GREEN IS WORTH LESS.
#
#   .bend          bend --check-only                 -> WARM / COLD      [bend]
#   .c             cc -fsyntax-only, in bend's own C  -> WARM / COLD      [cc]
#                  generated context (see C_CONTEXT)
#   .js  .mjs      node --check                      -> WARM / COLD      [node]
#   anything else  --                               -> NO INSTRUMENT    [none]
#                  INCLUDING a .c whose context could not be built, and a file
#                  whose instrument is not installed. **NEVER `COLD`.** A file
#                  with no instrument has NOT BEEN JUDGED, and printing COLD for
#                  it is a lie about a verdict nobody took. Counted apart.
#
# `NO INSTRUMENT` IS A FOURTH VERDICT BECAUSE THREE ARE NOT ENOUGH. EMPTY/MISSING
# PRE-GATE, WARM, COLD AND NO INSTRUMENT ARE FOUR DIFFERENT CLAIMS ABOUT A FILE
# AND COLLAPSING ANY PAIR OF THEM LOSES THE ONE THAT MATTERS.
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
# USAGE:  substrate-check.sh [-n] <file>...      -n = HALF 2 ONLY (skip verdicts)
cd "$(dirname "$0")/../.." || exit 2
BEND=""
if   [ -x ./bin/bend ];       then BEND=./bin/bend
elif command -v bend >/dev/null 2>&1; then BEND=$(command -v bend)
fi
CC=""
if   command -v cc >/dev/null 2>&1;   then CC=$(command -v cc)
elif command -v clang >/dev/null 2>&1; then CC=$(command -v clang)
fi
NODE=$(command -v node 2>/dev/null)
HERE=.agents/slop/guardfix
# THE ONE BEND PROGRAM THAT MAKES THE C INSTRUMENT POSSIBLE. It reaches a
# dtype.bend seam so `bend -o` emits bend's whole generated C runtime. See
# C_CONTEXT below for why that runtime is the only way a `.c` fragment can be read.
C_PROBE=$HERE/probe-c.bend
# AND THE `.c` THAT PROBE PULLS IN, whose FIRST LINE MARKS WHERE THE FOREIGN BLOCK
# BEGINS IN THE EMIT (`probe-c.bend` imports `tinybendygrad/dtype.bend`, whose seams
# import `tinybendygrad/runtime/dtype.c`). NAMED, NOT GUESSED -- and C_CONTEXT FAILS
# LOUD if that exact line is not in the emit, so if bend ever stops pasting the file
# the instrument reports NO INSTRUMENT rather than a silent pass.
C_PROBE_FOREIGN=tinybendygrad/runtime/dtype.c
names_only=0
if [ "$1" = "-n" ]; then names_only=1; shift; fi

fail=0
n_bend=0 n_cc=0 n_node=0 n_none=0

# ------------------------------------------------------------------ C CONTEXT
# C_CONTEXT -- bend's generated C runtime, ONCE, so `cc` can read a `.c` fragment
# AT ALL. MEASURED 2026-10-04, EVERY NUMBER IN IT:
#
#   1. `cc -fsyntax-only tinybendygrad/runtime/dtype.c` ON ITS OWN -> **190 errors**,
#      and every distinct one is "bend's runtime is not here": `Term` 22, `u32` 50,
#      `Env` 12, `IoWork` 10, `intptr_t`, `int64_t`, `ctr_take`, `io_tup`,
#      `f32_rewrap`, and 60 undeclared *locals* that are merely downstream of the
#      first unknown type. **SO THE BARE INVOCATION IS A CATEGORY ERROR** -- the same
#      one `bend --check-only` on a `.c` file was, asked of a different tool. It
#      reports a file RED that bend's own backend builds and RUNS.
#
#   2. A `.c` FILE HERE IS NOT A TRANSLATION UNIT. bend pastes it, verbatim, into the
#      C it generates (comp.ts `effect_srcs` -> `c_ids` -> `runtime_c`), so `Term`,
#      `IoWork` and `u32` are DECLARED BY THE GENERATOR, not by the fragment.
#
#   3. THE GENERATED UNIT CANNOT BE HALVED. Lines 1..2839 of the emit carry **44
#      `#if` opens against 43 `#endif` closes**: `#if !DEVICE` at line 1556 is closed
#      by the generated `main`, past the foreign block. So there is NO self-contained
#      preamble to `-include` -- `cc -fsyntax-only` on the extracted prefix alone says
#      `unterminated conditional directive` at 1556:2.
#
# So the deficit is COUNTED here, not assumed, and the closure is appended. That can
# only ADD declarations to the check, so it can make this instrument MORE PERMISSIVE;
# it can never turn a real syntax error green. And the finished context is compiled
# ONCE ON ITS OWN before any fragment is judged: if the context itself does not
# compile, the instrument produced nothing, and NO INSTRUMENT is printed -- never a
# pass, never a cold.
#
#   4. ONE MORE THING THE CONTEXT MUST SUPPLY, AND IT COST A FALSE RED FIRST.
#      `sz.c:51,53` evaluate `term_pak(CID(Nil), 0)`. `CID` IS **NOT C**: bend
#      substitutes `CID(<name>)` for an effect id at EMIT time (comp.ts `c_ids`),
#      and no generated C defines a `CID` function -- so a first cut of this context
#      reported `runtime/sz.c` COLD with 7 "call to undeclared function 'CID'".
#      **THAT RED WAS MY INSTRUMENT'S INCOMPLETENESS, NOT A DEFECT IN `sz.c`.** A
#      result that contradicts the tool is a suspect result, and this one contradicted
#      the fact that bend's own backend builds and runs the file. The context now
#      declares `#define CID(x) 0`: a NEUTRAL STUB, correct here because the id's
#      VALUE is irrelevant to whether a fragment parses, and a wrong id would only
#      ever hide a duplicate-registration error, which is not this instrument's job.
#      With it: `dtype.c` 0 errors, `sz.c` 0 errors, and a fragment with a syntax
#      error still stops the compile (measured in guardfix/RESULTS.md).
c_context() {
  [ -n "$CTX" ] && return 0
  [ -n "$BEND" ] || return 1
  [ -f "$C_PROBE" ] || return 1
  [ -f "$C_PROBE_FOREIGN" ] || return 1
  local gen="$SCR/gen.c"
  perl -e 'alarm 300; exec @ARGV' "$BEND" "$C_PROBE" -o "$gen" >/dev/null 2>&1
  [ -s "$gen" ] || return 1
  local at; at=$(grep -n -F -x -- "$(head -n 1 "$C_PROBE_FOREIGN")" "$gen" \
                 | head -n 1 | cut -d: -f1)
  case $at in ''|*[!0-9]*) return 1 ;; esac
  [ "$at" -gt 1 ] || return 1
  head -n $((at - 1)) "$gen" > "$SCR/pre.c"
  local o c i; o=$(grep -cE '^[[:space:]]*#[[:space:]]*(if|ifdef|ifndef)' "$SCR/pre.c")
  c=$(grep -cE '^[[:space:]]*#[[:space:]]*endif' "$SCR/pre.c")
  [ "$o" -ge "$c" ] || return 1
  i=1; while [ "$i" -le $((o - c)) ]; do print -r -- '#endif' >> "$SCR/pre.c"; i=$((i+1)); done
  print -r -- '#define CID(x) 0' >> "$SCR/pre.c"
  # TODO(GXR-11): CID IS THE ONE THING THIS INSTRUMENT CANNOT JUDGE. A fragment can
  # register an effect under an id bend will never define and this check stays green --
  # `runtime/sz.c:71` may already do. Only a `bend -o` build can see that, and it is a
  # DIFFERENT QUESTION (agent-core.md: `-o` success does not contradict `--check-only`
  # failure, and neither is the other). Do not widen this stub's remit; open a C-lane gate.
  $CC -fsyntax-only "$SCR/pre.c" >/dev/null 2>&1 || return 1
  CTX="$SCR/pre.c"; CTX_LINES=$(grep -c '' "$SCR/pre.c")
  return 0
}

SCR=$(mktemp -d "${TMPDIR:-/tmp}/substrate.XXXXXX") || exit 2
trap 'rm -rf "$SCR"' EXIT INT TERM
CTX=; CTX_LINES=0

# ------------------------------------------------------------------ HALF 1
for f in "$@"; do
  [ -f "$f" ] || { print -r -- "MISSING     $f"; fail=$((fail+1)); continue }
  lines=$(wc -l < "$f" | tr -d ' ')
  bytes=$(wc -c < "$f" | tr -d ' ')
  if [ "$lines" -eq 0 ] || [ "$bytes" -eq 0 ]; then
    print -r -- "EMPTY       $f  ($lines lines, $bytes bytes)  <-- THE VERDICT IS MEANINGLESS"
    fail=$((fail+1)); continue
  fi
  # ------------------------------------------------------------------ ROUTE
  # AN EXTENSION PICKS THE INSTRUMENT; A MISSING INSTRUMENT DOWNGRADES IT TO
  # `none`, WHICH IS THE SAME VERDICT AS AN UNROUTABLE CLASS. BOTH MEAN THE FILE WAS
  # NOT JUDGED. NEITHER IS A PASS.
  case $f in
  *.bend)     inst=bend; tag='bend --check-only'; why="" ;;
  *.c)        inst=cc;   tag="cc -fsyntax-only + bend's C context"
               why="cc and a compiling bend C context are both required, and one is absent" ;;
  *.js|*.mjs) inst=node; tag='node --check'
               why="node is not installed" ;;
  *)          inst=none; tag='no instrument exists for this file class'
               why="no instrument exists for this file class" ;;
  esac
  [ "$inst" = cc ]   && [ -z "$CC" ]   && { inst=none; why="cc is not installed"; }
  [ "$inst" = node ] && [ -z "$NODE" ] && { inst=none; why="node is not installed"; }
  [ "$inst" = bend ] && [ -z "$BEND" ] && { inst=none; why="bend is not installed"; }
  if [ "$names_only" -eq 1 ] && [ "$inst" != none ]; then
    print -r -- "SKIP-VERDICT $f  ($lines lines, verdict suppressed by -n)"
    continue
  fi
  case $inst in
  none) n_none=$((n_none+1))
    print -r -- "NO INSTRUMENT  $f  ($lines lines)  :: $why -- **NOT JUDGED, AND NOT COLD**"
    continue ;;
  bend) n_bend=$((n_bend+1))
    v=$(perl -e 'alarm 300; exec @ARGV' "$BEND" "$f" --check-only 2>&1 | head -1)
    if [ "$v" = "ALL PROOFS CHECK" ]; then
      print -r -- "WARM        $f  ($lines lines)  [$tag]"
    else
      print -r -- "COLD        $f  ($lines lines)  [$tag]  :: $v"
      fail=$((fail+1))
    fi ;;
  node) n_node=$((n_node+1))
    err=$(perl -e 'alarm 300; exec @ARGV' "$NODE" --check "$f" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then
      print -r -- "WARM        $f  ($lines lines)  [$tag]"
    else
      # node's FIRST line is only the path and the line number; the sentence that says
      # what is wrong is the `SyntaxError:` line. A verdict that prints a path is not a
      # verdict. Prefer the error line, and fall back to line 1 when node has none.
      nv=$(print -r -- "$err" | grep -m1 -E '^[A-Za-z]*Error')
      print -r -- "COLD        $f  ($lines lines)  [$tag]  :: ${nv:-$(print -r -- "$err" | head -1)}  :: $f:$(print -r -- "$err" | head -1 | sed -E 's#^.*:([0-9]+)$#\1#')"
      fail=$((fail+1))
    fi ;;
  cc)   if ! c_context; then n_none=$((n_none+1))
      print -r -- "NO INSTRUMENT  $f  ($lines lines)  :: $why"
      continue
    fi
    n_cc=$((n_cc+1))
    # THE FRAGMENT GOES IN *AFTER* THE CONTEXT, so a diagnostic at context line L is
    # the fragment's line L-CTX_LINES. REWRITTEN, because "gen.c:2891" names a file
    # THAT DOES NOT EXIST in the repo and a reader would go looking for it.
    cat "$CTX" "$f" > "$SCR/frag.c"
    err=$($CC -fsyntax-only "$SCR/frag.c" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then
      print -r -- "WARM        $f  ($lines lines)  [$tag]"
    else
      # A DIAGNOSTIC AT CONTEXT LINE L IS THE FRAGMENT'S LINE L-CTX_LINES. REWRITTEN,
      # BECAUSE `frag.c:2891` NAMES A FILE THAT DOES NOT EXIST IN THE REPO AND A
      # READER WOULD GO LOOKING FOR IT. THE FIRST `error:` ONLY: cc cascades, and a
      # list of 7 lines that all say the same thing is not 7 findings.
      msg=$(print -r -- "$err" | grep -m1 'error:')
      gln=$(print -r -- "$msg" | perl -ne 'print "$1\n" if /frag\.c:(\d+):/')
      gtxt=$(print -r -- "$msg" | perl -pe 's/^.*frag\.c:\d+:\d+:\s*//')
      case $gln in ''|*[!0-9]*) print -r -- "COLD        $f  ($lines lines)  [$tag]  :: $msg" ;;
      *) print -r -- "COLD        $f  ($lines lines)  [$tag]  :: $f:$((gln - CTX_LINES)): $gtxt" ;;
      esac
      fail=$((fail+1))
    fi ;;
  esac
done

# ------------------------------------------------------------------ THE ROUTE
# AN INSTRUMENT THAT HIDES ITS OWN ROUTING IS THE DEFECT THIS PROJECT HAS
# CATALOGUED TWENTY TIMES -- AND ITS OWN SECOND HALF ALREADY PRINTS AN `unseen=`
# COUNT FOR EXACTLY THIS REASON. SO EVERY VERDICT ABOVE CARRIES ITS INSTRUMENT AND
# THE TALLY IS PRINTED BESIDE THE TOTALS, NOT BURIED IN A COMMENT.
print -r -- "ROUTE   bend=$n_bend  cc=$n_cc  node=$n_node  no-instrument=$n_none  (of $# file(s))"

# ------------------------------------------------------------------ PROVENANCE
# `bend=` ABOVE COUNTS WHATEVER IT WAS HANDED, AND THAT IS THE DEFECT THIS BLOCK
# EXISTS FOR. MEASURED 2026-10-05: `find tinybendygrad -name '*.bend'` = 138, the port
# is 137, and the whole discrepancy is `probe_f32lit.bend` -- ONE PROBE, STILL ON DISK,
# OWNED BY A LIVE UNIT. Two earlier units did the same with `*.staged-*` names and were
# deleted before anyone read the number, so the count came back to 137 and NOBODY
# NOTICED IT HAD MOVED. **A DENOMINATOR THAT MOVES BY ONE STILL LOOKS LIKE A
# DENOMINATOR**, and `bend=137` printed the same in both worlds.
#
# SO THE ROUTE LINE NOW PRINTS ITS OWN SPLIT, `port=` AGAINST `non-port=`, AND THE
# CRITERION IS DERIVED RATHER THAN DECLARED. A registry -- a `PROBES.md` the router
# reads, or a list of known-scratch names -- REPRODUCES THE DEFECT ONE LEVEL DOWN: the
# probe that moves the count is the probe nobody remembered to register. Instead:
#
#   PORT     iff `git ls-files` knows the path. No registration, no naming convention,
#            no memory. A port file is in the index and a probe is not, because nothing
#            has ever committed one. `bend_mutate.py:46` is the producer that keeps
#            producing one, and `.gitignore:34-36` already names `*.mut.bend`.
#   no-upstream is the SECOND, WEAKER criterion and is REPORTED, NOT FAILED: 16 files
#            are legitimately not 1:1 with an upstream `.py` (`LAWS/**`, `PROOF*.bend`,
#            `base.bend`, `sz.bend`, `codegen/kernel.bend`, `uop/fold.bend`, ...), so
#            failing on it would report 16 findings forever. Measured: it agrees with
#            the index criterion on exactly the 2 files that are both.
#
# FAIL-SAFE DIRECTION, AND IT IS THE PART THAT MATTERS: THE ALARM FAILS, BUT THE ONLY
# WAY TO SILENCE IT IS `git add` THE FILE -- i.e. to take ownership of it IN THE INDEX.
# SILENCE REQUIRES AN EXPLICIT, RECORDED ACT. A probe that gets swept into a `jj split`
# does not disappear from the count; it flips `not-in-index` to 0 and the port count a
# reader compares against is one too high, which the same line now says.
#
# SCOPE: THE ALARM FIRES ONLY FOR A PATH INSIDE `tinybendygrad/`. A `$TMPDIR` SCRATCH
# COPY IS NOT IN THE INDEX EITHER -- `agent-core.md:217` records that a scratch copy
# also cannot resolve a relative import, so it is a documented way to work -- and
# failing it would be a false positive on the sanctioned workflow. Same split, softer
# verdict, stated rather than tuned.
PROVENANCE=$(print -l -- "$@" | python3 -c '
import os, subprocess, sys
P=N=I=U=A=NB=BENDPOP=0; rows=[]; alarm=[]
for p in [l for l in sys.stdin.read().split("\n") if l]:
    # AN EXACT PATHSPEC. `git ls-files <path>` IS THE QUESTION; A `grep -r tinybendygrad`
    # IS NOT -- a path SUBSTRING is not a path, and that mistake produced 315 phantom
    # "files swept", every one a `.agents/slop/.../tinybendygrad/...` copy.
    idx = subprocess.run(["git", "ls-files", "--error-unmatch", "--", p],
                         capture_output=True).returncode == 0
    live = p.startswith("tinybendygrad/")
    up = os.path.isfile("tinygrad/" + p[len("tinybendygrad/"):-5] + ".py") if live and p.endswith(".bend") else None
    if p.endswith(".bend"): BENDPOP += 1
    if idx and up is not False:
        P += 1; continue
    N += 1
    if p.endswith(".bend"): NB += 1
    if not idx: I += 1
    if up is False: U += 1; rows.append("  no-upstream   %s" % p)
    if live and not idx:
        A += 1
        alarm.append("  NOT-PORT      %s\n"
                     "                :: NOT IN THE INDEX. NO PORT FILE IS UNTRACKED, so this is a probe, a\n"
                     "                :: mutant, or scratch copy -- whatever it is, it is not in the tree.\n"
                     "                :: IT IS STILL COUNTED IN `bend=` ABOVE. Silence requires ownership:\n"
                     "                :: `git add` it, or delete it." % p)
print("PROVENANCE  port=%d  non-port=%d   of which not-in-index=%d no-upstream=%d   (of %d)"
      % (P, N, I, U, P + N))
for r in rows: print(r)
for r in alarm: print(r)
print("PORT ALARM  %d file(s) inside tinybendygrad/ are not in the index." % A)
# THE RESIDUAL, STATED AS A SUBTRACTION AND NOT AS A CLAIM. A first cut printed
# `none, so `port=` is the whole of `bend=`` -- and it was FALSE in the same breath it
# printed `port=0 bend=2`, because a `$TMPDIR` scratch copy is legitimately not in the
# index and legitimately not a port. A conditional sentence about agreement is a claim
# that can be wrong; a subtraction cannot.
#
# COUNTED FROM THE `.bend` POPULATION HANDED, NOT FROM `bend=` ABOVE, AND THE REASON IS
# MEASURED COST: the verdicts are ~0.1 s for a small file and tens of seconds for a
# 6,000-line one, so a full 138-file pass is minutes while this line is 2.4 s. Deriving
# the number from `$n_bend` would have made the honest answer unmeasurable in practice,
# which is the same failure as the defect: a number too expensive to check is a number
# nobody checks. `-n` suppresses verdicts and does not touch this line, so the split is
# available with and without a verdict -- which is what makes it usable as a pre-gate.
print("DENOMINATOR .bend handed=%d, of which non-port=%d  =>  the port count to compare against is %d"
      % (BENDPOP, NB, BENDPOP - NB))
sys.exit(1 if A else 0)
')
prov_rc=$?                      # CAPTURED IMMEDIATELY: `$?` AFTER ANY `[` IS THAT `[`'s rc,
print -r -- "$PROVENANCE"        # NOT python's -- AND A VACUOUS VERDICT LOOKS IDENTICAL TO A PASS.
[ "$prov_rc" -ne 0 ] && fail=$((fail+1))

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
if [ "$n_none" -gt 0 ]; then
  print -r -- "NO INSTRUMENT: $n_none of $# file(s) were **NOT JUDGED** (no instrument exists, or it produced nothing)."
  print -r -- "A FILE WITH NO INSTRUMENT IS NOT A PASS AND NOT A FAILURE. It is an unmeasured surface."
fi
if [ "$names_only" -eq 1 ]; then
  print -r -- "NAMES CLEAN: $# file(s), all non-empty, all cross-file names resolved. **VERDICT NOT TAKEN** (-n)."
else
  print -r -- "SUBSTRATE CLEAN: $# file(s), all non-empty, each judged by its OWN instrument, all cross-file names resolved."
fi
print -r -- "(name check is scoped to the IMPORT graph. It cannot see the unaliased \`import Base\`"
print -r -- " surface -- List. String. U32. -- which is most qualified refs in the tree. Read the"
print -r -- " \`unseen=\` number, not just the verdict: an instrument that hides its own blind spot"
print -r -- " is the defect this project has catalogued twenty times.)"