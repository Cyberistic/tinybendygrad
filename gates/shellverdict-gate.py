#!/usr/bin/env python3
"""shellverdict-gate.py -- CAN A SHELL GATE SAY WHAT IT MEANS?

    .venv/bin/python gates/shellverdict-gate.py            # the census
    .venv/bin/python gates/shellverdict-gate.py --rows     # rows only
    .venv/bin/python gates/shellverdict-gate.py --plant    # make it MOVE, on a synthetic tree

**THE INSTRUMENT THIS ONE FILLS A MEASURED HOLE IN, AND THE HOLE IS A POPULATION.**
`gates/verdictcopy-gate.py:143` builds its population with `endswith(".py")`, and MEASURED
2026-10-19T04:27Z it printed `population 322 .py under checks/gates/`. `checks/sb-gate.sh` is
not one of those 322. So the tree's only census of "can this guard tell `DEAD` from `FAIL`"
**cannot see the shell half at all** -- and `AGENTS.md` doctrine 1's sentence applies verbatim:
*an instrument that cannot see its population cannot be wrong, because it cannot be anything.*

**THE QUESTION, IN TWO HALVES, AND THE SECOND IS THE ONE THAT HAS A FINDING.**

  1 `EXIT`   For every shell entry point, every integer its source can `exit`, and the word
             `gates/gatekit.py`'s own table gives that integer.
  2 `TOKEN`  `checks/bounded.py` publishes five run TOKENS (`WITHIN-LIMITS`,
             `KILLED-ON-MEMORY`, `TIMED-OUT`, `NOT-STARTED`, `NO-VERDICT`). A shell gate that
             names a token in a `case` arm charges it an EXIT CODE, and `checks/gatesweep.py`'s
             `classify()` -- the consumer that reads that code -- has an opinion about the same
             token that it derived from the token ALONE. **When the gate's code and the
             consumer's code disagree, the same physical event is two verdicts, and neither is
             wrong on its own.** That is a `TOKEN-MISMATCH` row, and it is `FAIL`.

**MEASURED, NOT ASSERTED. One real kill, no `bend`:**

    $ .venv/bin/python checks/bounded.py --seconds 30 --mb 64 -- \\
          .venv/bin/python -c 'a=bytearray(400*1024*1024)'
    [bounded] KILLED-ON-MEMORY  rc=-9  peak-RSS=177 MB (ceiling 64)      # 2026-10-19T04:26:39Z
    classify('KILLED-ON-MEMORY', 3, ...)          -> ('SKIP', 'KILLED-ON-MEMORY')
    classify('WITHIN-LIMITS',     3,
             '== REFUSED, NOT A VERDICT: ... KILLED ON MEMORY')
                                                  -> ('REFUSED', 'REFUSED')

Same code, same consumer, one state, two words. `checks/sb-gate.sh` charged 3 to a kill
because `checks/gatesweep.py:315` and `gates/README.md:146` both call a kill a `SKIP`. **A
SHARED NUMBER IS NOT A SHARED VOCABULARY, AND NEITHER IS A MAPPING EVERY GATE HAS TO
REINVENT CORRECTLY.**

**EVERYTHING IS LOADED BY PATH AND NOTHING IS RETYPED**, which is the whole discipline:
`gates/gates-pop.py:discover()` is the population, `gates-pop.shell_code()` is the
comment-stripper (a scanner that reads a gate's own changelog finds roots it does not have --
`gates-pop.py:395`), `gates/gatekit.py:VERDICT` is the vocabulary, `checks/bounded.py` is the
token set, and `checks/gatesweep.py:classify` is the consumer whose opinion is compared. A
second copy of the vocabulary is the defect this file exists to name.

**AN UNRESOLVED ARM IS NOT AGREEMENT.** A `case` arm this file cannot resolve to an exit --
a function it cannot find, a body with no `exit` -- prints `unresolved` and is charged to
neither. `AGENTS.md`: "`DEAD` is not a zero and not a pass", and `gates/lane-census.py`'s
"0 disagreements over 0 comparisons" is indistinguishable from agreement. **A ROW THAT
COULD NOT BE READ MAY NOT SCORE GREEN.**

FIVE VERDICTS, `gates/gatekit.py`'s OWN EXITS, `PASS, FAIL, REFUSED, SKIP, DEAD = 0,1,3,4,5`.
NO `bend`: this file reads source and calls two shipped decision functions. Nothing here
compiles the port.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import shutil
import sys
import tempfile
import warnings
from pathlib import Path

warnings.simplefilter("ignore")   # `gates-pop.py` compiles two regexes whose docstrings
                                   # carry invalid escapes; its own caller suppresses them and
                                   # a syntax warning on stderr is noise beside a verdict row

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}

EXIT_RE = re.compile(r"\bexit\s+(\d+)\b")
EXIT_DYNAMIC_RE = re.compile(r"\bexit\b(?!\s+\d)")
FUNC_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{", re.M)
CASE_RE = re.compile(r"^\s*([A-Za-z_][A-Z0-9_-]*)\)\s*(.*?)(?:;;|\nesac)", re.M | re.S)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        spec.loader.exec_module(mod)
    return mod


gpop = _load("sv_gpop", HERE / "gates-pop.py")
gatekit = _load("sv_gatekit", HERE / "gatekit.py")
bounded = _load("sv_bounded", ROOT / "checks" / "bounded.py")
sweep = _load("sv_sweep", ROOT / "checks" / "gatesweep.py")

# `checks/bounded.py`'s OWN token tuple, read off its names rather than re-spelled: five strings
# and a `STATUS` table, and this file needs both the strings (to find the `case` arms) and the
# codes (to say what the WATCHDOG exits, which is not the same number as the verdict).
TOKENS = {getattr(bounded, n): getattr(bounded, "STATUS").get(getattr(bounded, n), 0)
          for n in ("WITHIN", "MEMORY", "TIMEOUT", "UNSTARTED", "NOVERDICT")}


def functions(src):
    """`name -> body` for every `name() { ... }` in comment-stripped shell.

    One regex that cannot nest, and that says so: `}` closes the innermost body it opened, so
    a function containing a brace group reports a body that ends early. **That is a KNOWN
    IMPRECISION AND IT IS REPORTED**, because the alternative -- a hand-written brace counter
    for one grammar -- is the second grammar this file would own. A function this cannot find
    makes its arms `unresolved`, never green.
    """
    out = {}
    for m in FUNC_RE.finditer(src):
        end = src.find("}", m.end())
        if end != -1:
            out[m.group(1)] = src[m.end():end]
    return out


def arm_exit(body, funcs, depth=0):
    """The exit code a `case` arm reaches, or `None` when this file cannot tell.

    Resolution order, and each step is a CLAIM this file is willing to make: a command that
    names a local function is that function's literal `exit`; else a literal `exit` in the arm
    body; else nothing. `None` is printed and never scored.
    """
    if depth > 2:
        return None
    m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)", body)
    if m and m.group(1) in funcs:
        return arm_exit(funcs[m.group(1)], funcs, depth + 1)
    lit = EXIT_RE.search(body)
    if lit:
        return int(lit.group(1))
    if m and m.group(1) in ("true", ":", "echo", "cat", "grep", "wc", "tr", "sed", "tail"):
        return None          # printed and fell through: no exit at all, which is its own state
    return None


def census(root):
    """`rows` -- one `EXIT` row per literal exit, one `TOKEN` row per bounded-token case arm."""
    with warnings.catch_warnings():      # `gates-pop` re-parses `.rows` fixtures on every call
        warnings.simplefilter("ignore")
        entries, _ = gpop.discover(root)
    rows = []
    for p in sorted(entries):
        if (gpop.entry_reason(p) or "").split("-")[0] != "sh":
            continue
        rel = str(p.relative_to(root))
        try:
            src = gpop.shell_code(p.read_text(errors="replace"))
        except OSError as e:
            rows.append(f"EXIT\t{rel}\t-\tUNREADABLE {type(e).__name__}\tcounted")
            continue
        funcs = functions(src)
        for code in sorted({int(c) for c in EXIT_RE.findall(src)}):
            rows.append(f"EXIT\t{rel}\t{code}\t{VERDICT.get(code, 'UNASSIGNED')}\tcensus")
        if EXIT_DYNAMIC_RE.search(EXIT_RE.sub("", src)):
            rows.append(f"EXIT\t{rel}\tdynamic\tUNRESOLVED\tcensus")
        for pat, body in CASE_RE.findall(src):
            if pat not in TOKENS:
                continue
            charged = arm_exit(body, funcs)
            consumer = sweep.classify(pat, TOKENS[pat], "the watchdog reported this token")[0]
            if charged is None:
                rows.append(f"TOKEN\t{rel}\t{pat}\tcharged=-\tconsumer={consumer}\tUNRESOLVED")
            else:
                agree = "yes" if VERDICT.get(charged) == consumer else "NO"
                rows.append(f"TOKEN\t{rel}\t{pat}\tcharged={charged}({VERDICT.get(charged, 'UNASSIGNED')})"
                            f"\tconsumer={consumer}\t{agree}")
    return rows


def reachable(rows):
    """`instrument -> the five it can emit`, printed so an ABSENT verdict is a visible count.

    READ FROM THE ROWS AND NOT BY A SECOND PASS: `gates-pop.discover()` re-parses `.rows`
    fixtures on every call and emits `SyntaxWarning`s, so asking the tree twice asks it twice.
    """
    per = {}
    for r in rows:
        f = r.split("\t")
        per.setdefault(f[1], set()).add(int(f[2]) if f[2].isdigit() else None)
    for rel, codes in sorted(per.items()):
        have = sorted(c for c in codes if c is not None)
        print(f"  {rel:<40} emits {have}  missing {[c for c in VERDICT if c not in have]}")


PLANT = """#!/bin/sh
set -eu
_d=${0%%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.."
s3() { echo said-3; exit 3; }
s4() { echo said-4; exit 4; }
s5() { echo said-5; exit 5; }
case "${tok:-NONE}" in
  KILLED-ON-MEMORY) s%d ;;
  TIMED-OUT)        s%d ;;
  WITHIN-LIMITS)    : ;;
  NO-VERDICT)       s%d ;;
