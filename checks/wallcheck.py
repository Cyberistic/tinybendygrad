#!/usr/bin/env python3
"""wallcheck -- re-measure every wall in the ledger, in two trees, against its own anchor.

WALL/1: a wall names its prerequisite; when the prerequisite lands the wall is STALE, not
retired.  This file produces that number and nothing else.  It is read-only: it never writes the
ledger, and it never writes the truth file -- a truth file the instrument may write is not a
truth file.

  .venv/bin/python checks/wallcheck.py [ID ...]
    --ledger PATH  default .agents/slop/wallcheck/walls.tsv
    --truth PATH   default .agents/slop/wallcheck/walls.truth.tsv  (read-only, ever)
    --pin REV      the second tree. default HEAD
    --no-truth     grade without the hand-measured column
    --selftest     the five guard failures, reproduced on in-memory fixtures

Exit 0 all stands | 1 something moved | 2 ledger unreadable | 3 a row is a STORY
      4 selection matched nothing | 5 nothing was graded.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import warnings
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import IO

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ".agents/slop/wallcheck/walls.tsv"
TRUTH = ".agents/slop/wallcheck/walls.truth.tsv"

# Trees that hold COPIES of the source tree. A walk that entered one would count a claim as
# stated in N places when the N-th copy is a snapshot. PRUNED during the walk, not filtered after
# it -- `rglob` descends into `.git` and only then drops it, which is how a census of 14 rows
# turns into 14 full traversals of the object store.
EXCLUDED = (".git", "references", "runs", "oracles", "tinygrad", "test", "examples",
            ".agents/slop/differverdict", ".agents/slop/xd1", ".agents/slop/wallcheck",
            ".venv", "node_modules", "__pycache__")

# A claim is stated where a reader meets one: a file header, a note, a doc. One walk, one read per
# file, cached, then queried per row.
WALK_ROOTS = ("tinybendygrad", ".agents/slop", "docs", "checks", "gates", "AGENTS.md", "README.md")
SUFFIXES = {".bend", ".py", ".sh", ".md", ".tsv", ".txt", ".c", ".h", ".js", ".mjs", ".rs", ".toml"}
MAX_BYTES = 2_000_000

# POSIX classes are NESTED SETS to python's re: `[[:space:]]` compiles and matches a colon, an
# s, and the literal "pace". Anchors are authored in POSIX because they are greps a reader can
# paste into a shell, and are TRANSLATED here -- a second dialect in a second file is its own wall.
POSIX_CLASS = {"alpha": "a-zA-Z", "digit": "0-9", "alnum": "a-zA-Z0-9", "upper": "A-Z",
               "lower": "a-z", "space": r" \t\r\n\f\v", "blank": r" \t",
               "punct": r"!-/:-@\[-`{-~", "xdigit": "0-9A-Fa-f"}

# "this file says the thing cannot be done", for the redundancy census. Printed with its hits, so
# a reader can disagree with the classification without re-running anything.
ABSENCE_WORDS = (r"NOWHERE|absent|is missing|are missing|does not exist|no such|not implemented|"
                 r"cannot be|is blocked|is not implemented")


def posix2re(pat: str) -> str:
    for name, body in POSIX_CLASS.items():
        pat = pat.replace(f"[[:{name}:]]", f"[{body}]")
    return pat


def compile_posix(pat: str) -> re.Pattern:
    # re.M because a POSIX grep is line-based, so `^` there means LINE start. Without it `^def`
    # matches only at offset 0 and every line-anchored anchor in the ledger reads 0 forever --
    # the mirror of GUARD 1: not "matches too much", but "matches nothing".
    return re.compile(posix2re(pat), re.M)


def branches(pat: str) -> list[str]:
    """The alternatives of the FIRST top-level group. Empty when the anchor names exactly one
    thing, which is the state GUARD 5 wants."""
    i, depth, start = 0, 0, None
    while i < len(pat):
        c = pat[i]
        if c == "\\":
            i += 2
            continue
        if c == "(" and pat[i:i + 3] != "(?:":
            if depth == 0:
                start = i + 1
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return pat[start:i].split("|")
        i += 1
    return []


def sites(witness: str) -> int:
    """The site count the instrument just recorded, read back off its own witness line. Returns
    -1 for a witness that carries no count (a refusal), so a caller cannot mistake one for zero."""
    m = re.search(r"work=(\d+)", witness)
    return int(m.group(1)) if m else -1


def code_only(text: str) -> str:
    """`#` opens a comment in every file this ledger touches (.bend, .py, .sh). A defect's anchor
    is read in code position only, because W7's two CID hits are both comments and counting them
    would report a code site that does not exist."""
    return "\n".join(re.sub(r"#.*$", "", ln) for ln in text.splitlines())


SOURCE_TREE = frozenset(p.name for p in (ROOT / "tinybendygrad").iterdir())
COPY_SHAPE = 3  # three of the source tree's own top-level names is a copy, not a coincidence


def tree_copy(path: Path) -> bool:
    """A snapshot of the source tree, by SHAPE rather than by name: two units called them
    `differverdict` and `xd1` and named them in the brief, but `dd-cone-wt`, `strays`, `rf2root`,
    `rebase`, `shadowtrees` and `proof-close/MUTANT` hold copies too and nobody listed them.
    A walk that counts a claim in a snapshot is counting a copy. Derived from the live
    `tinybendygrad/` listing, so it cannot drift, and a PARTIAL copy counts: `strays/working`
    carries 7 of the source dirs and none of the top-level files, so a file-name test misses it."""
    try:
        names = {p.name for p in path.iterdir()}
    except OSError:
        return False
    return len(names & SOURCE_TREE) >= COPY_SHAPE


PRUNED_COPIES: list[str] = []


def walk(root: Path):
    """One pruned pass, yielding (path, relpath). `os.walk` is handed a PRUNED `dirs` list so the
    walk never descends into a tree copy or the object store -- filtering the RESULTS instead still
    pays for the whole traversal, and 14 rows x the whole tree is the difference between a census
    and a hang."""
    import os
    for top in WALK_ROOTS:
        base = root / top
        if base.is_file():
            yield base, top
            continue
        for dirpath, dirs, files in os.walk(base):
            rel = Path(dirpath).relative_to(root).as_posix()
            dirs[:] = [d for d in dirs if not _prune(Path(dirpath) / d, rel, d)]
            for name in sorted(files):
                p = Path(dirpath) / name
                if p.suffix in SUFFIXES and p.stat().st_size <= MAX_BYTES:
                    yield p, p.relative_to(root).as_posix()


def _prune(p: Path, rel: str, name: str) -> bool:
    if name in EXCLUDED or f"{rel}/{name}" in EXCLUDED:
        return True
    if tree_copy(p):
        PRUNED_COPIES.append(f"{rel}/{name}")
        return True
    return False


_CORPUS: list[tuple[str, list[str]]] | None = None


def corpus() -> list[tuple[str, list[str]]]:
    """One read per file, cached, split to LINES. The redundancy rule is per line: a file that
    mentions `CID` in a comment and `cannot be` three hundred lines later has not stated
    anything, and a per-FILE conjunction counted 109 such files for one three-letter key."""
    global _CORPUS
    if _CORPUS is None:
        _CORPUS = [(rel, p.read_text(errors="ignore").splitlines()) for p, rel in walk(ROOT)]
    return _CORPUS


class Pin:
    """The second tree, in ONE process. `git show` per row is one process per row and the
    coarseness probe re-reads, so a ledger sweep would fork ~100 times; `git cat-file --batch`
    forks once. BINARY, and read with an exact-read loop: TextIOWrapper.read(n) blocks for a
    DECODED n, which against a pipe of a fixed byte count hangs forever."""

    def __init__(self, rev: str):
        self.rev = rev
        self._p: subprocess.Popen[bytes] = subprocess.Popen(
            ["git", "cat-file", "--batch"], cwd=ROOT, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE)
        # Popen types its streams Optional even when asked for PIPE. One check, then narrow to
        # the type every method below needs, rather than an Optional threaded through the class.
        if self._p.stdin is None or self._p.stdout is None:
            raise RuntimeError("git cat-file --batch opened without pipes")
        self._in: IO[bytes] = self._p.stdin
        self._out: IO[bytes] = self._p.stdout
        self._cache: dict[str, str | None] = {}

    def _exact(self, n: int) -> bytes:
        buf = b""
        while len(buf) < n:
            chunk = self._out.read(n - len(buf))
            if not chunk:
                raise EOFError(f"git cat-file closed mid-object at {self.rev}")
            buf += chunk
        return buf

    def read(self, rel: str) -> str | None:
        if rel not in self._cache:
            self._in.write(f"{self.rev}:{rel}\n".encode())
            self._in.flush()
            head = self._out.readline().split()
            # `git cat-file --batch` answers `<sha> blob <n>` for a hit and `<rev>:<path> missing`
            # for a miss. Test the SIZE token rather than the token count: a miss is two tokens, but
            # so is any answer this has not seen, and reading `missing` as a size is a crash on
            # exactly the row whose scope is the one thing a grep cannot read.
            size = int(head[2]) if len(head) > 2 and head[2].isdigit() else None
            body = None
            if size is not None:
                self._exact(1)  # the trailing newline git appends to every batch object
                body = self._exact(size).decode("utf-8", "replace")
            self._cache[rel] = body
        return self._cache[rel]

    def close(self):
        self._in.close()
        self._p.wait()


FIELDS = "id pol scope pattern expect home refuted key date claim reopen".split()


@dataclass(frozen=True)
class Row:
    """One ledger row. A dataclass and not setattr in a loop: the ledger's eleven names are the
    contract between the file on disk and the code that grades it, and a typo in one of them
    should be a type error rather than an AttributeError three verdicts later."""

    id: str
    pol: str
    scope: str
    pattern: str
    expect: str
    home: str
    refuted: str
    key: str
    date: str
    claim: str
    reopen: str

    @property
    def missing(self) -> str:
        """WALL/1's absent field, named. Absent anchor = story, absent reopen = permanent veto,
        absent date = a diary; three different diseases that all read as `None` if collapsed."""
        for name, consequence in (("scope", "a story"), ("reopen", "a permanent veto"),
                                  ("date", "a diary")):
            if getattr(self, name) in ("", "-"):
                return f"no {name}: absent, this wall is {consequence}"
        return ""


def load(path: Path) -> list[Row]:
    rows = []
    for line in path.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split("\t")
        if len(f) != len(FIELDS):
            raise ValueError(f"{f[0]}: {len(f)} fields, want {len(FIELDS)}")
        rows.append(Row(*f))
    return rows


def readable(rel: str) -> bool:
    return bool(rel) and not rel.endswith(" emit") and (ROOT / rel).is_file()


class Checker:
    def __init__(self, pin: Pin):
        self.pin = pin
        self._work: dict[str, str | None] = {}

    def work(self, rel: str) -> str | None:
        if rel not in self._work:
            self._work[rel] = (ROOT / rel).read_text() if readable(rel) else None
        return self._work[rel]

    def count(self, rx: re.Pattern, r: Row, text: str | None) -> int:
        if text is None:
            return 0
        return len(rx.findall(code_only(text) if r.pol == "DEFECT/code" else text))


def grade(r: Row, ck: Checker, rx: re.Pattern) -> tuple[str, str]:
    """(verdict, witness). A RUN row, a scope neither tree can read, or a missing field is a
    REFUSAL, and a refusal is counted in the denominator and never folded into agreement."""
    if r.pol == "RUN":
        return "REFUSED/RUN", f"a re-run, not a symbol -- the check is: {r.reopen}"
    if r.missing:
        return "STORY", r.missing
    w, p = ck.work(r.scope), ck.pin.read(r.scope)
    if w is None or p is None:
        return "REFUSED/NO-SCOPE", (f"`{r.scope}` is not a readable file in the working copy OR at "
                                   f"{ck.pin.rev}. A scope readable in NEITHER tree is a REFUSAL, "
                                   f"never a verdict: under DEFECT polarity a silent "
                                   f"`[[ -r scope ]]` failure reads as GONE")
    nw, np_ = ck.count(rx, r, w), ck.count(rx, r, p)
    wit = f"work={nw} pin={np_} {r.scope}"
    if (nw > 0) != (np_ > 0):
        return "SPLIT", f"{wit} -- the trees disagree, so the answer is WAIT"
    n = nw
    if r.pol == "MISSING":
        return ("LANDED", wit) if n else ("STANDS", wit)
    if not n:
        return "GONE", wit
    if r.refuted not in ("", "-") and re.search(posix2re(r.refuted), w):
        return "GONE/ANNOTATED", (f"{wit} -- the claim is still on disk and THIS FILE now says it "
                                  f"is false (`{r.refuted}`); it stays, because a deleted wall is a "
                                  f"wall somebody re-derives")
    return "STANDS", wit


def coarseness(r: Row, ck: Checker, rx: re.Pattern) -> list[str]:
    """GUARD 5. `^def (i64_mul|i64_div|i64_mod|i64_shl)\\(` read work=4; a plant removing one of
    the four moved it to 3 and the verdict did not change. So DROP EACH ALTERNATIVE and re-ask.
    An anchor that cannot lose any of its parts cannot fail, and that is a defect of the ledger."""
    alts = branches(r.pattern)
    if len(alts) < 2:
        return []
    base = grade(r, ck, rx)[0]
    still = [a for a in alts
             if grade(r, ck, re.compile(posix2re(r.pattern.replace(r.pattern, a))))[0] == base]
    return still if len(still) == len(alts) else []


def reasked(home: str) -> bool:
    """WALL/1 field (b), audited where the wall's WORDS live -- not at the anchor, which is a
    different file and usually somebody else's."""
    try:
        return bool(re.search(r"^\s*#?\s*REOPEN\b", (ROOT / home).read_text(), re.M))
    except OSError:
        return False


