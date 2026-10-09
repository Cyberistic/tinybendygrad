#!/usr/bin/env python3
"""gate-surface.py -- THE VERDICT SURFACE OF EVERY GATE: what each one DECLARES, and what a run
can actually MAKE it emit.

    .venv/bin/python gates/gate-surface.py            # the census AND the check
    .venv/bin/python gates/gate-surface.py --report   # the census only, rc never charged
    .venv/bin/python gates/gate-surface.py --plant    # the two-state self-test, synthetic tree only

THE NUMBER NOBODY WROTE DOWN. `.agents/slop/coindependent/REPORT.md` measured, over the 73 entry
points it could present a state for WITHOUT `bend`: **107 distinct exit codes declared, 28 reached,
79 (74%) never observed to fire, 40 more entry points presented in no state at all, and 9 gates
whose real surface is ZERO** (4 declare `REFUSED` as their only exit; 5 more could be driven only
to `REFUSED` because the input they compare against was swept). `AGENTS.md`'s sentence is why this
is the project's most important number: *"A gate that exits 0 having measured nothing is worse than
no gate, because it is trusted."* That measurement was a session's finding. This file makes it a
number EVERY RUN.

WHY THE DECLARATION, AND WHY IT IS NOT A SOURCE SCAN. `coindependent`'s 107 was PARSED from source
-- every literal that reaches an `exit`/`SystemExit`/`return` -- which is a SHAPE the file happens to
have, not a claim its author made. So a gate here DECLARES its own surface:

    VERDICTS = {0: "GREEN", 1: "RED", 3: "REFUSED"}     # exit code -> the token it prints
    PLANTS   = {0: ["--plant"], 3: ["--disarm", "DELETE"]}   # exit code -> argv that REACHES it
    RED_IS   = "FINDING"                               # OPTIONAL: what MY OWN red is about

Read by `ast.literal_eval` off the MODULE BODY and never by import, because importing a gate RUNS
it: `gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py` call `sys.exit(2)` at module scope,
and every `gatekit.Gate` clears its output directory in its constructor. Reading the constants
out of the source the author wrote is reading a DECLARATION; scanning for `return 1` is reading a
shape. **A declaration cannot audit itself (`gates/gates-pop.py`'s own lesson), so this file does
not TRUST the declaration -- it EXECUTES each plant and requires the observed rc to equal the
declared one.**

WHY `RED_IS` IS A CONSTANT AND NOT A LIST SOMEWHERE ELSE. "The gates whose redness is their
finding" was `--report-gate=<name>` on a runner, which is a name in a tuple: it can name a gate
that has moved, it cannot be checked by the gate it names, and it goes stale the moment a gate is
written. `RED_IS` is a gate saying something about ITSELF, in ITS OWN source, read from there --
so the population is DISCOVERED ("a gate that ships `RED_IS`"), a deleted gate takes its claim
with it, and a gate that changes what its red means changes the declaration in the same commit.
**ABSENT MEANS "my red is about the tree", so omission is never an excuse.**

`RED_IS` HAS EXACTLY ONE NON-DEFAULT VALUE, ON PURPOSE. A taxonomy of excusable reds would grow a
second class the first time somebody wanted one, and each class would need its own reader; one
value keeps the exception single, named, and impossible to grow into a loophole.

THE RULE, AND IT IS THE WHOLE POINT. **A declared verdict with no plant is RED, named.** *"A check
nobody has ever seen fire is a check of unknown value."* Three reds, each with its own denominator:

  UNPLANTED  a declared exit code no declared plant reaches -- a claim of unknown value.
  MISPLANT   a plant whose observed rc is not the rc it was declared to reach.
  NO-GREEN   a gate that declares no rc 0, so it can never report agreement: real surface ZERO.

THE SECOND RULE, AND IT IS WHAT MAKES A RUNNER WRITABLE. **A red has three meanings, and nothing
in the exit status tells them apart** -- so the census names a CLASS per gate, which a runner reads
instead of guessing. All three are DERIVED; none is a list, and two of the three are the ABSENCE of
something:

  FINDING    the gate DECLARED `RED_IS="FINDING"` in its own source AND its own rc-0 plant REACHED
             0 in this run. It has DEMONSTRATED green, so it has a green to fall from, and its red
             is information. This is `gate-surface.py` itself.
  UNTAKEN    the gate's rc-0 plant did not reach 0 -- unplanted, misplanted, or no rc 0 declared.
             Its red cannot be a failure of the tree, because the gate has never been seen agree
             and so has nothing to have failed from. `repro-rc`'s "the second measurement has never
             been taken" is exactly this: **"not yet taken" is not a fourth meaning, it is `REFUSED`
             with the wrong exit code**, and the runner that reads it as `UNTAKEN` says so.
  FAILURE    the default, and it is the ABSENCE of a declaration. An undeclared red is CHARGED. If
             a reader assumed any red was a finding, the declaration would be decoration and every
             red would pass; `prune4`'s lesson is that an assertion which cannot be false is not an
             assertion, so plant 4b is the same gate as 4a with one constant deleted.

**THE DECLARATION IS EARNED, NOT ASSERTED.** `RED_IS="FINDING"` on a gate that has never reached
0 is not a finding, it is `UNTAKEN` with a claim attached, and the census NAMES it UNEARNED --
because a declaration cannot audit itself, and the only evidence that a gate has a green to fall
from is a plant that reached one.

AND THE POPULATION IS NOT A SECOND LIST. It is `gates/gates-pop.py:discover()`, loaded BY PATH, the
same one-module-N-consumers shape `gates/gendirs.py` gave the generated directories. `coindependent`
walked its own `os.walk` and got **113** where `gates-pop` got **111** on the same tree. Reusing the
function makes the two numbers ONE BY CONSTRUCTION -- which is not the same as settling which was
right, and clause II prints the CONTROL (`os.walk`, recursive) beside it so the difference is named
rather than dissolved.

EXIT: 0 green, 1 red, 2 REFUSED -- a precondition was missing (no `pyproject.toml`/`tinybendygrad`
at the root, an EMPTY population, because a gate over 0 files cannot fail, or an AMBIGUOUS owner of
the exit vocabulary). A `--report` run prints the same census and returns 0. **A bare run needs NO
NAME: the population is `discover()` and the classes are read off each gate's own source, so a
runner invokes this with no arguments and reads the classes out. That is the whole replacement for
`--report-gate=<name>`.**

THIS FILE DECLARES ITS OWN SURFACE, which it did not, and the self-reference is the point: an
auditor of surfaces was the one gate in the population with no declaration to read. `RED_IS` is
`FINDING` because a red here is a census finding about unplanted verdicts, not a claim that the
tree disagrees with CPython.

EXIT CODES ARE A FOURTH SUBJECT, and they are OWNED, not listed. `gates/gatekit.py` holds the five
verdicts as ONE module-level name<-code unpack; `vocabulary()` reads that unpack BY PATH, so a
verdict code the tree has no name for is named `UNOWNED` and CHARGED. **MEASURED, four gates declare
one: `checks/dup-gate.py` and `checks/wallcheck.py` spell exit 2 `USAGE`, `checks/env-precond.py`
and THIS FILE spell it `REFUSED` -- two meanings on one number -- and `.agents/slop/hooks/run.py`'s
aggregator scores every code outside its own five as `DEAD`, which is a THIRD. A gate that refuses
where it should have refused is read as a gate that crashed, which is `refusalsweep`'s exact
failure: a gate that crashes cannot tell "the input is absent" from "I am broken".**

PLANTED, plus the blind spot this file OWNS. `--plant green` builds synthetic trees and asserts
twelve things (an UNPLANTED verdict is RED and NAMED; every verdict planted is GREEN; NO-GREEN is
RED; the blind spot; ZERO declarations is RED; the three classes 4a/4b/4c; an UNOWNED exit code is
RED and NAMED 5a, the same gate with an OWNED code is GREEN 5b, and an AMBIGUOUS vocabulary owner
is REFUSED 5c). `--plant red` asserts
the direction this file exists in: a census whose one gate has an UNPLANTED verdict is RED *and
charged*, which is what `PLANTS[1]` reaches. **The blind spot is asserted too, because it is the
class that let `checks/citation-gate.py` stay green against a root that does not exist:** a plant
that exits 0 having read nothing is indistinguishable, from the exit status alone, from a plant that
agreed. This file cannot tell green-correct from green-vacuous without a per-gate "did you read
your input" assertion, so plant 3 asserts the LIMIT rather than hiding it.
"""
import argparse
import ast
import contextlib
import io
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 180

