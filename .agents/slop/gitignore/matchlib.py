#!/usr/bin/env python3
"""A gitignore matcher for THIS tree's rule set, validated against git.

No negations exist in .gitignore, so `ignored == matched by some rule`.
The matcher exists to answer a counterfactual git cannot: "if rule R were
anchored, would path P still be ignored?" -- so it must first agree with git
on the tree as it stands.
"""
import os
import re
import subprocess

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True, check=True).stdout.strip()


SKIP_DIRS = {".git", ".jj", ".venv", "references", ".ruff_cache"}


def load_all_rules():
    """Every .gitignore reachable in the tree, with its base directory.

    Root rules are tagged file=".gitignore"; nested ones carry their own base
    so a counterfactual on a root rule can tell which paths a NESTED rule still
    ignores. Regular `git ls-files` only lists tracked ones, so walk the disk.
    """
    rules = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if ".gitignore" not in filenames:
            continue
        base = os.path.relpath(dirpath, ROOT)
        base = "" if base == "." else base
        fpath = os.path.join(dirpath, ".gitignore")
        with open(fpath) as fh:
            lines = fh.read().splitlines()
        for i, raw in enumerate(lines):
            line = raw.rstrip()
            if not line or line.lstrip().startswith("#"):
                continue
            neg = line.startswith("!")
            if neg:
                line = line[1:]
            dir_only = line.endswith("/")
            if dir_only:
                line = line[:-1]
            anchored = line.startswith("/") or "/" in line
            if line.startswith("/"):
                line = line[1:]
            rules.append({
                "base": base,
                "file": os.path.relpath(fpath, ROOT),
                "line": i + 1, "raw": raw, "pattern": line,
                "neg": neg, "dir_only": dir_only, "anchored": anchored,
            })
    return rules


def _glob_to_regex(pat):
    # tokenise on **
    out = []
    i = 0
    while i < len(pat):
        c = pat[i]
        if c == "*":
            if pat[i:i + 2] == "**":
                # `**/` -> zero or more dirs; bare `**` -> anything
                if pat[i:i + 3] == "**/":
                    out.append("(?:[^/]*/)*")
                    i += 3
                    continue
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
            i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == "[":
            j = i + 1
            if j < len(pat) and pat[j] in "!^":
                j += 1
            if j < len(pat) and pat[j] == "]":
                j += 1
            while j < len(pat) and pat[j] != "]":
                j += 1
            cls = pat[i:j + 1]
            cls = cls.replace("[!", "[^")
            out.append(cls)
            i = j + 1
        else:
            out.append(re.escape(c))
            i += 1
    return "".join(out)


def _rule_matches(rule, relpath, is_dir):
    if rule["dir_only"] and not is_dir:
        return False
    pat = rule["pattern"]
    if rule["anchored"]:
        regex = "^" + _glob_to_regex(pat) + "$"
        return re.match(regex, relpath, re.IGNORECASE) is not None
    # unanchored: matches basename (single component); any component match
    basename = relpath.rsplit("/", 1)[-1]
    regex = "^" + _glob_to_regex(pat) + "$"
    return re.match(regex, basename, re.IGNORECASE) is not None


def matched_rules(rules, relpath, is_dir, file_filter=None):
    """Rules that cause relpath to be ignored: those matching the path itself
    (respecting dir_only vs file) or any ancestor directory within the rule's
    own base scope."""
    hits = []
    for rule in rules:
        if file_filter is not None and rule["file"] != file_filter:
            continue
        base = rule["base"]
        if base:
            if relpath != base and not relpath.startswith(base + "/"):
                continue
            rel = relpath[len(base) + 1:] if relpath != base else ""
        else:
            rel = relpath
        if rel == "":
            continue
        comps = rel.split("/")
        prefixes = ["/".join(comps[:k]) for k in range(1, len(comps))]
        if any(_rule_matches(rule, p, True) for p in prefixes):
            hits.append(rule)
        elif _rule_matches(rule, rel, is_dir):
            hits.append(rule)
    return hits


def is_ignored(rules, relpath, is_dir):
    return any(r["neg"] is False for r in matched_rules(rules, relpath, is_dir)
               if not r["neg"])
    # (no negations in this file; kept explicit for clarity)


def walk_paths():
    skip = {".git", ".jj", ".venv", "references", ".ruff_cache"}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel = os.path.relpath(dirpath, ROOT)
        dirnames[:] = [d for d in dirnames if d not in skip]
        if rel != ".":
            yield rel, True
        for name in filenames:
            yield os.path.relpath(os.path.join(dirpath, name), ROOT), False


def git_ignored_set():
    """paths git reports as ignoring-matched, and which line decides.

    `--no-index` is essential: without it, check-ignore silently omits any
    path the index knows about (including a directory that holds tracked
    files), which is a DIFFERENT question than "does a pattern match".
    """
    paths = [p for p, _ in walk_paths()]
    proc = subprocess.run(
        ["git", "check-ignore", "--stdin", "-v", "-z", "--no-index"],
        input="\0".join(paths), capture_output=True, text=True)
    fields = proc.stdout.split("\0")
    out = {}
    for j in range(0, len(fields) - 1, 4):
        _, lineno, _, path = fields[j:j + 4]
        if path:
            out[path] = int(lineno)
    return out


def tracked_set():
    out = subprocess.run(["git", "ls-files", "-z"], capture_output=True,
                         text=True, check=True).stdout
    return set(p for p in out.split("\0") if p)


if __name__ == "__main__":
    rules = load_all_rules()
    git = git_ignored_set()
    paths = list(walk_paths())
    mism = 0
    for rel, is_dir in paths:
        mine = bool([r for r in matched_rules(rules, rel, is_dir) if not r["neg"]])
        theirs = rel in git
        if mine != theirs:
            mism += 1
            if mism <= 30:
                print("MISMATCH", "ign=" if theirs else "not=",
                      "mine=" if mine else "minenot=", rel)
    print(f"paths={len(paths)} git_ignored={len(git)} mismatches={mism}")
