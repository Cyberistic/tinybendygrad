#!/usr/bin/env python3
r"""pathwitness-gate.py -- FOR EACH FIXTURE STEM THE TREE DECLARES, NAME EVERY WITNESS AND ITS KIND.

    .venv/bin/python gates/pathwitness-gate.py
    .venv/bin/python gates/pathwitness-gate.py --plant      # prove all three cases are reachable

A RENAME THAT A LOADER SURVIVES STILL LEAVES EVERY MENTION OF THE OLD EXTENSION STANDING, and those
mentions are NOT ONE POPULATION. `.agents/slop/opsbend_milestone_gate.py` resolves its fixture by
STEM (`_EXPECTED_STEM`, `p.stem == _EXPECTED_STEM`), so a `.txt`->`.md` rename does not kill it --
MEASURED 2026-10-19T15:43:00Z, `os.walk` + `os.path.splitext(f)[0] == stem`: **1** match,
`.agents/slop/ops_bend-milestone-expected.md`, 4626 B. But a mention inside a `#` comment cannot
break a run, a mention inside a docstring cannot either, and a mention inside a `for p in [...]`
whose body is `os.path.exists(p)` is not a reader either -- it is a PROBE, and it goes on existing.
This gate exists so that those three are not all reported as "a dead path".

THE SUBJECT IS DISCOVERED, NOT NAMED (doctrine 1). The stem is read out of the loader that declares
it (`_EXPECTED_STEM = "..."`, found by walking `*.py`; MEASURED 2026-10-19T15:43:41Z, exactly ONE
file in the tree declares it, `.agents/slop/opsbend_milestone_gate.py`), so a rename moves this
census in the same commit the loader moves. The witness population is a DIRECTORY WALK over every
file -- NOT a suffix set, because a suffix set is blind by construction and `checks/repro-paths.py`'s
was measured reading `foo.pyc` as `foo.py`, which turned a DANGLING name into a RESOLVED one. The
suffix picks the LEXICAL CLASSIFIER, never membership.

`FROZEN` IS A COLUMN, NOT A CLASS, because the two facts are orthogonal and both matter: a line of
prose inside a content-pinned file is still prose, AND editing it is still a different act. `FROZEN`
is discovered by HASH -- a witness whose `sha256` appears as a `*_SHA = "..."` pin in `checks/*.py`
or `gates/*.py`. MEASURED 2026-10-19T15:43:14Z, the tree declares exactly 2 such pins
(`ORACLE_SHA`, `BODY_SHA`, `checks/e2e.py:244-245`), and `shasum -a 256
.agents/slop/e2epy/oracle-e2e.sh` = `05d7cfea...` = `ORACLE_SHA`, so the frozen oracle is recognised
without anyone listing it.

THE VERDICT IS BUILT FROM FACTS, NEVER FROM THE CLASSIFIER:
  * the `os.walk` count for the stem -- 0 or >=2 is a FAIL that NAMES THE SET, which is the loader's
    own contract, and is the only way this gate can be wrong about liveness;
  * `os.path.exists` on a literal path captured from the line -- a fact about the filesystem.
A dangling literal fails ONLY where the classification says code can reach it (`READER`, `QUOTED`).
`PROSE`, `DOCSTRING`, `PROBE`, `BEND` and `UNKNOWN` are reported WITH their evidence line and are not
failures, because a stale comment is a stale comment. `UNKNOWN` is reported rather than trusted
precisely so that an unlexable suffix cannot read as prose.

NO `.txt` OUTPUT, NO `.txt` INPUT: rows are `.rows`, and they land in `gates/artifacts/pathwitness/`.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ART = REPO / "gates/artifacts/pathwitness"
PRUNE = {".git", ".jj", "node_modules", "__pycache__", ".venv", "artifacts", "index", "tinygrad"}
PIN_RE = re.compile(r'^[A-Z_]*SHA = "([0-9a-f]{64})"$', re.M)
STEM_RE = re.compile(r'^\s*_EXPECTED_STEM\s*=\s*"([^"]+)"', re.M)
LITERAL = re.compile(r'[\w./-]*milestone[A-Za-z0-9_-]*\.[A-Za-z0-9]+')
READERS = {"open", "read", "read_text", "read_bytes", "readlines", "open_text", "load", "loads"}
DOC_PARENTS = (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)


def stem_of(root: Path) -> str | None:
    """The stem every witness is a mention OF, read out of the loader that declares it."""
    for p in sorted(root.rglob("*.py")):
        if any(part in PRUNE for part in p.parts):
            continue
        m = STEM_RE.search(p.read_text(encoding="utf-8", errors="replace"))
        if m:
            return m.group(1)
    return None


def loader_of(root: Path) -> Path:
    return next(p for p in sorted(root.rglob("*.py"))
                if not any(q in PRUNE for q in p.parts)
                and STEM_RE.search(p.read_text(encoding="utf-8", errors="replace")))


def resolve(stem: str, near: Path) -> list[str]:
    """`os.walk` + `splitext`, beside the loader -- the loader's own sentence, by discovery."""
    return sorted(str(Path(root, f).relative_to(near.parent))
                  for root, dirs, files in os.walk(near)
                  for f in files
                  if os.path.splitext(f)[0] == stem
                  for dirs[:] in [[d for d in dirs if d not in PRUNE]])