# THIS GATE'S OWN DECLARATION, read by the census above exactly as it reads everyone else's.
# `0` and `1` are PLANTED, so this gate's surface is 3 of 3 REACHABLE -- without plants, `RED_IS`
# would be an UNEARNED claim and the census would say so about itself.
VERDICTS = {0: "OK", 1: "RED", 2: "REFUSED"}
PLANTS = {0: ["--plant", "green"], 1: ["--plant", "red"], 2: ["--root", "/dev/null"]}
RED_IS = "FINDING"

FINDING, UNTAKEN, FAILURE = "FINDING", "UNTAKEN", "FAILURE"

# ---- the INTERPRETER, READ FROM THE SHEBANG. THIS REPLACES A SUFFIX SET, WITH A DECLARATION ---
# WHAT WAS WRONG, MEASURED, AND IT IS THE FIFTH OF THE SHELL-GATE SHAPES `gates/README.md` records.
# `reach()` built every plant's command as `[str(PY), str(gate), *argv]` -- PYTHON, unconditionally
# -- while `gates/gates-pop.py:141` puts `.py` AND `.sh` into ONE population (`SUFFIXES =
# (".py", ".sh")`, 17 of the 133 discovered entry points shipping a shell `#!`). So a `.sh` gate's
# verdict, as measured by this instrument, was the verdict of a Python parser meeting a shebang:
# a `SyntaxError` prints a `File "...", line N` traceback and exits **1**, and 1 is `FAIL` -- the
# one code a shell gate and a Python parser can both produce, so the error is INDISTINGUISHABLE
# from agreement. `checks/sb-gate.sh`'s `refuse()` is `exit 3`, and 3 is invisible to a Python
# parser entirely: **a shell gate that refuses to measure anything can only say so in a shell.**
# `.agents/slop/shellgates/` took the measurement; 17 of 17 are named there.
#
# BUT THE SENTENCE ABOVE IS NOT WHY THE LINE BELOW IS RIGHT. It is right because THE FILE SAYS SO.
# `#!` is a declaration a file ships about itself, and it is the kernel's own rule for what to
# exec; `AGENTS.md`'s doctrine 1 names the alternatives it replaces -- *"A BASENAME SHAPE, A SUFFIX
# SET, AND A HAND LIST ARE NOT POPULATIONS."* The line this replaced WAS a suffix set:
# `if p.suffix != ".py": continue`, which is why the census was silent rather than wrong. **A
# suffix filter does not merely mis-measure the shell half, it makes the shell half INVISIBLE, and
# an instrument that cannot see a population cannot be anything.**
#
# MEASURED AND IT IS NOT FREE: 8 of the 115 `.py` entry points ship NO `#!` AT ALL (`checks/run.py`,
# `gates/i64-shl-gate.py`, and 6 more). Refusing them would have been a second regression -- 8
# gates that reach rc 0 today would have read `UNREACHED`, and a census that reds because a file
# omitted a comment is not a census. So the resolution order is SHEBANG FIRST and only then the
# kind this file can otherwise establish, and **every plant records which of the two it used**, so
# the fallback is a counted number on every run rather than a silent default.
SHELLS = frozenset({"sh", "bash", "zsh", "dash", "ksh", "mksh", "ash"})
_SHEBANG = re.compile(r"^#!\s*(\S.*)$")
_ENV_SKIP = frozenset({"-S", "--split-string", "-i", "--ignore-environment"})


def interpreter(p):
    """`(argv0, kind, declared, why)` for entry point `p` -- the interpreter it SHIPS, by its `#!`.

    `kind` is one of `PYTHON`/`SHELL`/`NODE`/`NONE`, and `NONE` means the file ships no
    interpreter at all. It is NEVER a suffix test, and never an exception: a file that cannot be
    read is `NONE` with a reason, because "this instrument could not read it" and "this file
    declared nothing" are different findings.

    `env` IS RESOLVED rather than taken at its face value: Linux `#!` puts ONE token after the
    interpreter path and the kernel does not run `env` at all, so reading the first token would
    classify every `#!/usr/bin/env X` file as `env` and discriminate nothing.
    """
    try:
        with p.open("rb") as fh:
            first = fh.readline(4096).decode("utf-8", "replace")
    except OSError as e:
        return None, "NONE", "", f"{type(e).__name__}: {e}"
    m = _SHEBANG.match(first.rstrip("\n"))
    if not m:
        return None, "NONE", "", "no `#!` on the first line"
    toks = m.group(1).split()
    if toks and "=" in toks[0] and not toks[0].startswith("="):
        toks.pop(0)                                            # `env FOO=bar python3`
    if toks and toks[0].rsplit("/", 1)[-1] == "env":
        toks.pop(0)
        while toks and (toks[0] in _ENV_SKIP or ("=" in toks[0] and not toks[0].startswith("="))):
            toks.pop(0)
    if not toks:
        return None, "NONE", "", "`#!` present but names no interpreter"
    named = toks[0]
    base = named.rsplit("/", 1)[-1]
    if base.startswith("python"):
        return str(PY), "PYTHON", named, "shebang"
    if base in SHELLS:
        return named, "SHELL", named, "shebang"
    if base in {"node", "nodejs"}:
        return "node", "NODE", named, "shebang"
    return named, "OTHER", named, "shebang"


