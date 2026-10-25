#!/usr/bin/env python3
"""pin-cite-gate.py -- DOES THE PORT'S DECLARED PIN MATCH WHAT THE PORT'S CITATIONS RESOLVE AT?

    .venv/bin/python gates/pin-cite-gate.py
    .venv/bin/python gates/pin-cite-gate.py --rows OUT.rows
    .venv/bin/python gates/pin-cite-gate.py --no-report
    .venv/bin/python gates/pin-cite-gate.py --tree DIR
    .venv/bin/python gates/pin-cite-gate.py --plant

`--rows OUT.rows` WRITES the rows file and still prints the report. `--no-report` prints
the rows alone. (The header census's `--rows` means "rows alone"; this file separates the
two so that a run that saves its rows also shows the reader its numbers.) `--tree DIR`
judges a COPY of the port tree instead of the live one -- THE PORT TREE IS OWNED BY OTHER
UNITS AND MOVES UNDER THE GATE'S FEET, so a before/after reading taken at two different
moments compares two different trees, and `--tree` freezes ONE.

UPSTREAM IS THE LOCAL REF `refs/remotes/upstream/master`. This file does not fetch.

THE QUESTION, AND WHY IT IS NOT RHETORICAL. The tree declares a pin -- a commit the vendored
`tinygrad/` is *based on* -- and the port's own `.bend` headers cite upstream `file:line`
positions. Those are two claims about one relationship, and they can disagree: the pin says
"we are at revision R" and the headers say "line N of `ops.py` is the thing I am talking
about". If the headers' line numbers are R's, the two agree. If they are an older
revision's, the port mirrors an OLDER upstream than the pin names.

MEASURED 2026-10-21 ON THIS TREE, AND THE ANSWER IS NOT "THE PORT IS BEHIND". A port
mirrors upstream's BEHAVIOUR; it does not have to mirror upstream's LINE NUMBERS. Each
`.bend` file was ported at a time, and its header cites the line numbers as they stood
then. `AGENTS.md` says the shape out loud for a pin: "the pin's job is to compare a file
against that revision, and 'behind HEAD' is what a pin-for-a-past-revision looks like by
construction. This is not staleness." **SO A CITATION THAT RESOLVES AT AN OLDER REVISION
IS A ROW AND NOT A FAILURE.** It is a header pinned to the revision it was written
against. What IS a failure is a claim true at NO upstream revision (a dangling claim), a
claim true only at a revision NEWER than the pin (the port cites content it does not
have), and a declaration whose OUR PIN no longer names the tree that is vendored.

WHAT THIS ADDS TO THE GATES THAT EXIST. `gates/header-census-gate.py` measures the port's
headers and answers "IS THE CITED LINE INSIDE ITS FILE" -- a LINE-IN-RANGE question, and
it says so: "line-in-range, not a claim that the prose was authored there". This file
asks the CONTENT question: does the cited line HOLD what the port's comment says it
holds, at the declared pin and at the revision the citation actually resolves at. Those
are different questions, and a gate that answers one does not answer the other.
`gates/pinned-tree-gate.py` owns the TREE IDENTITY (`HEAD:tinygrad` vs
`refs/remotes/upstream/master:tinygrad`); this file owns the PIN-vs-CITATIONS relation,
which is a different question about a different pair of objects.

THE POPULATION IS DISCOVERED, NOT NAMED. `os.walk` over `tinybendygrad/` plus
`endswith(".bend")`, and the header/citation PARSER IS `gates/header-census-gate.py`'s,
LOADED BY PATH rather than copied -- one parser, one set of rules, one place a rule
changes.

THE CONTENT TEST, AND IT IS A MARKER AND NOT A STOPLIST. The port writes the thing it
means in BACKTICKS -- `` `pm_device_to_var` ``, `` `PI_A` ``, `` `assert` `` -- and that is
a MARKER the port itself supplies, so the claim tokens are discovered, not listed. A
citation HOLDS at a revision when a claim token is a word on the cited line, or names the
construct DECLARED at the cited line (`def X`, `class X`, `X = ...`), or names the
construct a DECORATOR at the cited line decorates, or (for a range) names a construct
whose body spans the cited range. A header line with no backticked token makes no
CHECKABLE content claim, and it is counted and not verdicted -- an unfalsifiable claim is
not a passing claim.

ONE SUBJECT RULE THE HEADER CENSUS CANNOT APPLY, AND IT IS A DEFECT IN THAT GATE. A bare
`:N` is attributed to the header's declared upstream target, but a header line may name a
file of ANOTHER extension -- `tinybendygrad/base.bend` cites `comp.ts:391`, and `comp.ts`
is a TypeScript file in the bend2 reference, not an upstream `.py`. Attributing its `:391`
to `tinygrad/dtype.py` reports a DANGLING line in a file that was never cited, and
reports that header as resolving at an OLDER REVISION for a reason that has nothing to do
with upstream. This file treats a bare cite on a line that names a non-`.py`/non-`.bend`
file as LOCAL-SIDED and takes it out of the upstream population.

THE EXITS ARE `gatekit`'s. `REFUSED` (3) when a precondition was absent -- the upstream
ref, the port tree, the declaration, or the pin record's own derivation. `DEAD` (5) when
no row was emitted. `FAIL` (1) when a lane is red.

===============================================================================
TWO REPAIRS, MEASURED 2026-10-23 ON THIS TREE. NEITHER OF THEM WEAKENS THE GATE.
===============================================================================

THE FIRST READING OF THIS GATE REPORTED 516 CITATIONS THAT HOLD AT NO UPSTREAM REVISION
AND CALLED 29 OF THEM "DANGLING CLAIMS". **MEASURED: 516 OF THOSE ARE THE GATE'S OWN
FALSE POSITIVES, AND THE TWO CAUSES ARE REPAIRABLE.** (The tree has moved since, so the
numbers below are a FRESH reading of a FROZEN tree -- see THE MEASURED READING.)
REPAIR 1 -- THE RANGE IS THE CITED THING, AND THE FIRST LINE IS NOT THE RANGE.
`holds()` tested the claim tokens against `lines[lo-1]` -- the FIRST line of the cited
range -- and against the construct DECLARED at that line. A citation to `file.py:100-104`
cites FIVE LINES, so a citation to a function BODY failed even when the claim is exactly
right. MEASURED: `tinybendygrad/engine/jit.bend:30` cites `jit.py:24-27` and claims
`on_disk`, and `on_disk` is at `tinygrad/engine/jit.py:25` -- INSIDE the cited range and
NOT on its first line (:24 is `def _copy_input(u:UOp) -> UOp:`). MEASURED ON THE FROZEN
TREE: that row is `at_no_revision` BEFORE the repair and `at_pin` AFTER it.
THE REPAIR: the claim tokens are ALSO tested against the WHOLE cited range.
**AND THE EXAMPLE THAT WAS HERE BEFORE IS NOT A PAYOFF ROW, AND IT IS NOT BECAUSE IT IS
WRONG ABOUT UPSTREAM.** `tinybendygrad/codegen/decomp/dtype.bend:73` cites
`dtype.py:100-104` and claims `bool`, `weakint`, `weakfloat`, and upstream's
`tinygrad/dtype.py:100-104` IS the body of `from_py` and DOES name all three -- but the
gate resolves the BARE BASENAME `dtype.py` with the header's declared target's DIRECTORY,
and that header declares `tinygrad/codegen/decomp/dtype.py`, so the gate reads THAT file,
whose :100-104 names none of the three. MEASURED: the row is `ambient_relocated` BEFORE
the repair AND AFTER it -- it was NEVER a false positive, and the ambient class already
carried it.**
**THIS REPAIR IS STRICTLY SAFE IN ONE DIRECTION: it can only turn a FAILURE into a HOLD.
IT CAN NEVER TURN A DANGLING CLAIM INTO A PASS, because a dangling claim's tokens are
NOWHERE in the range -- that is what "dangling" means.**

REPAIR 2 -- A CITATION THAT MAKES NO CLAIM ABOUT THE FILE IT CITES IS COUNTED, NOT
VERDICTED. The gate treated EVERY backticked token as a claim about the cited upstream
file. But a port comment routinely backticks THE PORT'S OWN VOCABULARY -- its own helper
(`l2i_cdiv`), its own class (`Scheduler`), a generic noun (`step`) -- on the same line
that cites an upstream line. MEASURED: `tinybendygrad/codegen/decomp/dtype.bend:138`
cites `dtype.py:65` and backticks `l2i_cdiv` and `step` -- the PORT's own helper and a
generic noun -- and NEITHER occurs in `tinygrad/codegen/decomp/dtype.py` at ANY revision.
MEASURED ON THE FROZEN TREE: that row is `at_no_revision` BEFORE the repair and
`unverifiable` AFTER it.
**AND THE EXAMPLE THAT WAS HERE BEFORE IS NOT AN UNVERIFIABLE ROW EITHER.**
`tinybendygrad/codegen/decomp/dtype.bend:99` cites `dtype.py:225` and backticks
`float_to_fp16`, `float_to_bf16`, `float_to_fp8`, and none of the three is in
`tinygrad/codegen/decomp/dtype.py` -- but all three ARE in the SIBLING
`tinygrad/dtype.py`, so the row is `ambient_relocated` BEFORE the repair AND AFTER it:
the census's directory ambient already carried it, and its `present_in_file` is empty.**
THE REPAIR: a citation is CHECKABLE only if at least ONE of its claim tokens OCCURS in
the cited upstream file at some revision. If none does, the citation makes NO CLAIM about
that file, so it is UNVERIFIABLE, and the gate COUNTS IT AND DOES NOT VERDICT IT -- which
is what this file's own header already said about a header line with no backticked token:
"an unfalsifiable claim is not a passing claim". The class is REPORTED, as
`cite.unverifiable_no_claim_about_the_file`, and the rows that landed in it are PRINTED,
so a reader sees how many became unverifiable rather than silently vanishing.
**THIS REPAIR IS ALSO SAFE IN THE RIGHT DIRECTION, AND THE PROOF IS A SUPERSET: a
GENUINE dangling claim's tokens DO occur in the file -- at a different line -- so the
candidate set is NON-EMPTY, the gate still looks for the line, and it still FAILS.** The
gate's own `--plant` PROVES IT: the `danger-arm` names a token that IS in the file and
cites a line that does not hold it, and it STAYS DANGLING.

THE MEASURED READING, BEFORE AND AFTER, ON ONE FROZEN TREE. The port tree is owned by
other units and MOVES, so both readings were taken on the SAME COPY of the tree, with
`--tree` (the BEFORE reading was taken with a copy of this file that differs ONLY in the
`--tree` plumbing):

    class                                     BEFORE    AFTER
    cite.total                                 2624     2624
    cite.checkable                             1624     1624
    cite.uncheckable_no_claim_token            1000     1000
    cite.at_pin                                 696      760
    cite.only_older_revision                    413      376
    cite.at_no_revision                         515      488
    cite.at_no_revision_dangling                 29       14
    cite.ambient_relocated                        4        4
    cite.unverifiable_no_claim_about_the_file     --      240

**THE GATE STILL FAILS.** It fails on 14 citations, and EVERY ONE OF THE 14 names a token
that DOES occur in the cited file -- so repair 2 rescued NONE of them. The 14 that left the
fail class are the port's own vocabulary, and they are counted as UNVERIFIABLE and
printed with their reason.

THE ROW-LEVEL MOVEMENT, PAIRED BY INDEX -- 2624 rows, the BEFORE gate's OWN five classes,
ONE process and ONE upstream corpus shared by both gates (MEASURED BY
`.agents/slop/pincite-verify/classes.py`):

    only_older_revision  -> at_pin                  50    REPAIR 1
    at_no_revision       -> at_pin                  13    REPAIR 1
    dangling             -> at_pin                   1    REPAIR 1
    at_no_revision       -> only_older_revision     13    REPAIR 1 at an older revision
    at_no_revision       -> unverifiable           226    REPAIR 2
    dangling             -> unverifiable            14    REPAIR 2
    ambient_relocated    -> ambient_relocated        4    THE SAME four rows, before and
                                                             after -- the census's
                                                             directory ambient was ALREADY
                                                             seen and carried them before
                                                             the repair too.

**NOT ONE ROW LEFT THE HOLDING CLASSES, WHICH IS THE PROOF THAT REPAIR 2 CANNOT WEAKEN A
HOLDING CLAIM: `holds()` implies the token is in the file, so a citation that holds is
never unverifiable.** MEASURED: 0 of 2624.

**AND NOT ONE ROW BECAME DANGLING.** The fail class only SHRINKS: a repair may rescue,
never accuse.

**THE SAFETY ARGUMENT IS AN ELEMENTWISE MEASUREMENT AND NOT A SAMPLE.** For EVERY
citation and EVERY revision of the cited file, the pre-repair test and the shipped test
were both evaluated, and the claim `holds_old(rev) ==> holds_new(rev)` was checked
ELEMENTWISE: **0 COUNTEREXAMPLES over 2624 citations**, and the holding-revision set GREW
for 197 of them. `.agents/slop/pincite-verify/proofs.py` is the instrument and it names
the counts. **AND EVERY ONE OF THE 14 SURVIVORS HAS A NON-EMPTY `present_in_file` AND ITS
TOKEN IS NOWHERE IN THE CITED RANGE AT ANY REVISION** -- so neither repair can rescue one
of them, which is the safety property stated as a fact about the population rather than as
an argument.

===============================================================================
THE THIRD CLASS: `upstream_removed`, A TRUE ABSENCE. MEASURED 2026-10-25.
===============================================================================

A CITATION MAY LEGITIMATELY CLAIM THAT UPSTREAM DOES NOT HAVE THE THING. "upstream
DELETED this construct at commit X; the survivors are Y and Z" is a TRUE claim about
upstream, and this file had NO CLASS FOR IT, so it read as `at_no_revision_dangling` --
which is a FALSE reading of a TRUE claim. The class is `upstream_removed`, and it is
defined by EVIDENCE, not by a phrase.

THE SIX CONDITIONS, AND EVERY ONE OF THEM IS NECESSARY. `absence_of()` is the whole of
it, and the reasons it gives are the reasons it refuses.

  1. THE ROW NAMES A REVISION R -- an upstream commit sha it writes, or the pin it
     names. **A ROW THAT NAMES NO REVISION DOES NOT QUALIFY.** "upstream removed this"
     with no revision is a mood, not a checkable claim about upstream.
  2. R IS CONSISTENT WITH THE PIN'S HISTORY -- R is an upstream commit that is an
     ancestor of (or equal to) the pin. **THE MEASUREMENT THAT MAKES THIS PLAIN:** the
     port's headers name **91 distinct hex runs**; **70 are not commits at all**
     (`0xffffffff`, `3.1415926218032836914`), **18 are upstream commits at or before
     the pin**, and **3 are commits of THIS PROJECT** (`80d329a33`, `e853efc4b`,
     `c2a66ea41`) -- so the condition is NOT vacuous, and a sha of this repo's own
     history is not a revision of upstream. The upstream ref's tip IS the pin
     (`5c2bf39d6c4b`), so today every upstream commit is at or before it.
     **A DATED READING: re-derive it with `.agents/slop/absence/measure.py`, because
     the port tree moves and the counts move with it.**
  3. THE CONSTRUCT IS ABSENT AT R -- a claim token of the row does not occur in the
     cited file's content at R.
  4. THE CONSTRUCT WAS PRESENT BEFORE R -- the same token occurred in that file at some
     revision OLDER than R. So upstream really removed it, and the token is an upstream
     construct and not the port's own vocabulary.
  5. THE REMOVAL IS ATTRIBUTABLE -- the commit D at which the file's content changed
     from holding the token to not holding it exists, and D is at or before R. D is
     what the claim is ABOUT, and it is REPORTED.
  6. THE ROW ASSERTS THE ABSENCE -- the port's absence marker is on the citation's own
     line. **THIS IS THE ONE LEXICAL PRECONDITION AND IT IS HERE FOR ONE REASON:** a
     claim that upstream DELETED a construct and a claim that upstream HAS one are the
     SAME SHAPE to every instrument that reads a citation -- a name, a file, a line --
     and no amount of upstream history can tell them apart. Only the row says which one
     it is making. **THE MARKER ALONE QUALIFIES NOTHING.**

THE MARKER IS NECESSARY AND THE EVIDENCE IS SUFFICIENT, AND THE MEASUREMENT SHOWS IT.
**44 citation lines in the port's headers carry an absence marker; the EVIDENCE
selects 2 of them.** The 42 the evidence refuses are the port talking about ITSELF
("`base.bend` has no `File.list`"), about a construct upstream never had ("`cfield` was
never in `tinygrad/runtime/support/c.py`"), or naming no revision at all.

THE TWO ROWS IT NOW CLASSIFIES, AND THEIR EVIDENCE:

  `tinybendygrad/runtime/ops_amd.bend:231` -- "`hashlib.md5` ... NOT IN upstream at this
  pin". `hashlib` and `md5` were REMOVED from `tinygrad/runtime/ops_amd.py` at
  `fa0f9af3b` ("amd: remove rgp markers", #18643) and are absent at the pin.
  `tinybendygrad/runtime/ops_cl.bend:159` -- "upstream's old `OSX_TIMING_RATIO` form is
  GONE at this pin". `OSX_TIMING_RATIO` was REMOVED from `tinygrad/runtime/ops_cl.py` at
  `38cbec532` ("move cl to hcq2", #18872) and is absent at the pin.

THE CLASS CAN GO RED, AND THE PLANT MAKES IT GO RED IN BOTH DIRECTIONS. FOUR ARMS THAT
DIFFER ONLY IN THE TAIL OF ONE LINE: the true absence classifies `upstream_removed`; the
same row naming a revision at which upstream had NOT removed the construct stays
`dangling`; the same row naming NO revision stays `dangling`; and the same row naming
the pin but NOT SAYING that the construct is gone stays `dangling`. **A ROW THAT LOOKS
LIKE AN ABSENCE CLAIM AND DOES NOT HOLD THE PIN'S EVIDENCE STILL FAILS.**

**AND THE CLASS DOES NOT WEAKEN ANY OTHER CLASS.** The new class sits BELOW `at_pin`,
`only_older_revision`, `ambient_relocated` and `unverifiable` in the precedence, so it
can only ever take a row OUT of `dangling` or `at_no_revision`. MEASURED ELEMENTWISE on
one frozen tree, pairing the rows by index: **2547 rows before and after, 2 rows moved
(`dangling -> upstream_removed`), and 0 of `at_pin`, `newest_rev`, `claim`,
`present_in_file` or `explicit` moved on ANY row.**
"""

