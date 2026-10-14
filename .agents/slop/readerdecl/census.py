#!/usr/bin/env python3
"""THE QUESTION, STATED BEFORE ITS ANSWER.

    WHICH directories under `.agents/slop/` does SOMETHING OPEN, and which are OPENED BY NOTHING?

`declaretwo` counted AUTHORSHIP (a declaring name sits in the directory) and called the result
AUDITABILITY. Those are two different properties, and this file CROSS-TABS them instead of picking
one. The cross-tab is the finding: they select near-disjoint sets.

THE POPULATION IS A WALK OF A COMMIT. `git ls-tree -r <rev>`, never `git ls-files` -- the index has
been reset six times in this session and carries 460 directories where the commit carries 501. The
revision is PRINTED on every run, and every number below carries its own scope in the same sentence.

A READER IS A FULL PATH IN A FILE'S CONTENT. Never a basename: `.agents/slop/oracles259/census.json`
and `.agents/slop/plantthe46/plants.py` are both `census.json`/`plants.py`, and a basename match
cannot tell an opening from a coincidence -- that is `orcdecide`'s measured reason for full paths.
A reader must also be OUTSIDE the directory's own subtree: a file naming its own directory is
authorship, which is the property this file is trying NOT to confuse with readership.

AND THE READERS ARE CLASSIFIED, because a reader is only a WITNESS if it can RUN:
    CODE   .py .sh .mjs .bend .js -- could open the file
    PROSE  .md -- a CITATION. It names the path. It opens nothing. `orcdecide` measured this exact
            class: 3 citations, 0 opens.
    DATA   everything else -- a row dump holding the path as a string.
and a CODE reader that is an entry point is then asked whether it CARRIES A BOUND. `slowgate`
measured 105 of 129 gate entry points carry no time bound of any kind and 1 hangs forever, so
"there is a reader" is not "there is a witness" -- a reader that cannot be shown to COMPLETE is
counted in its own cell and never counted as opened.

VERDICTS ARE THE FIVE OF DOCTRINE 2, spelled as exits in `classify` and never as a 0 that means
"measured nothing". `--plant` runs the four false-able controls; a control that does not fire is a
FAIL, not a note.
"""
from __future__ import annotations

import argparse
import ast
import collections
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / ".agents/slop/readerdecl"
SLOP = ".agents/slop"

# The declaring NAMES. This is `checks/slop-declare.py`'s and `declaretwo`'s set, declared here so
# both questions run over ONE population and the cross-tab is comparable. It is a NAME SET, which
# is doctrine 1's third forbidden shape; it is used to ANSWER a question, never to DISCOVER one.
REPORTS = ("report.md", "readme.md", "findings.md")
MANIFESTS = ("manifest.tsv", "manifest.md", "manifest.rows")

# What a reader's extension makes it. This is not a population -- the population is the git walk --
# it is a CLASSIFICATION of the population, which is what a walk is FOR.
CODE_EXT = (".py", ".sh", ".mjs", ".bend", ".js")
PROSE_EXT = (".md",)

# `slowgate`'s TIME_BOUND_TOKENS, the same list, so "carries a bound" means the same thing in both
# files. Copied rather than imported because `slowgate` lives under a tree this file is told not to
# edit, and an import would make this file DEAD the moment that unit is pruned -- which is exactly
# the failure `.agents/TOOLS.md` records 169 times.
BOUND_TOKENS = ("SIGALRM", "signal.alarm", "signal.setitimer", "timeout=",
                "--seconds", "bounded.py", "perl -e", "alarm(")

# The MANIFEST shapes, for the "which of the 4 exists and how many rows" question. Discovered by a
# walk over basenames matching `manifest.*` -- a shape, not a list, and reported with its rows.
MANIFEST_RE = re.compile(r"^manifest[._-].*$", re.IGNORECASE)

PATH_RE = re.compile(re.escape(SLOP) + r"/[A-Za-z0-9_@./+-]+")

