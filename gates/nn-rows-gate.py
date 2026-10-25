#!/usr/bin/env python3
"""nn-rows-gate.py -- the COMPARER for `tinybendygrad/nn/layers.bend`'s row harness.

    .venv/bin/python gates/nn-rows-gate.py                  # the live tree
    .venv/bin/python gates/nn-rows-gate.py --plant          # the six class plants, no bend
    .venv/bin/python gates/nn-rows-gate.py --control d       # one control, on a COPY
    .venv/bin/python gates/nn-rows-gate.py --port DIR        # measure an already-made copy

WHAT IT MEASURES. `nn/layers.bend` carries a row harness: `nn_row.line(nm, got, want)`
PRINTS `nm got=<...> want=<...>`. **IT ONLY PRINTS.** There was no comparer for those rows
anywhere in this tree, so every row was a LABEL: a string that named a claim and made it.
This gate is the comparer, and it is the first instrument in the tree that can make those
rows go red.

THE FIVE CLASSES, AND HOW EACH IS DETECTED. All five are decided from the driver's own
stdout and the harness's own source; nothing is transcribed here.

    MATCH        `got` == `want`, exactly.
    MISMATCH     `want` is not empty and `got` != `want`. A SUBSET is SPELLING: the two
                 sides are equal after the SPELLING RULE below (punctuation, and the two
                 dtype spellings), so the row differs only in how it is written. The
                 SPELLING rows are COUNTED AND NAMED because "19 of 31 rows could not pass
                 under exact comparison" is the number this tree needs, and a reader must
                 be able to see WHICH 19 and WHY.
    UNCHECKABLE  `want` is EMPTY and `got` is not. The expectation is absent, so the row
                 CANNOT FAIL: it is a label wearing a row's clothes.
    DEAD-ROW     `want` is empty AND `got` is empty. The row measured NOTHING.
    SHRUNK       a row the harness's own source DECLARES is not PRINTED: either its
                 function is not called from `main` any more, or it is called and its row
                 did not appear. The name is printed, because a population that shrank is
                 only useful if the reader is told WHICH name went.
    EXTRA        a printed row the source does not declare (or declares twice).
    MALFORMED    a non-blank stdout line that is not a row at all.

THE POPULATION IS THE HARNESS'S OWN DECLARATION, LOADED BY PATH. The row names come out
of the copy's `nn/layers.bend` -- the `nn_row.line(...)` call sites, the functions that
contain them, and the calls `main` makes -- and NOT from a hand list and NOT from a
basename shape. A hand list is a contract with no generator and it rots without anyone
noticing; `gates/README.md` records the same defect in `checks/sweep.py`'s `LIVE_UNITS`
and in `gates/gates-pop.py`'s `HOMES`.

THE EXPECTED VALUES LIVE ONLY IN THE `.bend` FILE. This gate reads them from the printed
`want=` column, so there is exactly ONE copy of every expectation. Nothing in this file
holds an expected value.

THE FIVE EXITS ARE `gates/gatekit.py`'s, and this file does not invent a sixth:
`PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5`. `SKIP IS NOT PASS` and `DEAD IS NOT A
ZERO AND NOT A PASS`.

    PASS     every declared row was printed and every printed row matched its `want`.
    FAIL     a class fired. Every failing row is NAMED, with its `got` and its `want`.
    REFUSED  a precondition was absent: no `bin/bend`, no driver, a port that will not
             copy, a port that does not COMPILE (bend named its own failure), or a harness
             whose population this file could not derive. **AN ABSENT SUBJECT IS REFUSED,
             NEVER FAIL** -- and a port that does not compile is the tree's defect, not
             this gate's answer, so the gate refuses and quotes bend.
    DEAD     the driver RAN and emitted no rows at all. A gate that compares nothing and
             exits 0 is worse than no gate, so this is exit 5 and not exit 0.

THE PORT IS COPIED FIRST AND READ SECOND. `tinybendygrad/nn/layers.bend` is being edited
by another agent WHILE this gate runs, so the gate copies the port into a temporary
directory and derives BOTH the population and the rows from that ONE copy. A gate that
read the row names from the live file and ran bend against a copy of it could see a
half-written pair: a name from one revision and a value from another. The copy is the
tree at one instant, to the resolution of a filesystem walk; a file written DURING the
copy may arrive half-written, and then the parse fails or bend names it, and this gate
REFUSES -- which is the honest reading of a half-written tree.

WHAT THIS GATE CANNOT SEE, STATED RATHER THAN LEFT IMPLIED. The population is the same
file the rows come from, so a row whose NAME is deleted from the file shrinks both sides
at once and this gate cannot see it. MEASURED, and reported in
`.agents/slop/nnrowsgate/REPORT.md`: the mutation that fires SHRUNK is the one where the
file still DECLARES the row and the OUTPUT loses it.
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import ART, DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT_NAME = "tinybendygrad"
DRIVER = Path("nn") / "layers.bend"
BEND = ROOT / "bin" / "bend"
GATE = "nn-rows-gate"
OUT = ART / GATE
# THE FROZEN BASELINE, BESIDE THE GATE AND IN GIT -- `AGENTS.md`'s own rule, and the reason it
# is here and not under `.agents/slop/`: A GATE'S REQUIRED INPUT BELONGS BESIDE THE GATE.
# **A BASELINE IS A RECORD, NOT A POPULATION.** THE POPULATION IS STILL THE HARNESS's OWN
# DECLARATION; THE BASELINE IS WHAT MAKES A DELETED ROW NAME VISIBLE.
BASELINE = HERE / "nn-rows-baseline.rows"

# THE CLASS NAMES ARE THE OUTPUT'S VOCABULARY, and every one of them is a name a reader
# can look up. A class with no name is a count nobody can check.
C_MATCH = "MATCH"
C_MISMATCH = "MISMATCH"
C_SPELLING = "SPELLING"        # a SUBSET of C_MISMATCH, not a sixth class
C_UNCHECKABLE = "UNCHECKABLE"
C_DEAD_ROW = "DEAD-ROW"
C_SHRUNK = "SHRUNK"
C_EXTRA = "EXTRA"
C_DUPLICATE = "DUPLICATE"
C_MALFORMED = "MALFORMED"
# THE TWO CLASSES THE FROZEN BASELINE ADDS. `DROPPED` IS A DEFECT AND `ADDED` IS NOT, AND
# THE DIFFERENCE IS THE WHOLE POINT: A ROW NAME THAT LEAVES THE HARNESS IS A ROW THAT STOPPED
# BEING CHECKED, WHILE A ROW NAME THAT ARRIVES IS A ROW THAT STARTED BEING CHECKED.
C_DROPPED = "DROPPED"
C_ADDED = "ADDED"

# THE CLASSES THAT MAKE A GATE RED. `MATCH` is not one of them, and `SPELLING` is a
# SUBSET of `MISMATCH` rather than a class of its own.
FIRED = (C_MISMATCH, C_UNCHECKABLE, C_DEAD_ROW, C_SHRUNK, C_EXTRA, C_DUPLICATE, C_DROPPED)
# `C_ADDED` IS DELIBERATELY NOT IN `FIRED`. A NEW ROW IS A LEGITIMATE ADDITION, AND A GATE
# THAT GOES RED FOR ONE FORCES EVERY ADDITION TO RE-FREEZE THE BASELINE. IT IS REPORTED SO
# THE ADDITION IS VISIBLE, AND THE FREEZE IS A DELIBERATE ACT WITH A VISIBLE DIFF.

# THE MARK a `MISMATCH` row carries when it differs only in SPELLING. It is written in
# ONE place and read in ONE place, so the tag and the count that reports it cannot
# drift apart.
SPELLING_MARK = f"[{C_SPELLING}]"

# THE SPELLING RULE. IT IS A COMPARISON RULE AND NOT A LIST OF EXPECTATIONS: it holds no
# expected VALUE, it is the only place a name is forgiven, and it is printed with every
# run so a reader can audit exactly which rows it forgave. The rule is: the two sides are
# equal as TOKEN LISTS once punctuation is dropped, case is folded, and the two dtype
# spellings the port and the harness use are the same spelling.
DTYPE_SPELLINGS = {"f32": "float32"}
TOKEN = re.compile(r"[^\w.+-]+")


def canonical(text: str):
    """`text` as a token list under the SPELLING RULE. See `DTYPE_SPELLINGS`."""
    return [DTYPE_SPELLINGS.get(t.lower(), t.lower()) for t in TOKEN.split(text) if t]


class Row(NamedTuple):
    """One printed row: `nm got=<...> want=<...>`."""
    name: str
    got: str
    want: str


class Site(NamedTuple):
    """One `nn_row.line(...)` call site, as the harness's own source declares it."""
    fn: str
    line: int
    literal: str | None      # the row name, when the name is a string literal
    pattern: str | None      # a regex for the name, when the name is computed
    expression: str          # the name argument's source text, for the report


