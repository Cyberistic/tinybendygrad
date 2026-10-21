#!/usr/bin/env python3
"""msgdiff-gate -- REFUSE a commit whose MESSAGE claims a change its DIFF does not witness.

WHAT IT CANNOT SEE, FIRST AND LOUDEST. A gate can only resolve a claim that names something
checkable. THREE of tonight's four bad claims named NOTHING a diff can answer, and this gate
does NOT catch them:

  - a PERCENTAGE with no artefact (the `41%` that was relayed all session and exists in no
    owned surface). A number with no denominator in the tree is not a claim about the tree.
  - a DEAD PID (a `jj` server at `2368` when it was `30543`). A pid is a LIVE MEASUREMENT and
    a commit message is IMMUTABLE, so EVERY pid claim is a claim that becomes false on its
    own. The gate COUNTS pids and never judges one (see PIDS below).
  - an INVENTED CONFIG KEY (`snapshot.auto-track="all()"`, `fsmonitor`) present in no config
    file. "In no file in this repo" is a claim about the filesystem, not about the diff.

It is the same residual `jjreset`'s mass-delete gate states about itself: THAT gate cannot see a
wrong message, and THIS gate cannot see a message that names nothing. They are complements, and
neither is a substitute for the other.

WHAT IT DOES SEE. `00b101574`'s message says, in the `prefixtxt` section:

    "Deleted the superseded oracles259/plants.py after proving oracletxt/plant.py covers it and
     the census output is byte-identical across the deletion."

`git show --stat 00b101574` touches FOUR files (`censusred/run.err`, `censusred/run.out`,
`tn_sin_log2_exp2_rsqrt.bend`, `tensor.bend`), NONE of them a deletion, and
`.agents/slop/oracles259/plants.py` is PRESENT in that commit's tree at the SAME blob
(`e6e31707`) it held in its parent. The message asserts a deletion the diff does not contain.
That is the claim this gate resolves, and the sentence it names is above.

WHY THIS IS A SEPARATE GATE AND NOT AN EXTENSION OF `git-massdelete-gate.py`. That gate's
SUBJECT is the DIFF (does this commit delete more than the tree's measured churn, 500 files /
900000 lines) and its population is `D` entries. This gate's SUBJECT is the MESSAGE and its
population is claim SENTENCES. They share `_git` and `gatekit`'s five exits and NOTHING else.
Folding them into one file would give one commit two subjects and one verdict, which is the
mistake `gates/gendirs.py` exists to name: A GATE THAT CANNOT SAY WHICH OF ITS SUBJECTS FAILED
IS A GATE WHOSE REFUSAL NOBODY CAN ACT ON.

THE CLAIM GRAMMAR, AND WHAT IS DELIBERATELY *NOT* CHECKED. A message names files, counts, and
pids, and they are not equally resolvable:

  CHECKED -- a DELETION ASSERTION: a delete verb and the file path it governs. Resolvable
    against the diff's `D` entries and the commit's tree. This is the `oracles259` shape. A
    claim is WITNESSED if the path is deleted here or absent from this commit's tree; it is
    REFUSED if the path is PRESENT in this commit's tree and NOT deleted by it; and it is
    UNCHECKABLE (counted, passed) if the path names nothing in this commit (a rename leaves no
    `D`, a path may sit outside the repo, a definition inside a file is not a path).
  CHECKED -- an EXPLICIT FILE COUNT: `N files changed|deleted|added|removed|touched`, in either
    order. The count is resolvable ONLY because the message says WHICH noun it counts AND ties it
    to the diff. MEASURED over the commits since 2026-10-06T12:00 (`run.py` re-derives it): ZERO
    such phrases, so this lane is dormant and cannot refuse an honest message -- but it is the
    shape that is checkable.
  NOT CHECKED -- "five units", "19 sites", "53 of 77 arms": a count with no denominator the diff
    holds is UNFALSIFIABLE. `00b101574`'s "the five units that landed" counts UNITS (each unit
    is a set of edits plus a report), not FILES -- the diff is 4 files and that is NOT a
    contradiction. Refusing it would be the failure mode.
  NOT CHECKED -- PIDS. Counted and reported, never judged: a pid is a claim that WILL be false.
    Marking it REFUSED would refuse every honest message that has ever cited a process.
  NOT CHECKED -- a claim the message is DISCUSSING rather than making ("the claim that X was
    deleted IS FALSE", "the predecessor's message was wrong"). A meta-marker in the clause
    (claim/message/said/false/wrong/predecessor/...) demotes it to UNCHECKABLE, because a
    message that REPORTS a defect must not be refused for naming it.

THE FIVE VERDICTS, AS EXITS (`gates/gatekit.py:60`): PASS,FAIL,REFUSED,SKIP,DEAD = 0,1,3,4,5.
REFUSED is exit 3 and NOT FAIL: the gate does not know the message is WRONG, it knows only that
THIS DIFF does not witness it -- a rename, a squashed push, or a sibling commit can all make an
honest message look unwitnessed by one diff. Supply `MESSAGE_DIFF_ACK="<reason>"` (or `--ack`)
and the refusal is recorded and passed.

THE SECOND SUBJECT, `SUBJECT_DIFF_ACK=`, AND WHY THE DOCSTRING ABOVE WAS NOT ENOUGH. Everything
above grades the MESSAGE against the DIFF, and it is therefore structurally blind to a diff the
message says NOTHING about: no claim, nothing to grade, exit 0. MEASURED on the three commits
that carry a sha in the ledger:

    9144d179e25a  removed 110 paths  ->  claim lane PASS (0 checked, 0 uncheckable)
    c83f04ad1c12  removed  66 paths  ->  claim lane PASS (0 checked, 0 uncheckable)
    75ab9b8f8984  removed   4 paths  ->  claim lane PASS (0 checked, 0 uncheckable)

The rule that closes it: **every path the diff REMOVES must be NAMED by the message or
ACKNOWLEDGED by `SUBJECT_DIFF_ACK=`.** It was chosen over a ratio rule because it has no
threshold to choose -- see the long comment above `SUBJECT_RE` for the head-to-head measurement
(allowlist 33 firings of 300 commits since 2026-10-06T00:00; ratio@8 131) and for why
"invisible in a diffstat" is a claim about `D` and not about removals.

THE THIRD SUBJECT: A GATE STEM THE SUBJECT NAMES AND THE DIFF DOES NOT CONTAIN.
`1dac4ab61` says `ledgergone:` and `git show --stat` is `gates/valscall-gate.py`.
Both lanes above PASS it (0 deletion claims, 0 removals) -- measured 2026-10-20T22:02:08Z,
rc=0. A `stem:` claim, or an explicit `gates/<file>.py`, whose stem is
`gates/<stem>-gate.py` or `gates/<stem>.py` in HEAD (discovered, `git ls-tree -r
HEAD`, not a list of these two commits) must be a stem the diff contains.
A diff path contains a named stem when the path's basename, with `-gate`,
`-oracle`, `-mutate`, `-plant`, or a trailing extension removed, equals the
stem. A `.bend` of that stem contains it. A rename still contains it.
`gates/opseven.bend` contains `opseven`. `gates/valscall-gate.py` does not
contain `ledgergone`. Discovery is unchanged: a `.bend` is not a known stem.
A subject that names no such stem is not a failure of this check. A bare word
is prose: any-token matching refuses "the census's banner shape" because
`banner` is a stem, and a blamed innocent is worse than a missed claim.

`stems` walks that check. No arguments means the last 800 (`rev-list -n 800
HEAD`). Any arguments are rev-list arguments, so `-n 50` or `--since=... HEAD`
overrides the default. Each refusal prints the sha, the subject, and the diff
paths. Exit REFUSED if any remain, PASS only if the walk found none. A missing
git object is REFUSED, not a pass: absence is not agreement. The shas it prints
are whatever the walk finds. This file does not list them. `range` is the other
walk — it grades every lane and forwards its arguments unchanged.

Run:  .venv/bin/python gates/msgdiff-gate.py check 00b101574
      .venv/bin/python gates/msgdiff-gate.py range --since=2026-10-06T12:00 HEAD
      .venv/bin/python gates/msgdiff-gate.py stems
      .venv/bin/python gates/msgdiff-gate.py stems -n 50
      .venv/bin/python gates/msgdiff-gate.py --plant
      SUBJECT_DIFF_ACK=".agents/slop/<unit>" .venv/bin/python gates/msgdiff-gate.py check <rev>
"""
import os
import re
import subprocess
import sys
import tempfile
from fnmatch import fnmatch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import PASS, FAIL, REFUSED, SKIP, DEAD  # noqa: E402  the five exits, no sixth