from __future__ import annotations

import collections
import importlib.util
import re
import shlex
import subprocess
import sys
import tempfile
import traceback
import warnings
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

PORT_REL = "tinybendygrad"
UPSTREAM = "refs/remotes/upstream/master"
DECLARATION = ROOT / ".agents" / "UPSTREAM-PIN.md"

#: A dated record, in the shape `gates/rotclaim-gate.py` reads: `*_RECORD_DATE` and
#: `*_RECORD_DERIVE` are a pair, the command must name a commit, and a second git call
#: reads that commit's date and compares it to the recorded one. `sha256(x) == sha256(x)`
#: CANNOT FAIL; this can, because the date and the object store are different values.
#:
#: THE DERIVE IS BY CONTENT AND NOT BY ASSUMPTION. The pin is the commit whose `tinygrad/`
#: TREE is the tree this repo vendored, and the newest upstream commit that TOUCHED
#: `tinygrad/` is the commit that last changed that content. The tip of `upstream/master`
#: need not be the same commit -- MEASURED, `5c2bf39d6c4b` (a benchmarks commit) does not
#: touch `tinygrad/` at all, and `45fc5ae734a2` is the upstream commit that last did. Both
#: carry the SAME `tinygrad/` tree, `6c91e897`, and the tree is what the port vendored.
#: THE DATE BOUNDS THE DERIVE, so a later upstream commit cannot silently move the record.
PIN_RECORD_DATE = "2026-10-19T22:06:46+08:00"
PIN_RECORD_DERIVE = "git --no-optional-locks log -1 --format=%H refs/remotes/upstream/master -- tinygrad/"

