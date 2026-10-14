#!/usr/bin/env python3
"""The class by DISCOVERY: which entry points can hang, which can crash at rc 1.

Scope is declared in SCOPE and printed with every number. A count without its scope is
meaningless, so the scope is a constant in this file rather than in this file's prose.
"""
import ast, os, stat, sys, time

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
os.chdir(ROOT)

# ---- the population, by DISCOVERY (a walk), not by a list -------------------------------
SCOPE = ("every `.py` and `.sh` DIRECTLY inside checks/ and gates/ (iterdir, no rglob, so no "
         "__pycache__), PLUS every executable file at the repo root that has a `#!` line. "
         "gates/gates-pop.py's HOMES=('checks','gates') is NOT used: a hand list is not a "
         "population, so the repo-root lane is walked here instead and is counted separately.")

TIME_BOUND_TOKENS = ("SIGALRM", "signal.alarm", "signal.setitimer", "timeout=",
                     "--seconds", "bounded.py", "perl -e", "alarm(")


def lstat_regular(p):
    return stat.S_ISREG(os.lstat(p).st_mode)


def walk_homes():
    out = []
    for home in ("checks", "gates"):
        d = os.path.join(ROOT, home)
        if not os.path.isdir(d):
            continue
        for p in sorted(os.listdir(d)):
            fp = os.path.join(d, p)
            if os.path.splitext(p)[1] not in (".py", ".sh") or not lstat_regular(fp):
                continue
            out.append(os.path.relpath(fp, ROOT))
    for p in sorted(os.listdir(ROOT)):
        fp = os.path.join(ROOT, p)
        if not os.path.isfile(fp):
            continue
        try:
            with open(fp, "rb") as fh:
                if fh.read(2) != b"#!":
                    continue
        except OSError:
            continue
        out.append(p)
    return out


def is_entry(path):
    """A `.py` is an entry point iff it has `if __name__ == '__main__'`; a `.sh` iff it has a
    shebang. Both are AST/text facts, not a naming convention."""
    try:
        with open(path, "rb") as fh:
            src = fh.read().decode("utf-8", "replace")
    except OSError:
        return False
    if path.endswith(".sh"):
        return src.startswith("#!")
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    for n in ast.walk(tree):
        if not isinstance(n, ast.If):
            continue
        t = n.test
        if (isinstance(t, ast.Compare) and isinstance(t.left, ast.Name)
                and t.left.id == "__name__"):
            return True
    return False


# ---- the two defects, each decidable from the source, not from a run -------------------
def argv_reads(tree):
    """`sys.argv[<int>]` subscripts, i.e. reads that raise IndexError on a short argv."""
    out = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Subscript):
            continue
        v = n.value
        if not (isinstance(v, ast.Attribute) and v.attr == "argv"
                and isinstance(v.value, ast.Name) and v.value.id == "sys"):
            continue
        # ONLY INDEX >= 1 CAN RAISE. MEASURED: the first version of this filter took every int
        # subscript and reported `checks/substrate.py:931` as CRASHABLE -- which reads `sys.argv[0]`
        # and cannot raise. Running it bare answers rc 3, WITHIN-LIMITS, in 0s. The static claim and
        # the measurement disagreed, the measurement was right, and the filter was the defect.
        if isinstance(n.slice, ast.Constant) and isinstance(n.slice.value, int) and n.slice.value >= 1:
            out.append(n.lineno)
    return out


def argv_guarded(tree):
    """A guard is any comparison of `len(sys.argv)`, or `not sys.argv`, anywhere in the file.
    Deliberately coarse: it CANNOT distinguish a guard that runs before the read from one that
    runs after it, nor a guard in `main` from a guard in a helper."""
    for n in ast.walk(tree):
        if isinstance(n, ast.Compare) and isinstance(n.left, ast.Call):
            f = n.left.func
            if isinstance(f, ast.Name) and f.id == "len" and n.left.args:
                a = n.left.args[0]
                if isinstance(a, ast.Attribute) and a.attr == "argv":
                    return True
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.Not):
            if isinstance(n.operand, ast.Attribute) and n.operand.attr == "argv":
                return True
    return False


SUBPROCESS = {"run", "call", "Popen", "check_output", "check_call"}


def spawns_unbounded(tree):
    """A call to subprocess.* with NO `timeout=` kwarg.

    THIS IS THE COLUMN THAT DISCRIMINATES, and column C is not it: "carries no time bound"
    is true of 105 of 127 and therefore distinguishes nothing. A gate that spawns a child
    process and does not bound it has an unbounded wait; a gate that spawns nothing and loops
    in-process has a different unbounded wait. Both are named, so the reader can see which.
    """
    out = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        if not (isinstance(f, ast.Attribute) and f.attr in SUBPROCESS
                and isinstance(f.value, ast.Name) and f.value.id == "subprocess"):
            continue
        if not any(kw.arg == "timeout" for kw in n.keywords):
            out.append(n.lineno)
    return sorted(set(out))


def has_self_bound(src):
    return any(t in src for t in TIME_BOUND_TOKENS)


def main():
    t0 = time.perf_counter()
    pop = walk_homes()
    entries = [p for p in pop if is_entry(p)]
    crashable, guarded, unbounded, spawns = [], [], [], []
    n_py = 0
    for p in entries:
        if not p.endswith(".py"):
            continue
        n_py += 1
        with open(p, "rb") as fh:
            src = fh.read().decode("utf-8", "replace")
        try:
            tree = ast.parse(src)
        except SyntaxError:
            continue
        reads = argv_reads(tree)
        if reads:
            (guarded if argv_guarded(tree) else crashable).append((p, reads))
        s = spawns_unbounded(tree)
        if s:
            spawns.append((p, len(s), s))
    for p in entries:
        with open(p, "rb") as fh:
            src = fh.read().decode("utf-8", "replace")
        if not has_self_bound(src):
            unbounded.append(p)
    dt = time.perf_counter() - t0

    print(f"# SCOPE: {SCOPE}")
    print(f"# population walked: {len(pop)} files; entry points: {len(entries)} "
          f"({len(entries) - n_py} shell, {n_py} python)")
    print(f"# census wall time: {dt:.2f}s\n")
    print(f"# A: reads sys.argv[i>=1] with NO len() guard anywhere in the file -- CRASHABLE at rc 1 "
          f"when invoked with fewer args. {len(crashable)} of {n_py} python entry points:")
    for p, ln in crashable:
        print(f"   {p}:{','.join(map(str, sorted(set(ln))))}")
    print(f"# B: same read, guard present (may be in the wrong place -- see caveat). {len(guarded)}:")
    for p, ln in guarded:
        print(f"   {p}:{','.join(map(str, sorted(set(ln))))}")
    print(f"# C: spawns subprocess.* with NO timeout= kwarg. {len(spawns)} of {n_py} python entry "
          f"points, {sum(n for _p, n, _l in spawns)} call sites -- AN UNBOUNDED WAIT:")
    for p, n, ln in sorted(spawns, key=lambda r: -r[1])[:15]:
        print(f"   {p:42s} {n:3d} sites, first :{ln[0]}")
    print(f"# C-total: no internal time bound of any kind. {len(unbounded)} of {len(entries)} -- "
          f"TRUE OF ALMOST EVERYTHING, SO IT DISTINGUISHES NOTHING.")


if __name__ == "__main__":
    main()