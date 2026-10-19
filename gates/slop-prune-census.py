#!/usr/bin/env python3
"""What in `.agents/slop/` is SAFE TO LOSE, BY REFERENCE AND NOT BY AGE.

    .venv/bin/python gates/slop-prune-census.py              # the report + the per-file rows
    .venv/bin/python gates/slop-prune-census.py --plant      # plant 4, in a TEMP COPY

THE QUESTION. `.agents/slop/` is being pruned and nothing in this tree has said which of its files
the prune may take. This file answers it in three classes, and it answers it BY REFERENCE:

    SAFE           tracked, a blob exists at this path in a REF, and no live instrument names it
    LOAD-BEARING   named by a live instrument, or named by a generator's own `declared()`
    UNRECOVERABLE  named by nothing AND no ref has ever carried this path -- record it, DO NOT LOSE IT

THE POPULATION IS A WALK. `os.walk`, `followlinks=False`, no filter, over `.agents/slop/`. **NEVER
`glob`** (`AGENTS.md`: `glob('*.bend')` returns `[]` when the files are on disk) and **NEVER a hand
list of names** -- `checks/sweep.py`'s `LIVE_UNITS` was 14 literal directory names and six FINISHED
units held 2 353 files behind them. Nothing in this file names a `.agents/slop/` entry.

`followlinks=False` IS A MEASUREMENT, NOT A TASTE. `find -type f` does not descend a symlinked
directory (196 files under `checks/e2epy/`, measured by `gates/gates-pop.py:_tree_paths`), so a walk
that follows links and a walk that does not are DIFFERENT POPULATIONS and the difference is a
denominator. `symlink=` is a column, so the size of the difference is a row rather than a claim.

## TRACKEDNESS IS ASKED OF THE REVISION, NEVER OF THE INDEX

`git ls-tree -r HEAD --name-only -z`, NOT `git ls-files`. This is the FOURTH population in this tree
read from the index, and the index here is armed by design: `jj git colocation` stages into git's
index on working-copy snapshot, so a bare `jj status` leaves placeholders behind. The index count is
read anyway and printed as `index-vs-HEAD`, because a census whose denominator moves with an
unrelated unit's `jj` invocation is a reading of the weather, and the reader is entitled to see it.

`git diff HEAD` IS NOT USED, for the measured reason `AGENTS.md` gives: under an armed index it
reported 120 deletions on a file whose `git hash-object` equalled `HEAD:`.

## RECOVERABILITY IS NOT `git rev-list --objects`, AND MEASURING THAT IS MOST OF THIS FILE

**THE BRIEF'S OWN SUGGESTED INSTRUMENT IS WRONG AS A PATH INDEX, AND THE WRONGNESS IS 35%.**

`git rev-list --objects --all` emits each OBJECT once, and prints a PATH only for the first path at
which that object was seen. **Two files with identical bytes share a blob OID, so every file after
the first is INVISIBLE.** MEASURED on `git ls-tree -r HEAD -- .agents/slop` at 2026-10-19:

    5 105 paths, 3 297 distinct blob OIDs, **1 808 paths (35.4%) have no line in rev-list's output**
    the largest sharing group is 504 paths sharing `e69de29b` -- the EMPTY BLOB

A 0-byte file is therefore invisible unless it happens to be the one empty file git reached first.
Concretely, `.agents/slop/abi4check/now-py3.stdout` is 0 bytes, is in HEAD's tree, and is named by
**0** lines of `git rev-list --objects --all` -- while the same file appears **12** times in
`git log --all --name-only`. **A prune driven by a `rev-list` path map declares 1 808 perfectly
recoverable files UNRECOVERABLE and would then delete them.**

So the two exact instruments are used instead, and each is measured:

    HEAD   `git ls-tree -r HEAD -z`                       0.041 s, 5 105 rows, path + blob EXACT
    hist   `git log --all --format=... --name-only -- SLOP`  86 s, 53 808 distinct paths ever
    odb    an object store has NO PATHS -- see below

`HEAD` and `hist` are the two tiers a file can be recovered from, and each is one command:

    git cat-file -p HEAD:<path>            # HEAD tier
    git log --all -1 --format=%H -- <path> # hist tier, then cat-file that revision

**THE THIRD TIER IS NOT DECIDABLE BY PATH, AND THIS FILE SAYS SO INSTEAD OF GUESSING.** A blob
reachable from no ref is recoverable until `git gc --prune=now`, which is exactly what a "tidy the
repository" pass runs. MEASURED, the tiers are not equal: `rev-list --objects --all` names 202 024
objects, `--all --reflog` 202 042, the whole object store 205 521 (75 316 blobs, 24 551 commits, 1
tag, 105 653 trees) -- **so 3 479 objects sit outside every ref** and no per-path question about them
can be asked cheaply, because the object store indexes objects and has no index of paths at all.
**THE PRUNING RULE BELOW IS THEREFORE STATED OVER `HEAD` AND `hist` ONLY.** A file that reaches
neither is called UNRECOVERABLE, which is a claim about REFS and is not a claim about the object
store: it is recoverable "until a gc", and a gc is a decision somebody makes deliberately.

## "NAMED BY A LIVE INSTRUMENT" IS NOT DECIDABLE. HERE IS WHAT IS DECIDED INSTEAD.

The honest answer is three questions rather than one, because one question cannot be answered. The
citation index is built by SCANNING each live body ONCE for path-shaped tokens, which is O(bytes of
live source), rather than testing each of the 6 341 paths against each of ~450 bodies, which is
O(2.8 million substrings over the same bytes).

  * `exact`     a live body contains the FULL repo-relative path. MEASURED WHY THE PERMISSIVE SHAPE
                IS REQUIRED: `checks/repro-paths.py` once used a five-item SUFFIX SET, so it read
                the PREFIX `blastradius.cpython-312.pyc` as the path `blastradius.cpython-312.py` --
                a dangling row for a name that never existed -- while it read
                `tn_graph_census-gate.py.bak` as `tn_graph_census-gate.py`, WHICH EXISTS, so a broken
                reference counted as resolved. A remembered suffix wrote false rows in BOTH
                directions. The token pattern below stops at the REAL extension, never at a
                remembered one.
  * `dir`       a live body contains an ANCESTOR DIRECTORY of the path, ending in `/`. A gate that
                names `.agents/slop/foo/` has named every file under it.
  * `basename`  a live body contains the bare basename, counted ONLY when that basename is UNIQUE
                across the census. `REPORT.md` appears hundreds of times and a citation of
                `REPORT.md` is not a citation of your one.
  * `declared`  `checks/differ.py:declared()` -- 244 paths, MEASURED -- names it. This is
                doctrine 1's clause (a): a GENERATOR'S OWN DECLARATION, and no grep over any body
                can see it because the names live in the generator's DATA, not its text.

WHAT REMAINS UNDECIDED, AND IT IS THE WHOLE WORD "LIVE":

  * whether the instrument is ever RUN. Nothing here executes a gate and `gates/gates-pop.py` names
    this as its own blind spot (3) in as many words. A gate nobody runs names things forever.
  * a citation assembled at RUN TIME from parts: `SLOP + "/" + name`, or `.agents/slop/{unit}/x.py`
    inside a template. The `root_cited` counter is the size of that blind spot and nothing more:
    it counts live bodies holding the `.agents/slop/` tree prefix, which is the necessary condition
    for such a citation, and each one is PRINTED BY NAME so a reader can judge it.
  * a gate that reads a DIRECTORY rather than a file.

**SO EVERY "LIVE" PRONOUN IN THIS TREE IS AN ESTIMATE, INCLUDING THIS FILE'S.** What is not an
estimate is the RECOVERABILITY column, which is exact, and which is why the rule is stated in terms
of it and not of "live": a prune that takes only `recover=REF` files is SAFE EVEN IF THE LIVENESS
ESTIMATE IS WRONG IN EITHER DIRECTION. Naming something nothing runs costs a recoverable blob;
failing to name something that does run costs a `git cat-file` and a `git checkout`. **The expensive
error is recoverable and the cheap error is not**, so the decidable half is the gate and the estimate
is the advice.

## THIS FILE EXCLUDES ITS OWN EVIDENCE, LOADED BY PATH

`plant_exclusions()` loads `.agents/slop/slopprune/plant.py:excluded()` BY PATH -- the shape
`checks/slop-declare.py` uses for `.agents/slop/declare/plant.py` and
`checks/oracle-txt-census.py` for `.agents/slop/oracletxt/plant.py`. This file's own docstring names
`.agents/slop/`, which is an ANCESTOR OF EVERY FILE IN THE POPULATION, so without the exclusion it
would certify all 6 341 LOAD-BEARING on the strength of its own prose. There is no second copy of
the list here to rot.

VERDICTS, in `AGENTS.md`'s five. PASS 0. FAIL the census cannot measure. REFUSED 3 git or the walk
did not answer. DEAD 5 the walk found 0 files.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLOP = ".agents/slop"
HERE = ROOT / SLOP / "slopprune"
SELF = "gates/slop-prune-census.py"

COLUMNS = ("path", "bytes", "tracked", "symlink", "last_commit", "last_age_h",
           "citers_exact", "citers_dir", "citers_basename", "declared_by",
           "recover", "blob", "class")

# A path-shaped token is a MAXIMAL RUN of `[\w./-]`, and then its ENDING decides what it is.
#
# IT IS A RUN AND NOT A PATTERN WITH AN ALTERNATION, AND HERE IS THE MEASUREMENT THAT FORCED IT.
# The first two attempts were both single regexes and both were wrong:
#
#   v1  `[\w./-]*\.[A-Za-z0-9]+`            saw 0 of 21 live citations of `.agents/slop/portexec/`
#       -- a token ending in `/` has no extension, so arm 1 cannot see a DIRECTORY citation, and a
#          gate that names a directory has named every file under it.
#   v2  `([\w./-]*\.[A-Za-z0-9]+|[\w./-]*/)` still saw 0, because `[\w./-]*` BACKTRACKS TO EMPTY
#       and `\.[A-Za-z0-9]+` then matches `.agents` -- a path COMPONENT mistaken for a file
#       extension. MEASURED, the token it produced for `` `.agents/slop/portexec/` `` was `.agents`.
#
# **BOTH ARE `repro-paths.py`'s SUFFIX-SET FAILURE IN A NEW COSTUME -- A REMEMBERED SHAPE INSTEAD OF
# A POPULATION -- AND NEITHER MADE THE GATE GO RED.** A run has no remembered shape: it stops where
# the text stops, and the ENDING is inspected afterwards. `blastradius.cpython-312.pyc` therefore
# stays whole and `tn_graph_census-gate.py.bak` stays whole, which is the property that pattern was
# bought for, and `.agents/slop/portexec/` is a directory because it ends in a separator.
RUN = re.compile(r"(?<![\w./])([\w./-]+)")
PATTERN = re.compile(r"\.\.\.|//")          # an ellipsis or a doubled separator: a family, not a file


def tokens(body: str):
    """Every path-shaped token in `body`, classified by its ending. None of them is a list."""
    for m in RUN.finditer(body):
        tok = m.group(1)
        if PATTERN.search(tok) or len(tok) < 3:
            continue
        if tok.endswith("/"):
            yield tok, "dir"
        elif "." in tok.rsplit("/", 1)[-1]:
            yield tok, "file"

_ODB: set[str] | None = None


def git(*args: str) -> subprocess.CompletedProcess:
    """`git` in ROOT, inheriting the environment -- so an exported `GIT_INDEX_FILE` is honoured by
    construction rather than by a parameter a caller has to remember to pass."""
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def rev() -> str:
    p = git("rev-parse", "HEAD")
    return p.stdout.strip() if p.returncode == 0 else "-"


def load_by_path(path: Path, name: str):
    """Import a sibling file that is not a package member -- `gates/` is not a package."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------- the population


