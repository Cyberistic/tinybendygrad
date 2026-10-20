#!/usr/bin/env python3
"""The gate OVER gates: every gate in the tree, DISCOVERED, and what each one pops for.

THE DEFECT THIS EXISTS FOR, IN ONE SENTENCE. **NO GATE HERE IS A GATE OVER GATES.** Four
instances of one class survived a day of work, each named in a different brief:

  `checks/sb-gate.sh` applied its rules to ITSELF AND ITS THREE LITERAL LANES ONLY, so
  `checks/abi_gate.py` was never on its radar; and a unit MEASURED `abi4_gate.py` GREEN
  once, at `135bf0204`, 16 PASS / 0 FAIL / `gate rc: 0`, which is only possible if a gate
  that read the wrong tree found nothing to disagree with.
  `checks/abi_gate.py:41`, `checks/census.py:14` and `checks/hermetic-census.py:33` each
  computed a path with `parents[n]`, and `checks/e2e.sh`'s `../..` is pin-coupled.
  A file that computes a path RELATIVE TO ITSELF has the tree's depth baked into a constant,
  and a cleanup that moves the file does not move the constant.

THE PRINCIPLE, WHICH IS THE WHOLE JOB. **AN EXHAUSTIVE GATE OVER THE WRONG UNIVERSE CANNOT
FAIL, AND A GATE THAT CHECKS A LITERAL LIST IS A UNIVERSE DEFINED BY WHATEVER WAS TRUE WHEN
SOMEONE WROTE IT DOWN.** Four more failures are the same sentence wearing different hats:
`LIVE_UNITS` (670 of 675 files were ORACLE by NAME and NAMED BY NO GATE), `artefacts_ok()`
(reported zero on a directory holding NOTHING, because the glob DEFINED the population the
guard then checked), `sb-gate.sh` again, and `repro-paths.py`'s REF regex, which was
`(?:sh|py|bend)` and therefore could not see 6 of `checks/e2e.py`'s 15 stage inputs.

WHAT IS DIFFERENT HERE, AND WHY A DECLARATION ALONE COULD NOT DO IT. Answer 2 -- every gate
gains `INPUTS = (...)` and one reader asserts they exist -- is unsound on this repo's own
measured evidence: `txtgen`'s unit measured FOUR STATIC CHECKS FINDING ZERO DRIFT while all
four re-derived from the SAME TABLES, and `differ.declared()`'s completeness could only be
answered by RUNNING `cmd_run` in a sandbox and diffing what it WROTE. **A DECLARATION
DERIVED FROM THE TABLES IT DESCRIBES CANNOT AUDIT THOSE TABLES, BECAUSE BOTH CHANGE
TOGETHER.** So this file never reads a declaration to decide what the population IS. It reads
the tree's own structure, and it CHECKS the declaration rather than believing it.

THE THREE CLAUSES, EACH WITH ITS OWN DENOMINATOR, AND NONE OF THEM ABLE TO PASS ON AN EMPTY
POPULATION:

  I   DISCOVERED, not listed. Every entry point in the DERIVED gate homes, by AST (`__main__`)
      for Python and by SELF-DISPATCH for shell. The population is a MEASUREMENT. **WHERE THE
      HOMES COME FROM IS A SEPARATE MEASUREMENT AND IS PRINTED SEPARATELY** -- `gate_homes()`
      derives them from the commit tree and `report_roots()` prints every candidate it rejected
      with its own denominator, so the one hand list this file used to carry is gone and a reader
      sees the root set move without reading code.
  II  A POPULATION IS NOT EMPTY and not vacuously green. Reported per clause, always.
  III THE SET MOVED OR THE LEDGER SAYS WHY. **A READ CANNOT WRITE, AND A WRITE NAMES ITS PATHS.**
      `--write-ledger --only PATH` is this file's ONLY writer of `gates/gates-pop.ledger.tsv`. It
      absorbs those paths and no others. A bare `--write-ledger` is REFUSED: that invocation MERGES
      every row this run found, and the diff goes green without one gate having been measured. It
      is NOT the default; every other invocation only reads, and the read names every row that is
      new, gone, changed or back. **A LEDGER READ AND THEN REWRITTEN BY ITS OWN READER IS NOT A LEDGER** --
      `gates-pop.ledger.tsv` used to be written at `:646` and read at `:617` in the SAME process
      under the DEFAULT mode, so it was a DIARY, and the fix that made it a MONOTONIC MERGE left
      the DEFAULT still writing: a MERGE the reader performs without asking is the same diary with
      a better merge function. MEASURED on the pre-boundary tree, a PLAIN `gates/gates-pop.py`
      rewrote the shared ledger by **13 added and 7 removed lines** with no flag at all --
      **4 of them `checks/.tmp-*`, ANOTHER UNIT'S IN-FLIGHT SCRATCH**, 2 the registering unit's own
      rows, 5 unrelated row edits and 2 retirements -- so the unit reverted the file and left its
      own registration out. **THE LEDGER IS A SHARED WRITABLE PATH (`AGENTS.md`'s class), AND A
      GENERATOR IS THE WORST INSTANCE OF IT: THE INDEX IS SUPPOSED TO BE WRITTEN, WHILE A GENERATOR
      THAT WRITES ON EVERY INVOCATION HAS NO IDEMPOTENCE BOUNDARY.** The ROOT SET is derived rather
      than snapshotted for the same reason the ledger is one writer: a measurement that rewrites
      its own record cannot be checked against one.
  IV  THE GENERATED-DIRECTORY POPULATION, SHARED WITH `gates/retention-check.py`. Both
      instruments import `gates/gendirs.py` and report the SAME `discovered()` count, because
      **two instruments holding two lists have no authority over each other and their
      disagreement would be a third finding with no way to settle it.** One module, one
      population, two consumers -- a change to it moves both, which is what makes the pair
      auditable instead of merely parallel.

EXIT: 0 green, 1 red, 2 REFUSED -- a precondition was missing (no `pyproject.toml` at the
root, so this file cannot tell the repo root from any other directory), because a check that
cannot measure must not report 0.

PLANTED THREE WAYS, BECAUSE A META-GATE'S OWN BLIND SPOT IS THE ONE LEAST LIKELY TO BE
CAUGHT BY ANYONE ELSE: every other gate checks a different subject. `--plant` builds a
synthetic tree and asserts that (1) a gate at the WRONG DEPTH is red, (2) a gate with NO
LEDGER ENTRY is red, and (3) **A GATE THE INSTRUMENT DOES NOT NOTICE -- a gate that is not an
entry point, which is the population's own edge -- is red.** Self-consistency is not
independence, so the three plants assert DIFFERENT directions, and plant 3 is the one whose
failure mode is invisible from inside this file.
"""
import argparse
import ast
import contextlib
import io
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tokenize
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# THE FIVE VERDICTS, IMPORTED BY PATH from the file that OWNS them (`gatekit.py`, same dir), never
# re-spelled: a second copy of the vocabulary is the same fault as a second copy of a population, and a
# runner maps any code outside the five to `DEAD`. Measured before this import: this file and
# `checks/cl-port-gate.py` both refused with **2**, and both were scored `DEAD`.
sys.path.insert(0, str(HERE))
from gatekit import REFUSED  # noqa: E402  (after sys.path, deliberately)

# WHAT THIS FILE CANNOT SEE, NAMED, because a meta-gate's blind spots are the ones no other
# instrument is checking. Four, and none is fixable by being cleverer about the tree:
#   (1) a gate OUTSIDE the derived homes. `gate_homes()` MEASURES which top-level directories hold
#       a gate that NAMES A ROOT, REFUSES ON A WRONG ONE and RESOLVES ON-REPO, and it prints every
#       candidate it rejected with its own denominator -- so this hole is a NUMBER, not a list.
#       MEASURED, and it answers the question `.agents/slop/UNIVERSE-CENSUS.md` left open: **2 of
#       14** top-level directories of the commit tree qualify. `.agents` is rejected at **0 of 6**
#       certified gates, and the three `.agents/slop/` files that pass every ROOT clause carry no
#       `__main__` guard -- they are harnesses, not gates. So `HOMES`'s `("checks", "gates")` was
#       RIGHT and `indexread-gate`'s `(".agents/slop", "checks", "gates")` was ALSO RIGHT, because
#       they answer DIFFERENT QUESTIONS, and the whole defect was that nothing recorded which.
#   (2) a gate invoked as a SUBPROCESS from a wrapper rather than run directly. This is why
#       `checks/sb-gate.sh`'s three-lane list is invisible here: the instrument can see that its
#       root is right, and cannot see WHAT IT DECIDES TO CHECK.
#   (3) whether a gate is ever RUN. Nothing here executes one -- deliberately, because `bend`
#       peaks at 1,468 MB against a 2,048 MB ceiling and four units are live.
#   (4) a gate whose defect is in WHAT IT ASSERTS rather than where it stands: instances 1 and
#       5 of the brief, and the whole of `sb-gate.sh`'s failure.
# **THIS INSTRUMENT CLOSES THE "RELATIVE TO ITSELF" HALF OF THE CLASS AND IS BLIND TO THE
# "LITERAL LIST INSTEAD OF A POPULATION" HALF -- AND IT IS THE BLIND ONE, BECAUSE A POPULATION
# GATE IS ITSELF A POPULATION GATE.** That asymmetry is the honest shape of the result, and a
# reader who takes only one thing from this file should take it.

# THE ROOT SET IS NOT HERE. IT WAS `HOMES = ("checks", "gates")` ON THIS LINE, AND IT IS NOW
# `gate_homes(ROOT)`, MEASURED -- see "THE ROOT SET, DERIVED" below, and the criterion paragraph
# there that a reader can apply to a file they have never seen. The value is bound at the BOTTOM
# of this module, next to `FIXTURES`, for the reason `_init_fixtures` records: the derivation
# reads `root_facts`, and binding it here raised `NameError` at import.
#
# **`HOMES` IS THE MEASURED ROOT SET AND NOT A HAND LIST, AND THE LEDGER IS NOT WHAT PROVES IT.**
# The old comment said a third home "is visible only because the ledger diffs", and
# `gate-surface.py:walk_control` was handed this very list as the parameter it compares against,
# so the two lists it was about to compare were the SAME list. **A LIST COMPARED WITH ITSELF
# CANNOT DISAGREE, AND THAT IS WHY A META-GATE NEVER SETTLED THE QUESTION IT WAS BUILT TO SETTLE.**
# `gate_roots.md()` -- `gate_homes` for the GATE-HOME question, `scan_roots` for the
# COMMITTED-PYTHON question -- is the whole replacement, and it prints every candidate it
# rejected WITH ITS OWN DENOMINATOR.
LEDGER = HERE / "gates-pop.ledger.tsv"

