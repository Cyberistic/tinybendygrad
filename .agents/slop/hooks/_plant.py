#!/usr/bin/env python3
"""Plant the hook wiring in a SCRATCH CLONE. Never in the live tree.

Each state asserts BOTH the exit code AND the wording that produced it. A gate that exits
3 because it CRASHED is the `refusalsweep`/`envguard` failure, and rc alone cannot tell the
two apart -- so every refusal here is checked for `REFUSED, NOT A VERDICT` in the words.

  A  an honest commit PASSes `pre-commit` = `massdelete staged`
  B  a commit whose MESSAGE claims a deletion its DIFF lacks is REFUSED (3)
  C  THE POINT: the bad commit is HEAD, and an honest commit on top still PASSES
  D  the WRONG wiring (`msgdiff check HEAD`) refuses a CLEAN commit, for a claim about
     a DIFFERENT commit -- a policy wearing a hook's clothes
  E  the GATE shape: `range <local> --not <remote>` -> PASS, bad ancestor excluded BY REV-SET
  F  the POLICY shape: `range <all history>` -> REFUSED forever, even over a new honest commit
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

LIVE = Path(__file__).resolve().parents[3]
WORK = Path(os.environ.get("HOOKPLANT_W", "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/hookplant"))
PASS, FAIL, REFUSED = 0, 1, 3

# `msgdiff-gate.py:81-82` puts its own directory on sys.path and does `from gatekit import`,
# so gatekit is a RUNTIME dependency of the gate, not an optional shared library.
GATES = (".agents/slop/jjreset/git-massdelete-gate.py", "gates/msgdiff-gate.py", "gates/gatekit.py")
MASS = ".agents/slop/jjreset/git-massdelete-gate.py"
MSG = "gates/msgdiff-gate.py"
PY = sys.executable
BAD_MSG = "Deleted the superseded oracles259/plants.py after proving the survivor covers it."
FAKE = "oracles259/plants.py"


def git(root, *a, check=True):
    r = subprocess.run(["git", "-C", str(root), *a], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {a}: rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout


def gate(root, rel, *a):
    r = subprocess.run([PY, str(root / rel), *a], capture_output=True, text=True, cwd=str(root))
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def hook(root, name, body):
    p = root / ".git" / "hooks" / name
    p.write_text(body)
    p.chmod(0o755)


def commit(root, msg, path, body, verify=True):
    (root / path).write_text(body)
    git(root, "add", path)
    cmd = ["git", "commit", "-q", "-m", msg] + ([] if verify else ["--no-verify"])
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(root))
    return r.returncode, (r.stdout or "") + (r.stderr or "")


bad_state = []


def check(label, got, want):
    ok = got == want
    if not ok:
        bad_state.append(f"{label}: rc={got}, want {want}")
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: rc={got} want={want}")
    return ok


def words(label, out, needle, present=True):
    hit = needle in out
    ok = hit if present else not hit
    if not ok:
        bad_state.append(f"{label}: {needle!r} {'present' if hit else 'ABSENT'}, wanted "
                         f"{'present' if present else 'absent'}")
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: {needle[:46]!r} {'present' if hit else 'absent'}")


def main():
    if WORK.exists():
        shutil.rmtree(WORK)
    for g in GATES:
        (WORK / g).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(LIVE / g, WORK / g)
    git(WORK, "init", "-q", "-b", "main")
    git(WORK, "config", "user.email", "p@example.invalid")
    git(WORK, "config", "user.name", "plant")
    (WORK / "seed.tsv").write_text("a\n")
    git(WORK, "add", "seed.tsv")
    git(WORK, "commit", "-q", "-m", "seed")
    # The claimed path MUST EXIST, or the gate demotes the claim to "renamed_or_absent"
    # and PASSes -- a false pass, and one of the reasons the lane is narrow.
    (WORK / FAKE).parent.mkdir(parents=True, exist_ok=True)
    (WORK / FAKE).write_text("# the file the bad message says it deleted\n")
    git(WORK, "add", FAKE)
    git(WORK, "commit", "-q", "-m", "seed the file the bad message later claims to delete")
    root_shas = git(WORK, "rev-list", "--reverse", "HEAD").split()
    print(f"scratch clone: {WORK}\n")

    # -- A ---------------------------------------------------------------------
    hook(WORK, "pre-commit", f'#!/bin/sh\nexec "{PY}" "{WORK/MASS}" staged\n')
    rc, _ = commit(WORK, "add a row", "a.tsv", "b\n")
    print("A  honest commit, pre-commit = `massdelete staged` (reads the INDEX)")
    check("A honest commit passes", rc, 0)
    _, out = gate(WORK, MASS, "staged")
    words("A the gate named the index", out, "the staged index")

    # -- B ---------------------------------------------------------------------
    (WORK / "c.tsv").write_text("c\n")
    git(WORK, "add", "c.tsv")
    git(WORK, "commit", "-q", "--no-verify", "-m", BAD_MSG)
    badsha = git(WORK, "rev-parse", "HEAD").strip()
    print("\nB  the commit that CARRIES the false claim, judged on its own sha")
    rc, out = gate(WORK, MSG, "check", badsha)
    check("B msgdiff refuses it", rc, REFUSED)
    words("B refused, not crashed", out, "REFUSED, NOT A VERDICT")
    words("B names the undeleted path", out, FAKE)

    # -- C. THE POINT ----------------------------------------------------------
    # HEAD IS the bad commit right now. An honest commit on top must still go through.
    rc, _ = commit(WORK, "add another row", "d.tsv", "d\n")
    print("\nC  THE POINT -- honest commit while the bad commit is HEAD")
    check("C an honest commit is not blocked by a bad ancestor", rc, 0)
    _, out = gate(WORK, MSG, "check", badsha)
    words("C ...even though that ancestor still refuses on its own sha", out,
          "REFUSED, NOT A VERDICT")

    # -- D. THE WRONG WIRING ---------------------------------------------------
    # Make HEAD bad again, then wire the hook to `check HEAD` and try to commit honestly.
    (WORK / "e.tsv").write_text("e\n")
    git(WORK, "add", "e.tsv")
    git(WORK, "commit", "-q", "--no-verify", "-m", BAD_MSG)
    badsha2 = git(WORK, "rev-parse", "HEAD").strip()
    hook(WORK, "pre-commit", f'#!/bin/sh\nexec "{PY}" "{WORK/MSG}" check HEAD\n')
    rc, out = commit(WORK, "a clean commit with no claims whatsoever", "f.tsv", "f\n")
    print("\nD  THE WRONG WIRING -- pre-commit = `msgdiff check HEAD`")
    check("D it blocks a clean commit", rc, FAIL)
    words("D and it blocked it by judging the PREVIOUS commit", out, "REFUSED, NOT A VERDICT")
    words("D ...a commit the author is not changing", out, FAKE)
    print(f"   the message being written was: 'a clean commit with no claims whatsoever'")

    # -- E. THE GATE SHAPE -----------------------------------------------------
    remote = WORK.parent / "hookplant-remote"
    if remote.exists():
        shutil.rmtree(remote)
    subprocess.run(["git", "clone", "-q", "--bare", str(WORK), str(remote)],
                   capture_output=True, text=True)
    hook(WORK, "pre-commit", f'#!/bin/sh\nexec "{PY}" "{WORK/MASS}" staged\n')
    rc, _ = commit(WORK, "an honest commit to push", "g.tsv", "g\n")
    local_sha = git(WORK, "rev-parse", "HEAD").strip()
    remote_sha = git(remote, "rev-parse", "main").strip()
    print("\nE  THE GATE SHAPE -- `msgdiff range <local> --not <remote>`")
    rc, out = gate(WORK, MSG, "range", local_sha, "--not", remote_sha)
    check("E the already-pushed bad commits are out of scope", rc, PASS)
    words("E ...and nothing is refused", out, "0 REFUSED")
    in_scope = git(WORK, "rev-list", local_sha, "--not", remote_sha).split()
    print(f"   in scope: {len(in_scope)} commit(s); bad ones in that set: "
          f"{badsha in in_scope}/{badsha2 in in_scope}")

    # -- F. THE POLICY SHAPE ---------------------------------------------------
    # `range` passes its argv straight to `rev-list`, so the range is ONE argument
    # ("A..B"). Two endpoints is a UNION, not a range -- state G.
    first = root_shas[0]
    rc, out = gate(WORK, MSG, "range", f"{first}..HEAD")
    print("\nF  THE POLICY SHAPE -- `msgdiff range <first>..HEAD` (what jjreset ran)")
    check("F it refuses, permanently", rc, REFUSED)
    words("F refused for the right reason", out, "REFUSED, NOT A VERDICT")
    print(f"   {out.strip().splitlines()[-1]}  <- a new honest commit never clears this")

    # -- G. THE FOOTGUN -------------------------------------------------------
    rc_u, out_u = gate(WORK, MSG, "range", first, "HEAD")   # two endpoints, NOT "first..HEAD"
    print("\nG  `msgdiff range <first> HEAD` -- two ENDPOINTS, which `rev-list` unions")
    print(f"   rc={rc_u}; {out_u.strip().splitlines()[-1] if out_u.strip() else '<none>'}")
    print(f"   `range {first[:8]}..HEAD` = {out.strip().splitlines()[-1]}")
    if rc_u == rc and out_u.strip().splitlines()[-1:] == out.strip().splitlines()[-1:]:
        print("   SAME population -> this tree's `range` is a union either way, and the")
        print("   --not form is the ONLY thing that scoped it in E. Naming that.")
    else:
        words("G the two endpoint spellings differ", out_u, "REFUSED", present=False)

    ok = not bad_state
    print(f"\n--plant: {'all states OK' if ok else 'FAILED: ' + '; '.join(bad_state)}")
    return PASS if ok else FAIL


if __name__ == "__main__":
    sys.exit(main())