ROOT = Path(__file__).resolve().parents[1]

# A delete VERB, not a delete noun: `deletions` and `deletion` are excluded on purpose, so
# "sees deletions per commit" is not read as an assertion. `retire` is excluded because
# `3c4ceeea3` writes "MOVED, NOT DELETED" and "retire 19" for files it KEPT.
VERB = re.compile(r"(?<![\w./-])(deleted|delete|deletes|deleting|removed|removes|removing"
                  r"|git\s+rm|dropped|drops|dropping)\b(?!\.[A-Za-z0-9])", re.I)
# A path token: ends in one or more known extensions (`elf.bend.mut` is one path, not the file
# `elf.bend`). Requiring an extension keeps a directory (`runs/graphcmp/D`) and a symbolic member
# (`Prog.hex.at`) out, which is the SAFE direction -- an unparsed claim is passed, never refused.
PATH = re.compile(r"[A-Za-z0-9_./{},-]+"
                  r"(?:\.(?:py|bend|md|rows|out|err|tsv|json|txt|sh|mjs|js|ts|tsx|c|h|yaml|yml"
                  r"|toml|lock|bin|png|hex|diff|patch|mut))+")
# A WILDCARD and a DIRECTORY are both declarations `PATH` cannot express, and BOTH occur in
# honest messages in this tree. MEASURED on `9b55d16a4` ("THE LAST FOUR TRACKED STRAY FILES IN
# `tinybendygrad/` ARE REMOVED -- `elf.bend.mut` ... AND 3x `memory.staged-mem-*`"): `PATH`
# matches NEITHER `` `tinybendygrad/` `` (no extension) NOR `memory.staged-mem-*` (`*` is not in
# its character class), so the SUBJECT lane called an HONEST strays-removal undeclared and the
# rule would have refused a message that declared all four paths. A declaration the grammar
# cannot read is not a declaration the author failed to make.
#
# `*` IS THE ONLY METACHARACTER. `?` and `[...]` are NOT added: no message in this population
# uses them, and a glob dialect nobody has exercised is a dialect nobody can check.
GLOB = re.compile(r"[A-Za-z0-9_./{},*-]+")
# A DIRECTORY DECLARATION: a slash-terminated token. `tinybendygrad/` and `runs/graphcmp/D`.
# This is the trailing-slash form only, NOT "any token containing a slash" -- the latter would
# make every message that names one file in a directory declare the whole directory, which is
# the leniency the whole rule is built to avoid.
DIR = re.compile(r"[A-Za-z0-9_.,-]+(?:/[A-Za-z0-9_.,-]+)*/")
# The words a verb's object may sit behind ("Deleted the superseded X"). Anything else -- a
# relative clause (`GUARDED BY`), a conjunction, a comma -- means the verb's object is NOT the
# path that follows, so the claim is unchecked rather than refused. This is the whole defence
# against refusing honest prose.
GAP_STOP = re.compile(r"(?<![\w-])(by|from|and|or|to|is|was|are|were|that|which|not|no"
                      r"|guarded|reads?|named|per|via|using)\b|[,;()]", re.I)
NEGATION = re.compile(r"(?<![\w-])(not|no|never|nothing|nobody|none|isn't|wasn't|weren't"
                      r"|aren't|cannot|can't)\b", re.I)
# A message that REPORTS a claim is not making it. `169ee6ac8` correctly says the predecessor's
# claim that `oracles259/plants.py` was deleted IS FALSE; refusing that would refuse the audit.
META = re.compile(r"(?<![\w-])(claim|claims|claimed|message|messages|said|says|false|falsely"
                  r"|wrong|wrongly|believed|asserted|relayed|reported|predecessor"
                  r"|orchestrator)\b", re.I)
COUNT = re.compile(r"(?:(?P<a>\d+)\s+(?:files?|paths?)\s+(?:changed|deleted|added|removed"
                   r"|touched)\b)|(?:(?:changed|deleted|added|removed|touched)\s+"
                   r"(?P<b>\d+)\s+(?:files?|paths?)\b)", re.I)
PID = re.compile(r"(?<![\w-])pid[\s=:]*\d{2,7}\b", re.I)

UNCHECKED_KINDS = ("no_path", "meta", "renamed_or_absent", "pid", "unfalsifiable_count")


