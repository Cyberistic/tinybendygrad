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
  III THE SET MOVED OR THE LEDGER SAYS WHY. `--ledger` diffs the previous run. **A LEDGER READ AND
      THEN REWRITTEN BY ITS OWN READER IS NOT A LEDGER** -- `gates-pop.ledger.tsv` used to be
      written at `:646` and read at `:617` in the SAME process under the DEFAULT mode -- so it is
      a DIARY, and the ROOT SET is derived rather than snapshotted for exactly this reason.
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
import io
import os
import re
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
    `Expr(Dict)` and is data, and `import os` is neither shape at all."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    return bool(tree.body) and all(
        isinstance(s, ast.Expr) and not isinstance(s.value, ast.Call) for s in tree.body)


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
SH_COMMENT = re.compile(r"^\s*#.*$", re.M)


def shell_code(src):
    """Shell source with `#` COMMENTS removed.

    Same reason as `code_of`, and MEASURED on the same fault: `checks/sb-gate.sh:17` is a
    comment saying "This gate used to `cd "$(dirname "$0")/../../.."`", and a scanner that
    reads comments would find a `../../..` root in a file that no longer has one. **A gate's
    own changelog is not its code** -- and this repo writes unusually thorough changelogs, which
    is exactly what makes the mistake likely here.
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


def _buckets(root):
    """`(entries, libs, opaque)`, by walking every REGULAR file in the DERIVED homes. NEVER a
    literal list of files, NEVER a suffix set, and NEVER a literal list of homes: the homes come
    from `gate_homes(root)` -- which is why a plant has to DECLARE its homes by planting a gate
    that certifies one, and why `_tree` below does exactly that.

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
    """
    entries, libs, opaque = [], [], []
    for home in _homes(root):
        h = root / home
        if not os.path.isdir(h):
            continue
        for p in sorted(h.iterdir()):
            if not stat.S_ISREG(os.lstat(p).st_mode):
                continue
            r = entry_reason(p)
            if r is None:
                opaque.append(p)
            elif r in ("py-main", "sh-dispatch", "sh-selfref", "js-main"):
                entries.append(p)
            else:
                libs.append(p)
    return entries, libs, opaque


def discover(root):
    """`(entries, libs)` -- **A TWO-VALUE TUPLE IS A CONTRACT, and this one is MEASURED, not
    assumed.** `gates/gate-surface.py:280` returns this call's result straight into a two-value
    unpack, so the first version of this change returned three and the regression was
    `ValueError: too many values to unpack (expected 2)` at `gate-surface.py:422` -- rc 1 in a
    gate this unit was told not to edit. **A FIX THAT BREAKS A CALLER IS NOT A FIX; IT IS A
    TRADE, AND THE TRADE HAS TO BE PAID SOMEWHERE ELSE.** So the third bucket leaves through
    `opaque()` instead of through this signature, and the walk itself happens once.
    """
    entries, libs, _ = _buckets(root)
    return entries, libs


def opaque(root):
    """The third bucket alone, so `discover()`'s arity can stay a contract somebody else owns."""
    return _buckets(root)[2]


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
    if "HERE" not in expr:
        return f.parents[depth]
    assignment = next((l for l in p.read_text(errors="replace").splitlines()
                       if re.match(r"\s*HERE\s*=", l)), "")
    is_directory = assignment.rstrip().endswith((".parent", ".parent)")) or "dirname" in assignment
    return f.parent.parents[depth] if is_directory else f.parents[depth]


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
    """
    r = subprocess.run(["git", "-C", str(root), "ls-tree", "-r", "--name-only", "HEAD"],
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
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
    homes, witnesses, rejected, read_total = [], {}, [], 0
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
        else:
            rejected.append(f"{top} {len(survivors)}/{read}")
    return tuple(homes), {"source": source, "read": read_total,
                          "candidates": len(witnesses) + len(rejected),
                          "witnesses": witnesses, "rejected": rejected}


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
    the INDEX", and a shipped instrument is not required to be a gate: `.agents/slop/**` holds 68 of
    the offenders and 0 certified gate homes. So it does NOT read `gate_homes()` -- and the reason
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
    print(f"{indent}          (rejected rows read `survivors/files-read`; {derivation['read']} "
          f"tracked file(s) read in total)")


# ---- clause III: THE LEDGER, AND WHY A SNAPSHOT IS THE ONLY THING THAT CATCHES A NEW GATE --
# WHERE THE LEDGER IS, resolved ONCE at import. A MODULE GLOBAL rather than `HERE` re-read at
# call time, and that is not tidiness -- it is the fix for a MEASURED defect. The first version
# computed `HERE / LEDGER.name` inside both `ledger_rows` and `write_ledger`, so a `--plant` run
# could not be pointed anywhere else and PLANT 4 CLOBBERED THE LIVE LEDGER: `--plant` printed
# 5/5 GREEN and left `gates/gates-pop.ledger.tsv` holding the 2 synthetic rows `checks/first.py`
# and `checks/undeclared.py` instead of the live 66. That is the exact shape the brief names --
# an instrument that destroys the state it is measuring between beats -- and it was invisible
# because every plant still passed. A plant that can MOVE the thing it audits is not a plant.
LEDGER_PATH = HERE / LEDGER.name


def ledger_rows():
    """The previous run's `(path, reason, root_const, asserts, onroot)` rows, or None if there
    is no ledger yet. THE LEDGER IS NOT A DECLARATION OF THE POPULATION: it is a SNAPSHOT OF
    THE LAST MEASUREMENT, and the diff between two snapshots is a difference -- which is the
    only kind of check that can notice a gate nobody wrote down."""
    lp = LEDGER_PATH
    if not lp.is_file():
        return None
    out = []
    for line in lp.read_text().splitlines()[1:]:
        f = line.split("\t")
        if len(f) >= 5:
            # The two booleans come back as the STRINGS "0"/"1" and are coerced here rather
            # than at the comparison, because `"0" != False` is True: an uncoerced round-trip
            # made all 66 rows report CHANGED on a second run with nothing altered, which is
            # the ledger-diff failure mode that teaches a reader to ignore the diff.
            out.append((f[0], f[1], f[2], f[3] == "1", f[4] == "1"))
    return out


def write_ledger(rows, path=None):
    body = ["path\treason\troot_const\tasserts_root\ton_root"] + [
        f"{p}\t{r}\t{' '.join(c.split())}\t{int(a)}\t{int(o)}" for p, r, c, a, o in rows]
    (path or LEDGER_PATH).write_text("\n".join(body) + "\n")


def read_ledger(path):
    """`ledger_rows` against an ARBITRARY ledger file. Exists so a plant can diff a synthetic
    ledger without the live one being the default -- `ledger_rows()` is hard-wired to the live
    path on purpose, so the only way a synthetic ledger is ever consulted is by naming it."""
    if not path.is_file():
        return None
    out = []
    for line in path.read_text().splitlines()[1:]:
        f = line.split("\t")
        if len(f) >= 5:
            out.append((f[0], f[1], f[2], f[3] == "1", f[4] == "1"))
    return out


# ---- the report -------------------------------------------------------------------------
def report(root, ledger_mode, ledger_path=None):
    """Every discovered gate, one line, with its denominator. A verdict with no denominator is
    a claim nobody can check -- `gates/retention-check.py` states that rule and this file
    holds to it.

    `ledger_path` DEFAULTS TO THE LIVE ONE AND A PLANT NAMES ITS OWN. The parameter exists
    because the alternative was measured to be destructive: with the path hard-wired inside
    `ledger_rows`, `--plant` diffed a synthetic tree against the live ledger and wrote the
    synthetic answer back over it.
    """
    lpath = ledger_path or LEDGER_PATH
    homes, derivation = _measure(root)
    entries, libs, opaque = _buckets(root)
    report_roots(derivation)
    print(f"     {derivation['read']} tracked file(s) read to answer that question; a rejected "
          f"candidate is a DIRECTORY, and every one of the\n     twelve below was asked the same "
          f"question and answered no -- the root set MOVES when one of them\n     starts "
          f"answering yes, and this line is where a reader sees it.\n")
    if not entries:
        print(f"I  EMPTY POPULATION: no entry point under {'/'.join(homes)}/ -- and an empty "
              f"population cannot\n   fail, which is the defect this file exists for. REFUSED.")
        return 2

    rows, named, unasserted, offroot = [], 0, 0, 0
    print(f"I  DISCOVERED {len(entries)} entry point(s) under {'/'.join(homes)}/ "
          f"(+{len(libs)} module(s) with no entry guard, {len(opaque)} file(s) OPAQUE -- readable\n"
          f"   by no grammar in this instrument, which is a DENOMINATOR and not a verdict: it is")
    # THE OPAQUE DENOMINATOR, BY EXTENSION, because a single total cannot say WHICH language the
    # instrument cannot read and a reader who is not told that cannot tell whether 148 is right.
    # It moves when the tree gains a language, which is the entire reason it is printed.
    for suf, n in sorted(Counter(suffix_of(p) for p in opaque).items(), key=lambda kv: -kv[1]):
        print(f"     opaque {suf:8} {n:4} file(s)")
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
    if prev is None:
        print(f"III NO LEDGER at {lpath.name} -- this run WRITES it; the NEXT run diffs. "
              f"A snapshot with\n               no predecessor is a denominator, not a verdict.")
        if ledger_mode == "check":
            red = 1
    else:
        old = {r[0]: r[1:] for r in prev}
        new = {r[0]: r[1:] for r in rows}
        added = sorted(set(new) - set(old))
        gone = sorted(set(old) - set(new))
        moved = sorted(k for k in set(new) & set(old) if new[k] != old[k])
        print(f"III LEDGER DIFF: {len(added)} added, {len(gone)} gone, {len(moved)} changed "
              f"({len(prev)} -> {len(rows)})")
        for k in added:
            print(f"III   NEW  {k}: {new[k][0]} root_ok={new[k][3]} "
                  f"asserts={'YES' if new[k][2] else 'NO'}")
        for k in gone:
            print(f"III   GONE {k} -- a gate that LEFT the population is not a silent event")
        for k in moved:
            print(f"III   CHANGED {k}: {old[k][0]} -> {new[k][0]}")
        if ledger_mode == "check" and (added or gone or moved):
            red = 1
        if not (added or gone or moved):
            print("III   no movement: the population is STABLE, and stability is the only state a "
                  "set-difference\n     gate can be quiet about -- it is also the state that hid "
                  "four defects today.")
        print()
    if ledger_mode != "check":
        write_ledger(rows, lpath)
        print(f"III LEDGER WRITTEN {lpath.name}: {len(rows)} row(s)\n")

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
    """FIVE plants, ASSERTING FIVE DIFFERENT DIRECTIONS. Returns rc.

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
    """The five plants. SPLIT OUT of `plants()` so the whole suite runs inside ONE inertness
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
        e, libs, _opaque = _buckets(r)
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
        e, libs, _opaque = _buckets(r)
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
        # holding one row makes the diff report TWO additions and the assertion `"1 added" in said`
        # fails -- which is the right kind of failure: a plant that has to be re-read when the
        # DERIVATION changes is a plant that is measuring the derivation and not the defect.
        write_ledger([("checks/first.py", "py-main", "x", True, True),
                      ("checks/home-witness.py", "py-main", "x", True, True)], syn)
        (r / "checks" / "undeclared.py").write_text(BAD_ROOT)   # a gate NOBODY wrote down
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc_new = report(r, "check", syn)
        said = buf.getvalue()
        # AND THE INERTNESS IS ITS OWN ASSERTION: the live ledger must be byte-identical after
        # a plant run. The one that could not see itself is the one to check.
        before = LEDGER_PATH.read_bytes() if LEDGER_PATH.is_file() else None
        plants_inert = None
        ok4 = (rc_new == 1 and "NEW  checks/undeclared.py" in said
               and "1 added" in said)
        checks.append(("4: a NEW GATE nobody declared makes the ledger MOVE and the run RED",
                       ok4, f"rc={rc_new} said_added={'NEW  checks/undeclared.py' in said}"))

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
        pe, pl, po = _buckets(r)
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
        _, _, live_opaque = _buckets(HERE.parent)
        live_rows_opaque = all(p in live_opaque for p in live_rows)
        ok9 = mjs_ok and shim_ok and bend_ok and rows_ok and live_rows_opaque
        checks.append(("9: THE POPULATION IS A DIRECTORY -- a `.mjs` gate and an EXTENSIONLESS "
                       "`sh` gate are ADMITTED, a `.bend` driver is NOT read as JavaScript, and a "
                       "`.rows` fixture is OPAQUE", ok9,
                       f"mjs={mjs_ok} extless_sh={shim_ok} bend_not_js={bend_ok} "
                       f"rows_opaque={rows_ok} live_rows_opaque={live_rows_opaque} "
                       f"({sum(p in live_opaque for p in live_rows)}/{len(live_rows)} real `.rows`) "
                       f"-- entries={got}"))

    print("PLANTS -- ten directions plus an inertness assertion, because a meta-gate's blind "
          "spot is the one nobody\nelse checks")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    return rc


def report_quiet(root):
    """`report` on a tree with no gates, with the ledger written so the run is repeatable."""
    import io
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        return report(root, "write")


# `FIXTURES` LAST, because it is derived from names this module defines above it. MEASURED: bound
# near the regexes it raised `NameError` at import -- see `_init_fixtures`. `HOMES` HERE FOR THE
# SAME REASON: it is `gate_homes(ROOT)`, which reads `root_facts`, and bound near `LEDGER` it
# raised `NameError` at import -- a crash inside a gate rather than a verdict.
_init_fixtures()
HOMES = _homes(ROOT)
HOME_DERIVATION = _derivation(ROOT)


def main():
    ap = argparse.ArgumentParser(
        prog="gates/gates-pop.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="DENOMINATOR: entry points under checks/ and gates/, discovered by AST and by "
               "self-dispatch. A verdict with no denominator is a claim nobody can check.")
    ap.add_argument("--plant", action="store_true",
                    help="assert the three plants on a synthetic tree; never touches the live tree")
    ap.add_argument("--ledger", choices=("write", "check"), default="write",
                    help="write: snapshot this run (default). check: the ledger MUST match, so a "
                         "gate that appeared without the ledger moving is red")
    ap.add_argument("--root", default=None, help="point at another tree (plant/disarm only)")
    a = ap.parse_args()
    if not a.root:
        for marker in ("pyproject.toml", "tinybendygrad"):
            if not (ROOT / marker).exists():
                refuse(f"the repo root is not here: {marker} is absent at {ROOT}")
        return plants() if a.plant else report(ROOT, a.ledger)
    return plants() if a.plant else report(Path(a.root).resolve(), a.ledger)


if __name__ == "__main__":
    sys.exit(main())