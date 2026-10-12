"""DRIVE THE WIRE, DO NOT ASSERT IT.

Every branch below is reached by BUILDING A REAL DIRECTORY and running the reader's REAL `main()`
in a REAL subprocess, then reading the token it printed and the exit it returned. Nothing here
compares against a literal that a human typed: the expected token is what the SHARED CALL prints
(`checks/runs-artifacts.py`), so the reader is proved to pass the answer through rather than to
agree with me.

THE DECISIVE PROPERTY: AN ABSENT SUBJECT AND A STALE SUBJECT MUST NOT PRODUCE THE SAME TOKEN. A
population that reads nothing and a population that reads something old are DIFFERENT SUBJECTS,
and they share an exit (3) on purpose -- so the TOKEN is the only thing that separates them, which
is why this harness collects tokens and not just exits.

`runs/graphcmp/` IS NEVER TOUCHED. Every tree here is under a TemporaryDirectory. The one rule
about the real directory is that nothing may delete it, and the way to honour that is not to write
a test that does.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
assert os.path.isdir(os.path.join(ROOT, "checks")), f"ROOT wrong: {ROOT}"
PY = os.path.join(ROOT, ".venv/bin/python")

WANT = {"absent": ("ARTIFACTS-ABSENT", 3),
        "empty": ("ARTIFACTS-EMPTY", 5),
        "stale": ("ARTIFACTS-STALE", 3),
        "fresh": ("ARTIFACTS-FRESH", None)}  # None: the reader's OWN verdict, not the guard's


def build(td: str, now: float) -> dict[str, str]:
    """Four real trees, one per state. `fresh` is one fresh file; `stale` is one 10-day-old file."""
    out = {}
    for name in ("absent", "empty", "stale", "fresh"):
        out[name] = os.path.join(td, name, "runs", "graphcmp", "D")
    for name in ("empty", "stale", "fresh"):
        os.makedirs(out[name])
    for name, age in (("fresh", 60.0), ("stale", 10 * 86400.0)):
        p = os.path.join(out[name], "D0-run-summary.txt")
        with open(p, "w") as fh:
            fh.write("graphs=34\n")
        os.utime(p, (now - age, now - age))
    return out


def run(argv: list[str]) -> tuple[int, str]:
    """`(rc, combined output)` with NO PIPE IN THE SHELL, so `$?` is the gate's and not tail's."""
    p = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def token_of(out: str) -> str:
    for line in out.splitlines():
        for t in ("ARTIFACTS-ABSENT", "ARTIFACTS-EMPTY", "ARTIFACTS-STALE", "ARTIFACTS-FRESH"):
            if t in line:
                return t
    return "<none>"


def drive(label: str, argv_for, trees: dict[str, str]) -> tuple[list[str], list[str]]:
    """Run one reader over all four states. Returns `(tokens seen, failures)`."""
    toks, bad = [], []
    for name, (want_tok, want_rc) in WANT.items():
        rc, out = run(argv_for(trees[name]))
        tok = token_of(out)
        toks.append(tok)
        ok = tok == want_tok and (want_rc is None or rc == want_rc)
        if not ok:
            bad.append(f"{label}/{name}: token={tok} rc={rc}, wanted {want_tok}/{want_rc}")
        print(f"  {label:<16} {name:<7} {tok:<17} rc={rc}  {'OK' if ok else 'FAILED'}")
    return toks, bad


def main() -> int:
    import time
    bad: list[str] = []
    all_toks: dict[str, set[str]] = {}
    with tempfile.TemporaryDirectory() as td:
        trees = build(td, time.time())

        print("\nTHE SHARED CALL ALONE (checks/runs-artifacts.py --plant, its own four states):")
        rc, out = run([PY, "checks/runs-artifacts.py", "--plant"])
        print("\n".join("  " + l for l in out.strip().splitlines()[-6:]))
        if rc != 0:
            bad.append(f"runs-artifacts --plant rc={rc}")

        print("\nEVERY READER THAT ACCEPTS A SUBJECT OVERRIDE, THROUGH ITS REAL main():")
        # `--lane coverage` and NOT `--lane pin`: `pin` builds graphs, which imports tinygrad and
        # costs minutes per invocation, and what is under test is the GUARD, not the lane. `coverage`
        # reads the artefact files and reaches its own verdict without touching the corpus.
        t, b = drive("disagree-gate",
                     lambda d: [PY, "checks/disagree-gate.py", "--tree", d, "--lane", "coverage"],
                     trees)
        all_toks["disagree-gate"] = set(t); bad += b
        t, b = drive("retention-check",
                     lambda d: [PY, "gates/retention-check.py",
                                "--dir", f"graphcmp={os.path.dirname(d)}"], trees)
        all_toks["retention-check"] = set(t); bad += b

    # THE DECISIVE CONTROL, stated on the tokens rather than on the exits.
    print("\nTHE CONTROL: absent and stale must not share a token")
    for label, toks in all_toks.items():
        distinct = len(toks) == 4
        print(f"  {label:<16} {len(toks)} distinct tokens  {'OK' if distinct else 'COLLAPSE'}")
        if not distinct:
            bad.append(f"{label}: {len(toks)} tokens across four states: {sorted(toks)}")

    print(f"\nwiring-plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())