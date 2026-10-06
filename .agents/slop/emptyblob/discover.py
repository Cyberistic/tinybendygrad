#!/usr/bin/env python3
"""Discover tracked paths at git's EMPTY BLOB by walking `git ls-files -s`.

Field layout: `<mode> <sha> <stage>\t<path>`.
  field[0] = MODE  (100644 / 100755 / 120000 / 160000)
  field[1] = SHA   (the blob/tree/commit hash)  <- this is the one we compare
  field[2] = STAGE
  field[3] = PATH
Population is git's OWN declaration (`git ls-files -s`), not a glob or a name list.
"""
import subprocess, json, sys, os, datetime

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"

def git(*args, check=True):
    return subprocess.run(["git", "-C", REPO, *args],
                          capture_output=True, text=True, check=check)

def walk_ls_files():
    """Return list of dicts for every path in the index."""
    out = git("ls-files", "-s").stdout
    rows = []
    for line in out.splitlines():
        if "\t" not in line:
            continue
        meta, path = line.split("\t", 1)
        parts = meta.split()
        mode, sha, stage = parts[0], parts[1], parts[2]
        rows.append({"path": path, "mode": mode, "sha": sha, "stage": stage})
    return rows

def head_blob_from_ls_tree():
    """HEAD's version of the tree, for comparison against the index."""
    r = git("ls-tree", "-r", "HEAD")
    rows = {}
    for line in r.stdout.splitlines():
        meta, path = line.split("\t", 1)
        mode, sha = meta.split()[0], meta.split()[2]
        rows[path] = {"mode": mode, "sha": sha}
    return rows

def main():
    rows = walk_ls_files()
    head = head_blob_from_ls_tree()
    empty_rows = [r for r in rows if r["sha"] == EMPTY]
    # which of the empty ones are ALSO empty in HEAD?
    for r in empty_rows:
        r["head_sha"] = head.get(r["path"], {}).get("sha")
        r["head_empty"] = (r["head_sha"] == EMPTY)
        r["in_head"] = r["path"] in head
    summary = {
        "generated": datetime.datetime.now().isoformat(),
        "head": git("rev-parse", "HEAD").stdout.strip(),
        "total_tracked": len(rows),
        "empty_blob_count": len(empty_rows),
        "head_total": len(head),
        "staged_additions": sum(1 for r in rows if r["path"] not in head),
        "empty_in_head_and_index": sum(1 for r in empty_rows if r["head_empty"]),
        "empty_index_only": sum(1 for r in empty_rows if not r["head_empty"]),
    }
    print(json.dumps(summary, indent=2))
    with open(os.path.join(REPO, ".agents/slop/emptyblob/summary.json"), "w") as f:
        json.dump({"summary": summary, "empty": empty_rows, "all": rows}, f, indent=2)

if __name__ == "__main__":
    main()