def refuse(*why):
    """exit 2 = REFUSED, and NOT a verdict. `checks/abi_gate.py`'s rule, in this file's idiom.

    Placed BEFORE any measurement, because an assertion downstream of what it asserts cannot turn
    an exception into a refusal (`checks/census.py`'s docstring records the tree doing exactly that:
    rc 1 and a traceback, which carries no denominator and so counts nowhere).
    """
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    sys.exit(2)


def gates_pop():
    """`gates/gates-pop.py`, loaded BY PATH -- NEVER by name. `gates/` is not a package, and putting
    it on `sys.path` would make `gates_pop` a name any file in the tree could shadow: an instrument
    loaded by a bindable name is an instrument whose POPULATION anybody can choose. This is the same
    loader `gates/gendirs.py`'s two consumers use, for the same reason."""
    p = HERE / "gates-pop.py"
    if not p.is_file():
        refuse("gates/gates-pop.py is gone -- it IS the shared population, and this file has no "
               "second copy of the gate list by design")
    spec = importlib.util.spec_from_file_location("gates_pop", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---- clause V: the exit vocabulary, OWNED BY gatekit.py, LOADED BY PATH --------------
def vocabulary(owner=None):
    """`{code: NAME}` from `gates/gatekit.py`'s module body, or from `owner` when a plant names one.

    `gatekit` OWNS the five verdicts (`AGENTS.md`'s table) and writes them as ONE module-level
    name<-code unpack. Reading that unpack reads the owner's declaration; re-typing
    `{0:"GREEN",1:"RED",3:"REFUSED"}` here would be a SECOND copy of the vocabulary, and a
    runner holding a second copy of a mapping is blind exactly where the copies disagree.

    AMBIGUOUS IS REFUSED, NOT DEFAULTED. Zero unpacks or two means there is no single owner, and
    defaulting to the first silently picks one -- `checks/env-precond.py`'s rule, and the whole
    point of clause V is that a number with no agreed meaning must be named rather than resolved.
    The `owner` parameter exists so that REFUSAL is a claim a plant can falsify.
    """
    p = Path(owner) if owner else HERE / "gatekit.py"
    if not p.is_file():
        refuse(f"{p} is gone -- it OWNS the exit vocabulary and this file has no second copy of it "
               f"by design")
    found = []
    for node in ast.parse(p.read_text(errors="replace")).body:
        targets = node.targets if isinstance(node, ast.Assign) else []
        for tgt in targets:
            if not (isinstance(tgt, ast.Tuple) and len(tgt.elts) > 1
                    and all(isinstance(e, ast.Name) for e in tgt.elts)):
                continue
            try:
                codes = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if isinstance(codes, tuple) and len(codes) == len(tgt.elts):
                found.append(dict(zip(codes, (e.id for e in tgt.elts))))
    if len(found) != 1:
        refuse(f"{p} holds {len(found)} module-level name<-code unpack(s); exactly 1 is required for "
               f"there to be an owner of the exit vocabulary, and an ambiguous owner is REFUSED "
               f"rather than guessed")
    return found[0]


# ---- clause I: the population, shared -----------------------------------------------
def population(root):
    """`(entries, libs)` from `gates-pop.discover()`. The ONLY definition of the population."""
    return gates_pop().discover(root)


def walk_control(root, homes):
    """A LABELLED CONTROL, not the population: the recursive `os.walk` count `coindependent` used.

    It exists to answer one question -- does reusing `discover()` make the disagreement disappear --
    and the answer is printed beside `discover()`'s count. It is never used to decide what is a gate;
    two instruments holding two lists have no authority over each other, and this is the SECOND one
    deliberately, so the difference is visible.

    IT USED `fn.endswith((".py", ".sh"))`, AND THAT MADE IT **UNFALSIFIABLE**: `checks/nan_census.mjs`
    and `checks/bend` -- a TRACKED, EXTENSIONLESS `#!/bin/sh` shim whose NAME IS THE PROGRAM -- can
    never enter a suffix set, so the control's residual could never reach 0 and a control that cannot
    be falsified is DECORATION. **A CONTROL WHOSE ANSWER IS FIXED IN ADVANCE IS NOT A CONTROL.**
    IT USES `interpreter()` -- whose docstring already says it is NEVER a suffix test -- **UNIONED** with
    the `.py`/`.sh` set, and the union is the whole fix. **`interpreter()` ALONE IS **NOT** ENOUGH AND WAS
    MEASURED **NOT** ENOUGH: it answers *"does this file SHIP AN INTERPRETER"*, and **12** GATES SHIP **NO
    `#!`** (`checks/run.py`, `gates/gatekit.py`, …) **AND ARE STILL ENTRY POINTS**. SWAPPING THE SUFFIX SET
    FOR `interpreter()` ALONE **GAINED \`checks/bend\`** — **THE \`HARDEST\` MEMBER \`IN\` \`THE\` TREE**, **AN
    EXTENSIONLESS \`#!/bin/sh\` SHIM** — **AND \`LOST\` **12** REAL GATES.** *** **THE \`CONTROL\` \`CAN\` NOW \`REACH\`
    \`AGREEMENT\` \`BECAUSE\` \`IT\` \`IS\` \`A\` \`SUPERSET\` \`OF\` \`BOTH\` \`QUESTIONS\`, NOT \`BECAUSE\` \`ONE\` \`QUESTION\` IS \`BETTER\`** —
    **AND \`A\` \`CONTROL\` THAT \`CAN\` \`NOT\` \`BE\` \`FALSIFIED\` IS DECORATION, SO \`WHAT\` \`MATTERS\` IS THE \`UNION\`, NOT THE \`VICTOR\`.***
    """
    out = set()
    for home in homes:
        h = root / home
        if not os.path.isdir(h):
            continue
        for dirpath, dirnames, filenames in os.walk(h):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                p = Path(dirpath) / fn
                if fn.endswith((".py", ".sh")) or interpreter(p)[1] != "NONE":
                    out.add(str(p.relative_to(root)))
    return out


# ---- clause II: the DECLARATION, read not executed ---------------------------------
# `RED_IS` IS HERE AND NOT IN A SEPARATE LIST because it is a CONSTANT A GATE SHIPS ABOUT ITSELF,
# so it is discovered by the same module-body walk that finds `VERDICTS`. A name in a tuple in the
# reader could name a gate that moved and could not be checked by the gate it named.
DECL = ("VERDICTS", "PLANTS", "RED_IS")


def declaration(p):
    """`(verdicts, plants, red_is, note)` from the MODULE BODY of `p`, by `ast.literal_eval`.

    NEVER by import: importing a gate RUNS it -- `gates/mixin-op-gate.py`/`gates/beautiful-mnist-gate.py`
    `sys.exit(2)` at module scope, every `gatekit.Gate` clears its own directory at construction, and
    a gate whose only input is missing refuses at import. A declaration is a constant the author
    wrote; `literal_eval` reads exactly that and nothing else.
    """
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError as e:
        return None, None, None, f"UNPARSEABLE ({e.msg} line {e.lineno})"
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            targets = [t for t in node.targets if isinstance(t, ast.Name)]
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            targets = [node.target] if isinstance(node.target, ast.Name) else []
        else:
            continue
        for t in targets:
            if t.id in DECL:
                try:
                    found[t.id] = ast.literal_eval(node.value)
                except (ValueError, SyntaxError, TypeError):
                    found[t.id] = f"NOT A LITERAL"
    # `VERDICTS` IS THE MARKER. A file that names a `PLANTS` variable for its own reasons
    # (`checks/differ.py`, `checks/abi4_gate.py` both do, MEASURED -- my first run reported them
    # MALFORMED, which was a finding about this scanner and not about those files) is NOT a gate
    # that declared a surface. Only a file that ships `VERDICTS` is asked for the rest.
    if "VERDICTS" not in found:
        return None, None, None, ""
    if not isinstance(found["VERDICTS"], dict):
        return None, None, None, "VERDICTS is not a mapping"
    if "PLANTS" in found and not isinstance(found["PLANTS"], dict):
        return None, None, None, "VERDICTS is declared but PLANTS is not a literal mapping"
    if "RED_IS" in found and found["RED_IS"] not in (FINDING, FAILURE, UNTAKEN):
        return None, None, None, f"RED_IS is {found['RED_IS']!r}, not one of the three classes"
    return found["VERDICTS"], found.get("PLANTS"), found.get("RED_IS"), ""


def classify(red_is, reached, verdicts):
    """`(klass, why)` -- WHAT A RED OF THIS GATE MEANS, derived, never listed.

    `UNTAKEN` first, and it is an ABSENCE: the gate has never been seen agree (no rc-0 plant
    reached 0, or no rc 0 declared), so it has no green to have fallen from and a red of it is not
    yet a claim about the tree. That is `repro-rc`'s state -- the second measurement has never been
    taken -- and it is `REFUSED` with the wrong exit code rather than a fourth meaning of red.

    `FINDING` requires BOTH halves: the gate declared `RED_IS="FINDING"` in its own source AND its
    rc-0 plant REACHED 0 in this run. A declaration alone is not enough, because a declaration
    cannot audit itself -- `UNTAKEN` is what an UNEARNED `RED_IS` gets, and the report names it.

    `FAILURE` is the DEFAULT, and therefore also what an undeclared red gets. That is the assertion
    that can be false (plant 4b): if any red could pass by not declaring, the declaration would be
    decoration and the whole reading would collapse into "red is fine".
    """
    green = 0 in reached or 0 not in verdicts
    if not green:
        return UNTAKEN, f"declared {red_is or 'nothing'} but its rc-0 plant never reached 0"
    if red_is == FINDING:
        return FINDING, "declared RED_IS=FINDING and demonstrated green in this run"
    if red_is:
        return FAILURE, f"declared RED_IS={red_is} and demonstrated green: a red is that class"
    return FAILURE, "undeclared and green was demonstrated: a red is charged"


def reach(gate, argv):
    """`(rc, output, how)` for one declared plant, run with the interpreter the GATE SHIPS.

    `how` is `f"{kind} {argv0} ({why})"` and the census prints it, so the interpreter a plant ran
    under is on every row rather than inferred by a reader from this file's source. **A plant that
    runs under the wrong interpreter cannot be distinguished from a FAIL** -- `python checks/x.sh`
    is a `SyntaxError`, prints a traceback naming the file, and exits 1, and 1 is `FAIL`. The
    only defence is for the arm to be visible where the verdict is read.

    A TIMEOUT/EXC is NOT a verdict -- it is this instrument refusing to call an unrun plant a
    dead one, which is `coindependent`'s own rule: "an instrument that has not tried cannot call a
    verdict dead."
    """
    argv0, kind, _declared, why = interpreter(gate)
    if argv0 is None:                          # no `#!`: fall back, and SAY SO on the row
        argv0, kind, why = str(PY), "PYTHON", "NO SHEBANG, defaulted (no `#!` on the first line)"
    cmd = [argv0, str(gate), *[str(a) for a in argv]]
    how = f"{kind} {argv0} [{why}]"
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=TIMEOUT)
        return r.returncode, (r.stdout or "") + (r.stderr or ""), how
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", how
    except Exception as e:                        # a crashed command is still a measurement
        return "EXC", f"{type(e).__name__}: {e}", how