esac
"""
# THE MAPPING `checks/gatesweep.py:classify` ASSIGNS TO EACH TOKEN, and it is not one number:
# a kill and a timeout are both `SKIP`, a run that emitted nothing is `DEAD`, and only
# `WITHIN-LIMITS` is the absence of a token. So the clean plant is `4 4 5` and not `4 4 4` --
# **A PLANT THAT PUTS EVERY TOKEN ON ONE EXIT IS PLANTING A GATE THAT IS WRONG**, and the
# detector saying so is the detector working.
WRONG, RIGHT = (3, 3, 3), (4, 4, 5)
# `exit "$2"` is the other unreadable shape, and it is planted too: an indirection this file
# cannot resolve must print `UNRESOLVED`, because `gates/lane-census.py`'s "0 disagreements
# over 0 comparisons" is indistinguishable from agreement and this file must not mint one.
DYNAMIC = PLANT.replace('s3() { echo said-3; exit 3; }', 's3() { echo said-3; exit "$2"; }')
SUBJECT = "checks/sb-gate.sh"
# A synthetic tree still has to be a TREE THIS INSTRUMENT'S POPULATION WILL LOOK AT, and
# `gates-pop.gate_homes()` admits a home only when an immediate file both carries every marker
# in `_CERTIFY` plus one of `_CERTIFY_OR` AND declares a ROOT (`gates-pop.py:877`). MEASURED on
# a temp tree with markers but no root assertion: `rejected ['checks 1/2']`, `discover()` returns
# `([], [])` -- an EMPTY POPULATION, which this file would have reported as agreement. So the
# plant copies the files `gate_homes` itself names as `checks`' witnesses. **THOSE NAMES COME FROM
# THE REAL TREE'S OWN DERIVATION, not from a list in this file**, so a witness that moves cannot
# make the plant vacuous.
CERTIFIER = "".join(f"{n}\n" for n in gpop._CERTIFY) + gpop._CERTIFY_OR[0] + "\nif __name__ == '__main__':\n    pass\n"


def seed(root):
    """Make `root/checks/` a home this instrument's population will admit."""
    (root / "checks").mkdir(parents=True, exist_ok=True)
    names = gpop.gate_homes(ROOT)[1]["witnesses"].get("checks", ())
    for rel in names:
        dst = root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / rel, dst)
    if not names:                       # the derivation is empty: say so rather than fake one
        (root / "checks" / "certify.py").write_text(CERTIFIER)