#: The upstream `.py` this header says it is a port of, or "". READ OUT OF THE HEADER by
#: the census's own reader, not remembered.
#: A filename of ANY extension, so the LOCAL-SIDED rule below can see `comp.ts`.
ANY_FILE = re.compile(r"(?<![\w./-])((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z0-9]+)\b")
BACKTICK = re.compile(r"`([^`]+)`")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
#: A backticked span that IS a citation is the citation, not the claim.
CITE_SPAN = re.compile(r":[0-9]+")
#: Python keywords, which are words in a header and name nothing.
KEYWORDS = frozenset("""and as assert async await break class continue def del elif else except
finally for from global if import in is lambda nonlocal not or pass raise return try while
with yield None True False self cls""".split())
#: The row of the declaration that says which sha is THE pin.
OUR_PIN = "OUR PIN"
#: How far, in characters, a backticked name may sit from a citation and still belong to
#: it. A name and the citation it belongs to are usually adjacent ("`dedup`
#: (search.py:89-90)"), and the port also writes a claim and its citation a clause apart
#: ("(`dtype.py:100-104`) returns ONLY `bool`"). A name FARTHER than this from every
#: other citation belongs to none of them.
_NEAREST = 40

#: THE PORT'S ABSENCE MARKERS -- the words it writes when it means "upstream does NOT
#: have this". NECESSARY AND NEVER SUFFICIENT: a marker alone qualifies nothing, and a
#: row whose EVIDENCE does not hold stays red however it is worded.
#:
#: WHY A MARKER IS HERE AT ALL, AND IT IS NOT A HACK. A claim that upstream DELETED a
#: construct and a claim that upstream HAS a construct are the SAME SHAPE to every
#: instrument that reads a citation -- a name, a file, a line -- and the CONTENT cannot
#: tell them apart. A citation to `ops_cl.py:139` whose token is nowhere in that file is
#: a DANGLING claim if the port says "upstream's `OSX_TIMING_RATIO` is at :139" and a
#: TRUE ABSENCE claim if it says "`OSX_TIMING_RATIO` is GONE at this pin". So the
#: DIRECTION has to come from the row, and the TRUTH has to come from upstream's
#: history. The marker says which direction the claim runs; the evidence says whether it
#: is right. The marker is searched on the CITATION'S OWN LINE, because that is the line
#: that makes the claim.
#:
#: MEASURED over the port's header lines, 2026-10-25, by `.agents/slop/absence/
#: measure.py`: 317 header lines carry a marker, and 44 of them also carry a citation.
#: The marker is a PRECONDITION, not the test: it says which DIRECTION the claim runs,
#: and the EVIDENCE says whether it is true.
ABSENCE_MARKER = re.compile(
  r"\bGONE\b|\bDELETED\b|\bREMOVED\b|\bNOT IN\b|\bDOES NOT EXIST\b|\bhas NO\b",
  re.IGNORECASE)
#: A REVISION THE ROW NAMES: an upstream commit sha, in the port's own abbreviation.
REVISION_SHA = re.compile(r"(?<![0-9a-f])([0-9a-f]{7,40})(?![0-9a-f])")
#: THE PORT'S OWN NAME FOR ITS PIN. MEASURED over the port's header lines: "at the pin"
#: 27, "at this pin" 21, "the pin" 5, "the pin's" 14.
PIN_REF = re.compile(r"\b(?:this|the) pin\b", re.IGNORECASE)


def load_census():
  """`gates/header-census-gate.py` BY PATH. ONE parser, so a rule changes in one place."""
  spec = importlib.util.spec_from_file_location("pin_cite_census", HERE / "header-census-gate.py")
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


