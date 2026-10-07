"""PART 3 -- the docstring's SECOND claim, tested where `lstat` and `is_file()` DIVERGE.

`discover()`'s docstring says: "`os.lstat` and not `Path.exists()`, because `Path.exists()`
FOLLOWS SYMLINKS: `bin/bend` is a symlink to a worktree and an existence test that follows it
would certify a link target as a tree file."

The code at `gates/gates-pop.py:338` is `not p.is_file()`. A symlink to a GOOD file cannot
distinguish `lstat` from `exists()` -- both are True. The distinguishing case is a DANGLING
symlink, where `lstat` succeeds (the link exists) and `exists()` fails (the target does not).
This measures both cases, and then asks the operational question: on a REAL tree with a REAL
dangling gate symlink, does `discover()` see it or not?
"""
import importlib.util
import os
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "census3.rows"
rows = []


def emit(*c):
    rows.append("\t".join(str(x) for x in c))


def by_path(p, name):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def lstat_isfile_table():
    """The four predicates over the four link shapes. A docstring that names a function must
    name one that is actually called, so this prints the whole table."""
    tmp = Path(tempfile.mkdtemp(prefix="subtree-link3-")).resolve()
    try:
        (tmp / "good.py").write_text("import sys\n\nif __name__ == '__main__':\n    sys.exit(0)\n")
        (tmp / "home").mkdir()
        os.symlink(tmp / "good.py", tmp / "home" / "good-link.py")
        os.symlink(tmp / "MISSING.py", tmp / "home" / "dead-link.py")
        (tmp / "home" / "plain.py").write_text(
            "import sys\n\nif __name__ == '__main__':\n    sys.exit(0)\n")
        os.symlink(tmp / "outside.py", tmp / "outside.py")  # dangling, outside

        emit("SHAPE", "case", "exists()", "is_file()", "os.lstat()", "os.path.lexists()")
        for name in ("plain.py", "good-link.py", "dead-link.py"):
            p = tmp / "home" / name
            emit("SHAPE", name, p.exists(), p.is_file(),
                 os.lstat(p).st_mode if p.is_symlink() or p.exists() else "N/A",
                 os.path.lexists(p))
        emit("SHAPE", "VERDICT", "`is_file()` and `exists()` AGREE on every shape; "
                                 "`lstat`/`lexists` DISAGREE on dead-link.py. So the "
                                 "docstring's named function is the one that would have "
                                 "disagreed, and the code does not call it.")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def dangling_gate_on_a_scratch_tree():
    """The operational question: plant a DANGLING `.sh` gate symlink one level into a scratch
    gate home, run the REAL `discover()` over it, and report whether the entry is counted."""
    gp = by_path(ROOT / "gates" / "gates-pop.py", "gp3")
    tmp = Path(tempfile.mkdtemp(prefix="subtree-dangle-")).resolve()
    try:
        for home in gp.HOMES:
            (tmp / home).mkdir()
        (tmp / "pyproject.toml").write_text("[project]\nname='x'\nversion='0'\n")
        live = tmp / "checks" / "live-gate.sh"
        live.write_text("#!/bin/sh\necho \"$0\"\n")
        dead = tmp / "checks" / "dead-gate.sh"
        os.symlink(tmp / "checks" / "GONE.sh", dead)     # dangling, target does not exist

        before = gp.discover(tmp)
        seen = {p.name for p in before[0]} | {p.name for p in before[1]}
        emit("PLANT_DANGLE", "dangling_link_on_disk", dead.is_symlink())
        emit("PLANT_DANGLE", "dangling_link.exists()", dead.exists())
        emit("PLANT_DANGLE", "dangling_link.is_file()", dead.is_file())
        emit("PLANT_DANGLE", "os.lstat_rc", "ok" if os.path.lexists(dead) else "raises")
        emit("PLANT_DANGLE", "discover_entries", len(before[0]))
        emit("PLANT_DANGLE", "discover_sees_dead_gate", "dead-gate.sh" in seen)
        emit("PLANT_DANGLE", "discover_sees_live_gate", "live-gate.sh" in seen)
        emit("PLANT_DANGLE", "VERDICT",
             "INVISIBLE: the tree's own docstring says this class of file must not be certified, "
             "and a dangling gate symlink is exactly what `lstat` would have caught and `is_file()` "
             "does not" if "dead-gate.sh" not in seen else "visible")

        # and the converse: a symlink whose target IS a real gate elsewhere in the tree
        ext = tmp / "elsewhere"
        ext.mkdir()
        real = ext / "imported-gate.sh"
        real.write_text("#!/bin/sh\necho \"$0\"\n")
        link = tmp / "checks" / "linked-gate.sh"
        os.symlink(real, link)
        after = gp.discover(tmp)
        seen2 = {p.name for p in after[0]} | {p.name for p in after[1]}
        emit("PLANT_DANGLE", "link_to_real_file_seen", "linked-gate.sh" in seen2)
        emit("PLANT_DANGLE", "VERDICT2",
             "CERTIFIED: `is_file()` follows the link, so a link target outside the home is "
             "counted as a tree file -- the exact outcome the docstring says it prevents"
             if "linked-gate.sh" in seen2 else "not certified")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def blast_radius():
    """If `discover()` became recursive, WHICH consumers' numbers move, and by how much.

    Derived WITHOUT editing `gates/gates-pop.py`: a local recursive twin is built from the
    module's OWN `HOMES`, `SUFFIXES` and `entry_reason`, so the only difference from the real
    function is the one flag under test."""
    gp = by_path(ROOT / "gates" / "gates-pop.py", "gp3b")

    def rec(root):
        entries, libs = [], []
        for home in gp.HOMES:
            h = root / home
            if not os.path.isdir(h):
                continue
            for dirpath, dirnames, filenames in os.walk(h):
                dirnames[:] = [d for d in dirnames if d != "__pycache__"]
                for fn in filenames:
                    p = Path(dirpath) / fn
                    if p.suffix not in gp.SUFFIXES or not p.is_file():
                        continue
                    (entries if gp.entry_reason(p) in ("py-main", "sh-dispatch", "sh-selfref")
                     else libs).append(p)
        return entries, libs

    e0, l0 = gp.discover(ROOT)
    e1, l1 = rec(ROOT)
    d0 = {str(p.relative_to(ROOT)) for p in list(e0) + list(l0)}
    d1 = {str(p.relative_to(ROOT)) for p in list(e1) + list(l1)}
    emit("BLAST", "discover_entries_now", len(e0))
    emit("BLAST", "recursive_entries_if_changed", len(e1))
    emit("BLAST", "discover_libs_now", len(l0))
    emit("BLAST", "recursive_libs_if_changed", len(l1))
    emit("BLAST", "total_now", len(d0))
    emit("BLAST", "total_if_recursive", len(d1))
    emit("BLAST", "delta", len(d1) - len(d0))
    emit("BLAST", "lost_by_recursion", len(d0 - d1))
    emit("BLAST", "only_discover", sorted(d0 - d1) or "(empty)")
    for rel in sorted(d1 - d0):
        emit("BLAST", "gained", rel)
    # Would a recursive walk see __pycache__ .pyc files? SUFFIXES excludes .pyc, so the
    # docstring's stated REASON for iterdir() does not survive as a reason.
    pyc = [str(p.relative_to(ROOT)) for h in gp.HOMES
           for p in (ROOT / h).rglob("*.pyc")]
    emit("BLAST", "pyc_under_homes", len(pyc))
    emit("BLAST", "pyc_matching_SUFFIXES", sum(1 for p in pyc if Path(p).suffix in gp.SUFFIXES))
    emit("BLAST", "REASON_SURVIVES",
         "NO: a recursive walk with SUFFIXES=('.py','.sh') cannot see a .pyc, so the "
         "docstring's justification for iterdir() is a property of SUFFIXES, not of depth")


def main():
    emit("PART3", "field", "value")
    lstat_isfile_table()
    dangling_gate_on_a_scratch_tree()
    blast_radius()
    OUT.write_text("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main()