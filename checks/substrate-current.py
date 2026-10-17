#!/usr/bin/env python3
"""IS `runs/graphcmp/D/` STILL A MEASUREMENT OF THIS TREE? -- the currency question, asked in the
WRITER'S OWN ENCODING.

    usage: .venv/bin/python checks/substrate-current.py [--check [SUMMARY] | --report | --plant]
                                          # default SUMMARY is runs/graphcmp/D/D0-run-summary.txt

EXIT: 0 PASS · 1 FAIL · 3 REFUSED · 5 DEAD (gatekit's five, `gates/gatekit.py:59`).

WHY THIS FILE IS NOT A SECOND `substrate-id.py`. Two instruments hashed "the substrate" for one
tree and named each other nowhere: `differ.substrate_digest()` = `be6874ca…` and
`substrate-id.py --rows` = `86ce8d93…`, and `D0-run-summary.txt` rows 23-24 carry the FORMER.
MEASURED here, on one tree, at one instant: the two populations differ by exactly 2 paths
(`.agents/slop/graphcmp-dbg.bend`, `.agents/slop/graphcmp-empty.bend`), they are ORDERED by
different keys, and they are AGGREGATED differently (`differ.py:905-911` folds a per-file sha256
hex string; `substrate-id.py:179-192` folds the raw bytes). Three independent deltas, so the fix
is not a hash and not a pin.

THE COMPARISON IS THE WRITER'S. A run's recorded row is only comparable to a live reading taken
with the SAME function that wrote it, so this file asks `differ.substrate_digest()` for the live
value and never re-types it. MEASURED, and this is the defect being closed: `substrate-id.py
--judge` compares a `differ`-encoded row against a `substrate-id`-encoded reading of the same
bytes, so it answers `REFUSED` on a tree that has not moved a byte and CANNOT EVER answer PASS.
It CANNOT because there are **2 emitters of these two row keys** (`census()`): `differ.py:718`
writes them into the summary, and `substrate-id.py`'s `rows()` writes the same keys to stdout --
which is where `86ce8d93` came from -- and only the first is ever recorded. `--plant` step 3
demonstrates the refusal on a scratch tree with nothing moved, and step 2 shows this file
answering PASS on it.

WHY `FAIL` AND NOT `REFUSED` FOR A MOVED SUBSTRATE. `REFUSED` is a precondition that was absent
(doctrine 2). Here every precondition is present -- summary, both rows, a non-empty population --
and the gate's own question has a decidable answer, which is NO. The tree has already ruled the
other way: `differ.py:1043` folds the same two rows into `unhealthy()` as a FAIL, and
`gates/retention-check.py` clause IV consumes that, so a REFUSED here would contradict the reader
of the same rows.

WHAT IT STILL CANNOT SEE, AS COUNTS, ON EVERY VERDICT (`residual()`). A FAIL says the tree moved
and not WHICH file moved: the run records two 64-hex rows and no per-path sha, so on a tree of
N members the diagnosis is 1 bit and the population is N. That is the same shape
`checks/runs-artifacts.py:825` reports, and it is why the line is printed rather than implied.
"""
from __future__ import annotations

import argparse
import importlib.util
import pathlib
import shutil
import sys
import tempfile
import types

ROOT = pathlib.Path(__file__).resolve().parents[1]
SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"

