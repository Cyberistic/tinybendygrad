#!/usr/bin/env python3
"""staged-guard-proof.py -- prove `staged_mut`'s guard FIRES, on real bytes.

    .venv/bin/python .agents/slop/staged-guard-proof.py

A GUARD THAT HAS NEVER BEEN SEEN TO FIRE IS A COMMENT.  This drives all three of
`staged_mut`'s outcomes to their real branch, and the substrate is a fixture file
this script creates, owns, and deletes -- so no agent's `.bend` is touched.

THE THREE OUTCOMES, and what each one is worth:

  A. `MirrorStale`   -- `sha256(jj @) != sha256(live)`.  PROVEN LIVE, because the
     mirror read uses `jj --ignore-working-copy file show -r @`, which does NOT
     snapshot.  Without that flag the branch is unreachable and the "assertion" is
     an identity: `jj file show -r @` commits the working-copy edit into `@`
     before the comparison, so the digests are equal by construction.  Both
     spellings are measured here, because the difference between them IS the
     finding.

  B. `LiveMoved`     -- the live digest moved between entry and exit.  PROVEN LIVE
     by writing the fixture mid-context.  This is the branch that would have
     caught `blob-intern-mutate.py`'s `finally` restore; here the only thing that
     moves the digest is the script itself, and the point is that the guard SEES it.

  C. no live write   -- the ordinary path: a full staged run leaves the live file
     byte-identical, and the staged copy is unlinked.  This is the property the
     whole module exists to provide, and it is the only one that is true rather
     than loud.

The fixture is a TRACKED repo file (`jj add`), because `Staged` refuses an untracked
subject -- `jj file show` cannot produce a mirror for it, and that refusal would
make every proof below test the wrong branch.  Nothing is committed.
"""
import hashlib
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
import staged_mut as S                                        # noqa: E402

FIXTURE = HERE / "guard-fixture.txt"       # 0o600, deleted on every exit
PRISTINE = b"GUARD FIXTURE\noriginal bytes\n"


def live_digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()[:16]


def jj_show(path, ignore):
    cmd = ["jj"] + (["--ignore-working-copy"] if ignore else []) + \
          ["file", "show", "-r", "@", "--", str(path.relative_to(ROOT))]
    r = subprocess.run(cmd, cwd=str(ROOT), capture_output=True)
    return r.returncode, r.stdout


def make_fixture():
    if FIXTURE.exists():
        FIXTURE.unlink()
    FIXTURE.write_bytes(PRISTINE)
    subprocess.run(["jj", "add", str(FIXTURE.relative_to(ROOT))],
                   cwd=str(ROOT), capture_output=True)
    # SNAPSHOT it, so `@` holds exactly PRISTINE and every probe below starts from
    # a known state.  This is the one jj call that is allowed to snapshot.
    jj_show(FIXTURE, ignore=False)
    return FIXTURE


def drop_fixture():
    if FIXTURE.exists():
        FIXTURE.unlink()


RESULTS = []


def claim(label, ok, detail=""):
    RESULTS.append((label, ok))
    print("  [%s] %s%s" % ("FIRED" if ok else "DID NOT FIRE", label,
                           ("\n         " + detail) if detail else ""), flush=True)


def part_zero():
    """THE MEASUREMENT THAT MAKES A AND B POSSIBLE.

    Both jj spellings, on the same perturbed file, in one run.  If these two lines
    agree, `MirrorStale` is unreachable and the guard in `staged_mut` is a comment.
    """
    print("0. THE MIRROR READ IS NOT A SNAPSHOT -- both spellings, one perturbation")
    f = make_fixture()
    f.write_bytes(PRISTINE + b"an uncommitted line\n")
    # ORDER IS THE MEASUREMENT.  The snapshotting spelling COMMITS the
    # perturbation into `@`, so it must be read SECOND -- read it first and both
    # calls agree for the wrong reason, which is exactly the false SAME this
    # whole exercise exists to catch.  It did agree on the first attempt here.
    _, frozen = jj_show(f, ignore=True)
    _, snapping = jj_show(f, ignore=False)
    print("     live bytes                                    %d" % (len(PRISTINE) + 22))
    print("     sha256(jj file show -r @)          SNAPSHOTS -> %s" %
          hashlib.sha256(snapping).hexdigest()[:16])
    print("     sha256(jj --ignore-working-copy ...)          %s" %
          hashlib.sha256(frozen).hexdigest()[:16])
    claim("the snapshotting spelling EQUALS live (so it can never raise MirrorStale)",
          hashlib.sha256(snapping).hexdigest() == hashlib.sha256(
              (PRISTINE + b"an uncommitted line\n")).hexdigest())
    claim("the --ignore-working-copy spelling DIFFERS from live (so it can raise)",
          hashlib.sha256(frozen).hexdigest() != hashlib.sha256(
              (PRISTINE + b"an uncommitted line\n")).hexdigest())
    f.write_bytes(PRISTINE)
    jj_show(f, ignore=False)                      # re-snapshot back to PRISTINE
    drop_fixture()


def part_a():
    print()
    print("A. MirrorStale -- an uncommitted edit on the substrate")
    f = make_fixture()
    f.write_bytes(PRISTINE + b"an uncommitted line\n")   # live != @
    try:
        S.Staged(f, "proof").__enter__()
        claim("Staged() raised MirrorStale", False, "it returned a staged mirror")
    except S.MirrorStale as e:
        claim("Staged() raised MirrorStale", True, str(e).splitlines()[0])
    f.write_bytes(PRISTINE)
    drop_fixture()


def part_b():
    print()
    print("B. LiveMoved -- the live digest moves DURING the run")
    f = make_fixture()
    fired = False
    try:
        with S.Staged(f, "proof") as g:
            f.write_bytes(PRISTINE + b"written by someone else\n")
            assert g.path.name.endswith(".staged-proof-%d" % os.getpid())
    except S.LiveMoved as e:
        fired = True
        claim("exiting the context raised LiveMoved", True, str(e))
    if not fired:
        claim("exiting the context raised LiveMoved", False, "it exited quietly")
    f.write_bytes(PRISTINE)
    drop_fixture()


def part_c():
    print()
    print("C. THE ORDINARY PATH -- a full run writes nothing live and leaves nothing")
    f = make_fixture()
    before = live_digest(f)
    staged_name = None
    with S.Staged(f, "proof") as g:
        staged_name = g.path.name
        g.write(g.origin().replace("original", "mutated"))
        assert g.text().count("mutated") == 1
    after = live_digest(f)
    claim("live %s is byte-identical after a staged mutation (%s)" % (f.name, before),
          before == after and f.read_bytes() == PRISTINE)
    claim("the staged copy %s was unlinked" % staged_name, not (f.parent / staged_name).exists())


def main():
    try:
        part_zero()
        part_a()
        part_b()
        part_c()
    finally:
        drop_fixture()
        subprocess.run(["jj", "forget", str(FIXTURE.relative_to(ROOT))],
                       cwd=str(ROOT), capture_output=True)
    print()
    print("D. NOTHING LEFT IN THE REPO -- a proof that deposits debris is not a proof")
    claim("the fixture file is gone", not FIXTURE.exists())
    debris = [p.name for p in HERE.glob("*staged-proof-*")]
    claim("no *.staged-proof-* debris anywhere under .agents/slop", not debris,
          ("found " + ", ".join(debris)) if debris else "")
    bad = [l for l, ok in RESULTS if not ok]
    print()
    print("%d/%d claims held%s" % (len(RESULTS) - len(bad), len(RESULTS),
                                   "" if not bad else "  FAILED: " + "; ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())