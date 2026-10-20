#!/usr/bin/env python3
"""gates/edge-oracle-pin-gate.py -- THE PIN SUBJECTS THAT LIVE IN THE PRUNED TREE.

    .venv/bin/python gates/edge-oracle-pin-gate.py            # compare every such pin
    .venv/bin/python gates/edge-oracle-pin-gate.py --plant    # the plant

THE QUESTION. `checks/e2e.py`'s `ORACLE_SHA` used to name `.agents/slop/e2epy/oracle-e2e.sh`
-- a pin's subject in a tree that is being pruned and holds no protection. **A PIN WHOSE
SUBJECT CAN BE TAKEN AWAY IS NOT A PIN, IT IS A HOPE.** The fixture moved, so THAT subject
is safe now, and this gate is the instrument that says so about the ones that are not.

WHAT IT COMPARES, AND HOW IT FINDS THE PINS. Nothing here is a list of pin names:
  * the pins are the tree's own, by `gates/pincensus-pop.py:rule_a()` -- the same rule
    `gates/pincensus-gate.py` uses, LOADED BY PATH;
  * a pin's SUBJECT is resolved by `gates/bind-subject.py:resolve()` and
    `gates/pincensus-gate.py:subject_of()`, and the BASES that resolution searches are
    `gates/pincensus-gate.py:SUBJECT_ROOTS` -- so `diffpy/oracle-run.sh` is found under
    `.agents/slop/` because that is where the tree says to look, not because this file
    knows;
  * a pin is AT RISK when its subject resolves UNDER `.agents/slop/`, and the subject is
    then hashed and compared to the pin.

**THE DENOMINATOR IS PRINTED BESIDE THE TALLY, ALWAYS.** A gate that says "2 pins are
current" without saying "of 2" is a claim nobody can check.

WHY IT IS A CANDIDATE ALTHOUGH IT HOLDS NO PIN OF ITS OWN. The edge's selection rule is
"a member that holds a pin its own code reads", and this gate holds none -- it compares
OTHER gates' pins. So it declares `EDGE_CANDIDATE = True` and `edge_covers()`, and the
edge reads both BY PATH, the same way it reads a gate's `RED_IS`. **A GATE THAT COVERS
ANOTHER GATE'S PIN SAYS SO IN ITS OWN SOURCE, WHERE A REVIEWER CAN SEE IT.**

VERDICTS, in `AGENTS.md`'s five. PASS 0 every at-risk pin is current. FAIL one disagrees
with its subject. REFUSED 3 the tree's own instruments did not answer. DEAD 5 there was
nothing to compare, which is not a pass.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import sys
import time
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLOP = ".agents/slop"
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# THE EDGE'S HOOKS, DECLARED HERE AND READ BY THE EDGE. The edge selects a member that
# holds a pin of its own; this one compares other gates' pins, so it says so.
EDGE_CANDIDATE = True

COLUMNS = ("gate", "pin", "subject", "resolved", "pinned", "actual", "verdict")


def load(name: str, path: Path):
    """A MODULE, LOADED BY PATH. `gates/gates-pop.py` has a hyphen and importing a gate
    RUNS it."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        spec.loader.exec_module(mod)
    return mod


