#!/usr/bin/env python3
"""Final tables for REPORT.md, after the change.

1. Every UNANCHORED root rule: line, rule, matches, untracked, freed-if-anchored.
2. The freed set for `/runs/`: extension mix and evidence-vs-output grouping.
All numbers from matchlib (validated 0 mismatches vs git). Read-only.
"""
import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matchlib as M  # noqa: E402


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


def main():
    all_rules = M.load_all_rules()
    root_rules = [r for r in all_rules if r["file"] == ".gitignore"]
    tracked = M.tracked_set()
    paths = list(M.walk_paths())

    print("LINE\tRULE\tMATCH\tUNTRACKED\tFREED_IF_ANCHORED\tVERDICT")
    for rule in root_rules:
        if rule["anchored"] or rule["pattern"].startswith("**/"):
            continue
        matched = [(p, d) for p, d in paths if M.matched_rules([rule], p, d)]
        alt = swap_anchored(all_rules, rule)
        freed = [p for p, d in matched
                 if p not in tracked and not M.matched_rules(alt, p, d)]
        print(f"{rule['line']}\t{rule['raw'].strip()}\t{len(matched)}\t"
              f"{sum(1 for p, _ in matched if p not in tracked)}\t{len(freed)}\t")

    # freed composition for the anchored rule: simulate the OLD broad form
    runs = [r for r in root_rules if r["pattern"] == "runs"]
    if runs:
        broad = dict(runs[0])
        broad["anchored"] = False
        # ruleset with the broad rule substituted back in, so we can ask what a
        # nested path would have been ignored BY and whether only it did so.
        unanchored_set = [broad if (r["file"] == ".gitignore"
                                    and r["line"] == runs[0]["line"]
                                    and r["raw"] == runs[0]["raw"]) else r
                           for r in all_rules]
        matched = [(p, d) for p, d in paths
                   if M.matched_rules([broad], p, d)]
        freed = [p for p, d in matched
                 if p not in tracked and not M.matched_rules(
                     [r for r in unanchored_set
                      if not (r["file"] == ".gitignore"
                              and r["line"] == runs[0]["line"]
                              and r["raw"] == runs[0]["raw"])], p, d)]
        print(f"\n# the rule is now line {runs[0]['line']} raw={runs[0]['raw'].strip()!r}")
        print(f"freed_by_anchoring_that_rule={len(freed)}")
        print("ext_mix=", dict(collections.Counter(
            os.path.splitext(p)[1] or "(dir/none)" for p in freed)))
        # evidence vs output by directory
        def klass(p):
            if "e2epy/fixtures" in p or "figure2/plant" in p:
                return "EVIDENCE(fixture)"
            if "differverdict/pristine" in p:
                return "EVIDENCE(oracle-baseline)"
            if "/scratch/" in p or "checkshells" in p:
                return "OUTPUT(scratch-artifacts)"
            return "OUTPUT(graphcmp-run)"
        print("class_mix=", dict(collections.Counter(klass(p) for p in freed)))
        print("freed_files_only=", sum(1 for p, d in matched
              if p in freed and not d))


if __name__ == "__main__":
    main()