#: THE PRODUCERS, BY THE ROLE THEY PLAY IN THE RECORD, not by the order they were written down.
#: `WRITER` is the only lane that writes the two rows INTO the summary (`differ.py:718`; `census()`
#: confirms it by content), so its function is the only one a recorded row is comparable to.
#: `READER` carries the row parser and the DECLARED population, and is asked for both.
WRITER, READER = "checks/differ.py", "checks/substrate-id.py"
#: THIS FILE, as a path, because `census()` has to be asserted against a tree that CONTAINS it or
#: the assertion is about a tree it was never run on.
SELF = "checks/substrate-current.py"
PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5
LANES = ("checks", "gates")
ROW_KEYS = ("substrate-start", "substrate-end")
#: HOW A LANE EMITS A ROW LINE, MARKED TWO WAYS BECAUSE THE TWO EMITTERS SPELL IT TWO WAYS:
#: `differ`'s emitter builds from `SUBSTRATE_ROWS`, `substrate-id`'s from `ROW_START`.
#: A matcher for either one alone reports a single emitter where there are two, and the one it
#: misses is the whole finding. NOTE THE PROSE HERE SAYS NEITHER MARKER WHOLE: `census()`
#: matches this file's text, so a docstring that named either one would make this file a third
#: emitter. It did, once, and `--plant` is what caught it.
#:
#: BOTH ARE ASSEMBLED, NOT WRITTEN WHOLE, and that is not a trick: a literal written whole here
#: appears in this file's own text, so `census()` counts this file as a third emitter -- measured
#: twice, once per marker, each time with the marker spelled whole and each time reporting a
#: writer that only ever reads. `--plant` asserts the census over a scratch tree, so the class is
#: caught by the gate rather than by whoever edits this next.
WRITE_MARK = "substrate_rows" + "("
EMIT_MARK = "ROW_START" + "}"


