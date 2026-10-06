#!/usr/bin/env python3
"""A CENSUS OF EVERY `needs=` CLAUSE, AND WHETHER ITS NUMBER MOVES WHEN ITS CONDITION IS CHANGED.

**BEFORE ADDING A `needs=`, ESTABLISH THAT ITS NUMBER MOVES.** A clause invariant under the change it
claims to measure is not a clause. `gates/retention-check.py`'s clause II counted `return`s for a
STRUCTURAL property and deleting the `finally` moved it by ZERO; `G8`'s disarm moved its count by 0 at
every window. This file applies the same test to every `needs=` in the tree.

DISCOVERY IS A WALK, NOT A LIST (doctrine 1). The population is found two ways and both are reported:

  A  the literal token `needs=<label>`, by regex over every CODE file in the tree.
  B  the tagged verdict `UNKNOWN:<label>`, the SAME concept spelled without the token, in `sweep.py`.

Prose and generated reports ECHO a label; they do not declare one, so `discover()` separates the two by
reporting declaration sites (code) and echo sites (`.md`/`.rows`) apart rather than as one set.

Each label gets a fixture TREE built under a scratch root, and a planted change that makes its own
condition false. The number is the count of rows whose `why` carries that `needs=`. A MOVES row has a
before>=1, after=0 pair; an INVARIANT row does not move; UNREACHABLE means no tree here can make the
condition the deciding clause, and the report says WHY and what would.

Nothing in the production tree is written: every fixture is `tempfile.mkdtemp`, git-init'd and
git-added like `checks/residue.py`'s own plant, and the live tree's hashes are read before and after.
"""
from __future__ import annotations

import collections
import hashlib
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SELF = os.path.relpath(HERE, ROOT)
SKIP = {".git", "node_modules", "references", ".venv", "__pycache__", SELF}
CODE_EXT = (".py", ".sh", ".bend", ".mjs", ".js", ".ts")
ECHO_EXT = (".md", ".rows", ".tsv", ".out", ".err")
WORD = r"[a-z][a-z0-9-]+"
SCRATCH = os.path.join(HERE, "scratch")            # the scratch root the task asks for; cleaned after
_TMP: list[str] = []


def load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


residue = load("residue", os.path.join(ROOT, "checks/residue.py"))
sweep = load("sweep", os.path.join(ROOT, "checks/sweep.py"))


def discover(root: str, pattern: str) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    """(code sites, echo sites), keyed by label, by WALK. This audit's own tree is skipped."""
    code: dict[str, set[str]] = collections.defaultdict(set)
    echo: dict[str, set[str]] = collections.defaultdict(set)
    rx = re.compile(pattern)
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP and os.path.join(dirpath, d) != HERE]
        for f in files:
            ext = os.path.splitext(f)[1]
            if ext not in CODE_EXT + ECHO_EXT:
                continue
            p = os.path.join(dirpath, f)
            try:
                text = open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            bucket = code if ext in CODE_EXT else echo
            for m in rx.finditer(text):
                bucket[m.group(1)].add(os.path.relpath(p, root))
    return dict(code), dict(echo)


# ------------------------------------------------------------------ the scratch tree
def build(files: dict[str, str], links: dict[str, str] | None = None,
          untracked: set[str] | None = None) -> str:
    """A git tree under a fresh dir in the scratch root. The live tree is never touched."""
    os.makedirs(SCRATCH, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="tree-", dir=SCRATCH)
    _TMP.append(tmp)
    for rel, content in files.items():
        if rel in (links or {}):
            continue
        p = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(content)
    for rel, target in (links or {}).items():
        p = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        os.symlink(target, p)
    g = lambda *a: subprocess.run(["git", *a], cwd=tmp, capture_output=True, text=True)  # noqa: E731
    g("init", "-q")
    g("add", "-A")
    for rel in (untracked or ()):
        g("rm", "-q", "--cached", rel)
    old = time.time() - 2592000            # old mtime: LIVE (window 0) cannot fire by accident
    for rel in files:
        if rel not in (links or {}):
            os.utime(os.path.join(tmp, rel), (old, old))
    g("-c", "user.email=p@p", "-c", "user.name=p", "commit", "-qm", "x")
    return tmp


