"""Plant: prove `checks/corpus-figure.py`'s `run_health()` can go BOTH ways.

A health check that cannot go red is a comment, and one that cannot go green is a
gate that will be skipped. So the plant runs the REAL script -- a byte-identical
copy -- against a scratch root, twice:

  A  green control. The live run's 4 red pins are repaired in the COPY, so all 17
     pins match. Expect `RUN HEALTH : OK -- 17 of 17 pins green` and rc=0. Without
     this half, "it refuses" is also consistent with "it always refuses".
  B  one red pin. The green copy with `graphs-agree` moved 19 -> 18. Expect
     `RUN HEALTH : **FAILED** -- 16 of 17` naming that pin, and rc=1.
  C  no summary at all. Expect `**NO RUN SUMMARY**` and rc=1: the old exit check
     looked for the absence of the word "FAILED", and a missing summary has neither,
     so it used to exit 0 -- a check that measured nothing reporting a pass.

THE LIVE TREE IS NEVER WRITTEN. The run directory is copied out of
`runs/graphcmp/D/` FIRST -- copy-first, because another unit may be
regenerating it -- and the script is copied into a scratch root whose own
`runs/graphcmp/D/` holds the planted bytes. `graphcmp.py` is symlinked, and it
resolves its own REPO through the symlink (`graphcmp.py:271`,
`Path(__file__).resolve()`), so the real tinygrad is what gets imported and the
copy is the real instrument, not a mock of one. The scratch is removed at the
end, so the tree is left with no duplicate `.txt` artifact names: they would
be excused by `no-txt.py`'s `differ.declared()` carve-out, but they would still
move the excused count this tree measures.
"""
import os
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent              # .agents/slop/figurefix/plant
ROOT = HERE.parents[3]                                      # repo root
SCRATCH = HERE / "scratch"
REPAIRS = [("expect-moved=1", "expect-moved=0"),
           ("graphs-agree=20", "graphs-agree=19"),
           ("byte-identical=20", "byte-identical=19"),
           ("selfcheck=# SELFCHECK: FAIL", "selfcheck=# SELFCHECK: OK")]


def build():
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    (SCRATCH / "checks").mkdir(parents=True)
    (SCRATCH / ".agents/slop").mkdir(parents=True)
    (SCRATCH / "runs/graphcmp").mkdir(parents=True)
    shutil.copy2(ROOT / "checks/corpus-figure.py", SCRATCH / "checks/corpus-figure.py")
    shutil.copy2(ROOT / "checks/devpin.py", SCRATCH / "checks/devpin.py")
    # `differ_pins()` reads `checks/differ.py` relative to the script's own ROOT, so
    # the scratch root needs the pin DECLARATION too. The live one is never written.
    shutil.copy2(ROOT / "checks/differ.py", SCRATCH / "checks/differ.py")
    (SCRATCH / ".agents/slop/graphcmp.py").symlink_to(ROOT / ".agents/slop/graphcmp.py")
    shutil.copytree(HERE / "D-live", SCRATCH / "runs/graphcmp/D")


def set_summary(pairs):
    p = SCRATCH / "runs/graphcmp/D/D0-run-summary.txt"
    t = p.read_text()
    for old, new in pairs:
        n = t.count(old)
        assert n == 1, f"{old!r} appears {n} times -- the plant edit is not unique"
        t = t.replace(old, new)
    p.write_text(t)


def run(tag):
    r = subprocess.run([str(ROOT / ".venv/bin/python"), str(SCRATCH / "checks/corpus-figure.py")],
                       capture_output=True, text=True, cwd=SCRATCH,
                       env={**os.environ, "DEV": "CPU"})
    lines = r.stdout.splitlines()
    health = next((ln for ln in lines if ln.startswith("RUN HEALTH")), "<no RUN HEALTH line>")
    device = next((ln for ln in lines if ln.startswith("DEVICE PRECONDITION")), "")
    built = next((ln for ln in lines if ln.startswith("graphs built")), "")
    print(f"{tag}: rc={r.returncode}")
    print(f"    {device}")
    print(f"    {built}")
    print(f"    {health}")
    return r.returncode, health


def main():
    build()
    print("plant A: green control -- the live run's 4 red pins repaired in the COPY")
    set_summary(REPAIRS)
    rc_a, health_a = run("A")
    ok_a = rc_a == 0 and "OK -- 17 of 17 pins green" in health_a
    print(f"    -> {'PASS' if ok_a else 'FAIL'}: expected rc=0 and 'OK -- 17 of 17 pins green'")
    print()
    print("plant B: ONE pin red -- graphs-agree moved 19 -> 18 on top of the green copy")
    set_summary([("graphs-agree=19", "graphs-agree=18")])
    rc_b, health_b = run("B")
    ok_b = (rc_b == 1 and "**FAILED** -- 16 of 17" in health_b
            and "graphs-agree=18 (expected 19)" in health_b)
    print(f"    -> {'PASS' if ok_b else 'FAIL'}: expected rc=1 naming 'graphs-agree=18 (expected 19)'")
    print()
    print("plant C: NO summary at all -- a check that measured nothing must not exit 0")
    summary = SCRATCH / "runs/graphcmp/D/D0-run-summary.txt"
    summary.unlink()
    rc_c, health_c = run("C")
    ok_c = rc_c == 1 and "**NO RUN SUMMARY**" in health_c
    print(f"    -> {'PASS' if ok_c else 'FAIL'}: expected rc=1 and the NO RUN SUMMARY line")
    return 0 if ok_a and ok_b and ok_c else 1


if __name__ == "__main__":
    sys.exit(main())