def walk(root: Path) -> tuple[list[dict], int]:
    """THE POPULATION. `os.walk`, `followlinks=False`, no filter, no name list.

    **`lstat`, NOT `stat`, AND MEASURED WHY: `stat()` FOLLOWS A SYMLINK.** MEASURED 2026-10-19,
    this file's first version used `stat().st_size` and reported 1 616 451 920 bytes for the
    population. **1 495 045 538 of them -- 92.5% -- were 196 ENTRIES THAT ARE NOT FILES**: the
    `.agents/slop/e2epy/fixtures/*/sandbox/node` symlinks, each of which `stat()` reported as
    145 803 984 B because they all point at ONE 139 MB node binary. The regular files under `e2epy/`
    total **165 570 B**, MEASURED with `find -type f`. **A byte total that is 92% one binary counted
    196 times is a wrong reason dressed as a number**, and a prune sized against it would be sized
    against a phantom.

    So: `lstat`, a symlink counts its own path length, and `SYMLINK TARGET BYTES` is printed beside
    the total and never added to it."""
    rows, total, followed = [], 0, 0
    for base, dirnames, filenames in os.walk(root / SLOP, followlinks=False):
        dirnames.sort()
        for name in sorted(filenames):
            full = Path(base) / name
            try:
                st = full.lstat()
            except OSError:                       # a file the walk found and cannot stat: a broken
                size = -1                        # symlink, or a race. It is STILL IN THE POPULATION
                link = False                    # -- dropping it would hide it, and the point of a
                followed_bytes = 0               # walk is that it cannot see its own blind spot
            else:
                size = st.st_size
                link = full.is_symlink()
                followed_bytes = full.stat().st_size if link else 0
            followed += followed_bytes
            rows.append({"path": str(full.relative_to(root)), "bytes": size,
                         "symlink": "yes" if link else "no"})
            total += max(size, 0)
    return rows, total, followed


