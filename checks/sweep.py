#!/usr/bin/env python3
"""Sort every file under .agents/slop and runs into exactly four buckets, then act on three.

    usage: .venv/bin/python checks/sweep.py --plan          # classify, print the plan, delete nothing
           .venv/bin/python checks/sweep.py --apply DOC GATE ORACLE DELETE

THE RULE, AS THE USER STATED IT:

    anything in slop which isn't real documentation, or should be moved to checks/ (gates),
    oracles, or whatever, should be deleted. This includes one-off test scripts.

So there are five buckets, and one verdict that is not a bucket:

    DOC      a .md report. It records a measurement or a decision. It stays in slop.
    GATE     it RUNS and DECIDES, and something load-bearing names it. It moves to checks/.
    ORACLE   it is reference DATA a gate compares against -- never executed, only diffed.
             It moves to oracles/.
    AUTHORED a NAMING AUTHORITY renders this name, so it is an OUTPUT CONTRACT rather than a file
             somebody made once. `checks/differ.py` DECLARES 136 of them and reads 12 by name; a
             sweep that calls them junk is measuring its own tokenizer, not the tree.
    DELETE   an OUTPUT no authority renders, no committed text names, and no one owns. ONE-OFF
             PROBES, MUTATORS, GENERATED ROW DUMPS, .err CAPTURES, SHADOW TREES OF THE SOURCE --
             and nothing else. It is a VERDICT, and it is reached only by saying so.

    UNKNOWN  a test COULD NOT BE RUN. Reported, never acted on, and tagged with `needs=`: the
             cheapest test that would resolve the row. **IT IS NOT A BUCKET, IT IS A RECORD OF
             NOT-SURE, AND IT IS THE ONLY VERDICT `--apply` CANNOT BE POINTED AT.**

DELETE WAS NOT A VERDICT UNTIL 2026-10-06. `verdict_for` ended in `return "DELETE"`, which is the
ABSENCE of a verdict: it is what a classifier emits when every escape declined to fire, and it is the
only bucket `--apply` destroys. **A CLASSIFIER WITH NO VERDICT FOR *I CANNOT TELL* DELETES THE
UNCLASSIFIABLE BY DEFAULT** -- and MEASURED on this tree, 354 of 1,421 rows were reaching that
default, with no record that any of them was doubtful. `UNKNOWN` is what a row says instead, and it
carries the test that would end the doubt, because **a group with no deciding test is a group that has
been labelled.**

WHY THE GATE SET IS DEFINED BY BEING NAMED, NOT BY BEING EXECUTABLE.  MEASURED: `.agents/slop`
holds 5,817 `.sh`/`.py` files and 515 executables, of which **367 are copies of UPSTREAM's own
scripts** (`dev`, `run`, `setup`, `serve`, `train`) inside shadow trees of the source. And the
citation test has already been got wrong three times in this project -- a bare-basename match
reported 3,574 false citations, 138 of them copies of one `__init__.bend`; a bare-substring match
reported 6 citers for a ZERO-BYTE `.err`. **A GATE IS A GATE BECAUSE SOMETHING DEPENDS ON IT, AND
THE ONLY WAY TO KNOW THAT IS TO ASK WHAT NAMES IT.**

CITATIONS ARE WHOLE PATH TOKENS. `in` IS NOT A CITATION TEST. The matcher is a word-boundary
regex over committed reports plus `AGENTS.md` and `checks/README.md`, because a bare `in` is how
four files at the repository root were once kept alive by a report mentioning `.error`.

LIVE FILES ARE NEVER TOUCHED. The window is `--live-minutes`, and it is checked at ACT time, not
only at classify time, because five units are writing into slop while this runs. **`--plan` ALSO
PRINTS THE COUNT AT WINDOW 0 BECAUSE THE WINDOW IS A CLOCK AND NOT A MEASUREMENT OF THE TREE:**
MEASURED, same tree, nothing edited, `DELETING 366 / 44 / 0` at 0, 60 and 1440 minutes.
"""
from __future__ import annotations

import argparse
import collections
import functools
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLOP = os.path.join(ROOT, ".agents/slop")
RUNS = os.path.join(ROOT, "runs")
CHECKS = os.path.join(ROOT, "checks")
ORACLES = os.path.join(ROOT, "oracles")
RESIDUE_ROOTS = (".agents/slop", "runs")