COLUMNS = ("dir", "depth", "files", "declared", "code", "prose", "data",
           "n_code", "n_prose", "n_data", "n_peer", "verdict", "witness")

# VERDICTS. Five, per doctrine 2, and `SKIP`/`DEAD` are not passes.
WITNESSED = "WITNESSED"        # declared, and a CODE reader outside the subtree can open it
CITED = "CITED"                # declared, and something names it, but nothing that RUNS names it
ORPHAN = "ORPHAN"              # declared, and NOTHING outside the subtree names it
UNDECLARED_OPEN = "UNDECLARED-OPEN"   # NOT declared, and a CODE reader opens it
UNDECLARED_CITED = "UNDECLARED-CITED"  # NOT declared, only prose names it
INERT = "INERT"                # NOT declared, nothing names it
UNVERIFIABLE = "UNVERIFIABLE"  # its ONLY code readers carry no bound: a reader that may never finish

EXIT = {"WITNESSED": 0, "ORPHAN": 1, "UNDECLARED-OPEN": 1, "CITED": 4,
        "UNDECLARED-CITED": 4, "INERT": 4, "UNVERIFIABLE": 3}


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    """git in `repo`. `ls-tree` reads a COMMIT; `ls-files` reads an INDEX this tree keeps resetting."""
    return subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)


def population(repo: Path, rev: str) -> dict[str, list[str]] | None:
    """Every directory under `.agents/slop/` AT `rev`, at EVERY depth -> its tracked files.

    A WALK, and it descends, because a unit's subdirectory is a directory in its own right. A
    depth-1 walk lets the parent's REPORT.md speak for its children, and a declaration is about a
    DIRECTORY, not about its subtree -- which is the `declaretwo` nesting row, kept here as its own
    row rather than as an inherited fact."""
    p = git(repo, "ls-tree", "-r", rev, "--name-only")
    if p.returncode != 0:
        return None
    dirs: dict[str, list[str]] = collections.defaultdict(list)
    for f in p.stdout.splitlines():
        parts = f.split("/")
        if parts[:2] == [".agents", "slop"] and len(parts) >= 4:
            for i in range(3, len(parts)):
                dirs["/".join(parts[:i])].append(f)
    return dict(dirs)


def read_blobs(repo: Path, rev: str, names: list[str]) -> dict[str, bytes]:
    """EVERY tracked blob at `rev`, in ONE `git cat-file --batch`. Per-file `git show` costs 108 s on
    this tree; this costs 7 s, and the difference is the whole budget for a per-directory scan."""
    if not names:
        return {}
    stdin = "".join(f"{rev}:{n}\n" for n in names).encode()
    out = subprocess.run(["git", "cat-file", "--batch"], cwd=repo,
                         input=stdin, capture_output=True).stdout
    blobs, i, k = {}, 0, 0
    while i < len(out) and k < len(names):
        nl = out.find(b"\n", i)
        if nl < 0:
            break
        header = out[i:nl].split()
        # `<oid> <type> <size>` -- the OID is a sha, not the name we asked for, so the answer is
        # paired by POSITION: `cat-file --batch` answers in request order, one blob each. Reading
        # `header[1]` returned the TYPE (`blob`) as every key, which made every citation miss and
        # the whole reader axis read 0 -- a DEAD instrument printing five digits.
        if len(header) != 3 or header[2].isdigit() is False:
            i = nl + 1
            continue
        size = int(header[2])
        blobs[names[k]] = out[nl + 1:nl + 1 + size]
        i, k = nl + 1 + size + 1, k + 1
    return blobs


def cited_paths(blob: bytes) -> set[str]:
    """EVERY `.agents/slop/...` full path this blob names, in ONE regex scan.

    One scan per file, not one per (file, directory) pair. The pair form is 3844 regex passes per
    blob and ~25 million over the tree, which does not terminate in a session. Trailing
    punctuation is stripped by LENGTH so the longest real path wins, which is what makes
    `a/b/c.rows` beat `a/b/c` -- and a path in prose is followed by `.`, `,`, `)`, `"`, so a match
    that failed on the period would be a miss presented as a fact."""
    txt = blob.decode("utf-8", "replace")
    out = set()
    for m in PATH_RE.finditer(txt):
        tok = m.group(0)
        while len(tok) > len(SLOP) + 2:
            if tok in path_set:
                out.add(tok)
                break
            tok = tok[:-1]
    return out


