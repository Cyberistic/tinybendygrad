"""git-massdelete-gate — REFUSE a commit that deletes more files than this tree's
normal churn can account for.

THE FAILURE IT EXISTS TO STOP. Two commits (`61be7ea90` and its predecessor) recorded the
whole of `.agents/slop/` as DELETED -- `git show --stat 61be7ea90` reads
`6168 files changed, 1 insertion(+), 1947172 deletions(-)` -- and `origin/master` was left
with 2 files. Recovery (`813bbec3e`) took a soft reset, a `read-tree`, and a re-publish. The
one-second check that would have caught it is `git show --stat <commit>` BEFORE pushing.
Nobody looked. This gate is that look, mechanised.

THE THRESHOLD IS MEASURED, NOT GUESSED. `.agents/slop/jjreset/churn.py` walks the last 120
commits of THIS tree and writes `churn.rows`; the envelope is:

    normal (120 commits)   max deleted files =  185   (15a485f0a)
                           max deleted lines = 237256  (a808071e8, a deliberate scratch-tree removal)
    catastrophe            6167 deleted files / 1947172 deleted lines (61be7ea90)

So a commit that deletes more than `REFUSE_FILES = 500` files (2.7x the worst normal churn)
or more than `REFUSE_LINES = 900000` lines (3.8x the worst normal churn, 2.2x below the
catastrophe) is REFUSED -- not FAIL: the gate does not know the deletion is WRONG, it knows
the PRECONDITION (an explanation for this much loss) is ABSENT. Supply one with
`MASS_DELETE_ACK="<reason>"` or `--ack "<reason>"` and it PASSes, having recorded it.

THE FIVE VERDICTS, AS EXITS (`gates/gatekit.py:60`): PASS,FAIL,REFUSED,SKIP,DEAD = 0,1,3,4,5.

MODES
  check  <rev>     one commit, against its parent        (the pre-push half)
  staged           the index against HEAD                (the pre-commit half)
  push             <local_sha> <remote_sha> ...          (a pre-push hook reading stdin)
  --plant          two states in a SCRATCH repo -- never this one

WHY NOT A POST-COMMIT HABIT. A habit is not a gate: it is skipped exactly when the tree is on
fire, which is when the commit is being made in a hurry. This runs at the two moments a large
deletion can still be stopped -- before `git commit` and before `git push` -- and it REFUSES
with a non-zero exit, so an unread habit cannot be mistaken for consent.

Run:  .venv/bin/python .agents/slop/jjreset/git-massdelete-gate.py check HEAD
      .venv/bin/python .agents/slop/jjreset/git-massdelete-gate.py --plant
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# The measured envelope -- see the module docstring and churn.rows.
REFUSE_FILES = 500
REFUSE_LINES = 900000

ROOT = Path(__file__).resolve().parents[3]
ZERO = "0" * 40


def _git(root, *args, stdin=None):
    """One git call. `--no-optional-locks` so this gate NEVER writes the index it is
    guarding -- a guard that moves the thing it measures is the jj-reset hazard restated."""
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(root), *args],
                       capture_output=True, text=True, input=stdin)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout


def _deletions_from_porcelain(text):
    """path -> deleted_lines, from `--numstat` (a path with deleted lines or a binary '-').
    Kept as (count, lines) rather than builtins to stay close to git's own vocabulary."""
    count = 0
    lines = 0
    for ln in text.splitlines():
        parts = ln.split("\t")
        if len(parts) != 3:
            continue
        dele = parts[1]
        count += 1
        if dele != "-":
            lines += int(dele)
    return count, lines


def commit_deletions(root, sha):
    """(deleted_files, deleted_lines, [paths]) for one commit against its parent."""
    status = _git(root, "diff-tree", "-r", "--no-commit-id", "--name-status",
                  "--diff-filter=D", sha)
    paths = [l.split("\t", 1)[1] for l in status.splitlines() if l.startswith("D\t")]
    numstat = _git(root, "diff-tree", "-r", "--no-commit-id", "--numstat", sha)
    files, lines = _deletions_from_porcelain(numstat)
    return len(paths), lines, paths


def staged_deletions(root):
    """(deleted_files, deleted_lines, [paths]) staged in the index against HEAD."""
    status = _git(root, "diff", "--cached", "--name-status", "--diff-filter=D")
    paths = [l.split("\t", 1)[1] for l in status.splitlines() if l.startswith("D\t")]
    numstat = _git(root, "diff", "--cached", "--numstat")
    files, lines = _deletions_from_porcelain(numstat)
    return len(paths), lines, paths


def _envelope_and_ack(ack):
    """The measured envelope, stated in the refusal so a reader can re-derive the number."""
    return (f"envelope: normal churn <= {REFUSE_FILES} files / {REFUSE_LINES} lines "
            f"(measured over 120 commits, churn.rows); "
            f"ack={ack!r}")


def judge(label, files, lines, paths, ack):
    """PASS, or REFUSED with the paths NAMED. FAIL is never returned: the gate does not
    know the deletion is wrong, only that nobody has explained it."""
    over = files > REFUSE_FILES or lines > REFUSE_LINES
    if over and not ack:
        print(f"REFUSED, NOT A VERDICT: {label} deletes {files} files / {lines} lines "
              f"-- {_envelope_and_ack(ack)}", file=sys.stderr)
        for p in paths[:40]:
            print(f"  D {p}", file=sys.stderr)
        if len(paths) > 40:
            print(f"  ... and {len(paths) - 40} more", file=sys.stderr)
        print(f"  re-run with MASS_DELETE_ACK=\"<reason>\" if the loss is intended", file=sys.stderr)
        return REFUSED
    acked = f" (ack: {ack})" if over and ack else ""
    print(f"PASS: {label} deletes {files} files / {lines} lines -- inside the envelope{acked}")
    return PASS