# `UNKNOWN` IS TAGGED, AND THE TAG IS THE POINT. `needs=` travels with the verdict instead of
# travelling with a sentence in a report nobody reads, and the tag is why no `--apply` argument can
# reach one of these rows: nothing equals `UNKNOWN:belts-disagree`. **AN UN-ACTIONABLE VERDICT IS SAFE
# BY CONSTRUCTION, NOT BY THE AUTHOR REMEMBERING.**
UNKNOWN = "UNKNOWN"

# A ROW THAT IS A TOOL IS A DIFFERENT KIND OF CLAIM FROM A ROW THAT IS AN OUTPUT. An output nobody
# names is junk. **A TOOL nobody names is a question about a person**, and this classifier cannot
# answer it, so it is `UNKNOWN` and not `DELETE` -- which is also the only thing standing between a
# sweep and the four of this project's own incident reports written by people.
TOOL_EXT = (".py", ".sh", ".mjs", ".c", ".js", ".ts", ".bend")

# What counts as being NAMED. Reports are where claims live; AGENTS.md and checks/README.md are
# what a reader actually reads.
#
# `:(glob)` IS LOAD-BEARING AND ITS ABSENCE WAS A 63% CORRUPTION. MEASURED 2026-10-05: git's
# DEFAULT pathspec magic treats `*` as FNM_PATHNAME-OFF, so `*` CROSSES `/`. `.agents/slop/*.md`
# therefore matched **195** files where `:(glob).agents/slop/*.md` matches **98** — and the extra 97
# were reports from INSIDE the shadow trees this script exists to delete, i.e. COPIES OF THE CORPUS
# ITSELF. The citation blob was **3,736,092 chars of which 1,370,376 were real**: 63% of the
# evidence was a copy of the evidence, so any file named inside a shadow tree counted as "named" and
# the KEEP set was inflated by exactly the files the sweep should have removed.
#
# **A CITATION INDEX BUILT FROM THE TREE BEING SWEPT IS NOT A CITATION INDEX.**
#
# **`checks/*.py` AND `gates/*.py` WERE MISSING, AND THAT IS WHY THE e2e GATE DIED.** MEASURED
# 2026-10-05: this list was byte-identical before and after the sweep that deleted `e2e_mm.py`,
# `e2e_mm.bend` and `e2e_mm_run.mjs` — stage 1's driver, so `checks/e2e.py` exited 2 in stage 1 and
# stages 2-8 NEVER RAN. The guard was not broken; **the gate was not in the corpus.** Both
# `checks/e2e.py` and `checks/sweep.py` name `e2e_mm.py`, and `checks/README.md` has named it
# **0 times, then and now** — so the ONLY thing keeping the project's one artifact alive was
# `.agents/slop/E2E-THROUGH-PORT.md`. **AN INSTRUMENT'S SURVIVAL DEPENDED ON A REPORT MENTIONING IT.**
#
# **A GATE NAMES ITS OWN INPUTS. THAT IS STRUCTURAL; A REPORT MENTIONING THEM IS A COINCIDENCE.**
NAMED_BY = [":(glob).agents/slop/*.md", "AGENTS.md", ":(glob)checks/*.md",
            ":(glob)gates/*.md", ":(glob).agents/*.md",
            ":(glob)checks/*.py", ":(glob)gates/*.py"]

# A gate names itself with these words. `-gate`/`-check` decide; `probe`/`mutate`/`gen`/`fix` are
# a thing that was run once. The distinction is the project's own vocabulary, not mine.
#
# **`GATE_WORD` IS GONE AND ITS BRANCH WAS DEAD CODE.** It was read in a branch that required
# `name in mentioned` to be true, and the line above it returned `KEEP-CITED` on exactly that
# condition, so the branch had no input that could reach it. **AN UNREACHABLE RULE IS NOT A SAFETY
# NET, IT IS A COMMENT THAT LOOKS LIKE ONE.** Its vocabulary is not lost: `differ.declared()` and the
# citation belts are what decide a gate now, and re-ordering that branch to be live would be a
# separate decision because it would make `--apply GATE` MOVE files.
ORACLE_WORD = re.compile(r"(^|[-_.])(oracle|rows|expect|pins|baseline)([-_.]|$)")

