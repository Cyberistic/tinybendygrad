#!/usr/bin/env python3
"""Emit PLAN.tsv for the 350 CAPTURED-STREAM `.txt` still on disk under `.agents/slop/`.

Columns: path, class, reason, sub, reader, planned_ext, one_line_change.

`reason` is DECLARED (basename in `checks/differ.py`'s `declared()`) or REFERENCED (a committed
code file names it). `sub` splits REFERENCED into `path` (a parent-qualified suffix, >=2 path
components, appears in committed code -- unambiguously this file) and `basename` (only a bare
basename appears -- the reader may be bound to a different directory, and this file is a
COLLISION candidate, which is why sloptxt's 49 REFERENCED is 20 real + 29 suspect).

No file is renamed: the NEITHER group is empty (sloptxt moved all 19), and every remaining file
is REFERENCED or DECLARED, so the plan states the one-line change instead of moving the name.
`.err`/`.out` is decided by content for the record.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DISC = os.path.join(ROOT, ".agents/slop/capstream/discover.json")
SPLIT = os.path.join(ROOT, ".agents/slop/capstream/refsplit.json")
ERR_LINE = re.compile(r"(Traceback \(most recent call last\)|^\s*File \"|(Error|Exception|panic|fatal|FAILED)\b)")


def planned_ext(text):
    lines = [l for l in text.splitlines() if l.strip()]
    if "Traceback (most recent call last)" in text:
        return ".err"
    errs = sum(1 for l in lines if ERR_LINE.search(l))
    return ".err" if errs and errs / max(len(lines), 1) >= 0.5 else ".out"


def one_line(t, reason, sub, refs, new):
    base = os.path.basename(t)
    if reason == "DECLARED":
        via = f"; also read at {refs[0]}" if refs else ""
        return (f"`{base}` must leave `checks/differ.py`'s declared() (1 line), with the "
                f"sha256-pinned oracle lines that write/read it moving in the same commit{via}; "
                f"then `{t}` -> `{new}`")
    if sub == "path":
        return f"`{refs[0]}` must name `{os.path.basename(new)}` not `{base}`"
    return f"`{refs[0]}` names `{base}` (basename, dir-bound) -- update it to `{os.path.basename(new)}`"


def main():
    d = json.load(open(DISC))
    s = json.load(open(SPLIT))
    path_ref = set(s["path_ref"])
    caps = sorted(t for t in d["targets"] if t.startswith(".agents/slop/") and d["class"][t] == "CAPTURED-STREAM")
    MOVED = {".agents/slop/dtypeb/gate.txt", ".agents/slop/fp8fix/gate.txt"}
    rows = []
    for t in caps:
        reason = d["reason"][t]
        refs = d["refs"].get(t, [])
        sub = ""
        if reason == "REFERENCED":
            sub = "path" if t in path_ref else "basename"
        src = os.path.join(ROOT, t)
        if not os.path.exists(src):  # already moved to its planned path
            src = os.path.splitext(os.path.join(ROOT, t))[0] + ".out"
        text = open(src, "rb").read().decode("utf-8", "replace")
        new = os.path.splitext(t)[0] + planned_ext(text)
        status = "MOVED (.out)" if t in MOVED else "STAYS"
        rows.append((t, "CAPTURED-STREAM", reason, sub, refs[0] if refs else "", new, status,
                     one_line(t, reason, sub, refs, new)))
    with open(os.path.join(ROOT, ".agents/slop/capstream/PLAN.tsv"), "w") as fh:
        fh.write("path\tclass\treason\tsub\treader\tplanned_ext\tstatus\tone_line_change\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")
    from collections import Counter

    print(f"rows={len(rows)}")
    print("reason:", Counter(r[2] for r in rows).most_common())
    print("referenced sub:", Counter(r[3] for r in rows if r[2] == "REFERENCED").most_common())


if __name__ == "__main__":
    main()