def _load(rel: str, root: pathlib.Path):
    """A LANE LOADED BY PATH, OUT OF THE ROOT BEING MEASURED (`substrate-id.py:133-148`). `None`
    is not an exception: a tree without a lane is a measurement of a tree without a lane, and the
    caller has a verdict for that."""
    p = root / rel
    if not p.is_file():
        return None
    spec = importlib.util.spec_from_file_location(rel.replace("/", "_").replace("-", "_"), p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fact(root: pathlib.Path) -> dict:
    """THE MEASURED DIFFERENCE BETWEEN THE TWO IDS. Every field is OBTAINED BY CALLING one of the
    two producers; nothing here is a second copy of either algorithm, and nothing here is a hand
    list of what either one hashes.

    `over_writer` IS THE FIELD THAT KILLS THE "MAKE THE IDS MATCH" FIX. It is the READER's
    algorithm over the WRITER's population -- one population, one encoding difference left -- so
    when it differs from `writer`, the disagreement is the aggregation and the ordering and not the
    membership. Both ids would still be correct about their own tree."""
    w, r = _load(WRITER, root), _load(READER, root)
    if w is None:
        return {}
    entries = w.substrate_entries()
    # SORTED, BECAUSE THE WRITER SORTS. `substrate_entries()` returns the walk in `rglob` order and
    # then appends the hand-list, and only `substrate_digest()` calls `sorted()` on it. Taking this
    # list as it comes made two fields wrong at once: the order comparison compared an order the
    # writer never hashes in, and `over_writer` was folded in a sequence the writer never folds, so
    # "the aggregation is a cause on its own" was an artefact of this file's own input order.
    w_rel = sorted(rel for rel, _ in entries)
    readable = sum(1 for rel in w_rel if (root / rel).is_file())
    r_rel = [p.relative_to(root).as_posix() for p in (r.population(root) if r else [])]
    f = {"writer": w, "reader": r, "w_rel": w_rel, "r_rel": r_rel,
         "writer_id": w.substrate_digest(), "readable": readable,
         "only_writer": sorted(set(w_rel) - set(r_rel)),
         "only_reader": sorted(set(r_rel) - set(w_rel)),
         "reader_id": r.digest(root)["digest"] if r else None,
         "over_writer": r.digest(root, members=[root / rel for rel in w_rel])["digest"] if r else None}
    # Order is compared over the INTERSECTION, not over a set, because a membership delta says
    # nothing about order and `None` here would hide the third cause behind the first one.
    common = set(w_rel) & set(r_rel)
    f["same_order"] = [x for x in w_rel if x in common] == [x for x in r_rel if x in common]
    return f


#: ROLE -> what the role MEANS, kept apart from the role so `census()` can return data and
#: `--plant` can assert on it. A census that returns formatted prose can only be asserted by
#: re-parsing the prose, which is how the plant's first version of this assertion was wrong.
ROLES = {"reads": "reads the two rows",
         "EMITS-RECORDED": "EMITS them into the summary, in differ's encoding -- the one D/ is in",
         "EMITS-OWN": "EMITS ITS OWN ENCODING to stdout -- nothing records these"}


def census(root: pathlib.Path) -> list[tuple[str, str]]:
    """WHO CAN WRITE THESE TWO ROWS, DISCOVERED BY A WALK over the instrument homes, so "which id
    does the run's own record use" is a COUNT here rather than a claim.

    MEASURED, and the count is **2 emitters**, which is the finding and not a footnote: `differ`'s
    `substrate_rows` writes them in `differ`'s encoding into the summary, and `substrate-id`'s
    `rows()` writes the SAME TWO KEYS to stdout in `substrate-id`'s encoding. The second is where
    `86ce8d93` came from, and it is emitted by a lane nothing reads, so the two ids look
    interchangeable and are not. Only the first calls `substrate_digest()`, so only the first is
    what `runs/graphcmp/D/D0-run-summary.txt` is in -- and that is decided here by CONTENT, not by
    a hand list of which lane that is."""
    out = []
    for home in LANES:
        for p in sorted((root / home).glob("*.py")):
            text = p.read_text(errors="replace")
            if not any(k in text for k in ROW_KEYS):
                continue
            if WRITE_MARK not in text and EMIT_MARK not in text:
                role = "reads"
            elif "substrate_digest()" in text:
                role = "EMITS-RECORDED"
            else:
                role = "EMITS-OWN"
            out.append((role, p.relative_to(root).as_posix()))
    return out


def residual(f: dict, rows: int) -> str:
    """WHAT IS STILL INVISIBLE, AS COUNTS, so the admission is falsifiable rather than a mood.

    `1 of 2` is the DEAD-branch census and it is honest: the plant exercises the EMPTY SUMMARY
    branch and cannot exercise the EMPTY-POPULATION one, because the population includes
    `checks/differ.py` itself and a tree that deleted it could not load the function that asks.
    `0 of N` is the per-path one: the run recorded `rows` `key=value` rows and not one of them
    names a path, so a FAIL can say THAT the tree moved and never WHICH file."""
    return (f"1 of 2 DEAD branches are exercised by --plant (an empty population is unreachable "
            f"from a tree whose population includes the function that reads it); "
            f"0 of {len(f.get('w_rel') or [])} members are recorded per-path ({rows} key=value rows, "
            f"2 of them 64-hex), so a FAIL says THAT the tree moved and not WHICH file")


def verdict(summary: pathlib.Path, root: pathlib.Path, f: dict | None = None) -> tuple[int, str]:
    """FOUR QUESTIONS IN THE ORDER THEY CAN BE ANSWERED, each with its own verdict, and none of
    them reachable by re-deriving the writer's digest locally."""
    f = fact(root) if f is None else f
    if not f:
        return REFUSED, (f"{WRITER} is ABSENT from this tree, so the id that wrote the recorded "
                         "rows cannot be recomputed and currency is not a question this tree can "
                         "ask")
    if not f["readable"]:
        return DEAD, (f"the writer's population holds no readable member ({len(f['w_rel'])} "
                      f"declared, 0 bytes), so the digest compares nothing and comparing nothing is "
                      "agreement only by accident")
    if not summary.exists():
        return REFUSED, f"{summary} is absent -- there is no run to be a measurement of anything"
    text = summary.read_text(errors="replace")
    if not any("=" in ln for ln in text.splitlines()):
        return DEAD, f"{summary.name} holds no key=value row -- it ran and emitted nothing checkable"
    got = f["reader"].declared_values(text)
    start, end = got.get("substrate-start"), got.get("substrate-end")
    for key, val in (("substrate-start", start), ("substrate-end", end)):
        if val is None:
            return REFUSED, (f"the summary records no {key}= -- a run that does not say which bytes "
                             "produced it is a measurement with no subject. Re-run "
                             "`checks/differ.py run`")
    if start != end:
        return FAIL, (f"substrate-start={start[:12]} but substrate-end={end[:12]} -- THE SUBSTRATE "
                      "MOVED DURING THE RUN, so no artifact set in D/ describes one thing")
    if end != f["writer_id"]:
        return FAIL, (f"substrate-end={end[:12]} but this tree reads {f['writer_id'][:12]} through "
                      f"the same function ({WRITER}) -- THE TREE MOVED SINCE THE RUN, so the pins in "
                      f"D/ are claims about bytes that are not here. Re-run, or snapshot with "
                      "checks/substrate-snapshot.py")
    return PASS, (f"this tree IS the substrate the run was taken on -- {f['readable']} members, "
                  f"{end[:12]}, recomputed through {WRITER}")


def note(f: dict) -> str:
    """THE THREE DELTAS, ON EVERY VERDICT, because a currency gate that prints PASS while two
    producers disagree about the word 'substrate' is the same defect one level down. Measured by
    calling both, never asserted."""
    if not f or f["writer_id"] is None:
        return ""
    order = ("the same order" if f["same_order"] else "DIFFERENT -- the writer sorts (relpath, sha) "
             "tuples by STRING and the reader sorts pathlib.Path OBJECTS, which compare "
             "component-wise, so the two disagree wherever a directory and a file share a prefix")
    aggregation = ("EQUAL, so the memberships are the whole difference"
                   if f["over_writer"] == f["writer_id"] else
                   "DIFFERENT, so the aggregation and the ordering differ too")
    return (f"\n  writer {WRITER:<24} {f['writer_id'][:12]}  {len(f['w_rel'])} members\n"
            f"  reader {READER:<24} {f['reader_id'][:12]}  {len(f['r_rel'])} members\n"
            f"  reader's algorithm over the writer's population: {f['over_writer'][:12]}"
            f"  <- {aggregation}\n"
            f"  only in the writer: {f['only_writer'] or 'none'}\n"
            f"  only in the reader: {f['only_reader'] or 'none'}\n"
            f"  order: {order}\n")


# --------------------------------------------------------------------------- the plant
#: The stub members of a scratch tree, so the planted population has the real SHAPE -- a port
#: walk, a `bin/` directory the writer names one file of, and the `.agents/slop/graphcmp*` lanes
#: the reader declares two of more than the writer names.
STUBS = ("bin/bend", ".agents/slop/graphcmp.py", ".agents/slop/graphcmp.bend",
         ".agents/slop/graphcmp-dbg.bend", ".agents/slop/graphcmp-empty.bend",
         ".agents/slop/graphcmp-oracle.py", ".agents/slop/graphcmp-dbg-oracle.py",
         ".agents/slop/graphcmp-p13-ops.py", "tinybendygrad/a.bend", "tinybendygrad/b.bend",
         "tinybendygrad/LAWS.bend", "tinybendygrad/LAWS/spec.bend")
#: `LAWS.bend` BESIDE `LAWS/` IS THE ORDER PLANT, and it is not decoration: the writer sorts its
#: `(relpath, sha)` tuples by STRING and the reader sorts `pathlib.Path` OBJECTS, which compare
#: component-wise, so `'LAWS.bend' < 'LAWS/'` for one of them and `'LAWS/' < 'LAWS.bend'` for the
#: other. It is the third cause, and it is invisible to a set comparison -- a population delta
#: reports it as nothing at all.


def _stub(rel: str) -> str:
    """WHAT A PLANTED MEMBER CONTAINS. One function, because the plant MOVES a member by rewriting
    it and then UNDOES that by rewriting it again, and the first version of this harness spelled
    the undo by hand -- `"tinybendygrad/b.bend\\n"` against a seed that wrote `f"// {rel}\\n"`. The
    undo was not an undo, so the tree was still moved, and the sensitivity census reported all 3
    edits caught on a tree that was never restored. Two spellings of one fact, one of them wrong.
    """
    return f"// {rel}\n"


def _seed(root: pathlib.Path) -> None:
    """A scratch tree with the SHAPE of the real one: the lanes copied for REAL, so the planted
    verdicts are the real functions' and not a paraphrase, and stubs everywhere else. The copies
    are what make `ROOT` the scratch tree -- each lane reads its own `__file__` -- so no step of
    the plant can measure the tree the plant was launched from."""
    for rel in (WRITER, READER, "checks/devpin.py", "checks/substrate-snapshot.py", SELF):
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, root / rel)
    for rel in STUBS:
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(_stub(rel))