# ---- the SUBJECT half -------------------------------------------------------------------
# WHY A SEPARATE LANE AND NOT AN EXTRA CLAIM KIND. The claim lane above is driven by the
# MESSAGE's sentences; this one is driven by the DIFF's paths. A commit has one message and one
# diff, and the two disagree in ways only one subject can name -- the failure `gates/gendirs.py`
# exists to name, restated in this file's own terms: ONE VERDICT FOR TWO SUBJECTS IS NO VERDICT.
# So the subject refusal is computed, reported and returned SEPARATELY from the claim refusals,
# and `main()` refuses if EITHER fired. A gate that could only say "REFUSED" would leave the
# reader unable to tell WHICH of the two questions failed.
#
# THE BLIND SPOT THIS EXISTS TO CLOSE, MEASURED. `9144d179e25a`, `c83f04ad1c12` and
# `75ab9b8f8984` all PASS the claim lane above with **0 claims checked and 0 uncheckable** -- not
# because the messages are honest but because the claim lane's POPULATION is claim sentences and
# none of the three messages contains one. 9144d179e25a removed 110 paths; its message names
# 7 globs and not one of the 110. Nothing to grade, so nothing is graded, and the exit is 0.
#
# RULE (a), THE ALLOWLIST, CHOSEN OVER (b) THE RATIO, AND WHY. Rule (a): every path the commit
# REMOVES must be either NAMED by the message or ACKNOWLEDGED by `SUBJECT_DIFF_ACK=`. Rule (b):
# refuse above N removals outside the subject.
#
# MEASURED over the same population (`--since=2026-10-06T00:00`, HEAD, 300 commits, every
# commit, no filter -- regenerated by `.agents/slop/diffrule/separation.py`):
#
#     rule                    fires on   of 300    catches the 3 named incidents
#     (a) ALLOWLIST, D only        33                3 of 3
#     (a) ALLOWLIST, D + R src    202                3 of 3
#     (b) RATIO at N=8            131                3 of 3
#
# (b) IS THE LOUDER RULE AND THE WORSE ONE, and the reason is that N IS A HUMAN DECISION.
# Every N is wrong for something: N=8 refuses 131 of 300 honest commits, and no N catches
# `75ab9b8f8984`'s 4 unacknowledged DELETIONS without also catching honest commits with 4.
# (a) HAS NO N. Its correctness is a FACT ABOUT THE DIFF, not a number a person chose: 33
# firings, and `.agents/slop/diffrule/triage.py` classifies 17 of those 33 as REPEATED
# deletions -- a path deleted twice in this population and restored in between, which no unit
# does to its own work. The other 16 are `SUBJECT_DIFF_ACK`-able, and that is the honest cost:
# (a) TRADES A THRESHOLD FOR AN ACKNOWLEDGEMENT, AND THE ACKNOWLEDGEMENT IS A SENTENCE THE
# COMMITTER ALREADY HAS TO WRITE.
#
# ADDITIONS ARE DELIBERATELY NOT IN THE RULE. MEASURED: 202 of 300 commits carry an addition
# outside their subject's globs, because a unit's report, its `.rows` and its gate land beside
# the code and a message that names the code need not name the report. Grading additions would
# refuse 67% of honest history to catch nothing: all six incidents are REMOVALS. A rule that
# fired on the harmless two thirds of every commit is a policy wearing a guard's name.
#
# THE REMOVAL SET IS DISCOVERED, NOT LISTED: it is whatever `diff-tree -r -M` reports as `D` or
# as a rename source. There is no directory in this file, and adding one -- "collateral lives
# under .agents/slop/" -- is the hand-list failure this rule is a reaction to.
SUBJECT_RE = re.compile(r"^(?P<path>[A-Za-z0-9_./{},-]+)$")


def _message_names(message):
    """The set of paths and PARENT DIRECTORIES the message names.

    A parent directory counts, because a message that says `gates/tn_where.bend` has declared
    `gates` -- refusing it for also editing `gates/tn_where-gate.py` would refuse the honest
    message for being concise. `PATH` is the SAME regex the claim lane uses: one grammar in
    this file, imported not restated.
    """
    tokens = set(PATH.findall(message))
    parents = set()
    for t in tokens:
        parts = t.split("/")
        parents.update("/".join(parts[:i]) for i in range(1, len(parts)))
    return tokens, parents


def _covered(path, roots):
    """`path` is under one of `roots`, as a full prefix, as a SUFFIX, or through a WILDCARD.

    **THE SUFFIX HALF IS NOT A NICETY, IT IS MEASURED.** `3188c1af86a1` is `portzz`: FOUR
    RELOCATED, ONE REPORTED AND NOT MOVED, and its message names every one of the four
    (`runtime/zzdiag.bend`, `runtime/support/zz_objc_mutant.bend`, ...) -- relative to
    `tinybendygrad/`, which the sentence does not repeat. A prefix test alone calls those four
    undeclared removals and refuses an HONEST commit, which is the failure mode this rule's
    whole design is built against (see `_nearest_path`: A BLAMED INNOCENT IS A REFUSED HONEST
    MESSAGE).

    The same suffix test is what the CLAIM lane already does at its own `cands` line, so this
    is one rule in one file rather than two rules that disagree about what a name is.

    `fnmatch` rather than a hand translate, and it is the only `fnmatch` in this file: `*` is
    the one metacharacter with a measured use (`memory.staged-mem-*`).
    """
    return (path in roots
            or any(path.startswith(pre + "/") for pre in roots)
            or any(path.endswith("/" + r) for r in roots if r)
            or any(fnmatch(path, pat) or fnmatch(path, pat.rstrip("/") + "/*")
                   for pat in roots if "*" in pat))


def unacknowledged_removals(removed, message, ack_paths):
    """`removed` minus (what the message declares) minus (`SUBJECT_DIFF_ACK=`'s paths).

    Sorted, so a refusal reads the same twice. The `named` test is the generous one (prefix,
    suffix, directory or wildcard); the strict one refuses a message for being concise, and a
    blamed innocent is worse than a missed claim.
    """
    tokens, parents = _message_names(message)
    # Wildcards and slash-terminated directories join the declaration set. Both are read from
    # the MESSAGE with the same care as `PATH`, and neither is a list: they are whatever the
    # author's prose declares, which is the only source a declaration can have.
    decl = tokens | parents | set(GLOB.findall(message)) | set(DIR.findall(message))
    acked = {p.strip().rstrip("/") for p in (ack_paths or "").split(",") if p.strip()}
    return [p for p in sorted(removed) if not _covered(p, decl) and not _covered(p, acked)]


def judge_subject(root, sha, message, ack_paths):
    """(PASS|REFUSED, n_removals, n_unacknowledged, first few paths).

    `DEAD` is impossible here and is not returned: `commit_view` raises `RuntimeError` and
    `main()` turns that into DEAD, so this lane cannot silently emit nothing."""
    present, _deleted, removed, _changed = commit_view(root, sha)
    del present
    bad = unacknowledged_removals(removed, message, ack_paths)
    if bad:
        return REFUSED, len(removed), len(bad), bad[:8]
    return PASS, len(removed), 0, []


def _git(root, *args, stdin=None):
    """One git call. `--no-optional-locks` so this gate NEVER writes the index it reads --
    a guard that moves the thing it measures is the jj-reset hazard restated."""
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(root), *args],
                       capture_output=True, text=True, input=stdin)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout


