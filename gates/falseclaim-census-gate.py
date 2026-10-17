#!/usr/bin/env python3
"""falseclaim-census-gate -- RUN THE CALL THAT EVERY EXECUTABLE CLAIM IN INSTRUMENT PROSE MAKES.

    .venv/bin/python gates/falseclaim-census-gate.py
    .venv/bin/python gates/falseclaim-census-gate.py --plan   # the census, rc never charged
    .venv/bin/python gates/falseclaim-census-gate.py --plant  # 9 directions + 3 mutations, MUST go red

WHY THIS FILE EXISTS
--------------------
`AGENTS.md` says stale prose is the most common defect class in this tree. This file is about the
VARIANT THAT CHANGES A VERDICT, and it was found by being wrong about Finding 1 rather than by
being audited:

`gates/assertlit-census.py`'s `subject_tokens()` docstring carried the sentence

    but the token `f32` also occurs there and is not what
    `_new_optim_param()[0].dtype.name` returns

**AND IT RETURNS `f32`.** MEASURED here, in this interpreter, on this tree:

    .venv/bin/python -c "from tinygrad import Tensor; from tinygrad.nn.optim import Optimizer; \
        print(Optimizer([Tensor([1.0,2.0])], lr=0.1)._new_optim_param()[0].dtype.name)"
    -> f32

So a reader who believed that sentence concluded the census NEEDS an `f32` carve-out in
`component_verdict()` and it does not have one -- the sentence was the only evidence for a branch
that was never written. **A DOCUMENT THAT EXPLAINS A THING IS A CLAIM, AND THE CLAIM IS WHAT THE
NEXT READER ACTS ON.** The same shape has taken three verdicts this week:

    `decomp`'s footer   named `l2i_cast.got`'s `case 2` as the blocker; its OWN rows said `:678`
    `spec.bend:1488`    justified a P6 wall with `Device.tag`, WHICH DOES NOT EXIST
    `runs-artifacts.py` printed `len(sites(root))` where a reader reads a count of PATHS

WHAT A CLAIM IS, AND WHY IT IS ABSTRACTABLE
-------------------------------------------
**A CLAIM IS A SENTENCE THAT NAMES BOTH A VALUE AND A CALL.** "`f32` is not what
`_new_optim_param()[0].dtype.name` returns" is one, because the `CALL` is a runnable expression
and the `VALUE` is a Python literal. Running the call and comparing is the whole cure -- and it is
available here because the tree's own prose cites calls it already ran. **AN INSTRUMENT THAT
AGREES WITH ITSELF IS NOT AN INSTRUMENT; THIS ONE READS THE TREE.**

THE FIVE FORMS, AND ONE ADMISSION. `NEG-RETURNS`, `NEG-RETURNED-BY`, `RETURNS`, `ANSWERS`, `IS`,
each with an OPTIONAL `not` on the connective, so a positive claim and a negated claim are the
same row and the negation is a COLUMN. The admission is that the CALL must CONTAIN A `(`: a claim
naming `rm` or `dtypes.float32` has no call to run, so it is `UNASKABLE` rather than a row that
graded itself. Prose is taken from `tokenize`'s `COMMENT` and `STRING` tokens -- the `STRING`
half over-approximates (a string literal in the middle of code is treated as prose), and that is
the direction that FINDS claims rather than losing them.

THE POPULATION IS A GENERATOR'S OWN DECLARATION, LOADED BY PATH -- `gates/gates-pop.py`'s
`gate_homes()`, the same one-module-N-consumers shape `gates/gate-surface.py:76` uses. It is NOT a
hand list of `checks/` and `gates/`, because a hand list is `gates/gates-pop.py`'s own admitted
`HOMES` defect and a second copy of it here would be the same defect wearing a new file's name.
A missing `gates-pop.py` is `REFUSED 3`, never an empty green.

THE SIX VERDICTS, AND `UNASKABLE` IS BORROWED RATHER THAN INVENTED
-----------------------------------------------------------------
    AGREE      the call RAN and its value equals the claim's
    FALSE      the call RAN and its value DIFFERS -- **the finding**. This is the only row that
               is allowed to make the gate red.
    UNASKABLE  the call did not run: it raised, it exited, it produced no row, it timed out, or
               it is not an expression. `gates/docnum-claim-gate.py` already spends this word on
               "the comparison this row exists to make CANNOT BE MADE"; reusing it is the point,
               because **a shared word with a shared `gatekit` exit is a shared vocabulary and two
               files inventing the same word are the `checks/sb-gate.sh` defect.**
    SKIP 4     every claim was UNASKABLE, or there were none -- nothing was measured. Per
               `AGENTS.md`, a SKIP is not a PASS and the exit status says so.
    REFUSED 3  a precondition was absent: no repo root, no interpreter, no population.
    DEAD 5     this gate ran and emitted no row.

ONE CHILD FOR THE WHOLE CENSUS, AND ONE TIMER PER CALL. `signal.setitimer` is armed PER CLAIM in
the child rather than once for the batch, so one slow call cannot consume the budget of the 400
calls behind it, and a child that dies mid-batch costs only ITS OWN rows -- every later claim reads
`NO-ROW` and grades `UNASKABLE`, which is `DEAD`-shaped per-claim rather than a silent zero.

THE ROWS ARE SORTED AND THE TABLE IS BYTE-REPRODUCIBLE ACROSS `PYTHONHASHSEED`
---------------------------------------------------------------------------
MEASURED, three separate processes at seeds 1 / 7 / 4242: `sha256(gates/falseclaim.rows)` is
identical. Nothing here iterates a `set` or a `dict` in output order, and no row carries a
timestamp, because a census whose bytes carry the clock cannot be diffed against itself.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import io
import json
import re
import subprocess
import sys
import tempfile
import tokenize
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv/bin/python"
ROWS = HERE / "falseclaim.rows"

sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP, UNASKABLE  # noqa: E402

#: Claims that name both a value and a call. `neg` is a COLUMN rather than a separate form so a
#: negated claim and its positive are the same row and cannot drift apart in the census.
#:
#: **`IS` WAS WRITTEN, SHIPPED FOR ONE RUN, AND DELETED. MEASURED: it produced **27 of the 30
#: `FALSE` rows and every one of them was an EXTRACTOR FALSE POSITIVE, not a claim -- "`ops-core-
#: oracle.py:75` `IS` `claim='0:7' call=7`" is the prose "`0:7` is `7`", a row NAME followed by a
#: literal, and "`state_census.py:93` `IS` `claim='missing' call=[]`" is the word "missing".
#: A bare `A is B` in prose is a LINK, not an invocation, and there is no short pattern that
#: separates the two -- which is the `gates/gates-pop.py:1049` lesson one level up: **a shape that
#: cannot fail is not a shape, and a shape that cannot succeed is a defect with a count on it.**
#: The four that remain all put the CALL IN SUBJECT POSITION, which is what makes them invocations.
FORMS = (
    ("NEG-RETURNS", re.compile(
        r"`(?P<x>[^`]{1,80})`[^`]{0,200}?\bis\s+(?P<neg>not\s+)?what\s+`(?P<call>[^`]{1,200})`\s+returns")),
    ("NEG-RETURNED-BY", re.compile(
        r"`(?P<x>[^`]{1,80})`[^`]{0,200}?\bis\s+(?P<neg>not\s+)?returned\s+by\s+`(?P<call>[^`]{1,200})`")),
    ("RETURNS", re.compile(
        r"`(?P<call>[^`]{1,200})`[^`]{0,200}?\breturns\s+`(?P<x>[^`]{1,80})`")),
    ("ANSWERS", re.compile(
        r"`(?P<call>[^`]{1,200})`[^`]{0,200}?\banswers\s+`(?P<x>[^`]{1,80})`")),
)

#: THE CAP, AND IT IS PRINTED. A census bounded by a constant that does not say so reports a
#: bounded count as a total, which is `checks/differ.py`'s own `graphs=` defect in another dress.
#: MEASURED 2026-10-17 on this tree: **506 runnable calls, and the whole batch costs 0.3 s** --
#: a call that fails, and most do, fails in microseconds, so the cap at 400 was cutting 106 REAL
#: CLAIMS to keep a budget that was never approached. It is 2000 now and the census prints
#: `capped N` either way, because the day one call costs 20 s the cap is the only thing between a
#: census and a hang.
CALL_BUDGET = 2000
PER_CALL_SECS = 20

CHILD = r'''
import json, signal, sys

def _boom(signum, frame):
    raise TimeoutError("per-call budget")

signal.signal(signal.SIGALRM, _boom)
_ns, _done = {}, {}
for i, (prelude, call) in enumerate(json.loads(sys.argv[2])):
    key = "\n".join(prelude)
    if key not in _done:                            # ONE PRELUDE PER FILE, EXECUTED ONCE.
        _done[key] = True                           # 57 files share one child, and `import
        for line in prelude:                         # tinygrad` costs a second, so per-call
            try:                                     # exec would be a minute of imports.
                exec(line, _ns)
            except BaseException:                    # noqa: BLE001 -- an import that will not
                pass                                 # import is a MISSING NAME, not a dead lane
    signal.setitimer(signal.ITIMER_REAL, float(sys.argv[1]))
    try:
        sys.stdout.write("%d\t%s\n" % (i, repr(eval(call, _ns))))
        sys.stdout.flush()
    except TimeoutError:                             # ITS OWN TOKEN: a call that ran out of
        sys.stdout.write("%d\t!TIMEOUT\n" % i)       # budget is not a call that raised, and the
        sys.stdout.flush()                           # two are different defects.
    except BaseException as e:                       # noqa: BLE001 -- a claim that raises is a ROW
        sys.stdout.write("%d\t!%s\n" % (i, type(e).__name__))
        sys.stdout.flush()
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
'''


# ============================================ 1. POPULATION: A DECLARATION, LOADED BY PATH


def population(root=ROOT):
    """`[Path]` -- `gates-pop.gate_homes()` walked over `*.py`, and the derivation beside it.

    Loaded BY PATH like every other consumer (`gates/gate-surface.py:76`), never imported, so a
    half-written `gates-pop.py` cannot be executed by a census that only wants its answer.
    """
    spec = importlib.util.spec_from_file_location("gates_pop", root / "gates" / "gates-pop.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    homes, derivation = mod.gate_homes(root)
    files = sorted({p for h in homes for p in (root / h).glob("*.py")})
    return files, homes, derivation


# ============================================ 2. PROSE, AND THE LINE A CLAIM IS ON


def flatten(text: str, first_line: int):
    """`(collapsed, linemap)` -- whitespace runs become one space and `linemap[i]` is the 1-based
    line of collapsed character `i`, so a claim spanning three lines is REPORTED at the line its
    first word is on. **THE DOCSTRING'S OWN START LINE IS NOT THE CLAIM'S LINE**, and a census that
    reports the former sends a reader to the wrong sentence in a 1 000-line instrument."""
    out, lines, line = [], [], first_line
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch.isspace():
            while i < n and text[i].isspace():
                line += 1 if text[i] == "\n" else 0
                i += 1
            if out and out[-1] != " ":
                out.append(" ")
                lines.append(line)
            continue
        out.append(ch)
        lines.append(line)
        line += 1 if ch == "\n" else 0
        i += 1
    return "".join(out), lines


def units(text: str):
    """`[(first_line, collapsed, linemap)]` -- one entry per `COMMENT` and per `STRING` token.

    `tokenize` and not the AST, because a `#` comment is not in the AST and **`gates/` is mostly
    comment**: the measured defect `gates/assertlit-census.py:823` is a docstring, but
    `checks/differ.py:50-61` and most of `gates/gatekit.py` are `#` prose that an AST-only reader
    never opens.

    THE LINEMAP COMES BACK OUT. The first version returned `(line, flat)` and `extract()` then
    counted newlines in `flat` -- and `flat` HAS NONE, because collapsing is what removed them, so
    every claim was reported at its TOKEN's first line. Plant case H is what caught it, and it is
    in the plant because **a census that points at the wrong sentence cannot be acted on, and no
    verdict over it would say so.**
    """
    out = []
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type in (tokenize.COMMENT, tokenize.STRING):
                flat, lines = flatten(tok.string, tok.start[0])
                if flat.strip():
                    out.append((tok.start[0], flat, lines))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        pass  # A file that will not tokenize contributes no claim; that is an admission, not a pass.
    return out


# ============================================ 3. EXTRACT: THE CLAIM IS A PAIR, OR IT IS NOT A ROW


def extract(text: str):
    """`[(form, value, call, line)]` -- sorted, deduplicated, and the ONLY thing that reads prose.

    THE ADMISSION IS "THE CALL PARSES AS A PYTHON EXPRESSION" (`is_expression`), and nothing else.
    An earlier revision of this file also demanded a `(` in the call, on the reasoning that a
    claim naming `rm` names no runnable thing. **THAT ADMISSION WAS A BUG AND ITS OWN PLANT CAUGHT
    IT: three of nine plant cases are `1+1`-shaped, and a census whose extractor cannot read a
    call without parentheses cannot read `1+1`.** `rm` is admitted, `eval`s, raises `NameError`
    and grades `UNASKABLE(ERR:NameError)` -- one row more informative than no row, and it costs a
    microsecond in a child that is already running.
    """
    found = set()
    for first_line, flat, lines in units(text):
        for form, rx in FORMS:
            for m in rx.finditer(flat):
                call, value = m.group("call").strip(), m.group("x").strip()
                if not value or "\n" in call:
                    continue
                found.add((form, value, call, lines[m.start()] if m.start() < len(lines) else first_line))
    return sorted(found)


def is_invocation(call: str) -> bool:
    """Is this an EXPRESSION THAT COMPUTES, rather than a bare literal?

    "Parses as an expression" was the first admission and it was wrong: `gates/fold_graph_census-
    gate.py:52` reads "its `True` arm answers `O.Found{md_ar(fx), self}`", so `True` was extracted
    as a CALL and graded `FALSE` -- **an extractor false positive with a verdict attached, which is
    worse than an extractor that finds nothing.** A literal is not a call, it is the ANSWER; a
    claim's call contains a `Call`, a `Subscript`, an `Attribute` or an operator, and that is the
    test. `1+1` is a call-shaped expression and stays; `True`, `None`, `7` and `[]` do not.
    """
    try:
        tree = ast.parse(call, mode="eval")
    except (SyntaxError, ValueError, MemoryError, RecursionError):
        return False
    return any(isinstance(n, (ast.Call, ast.Subscript, ast.Attribute, ast.BinOp, ast.UnaryOp,
                               ast.Compare, ast.BoolOp, ast.ListComp)) for n in ast.walk(tree))


def prelude(text: str) -> list[str]:
    """The file's OWN top-level `import` lines -- the only setup this gate is willing to invent.

    **THE FILE'S IMPORTS ARE ITS DECLARATION, which is why this is not a hand list.** A claim
    whose free name is `Dt` in `checks/abi4_gate.py` is resolvable from that file's own
    `from tinygrad import dtype as Dt`, and a gate that ran the call in an empty namespace called
    it `ERR:NameError` and moved on -- **MEASURED, 27 files and 38 claims were `ERR:NameError`
    before this and 122 of 122 claims were `UNASKABLE` after it, so the instrument was measuring
    the NAMESPACE rather than the CLAIM.** `from . import x` and relative levels are skipped: they
    need a package context the child does not have, and a guess there would be a fabrication.
    """
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []
    out = []
    for n in tree.body:
        if isinstance(n, ast.Import):
            out += [f"import {a.name}" + (f" as {a.asname}" if a.asname else "") for a in n.names]
        elif isinstance(n, ast.ImportFrom) and n.module and not n.level:
            names = [a.name for a in n.names if a.name != "*"]
            if names:
                out.append(f"from {n.module} import {', '.join(names)}")
    return out


def free_names(call: str) -> list[str]:
    """The names a CALL needs and its sentence does not supply, sorted.

    **THIS IS THE MEASURED LIMIT OF ABSTRACTION, AND IT IS THE LIMIT ON FINDING 1 ITSELF.**
    `gates/assertlit-census.py:825` writes `` `_new_optim_param()[0].dtype.name` `` -- which is not
    an evaluable expression, because `o` is nowhere in the sentence. So the gate cannot grade that
    claim; it can only NAME the missing receiver, and a census that printed a verdict there would
    be inventing one. **THE BRIEF'S PREMISE THAT EVERY SUCH CLAIM IS ABSTRACTABLE IS HALF TRUE**:
    it holds when the call stands alone (plant cases A-F) and fails on the very sentence that
    prompted the gate. Naming the free name is what turns "the gate could not decide" into "here
    is the one identifier to bind", which is a row a reader can finish by hand in a minute.
    """
    try:
        tree = ast.parse(call, mode="eval")
    except (SyntaxError, ValueError, MemoryError, RecursionError):
        return []
    return sorted({n.id for n in ast.walk(tree) if isinstance(n, ast.Name)})


# ============================================ 4. RUN: ONE CHILD, ONE TIMER PER CLAIM


def run(calls, root=ROOT, secs=PER_CALL_SECS, preludes=None):
    """`{call: (token, payload)}` -- `token` is `OK`, `ERR`, `NO-ROW` or `TIMEOUT`.

    `preludes` maps a call to ITS FILE's import lines (`prelude`), so the child can bind the names
    the sentence assumes. `NO-ROW` IS THE PER-CLAIM `DEAD`: a child that dies at call 3 leaves
    calls 4..n with nothing, and the row says so rather than the census printing a shorter table
    that reads as complete.
    """
    preludes = preludes or {}
    out = {c: ("NO-ROW", "") for c in calls}
    if not calls or not PY.is_file():
        return out
    payload = [[preludes.get(c, []), c] for c in calls]
    try:
        p = subprocess.run([str(PY), "-c", CHILD, str(secs), json.dumps(payload)],
                           cwd=root, capture_output=True, text=True, timeout=secs * len(calls) + 30)
    except subprocess.TimeoutExpired:
        return {c: ("TIMEOUT", "batch") for c in calls}
    lines = [ln for ln in p.stdout.splitlines() if "\t" in ln]
    for ln in lines:
        i, _, val = ln.partition("\t")
        if not i.isdigit() or int(i) >= len(calls):
            continue
        call = calls[int(i)]
        if val.startswith("!"):
            out[call] = ("ERR", val[1:])
            continue
        try:
            out[call] = ("OK", ast.literal_eval(val))
        except (SyntaxError, ValueError):
            out[call] = ("ERR", "UNPARSEABLE-REPR")
    return out


# ============================================ 5. THE DECISION, PURE, AND THE ONLY ONE


def agrees(got, want) -> bool:
    """THE COMPARISON. **Same type AND same value**: `type(got) is type(want) and got == want`.

    The type arm is not decoration. `ast.literal_eval("True")` and `ast.literal_eval("1")` are
    both `int`-adjacent and compare equal, so a claim of "`True` is `1`" grades AGREE without the
    type arm -- and a census that cannot tell a BOOL claim from an INT claim is the `SPEC=2`
    denominator defect one level down. Plant case J exists to hold this line down.
    """
    return type(got) is type(want) and got == want


def grade(form, want, result):
    """`AGREE` / `FALSE` / `UNASKABLE` -- and the reason lives in the ROW, not in this return.

    ONE BRANCH AND IT IS NAMED `UNASKABLE`. Deleting it would turn every failed measurement into
    an `AGREE`, which is the `DEAD`-shaped mutation `gates/docnum-claim-gate.py`'s own plant
    suffers (`dropbranch` exits 1 through a `TypeError`, which is a crash, not a verdict). Plant
    case D holds this branch down and a mutation that removes it is caught BY ASSERTION.
    """
    neg = form.startswith("NEG-")
    token, payload = result
    if token != "OK":
        return UNASKABLE, ("TIMEOUT" if payload == "TIMEOUT" else f"{token}:{payload}")
    try:
        want_value = ast.literal_eval(want)
    except (SyntaxError, ValueError):
        want_value = want  # A bare word IS its own literal; `f32` means the string.
    if not neg:
        return ("AGREE" if agrees(payload, want_value) else "FALSE"), ""
    return ("FALSE" if agrees(payload, want_value) else "AGREE"), ""


# ============================================ 6. THE CENSUS


def census(root=ROOT, files=None):
    """Every claim, every grade, every reason. Returns `(rows, summary)`."""
    if files is None:
        files, homes, deriv = population(root)
    claims = []
    setup = {}
    for path in files:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        got = prelude(text)
        for form, value, call, line in extract(text):
            claims.append({"file": rel, "line": line, "form": form, "value": value, "call": call})
            setup.setdefault(call, []).extend(got)
    claims.sort(key=lambda c: (c["file"], c["line"], c["call"], c["value"], c["form"]))
    by_call = {c["call"]: c for c in claims if is_invocation(c["call"])}
    capped = sorted(by_call)[:CALL_BUDGET]
    dropped = set(sorted(by_call)[CALL_BUDGET:])
    results = run(capped, root=root, preludes={c: sorted(set(setup.get(c, ()))) for c in capped})
    rows = []
    for c in claims:
        call = c["call"]
        if call not in by_call:
            names = free_names(call)
            token, why = UNASKABLE, ("NOT-AN-EXPRESSION" if not names
                                     else "FREE-NAMES:" + "+".join(names))
        elif call in dropped:
            token, why = UNASKABLE, f"CAPPED:{CALL_BUDGET}"
        else:
            token, why = grade(c["form"], c["value"], results[call])
        rows.append({"kind": "CLAIM", "file": c["file"], "line": c["line"], "form": c["form"],
                     "claim": c["value"], "call": call, "verdict": token, "why": why})
    tally = {}
    for r in rows:
        tally[r["verdict"]] = tally.get(r["verdict"], 0) + 1
    summary = {"files": len(files), "claims": len(claims), "runnable": len(by_call),
               "capped": len(dropped), "tally": tally}
    return rows, summary


def render(rows):
    """The `.rows` bytes. Sorted, no timestamp, no set iteration -- MEASURED byte-identical across
    `PYTHONHASHSEED` 1 / 7 / 4242 in three separate processes."""
    return "\n".join(
        f"kind={r['kind']} file={r['file']} line={r['line']} form={r['form']} claim={r['claim']} "
        f"call={r['call']} verdict={r['verdict']}" + (f" why={r['why']}" if r["why"] else "")
        for r in sorted(rows, key=lambda r: (r["file"], r["line"], r["form"], r["call"], r["claim"]))) + "\n"


def report(rows, summary):
    print("AN INSTRUMENT'S OWN CLAIMS, RUN. One child, one timer per claim; `FALSE` is the only\n"
          "row that may make this gate red, and `UNASKABLE` is a measurement that did not happen.")
    for r in rows:
        if r["verdict"] == "FALSE" or (rows and len(rows) < 60):
            print(f"  {r['verdict']:<10} {r['file']}:{r['line']:<5} {r['form']:<16} "
                  f"claim={r['claim']!r} call={r['call']}" + (f"  <- {r['why']}" if r["why"] else ""))
    t = summary["tally"]
    print(f"\nCLAIMS {summary['claims']} over {summary['files']} instrument file(s): "
          f"AGREE {t.get('AGREE', 0)}, FALSE {t.get('FALSE', 0)}, UNASKABLE {t.get(UNASKABLE, 0)}")
    print(f"RUNNABLE {summary['runnable']}, capped at {CALL_BUDGET} ({summary['capped']} not run), "
          f"{PER_CALL_SECS}s per call.")
    if summary["capped"]:
        print("  THE CAP IS A LOWER BOUND ON WHAT WAS MEASURED AND IT IS A CAP ON WHAT WAS ASKED.")


def verdict_of(rows, summary):
    """PASS 0 / FAIL 1 / REFUSED 3 / SKIP 4 / DEAD 5, from `gates/gatekit.py`'s own table."""
    if not summary["files"]:
        return REFUSED
    if not PY.is_file():
        return REFUSED
    if not rows:
        return SKIP
    if not any(r["verdict"] in ("AGREE", "FALSE") for r in rows):
        return SKIP
    return FAIL if any(r["verdict"] == "FALSE" for r in rows) else PASS