def mode_check(root, sha, ack):
    files, lines, paths = commit_deletions(root, sha)
    return judge(f"{sha[:12]}", files, lines, paths, ack)


def mode_staged(root, ack):
    files, lines, paths = staged_deletions(root)
    return judge("the staged index", files, lines, paths, ack)


def mode_push(root, specs, ack):
    """A pre-push hook's stdin: `<local_ref> <local_sha> <remote_ref> <remote_sha>` per line.
    Each newly-pushed commit is checked, and a NON-FAST-FORWARD update (a force push, which
    this tree forbids) is REFUSED outright -- that is the second half of the guard."""
    for raw in specs.splitlines():
        parts = raw.split()
        if len(parts) != 4:
            continue
        local_ref, local_sha, remote_ref, remote_sha = parts
        if local_sha == ZERO:
            continue  # deleting a remote branch: nothing to inspect here
        if remote_sha != ZERO:
            anc = subprocess.run(["git", "--no-optional-locks", "-C", str(root),
                                  "merge-base", "--is-ancestor", remote_sha, local_sha]).returncode
            if anc != 0:
                print(f"REFUSED, NOT A VERDICT: {local_ref} -> {remote_ref} is not a "
                      f"fast-forward (a force push); this tree forbids rewriting pushed history",
                      file=sys.stderr)
                return REFUSED
            revs = _git(root, "rev-list", local_sha, "--not", remote_sha).split()
        else:
            revs = _git(root, "rev-list", local_sha).split()
        for sha in revs:
            rc = mode_check(root, sha, ack)
            if rc != PASS:
                return rc
    return PASS


# ---------------------------------------------------------------- plant
def _plant():
    """TWO STATES IN A SCRATCH REPO -- never this one. `1 file -> PASS`, `6000 -> REFUSED`,
    distinguishable in token and exit code, with the refused paths named."""
    env = {"GIT_AUTHOR_NAME": "p", "GIT_AUTHOR_EMAIL": "p@x", "GIT_COMMITTER_NAME": "p",
           "GIT_COMMITTER_EMAIL": "p@x", "PATH": os.environ["PATH"]}
    bad = []

    def run(cwd, *args):
        return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True,
                              text=True, env=env)

    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as td:
        root = Path(td)
        run(root, "init", "-q")
        # seed 6000 files + one named victim, in one commit
        for i in range(6000):
            (root / f"f{i}.rows" if i % 2 else root / f"f{i}.bend").write_text(f"{i}\n")
        (root / "victim.rows").write_text("delete me\n")
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "seed")

        # STATE A: delete one file
        run(root, "rm", "-q", "victim.rows")
        run(root, "commit", "-q", "-m", "small")
        rc_a = mode_check(root, "HEAD", "")
        ok_a = rc_a == PASS
        bad += [] if ok_a else [f"state A rc={rc_a}, expected PASS(0)"]

        # STATE B: delete 6000 files
        for i in range(6000):
            (root / (f"f{i}.rows" if i % 2 else f"f{i}.bend")).unlink()
        run(root, "add", "-A")
        run(root, "commit", "-q", "-m", "catastrophe")
        rc_b = mode_check(root, "HEAD", "")
        ok_b = rc_b == REFUSED
        bad += [] if ok_b else [f"state B rc={rc_b}, expected REFUSED(3)"]

        # STATE C: same catastrophe, ACKNOWLEDGED -> PASS
        rc_c = mode_check(root, "HEAD", "the scratch tree is disposable")
        ok_c = rc_c == PASS
        bad += [] if ok_c else [f"state C rc={rc_c}, expected PASS(0) with --ack"]

        # STATE D: the PRE-PUSH half. A fast-forward carrying a small delete PASSes; a
        # non-fast-forward update (a force push) is REFUSED before any deletion is inspected.
        seed = _git(root, "rev-parse", "HEAD~2").strip()   # the 6001-file seed commit
        small = _git(root, "rev-parse", "HEAD~1").strip()  # the 1-file delete
        rc_ff = mode_push(root, f"refs/heads/m {small} refs/heads/m {seed}\n", "")
        rc_nf = mode_push(root, f"refs/heads/m {seed} refs/heads/m {small}\n", "")
        ok_d = rc_ff == PASS and rc_nf == REFUSED
        bad += [] if ok_d else [f"state D ff={rc_ff} (want 0) nonff={rc_nf} (want 3)"]

    print(f"--plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return FAIL if bad else PASS


def main(argv):
    if "--plant" in argv:
        return _plant()
    ack = os.environ.get("MASS_DELETE_ACK") or ""
    if "--ack" in argv:
        ack = argv[argv.index("--ack") + 1]
    try:
        if not argv:
            print("usage: git-massdelete-gate.py {check <rev> | staged | push | --plant}",
                  file=sys.stderr)
            return SKIP
        mode = argv[0]
        if mode == "check":
            return mode_check(ROOT, argv[1] if len(argv) > 1 else "HEAD", ack)
        if mode == "staged":
            return mode_staged(ROOT, ack)
        if mode == "push":
            specs = sys.stdin.read() if len(argv) < 2 else argv[1]
            return mode_push(ROOT, specs, ack)
        print(f"unknown mode {mode!r}", file=sys.stderr)
        return SKIP
    except RuntimeError as e:
        print(f"DEAD: git could not answer: {e}", file=sys.stderr)
        return DEAD


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
