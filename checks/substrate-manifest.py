#!/usr/bin/env python3
"""WHICH MEMBER MOVED -- one row per substrate member, written BY THE RUN, so it can be answered.

    usage: .venv/bin/python checks/substrate-manifest.py --write [PATH]   # the run's one call
           .venv/bin/python checks/substrate-manifest.py --diff  [PATH]   # tree vs manifest, no run claim
           .venv/bin/python checks/substrate-manifest.py --check [SUMMARY]
           .venv/bin/python checks/substrate-manifest.py --cost
           .venv/bin/python checks/substrate-manifest.py --plant

EXIT: 0 PASS · 1 FAIL · 3 REFUSED (gatekit's, `gates/gatekit.py:59`).

THE QUESTION THIS EXISTS TO ANSWER. A run records `substrate-start`/`substrate-end` as 64 hex
characters (`checks/differ.py:525,747`). Given those two rows and a tree, you can say WHETHER the
substrate moved and you can say it in the writer's own encoding (`checks/substrate-current.py`),
and then you are stuck: on a population of N the diagnosis is 1 bit and the population is N.
MEASURED 2026-10-17, `substrate-current.py --plant`, on this file's own tree:
`RESIDUAL: ... 0 of 151 members are recorded per-path (24 key=value rows, 2 of them 64-hex)`. So a
unit could only DEcline to write a lane into `runs/graphcmp/D/` -- citing that the substrate had
already moved and a lane taken from a different tree would falsify the record -- and the record
could not be defended, because the bytes it was taken from were unnameable.

TWO ANSWERS, NOT ONE, AND THE SECOND IS THE POINT. A digest is a FOLD: it is many-to-one, so from
`recorded != live` alone you cannot separate "a member's bytes moved" from "the population is
different" -- a file edited, a file added and a file deleted all print the same one bit. This file
makes both answers reachable, and they are different ANSWERS, not different shades of FAIL:

    BYTES-DRIFT   the same PATHS, different CONTENT. Every differing member is NAMED, with the
                  recorded and the live sha256 side by side, and the count is `k of N`.
    POPULATION-DRIFT  the recorded manifest carries paths the tree does not, or the tree carries
                  paths the manifest does not. THE DIGEST IS OVER A DIFFERENT POPULATION, and
                  saying so is the only true sentence available -- because a hash over a
                  different set of (path, bytes) pairs is not a measurement that missed, it is a
                  measurement of something else.

WHY THE MANIFEST LIVES BESIDE `D/` AND NOT INSIDE IT. MEASURED: planting a `MANIFEST.tsv` in a
copy of `runs/graphcmp/D` and calling the REAL `differ.artefacts_ok()` takes it from **0 findings
to 1**, and the finding is `UNEXPECTED MANIFEST.tsv` -- `artefacts_ok()` walks `D/` and reports
anything `declared()` does not name, so a new file there is a permanent red by construction. One
level up is untracked (`.gitignore:207` `/runs/`), beside the run directory it describes, and
invisible to every consumer of `D/`. The alternative -- naming it in `LITERALS` so `declared()`
knows it -- is a `checks/differ.py` edit, reported in `.agents/slop/manifestcost/REPORT.md`, NOT
made here.

THE MANIFEST IS THE DIGEST, UNFOLDED -- and that is why one extra row is not a second opinion.
`substrate_digest()` (`differ.py:919`) folds `sha256(relpath) + NUL + sha256(bytes).hexdigest()`,
NUL-terminated, over `sorted(substrate_entries())`. So the member rows are not a re-encoding of
the digest, they are its INPUT, and the header row carries the writer's OWN `substrate_digest()`
value so the reader can decide whether a manifest belongs to the run whose summary it is sitting
beside. **The header is a string compare, not a re-fold**: nothing here re-types the writer's
aggregation, because a re-typed aggregation is a pin that goes red when somebody tidies it
(`substrate-current.py:180-185` says this and passes `members=` into the reader instead). What
this file asks the writer for is `substrate_entries()` -- ONE call, the same list the digest folds
-- and a manifest whose rows disagree with the recorded digest is caught by the header row.

**`ABSENT` IS A MEMBER WITH NO BYTES, AND IT IS CARRIED AS ONE.** `differ.substrate_entries()`
already emits the token `ABSENT` for a declared input that is not on disk, so a deletion and an
addition both move the recorded digest and the population cannot silently shrink
(`differ.py:882`). The manifest therefore stores `ABSENT` verbatim and the comparison is uniform
over present and absent members -- no special case, no second code path.

WHAT IT COSTS, MEASURED, BECAUSE THE COMMON CASE IS THE TRADE. 151 rows and 15 077 B per run at
`--write`, against the 2-row `substrate-start`/`substrate-end` pair it accompanies, and the extra
hashing is **12.3 ms**, i.e. zero: the rows are the digest's own input, so a run that stamps the
manifest has already paid for the digest it is stamped with. THE NOISE IS THE BUY, and the noise
is bounded by measurement rather than by hope -- see `residual_noise()`.

THE DENOMINATOR IS THE WRITER's POPULATION, ASKED FOR, NEVER A WALK OF THIS FILE's OWN. Every
count here comes from `len(writer.substrate_entries())` on the root being measured. That is the
lesson of the cohort twice over: `checks/runs-artifacts.py`'s `DENOMINATOR` printed CALL SITES
where a reader read LANES, and a pin file a generator names is not a pin file a list names. The
number that would be tempting here -- `checks/substrate-snapshot.py`'s `COPIES`, 153 members, the
READER's population -- is the WRONG denominator for this instrument, and using it would make a
manifest that cannot fold to the run's own digest look correct.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import pathlib
import shutil
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
#: THE WRITER. Asked for `substrate_entries()` and for `substrate_digest()`, never re-typed: a
#: recorded `substrate-end` is only comparable to a live reading taken with the function that
#: wrote it (`substrate-current.py:19-23`).
WRITER = "checks/differ.py"
SUMMARY = "runs/graphcmp/D/D0-run-summary.txt"
#: BESIDE `D/`, measured above. `.gitignore:207` is `/runs/`, so this is untracked like the run it
#: describes -- and the run directory is a FIXED name reused by every run, which is exactly why the
#: header row earns its place: a manifest left behind by an older run is DETECTED, not believed.
MANIFEST = "runs/graphcmp/MANIFEST.tsv"
ROWS = ("substrate", "members")
ROW, COUNT = ROWS
PASS, FAIL, REFUSED = 0, 1, 3
NAMES = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED"}


def token(rc: int) -> str:
    """The verdict CODE as a WORD, the only place it happens. `bool` subclasses `int`, so a
    `return ok` would silently key the wrong word; `substrate-id.py:122-124` rejects exactly that
    type and keeps `IntEnum`, and this is the same one-line rule."""
    if isinstance(rc, bool):
        return f"NOT-A-VERDICT({type(rc).__name__})"
    return NAMES.get(rc, f"NOT-A-VERDICT({rc})")


def load(rel: str, root: pathlib.Path):
    """A LANE LOADED BY PATH, OUT OF THE ROOT BEING MEASURED. `None` is a tree without a lane, which
    is a measurement of a tree without a lane and has its own verdict."""
    p = root / rel
    if not p.is_file():
        return None
    spec = importlib.util.spec_from_file_location(rel.replace("/", "_").replace("-", "_"), p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def live(root: pathlib.Path, writer=None) -> list[tuple[str, str]]:
    """`(relpath, sha256|ABSENT)` for every member of the WRITER's population, SORTED BY RELPATH --
    the writer's own sort key (`differ.py:925`), because a manifest in another order would not be
    a manifest of that population."""
    w = writer or load(WRITER, root)
    return sorted(w.substrate_entries()) if w else []


def stamp(root: pathlib.Path, path: pathlib.Path | None = None,
          writer=None) -> int:
    """THE RUN's ONE CALL. Writes the manifest and returns its row count.

    STAGED AND RENAMED, like `differ.run()`'s own `.tmp.<name>` staging: a half-written manifest
    read by a later `--check` would name a population that never existed, and a torn file is worse
    than an absent one because it is believed. `os.replace` is atomic within a filesystem, and the
    temp name sits beside the target so the rename cannot cross one.

    `writer` IS A PARAMETER BECAUSE THE CALLER IS `differ.py` ITSELF, IN-PROCESS: the run passes
    the module it is already executing rather than making this file exec a second copy of it. The
    CLI passes `None` and gets the by-path load. Both paths take `substrate_entries()` from the
    same module object, so "written by the run" is a fact about the CALL, not a second reading.

    TWO HEADER ROWS, AND THE SECOND ONE IS NOT REDUNDANT. `members=` is what keeps a TRUNCATED
    manifest from being MISDIAGNOSED. MEASURED: the first version carried `substrate=` alone, and a
    manifest with one row dropped answered `FAIL -- THE DIGEST IS OVER A DIFFERENT POPULATION` and
    named the dropped path **TREE-ONLY**, i.e. it claimed THE TREE had gained a file, which was
    false -- the tree was exactly the tree the manifest was taken on. One row catches that, and the
    alternative (re-folding the rows and comparing to `substrate=`) would mean re-typing the
    writer's aggregation, which is the defect this file exists beside."""
    rows = live(root, writer)
    out = path or (root / MANIFEST)
    out.parent.mkdir(parents=True, exist_ok=True)
    body = [f"{ROW}={(writer or load(WRITER, root)).substrate_digest()}", f"{COUNT}={len(rows)}"] \
        + [f"{b}\t{r}" for r, b in rows]
    tmp = out.with_name(f".tmp.{out.name}")
    tmp.write_text("\n".join(body) + "\n")
    os.replace(tmp, out)
    return len(rows)


