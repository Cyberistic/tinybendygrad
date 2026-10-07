#!/usr/bin/env python3
"""INVENTORY OF UNCLAIMED WORK: who wrote a dirty path, who reads it, is it load-bearing.

A path nobody committed has no recorded purpose, so the only way to learn whether it matters
is to ask git three questions and MEASURE the answers:

  1. OWNER      -- `git log --all -1 -- PATH`. NOBODY means no commit has ever claimed it,
                   which is a finding and not a shrug: it is the state a unit's work reaches
                   when a stranger's `git add -A` lands first.
  2. READER     -- does a COMMITTED file name PATH as a WHOLE TOKEN? Substring matching is how
                   a citation to `helpers-tc-gate` gets counted as a citation to
                   `helpers-tc-gate.rows`, so the token boundary here is load-bearing.
  3. GENERATED  -- is PATH an artifact of running a committed file? Measured two ways, because
                   one of them is not enough. A whole-token search finds the sites that name
                   the file outright. It CANNOT find a site that builds the name from a
                   TEMPLATE -- `census.py` writes `rows-{name}-{which}.rows` and so names no
                   individual cache file at all -- so the template sites are declared in
                   `GENERATORS` below and each pin is CHECKED, not trusted.

Every fact comes out of git (HEAD plus chunked `git grep`), never out of the working tree's own
claim about itself, so a run reproduces on a fresh clone. Writes nothing.

    python3 checks/unowned.py                      # the table, from live `git status`
    python3 checks/unowned.py --from FILE          # from a captured `git status` (stable set)
    python3 checks/unowned.py --tsv                # machine-readable
    python3 checks/unowned.py --why PATH           # every committed line naming PATH
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Another unit's IN-FLIGHT staging is not the unowned set. A unit mid-run stages its scratch
# copy, and reporting that as unclaimed work is the same category of error as reporting a
# stranger's commit as yours.
LIVE = (".agents/slop/rerun/", ".agents/slop/stale71/")
def _coindep():
    """The single declaration, loaded BY PATH -- see checks/coindep.py."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "coindep", os.path.join(ROOT, "checks", "coindep.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SKIP_DIRS = _coindep().SKIP_DIRS

# A citation must be a WHOLE token: `X` may not be glued to a path separator or an identifier
# character on either side. This is what keeps `a/b.py` from counting as a citation of `b.py`.
BOUND = r"[A-Za-z0-9_.\-/]"
# A committed line that WRITES is a site that has told us the path is an artifact of running it.
# Matched as two independent facts on ONE line, not as one regex: `open(os.path.join(O, "f"), "w")`
# closes a paren inside the argument list, so a single `open\([^)]*['\"]w` pattern misses every
# `os.path.join` write in the tree -- which is how `residue/*.md` came out looking load-bearing.
# WRITE_VERB is unambiguous on its own. WRITE_MODE is the second half of the test for the two
# forms that are not: `open(...)` and `>`, which mean the opposite thing with an `r`.
WRITE_VERB = re.compile(r"write_text|write_bytes|writeFile|writeFileSync|copyFile|copyfile|"
                        r"shutil\.copy|\.rename\(|to_csv|json\.dump|\bemit\(|savefig")
WRITE_MODE = re.compile(r"""['"][wax]b?['"]""")
# A TEMPLATE site: the filename is assembled, so no whole-token search can ever find it.
TEMPLATED = re.compile(r"\{[^}]*\}|\$\(|%s|\.format\(|f[\"']")
# PROSE is a mention; CODE is a dependency -- but a `.bend` file mentioning a note in a `#`
# comment is still prose wearing a code file's clothes, and counting `indexing.bend`'s 18 comment
# references to `bend2-constraints.md` as 18 dependencies is how a table stops meaning anything.
# So CODE is not the test. A QUOTED token is: a path inside a string literal is code naming a
# path, and an unquoted one is a comment about it. Both gates, because a README that shows
# `sh helpers-tc-gate.sh` documents the invocation without being it.
PROSE = (".md", ".out", ".rows", ".tsv", ".json", ".txt", ".err")
# `#`-comment languages: in these, everything from an unquoted `#` is prose, however it is
# quoted inside. `ag-emit.bend:32` writes "at `.agents/slop/notes/bend2-constraints.md`" -- a
# backtick-quoted COMMENT, which the quoted-token rule alone counts as 75 dependencies.
HASH_COMMENT = (".py", ".sh", ".bend", ".yml", ".yaml", ".toml", ".cfg", ".js", ".mjs", ".ts")


