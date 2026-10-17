#!/usr/bin/env python3
"""READ-ONLY. Locate the 1-token difference between census.py's cited set and my per-line union.

census.py:423 applies BACKTICK to the WHOLE blob; split.py applies it per LINE.  Both are
`([^`\\n]+)` so the two SHOULD agree, and they disagree by exactly one token.  This finds which
token, and in which document, so the discrepancy is a measured fact rather than a shrug.

Two `git cat-file --batch` passes over the committed .md, one process, one line of output.
"""
from __future__ import annotations

import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
BACKTICK = re.compile(r"`([^`\n]+)`")
TOKEN = re.compile(r"[\w.+-]*\.[A-Za-z0-9]+")


def git(*args: str, stdin: bytes = b"") -> bytes:
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    return subprocess.run(["git", "-C", ROOT, *args], input=stdin, capture_output=True, env=env,
                          check=True).stdout


def texts(pairs):
    raw = git("cat-file", "--batch", stdin=("\n".join(h for _, h in pairs) + "\n").encode())
    i = 0
    for path, _ in pairs:
        j = raw.index(b"\n", i)
        size = int(raw[i:j].split()[2])
        yield path, raw[j + 1:j + 1 + size].decode("utf-8", "replace")
        i = j + 1 + size + 1


md = [(l.split("\t", 1)[1], l.split("\t", 1)[0].split()[2]) for l in git("ls-tree", "-r", "HEAD").decode().splitlines()
      if l.split("\t", 1)[1].endswith(".md")]


def keep(t: str) -> bool:
    return "/" not in t and TOKEN.fullmatch(t) is not None


whole: set[str] = set()
perline: set[str] = set()
where: dict[str, list[str]] = {}
for path, text in texts(md):
    for t in BACKTICK.findall(text):
        if keep(t):
            whole.add(t)
    for n, line in enumerate(text.split("\n"), 1):
        for t in BACKTICK.findall(line):
            if keep(t):
                perline.add(t)
                where.setdefault(t, []).append(f"{path}:{n}")

print(f"whole-text set (census.py:423) : {len(whole)}")
print(f"per-line set  (split.py)      : {len(perline)}")
print(f"in per-line only  : {sorted(perline - whole)}")
print(f"in whole-text only: {sorted(whole - perline)}")
for t in sorted(perline - whole)[:5]:
    print(f"  first citing line of {t!r}: {where[t][0]}")