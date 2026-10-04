#!/usr/bin/env python3
"""late-zero-classify.py -- CLASSIFY EVERY ZERO IN ra-mutations / ra2-mutations.

    python3 .agents/slop/late-zero-classify.py

A zero is one of exactly five things, and `zero-classify.py` owns the vocabulary --
QUERIED through `staged_mut.zero_verdicts()`, never transcribed, because a sixth
spelling reads as an unrecognised measurement and that classifier EXITS rather than
inventing a verdict.  A zero that fits none of them is an ERROR, never a pass.

WHAT MAKES THIS NOT A GUESS.  The classification turns on ONE question that is
DECIDABLE from the file: does the mutated def have a NAME that appears in any emitted
row's VALUE?  A row is `name=value`, so a def that no row's value mentions is a def
the reader cannot see -- the mutation is real, the port is real, and the gate is
blind.  That is `INVISIBLE-to-reader` and it is a MEASUREMENT, not an opinion:

    * the def's name appears in some row value      -> the reader CAN see it, so a
      zero here is either NO-MUTATION-WRITTEN (the mutation aimed elsewhere) or a
      genuine PORT-DEFECT.  Those two are told apart by whether the def is CALLED:
      a def no live code calls cannot be load-bearing at all.
    * the name appears in NO row value              -> INVISIBLE-to-reader.

A def nothing calls is not UNREACHABLE by theorem; it is a def nothing calls, and this
prints the caller census so the reader can tell a dead def from an unread one.
"""
import ast
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import staged_mut as SM

LATE = HERE.parent.parent / "tinybendygrad/codegen/late"
TABLES = [("ra-mutations.txt", "ra-mutate.py"),
          ("ra2-mutations.txt", "ra-mutate2.py")]


def rows_of(paths):
    """Every `name=value` line the three `late/` files emit, as one dict."""
    out = {}
    for p in paths:
        r = subprocess.run([str(SM.BEND), str(p)], capture_output=True, text=True)
        for line in r.stdout.splitlines():
            m = re.match(r"^([A-Za-z_][A-Za-z_0-9]*)=(.*)$", line)
            if m:
                out[m.group(1)] = m.group(2)
    return out


def mutanchor_transform(harness):
    """The harness's own `q()`, EXECUTED from its AST -- the same call
    `mutanchor.anchors()` makes, for the same reason: a transcribed qualification
    list is a second copy of the one thing most likely to drift."""
    import mutanchor as MA
    return MA.transform(MA.parse(str(HERE / harness)), harness)


def mutation_of(harness, label):
    """`(find, repl)` for one MUTATION row, TRANSFORMED, read with `ast`.

    `ast` rather than importing, because importing a harness RUNS its mutation loop
    -- which is the entire reason `mutanchor` reads harnesses with `ast` in the first
    place.  The transform is applied here because the anchor the harness SEARCHES is
    `q(find)`, not `find`; searching the raw literal against the file is the reader
    bug that reported 36 stale anchors where there were 15.
    """
    tree = ast.parse((HERE / harness).read_text())
    q = mutanchor_transform(harness)
    best = None
    for n in tree.body:
        if not (isinstance(n, ast.Assign) and getattr(n.targets[0], "id", None)
                in ("MUT", "MUTS", "MUTATIONS")):
            continue
        try:
            v = ast.literal_eval(n.value)
        except (ValueError, SyntaxError, TypeError):
            continue
        if best is None or len(v) > len(best):
            best = v
    for e in best or []:
        if e[0] == label:
            f, r = e[1], e[2]
            if q:
                f, r = q(f), q(r)
            return f, r
    return None, None