def uncommented(where: str, line: str) -> str:
    if not where.rsplit(":", 1)[0].endswith(HASH_COMMENT):
        return line
    out, in_s = [], None
    for ch in line:
        if in_s:
            out.append(ch)
            in_s = None if ch == in_s else in_s
        elif ch in "\"'":
            in_s, _ = ch, out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out)


def writes(line: str) -> bool:
    """One line creates or overwrites. `WRITE_VERB` alone, or `WRITE_MODE` closing an open/shell
    redirect -- those two are the only forms where the same spelling can also mean a READ."""
    return bool(WRITE_VERB.search(line) or (re.search(r"open\(|>", line) and WRITE_MODE.search(line)))


def quoted(line: str, tok: str) -> bool:
    return any(tok in m for m in re.findall(r"""['"`][^'"`]*['"`]""", line))

# Declared TEMPLATE generators, keyed by the path prefix they cover. Each value is
# (committed file, the substring the pin REQUIRES on that line). If the substring is gone the
# pin reports STALE rather than silently keeping the claim -- a pin that cannot fail is not a
# pin, and `checks/differ.py` exists because of what happens when one cannot.
GENERATORS = {
    "checks/rows-": ("checks/census.py", 'rows-{name}-{which}.rows'),
    "checks/gen/": ("checks/abi_gate.py", 'gendir = HERE / "gen"'),
    ".agents/slop/helpers-tc-gate": (".agents/slop/helpers-tc-gate.sh", "GT=.agents/slop/helpers-tc-gate"),
}


def git(*args: str, strict: bool = True) -> str:
    p = subprocess.run(("git", "-C", ROOT) + args, capture_output=True, text=True)
    if strict and p.returncode:
        raise RuntimeError(f"git {' '.join(args)}: rc={p.returncode} {p.stderr.strip()}")
    return p.stdout


def ere(tok: str) -> str:
    return re.sub(r"([.^$*+?()\[\]{}|\\])", r"\\\1", tok)


def status_paths() -> list[str]:
    out = []
    for line in git("status", "--porcelain=v1", "-z").split("\0"):
        if len(line) < 4:
            continue
        path = line[3:]
        if any(f"{d}/" in f"{path}/" for d in SKIP_DIRS) or path.startswith(LIVE):
            continue
        out.append(path)
    return out


def tokens_of(path: str) -> list[str]:
    """Every whole token by which a committed file could legitimately name `path`.

    The basename counts only when it is FILENAME-SHAPED. A bare word with no `.` is a module or
    directory name, and matching it as a filename turns `tinygrad/tinygrad` into 1876 hits on the
    word `tinygrad` -- a number that looks like a dependency and measures nothing."""
    base = os.path.basename(path)
    return list(dict.fromkeys((path, base if "." in base else "")))


def scan(paths: list[str], chunk: int = 40) -> dict[str, list[tuple[str, str]]]:
    """`{path: [(file:line, text)]}` for committed lines naming each path as a whole token.

    One `git grep` per CHUNK of tokens, not per path: 71 whole-tree passes take minutes, and
    a single alternation of every token overruns what git will accept."""
    tok_of = {p: [t for t in tokens_of(p) if t] for p in paths}
    union = sorted({t for ts in tok_of.values() for t in ts})
    hits: dict[str, list[tuple[str, str]]] = {p: [] for p in paths}
    for i in range(0, len(union), chunk):
        part = union[i:i + chunk]
        rx = re.compile(r"(?<!%s)(%s)(?!%s)" % (BOUND, "|".join(map(re.escape, part)), BOUND))
        raw = git("grep", "-n", "-I", "-E", "|".join(ere(t) for t in part), "HEAD", strict=False)
        for line in raw.splitlines():
            # `HEAD:<file>:<lineno>:<text>`. The tokenizer below re-checks the boundary, so a
            # mis-split on a path containing `:` degrades to a miss rather than a false hit.
            f = line.split(":", 3)
            if len(f) < 4 or f[0] != "HEAD":
                continue
            for tok in rx.findall(f[3]):
                for p, ts in tok_of.items():
                    if tok in ts:
                        hits[p].append((f"{f[1]}:{f[2]}", f[3]))
    return {p: sorted(set(v)) for p, v in hits.items()}