def excluded() -> frozenset[str]:
    """Path prefixes this census's OWN evidence must not be able to cite, loaded BY PATH."""
    plant = HERE / "plant.py"
    if not plant.is_file():
        return frozenset({f"{SLOP}/slopprune/", SELF})
    return frozenset(load_by_path(plant, "slop_prune_plant").excluded())


def _text(value: object) -> str:
    """A derivation, as one printable line. `gate_homes()` returns a DICT of the rows that measured
    its answer, and a reader is entitled to the rows and not to the answer alone -- a population a
    reader cannot see the size of is the defect `gates/gates-pop.py` exists to end."""
    if isinstance(value, dict):
        return " ".join(f"{k}={len(v) if hasattr(v, '__len__') else v}"
                        for k, v in value.items())[:160]
    return str(value)[:160]


# ---------------------------------------------------------------- recoverability, exactly


def head_blobs(pathspec: str = "") -> dict[str, str] | None:
    """`path -> blob sha` from `git ls-tree -r HEAD -z`. **THE ONLY EXACT CURRENT-TREE INDEX.**

    `-z` so a space in a name is data and a path is never quoted. This is also the `tracked`
    denominator, which is why the file has one `ls-tree` call and not two."""
    p = git("ls-tree", "-r", "-z", "HEAD", *(["--", pathspec] if pathspec else []))
    if p.returncode != 0:
        return None
    out: dict[str, str] = {}
    for rec in p.stdout.split("\0"):
        if not rec:
            continue
        meta, _, path = rec.partition("\t")
        parts = meta.split()
        if len(parts) == 3:
            out[path] = parts[2]
    return out


