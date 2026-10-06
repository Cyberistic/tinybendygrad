#!/usr/bin/env python3
"""Classify the live DECLARED-NAME population BY CONTENT, using sloptxt/classify.py's rule
(imported, not copied -- one content rule, not a second witness).

Also emits the reference census that decides SKIP vs RENAME:

  PROTECTED iff the file is opened by a committed code file, by one of two routes:
    (a) a DISTINCTIVE path reference -- a committed code token that is a >=2-component
        suffix of THIS target and of NO OTHER population file with the same basename.
        (`runs/graphcmp/D/D0-selfcheck.txt` is NOT distinctive: it is a suffix of the live
        file and of every mirror; that is a collision, not a reference.)
    (b) a TREE-OPEN -- a committed code file copies/opens the target's mirror tree by name
        (the copytree-then-read pattern; measured here for `figurefix/plant/D-live`).

Writes plan rows to PLAN.tsv: path, class, rule, ref, new_path, note.
"""
import importlib.util
import json
import os
import re
import subprocess
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
D = os.path.join(ROOT, ".agents/slop/declared472")
CODE_EXT = (".py", ".sh", ".bash", ".mjs", ".js", ".cjs", ".ts", ".bend")
NAME_RE = re.compile(rb"[\w./\-]+\.txt")
EXT = {"ROWDUMP": ".rows", "CAPTURED-STREAM": ".out", "TABULAR": ".tsv", "PROSE": ".md"}


def load(rel):
    """Exec sloptxt/classify.py's definitions WITHOUT running its main() (it has no guard)."""
    src = open(os.path.join(ROOT, rel)).read()
    src = src.rsplit("\nmain()", 1)[0]
    ns = {"__name__": "sloptxt_classify", "__file__": os.path.join(ROOT, rel)}
    exec(compile(src, rel, "exec"), ns)
    return ns


def mentions():
    files = subprocess.run(["git", "-C", ROOT, "ls-files"],
                           capture_output=True, text=True).stdout.splitlines()
    out = {}
    for f in files:
        if f.endswith(".txt") or not f.endswith(CODE_EXT):
            continue
        if "/declared47" in f:  # the rename-experiment harnesses; they name their targets
            continue
        p = os.path.join(ROOT, f)
        try:
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        out[f] = [(m.group(0).decode("utf-8", "replace"),
                   data[: m.start()].count(b"\n") + 1) for m in NAME_RE.finditer(data)]
    return out


def main():
    der = json.load(open(os.path.join(D, "derived.json")))
    pop = der["population"]
    clf = load(".agents/slop/sloptxt/classify.py")
    mnt = mentions()

    # tree-open: does any committed code file name the target's mirror root basename?
    mirror_roots = {}
    for t in pop:
        if "/runs/graphcmp/D/" in t:
            root = t.rsplit("/runs/graphcmp/D/", 1)[0]
        else:
            root = os.path.dirname(t)
        mirror_roots.setdefault(root, 0)
        mirror_roots[root] += 1
    root_base = {r: os.path.basename(r) for r in mirror_roots}
    # A tree is OPENED iff a committed code file's `copytree(` FIRST argument names it with a
    # LITERAL string (not a variable): `copytree(HERE / "D-live", ...)`. A bare variable names
    # no tree. Analysis instruments under `.agents/slop/declared47*/` are EXCLUDED: they are the
    # previous unit's own rename experiments, not project drivers (reported separately).
    tree_open = {}
    for f in mnt:
        data = open(os.path.join(ROOT, f), "rb").read()
        for m in re.finditer(rb"copytree\s*\(([^\n)]*)", data):
            src = m.group(1).split(b",")[0]
            if b'"' not in src and b"'" not in src:
                continue
            for r, base in root_base.items():
                if os.path.basename(r).encode() in src:
                    tree_open.setdefault(r, []).append(f)

    # distinctive path refs: a committed token that is a >=2-component suffix of THIS target
    # and of NO OTHER file with the same basename ANYWHERE the project owns (population +
    # excused). `runs/graphcmp/D/<name>` fails this: the live file and every mirror end in it.
    all_base = {}
    for t in der["owned_txt"]:
        all_base.setdefault(os.path.basename(t), []).append(t)
    rows = []
    for t in pop:
        base = os.path.basename(t)
        parts = t.split("/")
        sfx = {"/".join(parts[i:]) for i in range(1, len(parts))}
        refs = []
        for f, ms in mnt.items():
            for name, ln in ms:
                if os.path.basename(name) != base or name not in sfx:
                    continue
                n = sum(1 for o in all_base[base] if o.endswith("/" + name) or o == name)
                if n == 1:
                    refs.append(f"{f}:{ln} names `{name}`")
        root = t.rsplit("/runs/graphcmp/D/", 1)[0] if "/runs/graphcmp/D/" in t else os.path.dirname(t)
        read_after = []
        for drv in tree_open.get(root, []):
            dsrc = open(os.path.join(ROOT, drv), "rb").read().decode("utf-8", "replace")
            # a READ needs the basename as a QUOTED path literal; prose mentions are citations.
            if re.search(r"[\"'][^\"'\n]*" + re.escape(base) + r"[\"']", dsrc):
                read_after.append(f"{drv} copytree + quoted read of `{base}`")
        raw = open(os.path.join(ROOT, t), "rb").read()
        try:
            cls, rule = clf["classify"](t, raw.decode("utf-8"))
        except UnicodeDecodeError:
            cls, rule = "UNCLASSIFIED", "non-utf8"
        new = os.path.splitext(t)[0] + EXT.get(cls, ".txt")
        note = "SKIP (read after copytree): " + read_after[0] if read_after else ""
        rows.append((t, cls, rule, "; ".join(refs + read_after), t if read_after else new, note))

    with open(os.path.join(D, "PLAN.tsv"), "w") as fh:
        fh.write("path\tclass\trule\tref\tnew_path\tnote\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")
    print("class distribution:", Counter(r[1] for r in rows).most_common())
    print("skipped (protected):", sum(1 for r in rows if r[5]))
    for r in rows:
        if r[5]:
            print("   SKIP", r[0], "<-", r[3].split(";")[0])
    print("tree_open:", tree_open)


main()