def commit_view(root, sha):
    """(present, deleted, removed, changed) for one commit.

    `deleted` is the `D` set under rename detection (`-M`), so a pure MOVE is not a delete --
    and it is the set the MESSAGE lane judges against, UNCHANGED.

    `removed` is `D` PLUS every rename SOURCE, and it is a SEPARATE set for a reason that is a
    measurement rather than a preference: `c83f04ad1c12` reverted 46 renames and git records
    them as `R100`, so `deleted` sees NONE of them -- which is exactly why they were
    "invisible in a diffstat". A rename removes its source path; a set built from `D` alone
    cannot see a removal. Folding the two would CHANGE this lane's verdicts (a claim about a
    rename source would become witnessed), and this lane's verdicts are not this unit's to move.

    The two sets are kept apart so ONE commit can carry two subjects -- the DIFF-removal and
    the MESSAGE-claim -- and each has its own verdict. See `gates/README.md`.
    """
    present = set(_git(root, "ls-tree", "-r", "--name-only", sha).splitlines())
    status = _git(root, "diff-tree", "-r", "-M", "--root", "--no-commit-id",
                  "--name-status", sha)
    deleted, removed, changed = set(), set(), 0
    for line in status.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        changed += 1
        if parts[0].startswith("D"):
            deleted.add(parts[-1])
            removed.add(parts[-1])
        elif parts[0].startswith("R") and len(parts) >= 3:
            removed.add(parts[1])          # the SOURCE: what ceased to exist
    return present, deleted, removed, changed


def _clause(text, i):
    """The clause a position sits in: bounded by a newline, the `***` separator this tree's
    messages use, or a `. ` sentence end. Paths carry dots, but `plants.py` has `y` after the
    dot, so `. ` cannot split a path."""
    start = max(text.rfind(c, 0, i) for c in ("\n", "***", ". "))
    if start >= 0 and start == text.rfind("***", 0, i):
        start += 3
    start = max(start, 0)
    ends = [e for e in (text.find(c, i) for c in ("\n", "***", ". ")) if e != -1]
    hi = (min(ends) + 1) if ends else len(text)
    return " ".join(text[start:hi].split()).lstrip(".* "), start, hi


def _nearest_path(text, i, hi, window=40):
    """The path a verb governs, or None. FORWARD-ONLY, WINDOW-BOUNDED, and GAP-FILTERED: the
    path must START within `window` chars after the verb and the text between must be ordinary
    words ("the superseded X"). If the verb's object is a non-path noun ("DELETED 6000+ FILES"),
    a definition ("deleted `dec_limit`"), a relative clause ("DELETED, GUARDED BY `x.py`"), or
    the only path is BEFORE the verb, the verb governs no path here and the claim is unchecked.
    The asymmetry is deliberate: A MISSED CLAIM IS A PASS, A BLAMED INNOCENT IS A REFUSED
    HONEST MESSAGE."""
    m = PATH.search(text, i)
    if not m or m.start() - i > window or m.start() >= hi:
        return None
    return None if GAP_STOP.search(text[i:m.start()]) else m.group()


# A gate file is `gates/<stem>.py`. If the basename ends in `-gate`, the prefix is
# also a stem, so `ledgergone:` and `ledgergone-gate:` name the same file.
# Discovery is HEAD, not the commit being judged: the population is the tree the
# gate is running against, and a hand list of two commits is not a population.
_GATE_PY = re.compile(r"gates/([^/]+)\.py")
_STEM_CLAIM = re.compile(r"(?<![A-Za-z0-9_./-])([A-Za-z0-9_-]+)(?=\s*:)")
_GATE_PATH_IN_TEXT = re.compile(r"(?<![A-Za-z0-9_./-])(gates/[A-Za-z0-9_-]+\.py)")
_STEM_CACHE = {}


def _path_stems(path):
    """Stems one `gates/<file>.py` yields for discovery. Not containment.

    Stable order: the short stem, then the basename. A `.bend`, a `-oracle.py`,
    or a `-mutate.py` does not discover a stem. Whether a diff path contains one
    is `_contained_stems`.
    """
    m = _GATE_PY.fullmatch(path)
    if not m:
        return ()
    base = m.group(1)
    if base.endswith("-gate") and len(base) > 5:
        return (base[:-5], base)
    return (base,)


# One role suffix, not a loop: `gates-pop-rows-gate` contains `gates-pop-rows`,
# not `gates-pop`. Stripping every role would make those equal.
_CONTAIN_ROLES = ("-gate", "-oracle", "-mutate", "-plant")


def _contained_stems(path):
    """Stems one diff path contains. Extension off, then one role suffix off.

    A diff path contains a named stem when the path's basename, with `-gate`,
    `-oracle`, `-mutate`, `-plant`, or a trailing extension removed, equals the
    stem. A `.bend` of that stem contains it. A rename still contains it:
    `_diff_paths` yields the source and the destination, and both are asked.
    """
    base = path.rsplit("/", 1)[-1]
    name, dot, ext = base.rpartition(".")
    bare = name if dot and name and ext else base
    if not bare:
        return ()
    stems = [bare]
    for role in _CONTAIN_ROLES:
        if bare.endswith(role) and len(bare) > len(role):
            stems.append(bare[:-len(role)])
            break
    return tuple(stems)


def gate_stems(root):
    """Every stem `gates/<stem>-gate.py` or `gates/<stem>.py` in HEAD.

    Keyed on HEAD's sha, because the plant's scratch repo moves HEAD between
    states and a cache of the seed would hide the files the later states add.
    """
    head = _git(root, "rev-parse", "HEAD").strip()
    key = (str(root), head)
    if key in _STEM_CACHE:
        return _STEM_CACHE[key]
    found = set()
    for path in _git(root, "ls-tree", "-r", "--name-only", "HEAD").splitlines():
        found.update(_path_stems(path))
    _STEM_CACHE[key] = found
    return found


def named_gate_stems(subject, known):
    """Stems the subject line CLAIMS. A bare word is not a claim.

    `ledgergone:` is a claim. `gates/valscall-gate.py` is a claim. `banner` in
    "the census's banner shape" is not -- measured, that word is a stem, and
    refusing the sentence refuses an honest message for being prose.
    """
    hits = []
    for m in _GATE_PATH_IN_TEXT.finditer(subject):
        hits.extend((m.start(), stem) for stem in _path_stems(m.group(1)) if stem in known)
    for m in _STEM_CLAIM.finditer(subject):
        if m.group(1) in known:
            hits.append((m.start(), m.group(1)))
    named = []
    for _, stem in sorted(hits):
        if stem not in named:
            named.append(stem)
    return named


def _diff_paths(root, sha):
    """Every path the commit touches, rename source and destination included.

    A rename still contains the stem. Folding the source out would refuse an
    honest rename of the file the subject names.
    """
    status = _git(root, "diff-tree", "-r", "-M", "--root", "--no-commit-id",
                  "--name-status", sha)
    paths = []
    for line in status.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            paths.extend(parts[1:])
    return paths


