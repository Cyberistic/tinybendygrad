#!/usr/bin/env python3
"""Does a `file:line` citation in the port still name what it claims? MEASURED, per class.

    .venv/bin/python checks/citation-gate.py [PORT_DIR]

**A CITATION IS A COORDINATE, AND A COORDINATE GOES STALE WHEN EITHER COMPONENT MOVES -- the TEXT (the line
number) or the CONTENT (the rule).** Nothing in this project pinned either, so this file pins the CONTENT by
asking git, and separates the two failures because they have OPPOSITE REMEDIES:

| class       | what it means                                              | remedy     |
|-------------|------------------------------------------------------------|------------|
| `HOLDS`     | the quoted text is on the line it names                     | --         |
| `STALE-LINE`| the text is in that file, at ANOTHER line                   | RESTORE    |
| `WRONG-FILE`| the text is in another `.py`, not the one named             | RESTORE    |
| `NO-FILE`   | the named file does not resolve                             | RESTORE    |
| `STALE-RULE`| the text is in NO `.py`, and `git log -S` says it was ADDED then REMOVED | **AUTHOR** |
| `PROSE`     | the text is in no `.py` and git says it never existed        | -- not a citation |

**`STALE-LINE` IS RESTORABLE AND `STALE-RULE` IS NOT, AND THAT IS THE WHOLE VERDICT.** A moved line is
repaired by reading the file. A deleted rule has nothing left to read: `spec.py` no longer says the thing the
port's comment says it says, so closing the gap means DECIDING what the port should do -- authoring, not
retyping. A gate that blocked on `STALE-LINE` would be red on the 68-line mass migration that retyping a
number fixes; a gate that ignored `STALE-RULE` would pass a comment that spends a reader's trust on a rule
upstream deleted. So this file blocks on `STALE-RULE` only and PRINTS the rest, with counts.

**AND `STALE-RULE` IS THE CLASS THAT DEFEATS A LINE-NUMBER CHECK AND A TEXT-CHECK-ALIKE.** A citation can
name a line that exists, quote text that is on it, and still describe behaviour that was deleted -- because
the deleted conjunct's SIBLING survived the edit verbatim. See `.agents/slop/speccite/README.md` §3.

    exit 0  no `STALE-RULE`
    exit 1  at least one `STALE-RULE`, each printed with its two commits

TWO METHODS, NO SHARED REGEX. `STALE-LINE`/`HOLDS` ask a substring question of the file's own bytes; `STALE-RULE`
asks git a history question about a string it hands over verbatim. Neither reads the other's tokenizer, so a
plant that defeats one does not defeat the other -- MEASURED, both ways, in the README.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PYROOTS = ("tinygrad", "examples", "extra")
bodies: dict[str, str] = {}
# THE PIN. `git log -S` costs ~1.5 s a quote and this tree has 556 of them, so the verdicts are
# CACHED HERE, keyed by the quote itself. Delete a line and it is re-derived; nothing else is cached.
HIST = os.path.join(ROOT, "checks/citation-gate.ledger.tsv")
# ONE regex finds citations; a DIFFERENT one finds quotes. The two lanes below consume neither.
CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")
QUOTE = re.compile(r"`([^`\n]{8,400})`")
# The THIRD lane's tokenizer, and it is the only regex here that is not a citation or a quote.
TOKENS = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
CLASSES = ("HOLDS", "STALE-LINE", "WRONG-FILE", "NO-FILE", "STALE-RULE", "PROSE", "PAST-EOF")


def python_files() -> dict[str, list[str]]:
    """Basename index over `tinygrad/` ONLY, because that is the port's subject: `spec.py` is
    `tinygrad/uop/spec.py` here and `extra/hcqfuzz/spec.py` is a different program. A bare
    basename is resolvable at all ONLY because the port mirrors upstream's directory layout
    (15 basenames are ambiguous under `tinygrad/**` and the mirror settles every one of them
    that has a `.bend` counterpart) -- so a citation's resolvability is itself a function of a
    file having MOVED."""
    idx: dict[str, list[str]] = {}
    for dp, dn, fn in os.walk(os.path.join(ROOT, "tinygrad")):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for f in fn:
            if f.endswith(".py"):
                idx.setdefault(f, []).append(os.path.normpath(os.path.join(dp, f)))
    return idx


def resolve(name: str, rel: str, idx: dict[str, list[str]]) -> str | None:
    """A bare basename is disambiguated by MIRRORING: `tinybendygrad/renderer/cstyle.bend` citing
    `cstyle.py` means `tinygrad/renderer/cstyle.py`. 15 basenames are ambiguous under
    `tinygrad/**` (`dtype.py`, `__init__.py`, `movement.py`, ...) and the mirror settles every
    one of them that the port has a counterpart for."""
    if "/" in name:
        for base in PYROOTS + (".",):
            c = os.path.normpath(os.path.join(ROOT, base, name))
            if os.path.exists(c):
                return c
        return None
    d = os.path.dirname(rel)
    if d.startswith("tinybendygrad"):
        c = os.path.normpath(os.path.join(ROOT, d.replace("tinybendygrad", "tinygrad", 1), name))
        if os.path.exists(c):
            return c
    hits = idx.get(name)
    return hits[0] if hits and len(hits) == 1 else None


def read(path: str) -> str:
    """Any `.py` the port may cite, cached: `resolve` can land outside `tinygrad/` (a
    `gates/oracles/` script, an `examples/` file), and a citation is only as good as the
    bytes behind it."""
    if path not in bodies:
        bodies[path] = open(path, encoding="utf-8", errors="replace").read()
    return bodies[path]


def blocks(src: list[str]) -> list[list[tuple[int, str]]]:
    """Runs of consecutive `#` comment lines. A citation and the source it reproduces are one
    thought, and a thought in these files spans lines -- so the BLOCK is the unit, not the line."""
    out, cur = [], []
    for i, line in enumerate(src, 1):
        h = line.find("#")
        if h < 0:
            if cur:
                out.append(cur)
                cur = []
            continue
        cur.append((i, line[h:]))
    if cur:
        out.append(cur)
    return out


def history(quote: str, pathspec: str) -> list[str]:
    r = subprocess.run(["git", "log", "-S" + quote, "--format=%h", "--", pathspec],
                       cwd=ROOT, capture_output=True, text=True)
    return [c for c in r.stdout.split() if c]


def main(argv: list[str]) -> int:
    port = os.path.normpath(os.path.join(ROOT, argv[1])) if len(argv) > 1 else os.path.join(ROOT, "tinybendygrad")
    idx = python_files()
    for base in PYROOTS:
        for dp, dn, fn in os.walk(os.path.join(ROOT, base)):
            dn[:] = [d for d in dn if d != "__pycache__"]
            for f in fn:
                if f.endswith(".py"):
                    read(os.path.normpath(os.path.join(dp, f)))  # WRONG-FILE searches all of them
    hist: dict[str, str] = {}
    if os.path.exists(HIST):
        for ln in open(HIST, encoding="utf-8"):
            q, _, c = ln.rstrip("\n").partition("\t")
            hist[q] = c
    fresh: list[tuple[str, str]] = []
    found: dict[str, list[str]] = {c: [] for c in CLASSES}
    total = unbound = 0

    for dp, dn, fn in ([(os.path.dirname(port), [], [os.path.basename(port)])] if os.path.isfile(port)
                        else os.walk(port)):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for f in sorted(fn):
            if not f.endswith(".bend"):
                continue
            path = os.path.join(dp, f)
            rel = os.path.relpath(path, ROOT)
            for blk in blocks(open(path, encoding="utf-8", errors="replace").read().splitlines()):
                cites = [(bi, m.group(1), int(m.group(2)), ln)
                         for bi, (ln, c) in enumerate(blk) for m in CITE.finditer(c)]
                total += sum(1 for c in cites if c[1].endswith(".py"))
                quotes = [q for ln, c in blk if cites and ln == cites[0][3]
                          for q in QUOTE.findall(c)]
                # PRECISION, NOT RECALL. Exactly one citation of ANY extension in the block, and
                # the claim is the LONGEST backtick span ON THE CITATION'S OWN LINE: a span on a
                # later line of the block is elaboration of that claim, not a second claim. One
                # citation means there is no ambiguity about WHICH line is being claimed, so every
                # verdict is defensible line by line. Everything else is COUNTED, never judged.
                if len(cites) != 1 or not quotes or not cites[0][1].endswith(".py"):
                    unbound += sum(1 for c in cites if c[1].endswith(".py"))
                    continue
                bi, name, line, srcline = cites[0]
                quote = max(quotes, key=len)
                tgt = resolve(name, rel, idx)
                if tgt is None:
                    found["NO-FILE"].append(f"{rel}:{srcline}  {name}:{line}  `{quote[:60]}`")
                    continue
                n = read(tgt).count("\n") + 1
                if line > n:
                    found["PAST-EOF"].append(f"{rel}:{srcline}  {name}:{line} of {n}  `{quote[:60]}`")
                    continue
                body = read(tgt)
                if quote in body:
                    # EVERY occurrence, and the verdict is about the NEAREST one. Taking the
                    # first is wrong: `Allocator` first occurs inside `BumpAllocator` on
                    # device.py:11, `free_cache` first occurs at a CALL site -- both were
                    # reported as "the text is at line 11/273" for a comment citing 259/283.
                    # A short quote has many homes, so say which one and how far, never "the".
                    lines_at = [body[: m.start()].count("\n") + 1
                                for m in re.finditer(re.escape(quote), body)]
                    near = min(lines_at, key=lambda n: abs(n - line))
                    found["HOLDS" if near == line else "STALE-LINE"].append(
                        f"{rel}:{srcline}  {name}:{line}, nearest occurrence is {near} "
                        f"({abs(near - line)} off, {len(lines_at)} in the file)  `{quote[:60]}`")
                    continue
                other = next((p for p, b in list(bodies.items()) if quote in b), None)
                if other is not None:
                    found["WRONG-FILE"].append(f"{rel}:{srcline}  {name}:{line}  text is in {other}  `{quote[:60]}`")
                    continue
                key = quote
                if key not in hist:
                    cs = history(quote, os.path.relpath(tgt, ROOT))
                    hist[key] = ",".join(cs)
                    fresh.append((quote, ",".join(cs)))
                cs = [c for c in hist[key].split(",") if c]
                if len(cs) < 2:
                    found["PROSE"].append(f"{rel}:{srcline}  {name}:{line}  never existed  `{quote[:60]}`")
                    continue
                # `git log -S` is TEXT-EXACT, so this class is NECESSARY FOR A DELETION AND NOT
                # SUFFICIENT: reformatting, an inserted flag, or a renamed constructor all read as
                # "added then removed" -- MEASURED 4 of the 5 hits on this tree are exactly that.
                # So each row carries the one triage hint that separates them: are the quote's
                # identifiers still all in the file? AND IT IS NOT A VERDICT EITHER, because the
                # defect this instrument was built for -- `isinstance(x.arg, CallInfo) and
                # x.dtype is x.arg.dtype`, whose SECOND conjunct was deleted -- reports "all
                # survive", because the deleted conjunct shares every identifier with the sibling
                # that stayed. A hint that is wrong on the target defect is a hint, so this file
                # blocks on the POPULATION and names the ambiguity instead of resolving it.
                gone = [t for t in set(TOKENS.findall(quote))
                        if len(t) > 3 and t not in set(TOKENS.findall(read(tgt)))]
                found["STALE-RULE"].append(
                    f"{rel}:{srcline}  {name}:{line}  added+removed by {','.join(cs)}  "
                    f"{'GONE: ' + ','.join(sorted(gone)) if gone else 'identifiers all survive'}  "
                    f"`{quote[:60]}`")

    if fresh:
        with open(HIST, "a", encoding="utf-8") as fh:
            for q, c in fresh:
                fh.write(f"{q}\t{c}\n")
    judged = sum(len(found[c]) for c in CLASSES)
    print(f"  {total} `file:line` citations into a Python tree, from {port.replace(ROOT + '/', '')}/**")
    print(f"  {judged} ADJUDICABLE (one `.py` citation + one quote in the block); {unbound} unbound, counted not judged")
    for c in CLASSES:
        if found[c]:
            tag = "BLOCKS" if c == "STALE-RULE" else "reported"
            print(f"  {len(found[c]):5d} {c:12} ({tag})")
            for row in found[c][:60]:
                print(f"        {row}")
            if len(found[c]) > 60:
                print(f"        ... and {len(found[c]) - 60} more")
    if not found["STALE-RULE"]:
        print("  GREEN: no citation names a rule git says was added and then removed.")
        return 0
    print("  RED: a citation quotes text upstream added and then removed. NECESSARY, NOT SUFFICIENT --")
    print("       4 of 5 on this tree are RESPELLINGS. Only a human reading the rule can split them.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))