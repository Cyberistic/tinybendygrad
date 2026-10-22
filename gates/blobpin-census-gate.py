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
              **AND THE CLAIM IS NOW MEASURED RATHER THAN ASSUMED.** The population used to be
              the LITERALS THEMSELVES, so a pin whose value was `sha256(x).hexdigest()` of the
              very file it checks was not a site at all -- it was INVISIBLE, and the count simply
              went down. The population is now every PATH KEY in a pin dict, and the value is
              the claim: a value that is not a quoted hex constant is DERIVED and the gate
              fails. **THIS IS THE ARM NOBODY PLANTED, and it is planted here:** a copy of a
              caller whose pin is re-derived from the file it checks must be REPORTED, and the
              report must be shown to matter by running the reader against a MUTATED copy of
              the file -- a LITERAL pin goes red there and the RE-DERIVED one does not.

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

**AND THIS FILE WAS DEAD, WHICH IS WHY THE LITERAL CLAIM WAS NEVER MEASURED.** MEASURED
2026-10-22: `blobpin-census-gate.py` exited 1 with a traceback --
`IndexError: list index out of range` at the line that printed the unresolved caller's argument.
The cause was a call site with an EMPTY argument: `gates/edge-fixture-census.py:529` and
`checks/.e2e-fixture/e2esh/plant.py` name `oracle_drift()` in PROSE, and the census's
`_uncomment` strips `#` comments but not DOCSTRINGS. **A CENSUS THAT CRASHES ON ITS OWN
POPULATION REPORTS NOTHING**, and this one reported nothing at all, so the claim it exists to
make -- that every pin in the tree is a LITERAL -- was a sentence and not a reading. An empty
argument is now what it is: a MENTION, not a call, because `oracle_drift` REQUIRES an argument.
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
# EVERY PATH KEY IN A PIN DICT, WHATEVER ITS VALUE. `SITE` finds the sites whose value IS a
# quoted hex constant; this finds the KEYS, so a pin whose value is DERIVED is still in the
# population and can be REPORTED. A census whose population is the literals can only ever see
# literals, which is how a derived pin became invisible.
KEY = re.compile(r"""["'](?P<path>tinygrad/\S+\.py)["']\s*:""")
# AND WHAT COUNTS AS A LITERAL VALUE: a quoted hex constant and nothing else.
HEX = re.compile(r"""["'][0-9a-f]{40,64}["']""")
# EVERY CALL SITE OF THE READER. `gatekit.py` defines it; everyone else consumes it.
CALL = re.compile(r"\boracle_drift\s*\(")
DEF = "def oracle_drift"
# A `#` COMMENT IS NOT A CALL SITE. `gates/banner-gate.py:87` names `oracle_drift()` in prose and
# this file's first draft counted it as a caller and REFUSED on its own population -- an
# instrument that cannot tell a mention from a use is the `repro-paths.py` class one level up.
# Line comments are stripped before the scan; `splitlines`/`join` keeps one line per line, so
# every reported line number is still the file's own.
COMMENT = re.compile(r"#.*$")


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


# A SIBLING FILE THIS FILE NAMES BY PATH. `gates/float-halfclass-gate.py` loads
# `gates/subnormal-flush-gate.py` this way and `gates/bendfloat-gate.py` loads
# `gates/float-halfclass-gate.py` this way, so the two of them reach ONE pin dict
# through a chain of two.
PATHY = re.compile(r"""HERE\s*/\s*["'](?P<name>[\w.-]+\.py)["']""")
# A MODULE-LEVEL ASSIGNMENT, and the NAME its right-hand side starts with.
ASSIGN = re.compile(r"^\s*(?P<name>[A-Za-z_]\w*)\s*=\s*(?P<rhs>[^\n#]+)", re.M)
# A CONDITIONAL'S TRUE BRANCH: `pin = ORACLE_PIN if pin is None else pin` names
# `ORACLE_PIN`, and that is the dict the call site ends up reading.
COND = re.compile(r"([A-Za-z_]\w*)\s+if\b")
IDENT = re.compile(r"[A-Za-z_]\w*")