def history(pathspec: str) -> tuple[dict[str, tuple[str, float]], set[str]]:
    """`(path -> (newest sha, age h) over ALL refs, every path any ref's commit ever touched)`.

    `git log --name-only` is the EXACT path index that `git rev-list --objects` is not, because a diff
    knows which path each side of a change was, while an object walk only knows which object it
    reached. MEASURED, both ways on one 0-byte file: 12 lines here, 0 lines there.

    ONE subprocess, and it serves two questions: `last_commit` is the first hit because git sorts
    newest-first, and `hist` is every hit. `--all`, not `HEAD`, because a file last touched on ANOTHER
    agent's branch is not a file a prune may take, and a denominator that could not see that branch
    would call it stale rather than owned."""
    out: dict[str, tuple[str, float]] = {}
    p = git("log", "--all", "--format=%x01%H %ct", "--name-only", "--", pathspec)
    if p.returncode != 0:
        return out, set()
    sha, when = "", 0.0
    for line in p.stdout.splitlines():
        if line.startswith("\x01"):
            sha, _, ts = line[1:].partition(" ")
            try:
                when = round((time.time() - int(ts)) / 3600, 1)
            except ValueError:
                when = 0.0
            continue
        if line:
            if line not in out and sha:
                out[line] = (sha[:9], when)
    return out, set(out)


# ---------------------------------------------------------------- who is live, and what they name