#: THE THREE EDITS THAT BREAK THE COMPARISON THIS FILE EXISTS TO MAKE, as
#: `(label, old, new, caught)` over its OWN source. They are what "the plant can fail" has to
#: mean: a plant that only ever feeds it different DATA has not shown that it reads the
#: comparison, and a comparison that could be deleted without the plant noticing would be a
#: comment. Each is evaluated against the SAME two verdicts -- PASS on the unmoved scratch tree and
#: FAIL on the moved one -- so an edit is CAUGHT only if it changes one of them.
#:
#: THE MARKERS ARE ASSEMBLED, NOT WRITTEN WHOLE, BECAUSE `_patched()` REQUIRES A MARKER TO OCCUR
#: EXACTLY ONCE. Spelling them inline put a second copy inside this table, so every patch landed on
#: the table instead of on `verdict()` and the census reported 0 of 3 caught for the wrong reason.
#: A patch tool that cannot tell its own marker from its marker's name is a patch tool that
#: silently patches the wrong thing.
_CMP = 'if end != f["writer_id"' + "]:"
_EMPTY = 'if not f["readable"' + "]:"
MUTATIONS = (
    ("invert the currency comparison", _CMP, _CMP.replace("!=", "=="), True),
    ("compare the recorded row against the reader's id", _CMP,
     'if end != f["reader_id"' + "]:", True),
    ("delete the empty-population DEAD branch", _EMPTY, "if False" + ":", False),
)
#: `caught=False` ON THE THIRD IS THE POINT, NOT A LAX EXPECTATION. Deleting the empty-population
#: DEAD branch cannot be caught, because that branch is unreachable from any tree this gate can
#: load: the writer's own population CONTAINS `checks/differ.py`, so a tree whose declared
#: population is all-absent is a tree that cannot hand the gate the function that reads it. The
#: census states the hole instead of covering it, and if somebody makes the branch reachable the
#: plant goes RED and asks them to move the expectation -- which is the only direction a
#: falsifiable record should ever move.
#: The byte a planted member moves BY. One token, so "one byte" in a report means one byte, and
#: the member it moves, named once because the plant moves it and the sensitivity census un-moves
#: it, and two spellings of one path is how the census came to read a MOVED tree as an unmoved one.
MOVED, MEMBER = "// moved\n", "tinybendygrad/b.bend"