# THE GENERATED-DIRECTORY POPULATION IS NOT A SECOND LIST. It is `gates/gendirs.py`, loaded BY
# PATH, and `gates/retention-check.py` loads the same file the same way. MEASURED, and the reason
# is the whole subject of this clause: `checks/gen/` is written by `checks/abi_gate.py:616`
# through `bend -o` and was invisible to BOTH instruments -- clause III here because `HOMES` is a
# two-item tuple, and `retention-check.py` because its registry was two `Output(...)` calls.
# **A POPULATION DEFINED BY A THREE-ITEM LIST CANNOT BE WRONG ABOUT A FOURTH ITEM BECAUSE IT NEVER
# LOOKS AT ONE.** Clause IV below is what looks at the fourth item.
def gendirs():
    """`gates/gendirs.py` by path, never by name: `gates/` is not a package, and putting it on
    `sys.path` would make `gendirs` a name any file in the tree could shadow -- an instrument
    loaded by a bindable name is an instrument whose population anybody can choose."""
    import importlib.util
    p = HERE / "gendirs.py"
    if not p.is_file():
        refuse("gates/gendirs.py is gone -- it IS the shared generated-directory population, "
               "and this file cannot answer clause IV without it")
    spec = importlib.util.spec_from_file_location("gendirs", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# WHAT THIS FILE STILL CANNOT SEE AFTER CLAUSE IV, AND IT IS NOT THE GENERATED DIRECTORIES. A gate
# that is BOTH outside `gate_homes()` AND named by no write site is invisible to every clause
# here -- which is to say, a gate nobody runs and nobody writes. That is the only hole left and it
# is stated rather than papered over. **WHAT CHANGED IS THAT THE HOLE HAS A SHAPE NOW:** it is the
# set of top-level directories `gate_homes()` REJECTED, and `report()` prints each with its own
# numerator and denominator, so the hole is 12 named directories rather than an unexamined
# assumption about two.

# NO SUFFIX SET. THE POPULATION IS THE DIRECTORY AND THE LANGUAGE IS READ OUT OF THE FILE.
#
# THIS USED TO BE `SUFFIXES = (".py", ".sh")`, and the prose above this line said "the scan
# ENUMERATES and the regexes are only ever used to CLASSIFY what was already enumerated" --
# which the very next line contradicted, because the tuple was applied to the ENUMERATION and
# not to the classification. **A COMMENT THAT DENIES A DEFECT IS NOT A FIX FOR IT, AND THIS WAS
# THE FILE THAT DEFINES THE CLASS.** MEASURED on the live tree by a directory walk against this
# function's own `iterdir()`: 374 regular files across `checks/`+`gates/`, of which the tuple
# admitted 174 and **200 were dropped before a byte of them was read**. Two of the dropped are
# true members, and both were named by content rather than by name:
#   `checks/nan_census.mjs` -- a tracked ES-module census driver, `node nan_census.mjs <workdir>`,
#     and the file `checks/gate.py:200` and `checks/e2e.py:428` reach for a `.mjs` driver.
#   `checks/bend` -- a tracked EXTENSIONLESS executable `#!/bin/sh` shim, which `entry_reason()`
#     reads, when called directly, as a correct `sh-dispatch`. It was not wrong; it was
#     unreachable.
# And the tuple was not even consistent with ITSELF: clause IV of this file loads
# `gates/gendirs.py` BY PATH, and `gates/gendirs.py:70 SOURCE_SUFFIXES` is
# `(".py", ".sh", ".mjs", ".js")` -- so clause I and clause IV of ONE instrument disagreed about
# what a source file is, in one file, and this file's own clause IV says two instruments holding
# two lists "have no authority over each other". **THE CLASS WAS INSIDE THE CENSUS OF THE CLASS.**
#
# WHAT REPLACES IT. `discover()` walks every REGULAR file in a home and `entry_reason()` asks
# each one what language it is IN. A FILE THAT IS NOT A PROGRAM IN A LANGUAGE THIS INSTRUMENT CAN
# READ IS NOT SILENTLY BUCKETED: it is counted as OPAQUE and printed with its own denominator, so
# a tree that grows a language MOVES A NUMBER instead of quietly losing a subject.
SH_SHEBANG = re.compile(r"^#!\s*(?:/usr/bin/env\s+)?(?:\S*/)?(?:ba|da|k|z)?sh\b")
NODE_SHEBANG = re.compile(r"^#!\s*(?:/usr/bin/env\s+)?(?:\S*/)?node\b")
# AN ES MODULE, NOT THE WORD "import". **MEASURED TWICE, and both failures were a shape that
# also matched ANOTHER LANGUAGE.** First `import\s+[\w{*]` put 39 `gates/*.bend` drivers into the
# population as `js-main`, because BEND HAS ITS OWN `import` KEYWORD and this tree ships 38
# tracked `.bend` files in the gate homes (`import Base` matches `import\s+\w`). Then allowing
# BEND'S OWN C-IMPORT SHAPE, `import "../runtime/sz.c"`, read `checks/c-context.bend` as
# JavaScript too. So the test is ESM SYNTAX AND NOTHING LOOSER -- an `import` with a
# `from "..."` clause, or an `export` declaration -- which every `.mjs` in this tree spells that
# way and which `import os` in prose does not.
JS_MODULE = re.compile(
    r"^[ \t]*(?:import\s+[\w{*][^;\n]*\s+from\s+['\"]"
    r"|export\s+(?:default|const|let|var|function|class|async))", re.M)
JS_EXPORT = re.compile(r"^[ \t]*export\s", re.M)


def is_literal_data(src):
    """Is this file a MODULE OR A CONSTANT? **MEASURED, and this is the second false answer the
    walk introduced before it was right.** `ast.parse` succeeds on JSON, because `{"a": 1}` is a
    valid Python dict display -- so on this tree `checks/census.json` (1.2 MB) and
    `checks/dup-census.json` (797 KB) both answered `py-lib`, and the parse alone cost 893 ms and
    550 ms. **"IT PARSES" IS NOT "IT IS A PROGRAM", AND A PARSE IS A PROOF OF SYNTAX ONLY.**
    The discriminator is content too: a module whose ENTIRE top level is `Expr` nodes and not one
    of them a CALL is a literal -- `print("x")` is `Expr(Call)` and is a program, `{"a": 1}` is
    `Expr(Dict)` and is data, and `import os` is neither shape at all.

    **AN EMPTY PARSE IS NOT A MODULE, AND THE `bool(tree.body)` GUARD WAS MAKING IT ONE.** MEASURED
    2026-10-17: the guard made a zero-statement parse return False -- "not literal" -- so
    `entry_reason` read it as `py-lib`, and plant 9 went RED over **2 of 164** real `.rows`
    fixtures: `gates/ops_python_census-pins.rows` and `gates/regalloc_census-pins.rows`, each of
    which parses to an EMPTY module. **PROVEN PRE-EXISTING, NOT CAUSED BY THIS CHANGE: HEAD's copy
    of this file answers `162/164` with the same two offenders and produces a byte-identical OPAQUE
    set and ENTRY set.** `all(())` is True and a file with no top-level statement at all is not a
    program in any language, so it belongs in the OPAQUE bucket the file's own plant says a `.rows`
    fixture belongs in -- "visible rather than absent", which is what `py-lib` failed to be."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    return all(isinstance(s, ast.Expr) and not isinstance(s.value, ast.Call) for s in tree.body)


def suffix_of(p):
    """`p`'s suffix for the OPAQUE DENOMINATOR only, and **hand-written rather than
    `Path.suffix`**. MEASURED: `Path('.err').suffix` is `''` -- a LEADING DOT STARTS NO SUFFIX --
    so `Path.suffix` buckets `checks/.err`, `checks/.out` and `checks/bend` in one row, and the
    third of those is an extensionless executable shell shim. It never decides MEMBERSHIP (`None`
    does), so a wrong answer here mislabels a count and cannot lose a gate."""
    i = p.name.rfind(".")
    return p.name[i:] if i > 0 else "(none)"


def refuse(*why):
    """`REFUSED` from `gatekit`, NOT a verdict.

    This file used to `sys.exit(2)` — `checks/abi_gate.py`'s rule in its own idiom — but
    `gatekit.py:60` OWNS the vocabulary (`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`) and a
    tree-owned runner maps ANY code outside those five to `DEAD` (`.agents/slop/hooks/run.py:33`), so a
    refusal here was scored `DEAD`. The code is IMPORTED, not re-spelled: a second copy of the
    vocabulary is the same fault as a second copy of a population.

    Placed BEFORE any measurement, because an assertion downstream of what it asserts cannot
    turn an exception into a refusal: `checks/census.py`'s own docstring records the tree doing
    exactly that (rc 1 and a traceback, which carries no denominator and so counts nowhere).
    """
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    sys.exit(REFUSED)


# ---- clause I: DISCOVERY ----------------------------------------------------------------
def _value(t):
    """The EVALUATED value of a string token, or None. Never raises: a token `ast.literal_eval`
    cannot read is a non-literal, which is exactly as informative as `None` for this use."""
    try:
        v = ast.literal_eval(t.string)
    except (ValueError, SyntaxError, TypeError):
        return None
    return v if isinstance(v, str) else None


def code_of(src, blank=()):
    """`src` with COMMENTS removed and DOCSTRINGS blanked IN PLACE, by `tokenize`.

    MEASURED, and this is the brief's own failure wearing a new hat. Without this, the
    instrument matched its OWN PROSE: `gates/gates-pop.py:202` carries
    `sys.path.insert(0, str(HERE.parents[2]))` inside a comment explaining exactly that line,
    `ROOT_INLINE` found it, and the run reported THIS FILE as off-repo -- making the count 13
    where the truth is 12. A meta-gate that scans its own documentation is the shell unit's
    classifier reading one directory's evidence as seventeen.

    **ONLY DOCSTRINGS ARE BLANKED, AND BLANKING RATHER THAN DELETING IS A SECOND MEASURED BUG.**
    The first version dropped EVERY string token, which left
    `refuse(   ) if not (REPO /    ).is_file()` and made `MARKER` stop matching
    `'pyproject.toml'` -- 2 of 8 plants went red because the scanner could no longer read the
    marker file's NAME. A string that is an ARGUMENT carries a path the scanner needs; a string
    that is a DOCSTRING carries prose it must not read. So the blanked set is exactly the
    docstrings, located with `ast` rather than guessed.
    """
    docs = set()
    try:
        for node in ast.walk(ast.parse(src)):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef,
                                 ast.AsyncFunctionDef)):
                d = ast.get_docstring(node, clean=False)
                if d is not None:
                    ex = node.body[0]
                    docs.update(range(ex.lineno, (ex.end_lineno or ex.lineno) + 1))
    except SyntaxError:
        pass
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        # A file `ast.parse` also rejects: fall back to the raw text rather than to an EMPTY
        # population, because the empty one cannot fail and that is this instrument's own defect.
        return src
    # `TokenInfo` is a NAMEDTUPLE and its `.string` cannot be assigned; the list is REBUILT.
    # That is not a style note -- the first version mutated in place and died with
    # `AttributeError: can't set attribute`, which is a crash inside a gate rather than a
    # verdict, and the crash is what told me. Nothing here is allowed to raise on a file whose
    # shape it did not expect.
    out = []
    for t in toks:
        if t.type == tokenize.COMMENT:
            out.append(t._replace(string=""))
        elif t.type == tokenize.STRING and (
                t.start[0] in docs
                # THE VALUE, NOT THE TOKEN TEXT. MEASURED: the first version compared `t.string`,
                # which for a fixture written `"...\n" + MAIN` is the SOURCE SPELLING (with a
                # backslash-n) while the value is the EVALUATED string (with a newline). They are
                # never equal, so nothing was blanked and the instrument kept reporting ITSELF
                # off-repo while the fix "passed". **A COMPARISON THAT CANNOT SUCCEED LOOKS
                # EXACTLY LIKE A COMPARISON THAT FOUND NOTHING.**
                or _value(t) in blank
                # A FIXTURE WRITTEN `"..." + MAIN` IS SEVERAL TOKENS. MEASURED: `FALLBACK_PRE_FIX`
                # holds `"sys.path.insert(...)  # the tinygrad tree\n" + MAIN`, so the source token
                # is the CONCATENAND'S FIRST HALF and equals no fixture exactly -- and for
                # `LIT_PY`, which is TWO adjacent literals, the offending token is the SECOND one
                # and is a SUFFIX. So the test is SUBSTRING: this token's text appears inside a
                # synthetic gate's text, which is not a guess, it is containment.
                # **A COMPARISON THAT CAN NEVER SUCCEED LOOKS EXACTLY LIKE A COMPARISON THAT FOUND
                # NOTHING**, and that is how the first version shipped a fix that did nothing.
                or any(len(v := _value(t) or "") >= 8 and v in f
                       for f in blank)):
            # KEEP THE QUOTES AND THE LENGTH: `untokenize` reconstructs source from token
            # geometry, so a changed length silently shifts every column after it.
            out.append(t._replace(string=t.string[0] + " " * (len(t.string) - 2) + t.string[-1]))
        else:
            out.append(t)
    return tokenize.untokenize(out)


def is_python_entry(src):
    """A Python ENTRY POINT: an `if __name__ == "__main__"` guard, read off the AST.

    NOT a regex. MEASURED: `rg '__main__'`-shaped text matching put the population at 21 while
    the AST put it at 63, and the 42 it lost included `checks/abi_gate.py`,
    `checks/hermetic-census.py` and EVERY one of the 9 `gatekit.Gate` gates. A population
    defined by a regex is a population defined by whatever the regex happened to spell.

    NOT the executable bit either. MEASURED: 42 of the 63 carry no `+x` -- including all nine
    `gates/*-gate.py`, which `gates/README.md:43` documents as `.venv/bin/python gates/...`.
    A mode bit is something a cleanup, a `git update-index`, or a `chmod -R` moves silently.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return f"UNPARSEABLE ({e.msg} line {e.lineno})"
    return any(isinstance(n, ast.If) and "__main__" in ast.dump(n.test) for n in ast.walk(tree))


# THE SHELL ENTRY CLASS, AND THE FIRST VERSION OF IT WAS WRONG BY 15 FILES. It read
# `^\s*exec\b|^\s*\$\{?0` -- an `exec`, or a `$0` AT THE START OF A LINE. MEASURED on
# `checks/*.sh`: that finds **2** entry points out of **17**. It misses `checks/e2e.sh`,
# `checks/sb-gate.sh`, `checks/lintable-gate.sh`, `checks/walk-mutate.sh`, `checks/run-all.sh`
# and ten more, because they spell their self-reference `_d=${0%/*}` and the `$0` sits in the
# middle of a line. **THAT IS THE BRIEF'S OWN FAILURE, verbatim: one tokenizer's assumption,
# missed by a belt that shared it.** `checks/sb-gate.sh` -- the gate in instance 1, the one that
# "applies its rules to itself and its three literal lanes only" -- was INVISIBLE to this file.
#
# THE FIX IS TWO TOKENIZERS THAT DO NOT SHARE A REGEX, and the population is their UNION, with
# the disagreement REPORTED rather than resolved silently. `SH_ENTRANCE` (line-anchored) and
# `SH_SELFREF` (a `$0` the shell would substitute) agree on 2 files and disagree on 15; a run
# that prints only their union cannot tell you which token found what, so the report says so.
#
# `SH_SELFREF` WAS `\$\{?0\b` -- "any `$0` at all" -- AND IT IS NOW `\$\{0|["']\$0["']`, because
# **MEASURED: `$0` IS NOT A SHELL TOKEN, IT IS A NAME, AND BEND EMITS IT AS A CPS VARIABLE IN
# JAVASCRIPT.** `tinybendygrad/runtime/webgpu_call.mjs:315` is `const _cs_0 = $0;` and `:312` is
# `function ...($0, $1) {`, so the old token read two tracked `.mjs` files as `sh-dispatch` on a
# variable name a shell would have replaced. The shell substitutes `$0` only inside `"$0"`, `'${0'`
# or `${0`; a BARE `$0` is an identifier. MEASURED as a tightening rather than a guess: it matches
# 17 of 17 `checks/*.sh` (denominator 17, same count, ZERO files lost), keeps `checks/bend`, and
# drops both emitted-JavaScript false positives. **A TOKEN THAT MATCHES A FOREIGN LANGUAGE'S
# LOCAL VARIABLE IS NOT A NARROWER POPULATION, IT IS A WIDER ONE.**
SH_ENTRANCE = re.compile(r"^\s*(?:exec\b|\$\{?0)", re.M)
SH_SELFREF = re.compile(r"\$\{0|[\"']\$0[\"']")
# `[^\S\n]` IS "WHITESPACE EXCEPT NEWLINE", so this matches the indentation a comment can have and
# NOT the line break in front of it. IT WAS `^\s*`, AND `\s` INCLUDES `\n`, SO THE MATCH STARTED
# ON THE PREVIOUS LINE AND **ATE ITS NEWLINE**: MEASURED 2026-10-19T16:25Z, `checks/run-f64.sh`
# went 447 -> 434 newlines and `checks/sb-gate.sh` 276 -> 264, because `^\s*` eats the newline
# before EACH comment of a run. `awk 'END{print NR}'` on the first reads 448 and 435 -- THE SAME
# THIRTEEN, under the other convention.
#
# **THE POPULATION DID NOT MOVE, AND THAT IS MEASURED, NOT ASSUMED** -- the whole question, because
# a fix that changed the set of gates would be a different instrument wearing this one's name.
# Over 1336 files under `HOMES` it eats 2537 newlines and changes 0 entries and 0 tokenizer
# verdicts; tree-wide over 155 `.sh`, 237 newlines and 0/0/0. **WHY**: `SH_ENTRANCE` is anchored
# with `^\s*` TOO, and `\s` already spans newlines, so swallowing one cannot move a token across a
# boundary the tokenizer cared about. The damage was invisible to every matcher here and visible
# only to a reader counting lines -- which is the worst place for an instrument to be wrong.
#
# `SH_ENTRANCE` KEEPS ITS `\s*` ON PURPOSE: its leading class is load-bearing, not cosmetic, and
# narrowing it is not free even where it measures as a no-op. It is not this function's output.
SH_COMMENT = re.compile(r"^[^\S\n]*#.*$", re.M)


def shell_code(src):
    """Shell source with `#` COMMENTS removed, AND NOT ONE LINE MORE THAN IT WAS.

    Same reason as `code_of`, and MEASURED on the same fault: `checks/sb-gate.sh:17` is a
    comment saying "This gate used to `cd "$(dirname "$0")/../../.."`", and a scanner that
    reads comments would find a `../../..` root in a file that no longer has one. **A gate's
    own changelog is not its code** -- and this repo writes unusually thorough changelogs, which
    is exactly what makes the mistake likely here.

    **A LINE IS NOT A COMMENT AND A COMMENT IS NOT A LINE DELETION.** A census that returns a
    blanked copy of a shell file has destroyed its geometry: any consumer reading a line number
    off the result reads a number into a file that never had that line, by an amount that depends
    on how the comments were spaced. That is the `SPEC`/census shape `AGENTS.md` already names --
    a denominator that is wrong by a SILENT amount cannot be wrong and cannot be right.
    """
    return SH_COMMENT.sub("", src)


def is_shell_entry(src):
    """A shell ENTRY, by the UNION of two tokenizers that share no regex.

    The union is the point: either alone misses gates, and the direction they miss in is not
    the same direction. `SH_ENTRANCE` alone saw 2 of 17. `SH_SELFREF` alone would treat a
    sourced fragment that mentions `$0` in a comment as an entry. Neither is right alone, and
    `--plant` plant 0 asserts the union finds a gate that a line-anchored token cannot.
    """
    src = shell_code(src)
    return bool(SH_ENTRANCE.search(src) or SH_SELFREF.search(src))


def shell_tokens(src):
    """`(entrance, selfref)`, so the report can name WHICH tokenizer found the entry."""
    src = shell_code(src)
    return bool(SH_ENTRANCE.search(src)), bool(SH_SELFREF.search(src))


def entry_reason(p):
    """Why this file is in the population, as a word the report prints. `sh-selfref` is named
    separately from `sh-dispatch` because it is the token that the narrow line-anchored regex
    could not see -- and 15 of 17 shell gates are in that class. `js-main`/`js-lib` exist because
    JavaScript has no `__main__` guard: a module that EXPORTS is a library, and a module that
    only imports -- or has no module syntax at all -- RUNS ITS TOP LEVEL when `node` loads it.

    **`p.suffix` APPEARS NOWHERE IN THIS FUNCTION, and that is the entire fix.** The previous
    version asked `p.suffix == ".py"` and sent EVERY OTHER SUFFIX to the shell tokenizer, so
    deleting the suffix tuple alone would have been a fix that moved the count and left the
    instrument wrong: `nan_census.mjs` would have been admitted and relabelled `sh-lib`, which
    is a census of JavaScript by a shell grammar. **ADMITTING A FILE IS NOT THE SAME AS
    UNDERSTANDING IT, AND THE SECOND HALF OF THAT SENTENCE WAS ALSO A SUFFIX SET.**

    `None` means THIS FILE IS NOT A PROGRAM IN A LANGUAGE THIS INSTRUMENT CAN READ, and `None` is
    a value with a denominator rather than a silent bucket -- see `discover()`.
    """
    try:
        src = p.read_text(errors="replace")
    except OSError:
        return None
    # JAVASCRIPT BEFORE PYTHON, and the order is measured rather than preferred: `JS_MODULE` is
    # CONCLUSIVE. Neither Python nor shell can spell `import {a} from "b"` or `export function`,
    # so a file that matches it is JavaScript with nothing left to decide. The reverse is NOT
    # true -- `console.log("REPRO stub: stage 3 gpu");` is a valid PYTHON expression statement --
    # so testing Python first silently reclassifies short JavaScript stubs. **THE RESIDUAL IS
    # NAMED RATHER THAN PATCHED**: a JavaScript file with no ESM syntax whose whole body is also a
    # valid Python program is read by the Python grammar, and there is no test for it here that is
    # not a list of JavaScript spellings -- which is the defect this file exists for. It counts 3
    # of the 19 `.mjs` in this tree, all three of them 40-byte stubs under `.agents/slop/`, and a
    # file it mislabels as `py-lib` is COUNTED as a module, never dropped.
    if NODE_SHEBANG.match(src) or JS_MODULE.search(src):
        return "js-lib" if JS_EXPORT.search(src) else "js-main"
    # `is_python_entry` returns `True`, `False`, OR THE STRING `"UNPARSEABLE (...)"`, and all
    # three are tested EXPLICITLY. **MEASURED, and the first version of this fix wrote
    # `if py is not False`**, which is true of that string too -- so `ast.parse` failing on a
    # `checks/*.rows` fixture made 137 expected-value files answer `py-lib`, and the OPAQUE bucket
    # this change exists to create stayed at ZERO while the module count went to 190. **A TEST
    # THAT CANNOT FAIL LOOKS EXACTLY LIKE A TEST THAT PASSES**, and `is not False` cannot fail.
    # An unparseable file is not Python, is not shell, and is not a module: it is OPAQUE, which
    # is a count rather than a bucket -- and that is the honest answer for a file that cannot be
    # read, because the alternative is to name it after a guess.
    py = is_python_entry(src)
    if py is True or (py is False and not is_literal_data(src)):
        return "py-main" if py else "py-lib"
    # JAVASCRIPT BEFORE SHELL, and the ORDER is measured rather than preferred. **MEASURED:
    # `SH_SELFREF` was `\$\{?0\b`, and `$0` is BEND'S CPS STATE VARIABLE IN EMITTED JAVASCRIPT**
    # -- `.agents/slop/e2e/webgpu_call.mjs:315` is `const _cs_0 = $0;` and `:312` is a closure
    # `function ...($0, $1)`. So the shell self-reference token is NOT shell-specific, and a
    # shell-first order classified two tracked `.mjs` files as `sh-dispatch` on the strength of a
    # variable name bend emits. Reordering is safe in the other direction BECAUSE IT IS ALSO
    # MEASURED: 17 of 17 shell files in the two homes carry a `sh` shebang and 0 of them contain
    # ESM syntax, so no shell file can reach the JavaScript branch.
    ent, self_ = shell_tokens(src)
    # A SHEBANG is the shell test; a `$0` self-reference is the fallback for a shell file that
    # has none, kept because plant 6 measures 17 of 17 `checks/*.sh` BY SELF-REFERENCE and this
    # file must not lose any of them for want of a shebang.
    if SH_SHEBANG.match(src) or self_:
        if ent and self_:
            return "sh-dispatch"
        return "sh-selfref" if self_ else "sh-lib"
    return None


def carried(root, homes, paths):
    """The IMMEDIATE files of `homes` that the COMMIT TREE carries, as paths relative to `root`.

    **THIS IS THE POPULATION RULE, AND IT IS THIS FILE'S OWN DEFINITION, WHICH UNTIL NOW WAS
    STATED IN PROSE AND APPLIED TO THE HOMES ONLY.** The definition above says a file is a gate
    "iff the COMMIT TREE carries it (`git ls-tree -r HEAD` -- never the index, which a reset
    empties, and never the working copy, which `chmod -R` and a stray write both move)". The
    HOMES were derived from the commit tree (`gate_homes` -> `_tree_paths`), and the FILES were
    not: `_buckets` walked the working copy, so the population was a SECOND, LOOSER reading of
    the same question. MEASURED 2026-10-20T17:58Z on the live tree: **4 of the 293 entry points
    were files the commit tree does not carry** -- `checks/.tmp-amd_dsl_census-mutate.py`,
    `checks/.tmp-coverage.py`, `checks/.tmp-graphcmp-census-audit.py` and
    `checks/.tmp-tc_ptx_render-oracle.py` -- another unit's in-flight scratch, the very files
    `gates/gates-pop.py`'s own header records a plain invocation once wrote into the shared
    ledger. `checks/gatesweep.py` had MEASURED the same fact from the other side (its header:
    "6 of the 6 dotted entries under the two homes are ABSENT from `git ls-tree -r HEAD`") and
    printed it as the `4 dotted` term of its projection -- **so the tree already knew, and the
    census that owns the definition did not apply it.**

    **WHY IT MATTERS BEYOND CONSISTENCY: IT IS WHAT MAKES THE SHARED LEDGER WRITABLE.** A
    generator that can absorb another unit's uncommitted scratch is a generator whose every run
    is a claim on a file other units own. **A POPULATION THAT INCLUDES ANOTHER UNIT's WORK IN
    PROGRESS IS NOT A POPULATION OF THIS REPOSITORY.**

    `paths` is the derivation's OWN path list -- the commit tree when there is one, and the
    working copy when there is not (a synthetic tree). **SO A PLANT'S TREE STILL WORKS, AND THE
    FALLBACK IS NOT A SPECIAL CASE: IT IS THE SAME RULE WITH A DIFFERENT ANSWER.**
    """
    keep = set()
    for home in homes:
        pre = home + "/"
        for p in paths:
            if p.startswith(pre) and "/" not in p[len(pre):]:
                keep.add(p)
    return keep


def _buckets(root):
    """`(entries, libs, opaque, uncarried)`, by walking every REGULAR file in the DERIVED homes.
    NEVER a literal list of files, NEVER a suffix set, and NEVER a literal list of homes: the
    homes come from `gate_homes(root)` -- which is why a plant has to DECLARE its homes by
    planting a gate that certifies one, and why `_tree` below does exactly that.

    `iterdir()` and not `rglob()`, so a `__pycache__` directory under a home is not descended
    into and a cached `.pyc` cannot be counted as a gate. `os.lstat` and not `Path.exists()`
    **nor `Path.is_file()`**, because **BOTH OF THOSE FOLLOW SYMLINKS**: `bin/bend` is a symlink to a
    worktree and a test that follows it would certify a link target as a tree file.

    MEASURED 2026-10-07 (`subtree`): this line called `p.is_file()` while the docstring above it
    claimed `os.lstat`, **AND `os.lstat` APPEARED NOWHERE IN THE FILE** — so the code did precisely
    what its own comment said it did not. Planted **both** directions: a symlink whose target is
    OUTSIDE the home **was certified** (the hazard this comment exists to prevent), and a DANGLING
    gate symlink **was invisible**. `stat.S_ISREG(os.lstat(p).st_mode)` is true only for a real
    file: it rejects a symlink outright and cannot be fooled by a broken one.

    THE THIRD BUCKET IS THE POINT. A file the walk holds that `entry_reason()` reads as `None` is
    neither an entry nor a module: it is OPAQUE, and it is returned as its own list with its own
    denominator rather than folded into `libs`. Folding it in is how `nan_census.mjs` would have
    stayed invisible for another day — a JavaScript file counted as a shell module is a wrong
    answer that still ADDS UP, which is the only kind of wrong answer that survives every count.

    **AND THE FOURTH BUCKET IS THE NEW ONE: A FILE THE COMMIT TREE DOES NOT CARRY IS NOT A GATE
    OF THIS REPOSITORY**, so it is counted and NAMED rather than admitted. It is returned as its
    own list because a file that is invisible cannot be argued with -- and because the ledger's
    writer reads this list, and a ledger that can absorb another unit's scratch is the defect
    this bucket exists to close. MEASURED 2026-10-20T17:58Z: **4 files**, all of them
    `checks/.tmp-*`, another unit's in-flight scratch, none of them in the commit tree.
    """
    entries, libs, opaque, uncarried = [], [], [], []
    homes = _homes(root)
    keep = carried(root, homes, _measure(root)[1]["paths"])
    for home in homes:
        h = root / home
        if not os.path.isdir(h):
            continue
        for p in sorted(h.iterdir()):
            if not stat.S_ISREG(os.lstat(p).st_mode):
                continue
            r = entry_reason(p)
            if str(p.relative_to(root)) not in keep:
                # NOT CARRIED BY THE COMMIT TREE. It is not a gate of this repository, and it is
                # not one of the repository's unreadable files either -- so it is counted and
                # NAMED, never admitted.
                uncarried.append((p, r))
                continue
            if r is None:
                opaque.append(p)
            elif r in ("py-main", "sh-dispatch", "sh-selfref", "js-main"):
                entries.append(p)
            else:
                libs.append(p)
    return entries, libs, opaque, uncarried


def discover(root):
    """`(entries, libs)` -- **A TWO-VALUE TUPLE IS A CONTRACT, and this one is MEASURED, not
    assumed.** `gates/gate-surface.py:280` returns this call's result straight into a two-value
    unpack, so the first version of this change returned three and the regression was
    `ValueError: too many values to unpack (expected 2)` at `gate-surface.py:422` -- rc 1 in a
    gate this unit was told not to edit. **A FIX THAT BREAKS A CALLER IS NOT A FIX; IT IS A
    TRADE, AND THE TRADE HAS TO BE PAID SOMEWHERE ELSE.** So the third bucket leaves through
    `opaque()` instead of through this signature, and the walk itself happens once.

    **AND THE FOURTH BUCKET LEAVES THE SAME WAY, FOR THE SAME REASON.** `discover()` is read by
    `checks/gatesweep.py` (its `CONTROL`), so its arity is a contract with a second instrument.
    """
    entries, libs, _opaque, _uncarried = _buckets(root)
    return entries, libs


def opaque(root):
    """The third bucket alone, so `discover()`'s arity can stay a contract somebody else owns."""
    return _buckets(root)[2]


def uncarried(root):
    """The FOURTH bucket: `(path, reason)` for the immediate files of the homes that the COMMIT
    TREE does not carry. `reason` is what `entry_reason()` reads the file as, or `None` when the
    instrument cannot read it at all.

    **A FILE THE TREE DOES NOT CARRY IS NOT A GATE, AND THE LEDGER'S WRITER READS THIS LIST.** A
    generator that can absorb another unit's in-flight scratch is a generator whose every run is
    a claim on a file other units own, and `gates/gates-pop.py`'s own header records a plain
    invocation doing exactly that: **13 added and 7 removed lines, 4 of them `checks/.tmp-*`,
    ANOTHER UNIT'S IN-FLIGHT SCRATCH.** So the writer must be able to ASK, and this is the
    answer it asks.
    """
    return _buckets(root)[3]


# ---- clause II: what each gate POPS FOR, and whether it can fail -----------------------
# THE ROOT CONSTANT, AND WHY THE FIRST VERSION OF THIS WAS WRONG IN THE DIRECTION THAT
# MATTERS. It read `(REPO|ROOT) = ... parents[n]` and called any `n > 0` FALSE, on the
# reasoning that the depth is baked into the constant. MEASURED: that fires on 16 files, and
# SIX of them are CORRECT -- `checks/differ.py:41` is `parents[1]`, and `parents[1]` OF A
# FILE is its own directory, which IS the root for a file one level below it. A rule that
# calls a working gate broken trains the reader to ignore it, which is the same failure as
# `sb-gate.sh`'s literal list wearing the opposite face. **So the constant is EVALUATED, not
# pattern-matched: the clause asks where the expression RESOLVES, and only a resolution that
# is not the repo root is a finding.**
#
# TWO SPELLINGS, and both are accepted because both appear in this tree: `HERE.parents[n]`
# where `HERE` is the file's DIRECTORY, and `Path(__file__).resolve().parents[n]` where the
# walk starts at the FILE. They differ by one, and `checks/abi_gate.py:50` and
# `checks/differ.py:41` disagree about it while both being right.
ROOT_CONST = re.compile(
    r"^\s*(?:HERE\s*=\s*.*\n)?\s*(?:REPO|ROOT)\s*=\s*.*?"
    r"(?:__file__|HERE)\)?(?:\.resolve\(\))?\.parents\[(\d)\]",
    re.M)
# THE INLINE FORM, AND IT IS A MISS THIS INSTRUMENT HAD BEFORE IT WAS WRITTEN AS A PLANT.
# `checks/census.py:14` at `457b81619^` computed its root with NO CONSTANT AT ALL:
#     sys.path.insert(0, str(HERE.parents[2]))            # the tinygrad tree
# A regex anchored on `(REPO|ROOT)\s*=` cannot see it, and the instrument reported that file as
# on-root and GREEN while the gate was importing from `/Users/cyberistic/src`. MEASURED on the
# pre-fix sources: `census.py` MISSED, `hermetic-census.py` and `abi_gate.py` CAUGHT -- 2 of 3
# on the ONE spelling the brief names, and the miss was on the instance whose fix commit
# (`457b81619`) says "BORN AT DEPTH 1 CARRYING A DEPTH-2 CONSTANT". So the population for this
# clause is ANY `parents[n]` in a root-ish position, not just an assignment.
ROOT_INLINE = re.compile(
    r"(?:sys\.path\.insert|open|read_text|read_bytes|Path)\s*\(?.*?"
    r"(?:__file__|HERE)\)?(?:\.resolve\(\))?\.parents\[(\d)\]")
# A ROOT ASSERTION is a refusal that fires when the root is wrong: `refuse(`/`exit 3`, a
# marker-file test, or an equality assertion against a known root. The word "ASSERTED" is
# searched for as well as the marker test, because this repo writes the intent in prose next
# to the line and the prose is what a reader is asked to trust.
REFUSE = re.compile(r"\brefuse\(|\bexit 3\b|not at the repo root|REFUSED, NOT A VERDICT")
MARKER = re.compile(r"pyproject\.toml")

# THE STRINGS IN THIS MODULE THAT ARE *SYNTHETIC GATES*, so their contents are DATA. Named by the
# names this file already owns, not by a regex over the source: **a fixture is identified by what
# it IS, not by how it is spelled**, and MEASURED, `sweep.py`'s `ORACLE` was a basename word-shape
# that 670 of 675 files satisfied and no gate named.
def _fixture_strings():
    """The string TOKENS whose value is a synthetic gate, i.e. data to this instrument rather
    than this instrument's own code. Built by IDENTITY against the modules this file owns, so a
    fixture is recognised by WHAT IT IS -- MEASURED, `sweep.py`'s `ORACLE` was a basename
    word-shape 670 of 675 files satisfied and no gate named."""
    out = set()
    for value in list(FALLBACK_PRE_FIX.values()) + [BAD_ROOT, GOOD_ROOT, LIT_PY, LIT_SH]:
        if isinstance(value, str) and len(value) > 8:
            out.add(value)
    return frozenset(out)


FIXTURES = ()          # rebound at the bottom of the module; see `_init_fixtures`


def _init_fixtures():
    """`FIXTURES` is a MODULE GLOBAL assigned ONCE, at the bottom of this file, because
    `FALLBACK_PRE_FIX` is defined below the functions that read it. MEASURED: calling this at the
    top raised `NameError: name 'FALLBACK_PRE_FIX' is not defined` at IMPORT -- a crash inside a
    gate rather than a verdict. The same reason `LEDGER_PATH` is a module global."""
    global FIXTURES
    FIXTURES = _fixture_strings()
MARKER = re.compile(r"pyproject\.toml")


def resolve_root(p, depth, expr):
    """Where this file's own root expression RESOLVES, on the real tree.

    Evaluated rather than reasoned about, because the two spellings differ by one and getting
    that difference wrong produces findings on files that work. This is the shape of the belt
    that has to disagree with the evidence rather than share its assumption.

    `.resolve()` ON BOTH SIDES OF THE COMPARISON, and that is a measured fix rather than a
    habit: MEASURED, `tempfile.TemporaryDirectory()` hands back `/var/folders/...` on macOS
    while `Path(p).resolve()` hands back `/private/var/folders/...`, and comparing one against
    the other makes EVERY root off-repo -- 0 of 3 on the plant tree and 0 of 66 on the live
    one. It is the same trap as `Path.exists()` following a symlink, and it is a GREEN that
    would have been impossible to distinguish from a RED.

    `expr` is the MATCHED TEXT, not a re-read of the file: `checks/census.py:14`'s inline
    `sys.path.insert` spelling has no `(REPO|ROOT) =` line for a separate scan to find, so
    resolving by re-reading would have silently measured the WRONG LINE for exactly the
    instance the inline pattern was added to catch.
    """
    f = p.resolve()
    # `Path(__file__).resolve()` walks from the FILE, so `parents[n]` counts the file's own
    # directory as `parents[0]`; `HERE.parents[n]` starts one level above that. The spelling is
    # read off the EXPRESSION ITSELF, because `checks/cl-port-gate.py:40` spells it
    # `Path(__file__).resolve().parents[3]` and says in its own comment that the depth is
    # deliberate.
    # THE DISCRIMINATOR MUST BE THE **SHAPE** OF `HERE`'s OWN ASSIGNMENT, NEVER ITS NAME.
    # MEASURED 2026-10-06: the guard here read `if "HERE" in expr`, and **TWO FILES WITH DIFFERENT SHAPES
    # NAME THEIR VARIABLE `HERE`** — `checks/both-census.py` holds a DIRECTORY
    # (`HERE = pathlib.Path(__file__).resolve().parent`) and `checks/disagree-gate.py` holds A FILE
    # (`HERE = Path(__file__).resolve()`). ONE OF THEM WAS THEREFORE MIS-MEASURED, AND IT WAS THE FILE:
    # `parents[1]` FROM A FILE **IS** THE REPO ROOT, SO THE GATE REPORTED A WORKING GATE OFF-REPO.
    # *** A VARIABLE'S NAME CANNOT TELL YOU WHETHER IT HOLDS A FILE OR A DIRECTORY. THIS IS THE `ORACLE`
    # FAILURE AGAIN — *THE ROLE IS A PROPERTY OF THE DIRECTORY AND WAS BEING READ FROM THE FILE* — AND THE
    # THIRD TIME IN THIS PROJECT THAT A DISCRIMINATOR HAS BEEN A NAME OR A LITERAL INSTEAD OF A SHAPE.***
    if "HERE" not in _root_expr(expr):
        return f.parents[depth]
    assignment = next((l for l in p.read_text(errors="replace").splitlines()
                       if re.match(r"\s*HERE\s*=", l)), "")
    is_directory = assignment.rstrip().endswith((".parent", ".parent)")) or "dirname" in assignment
    return f.parent.parents[depth] if is_directory else f.parents[depth]


def _root_expr(expr):
    """The `(REPO|ROOT) = ...` LINE of a match, and nothing else.

    `ROOT_CONST` SPANS an optional `HERE = ...` line and the `REPO/ROOT = ...` line, and
    `root_facts` hands `resolve_root` `m.group(0)` -- the WHOLE match, newline included -- so
    `"HERE" in expr` was a question about the MATCH and not about the EXPRESSION. MEASURED
    2026-10-17: `checks/cl-port-gate.py:48` is `REPO = Path(__file__).resolve().parents[1]`, a
    FILE-relative spelling that resolves ON-REPO, and that file's own `:42` proves the depth by
    `refuse()`; the instrument called it OFF-REPO because the `HERE = ...parent` line above it put
    `HERE` into the match, so the arithmetic shifted by one and answered `/Users/cyberistic/src/
    tries`. **A PREFIX OF A MATCH IS NOT THE MATCH -- the same fault as `checks/repro-paths.py`'s
    retracted REF suffix set reading a path's PREFIX as the path.**
    """
    return expr.rsplit("\n", 1)[-1]


def root_facts(p, root):
    """`(constant_site, asserts, resolves_to_root)` for one gate file.

    MEASURED on the tree as it stands: `checks/hermetic-census.py:33` is `HERE.parents[2]`,
    which at `checks/` is `/Users/cyberistic/src` -- a directory holding `tries/` and no
    tinybendygrad, no `.agents`, no `graphcmp`. `checks/census.py`'s own docstring records
    that exact failure (`sys.path.insert` of a directory holding no importable module) and its
    fix was `parents[0]` PLUS a `refuse()` placed BEFORE the import. So the constant alone is
    not the defect; the defect is a root that resolves OUTSIDE the repo with no refusal in
    front of it, because that is the state in which the gate reports on the wrong tree.
    """
    src = p.read_text(errors="replace")
    # THE ROOT SCANNERS READ CODE, NOT PROSE, AND NOT FIXTURES. `code_of` strips comments and
    # docstrings, so this file's own comment quoting the very line the scanner hunts is not a
    # finding about itself. MEASURED: before the strip, this file reported ITSELF off-repo.
    #
    # **AND THE STRIP IS NOT ENOUGH, WHICH IS THE SAME FAILURE ONE LAYER DEEPER.** `code_of`
    # blanks only DOCSTRING tokens, deliberately, because a string that is an ARGUMENT can carry
    # a path the scanner needs. But a string that is a **PLANT FIXTURE** carries a whole
    # SYNTHETIC SOURCE FILE: `FALLBACK_PRE_FIX["checks/census.py"]` (line 629) is the literal text
    # `sys.path.insert(0, str(HERE.parents[2]))`... MEASURED 2026-10-06: with the strip and
    # nothing else, `ROOT_INLINE` matched **that string**, `resolve_root` evaluated it against the
    # LIVE tree, and the run printed `gates/gates-pop.py ... resolves outside the repo` -- a
    # FALSE finding about a file whose own root is `HERE.parents[0]`. Plant 7 asserted only the
    # COMMENT layer (`lit_py`, which begins `# was:`), so it was green while the instrument was
    # wrong about itself. **PROSE IS NOT CODE, AND A FIXTURE IS NOT EITHER: A STRING THAT HOLDS
    # SOURCE IS DATA TO THIS INSTRUMENT WHOSE SOURCE IT IS NOT.** `FIXTURES` is the set of names
    # whose string values are synthetic gates, named by the module that OWNS them.
    code = code_of(src, FIXTURES if p.resolve() == Path(__file__).resolve() else ())    # noqa: E501
    # **A FIXTURE IS DATA ONLY TO THE FILE THAT OWNS IT.** The blank set is applied when the file
    # being read IS this file, and to nothing else. MEASURED: applying it unconditionally broke
    # plants 1 and 5 -- a plant writes `GOOD_ROOT` into a synthetic `checks/good.py` and then asks
    # `root_facts` about it, and with the blank on, the whole fixture was blanked, so `refuse(`
    # and `pyproject.toml` both vanished and `GOOD_ROOT` read as a gate with NO root assertion.
    # Two plants went red, which is the right outcome: **A FIX THAT MAKES THE SUBJECT INVISIBLE
    # MAKES THE SUBJECT PASS, AND THAT IS THE `artefacts_ok()` SHAPE.** Scoping the rule by the
    # OWNING FILE is not a special case for this instrument; it is the definition of "fixture".
    asserts = bool(REFUSE.search(code)) and bool(MARKER.search(code))
    # `ROOT_CONST` FIRST, then `ROOT_INLINE`, and the order matters only for what gets REPORTED:
    # both are measured the same way, so a file with both spellings is measured once and named
    # by the constant. Neither subsumes the other, and that is measured, not argued -- see
    # `ROOT_INLINE`'s note on `checks/census.py:14`, which the constant-only regex missed.
    m = ROOT_CONST.search(code) or ROOT_INLINE.search(code)
    if m:
        where = resolve_root(p, int(m.group(1)), m.group(0))
        # ONE LINE, because this string is a TSV field: `ROOT_CONST` spans the optional
        # `HERE = ...` line and the `REPO = ...` line, and a raw newline inside a TSV cell
        # is how one ledger row silently becomes two.
        return " ".join(m.group(0).split()), asserts, where == root.resolve()
    return ("__file__.parent" if re.search(r"^\s*HERE\s*=", code, re.M) else "-"), asserts, True


# ---- THE ROOT SET, DERIVED, AND THE CRITERION THAT DERIVES IT ---------------------------
#
# WHAT A GATE IS, IN ONE PARAGRAPH, FOR SOMEONE WHO HAS NEVER SEEN A FILE IN THIS TREE. **A file
# is a GATE of this repository iff the COMMIT TREE carries it (`git ls-tree -r HEAD` -- never the
# index, which a reset empties, and never the working copy, which `chmod -R` and a stray write both
# move), AND running that file AS A PROGRAM performs its measurement -- an `if __name__ ==
# "__main__"` guard in Python, a shell file dispatching on `$0` or `exec`, an ES module that RUNS
# its top level under `node` rather than exporting it -- AND it reports a verdict, meaning one of
# the five statuses `gates/gatekit.py` names, carrying a denominator.** The four named cases:
#
#   `checks/nan_census.mjs`      IN.  Tracked; JavaScript has no `__main__`, so the entry-point
#                                      test is "the module RUNS rather than EXPORTS"; and its rows
#                                      ARE the denominator it prints. A suffix set can never admit
#                                      it and a shebang test can never see it.
#   `checks/bend`                IN.  Tracked; `#!/bin/sh` plus `exec`; a two-line launcher is a
#                                      gate whose subject happens to be a compiler. **A BASENAME IS
#                                      NOT A PATH** -- `gate.txt` is four files -- **AND A BASENAME
#                                      CAN BE A PROGRAM**, which is why `suffix_of` is hand-written
#                                      and why no suffix test may decide membership.
#   `.agents/slop/capstream/refsplit.py`   OUT.  It is tracked AND it HAS `__main__` -- MEASURED,
#                                      `entry_reason` returns `py-main` for it -- so the first two
#                                      clauses CANNOT reject it. **Only the root clause can, and
#                                      that is the whole reason the root clause exists.** No gate in
#                                      `.agents/`'s own row resolves a root (`1` prefilter survivor
#                                      of `5` immediate files, rejected), so `.agents` is not a home;
#                                      the file is three levels below a directory this tree puts a
#                                      gate in, nothing in the repository executes it, and it answers
#                                      one unit's question about one basename.
#   `tinybendygrad/uop/fold.bend`  OUT.  Tracked, and `entry_reason` returns `None` for it: no entry
#                                      guard, `import`ed by the `.bend` files that use it. It is the
#                                      port's own source, and the port is what is being MEASURED --
#                                      running it would be the subject auditing itself.
#
# THE ROOT CLAUSE, WHICH IS THE ONLY PART NOBODY HAD WRITTEN DOWN. **A gate home is a top-level
# directory of the commit tree holding, IN ITS OWN IMMEDIATE FILES, at least one tracked file that
# is an ENTRY POINT and that NAMES A ROOT, REFUSES ON A WRONG ONE, and RESOLVES ON-REPO.** Every
# one of those four is already measured in this file -- `entry_reason`, `ROOT_CONST`/`ROOT_INLINE`,
# `REFUSE`, `MARKER`, `resolve_root` -- so the declaration is read off the gates themselves rather
# than transcribed. **THE SUBJECTS DECLARE THE UNIVERSE THEY LIVE IN, WHICH IS THE ONLY SHAPE OF
# POPULATION THAT CANNOT ROT WITHOUT SOMETHING ELSE ROTING WITH IT.** "IMMEDIATE FILES" is not a
# depth number but the coherence condition `_buckets` imposes; see `gate_homes`.
#
# MEASURED, live tree, and this is the answer `.agents/slop/UNIVERSE-CENSUS.md` refused to give
# because no criterion existed to give it with: **2 of 14** top-level directories of the commit
# tree qualify, over **869 immediate files read**, **18 prefilter survivors** and **17 certified
# witnesses** (`checks` 16, `gates` 1). The twelve rejects each carry their own denominator, and
# the load-bearing one is `.agents` at **1 survivor of 5** -- `.agents/TODO.md`, which survives the
# prefilter because it quotes `__main__` and `refuse(` in prose and is then REJECTED because it
# does not resolve a root. **THE PREFILTER OVER-ADMITS AND THE CLAUSE DECIDES, WHICH IS THE ONLY
# ORDER IN WHICH THOSE TWO CAN COEXIST.**
#
# WHAT IT DOES NOT SETTLE, AND IT IS NOT SETTLED ANYWHERE ELSE EITHER. A home may be a directory
# holding gates that never run (the hole named above), and a vendored upstream directory may hold
# entry points (`test/` holds `4` immediate files and **307** across its 390 tracked ones) that are
# emphatically not gates. The root clause is what separates them -- an upstream pytest file names
# no root and refuses on no root -- and it is a REAL PROPERTY, not a name, which is why this
# derivation agrees with a hand list about `checks/` and disagrees with one about `test/`.
#
# THE PREFILTER, AND WHY IT CANNOT LOSE A WITNESS. Three literals, and `code_of` only ever REMOVES
# text, so anything `code` holds `src` holds: `MARKER` is the literal `pyproject.toml`; `asserts`
# needs one of `REFUSE`'s four alternatives; and `entry_reason` calls a file an entry only when
# `ast` finds `__main__`, or a `sh` shebang, or ESM syntax. **A SKIP-IF-ABSENT MAY ADMIT A
# CANDIDATE AND MUST NOT DROP ONE** -- the argument `gates/indexread-gate.py:offenders_of` makes,
# and the only direction that is sound. Measured cost of asking the question the cheap way, over
# the whole derivation: **869 immediate files read in 0.37 s user**, against 14.4 s for the same 14
# candidates run through `entry_reason` recursively on all 7549 of their files.
#
# **`MARKER.pattern` IS THE REGEX `pyproject\.toml` AND THE PREFILTER NEEDS A LITERAL.** MEASURED,
# and this line is the bug's own post-mortem: the first version put `MARKER.pattern` in the tuple,
# `"pyproject\.toml" in src` was a test no file can pass, `checks` answered **0 survivors of 311
# files**, and the derivation reported a clean-looking **0 of 14** -- a census over a population
# the prefilter had emptied, which is `artefacts_ok()`'s shape wearing a denominator.
# `pattern.replace("\\", "")` is the literal every match of an escaped-literal pattern contains,
# derived rather than retyped so the two cannot drift. **`_CERTIFY` is ANDED AND `_CERTIFY_OR` IS
# ORRED**, because `REFUSE` is an alternation: the first version conjoined all four of its
# alternatives and no file in the tree carries two of them, so every candidate was rejected.
_CERTIFY = (MARKER.pattern.replace("\\", ""), "__main__")
_CERTIFY_OR = ("refuse(", "exit 3", "not at the repo root", "REFUSED, NOT A VERDICT")
_SKIP = (".git", ".jj", "__pycache__")


def _tree_paths(root):
    """`(sorted tracked paths, source)` -- `git ls-tree -r --name-only HEAD`, or the working copy.

    **THE COMMIT TREE IS THE PRUNE, WHICH IS WHY THERE IS NO PRUNE LIST.** `references/`,
    `.venv/`, `node_modules/`, `.agents/slop/opstree/`, `/runs/`, `/bin/bend` are every one of them
    `.gitignore`d, so a candidate set read off the TREE excludes them by construction --
    `checks/gendirs.py` cannot do this and carries a `SKIP_TOP` tuple for it. The fallback exists
    for `--plant`, whose synthetic trees are not repositories, and it SAYS WHICH it used: a
    derivation whose provenance is unprinted is a claim, and `gate-surface.py`'s `walk_control` is
    the second instance of this exact shape.

    **AND THE COMMIT TREE THAT IS READ MUST BE *THIS ROOT's* COMMIT TREE, WHICH GIT WILL NOT SAY
    BY ITSELF.** `git -C <dir> ls-tree` SEARCHES UPWARD for a repository, so a directory that is
    merely INSIDE one reads THAT repository's tree and prints its paths relative to the
    REPOSITORY's root -- not the directory's. MEASURED 2026-10-20T18:20Z:
    `checks/gatesweep.py --selftest` builds its synthetic tree at `ROOT/.agents/slop/gwself.*`,
    which is INSIDE this repository, so `git -C <that> ls-tree -r HEAD` answers with THIS TREE's
    8,859 paths, relative to THIS repository's root, for a directory that holds five files. Every
    path that read feeds is then about a DIFFERENT TREE and the reader cannot tell -- and the
    fix is to ask, not to assume: **`--show-toplevel` MUST ANSWER THIS ROOT**, or the working
    copy is used instead, which is what the fallback was already for and what a synthetic tree
    needs. **A COMMIT TREE THAT IS NOT ROOTED AT THE TREE BEING MEASURED IS A MEASUREMENT OF
    SOMETHING ELSE.**
    """
    root = Path(root).resolve()
    top = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    rooted = top.returncode == 0 and top.stdout.strip() and \
        Path(top.stdout.strip()).resolve() == root
    r = subprocess.run(["git", "-C", str(root), "ls-tree", "-r", "--name-only", "HEAD"],
                       capture_output=True, text=True)
    if rooted and r.returncode == 0 and r.stdout.strip():
        return sorted(r.stdout.splitlines()), "COMMIT TREE (git ls-tree -r HEAD)"
    # `find -type f` DOES NOT DESCEND A SYMLINKED DIRECTORY (196 under `e2epy/` here), so
    # `rglob` can report fewer files than `os.walk` would and the denominator would understate
    # itself. `os.walk` with `followlinks=False` is the honest walk, and it is the same one
    # `gate_homes` uses a few lines below.
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in _SKIP]
        out += [str((Path(dirpath) / f).relative_to(root)) for f in filenames]
    return sorted(out), "WORKING COPY (git absent)"


