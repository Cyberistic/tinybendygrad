#!/usr/bin/env python3
"""d2-argv.py -- THE SET, with the predicate derived from the gate's OWN argv vocabulary.

d1's predicate was WRONG and this file is the correction, so both are reported.
d1 probed three argv SHAPES I chose (none / --help / a made-up flag).  Two gates
answered 3 to all three and are nevertheless argv-reachable, because their
interface is POSITIONAL.  A predicate declared by a shape I picked is the eighth
instance of the tree's own class.

Arm A (execution): does the process answer 3 with no argv?
Arm B (argv vocabulary, discovered from the gate's own AST write sites):
    can ANY argv this gate declares reach an exit other than 3?
Arm C (guard evaluation, no execution): for every module-scope refusal site,
    name the paths its own guard names and test existence -- this settles the
    gates d1 could not finish in 15 s WITHOUT running them.

No .txt.
"""
import ast, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
BUDGET = 20
WORKERS = 4
REFUSEISH = re.compile(r"^_?refuse\w*$")


def gates():
    out = []
    for home in ("checks", "gates"):
        out += [p for p in sorted((REPO / home).iterdir()) if p.is_file() and p.suffix == ".py"]
    return out


def const_bindings(tree):
    """Module-level `NAME = <literal>` / `NAME = BASE / "lit"` -- the only bindings
    this resolver follows.  A binding whose right side is not built from literals
    is simply not followed, and the paths under it are reported as UNRESOLVED."""
    env = {}

    def val(node, depth=0):
        if depth > 8:
            return None
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return env.get(node.id)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
            b, r = val(node.left, depth + 1), val(node.right, depth + 1)
            if isinstance(b, str) and isinstance(r, str):
                return f"{b}/{r}"
        return None

    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
            v = val(n.value)
            if v is not None:
                env[n.targets[0].id] = v
            elif isinstance(n.value, (ast.List, ast.Tuple)) and \
                    all(val(e) for e in n.value.elts):
                env[n.targets[0].id] = [val(e) for e in n.value.elts]
    return env


def resolve(node, env):
    """Resolve a path expression built from module-level literals only."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return [node.value]
    if isinstance(node, ast.Name):
        v = env.get(node.id)
        return [v] if isinstance(v, str) else (v or [])
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        base, rhs = resolve(node.left, env), resolve(node.right, env)
        if not base:
            return rhs
        return [f"{b}/{r}" for b in base for r in rhs]
    return []


def refuse_sites(src):
    """(line, [paths the guard names]) for MODULE-SCOPE refusals only.

    Scanned at STATEMENT granularity on purpose: every gate in this tree writes
    `if not (X).is_file(): refuse(...)`, and the path lives in the `if` TEST while
    the refusal lives in the BODY.  Walking the refuse call alone finds nothing --
    which is how modulerefuse's own version of this scan found nothing in 8 of 8."""
    tree = ast.parse(src)
    env = const_bindings(tree)
    out = []

    def has_refuse(node):
        return any(isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                   and REFUSEISH.match(n.func.id) for n in ast.walk(node))

    def scan(node):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            if has_refuse(child):
                line = min((n.lineno for n in ast.walk(child)
                            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                            and REFUSEISH.match(n.func.id)), default=child.lineno)
                paths = []
                for n in ast.walk(child):
                    if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                            and n.func.attr == "is_file" and n.args:
                        paths += resolve(n.args[0], env)
                    if isinstance(n, ast.JoinedStr):
                        paths += resolve(n, env)
                out.append((line, sorted(set(paths))))
                continue
            scan(child)

    scan(tree)
    seen, uniq = set(), []
    for line, paths in sorted(out):
        if line not in seen:
            seen.add(line)
            uniq.append((line, paths))
    return uniq


def argv_vocab(src):
    """Every argv token the gate itself writes down: argparse positionals, option
    strings, subparser choices, sys.argv reads.  Discovered, never hand-listed."""
    tree = ast.parse(src)
    pos, opt, choice, idx = [], [], [], set()

    def lit(node):
        return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None

    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute):
            if n.func.attr == "add_argument":
                a = n.args[0] if n.args else None
                v = lit(a) if a else None
                if v and v.startswith("-"):
                    opt.append(v)
                elif v:
                    pos.append(v)
                for kw in n.keywords:
                    if kw.arg == "choices":
                        choice += [x.value for x in ast.walk(kw.value)
                                   if isinstance(x, ast.Constant) and isinstance(x.value, str)]
            if n.func.attr in ("add_parser", "add_subparsers") and n.args:
                v = lit(n.args[0])
                if v:
                    choice.append(v)
        if isinstance(n, ast.Subscript) and isinstance(n.value, ast.Attribute) \
                and isinstance(n.value.value, ast.Name) and n.value.value.id == "sys" \
                and n.value.attr == "argv":
            s = n.slice
            if isinstance(s, ast.Constant) and isinstance(s.value, int):
                idx.add(s.value)
        if isinstance(n, ast.Compare) and isinstance(n.left, ast.Subscript) \
                and isinstance(n.left.slice, ast.Constant):
            idx.add(n.left.slice.value)
            for c in ast.walk(n):
                if isinstance(c, ast.Constant) and isinstance(c.value, str) and len(c.value) < 24:
                    choice.append(c.value)
    return pos, opt, sorted(set(choice)), sorted(idx, key=str)


