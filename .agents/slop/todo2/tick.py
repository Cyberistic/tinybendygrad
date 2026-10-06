#!/usr/bin/env python
"""Tick a task in .agents/TODO.md by STABLE ID, not by line number.

  .venv/bin/python .agents/slop/todo2/tick.py <id> [--check|--uncheck] [--write]

Resolves the id via tasks.idx.tsv to (section-slug, text), re-reads TODO.md,
finds the UNIQUE matching task line, and replaces only its checkbox. Default is
a dry run; --write mutates. Aborts if the match is not unique or if the file
changed between read and write (the race the seven contending units hit).
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TODO = REPO / ".agents" / "TODO.md"
IDX = REPO / ".agents" / "slop" / "todo2" / "tasks.idx.tsv"

HEAD = re.compile(r"^(#{1,6})\s+(.*)$")
CK = re.compile(r"^(\s*[-*]\s*)\[([ xX~])\]\s?(.*)$")


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower())


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:48] or "root"


def section_at(lines: list[str]) -> list[str]:
    out, cur = [], "root"
    for ln in lines:
        m = HEAD.match(ln)
        if m and len(m.group(1)) <= 2:
            cur = slug(m.group(2).strip())
        out.append(cur)
    return out


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    flags = {a for a in argv if a.startswith("--")}
    if len(args) != 1:
        print(__doc__)
        return 64
    want = "x" if "--check" in flags else (" " if "--uncheck" in flags else None)
    if want is None:
        print("pass --check or --uncheck")
        return 64
    ident = args[0]

    row = None
    for ln in IDX.read_text().splitlines()[1:]:
        f = ln.split("\t")
        if f and f[0] == ident:
            row = f
            break
    if row is None:
        print(f"id {ident} not in index")
        return 1
    _, _, _, sec_slug, text = row[0], row[1], row[2], row[3], row[4]

    raw = TODO.read_bytes()
    before = hashlib.sha256(raw).hexdigest()
    lines = raw.decode().split("\n")
    secs = section_at(lines)
    hits = [
        (i, m) for i, ln in enumerate(lines)
        for m in [CK.match(ln)]
        if m and secs[i] == sec_slug and norm(m.group(3)) == norm(text)
    ]
    if len(hits) != 1:
        print(f"refusing: {len(hits)} matches for {ident} in section {sec_slug!r}")
        return 3
    i, m = hits[0]
    old_state = m.group(2)
    lines[i] = f"{m.group(1)}[{want}]{' ' if text else ''}{m.group(3)}"
    print(f"line {i+1}: [{old_state}] -> [{want}]  {text[:70]}")

    if "--write" not in flags:
        print("dry run (pass --write to commit the line replace)")
        return 0
    if hashlib.sha256(TODO.read_bytes()).hexdigest() != before:
        print("RACE: file changed between read and write; re-run")
        return 2
    TODO.write_text("\n".join(lines))
    print(f"wrote: {before[:12]} -> {hashlib.sha256(TODO.read_bytes()).hexdigest()[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
