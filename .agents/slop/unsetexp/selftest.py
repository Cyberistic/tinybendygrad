#!/usr/bin/env python3
"""PLANT AND DISARM the two refusals by RUNNING the driver against a stub, never the port.

    .venv/bin/python .agents/slop/unsetexp/selftest.py

WHY A STUB. The claim under test is about the DRIVER'S OWN LOGIC -- does a row that disagrees
with the port refuse the run -- and answering it needs no `bend`. It must also not be answered
by reading `cmd_run`: `txtgen`'s unit measured that four static checks re-deriving from the same
tables found zero drift, because both change together, and the only thing that settled it was
RUNNING the command in a sandbox and diffing what it WROTE. So this imports the real
`checks/differ.py`, points `GCMP` at a throwaway `graphcmp.py` whose every subcommand prints
canned lines, points `D` at a temp directory, and calls the real `cmd_run`.

**NOTHING THE LIVE TREE CAN SEE IS TOUCHED.** No `bend` runs (the three `capture()` probes are
the only steps that would have, so `capture` is stubbed and that stub is the ONE function
replaced, because the thing under test is in `cmd_run`, not in the oracle). `runs/graphcmp/D/` is
never written and the live `WANT`/`PINS` are restored in a `finally`.

THE FOUR STATES, each named as the state it forces:

    1 DISARMED  every row right, every graph answered -> rc 0, `expect-moved=0`
    2 PLANTED   one row expects AGREE, the stub emits DISAGREE -> rc != 0, `expect-moved=1`,
                the offender NAMED in the refusal and by `unhealthy()`
    3 PLANTED   one row deleted -> rc != 0, `graphs-unset` rises, `expect-moved` STAYS 0, so
                the two refusals are demonstrably different questions
    4 NEGATIVE  an UNANSWERED graph that DISAGREEs -> triaged as the stronger gap and NOT
                counted as a moved row

**A BELT WITH TWO METHODS THAT SHARE NO PARSER.** Each case asserts on the EXIT STATUS, on the
summary line read by a tokenizer written HERE, and on `unhealthy()` -- which re-reads the same
file through the driver's own `text()` and compares it against `PINS`. A check that shared the
harness's regex would prove the harness agrees with itself, which is how a tokenizer in this
project ate a full stop and its own belt missed it.
"""
import contextlib
import importlib.util
import io
import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]

STUB = '''
import sys

GRAPHS = {name: None for name in __NAMES__}
PLANTS = ("dtype", "srcswap")
VERDICTS = __VERDICTS__


def opt(a, flag, default="matmul"):
    """`--flag value` with a DEFAULT, because the driver omits `--graph` on the 0-row guard."""
    return a[a.index(flag) + 1] if flag in a else default


def main():
    a = sys.argv[1:]
    if a[:1] == ["diff"]:
        v = VERDICTS.get(opt(a, "--graph"), "AGREE")
        print("# DENOMINATOR: graphs=2 (1 py + 1 bend)  nodes=2/2  fields=6  field-records=12")
        print(f"# VERDICT: {v}")
        return 0 if v == "AGREE" else 1
    if a[:1] == ["emit"]:
        sys.stdout.write(f"STUB {opt(a, '--side')} {opt(a, '--graph')}\\n")
        return 0
    for cmd, line in (("selfcheck", "# SELFCHECK: OK"), ("control", "# CONTROL VERDICT: OK"),
                      ("cross", "# CROSS VERDICT: OK"), ("conf", "# VERDICT: OK")):
        if a[:1] == [cmd]:
            print(line)
            return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
'''
DISAGREE = ("lin", "loop", "allred", "cdiv", "late", "flip")
ANSWERED = [g for g in sorted(("allred alu binblob bit buffer bw cast cdiv commute flip gate group "
                               "indexed late lin loop matmul move range rangeflat reduce sink special "
                               "sym where").split()) if g not in ("alu", "bit", "bw", "move", "where")]
fails = []


