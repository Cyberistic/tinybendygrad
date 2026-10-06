#!/usr/bin/env python3
"""Reader census over the live DECLARED-NAME population, refined by capstream's rule.

Two references are computed per target, because they mean DIFFERENT things:

  PATH    a committed CODE file (CODE_EXT) contains a >=2-component suffix of the target's
          repo-relative path.  This is the only test that unambiguously names THIS file
          (capstream/refsplit.py: "a basename match is not a reference").
  BASE    a committed CODE file contains only the bare basename.  Weak: it may be bound to
          another directory (e.g. `$RUN/gate.txt`) or to a copy made at runtime.

A target is PROTECTED iff it has a PATH reference.  It is a RENAME CANDIDATE otherwise.

Also records, per target, the mirror tree it lives in and whether any committed file OPENS
that tree by name (a `copytree(<tree>` or a literal `<tree>/` reference), which is where a
`copytree`-then-read driver hides its by-name read.
"""
import json
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
D = os.path.join(ROOT, ".agents/slop/declared472")
CODE_EXT = (".py", ".sh", ".bash", ".mjs", ".js", ".cjs", ".ts", ".bend")
NAME_RE = re.compile(rb"[\w./\-]+\.txt")


def tracked_code():
    files = subprocess.run(["git", "-C", ROOT, "ls-files"],
                           capture_output=True, text=True).stdout.splitlines()
    out = {}
    for f in files:
        if f.endswith(".txt") or not f.endswith(CODE_EXT):
            continue
        p = os.path.join(ROOT, f)
        try:
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        out[f] = data
    return out


def main():
    der = json.load(open(os.path.join(D, "derived.json")))
    targets = der["population"]
    code = tracked_code()

    # Pre-extract every .txt name mentioned per file, with line number.
    mentions = {}  # (file) -> list[(name, line)]
    for f, data in code.items():
        ms = []
        for m in NAME_RE.finditer(data):
            name = m.group(0).decode("utf-8", "replace")
            ln = data[: m.start()].count(b"\n") + 1
            ms.append((name, ln))
        mentions[f] = ms

    rows = []
    for t in targets:
        parts = t.split("/")
        sfx = {"/".join(parts[i:]) for i in range(1, len(parts))}  # >=2 components
        base = parts[-1]
        path_hits, base_hits = [], []
        for f, ms in mentions.items():
            for name, ln in ms:
                if os.path.basename(name) != base:
                    continue
                if name in sfx:
                    path_hits.append(f"{f}:{ln}")
                else:
                    base_hits.append(f"{f}:{ln}")
        rows.append({"path": t, "path_ref": path_hits, "base_ref": base_hits})

    n_path = sum(1 for r in rows if r["path_ref"])
    n_base = sum(1 for r in rows if r["base_ref"] and not r["path_ref"])
    n_none = sum(1 for r in rows if not r["path_ref"] and not r["base_ref"])
    print(f"population                      = {len(rows)}")
    print(f"PATH ref (>=2-comp suffix)      = {n_path}")
    print(f"BASENAME-only ref               = {n_base}")
    print(f"no committed code ref at all    = {n_none}")
    print("\nthe PATH-referenced set (this is the SKIP set):")
    for r in rows:
        if r["path_ref"]:
            print(f"  {r['path']}\n      <- {r['path_ref'][0]}")
    json.dump(rows, open(os.path.join(D, "census.json"), "w"), indent=1)
    json.dump({"path": [r["path"] for r in rows if r["path_ref"]],
               "base_only": [r["path"] for r in rows if r["base_ref"] and not r["path_ref"]],
               "none": [r["path"] for r in rows if not r["path_ref"] and not r["base_ref"]]},
              open(os.path.join(D, "census_split.json"), "w"), indent=1)


main()