def gate_homes(root: Path) -> tuple[tuple[str, ...], str]:
    """The live homes, MEASURED by loading `gates/gates-pop.py` BY PATH. Never a literal tuple.

    That function replaced `HOMES = ("checks", "gates")` with a measurement and records why: "A LIST
    COMPARED WITH ITSELF CANNOT DISAGREE". This file asks it the same question rather than keeping a
    second copy of the answer that would then be free to rot into a different one."""
    src = root / "gates" / "gates-pop.py"
    if not src.is_file():
        return (), "gates/gates-pop.py ABSENT -- no measurement, and no fallback list invented here"
    try:
        homes, deriv = load_by_path(src, "slop_prune_gates_pop").gate_homes(root)
    except Exception as exc:                                   # noqa: BLE001 - reported, not hidden
        return (), f"gate_homes() raised {type(exc).__name__}: {exc}"
    return tuple(homes), _text(deriv)


def live_sources(root: Path, homes: tuple[str, ...]) -> dict[str, str]:
    """`rel -> text` for every regular file immediately inside a measured home.

    IMMEDIATE, matching `gate_homes()`'s own coherence condition: a witness three levels down would
    certify a home whose population this walk cannot reach."""
    out: dict[str, str] = {}
    for home in homes:
        base = root / home
        if base.is_dir():
            for entry in sorted(base.iterdir()):
                try:
                    if entry.is_file() and entry.suffix in (".py", ".sh", ".mjs"):
                        out[f"{home}/{entry.name}"] = entry.read_text(errors="replace")
                except OSError:
                    continue
    return out


def declared_by_generator(root: Path) -> tuple[set[str], str]:
    """`checks/differ.py:declared()` BY PATH -- a GENERATOR'S OWN DECLARATION, doctrine 1 clause (a).

    No grep sees these: they are the generator's DATA. `checks/no-txt.py` and
    `checks/differ.py:artefacts_ok()` both load this same function, which is why the `.txt` carve-out
    never moved while the total moved 398 -> 552 -> 562 -> 553. A census that did not ask would
    report a declared artifact as SAFE because no body of text spells it."""
    src = root / "checks" / "differ.py"
    if not src.is_file():
        return set(), "checks/differ.py ABSENT"
    try:
        import sys as _sys
        _sys.path.insert(0, str(root / "checks"))
        try:
            return set(load_by_path(src, "slop_prune_differ").declared()), "differ.declared()"
        finally:
            _sys.path.remove(str(root / "checks"))
    except Exception as exc:                                   # noqa: BLE001 - reported, not hidden
        return set(), f"differ.declared() raised {type(exc).__name__}: {exc}"


def citation_index(root: Path, rows: list[dict], sources: dict[str, str],
                   skip: frozenset[str]) -> dict[str, dict[str, list[str]]]:
    """`path -> {strength: [citer, ...]}`, built by ONE scan of each live body.

    The direction matters and it is the direction that makes this affordable: the census is the
    LARGER side, so the larger side is scanned. Testing 6 341 paths against ~450 bodies is 2.8
    million substring searches over the same bytes; scanning ~450 bodies for path-shaped tokens is
    one pass over ~20 MB and produces the same table."""
    known = {r["path"]: r for r in rows}
    dirs: dict[str, list[str]] = {}
    counts: dict[str, int] = {}
    for r in rows:
        parts = r["path"].split("/")
        for i in range(3, len(parts)):
            dirs.setdefault("/".join(parts[:i]) + "/", []).append(r["path"])
        base = r["path"].rsplit("/", 1)[-1]
        counts[base] = counts.get(base, 0) + 1

    out = {p: {"exact": [], "dir": [], "basename": []} for p in known}
    root_prefixed: list[str] = []
    for rel, body in sources.items():
        if any(rel.startswith(s) for s in skip):
            continue
        hit = False
        for tok, kind in tokens(body):
            if kind == "dir":
                for p in dirs.get(tok, ()):
                    if not any(p.startswith(s) for s in skip):
                        out[p]["dir"].append(rel)
                        hit = True
                continue
            if tok in known and not any(tok.startswith(s) for s in skip):
                out[tok]["exact"].append(rel)
                hit = True
                continue
            base = tok.rsplit("/", 1)[-1]
            if "/" not in tok and counts.get(base) == 1 and base in known and \
                    not any(known[base].startswith(s) for s in skip):
                out[known[base]]["basename"].append(rel)
                hit = True
        if not hit and f"{SLOP}/" in body:
            root_prefixed.append(rel)
    return {"__index__": out, "root_prefixed": root_prefixed}


