#!/usr/bin/env python3
"""citations-census-gate.py -- every `file:line` the tree says about itself, MEASURED.

    .venv/bin/python gates/citations-census-gate.py
    .venv/bin/python gates/citations-census-gate.py --selftest
    .venv/bin/python gates/citations-census-gate.py --rows OUT.rows

ZERO `bend` LANES, ZERO rows of its own. The subject is PROSE, and `gates/devtag-gate.py`
already recorded the asymmetry that puts this file here: a citation of an upstream symbol is
not code, it is prose in a `#` line, so a comment stripper makes every citation in the tree
vanish while reporting rc=0 PASS.

TWO LANES, AND THEY HAVE DIFFERENT DENOMINATORS BECAUSE THEY ARE DIFFERENT QUESTIONS.

  R  REGRESSION.  A commit that inserted lines moved every citation past the insertion
                  point. `git` knows the before and the after, so for ONE NAMED COMMIT the
                  drift is EXACTLY DECIDABLE -- no estimate, no "the line moved", a byte
                  comparison of `b86e3c25e^:<f>` against `HEAD:<f>` at the cited index.
                  This is the only lane where COSMETIC / STALE / FALSIFIED / DANGLING are
                  four DIFFERENT answers rather than four names for one.
  X  RESOLUTION.  The whole tree, right now: does the cited file exist, does the cited line
                  exist in it, and does it still carry the text the claiming line puts
                  beside the citation. Nothing here needs a commit -- and nothing here can
                  prove a line NEVER MOVED, so its COSMETIC is a LOWER BOUND and says so in
                  the summary rather than letting the word imply a measurement it lacks.

THE POPULATION IS DISCOVERED TWICE AND THE TWO ARE DIFFERED. `os.walk` over the repo (R)
and `git ls-tree -r HEAD` (T). An instrument that reports one and never notices the other is
`checks/cites-census.py`'s own stated fault with the import removed, so this one prints both,
prints how many paths each has that the other lacks, and extracts from the WALK -- because
`.agents/slop/` holds 5,166 files git does not have and `runs/` holds files that are neither.

`references/` IS EXCLUDED AND SAYS SO IN ITS OWN LINE. It is `.gitignore`d, it holds 1,714
third-party `.bend` files, and a citation into someone else's fork is not this tree asserting
anything about itself. The count of what was dropped is printed, because an exclusion that
cannot be seen is an exclusion that cannot be checked.

`.agents/` IS INCLUDED, AND THAT IS A DECISION WITH A REASON. It holds the governing
document, `AGENTS.md`, which is this tree's largest single source of `file:line` claims --
so an instrument that excluded it could not see the defect class it exists for, which is the
`checks/sweep.py` `LIVE_UNITS` shape one level up. It is reported as its own STRATUM so a
reader can subtract it. `.agents/slop/` holds previous instruments' own censuses, whose rows
ARE citations about citations; those rows are real citations and are counted, and the
CITATION-OF-A-CITATION count is printed rather than left for a reader to discover.

WHY `checks/cites-census.py` IS IMPORTED AND NOT COPIED. Its `quoted_spans` and its
`_is_connector` are the two pieces of this extractor's precision work and they were each
bought with a measured fault -- paired delimiters instead of matched ones, and a predicate
that belongs to its path only if nothing but a connector separates them. A second copy in
`gates/` would be `checks/sweep.py`'s `LIVE_UNITS` all over again. So the import IS the
reuse, and when it fails this gate answers REFUSED (3) rather than silently running a weaker
matcher of its own.

EXIT STATUS, `gates/gatekit.py`'s five: 0 PASS · 1 FAIL · 3 REFUSED (`checks/cites-census.py`
absent, or no `bend`-free tree to walk) · 5 DEAD (the walk found no text to read, or the
regression lane found no cited file at all).

WHAT A FAIL HERE MEANS. Every DANGLING row is a finding and a finding is a FAIL, because
`AGENTS.md` records DANGLING as the class that LOOKS FINE. The gate is red on this tree and
stays red until somebody strikes the rows; `--report` prints the census and exits 0 without
claiming a verdict, and the two are separate arguments on purpose.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# THE FILE IS `cites-census.py` AND THE MODULE WOULD BE `cites_census`, so a plain
# `import cites_census` cannot find it: MEASURED, it answers `ModuleNotFoundError` even with
# `checks/` on `sys.path`, because the hyphen is in the FILE name. So the load is by PATH --
# which is also the shape the population rule asks for, a generator loaded from its own
# location rather than by a name someone remembered. And there is NO fallback copy: a
# `try/except ImportError` that quietly ran a private matcher is exactly the second copy this
# gate refuses to carry, so the failure is a REFUSED.
try:
    import importlib.util as _ilu
    _spec = _ilu.spec_from_file_location("cites_census", ROOT / "checks" / "cites-census.py")
    CC = _ilu.module_from_spec(_spec)
    _spec.loader.exec_module(CC)
except Exception as _exc:  # noqa: BLE001 -- the name is the evidence
    print(f"== REFUSED, NOT A VERDICT: checks/cites-census.py will not load ({_exc!r}); "
          f"this gate refuses rather than run a matcher that is a second copy of it")
    sys.exit(REFUSED)

# --------------------------------------------------------------------------- populations

# EVERY ENTRY TALLIES ITSELF.  `checks/cites-census.py`'s header and this tree's own history
# agree on the moral: a rule that drops rows and does not say how many is indistinguishable
# from a rule that never matched them.
EXCLUDED_DIRS = {
    ".git": "git's own object store",
    ".jj": "jj's operation log (colocated, binary)",
    ".venv": "the 3.12 interpreter that owns the editable tinygrad",
    "__pycache__": "compiled python",
    "node_modules": "not present; listed so the count is 0 and says so",
    "references": "gitignored; 1,714 third-party .bend files, not this tree's claims",
    # *** `.agents/slop/` IS A POPULATION OF INSTRUMENTS THAT ALREADY CENSUSED CITATIONS, AND
    # ITS ROWS ARE NOT CLAIMS THE TREE MAKES. ***  MEASURED: nine files there hold ~31,400
    # rows each -- `residual/cites-before.rows`, `cheapguards/{G1,G2,FINAL,BEFORE}.rows`,
    # `textguard/{BEFORE,AFTER}.rows`, `failaudit/fa.rows`, `unreadable/cites.rows`,
    # `precision/claims.rows`, `dangle/cites.rows` -- and together they are 452,070 of this
    # census's 467,482 rows, 96.7%.  Every one of those rows is a `file:line`, so they are
    # real citations of real files; what they are NOT is PRESENT-TENSE ASSERTIONS.  They are
    # RECORDS: a row written by an instrument at a moment when the tree was in a state that no
    # longer exists, which is the `runs/` shape and the `gates/artifacts/` shape.  Counting
    # them makes the denominator a measurement of previous instruments' output, and it is
    # EXACTLY the `realize.bend:881` citation-of-a-citation the briefing names -- except that
    # this is not one, it is 452,070 of them.  They are therefore excluded FROM THE HEADLINE
    # and COUNTED, and `.agents/*.md` -- the governing documents, AGENTS.md among them -- is
    # KEPT, because a document's claim is present tense by construction.
    ".agents/slop": "other units' instrument OUTPUT: 452,070 of this census's rows are "
                    "earlier censuses' own tables, i.e. records, not claims",
}
# `.ruff_cache` is a CACHE, and `gates/artifacts/` is gate OUTPUT; both are named rather
# than folded into a prefix rule so the tally has a reason attached to each row.
EXCLUDED_PREFIXES = {
    ".ruff_cache/": "ruff's cache, rewritten on every run",
    "gates/artifacts/": "gitignored gate OUTPUT -- AGENTS.md: `rm -rf gates/artifacts` is live",
    # *** THIS GATE'S OWN FINDINGS FILE IS ITS OWN OUTPUT, AND MEASURED IT IS NOT A SMALL
    # SELF-REFERENCE. ***  Every row of `gates/citations-census-findings.rows` holds a
    # `subject:N`, so the first version of this file -- 394 rows -- made the NEXT run's
    # headline 628, i.e. **+234 claims that are this instrument reporting its own findings**,
    # which is the `realize.bend:881` citation-of-a-citation shape at 234x.  It is excluded
    # for the same reason and with the same rule as `gates/artifacts/`: a gate's OUTPUT is not
    # a claim, and it is tallied below rather than quietly skipped.  `checks/census.json` and
    # `oracles/*.rows` are in the same position and are NOT excluded -- they are another unit's
    # instruments and removing them from this one is a decision this gate does not get to make
    # silently -- so the strata table prints what each of them carries.
    "gates/citations-census-findings.rows": "this gate's own findings table: every row is a "
                                            "`subject:N`, so keeping it IN the walk added 234 "
                                            "claims of this instrument quoting itself",
}
# A FILE larger than this is not censused and the count is printed.  It is a size rule and it
# is the only kind of rule in this file that can lose a TRUE row, so it is reported, not hidden.
MAX_BYTES = 8 * 1024 * 1024


def walk() -> tuple[list[str], Counter, int, int]:
    """(paths, exclusion tally, bytes decoded, files skipped for size). A DIRECTORY WALK."""
    tally: Counter = Counter()
    out: list[str] = []
    nbytes = nbig = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT)
        rel_dir = "" if rel_dir == "." else rel_dir.replace(os.sep, "/") + "/"
        pruned = [d for d in dirnames if d in EXCLUDED_DIRS or (rel_dir + d + "/") in EXCLUDED_PREFIXES]
        for d in pruned:
            why = EXCLUDED_DIRS.get(d) or EXCLUDED_PREFIXES.get(rel_dir + d + "/", "a prefix rule")
            tally[f"prune {d}/ -- {why}"] += sum(
                1 for _dp, _dn, fns in os.walk(os.path.join(dirpath, d)) for _ in fns)
        dirnames[:] = [d for d in dirnames if d not in pruned]
        for fn in filenames:
            rel = (rel_dir + fn).replace(os.sep, "/")
            hit = next((q for q in EXCLUDED_PREFIXES if rel.startswith(q)), None)
            if hit is not None:
                tally[f"skip {hit}* -- {EXCLUDED_PREFIXES[hit]}"] += 1
                continue
            out.append(rel)
    for rel in out:
        try:
            size = (ROOT / rel).stat().st_size
        except OSError:
            tally["vanished between walk and stat"] += 1
            continue
        if size > MAX_BYTES:
            nbig += 1
            continue
        nbytes += size
    return sorted(out), tally, nbytes, nbig


def tracked() -> list[str]:
    """`git ls-tree -r HEAD` -- git's OWN declaration of the tree.  NOT `git ls-files`, which
    reads the INDEX, and this repo arms that index with intent-to-add placeholders by design
    (`jj git colocation`); AGENTS.md measured 882 such placeholders and 7.9 MB across 149
    directories on this tree."""
    r = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"== REFUSED, NOT A VERDICT: git ls-tree rc={r.returncode}: {r.stderr.strip()}")
        sys.exit(REFUSED)
    return sorted(p for p in r.stdout.splitlines() if p)


# --------------------------------------------------------------------------- the extractor

# ONE PASS.  The first revision of this file used `re.search(r"[...]+$", text, 0, m.start())`
# to walk BACK from every `:N` to the start of the path, and the anchored `$` over a growing
# prefix made it quadratic: it ran 15 minutes over 205 MiB and printed nothing. An instrument
# that has to be believed at 189 rows cannot cost fifteen minutes.
RUN = re.compile(r"[A-Za-z0-9_.^~+/-]+")
LOC = re.compile(r":(\d+)(?:-(\d+))?(?![\w])")
# `ad117c928^:tinygrad/uop/ops.py:1398` NAMES A BLOB.  `:` is not in RUN's class, so the rev
# lands in its own run and is dropped for having no dot -- which is why the rev has to be
# recovered by looking LEFT of the surviving run.
REV = re.compile(r"([0-9a-f]{7,40}\^?):\s*$")

# ONE KEY TUPLE FOR THE WHOLE FILE.  MEASURED: the harness zipped `extract`'s nine-element row
# against a hand-written key tuple, and when a field was INSERTED rather than appended the two
# silently slid -- `rev` picked up the `neighbourhood` bool, every plant answered BLOB-GONE,
# and the instrument reported a FAIL that looked like a judgement. A second spelling of the
# same tuple is a second contract with no generator, which is the class this gate is measuring.
FIELDS = ("at", "subject", "loc", "lo", "hi", "needle", "rev", "neighbourhood",
          "line_text", "tail")

# A RANGE CITATION IS REGRESSED IF ANY LINE IN IT IS.  `tinybendygrad/uop/render.bend:347`'s
# `ops.bend:865-881` starts BELOW the insertion point and reaches past it, and an extractor
# that reads only the FIRST number of a range reports the second one resolved.  MEASURED on the
# live tree: nine range citations straddle their target's boundary and exactly one reaches past
# it -- and it is a TRUE citation today, so the straddle rule adds a row, never loses one.
#
# *** A REVERSED RANGE IS A DEFECT IN THE CITATION, AND IT IS TALLIED RATHER THAN GUESSED. ***
# `tinybendygrad/uop/validate.bend:2503` writes `ops.bend:7044-7012` -- an end before a start.
# `range(lo, hi+1)` over the raw pair is EMPTY, so an unnormalised extractor silently reports
# it as resolved, which is the `[^/]*`-matched-empty moral in a new costume: a token that
# matches nothing writes NO row, and no row does not argue back.  MEASURED, this ONE row is
# the difference between 190 and 189 in the census `b86e3c25e` reports, so it is worth naming
# rather than absorbing: the pair is normalised, the row is counted, and REVERSED tallies it.
REVERSED = Counter()


def loc_range(g: re.Match) -> tuple[int, int]:
    a = int(g.group(1))
    b = int(g.group(2)) if g.group(2) else a
    if b < a:
        REVERSED[g.group(0)] += 1
        a, b = b, a
    return a, b


def _needle(line: str, end: int, spans: list[tuple[int, int, str]]) -> str | None:
    """The quoted span a position citation is claiming ABOUT, or None.

    `checks/cites-census.py` owns the rule and this calls it: a predicate belongs to its path
    only if nothing but a connector separates them, and the delimiters PAIR rather than match
    (a backtick in markdown is a toggle). Re-implemented here it would be a second copy.
    `spans` is passed in rather than recomputed because the first live run called
    `quoted_spans` per citation over the whole file and never finished in 900 s."""
    for a, _b, span in spans:
        if a < end or len(line[end:a]) > 24 or not CC._is_connector(line[end:a]):
            continue
        t = span.strip("*\u2026 ")
        if len(t) >= 4 and "/" not in t:
            # *** A POSSESSIVE IS A CLAIM ABOUT THE NEIGHBOURHOOD, NOT AN OCCURRENCE. ***
            # MEASURED: `.agents/TODO.md:2800` reads "This is `reduce.py:45`'s `mo_downcast`
            # neighbourhood", and `grep -c mo_downcast tinygrad/mixin/reduce.py` answers **0**
            # over 138 lines -- correctly, because the name was RENAMED and TODO.md is a
            # changelog whose subjects are FORMER names. Answering FALSIFIED there would put
            # the census's strongest word on a true sentence about a deletion, so the
            # possessive is its own class and is COUNTED rather than guessed either way.
            gap = line[end:a].rstrip(" `")
            return t, gap.endswith(("'s", "\u2019s"))
    return None, False


def extract(text: str) -> list[tuple]:
    """`(line, subject, loc, lo, hi, needle, rev, line, tail)` for every citation.

    `rev` is the blob the citation names, or None.  A blob citation is the ONE shape whose
    drift is decidable with no commit at all: the reader can be handed the bytes.

    FOUR DEFECTS THIS FUNCTION HAD, ALL FOUND BY THE PLANTS AND ALL FIXED HERE, because a
    plant that only tests `judge` cannot see a defect in the extractor:

      `./ops.bend:868`  -- `.` IS IN `RUN`'s CLASS, so the run came out as `./ops.bend` and
        `resolve()` found no file called that. The leading `./` is stripped here, at the one
        place that can see it.
      THE NEEDLE WAS TAKEN FROM `m.end()`, WHICH IS BEFORE THE `:N`.  So the first quoted
        span of `` `subj.bend:2` -- `beta` `` was the citation ITSELF, and every plant came
        back EXISTENCE-ONLY. It is `g.end()`.
      *** `quoted_spans` WAS RUN OVER THE WHOLE FILE, ONCE PER CITATION. ***  That is
      quadratic in the file and it is what made the first live run of this gate exceed
        FIFTEEN MINUTES over 205 MiB and print nothing. It is computed ONCE PER LINE, which
        is where a predicate can live at all: a needle is a thing on ONE LINE.
      `head.count("\n")` PER MATCH was quadratic for the same reason; the line index comes
        from the same per-line loop.

    AND A TIMING THAT IS NOT A VERDICT: MEASURED, the first live run was killed by the
    harness at 900 s having printed NOTHING, and the only visible symptom was a timeout. An
    instrument that measures nothing and takes a quarter of an hour to say so is a DEAD
    instrument that reads as a slow one, so the line-at-a-time shape above is a correctness
    fix as much as a speed one."""
    rows = []
    for line_no, line in enumerate(text.split("\n"), 1):
        # ONE `quoted_spans` PER LINE, and the spans are line-relative so the gap test below
        # measures a gap on the line the reader is looking at.
        spans = CC.quoted_spans(line)
        if not spans:
            spans = []
        for m in RUN.finditer(line):
            run = m.group()
            i = run.rfind("/")
            name = run[i + 1:]
            # A CITATION NAMES A FILE.  `12:30:45` yields the runs `12`, `30`, `45`, and `30`
            # is followed by `:45` -- so without this test a CLOCK is a citation of a file
            # called `30`.  The rule is a dot in the FILENAME part, not a list of extensions:
            # a suffix set is exactly `checks/repro-paths.py`'s remembered-extension defect,
            # which stopped at `.pyc` and read it as `.py` and wrote a dangling row for a name
            # that never existed.
            if "." not in name or name.startswith(".") or not name[0].isalnum():
                continue
            g = LOC.match(line, m.end())
            if not g:
                continue
            rv = REV.search(line[:m.start()])
            lo, hi = loc_range(g)
            # `./x` AND `x/` are two SPELLINGS of one path and the universe is keyed by
            # neither. Stripped here, at the one place that can see it.
            while run.startswith("./"):
                run = run[2:]
            needle, near = _needle(line, g.end(), spans)
            rows.append((line_no, run, g.group(0)[1:], lo, hi, needle,
                         rv.group(1) if rv else None, near, line, line[g.end():]))
    return rows


# --------------------------------------------------------------------------- the resolver

class Universe:
    """Every path the walk and git both know, indexed the three ways a citation can spell one.

    A BASENAME IS NOT A PATH and `ops.bend:864` is not a path -- MEASURED, there is exactly
    ONE `ops.bend` outside `references/`, so the bare spelling resolves here. It is admitted
    ONLY because the index is built from the walk and the uniqueness is checked per citation:
    two `ops.py` in a tree makes every bare `ops.py:N` AMBIGUOUS, reported and unresolved,
    never silently resolved to the first hit.  `checks/cites-census.py`'s `read()` says the
    same thing for the same reason."""

    def __init__(self, paths: list[str], tracked_paths: list[str]):
        self.all = set(paths) | set(tracked_paths)
        self.on_disk = set(paths)
        self.suffix: dict[str, list[str]] = defaultdict(list)
        self.base: dict[str, list[str]] = defaultdict(list)
        self.exts: set[str] = set()
        for p in self.all:
            self.exts.add(p.rsplit(".", 1)[-1] if "." in os.path.basename(p) else "")
            j = p.find("/")
            while j != -1:
                self.suffix[p[j:]].append(p)
                j = p.find("/", j + 1)
            self.base[os.path.basename(p)].append(p)

    def resolve(self, subject: str, rev: str | None) -> tuple[str | None, str]:
        if rev:
            return subject, f"blob:{rev}"
        if subject in self.on_disk:
            return subject, "exact"
        hits = [p for p in self.suffix.get("/" + subject, ()) if p in self.on_disk]
        if len(hits) == 1:
            return hits[0], "suffix"
        # *** A SUFFIX THAT MATCHED SEVERAL PATHS IS AMBIGUOUS, NOT ABSENT. ***  MEASURED: the
        # first cut fell through to the basename index and returned `absent` for
        # `uop/fold.bend`, which EXISTS at `tinybendygrad/uop/fold.bend` (402,187 bytes) and is
        # ALSO at `.agents/slop/strays/{origin,working}/tinybendygrad/uop/fold.bend`.  Three
        # real files end in `/uop/fold.bend`, so the honest answer is a refusal -- and the
        # dishonest one was the strongest word in the vocabulary, on a file that is right
        # there. 20 of the 184 headline DANGLING-FILE rows were this bug and nothing else.
        if len(hits) > 1:
            return None, f"ambiguous:{len(hits)}"
        hits = self.base.get(subject, [])
        if len(hits) == 1:
            return hits[0], "unique-basename"
        if len(hits) > 1:
            return None, f"ambiguous:{len(hits)}"
        return None, "absent"


def read_text(path: Path) -> str | None:
    try:
        raw = path.read_bytes()
    except OSError:
        return None
    if b"\0" in raw[:8192]:
        return None
    return raw.decode("utf-8", "replace")


def read_blob(rev: str, subject: str) -> str | None:
    r = subprocess.run(["git", "show", f"{rev}:{subject}"], cwd=ROOT,
                       capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


# --------------------------------------------------------------------------- lane R

REGRESSOR = "b86e3c25e"  # the four `Device.tag` citations; the named instrument of the drift


def regressor_paths() -> set[str]:
    """The files the regressor TOUCHED, asked of git.  DISCOVERED, NOT NAMED.

    A four-element tuple of paths would be a hand list -- the `checks/sweep.py` `LIVE_UNITS`
    shape -- and it would go stale the moment a fifth file moved. `git diff --name-only`
    between the regressor and its parent IS the generator's own declaration, and it is one
    subprocess for the whole lane instead of two `git show` per RESOLVED PATH, which is what
    the first live run did: MEASURED, that version spent its time shelling out to `git show`
    for thousands of paths that were never regressed at all."""
    r = subprocess.run(["git", "diff", "--name-only", REGRESSOR + "^", REGRESSOR],
                       cwd=ROOT, capture_output=True, text=True)
    return set(r.stdout.split()) if r.returncode == 0 else set()


def regressed_lines(subject: str, touched: set[str]) -> set[int]:
    """OLD 1-BASED line indices of `subject` whose TEXT differs between the regressor's
    parent and HEAD.  DERIVED FROM THE BLOB PAIR, NEVER FROM A LINE DELTA.

    *** A NET DELTA IS NOT A REGRESSION BOUNDARY. ***  `b86e3c25e`'s message records
    `optim.bend` as `+0` and from the delta that is true -- the file is 1,426 lines before
    and 1,426 after. MEASURED HERE: old line 1,407 is the ONE line the commit rewrote
    (`@@ -1407 +1407 @@`), so a citation to `optim.bend:1407` points at text that no longer
    exists while the line count never moves. A boundary read off a diff's `+N` would have
    called that file clean.  The same derivation moves the other boundaries DOWN to the
    first REPLACED line rather than the first INSERTED one -- MEASURED, 880 not 883 in
    `realize.bend`, 190 not 196 in `memory.bend`, 865 not 868 in `ops.bend` -- so it is also
    a strictly LARGER population than the threshold the delta implies."""
    if subject not in touched:
        return set()
    pre = read_blob(REGRESSOR + "^", subject)
    post = read_text(ROOT / subject)
    if pre is None or post is None:
        return set()
    return regressed_indices(pre.splitlines(), post.splitlines())


def regressed_indices(a: list[str], b: list[str]) -> set[int]:
    """The PURE HALF, and the only half a plant is allowed to drive.

    *** THE FIRST VERSION OF THIS BOUNDARY PLANT ASSERTED A PROPERTY OF THE LIVE TREE. ***
    `regressed_lines("tinybendygrad/nn/optim.bend", ...)` returned 1 and the plant said 1, and
    after this gate was COMMITTED the same call returned 349 -- because another unit had moved
    `nn/optim.bend` since `b86e3c25e`, and the plant was asserting a property of a PAST tree
    state.  That is this commit's own defect class, produced by its own harness: a claim about
    a file that stopped being true while nobody lied, which `AGENTS.md` calls stale prose and
    which this file exists to count.  The fix is not a better expectation, it is that the
    boundary is a PURE function of two line lists and the plant drives THAT with literals."""
    return {i for i in range(1, len(a) + 1) if i > len(b) or a[i - 1] != b[i - 1]}


# --------------------------------------------------------------------------- the census

# LANE R's vocabulary and LANE X's are DISJOINT ON PURPOSE.  R can say STALE because a diff
# adjudicates it; X cannot, so X says OFF-LINE.  See the two measured comments at the two
# branch points that decide this.
VERDICTS = ("ON-LINE", "OFF-LINE", "ABSENT-TEXT", "DANGLING-FILE", "DANGLING-LINE",
            "NOT-A-PATH", "AMBIGUOUS", "EXISTENCE-ONLY", "NEIGHBOURHOOD", "REFUSED-NEEDLE",
            "BLOB-GONE")


def cite_once(row: tuple) -> dict:
    """One citation, judged.  `COSMETIC`/`STALE`/`FALSIFIED`/`DANGLING` are the four the
    briefing names, and each is produced by a DIFFERENT test -- which is the whole point:
    a drifted line number and a falsified claim are different defects and an instrument
    that reports one number for both cannot tell a reader which one they are holding."""
    return dict(zip(FIELDS, row)) | {"file": None}


def judge(c: dict, U: Universe, bodies: dict[str, list[str]], reg: dict[str, set[int]]) -> dict:
    path, how = U.resolve(c["subject"], c["rev"])
    c["how"] = how
    if path is None:
        if how.startswith("ambiguous"):
            c["verdict"] = "AMBIGUOUS"
            c["why"] = f"{how} tracked paths end in /{c['subject']}"
            return c
        # *** AN EXTENSION NO FILE IN THE CORPUS HAS IS NOT A CITATION. ***  MEASURED on the
        # first live run: `1000.0`, `10.0.0.1`, `dev_sort.GPU`, `row_tuple.ALUEXEC` and
        # `Ops.RANGE` were all emitted as DANGLING-FILE, and they are floats, IP addresses and
        # dotted Python attributes -- 95 of the 4,550.  The extension set is READ OUT OF THE
        # WALK (`Universe.exts`), never remembered, so this is not `checks/repro-paths.py`'s
        # suffix-set defect: adding a `.foo` file to the tree makes `.foo` admissible with no
        # edit here.  And the SPLIT rather than the FILTER is deliberate: a citation into a
        # file whose extension was RENAMED AWAY is exactly the class this census exists for,
        # so `oracles/dsl_oracle.txt` stays DANGLING-FILE (`.txt` still exists here) and the
        # weak class is reported under its own name with its own count.
        ext = c["subject"].rsplit(".", 1)[-1] if "." in c["subject"] else ""
        c["verdict"] = "DANGLING-FILE" if ext and ext in U.exts else "NOT-A-PATH"
        c["why"] = (f"no file in the walk or in HEAD is {c['subject']!r}"
                    + ("" if c["verdict"] == "DANGLING-FILE"
                       else f", and no file in the corpus has a .{ext} either -- a dotted "
                            f"identifier, not a path"))
        return c
    if c["rev"]:
        text = read_blob(c["rev"], c["subject"])
        if text is None:
            c["verdict"] = "BLOB-GONE"
            c["why"] = f"{c['rev']}:{c['subject']} is not a blob in this repository"
            return c
        body = text.splitlines()
        c["verdict"] = "DANGLING-LINE" if c["hi"] > len(body) else "EXISTENCE-ONLY"
        c["why"] = f"blob {c['rev']}:{c['subject']} has {len(body)} lines"
        return c
    body = bodies.get(path)
    if body is None:
        body = read_text(ROOT / path)
        if body is None:
            c["verdict"] = "DANGLING-FILE"
            c["why"] = f"{path} is tracked but not readable as text"
            return c
        body = body.splitlines()
        bodies[path] = body
    if c["lo"] > len(body):
        c["verdict"] = "DANGLING-LINE"
        c["why"] = f"{path} has {len(body)} lines, cited at :{c['loc']}"
        return c
    # ---- the claim test.  This is the only part that can say FALSIFIED.
    if c["needle"] is None:
        c["verdict"] = "EXISTENCE-ONLY"
        c["why"] = f":{c['lo']} exists in a {len(body)}-line file; NOTHING on the claiming " \
                   f"line says what it should say"
        return c
    # *** A NEEDLE THAT IS A DIFFERENT KIND OF CLAIM IS NOT A FALSIFICATION. ***  MEASURED on
    # the first live run: 543 of the headline FALSIFIED rows carried needles like `:281`,
    # `ops.bend:5332` and `llvmir-oracle.py:866` -- which are LOCATORS, and asking a file
    # whether it "contains `ops.bend:5332`" asks about a different object.  `CC.needle_kind`
    # already classifies exactly this (`reference`, `code`, `output`, `digest`, `exit-status`,
    # `command`, `cell-label`, `fragment`, `short`) and each was bought with a measured fault,
    # so the taxonomy is called rather than re-derived.
    c["needle_kind"] = CC.needle_kind(c["needle"], c.get("tail", ""), c.get("line_text", ""))
    if c["needle_kind"] != "text":
        c["verdict"] = "REFUSED-NEEDLE"
        c["why"] = f"the needle is {c['needle_kind']!r}, a different KIND of claim: " \
                   f"{c['needle'][:40]!r} is not a claim about this file's text"
        return c
    if c.get("neighbourhood"):
        c["verdict"] = "NEIGHBOURHOOD"
        c["why"] = f"the claim is about what SURROUNDS :{c['lo']}, not text AT it; " \
                   f"{c['needle'][:40]!r} may be a former name"
        return c
    if CC.cited(body[c["lo"] - 1], c["needle"]):
        c["verdict"] = "ON-LINE"
        c["why"] = f":{c['lo']} carries {c['needle'][:48]!r}"
        return c
    near = [i for i, l in enumerate(body, 1) if CC.cited(l, c["needle"])]
    # *** LANE X SAYS `OFF-LINE` AND NEVER `STALE`, AND THE REASON IS A MEASURED ONE. ***
    # `.agents/TODO.md:2519` reads "`ptx.py:13`/`ptx.py:16` (`render_val`'s signed-integer and
    # double ...)".  `render_val` is DEFINED at `tinygrad/renderer/ptx.py:11` and line 16 is
    # INSIDE its body -- `sed -n 16p` reads `return str(int(x)) + ("U" if ...)`.  The claim is
    # TRUE and a needle-at-the-line test calls it STALE, because the claim is about
    # CONTAINMENT, not about occurrence.  `OFF-LINE` is exactly what was measured -- "the named
    # text is not AT the cited line" -- and it makes no claim about whether the citation is
    # right.  The four-word vocabulary (COSMETIC / STALE / FALSIFIED / DANGLING) belongs to
    # LANE R alone, where a diff adjudicates it; a lane that cannot tell containment from
    # occurrence has no business using the word STALE at all.
    c["verdict"] = "OFF-LINE" if near else "ABSENT-TEXT"
    c["why"] = (f"{c['needle'][:48]!r} is NOT at :{c['lo']}; it is at {near[:4]} in {path} "
                f"-- a containment claim and a position claim are different claims"
                if near else
                f"{c['needle'][:48]!r} is NOWHERE in {path} ({len(body)} lines)")
    c["near"] = near[:4]
    return c


def regressed(c: dict, path: str, reg: dict[str, set[int]],
              bodies: dict[str, list[str]], touched: set[str]) -> dict:
    """Is THIS citation one the named regressor moved, and how badly.

    The post-image comes out of `bodies`, which `judge` already populated for every path it
    read -- so this reads no file of its own and the selftest can drive it off a four-line
    scratch file by seeding the same cache the census fills."""
    r = reg.get(path)
    if r is None:
        r = regressed_lines(path, touched)
        reg[path] = r
    hit = next((i for i in range(c["lo"], c["hi"] + 1) if i in r), None)
    if hit is None:
        c["regressed"] = False
        c["regression"] = "NOT-MOVED"
        return c
    c["regressed"] = True
    c["at_old"] = hit
    post = bodies.get(path) or []
    # *** AN EMPTY NEEDLE MATCHES EVERY LINE. ***  `cited(l, "")` is `re.search(r"(?![\w])", l)`,
    # which succeeds at position 0 of anything, so a citation carrying no claim at all read as
    # COSMETIC -- the strongest word in the vocabulary, handed to the weakest evidence.  The
    # `if c["needle"]` is the guard and it is the FIRST branch, not a filter at the end.
    if not c["needle"]:
        c["regression"] = "MOVED-UNCLASSIFIABLE"
    elif hit <= len(post) and CC.cited(post[hit - 1], c["needle"]):
        c["regression"] = "COSMETIC"
    elif not any(CC.cited(l, c["needle"]) for l in post):
        c["regression"] = "FALSIFIED"
    else:
        c["regression"] = "STALE"
        # NO NEEDLE: the honest answer is a lower bound, not a guess.  The line MOVED (that
        # is measured) and whether the CLAIM still follows is not decidable from the citation.
    return c


def main() -> int:
    argv = sys.argv[1:]
    if "--selftest" in argv:
        return selftest()
    report_only = "--report" in argv
    rows_out = argv[argv.index("--rows") + 1] if "--rows" in argv else None
    find_out = argv[argv.index("--findings") + 1] if "--findings" in argv else None

    paths, tally, nbytes, nbig = walk()
    tpaths = tracked()
    if not paths:
        print("== DEAD: the walk found no file to read; the census measured nothing")
        return DEAD
    U = Universe(paths, tpaths)
    only_walk = [p for p in paths if p not in set(tpaths)]
    only_head = [p for p in tpaths if p not in U.on_disk]

    claims: list[dict] = []
    bodies: dict[str, list[str]] = {}
    nfile = 0
    for rel in paths:
        text = read_text(ROOT / rel)
        if text is None:
            tally["not text (binary or unreadable)"] += 1
            continue
        nfile += 1
        for row in extract(text):
            c = cite_once(row)
            c["file"] = rel
            claims.append(c)
    if not claims:
        print("== DEAD: the corpus yielded no `file:line` shape at all")
        return DEAD

    reg: dict[str, set[int]] = {}
    for c in claims:
        judge(c, U, bodies, reg)
    touched = regressor_paths()
    for c in claims:
        path, _ = U.resolve(c["subject"], c["rev"])
        if path and not c["rev"]:
            regressed(c, path, reg, bodies, touched)

    CLAIMS = [c for c in claims if not c["file"].startswith(".agents/slop/")]
    # ---- the four-way answer the briefing asks for, over the REGRESSED population only.
    RV = Counter(c.get("regression") for c in claims if c.get("regressed"))
    XV = Counter(c["verdict"] for c in claims)
    claim_files = defaultdict(set)
    for c in claims:
        claim_files[c["verdict"]].add(c["file"])

    # ---- DANGLING sites: the class that LOOKS FINE.  Every one is printed.
    # THE HEADLINE DENOMINATOR IS THE CLAIM POPULATION, and `bad` is computed over IT.  A
    # verdict computed over 452,070 rows of other instruments' archived tables is a verdict
    # about a census of a census, and it would swamp the 2,181 rows a reader can act on.
    BAD = ("ABSENT-TEXT", "DANGLING-FILE", "DANGLING-LINE")
    bad = [c for c in CLAIMS if c["verdict"] in BAD]
    bad_all = [c for c in claims if c["verdict"] in BAD]
    for c in sorted(bad, key=lambda c: (c["verdict"], c["file"], c["at"]))[:400]:
        print(f"  {c['verdict']:14s} {c['file']}:{c['at']} -> {c['subject']}:{c['loc']}"
              f"  [{c['how']}] {c['why']}"
              + (f"  claim {c['needle'][:48]!r}" if c.get("needle") else "  (no needle on the line)"))

    # ---- strata, because the headline number is not one population
    strata = {
        "the whole walk (references/ excluded)": claims,
        "  minus .agents/slop/  <-- THE HEADLINE": CLAIMS,
        "    of which .agents/*.md (the governing documents)":
            [c for c in CLAIMS if c["file"].startswith(".agents/")],
        "    of which tinybendygrad/ (the port itself)":
            [c for c in CLAIMS if c["file"].startswith("tinybendygrad/")],
        "    of which gates/ + checks/ (the instruments)":
            [c for c in CLAIMS if c["file"].startswith(("gates/", "checks/"))],
        "      of which checks/census.json (a machine TABLE, a record not a claim)":
            [c for c in CLAIMS if c["file"] == "checks/census.json"],
        "    of which runs/ (captured graphcmp output)":
            [c for c in CLAIMS if c["file"].startswith("runs/")],
    }

    print(f"POPULATION : {len(paths)} files in the WALK, {len(tpaths)} in git ls-tree -r HEAD")
    print(f"             {len(U.all)} distinct; {len(only_walk)} on disk and NOT in HEAD "
          f"(gitignored or intent-to-add), {len(only_head)} in HEAD and not on disk")
    print(f"             {nfile} read as text, {nbytes/1048576:.1f} MiB, {nbig} over "
          f"{MAX_BYTES//1048574} MiB and NOT censused")
    print("EXCLUDED   : (every rule, its reason, and how many files it dropped)")
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"               {v:6d}  {k}")
    print(f"CLAIMS     : {len(claims)} `file:line` citations over "
          f"{len({c['file'] for c in claims})} files")
    print()
    print("LANE R -- REGRESSION by " + REGRESSOR + ".  EXACTLY DECIDED from the blob pair.")
    print(f"           {sum(RV.values())} citations the named regressor moved, in "
          f"{len({c['file'] for c in claims if c.get('regressed')})} files")
    for v in ("COSMETIC", "STALE", "FALSIFIED", "MOVED-UNCLASSIFIABLE"):
        n = RV.get(v, 0)
        print(f"           {v:22s} {n:6d}")
    print("           (COSMETIC here means the cited line STILL carries the claimed text after "
          "the move -- a byte comparison, not a judgement.)")
    print("           BY WHERE THE CLAIM LIVES:")
    for label, sel in (("  in the headline (no .agents/slop/)", CLAIMS),
                       ("  of which .agents/*.md", [c for c in CLAIMS
                                                     if c["file"].startswith(".agents/")]),
                       ("  of which tinybendygrad/", [c for c in CLAIMS
                                                      if c["file"].startswith("tinybendygrad/")]),
                       ("  of which gates/ + checks/", [c for c in CLAIMS
                                                        if c["file"].startswith(("gates/", "checks/"))]),
                       ("  in .agents/slop/ (archived censuses)",
                        [c for c in claims if c["file"].startswith(".agents/slop/")])):
        v = Counter(c["regression"] for c in sel if c.get("regressed"))
        print(f"           {label:42s} " + " ".join(f"{k}={v[k]}" for k in
              ("COSMETIC", "STALE", "FALSIFIED", "MOVED-UNCLASSIFIABLE") if v[k])
              + f"   TOTAL={sum(v.values())}")
    print()
    print("LANE X -- RESOLUTION over the whole tree.  COSMETIC IS NOT AVAILABLE HERE: nothing "
          "in this lane\n           can prove a line never moved, so EXISTENCE-ONLY is the word.")
    for v in VERDICTS:
        n = XV.get(v, 0)
        if n:
            hs = sum(1 for c in CLAIMS if c["verdict"] == v)
            print(f"           {v:22s} {n:6d}  in {len(claim_files[v]):4d} files"
                  + (f"   ({hs} in the headline)" if hs != n else ""))
    rk = Counter(c["needle_kind"] for c in claims if c["verdict"] == "REFUSED-NEEDLE")
    if rk:
        print("           REFUSALS BY NEEDLE KIND (the kinds a FALSIFIED would have been): "
              + ", ".join(f"{k}={v}" for k, v in sorted(rk.items(), key=lambda kv: -kv[1])))
    print("           RESOLUTION BY SPELLING: " +
          ", ".join(f"{k}={v}" for k, v in sorted(Counter(c["how"] for c in claims).items(),
                                                  key=lambda kv: -kv[1])))
    print()
    print("STRATA (the headline is not one population -- subtract a line if you want another):")
    for label, cs in strata.items():
        v = Counter(c["verdict"] for c in cs)
        d = sum(v[x] for x in BAD)
        print(f"           {label:62s} {len(cs):7d} claims, {d:5d} dangling-or-falsified")
    print()
    if REVERSED:
        print(f"REVERSED  : {sum(REVERSED.values())} range citation(s) written end-before-start; "
              f"normalised and COUNTED, not dropped -- " +
              ", ".join(f"{k}={v}" for k, v in sorted(REVERSED.items())))
    print()
    print(f"VERDICT: {'PASS' if not bad else 'FAIL'} -- {len(bad)} DANGLING or FALSIFIED "
          f"citations in the {len(CLAIMS)}-row headline "
          f"({len(bad)/max(1,len(CLAIMS))*100:.2f}%); over the whole walk, including the "
          f"{sum(1 for c in claims if c['file'].startswith('.agents/slop/'))} archived rows of "
          f"earlier censuses, it is {len(bad_all)} of {len(claims)}. A dangling citation looks "
          f"fine to a reader, which is why it is the class this tree counts.")
    if report_only:
        print("(REPORT: exit 0 by request; the number above is the census, not a verdict)")
    HEADER = ("verdict\tregression_or_blank\tclaiming_site\tsubject\thow\tneedle\t"
              "why\n")

    def _row(c: dict) -> str:
        return (f"{c['verdict']}\t{c.get('regression', '')}\t{c['file']}:{c['at']}\t"
                f"{c['subject']}:{c['loc']}\t{c['how']}\t{c.get('needle') or ''}\t{c['why']}\n")

    if rows_out:
        Path(rows_out).write_text("".join(_row(c) for c in claims))
        print(f"ROWS       : {len(claims)} -> {rows_out}")
    if find_out:
        # THE FINDINGS ARE A DELIVERABLE AND THEY LIVE BESIDE THE GATE, IN GIT.
        # `gates/artifacts/` is `.gitignore`d and `rm -rf gates/artifacts` is a live command
        # in this tree (AGENTS.md), so an artifact-only answer to "what is broken" is an answer
        # with a shelf life.  *** AND THE FILE IS ITS OWN CITATION-OF-A-CITATION: every row
        # holds a `subject:N`, so committing it adds ~400 rows to the NEXT run's population.
        # That is the `realize.bend:881` shape at 400x and it is stated here rather than left
        # for the next reader to wonder why the headline grew.
        Path(find_out).write_text(HEADER + "".join(_row(c) for c in bad))
        print(f"FINDINGS   : {len(bad)} headline DANGLING/ABSENT-TEXT rows -> {find_out} "
              f"(this file is itself ~{len(bad)} citations on the NEXT run)")
    return PASS if report_only or not bad else FAIL


# --------------------------------------------------------------------------- the harness

def selftest() -> int:
    """THE HARNESS COMES FIRST.  Nine plants, and the tree must MOVE ITS VERDICT for each.
    A census that cannot fail is the instrument `checks/cites-census.py` was written to catch,
    and the fourth of these is the plant for the one rule this file is most likely to get
    wrong by accident: a RANGE whose first line is below a boundary and whose last is above it."""
    import tempfile
    cases = []
    with tempfile.TemporaryDirectory(prefix="cites-gate-") as td:
        subj = Path(td) / "subj.bend"
        subj.write_text("alpha\nbeta\ngamma\ndelta\n")
        U = Universe(["subj.bend", "tinybendygrad/uop/ops.bend"], ["subj.bend"])
        reg: dict = {}
        bodies = {"subj.bend": subj.read_text().splitlines()}

        def j(subject, loc, tail="-- `beta`"):
            """One citation, built the way `extract` builds one -- so the plant drives the
            EXTRACTOR and not a hand-assembled dict, which is the same mistake
            `checks/cites-census.py`'s THOUSANDS plant records: `judge` never sees the string
            the regex produced, so a `judge` plant cannot fail when the regex breaks.

            THE GAP IS PUNCTUATION, AND IT IS PUNCTUATION ON PURPOSE.  `CC._is_connector`
            rejects a gap containing a three-letter word, because a predicate belongs to its
            path only if nothing but a connector separates them -- so a plant written
            "... carries `beta`" gets EXISTENCE-ONLY, CORRECTLY, and would have taught me
            nothing.  The tree writes `` `ops.bend:864` -- `Device.tag` `` and so does this."""
            line = f"`{subject}:{loc}` {tail} here"
            (c,) = [dict(zip(FIELDS, r), file="plant.md") for r in extract(line)]
            return judge(c, U, bodies, reg)["verdict"]

        cases.append(("CONTROL: :2 carries the claimed text", j("subj.bend", "2"), "ON-LINE"))
        cases.append(("OFF-LINE: the text is at :2, so a claim made at :3 is OFF-LINE",
                      j("subj.bend", "3"), "OFF-LINE"))
        cases.append(("ABSENT-TEXT: a text that is NOWHERE is not merely off-line",
                      j("subj.bend", "2", "-- `epsilon`"), "ABSENT-TEXT"))
        cases.append(("DANGLING-LINE: :99 is past the end of a 4-line file",
                      j("subj.bend", "99"), "DANGLING-LINE"))
        cases.append(("DANGLING-FILE: no file is `nonesuch.bend`",
                      j("nonesuch.bend", "2"), "DANGLING-FILE"))
        cases.append(("EXISTENCE-ONLY: no needle, so nothing checks what it says",
                      j("subj.bend", "2", "-- where it lives"), "EXISTENCE-ONLY"))
        # MEASURED on the live tree: TODO.md:2800 says "This is `reduce.py:45`'s `mo_downcast`
        # neighbourhood", and `grep -c mo_downcast tinygrad/mixin/reduce.py` answers **0** over
        # 138 lines -- correctly, because the name was RENAMED and TODO.md is a changelog whose
        # subjects are FORMER names. FALSIFIED there would put the census's strongest word on a
        # true sentence about a deletion.  THE PLANT IS THE TREE'S SPELLING AND NOT A PARAPHRASE:
        # an earlier revision of it read `` -- `gamma`'s `beta` ``, which has THREE quoted spans,
        # so the needle found first was `gamma` -- a STALE -- and the possessive was never
        # reached. A plant that paraphrases the shape it is testing tests nothing.
        cases.append(("NEIGHBOURHOOD: `f.py:N`'s `old_name` is a claim about the SURROUNDINGS",
                      j("subj.bend", "2", "'s `beta`"), "NEIGHBOURHOOD"))

        # THE RANGE PLANT.  `reg` says lines 3 and 4 moved.  `:2-4` reaches one of them and
        # `:2` does not, and an extractor that reads only the FIRST number of a range reports
        # the second one resolved.  MEASURED on the live tree: nine range citations straddle
        # their target's insertion point and exactly one of them -- `uop/render.bend`'s
        # `ops.bend:865-881` -- reaches past it, and it is a TRUE citation today.
        reg["subj.bend"] = {3, 4}

        def rg(loc):
            (c,) = [dict(zip(("at", "subject", "loc", "lo", "hi", "needle", "neighbourhood",
                             "rev", "line_text", "tail"), r), file="plant.md")
                    for r in extract(f"`subj.bend:{loc}` -- `beta`")]
            judge(c, U, bodies, reg)
            return regressed(c, "subj.bend", reg, bodies, {"subj.bend"})["regression"]

        cases.append(("RANGE: `:2-4` reaches a moved line even though `:2` does not",
                      rg("2-4") in ("STALE", "FALSIFIED"), True))
        # THE AMBIGUITY PLANT, BUILT IN THE TEMP UNIVERSE AND NOT ASSERTED FROM MEMORY.
        # `uop/fold.bend` exists at `tinybendygrad/uop/fold.bend` AND at
        # `.agents/slop/strays/{origin,working}/tinybendygrad/uop/fold.bend` -- three real
        # files, and 20 headline DANGLING-FILE rows said `absent`. The resolver REFUSES.
        U3 = Universe(["tinybendygrad/uop/fold.bend",
                       ".agents/slop/strays/origin/tinybendygrad/uop/fold.bend",
                       ".agents/slop/strays/working/tinybendygrad/uop/fold.bend"], [])
        cases.append(("AMBIGUOUS: three files end in /uop/fold.bend -> REFUSED, never `absent`",
                      U3.resolve("uop/fold.bend", None), (None, "ambiguous:3")))
        cases.append(("RANGE: `:1-2` misses every moved line", rg("1-2"), "NOT-MOVED"))

        # THE `[^/]*`-MATCHED-EMPTY PLANT, in the shape this tree has already paid for: a
        # token whose path part vanishes writes a FALSE ROW, so all three spellings must
        # still name the subject, and none may name the empty string.
        rows = extract("`tinybendygrad/uop/ops.bend:868` and `ops.bend:868` and `./ops.bend:868`")
        cases.append(("PREFIX: all three spellings RESOLVE to the one ops.bend there is",
                      sorted({U.resolve(r[1], None)[0] for r in rows}),
                      ["tinybendygrad/uop/ops.bend"]))
        cases.append(("PREFIX: no subject is ever the empty string",
                      [r for r in rows if not r[1]], []))
        cases.append(("PREFIX: an empty subject resolves to nothing, so it is never a row",
                      U.resolve("", None)[0], None))
        cases.append(("CLOCK: `12:30:45` is not a citation of a file called `30`",
                      extract("at 12:30:45 today"), []))

        # THE DERIVED-BOUNDARY PLANT, ON LITERALS AND NOT ON THE TREE.  `optim.bend`'s net
        # delta under `b86e3c25e` was 0 -- 1,426 lines before and 1,426 after -- and old line
        # 1407 was still REWRITTED (`@@ -1407 +1407 @@`), so a boundary read off the diff's
        # `+N` answers 0 here and calls a moved line resolved.
        pre = [f"line {i}" for i in range(1, 1427)]
        post = list(pre)
        post[1406] = "REWRITTEN"                       # the one line the commit replaced
        post = post[:5] + ["inserted a", "b", "c", "d"] + post[5:]
        got = regressed_indices(pre, post)
        cases.append(("BOUNDARY: a 0-line-delta file still has a rewritten line at 1407",
                      (1407 in got, len(pre) == len(pre)), (True, True)))
        cases.append(("BOUNDARY: 4 inserted lines move every index from the insertion on",
                      (len([i for i in range(6, 1427) if i in got]), 1407 in got),
                      (1421, True)))
        cases.append(("BOUNDARY: an UNCHANGED file has an empty regressed set",
                      regressed_indices(pre, list(pre)), set()))
        cases.append(("BOUNDARY: a file that SHRANK regresses every index past its new end",
                      sorted(regressed_indices([f"l{i}" for i in range(10)],
                                               [f"l{i}" for i in range(4)])),
                      [5, 6, 7, 8, 9, 10]))
    bad = 0
    for why, got, want in cases:
        ok = got == want
        bad += not ok
        print(f"[{'   PASS' if ok else '   FAIL'}] {why}\n          got {got!r}, want {want!r}")
    print(f"\n=== selftest {'PASS' if not bad else 'FAIL'}: {len(cases)} case(s), {bad} failed ===")
    return PASS if not bad else FAIL


if __name__ == "__main__":
    sys.exit(main())