def generator_for(path: str) -> tuple[str, bool]:
    """The declared template generator covering `path`, and whether its pin still HOLDS."""
    for prefix, (src, needle) in GENERATORS.items():
        if path.startswith(prefix):
            body = git("show", f"HEAD:{src}", strict=False)
            return f"{src} (template {needle!r})", any(needle in ln for ln in body.splitlines())
    return "", False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", action="store_true")
    ap.add_argument("--why", metavar="PATH")
    ap.add_argument("--from", dest="src", metavar="FILE",
                    help="read the path list from a captured `git status --porcelain` instead of "
                         "live -- the set moves while six units are running")
    a = ap.parse_args()

    paths = [ln[3:] for ln in open(a.src).read().splitlines() if len(ln) > 3] if a.src else status_paths()
    paths = [p for p in dict.fromkeys(paths) if p != os.path.relpath(__file__, ROOT)]
    if a.why:
        paths = [a.why]
    head = set(git("ls-tree", "-r", "--name-only", "HEAD").splitlines())
    owner = {p: (git("log", "--all", "--format=%h", "-1", "--", p).strip() or "NOBODY") for p in paths}
    hits = scan([a.why] if a.why else paths)

    print("path\towner\tin_head\tcited\texec\twritten\tverdict" if a.tsv else
          f"{'PATH':<50} {'OWNER':<10} {'HEAD':<5} {'CIT':>4} {'EXE':>4} {'WRT':>4}  VERDICT")
    for p in paths:
        keep = [(w, uncommented(w, t)) for w, t in hits.get(p, []) if w.rsplit(":", 1)[0] != p]
        tok = [x for x in tokens_of(p) if x]
        exe = [w for w, t in keep if is_code(w) and any(quoted(t, x) for x in tok)]
        wrt = [w for w, t in keep if is_code(w) and writes(t) and any(quoted(t, x) for x in tok)]
        cit = [(w, t) for w, t in hits.get(p, []) if w.rsplit(":", 1)[0] != p]
        gen, holds = generator_for(p)
        print(f"{p}\t{owner[p]}\t{int(p in head)}\t{len(cit)}\t{len(exe)}\t{len(wrt)}\t"
              f"{verdict(cit, exe, wrt, p in head, gen, holds)}" if a.tsv else
              f"{p:<50} {owner[p]:<10} {str(p in head):<5} {len(cit):>4} {len(exe):>4} {len(wrt):>4}  "
              f"{verdict(cit, exe, wrt, p in head, gen, holds)}")
        if a.why:
            for w, t in hits.get(p, []):
                tag = ">>" if (is_code(w) and any(quoted(uncommented(w, t), x) for x in tok)) else "  "
                tag += "W" if (is_code(w) and writes(t)) else " "
                print(f"{'':>76}{tag} {w}: {t.strip()[:100]}")
    print(f"\n{len(paths)} path(s). owner=`git log --all -1`; CIT/EXE/WRT are WHOLE-TOKEN hits in HEAD, "
          f"EXE/WRT only in CODE files; live staging under {LIVE[0]} excluded.")
    return 0


def is_code(where: str) -> bool:
    return not where.rsplit(":", 1)[0].endswith(PROSE)


def verdict(cit: list, exe: list, wrt: list, head: bool, gen: str, holds: bool) -> str:
    """From the measured facts and nothing else."""
    if gen:
        return f"GENERATED via {gen} pin {'HOLDS' if holds else '** STALE **'} -> untrack"
    if wrt:
        return f"GENERATED  written by {len(wrt)} committed site(s) -> untrack"
    if exe:
        return f"LOAD-BEARING  {len(exe)} committed EXECUTION site(s) open/launch it"
    if cit:
        return f"CITED-ONLY  {len(cit)} committed mention(s), 0 execution sites"
    return "INERT      no committed citer" + ("" if head else ", never committed")


if __name__ == "__main__":
    sys.exit(main())