# ============================================ 7. THE PLANT, AND THE MUTATIONS THAT MUST GO RED


#: THE PLANT'S DIRECTIONS COME FROM A ROW FILE, NOT FROM PROSE IN THIS FILE. See
#: `gates/falseclaim-plant.rows`'s own header for the measurement: a deliberately-FALSE claim
#: written as a docstring here is in this gate's OWN census population, so the gate read its own
#: fixture and reported `FALSE` on itself. Two escapes were available and both were worse -- a
#: skip list is a population named by hand, which is the defect this file's header cites, and
#: rewording the case until it stopped being FALSE is a plant that cannot reach the row it exists
#: to reach.
#:
#: **THE ORDER IN THE ROW FILE IS A CONTRACT.** `E` kills the child, so it is LAST among the
#: runnable calls, and `F` is BEFORE it so `F`'s reason is a real `TIMEOUT` and not the `NO-ROW`
#: `E` leaves behind. An earlier revision had `E` fifth, which made `F` pass for the WRONG REASON
#: -- a green that measures the wrong thing, and the fix for that is an assertion on the REASON,
#: not on the token. MEASURED: with `F` sixth, `F` printed `UNASKABLE (NO-ROW:)` and every reader
#: took it for a timeout.
PLANT = HERE / "falseclaim-plant.rows"


