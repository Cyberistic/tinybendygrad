#!/usr/bin/env python3
"""header-census-gate.py -- THE PORT's `.bend` HEADERS: what they CLAIM, and what still RESOLVES.

    .venv/bin/python gates/header-census-gate.py
    .venv/bin/python gates/header-census-gate.py --rows OUT.rows
    .venv/bin/python gates/header-census-gate.py --report
    .venv/bin/python gates/header-census-gate.py --plant

UPSTREAM IS THE LOCAL REF `refs/remotes/upstream/master`. This file does not fetch.

ZERO `bend` LANES. The subject is PROSE: a `.bend` header is a `#` comment block, and a
claim inside it is not code, so a comment stripper makes every claim in the tree vanish while
reporting rc=0 PASS. `gates/citations-census-gate.py` already established that asymmetry for
`file:line` claims in MARKDOWN; this file asks the same question of the PORT's OWN headers, and
asks a SECOND question that the markdown census cannot: not "does this line exist" but "AT WHICH
UPSTREAM REVISION does this header hold".

THE POPULATION IS DISCOVERED BY A DIRECTORY WALK, NOT NAMED. `os.walk` over `tinybendygrad/`
plus `endswith(".bend")`, because `glob('*.bend')` returns `[]` when `.bend` files ARE on disk --
the trap `AGENTS.md` records. A census that names its population by hand is a list.

WHAT A HEADER IS, AND WHY IT IS NOT "THE FIRST N LINES". `tinybendygrad/nn/__init__.bend` puts
its `import` lines FIRST and its header block AFTER them, so a "first comment run" rule that
insists on line 1 finds nothing; and `tinybendygrad/runtime/support/nv/ip.bend` has a 369-line
header, so a rule that stops at the first blank line would find 4 lines. The rule here is: skip a
leading run of blank/`import`/`export` lines, then take the maximal run of comment lines (blanks
allowed INSIDE it), which is the block a reader sees before the first `def`.

THE TWO CLAIM CLASSES, AND THEY ARE SEPARATE QUESTIONS.

  L  LINE-COUNT. A header says "<N> lines" and the reader checks the file. There are FOUR
     subject shapes and the instrument does not guess between them:
       NAMED-UPSTREAM  the line names a `.py` file          -> that upstream file
       NAMED-PORT     the line names a `.bend` file         -> that port file
       SELF           the line names nothing               -> the header's OWN file
       AMBIGUOUS      the line names nothing AND the header names an upstream target
                      -> the count is checked against BOTH, and the verdict says which one it
                         matched. A count that matches NEITHER is false of every file the header
                         names, which is a sound statement; a count that matches one is true of
                         that one, and naming WHICH is the whole value of the measurement.
     AN APPROXIMATOR ("about", "~", "remaining", "of the", "at least") makes the claim
     UNFALSIFIABLE, and an unfalsifiable claim is counted and not verdicted.

  C  CITATION. A header says `file.py:123` or a bare `:123` whose subject is the nearest file it
     named before. Every citation is resolved against TWO corpora: the PORT on disk, and UPSTREAM
     at HEAD (`refs/remotes/upstream/master`, which is what `tinygrad/` is vendored from).

THE MEASUREMENT NOBODY HAD, AND IT IS THE POINT OF THIS FILE. A header's citations are written
against SOME upstream revision, and that revision is DISCOVERED, not declared: for every upstream
commit that touched a file the header cites, the header's claims are evaluated against the state
of the tree AT that commit, and the newest commit at which they ALL hold is the revision the
header is written against. A header whose claims hold at NO commit is a header whose citations
are permanently dangling, and that is a different defect from a header that is merely BEHIND.

THE EXITS ARE `gatekit`'s. `REFUSED` (3) when the port tree or upstream is absent -- an absent
input is not a pass. `DEAD` (5) when no row was emitted. `FAIL` (1) when a lane is red.

THIS GATE IS RED ON THIS TREE, AND IT SAYS SO RATHER THAN HIDING IT. A red gate is a list of
defects to strike; a green one that was green because it measured nothing is worse.
"""

from __future__ import annotations

import bisect
import collections
import os
import re
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

ROOT = HERE.parent
PORT_REL = "tinybendygrad"
UPSTREAM = "refs/remotes/upstream/master"

SKIP_DIRS = {".git", ".venv", "references", "__pycache__", "node_modules"}

# --------------------------------------------------------------------------- the header

def header_block(lines: list[str]) -> tuple[int, int, list[str]]:
    """`(first line no, last line no, the block)` of a `.bend` file's header.

    SKIP a leading run of blank / `import` / `export` lines, then take the maximal run of
    comment lines. BLANKS ARE ALLOWED INSIDE the run, so a header that is broken into
    paragraphs is one block, and the run ENDS at the first line that is neither a comment nor
    blank -- which is the first `def`, the first `import` after the header, or the first data
    line. `(0, 0, [])` means the file has no header at all, and that is a RESULT and not a
    crash: it is counted and printed.
    """
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s == "" or s.startswith("import ") or s.startswith("export "):
            i += 1
            continue
        break
    start = i
    end = i
    seen = False
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("#"):
            seen = True
            end = i
            i += 1
            continue
        if s == "":
            i += 1
            continue
        break
    if not seen:
        return (0, 0, [])
    return (start + 1, end + 1, lines[start:end + 1])


def declared_target(block: list[str]) -> str:
    """The upstream `.py` this header says it is a port of, or "".

    READ OUT OF THE HEADER, not remembered: the first `tinygrad/...py` path in the block. A
    header that names none has no declared target and every bare `:N` in it is then
    UNRESOLVED-BY-SHAPE rather than pointed at a guess.
    """
    m = re.search(r"\b(tinygrad/[A-Za-z0-9_./]+\.py)\b", "\n".join(block))
    return m.group(1) if m else ""


# --------------------------------------------------------------------------- claim shapes

# "3960 lines", "4,641 lines", "626 LINES", "111 lines"
COUNT_RE = re.compile(r"(?<![\w.])(\d{1,7}(?:,\d{3})*)\s*[-–]?\s*(?:LINES|lines)\b")
# a file name in a header: `foo.py`, `tinygrad/a/b.py`, `foo.bend`
FILE_RE = re.compile(r"(?<![\w./-])((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(?:py|bend))\b")
# a citation with an explicit subject
CITE_RE = re.compile(r"(?<![\w./-])((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(?:py|bend)):(\d+)(?:-(\d+))?")
# a citation with NO subject: `:123` or `:123-456`. The negative lookbehind rejects `x.py:123`'s
# tail only because that span was already consumed by CITE_RE.
BARE_RE = re.compile(r"(?<![\w/.\-]):(\d+)(?:-(\d+))?(?![\w:])")
# "py:161-185" -- the header's own shorthand for its declared target
PY_ALIAS = "py"

# An approximator makes a count unfalsifiable only when it modifies THAT count. `and` / `or` /
# `per` anywhere earlier on the line do not: "WHAT THIS FILE IS, AND ... is 75 lines" is a
# falsifiable 75. The window is the characters immediately before the number.
APPROX_RE = re.compile(r"(?i)(?:~|\b(?:about|around|roughly|remaining|at least|nearly|almost|"
                       r"of the|of which)\b)")