def _mismatches(root):
    return [r for r in census(root) if r.split("\t")[0] == "TOKEN" and r.endswith("NO")]


def plant(root):
    """THREE SYNTHETIC TREES. A plant that perturbs something the detector does not read
    proves only that the tree parses.

    A. the same synthetic file with every token arm on one exit, and with the per-token
       mapping `4 4 5` -- same population, same tokenizer, same vocabulary, three integers;
    B. THE REAL `checks/sb-gate.sh`, its own live bytes, and then the SAME BYTES with its
       `KILLED-ON-MEMORY` arm reverted from `skip` to `refuse`. A detector that cannot see the
       defect when it is reintroduced into the file this file was written about is a detector
       that measured nothing. **It does not read `git show HEAD:`**, and that is on purpose:
       the fix moved HEAD, so a plant that reads the blob goes red for having been right.
    C. an arm whose exit this file CANNOT resolve, which must read `UNRESOLVED` and must NOT
       score green -- because an unread row is not an agreeing row.
    """
    d = root / "checks"
    seed(root)
    f = d / "plant-shellverdict-gate.sh"
    f.write_text(PLANT % WRONG)
    f.chmod(0o755)
    wrong = len(_mismatches(root))
    f.write_text(PLANT % RIGHT)
    right = len(_mismatches(root))
    f.unlink()

    real = d / "sb-gate.sh"
    live = (ROOT / SUBJECT).read_text()
    real.write_text(live)
    at_live = len(_mismatches(root))
    # THE PERTURBATION IS THE ONE-LINE REVERSION OF THE FIX, ON THE REAL FILE'S OWN BYTES.
    # An earlier version of this plant read the defect out of `git show HEAD:...`, and that was
    # a CHANGE-DETECTOR wearing a plant's clothes: the fix moved HEAD, the blob stopped being
    # broken, and the plant went red for having been RIGHT. `AGENTS.md`: "change-detector tests
    # considered harmful". **A PLANT MUST NOT DEPEND ON THE REPOSITORY STILL BEING BROKEN.**
    perturbed = live.replace('KILLED-ON-MEMORY) skip "', 'KILLED-ON-MEMORY) refuse "')
    same = perturbed == live
    real.write_text(perturbed)
    at_perturbed = len(_mismatches(root))
    real.unlink()

    unresolved = (PLANT % RIGHT).replace("KILLED-ON-MEMORY) s4 ;;", "KILLED-ON-MEMORY) : ;;")
    f.write_text(unresolved)
    f.chmod(0o755)
    unres = [r for r in census(root) if r.endswith("UNRESOLVED") and "KILLED-ON-MEMORY" in r]
    f.write_text(DYNAMIC % WRONG)
    f.chmod(0o755)
    dyn = [r for r in census(root) if r.endswith("UNRESOLVED") and "KILLED-ON-MEMORY" in r]

    results = [
        ("A  one exit on every token arm is caught", wrong == 3, f"{wrong} mismatching row(s)"),
        ("A  the per-token mapping is clean", right == 0, f"{right} mismatching row(s)"),
        (f"B  {SUBJECT} live bytes are clean", at_live == 0, f"{at_live} row(s)"),
        ("B  reverting its KILLED-ON-MEMORY arm moves the row",
         (not same) and at_perturbed > at_live, f"{at_live} -> {at_perturbed}"),
        ("C  a `:` arm is UNRESOLVED, not green", len(unres) == 1, f"{len(unres)} row(s)"),
        ("C  a `exit \"$2\"` arm is UNRESOLVED, not green", len(dyn) == 1, f"{len(dyn)} row(s)"),
    ]
    for what, ok, detail in results:
        print(f"  {'ok  ' if ok else 'FAIL'} {what:<52} {detail}")
    return PASS if all(ok for _, ok, _ in results) else FAIL


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rows", action="store_true", help="rows only")
    ap.add_argument("--plant", action="store_true", help="drive the census on synthetic trees")
    ap.add_argument("--root", default=str(ROOT))
    a = ap.parse_args(argv)
    if a.plant:
        with tempfile.TemporaryDirectory() as t:
            return plant(Path(t))
    root = Path(a.root).resolve()
    rows = census(root)
    if not rows:
        print("REFUSED, NOT A VERDICT: the census found no rows, which is not agreement")
        return DEAD
    bad = [r for r in rows if r.endswith("\tNO")]
    unresolved = [r for r in rows if r.endswith("UNRESOLVED")]
    if not a.rows:
        print(f"shellverdict: population {len({r.split(chr(9))[1] for r in rows})} shell entry points "
              f"(gates-pop.discover, by path); vocabulary gatekit.VERDICT (by path); "
              f"consumer checks/gatesweep.py:classify (by path)")
        reachable(rows)
        for r in bad:
            print("  MISMATCH " + r.replace("\t", "  "))
        for r in unresolved:
            print("  UNRESOLVED " + r.replace("\t", "  "))
    else:
        print("\n".join(rows))
    print(f"shellverdict: {len(rows)} rows; {len(bad)} TOKEN disagreement(s); "
          f"{len(unresolved)} unresolved (charged to NEITHER verdict)")
    # **ONLY A TOKEN DISAGREEMENT FAILS, AND THE `EXIT` HALF IS A CENSUS.** An integer outside
    # `gatekit.VERDICT` is not an undiscovered defect -- `gatekit.charge()` already assigns one
    # to `REFUSED` and `checks/gatesweep.py:329` already prints `UNASSIGNED(n)`, MEASURED on 4
    # live `.sh` gates in `gates/artifacts/gates-sweep.rows` (`checks/run-all.sh`,
    # `checks/run-f64.sh`, `checks/run-port-mm.sh`, `checks/lint_demo.sh`, all `UNASSIGNED(2)`).
    # A gate that goes red on a class the tree already handles, on 12 sites, forever, is a
    # change-detector -- `AGENTS.md`: "change-detector tests considered harmful". So the `EXIT`
    # rows are PRINTED and the TOKEN rows are CHARGED, because a TOKEN disagreement is the one
    # thing no consumer can see: both numbers are in the table and they mean different events.
    return FAIL if bad else PASS


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))