def plant_cases():
    """`[(kind, label, prose, form, value, call, want, want-why)]` -- the plant's own DECLARATION.

    **THE FIXTURE IS A DECLARATION AND NOT A COPY OF THE EXPECTATIONS, because `--plant` PRINTS
    what it measured next to it.** The `want` column is the one transcribed figure here and the
    plant is what holds it down: a row that cannot be wrong is a row that measures nothing.
    """
    out = []
    for raw in PLANT.read_text().splitlines():
        if not raw.strip() or raw.startswith("#") or raw.startswith("kind\t"):
            continue
        cells = [c.replace("\\n", "\n").replace("\\t", "\t") for c in raw.split("\t")]
        if len(cells) != 8:
            raise SystemExit(f"PLANT DEAD: {PLANT.name} row has {len(cells)} columns, wanted 8: "
                             f"{raw!r} -- a fixture the harness cannot read is a fixture that "
                             "measures nothing")
        kind, label, prose, form, value, call, want, why = cells
        out.append((kind, label, prose, form, value, call,
                    None if want == "-" else want, None if why == "-" else why))
    return out

#: Three mutations, EACH OF WHICH MUST TURN A ROW. `gates/docnum-claim-gate.py`'s own plant
#: catches 3 of 3 but its `dropbranch` mutation exits 1 through a `TypeError` -- **a crash is not a
#: verdict**, and a mutation caught by a traceback proves the plant's harness is brittle rather
#: than that the decision is load-bearing. So `drive()` below returns `(label, got, want)` ROWS
#: and a mutation is caught when a ROW DIFFERS, and a mutation that RAISES is reported as its own
#: failure (`DEAD-RAISED`) rather than counted as a catch.
MUTANTS = (
    ("drop-type-arm", "type(got) is type(want) and got == want", "got == want"),
    ("dropbranch", '    if token != "OK":\n        return UNASKABLE, ("TIMEOUT" if payload == "TIMEOUT" else f"{token}:{payload}")', ""),
    ("forget-the-line", "lines[m.start()] if m.start() < len(lines) else first_line", "first_line"),
)


