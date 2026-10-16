#!/usr/bin/env python3
"""Would a CORRECTED `self_output_dirs()` newly authorise any path for deletion?  THE SET.

The corpus, the tokenizer, the classifier and the resolver are `checks/sweep.py`'s, LOADED BY
PATH.  Two `--plan` runs would confound the population change with the clock, so one walk, one
corpus read and one classifier are shared and ONLY the population differs between passes.

    .venv/bin/python .agents/slop/sweepdirs/delset.py
"""
from __future__ import annotations

import collections
import importlib.util
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


SW = load("sweep", os.path.join(ROOT, "checks/sweep.py"))
CEN = load("census", os.path.join(HERE, "census.py"))


def corrected(mode: str) -> tuple[str, ...]:
    """The same question, the same resolver, a population that is a WALK and not two names."""
    writes, reads = CEN.census(CEN.scope("tree"))
    out = writes - reads
    if mode == "union":
        out |= CEN.shell_belt(CEN.scope("nonpy"))
    elif mode == "files":
        out = CEN.census(CEN.scope("tree"), namer=CEN.slop_file)[0]
    return tuple(sorted(out))


_house = SW.house_excluded
_self_excludes = SW.self_excludes
EXTRA: set[str] = set()          # exact FILES the population claims, for the file-granular arm
SW.house_excluded = lambda root, rel: rel in EXTRA or _house(root, rel)
SW.self_excludes = lambda root=ROOT: _self_excludes(root) + [f":(exclude){f}" for f in sorted(EXTRA)]


MAGIC = re.compile(r"^:\((glob|exclude)\)(.*)$", re.S)


def pathspec(pattern: str) -> tuple[re.Pattern[str], bool]:
    """ONE git pathspec -> (anchored regex, negated), or rather RAISE on one it cannot read.

    **THIS EXISTS BECAUSE `git ls-tree` HAS NO PATHSPEC VOCABULARY**, and the pathspecs are the
    population. MEASURED: `git ls-tree -r --name-only HEAD -- '*.py'` prints **0 rows and exits 0**
    and `:(glob)` is `fatal: pathspec magic not supported by this command: 'glob'`. So the filter
    has to be Python, and this is the translation -- NOT A COPY of `SW.NAMED_BY`: the seven
    pathspecs stay where their generator keeps them and this reads whatever it is handed.

    **TOTAL OVER THE VOCABULARY `sweep.py` GENERATES** (`:(glob)` literals, `:(exclude)<dir>/**`,
    and one bare literal `AGENTS.md`), and it **REFUSES** any other `:(...)` magic. THAT REFUSAL IS
    THE POINT: a pathspec this cannot read must not quietly match nothing, because a corpus that
    collapses to empty reports `corpus 0 -> 0` and calls it a settled question.

    THE TWO `*`s ARE DIFFERENT FUNCTIONS AND GIT MEASURED WHICH IS WHICH: a BARE pathspec is
    fnmatch with `*` **CROSSING** `/`, `:(glob)` is fnmatch with `*` **NOT** crossing it, and a
    `**` COMPONENT matches any run of components -- **including none**, so `:(glob).agents/slop/
    **/*.py` reaches the depth-1 `.agents/slop/x.py` (MEASURED: git answers depths 3 through 8).
    Hence `**` emits `(?:.*/)?` and consumes its own separator, which is the one line that makes
    the zero-component case work.
    """
    m = MAGIC.match(pattern)
    if m:
        negated, body = m.group(1) == "exclude", m.group(2)
        star = "[^/]*"                      # :(glob): `*` stops at a separator
    elif pattern.startswith(":("):
        raise SystemExit(f"delset cannot read pathspec magic in {pattern!r}: it would match "
                         f"nothing, and a corpus of 0 reads as a settled answer")
    else:
        negated, body, star = False, pattern, ".*"   # bare: git's default, `*` CROSSES `/`
    comps = body.split("/")
    parts = []
    for i, c in enumerate(comps):
        if c != "**":
            parts.append("".join(star if k == "*" else re.escape(k) for k in c))
        elif i + 1 < len(comps):
            parts.append("(?:.*/)?")       # a `**` with a successor OWNS its separator
        else:
            parts.append(".*")              # a trailing `**` has no separator to make optional
    return re.compile("(?s:" + "/".join(parts) + r")\Z"), negated


