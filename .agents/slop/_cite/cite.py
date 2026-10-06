#!/usr/bin/env python3
"""Whole-path-token citation index over LIVE code only.

Rules encoded here (each one has bitten this project before):
  * A citation is the path token `slop/<dir>` or `slop/<dir>/<file>`, matched as
    a WHOLE token.  `\b` is useless next to `/` and `.`, so delimiting is done
    with an explicit character class.  Bare-substring matching is not a test:
    it reported 23 citers for `.out` where the whole-token answer is 2.
  * Shadow trees (full source copies and worktree arms) are never index sources:
    a citation from inside the tree being swept proves nothing.  A citation
    index built from the swept tree is not a citation index.
  * `.agents/slop/**` is never an index source at all, its own `.md` included.
  * `jj`'s default pathspec lets `*` cross `/`; nothing here uses a pathspec, so
    the 98-vs-195 class of bug cannot arise.  (We enumerate with os.walk.)
"""
import os, re, sys, json

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SLOP = os.path.join(ROOT, ".agents/slop")

SHADOW_DIRS = {"plant", "strays", "strays-root", "rf2root", "dd-cone-wt", "xd1",
               "runs", "__pycache__", "node_modules", ".venv", ".git", ".jj",
               "_cite", "references", "target", "dist", "build"}
ANY_DEPTH = {".venv", "node_modules", "__pycache__", ".git", ".jj", ".hg", ".svn"}
INDEX_EXT = {".py", ".sh", ".bend", ".md", ".json", ".tsv", ".mjs", ".js",
             ".ts", ".toml", ".cfg", ""}


def tier(src):
    """Authority of a citing file.

    TIER A is the test the brief names: live `checks/*.py` or `gates/*.py`.
    TIER B is other live code that runs (bend sources, helpers, shims).
    TIER C is prose: ledgers, READMEs, TODO.  A prose mention is a claim about
    the tree, not a dependency on it, so it is reported separately and never
    on its own justifies ORACLE.
    """
    p = src.split("/")
    if p[0] == "checks" or p[0] == "gates":
        return "A"
    if p[0] == "runs" or p[0] == ".agents" or src in ("AGENTS.md", "README.md", "LAWS.bend", "PROOF.bend"):
        return "C"
    if p[0] == "checks" or p[0] == "gates":
        return "A"
    return "B"

# A path token: runs of path-ish chars that contain a `/`.  Longest-match not
# needed -- we index every suffix of the run, which is the set of things a
# citation could plausibly name.
TOK = re.compile(r"[A-Za-z0-9_.+@-]+(?:/[A-Za-z0-9_.+@-]+)*")


def is_shadow(rel):
    parts = rel.split("/")
    if ANY_DEPTH & set(parts):
        return True
    if parts[:2] in ([".agents", "runs"], ["runs", "graphcmp"]):
        return True
    if parts[:2] == [".agents", "slop"] and len(parts) > 2:
        if parts[2] in SHADOW_DIRS or parts[2:4] == ["shfinish", "plant"]:
            return True
    return False


def walk(base="."):
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, base)):
        r = os.path.relpath(dirpath, ROOT)
        r = "" if r == "." else r
        dirnames[:] = sorted(d for d in dirnames
                             if not is_shadow(os.path.join(r, d) if r else d))
        for f in sorted(filenames):
            fr = os.path.join(r, f) if r else f
            if not is_shadow(fr):
                yield fr


def main():
    # 1. what exists under slop, as repo-relative and slop-relative paths
    exist = {}          # slop-relative path -> lstat size
    dirs = set()
    for dirpath, dirnames, filenames in os.walk(SLOP):
        dirnames[:] = [d for d in dirnames if not is_shadow(
            os.path.relpath(os.path.join(dirpath, d), ROOT))]
        rel = os.path.relpath(dirpath, SLOP)
        if rel != ".":
            dirs.add(rel.split("/")[0])
        for f in filenames:
            p = os.path.join(dirpath, f)
            exist[os.path.relpath(p, SLOP)] = os.lstat(p).st_size

    # 2. one pass over every live index file; collect token suffixes mentioning slop
    citers = {}         # slop-rel path (no trailing /) -> {src: count}
    dirciters = {}      # top-level slop dir -> {src}
    nsrc = 0
    for src in walk("."):
        if src.startswith(".agents/slop"):
            continue                      # the swept tree is not an authority
        if os.path.splitext(src)[1] not in INDEX_EXT:
            continue
        try:
            blob = open(os.path.join(ROOT, src), "rb").read().decode("utf-8", "replace")
        except OSError:
            continue
        nsrc += 1
        seen = set()
        for m in TOK.finditer(blob):
            run = m.group(0)
            if "slop/" not in run:
                continue
            # every suffix of the run is a candidate name
            parts = run.split("/")
            for i, p in enumerate(parts):
                if p != "slop":
                    continue
                rest = "/".join(parts[i + 1:]).rstrip(".")
                # drop python attribute noise / trailing punctuation
                rest = rest.strip(".,:;)'\"")
                if not rest:
                    continue
                seen.add(rest)
        for rest in seen:
            if rest in exist:
                citers.setdefault(rest, set()).add(src)
            if rest.split("/")[0] in dirs and rest not in exist:
                dirciters.setdefault(rest.split("/")[0], set()).add(src)
            elif rest in dirs:
                dirciters.setdefault(rest, set()).add(src)

    json.dump({"citers": {k: sorted(v) for k, v in citers.items()},
               "dirciters": {k: sorted(v) for k, v in dirciters.items()},
               "dirs": sorted(dirs),
               "files": exist,
               "nsrc": nsrc},
              open(os.path.join(HERE, "cites.json"), "w"), indent=1)

    print(f"# live index sources scanned: {nsrc}")
    print(f"# slop dirs: {len(dirs)}   slop files: {len(exist)}")
    for d in sorted(dirs):
        mine = [p for p in exist if p.split("/")[0] == d]
        cits = {p: sorted(citers.get(p, ())) for p in mine if citers.get(p)}
        dc = sorted(dirciters.get(d, ()))
        flag = "CITED" if (cits or dc) else "----- "
        print(f"{flag} {d:22s} files={len(mine):3d} cited={len(cits):2d} dirnamed={len(dc)}")


main()