# ------------------------------------------------------------------ the two producers
def residue_counts(root: str, index_excluded: bool = False) -> dict[str, tuple[str, str]]:
    tracked = residue.git_tracked(root)
    files = residue.walk(root)
    age = residue.dir_ages(root, files)
    auth = residue.authorities()
    twins = residue.outside_twins(root, tracked, files)
    cites: dict[str, set[str]] = collections.defaultdict(set)
    for rel in sorted(tracked):
        if not index_excluded and residue.excluded(rel):
            continue
        try:
            blob = open(os.path.join(root, rel), "rb").read(4 << 20).decode("utf-8", "replace")
        except OSError:
            continue
        residue.index_citations(cites, root, rel, blob)
    out = {}
    for rel, sz in files:
        _f, v, why = residue.classify(root, rel, sz, sweep_named=set(),
                                      first_pass=lambda a, b: "DELETE", auth=auth, age=age,
                                      window=0, twins=twins, cites=cites, tracked=tracked,
                                      disabled=set())
        out[rel] = (v, why)
    return out


# ------------------------------------------------------------------ the fixtures
BASE = {".agents/slop/README.md": "# residue root\n", "keep/orig.rows": "name=shared value=1\n"}

# (label, plant files, change(files, links, untracked) -> None, links, untracked, index_excluded)
def _noop(*_a):
    pass


def _rename(src, dst):
    def go(files, links, untracked):
        if src in links:
            links[dst] = links.pop(src)
        files[dst] = files.pop(src, "x\n")
        if src in untracked:
            untracked.discard(src)
            untracked.add(dst)
    return go


def _regularize(path):
    def go(files, links, _u):
        links.pop(path, None)
        files[path] = "not a symlink any more\n"
    return go


def _drop(path):
    def go(files, links, _u):
        files.pop(path, None)
        links.pop(path, None)
    return go


def _track(path):
    def go(_f, _l, untracked):
        untracked.discard(path)
    return go


def _write(path, content):
    def go(files, _l, _u):
        files[path] = content
    return go


RESIDUE_CASES = [
    ("owner-decision",
     {".agents/slop/e2e/thing.rows": "x\n"}, _rename(".agents/slop/e2e/thing.rows",
                                                    ".agents/slop/plain/thing.rows"),
     {}, set(), False),
    ("readlink-target",
     {".agents/slop/sym/thing.rows": "x\n"}, _regularize(".agents/slop/sym/thing.rows"),
     {".agents/slop/sym/thing.rows": "README.md"}, set(), False),
    # belt A (git -w -F) sees `gate.sh` inside `gate.sh.bak`; belt B (str.translate) reads
    # `gate.sh.bak` as ONE token. The row is named exactly once, so belt B is nonempty and belt A is
    # a SUPERSET -- the disagreement is the extra citer, and only removing it makes the belts agree.
    ("belts-disagree",
     {".agents/slop/bd/gate.sh": "x\n", "keep/exact.md": "gate.sh\n", "keep/suffix.md": "gate.sh.bak\n"},
     _write("keep/suffix.md", "\n"), {}, set(), False),
    ("residue-internal-citer",
     {".agents/slop/ri/thing.rows": "x\n", ".agents/slop/ri/report.md": "see thing.rows\n"},
     _write("keep/ext.md", "thing.rows\n"), {}, set(), False),
    ("commit-or-drop",
     {".agents/slop/co/orphan.rows": "x\n"}, _track(".agents/slop/co/orphan.rows"), {},
     {".agents/slop/co/orphan.rows"}, False),
    ("commit-the-report-that-explains-it",
     {".agents/slop/cr/tool.py": "print(1)\n"},
     _write(".agents/slop/cr/why.md", "the report that explains this tool\n"), {}, set(), False),
    # The condition belt C looks for, planted in the MOST GENEROUS index: the SELF report IS indexed
    # as a citer. belt A excludes `.agents/slop/residue/**` by pathspec, so the row reaches
    # `belts-disagree` first, at every witness strength. No fixture can make belt C the clause.
    ("unstage-self",
     {".agents/slop/self/x.rows": "x\n",
      ".agents/slop/residue/000-the-residue.md": ".agents/slop/self/x.rows is a row\n"},
     _noop, {}, set(), True),
]

