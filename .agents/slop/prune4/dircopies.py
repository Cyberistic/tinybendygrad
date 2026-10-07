#!/usr/bin/env python3
"""prune4: DIRECTORY COPY detection. The new axis.

A directory copy is D, where D's (relative-path -> content-hash) map is EQUAL to
some other directory E's map. Not "shares some files" -- EQUAL as a set. That is
the shape of `orcdecide/retired/` (a copy of what it retired) and the shape a
prune must catch, because git already holds every one of those bytes.

Two answers per pair, and the difference is the whole question:
  MOVE  - the source no longer exists. The copy is the only worktree copy, but
          git may still hold the original content. Deleting is safe ONLY if git
          holds it; otherwise it deletes the only copy.
  COPY  - the source still exists. Then the worktree holds TWO answers to
          "what was there" and git is the archive. This is the cheap class.

Discovery, not a list: every directory under ROOT is keyed by its full
(relpath -> sha) map; equal maps are grouped. Subdirectories inherit their
parent's map, so I compare each dir against any dir with the same file COUNT
first (cheap reject) and only then hash.
"""
import os, sys, hashlib, subprocess, collections

ROOT = ".agents/slop"


def sha1_blob(path):
    st = os.lstat(path)
    h = hashlib.sha1()
    h.update(f"blob {st.st_size}\0".encode())
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def dirmap(root):
    """{relpath: sha} for one directory tree. Returns None if unreadable."""
    m = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if not os.path.islink(os.path.join(dirpath, d))]
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            if os.path.islink(p):
                continue
            try:
                m[os.path.relpath(p, root)] = sha1_blob(p)
            except OSError:
                pass
    return m


def main():
    dirs = []
    stack = [ROOT]
    while stack:
        d = stack.pop()
        dirs.append(d)
        try:
            for e in os.scandir(d):
                if e.is_dir(follow_symlinks=False):
                    stack.append(e.path)
        except OSError:
            pass
    dirs.sort(key=lambda d: -d.count(os.sep))

    maps = {}
    for d in dirs:
        try:
            maps[d] = dirmap(d)
        except OSError:
            pass

    groups = collections.defaultdict(list)
    for d, m in maps.items():
        if m:
            key = tuple(sorted(m.items()))
            groups[key].append(d)

    rows = []
    for key, ds in groups.items():
        if len(ds) < 2:
            continue
        ds.sort()
        nbytes = sum(os.lstat(os.path.join(ds[0], rel)).st_blocks * 512
                     for rel, _ in key)
        rows.append((nbytes * (len(ds) - 1), nbytes, len(key), ds))
    rows.sort(key=lambda r: -r[0])

    with open(".agents/slop/prune4/dircopies.rows", "w") as f:
        f.write("# redundant_bytes\tcopy_bytes\tnfiles\tis_copy_of(n dirs)\n")
        for red, cb, nf, ds in rows:
            f.write(f"{red}\t{cb}\t{nf}\t{len(ds)}\t" + " :: ".join(ds) + "\n")

    tot_red = sum(r[0] for r in rows)
    print(f"dirs_scanned={len(maps)} identical-map_groups={len(rows)} "
          f"redundant_bytes={tot_red} ({tot_red/1048576:.2f} MB)")
    for red, cb, nf, ds in rows[:25]:
        print(f"  {red/1048576:7.3f}MB  {nf:>4} files x{len(ds):<3} {ds[0]}")
        for o in ds[1:]:
            print(f"{'':>28}== {o}")


if __name__ == "__main__":
    main()