# Never touch these, whatever they look like. Each has caused a loss or a false verdict.
#
# `E2E_CHAIN` IS HERE BECAUSE I DELETED IT ONCE. The first `--apply DELETE` run moved 521 files
# and deleted the fixtures and stage drivers of the project's ONE artifact: `e2e_mm.py`,
# `e2e_mm.bend`, `e2e_mm_run.mjs`, `e2e_port/`, `f64/`, `e2e/`. `e2e.sh` itself was moved to
# `checks/` and left pointing at paths that no longer existed, so the artifact was a script that
# could not run. It was recoverable only because every one of those files happened to be
# committed -- WHICH IS NOT A PROPERTY OF THE SWEEP, IT IS A PROPERTY OF THE DAY.
#
# **`strays/` AND `strays-root/` WERE HERE AND WERE REMOVED, AND THE REASON IS THE THING THIS
# COMMENT ALREADY SAYS ABOVE IN ONE PLACE.** MEASURED 2026-10-05: the marking was
# `"42 files restored from origin after regressing"` -- an INCIDENT, not a DEPENDENCY, which is
# the same false-warrant shape as the six finished `LIVE_UNITS` that held 53% of `.slop`. Every
# mention of either directory outside itself is PROSE: `checks/nvrows-deadrow-gate.py:69`,
# `:205`, `checks/repro-paths.py:28`, `checks/wallcheck.py:101` name them in a docstring or a
# `--file` help string, and no code position reads them. Parked both, re-ran the gates: `no-strays`
# and `repro-paths` and `nvrows-deadrow-gate` produced BYTE-IDENTICAL output, `wallcheck` differed
# only in the pin hash (a concurrent commit), and `no-txt` fell 342 -> 338. **ZERO DEPENDENCY.**
# The `origin` arm is 18 of 21 byte-identical to live; the other 3 are older revisions, two of them
# reproduced by a named commit and `fold.bend` by none, which is why exactly one file was kept and
# 25 were deleted against `.agents/slop/strays/MANIFEST.tsv`. **A PAST ACCIDENT IS NOT A REASON TO
# KEEP A DIRECTORY FOREVER; THE TEST IS WHAT NAMES IT, AND THE ANSWER WAS NOTHING.**
PROTECTED = re.compile(
    r"(RECOVERY-0BYTE\.md$)"                           # the zero-byte incident
    r"|(^\.agents/slop/(e2e|e2e_port|f64|portexec)/)"  # the artifact's fixtures and stage drivers
    r"|(^\.agents/slop/e2e(_mm(\.py|\.bend|_run\.mjs))?\.sh$)"   # e2e.sh itself, and its three fixtures
    r"|(^\.agents/slop/(opsbend-milestone|substrate-check|graphcmp-(run|repro))\.sh$)"
    r"|(^checks/)"                                     # the gates themselves
)

# The differ's implementation and its frozen shell bodies. These are not one-off scripts: they are
# the thing every corpus number comes from. They move, but they move to a real home.
DIFFER = {"graphcmp.py", "graphcmp.bend", "graphcmp-oracle.py",
          "graphcmp-run.sh", "graphcmp-repro.sh", "graphcmp-dbg-oracle.py"}

# A DIRECTORY WHOSE OWN NAME DECLARES ITS ROLE CLASSIFIES ITS WHOLE SUBTREE. MEASURED 2026-10-05:
# `oracles/` (79 files, 520 KB, named by 4 reports) held 60 `.txt` of EXPECTED VALUES and was about to
# be deleted, because the verdict is computed per FILE from its BASENAME — and a file called
# `blob-bn.txt` inside a directory called `oracles` looks like a row dump. **THE ROLE IS A PROPERTY OF
# THE DIRECTORY AND WAS BEING READ FROM THE FILE.** These are the four names this project uses to
# mean a role, so a directory that is one of them is one.
#
# **`strays`/`strays-root` WERE IN THIS DICT AND ARE GONE.** A name in `ROLE_DIRS` is not a milder
# form of `PROTECTED`, it is a STRONGER one: `verdict_for` returns on the FIRST matching path part,
# before the citation test runs at all, so listing a directory here exempted its whole subtree from
# even being classified. **AN INCIDENT WAS ENCODED AS A NAME, WHICH MEANT NOBODY COULD EVER
# DISCOVER THAT THE INCIDENT HAD STOPPED BEING TRUE.** The name outlived its reason exactly the way
# the six finished `LIVE_UNITS` below did.
ROLE_DIRS = {"oracles": "ORACLE", "gates": "GATE", "checks": "GATE"}