# sweep's belts SHARE NO PATTERN WITH residue's: belt A is `mentioned_filenames` (a regex whose final
# segment `\.[A-Za-z0-9]+` truncates a hyphenated name) and belt B is `whole_path_tokens`. So a citer
# reading `gate.sh-extra` yields `gate.sh` for belt A and `gate.sh-extra` for belt B -- the SWEEP
# disagreement -- while residue's git-vs-translate pair needs the `.bak` suffix instead. The two
# producers genuinely need different fixtures, and pretending otherwise would test one and claim both.
SWEEP_CASES = [
    ("belts-disagree",
     {".agents/slop/bd/gate.sh": "x\n", "checks/namer.md": "gate.sh-extra\n"},
     _write("checks/namer.md", "gate.sh\n"), {}, set()),
    ("residue-internal-citer",
     {".agents/slop/ri/thing.rows": "x\n", ".agents/slop/ri/report.md": "see thing.rows\n"},
     _write("checks/ext.md", "thing.rows\n"), {}, set()),
    ("commit-or-drop",
     {".agents/slop/co/orphan.rows": "x\n"}, _track(".agents/slop/co/orphan.rows"), {},
     {".agents/slop/co/orphan.rows"}),
    ("commit-the-report-that-explains-it",
     {".agents/slop/cr/tool.py": "print(1)\n"},
     _write(".agents/slop/cr/why.md", "the report that explains this tool\n"), {}, set()),
]


def run_residue_case(case):
    label, plant, change, links, untracked, index_excluded = case
    before_rows = residue_counts(build(dict(BASE, **plant), links, untracked), index_excluded)
    files, links2, untracked2 = dict(BASE, **plant), dict(links), set(untracked)
    change(files, links2, untracked2)
    after_rows = residue_counts(build(files, links2, untracked2), index_excluded)
    before = collections.Counter(re.search(rf"needs=({WORD})", w).group(1)
                                 for _v, w in before_rows.values()
                                 if re.search(rf"needs=({WORD})", w))
    after = collections.Counter(re.search(rf"needs=({WORD})", w).group(1)
                                for _v, w in after_rows.values()
                                if re.search(rf"needs=({WORD})", w))
    return before, after, before_rows, after_rows


def run_sweep_case(case):
    _label, plant, change, links, untracked = case
    def rows(root):
        f = sweep.Facts(root)
        return {rel: (sweep.verdict_for(rel, f.mentioned, f), "") for rel, _sz in f.files}
    before_rows = rows(build(dict(BASE, **plant), links, untracked))
    files, links2, untracked2 = dict(BASE, **plant), dict(links), set(untracked)
    change(files, links2, untracked2)
    after_rows = rows(build(files, links2, untracked2))
    before = collections.Counter(re.match(rf"UNKNOWN:({WORD})", v).group(1)
                                 for v, _w in before_rows.values() if re.match(rf"UNKNOWN:({WORD})", v))
    after = collections.Counter(re.match(rf"UNKNOWN:({WORD})", v).group(1)
                                for v, _w in after_rows.values() if re.match(rf"UNKNOWN:({WORD})", v))
    return before, after, before_rows, after_rows


