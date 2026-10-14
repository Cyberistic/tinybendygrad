#!/usr/bin/env python3
"""PLANTS FOR `checks/slop-declare.py`. Each MUST BE ABLE TO MOVE.

A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES. Each plant below builds a PRIVATE `git init`
tree in a `tempfile`, so nothing here writes into the real `.agents/slop/` and no plant reads
the real tree's answer for its own verdict. The gate is loaded by path (`importlib`), the way
`.agents/slop/oracletxt/plant.py` loads `checks/oracle-txt-census.py`.

  PLANT 1  DECLARATION. A tracked directory with nothing that declares it MUST be named; the
           SAME directory plus a tracked `MANIFEST.tsv` MUST NOT be. `strays/MANIFEST.tsv` is the
           precedent that makes the second half the interesting one: a directory with no
           `REPORT.md` is auditable if it holds a manifest, and the walk has to know it.

  PLANT 2  THE ORCDECIDE TRAP. A directory WITH a `REPORT.md` whose only "reader" is a file that
           opens it BY BASENAME (`Path("evid") / "x.json"`) MUST NOT be credited with a reader.
           It must also still be called declared. Those are two different claims and both are
           true: a basename join would make `census.json` reachable from anywhere in the tree,
           so the walk would see liveness that does not exist, and reporting it as undeclared
           would be the false positive the brief names.

  PLANT 3  THE FALSE POSITIVE THAT IS REALLY IN THE TREE. A directory that declares itself and
           is named by nothing must be a ROW, not a defect. `citeresolve` and `coindependent`
           from the brief are exactly this shape: a unit's evidence with no reader is not
           residue, and a walk that flags it flags every unit that ever runs.

  PLANT 4  FRESHNESS. A directory committed inside the grace window and one committed outside it
           must land in DIFFERENT sets, with the inside one counted and never gated. This is the
           answer to "what does a NEW unit do in its first minute": it is counted, and it does
           not fail.

  PLANT 5  THE TWO NON-VERDICTS. A root with no `.agents/slop/` at all, and a root git cannot
           answer, must produce DIFFERENT NON-ZERO exits -- `DEAD` (5) and `REFUSED` (3), never
           `PASS`. `AGENTS.md`: a gate that exits 0 having measured nothing is worse than no
           gate, because it is trusted.

  PLANT 6  THE RESET CLOCK. Four directories with FOUR real mtimes must produce a real verdict;
           the same four stamped with ONE mtime -- the shape of a fresh `git clone`, where
           everything reads IN PROGRESS -- must REFUSE rather than pass. The first version of
           this guard tested the GATED subset, and MEASURED it had a hole: a reset clock makes
           every undeclared directory fresh, the gated set is empty, `if stale` never fires, and
           the walk answered PASS. The signature is in the WHOLE population, so that is the span.

usage: .venv/bin/python .agents/slop/declare/plant.py
"""
from __future__ import annotations

import contextlib
import datetime
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GATE = ROOT / "checks/slop-declare.py"
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": "/nonexistent",
       "GIT_AUTHOR_NAME": "plant", "GIT_AUTHOR_EMAIL": "plant@localhost",
       "GIT_COMMITTER_NAME": "plant", "GIT_COMMITTER_EMAIL": "plant@localhost"}


def excluded() -> frozenset[str]:
    """The prefix this unit's own files must not be able to cite, derived from `__file__`.

    This plant's fixture bytes ARE `.agents/slop/<dir>/` paths, so without this the walk would
    count the plant as a reader of every directory it names and would report a tree full of live
    directories that nothing opens. `checks/slop-declare.py:plant_exclusions()` loads THIS by
    path -- ONE declaration, loaded, not typed into the gate -- so move the plant and the
    exclusion moves with it.
    """
    return frozenset({f"{HERE.relative_to(ROOT)}/"})