def _arg_name(arg: str) -> str | None:
    """The NAME a call site's argument names, or None.

    `DRIFT_PIN` and `ORACLE_PIN` are names. `sfg.ORACLE_PIN` is a qualified name and
    the dict it names is the one the LAST component names. `DELEGATED if pins is None
    else pins` is a conditional and the dict it names is the one the TRUE branch names."""
    m = COND.match(arg)
    if m:
        return m.group(1)
    m = IDENT.match(arg)
    if not m:
        return None
    head = m.group(0)
    if arg.startswith(head) and "." in arg:
        return arg.rsplit(".", 1)[1].strip()
    return head


def _closure(src: Path, t: str) -> list[Path]:
    """The files this file NAMES BY PATH, and the files THOSE name, and so on.

    It is the TRANSITIVE closure because `gates/bendfloat-gate.py` reaches
    `gates/subnormal-flush-gate.py`'s `ORACLE_PIN` through
    `gates/float-halfclass-gate.py`, and a one-level search would not find it."""
    out: list[Path] = []
    seen: set[Path] = set()
    queue = [src]
    while queue:
        cur = queue.pop()
        try:
            txt = cur.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in PATHY.finditer(txt):
            nxt = cur.parent / m.group("name")
            if nxt in seen or not nxt.is_file():
                continue
            seen.add(nxt)
            out.append(nxt)
            queue.append(nxt)
    return out


def _assigned_name(t: str, name: str) -> str | None:
    """The NAME a module-level assignment of `name` starts its right-hand side with."""
    for m in ASSIGN.finditer(t):
        if m.group("name") != name:
            continue
        rhs = m.group("rhs").strip()
        c = COND.match(rhs)
        if c:
            return c.group(1)
        i = IDENT.match(rhs)
        return i.group(0) if i else None
    return None


def _resolve_pin_dict(src: Path, t: str, arg: str) -> str | None:
    """The TEXT of the pin dict a call site's argument names, or None.

    THE FOUR SHAPES, AND WHY THEY ARE ONE RULE. MEASURED 2026-10-22, three callers used
    the last three and the census REFUSED on all of them, so it certified nothing:

      1. `DRIFT_PIN = { ... }` in the caller's own file.
      2. `ORACLE_PIN = sfg.ORACLE_PIN` -- an ALIAS of another module's dict.
      3. `sfg.ORACLE_PIN` -- a QUALIFIED name.
      4. `def gate(..., pin=None)` and `pin = ORACLE_PIN if pin is None else pin` -- a
         PARAMETER whose default is a module-level dict.

    THE RULE: reduce the argument to a NAME, find the dict literal assigned to that name
    in the caller's own file and then in the files the caller NAMES BY PATH, and if it is
    not there, follow the caller's own assignment of that name and try again. A census
    that cannot see its population cannot be anything, so the shapes are resolved rather
    than reported as a smaller number."""
    name = _arg_name(arg)
    if not name:
        return None
    files = [src] + _closure(src, t)
    seen: set[str] = set()
    while name and name not in seen:
        seen.add(name)
        for f in files:
            try:
                body = _dict_for(f.read_text(encoding="utf-8", errors="replace"), name)
            except OSError:
                body = None
            if body is not None:
                return body
        nxt = _assigned_name(t, name)
        if not nxt or nxt == name:
            return None
        name = nxt
    return None


