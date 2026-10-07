#!/usr/bin/env python3
"""d1-derive.py -- RE-DERIVE the module-scope-refusal set BY EXECUTION.

Population BY DISCOVERY: top-level *.py in checks/ and gates/, from iterdir().
Verdict BY EXECUTION: the process's real exit status with no argv.
Site BY AST CONTAINMENT: module-scope statements (def bodies excluded) that
call a refuse-ish name anywhere in their subtree.

No .txt. Rows go to .rows.
"""
import ast, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
BUDGET = 15          # seconds per invocation. TIMED-OUT is recorded, never guessed.
WORKERS = 6
HOMES = ("checks", "gates")

REFUSEISH = re.compile(r"^(refuse\w*|_?refuse|abort\w*|die)$")


def discover():
    """Population by directory walk at the top level of each home. No hand list."""
    out = []
    for home in HOMES:
        d = REPO / home
        for p in sorted(d.iterdir()):
            if p.is_file() and p.suffix == ".py":
                out.append(p)
    return out


def head_set():
    """The same population as git sees it. GIT_INDEX_FILE is set: the index lies."""
    env = dict(os.environ, GIT_INDEX_FILE=".git/agent-index")
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD", "--", "checks", "gates"],
                       cwd=REPO, capture_output=True, text=True, env=env)
    return {n for n in r.stdout.splitlines() if n.endswith(".py") and "/" not in n[7:]}


def run(path, argv):
    try:
        r = subprocess.run([str(PY), str(REPO / path), *argv], cwd=REPO,
                           capture_output=True, text=True, timeout=BUDGET)
        first = (r.stderr or r.stdout).strip().splitlines()
        return r.returncode, (first[0][:90] if first else "")
    except subprocess.TimeoutExpired:
        return "TIMED-OUT", f"no exit in {BUDGET}s"


def module_scope_refusal_sites(src):
    """Module-scope containment scan. A statement nested two deep inside `for ... if ...`
    is still module scope; a call inside `def main()` is not."""
    tree = ast.parse(src)
    lines = []
    pa = [n.lineno for n in ast.walk(tree)
          if isinstance(n, ast.FunctionDef) and n.name == "parse_args"]
    parse_args_line = pa[0] if pa else None

    def scan(node):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            for n in ast.walk(child):
                if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and REFUSEISH.match(n.func.id):
                    lines.append(n.lineno)
                if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                        and n.func.attr in ("exit", "abort") and isinstance(n.func.value, ast.Name) \
                        and n.func.value.id == "sys":
                    lines.append(n.lineno)
            scan(child)

    scan(tree)
    return sorted(set(lines)), parse_args_line


def main():
    paths = discover()
    disk = {str(p.relative_to(REPO)) for p in paths}
    head = head_set()
    print(f"SCOPE: top-level checks/*.py + gates/*.py, iterdir() discovery")
    print(f"DENOMINATOR: {len(disk)} on disk, {len(head)} in `git ls-tree -r HEAD`, "
          f"{len(disk - head)} only-on-disk, {len(head - disk)} only-in-HEAD")
    print(f"INVOCATION: {PY.relative_to(REPO)} <gate> [argv], cwd=REPO, budget={BUDGET}s, "
          f"workers={WORKERS}\n")

    def job(p):
        rel = str(p.relative_to(REPO))
        a = run(rel, [])
        return rel, a

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        first = dict(ex.map(job, paths))

    rows = []
    for rel in sorted(first):
        rc0, msg0 = first[rel]
        rc_h = rc_b = "-"
        if rc0 == 3:                      # only the already-refusing get the argv census
            rc_h, _ = run(rel, ["--help"])
            rc_b, _ = run(rel, ["--definitely-not-a-flag"])
        rows.append((rel, rc0, rc_h, rc_b, msg0))

    site_rows = []
    for rel, *_ in rows:
        src = (REPO / rel).read_text()
        sites, pa = module_scope_refusal_sites(src)
        site_rows.append((rel, sites, pa))

    print(f"{'gate':44} {'noargv':>8} {'--help':>8} {'badflag':>8}  first-stderr")
    for rel, rc0, rc_h, rc_b, msg in rows:
        print(f"{rel:44} {str(rc0):>8} {str(rc_h):>8} {str(rc_b):>8}  {msg}")

    print(f"\nMODULE-SCOPE REFUSAL SITES (AST containment, def bodies excluded)")
    for rel, sites, pa in site_rows:
        if sites:
            s = ",".join(f":{n}" for n in sites)
            above = f"ABOVE parse_args():{pa}" if pa and min(sites) < pa else (
                "NO parse_args()" if pa is None else f"BELOW parse_args():{pa}")
            print(f"{rel:44} {s:24} {above}")

    # THE SET: refuses at module scope with no argv, and argv cannot change that.
    the_set = [r for r in rows if r[1] == 3 and r[2] == 3 and r[3] == 3]
    indist = [r for r in rows if r[1] == 3 and r[2] == 3 and r[3] not in (3,)]
    other3 = [r for r in rows if r[1] == 3 and (r[2] != 3 or r[3] != 3)]
    to = [r for r in rows if r[1] == "TIMED-OUT"]
    print(f"\nSET (rc=3 for NONE / --help / BAD FLAG -- argv-indistinguishable): {len(the_set)}")
    for r in the_set:
        print(f"  {r[0]}")
    print(f"\nrc=3 with no argv but --help or a bad flag DIFFERS: {len(indist) + len(other3)}")
    for r in indist + other3:
        print(f"  {r[0]:44} none={r[1]} help={r[2]} bad={r[3]}  {r[4]}")
    print(f"\nNOT MEASURED (no exit in {BUDGET}s) -- EXCLUDED BY EXCLUSION, NOT BY MEASUREMENT: {len(to)}")
    for r in to:
        print(f"  {r[0]}")

    out = REPO / ".agents/slop/unreachable/d1-derive.rows"
    with out.open("w") as f:
        f.write("path\trc_none\trc_help\trc_badflag\tin_set\tfirst_stderr\n")
        for rel, rc0, rc_h, rc_b, msg in rows:
            f.write(f"{rel}\t{rc0}\t{rc_h}\t{rc_b}\t"
                    f"{'YES' if (rc0, rc_h, rc_b) == (3, 3, 3) else 'no'}\t{msg}\n")


if __name__ == "__main__":
    main()