def def_name(find, src):
    """The def an anchor belongs to.

    Most anchors are a body EXPRESSION, not a `def` header -- and stopping there
    classifies eight of ra-mutate.py's twelve zeros as "no identifier to trace",
    which is not a verdict, it is an admission that the reader gave up.  So the
    anchor is LOCATED in the live source and the enclosing `def` is taken from the
    header above it.  An anchor that cannot be located is reported as NOT-FOUND and
    the row is refused rather than guessed at, because an unlocatable anchor means
    the file this harness read is not the file on disk.
    """
    head = re.match(r"\s*def\s+([A-Za-z_][A-Za-z_0-9_.]*)\s*\(", find)
    if head:
        return head.group(1)
    i = src.find(find)
    if i < 0:
        return None
    for line in reversed(src[:i].splitlines()):
        m = re.match(r"\s*def\s+([A-Za-z_][A-Za-z_0-9_.]*)\s*\(", line)
        if m:
            return m.group(1)
    return None


def callers(src, name):
    """How many times `name` is CALLED, excluding its own `def` and its own mention
    inside the definition's body -- a caller census, not a substring count."""
    if not name:
        return 0
    n = len(re.findall(r"(?<![\w.])%s\s*\(" % re.escape(name.split(".")[-1]), src))
    return max(n - 1, 0)


def main():
    verdicts = SM.zero_verdicts()
    files = sorted(LATE.glob("*.bend"))
    rows = rows_of(files)
    values = " ".join(rows.values())
    print("zero-classify.py's vocabulary, QUERIED: %s" % " | ".join(verdicts))
    print("row set: %d rows over %s\n" % (len(rows), ", ".join(p.name for p in files)))
    src = "\n".join(p.read_text() for p in files)

    for table, harness in TABLES:
        p = HERE / table
        if not p.exists():
            print("%s: no such table" % table)
            continue
        zeros = [l.strip() for l in p.read_text().splitlines()
                 if l.startswith("| ") and "| NONE |" in l]
        print("=" * 78)
        print("%s -- %d rows moved nothing" % (table, len(zeros)))
        print("=" * 78)
        for line in zeros:
            label = line[2:].split(" | ")[0].strip()
            find, _ = mutation_of(harness, label)
            if not find or find not in src:
                # REFUSE rather than classify: a mutation the harness reports as APPLIED
                # whose anchor is not in the file it supposedly ran against means the
                # table and the tree disagree, and every verdict below would be about a
                # file nobody is looking at.  This is the mirror-stale failure wearing a
                # different hat.
                print("\n  %s" % label)
                print("    VERDICT: REFUSED -- the anchor is not in late/*.bend, so this")
                print("    row cannot be classified at all.  Re-run ra-mutate.py; do not")
                print("    read this row's zero as a measurement.")
                continue
            name = def_name(find, src)
            seen = bool(name) and name.split(".")[-1] in values
            nc = callers(src, name)
            if not name:
                v, why = "NO-MUTATION-WRITTEN", (
                    "the anchor is in the file but no enclosing `def` header could be "
                    "found above it, so the mutation aims at top-level code that no row "
                    "reaches.")
            elif seen:
                v, why = ("PORT-DEFECT" if nc else "NO-MUTATION-WRITTEN"), (
                    "`%s` IS named in %d row value(s) and is CALLED %d time(s), so the "
                    "reader can see it and the port calls it -- yet the mutation moved "
                    "no row, which is a PORT-DEFECT: a fixture asserts this def's own "
                    "answer." % (name, sum(1 for v in rows.values()
                                           if name.split(".")[-1] in v), nc)
                    if nc else
                    "`%s` is named in a row value but is CALLED %d times -- nothing "
                    "calls it, so it cannot be load-bearing at any site." % (name, nc))
            else:
                v, why = "INVISIBLE-to-reader", (
                    "no emitted row VALUE mentions `%s`, so the reader cannot see the "
                    "def the mutation edits; the def is called %d time(s), so it is "
                    "live code that the gate never observes.  A `0` here is a REQUEST "
                    "FOR A FIXTURE, not a coverage claim." % (name, nc))
            print("\n  %s" % label)
            print("    def named by the anchor : %s" % (name or "(none -- an expression)"))
            print("    appears in a row value  : %s" % ("yes" if seen else "NO"))
            print("    call sites in late/*.bend: %d" % nc)
            print("    VERDICT: %s" % v)
            for s in why.split(".  "):
                if s.strip():
                    print("      " + s.strip().rstrip(".") + ".")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())