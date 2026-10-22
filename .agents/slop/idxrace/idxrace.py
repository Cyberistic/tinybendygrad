#!/usr/bin/env python3
"""WHICH COMMIT RECIPE SURVIVES A HEAD THAT MOVES BETWEEN THE SEED AND THE COMMIT?

MEASURED INCIDENT (2026-10-22, this repo): a commit carried 866 deletions across 5 paths,
INCLUDING `tinybendygrad/device.bend` (441 lines, a SUBSTRATE file), because the recipe was
    PARENT=$(git rev-parse HEAD)
    git read-tree "$PARENT"          # <- the tree, captured
    git add -- <path>
    git commit                       # <- HEAD had MOVED; the commit carried the OLD tree
and another unit committed between the `rev-parse` and the `commit`. `git show --stat` caught it.

THIS SCRIPT MEASURES WHICH RECIPE SURVIVES THAT RACE, IN A THROWAWAY REPO. It is not a
proposal; it is the measurement that decides the recipe.

THREE RECIPES, EACH RUN 40 TIMES:
  A  seed-from-CAPTURED-PARENT   read-tree "$PARENT" captured earlier, add, commit
  B  seed-from-CURRENT-HEAD      re-read-tree $(git rev-parse HEAD) IMMEDIATELY before add,
                                 and re-check HEAD did not move between seed and commit
  C  commit --only               NO seed at all: `git commit --only -m msg -- <path>`

THE RESULT, MEASURED 2026-10-22 (40 trials each, the race injected every time):
  A  SWEEPS 40 of 40   -- with a real DELETION of the other unit's file and a real REVERT of
                          the other unit's edit. **A IS THE RECIPE THIS REPO PRESCRIBED, AND
                          IT IS THE ONE THAT FAILS.**
  B  0 of 40
  C  0 of 40  -- and 0 of 40 on a NEW (untracked) file too

TWO OF MY OWN INSTRUMENTS WERE VACUOUS WHILE I MEASURED THIS, AND BOTH ARE FIXED HERE:
  * `git commit --only -- <path> -m msg` puts `-m` AFTER `--`, so `-m` is read as a PATHSPEC
    and the commit NEVER HAPPENS. The other unit's commit was then HEAD, HEAD's tree looked
    PERFECT, and the recipe read as a CLEAN PASS. **`-m` MUST COME BEFORE `--`.**
  * A recipe measurement must ASSERT THAT THE COMMIT IT IS MEASURING LANDED. A commit that
    did not happen is not a pass; it is a refusal, and a refusal is a different class.

THE VICTIM: another "unit" commits between the seed and the commit, in every trial. That is
the whole point -- the race is the SUBJECT, not a nuisance.

THE VERDICT: for each recipe, the commit's tree must equal THE HEAD AT COMMIT TIME's tree
plus exactly the one path the recipe touched. Anything else is a SWEEP, and a sweep is a
revert of somebody else's work.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent / "throwaway"
TRIALS = 40
REFUSED = []


def git(*args, cwd=REPO, env=None):
    e = dict(os.environ)
    e.pop("GIT_INDEX_FILE", None)
    if env:
        e.update(env)
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, env=e)


def out(*args, **kw):
    r = git(*args, **kw)
    if r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed rc={r.returncode}\n{r.stderr}")
    return r.stdout.strip()


def build_repo():
    if REPO.exists():
        shutil.rmtree(REPO)
    REPO.mkdir(parents=True)
    git("init", "-q", ".")
    git("config", "user.email", "unit@example.com")
    git("config", "user.name", "unit")
    (REPO / "a.txt").write_text("a0\n")
    (REPO / "b.txt").write_text("b0\n")
    git("add", "-A")
    git("commit", "-q", "-m", "base")
    # a SECOND unit's work, which a sweep would destroy
    (REPO / "b.txt").write_text("b1\n")
    git("add", "-A")
    git("commit", "-q", "-m", "unit B: its own work")
    # and a THIRD path unit B owns, to detect DELETIONS as well as reverts
    (REPO / "c.txt").write_text("c1\n")
    git("add", "-A")
    git("commit", "-q", "-m", "unit B: another path")


def other_unit_commits():
    """THE RACE: another unit lands a commit right now."""
    (REPO / "b.txt").write_text("b2\n")
    (REPO / "d.txt").write_text("d1\n")
    git("add", "--", "b.txt", "d.txt")
    git("commit", "-q", "-m", "the other unit, mid-race", "--", "b.txt", "d.txt")


def tree_of(rev):
    return dict(
        (ln.split("\t", 1)[1], ln.split("\t", 1)[0].split()[2])
        for ln in out("ls-tree", "-r", rev).splitlines()
    )


def mine_after_their_commit(recipe):
    """Run one trial of `recipe`; the other unit commits between the seed and the commit."""
    idx = REPO / ".git" / "unit-index"
    if idx.exists():
        idx.unlink()
    env = {"GIT_INDEX_FILE": str(idx)}
    (REPO / "a.txt").write_text(f"a-{recipe}-{os.urandom(3).hex()}\n")

    if recipe == "A":
        parent = out("rev-parse", "HEAD")
        git("read-tree", parent, env=env)
        git("add", "--", "a.txt", env=env)
        other_unit_commits()                      # <-- THE RACE
        _c = git("commit", "-q", "-m", f"unit A recipe {recipe}", env=env)
        if _c.returncode: REFUSED.append((recipe, _c.returncode, _c.stderr.strip()[:70]))
    elif recipe == "B":
        git("read-tree", out("rev-parse", "HEAD"), env=env)
        git("add", "--", "a.txt", env=env)
        other_unit_commits()                      # <-- THE RACE
        head_now = out("rev-parse", "HEAD")
        base = out("rev-parse", "HEAD~1")
        if base != head_now:                      # HEAD moved: RE-SEED and RE-ADD
            git("read-tree", head_now, env=env)
            git("add", "--", "a.txt", env=env)
        _c = git("commit", "-q", "-m", f"unit A recipe {recipe}", env=env)
        if _c.returncode:
            REFUSED.append((recipe, _c.returncode, _c.stdout.strip()[:70] or _c.stderr.strip()[:70]))
    elif recipe == "C":
        git("add", "--", "a.txt", env=env)        # no seed at all
        other_unit_commits()                      # <-- THE RACE
        _c = git("commit", "-q", "--only", "-m", f"unit A recipe {recipe}", "--", "a.txt", env=env)
        if _c.returncode: REFUSED.append((recipe, _c.returncode, _c.stderr.strip()[:70]))
    else:
        raise SystemExit(f"no such recipe {recipe}")

    committed = out("rev-parse", "HEAD")
    subject = out("log", "-1", "--format=%s", committed)
    if subject != f"unit A recipe {recipe}":
        # MY COMMIT DID NOT LAND. The other unit's commit is HEAD, so HEAD's tree looks
        # PERFECT -- and that is exactly how a broken recipe reads as a clean pass.
        return [f"REFUSED-MY-COMMIT-DID-NOT-LAND (HEAD is {subject!r})"], committed, ""
    parent = out("rev-parse", "HEAD^")
    # THE HEAD THE COMMIT WAS BUILT ON TOP OF -- but the OTHER unit's commit is its SIBLING.
    # The question is: does the commit's tree carry the OTHER unit's work?
    sibling = out("rev-parse", "HEAD^@")        # both parents, if a merge
    t_mine = tree_of(committed)
    swept = []
    for p in ("b.txt", "c.txt", "d.txt"):
        if p in t_mine:
            continue                              # present: fine either way
        swept.append(f"DELETED {p}")
    # the other unit's LATEST bytes must be present
    for p, want in (("b.txt", "b2\n"), ("d.txt", "d1\n")):
        if p not in t_mine:
            continue
        blob = out("rev-parse", f"{committed}:{p}")
        content = subprocess.run(["git", "cat-file", "blob", blob], cwd=REPO,
                                 capture_output=True, text=True).stdout
        if content != want:
            swept.append(f"REVERTED {p} ({content!r} != {want!r})")
    # and MY path must be in the commit
    if "a.txt" not in t_mine:
        swept.append("MISSING my own a.txt")
    return swept, committed, sibling


def new_file_with_only(trials=TRIALS):
    """RECIPE C ON A NEW FILE -- the case that matters, because agents CREATE files
    (`gates/nn-rows-gate.py` and friends), and `--only` on an UNTRACKED path is where a
    commit recipe usually falls over."""
    sweeps = 0
    example = ""
    for _ in range(trials):
        build_repo()
        idx = REPO / ".git" / "unit-index"
        if idx.exists():
            idx.unlink()
        env = {"GIT_INDEX_FILE": str(idx)}
        (REPO / "new.py").write_text("print('hello')\n")
        git("add", "--", "new.py", env=env)
        other_unit_commits()
        r = git("commit", "-q", "--only", "-m", "unit A: a new file", "--", "new.py", env=env)
        if r.returncode != 0:
            sweeps += 1
            example = example or f"COMMIT REFUSED: {r.stderr.strip()[:80]}"
            continue
        t = tree_of(out("rev-parse", "HEAD"))
        bad = []
        if "new.py" not in t:
            bad.append("MISSING new.py")
        for p, want in (("b.txt", "b2\n"), ("d.txt", "d1\n")):
            if p not in t:
                bad.append(f"DELETED {p}")
                continue
            blob = out("rev-parse", f"HEAD:{p}")
            content = subprocess.run(["git", "cat-file", "blob", blob], cwd=REPO,
                                     capture_output=True, text=True).stdout
            if content != want:
                bad.append(f"REVERTED {p}")
        if bad:
            sweeps += 1
            example = example or "; ".join(bad)
    return sweeps, example


def main():
    build_repo()
    print(f"  repo: {REPO}")
    print(f"  trials per recipe: {TRIALS}")
    print()
    results = {}
    for recipe in ("A", "B", "C"):
        build_repo()
        sweeps = 0
        example = ""
        for i in range(TRIALS):
            swept, commit, sib = mine_after_their_commit(recipe)
            if swept:
                sweeps += 1
                if not example:
                    example = "; ".join(swept)
        results[recipe] = (sweeps, example)
        print(f"  recipe {recipe}: swept {sweeps} of {TRIALS} trials" + (f"   e.g. {example}" if example else ""))
    print()
    print(f"  THE RECIPE THAT SWEEPS 0 of {TRIALS}: "
          + ", ".join(r for r, (s, _) in results.items() if s == 0))
    print(f"  THE RECIPES THAT SWEEP: "
          + (", ".join(f"{r} ({s}/{TRIALS})" for r, (s, _) in results.items() if s) or "none"))
    s, ex = new_file_with_only()
    print(f"  recipe C on a NEW (untracked) file: swept {s} of {TRIALS}" + (f"   e.g. {ex}" if ex else ""))
    # THE SELFCHECK: a recipe whose commits REFUSED reads as "0 swept" unless the refusal
    # is counted. It IS counted (a refusal returns a non-empty list), so a pass here is a
    # pass: the commit landed AND it swept nothing.
    print()
    if REFUSED:
        print(f"  SELFCHECK: {len(REFUSED)} REFUSED commit(s) -- a refusal is NOT a pass:")
        for r, rc, msg in REFUSED[:4]:
            print(f"    {r} rc={rc} {msg!r}")
    else:
        print(f"  SELFCHECK: OK -- 0 refused commits, so every 'swept 0' above is a real pass "
              f"(the commit landed and carried nothing of the other unit's)")
    # LEAVE NO REPO INSIDE A REPO: a throwaway .git under this tree confuses every
    # `git ls-files` / `git status` in the outer tree.
    shutil.rmtree(REPO, ignore_errors=True)
    print(f"  cleaned up {REPO}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
