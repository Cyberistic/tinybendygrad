#!/usr/bin/env python3
"""prune4: is a retirement directory a MOVE or a COPY? and is git the archive?

Two independent questions, answered by git, never by a name shape:

  MOVE-vs-COPY  For every file in the retirement dir, does its byte-identical
                twin still exist AT THE ORIGINAL PATH? If yes -> COPY (two
                working-tree answers). If no -> MOVE (this is the only worktree
                copy, and deleting it deletes the worktree's last answer).

  GIT-HOLDS     Does any commit reachable from HEAD contain a blob with this
                content? git IS the archive; if yes the bytes survive `rm`.

git ls-tree -r HEAD, NOT git ls-files: the index was reset (measured - see
REPORT.md), so ls-files reports committed files as untracked. An instrument
that reads a reset index reports the tree as smaller than it is.
"""
import os, sys, hashlib, subprocess, collections

SLOP = ".agents/slop"


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def all_history_blob_hashes():
    """Every blob hash in EVERY ref. git is the archive, measured not assumed."""
    out = sh("git", "rev-list", "--objects", "--all")
    ids = set()
    for line in out.splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2 or (parts and parts[0]):
            ids.add(parts[0])
    p = subprocess.run(["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                       input="\n".join(sorted(ids)), capture_output=True, text=True)
    return {l.split()[0] for l in p.stdout.splitlines()
            if l.strip().endswith(" blob")}, ids


def sha1_blob(path):
    st = os.lstat(path)
    h = hashlib.sha1()
    h.update(f"blob {st.st_size}\0".encode())
    with open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def index_content(path):
    """sha1 of the INDEX entry for this path (what is currently staged)."""
    return subprocess.run(["git", "rev-parse", f":{path}"],
                          capture_output=True, text=True).stdout.strip() or None


def analyse(retired, other_root):
    hist_blobs, _ = all_history_blob_hashes()
    rows = []
    for dirpath, _dn, filenames in os.walk(retired):
        for fn in sorted(filenames):
            p = os.path.join(dirpath, fn)
            if os.path.islink(p):
                continue
            rel = os.path.relpath(p, retired)
            h = sha1_blob(p)
            twin = os.path.join(other_root, rel)
            copy = os.path.exists(twin) and sha1_blob(twin) == h
            rows.append(dict(path=p, rel=rel, sha=h,
                             size=os.lstat(p).st_blocks * 512,
                             head_sha=index_content(p) if False else
                             sh("git", "rev-parse", "--verify", "--quiet",
                                f"HEAD:{p}").strip() or None,
                             in_history=h in hist_blobs,
                             copy_at_other=copy, twin=twin if copy else None))
    return rows


if __name__ == "__main__":
    retired = sys.argv[1] if len(sys.argv) > 1 else f"{SLOP}/orcdecide/retired"
    other = sys.argv[2] if len(sys.argv) > 2 else f"{SLOP}/oracles259"
    rows = analyse(retired, other)
    tot = sum(r["size"] for r in rows)
    print(f"{len(rows)} files, {tot} B ({tot/1048576:.3f} MB) in {retired}")
    print(f"  content in SOME commit (git is the archive): "
          f"{sum(1 for r in rows if r['in_history'])}/{len(rows)}")
    print(f"  committed at THIS path in HEAD            : "
          f"{sum(1 for r in rows if r['head_sha'])}/{len(rows)}")
    print(f"  byte-identical twin still at {other}/<rel>: "
          f"{sum(1 for r in rows if r['copy_at_other'])}/{len(rows)}  "
          f"-> {'COPY (two worktree answers)' if any(r['copy_at_other'] for r in rows) else 'MOVE (original is gone)'}")
    with open(".agents/slop/prune4/move-or-copy.rows", "w") as f:
        f.write("# path\tsize_B\tsha1\tin_any_commit\tin_HEAD\tcopy_at_other\ttwin\n")
        for r in rows:
            f.write(f"{r['path']}\t{r['size']}\t{r['sha'][:12]}\t"
                    f"{'Y' if r['in_history'] else 'N'}\t"
                    f"{'Y' if r['head_sha'] else 'N'}\t"
                    f"{'Y' if r['copy_at_other'] else 'N'}\t{r['twin'] or ''}\n")
    for r in rows:
        if not r["copy_at_other"]:
            pass