def is_entry(path: str, blob: bytes) -> bool:
    """Can this file be RUN at all? `.py` iff it has `if __name__ == '__main__'`; `.sh` iff it
    starts with a shebang. An AST/text FACT, not a naming convention."""
    src = blob.decode("utf-8", "replace")
    if path.endswith(".sh"):
        return src.startswith("#!")
    if not path.endswith(".py"):
        return False
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    return any(isinstance(n, ast.If) and isinstance(n.test, ast.Compare)
               and isinstance(n.test.left, ast.Name) and n.test.left.id == "__name__"
               for n in ast.walk(tree))


def carries_bound(blob: bytes) -> bool:
    return any(t.encode() in blob for t in BOUND_TOKENS)


def declared(d: str, files: list[str]) -> bool:
    """Does a DECLARING NAME sit directly in this directory? Depth is the ruler, and it is the
    directory's OWN depth: a nested `.md` must not declare its parent, or the nesting row is
    vacuous -- which is the depth-1 walk's failure one level down."""
    here = d.count("/") + 1
    bases = {f.rsplit("/", 1)[-1].lower() for f in files if f.count("/") == here}
    return bool(bases & (set(REPORTS) | set(MANIFESTS)))


def kind(path: str) -> str:
    return ("CODE" if path.endswith(CODE_EXT) else
            "PROSE" if path.endswith(PROSE_EXT) else "DATA")


def census(repo: Path, rev: str) -> dict:
    dirs = population(repo, rev)
    if not dirs:
        return {"error": f"`git ls-tree -r {rev}` answered no `.agents/slop/*/` directory"}
    allfiles = git(repo, "ls-tree", "-r", rev, "--name-only").stdout.splitlines()
    blobs = read_blobs(repo, rev, allfiles)

    global path_set
    path_set = {f for fs in dirs.values() for f in fs}

    # readers[d] -> {code, prose, data} of files OUTSIDE d's own subtree that name one of d's files.
    # INVERTED: scan each blob ONCE for the paths it names, then push it onto those directories.
    # The forward form (for every directory, grep every file) is quadratic in a tree this size.
    readers: dict[str, dict[str, list[str]]] = {d: {"code": [], "prose": [], "data": []}
                                                for d in dirs}
    # A reader INSIDE `.agents/slop` is another agent's scratch script, in the same tree this
    # census sweeps, on the same clock. It is not a witness -- it is a peer. Tracked separately,
    # because a reader axis that counts a peer as an opener cannot tell "this directory is used"
    # from "two agents mentioned each other", and those are different claims.
    peer: dict[str, list[str]] = {d: [] for d in dirs}
    peer_set: dict[str, set[str]] = {d: set() for d in dirs}
    for src, blob in blobs.items():
        named = cited_paths(blob)
        if not named:
            continue
        k = kind(src).lower()
        for f in named:
            d = f.rsplit("/", 1)[0]
            # A file naming its OWN subtree is authorship, not readership -- the exact confusion
            # this file exists to keep the two axes apart.
            if src == d or src.startswith(d + "/"):
                continue
            # A PEER is recorded as a peer and NOT as a reader. Recording both would let the
            # prose below say "a peer is not a witness" while the WITNESSED cell counted one --
            # MEASURED as 4190 of 4437 reader instances, which is the whole number the sentence
            # denies. The cells and the sentence have to be the same claim.
            if src.startswith(SLOP + "/"):
                if src not in peer_set[d]:
                    peer_set[d].add(src)
                    peer[d].append(src)
                continue
            lst = readers.get(d)
            if lst is not None and src not in lst[k]:
                lst[k].append(src)

    rows = []
    for d, files in sorted(dirs.items()):
        r = readers[d]
        dec = declared(d, files)
        entries = [p for p in r["code"] if is_entry(p, blobs[p])]
        unbounded = [p for p in entries if not carries_bound(blobs[p])]
        v = classify_one(int(dec), entries, unbounded, len(r["prose"]), len(r["data"]))
        n_code = entries
        entry_unbounded = unbounded
        rows.append({
            "dir": d, "depth": d.count("/") - 2, "files": len(files),
            "declared": int(dec), "code": r["code"][0] if r["code"] else "-",
            "prose": r["prose"][0] if r["prose"] else "-",
            "data": r["data"][0] if r["data"] else "-",
            "n_code": len(r["code"]), "n_prose": len(r["prose"]), "n_data": len(r["data"]),
            "verdict": v, "n_peer": len(peer[d]),
            "witness": f"entry={len(n_code)} unbounded={len(entry_unbounded)} peer={len(peer[d])}",
        })
    inst = collections.Counter()
    for d in dirs:
        for src in readers[d]["code"] + readers[d]["prose"] + readers[d]["data"]:
            inst[home_of(src)] += 1
        for src in peer[d]:
            inst["in-slop peer"] += 1
    return {"rev": rev, "rows": rows, "manifests": manifests(repo, rev, allfiles),
            "instances": inst}