# ---- the report --------------------------------------------------------------------
def report(root, charge=True):
    """The census over `root`: declared / reached / difference, per declaring gate, with every
    UNPLANTED, MISPLANT and NO-GREEN verdict NAMED. Returns rc."""
    gpop = gates_pop()
    vocab = vocabulary()
    entries, libs = population(root)
    if not entries:
        print(f"I  EMPTY POPULATION: no entry point under {'/'.join(gpop.HOMES)}/ -- and an empty "
              f"population\n   cannot fail, which is the defect this file exists for. REFUSED.")
        return 2

    print(f"I  DISCOVERED {len(entries)} entry point(s) under {'/'.join(gpop.HOMES)}/ "
          f"(+{len(libs)} module(s) with no entry guard)\n")
    # WHERE THE HOMES CAME FROM, IN THE CENSUS THAT CONSUMES THEM. `walk_control` below takes
    # `gpop.HOMES` as a PARAMETER, so before `gate_homes()` existed the two lists it compared were
    # the SAME list and the comparison was unfalsifiable -- **A CONTROL FED THE LIST IT IS ABOUT TO
    # CHECK CANNOT DISAGREE.** Printing the derivation next to the population is what makes the
    # difference between "the root set" and "the control's idea of the root set" visible at all,
    # and it is two lines rather than a new population: `report_roots` is `gates-pop`'s, loaded
    # BY PATH, so there is no second copy of anything.
    gpop.report_roots(gpop._derivation(root), indent="   ")
    print(f"I  EXIT VOCABULARY, read from gates/gatekit.py's own module body: "
          f"{', '.join(f'{k}={v}' for k, v in sorted(vocab.items()))} -- the OWNER, by path.\n")
    control = walk_control(root, gpop.HOMES)
    disc = {str(p.relative_to(root)) for p in entries} | {
        str(p.relative_to(root)) for p in libs}
    only_walk = sorted(control - disc)
    print(f"I  POPULATION CONTROL: `discover()` sees {len(disc)} file(s) "
          f"({len(entries)} entries + {len(libs)} libs) vs\n   recursive `os.walk` {len(control)} "
          f"-- reusing the shared function makes the two numbers ONE BY\n   CONSTRUCTION, which is "
          f"not the same as settling which was right. {len(only_walk)} file(s) the\n   recursive "
          f"walk sees and `discover()` does not:")
    for rel in only_walk:
        print(f"I    WALK-ONLY {rel}")
    print()

    declared_total = reached_total = 0
    unplanted = misplant = nogreen = malformed = 0
    unowned = renamed = 0
    declaring = 0
    rows = []
    classes = {}
    # THE POPULATION SPLIT, BY SHEBANG AND NOT BY SUFFIX. The line this replaces was
    # `if p.suffix != ".py": continue`, which is why the 17 shell entry points were neither
    # measured nor counted: a suffix set does not exclude a population, it loses one. `shell` and
    # `noshebang` are DISCOVERED by reading each file's `#!`, and both are PRINTED, because a
    # population a reader cannot see the size of is the defect this file exists to end.
    shell, noshebang, arms = [], [], {}
    for p in entries:
        kind = interpreter(p)[1]
        # ONLY `SHELL` LEAVES THE PYTHON CENSUS, and the reason is that `declaration()` reads a
        # PYTHON module body: a shell script has no `VERDICTS` literal for `ast.literal_eval` to
        # read, so sending it there would report `UNPARSEABLE` on 17 files -- a finding about this
        # reader wearing the costume of a finding about the tree. **A file that ships NO `#!` is
        # NOT a shell file**: it went through `continue` in the first version of this line, and
        # that silently dropped the 8 no-shebang `.py` gates AND every synthetic plant, which is
        # how `--plant green` stopped reaching its own rc 0 and `RED_IS="FINDING"` went UNEARNED.
        # The split is SHELL-AGAINST-EVERYTHING-ELSE, and no-shebang is COUNTED, not routed.
        if kind == "SHELL":
            shell.append(p)
            continue
        if kind != "PYTHON":
            noshebang.append(p)
        verdicts, plants, red_is, note = declaration(p)
        if note:
            malformed += 1
            rows.append((p, None, None, note, (FAILURE, "no readable declaration")))
            continue
        if verdicts is None:
            continue
        declaring += 1
        verdicts = dict(verdicts)
        plants = dict(plants or {})
        reached = {}
        issues = []
        for rc in verdicts:
            declared_total += 1
            if rc not in plants:
                unplanted += 1
                issues.append(f"UNPLANTED {rc} {verdicts[rc]!r} -- declared, no plant")
                continue
            got, _out, how = reach(p, plants[rc])
            arms[how] = arms.get(how, 0) + 1
            if got == rc:
                reached[rc] = got
                reached_total += 1
            elif got in ("TIMEOUT", "EXC"):
                issues.append(f"UNREACHED {rc} {verdicts[rc]!r} -- plant {got}, not tried")
            else:
                misplant += 1
                issues.append(f"MISPLANT  {rc} {verdicts[rc]!r} -- plant {plants[rc]} produced {got}")
        if 0 not in verdicts:
            nogreen += 1
            issues.append("NO-GREEN  -- declares no rc 0, so it can never report agreement")
        for rc in verdicts:
            if rc not in vocab:
                unowned += 1
                issues.append(f"UNOWNED    {rc} {verdicts[rc]!r} -- gates/gatekit.py has no name "
                              f"for this exit code, so a caller aggregating it is guessing")
            elif verdicts[rc] != vocab[rc]:
                # THE HALF THAT WAS MISSING, MEASURED. Checking only `rc not in vocab` is blind to
                # a table that names a code the owner DOES have a name for, differently: it is not
                # UNOWNED, so nothing above fired, and `checks/wallcheck.py` sat at `4: "NO-ROW"`
                # while the owner said `4: "SKIP"` -- and a runner that charges by INTEGER printed
                # the owner's word for a gate that had not said it. That is 1 of 14 verdict tables
                # in 131 discovered entries (`.agents/slop/verdictcollide/`), and the count of
                # UNOWNED codes here was 4, which is why the census was worth writing separately:
                # UNOWNED counted the codes nobody claimed and was blind to the one code two owners
                # claimed in two words. The NAME is compared here, by the owner's own word.
                renamed += 1
                issues.append(f"RENAMED    {rc} {verdicts[rc]!r} -- gates/gatekit.py calls this code "
                              f"{vocab[rc]!r}, so a caller charging by integer prints a word this "
                              f"gate never used")
        klass, why = classify(red_is, reached, verdicts)
        classes[str(p.relative_to(root))] = (klass, why)
        rows.append((p, verdicts, reached, issues, (klass, why)))

    print(f"II DECLARATIONS: {declaring}/{len(entries)} entries declare VERDICTS -- "
          f"{len(entries) - declaring} do not, and each\n   one is a gate whose surface nobody has "
          f"written down (the backlog, counted not hidden)\n")
    # THE ARM, ON EVERY RUN. Every plant this census just executed ran under one of these, and the
    # split is what `gates/gate-surface.py:311` could not see: `[str(PY), str(gate), *argv]` sent a
    # shell gate to python, where a `SyntaxError` prints a traceback and exits 1, and 1 is FAIL.
    for how, n in sorted(arms.items()):
        print(f"II PLANT ARM ({n} plant(s)): {how}")
    if shell:
        print(f"II SHELL HALF: {len(shell)} entry point(s) ship a SHELL `#!` and are therefore NOT "
              f"this census's\n   population -- a `VERDICTS` literal is a PYTHON declaration and "
              f"`ast.literal_eval` cannot\n   read a shell one. They are COUNTED here rather than "
              f"excluded, because the line\n   this replaced (`if p.suffix != \".py\": continue`) "
              f"made them invisible and an instrument\n   that cannot see a population cannot be "
              f"anything. `.agents/slop/shellgates/` measures their real verdicts:\n     "
              + ", ".join(sorted(str(p.relative_to(root)) for p in shell)))
    if noshebang:
        print(f"II NO SHEBANG: {len(noshebang)} entry point(s) ship no `#!`, so their interpreter is "
              f"NOT a\n   declaration and this file falls back to `.venv/bin/python` for them -- "
              f"stated, not assumed:\n     "
              + ", ".join(sorted(str(p.relative_to(root)) for p in noshebang)))
    if malformed:
        print(f"II MALFORMED DECLARATION: {malformed}\n")

    red = 0
    for p, verdicts, reached, issues, (klass, why) in rows:
        rel = str(p.relative_to(root))
        if verdicts is None:
            print(f"II {rel}: MALFORMED -- {issues}  -> class {klass}: {why}")
            red = 1
            continue
        d = "/".join(str(k) for k in sorted(verdicts)) or "-"
        r = "/".join(str(k) for k in sorted(reached)) or "(none)"
        print(f"   {rel:44} declared {d:16} reached {r:10} red={klass}")
        for issue in issues:
            print(f"     RED {rel}: {issue}")
            red = 1

    print()
    print(f"II SURFACE: {declared_total} verdicts declared, {reached_total} reached by a declared "
          f"plant,\n   {declared_total - reached_total} not reached, {unplanted} unplanted, "
          f"{misplant} misplant, {nogreen} NO-GREEN\n")

    # CLAUSE V: THE EXIT-CODE MAPPING, WHICH A RUNNER AGGREGATES ON AND CANNOT INVENT. A code the
    # owner has no name for is CHARGED, because two witnesses disagree about what the number means
    # and a disagreement is not a pass.
    print(f"V EXIT CODES: {unowned} declared verdict code(s) that `gates/gatekit.py` has no name "
          f"for, and {renamed}\n   declared code(s) the owner HAS a name for, under a different one. "
          f"A gate declaring an unowned one is saying `exit {sorted({rc for rc in vocab})}`\n   means "
          f"something here that the tree does not know, and an aggregator either guesses or calls it "
          f"DEAD;\n   a gate declaring a RENAMED one is worse in the way that matters least and most: "
          f"the code is\n   known, so a runner charging by integer silently prints the OWNER'S word "
          f"for a gate that never used it.\n   Both are `refusalsweep`'s failure: a gate that crashes "
          f"where it should have refused cannot say which.\n")

    # CLAUSE IV: THE CLASSES. A RUNNER READS THIS AND NEEDS NO GATE NAME. The three counts are
    # printed before the individual rows because a reader asking "can a runner exist?" wants the
    # shape of the population, not one gate's row -- and because the count is the thing that goes
    # stale, so it carries the reading that made it.
    print(f"IV VERDICT CLASSES -- what a red of each gate means, DERIVED from that gate's own "
          f"declaration\n   and this run's plants. No list anywhere: a class is read off the "
          f"gate that ships it.\n")
    for klass in (FINDING, UNTAKEN, FAILURE):
        names = sorted(n for n, (k, _) in classes.items() if k == klass)
        print(f"IV {klass} ({len(names)}): {', '.join(names) if names else '(none)'}")
    for n in sorted(classes):
        print(f"   {n:44} red={classes[n][0]:8} {classes[n][1]}")
    print(f"IV CHARGE: a red blocks unless its class is FINDING. UNTAKEN and FAILURE both block, "
          f"so\na gate must DEMONSTRATE green and DECLARE itself to earn the single exception.\n")
    if declaring == 0:
        print("III ZERO DECLARATIONS: this instrument measured the exit surface of NOTHING. A run "
              "that\ndeclares no verdict cannot fail, which is the `artefacts_ok()` shape. RED.")
        red = 1
    if charge and red:
        print("III RED: at least one declared verdict has no plant, or a plant missed its verdict, "
              "or a\ngate declares no green, or a gate declares an exit code the tree has no name "
              "for. EACH IS A CLAIM\nOF UNKNOWN VALUE (`AGENTS.md`: \"a check nobody has ever "
              "seen fire is a check of\nunknown value\").")
    print()
    print(f"GATE-SURFACE: {'RED' if red else 'OK'} -- {declaring} gate(s) declare a surface, "
          f"{reached_total}/{declared_total} verdicts reached, {unplanted} unplanted, "
          f"{nogreen} NO-GREEN, {unowned} UNOWNED exit code(s), {renamed} RENAMED exit code(s)")
    return 1 if (charge and red) else 0


