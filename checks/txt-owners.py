#!/usr/bin/env python3
"""Which GENERATOR writes each `.txt` `checks/no-txt.py` reports -- and does any generator's own
source still name one?

`checks/no-txt.py` answers a FILE question and is right to: `.txt` is not an extension this project
uses. It cannot say WHICH GENERATOR put one there, so the count it prints has no owner, and a count
with no owner is not a finding, it is a number. This answers the other half, and because the rule
is a GENERATOR rule, it reads GENERATOR SOURCES rather than the filesystem.

THE ATTRIBUTION IS A WRITE PATH, NOT A CITATION. `oracles/` holds 259 `.txt` and `checks/differ.py`
holds 139 more under names it declares; the first number is four times the second and nobody named
it, because a directory full of files is not an owner. So V-9 -- a citation and a write path are
the same token -- is applied from the other side: a redirection target is a WRITE, a mention on the
same line is a READ, and only the first can have produced a file.

THREE OF THIS CHECK'S OWN FAULTS ARE RECORDED HERE, because each one made the answer wrong in the
direction that flatters it, and each was caught by disagreeing with the tree rather than by reading
the code:

  1. BASENAME MATCHING. Keying on the basename handed `checks/gate.sh` credit for two files it
     writes into `mktemp -d`, because `bench.txt`, `py.txt` and `native.txt` each exist under four
     unrelated directories. A GENERATOR OWNS A DIRECTORY, so the key is the resolved path.
  2. RE-SCANNING THE LINE. `e2e_mm_gate.py "$RUN/e2e-mm-bend.txt" > "$RUN/e2e-mm-gate.txt"` is a
     program READING the first name, and finding tokens anywhere on the line credited it as the
     WRITER of the e2e gate's own input. The redirect is the evidence, so it is captured, not re-found.
  3. A GATE THAT CANNOT PASS. Scoping the exit status to generators found in the attribution set
     made a generator that correctly writes NO `.txt` indistinguishable from a typo, and the plant
     answered `no such generator` on BOTH sides -- rc 2 twice, having moved nothing. A gate that
     cannot be satisfied cannot be checked, so the scoped form reads the named file's source.

    usage: .venv/bin/python checks/txt-owners.py
           .venv/bin/python checks/txt-owners.py --gate [GENERATOR ...]

    no flag   print the census, exit 0. A census is a deliverable, not a gate: six units are writing
              here at once, and a gate that goes red on their unfinished work teaches nothing.
    --gate    with no names, exit 1 if ANY generator writes a `.txt`. With names, exit 1 if any of
              THOSE does -- answerable whatever the filesystem holds, which is what the plant needs.

The hard set is IMPORTED from `no-txt.py`, never re-derived, so the carve-out cannot drift: a second
walk here would be a second opinion about which 139 files are exempt, and a second opinion about an
exemption is how an exemption becomes a blanket.
"""
from __future__ import annotations

import collections
import importlib.util
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = (".py", ".sh", ".bend", ".mjs", ".ts", ".js", ".json", ".tsv")
SIZE_CAP = 2_000_000

# A BINDING IS A PLAIN LITERAL OR IT IS NOT A BINDING. `ROOT=$(cd "$(dirname "$0")/.." && pwd)`
# holds quotes and a command substitution; binding it to the text before the first quote produced
# `$(cd/runs/e2e/e2e-mm-bend.txt`, which resolved to nothing and cost 38 real write paths.
ASSIGN = re.compile(r"^\s*(?:export\s+|declare\s+-\w+\s+|let\s+|const\s+)?"
                    r"([A-Z_][A-Z0-9_]*)=[\"']?([^\"'\n]*)[\"']?\s*$", re.M)
NOT_A_PATH = re.compile(r"[`()\"']")
VAR = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")
LEAD_VAR = re.compile(r"^\$?\{?[A-Za-z_][A-Za-z0-9_]*\}?/")
REDIRECT = re.compile(r"""\d?>>?\s*(?:"([^"]+)"|'([^']+)'|([^\s;|&>]+))""")
# Python spells it two ways here: `open(p, "w")` and `pathlib .write_text(...)`. The argument is an
# EXPRESSION (`HERE / "census.txt"`), so the `.txt` is lifted out of the argument.
PYWRITE = re.compile(r"""open\(\s*([^,)]+?)\s*,\s*['"][wax]|(?:write_text|write_bytes)\(\s*([^,)]+?)\s*[,)]""")
TXT_IN_ARG = re.compile(r"[\"'][^\"']*\.txt[\"']")


def hard_set() -> list[str]:
    """The `.txt` `checks/no-txt.py` reports, computed by ITSELF."""
    spec = importlib.util.spec_from_file_location("notxt", os.path.join(ROOT, "checks/no-txt.py"))
    nt = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(nt)
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in nt.SKIP]
        for f in filenames:
            if f.endswith(".txt"):
                rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
                if nt.owned(rel):
                    found.append(rel)
    return sorted(rel for rel in found if rel not in nt.graphcmp_artifacts())