def disposition(v: str, r: Row) -> str:
    """RETIRED / RE-DATED / KEPT -- the two acts WALL/1 forbids conflating. A void wall whose home
    was never re-measured is the one that gets forwarded as fact, so it is named."""
    if not v.startswith(("LANDED", "GONE")):
        return "KEPT"
    if r.home in ("", "-"):
        return "STALE/NO-HOME"
    return "RE-DATED" if reasked(r.home) else "STALE/UN-RE-ASKED"


# A key that matches more than this many files is a key that cannot discriminate, and a count it
# produces is a sentence length, not a redundancy census. Reported as such rather than printed.
KEY_MAX_PLACES = 12
# A wall wraps across lines, so the absence word may sit on the line below the subject.
WINDOW = 2


def states(text: list[str], key: re.Pattern, absent: re.Pattern) -> list[int]:
    """Line numbers where the subject and an absence word co-occur within WINDOW lines."""
    return [i for i, ln in enumerate(text)
            if key.search(ln) and any(absent.search(l) for l in text[max(0, i - WINDOW):i + WINDOW + 1])]


def redundancy(r: Row) -> tuple[int, list[str], bool]:
    """How many files STATE this claim and which do not carry its correction. A claim stated in
    three places gets corrected in two by accident, and the third is the copy a reader finds, so
    this count is the one that predicts which copy goes stale."""
    if r.key in ("", "-"):
        return 0, [], False
    key, absent = re.compile(posix2re(r.key)), re.compile(ABSENCE_WORDS)
    ref = re.compile(posix2re(r.refuted)) if r.refuted not in ("", "-") else None
    stated = {rel: states(text, key, absent) for rel, text in corpus()}
    places = [rel for rel, at in stated.items() if at]
    if not places:
        return 0, [], False
    corrected = {rel for rel in places
                 if ref and ref.search("\n".join(dict(corpus())[rel]))}
    return len(places), [p for p in places if p not in corrected], len(places) > KEY_MAX_PLACES