# ---- clause III: the two-state plant, plus the blind spot ---------------------------
MAIN = "if __name__ == '__main__':\n    raise SystemExit(0)\n"
# A synthetic gate that returns the rc it is HANDED, so a declared plant reaches any code exactly.
DRIVER = ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 3: 'REFUSED'}\n"
          "PLANTS = {0: [], 1: ['1'], 3: ['3']}\n"
          "if __name__ == '__main__':\n"
          "    sys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)\n")
UNPLANTED = ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 3: 'REFUSED'}\n"
             "PLANTS = {0: []}\n"
             "if __name__ == '__main__':\n"
             "    sys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)\n")
NOGREEN = ("import sys\nVERDICTS = {3: 'REFUSED'}\nPLANTS = {3: ['3']}\n"
           "if __name__ == '__main__':\n"
           "    sys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)\n")
# THE BLIND SPOT, IN A GATE: exits 0, reads nothing, but plants every verdict it declares.
VACUOUS = ("import sys\nVERDICTS = {0: 'PASS'}\nPLANTS = {0: []}\n"
           "if __name__ == '__main__':\n    sys.exit(0)\n")
# PLANTS 4a/4b: ONE gate, differing ONLY in whether it ships RED_IS. Both are fully planted and both
# reach rc 0, so both are demonstrably green and neither is UNTAKEN -- the ONLY difference the class
# can be reading is the declaration. If 4a and 4b ever agree, the declaration is decoration.
CLAIM = ("import sys\nVERDICTS = {0: 'PASS', 1: 'RED'}\nPLANTS = {0: [], 1: ['--red']}\n"
         "if __name__ == '__main__':\n"
         "    sys.exit(1 if '--red' in sys.argv else 0)\n")