APPROX_WINDOW = 32
# a count of a COMMAND'S OUTPUT rather than of a file. Searched on THIS count's clause, not the
# rest of the line: "3960 lines, 611 gate rows" is a line count that shares a line with a row
# count, and marking it unfalsifiable hides the claim.
OUTPUT_RE = re.compile(r"(?i)\b(?:returns?|prints?|emits?|outputs?|rows?)\b")

SUBJECT_UPSTREAM = "UPSTREAM"
SUBJECT_PORT = "PORT"
SUBJECT_SELF = "SELF"
SUBJECT_AMBIGUOUS = "AMBIGUOUS"
SUBJECT_NONE = "NONE"


def count_claims(block: list[str], first: int, rel: str) -> list[dict]:
    """Every "<N> lines" claim in a header, with its subject shape.

    FOUR SHAPES, AND THE SHAPE DECIDES WHAT THE CLAIM IS ABOUT:

      RANGE   the line carries a `file:N-M` range whose span IS the count. The count is then
              not a separate claim at all -- it is the range written twice -- so the verdict
              is about the RANGE, and the arithmetic is checked too.
      FILE    the line names a file.
      TREE    the line names a GLOB or a total ("4,641 lines of autogen", "autogen/am/*.py"),
              so the subject is a SET of files and the count is a SUM.
      AMBIG   the line names no file and no glob, so the count is about "something"; it is
              checked against the header's own file and against the header's declared
              upstream target, and the verdict says which one it matched.

    A HEADER THAT NAMES NO FILE STILL MAKES A CLAIM, and the instrument says so rather than
    dropping the row: a rule that drops rows and does not say how many is indistinguishable
    from a rule that never matched them.
    """
    out: list[dict] = []
    for off, ln in enumerate(block):
        no = first + off
        for m in COUNT_RE.finditer(ln):
            n = int(m.group(1).replace(",", ""))
            before = ln[:m.start()]
            named = FILE_RE.findall(before)
            subject = named[-1] if named else ""
            # A RANGE ON THE SAME LINE WHOSE SPAN IS THE COUNT.
            rng = None
            for rm in CITE_RE.finditer(ln):
                lo, hi = int(rm.group(2)), int(rm.group(3)) if rm.group(3) else int(rm.group(2))
                if hi - lo + 1 == n:
                    rng = (rm.group(1), lo, hi)
                    break
            if rng:
                kind = "RANGE"
            elif subject and ("*" in subject or subject.endswith("/")):
                kind = "TREE"
            elif subject.endswith(".py"):
                kind = "UPSTREAM"
            elif subject.endswith(".bend"):
                kind = "PORT"
            else:
                kind = "AMBIG"
            window = before[-APPROX_WINDOW:]
            clause_tail = ln[m.end():].split(",")[0].split(";")[0][:40]
            approx = bool(APPROX_RE.search(window)) or bool(
                OUTPUT_RE.search(window + m.group(0) + clause_tail))
            out.append({"rel": rel, "at": no, "n": n, "named": subject, "kind": kind,
                        "range": rng, "approx": approx, "line": ln.strip()})
    return out

def citation_claims(block: list[str], first: int, rel: str, target: str) -> list[dict]:
    """Every `file:line` citation in a header, with its subject.

    A BARE `:N` IS THE DECLARED TARGET when the header has one. An explicit `other.py:12`
    does not replace it: `ops_nv.bend` writes `hcq2.py:63` and, on the same line,
    `:818-824`, and `:818` is inside `ops_nv.py` (834 lines), not `hcq2.py` (563). A sticky
    ambient reports that line DANGLING. A same-line filename wins only when it is not already
    the subject of an explicit cite on that line (`resnet.bend`'s census at `:40`).

    A header with NO declared target keeps the most recent filename, which is the only
    subject it has named. A bare `:N` with nothing named before it is UNRESOLVED-BY-SHAPE,
    counted, not pointed at a guess.
    """
    out: list[dict] = []
    last_named = ""
    for off, ln in enumerate(block):
        no = first + off
        consumed: list[tuple[int, int]] = []
        explicit = {m.group(1) for m in CITE_RE.finditer(ln)}
        for m in CITE_RE.finditer(ln):
            consumed.append(m.span())
            subject = m.group(1)
            lo = int(m.group(2))
            hi = int(m.group(3)) if m.group(3) else lo
            kind = SUBJECT_UPSTREAM if subject.endswith(".py") else SUBJECT_PORT
            out.append({"rel": rel, "at": no, "subject": subject, "kind": kind,
                        "lo": lo, "hi": hi, "line": ln.strip()})
        if not target:
            named_on_line = FILE_RE.findall(ln)
            if named_on_line:
                last_named = named_on_line[-1]
        for m in BARE_RE.finditer(ln):
            if any(a <= m.start() < b for a, b in consumed):
                continue
            lo = int(m.group(1))
            hi = int(m.group(2)) if m.group(2) else lo
            same = [fm.group(1) for fm in FILE_RE.finditer(ln)
                    if fm.end() <= m.start() and fm.group(1) not in explicit]
            subject = same[-1] if same else (target or last_named)
            if not subject:
                out.append({"rel": rel, "at": no, "subject": "", "kind": SUBJECT_NONE,
                            "lo": lo, "hi": hi, "line": ln.strip()})
                continue
            kind = SUBJECT_UPSTREAM if subject.endswith(".py") else SUBJECT_PORT
            out.append({"rel": rel, "at": no, "subject": subject, "kind": kind,
                        "lo": lo, "hi": hi, "line": ln.strip()})
    # `py:161-185` is the header's own shorthand for its declared target.
    for c in out:
        if c["subject"] == PY_ALIAS and target:
            c["subject"] = target
    return out


# --------------------------------------------------------------------------- upstream corpus

