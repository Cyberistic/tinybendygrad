#!/usr/bin/env python3
"""blobpin-census-gate.py -- every in-code pin on a `tinygrad/` blob, and what it can fail on.

    .venv/bin/python gates/blobpin-census-gate.py
    .venv/bin/python gates/blobpin-census-gate.py --plant

THE CLASS. A gate that diffs against CPython fingerprints the file it diffs against, so that a
re-vendor which changes what `fp8_to_float` answers moves a PIN instead of silently moving 78k
rows. `gatekit.oracle_drift` is the reader and there are several call sites; THIS gate is the
CENSUS over all of them at once, and it exists because the census was somebody's throwaway
script (`.agents/slop/revendor/findpins.py`, which prints a COUNT and names no site) and the
count is not the claim -- the sites are.

WHAT IT CLAIMS, AND WHY EACH CLAIM CAN BE WRONG.

  POPULATION  Every `"<path>": "<40..64 hex>"` site naming a `tinygrad/**` file, in EVERY file
              that CALLS `oracle_drift`. DISCOVERED by a directory walk over `gates/` and
              `checks/` and cross-checked against the caller set, because a regex that cannot
              see its own population cannot be wrong. A caller whose pin dict this file cannot
              RESOLVE is a REFUSAL, not a smaller number -- `gates/js-lane-census.py:109`
              records the same trap twice over with `REG_ANY`, and this is that trap one level up.

  INTACT      `sha256(<path>'s bytes)` equals the literal, per site. Same reader the gates use,
              so this gate cannot disagree with them about a drift; it asks about ALL of them.

  LITERAL     Every site is a quoted hex constant, and this gate FAILS if one ever stops being
              one. A DERIVED pin is `sha256(x) == sha256(x)`: it cannot fail, and `AGENTS.md`
              calls an instrument that cannot fail worse than no instrument. This is the claim
              that makes the census able to say "12 of 12 are literals" and mean it.

  VENDORED    Each pinned blob is byte-identical in the working tree, at `HEAD`, and at
              `refs/remotes/upstream/master` -- three DERIVED readings, no sha transcribed here.
              `tinygrad/` is upstream's bytes and a port must not edit them.

  LAST-MOVE   For each pinned blob, the LAST commit that touched it, and whether THAT commit
              moved it (`<c>^:path` vs `<c>:path`). This is the claim the whole class turns
              on, and it is why "SAME" and "MOVED" are not in contradiction: they are answers
              about DIFFERENT RANGES, and this gate prints the range instead of a verdict.

  WHY THE LAST TWO ARE SEPARATE ROWS. MEASURED 2026-10-20T01:01Z, `git rev-parse` on both ends
  of two ranges: all SEVEN pinned blobs are byte-identical between `002630241` and
  `refs/remotes/upstream/master` (`5c2bf39d6c4b`), and FIVE of the seven CHANGED across the
  re-vendor `86c4f1343`. One finder called the first "0 path(s) MOVE" and one gate header
  called the second "that is the one that MOVED"; both were right and they were answering
  about different intervals, and neither printed the interval.

  AND THE CLASS IS NOT HYPOTHETICAL, IT IS TWO DAYS OLD. `77e6c2bec` ("re-vendor tinygrad/ to
  upstream 5c2bf39d6 (2026-10-20) -- 299 commits", 2026-10-20T00:53:51Z) moved 29 `tinygrad/`
  paths and ZERO of the seven pinned blobs, so all 12 sites are intact today and this gate says
  so by asking git rather than by carrying a list of the seven.

EXIT STATUS: 0 every claim above holds · 1 a claim is false (named) · 3 a precondition was
absent (no git, no upstream ref, a caller this file cannot resolve) · 5 the population is empty,
which is DEAD: a census over zero pins reports zero drift and is indistinguishable from a census
that found nothing wrong.
"""
from __future__ import annotations

import hashlib
import re
import subprocess as S
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

# THE TWO HOMES OF `oracle_drift`: `gatekit`'s own and `checks/substrate.py`'s / `checks/e2e.py`'s
# copies. A WALK over both, not a list of the two directories -- `gates/gates-pop.py:95`'s
# `HOMES` is this tree's own record of a hand list being the one universe a file names by hand.
HOMES = ("gates", "checks")
# THE SITE SHAPE. `\s*` spans the newline, and it has to: MEASURED 2026-10-20, 6 of the 12 sites
# put the value on the line BELOW the key (`gates/rand_census-gate.py:147,149,151` and
# `gates/state_census-gate.py:112,114,116`), so a single-line pattern finds 6 and prints 6 as a
# count -- a population that is silently halved and a number nobody checks. Both quote styles are
# accepted for the same reason.
SITE = re.compile(r"""["'](?P<path>tinygrad/\S+\.py)["']\s*:\s*["'](?P<sha>[0-9a-f]{40,64})["']""")
# EVERY CALL SITE OF THE READER. `gatekit.py` defines it; everyone else consumes it.
CALL = re.compile(r"\boracle_drift\s*\(")
DEF = "def oracle_drift"
# A `#` COMMENT IS NOT A CALL SITE. `gates/banner-gate.py:87` names `oracle_drift()` in prose and
# this file's first draft counted it as a caller and REFUSED on its own population -- an
# instrument that cannot tell a mention from a use is the `repro-paths.py` class one level up.
# Line comments are stripped before the scan; `splitlines`/`join` keeps one line per line, so
# every reported line number is still the file's own.
COMMENT = re.compile(r"#.*$")
LEAD_NAME = re.compile(r"[A-Za-z_]\w*")


