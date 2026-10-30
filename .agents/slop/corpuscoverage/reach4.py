#!/usr/bin/env python3
"""STATIC CALL-GRAPH REACHABILITY over the port's `.bend` sources -- DEF-BODY PRECISE.

THE INSTRUMENT, AND WHY IT IS WRITTEN THIS WAY.  Bend's `def` bodies are INDENTED
blocks, so a def's body is the run of lines after its `def` header whose indentation is
deeper than the header's.  This parser splits each file into (def-name, body-lines) and
attributes every call site to the def that contains it.  A def is REACHED only when a
call site INSIDE A REACHED DEF names it.

THE CALL-SITE GRAMMAR.  A qualified call is `ALIAS.rest`, where `rest` is one or more
dotted segments: `O.UOp.new(`, `O.GroupOp.elementwise(`, `O.UOp.dtype.of(`.  The def's own
name is `rest` (`UOp.new`, `GroupOp.elementwise`, `UOp.dtype.of`) and it lives in the
file the ALIAS names.  An unqualified call is `f(` and resolves to a def of the SAME
FILE, and only when the name is unique in that file.

WHAT IT DOES NOT SEE, and the direction of each miss:
  * a `+`-bound PARAMETER shadowing a module-level def of the same name -- UNDER-approx.
  * a def reached only through a namespace the parser did not attribute -- UNDER-approx.
Both miss real reaches.  Neither can INVENT one: a def this calls REACHED is named by a
call site inside a def the walk actually entered.
"""
import re, sys
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
IMPORT_RE = re.compile(r'^\s*import\s+(\S+?)(?:\s+as\s+\w+)?\s*$')
DEF_RE = re.compile(r'^(\s*)def\s+((?:[A-Za-z_][\w]*\.)*[A-Za-z_][\w]*)\s*[\(\.:]')
# `ALIAS.rest(` -- ALIAS is one segment, rest is one OR MORE dotted segments.
QUAL_CALL_RE = re.compile(r'(?<![.\w])([A-Za-z_][\w]*)\.((?:[A-Za-z_][\w]*\.)*[A-Za-z_][\w]*)\s*\(')
BARE_CALL_RE = re.compile(r'(?<![.\w])([A-Za-z_][\w]*)\s*\(')

_IMPORTS: dict[Path, list[Path]] = {}


def imports_of(p: Path) -> list[Path]:
    if p in _IMPORTS:
        return _IMPORTS[p]
    out = []
    for line in p.read_text(errors="replace").splitlines():
        m = IMPORT_RE.match(line)
        if not m or m.group(1) == "Base":
            continue
        cand = (p.parent / m.group(1)).resolve()
        if cand.exists():
            out.append(cand)
    _IMPORTS[p] = out
    return out


def closure(entry: Path) -> set[Path]:
    seen, stack = set(), [entry.resolve()]
    while stack:
        f = stack.pop()
        if f in seen:
            continue
        seen.add(f)
        stack.extend(c for c in imports_of(f) if c not in seen)
    return seen


def strip_comments(text: str) -> list[str]:
    out = []
    for line in text.splitlines():
        if line.count('"') % 2 == 1:
            out.append(line)
            continue
        out.append(line.split('#', 1)[0])
    return out


def defs_and_bodies(f: Path):
    lines = strip_comments(f.read_text(errors="replace"))
    out, i = [], 0
    while i < len(lines):
        m = DEF_RE.match(lines[i])
        if not m:
            i += 1
            continue
        ind, name = len(m.group(1)), m.group(2)
        body, j = [lines[i]], i + 1
        while j < len(lines):
            ln = lines[j]
            if not ln.strip():
                body.append(ln)
                j += 1
                continue
            if len(ln) - len(ln.lstrip()) <= ind:
                break
            body.append(ln)
            j += 1
        out.append((name, body))
        i = j
    return out