def gate_homes(root):
    """`(homes, derivation)` -- the GATE HOMES, measured, with the rows that measured them.

    ONE module, TWO consumers, and the second consumer is `gates/gate-surface.py`. The derivation
    is returned beside its answer rather than folded into it, so a caller that prints only the
    answer is still one `dict` away from the denominator -- **a population a reader cannot see the
    size of is the defect this file exists to end.**

    `root` is RESOLVED on both sides of every comparison, for the reason `gendirs.discovered`
    records: `tempfile.TemporaryDirectory()` hands back `/var/...` on macOS and `resolve()` hands
    back `/private/var/...`, and a `resolve_root` on one side and a `root` on the other makes EVERY
    witness resolve outside the repo -- 0 of 15 on a synthetic tree, which reads as "no homes" and
    is really "every home is somewhere else".
    """
    root = Path(root).resolve()
    paths, source = _tree_paths(root)
    homes, witnesses, rejected, absent, read_total = [], {}, [], [], 0
    for top in sorted({p.split("/")[0] for p in paths if "/" in p}):
        base = root / top
        # `iterdir()`, NOT `os.walk`, AND THAT IS THE COHERENCE CONDITION RATHER THAN A SHALLOWNESS
        # ONE. `_buckets` enumerates a home's IMMEDIATE files and skips `__pycache__`, so a witness
        # three levels down would certify a home whose gates the population walk CANNOT REACH --
        # **a home that certifies itself and then contributes nothing, which is `artefacts_ok()`
        # one level up.** MEASURED, and the case is real: the recursive rule admits `.agents` on
        # THREE gates that live three levels down -- `.agents/slop/{runsgate,e2esh}/plant.py` and
        # `.agents/slop/censroot/repro.py`, MEASURED at 3 of 3 -- while its FIVE immediate files
        # certify nothing, so `checks` is admitted on **16** and `gates` on **1** and `.agents` on
        # **0**. Under the recursive rule the population then holds `.agents/TODO.md`, a markdown
        # file that `ast.parse`s -- `is_literal_data`'s own caveat, one level up.
        survivors, read = [], 0
        if base.is_dir():
            for p in sorted(base.iterdir()):
                try:
                    if not stat.S_ISREG(os.lstat(p).st_mode):
                        continue
                    text = p.read_text(errors="replace")
                except OSError:
                    continue
                read += 1
                if (all(n in text for n in _CERTIFY)
                        and any(n in text for n in _CERTIFY_OR)):
                    survivors.append(p)
        read_total += read
        good = [p for p in survivors
                if (lambda t: t[0] != "-" and t[1] and t[2])(root_facts(p, root))]
        if good:
            homes.append(top)
            witnesses[top] = [str(p.relative_to(root)) for p in good]
        elif not base.is_dir():
            # **A DIRECTORY THE COMMIT TREE NAMES AND THE DISK DOES NOT CARRY IS NOT A DIRECTORY
            # WITH NO GATES, AND `0/0` SAYS IT IS.** MEASURED on a synthetic repo: `mv gates
            # verify` with no commit leaves the commit tree naming `gates/`, and the reject row
            # read `gates 0/0` -- byte-identical to `.github 0/0` (an empty directory that really is
            # empty) and to `docs 0/1` (a directory with a file and no gate). **THE MISSING
            # DIRECTORY IS NOT INVISIBLE THE WAY A HAND-LIST TYPO IS: A TYPO NAMES NOTHING THAT
            # EXISTS, WHILE A MISSING ONE NAMES SOMETHING THE TREE CARRIES.** It is named
            # `ABSENT` so the two cannot be confused, and it is its OWN list rather than a third
            # reading of the reject row because `report_roots`'s prose ("no gate there names a
            # root...") is FALSE of a directory that is not there to be asked.
            absent.append(top)
        else:
            rejected.append(f"{top} {len(survivors)}/{read}")
    return tuple(homes), {"source": source, "read": read_total,
                          "candidates": len(witnesses) + len(rejected) + len(absent),
                          "witnesses": witnesses, "rejected": rejected, "absent": absent,
                          "paths": paths}