LIVE_UNITS = (
    # LIVE RIGHT NOW. MEASURED 2026-10-05: this list was written before the current four were
    # dispatched, and the plan put **255 files of a running unit's** (`e2epy/`) into the DELETE
    # bucket. A live unit's exclusion cannot live in a hand-maintained list that nobody updates at
    # dispatch time, so the mtime window is the real guard and this list is only a second belt.
    "readback", "jsbf16", "bitcastrow", "corpus24", "i64shl", "shfinish", "wallcheck",
    # DISPATCHED AFTER THAT LIST WAS WRITTEN, WHICH IS THE THIRD TIME IT HAS BEEN WRONG. The mtime
    # window catches files a unit is actively writing; it does NOT catch the directory a unit is about
    # to write into, which is why this list exists at all. **A GUARD THAT IS CORRECT EXCEPT FOR THE
    # LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER.**
    "staleruns", "straysunit", "noreports", "runskeep", "dotxt",
    # FINISHED UNITS US TO BE PINNED HERE WERE THE WHOLE PROBLEM. MEASURED 2026-10-05: six names
    # sat under a `# finished` heading and had never been removed, and two of them were
    # `differverdict` (**1,382 files**) and `gatecensus` (**971**) — **2,353 of the 4,455 files in
    # `.slop`, 53%**, every one of them **100% tracked in git** and named by **0 files outside
    # themselves**. A finished unit's tree is not evidence of anything a reader can check; it is a
    # copy, and `git show` is the copy. **THE MTIME WINDOW IS THE LIVENESS GUARD, EXACTLY AS THE
    # COMMENT ABOVE SAYS -- AND A LIST THAT OUTLIVES ITS UNITS IS NOT A SECOND BELT, IT IS THE
    # ONLY BELT, WHICH IS HOW 53% OF THE TREE BECAME PERMANENT.**
    # a port that just completed but whose tree is still the cleanest evidence of a migration
    "e2epy", "substrate",
)

# Four MUTATION ARMS, NOT A COPY. `dd-cone-wt/` is 43 MB and 572 files, and the shadowtrees unit
# measured that its four arms differ in exactly TWO files and that `codegen/decomp/dtype.bend` is
# FOUR DISTINCT STATES: **deleting three of the arms destroys three arms.** It is the record of what
# four mutations did, and a mutation's value is its DIFFERENCE from the real file, so the evidence
# is the four-way divergence rather than any one of the trees.
PROTECTED_DIRS = ("dd-cone-wt",)


def committed_files() -> list[tuple[str, str]]:
    """(path, text) for every committed report and every reader-facing doc, read once each.

    PER FILE, because a citation with no ATTRIBUTION cannot be examined. The union of these texts is
    a blob, and a blob answers "is this name mentioned" and nothing else -- so it cannot tell a
    report that depends on a file from a shadow tree naming the files it copied, which are the same
    answer and not the same fact. `checks/residue.py` says the same thing about the same instrument.
    """
    out = []
    try:
        names = subprocess.run(["git", "ls-files", "--"] + NAMED_BY, cwd=ROOT,
                               capture_output=True, text=True).stdout.split()
    except Exception:
        return []
    for nm in names:
        try:
            r = subprocess.run(["git", "show", f"HEAD:{nm}"], cwd=ROOT,
                               capture_output=True, text=True, errors="replace")
            if r.returncode == 0:
                out.append((nm, r.stdout))
        except Exception:
            pass
    return out


def committed_named_text() -> str:
    """Every committed report and every reader-facing doc, as one blob."""
    return "\n".join(t for _nm, t in committed_files())


def tracked_files() -> set[str]:
    """`git ls-files` MINUS the tracked-but-deleted.

    `git ls-files` RETURNS TRACKED-BUT-DELETED PATHS, so membership tested against it alone calls a
    file committed when it is not on disk at all -- and an uncommitted row would then be deleted as
    if `git` could restore it.
    """
    r = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, text=True)
    return {p for p in r.stdout.split("\0") if p and os.path.lexists(os.path.join(ROOT, p))}


def declared_names() -> set[str]:
    """Every artifact name `checks/differ.py` RENDERS, plus the `.err` twin its writer emits beside
    each one. IMPORTED, NEVER COPIED: a second list of these names would be a contract with no
    generator, and a stale copy of a contract is how four artifacts came to be LOST and four others
    NEW in this project (`differverdict/VERDICT.md`, at HEAD).

    An authority that cannot be asked yields NO names rather than a traceback: **a carve-out that
    cannot be computed must never become a blanket exemption**, so the rows simply stop being
    AUTHORED and become `UNKNOWN` or `DELETE` as the rest of the tests decide, visibly.
    """
    try:
        spec = importlib.util.spec_from_file_location("differ", os.path.join(CHECKS, "differ.py"))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        names = set(m.declared())
    except Exception:
        return set()
    return names | {n + ".err" for n in names}