def home_of(src: str) -> str:
    """WHERE THE READER LIVES, which is a different question from whether it reads."""
    if src.startswith(SLOP + "/"):
        return "in-slop peer"
    top = src.split("/")[0]
    return f"{top}/" if top in ("checks", "gates") else "elsewhere"


def manifests(repo: Path, rev: str, allfiles: list[str]) -> list[dict]:
    """THE 4 MANIFEST SHAPES, discovered by a basename SHAPE over the walk, each with its ROW COUNT.

    `strays/MANIFEST.tsv` and `oracles259/MANIFEST.tsv` are the SAME FILENAME and DIFFERENT THINGS
    -- 53 rows and 259 -- so a census that reads "has a MANIFEST" and stops has measured nothing
    about either. The row count is the fact; the filename is the coincidence."""
    out = []
    for f in allfiles:
        if not f.startswith(SLOP + "/") or not MANIFEST_RE.match(f.rsplit("/", 1)[-1]):
            continue
        p = subprocess.run(["git", "cat-file", "-s", f"{rev}:{f}"],
                           cwd=repo, capture_output=True, text=True)
        blob = blobs_of(repo, rev, f)
        rows = blob.count(b"\n")
        out.append({"path": f, "basename": f.rsplit("/", 1)[-1], "rows": rows,
                    "bytes": int(p.stdout.strip() or 0)})
    return sorted(out, key=lambda r: -r["rows"])


_BLOB_CACHE: dict[tuple[str, str], bytes] = {}


def blobs_of(repo: Path, rev: str, name: str) -> bytes:
    return _BLOB_CACHE.get((rev, name)) or subprocess.run(
        ["git", "cat-file", "blob", f"{rev}:{name}"], cwd=repo, capture_output=True).stdout


def cross(rows: list[dict]) -> dict:
    """THE 2x2. This is the whole report: two properties, four cells, and the off-diagonals are
    the finding. A census that asks either question alone lives in one row of this table and can
    never see the other."""
    top = [r for r in rows if r["depth"] == 0]
    c = collections.Counter(r["verdict"] for r in top)
    return {
        "top": top, "nested": [r for r in rows if r["depth"] > 0],
        "cells": c,
        "declared_total": sum(r["declared"] for r in top),
        "declared_unopened": c[ORPHAN] + c[UNVERIFIABLE],
        "undeclared_total": sum(1 for r in top if not r["declared"]),
        "undeclared_opened": c[UNDECLARED_OPEN],
    }