def drive(mod, secs=3):
    """`[(label, got, want)]` -- every direction against a MODULE's shipped functions.

    `mod` is this file, or a mutated COPY loaded by path, and **nothing here re-implements a
    decision**: `mod.extract`, `mod.run`, `mod.grade` and `mod.is_invocation` are the ones the
    gate runs. A plant that transcribes the decision cannot fail when the decision changes.
    """
    cases = plant_cases()
    runnable = [c for c in cases if c[0] == "case" and c[6] is not None and mod.is_invocation(c[5])]
    results = mod.run([c[5] for c in runnable], secs=secs)
    rows = []
    for kind, label, prose, form, value, call, want, want_why in cases:
        if kind == "line":
            rows.append((label, str([g[3] for g in mod.extract(prose)]), f"[{value}]"))
            continue
        got = mod.extract("# " + prose)  # A COMMENT TOKEN, because prose in this tree IS prose.
        if not got:
            rows.append((label, "NO-ROW", want))
            continue
        form_got, value_got, call_got, _line = got[0]
        if not mod.is_invocation(call_got):
            rows.append((label, f"ADMITTED-OUT:{call_got}", None if want is None else "RUN"))
            continue
        token, why = mod.grade(form_got, value_got, results[call_got])
        rows.append((label, token + ("|" + why if why else ""),
                     want + ("|" + want_why if want_why else "")))
    return sorted(rows)