class Expected(NamedTuple):
    """THE POPULATION, as the source declares it and as `main` promises to run.

    `literals` and `patterns` hold EVERY declared row, and the `called` flag says
    whether `main` reaches the function that declares it. A row whose function `main`
    does not call is a row that STOPPED EXISTING: the file still declares it and the
    output no longer prints it."""
    literals: tuple          # (name, fn, called)
    patterns: tuple          # (regex, count, fn, called)
    uncalled: tuple          # (fn, n_rows) -- the functions `main` does not reach


# ---------------------------------------------------------------- the source parse


FUNC = re.compile(r"^(\s*)def\s+([A-Za-z_]\w*)\s*\(")
ROW_CALL = "nn_row.line("
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
DYN_NAME = re.compile(r"String\.concat\(\[(.*)\]\)", re.S)
NUM_SHOW = re.compile(r"U32\.show\(\s*([A-Za-z_]\w*)\s*\)")


def _functions(lines):
    """Every `def` in the file with the line range of its body, BY INDENTATION.

    A body's extent is the first later non-blank line whose indent is not deeper than
    the `def`'s. Bend indents by two spaces, and a body that is not delimited by
    indentation would make the "which function is this call site in" question
    unanswerable."""
    out = []
    for i, line in enumerate(lines):
        m = FUNC.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        j = i + 1
        while j < len(lines):
            s = lines[j]
            if s.strip() and len(s) - len(s.lstrip()) <= indent:
                break
            j += 1
        out.append((m.group(2), i, j))
    return out


def _enclosing(defs, line_no):
    """The function whose body holds `line_no`: the innermost one."""
    best = None
    for name, first, last in defs:
        if first <= line_no < last and (best is None or first > best[1]):
            best = (name, first, last)
    return best


def _args(text, open_idx):
    """The spans of a call's top-level arguments. `open_idx` is the index of the `(`.

    Strings are skipped, so a comma inside `"a,b"` is not a separator. Depth is tracked
    over `()[]{}` so a comma inside a nested call is not a separator either."""
    spans, start, depth, i, in_str = [], open_idx + 1, 0, open_idx, False
    while i < len(text):
        ch = text[i]
        if in_str:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                spans.append((start, i))
                return spans
        elif ch == "," and depth == 1:
            spans.append((start, i))
            start = i + 1
        i += 1
    return spans


def _name_of(arg: str):
    """A name argument as `(literal, pattern)`. A literal is the name; a computed name
    is a `String.concat([...])` of literals and `U32.show(x)` reads, whose pattern is the
    concatenation with a DIGIT placeholder where the number goes.

    A name argument this file cannot read is `(None, None)`, and the caller REFUSES
    rather than guessing a population it did not derive."""
    lit = STRING.fullmatch(arg.strip())
    if lit:
        return lit.group(1), None
    dyn = DYN_NAME.fullmatch(arg.strip())
    if dyn:
        parts = []
        full = dyn.group(0)
        spans = _args(full, full.index("["))
        for a, b in spans:
            text = full[a:b].strip()
            s = STRING.fullmatch(text)
            if s:
                parts.append(re.escape(s.group(1)))
                continue
            if NUM_SHOW.fullmatch(text):
                parts.append(r"\d+")
                continue
            return None, None
        return None, "".join(parts)
    return None, None


def parse_source(text: str):
    """THE POPULATION, derived from the harness's own source. `(Expected, sites)`.

    Three questions, and the file answers all three:

    1. WHICH ROWS DOES THE HARNESS DECLARE? The `nn_row.line(...)` call sites, and the
       name each one asks for -- a literal, or a pattern for a computed name.
    2. WHICH OF THOSE DOES `main` RUN? A row function `main` does not reach cannot print,
       and a row that IS declared and is NOT printed is a SHRUNK population -- whether it
       stopped printing or stopped being called.
    3. HOW MANY TIMES? A computed name prints one row per invocation, so the count comes
       from how many times `main` calls that function."""
    lines = text.splitlines()
    defs = _functions(lines)

    sites = []
    for m in re.finditer(re.escape(ROW_CALL), text):
        line_start = text.rfind("\n", 0, m.start()) + 1
        if "def" in text[line_start:m.start()]:
            continue    # the PRINTER's own definition, not a call site
        line_no = text.count("\n", 0, m.start())
        spans = _args(text, m.end() - 1)
        if len(spans) < 3:
            sites.append(Site(fn="?", line=line_no + 1, literal=None, pattern=None,
                              expression=text[m.end() - 1:m.end() + 40]))
            continue
        owner = _enclosing(defs, line_no)
        arg = text[spans[0][0]:spans[0][1]]
        literal, pattern = _name_of(arg)
        sites.append(Site(fn=owner[0] if owner else "?", line=line_no + 1, literal=literal,
                          pattern=pattern, expression=" ".join(arg.split())))

    mains = [d for d in defs if d[0] == "main"]
    main_body = []
    if mains:
        name, first, last = mains[-1]
        main_body = lines[first + 1:last]

    def called_in(body, name):
        pat = re.compile(r"\b" + re.escape(name) + r"\s*\(")
        return sum(len(pat.findall(l)) for l in body)

    # THE REACHABILITY CLOSURE FROM `main`. A row function reached only through another
    # function still promises its rows, so the closure is taken rather than a direct
    # call. The MULTIPLICITY is the call count in `main` when `main` calls the function
    # directly, and otherwise the call count in the bodies of the reachable functions --
    # and the second rule is REPORTED, because it is a weaker claim than the first.
    reachable, frontier = set(), [mains[-1][0] if mains else None]
    while frontier:
        fn = frontier.pop()
        if fn is None or fn in reachable:
            continue
        reachable.add(fn)
        for nm, first, last in defs:
            if nm == fn:
                frontier += re.findall(r"\b([A-Za-z_]\w*)\s*\(", " ".join(lines[first + 1:last]))

    literals, patterns, uncalled = [], [], []
    per_fn = {}
    for site in sites:
        if site.literal is None and site.pattern is None:
            continue
        per_fn[site.fn] = per_fn.get(site.fn, 0) + 1
        called = site.fn in reachable
        if site.literal is not None:
            literals.append((site.literal, site.fn, called))
        elif called:
            mult = called_in(main_body, site.fn) or sum(
                called_in(lines[first + 1:last], site.fn)
                for nm, first, last in defs if nm in reachable and nm != site.fn)
            patterns.append((site.pattern, max(1, mult), site.fn, called))
        else:
            patterns.append((site.pattern, 0, site.fn, called))
    for fn, n in per_fn.items():
        if fn not in reachable:
            uncalled.append((fn, n))
    return Expected(tuple(literals), tuple(patterns), tuple(uncalled)), tuple(sites)


