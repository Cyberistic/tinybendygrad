"""PART 2 -- (a) the docstring's OTHER claim, and (b) every consumer of `discover()`.

`discover()`'s docstring makes TWO claims about its walk:
  1. `iterdir()` and not `rglob()`   -- MEASURED TRUE (line 337).
  2. `os.lstat` and not `Path.exists()`, because `Path.exists()` FOLLOWS SYMLINKS.
Claim 2 names a FUNCTION. Line 338 tests `p.is_file()`. This script checks what the code
actually calls and what `is_file()`/`exists()` do to a symlink, ON A SCRATCH TREE, so the
answer is a measurement and not an argument about pathlib semantics.
"""
import importlib.util
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "census2.rows"
rows = []


def emit(*c):
    rows.append("\t".join(str(x) for x in c))


def by_path(p, name):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def body_of(path, name):
    import ast
    tree = ast.parse(path.read_text())
    for n in ast.walk(tree):
        if isinstance(n, ast.FunctionDef) and n.name == name:
            return ast.unparse(n)
    return ""


def doc_of(path, name):
    import ast
    tree = ast.parse(path.read_text())
    for n in ast.walk(tree):
        if isinstance(n, ast.FunctionDef) and n.name == name:
            return ast.get_docstring(n) or ""
    return ""


# ---- (a) symlink behaviour, measured on a scratch tree -----------------------------
def symlink_probe():
    tmp = Path(tempfile.mkdtemp(prefix="subtree-link-"))
    try:
        (tmp / "real.py").write_text("import sys\n\nif __name__ == '__main__':\n    sys.exit(0)\n")
        (tmp / "home").mkdir()
        os.symlink(tmp / "real.py", tmp / "home" / "linked.py")
        link, real = tmp / "home" / "linked.py", tmp / "real.py"
        emit("LINK", "link.suffix", link.suffix)
        emit("LINK", "link.is_file()", link.is_file())
        emit("LINK", "link.exists()", link.exists())
        emit("LINK", "os.path.isfile(link)", os.path.isfile(link))
        emit("LINK", "os.path.islink(link)", link.is_symlink())
        emit("LINK", "link.resolve()==real", str(link.resolve()) == str(real))
        emit("LINK", "VERDICT", "is_file() FOLLOWS the link -> claim 2 in the docstring is FALSE"
             if link.is_file() else "is_file() does not follow -> claim 2 holds")
        # and the symlink's TARGET is outside the tree, which is the hazard the docstring names
        emit("LINK", "target_inside_home", str(real).startswith(str(tmp / "home")))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def docstring_vs_code():
    gp = ROOT / "gates" / "gates-pop.py"
    doc, body = doc_of(gp, "discover"), body_of(gp, "discover")
    emit("DOC", "doc_names_os_lstat", "os.lstat" in doc)
    emit("DOC", "code_calls_os_lstat", "os.lstat" in body)
    emit("DOC", "code_calls_is_file", "is_file()" in body)
    emit("DOC", "code_calls_exists", ".exists()" in body)
    emit("DOC", "BODY", " ".join(body.split()))
    # the SUFFIX comment at module level repeats the same claim
    src = gp.read_text().splitlines()
    for i, line in enumerate(src, 1):
        if "iterdir" in line or "rglob" in line:
            emit("DOC", f"module_comment:{i}", line.strip())
    # does ANY line of gates-pop.py import or call os.lstat?
    emit("DOC", "os_lstat_anywhere_in_file", "lstat" in gp.read_text())


# ---- (b) every consumer, and WHAT IT PRINTS ----------------------------------------
def consumers():
    """Files that CALL `discover(` or import `gates-pop`. Found by a DIRECTORY WALK over the
    tree's own `.py` files (Doctrine 1b), and every hit is printed with the line so a reader can
    check the grep against what it matched."""
    skip = {".venv", ".git", "__pycache__", "references", "node_modules", "tinybendygrad",
            ".agents/slop/peakrss"}
    hits = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in skip and not d.startswith(".git")]
        for fn in filenames:
            if not fn.endswith(".py"):
                continue
            p = Path(dirpath) / fn
            try:
                text = p.read_text(errors="replace")
            except OSError:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if "discover(" in line and ("gates-pop" in line or "gpop" in line
                                           or "gates_pop" in line or "gp." in line
                                           or "m.discover" in line or "pop().discover" in line
                                           or ".discover(" in line):
                    hits.append((str(p.relative_to(ROOT)), i, line.strip()))
                elif "gates-pop.py" in line and ("load" in line or "path" in line or "HERE" in line):
                    hits.append((str(p.relative_to(ROOT)), i, line.strip()))
    for rel, ln, line in hits:
        emit("CONSUMER", f"{rel}:{ln}", line)
    emit("CONSUMER", "count", len({h[0] for h in hits}))


# ---- (c) does each consumer PRINT the ceiling? --------------------------------------
def prints_ceiling():
    """A consumer reports the ceiling iff its source names the recursive-walk control
    (`os.walk` + `__pycache__`) or prints a second count beside `discover()`'s."""
    for rel in ["gates/gate-surface.py", "gates/gates-pop.py",
                ".agents/slop/hooks/run.py", ".agents/slop/onemodule/probe.py",
                ".agents/slop/plantthe46/reach.py", ".agents/slop/hooks/cost.py"]:
        p = ROOT / rel
        if not p.is_file():
            emit("CEILING", rel, "ABSENT")
            continue
        text = p.read_text(errors="replace")
        has_walk = "os.walk" in text
        has_cache_prune = "__pycache__" in text
        n_discover = text.count("discover(")
        emit("CEILING", rel, f"os.walk={has_walk} pycache_prune={has_cache_prune} "
                             f"discover_calls={n_discover}")


def git_view():
    """`git ls-tree -r HEAD`, NEVER `git ls-files` -- the index has reset and is not a witness."""
    for rel in ["gates/oracles", "checks"]:
        out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD", "--", rel],
                             cwd=ROOT, capture_output=True, text=True)
        paths = [x for x in out.stdout.splitlines() if x]
        deeper = sorted(x for x in paths if x.count("/") > 1 and x.endswith((".py", ".sh")))
        emit("GIT", f"{rel}:tracked_total", len(paths))
        emit("GIT", f"{rel}:tracked_deeper_py_sh", len(deeper))
        for d in deeper[:20]:
            emit("GIT", f"{rel}:deeper", d)
    out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD", "--", "gates/oracles"],
                         cwd=ROOT, capture_output=True, text=True)
    emit("GIT", "gates/oracles:ls-tree-rc", out.returncode)
    emit("GIT", "gates/oracles:names", " ".join(sorted(out.stdout.split())) or "(EMPTY)")


def main():
    emit("PART2", "field", "value")
    symlink_probe()
    docstring_vs_code()
    consumers()
    prints_ceiling()
    git_view()
    OUT.write_text("\n".join(rows) + "\n")
    print("\n".join(r for r in rows if r.startswith(("DOC", "LINK", "CEILING", "GIT"))))
    print(f"--- consumers: {sum(1 for r in rows if r.startswith('CONSUMER'))}")


if __name__ == "__main__":
    main()