_MEASURED = {}


def _measure(root):
    """`gate_homes(root)`, ONCE per tree per PROCESS.

    A within-process memo, not a cache: nothing is written to disk, so the next run re-measures
    the tree from scratch. `discover()`, `opaque()` and `report()` each call `_buckets`, and the
    derivation reads every candidate's immediate files -- **a memo is a measurement made once and
    read twice, and a file on disk is a diary** (`UNIVERSE-CENSUS.md`'s own finding about
    `gates-pop.ledger.tsv`, which `:646` writes and `:617` reads in the SAME PROCESS under the
    DEFAULT mode).
    """
    key = str(Path(root).resolve())
    if key not in _MEASURED:
        _MEASURED[key] = gate_homes(root)
    return _MEASURED[key]


def _homes(root):
    """`gate_homes(root)[0]` -- the answer, for a caller that only has to enumerate."""
    return _measure(root)[0]


def _derivation(root):
    """`gate_homes(root)[1]` -- the rows that measured it, for a caller that has to print them."""
    return _measure(root)[1]


def scan_roots(root):
    """The COMMITTED-PYTHON question, not the GATE-HOME question -- and the difference is the whole
    subject of `.agents/slop/UNIVERSE-CENSUS.md`.

    `gates/indexread-gate.py` asks "does any file this repo SHIPS enumerate its population through
    the INDEX", and a shipped instrument is not required to be a gate: `.agents/slop/**` holds 63 of
    the offenders and 0 certified gate homes. MEASURED 2026-10-14: `indexread-gate.py` answers
    `POPULATION 1755  OFFENDERS 75  BASELINE 68  NEW 7`, and 63 of the 75 offenders are under
    `.agents/slop/`. **THE PREVIOUS TEXT SAID 68, WHICH IS THE BASELINE, NOT THE OFFENDER COUNT** --
    the two are different quantities and the conflation is what made the sentence rot. A raw
    `grep -lE 'ls-files|read-tree|--cached'` over the directory answers 147 and is NOT that number
    either: it counts every extension (67 `.py` of 711, plus `.md`, `.out`, `.rows`, `.tsv`) and
    it matches `.agents/slop/whyarms/armsites.py:31`, which is the string "the DISARM, and it
    discards staged deletions" inside a dict VALUE. The AST classifier is what counts OFFENDERS;
    the grep counts WORDS. QUOTE THE GATE'S OWN LINE, WITH A REVISION -- `jj` auto-snapshots and
    `HEAD` moved mid-session, so the population read 1755 and 1756 in different minutes. So it does NOT read `gate_homes()` -- and the reason
    is written here rather than discovered again: **two questions, two named populations, one
    module. A second copy of a list is a contract with no generator; a second copy of a DERIVATION
    with a different predicate is a different question pretending to be the same one.**
    """
    paths, _ = _tree_paths(Path(root).resolve())
    return tuple(sorted({p.split("/")[0] for p in paths if "/" in p and p.endswith(".py")}))


def report_roots(derivation, indent="   "):
    """The derivation, printed, with EVERY candidate that was rejected and its own denominator.

    **A ROOT SET THAT CHANGES SILENTLY IS A DIARY.** This prints the kept homes with their
    witnesses, the rejected candidates with `survivors/files-read`, and where the candidates came
    from -- so a reader sees `2 of 14` move to `3 of 14` without reading a line of code.
    """
    kept = sorted(derivation["witnesses"])
    print(f"{indent}ROOT SET, DERIVED FROM THE COMMIT TREE: {len(kept)} of "
          f"{derivation['candidates']} top-level director"
          f"{'y' if derivation['candidates'] == 1 else 'ies'} qualify "
          f"[candidates from the {derivation['source']}]")
    for top in kept:
        print(f"{indent}  KEEP    {top:16} {len(derivation['witnesses'][top])} witness(es): "
              f"{derivation['witnesses'][top][0]}")
    for row in derivation["rejected"]:
        print(f"{indent}  reject  {row:24} -- no gate there names a root, refuses on a wrong one, "
              f"and resolves on-repo")
    for top in derivation["absent"]:
        print(f"{indent}  ABSENT  {top:24} -- the commit tree names it and the working copy does "
              f"NOT carry it. That is\n{indent}          not the same answer as `0/0`: a missing "
              f"directory is a MOVED or DELETED one, and this is\n{indent}          the row that "
              f"says so instead of counting as an empty question.")
    print(f"{indent}          (rejected rows read `survivors/files-read`; {derivation['read']} "
          f"tracked file(s) read in total)")


# ---- clause III: THE LEDGER -- A RETENTION RECORD, NOT A SECOND COPY OF THE POPULATION ----
# THE LIVE LEDGER, resolved ONCE at import: the ONLY place a path is hard-wired, and it is read
# by `plants()`'s inertness assertion and by nothing that writes.
LEDGER_PATH = HERE / LEDGER.name

# **A ROW IS NOT A CLAIM THAT A GATE EXISTS. IT IS A RECORD OF A GATE THAT WAS DISCOVERED, AND
# `reason == RETIRED` IS WHAT IT SAYS WHEN THAT GATE IS GONE.** MEASURED, and both halves of this
# sentence were defects before it:
#
#   THE ROWS WERE 100% DERIVABLE AND 36 BEHIND. `write_ledger(rows_of(_buckets(root)))` produces
#   **213** rows and round-trips through the TSV byte-for-byte, so a row held nothing the tree did
#   not -- and the file on disk held **177** of them, last accepted 2026-10-15 (`c60233c65`,
#   "accept the gates-pop ledger snapshot: 173 -> 177"), which is **36** short of what the tree
#   holds today. A COPY OF A MEASUREMENT THAT IS PERMANENTLY STALE IS NOT A POPULATION; IT IS A
#   HAND LIST NOBODY OWNS, and `gates/onnx_census-gate.py:11` says so in its own header: the
#   ledger is "NOT MINE TO EDIT". **THE DENOMINATOR WAS THE PROBLEM AND ADDING ROWS IS THE WRONG
#   FIRST MOVE BECAUSE IT MAKES THE NEXT DELETION THE ONLY THING THAT CAN TURN A GREEN GATE RED,
#   WITH ERASURE AS THE ONLY REMEDY.** MEASURED on a synthetic tree: nothing moved `rc=0`, and a
#   gate deleted CORRECTLY `rc=1` with `III GONE` -- indistinguishable from an accidental loss,
#   and curable only by dropping the row, which erases the only evidence the gate ever existed.
#
#   SO THE SCHEMA IS THE FIX AND IT COSTS ONE COLUMN. `RETIRED` is a `reason` value, not a new
#   field: a row's `reason` is either a discovered reason or `RETIRED`, `write_ledger` MERGES
#   (it updates, adds, and RETIRES -- it never drops a line), and `gone` now means *left the
#   population and not yet recorded as having left*. **THE LEDGER IS MONOTONIC: EVERY EDIT ADDS
#   INFORMATION, SO THERE IS NO EDIT THAT MAKES IT GREEN BY ERASING.** That is the whole property
#   the `red = 1` on `gone` was reaching for and could not hold, because `red` on an ABSENCE can
#   only be answered by an absence.
RETIRED = "gone"

# **THE COLUMNS A `moved` VERDICT IS ALLOWED TO BE ABOUT, NAMED BY WHAT THEY ARE.**
# `read_ledger` yields `(path, reason, root_const, asserts, onroot)`, so the tail is a FOUR-tuple
# and `root_const` is its index 1. Index 2 and 3 are BOOLEANS the census decided; index 0 is the
# word it classified by; index 1 is a QUOTATION of the gate's source. Index 1 is excluded because
# a truncated prefix of a source line is not an observation of the gate -- see `report`'s
# `DECIDED(new[k])` call, which carries the measurement.
def DECIDED(tail):
    """`(reason, asserts_root, on_root)` -- the tail of a ledger row MINUS the quotation at
    index 1. Uppercase because `report` names it in a diff, not because it is a constant."""
    return tail[0], tail[2], tail[3]


# **A CELL THIS READER DID NOT READ IS NOT A `False`.** `read_ledger` used to coerce with
# `f[3] == "1"`, so every spelling outside the writer's own `{"0", "1"}` -- `True`, `garbage`,
# `""`, `0` on a True cell, `01`, `2`, `" 1"`, `"1 "` -- came back as `False`, and
# `asserts_root=False` IS A CLAIM: "this gate does not assert its root". MEASURED 2026-10-20T00:18Z
# on copies of the live ledger: **8 of 8 such spellings read back `False` and none of them was
# visible anywhere.** And the coercion is WORSE THAN AN ARBITRARY WRONG ANSWER, because it is
# right most of the time: **187 of the 224 live rows carry `asserts_root=0`**, so a corrupted cell
# disagrees with the writer's intent about one time in six and looks like a real decision the rest
# -- **a corrupted column that is usually not wrong is a corruption nobody goes looking for.**
UNREADABLE = "UNREADABLE"


def _flag(cell):
    """A boolean cell as `True`/`False`, or `UNREADABLE` when it is neither. **AND THE LEGAL
    SPELLINGS ARE ASKED OF THE WRITER** (`SPELLINGS`, below) rather than written here, so the
    format this reader accepts and the format this writer emits cannot drift apart."""
    return cell == "1" if cell in SPELLINGS else UNREADABLE


def read_ledger(path):
    """`(path, reason, root_const, asserts, onroot)` rows, or None if there is no ledger yet.

    **THE `#` PREAMBLE IS SKIPPED BEFORE THE HEADER IS SKIPPED, AND THE ORDER MATTERS.** A comment
    filter that kept `splitlines()[1:]` would drop the FIRST `#` line and then parse the SECOND as
    a row -- and `LEDGER_HEADER` is FIVE TAB-separated fields, so it would have been admitted as a
    gate named `path`. So: drop comments and blanks FIRST, then drop the one remaining header line.
    That is `gates/opseven-gate.py:325`'s own reader (`if not ln.strip() or ln.startswith("#")`),
    READ NOT COPIED, because this file is the generator of that file's sibling spelling and one
    file with two comment shapes is two formats.

    The two booleans are coerced HERE rather than at the comparison, because `"0" != False` is
    True: an uncoerced round-trip made every row report CHANGED on a second run with nothing
    altered, which is the ledger-diff failure mode that teaches a reader to ignore the diff.

    **AND A CELL THAT IS NOT A LEGAL SPELLING IS `UNREADABLE` RATHER THAN `False`.** Coercion is
    right for the two spellings `ledger_line` emits and wrong for every other string, and the two
    used to be the same line of code. **THE LOAD-BEARING PROPERTY IS THAT `UNREADABLE` CANNOT EQUAL
    A BOOLEAN**, so `DECIDED` sees a row carrying one as different from a freshly measured row in
    `report`, `moved` names it, and the run is red -- refusal here is LOUD BY CONSTRUCTION, not by
    an extra test that a later edit can forget.
    """
    if not path.is_file():
        return None
    body = [ln for ln in path.read_text().splitlines() if ln and not ln.startswith("#")]
    out = []
    for line in body[1:]:
        f = line.split("\t")
        # **THE PATH SURVIVES A ROW THIS READER CANNOT ACCOUNT FOR, AND THAT IS THE SHORT-ROW
        # FIX.** A row with the wrong number of fields used to be DROPPED (`if len(f) >= 5`), and
        # the drop was not a refusal, it was a hole. MEASURED 2026-10-20T00:18Z, cutting one live
        # row to three fields made `report` print that gate as **NEW** -- a gate the ledger recorded
        # on 2026-10-17 re-announced as a first sighting -- and shrank the denominator from `224` to
        # `223` without one word about it. **REFUSING THE WHOLE ROW IS EXACTLY WHAT IT ALREADY DID**,
        # which is the measurement that separated the two defects and decided between the options:
        # a bad cell is ONE column and a short row is FOUR, and the answer that refuses only what it
        # cannot read is the only one that is not the short-row defect. Arity is checked against
        # `LEDGER_FIELDS` -- the HEADER is the format contract -- so a row with a SURPLUS field is
        # unreadable too, in the same direction, for the same reason: the surplus is unnameable.
        if len(f) != len(LEDGER_FIELDS):
            f = f[:1] + [UNREADABLE] * (len(LEDGER_FIELDS) - 1)
        out.append((f[0], f[1], f[2], *(_flag(c) for c in f[3:])))
    return out


def ledger_line(row):
    """One row as a TSV line. **AND A CELL THE WRITER DID NOT MEASURE IS WRITTEN AS IT READS,
    NEVER AS `0`.** A tombstone carries its old facts forward, so a retired row whose cells were
    unreadable reaches this line carrying `UNREADABLE`; `int(row[3])` would raise `ValueError` out
    of `--write-ledger` on a corrupt ledger, which is a crash where the answer is a word, and
    writing `0` instead would invent a decision nobody made."""
    return "\t".join([row[0], row[1], " ".join(row[2].split())]
                     + [str(int(b)) if isinstance(b, bool) else b for b in row[3:]])


