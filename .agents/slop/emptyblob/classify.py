#!/usr/bin/env python3
"""Classify every index entry whose blob is git's EMPTY BLOB.

`git ls-files -s` conflates three states under e69de29..., so the walk alone is
NOT a population. Disambiguators:
  - `git diff --cached --name-only`  -> paths with staged CONTENT
  - `git ls-tree -r HEAD`            -> paths committed in HEAD (and their blob)
An empty-blob index entry is:
  HEAD-EMPTY          committed in HEAD at the empty blob (a real tracked empty file)
  STAGED-EMPTY        staged with content (git diff --cached names it) but empty content
  INTENT-TO-ADD       neither -> `git add -N` placeholder; zeroes in porcelain v2
"""
import subprocess, json, os, datetime

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"

def git(*args, check=True):
    return subprocess.run(["git", "-C", REPO, *args],
                          capture_output=True, text=True, check=check)

def main():
    head_sha = git("rev-parse", "HEAD").stdout.strip()
    # index
    idx = {}
    for line in git("ls-files", "-s").stdout.splitlines():
        if "\t" not in line: continue
        meta, path = line.split("\t", 1)
        mode, sha, stage = meta.split()[:3]
        idx[path] = {"path": path, "mode": mode, "sha": sha, "stage": stage}
    # HEAD tree
    head = {}
    for line in git("ls-tree", "-r", "HEAD").stdout.splitlines():
        meta, path = line.split("\t", 1)
        mode, sha = meta.split()[0], meta.split()[2]
        head[path] = {"mode": mode, "sha": sha}
    # staged content
    staged = set(git("diff", "--cached", "--name-only").stdout.splitlines())

    empty_idx = [r for r in idx.values() if r["sha"] == EMPTY]
    rows = []
    for r in empty_idx:
        p = r["path"]
        if p in head:
            cls = "HEAD-EMPTY" if head[p]["sha"] == EMPTY else "HEAD-NONEMPTY"
        elif p in staged:
            cls = "STAGED-EMPTY"
        else:
            cls = "INTENT-TO-ADD"
        disk = os.path.join(REPO, p)
        if os.path.exists(disk):
            try: dbytes = os.path.getsize(disk)
            except OSError: dbytes = -1
        else:
            dbytes = None  # missing on disk
        head_sha_p = head.get(p, {}).get("sha")
        r2 = dict(r, cls=cls, disk_bytes=dbytes, head_sha=head_sha_p)
        rows.append(r2)

    head_empty = [r for r in rows if r["cls"] == "HEAD-EMPTY"]
    from collections import Counter
    counts = Counter(r["cls"] for r in rows)
    summary = {
        "generated": datetime.datetime.now().isoformat(),
        "head": head_sha,
        "index_total": len(idx),
        "head_total": len(head),
        "index_empty_blob": len(rows),
        "head_empty_blob": sum(1 for v in head.values() if v["sha"] == EMPTY),
        "class_counts": dict(counts),
        "head_empty_ondisk_zero": sum(1 for r in head_empty if r["disk_bytes"] == 0),
        "head_empty_ondisk_nonzero": sum(1 for r in head_empty if r["disk_bytes"] not in (0, None)),
        "head_empty_ondisk_missing": sum(1 for r in head_empty if r["disk_bytes"] is None),
    }
    print(json.dumps(summary, indent=2))
    json.dump({"summary": summary, "rows": rows}, open(os.path.join(REPO, ".agents/slop/emptyblob/classified.json"), "w"), indent=2)

if __name__ == "__main__":
    main()