def run(rel, argv):
    try:
        r = subprocess.run([str(PY), str(REPO / rel), *argv], cwd=REPO,
                           capture_output=True, text=True, timeout=BUDGET)
        first = (r.stderr or r.stdout).strip().splitlines()
        return r.returncode, (first[0][:70] if first else "")
    except subprocess.TimeoutExpired:
        return "TIMED-OUT", ""


def candidates(pos, opt, choice, idx):
    """argv vectors built ONLY from tokens the gate wrote down. `--help` on every
    one of them, because argparse is per-subparser."""
    seeds = [[]] + [[c] for c in choice] + [[o] for o in opt]
    out, seen = [], set()
    for s in seeds:
        for extra in ([], ["--help"]):
            v = tuple(s + extra)
            if v not in seen:
                seen.add(v)
                out.append(list(v))
    return out


def main():
    rels = [str(p.relative_to(REPO)) for p in gates()]

    # --- Arm C: guard evaluation, no execution. d1 could not finish 47 in 15 s.
    guard_rows = []
    for rel in rels:
        src = (REPO / rel).read_text()
        sites = refuse_sites(src)
        if not sites:
            continue
        named = sorted({d for _, ps in sites for d in ps})
        absent = []
        for d in named:
            # ROOT-relative directory names the guard names; resolve the real tree.
            cand = REPO / d
            if not cand.exists():
                absent.append(d)
        guard_rows.append((rel, len(sites), named, absent))

    fired_by_guard = {r for r, _, _, absent in guard_rows if absent}

    # --- Arm A + B on the union: rc=3 at rest, and the full argv vocabulary.
    arm_a = {r for r, rc, *_ in
             [(l.split("\t")[0], l.split("\t")[1]) for l in
              (REPO / ".agents/slop/unreachable/d1-derive.rows").read_text().splitlines()[1:]]
             if rc == "3"}

    print(f"SCOPE: top-level checks/*.py + gates/*.py, iterdir().  {len(rels)} files.\n")
    print(f"ARM A  rc=3 with NO argv (from d1-derive.rows): {len(arm_a)}")
    for r in sorted(arm_a):
        print(f"    {r}")

    print(f"\nARM C  a module-scope refusal names a path that DOES NOT EXIST: "
          f"{len(fired_by_guard)}")
    for r in sorted(fired_by_guard - arm_a):
        print(f"    {r}   <-- not rc=3 at rest: either it recovered or it was not finished")

    # --- Arm B
    print("\nARM B  can any argv this gate DECLARES reach an exit other than 3?")
    rows = []
    todo = sorted(arm_a)
    for rel in todo:
        pos, opt, choice, idx = argv_vocab((REPO / rel).read_text())
        hits = []
        for argv in candidates(pos, opt, choice, idx):
            rc, msg = run(rel, argv)
            if rc != 3:
                hits.append((argv, rc, msg))
        rows.append((rel, pos, opt, choice, idx, hits))

    in_set = []
    for rel, pos, opt, choice, idx, hits in rows:
        tag = "ARGV-REACHABLE" if hits else "NO ARGV REACHES A VERDICT"
        if not hits:
            in_set.append(rel)
        shown = ", ".join(" ".join(a) or "(none)" for a, _, _ in hits[:4]) or "--"
        print(f"  {rel:32} pos={pos or '-'} opt={opt or '-'} choice={choice or '-'} "
              f"sys.argv[idx]={idx or '-'}\n      {tag}; exits other than 3: {shown}")

    print(f"\nTHE SET (arm A AND arm B): {len(in_set)}")
    for r in in_set:
        print(f"  {r}")

    out = REPO / ".agents/slop/unreachable/d2-argv.rows"
    with out.open("w") as f:
        f.write("path\trc_none\tpositionals\toptions\tchoices\tsysargv_idx\tarm_b_exits"
                "\tin_set\tguard_absent_paths\n")
        absent_map = {r: absent for r, _, _, absent in guard_rows}
        for rel, pos, opt, choice, idx, hits in rows:
            f.write(f"{rel}\t3\t{'|'.join(pos)}\t{'|'.join(opt)}\t{'|'.join(choice)}\t"
                    f"{'|'.join(map(str, idx))}\t{';'.join(f'{a}={c}' for a, c, _ in hits)}\t"
                    f"{'YES' if rel in in_set else 'no'}\t{'|'.join(absent_map.get(rel, []))}\n")


if __name__ == "__main__":
    main()