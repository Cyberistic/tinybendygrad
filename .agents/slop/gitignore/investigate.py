#!/usr/bin/env python3
"""Evidence for the runs/ decision and the other unanchored rules.

Dumps, for the ROOT .gitignore rules we care about, the concrete paths an
anchoring would free, classified by extension; lists tracked paths that match
each rule; and probes whether e2e/gate code names any freed path.
"""
import collections
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matchlib as M  # noqa: E402

ROOT = M.ROOT


def root_rules():
    return [r for r in M.load_all_rules() if r["file"] == ".gitignore"]


def swap_anchored(all_rules, rule):
    out = []
    for r in all_rules:
        if (r["file"] == rule["file"] and r["line"] == rule["line"]
                and r["raw"] == rule["raw"]):
            a = dict(r)
            a["anchored"] = True
            out.append(a)
        else:
            out.append(r)
    return out


def grep(pattern, paths):
    if not paths:
        return []
    proc = subprocess.run(["git", "grep", "-n", "-F", "--", pattern],
                          cwd=ROOT, capture_output=True, text=True)
    return proc.stdout.splitlines()


def main():
    allr = M.load_all_rules()
    tracked = M.tracked_set()
    paths = list(M.walk_paths())
    by_line = {r["line"]: r for r in root_rules()
               if not r["anchored"]}

    for want in (157, 8, 13):
        rule = by_line[want]
        alt = swap_anchored(allr, rule)
        matched = [(p, d) for p, d in paths if M.matched_rules([rule], p, d)]
        freed = [p for p, d in matched
                 if p not in tracked and not M.matched_rules(alt, p, d)]
        ext = collections.Counter(
            os.path.splitext(p)[1] or "(none)" for p in freed)
        print(f"\n=== line {want}: {rule['raw'].strip()} ===")
        print(f"matched={len(matched)} tracked={sum(1 for p,_ in matched if p in tracked)}"
              f" freed={len(freed)}")
        print("tracked matching paths:")
        for p, d in matched:
            if p in tracked:
                print("   TRACKED", p)
        print("freed extensions:", dict(ext))
        tops = collections.Counter(
            p.split("/.agents/slop/", 1)[1].split("/")[0]
            if "/.agents/slop/" in p else "OUTSIDE-slp"
            for p in freed)
        print("freed by unit under .agents/slop:", dict(tops))
        outside = [p for p in freed if "/.agents/slop/" not in p]
        print("freed NOT under .agents/slop:", outside[:50])

    # every tracked path that contains a /runs/ component
    truns = sorted(p for p in tracked if "/runs/" in p or p.startswith("runs/"))
    print(f"\n=== tracked paths containing a runs/ component: {len(truns)} ===")
    for p in truns[:80]:
        print("  ", p)


if __name__ == "__main__":
    main()
