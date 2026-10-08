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

Run:  .venv/bin/python gates/msgdiff-gate.py check 00b101574
      .venv/bin/python gates/msgdiff-gate.py range --since=2026-10-06T12:00 HEAD
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


def _git(root, *args):
    """One git call. `--no-optional-locks` so this gate NEVER writes the index it reads --
    a guard that moves the thing it measures is the jj-reset hazard restated."""
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(root), *args],
                       capture_output=True, text=True)
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

    Returns `(code, checked, unchecked, refusals, subject)` where `subject` is
    `(code, n_removals, n_unacknowledged, sample_paths)` -- THE SECOND SUBJECT, reported rather
    than folded in, so `main()` can refuse on either and say which."""
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

    label = f"{sha[:12]}"
    if refusals and not ack:
        print(f"REFUSED, NOT A VERDICT: {label} -- the message claims a change the diff does "
              f"not witness ({checked} checked, {sum(unchecked.values())} uncheckable)",
              file=sys.stderr)
        for tok, clause, why in refusals:
            print(f"  claim: {clause}", file=sys.stderr)
            print(f"  file:  {tok}  ({why})", file=sys.stderr)
        print(f'  re-run with MESSAGE_DIFF_ACK="<reason>" if the message is right and the diff '
              f"is a partial view", file=sys.stderr)
        return REFUSED, checked, unchecked, refusals, (PASS, 0, 0, [])
    acked = f" (ack: {ack})" if refusals and ack else ""
    if verbose or refusals:
        print(f"PASS: {label} -- {checked} deletion claims checked, "
              f"{sum(unchecked.values())} uncheckable "
              f"(pids={unchecked['pid']}, counts=unfalsifiable, meta={unchecked['meta']})"
              f"{acked}")
    return PASS, checked, unchecked, refusals, judge_subject(root, sha, message, ack_paths)


def revs_for(root, args):
    """`<base>..<head>`, or any rev-list args, in history order."""
    if not args:
        return []
    return _git(root, "rev-list", "--reverse", *args).split()


# ---------------------------------------------------------------- plant
def _plant():
    """EIGHT STATES IN A SCRATCH REPO -- never this one. An HONEST message PASSes; a message
    claiming a deletion the commit did not make REFUSES (exit 3) naming the sentence; a message
    naming only uncheckable things (a pid) PASSes because it cannot be judged; the same false
    message PASSes with `--ack`; and the COUNT lane refuses a false count and passes an honest
    one. Two states are distinguishable in token AND exit code; the rest prove the asymmetry."""
    root_env = dict(os.environ)
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
        if not argv:
            print("usage: msgdiff-gate.py {check <rev> | range <rev-list args...> | --plant}",
                  file=sys.stderr)
            print("  env: MESSAGE_DIFF_ACK=<reason>  SUBJECT_DIFF_ACK=<path[,path...]>",
                  file=sys.stderr)
            return SKIP
        mode = argv[0]
        if mode == "check":
            sha = argv[1] if len(argv) > 1 else "HEAD"
            msg = _git(ROOT, "log", "-1", "--format=%B", sha)
            code, _checked, _unchecked, _ref, subj = judge_message(
                ROOT, sha, msg, ack, True, ack_paths)
            if code == PASS:
                return _report_subject(sha, subj)
            return code
        if mode == "range":
            revs = revs_for(ROOT, argv[1:])
            if not revs:
                print("range: no commits matched", file=sys.stderr)
                return SKIP
            passed = refused = claim_refused = subject_refused = 0
            for sha in revs:
                msg = _git(ROOT, "log", "-1", "--format=%B", sha)
                code, _c, _u, _r, subj = judge_message(ROOT, sha, msg, ack, False, ack_paths)
                if code == PASS and subj[0] == PASS:
                    passed += 1
                    continue
                refused += 1
                claim_refused += code == REFUSED
                subject_refused += subj[0] == REFUSED
                print(f"REFUSED {sha[:12]}: claim-subject={_w(code)} "
                      f"diff-subject={_w(subj[0])} "
                      f"({subj[1]} removals, {subj[2]} unacknowledged)", file=sys.stderr)
            print(f"range: {len(revs)} commits -- {passed} PASS, {refused} REFUSED "
                  f"(claims: {claim_refused}, diffs: {subject_refused})")
            return REFUSED if refused else PASS
        print(f"unknown mode {mode!r}", file=sys.stderr)
        return SKIP
    except RuntimeError as e:
        print(f"DEAD: git could not answer: {e}", file=sys.stderr)
        return DEAD


def _w(code):
    return {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP",
            DEAD: "DEAD"}.get(code, "UNASSIGNED")


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