def corpus(excluded: tuple[str, ...], copies: set[str]) -> list[str]:
    """`SW.committed_files`'s membership, with `self_output_dirs` pinned to one population.

    THE POPULATION IS THE COMMIT TREE (`CEN.committed_paths`, which is `checks/slop-declare.py:148`'s
    shape), and the FILTER is `SW.NAMED_BY` + `SW.self_excludes(ROOT)` consumed through
    `pathspec`. **`SW.tracked_files(ROOT)` IS GONE FROM THIS ARM TOO, AND IT WAS NOT A FREE PASS:
    it is `checks/sweep.py:858`, `git ls-files -z` again, so calling it would have left half this
    corpus index-sourced while the instrument stopped saying so.** Consuming it would have been
    moving the read, not removing it -- the one thing a gate like this must never do.

    **WHAT THAT COST, MEASURED:** `git ls-files` named the INDEX, which `jj` refills on every
    snapshot with INTENT-TO-ADD PLACEHOLDERS, and `head_texts` then asked `git cat-file --batch`
    for `HEAD:<name>` on an INDEX-SOURCED name. Before: `corpus()` returned **712** names,
    `head_texts()` resolved **668**, and **44 were dropped** -- and the **44 come from this arm
    exactly** (`tracked_files` ∩ `.md` ∩ `.agents/slop/` answers **513** where the tree answers
    **469**). MEASURED, `git cat-file --batch` answers `HEAD:<a placeholder>` with `<name> missing`
    (`gates/indexread-gate.py`'s trap 2), and one of the 44 is named here because it is the whole
    class in one line: **`.agents/slop/gate-surface-control.md` is in the index carrying the EMPTY
    blob `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391`, is absent from `HEAD`, and is 5 180 bytes on
    disk.** Forty-four live reports were enumerated and then thrown away without a word, and every
    verdict in `main()` was computed over the survivors. The other arm is now measured too: git's
    own pathspec set answers **347** against this translation's **349**, and all 349 minus 347 is
    accounted for -- 2 committed gates the index cannot see (`gates/upstream-pow-dtype-gate.py`,
    `gates/upstream-promo-lattice-gate.py`) and `gate-surface-control.md` -- so the translation
    itself is exact.
    """
    SW.self_output_dirs = lambda root=ROOT: excluded
    paths = CEN.committed_paths()
    if paths is None:
        raise SystemExit("`git ls-tree -r HEAD` did not answer: the corpus is UNKNOWN, not empty")
    specs = [pathspec(p) for p in (*SW.NAMED_BY, *SW.self_excludes(ROOT))]
    names = [n for n in sorted(paths)
             if any(r.match(n) for r, neg in specs if not neg)
             and not any(r.match(n) for r, neg in specs if neg)]
    names += [n for n in sorted(paths) if n.endswith(".md") and n.startswith(".agents/slop/")
              and n not in copies and not SW.house_excluded(ROOT, n)]
    return sorted(set(names))


def head_texts(names: list[str]) -> dict[str, str]:
    """ONE process for the whole corpus. `committed_files` spends 59.6 ms of `git show` per member.

    **`missing` NOW RAISES INSTEAD OF `continue`-ING, AND THAT IS THE CHANGE OF SUBSTANCE.** Every
    name `corpus()` hands over comes out of `git ls-tree -r HEAD`, so `HEAD:<name>` RESOLVES BY
    CONSTRUCTION and this branch is unreachable; it used to be the place **44 live reports** died
    without a word (`corpus`, above). A reader who cannot see its own population cannot be
    anything, so the reader that CANNOT SEE ONE OF ITS OWN MEMBERS says so. MEASURED: **0** of the
    post-fix corpus hits it, where the pre-fix corpus dropped 44 of 712.
    """
    inp = "".join(f"HEAD:{n}\n" for n in names).encode()
    out = subprocess.run(["git", "cat-file", "--batch"], cwd=ROOT, input=inp,
                         capture_output=True).stdout
    texts: dict[str, str] = {}
    i = 0
    for n in names:
        j = out.index(b"\n", i)
        hdr = out[i:j].split()
        if hdr[-1] == b"missing":
            raise SystemExit(f"HEAD:{n} is in the corpus but not in HEAD -- the population and the "
                             f"text came from different snapshots, which is the defect this file "
                             f"just fixed")
        size = int(hdr[-1])
        texts[n] = out[j + 1:j + 1 + size].decode("utf-8", "replace")
        i = j + 1 + size + 1
    return texts