# ---------------------------------------------------------------- the classification


def read_baseline():
    """THE FROZEN BASELINE, LOADED BY PATH. `(names, meta)`.

    **A MISSING BASELINE IS A REFUSAL, NOT A PASS.** The baseline is the thing that makes a
    DELETED ROW NAME visible, so a gate with no baseline is a gate with the hole OPEN, and
    **an absent witness is not a green one.** `names` is `None` when the file is absent or
    holds no row name; `meta` is the header, which is printed so a reader knows WHICH freeze
    the rows came from.
    """
    if not BASELINE.is_file():
        return None, [f"the frozen baseline {BASELINE.name} is absent"]
    try:
        text = BASELINE.read_text()
    except OSError as exc:
        return None, [f"the frozen baseline cannot be read: {exc}"]
    names, meta = set(), []
    for ln in text.splitlines():
        if ln.startswith("#"):
            meta.append(ln)
            continue
        name = ln.strip()
        if name:
            names.add(name)
    if not names:
        return None, [f"the frozen baseline {BASELINE.name} holds no row name"]
    return names, meta


def baseline_delta(baseline_names, printed_names):
    """THE FROZEN BASELINE's DELTA, as a value. `(dropped, added)`.

    A PURE FUNCTION, so a plant can drive it with no bend run at all.

    `dropped` -- a name the baseline has and THIS RUN DID NOT PRINT. **THIS IS THE HOLE THE
    BASELINE CLOSES.** The gate's population is declared by the very file the row was removed
    FROM, so deleting a row name shrinks the declaration AND the output together and nothing
    fires; the baseline is the ONE thing that does not shrink with them.
    `added` -- a name this run printed and the baseline does not have. **NOT A DEFECT**: a new
    row is a legitimate addition, and it is reported so the reader can see that the baseline
    wants re-freezing.
    """
    dropped = [(n, "the frozen baseline has this row name and this run did not print it")
               for n in sorted(baseline_names - printed_names)]
    added = [(n, "this run printed this row name and the frozen baseline does not have it")
             for n in sorted(printed_names - baseline_names)]
    return dropped, added


def classify(rows, expected: Expected, baseline=None) -> dict:
    """THE DECISION, and it is a pure function of the rows, the population and the baseline.

    It returns the CLASS COUNTS -- a class -> [(name, detail)] map -- and nothing else:
    the exit is decided by the caller from the classes, so there is one place where the
    verdict is computed. Every class this gate can report is decided here, and the PLANT
    drives this function directly -- `gates/README.md` records why: "a plant that drives a
    helper is not a plant of the decision."

    `baseline` IS THE FROZEN ROW-NAME SET, OR `None` FOR "NO BASELINE WAS ASKED FOR" -- WHICH
    IS WHAT A PLANT THAT IS ABOUT THE OTHER CLASSES PASSES. **THE BASELINE's TWO CLASSES ARE
    DECIDED HERE AND NOT IN `measure()`, SO A PLANT DRIVES THEM TOO.**"""
    counts = {C_MATCH: [], C_MISMATCH: [], C_UNCHECKABLE: [], C_DEAD_ROW: [],
              C_SHRUNK: [], C_EXTRA: [], C_DUPLICATE: [], C_DROPPED: [], C_ADDED: []}
    printed = {}
    for row in rows:
        printed.setdefault(row.name, []).append(row)

    for name, fn, called in expected.literals:
        if name not in printed:
            counts[C_SHRUNK].append(
                (name, f"declared by {fn} and never printed"
                       + ("" if called else f", and main no longer calls {fn}")))
    for pattern, want_n, fn, called in expected.patterns:
        rx = re.compile(pattern)
        got_n = sum(1 for r in rows if rx.fullmatch(r.name))
        if called and got_n < want_n:
            counts[C_SHRUNK].append(
                (pattern, f"declared by {fn} {want_n} time(s) and printed {got_n}"))

    declared = {n for n, _, _ in expected.literals}
    patterns = [(re.compile(p), n, fn) for p, n, fn, _ in expected.patterns]
    for row in rows:
        if row.name in declared:
            if len(printed[row.name]) > 1:
                counts[C_DUPLICATE].append((row.name, f"printed {len(printed[row.name])} times"))
            continue
        if any(rx.fullmatch(row.name) for rx, _, _ in patterns):
            if sum(1 for r in rows if any(p.fullmatch(r.name) for p, _, _ in patterns)) > \
                    sum(n for _, n, _ in patterns):
                counts[C_DUPLICATE].append((row.name, "printed more times than declared"))
            continue
        counts[C_EXTRA].append((row.name, "printed and not declared by the harness"))

    for name, group in printed.items():
        row = group[0]
        if row.want == "" and row.got == "":
            counts[C_DEAD_ROW].append((name, "got and want are both empty"))
        elif row.want == "":
            counts[C_UNCHECKABLE].append((name, f"want is empty, so the row cannot fail "
                                                f"(got={row.got!r})"))
        elif row.got == row.want:
            counts[C_MATCH].append((name, "exact"))
        else:
            spelling = canonical(row.got) == canonical(row.want)
            counts[C_MISMATCH].append(
                (name, f"got={row.got!r} want={row.want!r}"
                       + (f" {SPELLING_MARK}" if spelling else "")))
    if baseline is not None:
        dropped, added = baseline_delta(baseline, {r.name for r in rows})
        counts[C_DROPPED] = dropped
        counts[C_ADDED] = added
    return counts


# ---------------------------------------------------------------- the run


def parse_rows(stdout: str):
    """The printed rows, and the lines that are not rows."""
    rows, malformed = [], []
    for line in stdout.splitlines():
        if not line.strip():
            continue
        head, sep, rest = line.partition(" got=")
        if not sep:
            malformed.append(line)
            continue
        got, sep2, want = rest.rpartition(" want=")
        if not sep2 or not head or " " in head:
            malformed.append(line)
            continue
        rows.append(Row(head, got, want))
    return rows, malformed


def _head() -> str:
    """The tree's HEAD, read WITHOUT the index (`env -u GIT_INDEX_FILE`).

    The index is armed in this tree and `AGENTS.md` records what a reader of the index
    gets on a tree whose index disagrees with HEAD, so a gate that names a revision must
    name the one the OBJECTS hold."""
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=30)
        return out.stdout.strip() or "UNKNOWN"
    except (OSError, subprocess.SubprocessError):
        return "UNKNOWN"


def _materialize(dest: Path, rev: str | None) -> Path:
    """A PORT COPY. `rev` is a commit to extract the port from; `None` is the live tree.

    The live tree is COPIED, never read in place: the harness's source is read from the
    copy and bend runs against the copy, so the two can never be a half-written pair."""
    if rev in (None, "live"):
        shutil.copytree(ROOT / PORT_NAME, dest / PORT_NAME)
        return dest / PORT_NAME
    dest.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    proc = subprocess.run(["git", "archive", rev, PORT_NAME], cwd=ROOT, env=env,
                          capture_output=True, timeout=300)
    if proc.returncode != 0:
        raise RuntimeError(f"git archive {rev} failed: "
                           f"{proc.stderr.decode('utf-8', 'replace')[:200]}")
    with tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r:") as tar:
        tar.extractall(dest, filter="data")
    return dest / PORT_NAME