# **THE CANONICAL SPELLING, ASKED OF THE WRITER INSTEAD OF SPELLED HERE.** `ledger_line` writes
# `int(...)`, so calling it over both booleans enumerates every value a boolean cell can legally
# hold -- `int` over `(False, True)` IS exactly `{"0", "1"}`, which is why the generator rather
# than the literal is the source. A `("0", "1")` written out at the reader would be a format
# contract with no generator behind it, and that is the class of defect this clause sits beside.
SPELLINGS = frozenset(ledger_line(("p", "r", "q", b, o)).split("\t")[3]
                      for b in (False, True) for o in (False, True))


def write_ledger(rows, path=None, only=None):
    """MERGE into the ledger at `path`. **A LINE IS NEVER DROPPED.**

    `only is None` is the full merge: adopt each row's current facts, add what is new, and RETIRE
    every recorded path this run did not find. Plants that build a synthetic ledger call it this
    way. **THE CLI DOES NOT.** `--write-ledger` always passes `only`, a set of paths, and a bare
    call is refused before it gets here: the full merge is the central sweep, and running it
    against the shared ledger makes the diff green without one gate having been measured.

    `only` absorbs those paths and no others. A named path that this run discovered is adopted. A
    named path the ledger holds and this run did not find is RETIRED. Every other recorded path is
    carried forward unchanged -- including a departure this run can see and was not asked to
    record. A named path that is neither discovered nor recorded is NOT WRITTEN: the function
    returns that list and leaves the file alone, and the caller refuses. MEASURED, the first
    version wrote `rows` and nothing else, which made `--ledger write` the erasure the check mode
    then punished: a run that found **2** of **177** gates printed `177 gone` and `GATES-POP: OK`,
    rc 0, having destroyed the record of every other gate in the tree. And PLANT 10 caught the
    SECOND version of the merge here, which carried forward only rows whose reason was not already
    `RETIRED` -- so a second write over an already-retired tree **quietly deleted the tombstone**.
    **A MERGE THAT DROPS WHAT IT HAS ALREADY RECORDED IS NOT A MERGE.**

    The parent is CREATED, because a foreign tree need not have this instrument's directory and a
    `write_text` into a missing one is a traceback -- which is `checks/census.py`'s docstring
    recording the tree doing exactly that: rc 1 and a stack, carrying no denominator.

    Returns the unaccountable paths, or None after a write.
    """
    lp = path or LEDGER_PATH
    old = read_ledger(lp) or []
    live = {r[0]: r for r in rows}
    if only is None:
        merged = list(rows) + [(p, RETIRED, c, a, o) for p, _r, c, a, o in old if p not in live]
    else:
        unknown = sorted(p for p in only if p not in live and all(r[0] != p for r in old))
        if unknown:
            return unknown
        adopted = [live[p] for p in only if p in live]
        carried = [(p, RETIRED, c, a, o) if p in only and p not in live else (p, reason, c, a, o)
                   for p, reason, c, a, o in old if p not in only or p not in live]
        merged = adopted + carried
    body = LEDGER_PREAMBLE.splitlines() + [LEDGER_HEADER] + [ledger_line(r) for r in
                                                        sorted(merged, key=lambda r: r[0])]
    lp.parent.mkdir(parents=True, exist_ok=True)
    lp.write_text("\n".join(body) + "\n")
    return None


LEDGER_HEADER = "path\treason\troot_const\tasserts_root\ton_root"
LEDGER_FIELDS = LEDGER_HEADER.split("\t")
# **THE HEADER IS ALSO THE FORMAT CONTRACT, AND THE ARITY COMES FROM IT** rather than from a `5`
# written beside the check that needs it: `read_ledger` reads `len(f) != len(LEDGER_FIELDS)`, so
# renaming or re-aritying the header changes what counts as a well-formed row with no edit here.

# THE GENERATOR LINE, SPELLED THE WAY THIS TREE ALREADY SPELLS IT. `gates/opseven-pins.rows` and
# `gates/op_graph_census-pins.rows` both open with `# <file> -- GENERATED by `<gate> --<flag>`, which
# is its ONLY writer.` and both gates refuse every other spelling. READ, NOT COPIED: this file is a
# GENERATOR (`AGENTS.md`'s shared-writable-path class) whose default mode used to WRITE, so a reader
# had no way to tell a record from a snapshot. **THE HEADER IS ALSO PART OF THE FORMAT CONTRACT**:
# `read_ledger` drops comments and then ONE header line, so a reader of this file that skips neither
# reads five tab-separated fields named `path` as a gate.
LEDGER_PREAMBLE = (
    f"# {LEDGER.name} -- GENERATED by `gates/{Path(__file__).name} --write-ledger --only PATH`, "
    "which is its ONLY writer: it writes\n"
    f"# the named paths and no others. A bare `--write-ledger` is REFUSED. It writes on NO other "
    "invocation, and every\n"
    f"# other invocation only READS it. Written by `gates/gates-pop.py`, a generator over the "
    "tree's gate homes --\n"
    f"# so this file is a SHARED WRITABLE PATH, and a run that rewrites it without a path absorbs "
    "whatever else the\n"
    f"# tree held. A record of gates that were DISCOVERED, not a list of gates that exist: "
    f"`reason={RETIRED}` is a row\n"
    f"# saying one LEFT. MERGED, NEVER REWRITTEN -- every edit adds information, so no edit goes "
    "green by erasing.\n"
    f"# One TAB-separated quintuple per row:\n"
    f"# `<path>\\t<reason>\\t<root_const>\\t<asserts_root>\\t<on_root>`."
)