def mentioned_filenames(blob: str) -> set[str]:
    """Every filename-shaped token the corpus mentions, extracted in ONE pass.

    THE THIRD INSTANCE OF THIS PROJECT'S WORST PERFORMANCE BUG, AND THE THIRD TIME THE FIX IS ALSO
    THE MORE CORRECT ANSWER:
      1. `_cleanup/classify.py` ran an empty-pattern `git grep` over the whole repo -- >20 minutes.
      2. `move_gates.py` ran one `git grep` PER FILE over the same corpus.
      3. This file scanned a 3.4 MB corpus ONCE PER FILE: 23,000 x 3.4 MB = ~78 GB of scanning,
         and the first `--plan` TIMED OUT AT 15 MINUTES.

    All three share one shape: **A PER-ITEM SCAN OF A SHARED CORPUS.** The corpus does not change
    between items, so scanning it once is not an optimisation, it is the only correct shape.

    And the single pass is MORE correct than the regex-per-file was. A `name.ext` token pattern
    boundaries itself, so a report mentioning `.error` cannot cite a file called `.err`, and
    `xgraphcmp.py` cannot cite `graphcmp.py` -- which is exactly the rule, arrived at by indexing
    rather than by defending a boundary class.
    """
    return set(re.findall(r"[A-Za-z0-9_][A-Za-z0-9_.-]*\.[A-Za-z0-9]+", blob))


# BELT B, WHICH SHARES NO PATTERN WITH BELT A. This project has been bitten by a belt that could not
# see a stop its sibling belt stopped on, BECAUSE THE TWO SHARED THE REGEX'S ASSUMPTION, so the second
# belt here is a `str.translate` TABLE and has no pattern in it at all. It also finds something belt A
# provably cannot: `mentioned_filenames`'s pattern ends `\.[A-Za-z0-9]+`, so on `ops.staged-blob-24323`
# it matches `ops.staged-blob` and NEVER THE FILE'S NAME -- **a corpus token ending in a hyphenated
# segment is invisible to belt A, and there are files with those names.**
_WORD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./"


def whole_path_tokens(blob: str) -> set[str]:
    """Every byte that is not a path character becomes a space, then split. A token with a dot in it
    is a name; a token without one is a directory, and `runs/graphcmp/D` names no file."""
    table = str.maketrans({chr(i): " " for i in range(128) if chr(i) not in _WORD})
    return {t for t in blob.translate(table).split() if "." in t}


def in_residue(rel: str) -> bool:
    """Is this path inside one of the two trees this classifier sweeps?

    A CITATION FROM INSIDE THE RESIDUE DOES NOT KEEP A ROW. It is either a real dependency between
    two of the residue's own tools or a shadow tree naming the files it copied, **and those two are
    indistinguishable from out here**, so a row that only the residue names is `UNKNOWN`, not cited.
    """
    parts = rel.split(os.sep)
    return len(parts) > 1 and f"{parts[0]}/{parts[1]}" in RESIDUE_ROOTS


def witness_committed(rel: str, tracked: set[str]) -> bool:
    """Is there a COMMITTED report in this row's OWN directory?

    The cheapest decidable test for a tool row, and mechanical: either the directory holds a `.md`
    that is in git, in which case the citation belts have already asked it whether it names the tool,
    or it does not, in which case **the only thing that could ever explain this row is missing**.
    `committed_files` reads `git show HEAD:`, so an EDITED-BUT-UNCOMMITTED report contributes its old
    text -- an uncommitted report cites nothing, and says so here.
    """
    d = os.path.dirname(rel)
    try:
        names = os.listdir(os.path.join(ROOT, d))
    except OSError:
        return False
    return any(n.endswith(".md") and f"{d}/{n}" in tracked for n in names)


class Facts:
    """Everything the classifier needs that is not the row itself, measured ONCE.

    A PER-ITEM SCAN OF A SHARED CORPUS is this project's third performance bug and it is not an
    optimisation to avoid: the corpus does not change between items, so 1,421 scans of 3.4 MB is the
    same shape as the 23,000 x 3.4 MB that timed out `--plan` at 15 minutes.
    """

    def __init__(self) -> None:
        self.chars = 0
        # Belt A's key set is `mentioned_filenames` over the joined blob, token for token: neither
        # pattern can span the newline that joins the files, so indexing per file and taking the
        # union is the same set, and every verdict that used the blob keeps its meaning.
        self.cites: list[dict[str, set[str]]] = [{}, {}]
        for nm, text in committed_files():
            self.chars += len(text)
            for belt, toks in ((0, mentioned_filenames(text)), (1, whole_path_tokens(text))):
                index = self.cites[belt]
                for tok in toks:
                    index.setdefault(tok, set()).add(nm)
                    index.setdefault(tok.rsplit("/", 1)[-1], set()).add(nm)
        self.mentioned = set(self.cites[0])
        self.tracked = tracked_files()
        self.declared = declared_names()