def analyse(entry: Path):
    cl = closure(entry)

    def is_port(f: Path) -> bool:
        try:
            f.relative_to(ROOT / "tinybendygrad")
            return True
        except ValueError:
            return False

    port = {f for f in cl if is_port(f)}
    harness = {f for f in cl if not is_port(f)}

    alias: dict[Path, dict[str, Path]] = {}
    for f in cl:
        a = {}
        for line in f.read_text(errors="replace").splitlines():
            m = IMPORT_RE.match(line)
            if not m or m.group(1) == "Base":
                continue
            sp = m.group(1)
            rest = line.split(" as ", 1)
            al = rest[1].strip() if len(rest) > 1 else Path(sp).stem
            cand = (f.parent / sp).resolve()
            if cand.exists():
                a[al] = cand
        alias[f] = a

    defs: set[tuple[Path, str]] = set()
    names_in: dict[Path, set[str]] = {}
    for f in cl:
        for name, _ in defs_and_bodies(f):
            defs.add((f, name))
            names_in.setdefault(f, set()).add(name)

    def sites_of(f: Path, body: list[str]):
        """EVERY call site in the body, with EVERY reading the grammar allows.

        A dotted name `a.b(` has TWO possible readings and the parser must not pick
        one: `a` may be an IMPORT ALIAS (`O.UOp.new(`) or a LOCAL NAMESPACE
        (`GroupOp.commutative(`, `rows.pick(`).  BOTH are emitted and `resolve` decides,
        because guessing wrong in either direction loses a real reach.
        """
        cs = []
        for line in body:
            for m in QUAL_CALL_RE.finditer(line):
                cs.append(("Q", alias[f].get(m.group(1)), m.group(2)))
                # the same text read as a LOCAL qualified name
                cs.append(("QL", f, m.group(1) + "." + m.group(2)))
            # the bare reading of the LAST segment
            for m in QUAL_CALL_RE.finditer(line):
                cs.append(("L", f, m.group(2).split(".")[-1]))
            rest = QUAL_CALL_RE.sub(" ", line)
            for m in BARE_CALL_RE.finditer(rest):
                cs.append(("L", f, m.group(1)))
        return cs

    def resolve(origin: Path, kind: str, tgt: Path | None, nm: str):
        if kind == "Q":
            return [(tgt, nm)] if (tgt, nm) in defs else []
        if kind == "QL":
            # a local qualified name: the file defines `ns.member` -- and the LAST
            # segment alone may also be the def (`def member(` in the same file).
            out = []
            if (origin, nm) in defs:
                out.append((origin, nm))
            else:
                last = nm.split(".")[-1]
                if (origin, last) in defs and sum(1 for x in names_in[origin] if x == last) == 1:
                    out.append((origin, last))
            return out
        if (origin, nm) in defs and sum(1 for x in names_in[origin] if x == nm) == 1:
            return [(origin, nm)]
        return []

    # SEEDS: the harness's own defs are ENTRY POINTS -- the walk must ENTER them, or the
    # harness's private helpers (`matmul_of`, `rows.pick3`, ...) never lead to a port def.
    # Only PORT defs are counted as reached.
    seeds: set[tuple[Path, str]] = set()
    for f in harness:
        for name, body in defs_and_bodies(f):
            seeds.add((f, name))

    reached: set[tuple[Path, str]] = set()
    stack = list(seeds)
    while stack:
        it = stack.pop()
        if it in reached:
            continue
        reached.add(it)
        f = it[0]
        for nm2, body in defs_and_bodies(f):
            if nm2 != it[1]:
                continue
            for kind, tgt, nm in sites_of(f, body):
                for site in resolve(f, kind, tgt, nm):
                    if site not in reached:
                        stack.append(site)
    portreach = {d for d in reached if d[0] in port}
    return cl, port, harness, defs, names_in, seeds, portreach


def main():
    entry = Path(sys.argv[1]).resolve()
    cl, port, harness, defs, names_in, seeds, reached = analyse(entry)
    portdefs = {d for d in defs if d[0] in port}
    portreach = {d for d in reached if d[0] in port}
    print(f"ENTRY: {entry.relative_to(ROOT)}")
    print(f"closure files {len(cl)} (port {len(port)}, harness {len(harness)})")
    print(f"SEEDS: {len(seeds)}")
    for f, n in sorted(seeds, key=lambda x: (str(x[0]), x[1])):
        print(f"   SEED {f.relative_to(ROOT)}::{n}")
    print(f"port defs {len(portdefs)}   REACHED {len(portreach)}   UNREACHED {len(portdefs) - len(portreach)}")
    byfile: dict[Path, list[str]] = {}
    for f, n in sorted(portdefs - portreach):
        byfile.setdefault(f, []).append(n)
    for f in sorted(byfile, key=str):
        print(f"   UNREACH {f.relative_to(ROOT)}  ({len(byfile[f])}/{len(names_in[f])})")
        for n in sorted(byfile[f]):
            print(f"       - {n}")


if __name__ == "__main__":
    main()
