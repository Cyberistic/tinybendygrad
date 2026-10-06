#!/usr/bin/env python3
"""What is in `oracles/**.txt`, who still reads it, and what makes it a population.

    .venv/bin/python checks/oracle-txt-census.py
    .venv/bin/python checks/oracle-txt-census.py --gate

**THE POPULATION IS A GLOB, AND THAT IS THE FINDING.** `oracles/**.txt` is defined here by
`rglob("*.txt")` and by `checks/no-txt.py`'s walk, and by `checks/txt-owners.py`'s walk, and by
`checks/sweep.py`'s `ROLE_DIRS`. Four instruments, four independent ways of arriving at the same
set, and not one of them a list anybody maintains. **WHAT MAKES A FILE PART OF THIS POPULATION IS
NOTHING.** It is a directory name and an extension. That is why the inherited measurement could
report "named by nothing" for all 259 and be right about the citations while missing the reads:
a file becomes visible here by existing under a name that four unrelated tools glob for.

So this check answers the question the glob cannot, and it answers it by reading, not by name:

  SHAPE    what is inside, by three mechanisms that SHARE NO REGEX -- a hand-written predicate, a
           nearest-neighbour fit against the 35 `.rows` files the project already blessed, and a
           language test. A prior unit's `ORACLE_WORD.search(name)` classified 670 of 675 files by
           FILENAME; this one is told the answer must not depend on the filename, and the plant
           proves it by renaming a file and watching the group hold.

  REACH    for each file, whether anything READS it -- FOUR ways, because the project's own record
           is that a literal basename search is blind. LIVE, SHADOW, STALE and NOTHING, where
           STALE is a script naming the basename at a path that no longer exists while the file
           survives under `oracles/`. **`checks/sb-gate.sh` is a measured instance** and it is why
           this check exists: its inputs were moved to `oracles/schedule-bodies/` and it refuses
           with exit 3, while a basename search over the tree reports the name as cited.

  SELF-NAMING IS EXCLUDED, BECAUSE A CENSUS THAT READS ITS OWN EXAMPLES IS NOT A CENSUS. This
  file names `oracles/baseline.txt`, `oracles/BEFORE-rows.txt` and four others in its own prose and
  in its `RIGHT` table, so the first version counted THIS FILE as a reader of them: `LIVE` read 1
  on a population of 259 whose true answer is 0, and the plant wrote its own path into the tree and
  watched the verdict it was testing move. MEASURED, by the plant, which is the only reason it is
  known. A tool reporting on a population must be out of that population's citation graph, or its
  own examples become evidence.

usage: .venv/bin/python checks/oracle-txt-census.py [--gate]

  no flag   the census: shape groups, reach classes, and the stale-rooted reads. exit 0.
  --gate    exit 1 if any script reads a `.txt` whose basename is ALIVE under `oracles/` at a path
            that is not there -- a gate input that moved with no re-point. Answerable whatever the
            filesystem holds.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import pathlib
import re
import statistics
import subprocess
import sys

ROOT = pathlib.Path(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORACLES = ROOT / "oracles"
GATE_CODE = (".sh", ".py")
# SOURCE EXTENSIONS THE PROJECT ITSELF USES. A `.txt` holding any of these is a source file with
# the wrong suffix, which is a different defect from a row dump with the wrong suffix.
TRUTHFUL = {".rows": "expected values", ".out": "captured stdout", ".err": "captured stderr",
            ".tsv": "tabular", ".md": "prose", ".json": "a json value", ".names": "a name list",
            ".bend": "bend source", ".py": "python source", ".sh": "shell source"}

# ---------------------------------------------------------------- M1: hand-written shape test
KV = re.compile(r"^[A-Za-z_][A-Za-z0-9_.]*=")


def m1_kv(lines: list[str]) -> float:
    """Fraction of live lines that are a whole `name=value` row. THE SHAPE sb-gate.sh measures."""
    live = [ln for ln in lines if ln.strip()]
    return sum(bool(KV.match(ln)) for ln in live) / len(live) if live else 0.0


# ------------------------------------------------- M2: nearest-neighbour fit to the .rows corpus
def features(lines: list[str]) -> tuple[float, float, float]:
    """(token-per-line regularity, blank fraction, kv fraction). Three numbers, no pattern."""
    live = [ln for ln in lines if ln.strip()]
    if not live:
        return (0.0, 1.0, 0.0)
    widths = [len(ln.split()) for ln in live]
    med = statistics.median(widths)
    # 1 - coefficient of variation: a row dump's lines are all the same width, prose is not.
    reg = 1.0 - (statistics.pstdev(widths) / med if med else 1.0)
    return (max(0.0, reg), 1.0 - len(live) / len(lines), m1_kv(lines))


def l1(a, b) -> float:
    return sum(abs(x - y) for x, y in zip(a, b))


def m2_threshold(blessed: list[tuple[float, float, float]]) -> float:
    """The WORST nearest-neighbour distance INSIDE the blessed corpus. No threshold is invented."""
    if len(blessed) < 2:
        return 0.0
    return max(l1(blessed[i], blessed[j]) for i in range(len(blessed)) for j in range(i + 1, len(blessed)))


# ------------------------------------------------- M3: language test, and nothing about rows
# A CRASH DUMP IS NOT A ROW DUMP AND ITS EXTENSION IS NOT A MATTER OF TASTE. Python prints the
# banner, and a file holding one is a captured stderr stream whatever else it contains -- four
# files here are oracle runs that DIED, and reading them as data is reading a stack trace as a
# table. Measured, and the reason `ext_oracle_{0,1,2,4}.txt` are a class of their own.
TRACEBACK = "Traceback (most recent call last)"
# A COLUMN-0 line is the only thing that separates a row dump with wrapped continuations from a
# program with an indented body: in the dump the key is at column 0 and the continuation is not.
# `#` IS DELIBERATELY NOT IN THIS PATTERN. It was, and it classified `oracles/baseline.txt` and
# `oracles/cshape/rows-run0.txt` as source when both are PROSE WITH `#` HEADINGS -- and `sb-gate.sh`
# reads a `BEFORE-rows.txt` of the same kind as its regression floor, so calling that class source
# would have proposed `.bend` for a document. A comment marker is the weakest possible evidence of
# a language: every prose file in this project is allowed to have headings.
STRUCTURAL = re.compile(r"^(?:def |class |import |from \S+ import |@\w|M\d+\s|BL\d+\s)")
ARROW_TAIL = re.compile(r"(?:->|\)\s*:\s*|\]\s*:\s*)\s*$")


def m3_language(path: pathlib.Path, text: str) -> str | None:
    """`json`, `crash-dump`, `source`, or None -- content only, never the filename.

    **STRUCTURE BEFORE MIME, AND THE ORDER IS THE FINDING.** `file --mime-type` called
    `oracles/usb-arith-rows.bend.txt` `text/x-script.python`, so a mime-first classifier files
    424 lines of BEND under a python-shaped label and proposes `.py` for it. `file` infers a
    language from surface syntax and cannot tell bend from python from shell; this project's own
    source is three languages that look alike. So the structural test runs FIRST and mime is only
    consulted for a shebang, which is an unambiguous marker and not a guess.
    """
    lines = text.splitlines()
    try:
        json.loads(text)
        return "json"
    except Exception:
        pass
    if TRACEBACK in text:
        return "crash-dump"
    # STRUCTURAL COLUMN-0 LINES, not "is anything indented". `fold-mvt-oracle.py.txt` is a row dump
    # whose `mv_expsym` value wraps onto an indented second line, and an indentation test called it
    # source; the wrap is invisible at column 0 and that is the whole point. Two independent
    # signals, because one is not enough: a `def`/`class`/`import` keyword, or a SIGNATURE TAIL --
    # a line that ends in `-> ...` or `):`, which is what a function header ends in and what a row
    # dump never does. `ag-emit-oracle.txt` holds `E emit.def def addfn(a:int, b:int) -> int: ...`
    # and only the tail finds it.
    col0 = [ln for ln in lines if ln.strip() and not ln[0].isspace()]
    if col0:
        sig = sum(bool(STRUCTURAL.match(ln)) or bool(ARROW_TAIL.search(ln)) for ln in col0)
        if sig / len(col0) >= 0.25:
            return "source"
    # A shebang is the one marker that is a DECLARATION rather than an inference.
    if lines and lines[0].startswith("#!"):
        return "script"
    return None


def shape(path: pathlib.Path, thr: float) -> str:
    text = path.read_text(errors="replace")
    lang = m3_language(path, text)
    if lang:
        return f"{lang}-in-txt"
    f = features(text.splitlines())
    return "rowdump" if (m1_kv(text.splitlines()) >= 0.9
                         or l1(f, _BLESSED_MEDIAN) <= thr) else "prose-in-txt"


def _blessed_median() -> tuple[float, float, float]:
    return _BLESSED_MEDIAN


# ------------------------------------------------------------------ REACH: who reads a `.txt`
ASSIGN = re.compile(r"^\s*(?:export\s+|declare\s+-\w+\s+|let\s+|const\s+)?"
                    r"([A-Za-z_][A-Za-z0-9_]*)=[\"']?([^\"'\n]*)[\"']?\s*$", re.M)
NOT_A_PATH = re.compile(r"[`()\"'$]")
VAR = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")
LEAD_VAR = re.compile(r"^\$?\{?[A-Za-z_][A-Za-z0-9_]*\}?/")
# A `.txt` TOKEN, wherever it appears -- an argument, a redirect, a comparison. The class is the
# token, not the construct: a construct-shaped reader misses `diff $A $B` and finds `> $X` instead.
TXT_TOKEN = re.compile(r"[A-Za-z0-9_./${}-]*\.txt\b")


def unbind(tok: str, binds: dict[str, str]) -> str:
    for _ in range(6):
        if "$" not in tok:
            break
        new = VAR.sub(lambda m: binds.get(m.group(1), m.group(0)), tok)
        if new == tok:
            break
        tok = new
    return tok


def code_files() -> list[pathlib.Path]:
    """Tracked `.sh`/`.py`, MINUS THIS FILE AND THIS CHECK'S OWN PLANTS.

    The exclusions are the finding, not hygiene. A census that names `oracles/baseline.txt` in its
    own `RIGHT` table is a reader of that file by the token test, so the first version reported
    `LIVE 1/259` on a population where the true answer is 0 -- its own example, counted as
    evidence. `.agents/slop/oracles259/plants.py` names the same paths in its plant fixtures, and
    while the plants ran, the tree the census described was the tree the plants had written. **A
    PLANT THAT WRITES INTO THE POPULATION UNDER TEST IS A PLANT THAT MOVES THE ANSWER IT IS
    MEASURING**, so the plants live outside `oracles/` and are excluded from the reader set.
    """
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    me = os.path.relpath(os.path.abspath(__file__), ROOT)
    skip = (me, ".agents/slop/oracles259/plants.py")
    return [ROOT / r for r in out
            if pathlib.Path(r).suffix in GATE_CODE
            and not r.startswith(("references/", "tinygrad/"))
            and r not in skip]


def readers() -> dict[str, list[tuple[str, str, str, bool]]]:
    """basename -> [(reader, token, resolved, resolved_exists)] for every `.txt` token every
    tracked script MENTIONS.

    Mention, not write: a `diff a b` is a read, `> out` is a write, and only the first answers
    "is this file alive". The `resolved_exists` column is the whole finding, and dropping it is
    what makes a stale-rooted read look like a live one: `checks/sb-gate.sh` mentions
    `BEFORE-rows.txt`, joins `oracles/BEFORE-rows.txt` by basename, and the path it actually
    opens is `.agents/slop/schedule-bodies/BEFORE-rows.txt`, which is ABSENT. **A basename join
    cannot tell a gate that reads this file from a gate that lost it.**
    """
    hit: dict[str, list[tuple[str, str, str, bool]]] = collections.defaultdict(list)
    for rel in code_files():
        try:
            body = rel.read_text(errors="replace")
        except OSError:
            continue
        binds = {m.group(1): m.group(2) for m in ASSIGN.finditer(body)
                 if not NOT_A_PATH.search(m.group(2))}
        for m in TXT_TOKEN.finditer(body):
            raw = m.group(0)
            resolved = unbind(raw, binds)
            if "$" in resolved:
                continue          # a name this static pass cannot build; reported by --gate's census
            lead = LEAD_VAR.match(resolved)
            cands = [resolved] if lead is None else [resolved[lead.end():], resolved]
            # A BARE name is relative to the SCRIPT, not to the repo root, and resolving it against
            # ROOT credits `.agents/slop/fp8fix/gate.py` with opening `oracle.txt` at the top of the
            # repo -- a file that does not exist -- when the gate plainly means its OWN directory.
            # MEASURED: that misattribution is the difference between a row that reads
            # `.agents/slop/fp8fix/oracle.txt` and a row that reads nothing. The script's own
            # directory is tried FIRST for a bare token, and the hit is only recorded when the
            # resolved path's directory exists, so a name that matches no directory at all is
            # dropped rather than resolved against a guess.
            here = rel.parent
            ordered = ([os.path.relpath(here / resolved, ROOT)] if lead is None else []) + cands
            for c in ordered:
                if os.path.isdir(os.path.dirname(os.path.join(ROOT, c))):
                    hit[pathlib.Path(c).name].append(
                        (str(rel.relative_to(ROOT)), raw, c,
                         os.path.exists(os.path.join(ROOT, c))))
                    break
    return {k: v for k, v in hit.items()}


def sha(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for c in iter(lambda: fh.read(1 << 16), b""):
            h.update(c)
    return h.hexdigest()


_BLESSED_MEDIAN = (0.0, 0.0, 0.0)


def census() -> list[dict]:
    global _BLESSED_MEDIAN
    blessed = [features(p.read_text(errors="replace").splitlines())
               for p in sorted(ORACLES.rglob("*.rows")) if p.is_file()]
    thr = m2_threshold(blessed)
    if blessed:
        _BLESSED_MEDIAN = tuple(statistics.median(c) for c in zip(*blessed))
    read = readers()

    # ONE SHA PER FILE, AND THE CACHE KEY IS THE POINT. The first version keyed a digest cache on
    # `(st_size, int(st_mtime))` to make a 200-file duplicate group cost one hash, and **18 files
    # were handed another file's digest**: commit 2f4ffc7a0 moved 131 files in one commit, so they
    # share a size AND an mtime to the second, and `(size, mtime)` is not a unique key for content.
    # It surfaced as the manifest's restore proving 241/259 -- the restores were right and the
    # DIGESTS were wrong, which is the more dangerous direction, because a wrong digest makes a
    # correct restore look broken. `(path, size, mtime)` is unique per file, and a collision now
    # costs a hash rather than a false identity.
    digests: dict[str, str] = {}

    def digest(p: pathlib.Path) -> str:
        st = p.stat()
        k = f"{p}:{st.st_size}:{int(st.st_mtime)}"
        if k not in digests:
            digests[k] = sha(p)
        return digests[k]

    rows = []
    for p in sorted(ORACLES.rglob("*.txt")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(ROOT))
        mention = read.get(p.name, [])
        # REACH has THREE values, and collapsing any two of them is the mistake this file exists
        # next to. `live`     the reader opens THIS path -- the file is load-bearing today.
        #                   `stale`  the reader opens a path that is ABSENT and this file is the
        #                   basename it wanted -- a gate input that MOVED, invisible to a literal
        #                   search and to a write-path attribution alike.
        #                   `none`   nothing names it.
        # REACH IS ABOUT THE BYTES THE READER SEES, NOT ABOUT PATH STRINGS. MEASURED BY PLANT 2,
        # beat 3: writing this file's own bytes at the reader's path classified `shadow`, because
        # the test compared the two PATH strings and the paths differ -- and a reader holding the
        # identical bytes is the most alive state there is. So the comparison is by digest.
        #   live    the reader opens a path whose bytes ARE these bytes -- this path, or a copy.
        #   shadow  the reader opens a path that EXISTS and holds DIFFERENT bytes under this
        #           basename. Not this file and not a dead read: a namesake.
        #   stale   the reader's path is ABSENT and this file is the basename it wanted. The gate
        #           is broken, not the file -- and this is the real state of all 33 rows below.
        live, shadow, stale = [], [], []
        for reader, _, tok, ex in mention:
            if ex:
                other = os.path.join(ROOT, tok)
                same_bytes = os.path.isfile(other) and sha(pathlib.Path(other)) == digest(p)
                (live if same_bytes else shadow).append((reader, tok))
            else:
                stale.append((reader, tok))
        rows.append(dict(path=rel, bytes=p.stat().st_size, shape=shape(p, thr),
                         sha=digest(p),
                         live=sorted({r for r, _ in live}),
                         live_at=sorted({c for _, c in live}),
                         shadow=[list(s) for s in sorted(set(shadow))],
                         stale=[list(s) for s in sorted(set(stale))]))
    return rows, thr


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", action="store_true")
    args = ap.parse_args()

    rows, thr = census()
    by_shape = collections.defaultdict(list)
    for r in rows:
        by_shape[r["shape"]].append(r)
    # THE TRUTHFUL EXTENSION, PER GROUP, AND THE GENERATOR THAT WOULD HAVE TO BE FIXED. A group
    # with no correct extension is not a group, it is a leftover, and saying which is the whole
    # point of reading the files instead of globbing them.
    RIGHT = {
        "rowdump": (".rows", "the writer that redirected into a `.txt` name"),
        "crash-dump-in-txt": (".err", "the oracle run that DIED; it wrote stderr to a `.txt`"),
        "source-in-txt": (".bend/.py", "whatever emitted source into a `.txt` name"),
        "prose-in-txt": (".md", "the report writer; this is prose and `.txt` says nothing"),
        "json-in-txt": (".json", "the writer that serialized to a `.txt` name"),
        "script-in-txt": (".sh/.py", "the writer that captured a script into a `.txt` name"),
    }

    if args.gate:
        # A gate input that MOVED: named at a path that is absent, alive under oracles/.
        live = {r["sha"] for r in rows}
        stale = []
        for rel in code_files():
            body = rel.read_text(errors="replace")
            binds = {m.group(1): m.group(2) for m in ASSIGN.finditer(body)
                     if not NOT_A_PATH.search(m.group(2))}
            for m in TXT_TOKEN.finditer(body):
                tok = unbind(m.group(0), binds)
                if "$" in tok or not tok.endswith(".txt"):
                    continue
                if os.path.exists(os.path.join(ROOT, tok)):
                    continue
                for cand in ORACLES.rglob(pathlib.Path(tok).name):
                    if cand.is_file() and sha(cand) in live:
                        stale.append((str(rel.relative_to(ROOT)), tok,
                                      str(cand.relative_to(ROOT))))
                        break
        stale = sorted(set(stale))
        if not stale:
            print("  GATE  no tracked script reads a `.txt` that is alive only under oracles/.")
            return 0
        print(f"  GATE  {len(stale)} STALE-ROOTED READ(S): a script reads a path that is gone, and "
              f"the file survives under oracles/. Each is a gate input that moved with no re-point:")
        for reader, tok, cand in stale:
            print(f"    {reader}  reads  {tok}")
            print(f"        alive at  {cand}")
        return 1

    print(f"  {len(rows)} `.txt` under oracles/, grouped by WHAT IS INSIDE. "
          f"m2 threshold (worst in-corpus NN distance) = {thr:.4f}\n")
    for g, sel in sorted(by_shape.items(), key=lambda kv: -len(kv[1])):
        tot = sum(r["bytes"] for r in sel)
        ext, gen = RIGHT.get(g, ("?", "?"))
        print(f"\n  {len(sel):4d} files {tot:>10,d} B   {g}")
        print(f"        correct extension: {ext:12s} generator to fix: {gen}")
        for r in sorted(sel, key=lambda x: x["path"])[:5]:
            print(f"          {r['path']}  ({r['bytes']}B)")
        if len(sel) > 5:
            print(f"          ... and {len(sel) - 5} more")

    live = [r for r in rows if r["live"]]
    shadow = [r for r in rows if r["shadow"] and not r["live"]]
    stale = [r for r in rows if r["stale"] and not r["live"] and not r["shadow"]]
    print("\n  REACH. FOUR values, not two -- and the third one was found by a plant.\n")
    print(f"  LIVE       {len(live):3d} / {len(rows)}   a tracked script opens a path holding "
          f"THESE BYTES.")
    for r in sorted(live, key=lambda x: x["path"]):
        print(f"      {r['path']:52s} <- {', '.join(r['live'])}  at {', '.join(r['live_at'])}")
    print(f"\n  SHADOW     {len(shadow):3d} / {len(rows)}   a tracked script opens a DIFFERENT file "
          f"that has\n                         this basename and EXISTS. Not this file, not a dead "
          f"read: a namesake.")
    for r in sorted(shadow, key=lambda x: x["path"]):
        for reader, tok in r["shadow"]:
            print(f"      {r['path']}")
            print(f"          {reader}  opens  {tok}   [EXISTS, DIFFERENT FILE]")
    print(f"\n  STALE      {len(stale):3d} / {len(rows)}   a tracked script opens a path that is "
          f"ABSENT;\n                         this file is the basename it named. The gate is broken, "
          f"not the file.")
    for r in sorted(stale, key=lambda x: x["path"]):
        print(f"      {r['path']}")
        for reader, tok in r["stale"]:
            print(f"          {reader}  opens  {tok}   [ABSENT]")
    print(f"\n  NAMED BY NOTHING  "
          f"{len(rows) - len(live) - len(shadow) - len(stale):3d} / {len(rows)}")

    pathlib.Path(ROOT / ".agents/slop/oracles259/census.json").write_text(json.dumps(rows, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