@functools.cache
def facts() -> Facts:
    """The measurements, built once per process. `--plan` classifies 1,421 rows against one tree."""
    return Facts()


def live_set(minutes: int) -> set[str]:
    cutoff = time.time() - minutes * 60
    live = set()
    for base in (SLOP, RUNS):
        for dirpath, _d, files in os.walk(base):
            for f in files:
                p = os.path.join(dirpath, f)
                try:
                    if os.path.getmtime(p) >= cutoff:
                        live.add(os.path.relpath(p, ROOT))
                except OSError:
                    pass
    return live


def verdict_for(rel: str, mentioned: set[str], f: Facts | None = None) -> str:
    """The one classification. `f` defaults to the once-per-process measurements, so a caller that
    only has a `mentioned` set -- `checks/residue.py` has exactly that -- still gets them.

    RETURNS A TAGGED VERDICT: a bucket name, or `UNKNOWN:<the cheapest test that would resolve it>`.
    """
    f = f if f is not None else facts()
    name = os.path.basename(rel)
    parts = rel.split(os.sep)
    top = parts[2] if len(parts) > 2 else ""

    # A role directory decides for its whole subtree, before any per-file judgement.
    for part in parts:
        if part in ROLE_DIRS:
            return ROLE_DIRS[part]
    if PROTECTED.search(rel):
        return "PROTECTED"
    # A live unit's own directory, by name. The mtime window catches files; this catches the
    # DIRECTORY a unit is about to write into.
    if top in LIVE_UNITS:
        return "LIVE-UNIT"
    if top in PROTECTED_DIRS:
        return "PROTECTED"
    if name.endswith(".md"):
        return "DOC"
    if name in DIFFER:
        return "GATE"
    # A NAMING AUTHORITY RENDERS THIS NAME, so it is an output contract between two drivers and not a
    # file somebody made once. MEASURED 2026-10-06: `differ.declared()` renders 136 of the rows this
    # classifier used to call DELETE -- **100% of `runs/graphcmp/D` and 100% of `.agents/slop/spine/art-a`
    # -- and the literal-token citation corpus sees ONE of those basenames.** The corpus indexes
    # literal tokens; this project BUILDS its names. So `DELETE` was measuring "referenced by no
    # literal" and publishing it as "junk". One import, one call, and it is the whole of that group.
    if name in f.declared:
        return "AUTHORED"
    # THE CITATION, AND THE TWO BELTS MUST AGREE BEFORE IT DECIDES ANYTHING. They index the SAME
    # population and share no pattern, so a disagreement is a fact about the TOKENIZER and not about
    # the tree -- which is exactly the failure this project has already paid for once, in a belt that
    # missed a stop its sibling stopped on because the two shared the regex's assumption.
    belt_a, belt_b = f.cites[0].get(name, set()), f.cites[1].get(name, set())
    if belt_a ^ belt_b:
        only_a, only_b = sorted(belt_a - belt_b), sorted(belt_b - belt_a)
        # `mentioned_filenames`'s pattern both TRUNCATES a name whose last segment is followed by a
        # hyphen (`ops.staged-blob-24323` -> `ops.staged-blob`) and INVENTS a citation out of a glob
        # (`mm-*-gate.sh` -> `gate.sh`), so the two halves of this sentence are usually about the
        # REGEX being wrong. Which half is right is not a question a sweep may answer.
        return f"{UNKNOWN}:belts-disagree (the token regex sees {only_a[:1]}, " \
               f"the path scanner sees {only_b[:1]})"
    if belt_b and not {c for c in belt_b if not in_residue(c)}:
        return f"{UNKNOWN}:residue-internal-citer (named only from inside the residue by {sorted(belt_b)[0]})"
    # ORACLE IS NOT A WORD SHAPE. MEASURED 2026-10-05: this test was `ORACLE_WORD.search(name)` and
    # nothing else, so **670 of 675 ORACLE files were classified by their FILENAME and were named by NO
    # GATE AT ALL** — `gatecensus/` 167, `arith/` 51, `denom/` 50, `hermetic/` 49, `hdrbase/` 33, `eq/`
    # 32, `name-census-lanes/` 31: **finished units' row dumps that matched `rows|oracle|pins|baseline`
    # in a basename.** Only **5** are named by a live `checks/*.py` or `gates/*.py`.
    #
    # THIS IS THE SAME DEFECT AS `LIVE_UNITS`, ONE LEVEL UP, AND THE FILE ALREADY DIAGNOSED IT:
    # "the verdict is computed per FILE from its BASENAME — and a file called `blob-bn.txt` inside a
    # directory called `oracles` looks like a row dump. **THE ROLE IS A PROPERTY OF THE DIRECTORY AND
    # WAS BEING READ FROM THE FILE.**" `ROLE_DIRS` fixed it for four directory NAMES; the word shape
    # reintroduced it for every basename. **A FILE THAT NOBODY NAMES IS NOT REFERENCE DATA.**
    if name in mentioned and ORACLE_WORD.search(name) and not name.endswith((".sh", ".py")):
        return "ORACLE"
    # A FILE A COMMITTED REPORT NAMES IS **NEVER** DELETE. MEASURED 2026-10-05: the first sweep
    # deleted 3,603 files and `checks/repro-paths.py` went from 24 dangling reproduction paths to
    # **166** — because the GATE rule required a gate-shaped NAME *and* a citation, and everything
    # else fell through to DELETE. So a `.bend` fixture named by a report, and a `.py` an oracle
    # script needed, were both deletable while a report still pointed at them.
    #
    # **THE CITATION IS A LOWER BOUND ON VALUE, NOT A SUFFICIENT CONDITION FOR KEEPING.**
    # Naming something proves SOMEBODY DEPENDS ON IT; the name only decides which bucket.
    if name in mentioned:
        return "KEEP-CITED"
    # ---- THE FALLTHROUGH IS A DECISION NOW, NOT A DEFAULT. ----
    # Everything above declined, which used to mean DELETE. It no longer does: `DELETE` is a claim
    # about the row, and these are the two claims this classifier cannot make.
    if rel not in f.tracked:
        return (f"{UNKNOWN}:commit-or-drop (untracked, and nothing renders or names it; git could not"
                " restore it if this pass were wrong)")
    if os.path.splitext(name)[1] in TOOL_EXT and not witness_committed(rel, f.tracked):
        return (f"{UNKNOWN}:commit-the-report-that-explains-it (a TOOL, and its own directory has no"
                " committed report; nobody can say whose it is or what it was for)")
    return "DELETE"