def _drive(port: Path):
    """The driver's stdout, its stderr and its exit status. `(rows, malformed, code)`.

    THE DRIVER IS THE PORT'S OWN `nn/layers.bend`, because its `main` IS the row
    harness's entry point: the harness decides which rows run, so a row that stopped
    running is a row that stopped existing. A probe that called the row functions
    itself would have a SECOND list of them, and that list would decide the population
    instead of the harness."""
    driver = port / DRIVER
    if not driver.is_file():
        return None, None, REFUSED, f"the driver {DRIVER} is absent from {port}"
    proc = subprocess.run([str(BEND), str(driver)], capture_output=True, text=True,
                          timeout=900)
    rows, malformed = parse_rows(proc.stdout or "")
    return rows, malformed, proc.returncode, (proc.stdout or ""), (proc.stderr or "")


def measure(port: Path, label: str, use_baseline: bool = True):
    """THE GATE'S DECISION, as a value. `(code, counts, n_rows, n_expected, lines, rows)`.

    This is the function the CONTROLS drive, and it is the SAME one `run_gate` prints:
    `gates/README.md` records the reason in one line -- "a plant that drives a helper is
    not a plant of the decision" -- so the controls and the gate cannot disagree by
    construction."""
    lines = [f"{GATE}: port={label}"]

    def refuse(reason):
        """A REFUSAL, said ONCE and to BOTH streams: the terminal and the transcript.

        A refusal a reader cannot see is a refusal nobody can test, and the transcript is
        what a later reader reads."""
        print(f"{GATE}: REFUSED, NOT A VERDICT: {reason}", file=sys.stderr)
        lines.append(f"{GATE}: REFUSED, NOT A VERDICT: {reason}")
        lines.append(f"{GATE}: REFUSED")
        return REFUSED, {}, 0, 0, lines, ()

    driver = port / DRIVER
    if not driver.is_file():
        return refuse(f"the driver {DRIVER} is absent from {port}")
    if not BEND.is_file():
        return refuse("`bin/bend` is absent, so the rows cannot be produced at all")

    try:
        text = driver.read_text()
    except OSError as exc:
        return refuse(f"the driver cannot be read: {exc}")
    expected, sites = parse_source(text)
    unreadable = [s for s in sites if s.literal is None and s.pattern is None]
    if unreadable:
        for s in unreadable:
            print(f"{GATE}: REFUSED, NOT A VERDICT: the row name at {DRIVER}:{s.line} is "
                  f"`{s.expression}`, and this gate will not guess a population it did not "
                  f"derive", file=sys.stderr)
            lines.append(f"{GATE}: REFUSED, NOT A VERDICT: the row name at {DRIVER}:{s.line} "
                         f"is `{s.expression}`, and this gate will not guess a population it "
                         f"did not derive")
        lines.append(f"{GATE}: REFUSED")
        return REFUSED, {}, 0, 0, lines, ()
    if not expected.literals and not expected.patterns:
        return refuse(f"no `nn_row.line(...)` call site was found in {DRIVER}, so there is "
                      f"no population to check")

    rows, malformed, rc, out, err = _drive(port)
    OUT.mkdir(parents=True, exist_ok=True)
    for p in OUT.iterdir():
        p.unlink()
    (OUT / "rows.out").write_text(out)
    (OUT / "driver.err").write_text(err)

    if rc != 0:
        said = " | ".join(l.strip() for l in err.splitlines()[:4] if l.strip())
        print(f"{GATE}: REFUSED, NOT A VERDICT: the driver FAILED (rc={rc}), so no row was "
              f"measured. bend said: {said}", file=sys.stderr)
        lines.append(f"{GATE}: REFUSED, NOT A VERDICT: the driver FAILED (rc={rc}), so no "
                     f"row was measured. bend said: {said}")
        lines.append(f"{GATE}: REFUSED")
        return REFUSED, {}, len(rows), 0, lines, tuple(rows)
    if not rows and not malformed:
        print(f"{GATE}: DEAD: the driver ran and emitted NO rows, so nothing was compared. "
              f"This is exit 5 and not exit 0: a gate that compares nothing is worse than "
              f"no gate.", file=sys.stderr)
        lines.append(f"{GATE}: DEAD: the driver ran and emitted NO rows, so nothing was "
                     f"compared. This is exit 5 and not exit 0: a gate that compares "
                     f"nothing is worse than no gate.")
        lines.append(f"{GATE}: DEAD")
        return DEAD, {}, 0, 0, lines, ()

    # **THE FROZEN BASELINE, AND IT CROSS-CHECKS THE POPULATION RATHER THAN REPLACING IT.**
    # THE POPULATION IS STILL THE HARNESS's OWN DECLARATION.
    if use_baseline:
        baseline, meta = read_baseline()
        if baseline is None:
            return refuse("; ".join(meta) + " -- the gate would be BLIND TO A DELETED ROW NAME, "
                          "and an absent witness is not a green one. Re-freeze it with "
                          "`--freeze`, and let the diff be the change.")
    else:
        baseline, meta = None, []
    counts = classify(rows, expected, baseline)
    dropped = counts.get(C_DROPPED, [])
    added = counts.get(C_ADDED, [])
    n_rows = len(rows)
    n_expected = len(expected.literals) + sum(n for _, n, _, _ in expected.patterns)
    spelling = [c for c in counts[C_MISMATCH] if SPELLING_MARK in c[1]]
    not_passing = n_rows - len(counts[C_MATCH])

    lines.append(f"{GATE}: rows_declared={n_expected} "
                 f"({len(expected.literals)} literal name(s), "
                 f"{len(expected.patterns)} computed name(s) x "
                 f"{sum(n for _, n, _, _ in expected.patterns)} invocation(s))")
    for pattern, n, fn, _called in expected.patterns:
        lines.append(f"{GATE}: computed-name pattern={pattern} declared_by={fn} expected={n}")
    if expected.uncalled:
        lines.append(f"{GATE}: declared by a function main does NOT call: "
                     f"{', '.join(f'{f} ({n} row(s))' for f, n in expected.uncalled)}")
    lines.append(f"{GATE}: rows_printed={n_rows}")
    lines.append(f"{GATE}: MATCH={len(counts[C_MATCH])}/{n_rows} "
                 f"MISMATCH={len(counts[C_MISMATCH])}/{n_rows} "
                 f"UNCHECKABLE={len(counts[C_UNCHECKABLE])}/{n_rows} "
                 f"DEAD-ROW={len(counts[C_DEAD_ROW])}/{n_rows} "
                 f"SHRUNK={len(counts[C_SHRUNK])}/{n_rows} "
                 f"EXTRA={len(counts[C_EXTRA])}/{n_rows} "
                 f"DUPLICATE={len(counts[C_DUPLICATE])}/{n_rows}")
    lines.append(f"{GATE}: mismatching rows that differ only in SPELLING={len(spelling)} of "
                 f"{len(counts[C_MISMATCH])} (the rule: punctuation dropped, case folded, "
                 f"f32==float32)")
    lines.append(f"{GATE}: rows_not_passing_exact_comparison={not_passing} of {n_rows}")
    if use_baseline:
        lines.append(f"{GATE}: baseline={BASELINE.name} baseline_rows={len(baseline)} "
                     f"baseline_dropped={len(dropped)} baseline_added={len(added)}")
        for ln in meta:
            lines.append(f"{GATE}: baseline| {ln}")
    for cls in (C_MISMATCH, C_UNCHECKABLE, C_DEAD_ROW, C_SHRUNK, C_EXTRA, C_DUPLICATE,
                C_DROPPED, C_ADDED):
        for name, detail in counts[cls]:
            lines.append(f"{GATE}: {cls} {name} {detail}")
    for line in malformed:
        lines.append(f"{GATE}: MALFORMED {line!r} -- a line of the driver's output that is "
                     f"not a row")

    fired = [c for c in FIRED if counts.get(c)]
    if malformed:
        fired.append(C_MALFORMED)
    if fired:
        lines.append(f"{GATE}: FAIL -- {not_passing} of {n_rows} rows do not pass under exact "
                     f"comparison ({len(counts[C_MATCH])} match, "
                     f"{len(counts[C_MISMATCH])} mismatch of which {len(spelling)} differ only "
                     f"in spelling, {len(counts[C_UNCHECKABLE])} uncheckable, "
                     f"{len(counts[C_DEAD_ROW])} dead)")
        return FAIL, counts, n_rows, n_expected, lines, tuple(rows)
    lines.append(f"{GATE}: PASS -- {n_rows} of {n_rows} rows match their expectations, and the "
                 f"declared population is {n_expected}")
    return PASS, counts, n_rows, n_expected, lines, tuple(rows)