def inert(shipped: tuple[str, ...], copies: set[str], t0: float) -> int:
    """Does the shipped `self_output_dirs()` remove any corpus member AT ALL?

    `checks/residue.py:EXCLUDED_DIRS` already names `residue` (`:122-134`), so `house_excluded`
    answers `True` for every `residue/` path before the entry is consulted, and `NAMED_BY`'s first
    pathspec (`:(glob).agents/slop/*.md`, `:188`) cannot reach a depth-2 path.  So the entry is
    INERT iff the two corpora are the same list.
    """
    with_shipped = corpus(shipped, copies)
    without = corpus((), copies)
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    print(f"# inert {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}  HEAD {head}")
    print(f"# shipped   self_output_dirs() = {list(shipped)} -> corpus {len(with_shipped)}")
    print(f"# no entry  self_output_dirs() = ()               -> corpus {len(without)}")
    print(f"# INERT={with_shipped == without}  "
          f"removed_by_the_entry={len(set(without) - set(with_shipped))}")
    print(f"# wall {time.time() - t0:.1f} s")
    return 0 if with_shipped == without else 1


def index(names: list[str], tokens: dict[str, tuple[set[str], set[str]]]) -> list[dict]:
    cites: list[dict[str, set[str]]] = [{}, {}]
    for nm in names:
        for belt in (0, 1):
            for tok in tokens[nm][belt]:
                for t in (tok, tok.rsplit("/", 1)[-1]):
                    cites[belt].setdefault(t, set()).add(nm)
    return cites


class Facts:
    """`verdict_for`'s four attributes.  Nothing else is read from a `Facts`, so nothing else is built."""

    def __init__(self, cites: list[dict], tracked: set[str], declared: set[str]) -> None:
        self.root, self.cites, self.tracked, self.declared = ROOT, cites, tracked, declared
        self.mentioned = set(cites[0])


def main() -> int:
    t0 = time.time()
    mode = next((m for m in ("ast", "union", "files", "inert") if f"--{m}" in sys.argv), "ast")
    shipped = tuple(SW.self_output_dirs(ROOT))      # read BEFORE anything patches the module
    rows = SW.walk_residue(ROOT)
    copies = SW.residue_copies(ROOT, [r for r, _ in rows])
    if mode == "inert":
        return inert(shipped, copies, t0)
    fixed = corrected(mode)
    tracked, declared = SW.tracked_files(ROOT), SW.declared_names()
    live = SW.live_units(60, ROOT)

    EXTRA.clear()                                    # the shipped population: dir `residue`
    before_names = corpus(shipped, copies)
    if mode == "files":
        EXTRA.update(fixed)                          # the corrected one: file-granular, dir-free
    after_names = corpus(() if mode == "files" else fixed, copies)
    texts = head_texts(sorted(set(before_names) | set(after_names)))
    before_names = [n for n in before_names if n in texts]
    after_names = [n for n in after_names if n in texts]
    tokens = {nm: (SW.mentioned_filenames(t), SW.whole_path_tokens(t)) for nm, t in texts.items()}
    fb = Facts(index(before_names, tokens), tracked, declared)
    fa = Facts(index(after_names, tokens), tracked, declared)

    lost = set(before_names) - set(after_names)
    gained = set(after_names) - set(before_names)
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    print(f"# delset {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}  HEAD {head}  mode={mode}")
    print(f"# shipped  self_output_dirs() = {len(shipped)} {list(shipped)}")
    print(f"# fixed    population = {len(fixed)}: {sorted(set(fixed) - set(shipped))} + shipped")
    print(f"# corpus   {len(before_names)} -> {len(after_names)} : -{len(lost)} +{len(gained)}")
    for n in sorted(lost):
        print(f"#   lost  {n}")
    for n in sorted(gained):
        print(f"#   gained {n}")

    delta: list[tuple[str, str, int, str]] = []
    counts, before = collections.Counter(), collections.Counter()
    for rel, sz in rows:
        vb = SW.verdict_for(rel, fb.mentioned, fb, live)
        va = SW.verdict_for(rel, fa.mentioned, fa, live)
        counts[(SW.bucket(vb), SW.bucket(va))] += 1
        before[SW.bucket(vb)] += 1
        if SW.bucket(va) != SW.bucket(vb):
            delta.append((vb, va, sz, rel))
    print(f"# rows     {len(rows)} classified twice; before : "
          + "  ".join(f"{b}={n}" for b, n in sorted(before.items())))
    for (b, a), n in sorted(counts.items()):
        if b != a:
            print(f"#   moved {b} -> {a}: {n}")
    for vb, va, sz, rel in sorted(delta, key=lambda d: (d[1], d[3])):
        flag = "NEW-DELETE" if va == "DELETE" else "MOVED     "
        print(f"#   {flag} {sz:8d} B  {rel}\n#              {SW.bucket(vb)} -> {va}")
    print(f"# wall {time.time() - t0:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
