#!/usr/bin/env python3
"""THE ONE WRITER. It takes a plan TSV whose `new` column a human or the whole-text rule chose, and
it retypes exactly ONE number per row -- and it REFUSES any row whose port line is not a comment.

    .venv/bin/python .agents/slop/stale269/apply.py plan.tsv [--dry]

**WHY IT REFUSES NON-COMMENTS.** The deliverable is 0 code lines. A `.bend` line is a comment iff
everything before its first `#` is whitespace. So this checks that, per row, on the CURRENT bytes,
and exits non-zero rather than editing a row that fails. A writer that trusts its input is a
writer that has not measured its own blast radius.

It also edits only the FIRST citation token that matches the named file and the OLD number, so a
line carrying `ops.py:632-638` becomes `ops.py:635-638` -- the END of the range is untouched, and
the reader's span is preserved.
"""
import re
import sys

CITE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.py):(\d+)(?:-(\d+))?")


def main(argv: list[str]) -> int:
    dry = "--dry" in argv
    path = next(a for a in argv[1:] if not a.startswith("-"))
    rows = [f.rstrip("\n").split("\t") for f in open(path, encoding="utf-8").read().splitlines()[1:]]
    files: dict[str, list[str]] = {}
    refused: list[str] = []
    n = 0
    for cls, port, pl, rp, cl, new, *_ in rows:
        new = new.strip()
        if not new.isdigit():
            refused.append(f"{port}:{pl} new={new!r} is not a line number")
            continue
        if port not in files:
            files[port] = open(port, encoding="utf-8").read().splitlines()
        src = files[port]
        i = int(pl) - 1
        if i >= len(src):
            refused.append(f"{port}:{pl} is past the end of the file ({len(src)} lines)")
            continue
        line = src[i]
        head = line[: line.find("#")] if "#" in line else line
        if head.strip():
            refused.append(f"{port}:{pl} IS NOT A COMMENT LINE: {line.strip()[:80]}")
            continue
        m = CITE.search(line)
        # The gate matched ANY `.py`; find the one whose file and number are this row's.
        hits = [c for c in CITE.finditer(line) if c.group(1) == os.path.basename(rp) and c.group(2) == cl]
        hits = [c for c in hits if (c.group(3) is None or int(c.group(3)) >= int(new))
                or int(c.group(2)) != int(cl)]
        hits = hits or [c for c in CITE.finditer(line) if c.group(2) == cl and c.group(1).endswith(rp.split("/")[-1])]
        if not hits:
            refused.append(f"{port}:{pl} no citation token {rp}:{cl} on the line: {line.strip()[:80]}")
            continue
        c = hits[0]
        src[i] = line[: c.start(2)] + new + line[c.end(2):]
        n += 1
    for f, ls in files.items():
        if dry:
            continue
        open(f, "w", encoding="utf-8").write("\n".join(ls) + "\n")
    print(f"  {'WOULD RETYPE' if dry else 'retyped'} {n} numbers across {len(files)} files")
    for r in refused:
        print(f"  REFUSED {r}")
    return 1 if refused else 0


if __name__ == "__main__":
    import os
    sys.exit(main(sys.argv))