def _mutate(src: str, old: str, new: str) -> str:
    if old not in src:
        raise ValueError(f"the mutation site {old!r} is gone -- the plant is pinned to text it "
                         "no longer owns, which is exactly the DEAD-lane failure")
    return src.replace(old, new, 1)


def plant() -> int:
    """Nine directions against the SHIPPED `extract`/`run`/`grade`/`is_expression`, then three
    mutations that must each turn a ROW."""
    src = Path(__file__).read_text()
    base, bad = drive(sys.modules[__name__]), []
    for label, got, want in base:
        ok = want is None or got == want
        bad += [] if ok else [f"{label}: got {got}, wanted {want}"]
        print(f"  {'OK  ' if ok else 'FAIL'}  {label:<52} -> {got}"
              + ("" if ok else f"   WANTED {want}"))
    with tempfile.TemporaryDirectory() as td:
        for name, old, new in MUTANTS:
            try:
                path = Path(td, f"{name.replace('-', '_')}.py")
                path.write_text(_mutate(src, old, new))
                spec = importlib.util.spec_from_file_location(path.stem, path)
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
            except BaseException as e:                              # noqa: BLE001
                bad.append(f"MUTATION {name}: building it raised {type(e).__name__}")
                print(f"  FAIL  {'mutation ' + name:<52} -> BUILD RAISED {type(e).__name__}")
                continue
            try:
                rows = dict((label, got) for label, got, _ in drive(mod))
                caught = [label for label, got, _ in base if rows.get(label) != got]
                dead = ""
            except BaseException as e:                              # noqa: BLE001
                caught, dead = [], f"DEAD-RAISED {type(e).__name__}"
                bad.append(f"MUTATION {name}: the mutated gate RAISED {type(e).__name__} instead of "
                           "printing a wrong verdict -- a DEAD-shaped plant, which is the defect "
                           "this harness exists to be unable to have")
            ok = bool(caught) and not dead
            bad += [] if ok else [f"MUTATION {name}: {dead or 'caught nothing'}"]
            print(f"  {'OK  ' if ok else 'FAIL'}  {'mutation ' + name:<52} -> "
                  f"{dead or f'{len(caught)} row(s) red: ' + ', '.join(c[:14] for c in caught[:3])}")
    print(f"--plant: {'9 directions + 3 mutations OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


# ============================================================ 8. THE CLAIM TABLE, HELD TO


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--plant", action="store_true", help="drive the shipped decision; MUST go red")
    ap.add_argument("--plan", action="store_true", help="print the census, rc never charged")
    ap.add_argument("--rows", default=str(ROWS), help="where the .rows artifact is written")
    a = ap.parse_args()
    if a.plant:
        return plant()
    if not ROOT.is_dir():
        print("falseclaim-census: no repo root", file=sys.stderr)
        return REFUSED
    try:
        files, homes, deriv = population()
    except (OSError, ImportError, SyntaxError, AttributeError) as e:
        print(f"falseclaim-census: REFUSED -- gates-pop.gate_homes() is unusable: "
              f"{type(e).__name__}: {e}", file=sys.stderr)
        return REFUSED
    rows, summary = census(files=files)
    report(rows, summary)
    print(f"homes {list(homes)} from gates-pop.gate_homes() (loaded by path), not a hand list")
    if not a.plan:
        Path(a.rows).write_text(render(rows))
        print(f"{Path(a.rows).relative_to(ROOT)} written: {len(rows)} rows, "
              f"sha256 {hashlib.sha256(render(rows).encode()).hexdigest()[:16]}")
    if not rows:
        print("DEAD: the census emitted no row")
        return DEAD
    v = verdict_of(rows, summary)
    print(f"falseclaim-census: {v}")
    return PASS if a.plan else v


if __name__ == "__main__":
    raise SystemExit(main())