FINDING_GATE = CLAIM.replace("PLANTS = ", "RED_IS = 'FINDING'\nPLANTS = ")
# 4c: the UNEARNED case -- declares FINDING and has NO rc-0 plant, so it has never been seen agree.
UNEARNED = ("import sys\nRED_IS = 'FINDING'\nVERDICTS = {0: 'PASS', 1: 'RED'}\nPLANTS = {1: ['--red']}\n"
            "if __name__ == '__main__':\n"
            "    sys.exit(1 if '--red' in sys.argv else 0)\n")
# PLANTS 5a/5b: ONE gate, differing ONLY in whether exit 2 is a code the tree owns. 5a is the
# `checks/dup-gate.py`/`checks/wallcheck.py` shape (2 spelled USAGE); 5b is the
# `gates/gatekit.py` spelling (3 spelled REFUSED). Both are FULLY PLANTED, so both demonstrate
# green -- only the code can be what clause V reads.
UNOWNED_GATE = ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 2: 'USAGE'}\n"
                "PLANTS = {0: ['0'], 1: ['1'], 2: ['2']}\n"
                "if __name__ == '__main__':\n"
                "    sys.exit(int(sys.argv[1]))\n")
OWNED_GATE = UNOWNED_GATE.replace("2: 'USAGE'", "3: 'REFUSED'").replace("2: ['2']", "3: ['3']")
# PLANT 6: THE SHELL HALF, PLANTED. `interpreter()` replaces `[str(PY), str(gate), ...]`, and a
# fix to the interpreter a gate runs under is UNFALSIFIABLE unless a gate that ships a shell `#!`
# is in the population of a run. This one is: `#!/bin/sh`, `$0` on a line, so `gates-pop.py`'s
# own `SH_SELFREF` token classifies it `sh-selfref` and it is an ENTRY -- discovered, not listed.
# It carries `VERDICTS = {0: 'PASS'}` on purpose, because that line is what a Python reader is
# FORBIDDEN to score: in `sh` a spaced `=` is a command named `VERDICTS`, not an assignment, so a
# shell gate has no Python declaration and the census must SAY SO rather than report UNPARSEABLE.
SHELL_GATE = ("#!/bin/sh\n"
              "# a synthetic shell entry point, $0 self-referencing so discover() sees an entrance\n"
              "VERDICTS = {0: 'PASS'}\n"
              'echo "$0 ran under a shell"\nexit 0\n')


