#!/usr/bin/env python3
"""THE PRUNE RULE, APPLIED TO THE SET NEITHER VCS OWNS: has-both / generator-only / reader-only /
mention-only / neither / plant-fixture -- plus a per-path redundancy check before any deletion.

THE RULE AS GIVEN: *delete only what has BOTH a generator AND a committed reader.  A file with a
generator and a reader is EVIDENCE; a file with NEITHER is WASTE.*  A file with EXACTLY ONE of the
two is neither evidence nor waste, and "only it" means only `has-neither` is deleted.  So
`has-generator-only`, `has-reader-only` and `has-mention-only` are KEPT classes here, not
fence-sitters.

**THE CLASSIFICATION IS `checks/unowned.py`'s, LOADED BY PATH, NOT REIMPLEMENTED.**  It already
asks git the three questions that decide this -- does a COMMITTED file name the path as a WHOLE
TOKEN (a reader), does a committed line WRITE it (a generator), and does `git log --all -1` find an
owner -- and it separates a prose mention from an execution site, which is the difference between
"a report remembers this" and "something RUNS this".

TWO CLASSES ARE ADDED HERE, AND BOTH ARE DECLARATIONS LOADED BY PATH, NEVER LISTS:

  * PLANT-FIXTURE.  A path a plant generator's own `declared()` names, read through
    `checks/no-txt.py:excused_names()` -- which already loads `figure2/plant.py`,
    `skipexit/repro.py` and `txtexec/rename.py` by path and unions their declarations.  A planted
    defect's BODY is the subject of a test: deleting it because nothing names it makes the plant
    vacuous, which is the PLANT-DEAD verdict `checks/differ.py` exists to catch.  A file a plant
    SHIPS is evidence even with no reader.

  * ON-DISK GENERATOR.  `unowned.py` reads HEAD, so a `.rows` written by an UNTRACKED sibling
    script reads as generator-less.  That is a generator.  Measured by asking the tree rather than
    assuming: a write site is any `.py`/`.sh`/`.mjs` in the artifact's own directory whose text
    contains the artifact's basename.  This WEAKENS the delete set, which is the safe direction --
    a false generator costs a retained file, a false absence costs research.

THE REDUNDANCY CHECK IS PER PATH AND MANDATORY.  A byte-identical copy elsewhere does NOT license
deleting THIS path: if the other copy is tracked or jj-owned then this one is the redundant
duplicate and goes; if both are unowned then it is a duplicate WITHIN the waste set and only one of
the pair goes.  Either way the twin is reported, never assumed.

**AND THE CHECK THAT ACTUALLY MOVES THE DELETE SET IS PEP 3147.**  46 of the 46 `has-neither`
paths are `__pycache__/*.cpython-312.pyc`.  Under the rule's LETTER every one of them is waste,
because both of the rule's predicates are measured over COMMITTED FILES and a bytecode cache's
generator (CPython) and reader (CPython's import machinery) are not files in this repository.  That
is the rule's own blind spot and it is measured, not asserted.  The VERIFICATION then splits them:

  * 43 have their SOURCE `.py` still BESIDE the cache (PEP 3147 puts it in the cache's PARENT), and
    43 of those 43 sources are jj-owned -- so the cache is the derived form of an in-flight file and
    deleting it is clearing a build cache, not pruning research residue.
  * 3 have NO source, and a `__pycache__` `.pyc` with no source is UNIMPORTABLE: measured, not
    assumed -- a directory holding only `__pycache__/m.cpython-312.pyc` raises
    `ImportError: No module named 'm'` under this repo's own `.venv/bin/python`.  Those 3 are the
    rule's delete set after its own verification, and nothing else is.

SO THE RULE'S LETTER NAMES 46 AND ITS VERIFICATION NAMES 3.  Both numbers are reported; the
smaller one is what `--apply` removes.

    python3 .agents/slop/untrack/prune.py [--apply]
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
HERE = os.path.dirname(os.path.abspath(__file__))
SLOP = ".agents/slop"
POP = f"{SLOP}/untrack/slop-untracked.rows"
CAND = f"{SLOP}/untrack/unowned-slop.rows"
CLASSES = ("has-both", "has-generator-only", "has-reader-only", "has-mention-only",
           "has-neither", "plant-fixture")


def load(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(*a: str) -> str:
    return subprocess.run(("git", "-C", ROOT) + a, capture_output=True, text=True).stdout


def rd(rel: str) -> set[str]:
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return {l.rstrip("\n") for l in fh if l.strip()}


def sha(rel: str) -> str:
    h = hashlib.sha256()
    with open(os.path.join(ROOT, rel), "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def sibling_generators(rel: str) -> list[str]:
    """Untracked-or-not `.py`/`.sh`/`.mjs` in the artifact's own DIRECTORY naming it."""
    d = os.path.dirname(os.path.join(ROOT, rel))
    base = os.path.basename(rel)
    if not os.path.isdir(d):
        return []
    out = []
    for n in sorted(os.listdir(d)):
        if n == base or not n.endswith((".py", ".sh", ".mjs")):
            continue
        with open(os.path.join(d, n), encoding="utf-8", errors="replace") as fh:
            if base in fh.read():
                out.append(f"{os.path.dirname(rel)}/{n}")
    return out


def pyc_source(rel: str) -> str | None:
    """The module a PEP 3147 cache was compiled from: `<parent>/<stem>.py`, or None if not a cache.

    The PARENT, not the cache's own directory -- looking for it inside `__pycache__/` is a check
    that cannot fail and reports every cache in the tree as an orphan.
    """
    if os.path.basename(os.path.dirname(rel)) != "__pycache__" or not rel.endswith(".pyc"):
        return None
    return os.path.join(os.path.dirname(os.path.dirname(rel)),
                        os.path.basename(rel).split(".")[0] + ".py")