def check(label, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'} {label}{'' if ok else '  <- ' + detail}")
    if not ok:
        fails.append(label)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def summary(differ):
    """METHOD TWO. A tokenizer written HERE, not `differ.text()` and not `unhealthy()`'s."""
    out = {}
    for line in (differ.D / "D0-run-summary.txt").read_text().splitlines():
        m = re.match(r"^([a-z][a-z-]*)=(\S.*?)\s*$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def drive(differ, verdicts, mutate=None):
    """One `cmd_run` in a temp `D`, with the stub corpus, and the refusal captured.

    **`ROOT` MOVES WITH `D`, AND THAT IS NOT COSMETIC.** `cmd_run` ends with
    `print(f"wrote {D.relative_to(ROOT)}")`, so a `D` outside the repo raises `ValueError` in the
    last line of the function under test. The alternative -- a sandbox inside the repo -- would
    put ~100 transient `.txt` files where `checks/no-txt.py`'s `os.walk(ROOT)` can see them, and
    that gate's carve-out is `runs/graphcmp/D` plus `declared()`. So the whole temp tree becomes
    the driver's `ROOT` and `PY` is made absolute for it.

    `mutate(differ)` may edit the loaded module's `WANT`/`PINS` before the run; the caller
    restores them in a `finally`, so case 3 plants a MISSING ROW without editing a file on disk.

    **THE TABLE IS RESET AT THE TOP OF EVERY CALL, NOT ONLY IN THE `finally`.** A plant left in
    the module is a plant that moves the NEXT case: case 3 deletes a row, and without the reset
    case 4 ran against a table that was already wrong, which is the same class as the repro in
    this project where a `rmtree` between beats made both sides read `NOTHING`.
    """
    differ.WANT.clear(), differ.WANT.update(WANT)
    differ.PINS.clear(), differ.PINS.update(PINS)
    tmp = pathlib.Path(tempfile.mkdtemp())
    stub = tmp / "graphcmp.py"
    stub.write_text(
        STUB.replace("__NAMES__", repr(tuple(ANSWERED + ["alu", "bit", "bw", "move", "where"])), 1)
             .replace("__VERDICTS__", repr(verdicts), 1))
    differ.ROOT, differ.D = tmp, tmp / "D"
    differ.GCMP, differ.PY = str(stub), str(ROOT / ".venv/bin/python")
    differ.D.mkdir(parents=True, exist_ok=True)
    # THE ONE FUNCTION REPLACED: the three `capture()` probes are the only steps that would run
    # `bend`, and this file's claim is about `cmd_run`. Each still writes its artifact, so
    # `artefacts_ok()` has a body to inspect and nothing reports success on a file nobody wrote.
    differ.capture = lambda out, script, stamp_rc=False: (
        differ.write(out, ("# ORACLE SELFCHECK: OK\n" if "census" in out else "# PROBE\n")
                     + ("rc=0\n" if stamp_rc else "")))
    if mutate:
        mutate(differ)
    err = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
        rc = differ.cmd_run(None)
    return tmp, rc, err.getvalue(), differ


def restore(differ, want, pins):
    differ.WANT.clear(), differ.WANT.update(want)
    differ.PINS.clear(), differ.PINS.update(pins)
    differ.ROOT, differ.D = ROOT, ROOT / "runs/graphcmp/D"
    differ.GCMP, differ.PY = ".agents/slop/graphcmp.py", ".venv/bin/python"


differ = load("differ_plant", ROOT / "checks/differ.py")
WANT, PINS = dict(differ.WANT), dict(differ.PINS)
GAP = ["alu", "bit", "bw", "move", "where"]          # the five with no row, live
GOOD = {g: ("DISAGREE" if g in DISAGREE else "AGREE") for g in ANSWERED}
# CASES 1-3 NEED A CLOSED TABLE, or the OTHER refusal masks the one under test. Filling the five
# here is a PLANT of the state "the table is complete", not a claim that those rows belong: cases
# 4 and 5 deliberately leave them out and assert on the live gap instead.
def closed(m):
    """The state "the table is complete": five `AGREE` rows that this file does NOT claim belong."""
    m.WANT.update({g: "AGREE" for g in GAP})

try:
    print("CASE 1 -- DISARMED: every row right, every graph answered")
    tmp, rc, err, d = drive(differ, GOOD, closed)
    kv, bad = summary(d), d.unhealthy()
    check("rc 0", rc == 0, f"rc={rc}; stderr={err.strip()[:120]}")
    check("expect-moved=0", kv.get("expect-moved") == "0", str(kv.get("expect-moved")))
    check("graphs-unset=0", kv.get("graphs-unset") == "0", str(kv.get("graphs-unset")))
    check("graphs=25", kv.get("graphs") == "25", str(kv.get("graphs")))
    check("METHOD 3: `unhealthy()` does not name expect-moved",
          not any("expect-moved" in b for b in bad), str(bad))
    check("the stub WAS asked about every graph -- a check that reads an artifact nobody wrote "
          "proves nothing",
          len(list(d.D.glob("D1-graph-*.txt"))) == 25, str(len(list(d.D.glob("D1-graph-*.txt")))))
    check("and every one of them has a body",
          all((d.D / f"D1-graph-{g}.txt").stat().st_size > 2 for g in d.corpus()))
    shutil.rmtree(tmp)

    print("\nCASE 2 -- PLANTED: `matmul`'s row says AGREE and the stub emits DISAGREE")
    planted = dict(GOOD, matmul="DISAGREE")
    tmp, rc, err, d = drive(differ, planted, closed)
    kv, bad = summary(d), d.unhealthy()
    check("rc != 0 -- a run whose table is WRONG is not a measurement of the table", rc != 0,
          f"rc={rc}")
    check("expect-moved=1", kv.get("expect-moved") == "1", str(kv.get("expect-moved")))
    check("METHOD 3: the pin is named, with its value", any(b.startswith("expect-moved=") for b in bad),
          str(bad))
    check("the OFFENDER is named in the refusal", "matmul" in err, err.strip()[:160])
    check("and NOBODY ELSE is: the other 24 rows are not reported as moved",
          (d.D / "D1-verdicts.txt").read_text().count("VERDICT=") == 1,
          (d.D / "D1-verdicts.txt").read_text()[:200])
    check("graphs-unset stays 0 -- the two refusals do not absorb each other",
          kv.get("graphs-unset") == "0", str(kv.get("graphs-unset")))
    shutil.rmtree(tmp)

    print("\nCASE 3 -- PLANTED: a row is DELETED (the state `expect-moved` must NOT be about)")
    tmp, rc, err, d = drive(differ, GOOD, lambda m: (closed(m), m.WANT.pop("indexed")))
    kv, bad = summary(d), d.unhealthy()
    check("rc != 0", rc != 0, f"rc={rc}")
    check("graphs-unset rises by one", kv.get("graphs-unset") == "1", str(kv.get("graphs-unset")))
    check("graphs-answered=24", kv.get("graphs-answered") == "24", str(kv.get("graphs-answered")))
    check("expect-moved STAYS 0 -- a missing row is not a wrong row", kv.get("expect-moved") == "0",
          str(kv.get("expect-moved")))
    check("the graph is still RUN and its real verdict still recorded",
          (d.D / "D1-graph-indexed.txt").read_text().count("VERDICT:") == 1)
    check("METHOD 3: the gap is named as a gap", any(b.startswith("graphs-unset=") for b in bad),
          str(bad))
    shutil.rmtree(tmp)

    print("\nCASE 4 -- NEGATIVE: an UNANSWERED graph is the OTHER gap, and is triaged by what it "
          "did")
    tmp, rc, err, d = drive(differ, dict(GOOD, **{"alu": "DISAGREE"}))
    lines = (d.D / "D1-verdicts.txt").read_text()
    check("rc != 0 while a gap remains", rc != 0, f"rc={rc}")
    check("the DISAGREEING gap is called the stronger one",
          re.search(r"^alu: VERDICT=DISAGREE EXPECTED=UNSET.*table is behind the port",
                    lines, re.M) is not None,
          next((l for l in lines.splitlines() if l.startswith("alu")), "no line"))
    for g in ("bit", "bw", "where"):
        check(f"`{g}` triaged as a bookkeeping gap, not a fault",
              re.search(rf"^{g}: VERDICT=AGREE EXPECTED=UNSET.*bookkeeping gap", lines, re.M) is not None,
              next((l for l in lines.splitlines() if l.startswith(g)), "no line"))
    check("expect-moved is still 0 -- a graph with NO row cannot be a WRONG row",
          summary(d).get("expect-moved") == "0", str(summary(d).get("expect-moved")))
    check("the refusal names all five gaps", all(g in err for g in GAP), err.strip()[:200])
    check("graphs-unset=5 on the LIVE table", summary(d).get("graphs-unset") == "5")
    shutil.rmtree(tmp)

    print("\nCASE 5 -- THE PLANT THAT CANNOT MOVE: a planted verdict on an UNANSWERED graph")
    tmp, rc, err, d = drive(differ, dict(GOOD, flip="AGREE"), lambda m: m.WANT.pop("flip"))
    lines = (d.D / "D1-verdicts.txt").read_text()
    check("expect-moved=0 -- the graph is REPORTED, not COMPARED",
          summary(d).get("expect-moved") == "0", str(summary(d).get("expect-moved")))
    check("so its planted verdict is triaged, never counted as a wrong row",
          re.search(r"^flip: VERDICT=AGREE EXPECTED=UNSET.*bookkeeping gap", lines, re.M) is not None,
          next((l for l in lines.splitlines() if l.startswith("flip")), "no line"))
    check("and the run still refuses, because the gap did not close", rc != 0, f"rc={rc}")
    shutil.rmtree(tmp)
finally:
    restore(differ, WANT, PINS)

print(f"\n{'ALL PASS' if not fails else str(len(fails)) + ' FAILED: ' + ', '.join(fails)}")
sys.exit(1 if fails else 0)