def _tree(root):
    """A synthetic tree, and the homes it EARNS rather than declares.

    **A PLANT THAT WROTE ITS OWN ROOT LIST WOULD BE PLANTING THE DEFECT.** The population is
    `gates-pop.discover()`, whose homes are DERIVED from the commit tree by `gate_homes()`, so a
    synthetic tree gets a home the only way a real one does: it holds a gate that names a root,
    refuses on a wrong one and resolves on-repo. MEASURED: without this line `--plant green` fell
    from 8/14 to **3/14**, every new failure reporting `rc=2` -- the EMPTY-POPULATION refusal --
    because `_buckets` enumerated two empty directories. **AN INSTRUMENT THAT REFUSES BECAUSE ITS
    OWN FIXTURE IS EMPTY IS NOT FAILING SAFELY, IT IS FAILING LOUDLY AT THE WRONG SUBJECT.** The
    witness is `gates-pop.GOOD_ROOT`, read BY PATH from the module that owns it, so there is one
    copy; it declares no `VERDICTS`, so it does not join the census's declaring-gate counts.
    """
    (root / "pyproject.toml").write_text("[project]\nname='x'\n")
    (root / "tinybendygrad").mkdir()
    for home in ("checks", "gates"):
        (root / home).mkdir()
        (root / home / "home-witness.py").write_text(gates_pop().GOOD_ROOT)


