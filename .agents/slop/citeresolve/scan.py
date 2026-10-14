#!/usr/bin/env python3
"""Build the prose-citation population and resolve every `<path>:<N>` against the tree.

Population (by DISCOVERY, not a hand list): every file `git ls-files` returns for
    AGENTS.md  .agents/TOOLS.md  .agents/TODO.md  .agents/slop/*/REPORT.md
read AS COMMITTED (`git show HEAD:<p>`), so the reading carries its moment
(`git rev-parse HEAD`).  A claim is a `<path>:<spec>` where spec is `N`, `N-M`,
or a comma list `N,M,...` and `<path>` ends in a known tree extension.

Resolution tiers (mechanical, no token needed):
    RESOLVES     file resolves AND every N in spec is 1..line-count
    OUT-OF-RANGE file resolves but some N > line-count (or < 1)
    GONE-FILE    the path token resolves to no file on disk
    AMBIG        basename is non-unique and no candidate carries the cite's path
    UNREADABLE   target exists but could not be read

A citation into a shadow copy (`.agents/slop/**` full-source replicas) is not a
citation into the port; `prefer()` ranks the real tree above a shadow.

`NEEDLE` is the best-effort subject check, kept separate so the mechanical count
is not confused with it: the backticked code span nearest the cite on the same
line (the cite span itself is excluded) is looked up in the target file -- at the
cited line, elsewhere, or nowhere.  A cite with no other span is `UNCHECKED`.

Emits TSV on stdout; counts to stderr.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

SURFACES = ("AGENTS.md", ".agents/TOOLS.md", ".agents/TODO.md", ".agents/slop/*/REPORT.md")

EXTS = (
    "md|py|sh|bend|json|rows|tsv|out|err|txt|js|mjs|ts|toml|cfg|yml|yaml|"
    "jsonl|lock|cmp|log|names|sha256"
)
CITE = re.compile(
    r"(?P<path>\.{0,2}/?[A-Za-z0-9_][A-Za-z0-9_./@+-]*\.(?:" + EXTS + r"))"
    r":(?P<spec>[0-9]+(?:[-,][0-9]+)*)",
    re.IGNORECASE,
)
SPAN = re.compile(r"`([^`\n]+)`")

SKIP_DIRS = {".git", ".jj", ".venv", "node_modules", "__pycache__"}


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout


def head() -> str:
    return git("rev-parse", "HEAD").strip()


def surfaces() -> list[str]:
    return [p for p in git("ls-files", *SURFACES).splitlines() if p]


def tree_index() -> tuple[set[str], dict[str, list[str]]]:
    exact: set[str] = set()
    by_base: dict[str, list[str]] = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
            exact.add(rel)
            by_base.setdefault(f, []).append(rel)
    return exact, by_base


def prefer(cands: list[str]) -> list[str]:
    """Repo source before `.agents/slop`, before `runs/` snapshots, before `references/`."""
    def rank(p: str) -> tuple:
        return (
            p.startswith("runs/"),
            p.startswith("references/"),
            p.startswith(".agents/slop/"),
            p.count("/"),
            p,
        )
    return sorted(cands, key=rank)


def resolve(path: str, exact: set[str], by_base: dict[str, list[str]]) -> tuple[str, str, bool]:
    """Return (how, target, unique).  `unique` is False when >1 candidate shares
    the basename and none carries the cite's directory path."""
    if path.startswith("./"):
        path = path[2:]
    if "@" in path:
        path = path.rsplit("@", 1)[-1]
    for cand in (path, ".agents/" + path, "checks/" + path, "gates/" + path):
        if cand in exact:
            return "EXACT", cand, True
    base = os.path.basename(path)
    allc = by_base.get(base, [])
    if not allc:
        return "GONE-FILE", "", True
    suffix = [c for c in allc if c.endswith("/" + path) or c == path]
    if len(suffix) == 1:
        return "SUFFIX", suffix[0], True
    if len(suffix) > 1:
        return "AMBIG", prefer(suffix)[0], False
    real = [c for c in allc if not c.startswith((".agents/slop/", "runs/", "references/"))]
    pool = prefer(real or allc)
    if len(pool) == 1:
        return "BASENAME", pool[0], True
    return "AMBIG", pool[0], False


def read_target(rel: str) -> list[str] | None:
    try:
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return None


def spec_lines(spec: str) -> list[int]:
    out: list[int] = []
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-", 1)
            out += [int(a), int(b)]
        else:
            out.append(int(part))
    return out


def line_tokens(line: str, m: re.Match[str]) -> list[str]:
    """Code-ish candidate subjects on the cite's line: backticked spans (the cite
    span and pure numbers excluded) plus `def x`/`fn x`/`class x` heads."""
    cite = m.group(0)
    out: list[str] = []
    for s in SPAN.finditer(line):
        text = s.group(1).strip()
        if not text or text == cite or cite in text:
            continue
        if re.fullmatch(r"[0-9,:\-\s]+", text):
            continue
        out.append(re.split(r"[:(\s]", text)[0].strip("()[]`*_"))
    out += re.findall(r"\b(?:def|fn|class|func)\s+([A-Za-z_][A-Za-z0-9_.]*)", line)
    return [t for t in out if t and len(t) > 1]


def main() -> int:
    hd = head()
    exact, by_base = tree_index()
    rows: list[tuple] = []
    for rel in surfaces():
        try:
            blob = git("show", f"{hd}:{rel}")
        except subprocess.CalledProcessError:
            continue
        for i, line in enumerate(blob.splitlines(), 1):
            for m in CITE.finditer(line):
                path, spec = m.group("path"), m.group("spec")
                how, target, unique = resolve(path, exact, by_base)
                nums = spec_lines(spec)
                text, nclass = "", "UNCHECKED"
                if how == "GONE-FILE" or not target:
                    rows.append((rel, i, path, spec, target, "GONE-FILE", nclass, "", line.strip()[:160]))
                    continue
                tlines = read_target(target)
                if tlines is None:
                    rows.append((rel, i, path, spec, target, "UNREADABLE", nclass, "", line.strip()[:160]))
                    continue
                n = len(tlines)
                status = "RESOLVES" if all(1 <= x <= n for x in nums) else "OUT-OF-RANGE"
                if 1 <= nums[0] <= n:
                    text = tlines[nums[0] - 1].strip()
                toks = line_tokens(line, m)
                if toks:
                    at = any(
                        1 <= x <= n and any(t in tlines[x - 1] for t in toks)
                        for x in nums
                    )
                    elsewhere = any(any(t in tl for tl in tlines) for t in toks)
                    nclass = "AT-LINE" if at else ("ELSEWHERE" if elsewhere else "NOWHERE")
                rows.append((rel, i, path, spec, target, status, nclass, text[:110], line.strip()[:160], how, "unique" if unique else "WEAK"))
    print("surface\tsline\tpath\tspec\ttarget\tstatus\tneedle\tline_text\tsource_line\thow\tuniq")
    for r in rows:
        print("\t".join(str(x).replace("\t", " ") for x in r))
    from collections import Counter
    cs = Counter(r[5] for r in rows)
    cn = Counter(r[6] for r in rows)
    print(f"# HEAD={hd}", file=sys.stderr)
    print(f"# total={len(rows)} " + " ".join(f"{k}={v}" for k, v in sorted(cs.items())), file=sys.stderr)
    print(f"# needle " + " ".join(f"{k}={v}" for k, v in sorted(cn.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
