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

Run:  .venv/bin/python gates/msgdiff-gate.py check 00b101574
      .venv/bin/python gates/msgdiff-gate.py range --since=2026-10-06T12:00 HEAD
      .venv/bin/python gates/msgdiff-gate.py --plant
"""
import os
import re
import subprocess
import sys
import tempfile
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


def _git(root, *args):
    """One git call. `--no-optional-locks` so this gate NEVER writes the index it reads --
    a guard that moves the thing it measures is the jj-reset hazard restated."""
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(root), *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout


def commit_view(root, sha):
    """(present, deleted, changed) for one commit. `present` is the tree AT the commit and
    `deleted` is its `D` set under rename detection (`-M`), so a pure MOVE is not a delete."""
    present = set(_git(root, "ls-tree", "-r", "--name-only", sha).splitlines())
    status = _git(root, "diff-tree", "-r", "-M", "--root", "--no-commit-id",
                  "--name-status", sha)
    deleted, changed = set(), 0
    for line in status.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        changed += 1
        if parts[0].startswith("D"):
            deleted.add(parts[-1])
    return present, deleted, changed


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


def judge_message(root, sha, message, ack, verbose=False):
    """PASS, or REFUSED naming the sentence. FAIL is never returned: see the module docstring."""
    present, deleted, changed = commit_view(root, sha)
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
        return REFUSED, checked, unchecked, refusals
    acked = f" (ack: {ack})" if refusals and ack else ""
    if verbose or refusals:
        print(f"PASS: {label} -- {checked} deletion claims checked, "
              f"{sum(unchecked.values())} uncheckable "
              f"(pids={unchecked['pid']}, counts=unfalsifiable, meta={unchecked['meta']})"
              f"{acked}")
    return PASS, checked, unchecked, refusals


def revs_for(root, args):
    """`<base>..<head>`, or any rev-list args, in history order."""
    if not args:
        return []
    return _git(root, "rev-list", "--reverse", *args).split()


# ---------------------------------------------------------------- plant
def _plant():
    """SIX STATES IN A SCRATCH REPO -- never this one. An HONEST message PASSes; a message
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

    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
        root = Path(td)
        run(root, "init", "-q")
        (root / "keep.py").write_text("x = 1\n")
        (root / "victim.py").write_text("y = 2\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "seed")

        # STATE A: HONEST -- it really does delete victim.py
        (root / "victim.py").unlink()
        (root / "keep.py").write_text("x = 2\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "Removed victim.py, fixed keep.py")
        rc_a = judge_message(root, "HEAD", _git(root, "log", "-1", "--format=%B"), "", True)[0]
        bad += [] if rc_a == PASS else [f"state A rc={rc_a}, expected PASS(0)"]

        # STATE B: FALSE -- it says it deleted keep.py, but keep.py is present
        (root / "other.py").write_text("z = 3\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "Deleted keep.py and added other.py")
        r = judge_message(root, "HEAD", _git(root, "log", "-1", "--format=%B"), "", True)[0]
        bad += [] if r == REFUSED else [f"state B rc={r}, expected REFUSED(3)"]

        # STATE C: UNCHECKABLE -- a pid claim is counted and passed, never refused
        (root / "other.py").write_text("z = 4\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "bump; the server is at pid 30543, 41% done")
        r = judge_message(root, "HEAD", _git(root, "log", "-1", "--format=%B"), "", True)[0]
        bad += [] if r == PASS else [f"state C rc={r}, expected PASS(0) -- uncheckable"]

        # STATE D: ACK -- the same false message, explained, PASSES
        r = judge_message(root, "HEAD~1", _git(root, "log", "-1", "--format=%B", "HEAD~1"),
                          "the diff is a partial view", True)[0]
        bad += [] if r == PASS else [f"state D rc={r}, expected PASS(0) with --ack"]

        # STATE E: the COUNT lane -- "changed 9 files" over a 1-file diff REFUSES, and the
        # honest "changed 1 file" PASSes. The noun must be FILES for the count to be resolvable.
        (root / "cnt.py").write_text("q = 1\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "changed 9 files")
        r = judge_message(root, "HEAD", _git(root, "log", "-1", "--format=%B"), "", True)[0]
        bad += [] if r == REFUSED else [f"state E rc={r}, expected REFUSED(3)"]
        (root / "cnt.py").write_text("q = 2\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "changed 1 file")
        r = judge_message(root, "HEAD", _git(root, "log", "-1", "--format=%B"), "", True)[0]
        bad += [] if r == PASS else [f"state F rc={r}, expected PASS(0)"]

    print(f"--plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return FAIL if bad else PASS


def main(argv):
    if "--plant" in argv:
        return _plant()
    ack = os.environ.get("MESSAGE_DIFF_ACK") or ""
    if "--ack" in argv:
        ack = argv[argv.index("--ack") + 1]
    try:
        if not argv:
            print("usage: msgdiff-gate.py {check <rev> | range <rev-list args...> | --plant}",
                  file=sys.stderr)
            return SKIP
        mode = argv[0]
        if mode == "check":
            sha = argv[1] if len(argv) > 1 else "HEAD"
            msg = _git(ROOT, "log", "-1", "--format=%B", sha)
            rc, checked, unchecked, refusals = judge_message(ROOT, sha, msg, ack, True)
            return rc
        if mode == "range":
            revs = revs_for(ROOT, argv[1:])
            if not revs:
                print("range: no commits matched", file=sys.stderr)
                return SKIP
            passed = refused = 0
            for sha in revs:
                msg = _git(ROOT, "log", "-1", "--format=%B", sha)
                out = judge_message(ROOT, sha, msg, ack)
                if out[0] == PASS:
                    passed += 1
                else:
                    refused += 1
            print(f"range: {len(revs)} commits -- {passed} PASS, {refused} REFUSED")
            return REFUSED if refused else PASS
        print(f"unknown mode {mode!r}", file=sys.stderr)
        return SKIP
    except RuntimeError as e:
        print(f"DEAD: git could not answer: {e}", file=sys.stderr)
        return DEAD


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