def read(path: pathlib.Path) -> tuple[dict[str, str], str | None, int | None]:
    """`(relpath -> sha256|ABSENT, recorded digest, declared count)`. A row with no TAB is not a
    member row and is refused rather than guessed at, so a hand-edited or truncated file cannot
    become a population; a duplicated relpath is the same sentence, because a population that
    lists one member twice has stopped being a set."""
    rows: dict[str, str] = {}
    head: str | None = None
    count: int | None = None
    for ln in path.read_text().splitlines():
        if not ln.strip():
            continue
        blob, tab, rel = ln.partition("\t")
        if tab:
            if not rel or rel in rows:
                return {}, None, None
            rows[rel] = blob
        elif ln.startswith(f"{ROW}="):
            head = ln[len(ROW) + 1:]
        elif ln.startswith(f"{COUNT}="):
            count = int(ln[len(COUNT) + 1:] or -1)
        else:
            return {}, None, None
    return rows, head, count


def drift(rows: dict[str, str], here: list[tuple[str, str]]) -> dict:
    """THE THREE DISJOINT CASES, AS LISTS, and nothing else. Membership FIRST because a path that
    is not in both sets has no sha to compare, and reporting it as a content difference would be
    reporting a difference between a member and an absence."""
    now = dict(here)
    return {"gone": sorted(set(rows) - set(now)),
            "new": sorted(set(now) - set(rows)),
            "moved": sorted(r for r in set(rows) & set(now) if rows[r] != now[r]),
            "n": len(rows)}