def pins(root: Path) -> set[str]:
    """Every `*_SHA` pin the tree declares in its own code. A hash cannot name the wrong file."""
    out: set[str] = set()
    for d in ("checks", "gates"):
        for p in (root / d).glob("*.py"):
            out |= set(PIN_RE.findall(p.read_text(encoding="utf-8", errors="replace")))
    return out


def _fname(node: ast.AST) -> str:
    return node.func.attr if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
        else getattr(node, "id", "") if isinstance(node, ast.Name) else \
        getattr(getattr(node, "func", None), "id", "")


def py_occurrences(src: str, stem: str) -> list[tuple[int, str, str]]:
    """(lineno, kind, literal) per string literal mentioning the stem, via `ast` -- not a regex.

    DOCSTRING is an `Expr`-statement string under a module/class/function, which is prose by
    definition and is the case a `#`-stripper cannot see. PROBE is a literal inside a collection
    that no reader call wraps -- the shape of a `for p in [...]` existence list, which is the case
    a substring search reads as a reader.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    parents = {c: n for n in ast.walk(tree) for c in ast.iter_child_nodes(n)}
    out = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Constant) and isinstance(node.value, str)
                and stem in node.value):
            continue
        parent = parents.get(node)
        kind = "QUOTED"
        if isinstance(parent, ast.Expr) and isinstance(parents.get(parent), DOC_PARENTS):
            kind = "DOCSTRING"
        else:
            seen_reader, seen_coll = False, False
            for anc in _ancestors(node, parents):
                if isinstance(anc, (ast.List, ast.Tuple, ast.Set)):
                    seen_coll = True
                if isinstance(anc, ast.Call) and _fname(anc) in READERS:
                    seen_reader = True
            kind = "READER" if seen_reader else "PROBE" if seen_coll else "QUOTED"
        lit = LITERAL.search(node.value)
        out.append((node.lineno, kind, lit.group(0) if lit else ""))
    return out


def _ancestors(node: ast.AST, parents: dict) -> list[ast.AST]:
    chain, cur = [], parents.get(node)
    while cur is not None:
        chain.append(cur)
        cur = parents.get(cur)
    return chain


def sh_occurrences(src: str, stem: str) -> list[tuple[int, str, str]]:
    """(lineno, kind, literal) per line mentioning the stem: `#` at the start of a word is prose."""
    out = []
    for i, line in enumerate(src.splitlines(), 1):
        if stem not in line:
            continue
        lit = LITERAL.search(line)
        lit = lit.group(0) if lit else ""
        probe = re.search(r'\[\s*-[efdLr]\s', line) or re.search(r'\btest\s+-[efdLr]\s', line)
        kind = "PROBE" if probe else "PROSE" if re.match(r'\s*#', line) else "QUOTED"
        out.append((i, kind, lit))
    return out


def census(root: Path) -> tuple[list[str], list[tuple]]:
    stem = stem_of(root)
    if stem is None:
        return [f"no `_EXPECTED_STEM` declaration under {root} by walking *.py"], []
    hits = resolve(stem, loader_of(root).parent)
    if len(hits) != 1:
        return [f"{stem}: expected exactly one file beside the loader, found {len(hits)}: {hits}"], []
    frozen = pins(root)
    rows, bad = [], []
    for p in sorted(root.rglob("*")):
        if not p.is_file() or any(q in PRUNE for q in p.parts):
            continue
        src = p.read_text(encoding="utf-8", errors="replace")
        if stem not in src:
            continue
        is_frozen = hashlib.sha256(p.read_bytes()).hexdigest() in frozen
        if p.suffix == ".bend":
            occ = [(1, "BEND", "")]          # forbidden to edit; counted, never opened
        elif p.suffix == ".py":
            occ = py_occurrences(src, stem)
        elif p.suffix in (".sh", ".bash"):
            occ = sh_occurrences(src, stem)
        else:
            occ = [(i, "UNKNOWN", "") for i, ln in enumerate(src.splitlines(), 1) if stem in ln]
        for lineno, kind, lit in occ:
            exists = bool(lit) and os.path.exists(root / lit)
            ev = src.splitlines()[lineno - 1].strip()[:88] if lineno <= len(src.splitlines()) else ""
            rows.append((str(p.relative_to(root)), lineno, kind, "yes" if is_frozen else "no",
                         lit, "yes" if exists else "no", ev))
            if kind in ("READER", "QUOTED") and lit and not exists:
                bad.append(f"{p.relative_to(root)}:{lineno}: {kind} names {lit}, which does not exist")
    return bad, rows


def plant() -> int:
    """The four cases, each with the REASON it must fail for -- a FAIL for another cause is a green
    plant over a broken instrument, which is the defect this file is named for.

    0 and 2 matches exercise the discovery contract (the loader's own sentence). The third puts a
    real `open(...)` on a dead path, because `kind == "READER"` never occurs on the live tree and
    an unexercised failure path is indistinguishable from a missing one.
    """
    import tempfile
    cases = (
        (0, 1, "expected exactly one", None),
        (1, 0, "", None),
        (2, 1, "expected exactly one", None),
        (1, 1, "which does not exist",
         'open(".agents/slop/milestone-x.txt").read()\n'),
    )
    ok_all = True
    for n, want, why, extra in cases:
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as td:
            root = Path(td)
            (root / "gates").mkdir()
            (root / "gates/l.py").write_text('_EXPECTED_STEM = "milestone-x"\n')
            if extra:
                (root / "gates/r.py").write_text(extra)
            for i in range(n):
                (root / f"gates/milestone-x.{'md' if i == 0 else 'txt'}").write_text("x\n")
            bad, _ = census(root)
            got, why_seen = (1, why in " ".join(bad)) if bad else (0, True)
            ok = got == want and why_seen
            ok_all &= ok
            print(f"PLANT matches={n} extra={'reader' if extra else '-'} rc={got} want_rc={want} "
                  f"reason={'NAMED' if why_seen else 'MISSING'} {'OK' if ok else 'MISMATCH'}")
    print("PLANT OK" if ok_all else "PLANT MISMATCH")
    return 0 if ok_all else 1


def main() -> int:
    ap = argparse.ArgumentParser(prog=__file__, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=REPO)
    ap.add_argument("--plant", action="store_true", help="prove 0/1/2 matches are all reachable")
    opts = ap.parse_args()
    if opts.plant:
        return plant()
    bad, rows = census(opts.root.resolve())
    print(f"STEM     {stem_of(opts.root.resolve())}")
    counts: dict[str, int] = {}
    for _, _, kind, _, _, _, _ in rows:
        counts[kind] = counts.get(kind, 0) + 1
    print(f"WITNESS  {len(rows)} occurrence(s)  " + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    print(f"{'kind':<9} {'frozen':<7} {'exists':<7} {'ext':<6} path:line")
    for rel, lineno, kind, frz, lit, ex, ev in rows:
        if kind == "UNKNOWN":
            continue          # counted above, evidence unread -- never silently a pass
        print(f"{kind:<9} {frz:<7} {ex:<7} {Path(rel).suffix or '-':<6} {rel}:{lineno}  [{lit}]")
        print(f"{'':<32}{ev}")
    ART.mkdir(parents=True, exist_ok=True)
    (ART / "witnesses.rows").write_text(
        "\n".join(f"{k}\t{f}\t{l}\t{e}\t{r}:{n}" for r, n, k, f, l, e, _ in rows) + "\n")
    for b in bad:
        print(f"  FAIL {b}")
    print("PASS" if not bad else f"{len(bad)} failure(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())