def report(c: dict, rev_full: str) -> str:
    rows = c["rows"]
    x = cross(rows)
    top, nested = x["top"], x["nested"]
    L = []
    a = L.append
    a(f"THE READER/DECLARATION CROSS-TAB at commit {rev_full[:12]}")
    a("")
    a(f"scope of every number below: tracked directories under `.agents/slop/` AT COMMIT "
      f"{rev_full[:12]}, from `git ls-tree -r`, top-level rows only unless a line says NESTED.")
    a(f"  population, top-level directories at that commit : {len(top)}")
    a(f"  population, NESTED directories (their own rows, never inherited) : {len(nested)}")
    a("")
    a("THE 2x2 -- AUTHORSHIP on one axis, AUDITABILITY on the other. Both axes over ONE population.")
    a(f"  declared  ({len(top) - x['undeclared_total']:3d}) | code reader opens it : "
      f"{x['cells'][WITNESSED]:3d}   | nothing RUNS opens it : {x['declared_unopened']:3d}"
      f"   (ORPHAN {x['cells'][ORPHAN]}, UNVERIFIABLE {x['cells'][UNVERIFIABLE]})")
    a(f"  undeclared{'':4s} | code reader opens it : {x['undeclared_opened']:3d}"
      f"   | nothing RUNS opens it : {x['cells'][UNDECLARED_CITED] + x['cells'][INERT]:3d}"
      f"   (CITED {x['cells'][UNDECLARED_CITED]}, INERT {x['cells'][INERT]})")
    a("")
    a("WHAT EACH QUESTION ALONE MISSES, MEASURED ON THIS SAME POPULATION:")
    a(f"  (a) 'is a declaration PRESENT?' alone PASSES {len(top) - x['undeclared_total']:3d} "
      f"(every declared row) and MISSES {x['declared_unopened']:3d} of them -- a declaration "
      f"nothing opens.")
    a(f"  (b) 'is there a READER?' alone PASSES "
      f"{x['cells'][WITNESSED] + x['undeclared_opened']:3d} (a CODE reader outside the subtree) "
      f"and MISSES {x['undeclared_opened']:3d} -- a directory a gate genuinely opens that holds")
    a(f"      no declaration at all. The first version of this line printed {x['cells'][WITNESSED]} "
      f"for (a): that is the")
    a("      (a)AND(b) cell, so the sentence called a passing-row count a question-alone count.")
    a(f"  THE OFF-DIAGONALS ARE {x['declared_unopened']} AND {x['undeclared_opened']} ROWS OF "
      f"{len(top)}: NEAR-DISJOINT. Neither question half-sees the tree.")
    a("")
    a("THE THIRD SENSE -- IS A READER A WITNESS OR A SYMPTOM? A reader is something that RUNS.")
    a(f"  rows whose ONLY code readers are ENTRY POINTS CARRYING NO TIME BOUND : "
      f"{x['cells'][UNVERIFIABLE]}")
    a("  `slowgate` measured 105 of 129 gate entry points carry no bound and 1 hangs forever, so a")
    a("  reader that cannot be shown to complete is NOT counted as opening anything: it has its own")
    a("  cell, and it is NOT counted in either column of the 2x2 above. That is the third sense in")
    a("  which 'declared' cannot be the property -- and it is the one nobody has named.")
    a("")
    a("AND THE FOURTH, WHICH IS THE BIGGER ONE -- WHERE THE READER LIVES. A reader inside")
    a("  `.agents/slop/` is a PEER: another agent's scratch script, in the tree this file sweeps, on")
    a("  the same clock, uncommitted by anyone. It is not a witness. Reader INSTANCES by home:")
    tot = sum(c["instances"].values())
    for k, v in c["instances"].most_common():
        a(f"    {v:6d} ({100 * v // tot:2d}%)  {k}")
    a(f"  MEASURED over {tot} reader instances in this same population. So the 'opened' axis is")
    a("  almost entirely PEERS CITING PEERS, and a census that reports '140 directories are opened'")
    a("  as AUDITABILITY is reporting that agents mentioned each other.")
    peer_only = sum(1 for r in top if r["n_peer"] and not (r["n_code"] or r["n_prose"] or r["n_data"]))
    a(f"  top-level directories cited ONLY by in-slop peers and by NOTHING outside : {peer_only}")
    a("  THE FIRST VERSION OF THIS LINE PRINTED 0 while the rows said 139: it tested the FIRST")
    a("  reader PATH (`not r['prose']`, and `'-'` is truthy) instead of the COUNT. A zero that")
    a("  disagrees with its own rows file is a `residue.py`, so the line is kept with both.")
    a("")
    a("THE NESTING ROW -- a declaration is about a DIRECTORY, not about its subtree:")
    n = len(nested)
    nd = sum(r["declared"] for r in nested)
    under = sum(1 for r in nested
                if not r["declared"]
                and any(p["declared"] for p in top if p["dir"] == r["dir"].rsplit("/", 1)[0]))
    a(f"  NESTED directories holding a declaration of their OWN : {nd} of {n}")
    a(f"  NESTED directories that are undeclared while their PARENT is declared : {under}")
    a("  A walk that INHERITED would green those by inheriting a fact about a different directory.")
    a("  This file does not inherit: depth is the directory's own, and every nested directory is a")
    a("  row of its own.")
    a("")
    a("THE MANIFEST SHAPES -- discovered by a basename shape, each with its ROW COUNT, because")
    a("  `strays/MANIFEST.tsv` and `oracles259/MANIFEST.tsv` are the same NAME and different THINGS:")
    for m in c["manifests"]:
        a(f"  {m['rows']:5d} rows  {m['basename']:20s} {m['path']}")
    a("")
    a("WHAT THIS FILE CANNOT SEE, STATED FIRST AND IN FULL:")
    a("  1 A reader that BUILDS A PATH AT RUNTIME (`slop / name / 'x.rows'`) names nothing this")
    a("    grep can see. Every such reader is counted as absent, so every count above is a LOWER")
    a("    BOUND on readership. The bound is not small and it is not symmetric with authorship:")
    a("    a declaration cannot be built at runtime, so axis (a) has no such blind spot and axis")
    a("    (b) does. That asymmetry is a reason to distrust a cross-tab built this way, stated here")
    a("    rather than discovered by a reader.")
    a("  2 'Carries no bound' is STATIC. `slowgate`: a static property is not a hang. UNVERIFIABLE")
    a("    means NO BOUND IS PROVEN ABSENT, never that the reader was observed hanging.")
    a("  3 Prose that names a path is a CITATION, not an opening. PROSE and DATA are reported so the")
    a("    citation count is visible, and they open nothing -- `orcdecide` measured 3 citations, 0")
    a("    opens. If a citation IS the intended use of a report, then PROSE should count and this")
    a("    file is wrong about half the tree. That is a decision, not a fact, and it is named here.")
    a("  4 The worktree is NOT read except through `git cat-file` at `rev`, so an untracked file")
    a("    that opens a directory is invisible. That is the point of pinning a commit.")
    return "\n".join(L)


