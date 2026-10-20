"""gates/pincensus-pop.py -- DISCOVERY for the pin census.

WHAT THIS IS. The census asked for by `gates/pincensus-gate.py`. A pin is a site
that asserts an EXACT value about something else in this tree, and the question is
whether that assertion can fail. Five pin events in two days were each discovered by
ACCIDENT -- a crash, a diff, a plant going red -- and never by asking. This module is
the asking.

THE POPULATION IS DISCOVERED, AND THREE PLACES THAT IS REFUSED ARE NAMED HERE:

  * NEVER `glob`. `AGENTS.md` records the measurement: `glob('*.bend')` returns `[]`
    while the files are on disk and tracked. This module uses `os.walk`.
  * NEVER A SUFFIX LIST, and NEVER A BASENAME SHAPE. `checks/repro-paths.py` used a
    five-item extension set and therefore read a path's PREFIX as the whole path,
    writing false rows in BOTH directions. Here nothing is admitted or excluded by its
    name: a file is read because its BYTES DECODE as UTF-8, and it is code or prose
    because its CONTENT says so.
  * NEVER THE INDEX. The denominator is `git ls-tree -r HEAD`, the tree. AGENTS.md
    records that on this tree `git ls-files` and `git ls-tree -r HEAD` disagree
    (measured 2026-10-20T03:5xZ, 8030 against 8034 under an armed index), and the
    whole class of defects here comes from asking the index a question about the tree.

  The walk is bounded by the tree's own record so that a `differ.py` run LIVE in
  `runs/graphcmp/` (measured: pids 14253/14303 at 2026-10-20T03:5xZ) is never read,
  and `.venv/`, `references/`, `.jj/` and `runs/` -- all four measured 0 tracked
  paths -- are excluded by that bound rather than by a hand list.

THE HOST-LANGUAGE CLASSIFIER IS `ast.parse`, WHICH IS THE POINT. A markdown file
cannot parse as Python, so "is this code" needs no extension list and cannot be
fooled by a `.md` that quotes a `def `. The classifier's own error budget is
measured and printed, not assumed: `md-parses-as-python` is a row.
"""
import ast
import hashlib
import os
import re
import subprocess
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A content-addressed literal: >=7 lowercase hex chars. 7 is git's abbreviation floor
# and 64 is sha256. Nothing here knows what a pin IS yet -- that is the site rules' job.
HEX = re.compile(r"\b[0-9a-f]{7,64}\b")

# A PIN NAME. The word must be a WHOLE segment of the identifier, so `ORACLE_PIN` and
# `BODY_SHA` bind and `spinning` does not. A substring match would be the
# basename-regex defect that cost `checks/sweep.py` 670 of its 675 files.
PIN_SEGMENT = r"(?:PIN|PINS|SHA|SHA256|HASH|HASHES|REV|REVISION|COMMIT|DIGEST|BODY)"
PIN_NAME = re.compile(r"\A[A-Za-z0-9_]*(?:" + PIN_SEGMENT + r")[A-Za-z0-9_]*\Z")

# Rule A: an identifier bound to a literal.
#
# THE WINDOW IS BOUNDED BY LINES, NOT BY CHARACTERS, AND BOTH ENDS OF THAT WERE REAL
# DEFECTS IN THIS CENSUS'S OWN FIRST TWO DRAFTS, RECORDED HERE RATHER THAN QUIETLY FIXED:
#
#   * WITHOUT `(?s)`, `.{0,500}` cannot cross the newline between `ORACLE_PIN = {` and
#     the digest on the next line, so every dict-shaped pin vanished --
#     `checks/differ.py:62`, `checks/substrate.py:113`, `gates/onnx_census-gate.py:86`,
#     `gates/js-lane-census.py:92`, `gates/mixin-op-gate.py:68`,
#     `gates/beautiful-mnist-gate.py:66`. The census answered for 28 sites; the truth
#     was more, and the missing ones were exactly the pinned-ORACLE family.
#   * WITH `(?s)` and a GREEDY `.{0,600}`, the window runs on past the end of its own
#     binding and swallows the NEXT one. `re.finditer` does not return overlapping
#     matches, so six `gates/*` sites disappeared instead:
#     `paramarg-site-gate.py:81`, `amd_dsl_census-gate.py:282`,
#     `crp_graph_census-gate.py:161`, `ops_python_census-gate.py:228`,
#     `upstream-pow-dtype-gate.py:55`, `wgsl_render_census-gate.py:255`.
#
# So: `(?m)` only, and the right-hand side is AT MOST SEVEN LINES. Seven holds a dict
# literal of three entries -- `ORACLE_PIN` in `checks/differ.py` is two -- and cannot
# swallow a following binding. The constant is named so a reader can see the bound and
# disagree with it.
BIND_RHS_LINES = 7
OPENERS, CLOSERS = "{[", "}]"
# A dict-shaped pin names its own SUBJECT: `"diffpy/oracle-run.sh": "<sha256>"`. Capturing the
# pair is what makes such a pin RE-DERIVABLE -- the subject is in the tree, so the digest can
# be recomputed and compared, and "is this pin current" becomes a question with an answer.
# It was missed in the first draft, which looked for the subject ABOVE the binding while every
# dict-shaped pin in this tree writes it BELOW, and so scored 43 digests UNNAMED-SUBJECT.
DICT_PAIR = re.compile(r'["\']([^"\']+)["\']\s*:\s*["\']?([0-9a-f]{7,64})')