def run_gate(port: Path, label: str) -> int:
    """THE GATE, printed. One port copy, one driver run, one verdict.

    The verdict is decided by the CLASSES, and every class is named in the output with
    the row it is about, so a reader can tell WHICH row failed and WHY from this
    output alone."""
    code, _counts, _n_rows, _n_expected, lines, _rows = measure(port, label)
    for line in lines:
        print(line)
    return code


# ---------------------------------------------------------------- the plants


def plant() -> int:
    """THE SIX PLANTS, on synthetic state, driving `classify` -- the SHIPPED decision.

    `gates/README.md` records the reason in one line: "each plant calls the SHIPPED
    decision function -- MEASURED, the first version reached past them into the helpers,
    and breaking `preconditions`' branch left the plant green. A plant that drives a
    helper is not a plant of the decision." """
    exp_one = Expected((("a", "f", True),), (), ())
    exp_two = Expected((("a", "f", True), ("b", "f", True)), (), ())
    cases = [
        ("MATCH", exp_one, [Row("a", "1", "1")], PASS, C_MATCH),
        ("MISMATCH", exp_one, [Row("a", "1", "2")], FAIL, C_MISMATCH),
        ("UNCHECKABLE", exp_one, [Row("a", "1", "")], FAIL, C_UNCHECKABLE),
        ("DEAD-ROW", exp_one, [Row("a", "", "")], FAIL, C_DEAD_ROW),
        ("SHRUNK", exp_two, [Row("b", "1", "1")], FAIL, C_SHRUNK),
        ("DEAD-LANE", exp_one, [], DEAD, None),
    ]
    bad = []
    for name, exp, rows, want, cls in cases:
        if want == DEAD:
            got = DEAD if not rows else FAIL
        else:
            r = classify(rows, exp)
            got = FAIL if any(r[c] for c in FIRED) else PASS
            if cls and not r.get(cls):
                got = FAIL
                bad.append(f"{name}: the {cls} class did not fire")
        print(f"  {name:<12} rc={got} want={want}"
              + (f" class={cls}" if cls else " class=DEAD-LANE"))
        if got != want:
            bad.append(f"{name}: rc={got}, expected {want}")
    # **THE BASELINE's TWO CLASSES, PLANTED THE SAME WAY** -- THE PLANTS DRIVE THE SHIPPED
    # DECISION, AND THE SHIPPED DECISION IS `classify`, SO A PLANT OF `baseline_delta` ALONE
    # WOULD BE A PLANT OF A HELPER.
    base_cases = [
        # (name, baseline, expected, rows, want_rc, want_class)
        # **THE EXPECTATION EACH PLANT CARRIES IS THE ONE THAT MAKES ITS OWN ROW NOT `EXTRA`:**
        # A ROW THAT IS PRINTED AND NOT DECLARED IS `EXTRA`, WHICH IS A FIRING CLASS, SO THE
        # `ADDED` PLANT DECLARES THE ROW IT ADDS.
        ("DROPPED", {"a", "b"}, exp_one, [Row("a", "1", "1")], FAIL, C_DROPPED),
        ("ADDED", {"a"}, exp_two, [Row("a", "1", "1"), Row("b", "1", "1")], PASS, C_ADDED),
        ("BASELINE-AGREES", {"a"}, exp_one, [Row("a", "1", "1")], PASS, None),
    ]
    for name, base, exp, rows, want, cls in base_cases:
        r = classify(rows, exp, base)
        got = FAIL if any(r[c] for c in FIRED) else PASS
        if cls and not r.get(cls):
            got = FAIL
            bad.append(f"{name}: the {cls} class did not fire")
        print(f"  {name:<12} rc={got} want={want}"
              + (f" class={cls}" if cls else " class=-")
              + f" dropped={len(r.get(C_DROPPED, []))} added={len(r.get(C_ADDED, []))}")
        if got != want:
            bad.append(f"{name}: rc={got}, expected {want}")
    ok = f"all {len(cases) + len(base_cases)} plants OK"
    print(f"--plant: {ok if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


# ---------------------------------------------------------------- the controls


def _row_sites(text: str):
    """The `nn_row.line(...)` call sites with their argument spans, for a mutation."""
    out = []
    for m in re.finditer(re.escape(ROW_CALL), text):
        spans = _args(text, m.end() - 1)
        if len(spans) >= 3:
            out.append((m, spans))
    return out


def _set_want(text: str, row_name: str, new_want: str) -> str:
    """The `want` argument of the call site that declares `row_name`, replaced.

    A MUTATION of a COPY, and it edits the COPY's own source -- the live tree is never
    written to."""
    for m, spans in _row_sites(text):
        arg = text[spans[0][0]:spans[0][1]].strip()
        lit = STRING.fullmatch(arg)
        if not lit or lit.group(1) != row_name:
            continue
        a, b = spans[2]
        return text[:a] + '"' + new_want + '"' + text[b:]
    raise KeyError(f"no row named {row_name!r} in the harness")


def _drop_main_call(text: str, fn: str) -> str:
    """EVERY call to `fn` removed from `main`'s body. The rows it printed stop being
    printed while the file still DECLARES them -- which is the shrink a gate can see."""
    lines = text.splitlines(keepends=True)
    defs = _functions([l.rstrip("\n") for l in lines])
    mains = [d for d in defs if d[0] == "main"]
    if not mains:
        raise KeyError("the harness has no main")
    _, first, last = mains[-1]
    pat = re.compile(r"\b" + re.escape(fn) + r"\s*\(")
    kept = [l for i, l in enumerate(lines)
            if not (first < i < last and pat.search(l))]
    if len(kept) == len(lines):
        raise KeyError(f"main does not call {fn}")
    return "".join(kept)


def _drop_function(text: str, fn: str) -> str:
    """A whole function removed: its `def` line and its body.

    Used by the GREEN BASELINE, where a row that observed NOTHING has to leave the
    population as well as the output -- a declared row that is not printed is a SHRUNK
    population, and the green baseline has to be green."""
    lines = text.splitlines(keepends=True)
    for name, first, last in _functions([l.rstrip("\n") for l in lines]):
        if name == fn:
            return "".join(lines[:first] + lines[last:])
    raise KeyError(f"no function named {fn}")


def _drop_site(text: str, m, spans) -> str:
    """A whole `nn_row.line(...)` STATEMENT removed: the call and its continuation
    lines.

    A statement on a line of its own, or REFUSED: a call site sharing its line with
    other text would leave a half-statement behind, and this file does not guess."""
    line_start = text.rfind("\n", 0, m.start()) + 1
    if text[line_start:m.start()].strip():
        raise KeyError("the call site does not sit on a line of its own")
    end = spans[-1][1] + 1
    line_end = text.find("\n", end)
    line_end = len(text) if line_end == -1 else line_end + 1
    return text[:line_start] + text[line_end:]


def _green(text: str, rows) -> str:
    """THE GREEN BASELINE: a SYNTHETIC port, and it exists for one reason.

    On the live tree the gate is ALREADY red -- nineteen of the thirty-one rows do not
    pass -- so a control that started from the live baseline could not show that ITS
    mutation is what made the gate red: the exit was already 1. This rewrites the
    copy's expectations to agree with the copy's OWN observations (`want := got`) and
    removes the rows that observed NOTHING -- their call sites go, so the DECLARATION
    and the OUTPUT leave together and nothing is SHRUNK -- so the copy's gate is GREEN
    (exit 0) and the control's mutation is the only difference between 0 and the verdict
    it claims.

    It is a copy. The live tree is never rewritten."""
    by_name = {r.name: r for r in rows}
    for r in rows:
        if r.got and r.want != r.got:
            text = _set_want(text, r.name, r.got)
    _expected, sites = parse_source(text)
    by_fn = {}
    for site in sites:
        if site.literal is not None:
            r = by_name.get(site.literal)
            hit = [r] if r is not None else []
        elif site.pattern:
            rx = re.compile(site.pattern)
            hit = [r for r in rows if rx.fullmatch(r.name)]
        else:
            continue
        by_fn.setdefault(site.fn, []).append((site, hit))
    # A FUNCTION whose EVERY row observed nothing leaves the population and the output
    # together -- the whole function goes, because a function with an empty body is not
    # a `.bend` file. A function with only SOME dead rows keeps its other rows and
    # loses only the dead ones.
    doomed, drop_fns = [], set()
    for fn, entries in by_fn.items():
        dead = [s for s, hit in entries if hit and all(not r.got for r in hit)]
        if not dead:
            continue
        if len(dead) == len(entries):
            drop_fns.add(fn)
        else:
            doomed.extend(dead)
    for site in sorted(doomed, key=lambda s: -s.line):
        # THE SITE IS RE-FOUND IN THE CURRENT TEXT, because a deletion moves every
        # offset after it. The deletions run from the BOTTOM UP, so the line numbers
        # of the sites still to go are the ones the parse reported.
        m = next((x for x in re.finditer(re.escape(ROW_CALL), text)
                  if text.count("\n", 0, x.start()) + 1 == site.line), None)
        if m is None:
            continue
        spans = _args(text, m.end() - 1)
        if len(spans) >= 3:
            text = _drop_site(text, m, spans)
    for fn in sorted(drop_fns):
        text = _drop_main_call(text, fn)
        text = _drop_function(text, fn)
    return text


def _neuter_printer(text: str) -> str:
    """The row PRINTER neutered: `nn_row.line` prints an empty line instead of the row.

    The driver still RUNS and still does all the work -- and emits no rows at all, which
    is the DEAD lane: a gate that compares nothing must not exit 0."""
    m = re.search(r"def\s+nn_row\.line\s*\([^)]*\)\s*->\s*IO\(Unit\)\s*:\s*\n\s*\S[^\n]*",
                  text)
    if not m:
        raise KeyError("the harness has no nn_row.line printer")
    head = text[:m.start()]
    body = "def nn_row.line(nm: String, got: String, want: String) -> IO(Unit):\n  IO.print(\"\")\n"
    return head + body + text[m.end():]


CONTROLS = {
    "a": "a `want` that does not match the `got` -> MISMATCH -> FAIL (1)",
    "b": "an EMPTY `want` on a row whose `got` is not empty -> UNCHECKABLE -> FAIL (1)",
    "c": "an EMPTY `want` on a row whose `got` IS empty -> DEAD-ROW -> FAIL (1)",
    "d": "a row the harness's `main` no longer calls -> SHRUNK -> FAIL (1)",
    "e": "the driver printing ZERO rows -> DEAD (5), NOT PASS (0)",
    "f": "a row NAME removed from the `.bend` copy -> DROPPED -> FAIL (1). **THE HOLE, "
         "CLOSED.** THE POPULATION IS DECLARED BY THE FILE THE ROW WAS REMOVED FROM, SO "
         "BOTH SIDES SHRINK TOGETHER -- AND THE FROZEN BASELINE IS THE ONE THING THAT DOES "
         "NOT SHRINK WITH THEM.",
    "g": "a row ADDED to the `.bend` copy -> ADDED and NOTHING ELSE, and the gate STAYS "
         "GREEN. **THE NEGATIVE CONTROL FOR THE BASELINE ITSELF:** A BASELINE THAT GOES RED "
         "FOR A LEGITIMATE ADDITION WOULD FORCE A RE-FREEZE ON EVERY NEW ROW, SO ADDED IS "
         "REPORTED AND NOT FIRED.",
}

# WHAT EACH CONTROL MUST SHOW: the class that must fire, and the exit the GATE must
# return under the mutation. A control that does not show its class is a broken
# control, and a broken control exits 1 -- the control's own exit is 0 when it
# demonstrated what it claims to demonstrate. `f` is the negative control and its
# expectation is that NOTHING fires.
WANTS = {
    "a": (C_MISMATCH, FAIL),
    "b": (C_UNCHECKABLE, FAIL),
    "c": (C_DEAD_ROW, FAIL),
    "d": (C_SHRUNK, FAIL),
    "e": (None, DEAD),
    "f": (C_DROPPED, FAIL),
    "g": (C_ADDED, PASS),
}


def _set_got_and_want(text: str, row_name: str, value: str) -> str:
    """The `got` AND the `want` of the call site that declares `row_name`, replaced.

    A MUTATION of a COPY, and it edits the COPY's own source -- the live tree is never
    written to."""
    for m, spans in _row_sites(text):
        arg = text[spans[0][0]:spans[0][1]].strip()
        lit = STRING.fullmatch(arg)
        if not lit or lit.group(1) != row_name:
            continue
        a, b = spans[2]
        text = text[:a] + '"' + value + '"' + text[b:]
        a, b = spans[1]
        return text[:a] + '"' + value + '"' + text[b:]
    raise KeyError(f"no row named {row_name!r} in the harness")


def _add_row_function(text: str) -> str:
    """A NEW ROW FUNCTION, AND A CALL TO IT FROM `main`'s `do` BLOCK.

    **A FUNCTION BODY IN BEND IS ONE EXPRESSION** -- MEASURED 2026-10-25: a second
    `nn_row.line(...)` inside `nn_row_relu` made `bend` answer *"expected : 'def', 'type' or
    'law'"* AT THAT LINE, IN BOTH POSITIONS. `main`'s BODY IS A `do IO<Unit>:` BLOCK, WHICH IS
    WHY THE CALL GOES THERE.
    """
    lines = text.split("\n")
    mi = next((k for k, l in enumerate(lines) if l.startswith("def main()")), None)
    if mi is None:
        raise KeyError("the copy has no `def main()`")
    di = next((k for k in range(mi, len(lines)) if "do IO<Unit>:" in lines[k]), None)
    if di is None:
        raise KeyError("the copy's `main` has no `do IO<Unit>:` block")
    lines.insert(di + 1, "    nn_row_added()")
    lines.insert(mi, "def nn_row_added() -> IO(Unit):")
    lines.insert(mi + 1, '  nn_row.line("added_probe", "1", "1")')
    lines.insert(mi + 2, "")
    return "\n".join(lines)


def _mutate(text: str, rows, name: str):
    """THE MUTATION, as a transformation of the COPY's own source. `(text, detail)`.

    The mutation is chosen from the rows the copy ACTUALLY printed, so a control cannot
    mutate a row that is not there."""
    if name == "a":
        pick = next((r for r in rows if r.want and r.got), None)
        if pick is None:
            raise KeyError("no row has both a want and a got")
        return (_set_want(text, pick.name, "9,9"),
                f"row={pick.name} want='{pick.want}' -> '9,9'")
    if name == "b":
        pick = next((r for r in rows if r.want and r.got), None)
        if pick is None:
            raise KeyError("no row has both a want and a got")
        return (_set_want(text, pick.name, ""),
                f"row={pick.name} want='{pick.want}' -> '' (got='{pick.got}')")
    if name == "c":
        empty = next((r for r in rows if not r.got), None)
        if empty is not None:
            return (_set_want(text, empty.name, ""),
                    f"row={empty.name} got was ALREADY empty, want='{empty.want}' -> ''")
        pick = next((r for r in rows if r.got), None)
        if pick is None:
            raise KeyError("no row has a got")
        return (_set_got_and_want(text, pick.name, ""),
                f"row={pick.name} got='{pick.got}' want='{pick.want}' -> both empty")
    if name == "d":
        _expected, sites = parse_source(text)
        counts = {}
        for s in sites:
            counts[s.fn] = counts.get(s.fn, 0) + 1
        pick = min((f for f, n in counts.items() if n), key=lambda f: counts[f])
        return (_drop_main_call(text, pick),
                f"main no longer calls {pick}, so the {counts[pick]} row(s) it declared are "
                f"still DECLARED by the file and are no longer PRINTED")
    if name == "g":
        # A ROW ARRIVES: A NEW ROW FUNCTION, AND `main`'s OWN `do` BLOCK CALLS IT -- so the new
        # row is declared AND printed, and the FROZEN BASELINE, which does not have it, is the
        # only thing that can see the difference.
        #
        # **A NEW `def` AND NOT A SECOND STATEMENT IN AN EXISTING ONE.** MEASURED 2026-10-25:
        # putting a second `nn_row.line(...)` inside `nn_row_relu` -- BEFORE the existing call
        # AND AFTER IT -- made `bend` answer *"expected : 'def', 'type' or 'law'"* AT THAT LINE,
        # **IN BOTH POSITIONS**. **A FUNCTION BODY IN BEND IS ONE EXPRESSION, NOT A BLOCK OF
        # STATEMENTS.** `main` IS THE EXCEPTION BECAUSE ITS BODY IS A `do IO<Unit>:` BLOCK.
        return (_add_row_function(text),
                "a new row function `nn_row_added` was added and `main` now calls it, so the "
                "run prints one row the frozen baseline does not have")
    if name == "f":
        # THE ROW NAME LEAVES THE FILE: the function that declared it and its call in
        # `main` both go. **THE POPULATION IS DECLARED BY THIS FILE, SO THE DECLARATION AND
        # THE OUTPUT SHRINK TOGETHER** -- AND THE FROZEN BASELINE IS THE ONE THING THAT DOES
        # NOT SHRINK WITH THEM, SO THE GATE NOW CATCHES IT. THAT IS THE HOLE, CLOSED.
        _expected, sites = parse_source(text)
        counts = {}
        for s in sites:
            counts[s.fn] = counts.get(s.fn, 0) + 1
        pick = min((f for f, n in counts.items() if n), key=lambda f: counts[f])
        text = _drop_main_call(text, pick)
        text = _drop_function(text, pick)
        return (text, f"the row NAME is gone from the copy: {pick} and its call in main "
                      f"were removed, so the file declares {counts[pick]} row(s) fewer AND "
                      f"prints {counts[pick]} row(s) fewer")
    return (_neuter_printer(text),
            "the printer prints an empty line instead of the row")


def _summary(counts) -> str:
    return " ".join(f"{c}={len(counts.get(c, []))}" for c in
                     (C_MATCH, C_MISMATCH, C_UNCHECKABLE, C_DEAD_ROW, C_SHRUNK, C_EXTRA,
                      C_DUPLICATE, C_DROPPED, C_ADDED))


def control(name: str, rev: str | None) -> int:
    """ONE CONTROL, on COPIES of the port, and its ACTUAL exit code.

    A CONTROL MUTATES A COPY AND NEVER THE LIVE TREE. It runs TWICE over the same
    baseline:

    `real`   the tree as it is. It is already RED -- nineteen of the thirty-one rows do
             not pass -- so this variant shows the CLASS COUNT moving and the row NAMED.
    `green`  a SYNTHETIC copy whose expectations agree with its own observations, so
             the gate is GREEN (exit 0) and the control's mutation is the ONLY difference
             between 0 and the verdict it claims. This is the variant that shows the
             gate going from 0 to 1, which is what "a gate that cannot go red is a label"
             means.

    Both variants are produced by `measure` -- the SHIPPED decision -- so a control and
    the gate cannot disagree."""
    if name not in CONTROLS:
        print(f"{GATE}: no control named {name!r}; the controls are "
              f"{', '.join(sorted(CONTROLS))}", file=sys.stderr)
        return REFUSED
    want_class, want_code = WANTS[name]
    print(f"{GATE}: control={name} what={CONTROLS[name]}")
    print(f"{GATE}: control={name} baseline={'the live working tree' if rev is None else rev}")
    with tempfile.TemporaryDirectory(prefix="nn-rows-control-") as td:
        tmp = Path(td)
        try:
            port = _materialize(tmp / "real", rev)
            green_port = _materialize(tmp / "green", rev)
        except (OSError, RuntimeError) as exc:
            print(f"{GATE}: REFUSED, NOT A VERDICT: {exc}", file=sys.stderr)
            return REFUSED
        driver = port / DRIVER
        b_code, b_counts, b_n, _e, _l, b_rows = measure(port, "real/before")
        if b_code in (REFUSED, DEAD):
            print(f"{GATE}: REFUSED, NOT A VERDICT: the baseline port did not produce rows "
                  f"(rc={b_code}), so the control has no baseline to mutate",
                  file=sys.stderr)
            print(f"{GATE}: control={name} baseline_rc={b_code} after_rc=REFUSED")
            return REFUSED
        try:
            text, detail = _mutate(driver.read_text(), b_rows, name)
        except (KeyError, IndexError) as exc:
            print(f"{GATE}: REFUSED, NOT A VERDICT: the control cannot be applied: {exc}",
                  file=sys.stderr)
            return REFUSED
        driver.write_text(text)
        a_code, a_counts, a_n, _e2, a_lines, _r2 = measure(port, "real/after")

        g_driver = green_port / DRIVER
        try:
            gtext = _green(g_driver.read_text(), b_rows)
            g_driver.write_text(gtext)
        except (KeyError, IndexError) as exc:
            print(f"{GATE}: REFUSED, NOT A VERDICT: the green baseline cannot be built: {exc}",
                  file=sys.stderr)
            return REFUSED
        gb_code, gb_counts, gb_n, _e3, _l3, gb_rows = measure(green_port, "green/before")
        try:
            gtext2, _detail2 = _mutate(gtext, gb_rows, name)
            g_driver.write_text(gtext2)
        except (KeyError, IndexError) as exc:
            print(f"{GATE}: REFUSED, NOT A VERDICT: the control cannot be applied to the green "
                  f"baseline: {exc}", file=sys.stderr)
            return REFUSED
        ga_code, ga_counts, ga_n, _e4, ga_lines, _r4 = measure(green_port, "green/after")

        real_fired = [c for c in FIRED
                      if len(a_counts.get(c, [])) > len(b_counts.get(c, []))]
        green_fired = [c for c in FIRED
                       if len(ga_counts.get(c, [])) > len(gb_counts.get(c, []))]
        if want_class is None and a_code == DEAD:
            real_fired.append("DEAD-LANE")
        if want_class is None and ga_code == DEAD:
            green_fired.append("DEAD-LANE")

        print(f"{GATE}: control={name} mutation={detail}")
        print(f"{GATE}: control={name} real/before: {_summary(b_counts)} rows={b_n} "
              f"rc={b_code}")
        print(f"{GATE}: control={name} real/after:  {_summary(a_counts)} rows={a_n} "
              f"rc={a_code}")
        print(f"{GATE}: control={name} real class_fired={','.join(real_fired) if real_fired else 'NONE'}")
        print(f"{GATE}: control={name} green/before: {_summary(gb_counts)} rows={gb_n} "
              f"rc={gb_code}")
        print(f"{GATE}: control={name} green/after:  {_summary(ga_counts)} rows={ga_n} "
              f"rc={ga_code}")
        print(f"{GATE}: control={name} green class_fired={','.join(green_fired) if green_fired else 'NONE'}")
        print(f"{GATE}: control={name} gate_rc_under_mutation={ga_code} "
              f"({verdict_of(ga_code)}) [green baseline {gb_code} -> {ga_code}]")
        for cls in green_fired:
            for nm, det in ga_counts.get(cls, []):
                print(f"{GATE}: control={name} {cls} {nm} {det}")
        for line in ga_lines:
            print(f"{GATE}: control={name} gate| {line}")

        bad = []
        if name == "g":
            # THE NEGATIVE CONTROL FOR THE BASELINE: the ADDED class must fire and NOTHING
            # ELSE may, and the gate must stay GREEN -- because a baseline that goes red for a
            # legitimate addition would force a re-freeze on every new row.
            for tag, b, a in (("real", b_counts, a_counts), ("green", gb_counts, ga_counts)):
                if len(a.get(C_ADDED, [])) <= len(b.get(C_ADDED, [])):
                    bad.append(f"the {C_ADDED} class did not fire on the {tag} baseline")
                if len(a.get(C_DROPPED, [])) != len(b.get(C_DROPPED, [])):
                    bad.append(f"the {C_DROPPED} class moved on the {tag} baseline, and an "
                               f"ADDITION MUST NOT DROP ANYTHING")
                fired_here = [c for c in FIRED
                              if len(a.get(c, [])) > len(b.get(c, []))]
                if fired_here:
                    bad.append(f"{tag}: a firing class moved on an ADDITION: "
                               f"{','.join(fired_here)}")
            if ga_code != PASS:
                bad.append(f"the gate returned {ga_code} ({verdict_of(ga_code)}) under an "
                           f"ADDITION, and an addition must not make it red")
        else:
            if want_class is not None and want_class not in real_fired:
                bad.append(f"the {want_class} class did not fire on the real baseline")
            if want_class is not None and want_class not in green_fired:
                bad.append(f"the {want_class} class did not fire on the green baseline")
            if gb_code != PASS:
                bad.append(f"the green baseline is not green (rc={gb_code})")
            if ga_code != want_code:
                bad.append(f"the gate returned {ga_code} ({verdict_of(ga_code)}) under the "
                           f"mutation, expected {want_code} ({verdict_of(want_code)})")
        if bad:
            print(f"{GATE}: control={name} FAILED: " + "; ".join(bad), file=sys.stderr)
            return FAIL
        print(f"{GATE}: control={name} OK: "
              + ("the class fired and the gate went {0} -> {1}".format(gb_code, ga_code)
                 if name != "g"
                 else "the ADDED class fired, nothing else did, and the gate stayed green"))
        return PASS


# ---------------------------------------------------------------- the entry point


def freeze() -> int:
    """RE-FREEZE THE BASELINE FROM THE LIVE TREE, and say WHAT CHANGED.

    **A BASELINE IS GENERATED, NOT TYPED.** A hand-written list of row names is a contract
    with no generator, and it rots without anyone noticing -- and a baseline that rots is
    WORSE than no baseline, because it fires `DROPPED` for rows that are still there. So the
    baseline is written by this file, from the live tree's own printed rows, and the DIFF
    between the old and the new IS the change a reader has to approve.
    """
    with tempfile.TemporaryDirectory(prefix="nn-rows-freeze-") as td:
        try:
            port = _materialize(Path(td), None)
        except (OSError, RuntimeError) as exc:
            print(f"{GATE}: REFUSED, NOT A VERDICT: the port will not copy: {exc}", file=sys.stderr)
            return REFUSED
        code, _counts, n_rows, _n, lines, rows = measure(port, "the live tree, for the freeze",
                                                          use_baseline=False)
        if code != PASS:
            for ln in lines:
                print(ln)
            print(f"{GATE}: REFUSED, NOT A VERDICT: the live tree is not green (rc={code}), so "
                  f"a baseline frozen from it would freeze a defect", file=sys.stderr)
            return REFUSED
        names = sorted({r.name for r in rows})
        old, _meta = read_baseline()
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        head = _head()
        body = [
            f"# {BASELINE.name} -- ONE COLUMN, NO SEPARATOR. Generated; the generator is "
            f"`gates/nn-rows-gate.py --freeze`.",
            "# columns: name",
            f"# written {now} HEAD={head}",
            "# A FROZEN BASELINE, NOT A POPULATION: THE POPULATION IS STILL THE HARNESS's OWN",
            "# DECLARATION. THIS FILE IS WHAT MAKES A **DELETED ROW NAME** VISIBLE, BECAUSE THE",
            "# DECLARATION AND THE OUTPUT SHRINK TOGETHER WHEN A ROW IS REMOVED.",
            "# RE-FREEZE WITH `--freeze`, AND THE DIFF IS THE CHANGE.",
        ] + names
        BASELINE.write_text("\n".join(body) + "\n")
        print(f"{GATE}: froze {len(names)} row name(s) into {BASELINE.name} at HEAD={head}")
        if old is None:
            print(f"{GATE}: there was no baseline to compare against")
        else:
            added = sorted(set(names) - old)
            gone = sorted(old - set(names))
            print(f"{GATE}: baseline added={len(added)} removed={len(gone)}")
            for n in added:
                print(f"{GATE}: baseline| + {n}")
            for n in gone:
                print(f"{GATE}: baseline| - {n}")
        return PASS


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", help="measure an already-made port copy")
    ap.add_argument("--baseline", default="live",
                    help="'live' (the working tree) or a commit to extract the port from")
    ap.add_argument("--control", choices=sorted(CONTROLS), help="run one control")
    ap.add_argument("--plant", action="store_true", help="the class plants, no bend")
    ap.add_argument("--freeze", action="store_true",
                    help="re-freeze the baseline from the live tree, and print the diff")
    args = ap.parse_args(argv)

    if args.freeze:
        return freeze()
    if args.plant:
        return plant()
    if args.control:
        rev = None if args.baseline == "live" else args.baseline
        return control(args.control, rev)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"{GATE}: measured_at={now} head={_head()}")
    if args.port:
        port = Path(args.port)
        if not (port / DRIVER).is_file():
            print(f"{GATE}: REFUSED, NOT A VERDICT: `{port}` does not hold {DRIVER}",
                  file=sys.stderr)
            return REFUSED
        return run_gate(port, str(port))
    with tempfile.TemporaryDirectory(prefix="nn-rows-") as td:
        rev = None if args.baseline == "live" else args.baseline
        try:
            port = _materialize(Path(td), rev)
        except (OSError, RuntimeError) as exc:
            print(f"{GATE}: REFUSED, NOT A VERDICT: the port will not copy: {exc}",
                  file=sys.stderr)
            return REFUSED
        label = (f"live copy of {PORT_NAME} (HEAD {_head()[:12]})" if rev is None
                 else f"{PORT_NAME} at {rev}")
        return run_gate(port, label)


if __name__ == "__main__":
    sys.exit(main())
