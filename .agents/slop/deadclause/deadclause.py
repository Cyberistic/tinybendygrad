#!/usr/bin/env python3
"""THE TWO DEAD DUPLICATES IN `checks/residue.py`, DELETED, AND TWO PLANTS THAT FAIL BEFORE THE DELETE.

`checks/residue.py` classifies ONLY the rows `sweep.verdict_for` calls `DELETE`. `sweep` answers
`UNKNOWN:commit-or-drop` and `UNKNOWN:commit-the-report-that-explains-it` for EXACTLY the rows residue's
`untracked` and `witness` branches named -- same `tracked` set, same `TOOL_EXT`, same witness test. So
those branches were a SECOND AUTHORITY OVER ONE QUESTION: plantable inside `classify` (1 -> 0) and
unreachable in the pipeline that calls it, deciding 0 rows while sweep's originals fire 114 and 110.

THE PLANTS. Each plant builds a one-row git tree and classifies it with the PRE-change module
(`git show HEAD:checks/residue.py`) and the POST-change module (the working file), asserting:
  * POST falls through to `UNNAMED` (the branch is gone) -- an assertion the PRE file FAILS;
  * `sweep.verdict_for` still returns the SAME `UNKNOWN:` tag for that row, so no verdict was lost.

`--census pre|post` runs the production pipeline in memory over the real tree and prints both producers'
live counts, so the `8 of 11 -> 8 of 9` claim is measured, not asserted. No production file is written
and no `.txt` file is created.
"""
from __future__ import annotations

import collections
import importlib.util
import inspect
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))   # .agents/slop/deadclause -> repo root
CHECKS = os.path.join(ROOT, "checks")
WORD = r"[a-z][a-z0-9-]+"


