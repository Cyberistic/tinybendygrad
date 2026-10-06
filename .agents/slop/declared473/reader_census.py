#!/usr/bin/env python3
"""Reader census over the 473 DECLARED-NAME files.

A READER is a git-tracked CODE file (readers.py's CODE_EXT) whose bytes name the target
by FULL repo-relative path (strong) or by BASENAME only (weak, may point elsewhere).
CITATION artifacts (.md/.json/.tsv/...) are not readers.
"""
import json
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CODE_EXT = (".py", ".sh", ".bash", ".mjs", ".js", ".cjs", ".ts", ".bend")
NAME_RE = re.compile(rb"[\w./\-]+\.txt")


def main():
    d = json.load(open(os.path.join(ROOT, ".agents/slop/declared473/derived.json")))
    targets = d["refused"]
    by_base = {}
    for t in targets:
        by_base.setdefault(os.path.basename(t), []).append(t)

    tracked = subprocess.run(["git", "-C", ROOT, "ls-files"],
                             capture_output=True, text=True).stdout.splitlines()
    full = {t: [] for t in targets}
    weak = {t: [] for t in targets}
    for f in tracked:
        if f.endswith(".txt") or not f.endswith(CODE_EXT):
            continue
        p = os.path.join(ROOT, f)
        try:
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        for m in NAME_RE.finditer(data):
            name = m.group(0).decode("utf-8", "replace")
            base = os.path.basename(name)
            if base not in by_base:
                continue
            ln = data[: m.start()].count(b"\n") + 1
            for t in by_base[base]:
                (full if t in name else weak)[t].append(f"{f}:{ln}")

    n_full = sum(1 for t in targets if full[t])
    n_weak = sum(1 for t in targets if weak[t] and not full[t])
    n_none = sum(1 for t in targets if not full[t] and not weak[t])
    print(f"473 named by a committed code reader by FULL PATH  = {n_full}")
    print(f"473 named by BASENAME only (weak)                  = {n_weak}")
    print(f"473 named by NOTHING (only declared())             = {n_none}")
    print("\nsample full-path readers:")
    for t in targets:
        if full[t]:
            print(f"  {t}\n      <- {full[t][0]}")
            break
    json.dump({"full": {k: v for k, v in full.items() if v},
               "weak": {k: v for k, v in weak.items() if v and not full.get(k)}},
              open(os.path.join(ROOT, ".agents/slop/declared473/readers.json"), "w"), indent=1)


main()