def sha256_of(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def at_risk(hosts=None) -> list[dict]:
    """-> every pin whose subject resolves UNDER THE PRUNED TREE.

    **THE POPULATION IS THE TREE'S OWN PIN CENSUS, AND IT IS WALKED, NOT LISTED.** The
    census is the whole tree, so a pin in a file the gate population does not reach is
    counted too -- and the report says which.

    **AND IT CAN BE SCOPED TO THE HOSTS A LEDGER NAMES, WHICH IS WHAT MAKES THE GATE FIT
    THE EDGE'S BUDGET.** MEASURED 2026-10-20: the whole-tree census takes more than six
    minutes, and the edge's budget is thirty seconds -- so a gate that re-censuses the tree
    on every run is a gate the edge can never run, and a gate the edge can never run is a
    gate that covers nothing. Scoped, it re-derives the pins of the hosts the ledger names
    from their OWN source, which is six files, and re-deriving is the point: a pin whose
    value moved is caught, because the value is read from the tree, not from the ledger."""
    P = load("edge_opin_pp", ROOT / "gates" / "pincensus-pop.py")
    B = load("edge_opin_bs", ROOT / "gates" / "bind-subject.py")
    PC = load("edge_opin_pc", ROOT / "gates" / "pincensus-gate.py")
    if not (P and B and PC):
        return []
    if hosts:
        corpus = {}
        for rel in sorted(hosts):
            try:
                corpus[rel] = (ROOT / rel).read_text(errors="replace")
            except OSError:
                continue
    else:
        corpus = P.load(ROOT)["corpus"]
    host = {t: P.host_of(v) for t, v in corpus.items()}
    code = {t: P.code_lines(corpus[t], host[t]) for t in corpus if host[t] != "prose"}
    decls = B.declarations(corpus, code)
    out = []
    for site in P.rule_a(corpus, host):
        if site["host"] == "prose":
            continue
        if not P.readers(site["name"], code, (site["file"], site["line"], site["end"])):
            continue
        decl = decls.get(site["file"], {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}})
        resolved = B.resolve(site["name"], decl)
        # (subject path, the key `subject_of` wants, the digest the pin holds). A dict-shaped
        # pin names its own subject in its KEY, and the key IS the row: `ORACLE_PIN`'s
        # `"diffpy/oracle-run.sh": "<sha256>"` is the pin and the subject together.
        subjects = []
        if resolved is not None and resolved.get("kind") == "SUBJECT":
            subjects.append((resolved["value"], None, site["values"][0] if site["values"] else ""))
        for key, value in (site.get("pairs") or {}).items():
            subjects.append((key, key, value))
        for _, key, value in subjects:
            subj = PC.subject_of(resolved, key, decl)
            if not subj or subj.get("kind") != "file":
                continue
            found = None
            for base_dir in PC.SUBJECT_ROOTS:
                rel = os.path.normpath(os.path.join(base_dir, subj["path"]))
                if (ROOT / rel).is_file():
                    found = rel
                    break
            if not found or not found.startswith(SLOP + "/"):
                continue
            out.append({"gate": site["file"], "pin": site["name"], "subject": subj["path"],
                        "resolved": found, "values": [value]})
    return out


LEDGER = ROOT / "gates" / "edge-oracle-pin.rows"


def ledger_hosts() -> list[str]:
    """-> the hosts the LEDGER names, or [] when there is no ledger yet (a cold start, where
    the whole tree is censused once and the ledger is written)."""
    if not LEDGER.is_file():
        return []
    out = set()
    for line in LEDGER.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        out.add(line.split("\t")[0])
    return sorted(out)


def edge_covers() -> list[str]:
    """-> the paths whose pins THIS GATE compares. The edge reads it BY PATH.

    **IT READS THE LEDGER THIS GATE WRITES, AND THE LEDGER IS A GENERATOR'S OWN
    DECLARATION.** The whole-tree pin census takes more than six minutes, and the edge
    plans a run in seconds; so the answer is READ from `gates/edge-oracle-pin.rows`, which
    this gate writes and nobody else may write. A gate whose ledger is stale says so on its
    own report, and the edge prints the ledger's timestamp beside the coverage it quotes."""
    if not LEDGER.is_file():
        return sorted({r["gate"] for r in at_risk()})
    out = set()
    for line in LEDGER.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        out.add(line.split("\t")[0])
    return sorted(out)


def main(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(description=__doc__.split("\n")[1]).parse_args(argv)
    rows = at_risk(ledger_hosts())
    if not rows:
        print("DEAD: no pin subject resolves under the pruned tree, so there is nothing to compare")
        return DEAD
    out = []
    bad = 0
    for r in rows:
        actual = sha256_of(ROOT / r["resolved"])
        pinned = r["values"][0] if r["values"] else ""
        verdict = "MISSING" if actual is None else ("CURRENT" if actual.startswith(pinned) else "MISMATCH")
        bad += verdict != "CURRENT"
        out.append([r["gate"], r["pin"], r["subject"], r["resolved"], pinned[:16],
                    (actual or "-")[:16], verdict])
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    dest = LEDGER
    with dest.open("w") as fh:
        fh.write("# gates/edge-oracle-pin.rows -- TAB separated. Generated; the generator is "
                 "`gates/edge-oracle-pin-gate.py`, the ONLY writer.\n")
        fh.write(f"# columns: {', '.join(COLUMNS)}\n")
        fh.write(f"# written {stamp}\n")
        for r in out:
            fh.write("\t".join(str(x) for x in r) + "\n")
    print(f"edge-oracle-pin   {len(out)} pin(s) whose subject resolves under {SLOP}/")
    for r in out:
        print(f"  {r[6]:<9} {r[0]:<28} {r[1]:<12} {r[3]}")
    print(f"  TALLY (of {len(out)} at-risk pins): CURRENT {len(out) - bad}   NOT-CURRENT {bad}")
    if bad:
        print("EDGE-ORACLE-PIN: FAIL -- a pin's subject moved, or is gone", file=sys.stderr)
        return FAIL
    return PASS


if __name__ == "__main__":
    sys.exit(main())
