#!/usr/bin/env python3
"""Enumerate every UNANCHORED rule in .gitignore and measure what it matches.

An unanchored rule has no leading `/` and no interior `/` before its final
segment: it matches at ANY depth. The task's worked example is `runs/`.

Read-only. Writes nothing. Prints a JSON report to stdout.
"""
import json
import os
import subprocess
import sys

ROOT = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"],
    capture_output=True, text=True, check=True,
).stdout.strip()

# Directories that are either not part of "this tree" or are enormous clones.
SKIP_DIRS = {".git", ".jj", ".venv", "references", ".ruff_cache"}


def walk_paths():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel = os.path.relpath(dirpath, ROOT)
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if rel != ".":
            yield rel + "/"
        for name in filenames:
            yield os.path.relpath(os.path.join(dirpath, name), ROOT)


def main():
    gitignore = os.path.join(ROOT, ".gitignore")
    with open(gitignore) as fh:
        rules = fh.read().splitlines()

    def is_unanchored(rule):
        # strip trailing spaces (git treats them literally unless escaped; ignore)
        if not rule or rule.lstrip().startswith("#"):
            return False
        if rule.startswith("!"):
            return False  # negation; handled separately
        if rule.startswith("/"):
            return False
        if rule.startswith("**/"):
            return False  # leading **/ is the explicit "any depth" form
        stem = rule.rstrip("/")
        if "/" in stem:
            return False  # has an interior directory prefix -> rooted
        return True

    unanchored = {
        i + 1: rule for i, rule in enumerate(rules) if is_unanchored(rule)
    }

    # Feed every path to check-ignore; collect which rule matched.
    paths = list(walk_paths())
    proc = subprocess.run(
        ["git", "check-ignore", "--stdin", "-v", "-z"],
        input="\0".join(paths), capture_output=True, text=True,
    )
    # -z format: <source>\0<linenum>\0<pattern>\0<pathname>\0 ...
    fields = proc.stdout.split("\0")
    matched = {}  # lineno -> {"rule":..., "paths":[...]}
    for j in range(0, len(fields) - 1, 4):
        source, lineno, pattern, path = fields[j:j + 4]
        if not path:
            continue
        try:
            ln = int(lineno)
        except ValueError:
            continue
        rec = matched.setdefault(ln, {"rule": pattern, "paths": []})
        rec["paths"].append(path)

    report = {
        "root": ROOT,
        "total_paths_walked": len(paths),
        "unanchored_rules": [],
    }
    for ln in sorted(unanchored):
        rule = unanchored[ln]
        rec = matched.get(ln)
        paths_for_rule = rec["paths"] if rec else []
        depths = {}
        for p in paths_for_rule:
            d = p.count("/")
            depths[d] = depths.get(d, 0) + 1
        report["unanchored_rules"].append({
            "line": ln,
            "rule": rule,
            "match_count": len(paths_for_rule),
            "depth_histogram": depths,
            "at_root": sorted(p for p in paths_for_rule if "/" not in p.rstrip("/"))[:20],
            "nested_sample": sorted(p for p in paths_for_rule
                                    if "/" in p.rstrip("/"))[:20],
        })

    json.dump(report, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
