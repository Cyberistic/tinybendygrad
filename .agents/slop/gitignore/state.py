#!/usr/bin/env python3
"""Capture the state anchoring will be judged against: ignored-untracked paths
(matched by any rule), total tracked, and which of the ignored are under runs/.
Prints one name=value row per measurement. Read-only.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matchlib as M  # noqa: E402


def ignored_untracked(paths, tracked, all_rules):
    n = 0
    for rel, is_dir in paths:
        if rel in tracked:
            continue
        if M.matched_rules(all_rules, rel, is_dir):
            n += 1
    return n


def main():
    all_rules = M.load_all_rules()
    tracked = M.tracked_set()
    paths = list(M.walk_paths())
    iu = ignored_untracked(paths, tracked, all_rules)
    runs_rule = [r for r in all_rules
                 if r["file"] == ".gitignore" and r["pattern"] == "runs"]
    runs_paths = [p for p, d in paths
                  if M.matched_rules(runs_rule, p, d)]
    runs_untracked = [p for p in runs_paths if p not in tracked]

    # Counterfactual must be ANCHORED (keep the rule, tighten it), not REMOVED:
    # removing it also frees the root `runs/` the rule exists for. Anchoring a
    # path's root form still ignores it via ancestor match; only deeper `runs/`
    # components fall out.
    alt = []
    for r in all_rules:
        if r["file"] == ".gitignore" and r["pattern"] == "runs":
            a = dict(r)
            a["anchored"] = True
            alt.append(a)
        else:
            alt.append(r)
    freed = [p for p, d in paths
             if p not in tracked and M.matched_rules(runs_rule, p, d)
             and not M.matched_rules(alt, p, d)]
    print(f"tracked_total={len(tracked)}")
    print(f"ignored_untracked={iu}")
    print(f"walk_paths={len(paths)}")
    print(f"runs_rule_matches={len(runs_paths)}")
    print(f"runs_untracked={len(runs_untracked)}")
    print(f"freed_if_anchored={len(freed)}")
    print(f"runs_rule_line={runs_rule[0]['line'] if runs_rule else 'NONE'}")


if __name__ == "__main__":
    main()