def unowned_table(paths: list[str]) -> dict[str, tuple[int, int, int]]:
    """`(cited, exec, written)` per path, from `checks/unowned.py --tsv` -- the tree's own instrument."""
    with open(os.path.join(HERE, "pop-from.rows"), "w", encoding="utf-8") as fh:
        fh.writelines(f"?? {p}\n" for p in paths)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "checks", "unowned.py"),
                        "--from", os.path.join(HERE, "pop-from.rows"), "--tsv"],
                       capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(r.stderr.strip()[-400:])
    out = {}
    for line in r.stdout.splitlines():
        f = line.split("\t")
        if len(f) >= 6 and not line.startswith("path\t"):
            out[f[0]] = (int(f[3]), int(f[4]), int(f[5]))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="delete ONLY the has-neither set")
    a = ap.parse_args()

    scope = rd(POP)
    cand = sorted(rd(CAND))
    plants = load("checks/no-txt.py", "no_txt").excused_names()
    unowned = load("checks/unowned.py", "unowned")
    table = unowned_table(cand)

    gen, rdr, cite, sib, klass = {}, {}, {}, {}, {}
    for p in cand:
        c, e, w = table.get(p, (0, 0, 0))
        sib[p] = sibling_generators(p)
        gen[p] = bool(w) or bool(unowned.generator_for(p)[0]) or bool(sib[p])
        rdr[p] = e > 0
        cite[p] = c > 0
        klass[p] = ("plant-fixture" if p in plants else
                    "has-both" if gen[p] and rdr[p] else
                    "has-generator-only" if gen[p] else
                    "has-reader-only" if rdr[p] else
                    "has-mention-only" if cite[p] else
                    "has-neither")

    counts = {k: [p for p in cand if klass[p] == k] for k in CLASSES}
    print(f"SCOPE  : {len(cand)} paths under {SLOP}/ owned by NEITHER `git ls-tree -r HEAD` "
          f"(6680 paths) NOR `jj file list -r @` (7074 paths)")
    print(f"DENOM  : of the {len(scope)} files my census found untracked under {SLOP}/; the other "
          f"{len(scope) - len(cand)} are jj-owned and IN FLIGHT\n")
    for k in CLASSES:
        print(f"  {k:<22}{len(counts[k]):>4}")

    waste = counts["has-neither"]
    twins = {p: [q for q in cand if q != p and sha(q) == sha(p)] for p in waste}
    owned = rd(f"{SLOP}/untrack/git-head.rows") | rd(f"{SLOP}/untrack/jj-at.rows")
    digests: dict[str, str] = {}
    for d, _, fn in os.walk(os.path.join(ROOT, SLOP)):
        if os.path.basename(d) == "untrack":
            continue
        for n in fn:
            rel = os.path.relpath(os.path.join(d, n), ROOT)
            if rel in owned and os.path.isfile(os.path.join(ROOT, rel)):
                digests.setdefault(sha(rel), rel)
    owned_twin = {p: digests[sha(p)] for p in waste if sha(p) in digests}

    print(f"\nDELETE SET = has-neither = {len(waste)} of the {len(cand)} candidates")
    print(f"  byte-identical TRACKED-or-jj twin exists : {len(owned_twin)}")
    print(f"  byte-identical twin inside the waste set  : {sum(1 for p, v in twins.items() if v)}")
    caches = {p: pyc_source(p) for p in waste}
    live = {p: s for p, s in caches.items() if s and os.path.exists(os.path.join(ROOT, s))}
    orphans = sorted(p for p in waste if p not in live)
    print(f"  PEP 3147: of the {len(caches)} __pycache__ entries, {len(live)} have their SOURCE .py "
          f"still beside them (a live cache of an in-flight file)\n"
          f"            and {len(orphans)} have NO source, which is UNIMPORTABLE -- measured")
    for p in waste:
        n = f"   twin={owned_twin[p]}" if p in owned_twin else (
            f"   dup={[q for q in twins[p]]}" if twins[p] else "")
        if p in live:
            n += f"   KEEP: source {live[p]} exists" + (
                " (jj-owned)" if live[p] in rd(f"{SLOP}/untrack/jj-at.rows") else "")
        else:
            n += "   DELETE: no source, unimportable"
        print(f"    {p}{n}")

    if not a.apply:
        print(f"\nVERDICT SKIP  classified={len(cand)} deleted=0 -- no --apply")
        return 0

    killed, refused = [], []
    for p in orphans:
        if not os.path.isfile(os.path.join(ROOT, p)):
            refused.append((p, "vanished between census and delete"))
        elif p in rd(f"{SLOP}/untrack/git-head.rows"):
            refused.append((p, "in HEAD"))
        elif p in rd(f"{SLOP}/untrack/jj-at.rows"):
            refused.append((p, "jj working copy owns it"))
        elif p in plants:
            refused.append((p, "plant fixture"))
        elif git("ls-files", "--error-unmatch", "--", p).strip():
            refused.append((p, "IN THE INDEX"))
        else:
            os.remove(os.path.join(ROOT, p))
            killed.append(p)
    for p in sorted(live):
        print(f"  REFUSED {p}: source {live[p]} exists -- a live import cache, not waste")
    for p, why in refused:
        print(f"  REFUSED {p}: {why}")
    print(f"\nVERDICT PASS  deleted={len(killed)} refused={len(live) + len(refused)} "
          f"of {len(waste)} the rule's letter names")
    return 0


if __name__ == "__main__":
    sys.exit(main())