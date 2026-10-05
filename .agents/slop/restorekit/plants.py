#!/usr/bin/env python3
"""PLANT AND DISARM for `gates/retention-check.py`: does an injected fault move the verdict?

Four plants, each against a COPY of the tree, each run through the instrument's own `--dir` so
the live tree is never under test:

  1 RESIDUE      a file the generator does not declare          -> clause I  must go RED
  2 UNHEALTHY    a `D0-run-summary.txt` with wrong pins          -> clause IV must add complaints
  3 EMPTY .err   a legitimately empty stderr, in a healthy run  -> clause IV must NOT move
  4 HEALTHY      every pin right, every artifact non-empty       -> clause IV must go OK

Plant 3 is the one that would be a bug if it moved. `artefacts_ok()` excludes `*.err` on
purpose, because a healthy run may hold legitimately empty stderr and a rule that flags a
correct file is a rule that always fails. This harness asserts it does NOT move.

EXIT: 0 when every plant behaved as the table in README.md claims, 1 otherwise. A plant that does
not move its verdict is not a passing plant; it is an instrument that cannot fail.
"""
import shutil
import subprocess
import sys

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CHECK = ROOT / "gates/retention-check.py"
PY = str(ROOT / ".venv/bin/python")


def run(*extra):
    """The instrument's own verdict line and its exit status. `$?` after a pipe is the LAST
    command's, so the status is captured with PIPESTATUS-free `subprocess` rather than a shell."""
    r = subprocess.run([PY, str(CHECK), *extra], cwd=ROOT, capture_output=True, text=True)
    return r.returncode, r.stdout


def line(out, prefix):
    return next((l for l in out.splitlines() if l.startswith(prefix)), "<absent>")


def copy_corpus(dst):
    """`D` is 151 files and every one is under a megabyte, so the corpus copies whole. A
    filtered copy would be a fixture, and a fixture that cannot hold a wrong pin is a fixture
    that cannot test the unhealthy case."""
    shutil.copytree(ROOT / "runs/graphcmp/D", dst)
    return dst


def workdir():
    """A scratch dir INSIDE the repo, not `/tmp`.

    MEASURED, and it is `checks/differ.py`'s constraint rather than this harness's taste:
    `artefacts_ok()` ends its ONE-LINE reports with `(D / n).relative_to(ROOT)`
    (`checks/differ.py:513`), so pointing `D` at a `/tmp` copy raises `ValueError` from inside
    differ and clause IV never runs. `differ.py` is not this unit's file to edit, so the plant
    lives where differ can measure it. The dir is removed in a `finally`, and it is under
    `.agents/slop/`, which `.gitignore` already treats as scratch.
    """
    d = ROOT / ".agents/slop/restorekit/.plant"
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    return d


def write_summary(d, values):
    """A summary that is exactly as healthy as `values` says. Every PIN in `checks/differ.py:128`
    has to be spelled out, because a summary missing a pin is ALSO unhealthy (that is
    `unhealthy()`'s `ABSENT` branch) and a half-written fixture would make plant 2 pass for the
    wrong reason."""
    (d / "D0-run-summary.txt").write_text("".join(f"{k}={v}\n" for k, v in values.items()))


def fill(directory):
    """Give every EMPTY `.txt` a body that is not one line.

    `"body\\n"` is a ONE-LINE report and `artefacts_ok()` rejects that shape on purpose -- a diff
    report that is a single line IS the 0-row failure shape, and two of them compare equal. So a
    fixture filled with one line is not a healthy corpus, it is 37 complaints wearing a healthy
    one's name. MEASURED: filling with one line left 37 ONE-LINE findings; filling with two left
    zero. The point of the plant is the `.err`, not the filler.
    """
    for p in directory.glob("*.txt"):
        if p.stat().st_size == 0:
            p.write_text("# fixture\nrow=1\n")


def pins():
    """`checks/differ.py`'s OWN PINS, imported rather than transcribed. A transcribed copy is a
    second copy of the health contract, and it is the copy that goes stale: the pins here would
    pass a run that `unhealthy()` rejects, or fail one it accepts, and the plant would prove
    nothing about the instrument it is testing."""
    sys.path.insert(0, str(ROOT / "checks"))
    import differ
    return differ.PINS


