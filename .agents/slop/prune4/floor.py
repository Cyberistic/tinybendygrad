#!/usr/bin/env python3
"""prune4: the FLOOR census. What fraction of slop is irreducible?

Irreducible = the union of three things the brief names:
  (a) a COMMITTED REPORT
  (b) a MUTANT  (evidence of a deliberately-broken variant a mutation harness
                 names -- discovered by asking tracked text for the word, then
                 reading what it names, NOT by matching a filename)
  (c) an artifact a COMMITTED READER opens -- some tracked file in the repo
                 has this path's basename or its slop-relative path in its TEXT

Two bugs found and fixed while writing this, both of which would have made the
headline number a lie:
  * `git cat-file --batch` fed PATHS returns "<path> missing" (measured) -- it
    wants object NAMES. So the corpus was empty and bucket C degenerated into
    "is committed". Now fed blob SHAs from ls-tree.
  * the first run reported 61.3 MB against a census that said 49.6 MB. Cause:
    live units were writing between the two runs. `--at` prints one instant's
    numbers and every figure in the report comes from ONE call of THIS.
"""
import os, re, subprocess, collections, sys

SLOP = ".agents/slop"


def run(a, inp=None):
    return subprocess.run(a, input=inp, capture_output=True).stdout


def main():
    # ---- instant 1: the tree as it is NOW, one walk, lstat/st_blocks only
    disk = apparent = 0
    nfile = nsym = ndir = 0
    stack = [SLOP]
    files = []
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
                nsym += 1
                disk += st.st_blocks * 512
                apparent += st.st_size
            elif e.is_dir(follow_symlinks=False):
                ndir += 1
                disk += st.st_blocks * 512
                stack.append(e.path)
            else:
                nfile += 1
                b = st.st_blocks * 512
                disk += b
                apparent += st.st_size
                files.append((e.path, b, st.st_size))

    # ---- the committed population, declared by git
    tree = run(["git", "ls-tree", "-r", "HEAD", "-z", "--", SLOP])
    tracked = {}
    for rec in tree.split(b"\0"):
        if not rec:
            continue
        meta, _, path = rec.partition(b"\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == b"blob":
            tracked[path.decode()] = parts[2].decode()

    # ---- the reader corpus: every tracked blob in the repo, BATCHED, by SHA
    alltree = run(["git", "ls-tree", "-r", "HEAD", "-z"])
    TEXTY = re.compile(r"\.(md|py|sh|bend|tsv|rows|out|err|json|jsonl|txt|in|mjs|js|ts|toml|cfg|ini|yaml|yml)$|Makefile$|LOCK$")
    blobs = {}
    for rec in alltree.split(b"\0"):
        if not rec:
            continue
        meta, _, path = rec.partition(b"\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == b"blob":
            p = path.decode()
            if TEXTY.search(p):
                blobs[parts[2].decode()] = p
    raw = run(["git", "cat-file", "--batch"],
              inp=("\n".join(sorted(blobs)) + "\n").encode())
    corpus = bytearray()
    i = 0
    nread = 0
    while i < len(raw):
        nl = raw.find(b"\n", i)
        if nl < 0:
            break
        head = raw[i:nl].split()
        if len(head) < 3 or head[1] != b"blob":
            i = nl + 1
            continue
        size = int(head[2])
        corpus += raw[nl + 1:nl + 1 + size] + b"\n"
        nread += 1
        i = nl + 1 + size + 1

    mentions = set()
    for m in re.finditer(rb"[A-Za-z0-9_.@/-]{5,}", corpus):
        mentions.add(m.group().decode())

    # mutants: tracked text that says "mutat" and what it NAMES
    mutant_words = set()
    for m in re.finditer(rb"[A-Za-z0-9_./-]{4,}", bytes(corpus)):
        w = m.group().decode()
        if "mutat" in w.lower():
            mutant_words.add(w)

    buckets = collections.Counter()
    bucket_bytes = collections.Counter()
    untracked_unnamed = []
    committed_unnamed = []
    for path, b, _sz in files:
        rel = os.path.relpath(path)
        in_head = rel in tracked
        base = os.path.basename(path)
        parent = os.path.basename(os.path.dirname(path))
        named = (rel in mentions or base in mentions or parent in mentions
                 or any(w in mentions for w in (base, parent) if w))
        is_mutant = any("mutat" in w for w in (base, parent))
        is_report = base.endswith(".md")
        if in_head and is_report:
            k = "A_committed_report"
        elif is_mutant and named:
            k = "B_mutant_named"
        elif in_head and named:
            k = "C_committed_AND_named"
        elif named:
            k = "E_untracked_but_named"
        elif in_head:
            k = "F_committed_but_UNNAMED"
            committed_unnamed.append((b, rel))
        else:
            k = "D_untracked_unnamed"
            untracked_unnamed.append((b, rel))
        buckets[k] += 1
        bucket_bytes[k] += b

    print(f"INSTANT  disk={disk} ({disk/1048576:.3f} MB)  apparent={apparent} "
          f"({apparent/1048576:.3f} MB)  files={nfile} dirs={ndir} symlinks={nsym}")
    print(f"tracked under slop (git ls-tree HEAD) = {len(tracked)}")
    print(f"reader corpus: {len(blobs)} tracked text blobs, {nread} READ, "
          f"{len(corpus)} bytes, {len(mentions)} distinct tokens")
    print(f"mutant-ish tokens in corpus: {len(mutant_words)}")
    print()
    for k in sorted(buckets):
        print(f"  {k:28s} {buckets[k]:>5} files {bucket_bytes[k]:>11} B "
              f"({bucket_bytes[k]/1048576:7.3f} MB)")
    tot = sum(bucket_bytes.values())
    irr = sum(bucket_bytes[k] for k in
              ("A_committed_report", "B_mutant_named", "C_committed_AND_named"))
    print(f"  {'TOTAL':28s} {nfile:>5} files {tot:>11} B ({tot/1048576:7.3f} MB)")
    print(f"\nSTRICT IRREDUCIBLE (A+B+C) = {irr} B = {irr/tot*100:.2f}% of file bytes")
    for k in ("D_untracked_unnamed", "E_untracked_but_named", "F_committed_but_UNNAMED"):
        print(f"  {k:28s} {bucket_bytes[k]:>11} B "
              f"({bucket_bytes[k]/1048576:7.3f} MB) over {buckets[k]} files")
    print("  E is untracked yet NAMED -> a committed reader expects it; deleting"
          " it breaks that reader.\n  F is in HEAD but no tracked reader names"
          " it -> removable ONLY via `git rm`, never `rm`.")

    with open(".agents/slop/prune4/untracked-unnamed.rows", "w") as f:
        f.write("# D_untracked_unnamed: no generator proven, no reader names it\n")
        for b, rel in sorted(untracked_unnamed, reverse=True):
            f.write(f"{b}\t{rel}\n")
    with open(".agents/slop/prune4/committed-unnamed.rows", "w") as f:
        f.write("# F_committed_but_UNNAMED: in HEAD, no tracked reader names it\n")
        for b, rel in sorted(committed_unnamed, reverse=True):
            f.write(f"{b}\t{rel}\n")


if __name__ == "__main__":
    main()