# The one row each case is ABOUT, so the printed pair is a verdict on a row, not just a delta.
SUBJ_BEFORE = {
    "owner-decision": ".agents/slop/e2e/thing.rows",
    "readlink-target": ".agents/slop/sym/thing.rows",
    "belts-disagree": ".agents/slop/bd/gate.sh",
    "residue-internal-citer": ".agents/slop/ri/thing.rows",
    "commit-or-drop": ".agents/slop/co/orphan.rows",
    "commit-the-report-that-explains-it": ".agents/slop/cr/tool.py",
    "unstage-self": ".agents/slop/self/x.rows",
}
SUBJ_AFTER = dict(SUBJ_BEFORE, **{"owner-decision": ".agents/slop/plain/thing.rows"})


def live_census(root: str = ROOT) -> tuple[collections.Counter, collections.Counter, int, int]:
    """The counts the two producers print TODAY on the real tree, computed in memory, no file written.

    THE PLANTED NUMBER AND THE LIVE NUMBER ARE DIFFERENT CLAIMS. A class can be plantable and still fire
    on ZERO rows, and **a condition that never fires is not a condition** -- so a label whose live count
    is 0 is reported as such, whatever its plant does.
    """
    named = sweep.mentioned_filenames(sweep.committed_named_text(root))
    tracked = residue.git_tracked(root)
    files = residue.walk(root)
    age = residue.dir_ages(root, files)
    auth = residue.authorities()
    first = lambda rel, n: sweep.verdict_for(rel, n)            # noqa: E731
    rows = [(rel, sz, first(rel, named)) for rel, sz in files]
    residue_rows = [r for r in rows if r[2] == "DELETE"]
    twins = residue.outside_twins(root, tracked, residue_rows)
    cites: dict[str, set[str]] = collections.defaultdict(set)
    for rel in sorted(tracked):
        if residue.excluded(rel):
            continue
        try:
            blob = open(os.path.join(root, rel), "rb").read(4 << 20).decode("utf-8", "replace")
        except OSError:
            continue
        residue.index_citations(cites, root, rel, blob)
    rn: collections.Counter = collections.Counter()
    for rel, sz, _f in residue_rows:
        _sw, _v, why = residue.classify(root, rel, sz, sweep_named=named, first_pass=first,
                                        auth=auth, age=age, window=0, twins=twins, cites=cites,
                                        tracked=tracked, disabled=set())
        m = re.search(rf"needs=({WORD})", why)
        if m:
            rn[m.group(1)] += 1
    sn: collections.Counter = collections.Counter()
    for _rel, _sz, fv in rows:
        m = re.match(rf"UNKNOWN:({WORD})", fv)
        if m:
            sn[m.group(1)] += 1
    return rn, sn, len(rows), len(residue_rows)


def hash_live() -> dict[str, str]:
    return {rel: hashlib.sha256(open(os.path.join(ROOT, rel), "rb").read()).hexdigest()
            for rel in ("checks/residue.py", "checks/sweep.py")}