def judge_named_stem(root, sha, message):
    """(PASS|REFUSED, named, missing, diff gate paths).

    The subject line only. The body of `1dac4ab61` discusses `ledgerdue`, and a
    message that reports another gate must not be refused for naming it. No
    named stem is PASS with `named=[]` -- this lane did not fail that subject.

    A diff path contains a named stem when the path's basename, with `-gate`,
    `-oracle`, `-mutate`, `-plant`, or a trailing extension removed, equals the
    stem. A `.bend` of that stem contains it. A rename still contains it.
    A stolen subject is not exempted: `ledgergone` over `valscall-gate.py` is
    still absent.
    """
    subject = message.split("\n", 1)[0]
    known = gate_stems(root)
    named = named_gate_stems(subject, known)
    gate_paths = []
    diff_stems = set()
    for path in _diff_paths(root, sha):
        if _path_stems(path):
            gate_paths.append(path)
        diff_stems.update(_contained_stems(path))
    if not named:
        return PASS, [], [], gate_paths
    missing = [stem for stem in named if stem not in diff_stems]
    if missing:
        return REFUSED, named, missing, gate_paths
    return PASS, named, [], gate_paths


def deletion_claims(message):
    """Every deletion ASSERTION: (token, clause, index, kind) for a verb that is neither
    negated nor inside a meta-report. A verb governs at most one path (see `_nearest_path`)."""
    out = []
    for m in VERB.finditer(message):
        verb_at = m.start()
        clause, lo, hi = _clause(message, verb_at)
        skip = NEGATION.search(message[max(0, verb_at - 48):verb_at]) or META.search(clause)
        out.append((_nearest_path(message, verb_at, hi), clause, verb_at,
                    "skip" if skip else "claim"))
    return out


def judge_message(root, sha, message, ack, verbose=False, ack_paths=""):
    """PASS, or REFUSED naming the sentence. FAIL is never returned: see the module docstring.

    Returns `(code, checked, unchecked, refusals, subject, stem)` where `subject` is
    `(code, n_removals, n_unacknowledged, sample_paths)` and `stem` is
    `(code, named, missing, diff_gate_paths)`. Reported rather than folded, so
    `main()` can refuse on any and say which."""
    present, deleted, _removed, changed = commit_view(root, sha)
    unchecked = {k: 0 for k in UNCHECKED_KINDS}
    checked = 0
    refusals = []

    for tok, clause, _, kind in deletion_claims(message):
        if kind == "skip" or not tok:
            unchecked["meta" if kind == "skip" else "no_path"] += 1
            continue
        cands = [p for p in (present | deleted) if p == tok or p.endswith("/" + tok)]
        if not cands:
            unchecked["renamed_or_absent"] += 1
            continue
        checked += 1
        if not any(p in deleted for p in cands):
            refusals.append((tok, clause, "present in this commit's tree, not deleted by it"))

    for m in COUNT.finditer(message):
        n = int(m.group("a") or m.group("b"))
        checked += 1
        if n != changed:
            refusals.append((f"{n} files", _clause(message, m.start())[0],
                             f"the diff changes {changed} file{'s' if changed != 1 else ''}"))

    unchecked["pid"] = len(PID.findall(message))
    stem = judge_named_stem(root, sha, message)

    label = f"{sha[:12]}"
    if refusals and not ack:
        print(f"REFUSED, NOT A VERDICT: {label} -- the message claims a change the diff does "
              f"not witness ({checked} checked, {sum(unchecked.values())} uncheckable)",
              file=sys.stderr)
        for tok, clause, why in refusals:
            print(f"  claim: {clause}", file=sys.stderr)
            print(f"  file:  {tok}  ({why})", file=sys.stderr)
        print('  re-run with MESSAGE_DIFF_ACK="<reason>" if the message is right and the diff '
              "is a partial view", file=sys.stderr)
        return REFUSED, checked, unchecked, refusals, (PASS, 0, 0, []), stem
    acked = f" (ack: {ack})" if refusals and ack else ""
    # A stem refusal is the verdict. Printing PASS for the claim lane first would
    # make a reader who stops at the first line think the liar passed.
    if (verbose or refusals) and stem[0] == PASS:
        print(f"PASS: {label} -- {checked} deletion claims checked, "
              f"{sum(unchecked.values())} uncheckable "
              f"(pids={unchecked['pid']}, counts=unfalsifiable, meta={unchecked['meta']})"
              f"{acked}")
    return PASS, checked, unchecked, refusals, judge_subject(root, sha, message, ack_paths), stem


def revs_for(root, args):
    """`<base>..<head>`, or any rev-list args, in history order."""
    if not args:
        return []
    return _git(root, "rev-list", "--reverse", *args).split()


def format_stem_refusal(kind, sha, subject, paths):
    """The three fields a stem refusal prints: sha, subject, diff paths."""
    if kind == "missing":
        diff = "diff: (absent)"
    elif paths:
        diff = "\n".join(f"diff: {p}" for p in paths)
    else:
        diff = "diff: (none)"
    return f"REFUSED {sha}\nsubject: {subject}\n{diff}"


def stem_range(root, args):
    """(code, rows, walked) for subject-stem refusals.

    No args walks the last 800. Any args are `rev-list` args (`-n 50`,
    `--since=... HEAD`). A row is `(kind, sha, subject, paths)` with kind
    `stem` or `missing`. A missing git object is REFUSED, not PASS.
    The walk is the population: this function names no sha of its own.
    """
    spec = list(args) if args else ["-n", "800", "HEAD"]
    try:
        revs = _git(root, "rev-list", *spec).split()
    except RuntimeError as e:
        return REFUSED, [("missing", " ".join(spec), f"(missing git object: {e})", [])], 0
    if not revs:
        return SKIP, [], 0
    try:
        known = gate_stems(root)
        raw = _git(root, "log", "--no-walk", "--stdin", r"--format=%H%x1e%s",
                   stdin="\n".join(revs) + "\n")
    except RuntimeError as e:
        return REFUSED, [("missing", " ".join(spec), f"(missing git object: {e})", [])], 0
    subjects = {}
    # `\n` only. `splitlines()` also splits on `\x1e`, which is the separator
    # between sha and subject, so it would drop every subject and call a
    # present commit missing.
    for line in raw.split("\n"):
        if not line:
            continue
        sha, sep, subject = line.partition("\x1e")
        if sep and sha:
            subjects[sha] = subject
    rows = []
    for sha in revs:
        subject = subjects.get(sha)
        if subject is None:
            rows.append(("missing", sha, "(missing git object)", []))
            continue
        if not named_gate_stems(subject, known):
            continue
        try:
            code, _named, _missing, _gates = judge_named_stem(root, sha, subject)
            paths = _diff_paths(root, sha) if code == REFUSED else []
        except RuntimeError:
            rows.append(("missing", sha, "(missing git object)", []))
            continue
        if code == REFUSED:
            rows.append(("stem", sha, subject, paths))
    return (REFUSED if rows else PASS), rows, len(revs)