def git(*args: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks",) + args, cwd=ROOT, capture_output=True, text=True)
  if p.returncode:
    raise RuntimeError(f"git {' '.join(args)}: rc={p.returncode} {p.stderr.strip()}")
  return p.stdout


def git_opt(*args: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks",) + args, cwd=ROOT, capture_output=True, text=True)
  return p.stdout if p.returncode == 0 else ""


def same_instant(a: str, b: str) -> bool:
  def parse(s: str):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc).replace(microsecond=0)
  try:
    return parse(a) == parse(b)
  except ValueError:
    return False


def tree_of(rev: str) -> str:
  return git_opt("rev-parse", "--verify", "--quiet", f"{rev}:tinygrad").strip()


# --------------------------------------------------------------------------- lane P: the pin

def verify_record(date: str, derive: str) -> tuple[str, str, str]:
  """`(state, commit, detail)` for a dated record. A WRONG DATE IS REFUSED."""
  argv = shlex.split(derive)
  if not argv or argv[0] != "git":
    return ("REFUSED", "", "the derivation is not a git command")
  ran = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
  parts = ran.stdout.strip().split()
  commit = parts[0] if parts else ""
  if ran.returncode or not commit:
    return ("REFUSED", "", "the derivation named no commit")
  if git_opt("cat-file", "-t", commit).strip() != "commit":
    return ("REFUSED", "", "the derivation named no commit object")
  when = git_opt("log", "-1", "--format=%aI", commit).strip()
  if not when or not same_instant(when, date):
    return ("REFUSED", "", f"commit date {when or 'absent'} != record date {date}")
  return ("VERIFIED", commit, f"date matches ({when})")


def our_pin_shas(text: str) -> list[str]:
  """The hex runs on the declaration's OUR-PIN row. READ OUT OF THE DECLARATION, by the
  label the declaration itself uses, so a superseded pin elsewhere in the file is not
  mistaken for the pin."""
  out: list[str] = []
  for line in text.splitlines():
    if OUR_PIN not in line:
      continue
    out.extend(re.findall(r"\b[0-9a-f]{7,40}\b", line))
  return out


def declared_pin() -> str:
  """The DECLARATION's OUR PIN -- the commit the vendored `tinygrad/` is based on.

  READ OUT OF THE DECLARATION, not remembered, and CROSS-CHECKED against the pin
  RECORD's own tree: the sha on the OUR-PIN row that carries the pin's `tinygrad/`
  tree. MEASURED 2026-10-25: `5c2bf39d6c4b`, and the upstream ref's tip is the SAME
  commit -- so "the pin" and "the tip of upstream" are one revision today, and the
  class below does not depend on their being the same.
  """
  state, commit, _detail = verify_record(PIN_RECORD_DATE, PIN_RECORD_DERIVE)
  if state != "VERIFIED" or not DECLARATION.is_file():
    return ""
  tree = tree_of(commit)
  for sha in our_pin_shas(DECLARATION.read_text(errors="replace")):
    full = git_opt("rev-parse", "--verify", "--quiet", sha).strip()
    if full and tree_of(full) == tree:
      return full
  return ""


def abbreviation_map(corpus) -> dict[str, list[str]]:
  """`{7-char prefix: [full shas]}` for upstream's whole history, ONCE per corpus.

  THE ROWS NAME SHAS IN ABBREVIATION -- "upstream 9ff6db7b0" -- and the abbreviation
  has to be resolved AGAINST UPSTREAM'S HISTORY AND NOT AGAINST THIS REPO'S OBJECT
  STORE, because a seven-character prefix can name a commit of THIS PROJECT, and a
  commit of this project is not a revision of upstream."""
  m = getattr(corpus, "_abbrev", None)
  if m is None:
    m = {}
    for c in corpus.order:
      m.setdefault(c[:7], []).append(c)
    corpus._abbrev = m
  return m


def upstream_sha(abbrev: str, corpus) -> str:
  """The UPSTREAM commit whose sha starts with `abbrev`, or "" when there is none or
  when the abbreviation is ambiguous."""
  if not abbrev:
    return ""
  hits = [c for c in abbreviation_map(corpus).get(abbrev[:7], []) if c.startswith(abbrev)]
  return hits[0] if len(hits) == 1 else ""


def named_revisions(line: str, corpus, pin: str) -> list[tuple[str, str]]:
  """`(revision, how)` for every revision the row NAMES.

  An upstream commit sha the row writes, or the pin the row names. A hex run that does
  not resolve IN UPSTREAM'S HISTORY is not a revision of upstream and is not named --
  which is how a sha of THIS PROJECT's own history is kept out of the class."""
  out: list[tuple[str, str]] = []
  for m in REVISION_SHA.finditer(line):
    full = upstream_sha(m.group(1), corpus)
    if full:
      out.append((full, "sha"))
  if pin and PIN_REF.search(line):
    out.append((pin, "the pin"))
  return out


# --------------------------------------------------------------------------- lane C: the citations

def claim_tokens(line: str, subject: str) -> list[str]:
  """The identifiers the port put in BACKTICKS, minus the citation spans and the cited
  file's own stem. DISCOVERED BY A MARKER, not listed."""
  stem = set(IDENT.findall(subject))
  out: list[str] = []
  for span in BACKTICK.findall(line):
    if CITE_SPAN.search(span):
      continue
    for t in IDENT.findall(span):
      if len(t) < 3 or t.lower() in KEYWORDS or t in stem:
        continue
      if t not in out:
        out.append(t)
  return out


def window_tokens(line: str, spans: list[tuple[int, int]], i: int) -> list[str]:
  """The claim tokens that belong to citation `i` on a line that carries several.

  A header line often holds SEVERAL citations and SEVERAL backticked names, and a name
  that belongs to a DIFFERENT citation on the same line must not make this one look like
  it holds. **SO A BACKTICKED NAME BELONGS TO THE NEAREST CITATION.** The port writes
  "`l2i_cdiv.abs` (dtype.py:58-61)", and the name belongs to the citation it sits beside,
  not to the one before it. A citation no name is near makes no CHECKABLE claim, and it is
  counted and not verdicted.
  """
  if i >= len(spans):
    return []
  pos = sorted(enumerate(spans), key=lambda t: t[1][0])
  out: list[str] = []
  for m in BACKTICK.finditer(line):
    if CITE_SPAN.search(m.group(1)):
      continue
    if len(pos) > 1:
      gap = min(max(0, s - m.end(), m.start() - e) for j, (s, e) in pos if j != i)
      if gap > _NEAREST:
        continue
    for t in IDENT.findall(m.group(1)):
      if len(t) < 3 or t.lower() in KEYWORDS:
        continue
      if t not in out:
        out.append(t)
  return out


def declared_at(lines: list[str], idx: int) -> str:
  """The name DECLARED on line `idx` (0-based): `def X`, `class X`, or `X = ...`."""
  t = lines[idx].strip()
  m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", t)
  if m:
    return m.group(1)
  m = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", t)
  if m:
    return m.group(1)
  return ""


def decorator_target(lines: list[str], idx: int) -> str:
  """The name a DECORATOR on line `idx` decorates, or ""."""
  if not lines[idx].strip().startswith("@"):
    return ""
  for j in range(idx + 1, min(idx + 6, len(lines))):
    name = declared_at(lines, j)
    if name:
      return name
  return ""


def spans_of(lines: list[str], name: str) -> list[tuple[int, int]]:
  """`(first, last)` line numbers of every `def name`/`class name` block, 1-based."""
  starts: list[tuple[int, int, str]] = []
  for i, raw in enumerate(lines):
    t = raw.strip()
    if not t or t.startswith("#"):
      continue
    m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", t)
    if m:
      starts.append((i + 1, len(raw) - len(raw.lstrip()), m.group(1)))
  out: list[tuple[int, int]] = []
  for start, indent, nm in starts:
    if nm != name:
      continue
    end = len(lines)
    for j in range(start, len(lines)):
      raw = lines[j]
      if not raw.strip() or raw.strip().startswith("#"):
        continue
      if len(raw) - len(raw.lstrip()) <= indent:
        end = j
        break
    out.append((start, end))
  return out


def holds(lines: list[str], lo: int, hi: int, toks: list[str]) -> tuple[bool, str]:
  """Does the citation HOLD at this revision's content? `(ok, why)`.

  REPAIR 1 -- THE RANGE IS THE CITED THING, AND THE FIRST LINE IS NOT THE RANGE. A
  citation to `file.py:100-104` cites FIVE LINES, and the claim tokens are about the
  RANGE. The three checks above are FIRST-LINE-ONLY, so a citation to a function BODY
  failed even when the claim is exactly right: MEASURED, `tinybendygrad/engine/jit.bend:30`
  cites `jit.py:24-27` and claims `on_disk` -- and `on_disk` is at
  `tinygrad/engine/jit.py:25`, inside the range and NOT on its first line. So the claim
  tokens are ALSO tested against the whole cited range.

  THIS REPAIR IS STRICTLY SAFE IN ONE DIRECTION: it can only turn a FAILURE into a HOLD.
  It can never turn a DANGLING claim into a pass, because a dangling claim's tokens are
  NOWHERE in the range -- that is what "dangling" means. MEASURED ELEMENTWISE, over every
  citation and every revision of every cited file: 0 counterexamples, and the
  holding-revision set GREW for 197 of the 2624 citations.
  """
  if not (0 < lo <= len(lines)):
    return (False, f"the file has {len(lines)} lines, the citation is at :{lo}")
  cited = lines[lo - 1]
  for t in toks:
    if re.search(rf"\b{re.escape(t)}\b", cited):
      return (True, f"the cited line names `{t}`")
  name = declared_at(lines, lo - 1)
  if name and name in toks:
    return (True, f"the cited line declares `{name}`")
  deco = decorator_target(lines, lo - 1)
  if deco and deco in toks:
    return (True, f"the cited line decorates `{deco}`")
  if hi > lo:
    for t in toks:
      for start, end in spans_of(lines, t):
        if start <= lo and end >= hi:
          return (True, f"`{t}` spans :{start}-{end}, the cited range is inside it")
    body = "\n".join(lines[lo - 1:hi])
    for t in toks:
      if re.search(rf"\b{re.escape(t)}\b", body):
        return (True, f"the cited range :{lo}-{hi} names `{t}`")
  return (False, f"the cited line is {cited.strip()[:48]!r}")


def file_words(texts) -> set[str]:
  """EVERY identifier that occurs in ANY of these revisions of one upstream file.

  THIS IS THE FILE'S VOCABULARY, and it is what decides whether a citation MAKES A CLAIM
  ABOUT THAT FILE AT ALL. A port comment routinely backticks THE PORT'S OWN NAMES -- its
  own helper (`l2i_cdiv`), its own class (`Scheduler`), a generic noun (`step`) -- on the
  same line that cites an upstream line. Such a citation makes NO claim about the cited
  upstream file, so the gate cannot verdict it: an unfalsifiable claim is not a passing
  claim, and it is not a failing one either. MEASURED, `tinybendygrad/codegen/decomp/
  dtype.bend:138` cites `dtype.py:65` and backticks `l2i_cdiv` and `step` -- the PORT's
  own helper and a generic noun -- and NEITHER occurs in
  `tinygrad/codegen/decomp/dtype.py` at ANY revision. MEASURED ON THE FROZEN TREE: that
  row is `at_no_revision` before the repair and `unverifiable` after it.

  THE WORD SET IS THE SAME ONE `holds()` MATCHES AGAINST, so the two tests agree about
  what "the file names `x`" means: `\b` on both sides, so `src` is not found inside
  `src_dtype` and `foo` IS found inside `foo-bar`.
  """
  out: set[str] = set()
  for t in texts:
    out.update(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", t))
  return out


def batch_blobs(specs: list[str]) -> dict[str, str]:
  """`spec` -> text, for many specs, in ONE `git cat-file --batch`."""
  if not specs:
    return {}
  p = subprocess.run(["git", "--no-optional-locks", "cat-file", "--batch"], cwd=ROOT,
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


# --------------------------------------------------------------------------- the absence class

def absence_of(c: dict, path: str, corpus, pin: str, revs: list[str], gidx: list[int],
               words: list[set[str]]) -> tuple[str, str]:
  """`(evidence, removed_at)` for a citation whose claim may BE an absence, and
  `("", why)` when it is not.

  THE SIX CONDITIONS, AND EVERY ONE OF THEM IS NECESSARY:

  1. THE ROW NAMES A REVISION R.  An upstream commit sha the row writes, or the pin the
     row names.  A row that names no revision does not qualify: "upstream removed
     this" with no revision is a mood, not a checkable claim about upstream.
  2. R IS CONSISTENT WITH THE PIN'S HISTORY.  R is an upstream commit that is an
     ancestor of (or equal to) the pin.  THE PIN SHIPS THE TREE THIS PORT IS BASED ON,
     so a revision the pin does not contain is a revision the port cannot be checked
     against, and a hex run that is not a revision of upstream at all is not a
     revision of anything.
  3. THE CONSTRUCT IS ABSENT AT R.  A claim token of the row does not occur in the
     cited file's content at R.
  4. THE CONSTRUCT WAS PRESENT BEFORE R.  The same token occurred in that file at some
     revision OLDER than R -- so upstream really removed it, and the token is an
     upstream construct rather than the port's own vocabulary.
  5. THE REMOVAL IS ATTRIBUTABLE.  The commit D at which the file's content changed
     from holding the token to not holding it exists, and D is at or before R.  D is
     what the row's claim is ABOUT, and it is reported.
  6. THE ROW ASSERTS THE ABSENCE.  The port's absence marker is on the citation's own
     line.  See `ABSENCE_MARKER` for why the direction has to come from the row.

  A ROW THAT FAILS ANY ONE OF THEM IS NOT IN THE CLASS, AND A ROW THAT IS IN THE
  CLASS IS A ROW THAT WAS NEVER A FALSE CITATION: the claim is TRUE, and it was true
  all along.
  """
  if not ABSENCE_MARKER.search(c["line"]):
    return ("", "the row does not assert an absence")
  named = named_revisions(c["line"], corpus, pin)
  if not named:
    return ("", "the row names no revision of upstream")
  pin_i = corpus.index.get(pin) if pin else None
  why = "the row names no revision of upstream"
  for rev, _how in named:
    ri = corpus.index.get(rev)
    if ri is None:
      why = f"{rev[:12]} is not a revision of upstream"
      continue
    if pin_i is not None and ri < pin_i:
      why = f"{rev[:12]} is NEWER than the pin"
      continue
    # THE FILE'S CONTENT AT `rev`: the newest touching commit that is OLDER THAN OR
    # EQUAL TO `rev`.  The global index counts BACKWARDS from the tip, so "older or
    # equal" is "gi >= ri", and the newest of those is the SMALLEST such gi.
    older_eq = [i for i, gi in enumerate(gidx) if gi >= ri]
    if not older_eq:
      why = f"{path} does not exist at {rev[:12]}"
      continue
    at = min(older_eq, key=lambda i: gidx[i])
    gone = [t for t in c["toks"] if t not in words[at]]
    if not gone:
      why = f"the cited file still holds {','.join(c['toks'])} at {rev[:12]}"
      continue
    # WAS IT THERE BEFORE?  "strictly older" is "gi > ri".
    was = [t for t in gone
           if any(t in words[i] for i, gi in enumerate(gidx) if gi > ri)]
    if not was:
      why = f"{','.join(gone)} was never in {path}"
      continue
    # THE REMOVAL COMMIT: the newest touching commit AT OR OLDER THAN `rev` whose
    # content lacks the token, given that the next-older one's content holds it.
    # `gidx` ASCENDS, so the commits older-or-equal to `rev` are the TAIL of the list
    # and the ones newer than `rev` are its head.
    removed = ""
    for i, gi in enumerate(gidx):
      if gi < ri:
        continue                       # a commit NEWER than the row's revision
      if any(t in words[i] for t in was):
        continue
      if i + 1 < len(gidx) and any(t in words[i + 1] for t in was):
        removed = revs[i]
        break
    if not removed:
      why = "the removal is not attributable to a commit"
      continue
    return (f"`{','.join(was)}` was REMOVED from {path} at {removed[:12]}, and it is "
            f"absent at {rev[:12]}", removed)
  return ("", why)


# --------------------------------------------------------------------------- the census

def local_sided(line: str) -> bool:
  """Does this line name a file that is NEITHER `.py` NOR `.bend`? Then a bare `:N` on it
  is about that file and not about the header's declared upstream target."""
  for m in ANY_FILE.finditer(line):
    if m.group(1).rsplit(".", 1)[-1].lower() not in ("py", "bend"):
      return True
  return False


def line_spans(census, line: str) -> list[tuple[int, int]]:
  """The char spans of every citation on one header line, in the census's own order:
  the EXPLICIT `file.ext:NN` cites first, then the BARE `:NN` ones. The census's
  `citation_claims` emits them in that order too, so the two lists pair up by index."""
  explicit = [m.span() for m in census.CITE_RE.finditer(line)]
  bare = [m.span() for m in census.BARE_RE.finditer(line)
          if not any(a <= m.start() < b for a, b in explicit)]
  return explicit + bare


def collect(census, base: Path) -> tuple[list[dict], list[dict]]:
  """`(upstream citations, local-sided citations)` over the `.bend` tree at `base`."""
  up: list[dict] = []
  local: list[dict] = []
  for p in sorted(census.walk_bend(base / PORT_REL), key=lambda q: str(q.relative_to(base))):
    rel = str(p.relative_to(base))
    body = p.read_text(encoding="utf-8", errors="replace").splitlines()
    first, _last, blk = census.header_block(body)
    if not first:
      continue
    tgt = census.declared_target(blk)
    cites = census.citation_claims(blk, first, rel, tgt)
    up_dir = tgt.rsplit("/", 1)[0] if "/" in tgt else ""
    by_line: dict[int, list[dict]] = collections.defaultdict(list)
    for c in cites:
      by_line[c["at"]].append(c)
    for at, group in by_line.items():
      spans = line_spans(census, body[at - 1])
      for i, c in enumerate(group):
        c["toks"] = window_tokens(c["line"], spans, i) if i < len(spans) else []
        c["span"] = spans[i] if i < len(spans) else (0, 0)
    for c in cites:
      c["prefer_dir"] = up_dir
      if c["kind"] != census.SUBJECT_UPSTREAM:
        continue
      explicit = f"{c['subject']}:{c['lo']}" in c["line"]
      if not explicit and local_sided(c["line"]):
        local.append({"rel": rel, "at": c["at"], "subject": c["subject"], "line": c["line"]})
        continue
      up.append({**c, "explicit": explicit, "target": tgt})
  return (up, local)


def resolve_all(census, up: list[dict], corpus=None, pin: str = "") -> None:
  """Attach the upstream path and the CONTENT-REVISION to every citation.

  `corpus` is the SHARED upstream history. `census.Upstream(UPSTREAM)` costs one
  `git log --format=%H` over the whole upstream history, so a caller that judges many
  trees (the plant) passes ONE corpus in instead of paying for it per tree.
  `pin` is the DECLARATION's OUR PIN, and it is what the absence class measures
  against; without it the class is simply not computed.
  """
  if corpus is None:
    corpus = census.Upstream(UPSTREAM)
  blobs_cache: dict[str, tuple[list[str], dict[str, str], list[int]]] = {}
  words_cache: dict[str, set[str]] = {}

  def blobs_for(path: str) -> tuple[list[str], dict[str, str], list[int]]:
    """`(touching shas newest-first, their blobs, their global indices)`."""
    if path not in blobs_cache:
      corpus.load(path)
      pairs = corpus._steps.get(path) or []
      revs = [corpus.order[gi] for gi, _c in pairs]      # NEWEST FIRST
      gidx = [gi for gi, _c in pairs]
      blobs_cache[path] = (revs, batch_blobs([f"{r}:{path}" for r in revs]), gidx)
    return blobs_cache[path]

  def words_for(path: str) -> set[str]:
    """The file's vocabulary over ITS WHOLE HISTORY. The most permissive reading of
    "does this token occur in the cited file", and so the SAFEST: a token that occurs at
    ANY revision keeps the citation in the verdict population."""
    if path not in words_cache:
      _revs, blobs, _gidx = blobs_for(path)
      words_cache[path] = file_words(blobs.values())
    return words_cache[path]

  def eval_path(path: str, c: dict) -> tuple[str, str, str, str]:
    """`(newest_rev, why, at_pin, pin_why)` for one citation against ONE upstream path."""
    revs, blobs, _gidx = blobs_for(path)
    toks = c["toks"]
    newest, why = "", ""
    for r in revs:
      ok, w = holds(blobs.get(f"{r}:{path}", "").splitlines(), c["lo"], c["hi"], toks)
      if ok:
        newest, why = r, w
        break
    # THE PIN'S OWN CONTENT, which the newest touching commit may predate.
    pin_lines = blobs.get(f"{revs[0]}:{path}", "").splitlines() if revs else []
    ok, w = holds(pin_lines, c["lo"], c["hi"], toks)
    return (newest, why, "HOLDS" if ok else "NO", w)

  by_path: dict[str, list[dict]] = collections.defaultdict(list)
  for c in up:
    c.setdefault("toks", [])
    c["newest_rev"] = ""
    c["why"] = ""
    c["at_pin"] = "NO"
    c["pin_why"] = "the cited upstream file does not resolve"
    c["relocated_to"] = ""
    c["absence"] = ""
    c["absence_removed_at"] = ""
    # REPAIR 2 -- DOES THIS CITATION MAKE A CLAIM ABOUT THE FILE IT CITES? `None` means
    # UNKNOWN: the subject did not resolve to one upstream file, so there is no file to
    # read a vocabulary from, and the citation stays in the verdict population. `False`
    # means the file resolved and NONE of the claim tokens occurs in it anywhere.
    c["claims_the_file"] = None
    c["present"] = []
    path, how = corpus.resolve(c["subject"], history=True, prefer_dir=c.get("prefer_dir", ""))
    c["path"], c["how"] = path, how
    if path:
      by_path[path].append(c)
  for path, cs in by_path.items():
    words = words_for(path)
    revs, blobs, gidx = blobs_for(path)
    per_rev: list[set[str]] = []
    for c in cs:
      c["present"] = [t for t in c["toks"] if t in words]
      c["claims_the_file"] = bool(c["present"])
      c["newest_rev"], c["why"], c["at_pin"], c["pin_why"] = eval_path(path, c)
      # THE ABSENCE CLASS. The per-revision vocabularies are computed ONCE per path and
      # only when a row of that path could ask for them.
      if pin and ABSENCE_MARKER.search(c["line"]):
        if not per_rev:
          per_rev = [file_words([blobs.get(f"{r}:{path}", "")]) for r in revs]
        c["absence"], c["absence_removed_at"] = absence_of(c, path, corpus, pin, revs, gidx,
                                                           per_rev)

  # THE AMBIENT MIS-RESOLUTION, AND IT IS A DEFECT IN THE HEADER CENSUS, NOT IN THE PORT.
  # A bare basename is ambiguous upstream (`dtype.py` is three files) and the census
  # disambiguates it with the header's DECLARED TARGET's directory. That is right for the
  # header's own subject and WRONG for a citation to a DIFFERENT upstream file that
  # happens to share the basename: `tinybendygrad/codegen/decomp/dtype.bend` cites
  # `float_to_fp16` at `dtype.py:225`, and `float_to_fp16` is in the TOP-LEVEL
  # `tinygrad/dtype.py` and NOT in `tinygrad/codegen/decomp/dtype.py` at all. The census
  # therefore reports a DANGLING line in a file the header never cited. THIS ROW NAMES
  # THE CASE, so the defect is visible in the population that has it.
  for c in up:
    if c["newest_rev"] or "/" in c["subject"] or not c["path"]:
      continue
    for cand in corpus.files().get(c["subject"], []):
      if cand == c["path"]:
        continue
      newest, _why, at_pin, _pw = eval_path(cand, c)
      if newest:
        c["relocated_to"] = cand
        break


# --------------------------------------------------------------------------- the plant

def plant() -> int:
  """A plant that can fail, with an unbroken control, on COPIES."""
  try:
    return _plant()
  except Exception:
    print("PLANT FAILED: a crash is not a pass", file=sys.stderr)
    traceback.print_exc()
    return FAIL


def _span_index(lines: list[str]) -> dict[str, list[tuple[int, int]]]:
  """`{name: [(first, last)]}` for every `def name`/`class name` block, ONE pass.

  `spans_of()` answers this for ONE name and rescans the file each time. The plant
  asks about every name in a file, so it asks ONCE."""
  out: dict[str, list[tuple[int, int]]] = {}
  starts: list[tuple[int, int, str]] = []
  for i, raw in enumerate(lines):
    t = raw.strip()
    if not t or t.startswith("#"):
      continue
    m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", t)
    if m:
      starts.append((i + 1, len(raw) - len(raw.lstrip()), m.group(1)))
  for start, indent, nm in starts:
    end = len(lines)
    for j in range(start, len(lines)):
      raw = lines[j]
      if not raw.strip() or raw.strip().startswith("#"):
        continue
      if len(raw) - len(raw.lstrip()) <= indent:
        end = j
        break
    out.setdefault(nm, []).append((start, end))
  return out


def _range_case(lines: list[str], spans: dict[str, list[tuple[int, int]]]) -> tuple[int, int, str] | None:
  """`(lo, hi, token)`: a RANGE whose claim token is on a LATER line of the range.

  THE ARM IS NON-TRIVIAL BY CONSTRUCTION, and the plant asserts it: the token is NOT on
  the range's FIRST line, is not DECLARED there, does not DECORATE it, and no construct
  of that name SPANS the range. So the FIRST-LINE-only test cannot see it and only the
  RANGE test can -- which is exactly what REPAIR 1 buys."""
  for i, raw in enumerate(lines):
    t = raw.strip()
    m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", t)
    if not m:
      continue
    fname = m.group(1)
    indent = len(raw) - len(raw.lstrip())
    body: list[int] = []
    j = i + 1
    while j < len(lines):
      s = lines[j].strip()
      if not s or s.startswith("#"):
        j += 1
        continue
      if len(lines[j]) - len(lines[j].lstrip()) <= indent:
        break
      body.append(j)
      j += 1
    if len(body) < 2:
      continue
    first = body[0]
    for k in body[1:]:
      for ident in re.findall(r"\b[A-Za-z_][A-Za-z0-9_]{2,}\b", lines[k]):
        if ident == fname or ident.lower() in KEYWORDS:
          continue
        if re.search(rf"\b{re.escape(ident)}\b", lines[first]):
          continue
        if any(declared_at(lines, x) == ident for x in range(first, k + 1)):
          continue
        if any(s <= first + 1 and e >= k + 1 for s, e in spans.get(ident, [])):
          continue
        return (first + 1, k + 1, ident)
  return None


def _danger_case(lines: list[str], spans: dict[str, list[tuple[int, int]]]) -> tuple[int, str] | None:
  """`(lo, token)`: a line and a token that occurs ELSEWHERE IN THE FILE but not there.

  THIS IS THE ARM THAT PROVES REPAIR 2 IS SAFE. The token IS in the file, so the
  citation DOES make a claim about that file -- and the claim is FALSE at the cited
  line. The citation must therefore STAY RED after the repair. A repair that rescued it
  would have turned a dangling claim into a pass, and THAT is the failure mode the
  repair must not have."""
  names = sorted(spans)
  for lo in range(1, min(len(lines), 60) + 1):
    for tok in names:
      if len(tok) < 3:
        continue
      if re.search(rf"\b{re.escape(tok)}\b", lines[lo - 1]):
        continue
      if declared_at(lines, lo - 1) == tok:
        continue
      if decorator_target(lines, lo - 1) == tok:
        continue
      if any(s <= lo and e >= lo for s, e in spans.get(tok, [])):
        continue
      return (lo, tok)
  return None


def _removal_case(corpus, path: str) -> tuple[str, str, str] | None:
  """`(token, removed_at, present_at)` -- a construct upstream DELETED from `path`.

  DISCOVERED, NOT NAMED: the corpus's own history is walked for a token that one
  revision holds and the next-older one does not, and that is STILL GONE at the pin.
  The plant must not depend on a name someone remembered."""
  corpus.load(path)
  pairs = corpus._steps.get(path) or []
  revs = [corpus.order[gi] for gi, _c in pairs]
  if len(revs) < 2:
    return None
  blobs = batch_blobs([f"{r}:{path}" for r in revs])
  sets = [file_words([blobs.get(f"{r}:{path}", "")]) for r in revs]
  now = sets[0]
  for i in range(len(revs) - 1):
    for t in sorted(sets[i + 1] - sets[i]):
      if len(t) < 4 or t.lower() in KEYWORDS or not IDENT.fullmatch(t):
        continue
      if t in now:
        continue                      # it came BACK later, so it is not an absence
      return (t, revs[i], revs[i + 1])
  return None


def _line_without(revs: list[str], blobs: dict[str, str], path: str, token: str) -> int:
  """A line number in the pin's content that holds `token` at NO revision.

  THE PLANT'S ABSENCE ARMS CITE A LINE THE TOKEN NEVER SAT ON. A line the token DID
  sit on would resolve the citation at an older revision and the arm would be GREEN
  for the wrong reason -- the wrong reason being "the citation is true", which is not
  what these arms are about."""
  pat = re.compile(rf"\b{re.escape(token)}\b")
  hist = [blobs.get(f"{r}:{path}", "").splitlines() for r in revs]
  if not hist:
    return 0
  for i, line in enumerate(hist[0]):
    if pat.search(line):
      continue
    if any(i < len(h) and pat.search(h[i]) for h in hist):
      continue
    return i + 1
  return 0


def _plant() -> int:
  if not git_opt("rev-parse", "--verify", UPSTREAM):
    print(f"PLANT REFUSED: {UPSTREAM} is absent. This file does not fetch.", file=sys.stderr)
    return REFUSED
  census = load_census()
  corpus = census.Upstream(UPSTREAM)
  # A CITED FILE DISCOVERED FROM THE CORPUS, not remembered. `helpers.py` is seven upstream
  # files, so a basename is a refusal; a full path is not. The file must also DECLARE
  # something, so the claim is about a construct and not about a comment.
  path, lines, decl, name = "", [], None, ""
  for paths in corpus.files().values():
    for cand in paths:
      if not cand.startswith("tinygrad/") or cand.count("/") != 1:
        continue
      body = git("show", f"{UPSTREAM}:{cand}").splitlines()
      if len(body) < 3:
        continue
      at = next((i for i, l in enumerate(body)
                 if re.match(r"(?:def|class)\s+([A-Za-z_]\w*)", l.strip())), None)
      if at is None:
        continue
      path, lines, decl = cand, body, at
      name = re.match(r"(?:def|class)\s+([A-Za-z_]\w*)", body[at].strip()).group(1)
      break
    if path:
      break
  if not path:
    print("PLANT REFUSED: no top-level tinygrad/*.py declares anything", file=sys.stderr)
    return REFUSED
  n = decl + 1
  # THE HALF-LIE'S LINE: a line that does not name the thing and does not declare it.
  off = next((i for i, l in enumerate(lines)
              if i != decl and name not in l and not declared_at(lines, i) and not decorator_target(lines, i)),
             None)
  if off is None:
    print("PLANT REFUSED: no line to move the citation to", file=sys.stderr)
    return REFUSED
  m = off + 1

  spans = _span_index(lines)
  rng = _range_case(lines, spans)
  if rng is None:
    print("PLANT REFUSED: no range whose claim token is on a later line of the range",
          file=sys.stderr)
    return REFUSED
  rlo, rhi, rtok = rng
  danger = _danger_case(lines, spans)
  if danger is None:
    print("PLANT REFUSED: no line with a token that is elsewhere in the file but not there",
          file=sys.stderr)
    return REFUSED
  dlo, dtok = danger
  vocab = "port_only_symbol_9f3a2c"
  if re.search(rf"\b{vocab}\b", "\n".join(lines)):
    print("PLANT REFUSED: the vocabulary arm's name is in the file", file=sys.stderr)
    return REFUSED

  # THE ABSENCE ARM'S SUBJECT: a construct upstream DELETED, DISCOVERED from the
  # corpus's own history. The plant must not depend on a name someone remembered.
  pin = declared_pin()
  if not pin:
    print("PLANT REFUSED: the declaration names no OUR PIN", file=sys.stderr)
    return REFUSED
  rpath, atok, aremoved, apresent = "", "", "", ""
  for paths in corpus.files().values():
    for cand in sorted(paths):
      if not cand.startswith("tinygrad/"):
        continue
      case = _removal_case(corpus, cand)
      if case:
        rpath, (atok, aremoved, apresent) = cand, case
        break
    if rpath:
      break
  if not rpath:
    print("PLANT REFUSED: no upstream file has a construct that was deleted", file=sys.stderr)
    return REFUSED
  corpus.load(rpath)
  _pairs = corpus._steps.get(rpath) or []
  rrevs = [corpus.order[gi] for gi, _c in _pairs]
  rblobs = batch_blobs([f"{r}:{rpath}" for r in rrevs])
  alo = _line_without(rrevs, rblobs, rpath, atok)
  if not alo:
    print("PLANT REFUSED: no line of the deleted construct's file avoids it", file=sys.stderr)
    return REFUSED

  def cite(path: str, token: str, lo: int, hi: int | None = None) -> str:
    span = f"{lo}-{hi}" if hi else f"{lo}"
    return (f"# synthetic -- port of {path}\n"
            f"# the thing is `{token}`, and it is at {path}:{span}.\n")

  def absence_cite(path: str, token: str, lo: int, tail: str) -> str:
    """A header whose claim IS an absence. `tail` carries the revision, or the marker,
    or neither -- and the arms below differ ONLY in the tail."""
    return (f"# synthetic -- port of {path}\n"
            f"# the thing is `{token}`, and it is at {path}:{lo} -- {tail}\n")

  true_src = cite(path, name, n)
  half_src = cite(path, name, m)
  gone_src = cite(path, vocab, n)
  range_src = cite(path, rtok, rlo, rhi)
  vocab_src = cite(path, vocab, dlo)
  danger_src = cite(path, dtok, dlo)
  # THE FOUR ABSENCE ARMS. They differ ONLY in the tail of one line, so the class
  # cannot be decided by anything but that tail.
  absent_true = absence_cite(rpath, atok, alo,
                              f"upstream DELETED `{atok}` at {aremoved}.")
  absent_wrong = absence_cite(rpath, atok, alo,
                               f"upstream DELETED `{atok}` at {apresent}.")
  absent_norev = absence_cite(rpath, atok, alo, f"upstream DELETED `{atok}`.")
  absent_claim = absence_cite(rpath, atok, alo,
                               f"upstream's `{atok}` is there at this pin.")

  def write(root: Path, src: str) -> None:
    dest = root / PORT_REL / "plant.bend"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(src)

  def judge(root: Path) -> tuple[dict[str, list[dict]], list[dict]]:
    cites, _local = collect(census, root)
    resolve_all(census, cites, corpus, pin)
    return (classify(cites), cites)

  with tempfile.TemporaryDirectory(prefix="pin-cite-plant-") as raw:
    td = Path(raw)
    arms = {
        "control": true_src,
        "control-copy": true_src,
        "half-lie": half_src,
        "gone-name": gone_src,
        "range-arm": range_src,
        "range-copy": range_src,
        "vocab-arm": vocab_src,
        "danger-arm": danger_src,
        "danger-copy": danger_src,
        "absence-arm": absent_true,
        "absence-wrong-rev": absent_wrong,
        "absence-no-rev": absent_norev,
        "absence-not-a-claim": absent_claim,
    }
    trees = {k: td / k for k in arms}
    for k, src in arms.items():
      write(trees[k], src)
    for a, b in (("control", "control-copy"), ("range-arm", "range-copy"),
                 ("danger-arm", "danger-copy")):
      if (trees[a] / PORT_REL / "plant.bend").read_bytes() != \
         (trees[b] / PORT_REL / "plant.bend").read_bytes():
        print(f"PLANT FAILED: the {b} is not a byte copy of the {a}", file=sys.stderr)
        return FAIL
    if (trees["half-lie"] / PORT_REL / "plant.bend").read_bytes() == \
       (trees["control"] / PORT_REL / "plant.bend").read_bytes():
      print("PLANT DEAD: the half-lie copy is identical to the control", file=sys.stderr)
      return DEAD
    # THE FOUR ABSENCE ARMS MUST DIFFER ONLY IN THEIR TAIL, or the class could be
    # decided by something other than the tail.
    tails = {k: (trees[k] / PORT_REL / "plant.bend").read_text().splitlines()[-1]
             for k in ("absence-arm", "absence-wrong-rev", "absence-no-rev",
                       "absence-not-a-claim")}
    if len({t.split("-- ")[0] for t in tails.values()}) != 1:
      print("PLANT FAILED: the absence arms differ in more than their tail", file=sys.stderr)
      return FAIL

    judged = {k: judge(trees[k]) for k in arms}
    print(f"PLANT file {path} declares `{name}` at :{n} (local ref, not fetched)")
    print(f"PLANT range arm  : {path}:{rlo}-{rhi} token `{rtok}` -- NOT on the first line")
    print(f"PLANT danger arm : {path}:{dlo} token `{dtok}` -- IS elsewhere in the file")
    print(f"PLANT absence arm: {rpath}:{alo} token `{atok}` -- DELETED at {aremoved[:12]}, "
          f"and STILL PRESENT at {apresent[:12]}")
    for label in arms:
      cls, cs = judged[label]
      for c in cs:
        print(f"PLANT {label:12s} {c['subject']}:{c['lo']} at_pin={c['at_pin']} "
              f"newest={(c['newest_rev'] or 'NONE')[:12]} class={row_class(c):22s} "
              f"present_in_file={','.join(c['present'])!r} -- {c['pin_why']}")

    bad: list[str] = []

    def one(label: str) -> dict:
      cls, cs = judged[label]
      if len(cls["checkable"]) != 1:
        bad.append(f"{label}: expected one checkable citation, got {len(cls['checkable'])}")
        return {}
      return cls["checkable"][0]

    ca, cb = one("control"), one("control-copy")
    ch, cg = one("half-lie"), one("gone-name")
    cr, crc = one("range-arm"), one("range-copy")
    cv = one("vocab-arm")
    cd, cdc = one("danger-arm"), one("danger-copy")
    cat = one("absence-arm")
    cwr = one("absence-wrong-rev")
    cnr = one("absence-no-rev")
    cnc = one("absence-not-a-claim")

    # THE CONTROL AND ITS BYTE COPY.
    if ca and (ca["at_pin"] != "HOLDS" or not ca["newest_rev"]):
      bad.append(f"the control did not hold at the pin: {ca['at_pin']} {ca['pin_why']}")
    if ca and cb and [(c["at_pin"], c["newest_rev"]) for c in (ca,)] != \
       [(c["at_pin"], c["newest_rev"]) for c in (cb,)]:
      bad.append("the unbroken control moved")
    # THE HALF-LIE AND THE GONE-NAME.
    if ch and ch["at_pin"] == "HOLDS":
      bad.append(f"the moved line still holds at the pin: {ch['pin_why']}")
    if cg and (cg["at_pin"] == "HOLDS" or cg["newest_rev"]):
      bad.append(f"a name that exists nowhere was reported as holding: {cg['pin_why']}")
    # REPAIR 1 -- THE RANGE ARM MUST HOLD, AND ITS BYTE COPY MUST HOLD WITH IT.
    if cr and cr["at_pin"] != "HOLDS":
      bad.append(f"the range arm did not hold at the pin: {cr['at_pin']} {cr['pin_why']}")
    if cr and crc and (cr["at_pin"], cr["newest_rev"]) != (crc["at_pin"], crc["newest_rev"]):
      bad.append("the range arm's byte copy moved")
    if cr and re.search(rf"\b{re.escape(rtok)}\b", lines[rlo - 1]):
      bad.append("the range arm is trivial: the token IS on the first line of the range")
    # REPAIR 2 -- THE VOCABULARY ARM MAKES NO CLAIM ABOUT THE FILE, SO IT IS COUNTED
    # AND NOT VERDICTED. IT MUST NOT BE A DANGLING CLAIM.
    if cv and row_class(cv) != "unverifiable":
      bad.append(f"the vocabulary arm was not unverifiable: {row_class(cv)}")
    if cv and cv in judged["vocab-arm"][0]["dangling"]:
      bad.append("the vocabulary arm was reported as a dangling claim")
    # REPAIR 2 IS SAFE -- THE DANGER ARM'S TOKEN IS IN THE FILE AND THE CLAIM IS STILL
    # FALSE, SO IT MUST STILL BE RED.
    if cd and row_class(cd) != "dangling":
      bad.append(f"the danger arm did not stay dangling: {row_class(cd)}")
    if cd and cd["at_pin"] != "NO":
      bad.append(f"the danger arm was reported as holding: {cd['pin_why']}")
    if cd and not cd["present"]:
      bad.append("the danger arm's token is not in the file, so it proves nothing")
    if cd and cdc and (cd["at_pin"], cd["newest_rev"], row_class(cd)) != \
       (cdc["at_pin"], cdc["newest_rev"], row_class(cdc)):
      bad.append("the danger arm's byte copy moved")
    # THE ABSENCE CLASS -- FOUR ARMS THAT DIFFER ONLY IN THEIR TAIL.
    #
    # 1. THE TRUE ABSENCE: the row names the revision at which upstream removed the
    #    construct, and upstream's history confirms it. THE ROW IS NOT A FALSE
    #    CITATION, so it must leave the fail class.
    if cat and row_class(cat) != "upstream_removed":
      bad.append(f"the absence arm was not an absence claim: {row_class(cat)}")
    if cat and cat in judged["absence-arm"][0]["dangling"]:
      bad.append("the absence arm is still reported as a dangling claim")
    if cat and cat["absence_removed_at"] != aremoved:
      bad.append(f"the absence arm's removal commit moved: {cat['absence_removed_at']}")
    # 2. THE WRONG REVISION: the row names a revision at which upstream had NOT
    #    removed the construct. THE EVIDENCE FAILS, so the row must stay RED.
    if cwr and row_class(cwr) == "upstream_removed":
      bad.append("the wrong-revision arm was classified as an absence claim")
    if cwr and row_class(cwr) != "dangling":
      bad.append(f"the wrong-revision arm did not stay red: {row_class(cwr)}")
    if cwr and cwr["at_pin"] != "NO":
      bad.append(f"the wrong-revision arm was reported as holding: {cwr['pin_why']}")
    # 3. NO REVISION: a row that merely mentions a deleted name is not a checkable
    #    claim about upstream, and it must not qualify.
    if cnr and row_class(cnr) == "upstream_removed":
      bad.append("the no-revision arm was classified as an absence claim")
    if cnr and row_class(cnr) != "dangling":
      bad.append(f"the no-revision arm did not stay red: {row_class(cnr)}")
    # 4. NOT AN ABSENCE CLAIM: the row names the pin, and the construct really is
    #    gone at the pin, but the row does not SAY so. THE DIRECTION IS THE ROW'S TO
    #    STATE, so the row must stay red.
    if cnc and row_class(cnc) == "upstream_removed":
      bad.append("a row that is not an absence claim was swept into the class")
    if cnc and row_class(cnc) != "dangling":
      bad.append(f"the not-a-claim arm did not stay red: {row_class(cnc)}")
    if cnc and not cnc["present"]:
      bad.append("the not-a-claim arm's token is not in the file, so it proves nothing")
    # A WRONG DATE ON THE RECORD IS REFUSED.
    fresh = Path(__file__).read_text()
    broken = fresh.replace(f'PIN_RECORD_DATE = "{PIN_RECORD_DATE}"',
                           'PIN_RECORD_DATE = "1999-01-01T00:00:00Z"', 1)
    if broken == fresh:
      print("PLANT DEAD: the date mutation is a no-op", file=sys.stderr)
      return DEAD
    state, _commit, detail = verify_record("1999-01-01T00:00:00Z", PIN_RECORD_DERIVE)
    if state != "REFUSED":
      bad.append(f"a wrong date was not REFUSED: {state} {detail}")
    state, _commit, detail = verify_record(PIN_RECORD_DATE, PIN_RECORD_DERIVE)
    if state != "VERIFIED":
      bad.append(f"the record did not verify: {state} {detail}")
    if bad:
      print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
      return FAIL
    print("PLANT OK: the control holds at the pin, its byte copy holds, the moved line is "
          "seen, a name that exists nowhere is not held, the RANGE arm holds (REPAIR 1), "
          "the vocabulary arm is UNVERIFIABLE (REPAIR 2), the danger arm is STILL DANGLING "
          "(REPAIR 2 did not rescue it), the ABSENCE arm is a TRUE ABSENCE, and the "
          "wrong-revision, no-revision and not-a-claim arms are all STILL DANGLING")
    return PASS


def row_class(c: dict) -> str:
  """The class of ONE citation, by the SAME rules `classify()` applies. The rows file
  carries it, so a reader can see WHICH row went where instead of counting.

  THE ORDER IS A PRECEDENCE AND IT IS NOT AN ARBITRARY ONE. `upstream_removed` sits
  BELOW `at_pin`, `only_older_revision`, `ambient_relocated` and `unverifiable`, so the
  new class can only ever take a row OUT of `dangling` or `at_no_revision`: it can
  never re-label a row another class already holds, and it can never accuse.
  """
  if not c["toks"]:
    return "uncheckable_no_claim_token"
  if c["at_pin"] == "HOLDS":
    return "at_pin"
  if c["newest_rev"]:
    return "only_older_revision"
  if c["relocated_to"]:
    return "ambient_relocated"
  if c.get("claims_the_file") is False:
    return "unverifiable"
  if c.get("absence"):
    return "upstream_removed"
  if c["explicit"] and "/" in c["subject"]:
    return "dangling"
  return "at_no_revision"


def classify(up: list[dict]) -> dict[str, list[dict]]:
  """THE GATE'S CLASSES, as lists. ONE function, so the report and the plant cannot drift.

  `checkable`      a citation that names at least one claim token.
  `uncheckable`    a citation with NO claim token -- counted, not verdicted.
  `at_pin`         holds at the declared pin.
  `only_older`     holds only at a revision older than the pin.
  `removed`        of those: the row's claim IS an absence, and upstream's history
                   confirms it -- the construct is absent at the revision the row names
                   and was present before it. A TRUE claim about upstream, and NOT a
                   false citation.
  `nowhere`        holds at NO upstream revision.
  `relocated`      of those: holds at ANOTHER upstream file with the same basename. A
                   defect in the CENSUS's directory ambient, not in the port.
  `unverifiable`   of those: NO claim token occurs in the cited file at ANY revision, so
                   the citation makes NO claim about that file. Counted, NOT verdicted --
                   an unfalsifiable claim is not a passing claim and not a failing one.
  `dangling`       of those: the subject names ONE upstream file outright, the ambient
                   cannot explain it, and it DOES make a claim about that file. THIS IS
                   THE FAIL CLASS.

  REPAIR 2 MOVES NOTHING OUT OF `nowhere` AND NOTHING OUT OF THE FAIL CLASS EXCEPT THE
  CITATIONS THAT MAKE NO CLAIM. The proof that it cannot rescue a genuine dangling
  claim: a genuine dangling claim's tokens DO occur in the file -- at a different line --
  so `claims_the_file` is True for it, and it stays in `dangling` and stays red.
  """
  checkable = [c for c in up if c["toks"]]
  uncheckable = [c for c in up if not c["toks"]]
  buckets: dict[str, list[dict]] = collections.defaultdict(list)
  for c in checkable:
    buckets[row_class(c)].append(c)
  # THE FAIL CLASS IS THE ONE THE AMBIENT CANNOT REACH. A citation whose subject is a
  # FULL PATH names one upstream file, so the census's directory ambient cannot have
  # pointed it at the wrong one, and a claim that holds at NO upstream revision is a
  # DANGLING CLAIM. A bare basename is not in this class: the ambient may have pointed it
  # at a file the header never meant, and that is a defect in the CENSUS, reported as
  # `cite.ambient_relocated` and not as a defect in the port.
  nowhere = (buckets["ambient_relocated"] + buckets["unverifiable"]
             + buckets["dangling"] + buckets["at_no_revision"])
  return {"checkable": checkable, "uncheckable": uncheckable,
          "at_pin": buckets["at_pin"], "only_older": buckets["only_older_revision"],
          "removed": buckets["upstream_removed"], "nowhere": nowhere,
          "relocated": buckets["ambient_relocated"], "unverifiable": buckets["unverifiable"],
          "dangling": buckets["dangling"]}


# --------------------------------------------------------------------------- main

def main(argv: list[str]) -> int:
  if "--plant" in argv:
    return plant()
  rows_only = "--no-report" in argv
  report_only = "--report" in argv
  rows_out = argv[argv.index("--rows") + 1] if "--rows" in argv else None
  # `--tree DIR` judges a COPY of the port tree instead of the live one. THE PORT TREE
  # IS OWNED BY OTHER UNITS AND MOVES UNDER THE GATE'S FEET, so a before/after reading
  # taken on two different moments compares two different trees. `--tree` freezes ONE.
  tree_root = Path(argv[argv.index("--tree") + 1]).resolve() if "--tree" in argv else ROOT

  port_root = tree_root / PORT_REL
  if not port_root.is_dir():
    print(f"REFUSED  the port tree {port_root} is ABSENT", file=sys.stderr)
    return REFUSED
  if not git_opt("rev-parse", "--verify", UPSTREAM):
    print(f"REFUSED  {UPSTREAM} is ABSENT", file=sys.stderr)
    return REFUSED
  if not DECLARATION.is_file():
    print(f"REFUSED  the declaration {DECLARATION} is ABSENT", file=sys.stderr)
    return REFUSED

  # ---- lane P -----------------------------------------------------------------
  state, pin_commit, detail = verify_record(PIN_RECORD_DATE, PIN_RECORD_DERIVE)
  pin_tree = tree_of(pin_commit) if state == "VERIFIED" else ""
  head_tree = tree_of("HEAD")
  up_tree = tree_of(UPSTREAM)
  decl_text = DECLARATION.read_text(errors="replace")
  decl_shas = our_pin_shas(decl_text)
  if not decl_shas:
    print(f"REFUSED  {DECLARATION.relative_to(ROOT)} declares no OUR PIN", file=sys.stderr)
    return REFUSED
  decl_trees = {s: tree_of(s) for s in decl_shas}
  agreeing = [s for s, t in decl_trees.items() if t and t == pin_tree]
  disagreeing = [s for s, t in decl_trees.items() if t and t != pin_tree]
  unnamed = [s for s, t in decl_trees.items() if not t]

  # ---- lane C -----------------------------------------------------------------
  census = load_census()
  up, local = collect(census, tree_root)
  our_pin = declared_pin()
  resolve_all(census, up, pin=our_pin)
  if not up:
    print("DEAD  no upstream citation was collected", file=sys.stderr)
    return DEAD

  cls = classify(up)
  checkable = cls["checkable"]
  uncheckable = cls["uncheckable"]
  at_pin = cls["at_pin"]
  only_older = cls["only_older"]
  removed = cls["removed"]
  nowhere = cls["nowhere"]
  relocated = cls["relocated"]
  unverifiable = cls["unverifiable"]
  dangling = cls["dangling"]
  revs = collections.Counter(c["newest_rev"][:12] for c in only_older)

  rows = {
    "pin.record_state": state,
    "pin.commit": pin_commit,
    "pin.tree": pin_tree,
    "pin.our_pin": our_pin,
    "head.tinygrad_tree": head_tree,
    "upstream.tinygrad_tree": up_tree,
    "pin.declared_shas": len(decl_shas),
    "pin.declaration_agrees": len(agreeing),
    "pin.declaration_disagrees": len(disagreeing),
    "pin.declaration_unresolvable": len(unnamed),
    "cite.total": len(up),
    "cite.checkable": len(checkable),
    "cite.uncheckable_no_claim_token": len(uncheckable),
    "cite.at_pin": len(at_pin),
    "cite.only_older_revision": len(only_older),
    "cite.at_no_revision": len(nowhere),
    "cite.at_no_revision_dangling": len(dangling),
    "cite.ambient_relocated": len(relocated),
    "cite.unverifiable_no_claim_about_the_file": len(unverifiable),
    "cite.upstream_removed": len(removed),
    "cite.local_sided_excluded": len(local),
    "cite.distinct_older_revisions": len(revs),
  }
  if not rows_only:
    print(f"UPSTREAM   : {UPSTREAM} (local ref, not fetched)")
    print(f"PIN RECORD : {state}  {pin_commit[:12] if pin_commit else '(none)'}  {detail}")
    print(f"           tree {pin_tree[:12] if pin_tree else '(none)'}  "
          f"HEAD {head_tree[:12] if head_tree else '(none)'}  "
          f"upstream {up_tree[:12] if up_tree else '(none)'}")
    print(f"OUR PIN    : {our_pin[:12] if our_pin else '(none)'}  -- the commit the "
          f"vendored tinygrad/ is based on; the absence class measures against it")
    print(f"DECLARATION: {DECLARATION.relative_to(ROOT)} names {len(decl_shas)} sha(s) on its "
          f"OUR PIN row; {len(agreeing)} carry the pin's tree, {len(disagreeing)} carry another, "
          f"{len(unnamed)} name no tinygrad/ tree at all")
    print()
    print("LANE C -- THE PORT'S UPSTREAM CITATIONS, BY CONTENT.")
    print(f"           {len(up)} citations, {len(checkable)} with a checkable claim, "
          f"{len(uncheckable)} without one (counted, not verdicted)")
    print(f"           {len(at_pin):5d} HOLD AT THE DECLARED PIN")
    print(f"           {len(only_older):5d} hold ONLY AT AN OLDER REVISION "
          f"({len(revs)} distinct revisions)")
    print(f"           {len(nowhere):5d} hold AT NO UPSTREAM REVISION "
          f"({len(dangling)} of them name one upstream file outright)")
    print(f"           {len(relocated):5d} of those hold at ANOTHER upstream file with the same "
          f"basename (the census's directory ambient pointed them at the wrong one)")
    print(f"           {len(unverifiable):5d} of those name NO claim token that occurs in the "
          f"cited file at ANY revision (the port's own vocabulary -- counted, not verdicted)")
    print(f"           {len(removed):5d} are TRUE ABSENCES: the row's claim IS the absence, "
          f"and upstream's history confirms it")
    print(f"           {len(local):5d} bare cites taken out of the upstream population "
          f"(they name a file that is not a .py)")
    print()
    print("THE TRUE ABSENCES, the rows whose claim IS that upstream does NOT have the thing:")
    for c in sorted(removed, key=lambda c: (c["rel"], c["at"])):
      print(f"  {c['rel']}:{c['at']}  {c['subject']}:{c['lo']}  -- {c['absence']}")
      print(f"        {c['line'][:110]}")
    print()
    print("THE DANGLING CLAIMS, the ones whose subject names ONE upstream file outright:")
    for c in sorted(dangling, key=lambda c: (c["rel"], c["at"]))[:40]:
      print(f"  {c['rel']}:{c['at']}  {c['subject']}:{c['lo']}  -- {c['pin_why']}")
      print(f"        {c['line'][:110]}")
    if unverifiable:
      print()
      print("THE UNVERIFIABLE CITATIONS, the ones whose claim tokens are NOT IN THE CITED "
            "FILE AT ALL (counted, not verdicted):")
      for c in sorted(unverifiable, key=lambda c: (c["rel"], c["at"]))[:40]:
        print(f"  {c['rel']}:{c['at']}  {c['subject']}:{c['lo']}  tokens={','.join(c['toks'])}")
        print(f"        {c['line'][:110]}")
    print()
    print("THE REVISIONS THE CITATIONS RESOLVE AT, the top twenty:")
    for k, n in revs.most_common(20):
      print(f"  {k}  {n}")

  for k, v in rows.items():
    print(f"{k}={v}")

  if rows_out:
    # THE NEW COLUMNS ARE APPENDED, NOT INSERTED, so a reader of the old rows file
    # keeps every column it had at the index it had it at.
    head = ("rel\tat\tsubject\tlo\thi\texplicit\tat_pin\tnewest_rev\tclaim\t"
            "present_in_file\tclass\tline\tabsence\tabsence_removed_at\n")
    body = []
    for c in up:
      body.append(f"{c['rel']}\t{c['at']}\t{c['subject']}\t{c['lo']}\t{c['hi']}\t"
                  f"{int(c['explicit'])}\t{c['at_pin']}\t{c['newest_rev']}\t"
                  f"{','.join(c['toks'])}\t{','.join(c['present'])}\t{row_class(c)}\t"
                  f"{c['line']}\t{c.get('absence', '')}\t{c.get('absence_removed_at', '')}\n")
    Path(rows_out).write_text(head + "".join(body))
    print(f"ROWS       : {len(up)} -> {rows_out}")

  if report_only:
    print("(REPORT: exit 0 by request; the numbers above are the census, not a verdict)")
    return PASS

  if state != "VERIFIED":
    print(f"# pin-cite-gate: REFUSED -- the pin record does not verify: {detail}")
    return REFUSED
  failed: list[str] = []
  if head_tree != pin_tree:
    failed.append(f"the vendored tree {head_tree[:12]} is not the pin's tree {pin_tree[:12]}")
  if not agreeing:
    failed.append(f"the OUR PIN row of {DECLARATION.relative_to(ROOT)} names no sha whose "
                  f"tinygrad/ tree is the pin's {pin_tree[:12]}")
  if disagreeing:
    failed.append(f"{len(disagreeing)} sha(s) on the OUR PIN row carry a different tinygrad/ "
                  f"tree: {', '.join(s[:12] for s in disagreeing)}")
  if dangling:
    failed.append(f"{len(dangling)} citations name ONE upstream file and hold at NO upstream "
                  f"revision (a dangling claim)")
  if failed:
    print(f"# pin-cite-gate: FAIL -- {'; '.join(failed)}")
    return FAIL
  print("# pin-cite-gate: PASS")
  return PASS

if __name__ == "__main__":
  print(f"# exit vocabulary: {VERDICT}", file=sys.stderr)
  raise SystemExit(main(sys.argv[1:]))