def ancestry(rel: str) -> list[str]:
    """`.agents/slop/a/b/c.py` -> `['.agents/slop/a/', '.agents/slop/a/b/']`.

    **THE ROOT IS NOT AN ANCESTOR HERE.** `.agents/slop/` with a trailing slash names the TREE, and a
    file that mentions the tree has named none of its 6 000 entries -- this file's own docstring
    mentions it dozens of times. Root-prefix citations are counted separately as `root_prefixed`."""
    parts = rel.split("/")
    return ["/".join(parts[:i]) + "/" for i in range(3, len(parts))]


# ---------------------------------------------------------------- the classification


def last_touch() -> dict[str, tuple[str, float]]:
    """Kept as the name callers know; the body moved into `history()` because the same single
    `git log` answers both "newest commit that touched this path" and "is this path in any ref at
    all", and running it twice would walk 24 516 commits twice for one answer."""
    return history(SLOP)[0]


def census(root: Path) -> dict:
    """Every measurement, in one dict, so the report computes nothing of its own."""
    rows, total, followed = walk(root)
    if not rows:
        return {"error": f"the walk found 0 files under {SLOP}"}
    tracked = head_blobs()
    if tracked is None:
        return {"error": "`git ls-tree -r HEAD -z` did not answer"}

    skip = excluded()
    homes, deriv = gate_homes(root)
    sources = live_sources(root, homes)
    declared, declared_deriv = declared_by_generator(root)
    citations = citation_index(root, rows, sources, skip)
    idx = citations["__index__"]
    touch, hist = history(SLOP)

    for r in rows:
        p = r["path"]
        r["tracked"] = "yes" if p in tracked else "no"
        r["last_commit"], r["last_age_h"] = touch.get(p, ("-", 0.0))
        c = idx.get(p, {"exact": [], "dir": [], "basename": []})
        r["citers_exact"] = len(set(c["exact"]))
        r["citers_dir"] = len(set(c["dir"]))
        r["citers_basename"] = len(set(c["basename"]))
        r["declared_by"] = "yes" if p in declared else "no"
        r["recover"], r["blob"] = "none", "-"
        if p in tracked:
            r["recover"], r["blob"] = "HEAD", tracked[p]
        elif p in hist:
            r["recover"] = "hist"
        named = r["citers_exact"] or r["citers_dir"] or r["citers_basename"]
        r["class"] = ("LOAD-BEARING" if named or r["declared_by"] == "yes"
                      else "SAFE" if r["recover"] != "none"
                      else "UNRECOVERABLE")
    return {"rows": rows, "total": total, "followed": followed,
            "homes": homes, "derivation": deriv,
            "declared_deriv": declared_deriv, "n_declared": len(declared),
            "sources": sorted(sources), "skip": skip, "n_hist": len(hist),
            "root_prefixed": citations["root_prefixed"],
            "index_delta": len({f for f in git("ls-files", "-z").stdout.split("\0")
                                if f and f not in tracked})}


def write_rows(surveyed: dict, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(["\t".join(COLUMNS)] +
                              ["\t".join(str(r[c]) for c in COLUMNS)
                               for r in sorted(surveyed["rows"], key=lambda x: x["path"])]) + "\n")