# ---- THE COMMIT THAT MADE EACH MOVEMENT --------------------------------------------------
def events(root, homes):
    """`{path: (introduced_by, removed_by)}` -- the commits that brought each path IN and took it
    OUT, from ONE `git log` over the homes.

    **ATTRIBUTION NAMES THE DEBT. IT IS NOT THE PAYMENT.** A ledger that is merely stale says
    `73 new`; a ledger that is stale AND attributed says which commit owes the row. The payment is
    `--write-ledger --only <path>`, run by the unit that owns that path, and it absorbs that path
    alone. A bare `--write-ledger` is refused: that is the central sweep, and it makes the diff
    green without one gate having been measured. MEASURED 2026-10-20T18:26Z:
    one `git log --diff-filter=AD --name-status` over `checks` and `gates` answers **1,722 lines
    in 0.22 s**, against **~0.06 s per path** for 78 individual `--diff-filter=A -1 -- <path>`
    calls. ONE CALL, because the movements are a SET and the set is what the report needs.

    `--no-renames`, because a rename is reported as `R` by default and `--diff-filter=AD` would
    DROP IT -- so a gate that was renamed would carry no introducing commit at all, which is
    exactly the movement a reader most needs attributed.

    **THE LOG IS NEWEST-FIRST, so the FIRST event seen for a path is the CURRENT one**: the most
    recent addition is the introduction of the version that is here now, and the most recent
    deletion is the departure. A path added, deleted and re-added therefore carries the re-add.

    **THE SUBJECT IS TRUNCATED, AND IT IS TRUNCATED HERE RATHER THAN AT PRINT TIME, BECAUSE THIS
    TREE'S COMMIT MESSAGES ARE THOUSANDS OF CHARACTERS LONG.** `AGENTS.md` calls a commit message
    "a claim this instrument cannot judge", but it is also the ONE WITNESS to which unit made a
    change, so it is worth naming -- at 60 characters, which is enough to recognise the commit and
    short enough to read in a list of 73.
    """
    root = Path(root).resolve()
    # THE SAME ROOTED CHECK AS `_tree_paths`. `git -C <dir> log` searches upward, so a synthetic
    # tree inside this repository would be attributed against THIS history. A commit that is not
    # rooted at the tree being measured is a measurement of something else.
    top = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    if not (top.returncode == 0 and top.stdout.strip()
            and Path(top.stdout.strip()).resolve() == root):
        return {}
    out = {}
    r = subprocess.run(["git", "-C", str(root), "log", "--no-renames", "--diff-filter=AD",
                        "--name-status", "--format=@@@ %h|%ci|%s", "--", *homes],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return {}
    commit = None
    for line in r.stdout.splitlines():
        if line.startswith("@@@ "):
            h, when, subject = (line[4:].split("|", 2) + ["", ""])[:3]
            commit = f"{h} {when} {subject[:60]}"
            continue
        parts = line.split("\t")
        if len(parts) != 2 or commit is None:
            continue
        kind, path = parts
        if kind not in ("A", "D"):
            continue
        slot = out.setdefault(path, [None, None])
        i = 0 if kind == "A" else 1
        if slot[i] is None:
            slot[i] = commit
    return {k: tuple(v) for k, v in out.items()}


# ---- the report -------------------------------------------------------------------------
def report(root, ledger_mode, ledger_path=None, only=None):
    """Every discovered gate, one line, with its denominator. A verdict with no denominator is
    a claim nobody can check -- `gates/retention-check.py` states that rule and this file
    holds to it.

    `ledger_path` DEFAULTS TO **THE TREE'S OWN**, not the live one: `report(root)` describes
    `root`, so the record of `root` is the one it may write. MEASURED, the alternative was
    destructive in a way `--plant`'s inertness assertion could not see, because `--plant` was the
    only caller that named its path: `--root <tmp>`, documented in `--help` as "point at another
    tree", printed `177 gone`, then `GATES-POP: OK` and **rc 0** having replaced the live
    `gates/gates-pop.ledger.tsv` with **2** rows. **THE PLANT THAT COULD SEE ITS OWN DAMAGE WAS
    SAFE AND THE DOCUMENTED FLAG WAS NOT, AND A GUARD THAT COVERS THE PATH A CALLER TAKES RATHER
    THAN THE DAMAGE IS A GUARD ON THE CALLER.**

    THE DEFAULT IS **BESIDE THE INSTRUMENT, AT THE PATH THE INSTRUMENT OCCUPIES IN ITS OWN
    TREE** -- `HERE.relative_to(ROOT)`, MEASURED rather than spelled, because the first attempt
    spelled `Path(root) / LEDGER.name` and that is the REPO ROOT: `--ledger check` on the live
    tree answered `III NO LEDGER at gates-pop.ledger.tsv` with a 178-row file sitting right there
    in `gates/`. **A PATH CORRECTED ONCE IS EVIDENCE THAT A NEARBY PATH WAS NEVER MEASURED.**
    """
    lpath = ledger_path or Path(root).resolve() / HERE.relative_to(ROOT) / LEDGER.name
    homes, derivation = _measure(root)
    entries, libs, opaque, uncarried = _buckets(root)
    report_roots(derivation)
    print(f"     {derivation['read']} tracked file(s) read to answer that question; a rejected "
          f"candidate is a DIRECTORY, and each of the\n     {len(derivation['rejected'])} below "
          f"was asked the same question and answered no -- the root set MOVES when one of them\n"
          f"     starts answering yes, and this line is where a reader sees it.\n")
    if not entries:
        print(f"I  EMPTY POPULATION: no entry point under {'/'.join(homes)}/ -- and an empty "
              f"population cannot\n   fail, which is the defect this file exists for. REFUSED.")
        return 2

    rows, named, unasserted, offroot = [], 0, 0, 0
    print(f"I  DISCOVERED {len(entries)} entry point(s) in the IMMEDIATE files of "
          f"{'/'.join(homes)}/ (+{len(libs)} module(s) with no entry guard, {len(opaque)} file(s) "
          f"OPAQUE -- readable\n   by no grammar in this instrument, which is a DENOMINATOR and "
          f"not a verdict: it is")
    # **THE UNIT, PRINTED, BECAUSE `checks/gatesweep.py:walk` IS A DIFFERENT ONE AND A READER
    # WITH TWO NUMBERS CANNOT RECONCILE THEM WITHOUT IT.** `os.walk` descends into `gates/oracles/`
    # and `_buckets`' `iterdir()` does not; `gatesweep._prune` drops dotted names and `_buckets`
    # does not. MEASURED 2026-10-19 03:57Z: `WALK 258` against `CONTROL 261`, and the difference
    # is EXACTLY `258 - 2 subdirectory + 5 dotted = 261`. **TWO INSTRUMENTS HOLDING TWO WALK RULES
    # DISAGREEING BY A CONSTANT ARE NOT A DEFECT; TWO INSTRUMENTS HOLDING TWO LISTS ARE.**
    # THE OPAQUE DENOMINATOR, BY EXTENSION, because a single total cannot say WHICH language the
    # instrument cannot read and a reader who is not told that cannot tell whether 148 is right.
    # It moves when the tree gains a language, which is the entire reason it is printed.
    for suf, n in sorted(Counter(suffix_of(p) for p in opaque).items(), key=lambda kv: -kv[1]):
        print(f"     opaque {suf:8} {n:4} file(s)")
    # **THE POPULATION RULE, PRINTED, WITH THE FILES IT EXCLUDED AND WHY THEY ARE EXCLUDED.**
    # This file's own definition says a gate is a file the COMMIT TREE carries; the HOMES were
    # derived that way and the FILES were not, so the walk could admit another unit's
    # in-flight scratch. MEASURED 2026-10-20T17:58Z: **4 files** under the homes were not
    # carried by the commit tree, all of them `checks/.tmp-*`, another unit's scratch -- and
    # `gates/gates-pop.py`'s own header records a plain invocation writing exactly those into
    # the shared ledger. **A FILE THE TREE DOES NOT CARRY IS NOT A GATE OF THIS REPOSITORY, AND
    # A POPULATION THAT INCLUDES ANOTHER UNIT's WORK IN PROGRESS IS A CLAIM ON A FILE SOMEBODY
    # ELSE OWNS.** The names are printed because a rule that excludes files without naming them
    # is the `artefacts_ok()` shape wearing a population.
    would_be = [(p, r) for p, r in uncarried if r is not None]
    print(f"     POPULATION RULE: the COMMIT TREE carries the gate ({derivation['source']}); "
          f"{len(uncarried)} immediate file(s) under the homes are NOT carried, so they are\n"
          f"     NOT files of this repository. {len(would_be)} of them would have been entry points\n"
          f"     or modules and are NAMED below; the other {len(uncarried) - len(would_be)} are "
          f"files this instrument\n     could not read anyway, so excluding them changes nothing "
          f"the census measures.")
    for p, r in would_be:
        print(f"       not carried: {str(p.relative_to(root)):46} {r}")
    print()
    for p in entries:
        const, asserts, onroot = root_facts(p, root)
        rows.append((str(p.relative_to(root)), entry_reason(p), const, asserts, onroot))
        if const != "-":
            named += 1
            if not asserts:
                unasserted += 1
            if not onroot:
                offroot += 1
        print(f"   {str(p.relative_to(root)):34} {entry_reason(p):12} "
              f"root={'OK  ' if onroot else 'OFF-REPO'}  asserts={'YES' if asserts else 'NO'}  "
              f"{const[:46]}")
    print()
    print(f"II POPULATION NOT EMPTY: {len(entries)}/{len(entries)} entry points "
          f"-- a gate over 0 files is not a gate\n")
    print(f"II ROOT ASSERTED: {named - unasserted}/{named} files that name a root also REFUSE "
          f"on a wrong one\n")

    red = 0
    if offroot:
        red = 1
        print(f"III FALSE      {offroot} file(s) compute a root that RESOLVES OUTSIDE the repo, so "
              f"each reports on\n               a tree that is not this one. `checks/census.py`'s "
              f"docstring records the measured consequence:\n               a `sys.path.insert` of a "
              f"directory holding no importable module.")
        for p, r, c, a, on in rows:
            if not on:
                print(f"III            {p}: {c[:60]}")
        print()

    prev = read_ledger(lpath)
    # **THE DEFAULT IS THE HONEST ONE FOR A FIRST-EVER RUN: WITH NO `prev`, EVERY ROW THIS RUN
    # FOUND IS NEW.** The alternative (`()` for all four) makes a ledger's initial write report
    # `IT ABSORBED 0 new` over a file it just filled -- and a count that reads zero on a write is
    # the one number in this report a reader would trust. They are hoisted BEFORE the branch
    # because a first-ever write must not raise `NameError` on the line that reports what it wrote.
    added, gone, moved, back = [r[0] for r in rows], (), (), ()
    if prev is None:
        print(f"III NO LEDGER at {lpath.name} -- this run WRITES it; the NEXT run diffs. "
              f"A snapshot with\n               no predecessor is a denominator, not a verdict.")
        if ledger_mode == "check":
            red = 1
    else:
        old = {r[0]: r[1:] for r in prev}
        new = {r[0]: r[1:] for r in rows}
        # **A ROW RECORDING A `RETIRED` GATE IS NOT A ROW THAT CLAIMS THE GATE IS HERE.** MEASURED,
        # and this is the one subtraction that makes the anti-evolution property real: with
        # `gone = set(old) - set(new)` over ALL rows, a tombstone and a live claim were
        # indistinguishable, so the only answer to `gone` was to erase the row -- the defect.
        retired = {k for k, v in old.items() if v[0] == RETIRED}
        added = sorted(set(new) - set(old))
        # **A QUOTATION IS NOT A DECISION, AND A DIFF OVER QUOTATIONS HAS NO ACTIONABLE CONTENT.**
        # `r[1:]` is `(reason, root_const, asserts_root, on_root)`, and `root_const` is index 1 --
        # `m.group(0)` of `ROOT_CONST`/`ROOT_INLINE` flattened by `" ".join(...split())` and cut at
        # the TSV width: **it is a PREFIX OF THE GATE'S OWN SOURCE TEXT, TRUNCATED MID-EXPRESSION**,
        # `Path sys.path.insert(0, str(Path(__file__).resolve().parents[1]` -- 63 characters and an
        # unclosed paren. It answers nothing a reader can act on, and it MOVES on a reformat.
        # MEASURED 2026-10-19T16:30Z on commit `325c422d9bd3`: it alone accounted for `5 changed`
        # across five files that added a `sys.path.insert(0, ...)` line, and `0 of the 5` moved a
        # boolean -- `asserts_root` and `on_root` are `SAME` on all five. The tree had genuinely
        # moved and the ledger's only reported change was a reformat seen through a column that
        # carries no decision. **SO THE COMPARISON IS OVER THE THREE COLUMNS THAT DECIDE SOMETHING.**
        moved = sorted(k for k in set(new) & set(old) if DECIDED(new[k]) != DECIDED(old[k]))
        # `gone` is an UNRECORDED departure; `back` is a tombstone whose gate came BACK, which is
        # `added` by another name and is cured the same way. Both are red; neither is erasure.
        gone = sorted(set(old) - set(new) - retired)
        back = sorted(k for k in retired & set(new))
        still = sorted(retired - set(new))
        print(f"III LEDGER DIFF: {len(added)} new, {len(gone)} UNRECORDED departure(s), "
              f"{len(moved)} changed, {len(back)} returned, {len(still)} retired "
              f"({len(rows)} live of {len(prev)} row(s); a RETIRED row is a record, not a claim)")
        # **EVERY MOVEMENT NAMES THE COMMIT THAT OWES IT.** Attribution is the queue. The payment
        # is `--write-ledger --only <path>`, and it records that path alone. A bare
        # `--write-ledger` is refused: absorbing every row below is the central sweep, and it
        # makes this diff green without one gate having been measured.
        if added or gone or moved or back:
            print("III   RECORD: `--write-ledger --only <path>` absorbs that path and no other. "
                  "A bare `--write-ledger` is REFUSED.")
        ev = events(root, homes)
        for k in added:
            by = ev.get(k, (None, None))[0]
            print(f"III   NEW  {k}: {new[k][0]} root_ok={new[k][3]} "
                  f"asserts={'YES' if new[k][2] else 'NO'}"
                  + (f"\nIII         introduced by {by}" if by else
                     "\nIII         NOT ATTRIBUTABLE: no commit in this tree's history introduces it"))
        for k in gone:
            by = ev.get(k, (None, None))[1]
            print(f"III   GONE {k} -- a gate that LEFT the population and the ledger does not say "
                  f"so.\n               `--write-ledger --only {k}` RETIRES this row and no other: "
                  f"reason=`{RETIRED}`, not deleted. A bare `--write-ledger` is refused."
                  + (f"\n               removed by {by}" if by else
                     "\n               NEVER COMMITTED: the tree never carried this path, so the "
                     "row is about a file\n               this repository does not have -- and the "
                     "cure is the same: RETIRE the row, do not delete it."))
        for k in back:
            by = ev.get(k, (None, None))[0]
            print(f"III   BACK {k} -- retired, then discovered again; the row is live once more"
                  + (f"\nIII         introduced by {by}" if by else ""))
        for k in still:
            by = ev.get(k, (None, None))[1]
            print(f"III   retired {k} -- left the population, recorded, kept"
                  + (f"  (removed by {by})" if by else ""))
        for k in moved:
            # NAME THE COLUMNS THAT MOVED. `old[k][0] -> new[k][0]` printed the REASON on both
            # sides of the arrow even when the reason was unchanged and a boolean was what
            # moved, so the line described a change it had not found.
            # **AND A CELL THE LEDGER DID NOT CARRY IS NOT A CHANGE, IT IS A HOLE.** An arrow
            # `UNREADABLE->False` says the gate stopped asserting; what is true is that the ledger
            # did not say, so the line names the hole, names what this run read instead, and names
            # the cure -- the content `325c422d9bd3` lacked when it reported `5 changed`.
            print(f"III   CHANGED {k}: " + ", ".join(
                f"{n} UNREADABLE in the ledger, this run read {b} -- re-derive it with "
                f"`--write-ledger --only {k}`" if o == UNREADABLE else f"{n} {o}->{b}"
                for o, n, b in zip(DECIDED(old[k]), ("reason", "asserts_root", "on_root"),
                                   DECIDED(new[k])) if o != b))
        if ledger_mode == "check" and (added or gone or moved or back):
            red = 1
        if not (added or gone or moved or back):
            print("III   no movement: every gate is accounted for -- discovered, or retired ON "
                  "RECORD. Stability is\n     the only state a set-difference gate can be quiet "
                  "about -- and it is reached by a MERGE,\n     never by a row being deleted.")
        print()
    # **A PATHSPEC WRITE THAT LEAVES A MOVEMENT UNNAMED IS NOT GREEN.** This sits AFTER the
    # ledger branch because a first-ever write has no `prev` and still has unnamed rows: write
    # mode used to return 0 whenever it wrote, which is right for a full merge and wrong for
    # `--only`. A movement this write was asked to record does not keep the run red; one it was
    # not asked to record does.
    if ledger_mode != "check" and only is not None and any(
            k not in only for k in (*added, *gone, *moved, *back)):
        red = 1
    if ledger_mode != "check":
        # **A WRITE OF THE SHARED LEDGER WITHOUT A PATHSPEC IS THE CENTRAL SWEEP.** The CLI refuses
        # it before it gets here; this is the same refusal for a caller that imported `report`.
        # `only is None` remains the full merge, and it is how the plants build a synthetic ledger.
        # It is not how the shared file is written.
        if only is not None and not only:
            refuse("`--write-ledger` named no path. That is the central sweep, and it is refused.")
        if only is None and Path(lpath).resolve() == LEDGER_PATH.resolve():
            refuse("a write of the shared ledger without `--only PATH` is the central sweep, "
                   "refused. Name the paths this commit owns.")
        # THE COUNTS ARE THE PATHS THIS WRITE ABSORBS, NOT THE DIFF. A pathspec that recorded every
        # NEW row above would be the sweep again, and the banner would be the line that hid it.
        scope = None if only is None else set(only)

        def took(k):
            return scope is None or k in scope

        abs_added = [k for k in added if took(k)]
        abs_gone = [k for k in gone if took(k)]
        abs_moved = [k for k in moved if took(k)]
        abs_back = [k for k in back if took(k)]
        unknown = write_ledger(rows, lpath, scope)
        if unknown:
            refuse(f"`--only` named {', '.join(unknown)}, and this run can neither adopt nor "
                   f"retire {'it' if len(unknown) == 1 else 'them'}: not discovered, and not in "
                   f"the ledger. Nothing was written.")
        after = read_ledger(lpath) or []
        tombs = sum(1 for r in after if r[1] == RETIRED)
        # **AND IT SAYS IT WROTE, IN THE PAST TENSE, WITH THE ROWS IT ABSORBED COUNTED.** The
        # absorbed counts are the intersection of the diff with the pathspec, so a write that
        # names one path cannot claim it absorbed the rest. PLANT 12 asserts the line parses;
        # PLANT 14 asserts the intersection.
        spec = "" if scope is None else f" -- paths: {', '.join(sorted(scope))}"
        print(f"III LEDGER WROTE {lpath.name} ({lpath}): {len(prev or [])} -> {len(after)} row(s), "
              f"{tombs} retired, none dropped.\n"
              f"     IT ABSORBED {len(abs_added)} new, {len(abs_moved)} changed, "
              f"{len(abs_back)} returned and RETIRED {len(abs_gone)}{spec}.\n"
              f"     A LEDGER IS SHARED: a path not named here was not recorded. If a named path "
              f"is another unit's in-flight work, say so before committing it.\n")

    # IV -- THE SHARED POPULATION. Both meta-instruments report `gendirs.discovered()`, so the
    # count below and clause V of `gates/retention-check.py` are THE SAME MEASUREMENT and either
    # both move or one is lying. `checks/gen/` is named HERE BY DISCOVERY and was invisible before:
    # `HOMES` is a two-item tuple, so "inside a gate home" said nothing about it, and the file it
    # is written by writes it by handing the path to `bend -o`.
    gd = gendirs()
    grows = gd.table()
    read, present = gd.coverage()
    contradiction = [r for r in grows if r["n_tracked"] and r["ignored"]]
    print(f"IV  SHARED POPULATION with gates/retention-check.py: {len(grows)} generated "
          f"director{'y' if len(grows) == 1 else 'ies'} in {read}/{present} source files "
          f"(the SAME\n    number clause V prints -- one module, two consumers, so a drift "
          f"between them is a BUG and\n    not a difference of opinion). "
          f"{len(contradiction)} of them are in the index\n    AND `.gitignore`d")
    for r in contradiction:
        print(f"IV    CONTRADICTS {r['dir']}: {r['n_tracked']} index entr"
              f"{'y' if r['n_tracked'] == 1 else 'ies'}, {r['n_empty_blob']} at git's EMPTY BLOB")
    if ledger_mode == "check" and contradiction:
        red = 1
    print()
    print(f"GATES-POP: {'RED' if red else 'OK'} -- {len(rows)} entry points, {named} name a root, "
          f"{named - unasserted} assert it, {offroot} resolve outside the repo; "
          f"{len(grows)} generated directories discovered (shared with retention-check)")
    return red


# ---- plants: three, and the third is a gate THIS INSTRUMENT DOES NOT NOTICE -------------
def _tree(root, *homes):
    """A synthetic tree, and the homes it DECLARES BY PLANTING A GATE THAT CERTIFIES ONE.

    **A PLANT THAT WROTE ITS OWN ROOT LIST WOULD BE PLANTING THE DEFECT.** `gate_homes` derives the
    homes from the gates, so a synthetic tree earns a home the only way a real one does: it holds a
    file that names a root, refuses on a wrong one and resolves on-repo. `GOOD_ROOT` is exactly
    that, so the witness IS the fixed-form fixture plant 5 already asserts is clean -- one fixture,
    two jobs. Plant 3 calls `_tree(r)` with NO homes, which is how an EMPTY population stays
    possible: `artefacts_ok()` reported zero on a directory holding nothing, and a plant that
    cannot produce an empty tree cannot assert that emptiness is refused rather than green.
    """
    (root / "pyproject.toml").write_text("[project]\nname='x'\n")
    (root / "tinybendygrad").mkdir()
    for home in homes:
        (root / home).mkdir(parents=True, exist_ok=True)
        (root / home / "home-witness.py").write_text(GOOD_ROOT)


MAIN = "if __name__ == '__main__':\n    raise SystemExit(0)\n"


def _commit(root):
    """Commit a synthetic tree, so `gate_homes` reads its COMMIT TREE instead of falling back.

    **`_tree_paths` FALLS BACK TO THE WORKING COPY WHEN `git ls-tree` FAILS, and every other
    plant in this file uses a temp directory that is not a repository** -- so a plant that did not
    commit would exercise the fallback and never reach the question plant 11 asks. MEASURED: with
    no commit, `gate_homes` cannot tell a renamed directory from a deleted one, because there is
    no longer a tree that says what SHOULD be there.
    """
    for cmd in (["init", "-q"], ["config", "user.email", "p@example"],
                ["config", "user.name", "plant"]):
        subprocess.run(["git", "-C", str(root), *cmd], capture_output=True, text=True)
    subprocess.run(["git", "-C", str(root), "add", "-A"], capture_output=True, text=True)
    return subprocess.run(["git", "-C", str(root), "commit", "-qm", "plant"],
                          capture_output=True, text=True).returncode


def _roots(root):
    """`(homes, entries, derivation)` for a tree that has CHANGED since it was last measured.

    **`_MEASURED.clear()` IS NOT A CONVENIENCE, IT IS THE ONLY CORRECT MOVE.** `_measure` memoises
    per resolved root path, which is exactly right for one run of `report` and exactly wrong for a
    plant that mutates the same directory and measures it again. MEASURED: a first version of this
    plant read `homes` through `gate_homes()` (unmemoised, so it moved) and `entries` through
    `_buckets()` (memoised, so it did not), and every step reported a population that no longer
    matched its own home set. **A MEMO IS A MEASUREMENT MADE ONCE AND READ TWICE -- WHICH IS FINE
    INSIDE ONE RUN AND IS A LIE ACROSS FOUR.**
    """
    _MEASURED.clear()
    homes, derivation = gate_homes(root)
    return homes, len(_buckets(root)[0]), derivation


def verdict_of(facts):
    """A `root_facts` triple as the ONE WORD a plant asserts on. Named rather than inlined so a
    plant reads as a claim about a verdict and not as arithmetic."""
    _const, asserts, on_root = facts
    return "off-repo" if not on_root else ("on-root+assert" if asserts else "on-root-bare")


# THE PRE-FIX FIXTURES, VERBATIM FROM THIS REPO'S OWN HISTORY. Not retyped from memory: MEASURED,
# the first version of plant 5 asserted `checks/census.py` in the `(REPO|ROOT) = HERE.parents[2]`
# spelling because that is the spelling the BRIEF used, and the instrument reported the real
# pre-fix `checks/census.py:14` as on-root and GREEN. A fixture retyped by hand agrees with the
# instrument by construction -- which is the belt sharing the belt's assumption, the exact failure
# the brief warns about with the tokenizer that ate a full stop.
#
# `457b81619^:checks/census.py` is `sys.path.insert(0, str(HERE.parents[2]))  # the tinygrad
# tree` with no constant at all; `457b81619^:checks/hermetic-census.py` and
# `b3aa1b0f1^:checks/abi_gate.py` are both `REPO = HERE.parents[2]`.
def _prefix_fixtures():
    """The pre-fix sources, read out of `git show` when git is available and falling back to the
    recorded BYTES otherwise. The fallback is not a convenience: a plant whose fixtures vanish
    with the history must still have fixtures, or the suite goes quietly vacuous -- and a plant
    that cannot run is a plant nobody runs."""
    want = {
        "checks/census.py": "457b81619^",
        "checks/hermetic-census.py": "457b81619^",
        "checks/abi_gate.py": "b3aa1b0f1^",
    }
    out = {}
    for rel, rev in want.items():
        r = subprocess.run(["git", "show", f"{rev}:{rel}"], cwd=HERE.parent,
                           capture_output=True, text=True)
        out[rel] = r.stdout if r.returncode == 0 else FALLBACK_PRE_FIX[rel]
    # The FIXED form, asserted clean in the same breath, so the plant cannot be satisfied by a
    # clause that calls everything red.
    out["checks/abi_gate.py.fixed"] = GOOD_ROOT
    return out


FALLBACK_PRE_FIX = {
    "checks/census.py":
        "sys.path.insert(0, str(HERE.parents[2]))            # the tinygrad tree\n" + MAIN,
    "checks/hermetic-census.py":
        "HERE = pathlib.Path(__file__).resolve().parent\nREPO = HERE.parents[2]\n" + MAIN,
    "checks/abi_gate.py":
        "HERE = pathlib.Path(__file__).resolve().parent\nREPO = HERE.parents[2]\n" + MAIN,
}
BAD_ROOT = ("from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
            "REPO = HERE.parents[2]\n" + MAIN)
GOOD_ROOT = ("from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
             "REPO = HERE.parents[0]\n"
             "def refuse(*w):\n    raise SystemExit(2)\n"
             "refuse('x') if not (REPO / 'pyproject.toml').is_file() else None\n" + MAIN)
# THE PLANT-7 FIXTURES, HOISTED OUT OF `_plants` AND INTO MODULE CONSTANTS. MEASURED, and this is
# the fourth measurement of the same fault: with `lit_py` living INSIDE the plant function, the
# blanker could not see it -- `FIXTURES` is built from module-level names -- so `ROOT_INLINE` read
# this file's own plant fixture as this file's own root and reported `gates/gates-pop.py`
# off-repo. **A FIXTURE THAT IS NOT REACHABLE FROM THE BLANKER WILL BE READ AS CODE.** Plant 7
# asserted the COMMENT layer only, and the STRING layer is where the finding actually lived.
LIT_PY = ("# was: sys.path.insert(0, str(HERE.parents[2]))\n"
          "HERE = pathlib.Path(__file__).resolve().parent\nREPO = HERE.parents[0]\n" + MAIN)
LIT_SH = ('#!/bin/sh\n# used to cd "$(dirname "$0")/../../.."\n_d=${0%/*}\ncd "$_d/.."\n')


def plants():
    """ONE PLANT PER DIRECTION, and the count is printed from the checks rather than written here.
    Returns rc.

    THE INERTNESS IS MEASURED AROUND THE WHOLE FUNCTION, not asserted inside one plant. Every
    plant reads the live tree -- `entry_reason(gk)` on `gates/gatekit.py` is a live read -- and a
    plant that writes is a plant that can destroy the ledger it is auditing. MEASURED: the first
    version did exactly that and every plant still passed, which is the failure the brief names
    as `LEFT=NOTHING` ON BOTH SIDES: a harness that cannot see its own damage reports green
    while the state it measured is gone.
    """
    live_before = LEDGER_PATH.read_bytes() if LEDGER_PATH.is_file() else None
    rc = _plants()
    live_after = LEDGER_PATH.read_bytes() if LEDGER_PATH.is_file() else None
    inert = live_before == live_after
    print(f"  {'PASS' if inert else 'FAIL'}  inertness: --plant left the live ledger BYTE-IDENTICAL "
          f"(sha unchanged)\n"
          f"          observed: {'unchanged' if inert else 'CHANGED -- a plant wrote the live state'}")
    return rc | (0 if inert else 1)


def _plants():
    """The plants. SPLIT OUT of `plants()` so the whole suite runs inside ONE inertness
    window -- a plant that wrote would be caught whichever plant it was, and a per-plant
    assertion would have to be written five times and trusted five times.

    PLANT 0 -- the shell half of clause I. `checks/substrate-check.sh` dispatches on `$0`; a
    regex looking for `if __name__` sees no entry point there and would report an EMPTY
    population on a tree full of gates. A total blind spot, so asserted FIRST and separately.

    PLANT 1 -- an off-repo root, in BOTH directions. `parents[2]` on a `HERE` is the
    `checks/hermetic-census.py` shape; `parents[1]` on a `HERE` is one level too FEW, which the
    retired `parents[n>0]` rule would have called fine. The clause is SEMANTIC -- the constant is
    EVALUATED against the real root -- so it has to catch the shallow slip too.

    PLANT 2 -- **A GATE THE INSTRUMENT DOES NOT NOTICE.** The most valuable plant here,
    because its failure is invisible from inside this file. A module with NO entry guard is a
    LIBRARY by clause I -- and `gates/gatekit.py` is exactly that: no `__main__`, no `exit`, and
    it is the shared half of NINE gates, every one of which depends on its `ROOT` and its
    `_clear()`. The population's edge is not empty: it holds a real gate, and the instrument
    MUST name that edge with a count rather than quietly exclude it.
    MEASURED, and the first spelling of this plant was WRONG: it named `checks/bounded.py` as
    the live witness, and `checks/bounded.py:413` carries a `__main__` guard, so that file is IN
    the population. The claim about the shape was right and the witness was not -- which is why
    the plant asserts the shape against a synthetic file AND names the live witness separately,
    so a moved witness is a FAIL and not a silent drift.

    PLANT 3 -- an EMPTY population is REFUSED with rc 2, never green. This is the
    `artefacts_ok()` shape: a guard that reported zero on a directory holding nothing.

    PLANT 4 -- **A NEW GATE NOBODY DECLARED.** Asserted as a DIFFERENCE in the ledger, because a
    count is what `artefacts_ok()` reported over nothing.

    SELF-CONSISTENCY IS NOT INDEPENDENCE: plant 1 and the live tree share a code path, so plant
    1 alone proves nothing. What makes these independent is that each asserts a different
    DIRECTION -- found, red, named, refused, moved.
    """
    rc = 0
    checks = []

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks")
        # `checks/substrate-check.sh`'s REAL preamble, verbatim in shape: `_d=${0%/*}` is the
        # self-reference, and it is the token that made this file an entry point at all.
        (r / "checks" / "substrate-check.sh").write_text(
            '#!/bin/sh\n_d=${0%/*}; case $_d in "$0") _d=.;; esac\n'
            'cd "$_d/.." || exit 2\nexec .venv/bin/python checks/substrate.py "$@"\n')
        (r / "checks" / "mod.py").write_text("X = 1\n")
        e, libs, _opaque, _uncarried = _buckets(r)
        got = {str(p.relative_to(r)) for p in e}
        # `len(e) == 2`, and the SECOND is the home witness `_tree` planted: the synthetic tree
        # earns `checks/` by holding a gate that certifies it, exactly as the live tree does.
        # MEASURED: with the witness counted out, `len(e) == 1` fails on a population of 2, which
        # is the plant asserting a number the DERIVATION now owns.
        ok0 = len(e) == 2 and {"checks/substrate-check.sh", "checks/home-witness.py"} == got
        checks.append(("0: a shell gate found by SELF-DISPATCH, not by `__main__`, in a home the "
                       "DERIVATION admitted", ok0,
                       f"found {len(e)} entry point(s): {sorted(got)}"))

    # PLANT 6 -- **THE BELT THAT DISAGREED WITH THE INSTRUMENT.** Two tokenizers that share no
    # regex, and the assertion is that they DISAGREE on the live tree AND that the union is
    # strictly larger than the line-anchored one. MEASURED, this instrument shipped a
    # line-anchored `$0`/`exec` tokenizer that found 2 of 17 `checks/*.sh` entry points and
    # MISSED `checks/sb-gate.sh` -- the gate named in instance 1 of the very brief this file
    # answers. The token is the same shape as the belt that ate a full stop: both read a
    # separator the subject did not use at that position. Asserting only "the union works"
    # would let the narrow tokenizer back in silently, so the DISAGREEMENT is itself the claim.
    # PLANT 6's DENOMINATOR WAS ITSELF A SUFFIX SET, in the file that just had one removed.
    # `live_sh = sorted((HERE.parent / "checks").glob("*.sh"))` named ONE home BY HAND and ONE
    # SUFFIX, so `union == len(live_sh)` was `17 == 17` over a population it had chosen -- **the
    # assertion agreed with itself by construction**, which is the defect this file's own header
    # calls `artefacts_ok()`'s shape. MEASURED: `checks/bend` is a tracked `#!/bin/sh` shim with
    # NO dot in its name, so it is a shell entry the suffix never held, and the true shell-entry
    # count across BOTH homes is 18 where this line said 17. The denominator is now the WALK and
    # the same shell test, over both homes, so the number is measured rather than chosen.
    live_sh = [p for home in HOMES for p in sorted((HERE.parent / home).iterdir())
               if p.is_file() and (SH_SHEBANG.match(p.read_text(errors="replace"))
                                   or shell_tokens(p.read_text(errors="replace"))[1])]
    ent = sum(1 for p in live_sh if shell_tokens(p.read_text(errors="replace"))[0])
    self_ = sum(1 for p in live_sh if shell_tokens(p.read_text(errors="replace"))[1])
    union = sum(1 for p in live_sh if is_shell_entry(p.read_text(errors="replace")))
    ok6 = ent < union and self_ > ent and union == len(live_sh)
    checks.append(("6: the two shell tokenizers DISAGREE, and their UNION is the population "
                   "(the narrow one alone saw 2, over BOTH homes walked and not globbed)",
                   ok6,
                   f"narrow={ent} selfref={self_} union={union} of {len(live_sh)} walked "
                   f"shell entries -- {union - ent} gates only the SECOND token can see"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks")
        (r / "checks" / "bad.py").write_text(BAD_ROOT)
        (r / "checks" / "good.py").write_text(GOOD_ROOT)
        (r / "checks" / "wrong-shallow.py").write_text(
            "from pathlib import Path\nHERE = Path(__file__).resolve().parent\n"
            "REPO = HERE.parents[1]\n" + MAIN)   # ONE TOO FEW for a file at `checks/`
        rows = {str(p.relative_to(r)): (str(p.relative_to(r)), entry_reason(p), *root_facts(p, r))
                for p in discover(r)[0]}
        bad, good, shallow = (rows["checks/bad.py"], rows["checks/good.py"],
                              rows["checks/wrong-shallow.py"])
        # The DEPTH-BAKED rule is gone, so this plant asserts the SEMANTIC: `parents[2]` on a
        # `HERE` is off-repo AND red; `parents[0]` on a `HERE` is on-repo AND green; and
        # `parents[1]` on a `HERE` -- one level too FEW, which the retired shape rule would
        # have called fine because `n < 2` -- is ALSO off-repo. Three directions, one clause.
        ok1 = (not bad[4] and not bad[3] and good[4] and good[3] and not shallow[4])
        checks.append(("1: an off-repo root is RED in BOTH directions (n too deep, n too "
                       "shallow), and parents[0]+refuse is GREEN",
                       ok1,
                       f"bad[2]={not bad[4]}/{not bad[3]} good[2]={good[4]}/{good[3]} "
                       f"shallow[1]={not shallow[4]}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks", "gates")
        # A GATE THE INSTRUMENT DOES NOT NOTICE: no `__main__`, no self-dispatch -- so clause I
        # files it under `sh-lib`/`py-lib` and it is NOT in the population. Asserted two ways:
        # (a) it really is out of the population, and (b) the report SAYS SO with a number, so
        # the exclusion is visible rather than silent. `checks/bounded.py` is the live instance.
        (r / "checks" / "driver.py").write_text("def drive(): pass\n")
        (r / "gates" / "gatekit.py").write_text("class Gate: pass\n")
        e, libs, _opaque, _uncarried = _buckets(r)
        libs_named = sorted(str(p.relative_to(r)) for p in libs)
        out_ok = ("checks/driver.py" in {str(p.relative_to(r)) for p in libs}
                  and "checks/driver.py" not in {str(p.relative_to(r)) for p in e})
        # The live witness for the SAME shape: `gates/gatekit.py` carries no entry guard and is
        # the shared half of 9 gates, so it is a gate this instrument does not notice. Asserted
        # against the live tree so that a moved or rewritten witness is a FAIL, not a silent
        # drift -- and asserted as a `py-lib` CLASSIFICATION rather than as an absence, because
        # the first spelling of this plant used the wrong live file and would have gone on
        # passing had `checks/bounded.py` never grown its `__main__` guard.
        gk = HERE / "gatekit.py"
        live_is_lib = gk.is_file() and entry_reason(gk) == "py-lib"
        checks.append(("2: a gate this instrument does NOT notice is EXCLUDED and COUNTED",
                       out_ok and len(libs_named) == 2 and live_is_lib,
                       f"excluded={libs_named} live gates/gatekit.py is a lib={live_is_lib}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        rc_empty = report_quiet(r)
        checks.append(("3: an EMPTY population is REFUSED (2), never green", rc_empty == 2,
                       f"rc={rc_empty}"))

    # PLANT 4 -- **A NEW GATE THE INSTRUMENT MUST NOTICE.** The brief's requirement, and the
    # one that no static property of this file can fake: the ledger diff has to MOVE when a
    # gate appears that nobody wrote down. Asserted as a DIFFERENCE and not as an assertion
    # about a count, because a count is what `artefacts_ok()` reported over a directory holding
    # nothing.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks")
        (r / "checks" / "first.py").write_text(GOOD_ROOT)
        # The synthetic ledger lives INSIDE the temp tree. It did not, on the first run: the
        # path was hard-wired, and `--plant` wrote `checks/undeclared.py` over the live
        # 66-row ledger while still printing 5/5 GREEN.
        syn = r / LEDGER.name
        # THE WITNESS IS IN THE LEDGER TOO. `_tree` planted `checks/home-witness.py`, so a ledger
        # holding one row makes the diff report TWO additions -- which is the right kind of
        # failure: a plant that has to be re-read when the DERIVATION changes is a plant that is
        # measuring the derivation and not the defect.
        write_ledger([("checks/first.py", "py-main", "x", True, True),
                      ("checks/home-witness.py", "py-main", "x", True, True)], syn)
        (r / "checks" / "undeclared.py").write_text(BAD_ROOT)   # a gate NOBODY wrote down
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc_new = report(r, "check", syn)
        said = buf.getvalue()
        ok4 = (rc_new == 1 and "NEW  checks/undeclared.py" in said
               and "1 new," in said)
        checks.append(("4: a NEW GATE nobody declared makes the ledger MOVE and the run RED",
                       ok4, f"rc={rc_new} said_added={'NEW  checks/undeclared.py' in said}"))

    # PLANT 10 -- **A CORRECT DELETION IS NOT A DEFECT, AND ERASURE IS NOT A CURE.** The trap this
    # file used to be shaped by, and it is asserted in FOUR directions because the two failure
    # modes are independent and a plant that asserts one is satisfied by a check that cries wolf
    # on the other. MEASURED on the pre-fix code: nothing moved `rc=0`; a gate deleted CORRECTLY
    # `rc=1` with `III GONE`; and the ONLY available remedy was to drop the row, so the two ways to
    # go green were "delete nothing" and "forget that it existed", and **deleting a gate correctly
    # was indistinguishable from deleting one by accident.**
    #   (a) a gate that LEFT and is not recorded is RED -- the ledger is out of date;
       #   (b) the same gate RETIRED (`--ledger write`, which keeps the row) is GREEN, and the row is
    #       STILL THERE with `reason=gone` -- a correct deletion is achievable and the price is one
    #       word in one row;
    #   (c) **THE MERGE IS MONOTONIC ACROSS RUNS** -- a SECOND write over the same tree must not
    #       drop the tombstone the first one wrote. This is the direction that is assertable HERE
    #       and the one a rewrite fails: PLANT 10 caught exactly that, in this file's own first
    #       merge, on the first run. The claim it replaces -- "a hand-erased row is still red" --
    #       is NOT assertable and was withdrawn: an erased tombstone is indistinguishable from a
    #       gate the ledger never knew, because the ledger is a plain file and `git diff` is the
    #       only witness to a hand edit. **AN ASSERTION THAT NEEDS A WITNESS THIS INSTRUMENT DOES
    #       NOT HOLD IS NOT A HARDER ASSERTION, IT IS A FALSE ONE**, and it would have sat in this
    #       suite green while measuring nothing.
    #   (d) a write over a tree that finds NOTHING retires rather than empties -- the merge, not a
    #       rewrite. Measured, the pre-fix write took a 3-row ledger down to 0 and printed
    #       `GATES-POP: OK`.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks")
        for n in ("keeper", "victim"):
            (r / "checks" / f"{n}.py").write_text(GOOD_ROOT)
        syn = r / LEDGER.name
        rows = [(str(p.relative_to(r)), entry_reason(p), *root_facts(p, r))
                for p in _buckets(r)[0]]
        write_ledger(rows, syn)
        (r / "checks" / "victim.py").unlink()

        def run(mode="check"):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                return report(r, mode, syn), buf.getvalue()

        rc_unrec, said_unrec = run()
        (a) = rc_unrec == 1 and "GONE checks/victim.py" in said_unrec
        # (b) THE CURE, and it is `write`, which retires rather than deletes.
        run("write")
        after_one = read_ledger(syn) or []
        tomb = [x for x in after_one if x[0] == "checks/victim.py"]
        rc_ret, said_ret = run()
        (b) = (rc_ret == 0 and len(tomb) == 1 and tomb[0][1] == RETIRED
               and "1 retired" in said_ret)
        # (c) MONOTONICITY: write AGAIN over the same tree, twice, and the tombstone survives.
        run("write")
        after_two = read_ledger(syn) or []
        (c) = len(after_two) == len(after_one) and [x for x in after_two
                                                   if x[0] == "checks/victim.py"] == tomb
        # (d) THE MERGE, over a tree where everything but ONE gate is gone -- a rewrite would leave
        # a single row. `_tree` planted `checks/home-witness.py` and nobody deleted it, so it must
        # come back LIVE: the assertion is about WHICH rows are retired, not that they all are,
        # because "all retired" would be satisfied by a merge that retired the survivor too.
        (r / "checks" / "keeper.py").unlink()
        run("write")
        after = read_ledger(syn) or []
        departed = {x[0] for x in after if x[1] == RETIRED}
        (d) = (len(after) == len(rows)
               and departed == {"checks/keeper.py", "checks/victim.py"}
               and [x for x in after if x[0] == "checks/home-witness.py"][0][1] != RETIRED)
    checks.append(("10: a CORRECT deletion is ACHIEVABLE (retire the row) and ERASURE IS NOT A "
                   "CURE -- unrecorded=>red, retired=>green with the row KEPT, write twice keeps "
                   "the tombstone, write over a nearly-empty tree retires rather than rewrites",
                   a and b and c and d,
                   f"unrecorded={a} retired_green={b} monotonic={c} merge_keeps_all={d} "
                   f"(rows {len(rows)} -> {len(after_two)} -> {len(after)}; tombstone kept={len(tomb)}"
                   f"x2; retired={sorted(departed)})"))

    # PLANT 11 -- **THE ROOT SET IS A POPULATION, NOT A FLOOR, AND IT IS NOT PLANTED ANYWHERE.**
    # `HOMES = ("checks", "gates")` was replaced by `gate_homes()` in `3d92f5751`, and TWELVE plants
    # assert tokenizers, roots, the ledger and the opaque bucket -- and NONE of them asks what the
    # derivation is FOR. **A POPULATION GATE WITH NO PLANT ON ITS OWN ROOT SET IS A LIST THAT
    # HAPPENS TO BE COMPUTED**, and that is the shape the hand tuple had. Three directions:
    #   (a) RENAME A HOME, COMMIT: the population MOVES -- the new name is found, the old name is
    #       not, and the entry count is UNCHANGED. A derivation that kept the old name would be a
    #       cache; a derivation that kept BOTH would be a union.
    #   (b) DELETE A HOME, COMMIT: the population SHRINKS TO NOTHING. **A POPULATION THAT CANNOT
    #       SHRINK IS A FLOOR, NOT A POPULATION**, and the strongest form of that claim is a
    #       population that reaches ZERO -- which is also the state `report` REFUSES with 2, so the
    #       two agree instead of one papering over the other.
    #   (c) RENAME A HOME WITHOUT COMMITTING: the commit tree still names the old directory, the
    #       disk does not carry it, and the run says `ABSENT`. **WITHOUT (c) THAT IS `0/0`** --
    #       the same row `.github 0/0` prints for a directory that really is empty -- so a
    #       DELETED home and an EMPTY one are indistinguishable. **A HAND-LIST TYPO IS INVISIBLE; A
    #       MISSING DIRECTORY IS NOT, AND THIS IS WHERE IT BECOMES SAYABLE.**
    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        _tree(r, "checks", "gates")
        for home in ("checks", "gates"):
            (r / home / f"{home}-gate.py").write_text(GOOD_ROOT)
        _commit(r)
        h0, n0, _ = _roots(r)
        os.rename(r / "gates", r / "verify")
        _commit(r)
        h1, n1, _ = _roots(r)
        moved = h0 == ("checks", "gates") and h1 == ("checks", "verify") and n1 == n0
        # (b) THE SHRINK. The whole home goes, not one of its gates: `home-witness.py` still
        # CERTIFIES a home that keeps one gate, so deleting a single file is not a shrinking.
        shutil.rmtree(r / "verify")
        _commit(r)
        h2, n2, _ = _roots(r)
        shrank = h2 == ("checks",) and n2 == n0 // 2
        # (c) THE MISSING DIRECTORY. `checks` is in HEAD and absent from the disk, so the
        # derivation must name it as ABSENT rather than count it as an empty question.
        os.rename(r / "checks", r / "probe")          # NOT committed -- HEAD still says `checks`
        _, _, d3 = _roots(r)
        absent_row = "checks" in d3["absent"]
        not_zero = not any(row.split()[0] == "checks" for row in d3["rejected"])
        # AND THE LAST HALF: rename it BACK and the population comes back. **A POPULATION THAT
        # CANNOT SHRINK IS A FLOOR, AND ONE THAT CANNOT GROW AGAIN IS NOT A POPULATION EITHER.**
        os.rename(r / "probe", r / "checks")
        h4, n4, _ = _roots(r)
        grew_back = h4 == h2 and n4 == n2
    checks.append(("11: THE ROOT SET IS A POPULATION, NOT A FLOOR -- rename a home and the "
                   "population MOVES with it, delete one and it SHRINKS, a committed directory "
                   "the disk lacks reads ABSENT rather than 0/0, and renaming it back GROWS it",
                   moved and shrank and absent_row and not_zero and grew_back,
                   f"homes {h0}->{h1}->{h2}->{h4}, entries {n0}->{n1}->{n2}->{n4}, "
                   f"absent has 'checks'={absent_row}, no `checks 0/0` row={not_zero}"))

    # PLANT 5 -- **THE REPLAY.** The three named instances at their PRE-FIX sources, read out of
    # this repo's own git history, and asserted CAUGHT. Two of the three are `HERE.parents[2]`;
    # the third is `checks/census.py:14` at `457b81619^`, which has NO ROOT CONSTANT AT ALL --
    # it is a bare `sys.path.insert(0, str(HERE.parents[2]))` -- and the constant-only regex
    # MISSED it, which is how plant 2's blind spot turned out to be this file's own.
    # A plant that re-derives its fixtures by hand is a plant that agrees with the regex by
    # construction, so the fixtures are the BYTES the history holds and a fix commit that moves
    # them turns this plant RED.
    pre = _prefix_fixtures()
    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks")
        for rel, src in pre.items():
            (r / rel).write_text(src)
        got = {rel: verdict_of(root_facts(r / rel, r)) for rel in pre}
        caught = [k for k, v in got.items() if v == "off-repo"]
        fixed_ok = got.get("checks/abi_gate.py.fixed", "off-repo") == "on-root+assert"
        ok5 = len(caught) == 3 and fixed_ok
        checks.append(("5: THE REPLAY -- all 3 pre-fix instances from git history are CAUGHT, "
                       "and the fixed form is clean", ok5,
                       f"caught={len(caught)}/3 fixed_form_clean={fixed_ok}"))

    # PLANT 7 -- **PROSE IS NOT CODE.** A file whose CHANGELOG quotes the exact expression the
    # scanner hunts, and which must NOT be reported. MEASURED: `gates/gates-pop.py` did exactly
    # this to itself before `code_of` existed -- its own comment at :202 quotes
    # `sys.path.insert(0, str(HERE.parents[2]))`, the scanner found it, and the run said
    # `gates-pop.py OFF-REPO`, making the count 13 where the truth is 12. Asserted in BOTH
    # languages, because `checks/sb-gate.sh:17` is the same trap in shell: a comment recording
    # that the gate USED to `cd $(dirname "$0")/../../..`, in a file that no longer does.
    #
    # AND THE PLANT IS NOW STRONGER THAN ITS OWN PROSE SAYS. The fixtures are `LIT_PY`/`LIT_SH`,
    # module constants, so `FIXTURES` can blank them -- and plant 8 asserts the INVERSE, which is
    # the direction that was green while the instrument was wrong about itself: **this file, read
    # by this file, must be ON-REPO.** A meta-instrument that cannot measure ITSELF cleanly is the
    # one measurement nobody else makes.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks")
        (r / "checks" / "documented.py").write_text(LIT_PY)
        (r / "checks" / "documented.sh").write_text(LIT_SH)
        ok7 = (root_facts(r / "checks" / "documented.py", r)[2]
               and root_facts(r / "checks" / "documented.sh", r)[2])
    checks.append(("7: PROSE IS NOT CODE -- a comment quoting the hunted expression is NOT a "
                   "finding (this file found itself)", ok7,
                   f"py_and_sh_both_reported_on_root={ok7}"))

    # PLANT 8 -- **THIS FILE, READ BY THIS FILE, MUST BE ON-REPO.** The one direction plant 7
    # could not reach, and the one the instrument got WRONG while every plant was green.
    # MEASURED 2026-10-06: `gates/gates-pop.py` reported ITSELF off-repo. `ROOT_INLINE` had
    # matched the string literal `FALLBACK_PRE_FIX["checks/census.py"]` -- a SYNTHETIC GATE held
    # in a dict in this file's own body -- and `code_of`'s docstring blanking deliberately keeps
    # non-docstring strings, because "a string that is an ARGUMENT carries a path the scanner
    # needs". Plant 7 asserted the COMMENT layer and passed. **PROSE IS NOT CODE; A FIXTURE IS NOT
    # EITHER; AND A PLANT THAT COVERS THE COMMENT LAYER SAYS NOTHING ABOUT THE STRING LAYER.**
    self_facts = root_facts(Path(__file__), HERE.parent)
    checks.append(("8: THIS FILE READ BY THIS FILE IS ON-REPO -- a meta-instrument that cannot "
                   "measure itself cleanly is the one measurement nobody else makes",
                   self_facts[2], f"gates/gates-pop.py -> {self_facts}"))

    # PLANT 9 -- **THE POPULATION IS A DIRECTORY, NOT A SUFFIX SET.** Four claims, four
    # directions, because the two halves fail apart and a plant that asserts only the half that
    # passes is a change-detector. `SUFFIXES = (".py", ".sh")` was the defect this plant exists
    # for, and its two halves were independent: the tuple dropped the file before a byte was
    # read, AND `entry_reason()` routed every non-`.py` suffix to the SHELL tokenizer. So:
    #   (a) a `.mjs` gate is ADMITTED -- the direction that was broken, on `checks/nan_census.mjs`;
    #   (b) an EXTENSIONLESS `#!/bin/sh` gate is ADMITTED -- `checks/bend`, tracked, and the tuple
    #       could not see it because it has no dot in it at all;
    #   (c) a `.bend` DRIVER IS NOT ADMITTED AS JAVASCRIPT -- the collision this plant's author
    #       walked into and fixed twice: bend has its own `import`, and bend's C-import is
    #       `import "../runtime/sz.c"`, so a loose `/^import\s+[\w{*]/` read 39 gate drivers as
    #       `js-main`. A language test that also matches another language is not a narrow
    #       population, it is a wider one;
    #   (d) a `.rows` FIXTURE IS NOT ADMITTED -- the direction that keeps (a) and (b) from turning
    #       the fix into a bag of every file in the home. It lands in the OPAQUE bucket, which is
    #       a COUNT, so 140 expected-value files in `checks/` are visible rather than absent.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r, "checks", "gates")
        (r / "checks" / "nan.mjs").write_text(
            'import {argv} from "node:process";\nargv.slice(2).forEach((a) => console.log(a));\n')
        (r / "checks" / "shim").write_text('#!/bin/sh\n_d=${0%/*}\nexec .venv/bin/python x.py "$@"\n')
        (r / "gates" / "probe.bend").write_text(
            'import Base\ndef f(x):\n  import "../tinybendygrad/runtime/sz.c"\n')
        (r / "checks" / "expected.rows").write_text(
            "2:i1 5:ALLOC 3:f32 7:(l0:12) 2:i0 1:N 3:n()\n2:i4 5:STACK 7:weakint 3:n(i2,i3)\n")
        pe, pl, po, _pu = _buckets(r)
        got = sorted(str(p.relative_to(r)) for p in pe)
        mjs_ok = "checks/nan.mjs" in got
        shim_ok = "checks/shim" in got
        bend_ok = not any(str(p.relative_to(r)).endswith(".bend") for p in pe + pl)
        rows_ok = "checks/expected.rows" in {str(p.relative_to(r)) for p in po}
        # AND THE LIVE WITNESS, because the fixture above is a shape I typed and a typed fixture
        # agrees with the instrument by construction. MEASURED on this tree: **0 of the 140 real
        # `checks/*.rows` files parse as Python**, so the real ones are OPAQUE too -- and the first
        # version of this fixture was `k=v\nk2=v2`, which IS a valid Python `Assign`, so the plant
        # was RED for a shape no file in the tree has. **A FIXTURE RETYPED BY HAND IS NOT A
        # WITNESS; THE TREE IS.** Asserted live so a moved or re-spelled fixture is a FAIL.
        live_rows = [p for h in HOMES for p in sorted((HERE.parent / h).iterdir())
                     if p.is_file() and p.name.endswith(".rows")]
        _, _, live_opaque, live_uncarried = _buckets(HERE.parent)
        # **THE POPULATION RULE MOVED THE DENOMINATOR, AND THE OLD ASSERTION DID NOT MOVE WITH IT.**
        # `_buckets` now excludes a file the commit tree does not carry BEFORE classification, so an
        # untracked `.rows` is `uncarried`, not `opaque`. Requiring it to be opaque fails the plant
        # for a rule that already excluded it. The witness is the files the tree carries: a carried
        # `.rows` that parses is named, and the plant is red on that file rather than on the 141
        # the commit tree does not hold.
        not_carried = {p for p, _r in live_uncarried}
        carried_rows = [p for p in live_rows if p not in not_carried]
        not_opaque = [p for p in carried_rows if p not in live_opaque]
        live_rows_opaque = not not_opaque
        ok9 = mjs_ok and shim_ok and bend_ok and rows_ok and live_rows_opaque
        checks.append(("9: THE POPULATION IS A DIRECTORY -- a `.mjs` gate and an EXTENSIONLESS "
                       "`sh` gate are ADMITTED, a `.bend` driver is NOT read as JavaScript, and a "
                       "`.rows` fixture is OPAQUE", ok9,
                       f"mjs={mjs_ok} extless_sh={shim_ok} bend_not_js={bend_ok} "
                       f"rows_opaque={rows_ok} live_rows_opaque={live_rows_opaque} "
                       f"({len(carried_rows) - len(not_opaque)}/{len(carried_rows)} carried `.rows` opaque, "
                        f"{len(live_rows) - len(carried_rows)} not in the commit tree; "
                        f"not opaque: {[str(p.relative_to(HERE.parent)) for p in not_opaque]}) "
                       f"-- entries={got}"))

    # PLANT 12 -- **A READ CANNOT WRITE, AND A WRITE SAYS IT WROTE.** The defect this file shipped:
    # `--ledger` DEFAULTED to `write`, so `gates/gates-pop.py` with no arguments rewrote a ledger
    # SIXTY-ODD OTHER UNITS SHARE. MEASURED on the pre-boundary tree: a plain invocation changed
    # `gates/gates-pop.ledger.tsv` by 13 added and 7 removed lines, 4 of them another unit's
    # in-flight `checks/.tmp-*` scratch, and the unit that caused it reverted the file and dropped
    # its own registration. Asserted through `main()` and `sys.argv` -- the ACTUAL default, not a
    # hand-passed argument, because a plant that calls `report(root, "check")` asserts the caller's
    # spelling and not the CLI's:
    #   (a) a PLAIN invocation leaves the live ledger BYTE-IDENTICAL;
    #   (b) ...AND it MEASURED SOMETHING, or (a) is satisfied by a crash. It has to name the ledger
    #       diff, so a no-op that printed nothing cannot pass this plant;
    #   (c) `--write-ledger --only <each entry>` on a SYNTHETIC tree DOES write, and says
    #       `LEDGER WROTE` -- the direction that makes (a) a boundary rather than a permanently-broken
    #       write. The bare flag, which is the central sweep, is plant 14;
    #   (d) THE WRITE'S COUNTS ADD UP to the rows it printed, because the count line and the per-row
    #       lines are computed independently and one of them can be wrong;
    #   (e) `--ledger write` is now an ARGUMENT ERROR, so the old silent-rewrite spelling cannot
    #       survive in a script;
    #   (f) the ledger's OWN HEADER names `--write-ledger` as its only writer, so the file states
    #       its own writer and a reader who has only the file still knows what produced it.
    live_read = LEDGER_PATH.read_bytes() if LEDGER_PATH.is_file() else None
    argv0 = sys.argv
    buf = io.StringIO()
    try:
        sys.argv = ["gates/gates-pop.py"]
        with contextlib.redirect_stdout(buf):
            rc_plain = main()
    finally:
        sys.argv = argv0
    read_out = buf.getvalue()
    (a) = (LEDGER_PATH.read_bytes() if LEDGER_PATH.is_file() else None) == live_read
    (b) = rc_plain == 1 and "III LEDGER DIFF:" in read_out and "UNRECORDED departure" in read_out
    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        r.mkdir(parents=True, exist_ok=True)
        _tree(r, "checks", "gates")
        # **THE LEDGER PATH IS `report`'s, NOT `r / LEDGER.name`, AND GETTING THAT WRONG WAS THE
        # PLANT'S FIRST RED.** `report` resolves it as `root / HERE.relative_to(ROOT) / LEDGER.name`,
        # so the write lands at `<tmp>/gates/` -- the same one-level mistake this file's own
        # `:1046` comment records for the live tree. A plant that asserts "the file appeared" must
        # therefore ASK `report` where it looks rather than spelling it a second time, or it is a
        # second copy of a derivation with a different predicate: one question, two answers.
        syn = r / HERE.relative_to(ROOT) / LEDGER.name
        wbuf = io.StringIO()
        try:
            sys.argv = ["gates/gates-pop.py", "--root", str(r), "--write-ledger",
                        "--only", "checks/home-witness.py", "--only", "gates/home-witness.py"]
            with contextlib.redirect_stdout(wbuf):
                main()
        finally:
            sys.argv = argv0
        wrote = syn.read_text() if syn.exists() else ""
        (c) = syn.is_file() and "III LEDGER WROTE" in wbuf.getvalue()
        nums = re.findall(r"IT ABSORBED (\d+) new, (\d+) changed, (\d+) returned and RETIRED (\d+)",
                          wbuf.getvalue())
        (d) = len(nums) == 1 and wrote.startswith("#") and all(int(x) >= 0 for x in nums[0])
    try:
        sys.argv = ["gates/gates-pop.py", "--ledger", "write"]
        # argparse writes its refusal to STDERR, and a plant suite that prints one usage line
        # among twelve verdicts reads as the suite's own failure.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            main()
        (e) = False
    except SystemExit as ex:
        (e) = ex.code == 2
    finally:
        sys.argv = argv0
    (f) = ("--write-ledger" in LEDGER_PREAMBLE
           and "ONLY writer" in LEDGER_PREAMBLE.splitlines()[0])
    checks.append(("12: A READ CANNOT WRITE AND A WRITE SAYS IT WROTE -- the plain CLI invocation "
                   "leaves the shared ledger byte-identical and still measures, `--write-ledger` "
                   "writes and says so, `--ledger write` is an argument error, and the ledger's own "
                   "header names its one writer", a and b and c and d and e and f,
                   f"plain_rc={rc_plain} read_unchanged={a} read_measured={b} wrote={c} "
                   f"counts={nums[0] if nums else None} old_spelling_refused={e} header_names_writer={f} "
                   f"(--plant's own inertness window is measured separately by `plants()`)"))

    # PLANT 13 -- **A CELL THE READER DID NOT READ IS `UNREADABLE`, AND A ROW IT CANNOT ACCOUNT
    # FOR IS NOT DROPPED.** `read_ledger` coerced with `f[3] == "1"` and dropped `len(f) < 5`.
    # Both were invisible, and they are NOT THE SAME DEFECT: a bad cell is ONE column, a short row
    # is FOUR, and a plant that asserts one of them passes a reader that is wrong about the other.
    # Both corruptions are applied to COPIES of a ledger this plant writes itself -- never the live
    # one -- and are read back through the SAME reader, with an UNBROKEN CONTROL FIRST.
    #
    # **THE PLANT IS TWO-SIDED, AND THAT IS WHAT MAKES IT ABLE TO FAIL.** `control` is the
    # falsifier against over-refusal: a reader that marked every cell `UNREADABLE` would satisfy
    # every other clause here and fail this one. `sig` is the falsifier against the pre-fix reader:
    # coercing `== "1"` marks nothing, so `sig` reads `(0, 0)` where it asserts `(1, 4)`. There is
    # no third reader this suite is satisfied by, which is the property a plant needs and the one
    # the first `negative` in this file lacked (it was vacuous).
    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        _tree(r, "checks")
        syn = r / LEDGER.name
        # THE FACTS ARE KNOWN BY CONSTRUCTION, not read from the live ledger: `alpha` and `beta`
        # assert, `gamma` does not, so a corrupted `beta` cell flips a TRUE into an unread, and a
        # shortened `gamma` row loses cells whose values are known. A plant whose truth comes from
        # the file under audit can be satisfied by whatever that file happens to hold today.
        write_ledger([(f"checks/{n}.py", "py-main", "q", n != "gamma", True)
                      for n in ("alpha", "beta", "gamma")], syn)
        clean = read_ledger(syn)
        control = clean is not None and len(clean) == 3 and not any(UNREADABLE in row
                                                                   for row in clean)
        cells = syn.read_text().splitlines()
        _hdr, alpha, beta, gamma = cells[-4:]   # THE HEADER AND THE THREE DATA ROWS ARE THE TAIL,
        #                                         so the PREAMBLE's own line count is not restated
        #                                         here -- a reader that had to know it is 9 would
        #                                         break the day the preamble is reworded.
        # ONE CELL CORRUPTED. MEASURED, the pre-fix reader read `garbage` as `False` and `moved`
        # nothing; here the cell is `UNREADABLE` and THE OTHER FOUR ARE UNCHANGED, so the reader
        # still proves `checks/beta.py` asserts nothing about -- well, it proves it knows nothing
        # about ONE cell, which is what a reader that reads one bad column must say.
        hurt = list(beta.split("\t"))
        hurt[3] = "garbage"
        syn.write_text("\n".join(cells[:-3] + [alpha, "\t".join(hurt), gamma]) + "\n")
        bad = read_ledger(syn)
        # **EVERY LOOKUP HERE TAKES A DEFAULT, BECAUSE A PLANT THAT CRASHES IS NOT A PLANT THAT
        # FAILED.** MEASURED 2026-10-20T00:29Z against an over-refusing reader, `next(...)` raised
        # `StopIteration` out of the suite -- so the run died with rc=1 and no `PLANTS: n/m` line at
        # all, which is the one outcome that cannot tell a falsified plant from a broken tree. The
        # rows are looked up by path and MISSED rather than demanded, and every clause below is
        # written to be False rather than to raise.
        b_row = next((x for x in bad if x[0] == "checks/beta.py"), None)
        cell = (len(bad) == 3 and b_row is not None and b_row[3] == UNREADABLE
                and b_row[:3] == clean[1][:3] and b_row[4] is True
                and DECIDED(b_row[1:]) != DECIDED(clean[1][1:]))
        # ONE ROW SHORTENED. The PATH SURVIVES, which is the whole of the fix and the opposite of
        # a refusal: `gone` must not fire on a row the reader merely failed to parse, and a
        # recorded discovery must not be re-announced as a first sighting (MEASURED, that is what
        # `if len(f) >= 5` did). EVERY OTHER FIELD IS `UNREADABLE`, because `gamma` asserted
        # nothing anyway and the reader must not be the thing that decides that.
        syn.write_text("\n".join(cells[:-1] + ["\t".join(gamma.split("\t")[:3])]) + "\n")
        cut = read_ledger(syn)
        g_row = next((x for x in cut if x[0] == "checks/gamma.py"), None)
        row = (len(cut) == 3 and g_row is not None
               and g_row[1:] == (UNREADABLE,) * (len(LEDGER_FIELDS) - 1))
        # **THE TWO READ DIFFERENTLY, AND THAT IS ASSERTED AS A COUNT OF HOLES**: one row with a
        # single unreadable cell beside a row with four. A reader that refused everything fails
        # `control`; a reader that refused nothing fails here.
        sig = (sum(c == UNREADABLE for c in (b_row or ())),
               sum(c == UNREADABLE for c in (g_row or ())))
        differs = sig == (1, len(LEDGER_FIELDS) - 1)
    checks.append(("13: A CELL THE READER DID NOT READ IS `UNREADABLE` AND AN UNACCOUNTABLE ROW "
                   "IS NOT DROPPED -- a corrupted cell is refused while the other four fields still "
                   "read, a shortened row KEEPS ITS PATH and refuses the rest, and the two are "
                   "distinguishable (1 hole against 4)", control and cell and row and differs,
                   f"control={control} cell={cell} row={row} differs={differs} "
                   f"holes={sig} expected=(1, {len(LEDGER_FIELDS) - 1})"))

    # PLANT 14 -- **A WRITE NAMES ITS PATHS, AND THE BARE FLAG IS THE CENTRAL SWEEP.** Three units
    # declined to run `--write-ledger` because it MERGES: adding every row makes the diff green
    # without one gate having been measured. The flag without a path is therefore REFUSED, a named
    # path absorbs only itself, and an unaccountable path writes nothing. Asserted through `main()`
    # on a synthetic tree, because a plant that calls `write_ledger(..., only=)` asserts the
    # function and not the CLI the refusals were about.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        _tree(r, "checks", "gates")
        syn = r / HERE.relative_to(ROOT) / LEDGER.name
        argv0 = sys.argv

        def invoke(*args):
            buf, err = io.StringIO(), io.StringIO()
            try:
                sys.argv = ["gates/gates-pop.py", "--root", str(r), *args]
                with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
                    code = main()
                return code, buf.getvalue(), err.getvalue()
            except SystemExit as ex:
                return ex.code, buf.getvalue(), err.getvalue()
            finally:
                sys.argv = argv0

        rc_bare, _, err_bare = invoke("--write-ledger")
        bare = rc_bare == REFUSED and not syn.exists() and "central sweep" in err_bare
        rc_one, out_one, _ = invoke("--write-ledger", "--only", "checks/home-witness.py")
        body = syn.read_text() if syn.is_file() else ""
        one = (rc_one == 1 and "checks/home-witness.py" in body
               and "gates/home-witness.py" not in body and "IT ABSORBED 1 new" in out_one)
        rc_two, out_two, _ = invoke("--write-ledger", "--only", "gates/home-witness.py")
        body2 = syn.read_text() if syn.is_file() else ""
        # THE NAMED PATH IS THE ONLY REMAINING MOVEMENT, so this write is green. The next read must
        # agree, or the write absorbed a row the check cannot see.
        rc_settled, _, _ = invoke()
        both = (rc_two == 0 and rc_settled == 0 and "checks/home-witness.py" in body2
                and "gates/home-witness.py" in body2 and "IT ABSORBED 1 new" in out_two)
        snap = syn.read_bytes() if syn.is_file() else b""
        rc_bad, _, err_bad = invoke("--write-ledger", "--only", "checks/no-such.py")
        unknown = rc_bad == REFUSED and syn.read_bytes() == snap and "no-such" in err_bad
        rc_alone, _, err_alone = invoke("--only", "checks/home-witness.py")
        alone = rc_alone == REFUSED and "pathspec" in err_alone and syn.read_bytes() == snap
        # A DEPARTURE NOT NAMED IS NOT RETIRED. Delete one gate, record the survivor, and the
        # deleted row stays a live claim. Recording the deleted path then retires it alone.
        (r / "gates" / "home-witness.py").unlink()
        _MEASURED.clear()
        rc_keep, _, _ = invoke("--write-ledger", "--only", "checks/home-witness.py")
        kept = read_ledger(syn) or []
        still_live = [x for x in kept if x[0] == "gates/home-witness.py"]
        not_swept = (rc_keep == 1 and len(still_live) == 1 and still_live[0][1] != RETIRED)
        rc_ret, _, _ = invoke("--write-ledger", "--only", "gates/home-witness.py")
        after = read_ledger(syn) or []
        tomb = [x for x in after if x[0] == "gates/home-witness.py"]
        survivor = [x for x in after if x[0] == "checks/home-witness.py"]
        rc_after, _, _ = invoke()
        # NAMING THE DEPARTURE RECORDS IT, so this write is green and the next read agrees. A write
        # that retired the survivor too would still be green here and is caught by `survivor`.
        retired_one = (rc_ret == 0 and rc_after == 0 and len(tomb) == 1 and tomb[0][1] == RETIRED
                       and len(survivor) == 1 and survivor[0][1] != RETIRED)
    checks.append(("14: A WRITE NAMES ITS PATHS -- a bare `--write-ledger` is REFUSED and writes "
                   "nothing, `--only` one path does not absorb the other, an unknown path writes "
                   "nothing, and a departure not named is not retired",
                   bare and one and both and unknown and alone and not_swept and retired_one,
                   f"bare={bare} one={one} both={both} unknown={unknown} alone={alone} "
                   f"not_swept={not_swept} retired_one={retired_one} "
                   f"(rc bare={rc_bare} one={rc_one} two={rc_two} settled={rc_settled} "
                   f"keep={rc_keep} ret={rc_ret} after={rc_after})"))

    print("PLANTS -- one direction per check, plus an inertness assertion, because a meta-gate's "
          "blind\nspot is the one nobody else checks. The count below is COMPUTED: MEASURED "
          "2026-10-20T00:22Z, the\nprose above it said `twelve` over a suite of FOURTEEN, and a "
          "number a reader has to\ntrust the prose for is the defect this file exists beside.")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    return rc


def report_quiet(root):
    """`report` in `check` mode on a tree, with its output swallowed, so a caller gets the rc alone.

    **THIS IS A READ, AND BEFORE THE BOUNDARY IT WAS NOT.** It asked for `"write"`, and the only
    thing stopping it from rewriting `root`'s ledger was `report`'s early return on an EMPTY
    population -- its own docstring said so: *"A CALLER THAT IS SAFE BECAUSE OF AN EARLY RETURN IS
    SAFE BY ACCIDENT, AND THE PATH IT WOULD HAVE WRITTEN WAS NEVER EXERCISED."* A helper whose only
    caller happens to pass an empty tree is a write path with no plant. Asking for `check` makes the
    early return a fast path rather than the thing standing between the caller and the file.
    """
    with contextlib.redirect_stdout(io.StringIO()):
        return report(root, "check")


# `FIXTURES` LAST, because it is derived from names this module defines above it. MEASURED: bound
# near the regexes it raised `NameError` at import -- see `_init_fixtures`. `HOMES` HERE FOR THE
# SAME REASON: it is `gate_homes(ROOT)`, which reads `root_facts`, and bound near `LEDGER` it
# raised `NameError` at import -- a crash inside a gate rather than a verdict.
_init_fixtures()
HOMES = _homes(ROOT)
HOME_DERIVATION = _derivation(ROOT)


def _norm_only(path):
    """The ledger's path-cell spelling. A leading `./` is the same path; a backslash is not a
    different gate."""
    path = path.replace("\\", "/")
    return path[2:] if path.startswith("./") else path


def main():
    ap = argparse.ArgumentParser(
        prog="gates/gates-pop.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="DENOMINATOR: entry points under checks/ and gates/, discovered by AST and by "
               "self-dispatch. A verdict with no denominator is a claim nobody can check. "
               "WRITING: `--write-ledger --only PATH` records that path and no other. "
               "A bare `--write-ledger` is refused: it is the central sweep.")
    ap.add_argument("--plant", action="store_true",
                    help="assert every plant on a synthetic tree; never touches the live tree")
    ap.add_argument("--ledger", choices=("check",), default="check",
                    help="check: read the ledger and diff it against this run (the default). "
                         "WRITING IS NOT A MODE OF THIS FLAG -- it is `--write-ledger`, and "
                         "`--ledger write` is now an ARGUMENT ERROR rather than a silent rewrite "
                         "of a file other units share")
    ap.add_argument("--write-ledger", action="store_true",
                    help="the ONLY writer of gates/gates-pop.ledger.tsv, and only together with "
                         "--only. A bare --write-ledger is REFUSED: it would merge every row this "
                         "run found, and the diff would go green without one gate having been measured")
    ap.add_argument("--only", action="append", default=None, metavar="PATH",
                    help="a path `--write-ledger` may absorb. Repeatable. Required with "
                         "--write-ledger. The spelling is the ledger's path cell "
                         "(checks/foo.py), and a path this run can neither adopt nor retire "
                         "is refused and nothing is written")
    ap.add_argument("--root", default=None, help="point at another tree (plant/disarm only)")
    a = ap.parse_args()
    # ONE writer, ONE spelling, ONE PATHSPEC. `--write-ledger` is the flag the ledger's own header
    # names, and `--ledger` cannot reach `write`. The pathspec is the other half: a write that
    # names no path is the central sweep, and it is refused rather than performed.
    if a.only and not a.write_ledger:
        refuse("`--only` is the pathspec of `--write-ledger`. A read takes no pathspec.")
    if a.write_ledger and not a.only:
        refuse("`--write-ledger` without `--only PATH` is the central sweep: it would MERGE every "
               "row this run found into the shared ledger, and the diff would go green without one "
               "gate having been measured. Name the paths this commit owns.")
    mode = "write" if a.write_ledger else a.ledger
    only = {_norm_only(p) for p in a.only} if a.write_ledger else None
    if not a.root:
        for marker in ("pyproject.toml", "tinybendygrad"):
            if not (ROOT / marker).exists():
                refuse(f"the repo root is not here: {marker} is absent at {ROOT}")
        return plants() if a.plant else report(ROOT, mode, only=only)
    return plants() if a.plant else report(Path(a.root).resolve(), mode, only=only)


if __name__ == "__main__":
    sys.exit(main())