def main() -> int:
    if "--live" in sys.argv:
        rn, sn, nrows, ndel = live_census(ROOT)
        print(f"# LIVE CENSUS over the real tree: {nrows} walked rows, {ndel} reach residue.classify "
              f"(sweep=DELETE)")
        print("#   residue `needs=` (of its DELETE population)")
        for k in sorted(set(rn) | set(discover(ROOT, rf"needs=({WORD})")[0])):
            print(f"#     {k:40s} {rn.get(k, 0):6d}   {'FIRES' if rn.get(k) else 'NEVER FIRES LIVE'}")
        print("#   sweep `UNKNOWN:` (of every walked row)")
        for k in sorted(set(sn) | set(discover(ROOT, rf"UNKNOWN:({WORD})")[0])):
            print(f"#     {k:40s} {sn.get(k, 0):6d}   {'FIRES' if sn.get(k) else 'NEVER FIRES LIVE'}")
        return 0
    literal_code, literal_echo = discover(ROOT, rf"needs=({WORD})")
    tagged_code, tagged_echo = discover(ROOT, rf"UNKNOWN:({WORD})")
    print("# DISCOVERY (a walk, not a list; this audit's own tree skipped)")
    for tag, code, echo in (("A needs=", literal_code, literal_echo),
                            ("B UNKNOWN:", tagged_code, tagged_echo)):
        files = set().union(*code.values()) if code else set()
        print(f"#   {tag:12s} -> {len(code)} labels in {len(files)} code files; "
              f"{len(set().union(*echo.values())) if echo else 0} echo files")
        for k in sorted(code):
            print(f"#     {tag}{k:38s} {sorted(code[k])}")
    union = sorted(set(literal_code) | set(tagged_code))
    print(f"#   union of DECLARED labels: {len(union)} -> {union}")
    print()

    live_before = hash_live()
    verdicts = []
    print("# RESIDUE (checks/residue.py, the literal `needs=` producer)")
    print(f"#   {'label':40s} {'n':>2s} {'after':>5s}  class   verdict pair on the subject row")
    for case in RESIDUE_CASES:
        label = case[0]
        before, after, before_rows, after_rows = run_residue_case(case)
        b, a = before.get(label, 0), after.get(label, 0)
        bv, bw = before_rows.get(SUBJ_BEFORE[label], ("?", ""))
        av = after_rows.get(SUBJ_AFTER[label], ("(row gone)", ""))[0]
        if label == "unstage-self":
            cls = "UNREACHABLE"
            note = f"row -> {bv}: {bw[:70]}"
        elif b >= 1 and a == 0:
            cls = "MOVES"
            note = f"{bv} -> {av}"
        elif b == a:
            cls = "INVARIANT"
            note = f"{bv} -> {av} (unchanged)"
        else:
            cls = "CHECK"
            note = f"before={b} after={a}"
        verdicts.append((label, b, a, cls, note))
        print(f"#   {label:40s} {b:>2d} {a:>5d}  {cls:9s} {note}")
    print()

    print("# SWEEP (checks/sweep.py, the tagged `UNKNOWN:<label>` producer)")
    print(f"#   {'label':40s} {'n':>2s} {'after':>5s}  class   verdict pair on the subject row")
    for case in SWEEP_CASES:
        label = case[0]
        before, after, before_rows, after_rows = run_sweep_case(case)
        b, a = before.get(label, 0), after.get(label, 0)
        bv = before_rows.get(SUBJ_BEFORE[label], ("?", ""))[0]
        av = after_rows.get(SUBJ_AFTER[label], ("(row gone)", ""))[0]
        cls = "MOVES" if b >= 1 and a == 0 else ("INVARIANT" if b == a else "CHECK")
        verdicts.append((f"sweep:{label}", b, a, cls, f"{bv} -> {av}"))
        print(f"#   {label:40s} {b:>2d} {a:>5d}  {cls:9s} {bv} -> {av}")
    print()

    live_after = hash_live()
    same = live_before == live_after
    print("# LIVE TREE UNTOUCHED: " + ("yes, hashes identical" if same else "NO -- CHANGED!"))
    for rel in live_before:
        print(f"#   {rel} {live_before[rel][:16]} -> {live_after[rel][:16]}")
    moved = [v for v in verdicts if v[3] == "MOVES"]
    inv = [v for v in verdicts if v[3] == "INVARIANT"]
    unr = [v for v in verdicts if v[3] == "UNREACHABLE"]
    print(f"\n# CLASSES: MOVES {len(moved)}  INVARIANT {len(inv)}  UNREACHABLE {len(unr)} "
          f"(of {len(verdicts)})")
    return 0 if same else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        for d in _TMP:
            shutil.rmtree(d, ignore_errors=True)
        shutil.rmtree(SCRATCH, ignore_errors=True)