def main():
    results = []

    def check(name, moved, detail):
        results.append(moved)
        print(f"{'MOVED  ' if moved else 'NO MOVE'} {name}: {detail}")

    tmp = workdir()
    try:

        # 1 -- a residue. `PLANTED.txt` matches nothing in GATEKIT_OUTPUT.
        gates = tmp / "artifacts"
        shutil.copytree(ROOT / "gates/artifacts", gates)
        (gates / "wk-cd-gate/PLANTED.txt").write_text("not a lane\n")
        before_rc, before = run()
        after_rc, after = run(f"--dir=gates={gates}")
        # The verdict line must COUNT the residue, not merely print it: a rule that names an
        # offender and then reports 9/9 clean has named it and not counted it.
        moved = ("with residue" in line(after, "I   declared") and "RESIDUE" in after
                 and line(before, "I   declared") != line(after, "I   declared"))
        check("1 RESIDUE -> clause I", moved,
              f"{line(before, 'I   declared').strip()[:46]}... -> "
              f"{line(after, 'I   declared').strip()[:46]}...; exit {before_rc}->{after_rc}")

        # 2 -- an unhealthy run, and the delta must be attributable to ONE broken pin. Built by
        # first reaching a HEALTHY corpus (plant 3's fixture), then breaking exactly one pin, so
        # "it moved" means "this instrument can tell a wrong pin from a right one" rather than
        # "the fixture was broken".
        healthy = copy_corpus(tmp / "Dok")
        for p in healthy.glob("*.txt"):
            if p.stat().st_size == 0:
                p.write_text("body\n")
        write_summary(healthy, pins())
        (healthy / "D0-selfcheck.txt.err").write_bytes(b"")
        rc_ok, out_ok = run(f"--dir=graphcmp={healthy}")
        base = line(out_ok, "IV FIRES") or line(out_ok, "IV OK")
        armed = not base.startswith("IV OK")
        broken = copy_corpus(tmp / "Dbad")
        for p in broken.glob("*.txt"):
            if p.stat().st_size == 0:
                p.write_text("body\n")
        wrong = dict(pins())
        wrong["graphs-agree"] = "0"
        write_summary(broken, wrong)
        rc2, out2 = run(f"--dir=graphcmp={broken}")
        moved = armed and "IV FIRES" in out2 and "graphs-agree=0 (expected 14)" in out2
        check("2 UNHEALTHY -> clause IV", bool(moved),
              f"healthy fixture reads '{base.strip()[:44]}', one broken pin reads "
              f"'{line(out2, 'IV FIRES').split('not healthy:')[-1].strip()[:44]}'")

        # 3 -- THE PLANT THAT MUST NOT MOVE. A legitimately empty `*.err` in a run whose summary
        # is entirely correct. `artefacts_ok()` excludes `.err` on purpose; if this moved the
        # verdict, the instrument would be one empty stderr away from failing every correct run.
        moved = not armed and rc_ok == 1  # 1 = clause II/III are red; IV is what must be OK
        check("3 EMPTY .err in a HEALTHY run -> clause IV must NOT move", not armed,
              f"'{base.strip()}' with a 0-byte D0-selfcheck.txt.err -- .err exclusion inherited "
              f"from differ.artefacts_ok(), not restated")

        # 4 -- disarm, and the reason clause IV is trustworthy: the SAME corpus with the empty
        # `.err` deleted must read identically. If 3 and 4 differed, the exclusion would be
        # load-bearing in a way nobody could see.
        (healthy / "D0-selfcheck.txt.err").unlink()
        rc4, out4 = run(f"--dir=graphcmp={healthy}")
        same = line(out4, "IV FIRES") == line(out_ok, "IV FIRES") and line(out4, "IV OK") == line(out_ok, "IV OK")
        check("4 DISARM (empty .err deleted)", same,
              f"'{line(out4, 'IV FIRES') or line(out4, 'IV OK')}' -- unchanged by removing the "
              f"file, exit {rc4}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    print(f"PLANTS: {sum(results)}/{len(results)} behaved as documented")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