def _uncomment(t: str) -> str:
    return "\n".join(COMMENT.sub("", l) for l in t.splitlines())


def git(*a: str) -> tuple[int, str]:
    p = S.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)
    return p.returncode, p.stdout.strip()


def resolve(rev: str, path: str) -> str | None:
    """`git rev-parse <rev>:<path>`, or None. A blob is asked for, never written down."""
    rc, out = git("rev-parse", f"{rev}:{path}")
    return out if rc == 0 else None


def _span(t: str, i: int, op: str, cl: str) -> str:
    """The `op`/`cl`-delimited text starting at `i`, nesting-aware. Call args and dict bodies."""
    depth, j = 0, i
    while j < len(t):
        if t[j] == op:
            depth += 1
        elif t[j] == cl:
            depth -= 1
            if depth == 0:
                return t[i:j + 1]
        j += 1
    return ""


def _dict_for(t: str, name: str) -> str | None:
    """The dict literal `NAME = {` names in THIS file, or None."""
    m = re.search(rf"^{name}\s*(?::[^=\n]+)?=\s*\{{", t, re.M)
    return _span(t, m.end() - 1, "{", "}") if m else None


def census(src: Path) -> tuple[list[tuple[str, str, str, int]], list[str], dict[str, int]]:
    """`(path, sha, file, line)` per site, the callers this file could not resolve, and the
    number of `tinygrad` sites each resolved caller contributes.

    A caller is RESOLVED by taking the dict literal its `oracle_drift(X)` argument names -- by
    NAME in the same file (`DRIFT_PIN`, `ORACLE_PIN`, `DELEGATED`), or inline. An unresolved
    caller is reported, never skipped: a caller whose pins live where this file cannot see them
    is a population it cannot see, and a census that cannot see its population cannot be
    anything. The per-caller COUNT is what makes a caller that quietly stopped pinning anything
    visible rather than merely absent.
    """
    sites: list[tuple[str, str, str, int]] = []
    unresolved: list[str] = []
    per_caller: dict[str, int] = {}
    for home in HOMES:
        d = src / home
        if not d.is_dir():
            continue
        for p in sorted(d.rglob("*.py")):
            try:
                t = _uncomment(p.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                continue
            if CALL.search(t) is None or DEF in t:
                continue  # a definition is not a caller
            rel = str(p.relative_to(src))
            for c in CALL.finditer(t):
                line = t.count("\n", 0, c.start()) + 1
                arg = _span(t, c.end() - 1, "(", ")")[1:-1].strip()
                body = arg if arg.startswith("{") else _dict_for(t, LEAD_NAME.match(arg).group()) \
                    if LEAD_NAME.match(arg) else None
                if body is None:
                    unresolved.append(f"{rel}:{line} oracle_drift({arg.splitlines()[0][:40]})")
                    continue
                n = len(SITE.findall(body))
                per_caller[f"{rel}:{line}"] = n
                for m in SITE.finditer(body):
                    at = t.find(m.group(0))
                    sites.append((m.group("path"), m.group("sha"), rel,
                                  t.count("\n", 0, at) + 1 if at >= 0 else line))
    return sites, unresolved, per_caller


def claim_intact(sites) -> list[str]:
    bad = []
    for path, sha, at, ln in sites:
        f = ROOT / path
        got = hashlib.sha256(f.read_bytes()).hexdigest() if f.is_file() else "MISSING"
        if got != sha:
            bad.append(f"{at}:{ln} {path}: {got[:16]} != pinned {sha[:16]}")
    return bad


def claim_vendored(sites) -> tuple[list[str], list[tuple[str, str, str, str]]]:
    """`(path, head, upstream, last-move)` per pinned blob, plus the failures."""
    rows, bad = [], []
    for path in sorted({s[0] for s in sites}):
        head, up = resolve("HEAD", path), resolve("refs/remotes/upstream/master", path)
        if head is None or up is None:
            bad.append(f"{path}: not in HEAD ({head}) / not at refs/remotes/upstream/master ({up})")
            continue
        rc, out = git("hash-object", path)
        if rc == 0 and out != head:
            bad.append(f"{path}: working tree {out[:12]} != HEAD blob {head[:12]}")
        if head != up:
            bad.append(f"{path}: HEAD blob {head[:12]} != refs/remotes/upstream/master {up[:12]} "
                       f"-- tinygrad/ has DIVERGED from the vendored bytes")
        rc, c = git("log", "-1", "--format=%H", "--", path)
        last = c if rc == 0 else None
        moved = "NO-COMMIT"
        if last:
            before, after = resolve(f"{last}^", path), resolve(last, path)
            # THREE STATES, NOT TWO. A commit whose parent held NO blob for the path did not move
            # it and did not leave it alone -- it ADDED it, which is the reading of `813bbec3e`
            # ("RESTORE 6141 FILES DELETED BY THE JJ INDEX WIPE") and the state a binary
            # MOVED/unchanged pair would report as UNKNOWN, i.e. as an absence of evidence
            # about the one commit that explains the file's presence in this tree.
            moved = ("ADDED" if before is None and after else "MOVED" if before != after
                     else "unchanged")
        rows.append((path, head[:12], (up or "ABSENT")[:12], f"{moved} @ {(last or '?')[:9]}"))
    return bad, rows


def report(sites, rows, per_caller) -> None:
    print(f"population blobpin sites={len(sites)} paths={len({s[0] for s in sites})} "
          f"callers={len(per_caller)} literals={len(sites)} derived=0")
    for at, n in sorted(per_caller.items()):
        print(f"  caller {at:<44} tinygrad-sites={n}")
    for path, sha, at, ln in sorted(sites, key=lambda s: (s[0], s[2])):
        print(f"  LITERAL {path:<26} {sha[:16]}  {at}:{ln}")
    print("\nclaim LAST-MOVE -- DERIVED from git, no sha transcribed in this file:")
    for path, head, up, moved in rows:
        print(f"  {path:<26} HEAD={head} upstream={up}  last-commit {moved}")


def plant(sites) -> int:
    """One hex digit flipped in a COPY, and the census must notice. The tree is never a base."""
    with tempfile.TemporaryDirectory() as tmp:
        mirror = Path(tmp)
        for home in HOMES:
            (mirror / home).mkdir()
            for p in (ROOT / home).rglob("*.py"):
                (mirror / home / p.relative_to(ROOT / home)).symlink_to(p)
        victim = mirror / sites[0][2]
        # THE FIRST HEX DIGIT, because that is the real failure mode -- a mistyped pin -- and
        # because `gatekit.oracle_drift` prints 16 characters: flipping the LAST one leaves the
        # printed window identical and the plant reports FIRED with two equal strings, which is
        # the one message that cannot be read.
        mutant = victim.read_text().replace(sites[0][1], ("0" if sites[0][1][0] != "0" else "1")
                                            + sites[0][1][1:], 1)
        if mutant == victim.read_text():
            print("PLANT REFUSED: the site text was not found in its own file")
            return REFUSED
        victim.unlink()
        victim.write_text(mutant)
        got, _, _ = census(mirror)
        bad = claim_intact(got)
        print(f"PLANT one digit of {sites[0][1][:16]} flipped in a COPY of {sites[0][2]}")
        print(f"  population {len(sites)} -> {len(got)}   intact {len(sites)} -> {len(got) - len(bad)}")
        for b in bad:
            print(f"  FIRED {b}")
        if len(got) != len(sites) or not bad:
            print("PLANT FAILED: the census did not move, so it cannot see a drift")
            return FAIL
        print("PLANT OK: the population is unchanged and one site went red")
    return PASS


def main() -> int:
    if S.run(["git", "--version"], capture_output=True).returncode != 0:
        print("REFUSED: no git", file=sys.stderr)
        return REFUSED
    rc, _ = git("rev-parse", "--verify", "refs/remotes/upstream/master")
    if rc != 0:
        print("REFUSED: refs/remotes/upstream/master is absent -- the VENDORED claim needs the "
              "vendored bytes to compare against, and comparing against nothing is a PASS that "
              "measured nothing", file=sys.stderr)
        return REFUSED
    sites, unresolved, per_caller = census(ROOT)
    if unresolved:
        print(f"REFUSED, NOT A VERDICT: {len(unresolved)} caller(s) of oracle_drift are not "
              f"resolvable here: {unresolved}", file=sys.stderr)
        return REFUSED
    if not sites:
        print("DEAD: zero in-code tinygrad blob pins found, so zero drift is reportable",
              file=sys.stderr)
        return DEAD
    if "--plant" in sys.argv:
        return plant(sites)
    vendored, rows = claim_vendored(sites)
    report(sites, rows, per_caller)
    bad = claim_intact(sites) + vendored
    for b in bad:
        print(f"  FAILED {b}", file=sys.stderr)
    print(f"blobpin-census-gate: {verdict_of(FAIL if bad else PASS)} "
          f"-- {len(sites)} literal pin(s) over {len(rows)} blob(s), "
          f"{'all intact and all vendored' if not bad else str(len(bad)) + ' claim(s) false'}")
    return FAIL if bad else PASS


if __name__ == "__main__":
    sys.exit(main())