def _value_after(body: str, i: int) -> str:
    """The VALUE EXPRESSION of one dict entry, from the character after its key.

    It ends at the next `,` or `}` at DEPTH ZERO, so a call inside the value does not end
    it, and it may span lines -- six of the tree's sites put the literal on the line BELOW
    the key."""
    depth, j = 0, i
    while j < len(body):
        c = body[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return body[i:j].strip()
            depth -= 1
        elif c == "," and depth == 0:
            return body[i:j].strip()
        j += 1
    return body[i:j].strip()


def census(src: Path) -> tuple[list[tuple[str, str, str, int]], list[tuple[str, str, str, int]],
                               list[str], dict[str, int]]:
    """`(sites, derived, unresolved, per_caller)`.

    `sites` are the LITERAL pin sites -- `(path, sha, file, line)`. `derived` are the pin
    entries whose value is NOT a literal -- `(path, value, file, line)` -- and they are in
    the POPULATION, not in a footnote, because a census whose population is the literals can
    only ever see literals. `unresolved` are the callers this file could not resolve, and
    they are reported, never skipped: a caller whose pins live where this file cannot see
    them is a population it cannot see, and a census that cannot see its population cannot
    be anything. The per-caller COUNT is what makes a caller that quietly stopped pinning
    anything visible rather than merely absent.

    AN EMPTY ARGUMENT IS A MENTION, NOT A CALL. `oracle_drift` REQUIRES an argument, so
    `oracle_drift()` is a mention in prose -- `gates/edge-fixture-census.py:529` and
    `checks/.e2e-fixture/e2esh/plant.py` both have one -- and the census used to CRASH on
    them, because the line that reported an unresolved caller printed `arg.splitlines()[0]`
    and an empty argument has no lines. MEASURED 2026-10-22, this file exited 1 with an
    `IndexError` and reported NOTHING, so the LITERAL claim it exists to make was a
    sentence rather than a reading."""
    sites: list[tuple[str, str, str, int]] = []
    derived: list[tuple[str, str, str, int]] = []
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
                if not arg:
                    continue  # a MENTION: `oracle_drift()` has no argument and is not a call
                body = arg if arg.startswith("{") else _resolve_pin_dict(p, t, arg)
                if body is None:
                    unresolved.append(f"{rel}:{line} oracle_drift({arg.splitlines()[0][:40]})")
                    continue
                n = len(SITE.findall(body))
                per_caller[f"{rel}:{line}"] = n
                for m in SITE.finditer(body):
                    at = t.find(m.group(0))
                    sites.append((m.group("path"), m.group("sha"), rel,
                                  t.count("\n", 0, at) + 1 if at >= 0 else line))
                for m in KEY.finditer(body):
                    val = _value_after(body, m.end())
                    if HEX.fullmatch(val):
                        continue
                    at = t.find(m.group(0))
                    derived.append((m.group("path"), val, rel,
                                    t.count("\n", 0, at) + 1 if at >= 0 else line))
    return sites, derived, unresolved, per_caller


def claim_literal(derived) -> list[str]:
    """EVERY PIN ENTRY'S VALUE IS A LITERAL, and this is MEASURED.

    A DERIVED pin -- the sha256 of the very file it checks, computed at run time -- is
    `sha256(x) == sha256(x)`: it cannot fail, and an instrument that cannot fail is worse
    than no instrument. The population used to be the literals THEMSELVES, so such a pin
    was INVISIBLE: it was not a site, the count went down, and nothing said so."""
    return [f"{at}:{ln} {path}: the pinned sha256 is DERIVED ({val[:56]!r}) -- a pin "
            f"re-derived from the file it checks cannot fail"
            for path, val, at, ln in derived]


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


def report(sites, derived, rows, per_caller) -> None:
    print(f"population blobpin sites={len(sites)} paths={len({s[0] for s in sites})} "
          f"callers={len(per_caller)} literals={len(sites)} derived={len(derived)}")
    for at, n in sorted(per_caller.items()):
        print(f"  caller {at:<44} tinygrad-sites={n}")
    for path, sha, at, ln in sorted(sites, key=lambda s: (s[0], s[2])):
        print(f"  LITERAL {path:<26} {sha[:16]}  {at}:{ln}")
    for path, val, at, ln in sorted(derived, key=lambda s: (s[0], s[2])):
        print(f"  DERIVED {path:<26} {val[:40]:<42}  {at}:{ln}")
    print("\nclaim LAST-MOVE -- DERIVED from git, no sha transcribed in this file:")
    for path, head, up, moved in rows:
        print(f"  {path:<26} HEAD={head} upstream={up}  last-commit {moved}")


def plant(sites, derived) -> int:
    """THE ARMS, each on a COPY. The tree is never a base.

    ARM 0 CONTROL   the real tree's census is GREEN: every pin is a literal, every literal
                    is intact, and every pinned blob is vendored. This is the UNBROKEN
                    CONTROL -- a plant with no green control measures nothing.
    ARM 1 LITERAL   one hex digit of one pin is flipped in a COPY. The census must notice,
                    because the file the pin names no longer has the bytes the pin says.
    ARM 2 RE-DERIVED  **THE ARM NOBODY PLANTS.** A pin whose value is the sha256 of the
                    very file it checks, computed at run time, is `sha256(x) == sha256(x)`:
                    it CANNOT FAIL. Two things are measured, and both matter:
                      (a) the census must REPORT it -- the pin's entry is in the population
                          because the population is the KEYS, not the literals; and
                      (b) the report must be shown to MATTER, by running the reader
                          `gatekit.oracle_drift` itself against a MUTATED copy of the file: a
                          LITERAL pin goes RED there and the RE-DERIVED pin does not.
                    (b) is the half that shows the LITERAL claim is not bookkeeping."""
    import gatekit
    results: list[tuple[str, bool, str]] = []

    # ARM 0: THE UNBROKEN CONTROL.
    live_sites, live_derived, live_unresolved, _ = census(ROOT)
    live_vendored, _ = claim_vendored(live_sites)
    control = claim_intact(live_sites) + claim_literal(live_derived) + live_vendored
    results.append(("0 CONTROL the real tree's census is green", not control,
                    f"{len(live_sites)} literal(s), {len(live_derived)} derived, "
                    f"{len(control)} claim(s) false"))
    if live_unresolved:
        results.append(("0 CONTROL no caller is unresolved", False, str(live_unresolved)))

    with tempfile.TemporaryDirectory() as tmp:
        mirror = Path(tmp)
        for home in HOMES:
            (mirror / home).mkdir()
            for p in (ROOT / home).rglob("*.py"):
                # THE PARENT DIRECTORIES ARE MADE, because `gates/artifacts/` has SUBDIRECTORIES
                # and a symlink into a directory that does not exist raises. MEASURED: the first
                # run of this plant raised `FileNotFoundError` on
                # `gates/artifacts/code-reader-census/before-pincensus-pop.py`, and the plant had
                # never run before because the census CRASHED on its own population.
                dest = mirror / home / p.relative_to(ROOT / home)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.symlink_to(p)
        if not sites:
            print("PLANT REFUSED: no literal pin site to plant on", file=sys.stderr)
            return REFUSED
        victim = mirror / sites[0][2]
        original = victim.read_text()
        # ARM 1: THE FIRST HEX DIGIT, because that is the real failure mode -- a mistyped
        # pin -- and because `gatekit.oracle_drift` prints 16 characters: flipping the LAST
        # one leaves the printed window identical and the plant reports FIRED with two equal
        # strings, which is the one message that cannot be read.
        mutant = original.replace(sites[0][1], ("0" if sites[0][1][0] != "0" else "1")
                                  + sites[0][1][1:], 1)
        if mutant == original:
            print("PLANT REFUSED: the site text was not found in its own file", file=sys.stderr)
            return REFUSED
        victim.unlink()
        victim.write_text(mutant)
        got, got_derived, _, _ = census(mirror)
        bad = claim_intact(got)
        print(f"PLANT one digit of {sites[0][1][:16]} flipped in a COPY of {sites[0][2]}")
        print(f"  population {len(sites)} -> {len(got)}   intact {len(sites)} -> {len(got) - len(bad)}")
        for b in bad:
            print(f"  FIRED {b}")
        ok1 = len(got) == len(sites) and bool(bad)
        results.append(("1 LITERAL a mistyped sha256 is caught", ok1,
                        f"{len(bad)} site(s) red"))
        if not ok1:
            print("PLANT FAILED: the census did not move, so it cannot see a drift")

        # ARM 2: THE RE-DERIVED PIN. THE CENSUS MUST CATCH IT, AND THE CENSUS'S CATCH MUST
        # MATTER.
        #
        # (a) THE TAUTOLOGY, MEASURED ON A COPY. The file the pin names is COPIED and one
        # byte is appended; the reader is pointed at the copy. A LITERAL pin over it goes
        # RED; the SAME pin RE-DERIVED from the copy's own bytes stays GREEN, because
        # `sha256(x) == sha256(x)`. That is the whole reason the value must be a literal.
        rel = sites[0][0]
        with tempfile.TemporaryDirectory() as td:
            scratch = Path(td)
            (scratch / rel).parent.mkdir(parents=True, exist_ok=True)
            (scratch / rel).write_bytes((ROOT / rel).read_bytes() + b"\n# planted\n")
            keep = gatekit.ROOT
            gatekit.ROOT = scratch
            try:
                literal_bad = gatekit.oracle_drift({rel: sites[0][1]})
                rederived = hashlib.sha256((scratch / rel).read_bytes()).hexdigest()
                derived_bad = gatekit.oracle_drift({rel: rederived})
            finally:
                gatekit.ROOT = keep
        print(f"PLANT the file {rel} is COPIED and one byte appended, and the reader is "
              f"pointed at the copy")
        print(f"  a LITERAL pin over the copy: {len(literal_bad)} complaint(s) "
              f"{literal_bad[:1]}")
        print(f"  a RE-DERIVED pin over the copy: {len(derived_bad)} complaint(s) "
              f"{derived_bad[:1]}  <-- it CANNOT fail")
        ok2a = bool(literal_bad) and not derived_bad
        results.append(("2 RE-DERIVED the tautology cannot fail, the literal can", ok2a,
                        f"literal {len(literal_bad)}, re-derived {len(derived_bad)}"))

        # (b) THE CENSUS MUST REPORT IT. The victim's pin is replaced by the re-derivation
        # -- the EXACT shape that cannot fail -- and the census over the copy must name it.
        # THE VICTIM IS RESTORED FIRST, because ARM 1 already changed it.
        victim.unlink()
        victim.write_text(original)
        derived_expr = (f'__import__("hashlib").sha256((ROOT / "{rel}").read_bytes())'
                        f'.hexdigest()')
        mutant2 = original.replace(f'"{sites[0][1]}"', derived_expr, 1)
        if mutant2 == original:
            print("PLANT REFUSED: the site's literal was not found in the copy", file=sys.stderr)
            return REFUSED
        victim.unlink()
        victim.write_text(mutant2)
        got2, got_derived2, _, _ = census(mirror)
        named = [d for d in got_derived2 if d[2] == sites[0][2]]
        print(f"PLANT the pin in a COPY of {sites[0][2]} is RE-DERIVED from the file it checks")
        print(f"  literals {len(got2)} (was {len(got)})   derived {len(got_derived2)}")
        for d in named:
            print(f"  REPORTED {d[0]} at {d[2]}:{d[3]}: {d[1][:60]}")
        ok2b = bool(named) and len(got_derived2) > len(derived)
        results.append(("2 RE-DERIVED the census REPORTS it", ok2b,
                        f"{len(named)} derived entry/entries in the copy"))

    for label, ok, detail in results:
        print(f"  {'OK  ' if ok else 'FAIL'} {label}  --  {detail}")
    bad = [l for l, ok, _ in results if not ok]
    print(f"PLANT {'OK' if not bad else 'FAILED'}: {len(results) - len(bad)} of {len(results)} "
          f"arm(s) behaved as required")
    return PASS if not bad else FAIL


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
    sites, derived, unresolved, per_caller = census(ROOT)
    if unresolved:
        print(f"REFUSED, NOT A VERDICT: {len(unresolved)} caller(s) of oracle_drift are not "
              f"resolvable here: {unresolved}", file=sys.stderr)
        return REFUSED
    if not sites and not derived:
        print("DEAD: zero in-code tinygrad blob pins found, so zero drift is reportable",
              file=sys.stderr)
        return DEAD
    if "--plant" in sys.argv:
        return plant(sites, derived)
    vendored, rows = claim_vendored(sites)
    report(sites, derived, rows, per_caller)
    bad = claim_intact(sites) + claim_literal(derived) + vendored
    for b in bad:
        print(f"  FAILED {b}", file=sys.stderr)
    print(f"blobpin-census-gate: {verdict_of(FAIL if bad else PASS)} "
          f"-- {len(sites)} literal pin(s) over {len(rows)} blob(s), {len(derived)} derived, "
          f"{'all intact and all vendored' if not bad else str(len(bad)) + ' claim(s) false'}")
    return FAIL if bad else PASS


if __name__ == "__main__":
    sys.exit(main())
