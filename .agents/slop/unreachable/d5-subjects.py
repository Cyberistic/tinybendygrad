#!/usr/bin/env python3
"""d5-subjects.py -- PER GATE: DOES ITS SUBJECT EXIST, AND WHAT WOULD THE GATE
SAY IF IT CAME BACK?  Answered by RUNNING it, not by reasoning about it.

Three questions per gate, and none of them is answered from a column:
  1. the paths its OWN module-scope guards name: on disk? in HEAD? in history?
  2. the gate's verdict right now
  3. the gate's verdict with each missing subject RESTORED FROM GIT, transiently

Restores are guarded: the path must be ABSENT first, the written bytes are
compared against `git cat-file blob <rev>:<path>` after the write, and every
removal is in a `finally` with the residue counted and printed. A restore that
cannot be proven byte-exact does not count as a restore.

No .txt.
"""
import ast, os, re, subprocess, sys, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PY = REPO / ".venv/bin/python"
BUDGET = 25
GITENV = dict(os.environ, GIT_INDEX_FILE=".git/agent-index")
REFUSEISH = re.compile(r"^_?refuse\w*$")

CANDIDATES = [
    "checks/cl-port-gate.py", "checks/dup-census.py", "checks/dup-gate.py",
    "checks/gate.py", "checks/hermetic-census.py", "checks/nl-gate.py",
    "checks/nl-gate-noguard.py", "checks/oracle_f64.py", "checks/rn-gate.py",
]


def git(*args, text=True):
    r = subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True,
                       env=GITENV, timeout=60)
    return r.returncode, (r.stdout if text else r.stdout)


def const_bindings(tree):
    env = {}

    def val(node, d=0):
        if d > 8:
            return None
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return env.get(node.id)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
            b, rr = val(node.left, d + 1), val(node.right, d + 1)
            if isinstance(b, str) and isinstance(rr, str):
                return f"{b}/{rr}"
        return None

    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
            v = val(n.value)
            if v is not None:
                env[n.targets[0].id] = v
            elif isinstance(n.value, (ast.List, ast.Tuple)) and all(val(e) for e in n.value.elts):
                env[n.targets[0].id] = [val(e) for e in n.value.elts]
    return env


def resolve(node, env):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return [node.value]
    if isinstance(node, ast.Name):
        v = env.get(node.id)
        return [v] if isinstance(v, str) else (v or [])
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        b, r = resolve(node.left, env), resolve(node.right, env)
        return r if not b else [f"{x}/{y}" for x in b for y in r]
    return []


def guarded_paths(src):
    """Paths named by this gate's own module-scope guards."""
    tree = ast.parse(src)
    env = const_bindings(tree)
    out = []

    def has_refuse(n):
        return any(isinstance(x, ast.Call) and isinstance(x.func, ast.Name)
                   and REFUSEISH.match(x.func.id) for x in ast.walk(n))

    def scan(node):
        for c in ast.iter_child_nodes(node):
            if isinstance(c, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            if has_refuse(c):
                for n in ast.walk(c):
                    if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                            and n.func.attr == "is_file" and n.args:
                        out.extend(resolve(n.args[0], env))
                    if isinstance(n, ast.JoinedStr):
                        out.extend(resolve(n, env))
                continue
            scan(c)

    scan(tree)
    return sorted(set(p for p in out if "/" in p or "." in p))


def in_head(path):
    rc, out = git("ls-tree", "-r", "--name-only", "HEAD", "--", path)
    return out.strip() == path


def in_history(path):
    rc, out = git("log", "--all", "--format=%H", "--", path, "-n", "1")
    return out.strip()


def blob(rev, path):
    r = subprocess.run(["git", "cat-file", "blob", f"{rev}:{path}"], cwd=REPO,
                       capture_output=True, env=GITENV, timeout=60)
    return r.stdout if r.returncode == 0 else None


def run(rel, argv=()):
    try:
        r = subprocess.run([str(PY), str(REPO / rel), *argv], cwd=REPO,
                           capture_output=True, text=True, timeout=BUDGET)
        first = (r.stderr or r.stdout).strip().splitlines()
        return r.returncode, (first[0][:88] if first else ""), (r.stdout or "")[-400:]
    except subprocess.TimeoutExpired:
        return "TIMED-OUT", "", ""


def main():
    print(f"read {time.strftime('%H:%M:%S')}. GIT_INDEX_FILE=.git/agent-index; "
          f"git ls-tree/log/cat-file only, never git ls-files.\n")
    print("PART 1 -- the subject, three ways")
    print(f"{'gate':30} {'subject':52} {'disk':>6} {'HEAD':>5} {'recoverable-from':>18}")
    subjects = {}
    for rel in CANDIDATES:
        for p in guarded_paths((REPO / rel).read_text()):
            fp = REPO / p
            disk = fp.stat().st_size if fp.exists() else None
            head = in_head(p)
            rev = in_history(p)
            subjects.setdefault(rel, []).append(p)
            print(f"{rel:30} {p:52} {str(disk):>6} {('yes' if head else 'no'):>5} "
                  f"{(rev[:12] if rev else '-- NO BLOB IN ANY REF --'):>18}")

    print("\nPART 2 -- the gate's verdict NOW, and with each missing subject restored")
    created = []
    try:
        for rel in CANDIDATES:
            rc0, msg0, _ = run(rel)
            print(f"\n{rel}   NOW rc={rc0}  {msg0}")
            missing = [p for p in subjects.get(rel, []) if not (REPO / p).exists()]
            if not missing:
                print("    no missing subject on disk -> nothing to restore")
                continue
            for p in missing:
                rev = in_history(p)
                if not rev:
                    print(f"    {p}: NOT RECOVERABLE -- no blob in any ref")
                    continue
                data = blob(rev, p)
                if data is None:
                    print(f"    {p}: blob unreadable at {rev[:12]}")
                    continue
                fp = REPO / p
                fp.parent.mkdir(parents=True, exist_ok=True)
                fp.write_bytes(data)
                created.append(fp)
                exact = fp.read_bytes() == data
                print(f"    restored {p}  {len(data)} B from {rev[:12]}  byte-exact={exact}")
                rc1, msg1, tail = run(rel)
                print(f"      -> rc={rc1}  {msg1}")
                for line in tail.strip().splitlines()[-3:]:
                    print(f"         {line[:100]}")
    finally:
        for fp in created:
            fp.unlink(missing_ok=True)
            for d in list(fp.parents):
                if d != REPO and not any(d.iterdir()):
                    d.rmdir()
                elif d == REPO:
                    break
    residue = [str(p.relative_to(REPO)) for p in created if p.exists()]
    print(f"\nRESIDUE: {len(created)} restored, {len(residue)} still on disk "
          f"{residue if residue else ''}")


if __name__ == "__main__":
    main()