def diagnose(root: pathlib.Path, summary: pathlib.Path | None,
            manifest: pathlib.Path) -> tuple[int, list[str]]:
    """THE VERDICT, AND THE SENTENCE. Six questions in the order they can be answered; the first
    three are the residual made a REFUSAL instead of a mood."""
    w = load(WRITER, root)
    out: list[str] = []
    if w is None:
        return REFUSED, [f"{WRITER} is ABSENT from this tree, so the population that produced the "
                         "recorded digest cannot be named"]
    here = live(root, w)
    if not here:
        return REFUSED, ["the writer declares 0 members, so there is no population to compare"]
    recorded = None
    if summary is not None:
        if not summary.exists():
            return REFUSED, [f"{summary} is absent -- there is no run for a manifest to belong to"]
        got = {k.strip(): v.strip() for k, _, v in
               (ln.partition("=") for ln in summary.read_text(errors="replace").splitlines()) if _}
        recorded = got.get("substrate-end")
        if recorded is None:
            return REFUSED, ["the summary records no substrate-end= -- a run that does not say "
                             "which bytes produced it is a measurement with no subject"]
    if not manifest.exists():
        out.append(f"NO MANIFEST at {manifest} -- the run recorded a digest and 0 of {len(here)} "
                   "members per-path, so WHICH file moved is not a question this record can answer")
        return REFUSED, out
    rows, head, count = read(manifest)
    if head is None or not rows:
        return REFUSED, [f"{manifest} carries no header row or no member row -- a manifest without "
                         "a recorded digest cannot be attributed to a run and an unparsable one "
                         "cannot be a population"]
    if count != len(rows):
        return REFUSED, [f"{manifest} declares members={count} and holds {len(rows)} member row(s) "
                         "-- A MANIFEST THAT LOST ROWS. This is not POPULATION-DRIFT: reporting it "
                         "as such would name the missing paths TREE-ONLY and claim the tree gained "
                         "files it never had"]
    if recorded is not None and head != recorded:
        return REFUSED, [f"this manifest records {ROW}={head[:12]} but the run recorded "
                         f"substrate-end={recorded[:12]} -- A MANIFEST FROM A DIFFERENT RUN, so "
                         "naming members against it would name the wrong tree's"]
    out.append(f"manifest {ROW}={head[:12]}  {len(rows)} member row(s), members={count}"
               + ("  == the run's substrate-end" if recorded is not None else "  (no run claimed)"))
    d = drift(rows, here)
    if not (d["gone"] or d["new"] or d["moved"]):
        out.append(f"PASS: 0 of {d['n']} recorded member(s) differ -- this tree IS the substrate "
                   "the manifest was taken on")
        return PASS, out
    if d["gone"] or d["new"]:
        out.append(f"FAIL: THE DIGEST IS OVER A DIFFERENT POPULATION -- {len(rows)} recorded "
                   f"member(s) against {len(here)} here")
        out += [f"  RECORDED-ONLY  {r}" for r in d["gone"]] \
            + [f"  TREE-ONLY       {r}" for r in d["new"]]
    else:
        out.append(f"FAIL: {len(d['moved'])} of {d['n']} member(s) differ -- the population is "
                   "the same and these are the bytes that moved")
    now = dict(here)
    out += [f"  MOVED  {r}  recorded={rows[r][:12]} live={now[r][:12]}" for r in d["moved"]]
    return FAIL, out