def bucket(verdict: str) -> str:
    """The bucket a tagged verdict belongs to: `UNKNOWN:belts-disagree` is an `UNKNOWN`."""
    return verdict.partition(":")[0]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="classify and print; touch nothing")
    ap.add_argument("--apply", nargs="*", default=None,
                    help="verdicts to ACT on: DOC GATE ORACLE DELETE. "
                         "AUTHORED, UNKNOWN and the escapes are kept, never acted on")
    ap.add_argument("--live-minutes", type=int, default=60)
    ap.add_argument("--yes", action="store_true", help="required for DELETE")
    args = ap.parse_args()

    if UNKNOWN in (args.apply or ()):
        print(f"refusing to --apply {UNKNOWN}. It is a record of not-sure, and naming it is the mistake: "
              "the\ncheapest test that would resolve each row travels with it, in `--plan`.",
              file=sys.stderr)
        return 3

    f = facts()
    mentioned = f.mentioned
    live = live_set(args.live_minutes)
    # The same walk, with the window OFF, because the headline must not be a fact about the last hour.
    cold = live_set(0) if args.live_minutes else live

    rows = []
    for base in (SLOP, RUNS):
        for dirpath, _d, files in os.walk(base):
            for n in sorted(files):
                p = os.path.join(dirpath, n)
                rel = os.path.relpath(p, ROOT)
                v = verdict_for(rel, mentioned, f)
                if rel in live and v not in ("PROTECTED", "LIVE-UNIT"):
                    v = "LIVE"
                try:
                    # lstat, NOT getsize: getsize FOLLOWS SYMLINKS, and slop has 174 of
                    # them pointing into .venv and into shadow trees. Following them counted
                    # each link at its TARGET's size, so the sweep reported **1,291 MB for a
                    # 149 MB tree** -- a 7.5x headline on the ONE number it exists to publish.
                    rows.append((v, os.lstat(p).st_size, rel, rel not in cold))
                except OSError:
                    pass

    counts = collections.Counter()
    sizes = collections.Counter()
    for v, sz, _r, _c in rows:
        counts[bucket(v)] += 1
        sizes[bucket(v)] += sz

    total_n, total_b = len(rows), sum(sizes.values())
    print(f"# sweep: {total_n} files, {total_b/1048576:.0f} MB, "
          f"live-window {args.live_minutes}m, {len(mentioned)} filenames mentioned in {f.chars} chars")
    for v in ("DOC", "GATE", "ORACLE", "AUTHORED", "DELETE", "UNKNOWN",
              "LIVE", "LIVE-UNIT", "PROTECTED"):
        if counts[v]:
            share = sizes[v] / total_b * 100 if total_b else 0
            print(f"#   {v:11s} {counts[v]:7d} files {sizes[v]/1048576:8.1f} MB  {share:5.1f}%")
    # EVERY PATH BY WHICH A ROW REACHES `UNKNOWN`, COUNTED. A not-sure published as one number is a
    # not-sure nobody can act on except in bulk, and these are five different questions.
    needs = collections.Counter(v.partition(":")[2].split(" (")[0] for v, *_ in rows
                                if v.startswith(UNKNOWN))
    for k, n in needs.most_common():
        print(f"#     needs={k:38s} {n:6d} rows")
    if args.plan or not args.apply:
        keep = counts["DOC"] + counts["GATE"] + counts["ORACLE"] + counts["AUTHORED"]
        print(f"\n# KEEPING {keep} of {total_n}: "
              f"{counts['DOC']} doc + {counts['GATE']} gate + {counts['ORACLE']} oracle "
              f"+ {counts['AUTHORED']} authored")
        print(f"# REPORTING AND NOT ACTING ON {counts['UNKNOWN']} rows: a test could not be run for them")
        cold_n = sum(1 for v, _s, _r, c in rows if v == "DELETE" and c)
        cold_b = sum(s for v, s, _r, c in rows if v == "DELETE" and c)
        print(f"# DELETING {counts['DELETE']} files, {sizes['DELETE']/1048576:.0f} MB"
              + (f" -- of which {cold_n}, {cold_b/1048576:.0f} MB, with the liveness window OFF"
                 if cold_n != counts["DELETE"] else ""))
        if counts["DELETE"] > total_n * 0.5:
            print("#   (more than half. A sweep that keeps less than it removes is not a tidy-up;\n"
                  "#    it is a decision about what this directory is FOR.)")
        big = sorted((r for r in rows if r[0] == "DELETE"), key=lambda d: -d[1])[:12]
        if big:
            print("# largest DELETEs:")
            for _v, sz, rel, _c in big:
                print(f"#     {sz/1024:9.1f} KB  {rel}")
        return 0

    if "DELETE" in args.apply and not args.yes:
        print("refusing to DELETE without --yes. A deletion pass that needs no confirmation\n"
              "is the pass where the allow-list was wrong.", file=sys.stderr)
        return 3

    moved = deleted = 0
    for v, sz, rel, _cold in rows:
        src = os.path.join(ROOT, rel)
        # `v not in args.apply` is the check whose absence broke the artifact once: the bucket a
        # caller did NOT name was acted on anyway, because the `elif` tested the VERDICT rather
        # than the REQUEST. `--apply DELETE` moved 521 files and deleted e2e's fixtures.
        if v not in (args.apply or ()):
            continue
        if v == "DELETE":
            try:
                os.remove(src)
                deleted += 1
            except OSError:
                pass
        elif v in ("GATE", "ORACLE"):
            dest_dir = CHECKS if v == "GATE" else ORACLES
            # Flat, because 200 gates in a tree is a tree nobody reads; a name collision is
            # reported rather than silently resolved.
            dest = os.path.join(dest_dir, os.path.basename(rel))
            if os.path.exists(dest):
                continue
            os.makedirs(dest_dir, exist_ok=True)
            try:
                shutil.move(src, dest)
                moved += 1
            except OSError:
                pass

    # Prune directories left empty, derived never listed.
    pruned = 0
    for base in (SLOP, RUNS):
        for dirpath, _dn, _fn in os.walk(base, topdown=False):
            try:
                os.rmdir(dirpath)
                pruned += 1
            except OSError:
                pass
    print(f"DELETED {deleted} files, MOVED {moved} into checks/+oracles/, "
          f"pruned {pruned} empty directories")
    return 0


if __name__ == "__main__":
    sys.exit(main())