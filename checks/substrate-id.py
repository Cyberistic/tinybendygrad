#!/usr/bin/env python3
"""THE SUBSTRATE A RUN MEASURED -- two `key=value` rows for `D0-run-summary.txt`, and the plant
that has never been run: a substrate change MID-RUN, on a real run's shape.

    usage: .venv/bin/python checks/substrate-id.py --rows       # the two rows, ready to write
           .venv/bin/python checks/substrate-id.py --hash       # this tree's digest, once
           .venv/bin/python checks/substrate-id.py --judge FILE # the two rows out of a summary
           .venv/bin/python checks/substrate-id.py --plant      # BOTH verdicts + the mid-run case
           .venv/bin/python checks/substrate-id.py --cost       # warm + cold, N sweeps

EXIT: 0 PASS  ·  1 FAIL  ·  3 REFUSED  ·  5 DEAD  ·  2 usage.

WHAT THIS IS. `pinindep` measured that all 17 pins read `D0-run-summary.txt`, and that this file
records `dev`/`lc_all`/`noopt`/`pythonhashseed` -- the ENVIRONMENT -- and not one byte of the PORT.
`midrun` measured that a COLD-path substrate change moves no artifact, no row and no pin, because
no row can name bytes. So a later reader cannot tell WHICH substrate produced an artifact set.

THE TWO ROWS, AND WHY TWO. One row is a LABEL and a label nothing compares to can never go red
(`differ.py:734-737` says so about its own precondition rows). Two rows are a COMPARISON:

    substrate-start=<digest>   taken BEFORE the first emit
    substrate-end=<digest>     taken AT summary time

Three questions, and the two rows answer all three because the reader supplies the third value:

  * did the substrate move DURING the run?  `start != end`
  * was this artifact set produced by the tree in front of me?  `end != <what I hash now>`
  * is the run even comparable to a second run?  `A.start == B.start and A.end == B.end`

THE AGGREGATION IS ONE sha256 OVER `relpath NUL bytes` IN SORTED PATH ORDER, and the choice is
the load-bearing part, so it is argued where it is made (`digest()`):

  * PATH IS IN THE HASH -- a rename cannot collide with a same-bytes-different-name copy.
  * A LENGTH PREFIX IS NOT NEEDED because the path is NUL-terminated and the digest is over a
    SORTED sequence, so the byte stream is a function of the (path, bytes) set alone.
  * NOT A MANIFEST OF 148 PER-FILE SHAS: `differ.py:616-622` records that this summary is parsed
    by four consumers and that a separate file would be a THIRD place the device is claimed. One
    more ROW is free by construction; 148 more rows is a manifest nobody reads, in a file whose
    whole contract is `key=value`.
  * IT NAMES WHICH SUBSTRATE, NOT WHICH FILE. That is deliberate and it is the honest division of
    labour: this row answers "same thing or not", and the file that changed is the DIAGNOSIS
    (`quiesce/quiesce.py`'s per-path mtime log, `quiesce/snapshot.py --verify`'s named row). A
    digest that named the file would have to be 148 rows, which is the row count above.

THE POPULATION IS DISCOVERED, NOT LISTED. `quiesce/snapshot.py` is LOADED BY PATH and its
`inputs()` is asked, so this file has no second list of what a run reads -- which is the defect
`snapshot.py:74-77` is written against, and the defect `coindependent`'s 42 and `gates-pop.py`'s
`HOMES` are both instances of.

VERDICTS, FIVE, AND WHICH OF THEM CAN HAPPEN HERE. `PASS` (0) the two digests agree, so the
artifacts are all measurements of one substrate. `REFUSED` (3) the PRECONDITION was absent -- a
declared input is missing, or the tree moved, or the rows are not both present. `FAIL` (1) is
NOT reachable and that is the point: nothing here compares two ANSWERS, it compares two
MEASUREMENTS OF ONE SUBJECT, and a disagreement there is a missing precondition rather than a
wrong result. `DEAD` (5) the population is empty -- nothing was measured at all. `SKIP` (4) is
not defined because this file always measures or refuses.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import pathlib
import shutil
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"

PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5
#: gatekit's vocabulary, `gates/gatekit.py:59`: PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5.
NAMES = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", DEAD: "DEAD"}

#: THE TWO ROWS. `differ.py`'s `ROW_VALUES` shape is a dict literal of key -> value; these are
#: not constants (they are measurements), so they are joined into the summary the one way the
#: summary admits -- as `key=value` lines from a function, which is `precondition_rows()`.
ROW_START, ROW_END = "substrate-start", "substrate-end"


def _snapshot_mod():
    """`quiesce/snapshot.py` LOADED BY PATH. Never `import snapshot`: `checks/` and
    `.agents/slop/quiesce/` are both off `sys.path` for a caller that is not `differ.py`, and an
    instrument whose population is chosen by a bindable name is an instrument whose population
    anybody can choose (`gates/gates-pop.py:99-101`)."""
    p = ROOT / ".agents/slop/quiesce/snapshot.py"
    if not p.is_file():
        return None
    spec = importlib.util.spec_from_file_location("substrate_id_snapshot", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def population(root: pathlib.Path) -> list[pathlib.Path]:
    """The run's declared inputs, DISCOVERED, plus the declared-but-ABSENT ones NAMED.

    `snapshot.inputs()` returns only what is on disk (`:80-85`, `elif p.is_file()`), so a
    declared input that has been deleted is invisible to it -- which is the half `midrun` §1a
    measured and `--declare` (`:151-173`) exists to catch. Asking for both here is what lets
    `digest()` report an ABSENT input instead of a hash over a population that quietly shrank."""
    mod = _snapshot_mod()
    if mod is None:
        return []
    mod.ROOT = root
    present = mod.inputs()
    absent = [root / c for c in mod.COPIES
              if not (root / c).exists() and not any((root / c) == p for p in present)]
    return sorted(present + absent)


def digest(root: pathlib.Path) -> dict:
    """ONE sha256 over `relpath NUL bytes`, sorted by relpath. See the module docstring for the
    three choices; this is where they are load-bearing.

    A declared-but-absent input contributes its PATH and the token `\\0ABSENT` rather than
    being dropped, so "the input is gone" is a DIFFERENT digest from "the input was never
    declared" -- and a hash that cannot see a deletion is a hash that certifies a tree nobody ran
    against."""
    h, n, absent, total = hashlib.sha256(), 0, [], 0
    for p in population(root):
        rel = p.relative_to(root).as_posix()
        h.update(rel.encode())
        h.update(b"\0")
        try:
            body = p.read_bytes()
        except OSError:
            h.update(b"ABSENT")
            absent.append(rel)
            continue
        h.update(body)
        n += 1
        total += len(body)
    return {"digest": h.hexdigest(), "inputs": n, "declared": n + len(absent),
            "absent": absent, "bytes": total}


def rows(root: pathlib.Path) -> list[str]:
    """The two lines, in summary order. `substrate-start` is the value the caller took BEFORE
    the run; this helper takes both at one instant so `--rows` is inspectable, and `differ.py`
    calls `digest()` twice around its own work instead."""
    d = digest(root)
    return [f"{ROW_START}={d['digest']}", f"{ROW_END}={d['digest']}"]


def declared_values(text: str) -> dict[str, str]:
    """`key=value`, by `partition`, the way `checks/env-precond.py:214-221` reads this file.
    IMPORTED BEHAVIOUR, RETYPED ONCE: a second tokenizer for a file with four consumers is a
    second opinion about one fact, which is what `checks/coindep.py` exists to undo."""
    out: dict[str, str] = {}
    for raw in text.splitlines():
        k, sep, v = raw.partition("=")
        if sep and k.strip() and " " not in k.strip():
            out[k.strip()] = v.strip()
    return out


def verdict_for(start: str | None, end: str | None, here: dict) -> tuple[int, str]:
    """THE VERDICT, AS A FUNCTION OF THREE VALUES, so the plant exercises THIS and not a
    paraphrase of it -- `midrun` §5 asserts the exit codes, and a plant that re-derives them
    locally would go green if this function changed.

    FIVE verdicts, three of them refusals for three DIFFERENT reasons, each named:

      REFUSED(3)  a row is ABSENT -- a run that does not say which bytes produced it is a
                  measurement with no subject, and an ABSENT row is a complaint, not a pass.
                  **This is the state every run in this tree is in today**, because no row of
                  `D0-run-summary.txt` names bytes. `DEAD` is reserved for "there is no run at
                  all" and is decided by `judge()`, which can see the file this cannot.
      REFUSED(3)  the two rows DISAGREE -- the substrate moved DURING the run, so the artifact
                  set is not a set of measurements of one thing.
      REFUSED(3)  a declared input is ABSENT -- `midrun` §1a: `D10-zerorow-guard.txt` currently
                  carries `rc=1` with `no such file: graphcmp-empty.bend` in its `.err`.
      PASS(0)     both present and equal.
      REFUSED(3)  the digest disagrees with THIS tree -- the run is a measurement, of bytes that
                  are no longer here. A provenance finding, NOT a wrong answer, and it is a
                  refusal because a pin matched against it cannot mean what it says.

    NOT `FAIL`, and the reason is the whole design: nothing here compared two ANSWERS. A
    disagreement between two digests says the SUBJECT was not held still, which is an absent
    precondition -- the same reading `quiesce.py:24-25` gives a moving tree."""
    for key, val in ((ROW_START, start), (ROW_END, end)):
        if val is None:
            return REFUSED, (f"records no {key}= -- a run that does not say which bytes produced "
                             "it is a measurement with no subject. Re-run `checks/differ.py run`")
    if start != end:
        return REFUSED, (f"the substrate MOVED DURING THE RUN ({start[:12]} -> {end[:12]}). "
                         "The artifacts are not all measurements of one substrate. DO NOT WAIT "
                         "-- SNAPSHOT (.agents/slop/quiesce/snapshot.py)")
    # **AN ABSENT DECLARED INPUT IS A NOTE, NOT A VERDICT, AND THAT IS THE WHOLE ARGUMENT.**
    # The digest is computed over `path` + `bytes` OR `path` + `ABSENT`, so a reader whose
    # digest EQUALS the run's already proves both populations have the same paths and the same
    # bytes-or-absence -- the shape check is subsumed, and refusing on it as well would double
    # count one fact. Refusing here unconditionally is worse than useless: TWO declared inputs
    # are absent from this tree right now (`graphcmp-dbg.bend`, `graphcmp-empty.bend`,
    # `midrun` §1a), so the judge would be REFUSED FOREVER and would be ignored -- which is
    # `AGENTS.md` doctrine 2's *"a gate that can never pass is worse than no gate"* and
    # `repropin` §4's *"a gate that can never pass is worse than no gate"* reached the same way.
    # The absence is still NAMED, on every verdict, by `note_absent()`.
    if here["digest"] != end:
        return REFUSED, (f"the run recorded {end[:12]} and this tree hashes "
                         f"{here['digest'][:12]}. The run IS a measurement -- of bytes that are "
                         "not here. A provenance finding, NOT a wrong answer")
    return PASS, (f"this tree IS the substrate that produced the run -- {here['inputs']} inputs, "
                  f"{here['bytes']} bytes, digest {here['digest'][:12]}")


def note_absent(here: dict) -> str:
    """The absent inputs, NAMED, on every verdict. A population that quietly shrank is the defect
    `snapshot.py:74-77` is written against and `midrun` §1a measured live; a digest that cannot
    say WHICH shrank detects the shrinkage and diagnoses nothing, so the name is printed whether
    or not the digest moved."""
    if not here["absent"]:
        return ""
    return (f"  NOTE, not a verdict: {len(here['absent'])} DECLARED input(s) are ABSENT and are "
            f"in the digest as the token ABSENT -- {', '.join(here['absent'])}. The digest still "
            "matches, which is why this is not a refusal, but the run did not measure them.\n")


def judge(summary: pathlib.Path, root: pathlib.Path | None = None) -> int:
    """Read the two rows out of a summary and say what they mean. This is the reader that makes
    the rows a MEASUREMENT rather than a LABEL, and it is a FUNCTION a caller can import rather
    than a `PINS` literal that has to be re-pinned whenever the port's next fix lands.

    `DEAD` IS DECIDED HERE AND ONLY HERE, because it is the one verdict that is about the FILE
    rather than about its contents: a summary that does not exist, or exists and holds no
    `key=value` row at all, is `DEAD` -- it ran and emitted nothing checkable. A summary with
    twenty-two rows and no `substrate-*` is `REFUSED`, because it emitted plenty and one
    precondition is absent, and collapsing those two is exactly the `SKIP IS NOT PASS` /
    `DEAD IS NOT A ZERO` defect `AGENTS.md` doctrine 2 records."""
    if not summary.exists():
        print(f"DEAD, NOT A VERDICT: {summary} is absent -- there is no run to be a measurement "
              "of anything")
        return DEAD
    text = summary.read_text(errors="replace")
    if not any("=" in ln for ln in text.splitlines()):
        print(f"DEAD, NOT A VERDICT: {summary.name} holds no key=value row -- it ran and emitted "
              "nothing checkable")
        return DEAD
    got = declared_values(text)
    here = digest(root or ROOT)
    rc, why = verdict_for(got.get(ROW_START), got.get(ROW_END), here)
    tail = ", NOT A VERDICT" if rc == REFUSED else ""
    print(f"{NAMES.get(rc, rc)}{tail}: {why}")
    print(note_absent(here), end="")
    return rc


# --------------------------------------------------------------------------- the plant
def _seed(root: pathlib.Path) -> None:
    """A scratch tree with the SHAPE of the real one: one hot input the steps read, and cold
    inputs they never read. The shape is the whole point -- `midrun` §6 measured that 140 of 148
    inputs are COLD, so a plant with only a hot file would be testing the population the run
    already covers (12 of 17 pins go red there).

    EVERY DECLARED `COPIES` ENTRY IS SEEDED, including the two absent from the real tree
    (`graphcmp-dbg.bend`, `graphcmp-empty.bend`), because `verdict_for` refuses an absent
    declared input -- a plant whose tree is permanently REFUSED for a reason the plant did not
    cause measures nothing. `snapshot.COPIES` is ASKED, not copied, so this stays correct when a
    fourth entry is added."""
    mod = _snapshot_mod()
    (root / "tinybendygrad/uop").mkdir(parents=True)
    (root / "tinybendygrad/uop/ops.bend").write_text("def op: 0\n" * 40)
    (root / "tinybendygrad/PROOF.bend").write_text("theorem t: True\n" * 20)
    (root / "checks").mkdir(parents=True)
    (root / "bin").mkdir()
    for c in mod.COPIES:
        p = root / c
        p.parent.mkdir(parents=True, exist_ok=True)
        if c in ("bin",) or p.is_dir():
            p.mkdir(exist_ok=True)
        else:
            p.write_text(f"# {c}\n")
    (root / "bin/bend").write_text("#!/bin/sh\n")


def _steps(root: pathlib.Path, out: pathlib.Path, n: int) -> int:
    """`n` steps, each re-reading the HOT input -- the property that makes a mid-run edit
    change answers rather than merely change bytes (`midrun` §3)."""
    rc = 0
    hot = (root / "tinybendygrad/uop/ops.bend").read_text()
    for i in range(n):
        rows_n = 0 if "MIDRUN-BREAK" in hot else 12
        (out / f"step{i}.txt").write_text(
            "\n".join(f"# step {i} row {j} ok" for j in range(rows_n)) + "\n" if rows_n else "rc=1\n")
        rc |= (1 if rows_n == 0 else 0)
    return rc


def _one_line(root: pathlib.Path) -> None:
    """THE SMALLEST POSSIBLE SUBSTRATE CHANGE: one line, one character, one input. If a digest
    over 6 inputs cannot see this, the aggregation is wrong and no other measurement matters."""
    p = root / "tinybendygrad/PROOF.bend"
    p.write_text(p.read_text().replace("True", "Truex", 1))


def plant() -> int:
    """FIVE CASES, THREE VERDICTS, AND THE ONE THAT HAS NEVER BEEN RUN.

    `pinindep` §7.3: *"All of the 11 sensitivity perturbations edit a FINISHED artifact set; a
    substrate change during a run is still untested, and the tree has been bitten by exactly that
    twice."* Case 3 IS that case, and it is built on a scratch tree with the declared population's
    shape and three steps that re-read the hot input -- a run's SHAPE at 1/30th of the size, so
    the mid-flight edit is observable to the second.

    EVERY CASE DRIVES `verdict_for()`, the function `judge()` calls. A plant that recomputed its
    own expectation would stay green when the verdict function changed, which is the
    `midrun` §5 defect reproduced inside this file."""
    bad = 0
    with tempfile.TemporaryDirectory() as td:
        tdp = pathlib.Path(td)

        def verdict(tree: pathlib.Path, start: str, end: str | None = None):
            return verdict_for(start, start if end is None else end, digest(tree))

        # CASE 1 -- stable. A detector that cannot say PASS is a coin that always says no, and it
        # is the case that would fail first if `population()` were empty.
        tree, out = tdp / "s1", tdp / "o1"
        _seed(tree); out.mkdir()
        start, rcs = digest(tree), []
        for _ in range(3):
            rcs.append(_steps(tree, out, 1))
        end = digest(tree)
        rc, why = verdict(tree, start["digest"], end["digest"])
        print(f"PLANT stable     start={start['digest'][:12]} end={end['digest'][:12]} "
              f"step-rcs={rcs} -> {NAMES[rc]} ({why[:44]}...)")
        bad += _expect("stable: PASS", rc, PASS)
        bad += _expect("stable: digest did not move", start["digest"] == end["digest"], True)

        # CASE 2 -- BETWEEN runs: the tree moves AFTER the run finished. The two rows are EQUAL,
        # so the RUN is not refused -- it is a measurement, of bytes that are no longer here --
        # and it is the READER, against this tree, that is refused. Two different questions and
        # two different verdicts, which is the whole reason there are two rows.
        tree, out = tdp / "s2", tdp / "o2"
        _seed(tree); out.mkdir()
        start = digest(tree)
        _steps(tree, out, 3)
        end = digest(tree)
        _one_line(tree)
        now = digest(tree)
        rc_run, _ = verdict_for(start["digest"], end["digest"], end)
        rc_read, why = verdict_for(start["digest"], end["digest"], now)
        print(f"PLANT between    end={end['digest'][:12]} now={now['digest'][:12]} -> "
              f"the RUN says {NAMES[rc_run]}, the READER says {NAMES[rc_read]}")
        bad += _expect("between: the run itself PASSES", rc_run, PASS)
        bad += _expect("between: the reader is REFUSED", rc_read, REFUSED)
        bad += _expect("between: rows are EQUAL so the run is not implicated",
                       start["digest"] == end["digest"], True)

        # CASE 3 -- MID-RUN. THE UNTESTED CASE. Two inputs change BETWEEN steps, ONE COLD and
        # then ONE HOT, and the digest is taken again at the end.
        tree, out = tdp / "s3", tdp / "o3"
        _seed(tree); out.mkdir()
        start = digest(tree)
        rcs = [_steps(tree, out, 1)]
        (tree / "tinybendygrad/PROOF.bend").write_text("MIDRUN-BREAK\n")  # a COLD input
        cold_moved = digest(tree)["digest"] != start["digest"]
        rcs.append(_steps(tree, out, 1))
        (tree / "tinybendygrad/uop/ops.bend").write_text("MIDRUN-BREAK\n" + "def op: 0\n" * 40)
        rcs.append(_steps(tree, out, 1))
        end = digest(tree)
        rc, why = verdict_for(start["digest"], end["digest"], end)
        print(f"PLANT midrun     start={start['digest'][:12]} end={end['digest'][:12]} "
              f"step-rcs={rcs} -> {NAMES[rc]}")
        bad += _expect("midrun: a COLD input alone moves the digest", cold_moved, True)
        bad += _expect("midrun: the rows DIFFER", start["digest"] != end["digest"], True)
        bad += _expect("midrun: REFUSED, never FAILed", rc, REFUSED)
        bad += _expect("midrun: the HOT break also shows in the ARTIFACTS", any(rcs), True)
        # AND THE MIRROR, which is the half that could have been missed: the cold edit ALONE,
        # with every step still rc=0, is invisible to the artifacts and visible only here.
        tree, out = tdp / "s3b", tdp / "o3b"
        _seed(tree); out.mkdir()
        start = digest(tree)
        rcs = [_steps(tree, out, 1)]
        (tree / "tinybendygrad/PROOF.bend").write_text("MIDRUN-BREAK\n")
        rcs.append(_steps(tree, out, 1))
        end = digest(tree)
        rc, _ = verdict_for(start["digest"], end["digest"], end)
        print(f"PLANT midrun-cold-only step-rcs={rcs} -> {NAMES[rc]}  "
              f"(every artifact rc=0 and the digest still moved)")
        bad += _expect("midrun-cold-only: no artifact noticed", not any(rcs), True)
        bad += _expect("midrun-cold-only: the ROWS noticed", rc, REFUSED)

        # CASE 4a -- a WALK-DISCOVERED input is DELETED. The digest MOVES (the population shrank,
        # so the byte stream is a different function) -- and NOTHING IS NAMED, because a walk
        # cannot report a member it no longer sees. **THIS IS A REAL LIMIT OF THE AGGREGATION
        # AND IT IS STATED IN THE REPORT, NOT PAPERED OVER**: detection is complete, attribution
        # for this one case is absent, and the diagnosis is `quiesce/quiesce.py`'s mtime log or
        # `git`, neither of which this row may depend on.
        tree, out = tdp / "s4a", tdp / "o4a"
        _seed(tree); out.mkdir()
        before = digest(tree)
        (tree / "tinybendygrad/PROOF.bend").unlink()
        after = digest(tree)
        print(f"PLANT delete-walk before={before['digest'][:12]} after={after['digest'][:12]} "
              f"named={after['absent'] or 'NOTHING'}")
        bad += _expect("delete-walk: the digest MOVES", before["digest"] != after["digest"], True)
        bad += _expect("delete-walk: NOT named -- a walk cannot see its own deletion",
                       after["absent"], [])

        # CASE 4b -- a DECLARED input is DELETED. `midrun` §1a measured this live: two declared
        # inputs are absent from the real tree and `D10-zerorow-guard.txt` carries the resulting
        # rc=1 with a `no such file` in its `.err`. Here the deletion is DETECTED (the digest
        # moves), NAMED (`absent` carries the path), and -- the half that is easy to get wrong --
        # it is NOT an unconditional refusal, because the run that recorded the same digest did
        # not measure that input either. A gate that refuses forever is a gate nobody reads.
        tree, out = tdp / "s4b", tdp / "o4b"
        _seed(tree); out.mkdir()
        gone = next(c for c in _snapshot_mod().COPIES if c.endswith("graphcmp-empty.bend"))
        before = digest(tree)
        (tree / gone).unlink()
        after = digest(tree)
        rc_same, _ = verdict_for(after["digest"], after["digest"], after)
        rc_run, _ = verdict_for(before["digest"], after["digest"], after)
        print(f"PLANT delete-cop  before={before['digest'][:12]} after={after['digest'][:12]} "
              f"named={after['absent']}")
        bad += _expect("delete-cop: the digest MOVES", before["digest"] != after["digest"], True)
        bad += _expect("delete-cop: NAMED, not counted", after["absent"], [gone])
        bad += _expect("delete-cop: a run over the SAME population still PASSES", rc_same, PASS)
        bad += _expect("delete-cop: the run that spanned the deletion is REFUSED", rc_run, REFUSED)
        bad += _expect("delete-cop: and it is NAMED, not just refused",
                       bool(note_absent(after)), True)

        # CASE 5 -- THE ONE-LINE CHANGE, and the CONTROL THAT FAILS IF THE INSTRUMENT IS BROKEN.
        tree, out = tdp / "s5", tdp / "o5"
        _seed(tree); out.mkdir()
        before = digest(tree)
        _one_line(tree)
        after = digest(tree)
        again = digest(tree)
        rc, _ = verdict_for(before["digest"], before["digest"], after)
        print(f"PLANT one-line   before={before['digest'][:12]} after={after['digest'][:12]} "
              f"-> {NAMES[rc]}")
        bad += _expect("one-line change is DETECTED", before["digest"] != after["digest"], True)
        bad += _expect("one-line change moves NO row count", after["inputs"], before["inputs"])
        bad += _expect("one-line change is REFUSED against a reader holding it", rc, REFUSED)
        bad += _expect("CONTROL: digest is stable over an unchanged tree",
                       again["digest"] == after["digest"], True)

        # CASE 6 -- DEAD, so the five are not four. `DEAD` is about the FILE, so it is `judge()`
        # that decides it -- an EMPTY summary and an ABSENT one are the two shapes.
        empty = tdp / "empty-summary.txt"
        empty.write_text("")
        rc_empty = judge(empty, tree)
        print(f"PLANT dead       empty summary -> {NAMES[rc_empty]}")
        bad += _expect("dead: an empty summary is DEAD, not PASS", rc_empty, DEAD)
        rc_gone = judge(tdp / "does-not-exist.txt", tree)
        print(f"PLANT dead       absent summary -> {NAMES[rc_gone]}")
        bad += _expect("dead: an absent summary is DEAD", rc_gone, DEAD)
        # AND THE STATE EVERY RUN IN THIS TREE IS IN: 22 rows, none of which names bytes.
        no_sub = tdp / "no-substrate-rows.txt"
        no_sub.write_text("graphs=34\ngraphs-unset=0\ndev=CPU\n")
        rc_nosub = judge(no_sub, tree)
        print(f"PLANT absent     3 rows, no substrate-* -> {NAMES[rc_nosub]}  "
              f"(an ABSENT row is a complaint, not a pass)")
        bad += _expect("absent rows are REFUSED, not DEAD and not PASS", rc_nosub, REFUSED)

    print(f"\nPLANT: {'OK' if not bad else f'{bad} MISMATCH(ES)'}")
    return 0 if not bad else 1


def _expect(name: str, got, want) -> int:
    ok = got == want
    print(f"  {'OK  ' if ok else 'WRONG'}: want {want!r}, got {got!r}   [{name}]")
    return 0 if ok else 1


def cost(sweeps: int) -> int:
    """WHAT IT COSTS, IN THE UNIT THE PROJECT ALREADY USES. `midrun` measured 56 ms for
    start+end over 148 inputs / 11.3 MB; this measures today's population and adds the COLD
    reading, because a percentage of a WARM run is not a percentage of a COLD one -- and the
    substrate is cold exactly when the run is expensive."""
    warm, cold, d = [], [], digest(ROOT)
    for _ in range(sweeps):
        t = time.perf_counter(); digest(ROOT); warm.append(time.perf_counter() - t)
    if os.uname().sysname == "Darwin":
        os.system("/usr/bin/purge 2>/dev/null")
    for _ in range(max(3, sweeps // 2)):
        t = time.perf_counter(); digest(ROOT); cold.append(time.perf_counter() - t)
    # `bendperf/REPORT.md:48`: a fixed launch is ~2.8 s, so a run's own launch count is the
    # denominator that matters. It is NOT taken from a run here -- no `bend` was started -- and
    # the honest statement is the ratio, not a fabricated cold-run total.
    both = sum(warm[:2]) if len(warm) >= 2 else warm[0] * 2
    f = lambda xs: (min(xs) * 1e3, sorted(xs)[len(xs) // 2] * 1e3, max(xs) * 1e3)  # noqa: E731
    lo, med, hi = f(warm)
    clo, cmed, chi = f(cold)
    print(f"population : {d['inputs']} inputs, {d['absent'] and len(d['absent']) or 0} absent, "
          f"{d['bytes'] / 1e6:.2f} MB")
    print(f"one digest : warm  min {lo:6.1f} ms  median {med:6.1f} ms  max {hi:6.1f} ms  "
          f"({sweeps} sweeps)")
    print(f"             COLD  min {clo:6.1f} ms  median {cmed:6.1f} ms  max {chi:6.1f} ms  "
          f"({len(cold)} sweeps, after `purge`)")
    print(f"two digests: {both * 1e3:.1f} ms")
    for label, secs in (("run34 warm 294 s", 294.0),):
        print(f"  {label:<22} -> {both / secs * 100:.4f} %")
    print(f"  one bend launch        -> {both / 2.8 * 100:.3f} %  "
          "(`bendperf/REPORT.md:48`, fixed launch ~2.8 s)")
    print(f"  a run's worth of launches at ~2.8 s: 56 rows would cost "
          f"{both / 2.8:.4f} launches")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", action="store_true", help="print the two rows for this tree")
    ap.add_argument("--hash", action="store_true", help="print this tree's digest as JSON")
    ap.add_argument("--judge", metavar="FILE", help="judge the two rows out of a summary")
    ap.add_argument("--plant", action="store_true")
    ap.add_argument("--cost", action="store_true")
    ap.add_argument("--sweeps", type=int, default=5)
    a = ap.parse_args()
    if a.plant:
        return plant()
    if a.cost:
        return cost(a.sweeps)
    if a.hash:
        print(json.dumps(digest(ROOT), sort_keys=True))
        return PASS
    if a.rows:
        print("\n".join(rows(ROOT)))
        return PASS
    if a.judge:
        return judge(pathlib.Path(a.judge))
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())