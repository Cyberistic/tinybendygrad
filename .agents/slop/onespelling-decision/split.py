#!/usr/bin/env python3
"""READ-ONLY. Decides how many prose-basename-citation rows each branch of a SPLIT would get.

The census's OWN definition is reused verbatim, not re-invented, so the population here is the
population `census.py:417-426` computes:

    BACKTICK = re.compile(r"`([^`\\n]+)`")
    token    : "/" not in t and re.fullmatch(r"[\\w.+-]*\\.[A-Za-z0-9]+", t)
    ambiguous: the token is the basename of >= 2 committed paths

Two passes over the committed .md, one `git cat-file --batch` each, one process, no writes outside
this directory.  Pass 1 finds the cited set (a set of strings, not a list of lines).  Pass 2 keeps
per-LINE classification for the ambiguous set only, so memory is O(#ambiguous), not O(#citations).

A citing line is OPERATIONAL when it is inside a fenced code block or an indented code block:
  * FENCED    -- between an opening fence (` ``` ` or `~~~`, <=3 leading spaces, optional info
                 string) and the next line that is only that fence character, >= as long, no info.
  * INDENTED   -- begins with a tab or 4+ spaces, is not inside a fence, and the PREVIOUS line is
                 blank (markdown requires the blank line; without it this is list continuation).
A row is OPERATIONAL if AT LEAST ONE of its citing lines is operational, which is the whole point
of the SPLIT: one runnable citation makes the bare basename a thing a reader must resolve to act.

`slash` records whether the citing line carries any `/` anywhere -- a mechanical proxy for "the
line already names a path", i.e. an in-context disambiguator.  It is reported as a CROSS-TAB, not
applied as a rule, because the precision audit showed a purely mechanical discharge does not
discriminate.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PROSE_EXT = ".md"
BACKTICK = re.compile(r"`([^`\n]+)`")
TOKEN = re.compile(r"^[\w.+-]*\.[A-Za-z0-9]+$")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")


def git(*args: str, stdin: bytes = b"") -> bytes:
    """git with the default INDEX scrubbed, exactly as `census.py:51-55` does it."""
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    return subprocess.run(["git", "-C", ROOT, *args], input=stdin, capture_output=True, env=env,
                          check=True).stdout


def committed(ext: str | None = None) -> list[tuple[str, str]]:
    out = []
    for line in git("ls-tree", "-r", "HEAD").decode("utf-8", "replace").splitlines():
        meta, path = line.split("\t", 1)
        if ext is None or path.endswith(ext):
            out.append((path, meta.split()[2]))
    return out


def texts(pairs: list[tuple[str, str]]):
    """Yield (path, text) through one `git cat-file --batch`, holding one file at a time."""
    if not pairs:
        return
    raw = git("cat-file", "--batch", stdin=("\n".join(h for _, h in pairs) + "\n").encode())
    i = 0
    for path, _ in pairs:
        j = raw.index(b"\n", i)
        size = int(raw[i:j].split()[2])
        yield path, raw[j + 1:j + 1 + size].decode("utf-8", "replace")
        i = j + 1 + size + 1


def tokens(line: str) -> list[str]:
    return [t for t in BACKTICK.findall(line) if "/" not in t and TOKEN.fullmatch(t)]


def cite_states(text: str):
    """Yield (lineno, line, tokens, fenced, indented) over one document."""
    fence: str | None = None
    lines = text.split("\n")
    for n, line in enumerate(lines, 1):
        m = FENCE.match(line)
        if fence is not None:
            body = line.strip()
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            yield n, line, tokens(line), True, False
            continue
        if m:
            fence = m.group(1)
            yield n, line, tokens(line), True, False
            continue
        blank_before = n == 1 or not lines[n - 2].strip()
        indented = blank_before and (line.startswith("\t") or line.startswith("    "))
        yield n, line, tokens(line), False, indented


def main() -> int:
    paths = [p for p, _ in committed()]
    md = committed(PROSE_EXT)
    by_name: dict[str, list[str]] = {}
    for p in paths:
        by_name.setdefault(os.path.basename(p), []).append(p)

    # pass 1: the cited set and its DENOMINATOR (every distinct bare basename cited)
    cited: set[str] = set()
    cite_lines = 0
    for _, text in texts(md):
        for _, _, tk, _, _ in cite_states(text):
            if tk:
                cite_lines += 1
                cited.update(tk)
    ambiguous = sorted(t for t in cited if t in by_name and len(by_name[t]) > 1)

    # pass 2: per-line state, for the ambiguous set only
    state: dict[str, dict] = {b: dict(rows=0, fenced=0, indented=0, prose=0, slash=0,
                                       files=set(), fenced_files=set()) for b in ambiguous}
    for path, text in texts(md):
        for n, line, tk, fenced, indented in cite_states(text):
            for t in tk:
                if t not in state:
                    continue
                s = state[t]
                s["rows"] += 1
                s["files"].add(path)
                s["slash"] += "/" in line
                if fenced:
                    s["fenced"] += 1
                    s["fenced_files"].add(path)
                elif indented:
                    s["indented"] += 1
                else:
                    s["prose"] += 1

    out = ["basename\tcollisions\tciting_lines\tfenced\tindented\tprose\tlines_with_slash"
           "\tclaiming_md\top_branch\tslash_any_prose"]
    branches = Counter()
    cross = Counter()
    for b in ambiguous:
        s = state[b]
        op = "POSITIVE" if (s["fenced"] or s["indented"]) else "SUGGESTED"
        branches[op] += 1
        cross[(op, bool(s["slash"]))] += 1
        out.append(f"{b}\t{len(by_name[b])}\t{s['rows']}\t{s['fenced']}\t{s['indented']}\t{s['prose']}"
                   f"\t{s['slash']}\t{len(s['files'])}\t{op}\t{bool(s['slash'])}")
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "split.rows"), "w") as fh:
        fh.write("\n".join(out) + "\n")

    print(f"HEAD {git('rev-parse', 'HEAD').decode().strip()}")
    print(f"committed {PROSE_EXT} documents : {len(md)}")
    print(f"bare-basename CITING LINES     : {cite_lines}")
    print(f"bare basenames cited (DENOM)   : {len(cited)}")
    print(f"AMBIGUOUS (>=2 tracked files)  : {len(ambiguous)}")
    print("SPLIT branch A  POSITIVE  = >=1 citing line in a fenced or indented code block : "
          f"{branches['POSITIVE']}")
    print("SPLIT branch B  SUGGESTED = every citing line is ordinary prose                 : "
          f"{branches['SUGGESTED']}")
    print("cross-tab (branch, any_citing_line_carries_a_slash): " +
          "  ".join(f"{k[0]}/slash={int(k[1])}: {v}" for k, v in sorted(cross.items(), key=str)))
    tot = sum(b["rows"] for b in state.values())
    print(f"citing lines inside the ambiguous set : {tot}   (fenced {sum(b['fenced'] for b in state.values())}"
          f"  indented {sum(b['indented'] for b in state.values())}  prose {sum(b['prose'] for b in state.values())})")
    coll = Counter(len(by_name[b]) for b in ambiguous)
    print("collision-count histogram : " + "  ".join(f"{k}:{v}" for k, v in sorted(coll.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())