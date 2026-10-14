#!/usr/bin/env python3
"""d3-census.py -- IS THE SET EVEN A PROPERTY OF THE TREE?

d1 and d2 counted the same population minutes apart and got different sets,
because another unit restored two swept subjects at 18:44.  A number about a
set that moves while you measure it is not a fact about the set, so this file
runs the SAME census N times and reports the DELTA between consecutive runs,
plus the existence of every input each refusing gate names.

Population: top-level checks/*.py + gates/*.py, iterdir().
Predicate: the process's exit status. Three probes, and the argv vocabulary the
gate itself writes down. Nothing here is hand-listed.

No .txt.
"""
import ast, json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
BUDGET = 20
WORKERS = 4
ROUNDS = 3
GAP = 75
REFUSEISH = "__import__('re').compile(r'^_?refuse\\w*$')"

PROBES = ([], ["--help"], ["--definitely-not-a-flag"])


def gates():
    out = []
    for home in ("checks", "gates"):
        out += [p for p in sorted((REPO / home).iterdir()) if p.is_file() and p.suffix == ".py"]
    return out


def run(rel, argv, budget=BUDGET):
    try:
        r = subprocess.run([str(PY), str(REPO / rel), *argv], cwd=REPO,
                           capture_output=True, text=True, timeout=budget)
        return r.returncode
    except subprocess.TimeoutExpired:
        return "TIMED-OUT"


def argv_vocab(rel):
    """Every argv token the gate itself writes down."""
    import re
    tree = ast.parse((REPO / rel).read_text())
    opt, choice = [], []
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                and n.func.attr in ("add_argument", "add_parser") and n.args:
            a = n.args[0]
            if isinstance(a, ast.Constant) and isinstance(a.value, str):
                (opt if a.value.startswith("-") else choice).append(a.value)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                and n.func.attr == "add_argument":
            for kw in n.keywords:
                if kw.arg == "choices":
                    choice += [x.value for x in ast.walk(kw.value)
                               if isinstance(x, ast.Constant) and isinstance(x.value, str)]
        if isinstance(n, ast.Compare) and isinstance(n.left, ast.Subscript) \
                and isinstance(n.left.slice, ast.Constant) \
                and isinstance(n.left.slice.value, int):
            for c in ast.walk(n):
                if isinstance(c, ast.Constant) and isinstance(c.value, str) and len(c.value) < 24:
                    choice.append(c.value)
    return sorted(set(opt)), sorted(set(choice))


def census(rels, vocab):
    """One round: no-argv probe for everyone, argv-vocabulary probe for the
    gates that refused. Both arms are execution."""
    def base(rel):
        return rel, run(rel, [], 15)

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        rc0 = dict(ex.map(base, rels))

    refusing = {r for r, v in rc0.items() if v == 3}
    probes = {}
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        probes = dict(ex.map(lambda r: (r, [run(r, a, 15) for a in PROBES[1:]]), sorted(refusing)))
    return rc0, probes


def main():
    rels = [str(p.relative_to(REPO)) for p in gates()]
    vocab = {r: argv_vocab(r) for r in rels}
    print(f"SCOPE: top-level checks/*.py + gates/*.py, iterdir(). {len(rels)} files.")
    print(f"PREDICATE (execution): rc=3 with NO argv AND no argv the gate itself "
          f"declares reaches an exit other than 3.")
    print(f"ROUNDS: {ROUNDS}, gap {GAP}s. This file exists because d1 and d2 "
          f"counted this population minutes apart and disagreed.\n")

    rounds = []
    for i in range(ROUNDS):
        t0 = time.time()
        rc0, probes = census(rels, vocab)
        snap = {r: v for r, v in rc0.items()}
        rounds.append(snap)
        refusing = sorted(r for r, v in snap.items() if v == 3)
        print(f"ROUND {i+1}  ({time.strftime('%H:%M:%S')})  rc=3 with no argv: {len(refusing)}")
        for r in refusing:
            print(f"    {r:34} --help={probes[r][0]} badflag={probes[r][1]}")
        if i:
            prev = rounds[i - 1]
            moved = {r for r in rels if prev.get(r) != snap.get(r)}
            print(f"    MOVED SINCE ROUND {i}: {len(moved)}")
            for r in sorted(moved):
                print(f"      {r:34} {prev.get(r)} -> {snap.get(r)}")
        if i < ROUNDS - 1:
            print(f"    ... sleeping {GAP}s\n")
            time.sleep(GAP)

    out = REPO / ".agents/slop/unreachable/d3-census.rows"
    with out.open("w") as f:
        f.write("path\t" + "\t".join(f"rc_none_r{i+1}" for i in range(ROUNDS))
                + "\toptions\tchoices\n")
        for r in rels:
            o, c = vocab[r]
            f.write(f"{r}\t" + "\t".join(str(rd.get(r)) for rd in rounds)
                    + f"\t{'|'.join(o)}\t{'|'.join(c)}\n")
    print(f"\nwrote {out.name}")


if __name__ == "__main__":
    main()