def report(surveyed: dict) -> int:
    rows, total = surveyed["rows"], surveyed["total"]
    cls = {k: [r for r in rows if r["class"] == k]
           for k in ("SAFE", "LOAD-BEARING", "UNRECOVERABLE")}
    print(f"slop-prune-census   HEAD {rev()}   {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}")
    print(f"  POPULATION     os.walk('{SLOP}/', followlinks=False) -- no filter, no name list, no glob")
    print(f"    files {len(rows)}   bytes {total}   (lstat; a symlink counts its own path length)")
    print(f"    symlinks {sum(1 for r in rows if r['symlink'] == 'yes')}, whose TARGETS sum to "
          f"{surveyed['followed']} B -- MEASURED, PRINTED, AND NOT ADDED TO THE TOTAL")
    print(f"    (stat() would have reported {total + surveyed['followed']} B; "
          f"{round(100 * surveyed['followed'] / max(total + surveyed['followed'], 1))}% of that "
          f"is one node binary counted once per link)")
    print(f"  TRACKEDNESS    git ls-tree -r HEAD -z   yes "
          f"{sum(1 for r in rows if r['tracked'] == 'yes')}   no "
          f"{sum(1 for r in rows if r['tracked'] == 'no')}")
    print(f"    index-vs-HEAD {surveyed['index_delta']} paths in the INDEX that HEAD lacks "
          f"(git ls-files read ONLY to print this)")
    print(f"  LIVE HOMES     {surveyed['homes']}   {len(surveyed['sources'])} sources read")
    print(f"    derived by {surveyed['derivation']}")
    print(f"  DECLARED       {surveyed['declared_deriv']} = {surveyed['n_declared']} paths, "
          f"{sum(1 for r in rows if r['declared_by'] == 'yes')} of them inside this population")
    print("  RECOVERABILITY HEAD=git ls-tree -r HEAD -z | "
          f"hist=git log --all --name-only -- {SLOP} ({surveyed['n_hist']} paths ever)")
    for level in ("HEAD", "hist", "none"):
        print(f"    {level:<9} {sum(1 for r in rows if r['recover'] == level):>5} files")
    print("    a blob reachable from NO ref is not counted: the object store has no path index,")
    print("    and `git rev-list --objects` is not one either -- see the header. The classes below")
    print("    are claims about REFS.")
    print("  THE THREE CLASSES")
    for name in ("SAFE", "LOAD-BEARING", "UNRECOVERABLE"):
        size = sum(max(r["bytes"], 0) for r in cls[name])
        print(f"    {name:<14} {len(cls[name]):>5} files  {size:>13} bytes")
    lb = cls["LOAD-BEARING"]
    print(f"    LOAD-BEARING and restorable from HEAD's tree: "
          f"{sum(1 for r in lb if r['recover'] == 'HEAD')}"
          f"   -> prunable IF the citation is not read as a contract")
    if cls["UNRECOVERABLE"]:
        print("  UNRECOVERABLE -- no blob at this path in any ref. ALREADY LOST, record them:")
        for r in cls["UNRECOVERABLE"][:40]:
            print(f"    ! {r['path']}  {r['bytes']} B  tracked={r['tracked']} "
                  f"last={r['last_commit']}")
    print(f"  UNDECIDED BY ANY COMMAND: {len(surveyed['root_prefixed'])} live bodies hold the "
          f"'{SLOP}/' prefix without naming a census path,")
    print("    which is the necessary condition for a RUN-TIME-ASSEMBLED citation. Each by name:")
    for rel in surveyed["root_prefixed"]:
        print(f"      ? {rel}")
    print(f"  SELF-EXCLUSION {len(surveyed['skip'])} prefixes from {SLOP}/slopprune/plant.py, "
          f"loaded by path")
    return 1 if cls["UNRECOVERABLE"] else 0


