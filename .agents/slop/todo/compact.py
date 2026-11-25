#!/usr/bin/env python3
"""compact.py -- rewrite .agents/TODO.md as a board, archive the prose verbatim.

    .venv/bin/python .agents/slop/todo/compact.py [--write]

Reading is default; `--write` replaces .agents/TODO.md and writes the archive.

A block is one task line (`name [bar] n/m …`) plus the indented lines under it.
Closed categories collapse to a table row. Open ones keep the head of their block,
and the whole original survives at .agents/slop/todo-archive-<date>.md, because a
compaction that loses the evidence is a deletion with extra steps.
"""
import re
import shutil
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TODO = ROOT / ".agents/TODO.md"
ARCHIVE = ROOT / f".agents/slop/todo-archive-{date.today():%Y%m%d}.md"
TASK = re.compile(r"^(\S+)\s+\[([#.]+)\]\s+(\d+)(?:/(\d+))?\s*(.*)$")
OPEN_LINES = 14


def blocks(lines):
    start = next(i for i, l in enumerate(lines) if TASK.match(l))
    header, found = lines[:start], []
    for i in range(start, len(lines)):
        m = TASK.match(lines[i])
        if m:
            found.append({"m": m, "body": [lines[i]]})
        else:
            found[-1]["body"].append(lines[i])
    return header, found


def status_of(b, m):
    inline = m.group(5).strip()
    if inline:
        return inline
    for line in b["body"][1:]:
        if line.strip():
            return line.strip()
    return ""


def main():
    lines = TODO.read_text().split("\n")
    header, found = blocks(lines)
    rows = []
    for b in found:
        m = b["m"]
        done = int(m.group(3))
        total = int(m.group(4)) if m.group(4) else done
        rows.append({
            "name": m.group(1), "bar": m.group(2), "done": done, "total": total,
            "status": status_of(b, m), "body": b["body"],
        })
    open_rows = [r for r in rows if r["done"] < r["total"]]
    closed = [r for r in rows if r["done"] >= r["total"]]

    def esc(s):
        return s.replace("|", "\\|")

    def cut(s, n):
        return s if len(s) <= n else s[: n - 1].rstrip() + "…"

    out = [
        "# TODO",
        "",
        f"`{len(rows)}` categories: **{len(open_rows)} open**, {len(closed)} closed.",
        "The full history is `.agents/slop/"
        f"{ARCHIVE.name}` — this file is the board, that file is the evidence.",
        "",
        "Closed categories keep one row and no prose. Open ones keep the head of their block.",
        "",
        "## Open",
        "",
        "| category | bar | done | status |",
        "|---|---|---|---|",
    ]
    for r in open_rows:
        out.append(f"| `{r['name']}` | `[{r['bar']}]` | {r['done']}/{r['total']} "
                   f"| {esc(cut(r['status'], 110))} |")
    out += ["", "## Closed", "", "| category | done | status |", "|---|---|---|"]
    for r in closed:
        out.append(f"| `{r['name']}` | {r['done']}/{r['total']} "
                   f"| {esc(cut(r['status'], 90))} |")

    out += ["", "---", "", "## Open categories, in full", ""]
    for r in open_rows:
        body = r["body"]
        out.append(f"### {r['name']}  `[{r['bar']}]` {r['done']}/{r['total']}")
        out.append("")
        kept = body[:OPEN_LINES]
        out += [l.rstrip() for l in kept]
        if len(body) > OPEN_LINES:
            out.append("")
            out.append(f"*…{len(body) - OPEN_LINES} more lines in the archive.*")
        out.append("")

    text = "\n".join(out).rstrip() + "\n"
    print(f"categories {len(rows)}  open {len(open_rows)}  closed {len(closed)}")
    print(f"lines {len(lines)} -> {len(text.splitlines())}")
    missing = [r["name"] for r in rows if f"`{r['name']}`" not in text]
    if missing:
        print("MISSING:", missing)
        return 1
    if "--write" in sys.argv:
        shutil.copyfile(TODO, ARCHIVE)
        TODO.write_text(text)
        print(f"wrote {TODO} and {ARCHIVE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
