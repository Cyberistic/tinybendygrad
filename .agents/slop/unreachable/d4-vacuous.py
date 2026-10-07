#!/usr/bin/env python3
"""d4-vacuous.py -- HOW MANY GATES SHIP A FLAG THAT CAN MAKE THEM GREEN WITHOUT
MEASURING ANYTHING?

`modulerefuse` found one: `checks/nl-gate-noguard.py --oracle-stdout <empty>`
exits 0 having compared 0 rows.  A FINDING ON ONE GATE'S FLAG IS A FINDING
ABOUT EVERY GATE THAT SHIPS ONE, so the class has to be counted, not quoted.

Discovery is by AST over each gate's OWN `add_argument` write sites -- never a
hand list, never a filename shape.  A candidate must ALSO flow into a read in
that same file, which is what keeps the census from passing --out at a gate that
writes one.  The VERDICT is by execution: run it with an EMPTY file and parse the
gate's own denominator out of its own output.

No .txt.
"""
import ast, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
BUDGET = 25
WORKERS = 4

# An option whose NAME suggests a comparison input. The name is only a CANDIDATE
# filter; the AST read-check below is what admits it, and execution is the verdict.
CAND = re.compile(r"(stdout|rows|expect|oracle|baseline|golden|reference|fixture|snapshot)$")
# Anything that could WRITE is excluded outright. Cost of being wrong here is a
# truncated tracked file; cost of missing a candidate is one row of a census.
NEVER = re.compile(r"(^--out|write|save|emit|generate|plant|target|dest|dir|path)")

READS = re.compile(r"\b(read_text|readlines|open|load|splitlines|loadtxt|genfromtxt)\b")
# Denominators a gate may print. Any of these, if 0, means nothing was compared.
DENOM = re.compile(
    r"(?i)\b(gated|compared|rows?|checked|shared|matched|compared_rows|over)\W{0,3}(\d+)")


def gates():
    out = []
    for home in ("checks", "gates"):
        out += [p for p in sorted((REPO / home).iterdir()) if p.is_file() and p.suffix == ".py"]
    return out


def candidates(src):
    """Options the gate itself declares that (a) look like an input file and
    (b) whose name appears in a read call in the SAME file."""
    tree = ast.parse(src)
    found = {}
    for n in ast.walk(tree):
        if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                and n.func.attr == "add_argument" and n.args):
            continue
        a = n.args[0]
        if not (isinstance(a, ast.Constant) and isinstance(a.value, str)):
            continue
        name = a.value
        if not name.startswith("--") or NEVER.search(name) or not CAND.search(name.lstrip("-")):
            continue
        dest = name.lstrip("-").replace("-", "_")
        for kw in n.keywords:
            if kw.arg == "dest" and isinstance(kw.value, ast.Constant):
                dest = kw.value.value
        found[dest] = name
    if not found:
        return []
    return sorted(set(found.values())) if READS.search(src) else []


def run_empty(rel, opt):
    with tempfile.NamedTemporaryFile("w", suffix=".rows", delete=False) as t:
        t.write("")
        empty = t.name
    try:
        r = subprocess.run([str(PY), str(REPO / rel), opt, empty], cwd=REPO,
                           capture_output=True, text=True, timeout=BUDGET)
        out = (r.stdout + r.stderr)
        denoms = [(m.group(0), int(m.group(2))) for m in DENOM.finditer(out)]
        return r.returncode, out, denoms, empty
    except subprocess.TimeoutExpired:
        return "TIMED-OUT", "", [], empty
    finally:
        os.unlink(empty)


def main():
    rels = [str(p.relative_to(REPO)) for p in gates()]
    cands = {r: candidates((REPO / r).read_text()) for r in rels}
    cands = {r: v for r, v in cands.items() if v}

    print("SCOPE: top-level checks/*.py + gates/*.py, iterdir(). "
          f"{len(rels)} files walked.\n")
    print(f"DISCOVERY (AST over each gate's own add_argument write sites, read-checked): "
          f"{len(cands)} gate(s) ship a comparison-input flag\n")
    for r, v in sorted(cands.items()):
        print(f"  {r:34} {' '.join(v)}")

    jobs = [(r, o) for r, v in sorted(cands.items()) for o in v]
    rows, vacuous = [], []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        res = list(ex.map(lambda j: (j[0], j[1], *run_empty(*j)), jobs))

    print("\nEXECUTION: each flag driven with an EMPTY file")
    for rel, opt, rc, out, denoms, _ in sorted(res):
        zero = [d for d in denoms if d[1] == 0]
        nonzero = [d for d in denoms if d[1] > 0]
        verdict = "VACUOUS GREEN" if rc == 0 and zero and not nonzero else (
            "rc=0" if rc == 0 else f"rc={rc}")
        if rc == 0 and zero and not nonzero:
            vacuous.append((rel, opt, denoms, out))
        first = (out.strip().splitlines() or [""])[0][:78]
        print(f"  {rel:34} {opt:16} rc={str(rc):10} denoms={denoms or '-'}  {verdict}")
        print(f"      {first}")
        rows.append((rel, opt, rc, ";".join(d[0] for d in denoms)))

    print(f"\nVACUOUS GREEN REACHABLE THROUGH A FLAG THE GATE SHIPS ITSELF: {len(vacuous)}")
    for rel, opt, denoms, out in vacuous:
        print(f"  {rel} {opt}  denoms={denoms}")
        for line in out.strip().splitlines()[-4:]:
            print(f"      {line[:100]}")

    p = REPO / ".agents/slop/unreachable/d4-vacuous.rows"
    with p.open("w") as f:
        f.write("path\toption\trc_empty_input\tdenominators\tvacuous_green\n")
        for rel, opt, rc, d in rows:
            v = "YES" if any(r == rel and rc == 0 for r, _, _, _ in vacuous) else "no"
            f.write(f"{rel}\t{opt}\t{rc}\t{d}\t{v}\n")


if __name__ == "__main__":
    main()