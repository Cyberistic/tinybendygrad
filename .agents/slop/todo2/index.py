#!/usr/bin/env python
"""Duplicate-task census + stable-id index generator for .agents/TODO.md.

Population is the file itself, walked by discovery (heading spans + checkbox regex).
No hand lists. Writes: dup.md, tasks.idx.tsv, citations.md, collisions.out
"""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TODO = REPO / ".agents" / "TODO.md"
OUT = REPO / ".agents" / "slop" / "todo2"

HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
CHECKBOX = re.compile(r"^\s*[-*]\s*\[([ xX~])\]\s?(.*)$")


def slug(s: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s[:48] or "root"


def main() -> int:
    text = TODO.read_text()
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]

    # section assignment: each line's nearest level<=2 heading
    section_of = [None] * len(lines)
    cur = "root"
    for i, ln in enumerate(lines):
        m = HEADING.match(ln)
        if m and len(m.group(1)) <= 2:
            cur = m.group(2).strip()
        section_of[i] = cur

    tasks = []  # (lineno, state, text, section)
    for i, ln in enumerate(lines):
        m = CHECKBOX.match(ln)
        if m:
            tasks.append((i + 1, m.group(1).lower(), m.group(2).strip(), section_of[i]))

    # ---- duplicate TASK census -----------------------------------------
    def norm(s: str) -> str:
        return re.sub(r"\s+", " ", s.strip().lower())

    by_text = defaultdict(list)
    for ln, st, tx, sec in tasks:
        by_text[norm(tx)].append((ln, st, sec, tx))
    dups = {k: v for k, v in by_text.items() if len(v) > 1}
    dup_instances = sum(len(v) for v in dups.values())
    # conflicting states: same text, both checked and unchecked somewhere
    conflicting = {
        k: v for k, v in dups.items() if len({st for _, st, _, _ in v}) > 1
    }

    # ---- stable-id index -----------------------------------------------
    seen = Counter()
    rows = []
    collisions = 0
    for ln, st, tx, sec in tasks:
        key = f"{slug(sec)}\x00{norm(tx)}"
        k = seen[key]
        seen[key] += 1
        ident = hashlib.sha1(f"{key}\x00{k}".encode()).hexdigest()[:10]
        rows.append((ident, ln, st, slug(sec), tx.replace("\t", " ")))
    ids = [r[0] for r in rows]
    collisions = len(ids) - len(set(ids))

    with (OUT / "tasks.idx.tsv").open("w") as f:
        f.write("id\tline\tstate\tsection\ttext\n")
        for r in rows:
            f.write("\t".join(str(x) for x in r) + "\n")

    # ---- citation census (paths that pin TODO.md:NNNN) -----------------
    cite = subprocess.run(
        ["grep", "-rn", "-I", "-E", r"TODO\.md:[0-9]+", "."],
        cwd=REPO, capture_output=True, text=True,
    )
    cites = [l for l in cite.stdout.splitlines()
             if not l.startswith("./.agents/TODO.md:") and "/.git/" not in l]

    w = ["# TODO.md duplication + stable-id index", ""]
    w.append("## Duplicate TASK items")
    w.append("")
    w.append("| quantity | value | denominator |")
    w.append("|---|---|---|")
    w.append(f"| task items | {len(tasks)} | file |")
    w.append(f"| distinct task texts (whitespace+case-normalised) | {len(by_text)} | {len(tasks)} items |")
    w.append(f"| duplicated task texts | {len(dups)} | {len(by_text)} distinct |")
    w.append(f"| duplicated task instances | {dup_instances} | {len(tasks)} items |")
    w.append(f"| texts with CONFLICTING states ([ ] and [x]) | {len(conflicting)} | {len(dups)} duplicated |")
    w.append("")
    w.append("### All duplicated task texts")
    w.append("")
    w.append("| xN | states | line(s) | text |")
    w.append("|---|---|---|---|")
    for k, v in sorted(dups.items(), key=lambda kv: -len(kv[1])):
        states = ",".join(sorted({st for _, st, _, _ in v}))
        lns = ",".join(str(x[0]) for x in v)
        show = v[0][3] if len(v[0][3]) <= 90 else v[0][3][:87] + "..."
        w.append(f"| {len(v)} | `{states}` | {lns} | {show} |")
    w.append("")
    w.append("## Stable-id index")
    w.append("")
    w.append(f"- ids generated: {len(ids)}; distinct: {len(set(ids))}; collisions: **{collisions}**.")
    w.append("- id = `sha1(section-slug + NUL + normalised text + NUL + occurrence)[:10]`, so it is "
             "stable across LINE MOVES and unique within a section.")
    w.append(f"- written to `.agents/slop/todo2/tasks.idx.tsv` ({len(rows)} rows).")
    w.append("")
    w.append("## External `file:line` citations INTO TODO.md (they pin line numbers)")
    w.append("")
    w.append(f"Found **{len(cites)}** citation lines in tracked files outside TODO.md itself:")
    w.append("")
    w.append("```")
    for c in cites[:40]:
        w.append(c)
    if len(cites) > 40:
        w.append(f"... and {len(cites)-40} more")
    w.append("```")
    (OUT / "dup.md").write_text("\n".join(w) + "\n")
    (OUT / "collisions.out").write_text(f"collisions={collisions} ids={len(ids)}\n")

    print(f"tasks={len(tasks)} distinct_text={len(by_text)} dup_texts={len(dups)} dup_instances={dup_instances} conflicting={len(conflicting)}")
    print(f"ids={len(ids)} collisions={collisions}")
    print(f"external_TODO_line_citations={len(cites)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