def report(rows, ck, truth, want, rev):
    # WALL/4: an agreement number against an unnamed tree is a number with no tree. Print the
    # resolved commit, because the tree moved under this rebuild once and every verdict held.
    sha = subprocess.run(["git", "rev-parse", "--short", rev], cwd=ROOT, capture_output=True,
                         text=True).stdout.strip() or "?"
    dirty = subprocess.run(["git", "status", "--porcelain", "--", "tinybendygrad", "checks"],
                           cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
    print(f"wallcheck  ledger={LEDGER}  pin={rev}={sha}  "
          f"{'truth=' + TRUTH if truth else 'no hand-measured column'}")
    if dirty:
        named = ", ".join(d.split()[-1] for d in dirty)
        print(f"WARNING: work and pin are NOT the same tree -- {len(dirty)} file(s) differ from "
              f"{sha}: {named}. SPLIT rows are then a fact about the repo, not a surprise.")
    print(f"walk roots {len(WALK_ROOTS)}, pruned: {', '.join(EXCLUDED)}")
    sel = [r for r in rows if r.id in want] if want else rows
    if want and not sel:
        print(f"\nNO ROW MATCHES {sorted(want)} -- REFUSED, not CLEAN: a guard over an empty "
              f"population has measured nothing.")
        return 4
    if not sel:
        print("\nLEDGER HAS NO ROWS -- REFUSED, not CLEAN.")
        return 5

    # GUARD 4. Assert every anchor COMPILES before a single row is graded with it: a checker that
    # raises on one row reports the other eighteen and calls the run a pass.
    rx_of, refused = {}, []
    for r in sel:
        if r.pol != "RUN":
            try:
                rx_of[r.id] = compile_posix(r.pattern)
            except re.error as e:
                refused.append((r, f"BAD-ANCHOR {e}"))
                rx_of[r.id] = None
        else:
            rx_of[r.id] = None

    print(f"\n{'id':5} {'verdict':16} {'disposition':18} {'reopen':7} {'n':>5} claim")
    graded, refused, coarse, mismatch = [], [], [], []
    for r in sel:
        rx = rx_of[r.id]
        if r.pol == "RUN":
            v, wit = grade(r, ck, rx)
        elif rx is None:
            v, wit = "REFUSED/BAD-ANCHOR", "the anchor does not compile; the ledger keeps POSIX " \
                                            "spelling, so this one is not a pattern"
        else:
            v, wit = grade(r, ck, rx)
            n = sites(wit)
            if r.expect not in ("", "-") and n != int(r.expect) and not v.startswith("REFUSED"):
                mismatch.append(f"{r.id}: work={n}, the claim asserts {r.expect}")
            if len(branches(r.pattern)) > 1 and coarseness(r, ck, rx):
                coarse.append(r.id)
        # One verdict, one list, one shape: a `Row, verdict, witness` triple. It was a 2-tuple in one
        # list and a 3-tuple in the other, which is how three separate unpack sites shipped as bugs.
        (refused if v.startswith("REFUSED") else graded).append((r, v, wit))
        n = sites(wit)
        print(f"{r.id:5} {v:16} {disposition(v, r):18} {'yes' if reasked(r.home) else '-':7} "
              f"{n if n >= 0 else '-':>5} {r.claim[:58]}")

    print("\nwitness / how")
    for r, v, wit in graded + refused:
        print(f"  {r.id:5} {v:20} {wit}")

    print("\nREDUNDANCY -- files that STATE the claim on one line, and which lack its correction")
    print(f"  (a wall WRAPS, so the absence word may sit {WINDOW} lines off the subject)")
    if PRUNED_COPIES:
        print(f"  tree copies pruned BY SHAPE, not by name: {', '.join(sorted(PRUNED_COPIES))}")
    for r, _, _ in graded:
        if r.key in ("", "-"):
            continue
        n, stale, broad = redundancy(r)
        if not n:
            continue
        flag = f"  KEY-TOO-BROAD (> {KEY_MAX_PLACES} files: this count is a sentence length)" if broad else ""
        print(f"  {r.id:5} places={n} uncorrected={len(stale)}  {', '.join(stale[:5])}{flag}")
        if stale and not broad:
            print(f"        -> stated in {n} place(s), corrected in {n - len(stale)}; the "
                  f"uncorrected copy is the one nobody owns")

    print(f"\n--- {len(sel)} row(s) selected -> {len(graded)} GRADED, {len(refused)} REFUSED "
          f"({' '.join(r.id for r, _, _ in refused) or 'none'})")
    c = Counter(v.split("/")[0] for _, v, _ in graded)
    print("outcomes: " + " ".join(f"{k}={v}" for k, v in sorted(c.items())))
    void = [r.id for r, v, _ in graded if v.startswith(("LANDED", "GONE"))]
    kept = [r.id for r, v, _ in graded if not v.startswith(("LANDED", "GONE"))]
    unasked = [r.id for r, v, _ in graded if disposition(v, r) == "STALE/UN-RE-ASKED"]
    print(f"RETIRED-or-GONE {len(void)}: {' '.join(void)}")
    print(f"KEPT, wall still true {len(kept)}: {' '.join(kept)}")
    print(f"NOT RE-ASKED, the forwarding hazard {len(unasked)}: {' '.join(unasked) or 'none'}")
    if coarse:
        print(f"COARSE ANCHOR, dropping an alternative cannot move the verdict: {sorted(set(coarse))}")
    if mismatch:
        print("COUNT MISMATCH, the claim asserts a number the tree no longer has:")
        for m in mismatch:
            print("  " + m)

    if truth:
        agree = dis = 0
        got = {r.id: v for r, v, _ in graded}
        said = {r.id for r, _, _ in refused}
        for r, v, _ in graded:
            t = truth.get(r.id)
            if t is None:
                continue
            if t == v:
                agree += 1
            else:
                dis += 1
                print(f"  {r.id} instrument={v} hand={t}  <-- DISAGREES")
        for rid, t in sorted(truth.items()):
            if rid in got or rid == "id":
                continue
            why = "REFUSED, and a refusal is not agreement" if rid in said else "NOT IN THE LEDGER"
            print(f"  {rid} hand={t}  <-- {why}")
        print(f"agreement {agree}/{agree + dis}   ERROR RATE {dis}/{agree + dis}   "
              f"(self-consistency: ONE labeller wrote both, so this cannot catch an anchor and its "
              f"truth wrong in the SAME way)")
    # The exit contract in RULE.md, which an instrument that always exits 0 does not honour:
    # 1 something MOVED, 3 a row is a STORY. A refusal is not a pass and not a failure.
    story = [r.id for r, v, _ in graded if v == "STORY"]
    moved = [r.id for r, v, _ in graded if v.startswith(("LANDED", "GONE", "SPLIT"))]
    if story:
        return 3
    if not graded:
        # everything was refused. That is neither a pass nor a failure, and it is emphatically
        # not CLEAN: nothing was measured, so it must not read as the wall standing.
        print("\nNOTHING WAS GRADED: every row was refused. That is not a clean tree.")
        return 5
    return 1 if moved else 0


def selftest() -> int:
    """Reproduce each of the five failures the last instrument died of. In-memory fixtures; no file
    in the tree is touched, and each fixture is the shape that actually shipped the bug."""
    bad = []
    # 1. v1 had no file, so the anchor was the tree and every wall matched its own prose.
    prose = "W1a: i64_mul is absent - NOWHERE. Not helpers.bend, not dtype.bend."
    hit = [p for p in ("i64_mul", "NOWHERE", "helpers.bend") if re.search(p, prose)]
    if len(hit) != 3:
        bad.append(f"G1 expected 3/3 tree-anchor matches, got {len(hit)}")
    print("G1 tree anchor: {len(hit)}/3 patterns match the wall's own sentence -> PRESENT for "
          "every wall, hit rate 100%, information 0.  guard: the scope is ONE file.")

    # 2. v2 graded the working copy only, so a capability at HEAD read STANDS.
    work, pined = "def i64_mul(a):\n", ""
    w_only = bool(re.search("i64_mul", work)) and not re.search("i64_mul", pined)
    if not w_only:
        bad.append("G2 fixture is not a work-only divergence")
    print("G2 work-only read: work=1 pin=0 -> STANDS, which is half a truth.  guard: grade both "
          "trees and answer SPLIT when they disagree.")

    # 3. `runtime/dtype.c emit` is not a path; `[[ -r scope ]]` failing silently made it GONE.
    if readable("tinybendygrad/runtime/dtype.c emit"):
        bad.append("G3 fixture resolved, so the guard is not testing anything")
    print("G3 non-path scope: readable=False in the working copy; a silent `[[ -r ]]` failure "
          "reads as GONE under DEFECT polarity.  guard: NEITHER tree readable => REFUSED/NO-SCOPE.")

    # 4. A POSIX class is not a python class. `[[:space:]]` COMPILES -- no error, so a pre-flight
    #    assert on "does it compile" alone does not catch it -- and matches a COLON and nothing
    #    else, not a space. So the row's count is pinned at 0 forever and its verdict never moves.
    with warnings.catch_warnings():  # the FutureWarning is part of the evidence, not noise
        warnings.simplefilter("ignore", FutureWarning)
        raw = re.compile("[[:space:]]")
    spaced = "a b:c"
    if raw.search(" "):
        bad.append("G4 fixture changed: [[:space:]] now matches a space, python changed under us")
    if not compile_posix("[[:space:]]").search(" "):
        bad.append("G4 translation no longer matches a space")
    if raw.findall(spaced) == [" "]:
        bad.append("G4 fixture is no longer the nested-set misparse")
    try:
        re.compile("(unclosed")
    except re.error:
        pass
    else:
        bad.append("G4 a genuinely broken anchor compiled, so the pre-flight assert is not testing")
    print(f"G4 `[[:space:]]` compiles (so 'does it compile' is NOT the guard) and matches "
          f"{raw.findall(spaced)!r}, not the space.  guard: translate the POSIX class, then assert "
          f"EVERY anchor compiles before a single row is graded with it.")

    # 5. a four-way anchor: dropping one alternative changed the count and not the verdict.
    four = "def i64_mul(\ndef i64_div(\ndef i64_mod(\ndef i64_shl("
    all_four = compile_posix("^def (i64_mul|i64_div|i64_mod|i64_shl)\\(")
    just_mul = compile_posix("^def i64_mul\\(")
    dropped = {a: len(compile_posix("^def (%s)\\(" % a).findall(four)) for a in branches(
        "^(i64_mul|i64_div|i64_mod|i64_shl)\\(")}
    if len(all_four.findall(four)) != 4 or len(just_mul.findall(four)) != 1 or set(dropped) != {
            "i64_mul", "i64_div", "i64_mod", "i64_shl"} or any(n != 1 for n in dropped.values()):
        bad.append(f"G5 fixture is not the shipped one: {dropped}")
    arity1 = branches(r"^def i64_mul\(")
    print("G5 coarse anchor: work=4 -> drop one alternative -> work=1 of the 4, verdict LANDED "
          "either way, so the plant cannot be seen.  guard: re-ask per alternative; an arity-1 "
          f"anchor returns {arity1} and is exempt -- it has nothing to drop.")
    print(f"\nselftest: {len(bad)} fixture assertion(s) failed")
    for b in bad:
        print("  " + b)
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="wall ids; zero selects every row, never `CLEAN`")
    ap.add_argument("--ledger", default=LEDGER)
    ap.add_argument("--truth", default=TRUTH)
    ap.add_argument("--pin", default="HEAD")
    ap.add_argument("--no-truth", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    lp = Path(a.ledger) if Path(a.ledger).is_absolute() else ROOT / a.ledger
    if not lp.is_file():
        print(f"LEDGER UNREADABLE: {lp} does not exist. A missing ledger is exit 2, never CLEAN.")
        return 2
    tp = Path(a.truth) if Path(a.truth).is_absolute() else ROOT / a.truth
    truth = {}
    if not a.no_truth and tp.is_file():
        truth = {f.split("\t")[0]: f.split("\t")[1] for f in tp.read_text().splitlines()
                 if not f.startswith("#") and "\t" in f}
    pin = Pin(a.pin)
    try:
        try:
            rows = load(lp)
        except ValueError as e:
            print(f"LEDGER MALFORMED: {e}")
            return 2
        rc = report(rows, Checker(pin), truth, set(a.ids), a.pin)
    finally:
        pin.close()
    return rc


# THE VERDICT SURFACE, DECLARED. `gates/gate-surface.py` reads these by AST -- never by import,
# because import RUNS a gate -- and EXECUTES each plant, requiring the observed rc to be the
# declared one. A declared verdict with no plant is RED, named.
VERDICTS = {0: "PASS", 1: "FAIL", 2: "USAGE", 3: "REFUSED", 4: "NO-ROW", 5: "DEAD"}
PLANTS = {0: ["--selftest"], 4: ["NO-SUCH-ID"]}


if __name__ == "__main__":
    sys.exit(main())