def resolve(tok: str, binds: dict[str, str]) -> tuple[str | None, str]:
    """A write target as a repo-relative path, or the reason it could not be resolved.

    A variable the check cannot evaluate must stay UNBOUND so the DIRECTORY MEASUREMENT can carry
    it: `RUN="$ROOT/runs/e2e"` cannot be computed without running a shell, but if dropping `$ROOT`
    names a directory that EXISTS then that is the directory. This measurement runs BEFORE any
    bail-out on `$` -- bailing out first is what left `checks/e2e.sh` with six write paths
    "unresolved" while `runs/e2e/` sat right there.
    """
    out = tok
    for _ in range(6):                      # bounded: two variables deep is the shape that occurs
        if "$" not in out:
            break
        sub = VAR.sub(lambda m: binds.get(m.group(1), m.group(0)), out)
        if sub == out:
            break
        out = sub
    if not out.endswith(".txt"):
        return None, "not a .txt path"
    lead = LEAD_VAR.match(out)
    for cand in ([out] if lead is None else [out[lead.end():], out]):
        cand = os.path.normpath(cand)
        if os.path.isdir(os.path.join(ROOT, os.path.dirname(cand))):
            return cand, "resolved"
    return None, (f"no such directory: {out}" if "$" not in out else "unresolved variable")


def txt_writes(rel: str) -> list[tuple[int, str, str]]:
    """Every `.txt` write target in ONE file: (line number, resolved path or '', why)."""
    path = os.path.join(ROOT, rel)
    try:
        if os.path.getsize(path) > SIZE_CAP:
            return []
        body = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    binds = {m.group(1): m.group(2) for m in ASSIGN.finditer(body)
             if not NOT_A_PATH.search(m.group(2))}
    hits = []
    for n, line in enumerate(body.split("\n"), 1):
        if ".txt" not in line:
            continue
        targets = [next(g for g in m.groups() if g is not None) for m in REDIRECT.finditer(line)]
        for m in PYWRITE.finditer(line):
            targets += TXT_IN_ARG.findall(m.group(1) or m.group(2) or "")
        for tok in targets:
            made, why = resolve(tok.strip("\"'"), binds)
            hits.append((n, made or "", why))
    return hits


def code_files() -> list[str]:
    return [r for r in subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True,
                                      text=True).stdout.split()
            if r.endswith(CODE)
            and not r.startswith(("references/", "tinygrad/", "runs/graphcmp/"))]


def callers(gen: str) -> int:
    """How many other tracked files NAME this generator. 0 means nothing reaches it."""
    stem = os.path.basename(gen)
    n = 0
    for rel in code_files():
        if rel == gen:
            continue
        try:
            if os.path.getsize(os.path.join(ROOT, rel)) > SIZE_CAP:
                continue
            if stem in open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read():
                n += 1
        except OSError:
            continue
    return n


def census() -> tuple[list[str], dict[str, list[str]], dict[str, set[str]]]:
    """(the hard set, repo-relative path -> every generator writing it, generator -> refusals)."""
    hard = hard_set()
    own: dict[str, list[str]] = collections.defaultdict(list)
    refused: dict[str, set[str]] = collections.defaultdict(set)
    for rel in code_files():
        for _, made, why in txt_writes(rel):
            if made is None:
                refused[rel].add(why)
            elif made in hard and rel not in own[made]:
                # EVERY writer is credited: `checks/e2e.sh` and `.agents/slop/e2epy/oracle-e2e.sh`
                # are the same driver and both write `runs/e2e/e2e-mm-gate.txt`, so keeping only
                # the first would make the answer depend on `git ls-files` sort order.
                own[made].append(rel)
    return hard, own, refused


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--gate":
        return scoped_gate(args[1:])

    hard, own, refused = census()
    attributed: collections.Counter[str] = collections.Counter()
    for rel in hard:
        for g in own.get(rel, ()):
            attributed[g] += 1
    unowned = [r for r in hard if not own.get(r)]

    print(f"  {len(hard)} `.txt` reported by checks/no-txt.py, attributed to OWNING GENERATORS\n")
    print(f"  {'files':>6}  {'reached':>7}  generator")
    for g, n in attributed.most_common():
        print(f"  {n:6d}  {callers(g):7d}  {g}")
    print(f"\n  {len(attributed)} generators own {sum(attributed.values())} credits over "
          f"{len(hard) - len(unowned)} distinct files.")
    print(f"  {len(unowned)} are named by NO write path in the tree:\n")
    for d, n in collections.Counter(os.path.dirname(u) for u in unowned).most_common():
        print(f"  {n:6d}  {d}/")
    why = collections.Counter(w for ws in refused.values() for w in ws)
    if why:
        print(f"\n  {len(refused)} generators write a `.txt` this check REFUSED to follow. "
              f"Those write paths are not credited above:")
        for reason, n in why.most_common():
            print(f"  {n:6d}  {reason}")
    return 0


def scoped_gate(names: list[str]) -> int:
    """Exit 1 if a named generator's OWN SOURCE still names a `.txt` write target.

    Read from the source rather than from the attribution set, so a generator that has been FIXED is
    answerable -- it writes none, and that is rc 0, not `no such generator`.
    """
    if not names:
        hard, own, _ = census()
        red = collections.Counter(g for rel in hard for g in own.get(rel, ()))
        if not red:
            print("  GATE  no generator writes a reported `.txt`.")
            return 0
        print(f"  GATE  {len(red)} generators still write a reported `.txt`:")
        for g, n in red.most_common():
            print(f"    {n:5d}  {g}")
        return 1

    missing = [n for n in names if not os.path.isfile(os.path.join(ROOT, n))]
    if missing:
        print(f"  GATE  no such file, so nothing was checked: {missing}")
        return 2
    red = 0
    for name in names:
        for line, _, _ in (h for h in txt_writes(name) if h[1]):
            print(f"  GATE  {name}:{line} still writes a `.txt`")
            red += 1
    if not red:
        print(f"  GATE  none of {', '.join(names)} names a `.txt` write target.")
    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())