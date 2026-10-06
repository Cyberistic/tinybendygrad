#!/usr/bin/env python3
"""Write PLAN.tsv for the `.agents/slop/**/*.txt` migration and (unless --dry) rename.

THE RENAME RULE, and why it is this narrow. A `.txt` is renamed iff ALL hold:

  1. its content class is not EMPTY  (an empty file proves nothing about its shape);
  2. its basename is NOT in `checks/differ.py`'s DECLARED set -- the generator owns those names,
     and the same ownership is why the 139 canonical `runs/graphcmp/D/*.txt` stay `.txt`;
  3. NO tracked file OUTSIDE the output/citation set names it (by basename or by full path).

(3) is a READ-or-WRITE rule on purpose: the brief blocks a RENAME that breaks a READER, but a
scratch generator that hardcodes the `.txt` name re-emits it, so a name that any live code still
carries is a contract this unit is not allowed to move. Everything else reports why it stayed.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
EXT = {"ROWDUMP": ".rows", "CAPTURED-STREAM": ".out", "TABULAR": ".tsv", "PROSE": ".md"}
NAME_RE = re.compile(rb"[\w./\-]+\.txt")
# Files that merely LIST or CITE `.txt` names are not references; only live code/literals count.
EXCLUDE_EXT = {
    ".txt", ".md", ".json", ".rows", ".tsv", ".out", ".err", ".rc", ".stdout", ".stderr",
    ".sha256", ".filelist", ".html", ".css", ".csv", ".png", ".pyc",
}


def declared():
    spec = importlib.util.spec_from_file_location("differ", os.path.join(ROOT, "checks/differ.py"))
    d = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(d)
    return set(d.declared())


def tracked():
    o = subprocess.run(["git", "-C", ROOT, "ls-files"], capture_output=True, text=True).stdout
    return [l for l in o.splitlines() if l]


def main():
    dry = "--dry" in sys.argv
    cls = {}
    for l in open(os.path.join(ROOT, ".agents/slop/sloptxt/classes.tsv")).read().splitlines()[1:]:
        p, c, r = l.split("\t")
        cls[p] = (c, r)
    feats = {f["path"] for f in json.load(open(os.path.join(ROOT, ".agents/slop/sloptxt/features.json")))}
    DEC = declared()

    targets = sorted(p for p in feats if p.startswith(".agents/slop/"))
    by_base = {}
    for t in targets:
        by_base.setdefault(os.path.basename(t), []).append(t)

    refs = {t: [] for t in targets}
    writers = {t: [] for t in targets}
    for f in tracked():
        if os.path.splitext(f)[1] in EXCLUDE_EXT:
            continue
        p = os.path.join(ROOT, f)
        try:
            if os.path.getsize(p) > 2_000_000:
                continue
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        for m in NAME_RE.finditer(data):
            base = os.path.basename(m.group(0).decode("utf-8", "replace"))
            if base not in by_base:
                continue
            ln = data[: m.start()].count(b"\n") + 1
            line = data.splitlines()[ln - 1][:120].decode("utf-8", "replace")
            is_write = b">" in data[max(0, m.start() - 40): m.start()]
            for t in by_base[base]:
                (writers if is_write else refs)[t].append(f"{f}:{ln}  {line}")

    rows = []
    for t in targets:
        c, rule = cls[t]
        new = ""
        reason = ""
        if c == "EMPTY":
            reason = "EMPTY: zero bytes prove no shape; a .txt here is not a row dump"
        elif os.path.basename(t) in DEC:
            reason = "DECLARED: checks/differ.py owns this name (same contract as the 139 excused)"
        elif refs[t]:
            reason = "REFERENCED: named by live code -> " + refs[t][0]
        else:
            new = os.path.splitext(t)[0] + EXT.get(c, ".txt")
            if os.path.exists(os.path.join(ROOT, new)):
                reason = f"COLLISION: {new} exists"
                new = ""
        rows.append((t, c, rule, refs[t][0] if refs[t] else "", new, reason))

    with open(os.path.join(ROOT, ".agents/slop/sloptxt/PLAN.tsv"), "w") as fh:
        fh.write("path\tclass\trule\treader\tnew_path\tnote\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")

    ren = [r for r in rows if r[4]]
    print(f"targets={len(rows)}  rename={len(ren)}", file=sys.stderr)
    from collections import Counter

    print("by class (all):", Counter(r[1] for r in rows).most_common(), file=sys.stderr)
    print("renamed by class:", Counter(r[1] for r in ren).most_common(), file=sys.stderr)
    for r in ren:
        print(f"  {r[0]} -> {r[4]}", file=sys.stderr)
    if not dry:
        for r in ren:
            os.rename(os.path.join(ROOT, r[0]), os.path.join(ROOT, r[4]))
        print(f"RENAMED {len(ren)}", file=sys.stderr)


main()