def rhs_of(lines, start):
    """-> (rhs_text, next_line_index) for the binding whose RHS begins at `lines[start]`.

    THE LENGTH OF THE RIGHT-HAND SIDE IS NOT A CONSTANT, AND THREE DRAFTS OF THIS CENSUS
    EACH GOT IT WRONG IN A DIFFERENT DIRECTION. All three are recorded here rather than
    quietly fixed, because the shape is the lesson:

      1. A CHARACTER WINDOW WITHOUT `(?s)` cannot cross the newline between
         `ORACLE_PIN = {` and the digest on the next line, so every dict-shaped pin
         vanished: `checks/differ.py:62`, `checks/substrate.py:113`,
         `gates/onnx_census-gate.py:86`, `gates/rand_census-gate.py:146`,
         `gates/state_census-gate.py:111`, `gates/js-lane-census.py:92`,
         `gates/mixin-op-gate.py:68`, `gates/beautiful-mnist-gate.py:66`.
      2. A CHARACTER WINDOW WITH `(?s)` runs on past its own binding and swallows the
         NEXT one, and `re.finditer` does not return overlapping matches, so six
         `gates/*` sites disappeared instead.
      3. A LINE WINDOW IS MANDATORY, SO IT IS WRONG IN A NEW WAY: a binding in the LAST
         SIX LINES OF A FILE matched nothing, which is exactly where six of them sit --
         `gates/paramarg-site-gate.py:81`, `gates/amd_dsl_census-gate.py:282`,
         `gates/crp_graph_census-gate.py:161`, `gates/ops_python_census-gate.py:228`,
         `gates/upstream-pow-dtype-gate.py:55`, `gates/wgsl_render_census-gate.py:255`.

    And a fourth defect, in this function's first version, which is the one worth keeping:
    the depth was computed with `list.count('{')`, which counts list ELEMENTS EQUAL TO the
    brace and not the brace as a SUBSTRING. It answered 0 for every dict in the tree, so
    the census reported 28 sites while the truth was 40. A container method where a string
    method was meant, silently returning a plausible number. `"\n".join` first is the fix.
    """
    text = [lines[start]]
    i = start + 1
    while i < len(lines) and i - start < BIND_RHS_LINES:
        so_far = "\n".join(text)
        if sum(so_far.count(c) for c in OPENERS) <= sum(so_far.count(c) for c in CLOSERS):
            break
        text.append(lines[i])
        i += 1
    return "\n".join(text), i


SHEBANG = re.compile(r"\A#!")

SKIP_DIR = ".git"
MAX_BYTES = 8_000_000


def git(*argv, cwd=None):
    """-> stdout of `git <argv>`, or ''. Every tree question in this file goes through
    `ls-tree -r HEAD`, never `ls-files`, and this is where that is enforced.

    `cwd` is a parameter for the same reason `load`'s root is: a copy of this file placed
    elsewhere would otherwise ask the WRONG TREE, and it answers '' rather than complaining,
    so the caller's population comes back empty and the census reports nothing at all.
    """
    r = subprocess.run(["git", *argv], cwd=cwd or ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def walk_text(root=None):
    """-> {relpath: text}. os.walk + a UTF-8 decode, NEVER `glob` and NEVER a suffix.

    Yields the decode decision as the reason a file is in the population: a binary is
    absent because its bytes did not decode, which is a measured fact about the bytes
    and not a guess about the name.
    """
    base = root or ROOT
    out, binary = {}, 0
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d != SKIP_DIR]
        for fn in filenames:
            path = os.path.join(dirpath, fn)
            try:
                raw = open(path, "rb").read()
            except OSError:
                continue
            if len(raw) > MAX_BYTES:
                continue
            try:
                out[os.path.relpath(path, base)] = raw.decode("utf-8")
            except UnicodeDecodeError:
                binary += 1
    out["__undecodable__"] = str(binary)
    return out


