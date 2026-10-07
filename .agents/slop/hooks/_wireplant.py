#!/usr/bin/env python3
"""Prove the hooks `wire.py` GENERATES actually work, in a scratch clone.

The generator is the unit under test, not the gates: `wire.py` is what was never run, so
what needed planting was its OUTPUT. States:

  1  pre-commit fires on an honest commit and passes (rc 0)
  2  pre-commit REFUSES (3) a staged mass delete, and the refusal reaches the tree
  3  pre-push REFUSES (3) a pushed commit whose message the diff does not witness
  4  THE VERDICT FILE: git flattened the exit code, so the hook recorded 3 where
     `git commit`/`git push` returned 1 -- REFUSED is recoverable only from the file
  5  a pre-existing bad commit already on the remote does NOT refuse a new honest push
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

LIVE = Path(__file__).resolve().parents[3]
WORK = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/wireplant")
REMOTE = WORK.parent / "wireplant-remote"
PY = sys.executable
bad = []


def git(*a, cwd=WORK, check=True):
    r = subprocess.run(["git", "-C", str(cwd), *a], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {a}: rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout


def check(label, got, want):
    ok = got == want
    if not ok:
        bad.append(f"{label}: rc={got}, want {want}")
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: rc={got} want={want}")


def scaffold():
    if WORK.exists():
        shutil.rmtree(WORK)
    for g in (".agents/slop/jjreset/git-massdelete-gate.py", "gates/msgdiff-gate.py",
              "gates/gatekit.py", ".agents/slop/hooks/wire.py",
              ".agents/slop/hooks/pushshim.py"):
        (WORK / g).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(LIVE / g, WORK / g)
    git("init", "-q", "-b", "main")
    git("config", "user.email", "p@example.invalid")
    git("config", "user.name", "wire")
    (WORK / "seed.tsv").write_text("a\n")
    git("add", "seed.tsv")
    git("commit", "-q", "-m", "seed")
    (WORK / "oracles259").mkdir()
    (WORK / "oracles259/plants.py").write_text("# real file, for the message to mis-claim\n")
    git("add", "oracles259/plants.py")
    git("commit", "-q", "-m", "seed the file the bad message later claims to delete")


def main():
    scaffold()
    print(f"scratch clone: {WORK}\n")
    # generate the hooks INTO the scratch clone's .git/hooks, with --install
    r = subprocess.run([PY, str(WORK / ".agents/slop/hooks/wire.py"), "--install"],
                       capture_output=True, text=True, cwd=str(WORK))
    print("wire.py --install ->", (r.stdout or "").strip().replace("\n", " | "))
    for name in ("pre-commit", "pre-push"):
        p = WORK / ".git/hooks" / name
        print(f"   {name}: {'executable' if os.access(p, os.X_OK) else 'NOT EXECUTABLE'}")

    # -- 1 ---------------------------------------------------------------------
    (WORK / "a.tsv").write_text("b\n")
    git("add", "a.tsv")
    r = subprocess.run(["git", "commit", "-m", "add a row"], capture_output=True,
                       text=True, cwd=str(WORK))
    print("\n1  honest commit through the generated pre-commit")
    check("1 honest commit passes", r.returncode, 0)

    # -- 2 ---------------------------------------------------------------------
    # >500 files staged for deletion is the REFUSED band. Made as real files, cheaply.
    big = WORK / "big"
    big.mkdir()
    for i in range(520):
        (big / f"f{i}.tsv").write_text(f"{i}\n")
    git("add", "big")
    git("commit", "-q", "-m", "seed 520 files")
    git("rm", "-r", "-q", "--cached", "big")
    for i in range(520):
        (big / f"f{i}.tsv").unlink()
    big.rmdir()
    r = subprocess.run(["git", "commit", "-m", "delete them all"], capture_output=True,
                       text=True, cwd=str(WORK))
    print("\n2  a 520-file deletion staged, through the same pre-commit")
    check("2 the mass delete is REFUSED", r.returncode, 1)
    print(f"   gate said: {next((l for l in r.stderr.splitlines() if 'REFUSED' in l), '<none>')[:88]}")
    print(f"   git commit returned {r.returncode} -- state 4 explains why that is not 3")
    git("reset", "-q", "--hard", "HEAD")

    # -- 3/4/5 -----------------------------------------------------------------
    if REMOTE.exists():
        shutil.rmtree(REMOTE)
    subprocess.run(["git", "clone", "-q", "--bare", str(WORK), str(REMOTE)],
                   capture_output=True, text=True)
    (WORK / "c.tsv").write_text("c\n")
    git("add", "c.tsv")
    git("commit", "-q", "--no-verify", "-m",
        "Deleted the superseded oracles259/plants.py after proving the survivor covers it.")
    (WORK / "d.tsv").write_text("d\n")
    git("add", "d.tsv")
    git("commit", "-q", "-m", "an honest commit on top of the bad one")
    print("\n3  pre-push, with a bad-message commit already in the local set")
    p = subprocess.run(["git", "push", "-q", str(REMOTE), "main"], capture_output=True,
                       text=True, cwd=str(WORK))
    check("3 the pushed bad message is REFUSED", p.returncode, 1)
    said = next((l for l in (p.stdout + p.stderr).splitlines() if "REFUSED" in l), "<none>")
    print(f"   gate said: {said[:88]}")

    vf = WORK / ".agents/slop/hooks/last-verdict.tsv"
    print("\n4  the verdict FILE, which is the only place REFUSED survives")
    print("   " + (vf.read_text().strip() if vf.exists() else "<no file written>"))
    got = vf.read_text().strip().splitlines()[-1].split("\t") if vf.exists() else []
    ok = len(got) >= 3 and got[2] == "3"
    if not ok:
        bad.append(f"4: verdict file says {got}")
    print(f"  {'ok  ' if ok else 'FAIL'} 4 the file records 3 where git returned "
          f"{p.returncode} (REFUSED is not in git's exit code)")

    # -- 5 ---------------------------------------------------------------------
    # State 3's push was REFUSED, so the bad commit is NOT on the remote and state 5 would
    # be re-testing state 3. Land it deliberately with the gate's own ack, THEN push an
    # honest commit over it: that is the scenario the brief is really about.
    env = dict(os.environ, MESSAGE_DIFF_ACK="planted on purpose")
    r = subprocess.run(["git", "push", "-q", str(REMOTE), "main"], capture_output=True,
                       text=True, cwd=str(WORK), env=env)
    print("\n5  the bad commit is now ON the remote; a new honest push must go through")
    print(f"   (it landed by ack: push rc={r.returncode})")
    (WORK / "e.tsv").write_text("e\n")
    git("add", "e.tsv")
    git("commit", "-q", "-m", "an honest commit, pushed after the bad one landed")
    vf.unlink(missing_ok=True)
    p = subprocess.run(["git", "push", "-q", str(REMOTE), "main"], capture_output=True,
                       text=True, cwd=str(WORK))
    check("5 the honest push is NOT blocked by the pushed bad commit", p.returncode, 0)
    print(f"   verdict file after: {vf.read_text().strip() if vf.exists() else '<none>'}")

    ok = not bad
    print(f"\n--wireplant: {'all states OK' if ok else 'FAILED: ' + '; '.join(bad)}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