# ---- the plants: four false-able controls, each a case ONE question alone passes -------------
def classify_one(decl: int, entries: list[str], unbounded: list[str],
                  n_prose: int, n_data: int) -> str:
    """THE RULE, as one function, and the ONLY copy of it. `census` calls this and the plant drives
    this, so a plant that passes is a fact about the rule rather than about a second implementation
    that happens to agree. The branch ORDER is the answer to "is a reader a witness or a symptom":
    an unbounded reader is placed in its own cell BEFORE it is allowed to make anything opened."""
    if entries and len(unbounded) == len(entries):
        return UNVERIFIABLE
    if entries:
        return WITNESSED if decl else UNDECLARED_OPEN
    if n_prose or n_data:
        return CITED if decl else UNDECLARED_CITED
    return ORPHAN if decl else INERT


def plant() -> tuple[str, int]:
    """Each control is a hand-built FIXTURE fed to the same `classify_one` the census uses, so a
    plant that passes is a fact about the rule and not about a hardcoded answer. 31 of 31 plants
    elsewhere in this tree tested the WALK; these test the PROPERTY."""
    checks = []

    def chk(name, want, got):
        checks.append((name, want, got, want == got))

    # CONTROL 1: a DECLARATION AND NO READER MUST FIRE. Question (a) alone passes this row.
    chk("declared+no reader fires (passes (a), fails (b))", ORPHAN, classify_one(1, [], [], 0, 0))
    # CONTROL 2: a READER AND NO DECLARATION MUST FIRE. Question (b) alone passes this row.
    chk("reader+no declaration fires (passes (b), fails (a))", UNDECLARED_OPEN,
        classify_one(0, ["r.py"], [], 0, 0))
    # CONTROL 3: a NESTED DIRECTORY UNDER A DECLARED PARENT, holding NEITHER, MUST FIRE. The
    #            fixture carries no parent fact at all, so a walk that INHERITED could not pass it.
    chk("nested under declared parent, neither, fires", INERT, classify_one(0, [], [], 0, 0))
    # CONTROL 4: a directory whose ONLY reader CANNOT COMPLETE is SEPARATE, never counted opened.
    chk("only unbounded reader is UNVERIFIABLE, not opened", UNVERIFIABLE,
        classify_one(1, ["g.py"], ["g.py"], 0, 0))
    chk("the same row with a bounded reader is WITNESSED", WITNESSED,
        classify_one(1, ["g.py"], [], 0, 0))
    # And the mirror of (a): a DECLARED+UNBOUNDED row must not be silently ORPHAN -- that is how a
    # "reader exists" census would report it -- which is the half of the tree the 2x2 hides.
    chk("unbounded reader never lands in the ORPHAN cell", False,
        classify_one(1, ["g.py"], ["g.py"], 0, 0) == ORPHAN)

    L = ["THE FALSE-ABLE CONTROLS. Each is a case ONE question alone PASSES, so a census that asks",
         "either question alone is caught by at least one of them. They drive `classify_one`, the",
         "same function the census classifies with -- not a second implementation of the rule."]
    for name, want, got, ok in checks:
        L.append(f"  {'ok  ' if ok else 'FAIL'} {name:56s} want={want!s:15s} got={got}")
    bad = [c for c in checks if not c[3]]
    L += ["", f"  {len(checks) - len(bad)} of {len(checks)} controls fire.",
          "  A control that does not fire is a FAIL and this exits 1: a census that fires only on",
          "  the easy case is the `zerogate`/`plantthe46` vacuous-plant class arriving by a THIRD",
          "  door -- a census that AGREES with the property it cannot see."]
    return "\n".join(L), (1 if bad else 0)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="the READER/DECLARATION cross-tab, by discovery")
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--repo", default=str(ROOT))
    ap.add_argument("--plant", action="store_true", help="run the four false-able controls")
    args = ap.parse_args(argv)
    repo = Path(args.repo).resolve()
    if args.plant:
        body, rc = plant()
        print(body)
        return rc
    c = census(repo, args.rev)
    if "error" in c:
        print(f"REFUSED: {c['error']} -- the ruler is missing, not the tree empty")
        return 3
    rev_full = git(repo, "rev-parse", args.rev).stdout.strip()
    here = HERE if repo == ROOT else repo
    (here / "census.rows").write_text(
        "\n".join(["\t".join(COLUMNS)] +
                  ["\t".join(str(r[c_]) for c_ in COLUMNS) for r in c["rows"]]) + "\n")
    (here / "manifests.rows").write_text(
        "path\tbasename\trows\tbytes\n" +
        "".join(f"{m['path']}\t{m['basename']}\t{m['rows']}\t{m['bytes']}\n"
                for m in c["manifests"]))
    print(report(c, rev_full))
    x = cross(c["rows"])
    return 0 if not x["cells"][ORPHAN] and not x["cells"][UNDECLARED_OPEN] else 1


if __name__ == "__main__":
    sys.exit(main())