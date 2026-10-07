#!/usr/bin/env python3
"""prune4 final table: the 12 biggest unit dirs, LIVE-flagged, with the biggest
files inside each and a CLASS per file.

The class is NOT a name shape. It is decided by, in order:
  LIVE            -- owner dir written within COLD_MIN: a running unit's scratch.
                     Excluded from every verdict.
  COMMIT-REPORT   -- in HEAD and a *.md. The audit record.
  COMMIT-EVIDENCE -- in HEAD, not a report. Committed; removable only by an
                     orchestrator `git rm`, and only if no reader needs it.
  BUILD-PRODUCT   -- untracked + gitignored + committed sibling generator.
  ORPHAN          -- untracked, no reader names it, content NOT reachable from
                     any ref. The only class whose deletion is irreversible.
  COPY-OF-GIT     -- untracked, content byte-identical to a blob some ref
                     reaches. git is the archive; the worktree is a 2nd answer.
  EVIDENCE-DUP    -- byte-identical to another LIVE file, and the duplicates are
                     the measurement (ledger: spine/ 8, rerun/ 7). KEEP.
"""
import os, time, subprocess, hashlib, collections, sys

SLOP = ".agents/slop"
COLD_MIN = 120.0


def sh(*a, inp=None):
    return subprocess.run(a, input=inp, capture_output=True).stdout


def main():
    tracked = {p for p in sh("git", "ls-tree", "-r", "HEAD", "--name-only",
                             "-z", "--", SLOP).decode().split("\0") if p}
    # every blob some ref reaches, one batch
    raw = sh("git", "rev-list", "--objects", "--all")
    oid2 = {}
    for line in raw.decode(errors="replace").splitlines():
        p = line.split(" ", 1)
        oid2.setdefault(p[0], p[1] if len(p) > 1 else None)
    ids = list(oid2)
    live_blobs = {l.split()[0] for l in
                  sh("git", "cat-file", "--batch-check=%(objectname) %(objecttype)",
                     inp=("\n".join(ids) + "\n").encode()).decode().splitlines()
                  if l.endswith(" blob")}

    # content hash of every regular file under slop, for the dup evidence test
    sig = {}
    stack = [SLOP]
    while stack:
        d = stack.pop()
        try:
            es = os.scandir(d)
        except OSError:
            continue
        for e in es:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if e.is_dir(follow_symlinks=False):
                stack.append(e.path)
            elif not e.is_symlink():
                b = open(e.path, "rb").read()
                sig[e.path] = (hashlib.sha1(f"blob {len(b)}\0".encode() + b)
                               .hexdigest(), st.st_blocks * 512, st.st_size)
    dupcount = collections.Counter(h for h, _b, _s in sig.values())

    now = time.time()
    units = []
    for e in sorted(os.scandir(SLOP), key=lambda x: x.name):
        if not e.is_dir(follow_symlinks=False):
            continue
        disk = n = 0
        newest = 0.0
        files = []
        st2 = [e.path]
        while st2:
            d = st2.pop()
            try:
                es = os.scandir(d)
            except OSError:
                continue
            for x in es:
                try:
                    s = x.stat(follow_symlinks=False)
                except OSError:
                    continue
                newest = max(newest, s.st_mtime)
                if x.is_dir(follow_symlinks=False):
                    st2.append(x.path)
                elif not x.is_symlink():
                    disk += s.st_blocks * 512
                    n += 1
                    files.append(x.path)
        units.append((disk, e.name, n, (now - newest) / 60.0, files))
    units.sort(reverse=True)

    print(f"{'MB':>7} {'files':>5} {'cold_min':>8}  unit")
    for disk, name, n, cold, files in units[:12]:
        tag = "LIVE" if cold <= COLD_MIN else "cold"
        print(f"{disk/1048576:7.3f} {n:5d} {cold:8.0f}  {name}  [{tag}]")
        top = sorted(files, key=lambda p: -sig[p][1])[:4]
        for p in top:
            h, b, _sz = sig[p]
            rel = os.path.relpath(p)
            inhead = rel in tracked
            ncopies = dupcount[h]
            if cold <= COLD_MIN:
                cls = "LIVE"
            elif inhead and os.path.basename(p).endswith(".md"):
                cls = "COMMIT-REPORT"
            elif inhead:
                cls = "COMMIT-EVIDENCE"
            elif h in live_blobs:
                cls = "COPY-OF-GIT"
            elif ncopies > 1:
                cls = "EVIDENCE-DUP"
            else:
                cls = "ORPHAN"
            print(f"       {b:>9} {b and b/1024:>8.0f}K  {cls:<15} {rel}"
                  + (f"  (x{ncopies} identical)" if ncopies > 1 else ""))
    tot = sum(u[0] for u in units)
    liveb = sum(u[0] for u in units if u[3] <= COLD_MIN)
    print(f"\n12 dirs = {sum(u[0] for u in units[:12])/1048576:.2f} MB of "
          f"{tot/1048576:.2f} MB total ({len(units)} unit dirs)")
    print(f"LIVE units hold {liveb/1048576:.2f} MB ({liveb/tot*100:.1f}%) -- "
          f"EXCLUDED from every verdict above")


if __name__ == "__main__":
    main()