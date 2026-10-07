"""PART 6 -- the MECHANISM, and a clean census of every consumer and what it PRINTS.

(a) MECHANISM. `iterdir()` DOES return `gates/oracles` -- the directory is SEEN. It is dropped
    by `p.suffix not in SUFFIXES`, because a directory's suffix is `''`. So the walk is not
    "blind to the directory"; it is blind to the FILES inside it, and the drop happens on a
    shape the caller never sees. That distinction matters for the fix: a filter that silently
    discards a directory looks identical to a walk that never visited it.

(b) CONSUMERS. Found by a DIRECTORY WALK for `.discover(` calls (Doctrine 1b), every hit printed
    with its line. For each: does it print a SECOND, deeper projection beside `discover()`'s
    number? That is the difference between a KNOWN CEILING and an UNKNOWN ONE.
"""
import ast
import importlib.util
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "census6.rows"
rows = []


def emit(*c):
    rows.append("\t".join(str(x) for x in c))


def by_path(p, name):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def mechanism():
    gp = by_path(ROOT / "gates" / "gates-pop.py", "gp6")
    emit("MECH", "field", "value")
    for home in gp.HOMES:
        h = ROOT / home
        if not os.path.isdir(h):
            continue
        for p in sorted(h.iterdir()):
            if p.is_dir():
                emit("MECH", f"{p.relative_to(ROOT)}",
                     f"is_dir=True suffix={p.suffix!r} in_SUFFIXES="
                     f"{p.suffix in gp.SUFFIXES} is_file={p.is_file()} "
                     f"files_inside={sum(1 for q in p.iterdir() if q.is_file())}")
    emit("MECH", "VERDICT",
         "`iterdir()` RETURNS the directory; line 338 drops it on `p.suffix not in SUFFIXES` "
         "because a directory's suffix is ''. The walk VISITED gates/oracles and DISCARDED it.")
    # how many `.py`/`.sh` files does the dropped directory hold?
    d = ROOT / "gates" / "oracles"
    if d.is_dir():
        inside = [q for q in d.rglob("*") if q.is_file() and q.suffix in gp.SUFFIXES]
        emit("MECH", "gates/oracles files matching SUFFIXES", len(inside))
        for q in inside:
            emit("MECH", "  inside", str(q.relative_to(ROOT)))
        emit("MECH", "gates/oracles ALL files",
             sorted(str(q.relative_to(ROOT)) for q in d.rglob("*") if q.is_file()))


def consumers():
    """Every `.py` in the tree that CALLS `.discover(` on the gates-pop module, plus every file
    that loads `gates/gates-pop.py` by path. Each is classified by whether it prints a second
    projection."""
    skip = {".venv", ".git", "__pycache__", "references", "node_modules", "tinybendygrad",
            ".agents/slop/peakrss"}
    callers, loaders = set(), set()
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in skip]
        for fn in sorted(filenames):
            if not fn.endswith(".py"):
                continue
            p = Path(dirpath) / fn
            try:
                text = p.read_text(errors="replace")
            except OSError:
                continue
            rel = str(p.relative_to(ROOT))
            if "gates/gates-pop.py" in text:
                loaders.add(rel)
            if re.search(r"\w[\w.()]*\.discover\(", text) and (
                    "gates_pop" in text or "gpop" in text or "gp\." in text
                    or "gates-pop" in text):
                callers.add(rel)
    emit("CONSUMERS", "loads_gates_pop_by_path", len(loaders))
    for rel in sorted(loaders):
        emit("CONSUMERS", "  loads", rel)
    emit("CONSUMERS", "calls_discover", len(callers))
    for rel in sorted(callers):
        text = (ROOT / rel).read_text(errors="replace")
        has_walk = "os.walk" in text
        names_ctl = bool(re.search(r"only_walk|WALK-ONLY|walk_control", text))
        prints_two = bool(re.search(r"vs\b|recursive `os\.walk`", text))
        is_owner = rel == "gates/gates-pop.py"
        verdict = ("OWNS IT and does NOT print the ceiling" if is_owner and not names_ctl else
                   "prints the ceiling" if names_ctl else
                   "no ceiling -- prints `discover()`'s number alone")
        emit("CONSUMERS", "  calls", rel,
             f"os.walk={has_walk} names_control={names_ctl} prints_two_counts={prints_two} "
             f"-> {verdict}")


def is_discover_a_gate_body():
    """`discover()` is defined in `gates/gates-pop.py`, so IT is an entry point's dependency, not
    itself a gate. State that, because 'is the shared population a gate' is not the question."""
    gp = ROOT / "gates" / "gates-pop.py"
    mod = by_path(gp, "gp6b")
    entries, libs = mod.discover(ROOT)
    emit("OWNER", "gates-pop.py_is_in_its_own_entries",
         str(gp.relative_to(ROOT)) in {str(p.relative_to(ROOT)) for p in entries})
    emit("OWNER", "discover_has_main_guard",
         "if __name__" in gp.read_text())


def main():
    emit("PART6", "field", "value")
    mechanism()
    consumers()
    is_discover_a_gate_body()
    OUT.write_text("\n".join(rows) + "\n")
    print("\n".join(r for r in rows if r.startswith(("MECH", "CONSUMERS", "OWNER"))))


if __name__ == "__main__":
    main()