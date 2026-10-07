#!/usr/bin/env python3
"""prune4 guarded delete. Refuses unless EVERY precondition still holds AT THE
MOMENT OF DELETION, re-verified here and not trusted from prove.py's earlier run
(the tree moves; a 20-minute-old verdict is not a verdict).

Refuses to touch anything that is tracked in HEAD, anything not gitignored,
anything whose owner was written in the last COLD_MIN minutes, and anything
without a committed sibling generator. Prints the bytes it freed from its own
lstat, which is the number the report quotes -- not a whole-tree delta, because
a whole-tree delta on a tree other units are writing is not a measurement
(prune3 sec.3 measured exactly this trap).
"""
import os, subprocess, sys, time

SLOP = ".agents/slop"
COLD_MIN = 120.0


def tracked():
    t = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only", "-z",
                        "--", SLOP], capture_output=True).stdout.decode()
    return {p for p in t.split("\0") if p}


def newest(path):
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


def main(paths):
    tr = tracked()
    now = time.time()
    freed = nfiles = 0
    for p in paths:
        owner = os.path.dirname(p)
        if not os.path.isdir(p):
            print(f"REFUSE {p}: absent")
            continue
        if any(x == p or x.startswith(p + os.sep) for x in tr):
            print(f"REFUSE {p}: TRACKED IN HEAD")
            continue
        if subprocess.run(["git", "check-ignore", "-q", p]).returncode != 0:
            print(f"REFUSE {p}: not gitignored")
            continue
        cold = (now - newest(owner)) / 60.0
        if cold <= COLD_MIN:
            print(f"REFUSE {p}: owner {owner} written {cold:.1f} min ago (LIVE)")
            continue
        mods = [f for f in os.listdir(owner) if f.endswith(".py")]
        gen = [f for f in mods
               if os.path.relpath(os.path.join(owner, f)) in tr]
        if not gen:
            print(f"REFUSE {p}: no committed sibling generator")
            continue
        b = n = 0
        for dp, _dn, fns in os.walk(p):
            for fn in fns:
                try:
                    st = os.lstat(os.path.join(dp, fn))
                except OSError:
                    continue
                b += st.st_blocks * 512
                n += 1
        import shutil
        shutil.rmtree(p)
        freed += b
        nfiles += n
        print(f"DELETED {p}  {b} B  {n} files  (gen={gen[0]}, owner cold {cold:.0f} min)")
    print(f"\nFREED {freed} B ({freed/1024:.0f} KB) over {nfiles} files")


if __name__ == "__main__":
    main(sys.argv[1:])