def _patched(label: str, old: str, new: str):
    """THIS FILE WITH ONE EDIT, EXECUTED. `__file__` is pinned to the real path so the patched
    module's `ROOT` is the real tree and the two modules agree about what they are looking at."""
    src = (ROOT / SELF).read_text()
    mod = types.ModuleType(f"substrate_current_mutant_{abs(hash(label)) % 9973}")
    mod.__file__ = str(ROOT / SELF)
    if src.count(old) != 1:
        return None  # a marker that is not UNIQUE patches something other than what it names
    exec(compile(src.replace(old, new, 1), mod.__file__, "exec"), mod.__dict__)
    return mod


def _caught(root: pathlib.Path, summary: pathlib.Path, member: pathlib.Path, base: tuple) -> list:
    """WHICH EDITS THE PLANT WOULD NOTICE, measured by re-running `verdict()` from the patched
    module with one planted member moved and then undone. **BOTH READINGS COME FROM THE PATCHED
    MODULE** -- the first version took the unmoved tree's reading from the unpatched `verdict()`,
    and that asymmetry reported all 3 edits caught, a catch invented by the harness."""
    out = []
    for label, old, new, _want in MUTATIONS:
        mod = _patched(label, old, new)
        if mod is None:
            out.append((label, False))
            continue
        member.write_text(MOVED)
        after = mod.verdict(summary, root)[0]
        member.write_text(_stub(MEMBER))  # the SEED bytes, never read back off a moved tree
        out.append((label, (mod.verdict(summary, root)[0], after) != base))
    return out


