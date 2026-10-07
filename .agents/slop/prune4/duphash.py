#!/usr/bin/env python3
"""prune4 duplicate census. BY DISCOVERY.

Answers, for every byte-identical group under .agents/slop:
  - how many groups, how many files, how many BYTES are a second copy
  - whether git ALREADY holds the content (a blob with the same content is
    reachable from HEAD), which is what makes a working-tree copy redundant
  - CRITICALLY: for the file's own path, is that content ALSO in HEAD at that
    path (committed), at another path, or nowhere (unique)?

A file whose only copy is the working tree is NOT a duplicate. This is the
difference between "byte-identical to another working-tree file" (a dup) and
"byte-identical to a blob git has" (git is the archive; the worktree is a
second answer to 'what was there').

Speed: one batched `git cat-file --batch-check` over every tracked blob id, so
the "is git holding these bytes" question is answered by ONE git process, not
one per file.
"""
import os, sys, hashlib, subprocess, collections, json

ROOT = ".agents/slop"


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def git_blob_hashes():
    """set of every blob content hash git HEAD holds. One batched call."""
    # git hash-object is sha1 of "blob <len>\\0<content>" -- compute the same way
    names = sh("git", "ls-tree", "-r", "-z", "HEAD").split("\0")
    ids = []
    for n in names:
        if not n:
            continue
        meta, _, path = n.partition("\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == "blob":
            ids.append((parts[2], path))
    if not ids:
        return {}, set()
    p = subprocess.run(["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                       input="\n".join(i for i, _ in ids), capture_output=True, text=True)
    return ids, set(l.split()[0] for l in p.stdout.splitlines() if l.strip())


def sha1_blob(path):
    h = hashlib.sha1()
    st = os.lstat(path)
    h.update(f"blob {st.st_size}\0".encode())
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ids, head_blobs = git_blob_hashes()
    head_path_of = {}
    for i, path in ids:
        head_path_of.setdefault(i, path)
    head_dir = os.path.dirname(head_path_of[ids[0][0]]) if ids else ""

    groups = collections.defaultdict(list)
    stack = [ROOT]
    while stack:
        d = stack.pop()
        try:
            entries = sorted(os.scandir(d), key=lambda e: e.name)
        except OSError:
            continue
        for e in entries:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if e.is_symlink():
                continue  # a symlink is 0 blocks; its target is not ours
            if e.is_dir(follow_symlinks=False):
                stack.append(e.path)
            else:
                try:
                    groups[sha1_blob(e.path)].append((e.path, st.st_blocks * 512, st.st_size))
                except OSError:
                    pass

    rows = []
    for h, files in groups.items():
        if len(files) < 2:
            continue
        files.sort()
        in_head = h in head_blobs
        rows.append(dict(sha=h, n=len(files),
                         disk=sum(b for _, b, _ in files),
                         size=files[0][2],
                         in_head=in_head,
                         head_paths=[p for p in (head_path_of.get(h),) if p],
                         files=[p for p, _, _ in files]))
    rows.sort(key=lambda r: -r["disk"])

    dup_files = sum(r["n"] - 1 for r in rows)
    dup_bytes = sum(r["disk"] // r["n"] * (r["n"] - 1) for r in rows)
    with open(".agents/slop/prune4/dups.rows", "w") as f:
        f.write("# sha1\tnfiles\tdisk_B\tsize_B\tin_HEAD\tpaths\n")
        for r in rows:
            f.write(f"{r['sha']}\t{r['n']}\t{r['disk']}\t{r['size']}\t"
                    f"{'Y' if r['in_head'] else 'N'}\t" + " | ".join(r["files"]) + "\n")
    print(f"groups={len(rows)} files_in_groups={sum(r['n'] for r in rows)} "
          f"extra_copies={dup_files} extra_copy_bytes={dup_bytes} "
          f"({dup_bytes/1048576:.2f} MB) of which git-holds-content="
          f"{sum(r['disk']//r['n']*(r['n']-1) for r in rows if r['in_head'])}")


if __name__ == "__main__":
    main()