def host_of(text):
    """-> 'python' | 'shell' | 'prose'. `ast.parse` IS the definition of a Python file.

    A markdown file cannot parse, so this cannot be fooled by a `.md` that quotes a
    `def ` -- which is exactly how the first draft of this census scored
    `.agents/TODO.md` as a READER of `gates/paramarg-site-gate.py:81`'s `PIN` and
    reported CANNOT-FAIL 0. A sentence mentioning a constant is not a read.
    """
    try:
        ast.parse(text)
        return "python"
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        pass
    first = next((l for l in text.splitlines() if l.strip()), "")
    if SHEBANG.match(first) and re.search(r"\b(?:sh|bash)\b", first):
        return "shell"
    return "prose"


def code_lines(text, host):
    """-> [(lineno, line)] a reader could execute. Comments and docstrings are out.

    THE LINE NUMBERS ARE THE FILE'S, not the filtered list's indices. Dropping a docstring
    line shifts every index after it, and `gates/upstream-promo-lattice-gate.py`'s `PIN`
    binding at real line 68 was reported at 17 -- a plausible-looking wrong answer, which is
    the only kind worth refusing to print. `where` is a deliverable of this census.

    Stated as a heuristic and it is one: a `#` inside a string is handled, a docstring body
    line that does not begin the string is not. It over-approximates, so a name counted as
    READ is counted on a line that may not run. That direction is chosen on purpose -- it can
    only move a row from CANNOT-FAIL to CAN-FAIL, and CANNOT-FAIL is the accusation, so the
    bias runs against the census's own conclusion.
    """
    if host == "prose":
        return []
    out = []
    in_doc = False
    for lineno, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if in_doc:
            if s.endswith('"""') or s.endswith("'''"):
                in_doc = False
            continue
        if s.startswith("#"):
            continue
        if s.startswith('"""') or s.startswith("'''"):
            q = s[:3]
            if not (len(s) > 3 and s.count(q) >= 2):
                in_doc = True
            continue
        i, cut, quote = 0, line, None
        while i < len(line):
            c = line[i]
            if quote:
                if c == "\\":
                    i += 2
                    continue
                if c == quote:
                    quote = None
            elif c in "\"'":
                quote = c
            elif c == "#":
                cut = line[:i]
                break
            i += 1
        out.append((lineno, cut))
    return out


def load(root=None):
    """-> the census's corpus, and the measured shape of the walk that produced it.

    The root is a PARAMETER and this was a bug, found by the sabotage run and not by reading:
    the function took no root and walked its own module-level `ROOT`, so `gates/pincensus-gate.py`'s
    `census(root, git_root)` advertised a root it never forwarded and answered a census of
    NOTHING (0 rows, silently) whenever the caller's root was not this file's parent. An
    instrument that returns zero rows when pointed somewhere else is indistinguishable from an
    instrument that found nothing, which is the DEAD lane the tree already has a word for.
    """
    disk = walk_text(root)
    undecodable = int(disk.pop("__undecodable__"))
    tracked = set(git("ls-tree", "-r", "HEAD", "--name-only", cwd=root).split())
    both = {t: v for t, v in disk.items() if t in tracked}
    return {
        "disk": disk,
        "tracked": tracked,
        "corpus": both,
        "counts": {
            "walk-decoded": len(disk),
            "walk-undecodable-binary": undecodable,
            "tree-tracked": len(tracked),
            "in-both": len(both),
            "on-disk-not-in-tree": len(set(disk) - tracked),
            "in-tree-not-on-disk": len(tracked - set(disk)),
        },
        "untracked_examples": sorted(set(disk) - tracked)[:8],
        "absent_examples": sorted(tracked - set(disk))[:8],
    }


def hosts(corpus):
    return {t: host_of(v) for t, v in corpus.items()}


def twins(corpus):
    """-> {relpath: [every tracked path with the same bytes]}.

    A file byte-identical to another tracked file is a COPY, and a copy of an
    instrument is not an authored pin -- it is the shadow `.agents/slop/figure2/plant/`
    keeps of `checks/differ.py`. Discovered by CONTENT, so no copy list is hand-written.
    """
    by = defaultdict(list)
    for t, v in corpus.items():
        by[hashlib.sha256(v.encode("utf-8")).hexdigest()].append(t)
    return {t: by[hashlib.sha256(v.encode("utf-8")).hexdigest()] for t, v in corpus.items()}


