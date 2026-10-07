#!/usr/bin/env python3
"""REACHABILITY, BY PLANTING. Runs a curated set of states and records the exit + token.

    .venv/bin/python .agents/slop/coindependent/probe.py            # run, print the table
    .venv/bin/python .agents/slop/coindependent/probe.py --rows     # same, TSV to stdout

NO `bend` IS STARTED. Every command below was chosen to reach a verdict WITHOUT the port
compiler -- a missing input, a plant argument, a synthetic tree, or an at-rest read. A gate whose
only states need `bend` is recorded as NOT-TESTED, which is a refusal of this instrument and not a
verdict about the gate: the rule is `AGENTS.md`'s, *"a gate demonstrated only in its green state
has been shown to do nothing"*, and the honest response is to say so rather than guess.

THIS IS NOT A POPULATION BY DISCOVERY -- it is a hand list of EXPERIMENTS, which is the correct
shape for a plant: an experiment is an act, and the acts we can perform are not a set the tree
declares. The POPULATION of gates is `vocab.py`'s `os.walk`; this file chooses which of them to
TRY TO BREAK, and the two are joined in `REPORT.md`. A hand list of experiments cannot be called
a population and is labelled one here so that it cannot be mistaken for one.
"""
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = str(ROOT / ".venv" / "bin" / "python")

# A token is a verdict word the tree prints. Kept separate from exit codes: `OK`/`RED` have no
# exit and `REFUSED` has both.
WORD = re.compile(r"\b(PASS|FAIL|REFUSED|SKIP|DEAD|OK|RED|GREEN|CLEAN|BROKEN|INCOMPLETE|"
                  r"UNMEASURABLE|STALE|TIMED-OUT|KILLED-ON-MEMORY|WITHIN-LIMITS|NOT A VERDICT)\b")

# (gate, state, argv). `state` is the CONDITION the command is meant to present, so the table
# reads as "gate X, in state Y, answer Z". `expect` is NOT asserted -- the measurement is the
# point -- but a state whose rc is 0 is marked GREEN and one > 0 RED in the report.
EXPERIMENTS = [
    # --- gatekit's own two-state plant: three output-directory conditions, no bend ---
    ("gates/gatekit.py", "plant: 3 output-dir states", ["gates/gatekit.py", "--plant"]),
    ("gates/wk-f32-gate.py", "plant: output-dir", ["gates/wk-f32-gate.py", "--plant"]),
    ("gates/wk-cd-gate.py", "plant: output-dir", ["gates/wk-cd-gate.py", "--plant"]),

    # --- the meta-gates over the gates ---
    ("gates/gates-pop.py", "at rest", ["gates/gates-pop.py"]),
    ("gates/gates-pop.py", "plant: nine directions", ["gates/gates-pop.py", "--plant"]),
    ("gates/gendirs.py", "at rest", ["gates/gendirs.py"]),
    ("gates/gendirs.py", "plant: seven directions", ["gates/gendirs.py", "--plant"]),
    ("gates/retention-check.py", "at rest", ["gates/retention-check.py"]),

    # --- the checks/ gates that present a verdict without bend ---
    ("checks/no-txt.py", "at rest", ["checks/no-txt.py"]),
    ("checks/no-strays.py", "at rest", ["checks/no-strays.py"]),
    ("checks/repro-paths.py", "at rest", ["checks/repro-paths.py"]),
    ("checks/txt-owners.py", "at rest", ["checks/txt-owners.py"]),
    ("checks/unowned.py", "at rest", ["checks/unowned.py"]),
    ("checks/citation-gate.py", "at rest", ["checks/citation-gate.py"]),
    ("checks/oracle-txt-census.py", "at rest", ["checks/oracle-txt-census.py"]),
    ("checks/oracle-txt-census.py", "gate mode", ["checks/oracle-txt-census.py", "--gate"]),
    ("checks/hermetic-census.py", "at rest (input swept?)", ["checks/hermetic-census.py"]),
    ("checks/dup-census.py", "at rest (input swept?)", ["checks/dup-census.py"]),
    ("checks/dup-gate.py", "at rest (input swept?)", ["checks/dup-gate.py"]),
    ("checks/rn-gate.py", "at rest (input swept?)", ["checks/rn-gate.py"]),
    ("checks/nl-gate.py", "at rest (input swept?)", ["checks/nl-gate.py"]),
    ("checks/nl-gate-noguard.py", "at rest (input swept?)", ["checks/nl-gate-noguard.py"]),
    ("checks/disagree-gate.py", "at rest", ["checks/disagree-gate.py"]),
    ("checks/disagree-gate.py", "lane: plant", ["checks/disagree-gate.py", "--lane", "plant"]),
    ("checks/coverage.py", "at rest", ["checks/coverage.py"]),
    ("checks/corpus-figure.py", "at rest (DEV unset)", ["checks/corpus-figure.py"]),

    # --- two-state plants the tree already carries ---
    ("checks/residue.py", "plant", ["checks/residue.py", "--plant"]),
    ("checks/residue.py", "disarm DELETE", ["checks/residue.py", "--disarm", "DELETE"]),
    ("checks/env-precond.py", "declare", ["checks/env-precond.py", "--declare"]),
    ("checks/env-precond.py", "plant satisfied", ["checks/env-precond.py", "--plant", "satisfied"]),
    ("checks/env-precond.py", "plant moved", ["checks/env-precond.py", "--plant", "moved"]),
    ("checks/env-precond.py", "at rest", ["checks/env-precond.py"]),
    ("checks/wallcheck.py", "selftest", ["checks/wallcheck.py", "--selftest"]),
    ("checks/bounded.py", "selftest", ["checks/bounded.py", "--selftest"]),
    ("checks/sweep.py", "plan", ["checks/sweep.py", "--plan"]),
    ("checks/nvrows-deadrow-gate.py", "plant STRIP", ["checks/nvrows-deadrow-gate.py", "--plant", "STRIP"]),
    ("checks/nvrows-deadrow-gate.py", "plant ORPHAN", ["checks/nvrows-deadrow-gate.py", "--plant", "ORPHAN"]),
    ("checks/nvrows-deadrow-gate.py", "plant SELF", ["checks/nvrows-deadrow-gate.py", "--plant", "SELF"]),
    ("checks/nvrows-deadrow-gate.py", "plant REVIVE", ["checks/nvrows-deadrow-gate.py", "--plant", "REVIVE"]),

    # --- differ's own subcommands that do not run the corpus ---
    ("checks/differ.py", "snap", ["checks/differ.py", "snap"]),
    ("checks/differ.py", "plant", ["checks/differ.py", "plant"]),

    # --- REFUSED on a missing/bad argument, the cheapest red there is ---
    ("checks/env-precond.py", "plant unknown kind", ["checks/env-precond.py", "--plant", "nonsense"]),
    ("checks/unowned.py", "why a missing path", ["checks/unowned.py", "--why", "/nonexistent/coindependent"]),
]


