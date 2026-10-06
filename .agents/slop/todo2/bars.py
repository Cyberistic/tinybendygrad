#!/usr/bin/env python
"""Generate COMPUTED progress bars (one per category) and append them to .agents/TODO.md.

Category = a level-2 `##` heading span (the file's OWN partition, found by discovery).
Counts come from the checkbox regex, never typed. Appends at EOF so no existing line moves
(the file is pinned by 303 external `file:line` citations). Idempotent via a marker.
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TODO = REPO / ".agents" / "TODO.md"
OUT = REPO / ".agents" / "slop" / "todo2"
MARKER = "<!-- GENERATED-PROGRESS-BARS by .agents/slop/todo2/bars.py; do not hand-edit -->"

HEAD = re.compile(r"^(#{1,6})\s+(.*)$")
CK = re.compile(r"^\s*[-*]\s*\[([ xX~])\]\s?(.*)$")
FULL, EMPTY = "\u2588", "\u2591"


def bar(done: int, total: int) -> str:
    if total == 0:
        return "".join(EMPTY for _ in range(10))
    filled = round(10 * done / total)
    return FULL * filled + EMPTY * (10 - filled)


def collect(lines: list[str]):
    """Return (overall, [(title, done, total, tilde)]) for level<=2 heading spans.

    Headings inside fenced code blocks are not sections.
    """
    order = []
    spans = {}
    in_fence = False
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEAD.match(ln)
        if m and len(m.group(1)) <= 2:
            key = (i, m.group(2).strip())
            order.append(key)
            spans[key] = [0, 0, 0]
    # attribute each checkbox to the nearest preceding level<=2 heading
    in_fence = False
    cur = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEAD.match(ln)
        if m and len(m.group(1)) <= 2:
            cur = (i, m.group(2).strip())
        m2 = CK.match(ln)
        if m2 and cur is not None:
            spans[cur][0] += 1
            if m2.group(1).lower() == "x":
                spans[cur][1] += 1
            elif m2.group(1) == "~":
                spans[cur][2] += 1
    rows = []
    for key in order:
        tot, done, tilde = spans[key]
        rows.append((key[1], done, tot, tilde))
    overall = (sum(r[1] for r in rows), sum(r[2] for r in rows), sum(r[3] for r in rows))
    return overall, rows


def main() -> int:
    raw = TODO.read_bytes()
    before = hashlib.sha256(raw).hexdigest()
    text = raw.decode()
    # exclude any previously generated block from the category population
    base = text.split(MARKER)[0]
    lines = base.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]

    overall, rows = collect(lines)
    with_items = [r for r in rows if r[2] > 0]

    def line_for(title: str, done: int, total: int, tilde: int) -> str:
        pct = f"{100*done/total:3.0f}%" if total else "  --"
        note = f"  (+{tilde} [~])" if tilde else ""
        t = title.replace("`", "") if len(title) <= 72 else title[:69].replace("`", "") + "..."
        return f"\u2022 {t} \u2014 {bar(done,total)} {done}/{total} {pct}{note}"

    body = [MARKER, "", "## Progress by category (GENERATED from checkbox counts)", ""]
    od, ot, otil = overall
    body.append(f"**OVERALL** \u2014 {bar(od,ot)} {od}/{ot} {100*od/ot:.1f}%"
                + (f"  (+{otil} `[~]`)" if otil else ""))
    body.append("")
    body.append(f"Category = each level<=2 (`#`/`##`) heading, found by discovery; "
                f"{len(with_items)} of {len(rows)} sections carry tasks.")
    body.append("")
    for title, done, total, tilde in with_items:
        body.append(line_for(title, done, total, tilde))
    block = "\n".join(body) + "\n"

    (OUT / "dashboard.md").write_text("# Computed progress bars\n\n" + block)

    # --- concurrency: append-only, cannot clobber existing bytes, but still
    # --- verify no writer changed the file since we derived the block.
    raw2 = TODO.read_bytes()
    if hashlib.sha256(raw2).hexdigest() != before:
        print(f"RACE: TODO.md changed between read and write "
              f"({before[:12]} -> {hashlib.sha256(raw2).hexdigest()[:12]}); re-read, re-run.")
        return 2
    if MARKER in text:
        # regenerate: drop the previous generated block (it is the file tail) and re-append
        head = text[: text.index(MARKER)].rstrip("\n")
        TODO.write_text(head + "\n\n" + block)
        mode = "regenerated"
    else:
        with TODO.open("a") as f:
            f.write("\n" + block)
        mode = "appended"
    after = hashlib.sha256(TODO.read_bytes()).hexdigest()

    print(f"{mode}: before_sha={before[:12]} after_sha={after[:12]}")
    print(f"block_lines={block.count(chr(10))} overall={od}/{ot} "
          f"categories_with_items={len(with_items)}")
    print(f"new_bytes={len(TODO.read_bytes()) - len(raw)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