def plant() -> int:
    """EVERY ASSERTION IS A (name, got, want) AGAINST THE REAL FUNCTIONS, and the gate is asserted
    in BOTH directions on one tree -- a byte moves and the same gate flips PASS -> FAIL, so `PASS`
    is not a constant this file emits."""
    checks: list[tuple] = []
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp) / "tree"
        _seed(root)
        summary = root / "runs/graphcmp/D/D0-run-summary.txt"
        member = root / MEMBER
        summary.parent.mkdir(parents=True)
        w, r = _load(WRITER, root), _load(READER, root)
        live = w.substrate_digest()
        summary.write_text(f"graphs=1\ndev=CPU\nsubstrate-start={live}\nsubstrate-end={live}\n")

        rc_unmoved, why = verdict(summary, root)
        print(f"PLANT unmoved    {rc_unmoved}: {why[:88]}")
        checks.append(("an unmoved tree is PASS -- compared in the WRITER's own encoding", rc_unmoved, PASS))
        checks.append(("and PASS names the live digest, not a local re-hash", live[:12] in why, True))

        rc_old = r.judge(summary, root)  # the reader PRINTS its own reason; capture the code only
        print(f"PLANT old-reader {rc_old}: one writer, two encodings, nothing moved")
        checks.append(("the OLD reader REFUSES that same unmoved tree: one writer, two encodings",
                       rc_old, REFUSED))

        f = fact(root)
        checks.append(("the planted reader names the 2 declared members the writer's hand-list "
                       "omits", f["only_reader"],
                       [".agents/slop/graphcmp-dbg.bend", ".agents/slop/graphcmp-empty.bend"]))
        checks.append(("and the delta is ONE-DIRECTIONAL: nothing the writer names is unnamed",
                       f["only_writer"], []))
        checks.append(("over ONE population the two encodings still give two ids -- so the "
                       "aggregation is a cause on its own", f["over_writer"] != f["writer_id"], True))
        checks.append(("and the two producers disagree on ORDER too, over the same members: "
                       "`LAWS.bend` beside `LAWS/` sorts both ways", f["same_order"], False))

        member.write_text(MOVED)
        rc, why = verdict(summary, root)
        moved_live = w.substrate_digest()  # taken HERE, while moved, so the next case does not
        print(f"PLANT moved      {rc}: {why[:88]}")  # depend on where the census left the tree
        checks.append(("one byte in ONE of the members turns the same gate FAIL", rc, FAIL))
        checks.append(("and the FAIL names the writer, because that is what it asked",
                       WRITER in why, True))

        # HERE, WHILE THE TREE IS COHERENT. Run at the end of this function -- after the summary has
        # been overwritten twice and the declarer deleted -- the census reads a summary with no
        # rows, gets DEAD for every reading, and calls all three edits caught. A sensitivity census
        # that reports 3 of 3 because its fixture was broken is the exact instrument it exists to
        # distrust, so it runs where the two readings it compares are the two it means.
        caught = _caught(root, summary, member, (rc_unmoved, rc))
        for (label, _, _, want), (_, seen) in zip(MUTATIONS, caught):
            checks.append((f"plant sensitivity census -- {label} "
                           f"{'IS' if want else 'is NOT'} caught", seen, want))
        print(f"MUTATION {sum(1 for _, s in caught if s)} of {len(caught)} edits to the comparison "
              f"are caught by --plant; NOT caught: "
              f"{', '.join(l for l, s in caught if not s) or 'none'}")

        summary.write_text(f"substrate-start={live}\nsubstrate-end={moved_live}\n")
        checks.append(("rows that disagree with EACH OTHER are FAIL: a mixture, not a stale run",
                       verdict(summary, root)[0], FAIL))
        summary.write_text("substrate-start=deadbeef\n")
        checks.append(("one row present and one absent is REFUSED", verdict(summary, root)[0], REFUSED))
        summary.write_text("no rows here\n")
        checks.append(("a summary with no key=value row is DEAD, not REFUSED",
                       verdict(summary, root)[0], DEAD))
        checks.append(("an absent summary is REFUSED", verdict(root / "nope.txt", root)[0], REFUSED))

        (root / "checks/substrate-snapshot.py").unlink()
        f2 = fact(root)
        checks.append(("declarer gone -> the reader has 0 declared members, the live defect "
                       "substrate-id.py:50-55 documents", len(f2["r_rel"]), 0))
        checks.append(("and this gate still answers, because it asks the WRITER: an empty reader is "
                       "not an empty writer", f2["readable"] > 0, True))

        checks.append(("the census finds 2 emitters with THIS FILE PRESENT in the tree it walks, and "
                       "counts it as neither", census(root),
                       [("EMITS-RECORDED", WRITER), ("reads", SELF), ("EMITS-OWN", READER)]))

        ok = True
        for name, got, want in checks:
            good, ok = got == want, ok and got == want
            print(f"  {'OK  ' if good else 'RED '} : want {want!r}, got {got!r}   [{name}]")
        print(f"PLANT: {'OK' if ok else 'RED'} -- {sum(1 for c in checks if c[1] == c[2])} of "
              f"{len(checks)} assertions")
        return PASS if ok else FAIL