def residual_noise(root: pathlib.Path) -> str:
    """THE PRICE, MEASURED BY WRITING ONE, WITH ITS OWN TIMESTAMP -- an unsigned row count in a
    report is the defect `AGENTS.md` records twice (`ruff check .` read 18781, 18797, 19677, 19679
    on four runs 193 s apart with no edit). The tree moves under every measurement here, and the
    bytes are `stat()`ed off a real file rather than summed from the row tuples, so the number
    printed is the number on disk."""
    w = load(WRITER, root)
    if w is None:
        return "REFUSED: no writer"
    t = time.perf_counter()
    w.substrate_digest()
    per = (time.perf_counter() - t) * 1e3
    with tempfile.TemporaryDirectory() as td:
        man = pathlib.Path(td) / "MANIFEST.tsv"
        n = stamp(root, man, w)
        size = man.stat().st_size
    return (f"MEASURED {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} on {root}\n"
            f"  members {n}   rows written {n + 2}   bytes on disk {size}\n"
            f"  digest {per:.1f} ms per pass, and the manifest adds no hashing: its rows ARE the\n"
            f"    digest's input, so a run that stamps it has already paid for the digest it is\n"
            f"    stamped with -- the marginal cost is the sort and the {size} B write\n"
            f"  against the 2 `substrate-` rows it accompanies: {n + 2} rows where there were 2")


# --------------------------------------------------------------------------- the plant
#: The stub members of a scratch tree, so the planted population has the real SHAPE and the real
#: `substrate_entries()` is the function under test. Copied for REAL: `checks/differ.py` and THIS
#: FILE, so `ROOT` is the scratch tree in both -- each lane reads its own `__file__`.
LANES = (WRITER, "checks/devpin.py", "checks/substrate-manifest.py")
STUBS = ("bin/bend", ".agents/slop/graphcmp.py", ".agents/slop/graphcmp.bend",
         ".agents/slop/graphcmp-oracle.py", ".agents/slop/graphcmp-dbg-oracle.py",
         ".agents/slop/graphcmp-p13-ops.py", "tinybendygrad/a.bend", "tinybendygrad/b.bend",
         "tinybendygrad/LAWS.bend", "tinybendygrad/LAWS/PROOF-ALL.bend")