def load(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def pre_module():
    """`checks/residue.py` at HEAD. `HERE` is repointed to `checks/` so `sweep_module()` and
    `authorities()` resolve the REAL neighbours instead of the temp directory the file sits in."""
    src = subprocess.run(["git", "show", "HEAD:checks/residue.py"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout
    fh = tempfile.NamedTemporaryFile("w", suffix=".py", dir=HERE, delete=False)
    fh.write(src)
    fh.close()
    mod = load(fh.name, "residue_pre")
    mod.HERE = CHECKS
    mod._SRC_PATH = fh.name
    return mod, fh.name


_TREES: list[str] = []


def tree(files: dict[str, str], untracked=()) -> str:
    tmp = tempfile.mkdtemp(dir=HERE, prefix="tree-")
    _TREES.append(tmp)
    for rel, content in files.items():
        p = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(content)
    g = lambda *a: subprocess.run(["git", *a], cwd=tmp, capture_output=True, text=True)  # noqa: E731
    g("init", "-q")
    g("add", "-A")
    for rel in untracked:
        g("rm", "-q", "--cached", rel)
    old = time.time() - 2592000
    for rel in files:
        os.utime(os.path.join(tmp, rel), (old, old))
    g("-c", "user.email=p@p", "-c", "user.name=p", "commit", "-qm", "x")
    return tmp


def classify(mod, root: str, rel: str) -> tuple[str, str]:
    tracked = mod.git_tracked(root)
    files = mod.walk(root)
    cites: dict[str, set[str]] = collections.defaultdict(set)
    for r in sorted(tracked):
        if mod.excluded(r):
            continue
        try:
            blob = open(os.path.join(root, r), "rb").read(4 << 20).decode("utf-8", "replace")
        except OSError:
            continue
        mod.index_citations(cites, root, r, blob)
    kw = dict(sweep_named=set(), first_pass=lambda a, b: "DELETE", auth=mod.authorities(),
              age=mod.dir_ages(root, files), window=0, twins=mod.outside_twins(root, tracked, files),
              cites=cites, tracked=tracked, disabled=set())
    sig = inspect.signature(mod.classify)
    _sw, v, why = mod.classify(root, rel, 0, **{k: x for k, x in kw.items() if k in sig.parameters})
    return v, why


CASES = {
    "commit-or-drop": dict(
        files={".agents/slop/co/orphan.rows": "orphan\n", "keep/README.md": "keep\n"},
        untracked=[".agents/slop/co/orphan.rows"], row=".agents/slop/co/orphan.rows"),
    "commit-the-report-that-explains-it": dict(
        files={".agents/slop/cr/tool.py": "print(1)\n"}, row=".agents/slop/cr/tool.py"),
}


def plant(label: str) -> bool:
    c = CASES[label]
    root = tree(c["files"], c.get("untracked", []))
    pre, path = pre_module()
    try:
        pv, _pw = classify(pre, root, c["row"])
        qv, qw = classify(load(os.path.join(CHECKS, "residue.py"), "residue_post"), root, c["row"])
    finally:
        os.unlink(path)
    sweep = load(os.path.join(CHECKS, "sweep.py"), "sweep_probe")
    f = sweep.Facts(root)
    sv = sweep.verdict_for(c["row"], f.mentioned, f)
    post_ok = qv == "UNNAMED" and f"needs={label}" not in qw
    pre_fails = pv == "UNKNOWN" and f"needs={label}" in _pw
    sweep_ok = sv.startswith(f"UNKNOWN:{label}")
    print(f"# plant {label}")
    print(f"#   post  -> {qv:8s} needs={label} present: {'no' if f'needs={label}' not in qw else 'YES'} "
          f"{'PASS' if post_ok else 'FAIL'}")
    print(f"#   pre   -> {pv:8s} ({'FAILS the post assertion, as required' if pre_fails else 'PASSES?'})")
    print(f"#   sweep -> {sv.partition(' ')[0]} {'(verdict survives the delete)' if sweep_ok else '(LOST!)'}")
    return post_ok and pre_fails and sweep_ok


def _labels(mod) -> set[str]:
    src = getattr(mod, "_SRC_PATH", os.path.join(CHECKS, "residue.py"))
    return set(re.findall(rf"needs=({WORD})", open(src).read()))


def _needs(mod, root, rows, auth, age, twins, cites, tracked, disabled) -> collections.Counter:
    """`needs=` counts for one module over a fixed row list. `first_pass` is a stub: only `why` matters."""
    rn: collections.Counter = collections.Counter()
    sig = inspect.signature(mod.classify)
    kw = dict(sweep_named=set(), first_pass=lambda a, b: "", auth=auth, age=age, window=0,
              twins=twins, cites=cites, tracked=tracked, disabled=disabled)
    kw = {k: v for k, v in kw.items() if k in sig.parameters}
    for rel, sz, _f in rows:
        _sw, _v, why = mod.classify(root, rel, sz, **kw)
        m = re.search(rf"needs=({WORD})", why)
        if m:
            rn[m.group(1)] += 1
    return rn


def diff_mode() -> int:
    """One frozen scan of the live tree, classified by BOTH modules: the only difference is the delete.

    One walk, one twin pass, one belt pass -- so pre and post see the SAME population and the SAME
    citations, and any delta is the delete rather than the clock. This is the 'loses nothing' proof.
    """
    pre, path = pre_module()
    post = load(os.path.join(CHECKS, "residue.py"), "residue_post")
    cache: dict[tuple[str, str], set[str]] = {}
    for mod in (pre, post):                       # one `git grep` per name, SHARED by both modules
        orig = mod.belt_git
        mod.belt_git = lambda root, name, _o=orig: cache.setdefault(  # noqa: E731
            (root, name), _o(root, name))
    try:
        sweep = post.sweep_module()
        named = sweep.mentioned_filenames(sweep.committed_named_text(ROOT))
        tracked = post.git_tracked(ROOT)
        files = post.walk(ROOT)
        rows = [(rel, sz, sweep.verdict_for(rel, named)) for rel, sz in files]
        residue_rows = [r for r in rows if r[2] == "DELETE"]
        twins = post.outside_twins(ROOT, tracked, residue_rows)
        cites: dict[str, set[str]] = collections.defaultdict(set)
        for rel in sorted(tracked):
            if post.excluded(rel):
                continue
            try:
                blob = open(os.path.join(ROOT, rel), "rb").read(4 << 20).decode("utf-8", "replace")
            except OSError:
                continue
            post.index_citations(cites, ROOT, rel, blob)
        auth, age = post.authorities(), post.dir_ages(ROOT, files)
        pre_n = _needs(pre, ROOT, residue_rows, auth, age, twins, cites, tracked, set())
        post_n = _needs(post, ROOT, residue_rows, auth, age, twins, cites, tracked, set())
        sn: collections.Counter = collections.Counter()
        for _rel, _sz, fv in rows:
            m = re.match(rf"UNKNOWN:({WORD})", fv)
            if m:
                sn[m.group(1)] += 1
        labels = sorted(_labels(pre) | _labels(post))
        print(f"# DIFF: {len(rows)} walked rows, {len(residue_rows)} reach residue.classify "
              f"(one frozen scan, both modules)")
        print("#   residue needs= PRE : " + " ".join(f"{k}={pre_n.get(k, 0)}" for k in labels))
        print("#   residue needs= POST: " + " ".join(f"{k}={post_n.get(k, 0)}" for k in labels))
        print(f"#   residue OUTPUT IDENTICAL: {pre_n == post_n}")
        print(f"#   deleted from pre: {sorted(_labels(pre) - _labels(post))}")
        print("#   sweep UNKNOWN: " + " ".join(f"{k}={sn.get(k, 0)}" for k in sorted(sn)))
        assert pre_n == post_n, "the delete changed the residue output"
    finally:
        os.unlink(path)
    return 0


def main() -> int:
    if "--diff" in sys.argv:
        return diff_mode()
    ok = all([plant(label) for label in CASES])
    print(f"# PLANTS {'PASS -- each fails on the pre-change file' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        for t in _TREES:
            shutil.rmtree(t, ignore_errors=True)
