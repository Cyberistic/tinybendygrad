#!/usr/bin/env python3
"""prune4 census. BY DISCOVERY: no hand list of directories anywhere.

Aggregates lstat st_blocks per DIRECTORY OF RECORD (one level of fan-out from the
unit dirs, then one more for files inside), and classifies every unit dir by
tracked/untracked status read from git, not from a name shape.
"""
import os, subprocess, sys, json, collections

ROOT = ".agents/slop"


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def git_ls(path):
    out = sh("git", "ls-files", "-z", "--", path)
    return set(p for p in out.split("\0") if p)


def git_head_blob(path):
    """Return the HEAD blob sha at this exact path, or None."""
    r = subprocess.run(["git", "rev-parse", "--verify", "--quiet",
                        f"HEAD:{path}"], capture_output=True, text=True)
    return r.stdout.strip() or None


def measure_one(path):
    blocks = size = 0
    nfiles = nsym = 0
    stack = [path]
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                entries = list(it)
        except OSError:
            continue
        for e in entries:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            blocks += st.st_blocks
            size += st.st_size
            if e.is_symlink():
                nsym += 1
            elif e.is_dir(follow_symlinks=False):
                stack.append(e.path)
            else:
                nfiles += 1
    return blocks * 512, size, nfiles, nsym


def unit_dirs():
    """DISCOVER the population: every entry in ROOT. No list."""
    for e in sorted(os.scandir(ROOT), key=lambda e: e.name):
        if e.is_dir(follow_symlinks=False):
            yield e.name, e.path
        else:
            yield e.name, None  # a loose FILE at the top of slop


if __name__ == "__main__":
    rows = []
    tracked_all = git_ls(ROOT)
    for name, path in unit_dirs():
        if path is None:
            st = os.lstat(os.path.join(ROOT, name))
            rows.append(dict(name=name, kind="loosefile", disk=st.st_blocks * 512,
                             size=st.st_size, files=1, symlinks=0,
                             tracked=name in tracked_all))
            continue
        disk, size, nf, ns = measure_one(path)
        t = git_ls(path)
        rows.append(dict(name=name, kind="dir", disk=disk, size=size,
                         files=nf, symlinks=ns, tracked=len(t),
                         untracked_files=sum(
                             1 for _r, ds, fs in os.walk(path) for f in fs
                             if os.path.join(_r, f) not in tracked_all)))
    rows.sort(key=lambda r: -r["disk"])
    with open(".agents/slop/prune4/census.rows", "w") as f:
        for r in rows:
            f.write(f"{r['disk']:>10}\t{r['size']:>10}\t{r['kind']:>8}\t"
                    f"{r['files']:>5}\t{r['symlinks']:>4}\t{r.get('tracked','-'):>5}\t"
                    f"{r.get('untracked_files','-'):>5}\t{r['name']}\n")
    for r in rows[:30]:
        print(f"{r['disk']/1048576:8.3f}MB files={r['files']:>5} sym={r['symlinks']:>4} "
              f"tracked={r.get('tracked','-'):>5} {r['name']}")
    print(f"... {len(rows)} rows total, "
          f"{sum(r['disk'] for r in rows)/1048576:.2f} MB")