def load():
    spec = importlib.util.spec_from_file_location("slop_declare", GATE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@contextlib.contextmanager
def unindexed():
    """The gate's `git()` INHERITS the environment, so an exported `GIT_INDEX_FILE` selects the
    population -- which is the point on the real tree and is a trap in a fixture: this tree's
    index path resolved against a `tempfile` repo answers an EMPTY index, and the walk then
    reports DEAD (0 directories) for a fixture that plainly holds some. MEASURED: that is what
    this context exists for, and PLANT 5a below would otherwise have been testing the wrong
    thing. Clearing it here is not a fix to the gate -- it is the caller naming which index it
    means, which is exactly the argument for the inheritance."""
    saved = os.environ.pop("GIT_INDEX_FILE", None)
    try:
        yield
    finally:
        if saved is not None:
            os.environ["GIT_INDEX_FILE"] = saved


def fixture(files: dict[str, str], *, when: str | None = None) -> pathlib.Path:
    """A private TRACKED tree, because the gate reads `git ls-files` and nothing else. `when`
    moves BOTH clocks -- the commit date and every file's mtime -- because the walk decides on
    the second and its cross-check column reads the first, and a plant that moved only one of
    them would be testing a coincidence."""
    root = pathlib.Path(tempfile.mkdtemp(prefix="slop-declare-plant-"))
    for rel, body in files.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(body)
    env = dict(ENV)
    if when:
        env.update(GIT_AUTHOR_DATE=when, GIT_COMMITTER_DATE=when)
    with unindexed():
        for argv in (["git", "init", "-q"], ["git", "add", "-A"], ["git", "commit", "-qm", "f"]):
            r = subprocess.run(argv, cwd=root, capture_output=True, text=True, env=env)
            assert r.returncode == 0, r.stderr
    if when:
        stamp = datetime.datetime.fromisoformat(when).timestamp()
        for rel in files:
            os.utime(root / rel, (stamp, stamp))
    return root


def walk(mod, root: pathlib.Path):
    """The gate's own survey over a fixture, on the fixture's OWN index. Returned as
    (row by dir, the three named sets)."""
    with unindexed():
        surveyed = mod.survey(root)
    assert "error" not in surveyed, surveyed
    return {r["dir"]: r for r in surveyed["rows"]}, mod.classify(surveyed)


def report(name: str, ok: bool, detail: str) -> bool:
    print(f"  {'PASS' if ok else 'FAIL'}  {name}\n        {detail}")
    return ok


def plant_declaration(mod):
    print("  plant_declaration")
    a, _ = walk(mod, fixture({".agents/slop/probe/x.rows": "a=1\n"}))
    b, _ = walk(mod, fixture({".agents/slop/probe/x.rows": "a=1\n",
                              ".agents/slop/probe/MANIFEST.tsv": "path\tverdict\n"}))
    return [
        report("PLANT 1a  an undeclared directory is named",
               a["probe"]["declared"] == "-" and a["probe"]["code_readers"] == 0,
               f"declared={a['probe']['declared']!r} code_readers={a['probe']['code_readers']}"),
        report("PLANT 1b  MANIFEST.tsv silences it",
               b["probe"]["declared"] == "MANIFEST.tsv", f"declared={b['probe']['declared']!r}"),
    ]


def plant_basename_reader(mod):
    print("  plant_basename_reader")
    tree = {".agents/slop/evid/REPORT.md": "# evid\n",
            ".agents/slop/evid/x.json": '{"n":1}\n',
            "tool.py": 'p = Path("evid") / "x.json"\n'}
    r, _ = walk(mod, fixture(tree))
    return [
        report("PLANT 2a  an open by BASENAME credits NO reader",
               r["evid"]["code_readers"] == 0,
               f"code_readers={r['evid']['code_readers']} for `Path('evid')/'x.json'`"),
        report("PLANT 2b  ...and the directory is still DECLARED, not a defect",
               r["evid"]["declared"] == "REPORT.md", f"declared={r['evid']['declared']!r}"),
    ]


def plant_declared_unread_is_not_a_defect(mod):
    print("  plant_declared_unread_is_not_a_defect")
    rows, sets = walk(mod, fixture({".agents/slop/evidence/REPORT.md": "# evidence\n",
                                    ".agents/slop/evidence/rows.rows": "n=1\n"}))
    gated = {x["dir"] for x in sets["unread_stale"] + sets["unread_fresh"]}
    named = [x["dir"] for x in sets["declared"]]
    return [
        report("PLANT 3a  declared + unread -> 0 code readers",
               rows["evidence"]["code_readers"] == 0,
               f"code_readers={rows['evidence']['code_readers']}"),
        report("PLANT 3b  it is in `declared`, and in NEITHER gated set",
               "evidence" in named and not gated,
               f"declared={named} unread_stale={sorted(gated)}"),
    ]


def plant_freshness(mod):
    print("  plant_freshness")
    old, _ = walk(mod, fixture({".agents/slop/stale/x.rows": "a=1\n"}, when="2000-01-01T00:00:00"))
    _, sets = walk(mod, fixture({".agents/slop/fresh/x.rows": "a=1\n"}))
    fresh = {x["dir"] for x in sets["unread_fresh"]}
    stale = {x["dir"] for x in sets["unread_stale"]}
    return [
        report("PLANT 4a  a 2000 stamp is STALE",
               old["stale"]["fresh"] is False and old["stale"]["age_h"] > 100000,
               f"age_h={old['stale']['age_h']} commit_age_h={old['stale']['commit_age_h']}"),
        report("PLANT 4b  a stamp from now is IN PROGRESS, counted, and not gated",
               fresh == {"fresh"} and stale == set(),
               f"unread_fresh={sorted(fresh)} unread_stale={sorted(stale)}"),
    ]


def plant_reset_clock(mod):
    """THE FRESH-CLONE SHAPE, AND THE GUARD ON THE RULER. A checkout stamps every file with one
    instant, so every undeclared directory reads IN PROGRESS and the gate would pass because the
    clock says so. A population whose mtimes span less than `MIN_SPREAD_MIN` is a population
    measured by a reset clock, and the walk must REFUSE rather than report it as progress."""
    print("  plant_reset_clock")
    now = time.time()
    tree = {f".agents/slop/d{i}/x.rows": "a=1\n" for i in range(4)}
    root = fixture(tree)
    for i, rel in enumerate(tree):
        os.utime(root / rel, (now - (90000 - i * 30000),) * 2)   # 25 h .. 6 h: FOUR REAL ages
    with unindexed():
        rc = mod.verdict(mod.survey(root))
    for rel in tree:
        os.utime(root / rel, (now, now))                          # the checkout: ONE stamp for all
    with unindexed():
        reset = mod.verdict(mod.survey(root))
    return [
        report("PLANT 6a  four mtimes 25 h..6 h old -> a real verdict, not a refusal",
               rc == 1, f"exit={rc} (FAIL: stale undeclared-and-unread, nothing in the baseline)"),
        report("PLANT 6b  ONE mtime for the whole tree -> REFUSED (3), not PASS",
               reset == 3, f"exit={reset} (a reset ruler must not read as progress)"),
    ]


def plant_non_verdicts(mod):
    print("  plant_non_verdicts")
    with unindexed():
        empty = mod.verdict(mod.survey(fixture({"checks/thing.py": "x = 1\n"})))
        nogit = mod.verdict(mod.survey(pathlib.Path(tempfile.mkdtemp(prefix="slop-declare-nogit-"))))
    return [
        report("PLANT 5a  no `.agents/slop/` -> DEAD (5), not PASS", empty == 5, f"exit={empty}"),
        report("PLANT 5b  a root git refuses -> REFUSED (3), not PASS", nogit == 3, f"exit={nogit}"),
    ]


def main() -> int:
    mod = load()
    print("plants for checks/slop-declare.py")
    results: list[bool] = []
    for plant in (plant_declaration, plant_basename_reader, plant_declared_unread_is_not_a_defect,
                  plant_freshness, plant_reset_clock, plant_non_verdicts):
        results += plant(mod)
    bad = results.count(False)
    print(f"--plant: {'all plants pass' if not bad else f'{bad} FAILED'}   ({len(results)} assertions)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())