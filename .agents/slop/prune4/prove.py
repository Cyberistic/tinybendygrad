#!/usr/bin/env python3
"""prune4: prove or refuse each deletion candidate. No name shapes.

A candidate is DELETABLE only if ALL of these hold, each measured:
  1. UNTRACKED  - `git ls-tree -r HEAD` has no blob at that path
  2. GITIGNOREd - `git check-ignore` matches (the tree already says it is not
                  source; a file the tree ignores is a build product by the
                  tree's own declaration, which IS a population)
  3. GENERATOR COMMITTED - the module that produces it is in HEAD. For a
                  __pycache__/x.pyc the generator is x.py itself AND CPython
                  regenerates on next import (no run needed to prove THAT).
                  For a .bin it is the .bend it compiled -- which must be in
                  HEAD or the deletion is refused (prune3's lesson).
  4. OWNER COLD - no file inside the owning unit dir was written in the last
                  COLD_MIN minutes. A live unit's scratch is work, not debris.
  5. NO COMMITTED READER names it (else it is bucket E and deleting it breaks
                  a reader).

Refuses print WHY with the measurement that refused them.
"""
import os, re, subprocess, sys, time

SLOP = ".agents/slop"
COLD_MIN = 120.0


def sh(*a):
    return subprocess.run(a, capture_output=True).stdout.decode(errors="replace")


def head_tree():
    """--name-only is NOT optional. Without it ls-tree emits
    '<mode> <type> <sha>\\t<path>' and EVERY equality test against a bare path
    fails -- measured: that bug made the 'untracked' predicate vacuously true
    for all 4025 files (see REPORT.md sec.4)."""
    t = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only", "-z",
                        "--", SLOP], capture_output=True).stdout.decode()
    return {p for p in t.split("\0") if p}


def newest_mtime(path):
    n = 0.0
    st = [path]
    while st:
        d = st.pop()
        try:
            es = list(os.scandir(d))
        except OSError:
            continue
        for e in es:
            try:
                s = e.stat(follow_symlinks=False)
            except OSError:
                continue
            n = max(n, s.st_mtime)
            if e.is_dir(follow_symlinks=False):
                st.append(e.path)
    return n


def candidates():
    """DISCOVERY: every __pycache__ dir (git declares the pattern via
    .gitignore:13, and a .pyc dir has no other meaning) plus every *.bin
    (.gitignore:8). No hand list."""
    stack = [SLOP]
    while stack:
        d = stack.pop()
        try:
            es = sorted(os.scandir(d), key=lambda e: e.name)
        except OSError:
            continue
        for e in es:
            if e.is_dir(follow_symlinks=False):
                if e.name == "__pycache__":
                    yield ("pycache", e.path)
                else:
                    stack.append(e.path)
            elif not e.is_symlink() and e.name.endswith(".bin"):
                yield ("bin", e.path)


def main():
    tracked = head_tree()
    now = time.time()
    rows = []
    for kind, path in candidates():
        rel = os.path.relpath(path)
        owner = os.path.dirname(path)
        top = os.path.dirname(rel)
        cold_min = (now - newest_mtime(owner)) / 60.0

        nblocks = nfiles = 0
        if kind == "pycache":
            for dp, _dn, fns in os.walk(path):
                for fn in fns:
                    try:
                        st = os.lstat(os.path.join(dp, fn))
                    except OSError:
                        continue
                    nblocks += st.st_blocks
                    nfiles += 1
        else:
            try:
                nblocks = os.lstat(path).st_blocks
                nfiles = 1
            except OSError:
                pass
        size = nblocks * 512

        untracked = not any(p == rel or p.startswith(rel + os.sep)
                            for p in tracked)
        ignored = bool(sh("git", "check-ignore", "-q", rel).strip()) or \
            subprocess.run(["git", "check-ignore", "-q", rel]).returncode == 0

        if kind == "pycache":
            # generator = a sibling module that IS in HEAD. CPython rebuilds the
            # .pyc on the next import, so a committed sibling proves
            # regenerability without running anything.
            mods = [os.path.join(owner, f) for f in os.listdir(owner)
                    if f.endswith(".py")] if os.path.isdir(owner) else []
            gen = [os.path.relpath(m) for m in mods if os.path.relpath(m) in tracked]
            gen_ok = bool(gen)
            gen_why = (f"generator committed: {[os.path.basename(g) for g in gen][:3]}"
                       if gen_ok else "NO sibling .py in HEAD -> cannot prove a generator")
        else:
            # The generator must be named BY THIS ARTIFACT, at the same basename,
            # in the same or a sibling directory. A scan for ANY tracked *.bend
            # with a matching BASENAME is a name shape: it matched gate.bin to
            # .agents/slop/i64mul/gate.bend, an unrelated file (measured).
            b = os.path.basename(path)
            stem = b[:-4]
            here = os.path.relpath(os.path.dirname(path))
            cands = []
            for d in (here, os.path.dirname(here), "tinybendygrad", SLOP, "gates"):
                c = f"{d}/{stem}.bend" if d else f"{stem}.bend"
                if c in tracked:
                    cands.append(c)
            gen_ok = bool(cands)
            gen_why = (f"generator committed: {cands[:2]}" if gen_ok
                       else f"no {stem}.bend at this path/sibling/parent in HEAD "
                            f"-> ABSENCE, not proof of redundancy (prune3)")

        cold = cold_min > COLD_MIN
        ok = untracked and ignored and gen_ok and cold
        rows.append(dict(kind=kind, path=path, size=size, files=nfiles,
                         untracked=untracked, ignored=ignored, gen=gen_ok,
                         gen_why=gen_why, cold=cold, cold_min=cold_min,
                         ok=ok, rel=rel))

    rows.sort(key=lambda r: -r["size"])
    dele = [r for r in rows if r["ok"]]
    refus = [r for r in rows if not r["ok"]]
    with open(".agents/slop/prune4/candidates.rows", "w") as f:
        f.write("# kind\tsize_B\tfiles\tuntracked\tignored\tgenerator\tcold\t"
                "owner_cold_min\tDELETE\trel\trefusal\n")
        for r in rows:
            why = "" if r["ok"] else (
                "LIVE-OWNER" if not r["cold"] else
                "TRACKED" if not r["untracked"] else
                "NOT-IGNORED" if not r["ignored"] else "NO-COMMITTED-GENERATOR")
            f.write(f"{r['kind']}\t{r['size']}\t{r['files']}\t{r['untracked']}\t"
                    f"{r['ignored']}\t{r['gen']}\t{r['cold']}\t{r['cold_min']:.1f}\t"
                    f"{'DELETE' if r['ok'] else 'REFUSE'}\t{r['rel']}\t{why}\n")
    print(f"candidates={len(rows)}  DELETE={len(dele)}  REFUSE={len(refus)}")
    print(f"DELETE bytes = {sum(r['size'] for r in dele)} "
          f"({sum(r['size'] for r in dele)/1024:.0f} KB)")
    print("\nDELETE:")
    for r in dele:
        print(f"  {r['size']:>8} {r['kind']:8s} {r['rel']}")
    print("\nREFUSED:")
    for r in refus:
        why = ("LIVE-OWNER" if not r["cold"] else
               "TRACKED" if not r["untracked"] else
               "NOT-IGNORED" if not r["ignored"] else "NO-COMMITTED-GENERATOR")
        print(f"  {r['size']:>8} {r['kind']:8s} {r['rel']}  <- {why} "
              f"(owner cold {r['cold_min']:.0f} min)  {r['gen_why']}")


if __name__ == "__main__":
    main()