def run_one(gate, state, argv):
    cmd = [PY, *argv]
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=45)
        rc = r.returncode
        out = (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return {"gate": gate, "state": state, "cmd": " ".join(argv), "rc": "TIMEOUT",
                "tokens": "", "note": "exceeded 45s (an instrument refusal, not a gate verdict)"}
    except Exception as e:  # a crashed command is still a measurement
        return {"gate": gate, "state": state, "cmd": " ".join(argv), "rc": "EXC",
                "tokens": "", "note": f"{type(e).__name__}: {e}"}
    toks = sorted(set(WORD.findall(out)))
    return {"gate": gate, "state": state, "cmd": " ".join(argv), "rc": rc,
            "tokens": ",".join(toks), "note": ""}


def main(argv):
    rows = [run_one(*e) for e in EXPERIMENTS]
    if "--rows" in argv:
        print("gate\tstate\trc\ttokens\tcmd\tnote")
        for r in rows:
            print(f"{r['gate']}\t{r['state']}\t{r['rc']}\t{r['tokens'] or '-'}\t"
                  f"{r['cmd']}\t{r['note']}")
        return 0
    print(f"# {len(rows)} experiments, no `bend` started\n")
    print(f"{'rc':7} {'gate':34} {'state':26} tokens")
    greens = reds = 0
    for r in rows:
        verdict = "GREEN" if r["rc"] == 0 else ("RED" if isinstance(r["rc"], int) else str(r["rc"]))
        greens += r["rc"] == 0
        reds += isinstance(r["rc"], int) and r["rc"] != 0
        print(f"{verdict:7} {r['gate']:34} {r['state']:26} {r['tokens'] or '-'}")
    print(f"\n# reached GREEN {greens}, RED {reds}, other {len(rows)-greens-reds}")
    (HERE / "probe.json").write_text(json.dumps(rows, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
