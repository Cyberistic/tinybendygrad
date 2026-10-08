#!/usr/bin/env python3
"""VERBATIM DUPLICATED COMMENT BLOCKS. The class that needs no taste judgement.

`redundancy.py` ranks by Jaccard, which needs a threshold and therefore needs
taste. This needs none: two runs of >= 2 consecutive comment lines whose text is
byte-equal after strip. Either it is a paste or it is not, and a paste is always
wrong -- the same claim twice is not redundancy-with-a-reason the way a
repetition-with-a-different-reason can be.

A paste that was later APPENDED TO is the common form and the reason this class is
worth an instrument: the edit lands on the second copy, so the file ends up
carrying the original text AND the original text plus the new sentence. Deleting
the shorter copy loses nothing, because the longer one is a superset -- and that
superset property is CHECKED here, not assumed:

  EXACT    the runs are byte-equal.
  SUBSET  one run is a proper PREFIX of a longer run elsewhere. Deleting the
          short copy is provably lossless, and the tool says so.

Population: every tracked .py, discovered by os.walk and intersected with
`git ls-tree -r HEAD` blobs. Shadow copies are reported separately and not
counted in the editable total, because trimming a copy of the port does not
change the port.
"""

import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from paraphrase import prose_lines  # noqa: E402

ROOTS = ("checks", "gates", "tinybendygrad", ".agents/slop")
SHADOW = ("/.agents/slop/strays/", "/.agents/slop/argowner/", "/.agents/slop/rf2root/",
          "/.agents/slop/portzz/", "/.agents/slop/denominator/probe/",
          "/.agents/slop/corpuswire/", "/.agents/slop/census7/",
          "/.agents/slop/figure2/plant/", "/.agents/slop/clearfix/gk",
          "/.agents/slop/e2esh/", "/.agents/slop/gatecensus/")


def runs(lines: list[tuple[int, str]]) -> list[list[tuple[int, str]]]:
    """Maximal runs of consecutive comment linenos."""
    out, cur = [], []
    for item in lines:
        if cur and item[0] == cur[-1][0] + 1:
            cur.append(item)
        else:
            if cur:
                out.append(cur)
            cur = [item]
    if cur:
        out.append(cur)
    return out


NOT_PROSE = re.compile(
    r"^(?:noqa|type|pylint|flake8|ruff|fmt|isort|pragma)\s*:.*"   # a lint DIRECTIVE
    r"|[-=#*~_+.^\s]*$"                                            # a `# ====` RULER
)


def repeats_within(run: list[tuple[int, str]]) -> list[tuple[str, list[int]]]:
    """A line whose stripped text occurs 2+ times INSIDE ONE maximal run.

    v1 of this file compared whole maximal runs, and found 0 sites in 823 files --
    including the one real paste it was written for, `.agents/slop/e2epy/diff.py`,
    where lines 124-126 repeat at 127-129 and line 129 continues into a new
    sentence. Two consecutive comments are ONE maximal run, so grouping by run
    hid the duplication INSIDE the group. The unit of comparison has to be the
    line, scoped to a run.
    """
    seen: dict[str, list[int]] = {}
    for n, text in run:
        key = " ".join(text.split())
        if key and not NOT_PROSE.match(key):
            seen.setdefault(key, []).append(n)
    return [(text, ns) for text, ns in seen.items() if len(ns) > 1]


def main() -> int:
    tracked = set(subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", *ROOTS],
        capture_output=True, text=True, check=True).stdout.splitlines())
    files = []
    for root in ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            files += [os.path.join(dirpath, f) for f in filenames if f.endswith(".py")]
    files = sorted(set(files) & tracked)

    exact, subset, shadow_hits = [], [], []
    for path in files:
        for run in runs(prose_lines(path)):
            for text, nums in repeats_within(run):
                rec = (path, nums, text)
                (shadow_hits if any(s in path for s in SHADOW) else exact).append(rec)
        blocks = [b for b in runs(prose_lines(path))
                  if len(b) >= 2 and any(t.strip() for _, t in b)]
        seen: dict[tuple[str, ...], list[int]] = {}
        for block in blocks:
            key = tuple(" ".join(t.split()) for _, t in block)
            if all(NOT_PROSE.match(k) for k in key):
                continue
            seen.setdefault(key, []).append(block[0][0])
        for key, starts in seen.items():
            if len(starts) < 2:
                continue
            rec = (path, starts, list(key))
            (shadow_hits if any(s in path for s in SHADOW) else exact).append(rec)
        keys = sorted(seen, key=len)
        for short in keys:
            if not any(short):
                continue
            for long in keys:
                if len(long) > len(short) and tuple(long[:len(short)]) == short:
                    if not any(seen[long]):
                        continue
                    rec = (path, [seen[short][0], seen[long][0]], list(short))
                    (shadow_hits if any(s in path for s in SHADOW) else subset).append(rec)

    print(f"population: {len(files)} tracked .py files, os.walk x git ls-tree -r HEAD\n")
    print(f"EXACT  a comment LINE whose text occurs 2+ times inside one consecutive "
          f"run, or a >=2-line run appearing byte-identical 2+ times: {len(exact)} "
          f"sites in {len({e[0] for e in exact})} files\n")
    for path, starts, key in exact:
        print(f"  {path}  lines {', '.join(str(s) for s in starts)}")
        for line in (key if isinstance(key, list) else [key])[:6]:
            print(f"      | {str(line)[:100]}")

    print(f"\nSUBSET  a short run that is a PROPER PREFIX of a longer run elsewhere in "
          f"the same file (deleting the short copy is provably lossless): "
          f"{len(subset)} sites in {len({e[0] for e in subset})} files\n")
    for path, (short_at, long_at), key in subset:
        print(f"  {path}  short@{short_at} is a prefix of @{long_at}")
        for line in key[:6]:
            print(f"      | {str(line)[:100]}")

    print(f"\nshadow copies, REPORTED AND NOT EDITED: {len(shadow_hits)} sites in "
          f"{len({e[0] for e in shadow_hits})} files")
    for path, starts, key in shadow_hits[:6]:
        print(f"  {path}  lines {', '.join(str(s) for s in starts)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
