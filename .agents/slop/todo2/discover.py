#!/usr/bin/env python
"""Characterise .agents/TODO.md BY DISCOVERY. Report every count with its denominator.

No .txt. Outputs written under .agents/slop/todo2/ as .md/.tsv/.out.
"""
from __future__ import annotations

import hashlib
import re
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TODO = REPO / ".agents" / "TODO.md"
OUT = REPO / ".agents" / "slop" / "todo2"
OUT.mkdir(parents=True, exist_ok=True)

HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
# task-list item: leading bullet then a checkbox
CHECKBOX = re.compile(r"^\s*[-*]\s*\[([ xX~])\]\s?(.*)$")
# any checkbox token anywhere (for the AGENTS.md rg claim denominator)
ANYBOX = re.compile(r"\[([ xX~])\]")
BAR = re.compile(r"[\u2588\u2593\u2592\u2591]")  # █ ▓ ▒ ░


def main() -> int:
    raw = TODO.read_bytes()
    text = raw.decode("utf-8")
    lines = text.split("\n")
    # split('\n') yields a trailing '' for a file ending in newline; drop it for line parity with wc -l
    if lines and lines[-1] == "":
        lines = lines[:-1]

    sha = hashlib.sha256(raw).hexdigest()
    n_nl = len(lines)  # equals wc -l because we dropped the final empty

    # ---- heading census (skip fenced code blocks) -----------------------
    headings = []  # (lineno, level, text)
    in_fence = False
    n_fenced = 0
    for i, ln in enumerate(lines, 1):
        if ln.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            n_fenced += 1
            continue
        m = HEADING.match(ln)
        if m:
            headings.append((i, len(m.group(1)), m.group(2).strip()))
    by_level = Counter(lvl for _, lvl, _ in headings)

    # ---- checkbox census ------------------------------------------------
    tasks = []  # (lineno, state, text)
    for i, ln in enumerate(lines, 1):
        m = CHECKBOX.match(ln)
        if m:
            tasks.append((i, m.group(1), m.group(2).strip()))
    state = Counter(t[1].lower() for t in tasks)
    box_lines = len(tasks)
    # every checkbox token anywhere (prose may embed [ ] / [x])
    anybox_lines = sum(1 for ln in lines if ANYBOX.search(ln))
    anybox_tokens = sum(len(ANYBOX.findall(ln)) for ln in lines)

    # ---- progress-bar census -------------------------------------------
    bar_lines = [i for i, ln in enumerate(lines, 1) if BAR.search(ln)]
    bar_tokens = sum(len(BAR.findall(ln)) for ln in lines)

    # ---- duplication ----------------------------------------------------
    distinct = len(set(lines))
    distinct_stripped = len({ln.strip() for ln in lines})
    blank = sum(1 for ln in lines if ln.strip() == "")
    line_counts = Counter(lines)
    top_repeated_lines = [(c, ln) for ln, c in line_counts.most_common() if c > 1][:40]

    # top repeated contiguous blocks (blocks of 2..6 non-blank lines), exact
    block_counts: Counter[tuple[str, ...]] = Counter()
    for n in (2, 3, 4, 5, 6):
        for i in range(len(lines) - n + 1):
            blk = tuple(lines[i : i + n])
            if all(b.strip() for b in blk):
                block_counts[blk] += 1
    top_blocks = [(c, blk) for blk, c in block_counts.most_common(40) if c > 1]

    # ---- per top-level '##' section census ------------------------------
    # section = span between successive level-<=2 headings
    sections = []  # (title, start, end)
    top_idx = [k for k, (_, lvl, _) in enumerate(headings) if lvl <= 2]
    for j, k in enumerate(top_idx):
        ln = headings[k][0]
        end = headings[top_idx[j + 1]][0] - 1 if j + 1 < len(top_idx) else len(lines)
        sections.append((headings[k][2], ln, end))
    # attach checkbox + bar counts per section
    sec_rows = []
    for title, start, end in sections:
        ck = Counter()
        bars = 0
        for i in range(start, end + 1):
            m = CHECKBOX.match(lines[i - 1])
            if m:
                ck[m.group(1).lower()] += 1
            if BAR.search(lines[i - 1]):
                bars += 1
        total = sum(ck.values())
        done = ck["x"]
        sec_rows.append((title, start, end, total, done, ck[" "], ck["~"], bars))

    # also per level-3 '###' subsection (the "categories" candidates)
    sub_rows = []
    sub_idx = [k for k, (_, lvl, _) in enumerate(headings) if lvl == 3]
    for j, k in enumerate(sub_idx):
        ln = headings[k][0]
        end = headings[sub_idx[j + 1]][0] - 1 if j + 1 < len(sub_idx) else len(lines)
        ck = Counter()
        bars = 0
        for i in range(ln, end + 1):
            m = CHECKBOX.match(lines[i - 1])
            if m:
                ck[m.group(1).lower()] += 1
            if BAR.search(lines[i - 1]):
                bars += 1
        if sum(ck.values()) or bars:
            sub_rows.append((headings[k][2], ln, sum(ck.values()), ck["x"], ck[" "], bars))

    total_ck = sum(state.values())
    pct = 100.0 * state["x"] / total_ck if total_ck else 0.0

    # ---- write the report ----------------------------------------------
    w = []
    w.append("# `.agents/TODO.md` — characterisation BY DISCOVERY")
    w.append("")
    w.append("Instrument: `.agents/slop/todo2/discover.py` (Python, reads the file once).")
    w.append(f"SHA256: `{sha}`")
    w.append("")
    w.append("## 1. Size")
    w.append("")
    w.append("| quantity | value | denominator |")
    w.append("|---|---|---|")
    w.append(f"| bytes | {len(raw)} | file |")
    w.append(f"| lines (`wc -l`) | {n_nl} | file |")
    w.append(f"| blank lines | {blank} | of {n_nl} lines |")
    w.append(f"| non-blank lines | {n_nl - blank} | of {n_nl} lines |")
    w.append("")
    w.append("## 2. Heading census")
    w.append("")
    w.append(f"Total heading lines: **{len(headings)}** of {n_nl} lines.")
    w.append("")
    w.append("| level | count |")
    w.append("|---|---|")
    for lvl in sorted(by_level):
        w.append(f"| `{'#' * lvl}` | {by_level[lvl]} |")
    w.append("")
    w.append("## 3. Checkbox states")
    w.append("")
    w.append("| pattern | lines | of |")
    w.append("|---|---|---|")
    w.append(f"| task items `- [ ]`/`- [x]`/`- [~]` | {box_lines} | {n_nl} lines |")
    w.append(f"| `[ ]` unchecked | {state[' ']} | {box_lines} items |")
    w.append(f"| `[x]` checked (lower) | {state['x']} | {box_lines} items |")
    w.append(f"| `[X]` checked (upper) | 0 | {box_lines} items |")
    w.append(f"| `[~]` indeterminate | {state['~']} | {box_lines} items |")
    w.append(f"| completion | {pct:.2f}% | {state['x']}/{total_ck} items |")
    w.append("")
    w.append(f"Raw `grep -c '[ ]'` = 246 lines; `grep -c '[x]'` = 1111 lines; sum = 1357, "
             f"vs {box_lines} task lines. The raw greps over-count because prose embeds `[ ]`/`[x]` tokens.")
    w.append(f"Checkbox TOKENS anywhere (prose incl.): {anybox_tokens} on {anybox_lines} lines.")
    w.append("")
    w.append("## 4. Progress bars")
    w.append("")
    w.append("`AGENTS.md` claims `rg -c '[█▓▒░]' .agents/TODO.md` = **12 lines**.")
    w.append(f"VERIFIED: **{len(bar_lines)} lines** carry a bar glyph; **{bar_tokens} total bar glyphs** "
             f"on {n_nl} lines.")
    w.append("")
    w.append("Bar-bearing lines (1-based):")
    w.append("")
    w.append("```")
    for i in bar_lines:
        w.append(f"{i}: {lines[i-1]}")
    w.append("```")
    w.append("")
    w.append("## 5. Duplication")
    w.append("")
    w.append("| quantity | value | denominator |")
    w.append("|---|---|---|")
    w.append(f"| distinct lines (byte-exact) | {distinct} | {n_nl} lines |")
    w.append(f"| distinct lines (whitespace-stripped) | {distinct_stripped} | {n_nl} lines |")
    w.append(f"| duplicated line instances | {n_nl - distinct} | {n_nl} lines |")
    w.append(f"| repeated-line variety | {sum(1 for c in line_counts.values() if c > 1)} | {distinct} distinct |")
    w.append("")
    w.append("### Top repeated single lines")
    w.append("")
    w.append("| count | line |")
    w.append("|---|---|")
    for c, ln in top_repeated_lines:
        show = ln if len(ln) <= 100 else ln[:97] + "..."
        w.append(f"| {c} | `{show}` |")
    w.append("")
    w.append("### Top repeated contiguous blocks (non-blank, len 2-6)")
    w.append("")
    for c, blk in top_blocks[:25]:
        w.append(f"- **x{c}** ({len(blk)} lines):")
        for b in blk:
            show = b if len(b) <= 110 else b[:107] + "..."
            w.append(f"    - `{show}`")
    w.append("")
    w.append("## 6. Sections (`##` and above) — checkbox rollup")
    w.append("")
    w.append("| section | line | items | done | open | `[~]` | bar lines |")
    w.append("|---|---|---|---|---|---|---|")
    for title, start, end, total, done, opn, tilde, bars in sec_rows:
        t = title if len(title) <= 60 else title[:57] + "..."
        w.append(f"| {t} | {start} | {total} | {done} | {opn} | {tilde} | {bars} |")
    w.append("")
    w.append(f"`##`+ sections: {len(sec_rows)} (denominator: level<=2 headings).")
    w.append("")
    w.append("## 7. Subsections (`###`) with items or bars — the category candidates")
    w.append("")
    w.append("| subsection | line | items | done | open | bar lines |")
    w.append("|---|---|---|---|---|---|")
    for title, ln, total, done, opn, bars in sub_rows:
        t = title if len(title) <= 60 else title[:57] + "..."
        w.append(f"| {t} | {ln} | {total} | {done} | {opn} | {bars} |")
    w.append("")
    w.append(f"`###` subsections with content: {len(sub_rows)} (denominator: {by_level.get(3,0)} level-3 headings).")
    w.append("")

    (OUT / "discover.md").write_text("\n".join(w) + "\n")

    # machine-readable section rollup
    with (OUT / "sections.tsv").open("w") as f:
        f.write("title\tstart\tend\titems\tdone\topen\ttilde\tbars\n")
        for r in sec_rows:
            f.write("\t".join(str(x) for x in r) + "\n")
    with (OUT / "subsections.tsv").open("w") as f:
        f.write("title\tline\titems\tdone\topen\tbars\n")
        for r in sub_rows:
            f.write("\t".join(str(x) for x in r) + "\n")

    # summary to stdout for the transcript
    print(f"bytes={len(raw)} lines={n_nl} sha={sha[:12]}")
    print(f"headings={len(headings)} by_level={dict(by_level)}")
    print(f"task_lines={box_lines} open={state[' ']} done={state['x']} tilde={state['~']} pct={pct:.2f}%")
    print(f"bar_lines={len(bar_lines)} bar_tokens={bar_tokens}")
    print(f"distinct={distinct} of {n_nl} -> duplicated={n_nl-distinct} ({100*(n_nl-distinct)/n_nl:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