MEMBER = "tinybendygrad/b.bend"
MOVED, MEMBER_BYTES = "// moved\n", "// tinybendygrad/b.bend\n"


def _seed(root: pathlib.Path) -> None:
    """A scratch tree with the SHAPE of the real one. `LAWS.bend` BESIDE `LAWS/` is deliberate: a
    directory and a file share a prefix there, which is where the two producers' sort orders part
    company (`substrate-current.py:244-248`)."""
    for rel in LANES:
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, root / rel)
    for rel in STUBS:
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(MEMBER_BYTES if rel == MEMBER else f"// {rel}\n")


#: THE THREE EDITS TO THE COMPARISON THIS FILE EXISTS TO MAKE, as
#: `(label, scenario, old, new, caught)` over its OWN source, each evaluated against the SAME TWO
#: READINGS OF THE SCENARIO IT IS ABOUT -- so an edit is CAUGHT only if it changes one of them.
#: A plant that only ever feeds the gate different DATA has not shown it reads the comparison, and
#: one fixed scenario would have called the first two edits "not caught" for the wrong reason.
#:
#: EACH MUTATION IS PAIRED WITH ITS OWN SCENARIO, and that is the fix for a census that reported
#: `0 of 3` on a tree where two of the three patches had not applied at all: `NOT-APPLIED` used to
#: be counted as `not caught`, so an instrument that could not edit anything looked like an
#: instrument with a blind spot. The two are different facts and are now reported differently.
_SELF = "if recorded is not None and head != recorded" + ":"
_POP = 'if d["gone"] or d["new"]' + ":"
MUTATIONS = (
    ("accept any manifest, not the run's", "other-run", _SELF, "if False" + ":", True),
    ("compare the LIVE digest instead of the recorded one", "bytes", _SELF,
     'if head != str(load(WRITER, root).substrate_digest())' + ":", True),
    ("drop the POPULATION case and report content drift only", "population", _POP,
     'if d["gone"] or d["new"] or True' + ":", True),
)
#: SCENARIO -> the change that makes it, and the undo. Named once each because the census makes the
#: change and undoes it, and two spellings of one fact is how a census comes to read a MOVED tree
#: as an unmoved one (`substrate-current.py:251-258`).
SCENARIOS = {"bytes": (MEMBER, MEMBER_BYTES, MOVED),
             "other-run": (None, None, None),  # the fixture, handled below
             "population": ("tinybendygrad/c.bend", None, "// new\n")}
#: `scenario -> the UNPATCHED reading`, filled by `plant()` from THIS module. It is the baseline a
#: patch is graded against, and it must be the real code's reading and not a constant: a census
#: that compares against a hand-written expectation is a test of the expectation.
_BASE: dict = {}


def _scenario(root: pathlib.Path, name: str) -> list:
    """PUT THE TREE IN THE SCENARIO AND SAY HOW TO UNDO IT. A scenario that cannot be undone is not
    a scenario."""
    if name == "other-run":
        s = root / SUMMARY
        s.write_text(s.read_text().replace("substrate-end=", "substrate-end=f", 1))
        return [lambda: s.write_text(s.read_text().replace("substrate-end=f", "substrate-end=", 1))]
    rel, _want, body = SCENARIOS[name]
    if name == "bytes":
        (root / rel).write_text(body)
        return [lambda: (root / rel).write_text(SCENARIOS["bytes"][1])]
    (root / rel).write_text(body)
    return [lambda: (root / rel).unlink()]


def _patched(old: str, new: str):
    """THIS FILE WITH ONE EDIT, EXECUTED. `__file__` is pinned to the real path so the patched
    module's `ROOT` is the real tree. **A marker that is not UNIQUE patches something other than
    what it names**, and that returns `None` -- which the census now REPORTS rather than counting
    as a miss."""
    src = pathlib.Path(__file__).read_text()
    if src.count(old) != 1:
        return None
    mod = type(sys)("substrate_manifest_mutant")
    mod.__file__ = str(pathlib.Path(__file__))
    exec(compile(src.replace(old, new, 1), mod.__file__, "exec"), mod.__dict__)
    return mod