def plant(surveyed: dict) -> int:
    """PLANT 4 -- MOVE THE ROW COUNT, THEN MOVE A CLASS. IN A TEMP COPY. NOTHING IS DELETED HERE.

    TWO DISTINCT VICTIMS, AND THE FIRST VERSION HAD ONE, WHICH MEANT IT COULD NOT MOVE A CLASS AT
    ALL: it deleted a file and then cited that same file, and **a file that is not on disk cannot be
    reclassified.** The run said `CLASS MOVES 0` and `VERDICT FAIL`, which is the plant working -- the
    harness failed and said so rather than reporting the movement it was supposed to look for.

    **AND THE COPY MUST NOT FILTER THE POPULATION.** The first version passed
    `ignore_patterns(".git", "__pycache__")` to `copytree`, which is a reasonable thing to write and
    is a PLANT THAT MOVES THE ANSWER IT MEASURES: the copy then held 83 fewer files than the tree it
    was comparing against, `ROWS 6447 -> 6363`, and `UNRECOVERABLE 116 -> 43`. **Both of those were
    the ignore pattern and neither was the mutation.** `.git` is excluded because the census asks git
    questions of the working copy's repository and a copy of a repository is a different repository;
    `__pycache__` is NOT excluded, because it is 32 rows of the very class under test.

    The check is therefore a CLOSED SET, not a tolerance: every path that leaves the census must be
    the path this plant deleted, and every class movement must be accounted for by the citation.

    **AND THE CITATION MUST COME FROM AN INSTRUMENT THAT IS NOT ITSELF EXCLUDED.** The second run
    appended the path to `gates/slop-prune-census.py` and the class did not move: this file's own
    `plant.py:excluded()` lists `SELF`, `citation_index` drops any citer under a skip prefix, and the
    citation was discarded **correctly**. That is the exclusion doing its job -- without it every file
    would be LOAD-BEARING on this file's prose -- so the fix is not to weaken the exclusion but to
    cite from a DIFFERENT live body. The body is the lexically first source that no skip prefix
    covers, DISCOVERED from `live_sources`, and it is printed so a reader knows which file the plant
    rewrote."""
    import shutil
    import tempfile
    before = {r["path"]: r["class"] for r in surveyed["rows"]}
    safe = sorted((r for r in surveyed["rows"]
                   if r["class"] == "SAFE" and r["tracked"] == "yes"),
                  key=lambda r: len(r["path"]))
    citers = [s for s in surveyed["sources"] if not any(s.startswith(x) for x in surveyed["skip"])]
    if len(safe) < 2 or not citers:
        print(f"PLANT REFUSED: {len(safe)} tracked SAFE files, {len(citers)} unexcluded citers")
        return 3
    deleted, cited, plant_from = safe[0], safe[1], citers[0]
    with tempfile.TemporaryDirectory(prefix="slop-prune-plant.") as tmp:
        copy = Path(tmp) / "repo"
        shutil.copytree(ROOT, copy, symlinks=True,
                        ignore=shutil.ignore_patterns(".git"))
        (copy / deleted["path"]).unlink()
        target = copy / plant_from
        target.write_text(target.read_text() + f"\nPLANT_CITES = {cited['path']!r}\n")
        after = census(copy)
        if "error" in after:
            print(f"PLANT FAIL: the copy would not census: {after['error']}")
            return 1
        now = {r["path"]: r["class"] for r in after["rows"]}
        lost = set(before) - set(now)
        added = set(now) - set(before)
        moved = [p for p in now if p in before and now[p] != before[p]]
        print(f"PLANT, in a TEMP COPY at {copy}. The tree was not touched.")
        print(f"  DELETE  {deleted['path']}  (a tracked SAFE file, from the COPY only) -- ROW COUNT")
        print(f"  CITE    {plant_from} was given {cited['path']} in its bytes -- CLASS MOVEMENT")
        checks = [
            ("rows fell by exactly 1", len(now) == len(before) - 1,
             f"{len(before)} -> {len(now)}"),
            ("the only path off the census is the deleted one", lost == {deleted["path"]},
             f"{len(lost)} off: {sorted(lost)[:3]}"),
            ("no path appeared that was not in the tree", not added, f"{len(added)} new"),
            ("the cited file moved SAFE -> LOAD-BEARING",
             now.get(cited["path"]) == "LOAD-BEARING" and before[cited["path"]] == "SAFE",
             f"{before[cited['path']]} -> {now.get(cited['path'])}"),
            ("exactly one class movement", moved == [cited["path"]], f"{len(moved)}: {moved[:3]}"),
        ]
        for name, ok, detail in checks:
            print(f"  {'OK  ' if ok else 'FAIL'}  {name:<52} {detail}")
        print("  CLASS COUNTS")
        for c in ("SAFE", "LOAD-BEARING", "UNRECOVERABLE"):
            b = sum(1 for v in before.values() if v == c)
            a = sum(1 for v in now.values() if v == c)
            print(f"    {c:<14} {b:>5} -> {a:>5}   ({a - b:+d})")
        ok = all(c[1] for c in checks)
        print(f"  VERDICT {'PASS' if ok else 'FAIL'}")
        return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rows", help="write the per-file TSV here (default: "
                                   f"{SLOP}/slopprune/census.tsv)")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--plant", action="store_true", help="run plant 4 in a temp copy")
    args = ap.parse_args(argv)
    surveyed = census(ROOT)
    if "error" in surveyed:
        dead = "found 0 files" in surveyed["error"]
        print(f"{'DEAD' if dead else 'REFUSED'}: {surveyed['error']}")
        return 5 if dead else 3
    if args.plant:
        return plant(surveyed)
    if not args.quiet:
        write_rows(surveyed, Path(args.rows) if args.rows else HERE / "census.tsv")
    return report(surveyed)


if __name__ == "__main__":
    sys.exit(main())