def git(*args: str) -> str:
    p = subprocess.run(("git",) + args, cwd=ROOT, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(f"git {' '.join(args)}: rc={p.returncode} {p.stderr.strip()}")
    return p.stdout


def git_opt(*args: str) -> str:
    p = subprocess.run(("git",) + args, cwd=ROOT, capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else ""


def git_exists(spec: str) -> bool:
    """Does `git cat-file -e <spec>` SUCCEED?

    NOT `git_opt`, WHICH RETURNS STDOUT: `git cat-file -e` prints NOTHING and exits 0, so
    `if git_opt("cat-file", "-e", spec):` is FALSE FOR EVERY FILE THAT EXISTS -- an empty
    string is falsy. MEASURED: that bug reported **50 of 152** line-count claims and
    **1,198 of 4,165** citations as ABSENT-FILE, and every one of them was a file that is
    plainly there (`tinygrad/helpers.py`, `tinygrad/nn/__init__.py`). The exit STATUS is the
    answer to "does this blob exist"; stdout is the answer to "what is it".
    """
    p = subprocess.run(["git", "cat-file", "-e", spec], cwd=ROOT, capture_output=True)
    return p.returncode == 0


def upstream_files(rev: str) -> dict[str, int]:
    """`{basename: [paths]}` for every `.py` at `rev`."""
    out: dict[str, list[str]] = collections.defaultdict(list)
    for p in git("ls-tree", "-r", rev, "--name-only").splitlines():
        if p.endswith(".py"):
            out[p.rsplit("/", 1)[-1]].append(p)
    return out


class Upstream:
    """The upstream corpus and its HISTORY, asked of git.

    THE TIMELINE IS A STEP FUNCTION, NOT A LIST OF SNAPSHOTS. A file's content changes only at
    the commits that touched it, so for every cited file the instrument keeps, per upstream
    commit index (0 = HEAD, descending), the LINE COUNT at that point. A header's claims are
    then evaluated against a candidate revision by asking the step function, which is O(log n)
    per claim rather than a checkout per revision.
    """

    def __init__(self, rev: str):
        self.rev = rev
        self.order: list[str] = git("log", "--format=%H", rev).split()
        self.index = {c: i for i, c in enumerate(self.order)}
        self.nlines: dict[str, list[int | None]] = {}   # path -> [nlines at each touching commit]
        self.touch: dict[str, list[int]] = {}            # path -> [global index of each touching commit]
        self._steps: dict[str, list[tuple[int, int | None]]] = {}
        self._holds: dict[tuple[str, int], list[tuple[int, int]]] = {}
        self._counts: dict[str, dict[int, list[tuple[int, int]]]] = {}
        self._files: dict[str, list[str]] | None = None
        self._suffix: dict[str, list[str]] | None = None
        self._ever: dict[str, list[str]] | None = None
        self._head_files: dict[str, int] = {}

    # -- the corpus --------------------------------------------------------------
    def files(self) -> dict[str, list[str]]:
        if self._files is None:
            self._files = upstream_files(self.rev)
        return self._files

    def suffixes(self) -> dict[str, list[str]]:
        """`{'/a/b.py': [paths]}` -- the three ways a header spells an upstream file.

        A HEADER SPELLS AN UPSTREAM FILE FOUR WAYS and three of them are not the full path:
        `tinygrad/runtime/support/hcq2.py`, `runtime/support/hcq2.py`, `support/hcq2.py` and
        `hcq2.py`. MEASURED: a resolver that knew only the basename and the `tinygrad/`-prefixed
        full path reported **1,693 of 4,165** citations as ABSENT-FILE, and every one of them
        was a PATH THAT EXISTS. A suffix index is what closes that, and it is the same rule
        `checks/cites-census.py` uses for its own universe.
        """
        if self._suffix is None:
            s: dict[str, list[str]] = collections.defaultdict(list)
            for p in self.files().values():
                for path in p:
                    s["/" + path].append(path)
                    j = path.find("/")
                    while j != -1:
                        s[path[j:]].append(path)
                        j = path.find("/", j + 1)
            self._suffix = s
        return self._suffix

    def ever(self) -> dict[str, list[str]]:
        """Every path that EVER existed upstream, by basename.

        A HEADER MAY CITE A FILE UPSTREAM NO LONGER KEEPS, and that citation can still be
        TRUE at an older revision -- so the corpus of the HISTORY is not the corpus at HEAD.
        MEASURED on this tree: `tinygrad/runtime/support/hcq.py` was removed upstream
        (`98807603d`, 2026-09-22) and headers still cite it.
        """
        if self._ever is None:
            e: dict[str, list[str]] = collections.defaultdict(list)
            out = git("log", "--format=", "--name-only", "--diff-filter=AM", self.rev,
                      "--", "*.py")
            for path in out.splitlines():
                if path.endswith(".py") and path not in e[path.rsplit("/", 1)[-1]]:
                    e[path.rsplit("/", 1)[-1]].append(path)
            self._ever = e
        return self._ever

    def head_nlines(self, path: str) -> int:
        if path not in self._head_files:
            t = git_opt("show", f"{self.rev}:{path}")
            self._head_files[path] = len(t.splitlines()) if t else 0
        return self._head_files[path]

    def resolve(self, subject: str, history: bool = False,
                prefer_dir: str = "") -> tuple[str | None, str]:
        """A cited subject -> `(upstream path, how)`. AMBIGUOUS IS A REFUSAL, NEVER `absent`.

        `history=True` also considers paths upstream no longer keeps, because a header's
        citation of a DELETED upstream file can still be TRUE at an older revision.

        `prefer_dir` is the AMBIENT DISAMBIGUATOR, and it is what makes a bare basename
        resolvable: MEASURED, `op.py` names TWO upstream files, `dtype.py` three and
        `helpers.py` seven, so a basename-only resolver called 438 of 4,165 citations
        ABSENT-FILE -- every one of them a file that EXISTS. A header that declares its port
        target (`tinygrad/codegen/decomp/op.py`) has already said which directory it means,
        and the candidate in that directory is the citation. Without the tie-break the honest
        answer is AMBIGUOUS, and an ambiguous answer that the header itself can settle is a
        refusal the header has already answered.
        """
        files = self.files()
        if subject.startswith("tinygrad/"):
            if git_exists(f"{self.rev}:{subject}"):
                return subject, "exact"
            return None, "absent"
        hits = files.get(subject, [])
        if len(hits) > 1 and prefer_dir:
            near = [h for h in hits if h.rsplit("/", 1)[0] == prefer_dir]
            if len(near) == 1:
                return near[0], "basename-in-declared-dir"
            if near:
                hits = near
        if len(hits) == 1:
            return hits[0], "unique-basename"
        if len(hits) > 1:
            return None, f"ambiguous:{len(hits)}"
        hits = self.suffixes().get("/" + subject, [])
        if len(hits) > 1 and prefer_dir:
            near = [h for h in hits if h.rsplit("/", 1)[0] == prefer_dir]
            if len(near) == 1:
                return near[0], "suffix-in-declared-dir"
            if near:
                hits = near
        if len(hits) == 1:
            return hits[0], "suffix"
        if len(hits) > 1:
            return None, f"ambiguous:{len(hits)}"
        if history:
            ever = self.ever().get(subject, [])
            if len(ever) == 1:
                return ever[0], "ever-existed"
            if len(ever) > 1:
                return None, f"ambiguous:{len(ever)}"
        return None, "absent"

    # -- the history -------------------------------------------------------------
    def load(self, path: str) -> None:
        """The line count of `path` at every upstream commit that touched it.

        CACHED, AND THE CACHE IS THE POINT: the first revision of this asked git for the
        commit list on EVERY `nlines_at` call, so a header with 300 citations shelled out 300
        times for the same answer. The step function is built once per path and asked again.
        """
        if path in self._steps:
            return
        revs = git("log", "--format=%H", self.rev, "--", path).split()
        specs = [f"{c}:{path}" for c in revs]
        blobs = batch_blobs(specs)
        pairs: list[tuple[int, int | None]] = []
        for c in revs:
            if c not in self.index:
                continue
            b = blobs.get(f"{c}:{path}")
            pairs.append((self.index[c], len(b.splitlines()) if b is not None else None))
        pairs.sort()
        self._steps[path] = pairs

    def nlines_at(self, path: str, gidx: int) -> int | None:
        """The line count of `path` at global commit index `gidx`."""
        self.load(path)
        pairs = self._steps.get(path) or []
        if not pairs:
            return None
        # the state at gidx is the newest touching commit at index <= gidx
        j = bisect.bisect_right([p[0] for p in pairs], gidx) - 1
        if j < 0:
            return None
        return pairs[j][1]

    def touch_indices(self, path: str) -> list[int]:
        self.load(path)
        return [p[0] for p in (self._steps.get(path) or [])]

    def holds_at(self, path: str, hi: int) -> list[tuple[int, int]]:
        """The global-index INTERVALS at which `path` has at least `hi` lines.

        AN INTERVAL SET, NOT A SCAN. A header's claims are intersected, and a header may cite
        a file with 400 versions; scanning 400 candidates per claim per header is 400 x N
        claims x N headers of `git` calls, which is how the first version of this file ran for
        minutes without answering. The step function is monotone in the file's own history, so
        the satisfying set is a union of intervals and the intersection of those is a sweep.
        """
        key = (path, hi)
        if key in self._holds:
            return self._holds[key]
        self.load(path)
        pairs = self._steps.get(path) or []
        n = len(self.order)
        out: list[tuple[int, int]] = []
        for k, (_i, cnt) in enumerate(pairs):
            if cnt is None or cnt < hi:
                continue
            end = (pairs[k + 1][0] - 1) if k + 1 < len(pairs) else n - 1
            if out and out[-1][1] + 1 == _i:
                out[-1] = (out[-1][0], end)
            else:
                out.append((_i, end))
        self._holds[key] = out
        return out

    def count_intervals(self, path: str) -> dict[int, list[tuple[int, int]]]:
        """The global-index INTERVALS at which `path` has EXACTLY N lines, for every N.

        THIS IS WHAT MAKES "RESOLVES AT AN OLDER REVISION" A MEASUREMENT. A header that says
        "`hcq2.py` is 646 lines" is false at upstream HEAD (563 lines) and TRUE at a revision
        where the file was 646 lines, and the difference between the two is a claim about the
        tree's PRESENT and a claim about its PAST -- two different defects, and the instrument
        has to be able to say which one it is holding.
        """
        if path in self._counts:
            return self._counts[path]
        self.load(path)
        pairs = self._steps.get(path) or []
        n = len(self.order)
        out: dict[int, list[tuple[int, int]]] = {}
        for k, (_i, cnt) in enumerate(pairs):
            if cnt is None:
                continue
            end = (pairs[k + 1][0] - 1) if k + 1 < len(pairs) else n - 1
            out.setdefault(cnt, [])
            if out[cnt] and out[cnt][-1][1] + 1 == _i:
                out[cnt][-1] = (out[cnt][-1][0], end)
            else:
                out[cnt].append((_i, end))
        self._counts[path] = out
        return out

    def newest_with_count(self, path: str, want: int) -> str:
        """The NEWEST upstream commit at which `path` has exactly `want` lines, or ""."""
        iv = self.count_intervals(path).get(want)
        if not iv:
            return ""
        return self.order[iv[0][0]]


def batch_blobs(specs: list[str]) -> dict[str, str]:
    """`spec` -> text for many specs, in ONE `git cat-file --batch`.

    THE CONTENT IS READ BY SIZE AND NOT BY A DELIMITER: a `.py` file contains newlines.
    """
    if not specs:
        return {}
    p = subprocess.run(["git", "cat-file", "--batch"], cwd=ROOT,
                       input=("\n".join(specs) + "\n").encode(), capture_output=True)
    out: dict[str, str] = {}
    buf, pos = p.stdout, 0
    for spec in specs:
        nl = buf.find(b"\n", pos)
        if nl < 0:
            break
        parts = buf[pos:nl].decode("utf-8", "replace").split()
        pos = nl + 1
        if len(parts) < 3 or parts[1] == "missing":
            continue
        size = int(parts[2])
        out[spec] = buf[pos:pos + size].decode("utf-8", "replace")
        pos += size + 1
    return out


# --------------------------------------------------------------------------- the port corpus

class Port:
    """The port's own files on disk, indexed the three ways a citation can spell one.

    PATHS ARE REPO-RELATIVE, so a header's own path and a cited path are the same kind of
    string and the SELF comparison in `resolve_count` is a comparison of two paths of one
    shape.  A port-relative path would make `nn/__init__.bend` resolve and
    `tinybendygrad/nn/__init__.bend` not, and the difference is a spelling.
    """

    def __init__(self, base: Path, port_root: Path):
        self.base = base
        self.paths: list[str] = []
        for dp, dn, fn in os.walk(port_root):
            dn[:] = [d for d in dn if d not in SKIP_DIRS]
            for n in sorted(fn):
                if n.endswith(".bend"):
                    self.paths.append(str((Path(dp) / n).relative_to(base)))
        self.suffix: dict[str, list[str]] = collections.defaultdict(list)
        self.base_name: dict[str, list[str]] = collections.defaultdict(list)
        self.lines: dict[str, list[str]] = {}
        for p in self.paths:
            self.suffix["/" + p].append(p)
            j = p.find("/")
            while j != -1:
                self.suffix[p[j:]].append(p)
                j = p.find("/", j + 1)
            self.base_name[p.rsplit("/", 1)[-1]].append(p)

    def resolve(self, subject: str, prefer_dir: str = "") -> tuple[str | None, str]:
        if subject in self.paths:
            return subject, "exact"
        # a port path is spelled relative to the port tree in the headers
        rel = subject if subject.startswith(PORT_REL + "/") else f"{PORT_REL}/{subject}"
        if rel in self.paths:
            return rel, "port-relative"
        hits = self.suffix.get("/" + subject, [])
        if len(hits) == 1:
            return hits[0], "suffix"
        if len(hits) > 1:
            return None, f"ambiguous:{len(hits)}"
        hits = self.base_name.get(subject, [])
        if len(hits) > 1 and prefer_dir:
            near = [h for h in hits if h.rsplit("/", 1)[0] == prefer_dir]
            if len(near) == 1:
                return near[0], "basename-in-declared-dir"
            if near:
                hits = near
        if len(hits) == 1:
            return hits[0], "unique-basename"
        if len(hits) > 1:
            return None, f"ambiguous:{len(hits)}"
        return None, "absent"

    def body(self, rel: str) -> list[str]:
        if rel not in self.lines:
            self.lines[rel] = (self.base / rel).read_text(encoding="utf-8",
                                                          errors="replace").splitlines()
        return self.lines[rel]


# --------------------------------------------------------------------------- the census

#: A SCRATCH COPY IS NOT A SOURCE FILE. The tree's own `.gitignore` carries `*mut.bend`
#: for exactly this: a mutation-probe copy of a file, kept beside the original so a probe
#: can mutate it. A census that walked the FILESYSTEM counted a scratch copy's markers as
#: the port's citations, and one of them was a FALSE CITATION that NOBODY COULD FIX,
#: because the file is not the port's. A NAME RULE, NOT A GIT CALL: `git ls-files` reads
#: the INDEX, and this tree's index is armed (see `checks/index-arm-gate.py`).
def is_scratch(name: str) -> bool:
    return name.endswith("-mut.bend") or name.endswith(".bak")


def walk_bend(base: Path) -> list[Path]:
    """The port's `.bend` SOURCE files. DISCOVERED, NOT NAMED."""
    out: list[Path] = []
    for dp, dn, fn in os.walk(base):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for n in sorted(fn):
            if n.endswith(".bend") and not is_scratch(n):
                out.append(Path(dp) / n)
    return out


_PORT_HIST: dict[str, list[tuple[str, int]]] = {}


def port_history(rel: str) -> list[tuple[str, int]]:
    """`(commit, splitlines count)` newest-first, in THIS repo, not upstream.

    A self-count can be true of a commit here and false of HEAD, and upstream's history
    cannot see it. `ops_nv.bend`'s "3960 lines, 630 def/type" held at `d2cde2f2c` and has
    never been the line count of `ops_nv.py`.
    """
    if rel in _PORT_HIST:
        return _PORT_HIST[rel]
    revs = git_opt("log", "--format=%H", "HEAD", "--", rel).split()
    blobs = batch_blobs([f"{c}:{rel}" for c in revs])
    rows = [(c, len(blobs[f"{c}:{rel}"].splitlines())) for c in revs if f"{c}:{rel}" in blobs]
    _PORT_HIST[rel] = rows
    return rows


def port_newest_with_count(rel: str, want: int) -> str:
    """The newest commit of THIS repo at which `rel` has exactly `want` lines, or ""."""
    for commit, n in port_history(rel):
        if n == want:
            return commit
    return ""


def missing(subject: str, how: str, where: str) -> tuple[str, str]:
    """AMBIGUOUS IS NOT ABSENT. A basename that names seven files is a refusal to guess."""
    if how.startswith("ambiguous:"):
        return ("AMBIGUOUS", f"{subject!r} names {how.removeprefix('ambiguous:')} {where} "
                             f"files; not guessed")
    return ("ABSENT-FILE", f"no {where} file is {subject!r} ({how})")


def resolve_count(claim: dict, up: Upstream, port: Port, target: str) -> tuple[str, str]:
    """`(verdict, why)` for one line-count claim.

    THE VERDICT NAMES WHICH QUESTION WAS ASKED, because "the count is wrong" and "the count
    was right and the file has since changed" are different defects and a reader cannot act
    on the second one by editing the header.
    """
    if claim["approx"]:
        return ("APPROXIMATE", "the claim carries an approximator or counts a command's output, "
                               "so it is not falsifiable and is counted, not verdicted")
    kind = claim["kind"]
    if kind == "RANGE":
        subject, lo, hi = claim["range"]
        if subject.endswith(".py"):
            path, how = up.resolve(subject, prefer_dir=claim.get("prefer_dir", ""))
            if path is None:
                return missing(subject, how, "upstream")
            n = up.head_nlines(path)
            if hi > n:
                iv = up.holds_at(path, hi)
                rev = up.order[iv[0][0]] if iv else ""
                return ("RANGE-DANGLING",
                        f"{path} has {n} lines at upstream HEAD, the range ends at :{hi}"
                        + (f"; the range was inside the file at {rev[:12]}" if rev else
                           "; the range has never been inside the file"))
            return ("RANGE-RESOLVES", f"{path} has {n} lines at upstream HEAD; the range "
                                      f":{lo}-{hi} is inside it")
        path, how = port.resolve(subject, prefer_dir=claim.get("prefer_port_dir", ""))
        if path is None:
            return missing(subject, how, "port")
        body = port.body(path)
        if hi > len(body):
            return ("RANGE-DANGLING", f"{path} has {len(body)} lines, the range ends at :{hi}")
        return ("RANGE-RESOLVES", f"{path} has {len(body)} lines; the range :{lo}-{hi} is inside it")
    if kind == "UPSTREAM":
        path, how = up.resolve(claim["named"], prefer_dir=claim.get("prefer_dir", ""))
        if path is None:
            return missing(claim["named"], how, "upstream")
        n = up.head_nlines(path)
        if n == claim["n"]:
            return ("RESOLVES", f"{path} has {n} lines at upstream HEAD")
        rev = up.newest_with_count(path, claim["n"])
        if rev:
            return ("RESOLVES-AT-OLDER-REVISION",
                    f"{path} has {n} lines at upstream HEAD, not {claim['n']}; it had "
                    f"{claim['n']} lines at {rev[:12]}")
        return ("STALE", f"{path} has {n} lines at upstream HEAD and has NEVER had "
                         f"{claim['n']} lines")
    if kind == "PORT":
        path, how = port.resolve(claim["named"], prefer_dir=claim.get("prefer_port_dir", ""))
        if path is None:
            return missing(claim["named"], how, "port")
        n = len(port.body(path))
        if n == claim["n"]:
            return ("RESOLVES", f"{path} has {n} lines")
        rev = port_newest_with_count(path, claim["n"])
        if rev:
            return ("RESOLVES-AT-OLDER-REVISION",
                    f"{path} has {n} lines now, not {claim['n']}; it had {claim['n']} lines "
                    f"at {rev[:12]} (this repo, not upstream)")
        return ("STALE", f"{path} has {n} lines, not {claim['n']}, and no commit of it has")
    if kind == "TREE":
        return ("TREE-COUNT", f"the subject is a SET of files ({claim['named'] or '(a total)'}) "
                               f"and this instrument sums single files; the count is "
                               f"{claim['n']} and is NOT verdicted here")
    # AMBIG: the claim names no file. It is checked against the header's OWN file and
    # against the header's DECLARED UPSTREAM TARGET, and the verdict says which it matched.
    own = len(port.body(claim["rel"]))
    if own == claim["n"]:
        return ("RESOLVES-SELF", f"the header's own file {claim['rel']} has {own} lines")
    if target:
        path, how = up.resolve(target.rsplit("/", 1)[-1], prefer_dir=claim.get("prefer_dir", ""))
        if path:
            n = up.head_nlines(path)
            if n == claim["n"]:
                return ("RESOLVES-UPSTREAM", f"{path} has {n} lines at upstream HEAD")
            rev = up.newest_with_count(path, claim["n"])
            if rev:
                return ("RESOLVES-AT-OLDER-REVISION",
                        f"neither {claim['rel']} ({own} lines) nor {path} ({n} lines at HEAD) "
                        f"has {claim['n']} lines NOW; {path} had {claim['n']} lines at "
                        f"{rev[:12]}")
    rev = port_newest_with_count(claim["rel"], claim["n"])
    if rev:
        return ("RESOLVES-AT-OLDER-REVISION",
                f"{claim['rel']} has {own} lines now; it had {claim['n']} lines at {rev[:12]} "
                f"(this repo, not upstream)")
    return ("STALE", f"neither {claim['rel']} ({own} lines, and no commit of it) nor the "
                     f"declared target {target or '(none)'} has {claim['n']} lines")


def resolve_citation(claim: dict, up: Upstream, port: Port) -> tuple[str, str]:
    """`(verdict, why)` for one citation, at upstream HEAD / on the port's disk."""
    if claim["kind"] == SUBJECT_NONE or not claim["subject"]:
        return ("UNRESOLVED-BY-SHAPE",
                "a bare :N with no file named before it; counted, not pointed at a guess")
    if claim["kind"] == SUBJECT_PORT:
        path, how = port.resolve(claim["subject"], prefer_dir=claim.get("prefer_port_dir", ""))
        if path is None:
            return missing(claim["subject"], how, "port")
        body = port.body(path)
        if claim["hi"] > len(body):
            return ("DANGLING-LINE", f"{path} has {len(body)} lines, cited at :{claim['lo']}-{claim['hi']}")
        return ("RESOLVES", f":{claim['lo']}-{claim['hi']} is inside {path} ({len(body)} lines)")
    path, how = up.resolve(claim["subject"], prefer_dir=claim.get("prefer_dir", ""))
    if path is None:
        return missing(claim["subject"], how, "upstream")
    n = up.head_nlines(path)
    if claim["hi"] > n:
        return ("DANGLING-LINE",
                f"{path} has {n} lines at upstream HEAD, cited at :{claim['lo']}-{claim['hi']}")
    return ("RESOLVES", f":{claim['lo']}-{claim['hi']} is inside {path} ({n} lines at upstream HEAD)")


def intersect(a: list[tuple[int, int]], b: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """The intersection of two interval sets."""
    out: list[tuple[int, int]] = []
    i = j = 0
    while i < len(a) and j < len(b):
        lo = max(a[i][0], b[j][0])
        hi = min(a[i][1], b[j][1])
        if lo <= hi:
            if out and out[-1][1] + 1 >= lo:
                out[-1] = (out[-1][0], max(out[-1][1], hi))
            else:
                out.append((lo, hi))
        if a[i][1] < b[j][1]:
            i += 1
        else:
            j += 1
    return out


def revision_set(header: dict, up: Upstream, port: Port, target: str) -> tuple[str, str]:
    """The newest upstream commit at which EVERY claim of a header holds, or "".

    DISCOVERED, NOT DECLARED. The candidate revisions are the upstream commits that touched a
    file the header cites -- the state of the tree can only change there -- and each candidate
    is EVALUATED against the header's claims. The newest candidate at which they all hold is
    the revision the header is written against, and it is found, not remembered.
    """
    claims = [c for c in header["citations"] if c["kind"] == SUBJECT_UPSTREAM]
    if not claims:
        return ("", "the header cites no upstream file")
    sets: list[tuple[str, list[tuple[int, int]]]] = []
    for c in claims:
        p, how = up.resolve(c["subject"], history=True,
                            prefer_dir=c.get("prefer_dir", ""))
        if not p:
            return ("", f"the cited upstream file {c['subject']!r} does not resolve ({how})")
        sets.append((c["subject"], up.holds_at(p, c["hi"])))
    common: list[tuple[int, int]] | None = None
    for _subject, s in sets:
        common = s if common is None else intersect(common, s)
    if not common:
        return ("", "the header's upstream citations hold at NO upstream commit")
    lo, _hi = common[0]
    rev = up.order[lo]
    return (rev, f"the header's upstream citations hold at {rev[:12]}, "
                f"{lo} upstream commits behind HEAD")


def judge_tree(root: Path, up: Upstream) -> tuple[list[str], list[str]] | None:
    """Verdict lists for the one `.bend` file under `root/tinybendygrad`. None if the copy is empty."""
    port_root = root / PORT_REL
    files = walk_bend(port_root)
    if len(files) != 1:
        return None
    port = Port(root, port_root)
    p = files[0]
    body = p.read_text(encoding="utf-8").splitlines()
    first, _last, blk = header_block(body)
    rel = str(p.relative_to(root))
    tgt = declared_target(blk)
    counts = count_claims(blk, first, rel)
    cites = citation_claims(blk, first, rel, tgt)
    up_dir = tgt.rsplit("/", 1)[0] if "/" in tgt else ""
    port_dir = rel.rsplit("/", 1)[0]
    for c in counts + cites:
        c["prefer_dir"] = up_dir
        c["prefer_port_dir"] = port_dir
    return ([resolve_count(c, up, port, tgt)[0] for c in counts],
            [resolve_citation(c, up, port)[0] for c in cites])


def plant() -> int:
    """A lie on a copy, and an unbroken control. A crash is FAIL, not PASS.

    THE CONTROL is a byte-identical second copy and must reproduce the first copy's verdicts.
    THE HALF-LIE keeps a true line count and moves one citation past the file. A comparator
    that paints everything red fails the count; one that paints nothing red fails the citation.
    AN ABSENT FILE must not resolve. A COMMENT-STRIPPED copy must carry no claim -- the
    asymmetry the module docstring names, and the direction a census can pass by not looking.
    """
    try:
        return _plant()
    except Exception:
        print("PLANT FAILED: a crash is not a pass", file=sys.stderr)
        traceback.print_exc()
        return FAIL


def _plant() -> int:
    if not git_opt("rev-parse", "--verify", UPSTREAM):
        print(f"PLANT REFUSED: {UPSTREAM} is absent. This file does not fetch.", file=sys.stderr)
        return REFUSED
    up = Upstream(UPSTREAM)
    # A BASENAME IS NOT A FILE. `helpers.py` is 7 upstream files, and a plant that cites the
    # basename REFUSES -- which is the instrument being honest, and not a control. Cite the
    # full path, discovered from the corpus, not remembered.
    path, n = "", 0
    for paths in up.files().values():
        for cand in paths:
            if not (cand.startswith("tinygrad/") and cand.count("/") == 1):
                continue
            got = up.head_nlines(cand)
            if got >= 2:
                path, n = cand, got
                break
        if path:
            break
    if not path:
        print("PLANT REFUSED: no top-level tinygrad/*.py with at least 2 lines", file=sys.stderr)
        return REFUSED
    lie = 10_000_000
    true_src = (f"# synthetic -- port of {path}\n"
                f"# {path} is {n} lines.\n"
                f"# the first line is {path}:1.\n")
    half_src = (f"# synthetic -- port of {path}\n"
                f"# {path} is {n} lines.\n"
                f"# the first line is {path}:{lie}.\n"
                f"# and a range {path}:1-{lie}.\n")
    absent_src = ("# synthetic -- port of tinygrad/no_such_header_census_file.py\n"
                  "# no_such_header_census_file.py is 10 lines.\n"
                  "# see no_such_header_census_file.py:1.\n")
    # An explicit cite of a missing file must not poison the next bare cite. Sticky ambient
    # attributes `:1` to the missing file and reports ABSENT; the bare cite is the declared target.
    sticky_src = (f"# synthetic -- port of {path}\n"
                  f"# {path} is {n} lines.\n"
                  "# a different file is named (tinygrad/no_such_header_census_file.py:1), and\n"
                  "# the next bare cite :1 is the declared target, not that file.\n"
                  "# same line (tinygrad/no_such_header_census_file.py:1) and then :1.\n")
    stripped_src = "def plant_body() -> U32: 1\n"
    if half_src == true_src:
        print("PLANT DEAD: the mutation is a no-op", file=sys.stderr)
        return DEAD

    def write(root: Path, src: str) -> None:
        dest = root / PORT_REL / "plant.bend"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(src)

    with tempfile.TemporaryDirectory(prefix="header-census-plant-") as raw:
        td = Path(raw)
        control, control2 = td / "control", td / "control-copy"
        half, absent = td / "half", td / "absent"
        sticky, stripped = td / "sticky", td / "stripped"
        write(control, true_src)
        write(control2, true_src)
        write(half, half_src)
        write(absent, absent_src)
        write(sticky, sticky_src)
        write(stripped, stripped_src)
        raw_a = (control / PORT_REL / "plant.bend").read_bytes()
        if (control2 / PORT_REL / "plant.bend").read_bytes() != raw_a:
            print("PLANT FAILED: the unbroken control is not a byte copy", file=sys.stderr)
            return FAIL
        if (half / PORT_REL / "plant.bend").read_bytes() == raw_a:
            print("PLANT DEAD: the half-lie copy is identical to the control", file=sys.stderr)
            return DEAD
        a, b = judge_tree(control, up), judge_tree(control2, up)
        h, z = judge_tree(half, up), judge_tree(absent, up)
        k, s = judge_tree(sticky, up), judge_tree(stripped, up)
        print(f"PLANT file {path} has {n} lines at {UPSTREAM} (local ref, not fetched)")
        print(f"PLANT control {a}")
        print(f"PLANT control-copy {b}")
        print(f"PLANT half-lie {h}")
        print(f"PLANT absent {z}")
        print(f"PLANT sticky {k}")
        print(f"PLANT stripped {s}")
        bad: list[str] = []
        if a is None or b is None or a != b:
            bad.append(f"unbroken control moved or missing: {a} vs {b}")
        elif not a[0] or any(v not in ("RESOLVES", "RESOLVES-SELF", "RESOLVES-UPSTREAM")
                             for v in a[0]):
            bad.append(f"control count did not resolve: {a[0]}")
        elif not a[1] or any(v != "RESOLVES" for v in a[1]):
            bad.append(f"control citation did not resolve: {a[1]}")
        if h is None:
            bad.append("half-lie produced no header")
        else:
            if not h[0] or any(v not in ("RESOLVES", "RESOLVES-SELF", "RESOLVES-UPSTREAM")
                               for v in h[0]):
                bad.append(f"a true count went red on the half-lie: {h[0]}")
            if not h[1] or any(v == "RESOLVES" for v in h[1]):
                bad.append(f"the dangling line was not seen: {h[1]}")
        if z is None or not z[0] or not z[1]:
            bad.append(f"absent-file copy produced no claim: {z}")
        elif any(v.startswith("RESOLVES") for v in z[0] + z[1]):
            bad.append(f"an absent file resolved: {z}")
        elif any(v != "ABSENT-FILE" for v in z[0] + z[1]):
            bad.append(f"absent file was not ABSENT-FILE: {z}")
        if k is None or k[1] != ["ABSENT-FILE", "RESOLVES", "ABSENT-FILE", "RESOLVES"]:
            bad.append(f"sticky ambient was not refused: {k}")
        if s is None:
            bad.append("stripped copy was not readable")
        elif s[0] or s[1]:
            bad.append(f"a comment stripper left claims: {s}")
        if bad:
            print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
            return FAIL
        print("PLANT OK: control holds, its copy holds, the lie is seen, the true count "
              "stays true, an absent file does not resolve, a later bare cite is not poisoned, "
              "a comment stripper leaves nothing")
        return PASS


def main(argv: list[str]) -> int:
    if "--plant" in argv:
        return plant()
    rows_only = "--rows" in argv
    report_only = "--report" in argv
    rows_out = argv[argv.index("--rows") + 1] if "--rows" in argv else None

    port_root = ROOT / PORT_REL
    if not port_root.is_dir():
        print(f"REFUSED  the port tree {port_root} is ABSENT", file=sys.stderr)
        return REFUSED
    if not git_opt("rev-parse", "--verify", UPSTREAM):
        print(f"REFUSED  {UPSTREAM} is ABSENT", file=sys.stderr)
        return REFUSED

    up = Upstream(UPSTREAM)
    port = Port(ROOT, port_root)

    files = walk_bend(port_root)
    if not files:
        print("DEAD  the port tree holds no .bend file", file=sys.stderr)
        return DEAD

    headers: list[dict] = []
    nlines_all = 0
    for p in files:
        rel = str(p.relative_to(ROOT))
        body = p.read_text(encoding="utf-8", errors="replace").splitlines()
        nlines_all += len(body)
        first, last, blk = header_block(body)
        tgt = declared_target(blk)
        headers.append({"rel": rel, "first": first, "last": last, "block": blk, "target": tgt,
                        "body": len(body),
                        "counts": count_claims(blk, first, rel),
                        "citations": citation_claims(blk, first, rel, tgt)})

    with_hdr = [h for h in headers if h["first"]]
    count_claims_all = [c for h in headers for c in h["counts"]]
    cites_all = [c for h in headers for c in h["citations"]]
    hdr_with_count = {c["rel"] for c in count_claims_all}
    hdr_with_cite = {c["rel"] for c in cites_all}

    # THE AMBIENT DISAMBIGUATOR, PER HEADER: the directory of the header's declared upstream
    # target, and the directory of the header's own file. A bare basename is ambiguous in
    # upstream (`op.py` is two files, `helpers.py` seven) and the header has already said
    # which directory it means.
    for h in headers:
        up_dir = h["target"].rsplit("/", 1)[0] if "/" in h["target"] else ""
        port_dir = h["rel"].rsplit("/", 1)[0] if "/" in h["rel"] else ""
        for c in h["counts"] + h["citations"]:
            c["prefer_dir"] = up_dir
            c["prefer_port_dir"] = port_dir

    # ---- resolve every claim --------------------------------------------------------
    for c in count_claims_all:
        h = next(x for x in headers if x["rel"] == c["rel"])
        c["verdict"], c["why"] = resolve_count(c, up, port, h["target"])
    for c in cites_all:
        c["verdict"], c["why"] = resolve_citation(c, up, port)

    # ---- the revision each header is written against ---------------------------------
    for h in with_hdr:
        h["rev"], h["rev_why"] = revision_set(h, up, port, h["target"])

    CV = collections.Counter(c["verdict"] for c in count_claims_all)
    XV = collections.Counter(c["verdict"] for c in cites_all)
    hdr_count_v = collections.defaultdict(set)
    hdr_cite_v = collections.defaultdict(set)
    for c in count_claims_all:
        hdr_count_v[c["rel"]].add(c["verdict"])
    for c in cites_all:
        hdr_cite_v[c["rel"]].add(c["verdict"])

    def hdr_has(rel: str, verdicts: tuple[str, ...], table) -> bool:
        return bool(table[rel] & set(verdicts))

    stale_count = [c for c in count_claims_all
                   if c["verdict"] in ("STALE", "ABSENT-FILE", "RANGE-DANGLING")]
    dang_cite = [c for c in cites_all
                 if c["verdict"] in ("DANGLING-LINE", "ABSENT-FILE", "AMBIGUOUS")]
    behind = [h for h in with_hdr if h["rev"] and h["rev"] != up.order[0]]
    nowhere = [h for h in with_hdr if not h["rev"] and h["citations"]]
    with_cites = [h for h in with_hdr if any(c["kind"] == SUBJECT_UPSTREAM for c in h["citations"])]

    if not rows_only:
        print(f"UPSTREAM   : {UPSTREAM} = {up.rev[:12]} (local ref, not fetched)")
        print(f"POPULATION : {len(files)} .bend files (walk of {PORT_REL}/), "
              f"{nlines_all} lines")
        print(f"             {len(with_hdr)} carry a header, {len(headers) - len(with_hdr)} do not, "
              f"{sum(len(h['block']) for h in with_hdr)} header lines")
        print(f"CLAIMS     : {len(count_claims_all)} line-count claims in "
              f"{len(hdr_with_count)} headers; {len(cites_all)} file:line citations in "
              f"{len(hdr_with_cite)} headers")
        print()
        print("LANE L -- LINE-COUNT CLAIMS.  Every verdict is a MEASUREMENT against a named file.")
        for v in ("RESOLVES", "RESOLVES-SELF", "RESOLVES-UPSTREAM", "RESOLVES-AT-OLDER-REVISION",
                  "STALE", "ABSENT-FILE", "APPROXIMATE", "TREE-COUNT",
                  "RANGE-RESOLVES", "RANGE-DANGLING"):
            n = CV.get(v, 0)
            if n:
                print(f"           {v:20s} {n:6d}")
        print()
        print("LANE C -- CITATIONS, at upstream HEAD and against the port's disk.")
        for v in ("RESOLVES", "DANGLING-LINE", "ABSENT-FILE", "AMBIGUOUS", "UNRESOLVED-BY-SHAPE"):
            n = XV.get(v, 0)
            if n:
                print(f"           {v:20s} {n:6d}")
        print()
        print("LANE R -- NEWEST UPSTREAM COMMIT AT WHICH EVERY CITED LINE IS INSIDE ITS FILE.")
        print("           line-in-range, not a claim that the prose was authored there.")
        print(f"           {len(with_cites)} headers cite an upstream file")
        print(f"           {len(behind)} resolve at a revision OLDER than upstream HEAD "
              f"({up.rev[:12]})")
        print(f"           {len(nowhere)} resolve at NO upstream commit at all")
        for h in behind[:25]:
            print(f"             {h['rel']}")
            print(f"                 {h['rev_why']}")
        for h in nowhere[:25]:
            print(f"             {h['rel']}")
            print(f"                 {h['rev_why']}")
        print()
        print("THE STALE CLAIMS, EVERY ONE, because a stale claim looks fine to a reader:")
        for c in stale_count:
            print(f"  {c['rel']}:{c['at']}  claims {c['n']} lines  -- {c['why']}")
            print(f"        {c['line'][:120]}")
        print()
        print("THE DANGLING CITATIONS, EVERY ONE:")
        for c in dang_cite[:200]:
            print(f"  {c['rel']}:{c['at']}  -> {c['subject']}:{c['lo']}  -- {c['why']}")
        print()

    rows: dict[str, str] = {
        "header.port_bend_files": str(len(files)),
        "header.port_bend_lines": str(nlines_all),
        "header.files_with_header": str(len(with_hdr)),
        "header.files_without_header": str(len(headers) - len(with_hdr)),
        "header.header_lines": str(sum(len(h["block"]) for h in with_hdr)),
        "header.count_claims": str(len(count_claims_all)),
        "header.headers_with_count_claim": str(len(hdr_with_count)),
        "header.count_resolves": str(sum(CV[v] for v in ("RESOLVES", "RESOLVES-SELF",
                                                        "RESOLVES-UPSTREAM"))),
        "header.count_resolves_at_older_revision": str(CV.get("RESOLVES-AT-OLDER-REVISION", 0)),
        "header.count_range_resolves": str(CV.get("RANGE-RESOLVES", 0)),
        "header.count_range_dangling": str(CV.get("RANGE-DANGLING", 0)),
        "header.count_tree": str(CV.get("TREE-COUNT", 0)),
        "header.count_stale": str(CV.get("STALE", 0)),
        "header.count_absent_file": str(CV.get("ABSENT-FILE", 0)),
        "header.count_approximate": str(CV.get("APPROXIMATE", 0)),
        "header.headers_with_stale_count": str(len({c["rel"] for c in stale_count})),
        "header.citations": str(len(cites_all)),
        "header.headers_with_citation": str(len(hdr_with_cite)),
        "header.cite_resolves": str(XV.get("RESOLVES", 0)),
        "header.cite_dangling": str(XV.get("DANGLING-LINE", 0)),
        "header.cite_absent_file": str(XV.get("ABSENT-FILE", 0)),
        "header.cite_ambiguous": str(XV.get("AMBIGUOUS", 0)),
        "header.cite_unresolved_by_shape": str(XV.get("UNRESOLVED-BY-SHAPE", 0)),
        "header.headers_citing_upstream": str(len(with_cites)),
        "header.headers_behind_head": str(len(behind)),
        "header.headers_nowhere": str(len(nowhere)),
        "header.upstream_head": up.rev,
    }
    if rows_only or True:
        for k, v in rows.items():
            print(f"{k}={v}")
    if rows_out:
        head = ("rel\tat\tkind\tclaim\tverdict\twhy\tline\n")
        body = []
        for c in count_claims_all:
            body.append(f"{c['rel']}\t{c['at']}\tCOUNT\t{c['n']}\t{c['verdict']}\t{c['why']}\t"
                        f"{c['line']}\n")
        for c in cites_all:
            span = (f"{c['subject']}:{c['lo']}" if c["lo"] == c["hi"]
                    else f"{c['subject']}:{c['lo']}-{c['hi']}")
            body.append(f"{c['rel']}\t{c['at']}\tCITE\t{span}\t{c['verdict']}\t"
                        f"{c['why']}\t{c['line']}\n")
        Path(rows_out).write_text(head + "".join(body))
        print(f"ROWS       : {len(count_claims_all) + len(cites_all)} -> {rows_out}")

    if report_only:
        print("(REPORT: exit 0 by request; the numbers above are the census, not a verdict)")
        return PASS
    failed = []
    if stale_count:
        failed.append(f"{len(stale_count)} STALE line-count claims")
    if dang_cite:
        failed.append(f"{len(dang_cite)} DANGLING, ABSENT, or AMBIGUOUS citations")
    if failed:
        print(f"# header-census-gate: FAIL -- {'; '.join(failed)}")
        return FAIL
    print("# header-census-gate: PASS")
    return PASS


if __name__ == "__main__":
    print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
    raise SystemExit(main(sys.argv[1:]))
