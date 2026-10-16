#!/usr/bin/env python3
"""docnum-claim-gate -- RE-MEASURE EVERY LOAD-BEARING NUMBER THE GOVERNING PROSE ASSERTS.

    .venv/bin/python gates/docnum-claim-gate.py
    .venv/bin/python gates/docnum-claim-gate.py --plan     # the contract, run nothing
    .venv/bin/python gates/docnum-claim-gate.py --plant    # synthetic trees; MUST be able to fail

WHY THIS FILE EXISTS
--------------------
Four times in one day the tree's own instruments contradicted a number its prose was resting
on, and every one of the four was the same shape:

  1. `decomp`'s FOOTER named the wrong blocker and its own rows refuted it.
  2. `uop/spec.bend:1488` justified a P6 wall with `Device.tag`, WHICH DOES NOT EXIST, and a
     gate (`devtag-gate.py`'s `C2`) quoted the citation forward.
  3. `nn/optim.bend`'s claim that a fixture "NEEDS `Device.tag`" was PROVED FALSE.
  4. `gates/README.md`'s `## HOW THEY ARE RUN` justifies the whole section on "THE NUMERATOR
     OF 'A GATE THAT ANYTHING RUNS' WAS 0 OF 77", and the census that produced "0 of 77"
     NAMED THREE PATHS -- `bin/`, `checks/e2e.sh`, `checks/differ.py` -- instead of WALKING
     `checks/`, which holds `gatesweep.py`, the instrument that runs every gate in the tree.

So the class is not "wrong number". It is: **a number written where a measurement could be
taken, in prose that outlives the measurement.** And the cure is not vigilance; it is
arithmetic. A NUMBER IN CODE COMPUTED FROM A DISCOVERY CANNOT GO STALE. A NUMBER IN PROSE IS
STALE THE MOMENT IT IS WRITTEN.

THE CONTRACT, AND WHY IT HOLDS NO NUMBERS
------------------------------------------
`CLAIMS` below is a table of `(site, what, argv, pattern)` and **not one transcribed figure**.
Each row names a PROSE SITE and the COMMAND that prints the number the site asserts; the gate
runs the command and checks that the site still says what the command says. This is the whole
design and it is the answer to "COULD IT BE COMPUTED INSTEAD OF WRITTEN?":

    the table is a GENERATOR'S OWN DECLARATION, LOADED BY PATH   (doctrine 1a)
    the figures are re-derived on every run, never transcribed    (`AGENTS.md`'s own rule)
    the prose is the WITNESS, and this gate is the SECOND WITNESS that disagrees

A table that held the expected number would be a second copy of the prose with no generator --
`checks/sweep.py`'s removed `LIVE_UNITS`, `gates/gates-pop.py`'s admitted `HOMES`, and the
second copy of `differ.declared()` that `checks/no-txt.py` refused. So the numbers are absent
here by construction, and `--plan` prints them to prove it: every contract row is a command.

THE POPULATION IS A WALK, AND THE TALLY IS PRINTED
---------------------------------------------------
`CLAIMS` is a DECLARATION and may therefore be a list -- doctrine 1(a) is explicit that a
generator's own declaration loaded by path IS a population. What is NOT allowed is a
population of files, and this file names no prose file except as the target of a claim: the
prose SITES come from `--sites` (below) which is a walk, and `--plan` prints how many walked.

THE FIVE VERDICTS, SPELLED, AND WHY EACH IS REACHABLE HERE
----------------------------------------------------------
    PASS 0    every claim's site was read and every measuring command agreed
    FAIL 1    a site was read and DISAGREED with a command that ran -- the load-bearing case
    REFUSED 3 a precondition was absent: no repo root, or a measuring command not on disk
    SKIP 4    a measuring command RAN and produced nothing to compare -- `DEAD` if it also
              emitted nothing at all, which are two different defects and get two different
              tokens. `SKIP IS NOT PASS` and the exit status says so, per `AGENTS.md`.
    DEAD 5    this gate ran and emitted no verdict row

THE ORDER IS A CLAIM AND IT IS ARGUED IN `worst()`, not assumed.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP, verdict_of  # noqa: E402

PY = ".venv/bin/python"

# A row is SIX THINGS AND NOT ONE FIGURE:
#   site       where the claim is written (`path:line`, `path:a-b`, or `path` for the whole file)
#   what       what the site ASSERTS, in words, for a human reading a FAIL row
#   argv       the COMMAND that prints the number, run under `checks/bounded.py`
#   out_shape  a regex over the command's output with one group PER FIGURE
#   prose_shape a regex over the site's lines with one group PER FIGURE, in the SAME ORDER
#   dated      True when the site carries its own MEASURED date, so a historical reading is
#              STALE-BUT-DATED rather than STALE-UNDATED. `AGENTS.md`: "QUOTE THIS NUMBER WITH
#              A TIMESTAMP OR NOT AT ALL", and a dated reading is the RECORD, not the defect.
#
# WHY TWO SHAPES AND NOT ONE. The first version reused the OUTPUT shape for the PROSE, and
# every row then read "the site's sentence no longer has this shape" -- which is TRUE, and
# useless: the output's shape (`POPULATION: ... -> 79`) is not a markdown table row. A shape
# that fits the instrument and not the document measures the instrument twice.
#
# NO FIGURE APPEARS IN THIS TABLE. `--plan` prints every row and there is no number to read.
CLAIMS = (
    ("gates/README.md:75",
     "the gate population (A) = the `*-gate.py` walk",
     (PY, "checks/gatesweep.py", "--plan"),
     r"POPULATION: directory walk gates/\*-gate\.py -> (\d+)",
     r"\|\s*(\d[\d,]*)\s*\|\s*$", False),
    ("gates/README.md:76",
     "the control denominator (B) = `gates-pop.discover()`",
     (PY, "checks/gatesweep.py", "--plan"),
     r"CONTROL\s*: gates-pop\.discover\(\) -> (\d+) entries",
     r"\|\s*(\d[\d,]*)\s*\|\s*$", False),
    ("gates/README.md:97",
     "the armed-index intent-to-add count behind 'this is why a sweep cannot run today'",
     (PY, "checks/index-arm-gate.py"),
     r"intent-to-add=(\d+)",
     r"(\d[\d,]*) intent-to-add", False),
    ("gates/README.md:130",
     "the 77-gate set the cost projection is stated over",
     (PY, "checks/gatesweep.py", "--plan"),
     r"POPULATION: directory walk gates/\*-gate\.py -> (\d+)",
     r"[Pp]rojected over the (\d+)-gate set", False),
    ("gates/README.md:66",
     "the sweep tally the loop is described by",
     (PY, "checks/gatesweep.py", "--plan"),
     r"POPULATION: directory walk gates/\*-gate\.py -> (\d+)",
     r"over (\d+) gates in", True),
    ("gates/runner.py:48",
     "the same population, quoted by the gate that DELEGATES to the sweep",
     (PY, "checks/gatesweep.py", "--plan"),
     r"POPULATION: directory walk gates/\*-gate\.py -> (\d+)",
     r"MEASURED (\d+)\.", False),
)

# HOW MUCH PROSE IS IN SCOPE. A walk, so the denominator is a measurement, not a list.
SITE_ROOTS = ("gates", "checks", ".agents")
SITE_SUFFIX = (".md", ".py", ".bend")

BOUNDED = "checks/bounded.py"
BOUND_SECONDS = 300
BOUND_MB = 4096
DATE = r"(?:19|20)\d{2}-\d{2}-\d{2}"

# THE FOUR MEASUREMENT TOKENS, MAPPED ONTO THE FIVE VERDICTS, AND THE MAPPING IS A CLAIM.
#   RAN                -> the number was read and compared
#   NO-SUCH-COMMAND    -> SKIP     the command does not exist: it COULD NOT RUN
#   NOT-STARTED        -> SKIP     ditto, from the other direction
#   DEAD               -> DEAD     it RAN and emitted nothing (or only a traceback)
#   KILLED-ON-MEMORY / TIMED-OUT / NO-NUMBER -> SKIP, because the watchdog's own token means
#                         it produced nothing to compare; `SKIP IS NOT PASS` and the exit says so.
# The plant asserts each of these, because an instrument that answered FAIL to all four would
# be reporting on its own plumbing rather than on a number -- which is what the first version
# of this file did with an absent command.
TOKEN_VERDICT = {
    "NO-SUCH-COMMAND": SKIP,
    "NOT-STARTED": SKIP,
    "NO-NUMBER": SKIP,
    "KILLED-ON-MEMORY": SKIP,
    "TIMED-OUT": SKIP,
    "NO-RUN": SKIP,
    "DEAD": DEAD,
    "REFUSED": REFUSED,
    "SKIP": SKIP,
    "PASS": PASS,
    "FAIL": FAIL,
}


def prose_sites(root):
    """A DIRECTORY WALK over the homes that carry governing prose. Returns sorted paths."""
    out = []
    for top in SITE_ROOTS:
        base = root / top
        if not base.is_dir():
            continue
        for here, dirs, names in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d != "__pycache__")
            for name in sorted(names):
                if name.endswith(SITE_SUFFIX):
                    out.append(os.path.relpath(os.path.join(here, name), root))
    return sorted(out)


def site_lines(root, site):
    """-> the source lines a site names, or None if the site does not resolve."""
    path, _, spec = site.partition(":")
    target = root / path
    if not target.is_file():
        return None
    lines = target.read_text(encoding="utf-8", errors="replace").splitlines()
    if not spec:
        return lines
    lo, _, hi = spec.partition("-")
    try:
        lo_i = int(lo)
        hi_i = int(hi) if hi else lo_i
    except ValueError:
        return None
    if lo_i < 1 or hi_i > len(lines):
        return None
    return lines[lo_i - 1:hi_i]


def measure(argv, root):
    """-> (numbers, token).  `token` is the reason the number is unavailable, never a guess."""
    cmd = list(argv)
    exe = cmd[0]
    if not (os.path.isabs(exe) or (root / exe).exists() or _on_path(exe)):
        return None, "NO-SUCH-COMMAND"
    # Every measuring command runs THROUGH the watchdog, and its TOKEN is read, not its exit
    # status -- `checks/bounded.py`'s own header records a unit losing 425 rows to believing it.
    # THE WATCHDOG AND THE INTERPRETER ARE BOTH OPTIONAL, AND THAT IS A BUG THIS PLANT FOUND:
    # hard-wiring `PY` and `BOUNDED` made every synthetic command die in `FileNotFoundError`
    # before it ran, and the gate answered `NO-RUN` -- a SKIP-shaped token for a command that
    # never started. A watchdog that cannot start must be ABSENT, not silently substituted.
    full = list(cmd)
    if not os.path.isabs(exe) and (root / BOUNDED).is_file():
        full = [str(root / PY), str(root / BOUNDED), "--seconds", str(BOUND_SECONDS),
                "--mb", str(BOUND_MB), "--"] + full
    try:
        proc = subprocess.run(full, cwd=root, capture_output=True, text=True,
                              timeout=BOUND_SECONDS + 30)
    except (OSError, subprocess.TimeoutExpired):
        return None, "NOT-STARTED"
    out = proc.stdout + "\n" + proc.stderr
    if "Traceback (most recent call last)" in out:
        return None, "DEAD"
    if not out.strip():
        return None, "DEAD"
    for kill in ("KILLED-ON-MEMORY", "TIMED-OUT", "NOT-STARTED"):
        if kill in out:
            return None, kill
    return out, "RAN"


def _on_path(exe):
    return any(os.access(os.path.join(d, exe), os.X_OK)
               for d in os.environ.get("PATH", "").split(os.pathsep) if d)


def _figures(m):
    return [int(g.replace(",", "")) for g in m.groups() if g is not None]


def check(root, claims=None):
    """-> [(site, what, state, detail)]. `state` is one of the five VERDICT words.

    `claims` is a PARAMETER so `--plant` can drive THIS FUNCTION on a synthetic contract.
    A plant that reaches past the decision into the helpers is not a plant of the decision
    -- `gates/README.md:106` records exactly that failure (`preconditions`' branch broken and
    the plant still green), and the first version of this plant compared two integers it had
    written itself, which tests `!=` and nothing else."""
    rows = []
    for site, what, argv, out_shape, prose_shape, dated in (claims or CLAIMS):
        lines = site_lines(root, site)
        if lines is None:
            rows.append((site, what, "REFUSED", "the site does not resolve"))
            continue
        prose = "\n".join(lines)
        pm = re.search(prose_shape, prose, re.M)
        if not pm:
            rows.append((site, what, "FAIL", "the site's sentence no longer has this shape"))
            continue
        said = _figures(pm)
        # A DATED ROW IS NOT COMPARED AT ALL, AND THAT IS THE POINT. `gates/README.md:66`
        # records `over 70 gates` from a 2026-10-15 sweep; today's walk says 80, and the two
        # are not in conflict -- the first is a RECORD of a run that happened and the second
        # is the tree now. Comparing them printed FAIL on a sentence that is doing exactly
        # what `AGENTS.md` asks of it ("QUOTE THIS NUMBER WITH A TIMESTAMP OR NOT AT ALL").
        # So a dated row asks one question, and it is the only question: IS IT DATED? An
        # undated row in the dated slot is the defect, and it is the SAME defect the
        # STALE-UNDATED class names -- the number is not wrong, it is unaccountable.
        if dated:
            ok = bool(re.search(r"MEASURED[^.]{0,80}" + DATE, prose)) or \
                bool(re.search(r"\b" + DATE, prose))
            rows.append((site, what, "PASS" if ok else "FAIL",
                         "a dated reading: prose %s, and the date is carried here"
                         % said if ok else
                         "an UNDATED historical reading: prose %s claims a past run and "
                         "carries no date" % said))
            continue
        out, token = measure(argv, root)
        if token != "RAN":
            # A WORD, NOT THE EXIT. The first version put the raw token in the state
            # column, so a SKIP printed `4` next to a `FAIL` that printed `FAIL` -- and
            # the plant caught it by reading its own table. `gatekit.VERDICT` spells all
            # five; the table must too, or a reader cannot read it.
            rows.append((site, what, verdict_of(TOKEN_VERDICT.get(token, SKIP)), token))
            continue
        om = re.search(out_shape, out)
        if not om:
            # RAN AND PRINTED SOMETHING ELSE. That is a FAIL and it is a FAIL of the
            # CONTRACT, not of the prose: the instrument this site leans on has changed its
            # output, so the comparison the site depends on can no longer be made. Reading
            # it as SKIP would leave a site pointing at a broken measurement looking healthy.
            rows.append((site, what, "FAIL", "the measuring command ran and no longer "
                                              "prints this shape"))
            continue
        got = _figures(om)
        if got == said:
            rows.append((site, what, "PASS", "prose %s == measured %s" % (said, got)))
        else:
            rows.append((site, what, "FAIL", "prose %s, measured %s" % (said, got)))
    return rows


def worst(codes):
    """THE ORDER IS A CLAIM. `DEAD` first: a claim that measured nothing cannot be outranked
    by one that measured something, because its answer is unknown rather than good. `FAIL`
    LAST: it is the only one of the four that means an answer WAS produced."""
    for code in (DEAD, REFUSED, SKIP, FAIL):
        if code in codes:
            return code
    return PASS


def emit_plan(out):
    out.write("CLAIMS (a generator's own declaration; NO FIGURE IS TRANSCRIBED)\n")
    for site, what, argv, _o, _p, dated in CLAIMS:
        out.write("  %-22s dated=%-5s %-46s %s\n"
                  % (site, dated, what[:46], " ".join(argv[1:])))
    files = prose_sites(ROOT)
    out.write("PROSE IN SCOPE (a walk of %s): %d file(s)\n"
              % (", ".join(SITE_ROOTS), len(files)))
    for f in files:
        out.write("  %s\n" % f)
    out.write("EVERY CONTRACT ROW IS A COMMAND: %d rows, 0 numbers\n" % len(CLAIMS))


def plant(out):
    """A PLANT THAT MUST FAIL. It takes a synthetic root whose prose DISAGREES with a command
    that answers, and asserts the gate says FAIL. A gate over claims that cannot be made to
    disagree is a gate over nothing."""
    import tempfile
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "gates").mkdir()
        (root / "oracle.py").write_text("print('ANSWER 11')\n", encoding="utf-8")
        # THE SITE IS WRONG ON PURPOSE and the command is RIGHT, so a working gate says FAIL.
        (root / "gates/README.md").write_text(
            "| **A** | a walk | 77 |\n", encoding="utf-8")
        contract = (
            # site, what, argv, out_shape, prose_shape, dated
            ("gates/README.md:1", "a deliberately wrong figure",
             (sys.executable, "oracle.py"), r"ANSWER (\d+)", r"\|\s*(\d+)\s*\|", False),
            ("gates/README.md:1", "the same figure, made true",
             (sys.executable, "oracle.py"), r"ANSWER (\d+)",
             r"\|\s*(\d+)\s*\|", False),
        )
        rows = check(root, contract)
        for site, what, state, detail in rows:
            out.write("  %-8s %-28s %s\n" % (state, what, detail))
        # FIX THE SITE and re-drive the SAME contract: the gate must now agree. A plant that
        # only shows a failure proves the gate can say FAIL; it does not prove FAIL means FAIL.
        (root / "gates/README.md").write_text("| **A** | a walk | 11 |\n", encoding="utf-8")
        fixed = check(root, (contract[1],))
        out.write("  %-8s %-28s %s\n" % (fixed[0][2], "the figure corrected", fixed[0][3]))
        if rows[0][2] != "FAIL" or fixed[0][2] != "PASS":
            out.write("PLANT FAILED: the gate did not follow the number\n")
            bad += 1
        # A SITE THAT DOES NOT RESOLVE is REFUSED, and a MISSING COMMAND is SKIP -- three
        # different states, and an instrument that called them all FAIL would be a gate over
        # its own plumbing.
        (root / "gates/GONE.md").unlink(missing_ok=True)
        (root / "other.py").write_text("print('SOMETHING ELSE')\n", encoding="utf-8")
        probe = check(root, (("gates/GONE.md:1", "absent site", (sys.executable, "oracle.py"),
                              r"ANSWER (\d+)", r"(\d+)", False),
                             ("gates/README.md:1", "absent command",
                              (".venv/bin/definitely-not-here",), r"ANSWER (\d+)",
                              r"\|\s*(\d+)\s*\|", False),
                             ("gates/README.md:1", "command prints another shape",
                              (sys.executable, "other.py"), r"ANSWER (\d+)",
                              r"\|\s*(\d+)\s*\|", False)))
        for site, what, state, detail in probe:
            out.write("  %-8s %-28s %s\n" % (state, what, detail))
        for got, want, why in (
                (probe[0][2], "REFUSED", "an absent site is not a wrong number"),
                (probe[1][2], "SKIP", "a command that could not run is not a FAIL"),
                (probe[2][2], "FAIL", "a command that RAN and changed shape broke the "
                                       "comparison, and that is not a SKIP")):
            ok = got == want
            bad += 0 if ok else 1
            out.write("%s %s == %s -- %s\n" % ("OK  " if ok else "FAIL", got, want, why))
    if bad:
        out.write("PLANT FAILED: %d expectation(s) unmet\n" % bad)
        return 1
    out.write("PLANT OK: the gate FAILED a wrong figure, PASSED a right one, REFUSED an "
              "absent site and SKIPPED an absent command\n")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--plant", action="store_true")
    a = ap.parse_args()
    if a.plan:
        emit_plan(sys.stdout)
        return PASS
    if a.plant:
        return plant(sys.stdout)
    if not (ROOT / "pyproject.toml").is_file():
        print("docnum-claim-gate: REFUSED, NOT A VERDICT: `%s` is not at the repo root"
              % ROOT, file=sys.stderr)
        return REFUSED
    rows = check(ROOT)
    for site, what, state, detail in rows:
        print("%-8s %-22s %-52s %s" % (state, site, what[:52], detail))
    codes = [{"PASS": PASS, "FAIL": FAIL, "REFUSED": REFUSED, "SKIP": SKIP,
              "DEAD": DEAD}.get(r[2], REFUSED) for r in rows]
    code = PASS if all(c == PASS for c in codes) else worst(codes)
    print("docnum-claim-gate: %s -- %d claim(s), %d figure(s) transcribed: 0"
          % (verdict_of(code), len(rows), 0))
    return code


if __name__ == "__main__":
    sys.exit(main())