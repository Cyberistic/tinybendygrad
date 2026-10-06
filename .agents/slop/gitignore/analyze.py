#!/usr/bin/env python3
"""For every UNANCHORED root .gitignore rule: what it matches, where, and what
anchoring it to the root would change.

Uses matchlib (validated 0 mismatches vs git on the whole tree). Read-only.
A path is "freed" by anchoring rule R when R is the only reason it is ignored.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matchlib as M  # noqa: E402


def swap_anchored(all_rules, rule):
    """Return all_rules with `rule` replaced by an anchored copy."""
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


def group_by_parent(paths_):
    groups = {}
    for rel in paths_:
        comps = rel.split("/")
        groups.setdefault("/".join(comps[:-1]) or ".", []).append(rel)
    return groups


def main():
    all_rules = M.load_all_rules()
    root_rules = [r for r in all_rules if r["file"] == ".gitignore"]
    tracked = M.tracked_set()
    paths = list(M.walk_paths())
    unanchored = [r for r in root_rules
                  if not r["anchored"] and not r["pattern"].startswith("**/")]

    report = {"rules": []}
    for rule in unanchored:
        matched = [(rel, is_dir) for rel, is_dir in paths
                   if M.matched_rules([rule], rel, is_dir)]
        alt = swap_anchored(all_rules, rule)
        freed = [rel for rel, is_dir in matched
                 if rel not in tracked and not M.matched_rules(alt, rel, is_dir)]

        where = {g: len(v) for g, v in sorted(
            group_by_parent([r for r, _ in matched]).items(),
            key=lambda kv: -len(kv[1]))}
        freed_where = {g: len(v) for g, v in sorted(
            group_by_parent(freed).items(), key=lambda kv: -len(kv[1]))}

        report["rules"].append({
            "line": rule["line"],
            "rule": rule["raw"].strip(),
            "pattern": rule["pattern"],
            "dir_only": rule["dir_only"],
            "matched_total": len(matched),
            "matched_tracked": sum(1 for r, _ in matched if r in tracked),
            "matched_untracked": sum(1 for r, _ in matched if r not in tracked),
            "where": where,
            "freed_by_anchoring": len(freed),
            "freed_where": freed_where,
        })

    json.dump(report, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