def _caught(root, summary, manifest) -> list:
    """WHICH EDITS THE PLANT WOULD NOTICE, as `(label, seen, applied)`. **BOTH READINGS COME FROM
    THE PATCHED MODULE** and the comparison is `(rc, lines)`, not `rc`: dropping the POPULATION arm
    leaves both arms FAIL and differs only in the sentence, and a gate whose verdict includes its
    sentence has to be graded on the sentence (reading the unmoved tree from the unpatched module
    instead reports every edit caught -- a catch invented by the harness, measured in this cohort
    at `substrate-current.py:319-334`)."""
    out = []
    for label, scenario, old, new, _want in MUTATIONS:
        mod = _patched(old, new)
        if mod is None:
            out.append((label, False, False))
            continue
        undo = _scenario(root, scenario)
        after = mod.diagnose(root, summary, manifest)
        for u in undo:
            u()
        out.append((label, (mod.diagnose(root, summary, manifest), after) != _BASE[scenario], True))
    return out


def _rewrite(p: pathlib.Path, new: str) -> None:
    """One line, because every fixture in this plant replaces a file's whole contents and spelling
    that three times per case is three chances to assert against the wrong bytes."""
    p.write_text(new)


def plant() -> int:
    """EVERY ASSERTION IS A (name, got, want) AGAINST THE REAL FUNCTIONS, on a scratch tree seeded
    with REAL COPIES of both lanes, and the gate is asserted in BOTH directions -- a byte moves and
    the same gate flips PASS -> FAIL, so `PASS` is not a constant this file emits."""
    checks: list[tuple] = []
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp) / "tree"
        _seed(root)
        summary, manifest = root / SUMMARY, root / MANIFEST
        summary.parent.mkdir(parents=True)
        w = load(WRITER, root)
        member = root / MEMBER
        n = len(w.substrate_entries())
        good_summary = f"substrate-start={w.substrate_digest()}\nsubstrate-end={w.substrate_digest()}\n"
        stamped = lambda: manifest.read_text()  # noqa: E731 -- a thunk over the CURRENT bytes

        checks.append(("stamp writes one row per member of the WRITER's population",
                       stamp(root, manifest, w), n))
        checks.append(("plus a `substrate=` header carrying the WRITER's own digest",
                       stamped().splitlines()[0], f"{ROW}={w.substrate_digest()}"))
        checks.append(("plus a `members=` header, which is what catches a manifest that lost rows",
                       stamped().splitlines()[1], f"{COUNT}={n}"))
        rc, lines = diagnose(root, summary, manifest)
        checks.append(("no summary yet -> REFUSED, never a verdict about a run", rc, REFUSED))

        _rewrite(summary, good_summary)
        rc, lines = diagnose(root, summary, manifest)
        print(f"PLANT unmoved {token(rc)}: {lines[-1][:88]}")
        checks.append(("an unmoved tree is PASS, per-path, with 0 named", rc, PASS))
        checks.append(("and the PASS denominator is the WRITER's population, asked for, not listed",
                       f"0 of {n} recorded member(s)" in lines[-1], True))

        member.write_text(MOVED)
        rc, lines = diagnose(root, summary, manifest)
        print(f"PLANT moved   {token(rc)}: {lines[-2][:88]}")
        checks.append(("one byte in ONE member turns the same gate FAIL", rc, FAIL))
        named = [ln.strip() for ln in lines if ln.strip().startswith("MOVED")]
        checks.append(("and it NAMES that member, with the recorded and the live sha on one line",
                       (len(named), named[0].startswith(f"MOVED  {MEMBER}  recorded=")
                        if named else False, hashlib.sha256(MOVED.encode()).hexdigest()[:12]
                        in (named[0] if named else "")),
                       (1, True, True)))
        checks.append(("and the count is 1 of N: the common case is a 1-row diff either way",
                       [ln for ln in lines if "member(s) differ" in ln][0],
                       f"FAIL: 1 of {n} member(s) differ -- the population is the same and these "
                       "are the bytes that moved"))

        # THE SENSITIVITY CENSUS, HERE, WHILE THE TREE IS COHERENT -- the manifest matches the
        # summary and the tree is the tree. Run after either is broken it reads DEAD for every case
        # and reports every edit caught (`substrate-current.py:381-386`).
        _BASE.clear()
        for name in SCENARIOS:
            undo = _scenario(root, name)
            _BASE[name] = diagnose(root, summary, manifest)
            for u in undo:
                u()
        caught = _caught(root, summary, manifest)
        for (label, _, _, _, want), (_, seen, applied) in zip(MUTATIONS, caught):
            checks.append((f"plant sensitivity census -- {label} "
                           f"{'IS' if want else 'is NOT'} caught", (seen, applied), (want, True)))
        print(f"MUTATION {sum(1 for _, s, a in caught if s)} of {len(caught)} edits to the comparison "
              f"are caught by --plant; NOT APPLIED: "
              f"{', '.join(l for l, _, a in caught if not a) or 'none'}; not caught: "
              f"{', '.join(l for l, s, _ in caught if not s) or 'none'}")

        # THE SECOND ANSWER, WHICH IS NOT A SHADE OF THE FIRST: the population is not the same, so
        # no count of moved members is a true sentence and the tool must say so instead.
        (root / "tinybendygrad/c.bend").write_text("// new\n")
        rc, lines = diagnose(root, summary, manifest)
        checks.append(("an ADDED member is POPULATION-DRIFT, and is named TREE-ONLY",
                       (rc, [ln.strip() for ln in lines if "TREE-ONLY" in ln]),
                       (FAIL, ["TREE-ONLY       tinybendygrad/c.bend"])))
        checks.append(("and it says THE DIGEST IS OVER A DIFFERENT POPULATION, in words",
                       any("DIFFERENT POPULATION" in ln for ln in lines), True))
        # A DELETED member is the third case and not the second: the manifest carries a path the
        # tree does not, so the two disagree on MEMBERSHIP and not on bytes.
        (root / "tinybendygrad/c.bend").unlink()
        member.unlink()
        rc, lines = diagnose(root, summary, manifest)
        checks.append(("a DELETED member is POPULATION-DRIFT, and is named RECORDED-ONLY",
                       (rc, [ln.strip() for ln in lines if "RECORDED-ONLY" in ln]),
                       (FAIL, [f"RECORDED-ONLY  {MEMBER}"])))
        member.write_text(MEMBER_BYTES)

        _rewrite(manifest, stamped().replace(f"{ROW}=", f"{ROW}=x", 1))
        checks.append(("a manifest from ANOTHER run is REFUSED, not read",
                       diagnose(root, summary, manifest)[0], REFUSED))
        _rewrite(manifest, stamped().split("\n", 2)[2])
        checks.append(("a manifest with NO header row cannot be attributed to a run",
                       diagnose(root, summary, manifest)[0], REFUSED))
        stamp(root, manifest, w)
        _rewrite(manifest, "".join(ln + "\n" for ln in stamped().splitlines()[:-1]))
        rc, lines = diagnose(root, summary, manifest)
        checks.append(("a TRUNCATED manifest -- one row dropped -- is REFUSED, NOT POPULATION-DRIFT",
                       (rc, any("LOST ROWS" in ln for ln in lines)), (REFUSED, True)))
        checks.append(("and it NAMES NO path at all: calling it POPULATION-DRIFT would name the "
                       "lost path TREE-ONLY and claim the tree gained a file it never had, which "
                       "is the misdiagnosis `members=` exists to prevent",
                       [ln for ln in lines if ln.strip().startswith(("TREE-ONLY", "RECORDED-ONLY"))],
                       []))
        stamp(root, manifest, w)
        _rewrite(manifest, stamped().replace(f"{COUNT}={n}", f"{COUNT}={n + 1}", 1))
        checks.append(("and an over-declared count is refused too, so `members=` is not a spelling "
                       "of the row count", diagnose(root, summary, manifest)[0], REFUSED))
        stamp(root, manifest, w)
        _rewrite(manifest, stamped() + f"deadbeef\t{MEMBER}\n")
        checks.append(("a DUPLICATED relpath is REFUSED: a population that lists one member twice "
                       "has stopped being a set", diagnose(root, summary, manifest)[0], REFUSED))
        stamp(root, manifest, w)
        _rewrite(summary, "graphs=1\n")
        checks.append(("a summary with no substrate-end= is REFUSED",
                       diagnose(root, summary, manifest)[0], REFUSED))
        checks.append(("an absent summary is REFUSED",
                       diagnose(root, root / "nope.txt", manifest)[0], REFUSED))
        stamp(root, manifest, w)
        _rewrite(summary, good_summary)
        manifest.unlink()
        rc, lines = diagnose(root, summary, manifest)
        checks.append(("THE RESIDUAL, AS A VERDICT: no manifest is REFUSED", rc, REFUSED))
        checks.append(("and it states the count it cannot name members of: 0 of N",
                       f"0 of {n} members per-path" in lines[-1], True))
        noW = pathlib.Path(tmp) / "nowriter"
        _seed(noW)
        checks.append(("a tree with no writer at all is REFUSED, not an empty population",
                       diagnose(noW, noW / SUMMARY, noW / MANIFEST)[0], REFUSED))
        # `ABSENT` IS A MEMBER WITH NO BYTES, AND THE TOKEN IS THE WRITER's: delete a declared
        # input and the manifest must still carry the row, so re-creating the file reads as a MEMBER
        # MOVED rather than as a NEW member -- which would be the population-drift sentence about a
        # file that was always declared.
        gone = pathlib.Path(tmp) / "absent"
        _seed(gone)
        (gone / "checks/devpin.py").unlink()
        gw = load(WRITER, gone)
        stamp(gone, gone / MANIFEST, gw)
        checks.append(("a declared input that is NOT on disk is carried as the token ABSENT",
                       [ln for ln in (gone / MANIFEST).read_text().splitlines()
                        if ln == "ABSENT\tchecks/devpin.py"], ["ABSENT\tchecks/devpin.py"]))
        (gone / "checks/devpin.py").write_text("// restored\n")
        rc, lines = diagnose(gone, None, gone / MANIFEST)
        checks.append(("and RE-CREATING it reads as 1 member MOVED, not as a new member",
                       (rc, [ln.strip().split()[0] + " " + ln.strip().split()[1] for ln in lines
                             if ln.strip().startswith("MOVED")],
                        any("TREE-ONLY" in ln for ln in lines)),
                       (FAIL, ["MOVED checks/devpin.py"], False)))

        ok = True
        for name, got, want in checks:
            good, ok = got == want, ok and got == want
            print(f"  {'OK  ' if good else 'RED '} : want {want!r}, got {got!r}   [{name}]")
        print(f"PLANT: {'OK' if ok else 'RED'} -- {sum(1 for c in checks if c[1] == c[2])} of "
              f"{len(checks)} assertions")
        return PASS if ok else FAIL


def main() -> int:
    ap = argparse.ArgumentParser(description="name every substrate member that moved")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--write", nargs="?", const=MANIFEST, metavar="PATH")
    g.add_argument("--diff", nargs="?", const=MANIFEST, metavar="PATH")
    g.add_argument("--check", nargs="?", const=SUMMARY, metavar="SUMMARY")
    g.add_argument("--cost", action="store_true")
    g.add_argument("--plant", action="store_true")
    a = ap.parse_args()
    if a.plant:
        return plant()
    if a.cost:
        print(residual_noise(ROOT))
        return PASS
    if a.write:
        n = stamp(ROOT, pathlib.Path(a.write))
        print(f"wrote {a.write}: {n} member row(s) + 2 header rows, from {WRITER}'s own population")
        return PASS
    if a.check:
        rc, lines = diagnose(ROOT, pathlib.Path(a.check), ROOT / MANIFEST)
    elif a.diff:
        rc, lines = diagnose(ROOT, None, pathlib.Path(a.diff))
    else:
        ap.print_help()
        return 2
    print("\n".join(lines))
    print(f"VERDICT: {token(rc)}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