def show(f: dict, rc: int, why: str) -> int:
    """ONE SURFACE, and the three lines every verdict carries: what it decided, what the two ids
    are, and what it still cannot see."""
    print(f"VERDICT: {f['reader'].token(rc)}: {why}")
    print(note(f), end="")
    print(f"RESIDUAL: {residual(f, _rows(f))}\n")
    return rc


def _rows(f: dict) -> int:
    """`key=value` rows in the LIVE summary -- the denominator for `residual()`'s "records no
    path" claim. Read through the reader's own parser, not a second tokenizer."""
    return len(f["reader"].declared_values(SUMMARY.read_text(errors="replace"))) if SUMMARY.exists() else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Is the artifact set still a measurement of this tree?")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--check", nargs="?", const=SUMMARY, metavar="SUMMARY")
    g.add_argument("--report", action="store_true")
    g.add_argument("--plant", action="store_true")
    a = ap.parse_args()
    if a.plant:
        return plant()
    if a.report:
        f = fact(ROOT)
        if not f:
            print(f"REFUSED: {WRITER} is absent from {ROOT}")
            return REFUSED
        print("\nlanes naming the two rows, by walk of " + " + ".join(LANES) + ":")
        for role, rel in census(ROOT):
            print(f"    {ROLES[role]:<78} {rel}")
        return show(f, *verdict(SUMMARY, ROOT, f))
    f = fact(ROOT)
    return show(f, *verdict(pathlib.Path(a.check) if a.check else SUMMARY, ROOT, f))


if __name__ == "__main__":
    sys.exit(main())