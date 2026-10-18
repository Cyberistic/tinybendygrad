#!/usr/bin/env python3
"""prose-census.py -- EVERY NUMBER THE GOVERNING PROSE ASSERTS, WITH ITS POPULATION, RE-DERIVED.

    .venv/bin/python gates/prose-census.py              # the census
    .venv/bin/python gates/prose-census.py --plan       # the contract; run nothing
    .venv/bin/python gates/prose-census.py --rows OUT   # the byte-reproducible table
    .venv/bin/python gates/prose-census.py --prove      # the row identity; MUST be able to fail
    .venv/bin/python gates/prose-census.py --plant      # a synthetic tree; MUST be able to fail

WHAT THIS IS FOR, AND WHICH PRIOR ART IT DOES NOT REPEAT
-------------------------------------------------------
This tree already holds two halves of this problem and NEITHER holds both:

  `gates/docnum-census.py`   WALKS the prose and censuses every number token -- and then says
                             so itself: "CURRENT / STALE-UNDATED / LOAD-BEARING-AND-WRONG
                             / NOT-A-NUMBER are the report's five, and they need the
                             MEASUREMENT, which this file does not have."
  `gates/docnum-claim-gate.py` SUPPLIES the measurement -- but from `CLAIMS`, a table of SIX
                             hand-named sites, and each row carries a COMMAND and no
                             POPULATION.

So the measurement exists and the census exists and the JOIN does not. This file is the join,
and the join is where the defect actually lives, because of the sentence that decides it:

    A NUMBER IN PROSE CANNOT BE CHECKED WITHOUT KNOWING WHICH POPULATION IT REFERS TO.

Each of those two files has half the answer and therefore can be wrong in the half it cannot
see. `docnum-claim-gate.py` compares a prose figure to a command and reports `PASS` -- and its
six rows all carry no population, so a row whose command measures population A while the prose
means population B compares two different things and can still come out green. That is the
member of the class nobody counts:

    (ii) A NUMBER THAT IS RIGHT, ATTACHED TO THE WRONG POPULATION.

It is the dangerous half because it is CORRECT, and a correct number is never re-checked. THIS
FILE IS BUILT SO THAT IT CANNOT HAPPEN QUIETLY: every measurer prints its own `population=`
BESIDE its `value=`, so every row records the population the figure was read over -- and where
a claimed figure's population cannot be determined, the row says `POPULATION-NOT-DECLARED` and
is still emitted. A population you cannot see is a population you cannot be wrong about, and
that must be a NAMED ROW, not a silence.

THE FOUR ROW KINDS, AND WHICH MEMBER OF THE CLASS EACH ONE IS
-------------------------------------------------------------
    HELD                        the prose figure EQUALS the re-derived figure.  PASS
    MOVED                       the prose figure DIFFERS.  Member (i).  FAIL
    CLAIM-FALSE-IN-PASSING-GATE a MOVED row whose SITE IS A GATE WHOSE OWN LIVE RUN
                                DISAGREES AND WHOSE EXIT IS 0.  Member (iii).  FAIL
    VALUE-COLLISION             one figure is claimed by MORE THAN ONE declared population.
                                Member (ii).  A NAMED ROW; not blocking unless --strict
    POPULATION-NOT-DECLARED     a claim whose population this instrument cannot determine.
                                Emitted, counted, and NOT counted as agreement.

THE THIRD MEMBER IS THE ONE THAT MATTERS MOST, AND IT IS THE EXPENSIVE ONE
--------------------------------------------------------------------------
`gates/corpuslane-gate.py` asserts in its own docstring that 30 of 34 graphs raise, and its own
live run answers `34 graphs ... 0 missing attrs`, and it EXITS 0. A gate that passes on a false
claim is worse than a gate that fails on a true one, because it is TRUSTED. So a MOVED row
whose site is a gate is upgraded to `CLAIM-FALSE-IN-PASSING-GATE` by RUNNING THAT GATE and
recording its exit -- the gate's verdict on the very claim its prose makes. `--gates` (default
ON) does it; a gate that needs `bend` or overruns the watchdog is `SKIP`, never a pass.

ONE PRECONDITION, AND IT IS THE ONE THIS TREE RECORDED A RETRACTION FOR
-----------------------------------------------------------------------
`AGENTS.md`: "NEVER READ OR QUITE AN ARTIFACT WHILE A RUN IS IN FLIGHT ... `elf.bend` ONCE READ
`246` ROWS FROM AN IN-FLIGHT RUN AND THAT NUMBER HAD TO BE PULLED." MEASURED on this tree while
writing this file: at 2026-10-18T17:31:40Z a `bend` child was live (pid 48775, `graphcmp.bend
move`, etime 00:01) AND `runs/graphcmp/D/D0-run-summary.txt` carried
`substrate-start=9528bb5e...` != `substrate-end=a842e832...`, which is the run's own record that
the substrate MOVED UNDER IT. Every measurer whose artifact lives under `runs/` therefore
REFUSES while any `bend` process is live. `SKIP IS NOT PASS` and `REFUSED` is not `PASS`.

THE TABLE IS A GENERATOR'S OWN DECLARATION AND HOLDS NO FIGURE
--------------------------------------------------------------
`MEASURERS` below is `(probe, population_text, argv)` -- never an expected value. Each `argv` is
a COMMAND that prints `population=` and `value=`, so the figures are re-derived on every run.
`--plan` prints the whole table to prove it: every contract row is a command. A table holding an
expected figure would be a second copy of the prose with no generator, which is
`checks/sweep.py`'s removed `LIVE_UNITS`, `gates/gates-pop.py`'s admitted `HOMES`, and the
second `differ.declared()` that `checks/no-txt.py` refused.

THE PROSE POPULATION IS A WALK, LOADED BY PATH FROM THE FILE THAT ALREADY OWNS IT
----------------------------------------------------------------------------------
`walk()` is imported from `gates/docnum-census.py` BY PATH (`importlib`, the same shape as
`gates/assertlit-census.py:122` and `gates/allcopies-census.py:167`). A second `PRUNE_DIRS` /
`PROSE_EXT` pair written here would be `AGENTS.md` doctrine 1's seventh member: a hand list
where a walk belongs, which cannot see a home it did not think of. If that file is absent the
gate REFUSES rather than falling back to a population of its own inventing.

THE TABLE IS NOT BYTE-REPRODUCIBLE, AND THE HEADER NO LONGER CLAIMS IT IS
---------------------------------------------------------------------------
MEASURED on this file, twice, ninety seconds apart: the two tables DIFFER, and the delta is
entirely in the two UNDECLARED counters (`16492/16459` against `16501/16468`) while **all 36
verdict rows were byte-identical**. The cause is the tree, not the census: `AGENTS.md` records
that `.agents/TODO.md` is touched by 61 of 131 commits and `.agents/TODO.md` grew by 9 claims
during the interval. `AGENTS.md`: "NEVER QUOTE A ROW COUNT WITHOUT THE RULE THAT PRODUCED IT,
AND NEVER QUOTE ONE FROM A JOB THAT MAY STILL BE RUNNING" -- and a census of prose is a job
over a tree other agents are writing.

So the honest statement is the one the header makes: the CHECKED rows are reproducible and the
UNDECLARED COUNTERS ARE NOT, AND THAT IS A PROPERTY OF THE POPULATION, NOT A BUG IN THE WALK.
A previous revision of this file's own help text called the table "byte-reproducible" with no
measurement behind it, which is the exact line `AGENTS.md`'s preamble says to delete.

EXIT, AND WHY IT IS `gatekit`'s AND NOT A SIXTH NUMBER
------------------------------------------------------
`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` and `UNASKABLE` are IMPORTED from
`gates/gatekit.py`, never re-spelled. The order is argued in `worst()`: `DEAD` first (a census
that measured nothing cannot be outranked by one that measured something), then `REFUSED`
(a precondition was absent), then `FAIL` (an answer WAS produced and it was wrong), then
`SKIP`, then `PASS`. A zero-denominator census is `DEAD`, never `PASS`: "0 stale over 0 claims
checked" is indistinguishable from agreement, which is what
`.agents/slop/rebase-gate-selftest.py:1168-1180`'s six declared states exist to prevent.
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP  # noqa: E402

PY = ".venv/bin/python"
BOUNDED = "checks/bounded.py"
BOUND_SECONDS = 300
BOUND_MB = 4096

# WHERE THE WALK COMES FROM, AND WHY IT IS NOT RE-SPELLED HERE.
WALK_OWNER = HERE / "docnum-census.py"

# THE SITES IN SCOPE. NOT A POPULATION OF NUMBERS -- it is a set of prose HOMES, and the
# population of CLAIMS is what the walk finds inside them. `AGENTS.md` is a ROOT file, which is
# why the prior art in `gates/docnum-claim-gate.py` (`SITE_ROOTS = ("gates", "checks",
# ".agents")`) misses the densest single source of prose numbers in the tree: it is a
# DIRECTORY walk of three directories and `AGENTS.md` is in none of them.
SCOPE_PREFIXES = ("gates/", "checks/", ".agents/")
SCOPE_NAMES = ("AGENTS.md", "README.md")

# A CLAIM, for the purpose of the undeclared census: a number followed by a word that can serve
# as its unit. This is the SAME `AFTER` shape `docnum-census.py` already applies, and it is
# re-derived here rather than imported so that this file's own admission test is legible.
UNIT_AFTER = re.compile(r"\s*([A-Za-z][A-Za-z'/-]{2,})")
NUMBER = re.compile(r"\d[\d,]*(?:\.\d+)?")

# ONE COMMAND, THREE PROBES. The pin ledger's `204/230` and its `230 vendored blobs` are the
# SAME population counted two ways, so they share one command rather than restating `git
# ls-tree` three times -- `AGENTS.md`: "Shareable logic should be reused."
PIN_POP_CMD = [PY, "-c",
               "import subprocess;ps=[x for x in subprocess.run(['git','ls-tree','-r',"
               "'6c3d401cf324','--name-only'],capture_output=True,text=True).stdout.split() "
               "if x.startswith('tinygrad/')];print('population=%d value=%d'%(len(ps),len(ps)))"]

# THE MEASURERS. (probe_name, probe_regex, which_group_is_THE_figure, population_text, argv, shape)
#
# THE REGEX IS THE POPULATION DECLARATION ON THE PROSE SIDE. It cannot bind a figure without
# also carrying the words that say WHAT it counts, so a probe-bound row is a row whose
# population the prose named. A claim with no such words on its line cannot bind, and lands in
# `POPULATION-NOT-DECLARED`. That is the whole mechanism, and it is why the instrument can
# answer for the half it cannot check.
#
# `group` selects WHICH captured number is the figure being asserted. `70 of 77 enum members`
# asserts 77, so its regex captures both and names the second.
MEASURERS = (
    # `Ops` is an enum whose MEMBERSHIP is the figure, so population == value; it is kept
    # anyway because the row must RECORD the population even when the two coincide.
    ("OPS_ENUM", r"(\d+)\s+enum\s+members", 1, "tinygrad.uop.Ops enum members",
     [PY, "-c", "from tinygrad.uop import Ops; n=len(Ops); "
                "print(f'population={n} value={n}')"], None),
    ("PORT_VARIANTS", r"SAME\s+(\d+)\s+members", 1, "Ops* constructors in tinybendygrad/uop/ops.bend",
     [PY, "-c", "import re;t=open('tinybendygrad/uop/ops.bend').read();"
                "n=len(set(re.findall(r'\\bOps[A-Z][A-Z0-9_]*',t)));"
                "print(f'population={n} value={n}')"], None),
    ("OPS_VARIANTS_77", r"(\d+)\s+(-variant|variant)\b", 1, "Ops* constructors in tinybendygrad/uop/ops.bend",
     [PY, "-c", "import re;t=open('tinybendygrad/uop/ops.bend').read();"
                "n=len(set(re.findall(r'\\bOps[A-Z][A-Z0-9_]*',t)));"
                "print(f'population={n} value={n}')"], None),
    # THE TWO `34`s. Same figure, two populations, and the ONLY thing that tells them apart is
    # the words on the line -- which is why both probes exist and why VALUE-COLLISION exists.
    # THE LOOSE PROBE IS A DEFECT AND IT WAS MEASURED. A first version read `(\d+)\s+graphs\b`
    # and bound 121 rows of which most were `.agents/TODO.md` history -- "16 graphs",
    # "22 graphs", "3 graphs" -- figures about a corpus that WAS 16 and is not now. **A PROBE
    # BINDS ONLY WHEN THE LINE NAMES THE POPULATION**, which is the whole mechanism of this
    # file, so `CORPUS_GRAPHS` requires the corpus word on the same line. The dated readings it
    # used to swallow are not thereby excused: they fall into `POPULATION-NOT-DECLARED`, a
    # named row, which is where a claim whose population the line does not name belongs.
    ("CORPUS_GRAPHS", r"(?=[^.]{0,80}\b(?:corpus|graphcmp))\b(\d+)\s+graphs\b", 1,
     "graphcmp.GRAPHS members",
     [PY, "-c", "import importlib.util;s=importlib.util.spec_from_file_location("
                "'g','.agents/slop/graphcmp.py');m=importlib.util.module_from_spec(s);"
                "s.loader.exec_module(m);n=len(m.GRAPHS);print(f'population={n} value={n}')"], None),
    ("LAW_DECLS", r"the\s+(\d+)\s+`?law`?\s+decls", 1, "LAWS.bend `^law ` declarations",
     ["grep", "-c", "^law ", "tinybendygrad/LAWS.bend"], None),
    ("CORPUS_PLANTS", r"`?graphcmp\.PLANTS`?\s+has\s+(\d+)\s+members", 1, "graphcmp.PLANTS members",
     [PY, "-c", "import importlib.util;s=importlib.util.spec_from_file_location("
                "'g','.agents/slop/graphcmp.py');m=importlib.util.module_from_spec(s);"
                "s.loader.exec_module(m);n=len(m.PLANTS);print(f'population={n} value={n}')"], None),
    # THE PIN LEDGER. Three separate figures, three separate populations, one table row each.
    ("PIN_MATCH_NUM", r"\*\*PIN MATCH\*\*\s*\|\s*\*\*\s*(\d+)\s*/\s*(\d+)\s*\*\*", 1,
     "tinygrad/ paths in git ls-tree -r 6c3d401cf324",
     [PY, "-c", "import subprocess;P='6c3d401cf324';"
                "ps=[x for x in subprocess.run(['git','ls-tree','-r',P,'--name-only'],"
                "capture_output=True,text=True).stdout.split() if x.startswith('tinygrad/')];"
                "n=sum(1 for p in ps if subprocess.run(['git','hash-object',p],"
                "capture_output=True,text=True).stdout.strip()=="
                "subprocess.run(['git','rev-parse',P+':'+p],capture_output=True,text=True)"
                ".stdout.strip());print(f'population={len(ps)} value={n}')"], None),
    ("PIN_MATCH_DEN", r"\*\*PIN MATCH\*\*\s*\|\s*\*\*\s*(\d+)\s*/\s*(\d+)\s*\*\*", 2,
     "tinygrad/ paths in git ls-tree -r 6c3d401cf324", list(PIN_POP_CMD), None),
    ("PIN_PAST", r"(\d+)\s+blobs are past the pin", 1,
     "tinygrad/ paths whose blob differs from the pin",
     [PY, "-c", "import subprocess;P='6c3d401cf324';"
                "ps=[x for x in subprocess.run(['git','ls-tree','-r',P,'--name-only'],"
                "capture_output=True,text=True).stdout.split() if x.startswith('tinygrad/')];"
                "n=sum(1 for p in ps if subprocess.run(['git','hash-object',p],"
                "capture_output=True,text=True).stdout.strip()!="
                "subprocess.run(['git','rev-parse',P+':'+p],capture_output=True,text=True)"
                ".stdout.strip());print(f'population={len(ps)} value={n}')"], None),
    ("PIN_TOTAL_BLOBS", r"(\d+)\s+vendored blobs", 1, "tinygrad/ paths in git ls-tree -r 6c3d401cf324",
     list(PIN_POP_CMD), None),
    # THE PORT DIFFERENTIAL, AND THE TWO FIGURES ITS COMMENTS REST ON.
    ("DIFFER_BYTE_IDENTICAL", r"(\d+)\s+of\s+\d+\s+graphs byte-identical", 1,
     "runs/graphcmp/D/D0-run-summary.txt byte-identical",
     [PY, "-c", "import sys;d=dict(l.strip().split('=',1) for l in "
                "open('runs/graphcmp/D/D0-run-summary.txt') if '=' in l);"
                "print('population=%s value=%s'%(d.get('graphs'),d.get('byte-identical')))"], None),
    ("DIFFER_AGREE", r"`graphs-agree=(\d+)`", 1, "runs/graphcmp/D/D0-run-summary.txt graphs-agree",
     [PY, "-c", "d=dict(l.strip().split('=',1) for l in "
                "open('runs/graphcmp/D/D0-run-summary.txt') if '=' in l);"
                "print('population=%s value=%s'%(d.get('graphs'),d.get('graphs-agree')))"], None),
    ("PINS_TOTAL", r"\b(\d+)\s+of\s+\d+\s+(?:claims|pins)\b|PINS[^.]{0,24}\b(\d+)\s+claims", 2,
     "len(checks/differ.py PINS)",
     [PY, "-c", "import importlib.util,sys;s=importlib.util.spec_from_file_location("
                "'d','checks/differ.py');m=importlib.util.module_from_spec(s);"
                "sys.argv=['differ.py'];s.loader.exec_module(m);n=len(m.PINS);"
                "print(f'population={n} value={n}')"], None),
    # THE CORPUS LANE, AND THE CLAIM ITS OWN GATE PASSES ON. `CORPUS_RAISE` and `CORPUS_READS`
    # are member (iii): `gates/corpuslane-gate.py` asserts both in its own docstring while its
    # own run answers the opposite and exits 0. These three drive the gate and read ITS OWN
    # totals line, which is why they declare a `shape`: the gate prints `0 missing attrs`, not
    # `value=0`, and re-printing that here would be a transcription with a command round it.
    # The denominator `graphs` in that same line is the POPULATION, so every row that binds one
    # of these records it rather than assuming the corpus size.
    ("CORPUS_RAISE", r"\*\*(\d+)\s+of its (\d+)\s+graphs\*\*", 1,
     "graphs of graphcmp.GRAPHS that raised on 2026-10-17",
     [PY, "gates/corpuslane-gate.py"], r"(\d+) graphs \+ .*?(\d+) missing attrs"),
    ("CORPUS_RAISED2", r"\*\*(\d+)\s+raised,\s*(\d+)\s+emitted\*\*", 1,
     "graphs of graphcmp.GRAPHS that raised on 2026-10-17",
     [PY, "gates/corpuslane-gate.py"], r"(\d+) graphs \+ .*?(\d+) missing attrs"),
    ("CORPUS_READS", r"`ParamArg\.size`,\s*(\d+)\s+reads,\s*(\d+)\s+graphs", 1,
     "__getattr__ reads of ParamArg.size over graphcmp.GRAPHS",
     [PY, "gates/corpuslane-gate.py"], r"(\d+) graphs \+ .*?(\d+) missing attrs"),
    ("PROSE_FILES", r"(\d+)\s+prose files", 1, "docnum-census walk over the repo",
     [PY, "gates/docnum-census.py", "--plan"], r"prose files \(.*?\): (\d+)"),
    ("NUMBER_TOKENS", r"NUMBER TOKENS IN PROSE:\s*(\d+)", 1, "docnum-census walk over the repo",
     [PY, "gates/docnum-census.py", "--plan"], r"NUMBER TOKENS IN PROSE: (\d+)"),
)

# MEASURERS WHOSE ARTIFACT LIVES UNDER `runs/`. These are the CONTESTED ones, and the
# precondition below is the whole reason they can be trusted at all.
CONTESTED = ("DIFFER_BYTE_IDENTICAL", "DIFFER_AGREE")

# THE TOKEN A LIVE `bend` PRODUCES, AND WHY THE MATCH IS NOT `bend`: `bin/bend` is a shell
# wrapper whose own command line contains "bend", and a substring match on the process table
# would then count THIS census's own subprocesses.
BEND_PROC = re.compile(r"references/bend/bend2/main\.ts")


def load_walk(root):
    """-> (`docnum-census`'s own `walk`) or (None, reason).

    THE OWNER IS RESOLVED **INSIDE THE ROOT UNDER CENSUS**, NOT AT THIS MODULE'S OWN PATH.
    MEASURED, and it is what this file's own plant caught on its first run: state 6 deletes
    `gates/docnum-census.py` from the synthetic root and asserts the census REFUSES, and it
    reported `walk=OK, rows=5` -- because the loan was being taken from the REAL tree's gate,
    so a root that does not own a walk still got one. **AN INSTRUMENT'S SOURCE AND ITS
    SUBJECT MUST NOT COME FROM TWO PLACES**, which is `checks/repro-paths.py`'s recorded
    defect and `gates/gapcensus-gate.py --plant`'s first `FAILED`, in a third costume. The
    parameter is what makes the loan honest: the population belongs to the tree being
    censused, so the census reads that tree's walk owner or it has no population.

    DOCTRINE 1(a) BY EXECUTION: this tree's governing rule is that a population is a
    generator's own declaration LOADED BY PATH, and the walk of prose files is
    `docnum-census.py`'s to give. Writing a second `PRUNE_DIRS` here would make this file the
    seventh member of the very class it exists to census, so it borrows instead -- and says so
    when the loan cannot be made, because a fallback population invented here would be exactly
    the `LIVE_UNITS` defect wearing a different hat.
    """
    owner = Path(root) / "gates" / WALK_OWNER.name
    if not owner.is_file():
        return None, "NO-SUCH-WALK: %s is not on disk under this root" % WALK_OWNER.name
    spec = importlib.util.spec_from_file_location("_docnum_census_%d" % os.getpid(), owner)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as exc:  # noqa: BLE001 -- a REFUSED loan must be a row, not a traceback
        return None, "WALK-UNLOADABLE: %s: %s" % (WALK_OWNER.name, exc)
    return getattr(mod, "walk", None), "OK"


def bend_live():
    """-> the `argv` of every live `bend` interpreter, so a CONTESTED artifact is refused.

    `ps -Ao args` and a match on `references/bend/bend2/main.ts`. NOT a substring match on
    "bend": the wrapper and this file's own argv both contain it.
    """
    try:
        out = subprocess.run(["ps", "-Ao", "args"], capture_output=True, text=True,
                             timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ["ps-UNAVAILABLE"]
    return [ln.strip() for ln in out.splitlines() if BEND_PROC.search(ln)]


def on_path(exe):
    if os.path.isabs(exe):
        return os.path.isfile(exe)
    return any(os.access(os.path.join(d, exe), os.X_OK)
               for d in os.environ.get("PATH", "").split(":") if d)


def measure(argv, root, shape=None):
    """-> (population, value, token). `token` is the REASON, never a guess.

    A measurer that prints `population=` and `value=` needs no `shape`: that is the census's
    own two-number contract and every inline measurer obeys it. A measurer driving an
    instrument that prints its OWN shape declares a two-group `shape` instead -- that is what
    `gates/corpuslane-gate.py`'s totals line needs, and re-printing it here in the census's
    shape would be a transcription with a command wrapped round it.

    The watchdog is OPTIONAL and its absence must be ABSENT, not silently substituted: a
    watchdog that cannot start and a command that never started both look like "no rows" to a
    reader, and `gates/docnum-claim-gate.py`'s own header records that its first version
    answered `NO-RUN` -- a SKIP-shaped token for a command that never executed.
    """
    exe = argv[0]
    if not (os.path.isabs(exe) or (root / exe).exists() or on_path(exe)):
        return None, None, "NO-SUCH-COMMAND"
    full = list(argv)
    if not os.path.isabs(exe) and (root / BOUNDED).is_file():
        full = [str(root / PY), str(root / BOUNDED), "--seconds", str(BOUND_SECONDS),
                "--mb", str(BOUND_MB), "--"] + full
    try:
        proc = subprocess.run(full, cwd=root, capture_output=True, text=True,
                              timeout=BOUND_SECONDS + 60)
    except (OSError, subprocess.TimeoutExpired):
        return None, None, "NOT-STARTED"
    out = proc.stdout + "\n" + proc.stderr
    # READ THE VERDICT TOKEN, NEVER THE EXIT CODE AND NEVER A SUBSTRING. `AGENTS.md`:
    # "`checks/bounded.py`'s own header records a unit that lost 425 rows by believing the
    # status." MEASURED on this file's first run: EVERY measurer came back `UNMEASURED`
    # because this list contained `MACHINE: **VIOLATED**`, and bounded prints that line --
    # meaning only that THE TIME BOUND IS NOT ATTRIBUTABLE TO THE CHILD -- on a run that
    # answered `WITHIN-LIMITS rc=0` and printed its figure. A substring test on stderr
    # therefore DISCARDED EVERY SUCCESSFUL MEASUREMENT TAKEN WHILE THE MACHINE WAS LOADED,
    # which in this tree is most of the time, and it did so while printing nothing wrong.
    # The four tokens below are the watchdog's OWN verdicts; anything else is prose.
    for kill in ("KILLED-ON-MEMORY", "TIMED-OUT", "NOT-STARTED", "DEAD", "REFUSED"):
        if kill in out:
            return None, None, kill
    if "Traceback (most recent call last)" in out:
        return None, None, "DEAD"
    if shape:
        m = re.search(shape, out)
        if not m:
            return None, None, "NO-NUMBER"
        return int(m.group(1)), int(m.group(2)), "RAN"
    pop = re.search(r"population=(\d+)", out)
    val = re.search(r"value=(\d+)", out)
    if not pop or not val:
        return None, None, "NO-NUMBER"
    return int(pop.group(1)), int(val.group(1)), "RAN"


def prose_files(root):
    """-> (paths in scope, every walked path, pruned ledger). The walk is `docnum-census`'s."""
    walk, token = load_walk(root)
    if walk is None:
        return None, None, None, token, []
    files, pruned = walk(root)
    # THIS FILE EXCLUDES ITSELF, AND THE EXCLUSION IS COUNTED AND PRINTED. MEASURED on the
    # first run: the census found `77` and `34` in `gates/prose-census.py` and reported them as
    # MOVED, because they ARE in this file -- inside the `MEASURERS` patterns and inside the
    # prose explaining the `34` collision. **AN INSTRUMENT THAT READS ITS OWN TABLE FINDS ITS
    # OWN EXAMPLES**, which is the `docnum-census.py` reading of `gates/gapcensus-gate.py`'s
    # plant ("`UP`/`PORT` WERE BOUND AT IMPORT" -- the source and the subject from two places)
    # in a fourth costume. A probe is not a claim, and an exclusion that cannot be seen is an
    # exclusion that cannot be checked, so `self_excluded` is on the header of the table.
    self_excluded = [f for f in files if f.endswith("prose-census.py")]
    scope = [f for f in files
             if (f in SCOPE_NAMES or f.startswith(SCOPE_PREFIXES)) and f not in self_excluded]
    return scope, files, pruned, "OK", self_excluded


def lines_of(scope, root):
    """-> [(file, lineno, line)] for every prose line in scope. The WALK, once.

    THE ADMISSION TEST LIVES IN `census()`, NOT HERE, and that is the whole fix. An earlier
    version of this function decided what a CLAIM was -- "a number followed by a word that can
    be its unit" -- and emitted one entry per admitted token. **THAT ADMISSION TEST COULD NOT
    SEE ITS OWN PROBES**: `34 of 34 graphs byte-identical` has no unit word after the leading
    `34`, so the figure the `DIFFER_BYTE_IDENTICAL` probe names was never admitted and the
    probe was unreachable. A rule that filters before the thing it filters for has been
    implemented is a rule that filters it out.
    """
    for rel in scope:
        try:
            text = (root / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            yield rel, i, line


def bind(line, measurers=None):
    """-> [(probe, figure, population_text, argv, shape, start)] for every probe the line
    satisfies. Empty means UNDECLARED. `start` is the OFFSET of the figure in the line.

    THE OFFSET IS LOAD-BEARING AND ITS ABSENCE WAS A MEASURED DEFECT. The first version
    returned the probe's match and `census()` then bound EVERY number token on that line to
    it, so `AGENTS.md:389` -- one long table row containing `77` five times and `26` once --
    produced eleven `OPS_ENUM` rows, four of which asserted figures the probe never matched.
    **A PROBE BINDS THE FIGURE IT MATCHED, NOT EVERY FIGURE NEAR IT.** The offset is what makes
    that enforceable rather than a intention, and it is also what lets two probes on ONE line
    bind TWO DIFFERENT figures -- which is exactly the `34` collision's shape, and the reason
    a line is allowed to satisfy more than one probe.
    """
    hits = []
    for name, pattern, group, pop_text, argv, shape in (measurers or MEASURERS):
        for m in re.finditer(pattern, line):
            if group <= (m.lastindex or 0):
                hits.append((name, m.group(group).replace(",", ""), pop_text, argv, shape,
                             m.start(group)))
    return hits


def in_scope_site(rel):
    """A site that is a GATE. Member (iii) is only decidable for these."""
    return rel.startswith("gates/") and rel.endswith(("-gate.py", "_census-gate.py", "-census.py"))


def gate_exit(rel, root):
    """-> (exit, verdict word). A gate that needs `bend`, or overruns, is SKIP -- never a pass."""
    path = root / rel
    if not path.is_file() or bend_live():
        return SKIP, "SKIP"
    full = [str(root / PY), str(root / BOUNDED), "--seconds", str(BOUND_SECONDS),
            "--mb", str(BOUND_MB), "--", str(root / PY), rel]
    try:
        proc = subprocess.run(full, cwd=root, capture_output=True, text=True,
                              timeout=BOUND_SECONDS + 60)
    except (OSError, subprocess.TimeoutExpired):
        return SKIP, "SKIP"
    code = proc.returncode
    if code in (0, 1, 3, 4, 5):
        return code, {0: "PASS", 1: "FAIL", 3: "REFUSED", 4: "SKIP", 5: "DEAD"}[code]
    return REFUSED, "REFUSED"


def census(root, run_gates=True, measurers=None):
    """-> (rows, ledger). `rows` is one entry per CLAIM the instrument can speak about.

    `measurers` is a PARAMETER, not a module read, so `--plant` can drive THIS FUNCTION on a
    synthetic contract whose command runs in a temp root with no `.venv`. A plant that reaches
    past the decision into the real table is a plant of the plumbing: `gates/README.md:106`
    records exactly that failure, and `gates/docnum-claim-gate.py` records the first version of
    its own plant comparing two integers it had written itself -- which tests `!=` and nothing
    else.
    """
    table = measurers if measurers is not None else MEASURERS
    scope, walked, pruned, wtoken, selfx = prose_files(root)
    if scope is None:
        # A REFUSED loan is not an empty census, and the difference is the point: `DEAD` means
        # "it ran and emitted nothing", `REFUSED` means "a precondition was absent", and here
        # the absent precondition is a POPULATION. Reporting it as `scope_files: 0` with no
        # marker would make an absent walk indistinguishable from a tree with no prose in it.
        return [], {"walk": wtoken, "scope_files": 0, "walked": 0, "claims": 0,
                    "checked": 0, "undeclared": 0, "collisions": 0, "bend_live": 0,
                    "refused": True, "self_excluded": []}
    live = bend_live()
    rows, checked = [], 0
    cache = {}
    undeclared = {}
    n_claims = 0
    for rel, lineno, line in lines_of(scope, root):
        # A TOKEN IS ADMITTED IF A PROBE BINDS IT **OR** IT CARRIES A UNIT. This ordering is
        # the fix, and the defect it fixes was MEASURED: admission used to require a unit word
        # AFTER the number, so the figure in `34 of 34 graphs byte-identical` -- whose next
        # token is `of`, not a unit -- was never admitted, and the probe that names it could
        # never bind. **THE POPULATION WORDS ARE THE UNIT**, so a probe-bound figure must not
        # have to supply a second one.
        hits = {}
        for name, figure, pop_text, argv, shape, off in bind(line, table):
            hits.setdefault(off, []).append((name, figure, pop_text, argv, shape))
        for m in NUMBER.finditer(line):
            unit = UNIT_AFTER.match(line, m.end())
            bound = hits.get(m.start())
            if bound is None:
                if unit:
                    n_claims += 1
                    undeclared.setdefault((rel, unit.group(1)), 0)
                    undeclared[(rel, unit.group(1))] += 1
                continue
            if bound:
                n_claims += 1
            unit_txt = unit.group(1) if unit else ""
            _d = DATED_ON_LINE.search(line)
            dt = _d.group(0) if _d else ""
            for name, written, pop_text, argv, shape in bound:
                if name in cache:
                    pop, val, token = cache[name]
                else:
                    if name in CONTESTED and live:
                        token, pop, val = "CONTESTED", None, None
                    else:
                        pop, val, token = measure(argv, root, shape)
                    cache[name] = (pop, val, token)
                checked += 1
                if token != "RAN":
                    rows.append({
                        "kind": "POPULATION-NOT-DECLARED" if token == "NO-SUCH-COMMAND" else "UNMEASURED",
                        "file": rel, "line": lineno, "written": written, "unit": unit_txt,
                        "dated": dt,
                        "probe": name, "population": pop_text, "pop_n": "" if pop is None else pop,
                        "measured": "" if val is None else val, "token": token,
                        "site_verdict": "", "cmd": " ".join(argv)})
                    continue
                held = int(written) == val
                kind = "HELD" if held else "MOVED"
                sv = ""
                if not held and run_gates and in_scope_site(rel):
                    _, sv = gate_exit(rel, root)
                    if sv == "PASS":
                        kind = "CLAIM-FALSE-IN-PASSING-GATE"
                rows.append({"kind": kind, "file": rel, "line": lineno, "written": written,
                             "unit": unit_txt, "dated": dt, "probe": name, "population": pop_text,
                             "pop_n": pop, "measured": val, "token": token,
                             "site_verdict": sv, "cmd": " ".join(argv)})
    # MEMBER (ii). ONE figure, MORE THAN ONE declared population. Built from the rows, so it
    # cannot be a hand list, and it is the only place in this tree that compares two claims
    # about different populations at all.
    pops = {}
    for r in rows:
        if r["kind"] in ("HELD", "MOVED", "CLAIM-FALSE-IN-PASSING-GATE"):
            pops.setdefault(r["written"], {}).setdefault(r["population"], []).append(r)
    collisions = 0
    for written, bypop in sorted(pops.items()):
        if len(bypop) < 2:
            continue
        collisions += 1
        where = " | ".join("%s (%d site(s))" % (p, len(v)) for p, v in sorted(bypop.items()))
        rows.append({"kind": "VALUE-COLLISION", "file": "", "line": 0, "written": written,
                     "unit": "", "dated": "", "probe": "", "population": where, "pop_n": len(bypop),
                     "measured": "", "token": "RAN", "site_verdict": "",
                     "cmd": "gates/prose-census.py --rows -"})
    ledger = {"walk": wtoken, "scope_files": len(scope), "walked": len(walked or []),
              "pruned": pruned or {}, "claims": n_claims, "checked": checked,
              "undeclared": sum(undeclared.values()), "undeclared_sites": len(undeclared),
              "collisions": collisions, "bend_live": len(live), "refused": False,
              "self_excluded": list(selfx or [])}
    return rows, ledger


def worst(kinds, checked=1):
    """THE ORDER IS A CLAIM. `DEAD` first: a census that measured nothing cannot be outranked
    by one that measured something, because its answer is unknown rather than good. Then
    `REFUSED` -- a precondition was absent -- then `FAIL`, the only state that means an answer
    WAS produced and it was wrong. `UNMEASURED` and `POPULATION-NOT-DECLARED` are the
    `UNASKABLE` family: they measured nothing about the figure and are NOT agreement, so they
    are ranked last and can never make a table of them look green.

    `checked` IS THE ZERO DENOMINATOR GUARD, AND IT IS A PARAMETER BECAUSE IT MUST ALSO HOLD
    FOR AN EMPTY TABLE. MEASURED on this file's own plant, state 7: `census()` over an empty
    tree returns NO ROWS, so the kind set is empty, `worst()` falls through to `"PASS"`, and
    the gate answers PASS having measured NOTHING -- which is
    `.agents/slop/rebase-gate-selftest.py:1168-1180`'s declared state 2 ("EMPTY OUTPUT prints
    no `name=value` row -> 'compared nothing'") reproduced in the aggregate rather than in a
    lane. So the empty table is `DEAD` and the guard is passed in, not inferred from a set the
    caller may have emptied.
    """
    if not kinds and not checked:
        return "DEAD"
    for kind in ("DEAD", "REFUSED", "CLAIM-FALSE-IN-PASSING-GATE", "MOVED", "UNMEASURED",
                 "POPULATION-NOT-DECLARED"):
        if kind in kinds:
            return kind
    return "PASS"


VERDICT_OF = {
    "HELD": PASS, "VALUE-COLLISION": PASS,
    "MOVED": FAIL, "CLAIM-FALSE-IN-PASSING-GATE": FAIL,
    "UNMEASURED": SKIP, "POPULATION-NOT-DECLARED": SKIP,
    "REFUSED": REFUSED, "DEAD": DEAD,
}

COLUMNS = ("kind", "file", "line", "written", "probe", "population", "pop_n", "measured",
           "unit", "dated", "site_verdict", "cmd")
HEADER = ("KIND", "FILE", "LINE", "WRITTEN", "PROBE", "POPULATION", "POP_N", "MEASURED",
          "UNIT", "DATED", "SITE_VERDICT", "CMD")

# DATED IS A COLUMN AND NOT A FIFTH KIND, AND THE REASON IS A REMEDY DIFFERENCE. `docnum-census.py`
# already owns the disposition -- "STALE-BUT-DATED ... NOT A DEFECT", because a dated reading is
# the RECORD of a run that happened -- so this file does not re-derive it, it CARRIES it: a MOVED
# row whose line carries a date is a different claim from one that does not, and a reader who
# cannot see the difference cannot tell a stale ledger from a false current assertion. Making it
# a `kind` would have meant either duplicating that instrument's disposition or silently dropping
# the flag; a column is the honest third thing.
DATED_ON_LINE = re.compile(r"(?:19|20)\d{2}-\d{2}(?:-\d{2})?")


def render(rows, ledger, out):
    """-> the table. One row per claim, and the header carries the FIVE UNITS the numbers are
    in, because a count whose unit the reader will assume differently is not a measurement."""
    out.write("# prose-census -- ONE ROW PER CLAIMED NUMBER, WITH ITS POPULATION\n")
    out.write("# SCOPE        : %d prose file(s) in scope, of %d walked (walk owned by %s: %s)\n"
              % (ledger["scope_files"], ledger["walked"], WALK_OWNER.name, ledger["walk"]))
    out.write("# CLAIMS       : %d number-with-unit token(s); %d probe-bound, %d undeclared\n"
              % (ledger["claims"], ledger["checked"], ledger["undeclared"]))
    out.write("# UNDECLARED   : %d claim(s) at %d (file, unit) site(s) name no population\n"
              % (ledger["undeclared"], ledger["undeclared_sites"]))
    out.write("# BEND LIVE    : %d -- a CONTESTED artifact is REFUSED, never read\n"
              % ledger["bend_live"])
    out.write("# SELF         : excluded %d file(s) -- an instrument must not read its own table\n"
              % len(ledger["self_excluded"]))
    out.write("# UNITS        : POP_N counts the POPULATION; MEASURED is the figure over that\n"
              "#                population; WRITTEN is the figure as the prose states it.\n")
    out.write("\t".join(HEADER) + "\n")
    for r in sorted(rows, key=lambda r: (r["kind"], r["file"], r["line"])):
        out.write("\t".join(str(r[c]) for c in COLUMNS) + "\n")


def plan(out):
    out.write("MEASURERS (a generator's own declaration; NO EXPECTED FIGURE IS TRANSCRIBED)\n")
    for name, pattern, group, pop_text, argv, shape in MEASURERS:
        out.write("  %-24s figure=group%d  pop=%-52s %s\n"
                  % (name, group, pop_text[:52], " ".join(argv)))
    out.write("EVERY CONTRACT ROW IS A COMMAND: %d rows, 0 expected figures\n" % len(MEASURERS))
    out.write("CONTESTED (refused while any `bend` is live): %s\n" % ", ".join(CONTESTED))
    out.write("WALK OWNER (doctrine 1a, loaded by path): %s\n" % WALK_OWNER.name)


def prove(root, rows, ledger, out):
    """The row identity, and it MUST be able to fail. A zero denominator is DEAD, never PASS."""
    bad = []
    if ledger["walk"] != "OK":
        bad.append("the walk could not be loaded: %s" % ledger["walk"])
    if ledger["scope_files"] == 0:
        bad.append("0 prose files in scope")
    if ledger["claims"] == 0:
        bad.append("0 claims admitted")
    if ledger["checked"] == 0:
        bad.append("0 claims probe-bound -- the probes match nothing, which is not agreement")
    if ledger["checked"] + ledger["undeclared"] != ledger["claims"]:
        bad.append("%d checked + %d undeclared != %d claims"
                   % (ledger["checked"], ledger["undeclared"], ledger["claims"]))
    for r in rows:
        if r["kind"] in ("HELD", "MOVED", "CLAIM-FALSE-IN-PASSING-GATE") and r["pop_n"] == "":
            bad.append("row %s:%s carries no measured population" % (r["file"], r["line"]))
    for b in bad:
        out.write("LEAK %s\n" % b)
    out.write("PROVE %s: %d claim(s) = %d checked + %d undeclared; %d row(s); %d leak(s)\n"
              % ("FAIL" if bad else "OK", ledger["claims"], ledger["checked"],
                 ledger["undeclared"], len(rows), len(bad)))
    return bool(bad)


def plant(out):
    """A PLANT THAT MUST FAIL, AND THAT MUST BE ABLE TO FAIL ITS OWN NEGATIVE.

    THE PRIOR ART IS STRICTER THAN IT LOOKS. `gates/gapcensus-gate.py --plant` has FOUR states
    and its own plant FIRST REPORTED `FAILED` because `UP`/`PORT` WERE BOUND AT IMPORT -- the
    same shape as `checks/repro-paths.py`: an instrument's SOURCE and its SUBJECT read from
    two places. And a later unit recorded that A MALFORMED PLANT MADE ITS LANE EMIT NOTHING
    WHILE THE CHECK SCORED IT AS A SUCCESSFUL PLANT. So this plant asserts, in order:

      1. the positive: a prose figure that DISAGREES with its command is MOVED
      2. the negative: a prose figure that AGREES is HELD
      3. the undeclared: a claim with no population words binds no probe
      4. the collision: one figure under two declared populations
      5. THE PLANT'S OWN NEGATIVE: an EMPTY tree yields ZERO rows, and the harness must score
         that as FAIL -- NOT as a green "nothing stale", and NOT as a silent pass.

    Point 5 is the one that matters. A plant that emits nothing while its check reports success
    is the defect this whole file exists for, reproduced inside the plant.
    """
    failures = []

    # THE SYNTHETIC CONTRACT. Its oracle prints `population=9 value=3`, so the three figures
    # below are decidable INDEPENDENTLY of this repo's `.venv`, its `bend`, and its corpus.
    oracle = "print('population=9 value=3')\n"
    # POP_A and POP_B SHARE A VALUE on purpose -- that is the `34` collision's shape -- and
    # the third command does not exist, which is the undeclared/population-not-declared state.
    plant_measurers = (
        ("POP_A", r"population A is (\d+)", 1, "the synthetic population A",
         [sys.executable, "-c", oracle], None),
        ("POP_A_OK", r"population A agrees at (\d+)", 1, "the synthetic population A",
         [sys.executable, "-c", oracle], None),
        ("POP_B", r"population B is also (\d+)", 1, "the synthetic population B",
         [sys.executable, "-c", oracle], None),
        ("POP_ABSENT", r"population C is (\d+)", 1, "the synthetic population C",
         [sys.executable, "-c", "raise SystemExit(3)"], None),
    )

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "gates").mkdir()
        # The walk is LOADED BY PATH from `docnum-census.py`, so the synthetic tree needs its
        # own copy of the owner or `census()` REFUSES -- which is correct, and is state 6.
        (root / "gates" / "docnum-census.py").write_text(
            "import os\n"
            "def walk(root):\n"
            "    out = []\n"
            "    for here, dirs, names in os.walk(root):\n"
            "        dirs[:] = sorted(d for d in dirs)\n"
            "        for n in sorted(names):\n"
            "            if n.endswith(('.md', '.py', '.bend')):\n"
            "                p = os.path.relpath(os.path.join(here, n), root)\n"
            "                out.append(p)\n"
            "    return sorted(out), {}\n", encoding="utf-8")
        (root / "gates" / "synthetic.md").write_text(
            "population A is 7 members\n"          # 7 != 3  -> MOVED
            "population A agrees at 3 members\n"   # 3 == 3  -> HELD
            "population B is also 7 members\n"     # 7 != 3  -> MOVED, and 7 under a 2nd population
            "population C is 3 members\n"         # command exits 3 -> NOT-STARTED -> unmeasured
            "a claim naming no population at all: 55 files\n",  # binds nothing -> UNDECLARED
            encoding="utf-8")

        rows, ledger = census(root, run_gates=False, measurers=plant_measurers)
        kinds = {r["kind"] for r in rows}
        out.write("PLANT rows=%d ledger=%s kinds=%s\n"
                  % (len(rows), {k: ledger[k] for k in ("claims", "checked", "undeclared")},
                     sorted(kinds)))

        # 1 + 2: the census must be able to say BOTH. A gate that can only fail cannot be
        # trusted, and one that can only pass cannot be trusted either.
        if not any(r["kind"] == "MOVED" for r in rows):
            failures.append("a figure that disagrees with its command was not MOVED")
        if not any(r["kind"] == "HELD" for r in rows):
            failures.append("a figure that agrees with its command was not HELD")

        # 3: the claim that names no population must be ADMITTED as undeclared, not dropped.
        if ledger["undeclared"] < 1:
            failures.append("a claim naming no population was not admitted as undeclared")

        # 4: THE COLLISION. One WRITTEN figure, TWO declared populations, built from the rows.
        coll = [r for r in rows if r["kind"] == "VALUE-COLLISION"]
        if not coll:
            failures.append("two populations asserting one figure did not collide")
        else:
            named = coll[0]["population"]
            if "population A" not in named or "population B" not in named:
                failures.append("the collision row does not NAME both populations: %s" % named)

        # 5: a command that cannot run is UNMEASURED, never a pass and never a FAIL.
        if not any(r["kind"] == "UNMEASURED" for r in rows):
            failures.append("a command that exited non-zero was not UNMEASURED")

        # 6: THE REFUSED LOAN. Delete the walk owner and the census must REFUSE rather than
        # invent a population of its own -- a fallback walk written here would be
        # `checks/sweep.py`'s removed `LIVE_UNITS` all over again.
        saved = (root / "gates" / "docnum-census.py").read_text(encoding="utf-8")
        (root / "gates" / "docnum-census.py").unlink()
        rrows, rledger = census(root, run_gates=False, measurers=plant_measurers)
        if rrows or rledger["walk"] == "OK" or not rledger.get("refused"):
            failures.append("with the walk owner absent the census invented a population "
                            "instead of refusing (walk=%s, rows=%d)"
                            % (rledger["walk"], len(rrows)))
        else:
            out.write("PLANT refused-without-walk: %s\n" % rledger["walk"])
        (root / "gates" / "docnum-census.py").write_text(saved, encoding="utf-8")

        # 7. ***THE PLANT'S OWN NEGATIVE.*** An EMPTY tree must yield ZERO rows AND the
        # aggregate must NOT be a green "nothing is stale". A MALFORMED PLANT THAT EMITS
        # NOTHING WHILE ITS CHECK SCORES IT AS A SUCCESSFUL PLANT IS THE DEFECT THIS FILE
        # EXISTS FOR, REPRODUCED INSIDE THE PLANT -- so the empty case is asserted, not
        # assumed.
        with tempfile.TemporaryDirectory() as blank:
            brows, bledger = census(Path(blank), run_gates=False, measurers=plant_measurers)
            empty_worst = worst({r["kind"] for r in brows}, bledger["checked"])
            if brows:
                failures.append("an EMPTY tree produced %d row(s); the census must emit nothing "
                                "on nothing" % len(brows))
            if empty_worst == "PASS":
                failures.append("an EMPTY tree aggregated to PASS -- '0 stale over 0 claims' is "
                                "indistinguishable from agreement and must not be green")
            out.write("PLANT empty: rows=%d worst=%s\n" % (len(brows), empty_worst))

        # 8. AND THE ORDER IS A CLAIM, SO IT IS ASSERTED TOO: a table holding nothing but the
        # unmeasured family must NOT aggregate to PASS.
        if worst({"POPULATION-NOT-DECLARED"}) == "PASS":
            failures.append("a table of nothing but POPULATION-NOT-DECLARED aggregated to PASS")
        if worst({"MOVED", "POPULATION-NOT-DECLARED"}) != "MOVED":
            failures.append("the undeclared family outvoted a real MOVED")

    for f in failures:
        out.write("PLANT-FAIL %s\n" % f)
    out.write("PLANT %s: %d failure(s)\n" % ("FAIL" if failures else "OK", len(failures)))
    return bool(failures)


def plant_live(target, out, probe=None):
    """A PLANT ON THE REAL TREE: one prose number moved from TRUE to FALSE, and the census must
    go RED NAMING IT. Both directions are asserted, so this is the plant's OWN NEGATIVE CASE
    and not a demonstration.

    WHY A MIRROR TREE AND NOT AN EDIT. The grant here is read-only on the tree, and more to the
    point a plant that edits its subject leaves the tree wrong if it dies between the edit and
    the revert. So the mirror SYMLINKS every instrument directory -- `.venv`, `tinygrad`,
    `tinybendygrad`, `.agents`, `checks` -- and REAL-COPIES `gates/`, then plants into the copy.
    The instruments that derive the figures are the real ones; only the PROSE under test is
    synthetic. That is the same split the whole file argues for: a figure is derived by
    something, and the something here is not synthetic.

    WHY IT MUST BE ABLE TO FAIL FIRST. `gates/gapcensus-gate.py --plant`'s first run reported
    `FAILED` for the wrong reason (`UP`/`PORT` bound at import) and a later unit recorded that a
    MALFORMED PLANT EMITTED NOTHING WHILE ITS CHECK SCORED IT A SUCCESSFUL PLANT. So this
    asserts BOTH halves before it asserts the defect: the UNPLANTED mirror must already be
    clean on that probe, and the PLANTED mirror must be red ON THAT PROBE AND NO OTHER. A plant
    that is red for an unrelated reason proves nothing.
    """
    failures = []
    if not (ROOT / target).is_file():
        out.write("PLANT-LIVE REFUSED: %s is not on disk\n" % target)
        return True
    with tempfile.TemporaryDirectory() as tmp:
        mirror = Path(tmp)
        for d in (".venv", "tinygrad", "tinybendygrad", ".agents", "checks"):
            if (ROOT / d).exists():
                os.symlink(ROOT / d, mirror / d)
        (mirror / "gates").mkdir()
        os.symlink(ROOT / "gates" / "prose-census.py", mirror / "gates" / "prose-census.py")
        real = ROOT / "gates"
        for p in sorted(real.iterdir()):
            if p.name == "prose-census.py":
                continue
            if p.name == "docnum-census.py":
                (mirror / "gates" / p.name).write_bytes(p.read_bytes())
            elif p.is_file():
                (mirror / "gates" / p.name).write_bytes(p.read_bytes())
            else:
                os.symlink(p, mirror / "gates" / p.name)
        for p in sorted(mirror.iterdir()):
            if p.name == "gates":
                continue
            os.unlink(p)
            os.symlink(ROOT / p.name, mirror / p.name)
        # THE ROOT PROSE IS COPIED, NOT SYMLINKED. `AGENTS.md` and `README.md` are in scope
        # (`SCOPE_NAMES`) and one of them is the densest single source of prose numbers in the
        # tree, so a mirror that symlinked them could never plant into them -- and a plant that
        # writes THROUGH a symlink would edit the real file, which is exactly what this mirror
        # exists to avoid.
        for name in SCOPE_NAMES:
            if (ROOT / name).is_file():
                (mirror / name).write_bytes((ROOT / name).read_bytes())

        def verdicts():
            rows, ledger = census(mirror, run_gates=False)
            return rows, ledger, worst({r["kind"] for r in rows}, ledger["checked"])

        clean_rows, clean_ledger, clean = verdicts()
        planted = [r for r in clean_rows if r["file"] == target and r["probe"] == probe]
        if not planted:
            out.write("PLANT-LIVE REFUSED: %s carries no probe-bound claim on probe %s; a "
                      "plant on a claim the census cannot see proves nothing\n" % (target, probe))
            return True
        written, measured = int(planted[0]["written"]), int(planted[0]["measured"])
        before = [(r["written"], r["measured"], r["kind"]) for r in planted]
        out.write("PLANT-LIVE clean mirror on %s/%s: %s -> verdict %s\n"
                  % (target, probe, before, clean))
        if any(k in ("MOVED", "CLAIM-FALSE-IN-PASSING-GATE") for _, _, k in before):
            failures.append("the UNPLANTED mirror was already stale on %s/%s, so the plant "
                            "would prove nothing" % (target, probe))

        # MOVE THE FIGURE FROM WHAT THE INSTRUMENT DERIVES TO ANYTHING ELSE. The false value is
        # DERIVED (one more than measured), never chosen, so this plant cannot accidentally
        # agree with a second stale figure.
        dest = mirror / target
        false = str(measured + 1)
        text = dest.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines(keepends=True)
        ln = planted[0]["line"]
        if str(written) not in lines[ln - 1]:
            failures.append("line %d no longer carries the figure %s" % (ln, written))
        else:
            lines[ln - 1] = lines[ln - 1].replace(str(written), false, 1)
            dest.write_text("".join(lines), encoding="utf-8")
        dirty_rows, dirty_ledger, dirty = verdicts()
        out.write("PLANT-LIVE planted %s -> %s at %s:%d\n" % (written, false, target, ln))
        named = [r for r in dirty_rows
                 if r["file"] == target and r["probe"] == probe and r["kind"] == "MOVED"
                 and r["written"] == false]
        out.write("PLANT-LIVE dirty mirror: verdict %s; %d MOVED row(s) naming %s\n"
                  % (dirty, len(named), target))
        if not named:
            failures.append("the census did not go red naming the planted figure at %s:%d"
                            % (target, ln))
        # THE VERDICT MOVES **FOR THAT PROBE**, NOT FOR THE TREE. MEASURED on this plant's
        # first run: it asserted `dirty == clean` and reported `the verdict did not move from
        # MOVED` -- while the census had in fact caught the planted figure perfectly. The
        # mirror was ALREADY `MOVED` on five other probes (`OPS_ENUM`, `PORT_VARIANTS`,
        # `CORPUS_RAISE`, ...), so a tree-wide verdict cannot move and the assertion could
        # never pass on a tree that is not already perfect. **A PLANT ON A DIRTY TREE MUST BE
        # ASSERTED LOCALLY**, or it can only ever be run on a clean tree -- which is to say it
        # could never be run at all.
        after = [r["kind"] for r in dirty_rows if r["file"] == target and r["probe"] == probe]
        if after and after[0] != "MOVED":
            failures.append("probe %s on %s read %s after the plant and not MOVED"
                            % (probe, target, after[0]))
        if after and before[0][2] == "MOVED":
            failures.append("probe %s was already MOVED on %s before the plant"
                            % (probe, target))
        others = {r["probe"] for r in dirty_rows if r["kind"] == "MOVED"} - {probe}
        if others:
            out.write("PLANT-LIVE note: %d other probe(s) also stale on this mirror: %s\n"
                      % (len(others), ", ".join(sorted(others))))
    for f in failures:
        out.write("PLANT-LIVE-FAIL %s\n" % f)
    out.write("PLANT-LIVE %s: %d failure(s)\n" % ("FAIL" if failures else "OK", len(failures)))
    return bool(failures)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--plan", action="store_true", help="print the contract, run nothing")
    ap.add_argument("--rows", metavar="OUT",
                    help="write the table to OUT ('-' for stdout)")
    ap.add_argument("--prove", action="store_true", help="assert the row identity")
    ap.add_argument("--plant", action="store_true", help="a synthetic tree that must be able to fail")
    ap.add_argument("--plant-live", metavar="FILE", nargs="?", const="gates/tn_minimum-gate.py",
                    help="plant a false figure in a MIRROR of the real tree and assert it goes red")
    ap.add_argument("--probe", default="PORT_VARIANTS",
                    help="the probe --plant-live perturbs")
    ap.add_argument("--no-gates", action="store_true",
                    help="do not run a MOVED site's gate (skips member iii)")
    ap.add_argument("--strict", action="store_true", help="a VALUE-COLLISION is blocking")
    args = ap.parse_args(argv)

    if args.plan:
        plan(sys.stdout)
        return PASS
    if args.plant:
        return FAIL if plant(sys.stdout) else PASS
    if args.plant_live:
        return FAIL if plant_live(args.plant_live, sys.stdout, args.probe) else PASS

    rows, ledger = census(ROOT, run_gates=not args.no_gates)
    kinds = {r["kind"] for r in rows}
    if ledger.get("refused") or ledger["walk"] != "OK":
        kinds.add("REFUSED")
    verdict = worst(kinds, ledger["checked"])
    if args.strict and "VALUE-COLLISION" in kinds and verdict == "PASS":
        verdict = "FAIL"

    if args.rows:
        buf = []
        render(rows, ledger, _Sink(buf))
        text = "".join(buf)
        if args.rows == "-":
            sys.stdout.write(text)
        else:
            Path(args.rows).write_text(text, encoding="utf-8")
    else:
        render(rows, ledger, sys.stdout)

    stale = [r for r in rows if r["kind"] in ("MOVED", "CLAIM-FALSE-IN-PASSING-GATE")]
    sys.stdout.write("prose-census: %s -- %d claim(s), %d checked, %d stale, %d undeclared, "
                     "%d collision(s); %d site gate(s) consulted\n"
                     % (verdict, ledger["claims"], ledger["checked"], len(stale),
                        ledger["undeclared"], ledger["collisions"],
                        len({r["file"] for r in stale if r["site_verdict"]})))
    if not stale:
        sys.stdout.write("NOTHING IS STALE: every probe-bound claim equals its re-derived "
                         "figure. This is a POSITIVE answer, not an absence of rows.\n")
    if args.prove and not prove(ROOT, rows, ledger, sys.stdout):
        return DEAD
    return VERDICT_OF.get(verdict, FAIL)


class _Sink:
    """A list-appendable text sink, so `render` can be reused for a file and for stdout."""

    def __init__(self, buf):
        self.buf = buf

    def write(self, text):
        self.buf.append(text)


if __name__ == "__main__":
    sys.exit(main())