def _run_report(root, charge=True):
    """`report` with its stdout captured, so a plant can assert what was NAMED rather than only
    that the exit moved. A plant that checks the rc alone cannot tell naming from silence."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = report(root, charge=charge)
    return rc, buf.getvalue()


def _class_of(root, name, source):
    """`(rc, transcript, klass)` for a census over a synthetic tree holding ONE gate."""
    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        _tree(r)
        (r / "checks" / name).write_text(source)
        rc, said = _run_report(r)
    klass = next((line.split("red=")[1].split()[0] for line in said.splitlines()
                  if f"checks/{name}" in line and "red=" in line), "")
    return rc, said, klass


def plants(red=False):
    """THREE plants, asserting THREE different directions, on SYNTHETIC trees only. Returns rc.

    `red=True` is not a ninth assertion -- it is THIS GATE'S OWN RED, charged, which is what
    `PLANTS[1]` has to reach or `RED_IS="FINDING"` would be an unearned claim. A gate cannot
    demonstrate the direction it exists in by asserting it can pass.

    PLANT 1 -- an UNPLANTED verdict is RED **and NAMED**. `rc==1` alone is satisfiable by a gate
    that reds on everything, so the assertion is on the WORD: the verdict's token and its code must
    appear in the transcript.
    PLANT 2 -- every verdict planted is GREEN. The control direction: a checker that never passes
    has shown nothing (`coindependent`: "a gate demonstrated only in its green state has shown
    nothing" -- and the converse is equally true).
    PLANT 3 -- the BLIND SPOT, ASSERTED NOT HIDDEN. A gate that exits 0 having read NOTHING is
    PASSED by this file. That is the `checks/citation-gate.py` shape -- green against a root that
    does not exist -- and this file CANNOT distinguish it from agreement without a per-gate "did
    you read your input" assertion. Asserting the limit is the honest alternative to promising a
    discrimination this instrument does not have.
    PLANT 4 -- THE CLASSES, AND 4b IS THE ONE THAT MATTERS MOST. 4a and 4b are the SAME gate with
    one constant differing; both are fully planted, so both have demonstrated green, and only the
    declaration can be what the class reads. 4c is the UNEARNED declaration: a FINDING claim on a
    gate that has never reached 0 is `UNTAKEN`, not `FINDING`, because a declaration cannot audit
    itself.
    """
    if red:
        with tempfile.TemporaryDirectory() as td:
            r = Path(td)
            _tree(r)
            (r / "checks" / "unplanted.py").write_text(UNPLANTED)
            return _run_report(r, charge=True)[0]

    rc = 0
    checks = []

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "unplanted.py").write_text(UNPLANTED)
        got, said = _run_report(r)
        named = ("FAIL" in said and "UNPLANTED 1" in said and "UNPLANTED 3" in said
                 and "REFUSED" in said)
        checks.append(("1: an UNPLANTED verdict is RED and the verdict is NAMED", got == 1 and named,
                       f"rc={got} named 'UNPLANTED 1'/'UNPLANTED 3'/FAIL/REFUSED={named}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "planted.py").write_text(DRIVER)
        got, said = _run_report(r)
        checks.append(("2: every verdict planted is GREEN", got == 0 and "GATE-SURFACE: OK" in said,
                       f"rc={got} said_ok={'GATE-SURFACE: OK' in said}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "nogreen.py").write_text(NOGREEN)
        got, said = _run_report(r)
        checks.append(("3a: a gate that declares NO GREEN is RED (real surface ZERO)",
                       got == 1 and "NO-GREEN" in said, f"rc={got} named_NO-GREEN={'NO-GREEN' in said}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "vacuous.py").write_text(VACUOUS)
        got, said = _run_report(r)
        blind = got == 0
        checks.append(("3b: THE BLIND SPOT, ASSERTED -- a plant that exits 0 having read NOTHING is "
                       "PASSED. This file cannot tell green-correct from green-vacuous without a "
                       "per-gate input assertion.", blind,
                       f"rc={got} -- the honest limit, not a hidden one"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "empty.py").write_text(MAIN)
        got, _said = _run_report(r)
        checks.append(("3c: ZERO declaring gates is RED, never a vacuous green", got == 1,
                       f"rc={got}"))

    got, _said, klass = _class_of(None, "claimed.py", FINDING_GATE)
    checks.append(("4a: a gate that DECLARES RED_IS=FINDING and reached rc 0 is class FINDING",
                   klass == FINDING, f"class={klass!r}"))

    got, _said, klass = _class_of(None, "claimed.py", CLAIM)
    checks.append(("4b: THE SAME GATE, `RED_IS` DELETED -- an UNDECLARED red is class FAILURE and is "
                   "CHARGED. Without this plant the declaration would be decoration and every red "
                   "would pass.", klass == FAILURE, f"class={klass!r}"))

    got, _said, klass = _class_of(None, "claimed.py", UNEARNED)
    checks.append(("4c: a FINDING claim on a gate that has NEVER reached rc 0 is UNTAKEN, not "
                   "FINDING -- a declaration cannot audit itself",
                   klass == UNTAKEN, f"class={klass!r}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "usage.py").write_text(UNOWNED_GATE)
        got, said = _run_report(r)
        named = "RED checks/usage.py: UNOWNED" in said and "'USAGE'" in said
        checks.append(("5a: a declared exit code `gates/gatekit.py` has no name for is RED and the "
                       "code AND its token are NAMED -- `checks/dup-gate.py`'s shape", got == 1 and named,
                       f"rc={got} named_UNOWNED={named}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "usage.py").write_text(OWNED_GATE)
        got, said = _run_report(r)
        flagged = "checks/usage.py: UNOWNED" in said
        checks.append(("5b: THE SAME GATE with 2 spelled as gatekit spells 3 -- an OWNED code is not "
                       "flagged, or 5a is a checker that reds on every code", got == 0 and not flagged,
                       f"rc={got} flagged={flagged}"))

    # 5c: the REFUSAL is falsifiable, or "an ambiguous owner is REFUSED" is a sentence.
    def _refused(src):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "owner.py"
            p.write_text(src)
            try:
                vocabulary(owner=p)
                return 0, ""
            except SystemExit as e:
                return e.code, "REFUSED" if e.code == 2 else "WRONG CODE"

    one, _said = _refused("X = 1\n")
    two, _said = _refused("A, B = 0, 3\nC, D = 1, 4\n")
    checks.append(("5c: ZERO or TWO module-level unpacks in the vocabulary's owner is exit 2 "
                   "REFUSED, never a default -- an ambiguous owner is the one thing clause V exists "
                   "for", one == 2 and two == 2, f"rc={one}/{two}"))

    # PLANT 6 -- THE ARM, IN BOTH DIRECTIONS. Three assertions, because the fix has three parts
    # and any one of them can rot silently: read a SHELL shebang; resolve `env` instead of taking
    # its name; and put a shell gate in a real population and assert the census COUNTS it rather
    # than reporting it malformed. The third is the one that matters: without it, 6a and 6b would
    # pass while `report()` still filtered shell gates out and the census still read 0 of them.
    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        _tree(r)
        (r / "checks" / "shellgate.sh").write_text(SHELL_GATE)
        argv0, kind, declared, _why = interpreter(r / "checks" / "shellgate.sh")
        arm_ok = kind == "SHELL" and argv0 == "/bin/sh"
        got, said = _run_report(r)
        counted = "II SHELL HALF: 1 entry point(s) ship a SHELL" in said
        # A shell gate in the population must NOT become a MALFORMED red: `rc` is whatever the
        # Python half earned, and a run whose only shell gate reads MALFORMED has regressed to
        # `ast.parse` on a shell script.
        not_red = "shellgate.sh: MALFORMED" not in said
        checks.append(("6a: a `#!/bin/sh` entry point is run with a SHELL and is COUNTED in the "
                       "census's SHELL HALF, not parsed as python and not called malformed",
                       arm_ok and counted and not_red,
                       f"argv0={argv0!r} kind={kind!r} declared={declared!r} "
                       f"counted={counted} not_malformed={not_red} rc={got}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        _tree(r)
        (r / "checks" / "envgate.py").write_text("#!/usr/bin/env python3\n" + MAIN)
        argv0, kind, declared, _why = interpreter(r / "checks" / "envgate.py")
        # `env` must be RESOLVED: reading the first token makes every `#!/usr/bin/env X` classify
        # as `env`, which discriminates nothing and is how a reader could believe 0 gates were fixed.
        ok = kind == "PYTHON" and declared == "python3" and argv0 == str(PY)
        checks.append(("6b: `#!/usr/bin/env python3` is RESOLVED to the PYTHON arm -- the token "
                       "after `env` is the declaration, and the arm is `.venv/bin/python` because "
                       "PATH's 3.14 has no `.pth`", ok,
                       f"argv0={argv0!r} kind={kind!r} declared={declared!r}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td)
        _tree(r)
        (r / "checks" / "bare.py").write_text(MAIN)          # NO shebang at all
        argv0, kind, declared, why = interpreter(r / "checks" / "bare.py")
        # A no-shebang file must be a NAMED state, not a silent default: 8 of the tree's own `.py`
        # entry points ship none, and `arm()` falls back for them on purpose -- so the fallback has
        # to be visible on the row, which is what `reach()`'s `how` is for.
        checks.append(("6c: a file shipping NO `#!` reports kind NONE with a reason rather than "
                       "guessing an interpreter from its suffix -- 8 of the tree's `.py` entry "
                       "points are exactly this shape", kind == "NONE" and argv0 is None and why,
                       f"argv0={argv0!r} kind={kind!r} why={why!r}"))

    print("PLANTS -- three directions, the blind spot, and the classes, because an instrument that "
          "hides\nits own blind spot is the defect this project has catalogued twenty times")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    return rc


def main():
    ap = argparse.ArgumentParser(
        prog="gates/gate-surface.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="DENOMINATOR: every entry point `gates-pop.discover()` finds. A verdict with no "
               "denominator is a claim nobody can check.")
    ap.add_argument("--plant", choices=("green", "red"), default=None,
                    help="the self-test on synthetic trees; never touches the live tree. `green` is "
                         "the eight assertions, `red` is this gate's own RED, charged -- which is "
                         "what `PLANTS[1]` reaches")
    ap.add_argument("--report", action="store_true",
                    help="the census only; rc is never charged, so a red surface does not fail a run")
    ap.add_argument("--root", default=None, help="point at another tree (plant only)")
    a = ap.parse_args()
    if a.plant == "red":
        return plants(red=True)
    if not a.root:
        for marker in ("pyproject.toml", "tinybendygrad"):
            if not (ROOT / marker).exists():
                refuse(f"the repo root is not here: {marker} is absent at {ROOT}")
        return plants() if a.plant else report(ROOT, charge=not a.report)
    return plants() if a.plant else report(Path(a.root).resolve(), charge=not a.report)


if __name__ == "__main__":
    sys.exit(main())