# ---------------------------------------------------------------- plant
def _plant():
    """STATES IN A SCRATCH REPO -- never this one. An HONEST message PASSes; a message
    claiming a deletion the commit did not make REFUSES (exit 3) naming the sentence; a message
    naming only uncheckable things (a pid) PASSes because it cannot be judged; the same false
    message PASSes with `--ack`; and the COUNT lane refuses a false count and passes an honest
    one. The stem lane refuses a subject that names a gate stem the diff lacks, passes one
    that names the stem the diff has, and does not fail a subject that names no stem.
    State B is the unbroken deletion-claim control. The stems walk refuses the stolen
    subject, passes a walk that contains only the file the subject names, does not fail
    a subject with no stem, and REFUSES a missing object rather than passing it.
    A subject `opseven:` over a diff of `gates/opseven.bend` stays green. A subject
    `ledgergone:` over `gates/valscall-gate.py` stays red. A `.bend` of a different
    stem does not contain it. A rename of the file still contains it."""
    root_env = dict(os.environ)
    # The scratch repo must not inherit a private index from the caller. A commit
    # here that wrote the real tree's index would be the hazard this gate exists for.
    root_env.pop("GIT_INDEX_FILE", None)
    for k in ("GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"):
        root_env[k] = "p"
    bad = []

    def run(cwd, *args):
        return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True,
                              text=True, env=root_env)

    def verdict(cwd, rev="HEAD", ack="", ack_paths=""):
        """`judge_message` on `rev`, in this scratch repo. `rev` rather than `HEAD` because
        states D and G re-grade an EARLIER commit than the one just made."""
        return judge_message(cwd, rev, _git(cwd, "log", "-1", "--format=%B", rev),
                             ack, True, ack_paths)

    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
        root = Path(td)
        run(root, "init", "-q")
        (root / "keep.py").write_text("x = 1\n")
        (root / "victim.py").write_text("y = 2\n")
        # FIVE collateral paths, seeded TRACKED, whose names no message below ever mentions.
        for i in range(5):
            (root / f"other{i}.py").write_text(f"z = {i}\n")
        # Two gate files, so the stem lane's population is discovered from this repo's
        # HEAD rather than named in the gate. The names are the measured pair; the
        # lookup is still `git ls-tree`.
        (root / "gates").mkdir()
        (root / "gates" / "ledgergone-gate.py").write_text("g = 1\n")
        (root / "gates" / "valscall-gate.py").write_text("v = 1\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "seed")

        # STATE A: HONEST -- it really does delete victim.py, and the message says so
        (root / "victim.py").unlink()
        (root / "keep.py").write_text("x = 2\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "Removed victim.py, fixed keep.py")
        r = verdict(root)
        bad += [] if r[0] == PASS and r[4][0] == PASS else [
            f"state A claim={_w(r[0])} subject={_w(r[4][0])}, expected PASS(0)/PASS"]

        # STATE B: FALSE CLAIM -- it says it deleted keep.py, but keep.py is present
        (root / "more.py").write_text("q = 9\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "Deleted keep.py and added more.py")
        claim_sha = _git(root, "rev-parse", "HEAD").strip()
        r = verdict(root)
        bad += [] if r[0] == REFUSED else [f"state B rc={r[0]}, expected REFUSED(3)"]

        # STATE C: UNCHECKABLE -- a pid claim is counted and passed, never refused
        (root / "more.py").write_text("q = 10\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "bump; the server is at pid 30543, 41% done")
        r = verdict(root)
        bad += [] if r[0] == PASS else [f"state C rc={r[0]}, expected PASS(0) -- uncheckable"]

        # STATE D: ACK -- the same false message, explained, PASSes
        r = verdict(root, "HEAD~1", "the diff is a partial view")
        bad += [] if r[0] == PASS else [f"state D rc={r[0]}, expected PASS(0) with --ack"]

        # STATE E/F: the COUNT lane -- "changed 9 files" over a 1-file diff REFUSES, and the
        # honest "changed 1 file" PASSes. The noun must be FILES for the count to be resolvable.
        (root / "cnt.py").write_text("q = 1\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "changed 9 files")
        r = verdict(root)
        bad += [] if r[0] == REFUSED else [f"state E rc={r[0]}, expected REFUSED(3)"]
        (root / "cnt.py").write_text("q = 2\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "changed 1 file")
        r = verdict(root)
        bad += [] if r[0] == PASS else [f"state F rc={r[0]}, expected PASS(0)"]

        # STATE G: **THE BLIND SPOT.** An HONEST message about `ported.py`, and the commit ALSO
        # removes five files it never mentions -- the `9144d179e25a` shape exactly. The CLAIM
        # lane sees no claim and PASSes, which is not a bug in the claim lane but the reason
        # this lane exists. Asserted on BOTH halves, because the claim lane passing here IS
        # the defect being closed.
        (root / "ported.py").write_text("p = 1\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "seed ported")
        for i in range(5):
            (root / f"other{i}.py").unlink()
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "ported: tn_sample and tn_other ported, 12/12 green")
        r = verdict(root)
        if r[0] != PASS:
            bad += [f"state G claim lane rc={r[0]}, expected PASS(0) -- it has no claim to judge"]
        if r[4][0] != REFUSED:
            bad += [f"state G subject lane={_w(r[4][0])}, expected REFUSED(3), "
                    f"got {r[4][2]} undeclared removals"]
        else:
            print(f"  G the subject lane caught {r[4][2]} undeclared removals: {r[4][3][:2]}")

        # STATE H: the SAME commit with SUBJECT_DIFF_ACK naming those five paths -> PASS.
        r = verdict(root, "HEAD", "", ",".join(f"other{i}.py" for i in range(5)))
        if r[4][0] != PASS:
            bad += [f"state H subject lane={_w(r[4][0])}, expected PASS(0) with SUBJECT_DIFF_ACK"]

        # STATE I: subject names a stem the diff lacks. Claim lane has nothing to
        # judge; the removal lane has nothing to judge; the stem lane must refuse.
        (root / "gates" / "valscall-gate.py").write_text("v = 2\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m",
            "ledgergone: classify each GONE ledger path without writing the ledger")
        stolen = _git(root, "rev-parse", "HEAD").strip()
        r = verdict(root)
        if r[0] != PASS:
            bad += [f"state I claim lane={_w(r[0])}, expected PASS(0) -- no deletion claim"]
        if r[4][0] != PASS:
            bad += [f"state I removal lane={_w(r[4][0])}, expected PASS(0) -- no removals"]
        if r[5][0] != REFUSED or r[5][2] != ["ledgergone"]:
            bad += [f"state I stem={_w(r[5][0])} missing={r[5][2]}, expected REFUSED ledgergone"]
        else:
            print(f"  I the stem lane refused {r[5][2]} (diff {r[5][3]})")

        # STATE J: the SAME commit, a message copy that names the stem the diff has.
        # Fed to the judge. The commit is not rewritten.
        r = judge_message(root, "HEAD", "valscall: the file this diff contains\n",
                          "", True, "")
        if r[0] != PASS or r[5][0] != PASS or r[5][1] != ["valscall"]:
            bad += [f"state J claim={_w(r[0])} stem={_w(r[5][0])} named={r[5][1]}, "
                    f"expected PASS naming valscall"]

        # STATE K: a subject that names no gate stem is not failed by this check.
        r = judge_message(root, "HEAD",
                          "classify each path without writing the ledger\n", "", True, "")
        if r[5][0] != PASS or r[5][1]:
            bad += [f"state K stem={_w(r[5][0])} named={r[5][1]}, expected PASS with no stem"]

        # STATE L: a bare stem word is prose. Any-token matching would refuse this,
        # because `ledgergone` is a stem and the diff does not contain it.
        r = judge_message(root, "HEAD",
                          "the census banner shape mentions ledgergone in prose\n",
                          "", True, "")
        if r[5][0] != PASS or r[5][1]:
            bad += [f"state L stem={_w(r[5][0])} named={r[5][1]}, "
                    f"expected PASS -- a bare word is not a stem claim"]

        # STATE M: a commit whose subject names the file the diff contains.
        (root / "gates" / "valscall-gate.py").write_text("v = 3\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "valscall: the file this diff contains")
        green = _git(root, "rev-parse", "HEAD").strip()
        r = verdict(root)
        if r[5][0] != PASS or r[5][1] != ["valscall"]:
            bad += [f"state M stem={_w(r[5][0])} named={r[5][1]}, expected PASS naming valscall"]

        # STATE N: no stem claim, committed, so the walk can see it. A bare
        # `ledgergone` is prose. Any-token matching would refuse this commit.
        (root / "keep.py").write_text("x = 3\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "the census banner shape mentions ledgergone in prose")
        prose = _git(root, "rev-parse", "HEAD").strip()
        r = verdict(root)
        if r[5][0] != PASS or r[5][1]:
            bad += [f"state N stem={_w(r[5][0])} named={r[5][1]}, expected PASS with no stem"]

        # STATE O: default walk (last 800) refuses the stolen subject and prints
        # its sha, subject, and the one diff path. The deletion-claim commit is
        # in that walk and is not a stem refusal — this lane does not grade it.
        code, rows, walked = stem_range(root, [])
        hit = [row for row in rows if row[1] == stolen]
        if code != REFUSED or not walked or len(hit) != 1:
            bad += [f"state O code={_w(code)} walked={walked} hits={len(hit)}, "
                    f"expected REFUSED naming the stolen subject"]
        else:
            kind, sha, subject, paths = hit[0]
            text = format_stem_refusal(kind, sha, subject, paths)
            if (kind != "stem" or paths != ["gates/valscall-gate.py"]
                    or not subject.startswith("ledgergone:")
                    or sha not in text or subject not in text
                    or "gates/valscall-gate.py" not in text):
                bad += [f"state O row did not carry sha, subject, and diff path: {hit[0]!r}"]
            else:
                print(f"  O range refused {sha[:12]} diff {paths}")
        if any(row[1] in (green, prose, claim_sha) for row in rows):
            bad += ["state O listed a green, prose, or deletion-claim commit"]
        narrow, narrow_rows, narrow_n = stem_range(root, ["-n", "1", stolen])
        if narrow != REFUSED or narrow_n != 1 or [row[1] for row in narrow_rows] != [stolen]:
            bad += [f"state O override stolen={_w(narrow)} n={narrow_n} "
                    f"rows={len(narrow_rows)}, expected REFUSED"]

        # STATE P: the same check, overridden to one honest commit, stays green.
        # A subject with no stem is in the prose override and is not failed.
        for label, spec in (("green", ["-n", "1", green]), ("prose", ["-n", "1", prose])):
            code, rows, walked = stem_range(root, spec)
            if code != PASS or rows or walked != 1:
                bad += [f"state P {label}={_w(code)} rows={len(rows)} walked={walked}, "
                        f"expected PASS"]

        # STATE Q: a missing object is REFUSED, not a pass and not DEAD.
        missing = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        code, rows, _walked = stem_range(root, [missing])
        if code != REFUSED or not rows or rows[0][0] != "missing":
            bad += [f"state Q missing={_w(code)} rows={rows!r}, expected REFUSED not PASS"]
        else:
            text = format_stem_refusal(*rows[0])
            if missing not in text or "(missing git object" not in text or "diff: (absent)" not in text:
                bad += [f"state Q text omitted sha, subject, or diff: {text!r}"]
            else:
                print("  Q missing object REFUSED")

        # Containment, on synthetic commits. `opseven` is discovered from the
        # gate file, which is not in the diffs below. State I remains the stolen
        # subject: `ledgergone:` over `gates/valscall-gate.py` is not exempted.
        (root / "gates" / "opseven-gate.py").write_text("o = 1\n")
        seeded = run(root, "add", "--", "gates/opseven-gate.py")
        seeded_c = run(root, "commit", "-q", "-m", "seed opseven so the stem is discovered")
        if seeded.returncode or seeded_c.returncode:
            bad += [f"state R seed failed: {seeded.stderr.strip()} {seeded_c.stderr.strip()}"]
        bend_sha = ""
        contain = (
            ("R", "gates/opseven.bend", "b = 1\n",
             "opseven: the bend file contains the stem", PASS),
            ("S", "gates/opseven-oracle.py", "o = 2\n",
             "opseven: the oracle contains the stem", PASS),
            ("T", "gates/opseven-mutate.py", "m = 1\n",
             "opseven: the mutate file contains the stem", PASS),
            ("U", "gates/opseven-plant.py", "p = 1\n",
             "opseven: the plant file contains the stem", PASS),
            ("V", "gates/not-the-stem.bend", "n = 1\n",
             "opseven: a different bend does not contain it", REFUSED),
        )
        for label, rel, text, message, expect in contain:
            dest = root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(text)
            added = run(root, "add", "--", rel)
            committed = run(root, "commit", "-q", "-m", message)
            if label == "R":
                bend_sha = _git(root, "rev-parse", "HEAD").strip()
            got = verdict(root)[5]
            ok = got[0] == expect and not added.returncode and not committed.returncode
            if expect == PASS:
                ok = ok and got[1] == ["opseven"] and not got[2]
            else:
                ok = ok and got[2] == ["opseven"]
            if not ok:
                bad += [f"state {label} stem={_w(got[0])} named={got[1]} missing={got[2]} "
                        f"add={added.returncode} commit={committed.returncode}, expected {_w(expect)}"]
            else:
                print(f"  {label} {rel} -> {_w(expect)}")
        no_stem = judge_message(root, bend_sha, "a subject with no stem\n", "", True, "")
        if not bend_sha or no_stem[5][0] != PASS or no_stem[5][1]:
            bad += [f"state R prose stem={_w(no_stem[5][0])} named={no_stem[5][1]}, "
                    f"expected PASS with no stem"]
        else:
            print("  R a subject with no stem is not failed")
        moved = run(root, "mv", "gates/opseven.bend", "gates/opseven-renamed.bend")
        committed = run(root, "commit", "-q", "-m", "opseven: a rename still contains the stem")
        status = _git(root, "diff-tree", "-r", "-M", "--root", "--no-commit-id",
                      "--name-status", "HEAD")
        renamed = any(line.startswith("R") and "gates/opseven.bend" in line
                      for line in status.splitlines())
        got = verdict(root)[5]
        if (moved.returncode or committed.returncode or not renamed
                or got[0] != PASS or got[1] != ["opseven"]):
            bad += [f"state W rename stem={_w(got[0])} named={got[1]} status={status!r}"]
        else:
            print("  W rename of opseven.bend still contains opseven")
        (root / "gates" / "ledgergone-gate.py").write_text("g = 2\n")
        added = run(root, "add", "--", "gates/ledgergone-gate.py")
        committed = run(root, "commit", "-q", "-m",
                        "ledgergone-gate: the long form is the same file")
        got = verdict(root)[5]
        if (added.returncode or committed.returncode or got[0] != PASS
                or got[1] != ["ledgergone-gate"]):
            bad += [f"state X long form stem={_w(got[0])} named={got[1]}, "
                    f"expected PASS naming ledgergone-gate"]
        else:
            print("  X ledgergone-gate: over the gate file stays green")

    print(f"--plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return FAIL if bad else PASS


def main(argv):
    if "--plant" in argv:
        return _plant()
    ack = os.environ.get("MESSAGE_DIFF_ACK") or ""
    ack_paths = os.environ.get("SUBJECT_DIFF_ACK") or ""
    if "--ack" in argv:
        ack = argv[argv.index("--ack") + 1]
    if "--subject-ack" in argv:
        ack_paths = argv[argv.index("--subject-ack") + 1]
    try:
        # NO ARGUMENT IS `check HEAD`, AND THAT IS A MEASUREMENT AND NOT A BYPASS. The subject
        # is "the commit message against its own diff", so the last commit is the one a bare run
        # should grade; `check` already defaults its REVISION to HEAD, so only the MODE was
        # missing. The old bare run printed usage and returned SKIP, which is honest ("I could
        # not measure") but leaves a bare `for x in gates/*-gate.py` sweep unable to say anything
        # about this gate at all. All three subjects still run: the claim lane, the
        # diff lane, and the gate-stem lane.
        if not argv:
            argv = ["check", "HEAD"]
        mode = argv[0]
        if mode == "check":
            sha = argv[1] if len(argv) > 1 else "HEAD"
            msg = _git(ROOT, "log", "-1", "--format=%B", sha)
            code, _checked, _unchecked, _ref, subj, stem = judge_message(
                ROOT, sha, msg, ack, True, ack_paths)
            if code != PASS:
                return code
            stem_code = _report_stem(sha, stem)
            # A passing removal lane must not print PASS under a stem refusal: the
            # first sentence a reader sees would be the wrong verdict.
            if stem_code == PASS or subj[0] != PASS:
                subj_code = _report_subject(sha, subj)
            else:
                subj_code = PASS
            if stem_code == REFUSED or subj_code == REFUSED:
                return REFUSED
            return PASS
        if mode == "range":
            revs = revs_for(ROOT, argv[1:])
            if not revs:
                print("range: no commits matched", file=sys.stderr)
                return SKIP
            passed = refused = claim_refused = subject_refused = stem_refused = 0
            for sha in revs:
                msg = _git(ROOT, "log", "-1", "--format=%B", sha)
                code, _c, _u, _r, subj, stem = judge_message(
                    ROOT, sha, msg, ack, False, ack_paths)
                if code == PASS and subj[0] == PASS and stem[0] == PASS:
                    passed += 1
                    continue
                refused += 1
                claim_refused += code == REFUSED
                subject_refused += subj[0] == REFUSED
                stem_refused += stem[0] == REFUSED
                missing = f", missing {','.join(stem[2])}" if stem[2] else ""
                print(f"REFUSED {sha[:12]}: claim-subject={_w(code)} "
                      f"diff-subject={_w(subj[0])} stem={_w(stem[0])} "
                      f"({subj[1]} removals, {subj[2]} unacknowledged{missing})",
                      file=sys.stderr)
            print(f"range: {len(revs)} commits -- {passed} PASS, {refused} REFUSED "
                  f"(claims: {claim_refused}, diffs: {subject_refused}, "
                  f"stems: {stem_refused})")
            return REFUSED if refused else PASS
        if mode == "stems":
            code, rows, walked = stem_range(ROOT, argv[1:])
            for row in rows:
                print(format_stem_refusal(*row), file=sys.stderr)
                print(file=sys.stderr)
            if code == SKIP:
                print("stems: no commits matched", file=sys.stderr)
                return SKIP
            n_stem = sum(row[0] == "stem" for row in rows)
            n_miss = sum(row[0] == "missing" for row in rows)
            print(f"stems: walked={walked} subject-stem-refused={n_stem} missing={n_miss}")
            return code
        print(f"unknown mode {mode!r}", file=sys.stderr)
        return SKIP
    except RuntimeError as e:
        print(f"DEAD: git could not answer: {e}", file=sys.stderr)
        return DEAD


def _w(code):
    return {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP",
            DEAD: "DEAD"}.get(code, "UNASSIGNED")


def _report_stem(sha, stem):
    """The claim lane passed, so a stem refusal is printed as its own sentence.

    A subject that named nothing is silent here: printing PASS for "no stem"
    would look like a judgment of prose, which this lane does not make.
    """
    code, named, missing, gate_paths = stem
    if code == PASS:
        if named:
            print(f"PASS: {sha[:12]} -- the subject names {', '.join(named)}, "
                  f"which the diff contains")
        return PASS
    shown = ", ".join(gate_paths) if gate_paths else "no gates/*.py"
    print(f"REFUSED, NOT A VERDICT: {sha[:12]} -- the subject names gate stem "
          f"{', '.join(missing)} and the diff does not contain it (diff: {shown})",
          file=sys.stderr)
    return REFUSED


def _report_subject(sha, subj):
    """The claim subject PASSed, so the verdict is the DIFF subject's -- and it is PRINTED with
    its own numbers rather than folded into the claim lane's sentence. A reader who sees PASS
    must be able to see what was measured to earn it."""
    code, n_rem, n_bad, sample = subj
    if code == PASS:
        print(f"PASS: {sha[:12]} -- the diff subject: {n_rem} removal(s), all named by the "
              f"message or acknowledged")
        return PASS
    print(f"REFUSED, NOT A VERDICT: {sha[:12]} -- the DIFF removes {n_bad} path(s) the message "
          f"does not name ({n_rem} removal(s) total)", file=sys.stderr)
    for p in sample:
        print(f"  undeclared removal: {p}", file=sys.stderr)
    print('  re-run with SUBJECT_DIFF_ACK="<path[,path...]>" if these removals were intended',
          file=sys.stderr)
    return REFUSED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