def rule_a(corpus, host):
    """-> named pin constants. [{file, line, name, values}].

    The scan is LINE-DRIVEN and calls `rhs_of`, so `re.finditer`'s non-overlapping rule
    cannot swallow the next binding: each match consumes only its own RHS.
    """
    out = []
    head = re.compile(r"^[ \t]*([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?::[^=\n]{1,60})?[ \t]*=[ \t]*")
    for t, txt in corpus.items():
        lines = txt.splitlines()
        i = 0
        while i < len(lines):
            m = head.match(lines[i])
            if not m:
                i += 1
                continue
            name = m.group(1)
            rhs, nxt = rhs_of(lines, i)
            body = rhs[m.end():]
            line_no = i + 1
            i = max(nxt, i + 1)
            if not PIN_NAME.match(name):
                continue
            vals = HEX.findall(body)
            if not vals:
                continue
            out.append({"file": t, "line": line_no, "end": nxt, "name": name,
                        "values": vals, "host": host[t],
                        "pairs": dict(DICT_PAIR.findall(body))})
    return out


def rule_b(corpus, host):
    """-> prose lines carrying a pin word AND a content-addressed literal.

    This is class 3's population, and it is where the five events left their other
    half: `AGENTS.md`'s own preamble quotes a PIN of 177/176, a CARVE-OUT of 175/244
    and a `.txt` COUNT of 550/183, each with a date and NOT with a command.
    """
    out = []
    for t, txt in corpus.items():
        if host[t] != "prose":
            continue
        for i, line in enumerate(txt.splitlines(), 1):
            if not re.search(PIN_SEGMENT, line):
                continue
            vals = HEX.findall(line)
            if not vals:
                continue
            out.append({"file": t, "line": i, "values": vals,
                        "text": line.strip()[:160]})
    return out


def readers(name, code, skip):
    """-> [(file, line)] where CODE READS the constant `name`. `code` is the caller's
    {path: [(lineno, line)]} map from `code_lines`, so nothing is cached here.

    THE CACHE THAT IS NOT HERE WAS A HAZARD. An earlier version memoised the line map on
    `id(corpus)`. CPython reuses an address once an object is freed, so a second census over
    a DIFFERENT corpus can read the FIRST one's lines -- and this census's plant runs two
    censuses in one process over two corpora that differ by exactly one hex digit. A cache
    that aliases those two would hand the plant the control's answer and score a vacuous
    negative as a pass. The caller already builds the map, so nothing needs memoising.

    THE READER TEST IS SCOPED TO THE FILE THAT DEFINES THE CONSTANT, and the first draft of
    this census got that wrong in a way that flattered the tree: it searched every code file
    for the NAME, so `checks/differ.py:62`'s `ORACLE_PIN` scored 37 readers -- all of them
    `gates/beautiful-mnist-gate.py` reading its OWN `ORACLE_PIN` -- and CANNOT-FAIL came out
    0. A module-level constant is visible to its own module and to nobody else; a name seen
    somewhere else in the tree is a DIFFERENT variable that happens to share a spelling. This
    is the same mistake as the prose reader defect, one level down: a mention is not a read,
    and now neither is a namesake.

    A file that does `from <module> import <NAME>` really does read it, so an import of the
    name is counted too. That arm is deliberately weak -- a hyphenated module name cannot be
    imported by `import`, only by `importlib`, so this tree's constants are nearly all
    file-local and the lexical arm is the one that decides.

    `skip` is `(file, first_line, last_line)` and `last_line` is the binding's OWN measured
    extent from `rhs_of`, not a guessed margin. The guess was `abs(i - binding) <= 4`, and it
    declared all three of `examples/mlperf/scripts/stable_diffusion_downloads.sh`'s pins
    CANNOT-FAIL when its own file reads them four lines later at
    `echo "${CLIP_WEIGHTS_SHA256} ..." | sha256sum -c`. A margin wide enough to cover a dict
    literal is also wide enough to swallow the read, and it reported the accusation as a fact.
    """
    pat = re.compile(r"\b" + re.escape(name) + r"\b")
    file_name, first, last = skip
    hit = []
    for t, lines in code.items():
        for i, ln in lines:
            if not pat.search(ln):
                continue
            if t == file_name and first <= i <= last:
                continue
            if t == file_name:
                hit.append((t, i))
            elif re.search(r"\bimport\b.*\b" + re.escape(name) + r"\b", ln):
                hit.append((t, i))
    return hit


def host_census(corpus, host):
    """The classifier's own error budget, measured. A census that reports a population
    it cannot account for is the `checks/sweep.py` LIVE_UNITS defect in a new costume."""
    by = Counter(host.values())
    bad_py = sorted(t for t in corpus if host[t] == "prose" and t.endswith(".py"))
    bad_md = sorted(t for t in corpus if host[t] == "python" and t.endswith(".md"))
    return {
        "by-host": dict(by),
        "py-extends-host-prose": len(bad_py),
        "py-examples": bad_py[:5],
        "md-parses-as-python": len(bad_md),
        "md-examples": bad_md[:5],
    }