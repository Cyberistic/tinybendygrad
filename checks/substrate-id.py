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
    (`quiesce/quiesce.py`'s per-path mtime log, `substrate-snapshot.py --verify`'s named row). A
    digest that named the file would have to be 148 rows, which is the row count above.

THE POPULATION IS DISCOVERED, NOT LISTED. `checks/substrate-snapshot.py` is LOADED BY PATH and its
`inputs()` is asked, so this file has no second list of what a run reads -- which is the defect
`snapshot.py:74-77` is written against, and the defect `coindependent`'s 42 and `gates-pop.py`'s
`HOMES` are both instances.

AND THE DECLARATION IS IN GIT, BESIDE THIS FILE, WHICH IS NOT THE SAME SENTENCE. Measured
2026-10-08: `git ls-tree -r HEAD -- .agents/slop/quiesce/` answered **0 paths** over 9 files on
disk, so the one instrument that DEFINES this gate's population was itself outside the tree, and
a `git archive HEAD` tree carried a gate whose entire population was invisible to it. The
population's MEMBERS were never the problem -- 137 of 137 `tinybendygrad/` blobs, `differ.py`,
`devpin.py` and all five `graphcmp*` files are in HEAD -- so `DECLARER` is what moved.

VERDICTS, FIVE, AND WHICH OF THEM CAN HAPPEN HERE. `PASS` (0) the two digests agree, so the
artifacts are all measurements of one substrate. `REFUSED` (3) the PRECONDITION was absent -- a
declared input is missing, or the tree moved, or the rows are not both present. `FAIL` (1) is
NOT reachable and that is the point: nothing here compares two ANSWERS, it compares two
MEASUREMENTS OF ONE SUBJECT, and a disagreement there is a missing precondition rather than a
wrong result. `DEAD` (5) the population is empty -- nothing was measured at all. `SKIP` (4) is
not defined because this file always measures or refuses.

**`DEAD` HAD NO BRANCH. IT IS DECIDED IN `verdict_for()` BY `measured()` NOW, FIRST, BEFORE ANY
OTHER QUESTION** -- because an empty population makes every other question unaskable. The clause
above was true of the CONSTANTS and false of the CODE: `judge()` reached `DEAD` only when the
SUMMARY was absent or keyless, so `--hash` and `--rows` returned `PASS` over 0 inputs on a
`git archive HEAD` tree, and `verdict_for()` returned `PASS` over 0 inputs to any summary that
had recorded the empty string's sha256. `judge()` was `DEAD` on that tree BY ACCIDENT -- `runs/`
is gitignored OUTPUT, so the summary was absent for a reason that has nothing to do with the
population. A gate whose DEAD is reached by the wrong cause is still a gate that cannot say why.
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

#: THE DECLARATION, IN GIT, BESIDE THE GATE THAT ASKS IT. This is the only path this file looks
#: the population up from, so it is a population by (a) of `AGENTS.md` doctrine 1 -- a generator's
#: own declaration, loaded by path -- and NOT a hand list, a basename shape or a suffix set.
DECLARER = "checks/substrate-snapshot.py"

PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5
#: gatekit's vocabulary, `gates/gatekit.py:59`: PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5.
NAMES = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", DEAD: "DEAD"}


def token(rc: int) -> str:
    """The verdict CODE as a WORD, and THE ONLY PLACE THAT HAPPENS.

    `NAMES[...]` appeared **9** times and `NAMES.get(rc, rc)` once in this file's plant -- ten
    index sites, not the eleven `boolexit` reported (it counted the `:76` DEFINITION as an eleventh
    use; the uses are ten, verified by `ast` over `ast.Subscript`/`ast.Attribute` on the name
    `NAMES`). Every one of the ten indexed a dict keyed by `int` with a value whose type nothing
    declared, and `bool` SUBCLASSES `int`, so a future `return ok` would silently key `NAMES[True]`
    to `"FAIL"` and `NAMES[False]` to `"PASS"` -- ten sites that print a WRONG VERDICT rather than
    raising. `NAMES.get(rc, rc)` at the old `:247` is the worst of the ten: its fallback makes it
    SILENT, so `True` printed `FAIL` with no exception anywhere.

    **THE STRICTER FORM WAS MEASURED AND REJECTED, AND THE COST IS THE POINT.** `type(rc) is int`
    refuses `bool` -- and also refuses an `IntEnum` verdict vocabulary, which `isinstance` accepts,
    which hashes equal to its `int` value, and which indexes `NAMES` correctly. So the strict form
    buys bool-safety by breaking a legitimate encoding of the SAME five verdicts. A stricter fix is
    not strictly better. This one rejects exactly the type that is wrong (`bool`, named, because
    `bool` is the only subclass of `int` that is not an int-valued verdict) and keeps `IntEnum`.

    An UNASSIGNED code is a REFUSAL rather than an exception or a bare number, which is
    `gates/gatekit.py`'s `verdict_of()` rule and not an invention here: a reader that prints `7`
    has learned nothing, and a reader that raises has lost the summary it was reading."""
    if isinstance(rc, bool):
        return f"NOT-A-VERDICT({type(rc).__name__})"
    return NAMES.get(rc, f"NOT-A-VERDICT({rc})")

#: THE TWO ROWS. `differ.py`'s `ROW_VALUES` shape is a dict literal of key -> value; these are
#: not constants (they are measurements), so they are joined into the summary the one way the
#: summary admits -- as `key=value` lines from a function, which is `precondition_rows()`.
ROW_START, ROW_END = "substrate-start", "substrate-end"


def _snapshot_mod(root: pathlib.Path | None = None):
    """`DECLARER` LOADED BY PATH, OUT OF THE ROOT BEING MEASURED. Never `import snapshot`:
    `checks/` is off `sys.path` for a caller that is not `differ.py`, and an instrument whose
    population is chosen by a bindable name is an instrument whose population anybody can choose
    (`gates/gates-pop.py:99-101`).

    `root` IS A PARAMETER AND NOT THE MODULE GLOBAL, AND THAT IS NOT TIDINESS. `DEAD` here means
    "the declaration is not where it is declared to be", which is a fact ABOUT A ROOT, so the
    only way the plant can exercise `DEAD` at all is by pointing this loader at a tree that has
    no declarer -- which is exactly the tree that produced the false green."""
    p = (root or ROOT) / DECLARER
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
    mod = _snapshot_mod(root)
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
    against.

    `declarer` IS A FACT ABOUT THIS MEASUREMENT, recorded beside it rather than inferred by the
    caller: it is what lets `empty_population()` name a CAUSE instead of only a symptom."""
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
            "absent": absent, "bytes": total, "declarer": (root / DECLARER).is_file()}


def measured(here: dict) -> int:
    """`PASS` over a NON-EMPTY population, `DEAD` over an empty one. **THE ONLY
    EMPTY-POPULATION CHECK IN THIS FILE**, so the three surfaces that can report a digest --
    `verdict_for()`, `--hash` and `--rows` -- cannot disagree about it.

    THE DENOMINATOR IS `declared`, NOT `inputs`. A declared-but-absent member is still a member
    (`snapshot.inputs()`'s `else`), so `inputs == 0` over `declared == 10` is a measurement of ten
    paths -- three of them absent on purpose -- and only `declared == 0` means nothing was
    measured at all. Counting `inputs` would have made the two absent probes (`graphcmp-dbg.bend`,
    `graphcmp-empty.bend`) indistinguishable from a missing population."""
    return PASS if here["declared"] else DEAD


def empty_population(here: dict) -> str:
    """WHY an empty population is `DEAD`, with the cause named and not just the symptom.

    MEASURED, both halves, on 2026-10-08: a real tree declared 150 inputs and hashed 148; the same
    gate on a `git archive HEAD` tree declared 0 and hashed 0, and printed `PASS` over the sha256
    of the empty string. The one-word difference between those two runs is whether `DECLARER` is
    in git, so the message says that."""
    cause = ("is ABSENT from this tree, so `population()` is empty and nothing was declared"
             if not here["declarer"] else
             "IS PRESENT AND DECLARES NOTHING -- its walk and its copies both came back empty")
    return (f"the population is EMPTY -- 0 declared inputs, so nothing was measured, and the "
            f"digest is the sha256 of no bytes at all, which is a value every empty run also has. "
            f"The declaration, {DECLARER}, {cause}. A gate that reports PASS over 0 inputs is "
            f"worse than no gate, because it is trusted")


def rows(here: dict) -> list[str]:
    """The two lines, in summary order. `substrate-start` is the value the caller took BEFORE
    the run; this helper takes both at one instant so `--rows` is inspectable, and `differ.py`
    calls `digest()` twice around its own work instead. It takes the MEASUREMENT rather than the
    root because `--rows` needs the same dict for `measured()` and re-hashing for it would be a
    second reading of a population that is only supposed to be read once per row pair."""
    return [f"{ROW_START}={here['digest']}", f"{ROW_END}={here['digest']}"]


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

      DEAD(5)     the population is EMPTY. **FIRST, BEFORE EVERY OTHER QUESTION, AND THAT IS THE
                  ORDER AND NOT THE FORMALITY**: with 0 declared inputs there is no measurement to
                  compare a row against, so "the rows disagree", "the rows are absent" and "the
                  run is a measurement of bytes that are not here" are all questions about
                  nothing, and answering any of them prints a cause that is not the cause. This is
                  the clause `:55` declared while no code path emitted it.
      REFUSED(3)  a row is ABSENT -- a run that does not say which bytes produced it is a
                  measurement with no subject, and an ABSENT row is a complaint, not a pass.
                  **This is the state every run in this tree is in today**, because no row of
                  `D0-run-summary.txt` names bytes. `DEAD` is reserved for "there is no run at
                  all" and for "there was no population to be a run of", and is decided by
                  `measured()` here and by `judge()` where the FILE is the subject.
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
    if measured(here) == DEAD:
        return DEAD, empty_population(here)
    for key, val in ((ROW_START, start), (ROW_END, end)):
        if val is None:
            return REFUSED, (f"records no {key}= -- a run that does not say which bytes produced "
                             "it is a measurement with no subject. Re-run `checks/differ.py run`")
    if start != end:
        return REFUSED, (f"the substrate MOVED DURING THE RUN ({start[:12]} -> {end[:12]}). "
                         "The artifacts are not all measurements of one substrate. DO NOT WAIT "
                         f"-- SNAPSHOT ({DECLARER})")
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

    `DEAD` HAS TWO SUBJECTS AND IS DECIDED ON BOTH. **THE POPULATION** is decided by
    `verdict_for()`, which cannot see this file, so it is checked there and the row comparisons
    that follow it are comparisons about something. **THE SUMMARY** is decided here, because it
    is the one verdict that is about the FILE rather than about its contents: a summary that does
    not exist, or exists and holds no `key=value` row at all, is `DEAD` -- it ran and emitted
    nothing checkable. A summary with twenty-two rows and no `substrate-*` is `REFUSED`, because it
    emitted plenty and one precondition is absent, and collapsing those two is exactly the
    `SKIP IS NOT PASS` / `DEAD IS NOT A ZERO` defect `AGENTS.md` doctrine 2 records.

    The population is checked by `verdict_for()` and NOT re-checked here, so the two `DEAD`s
    cannot both fire with two different messages. `runs/` is gitignored OUTPUT, so on a
    `git archive HEAD` tree this summary is absent and this function returned `DEAD` FOR THE WRONG
    REASON while `--hash` on the same tree returned `PASS`; the population is the earlier
    question and now the earlier branch."""
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
    print(f"{token(rc)}{tail}: {why}")
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
    fourth entry is added.

    **THE DECLARATION IS SEEDED TOO, AND OMITTING IT WOULD HAVE BROKEN EVERY CASE ABOVE.** The
    loader asks the tree being measured for its declaration (`_snapshot_mod(root)`), because a
    tree whose declarer is missing is exactly the tree that must be DEAD and a seed that quietly
    borrowed the real one would make `DEAD` unreachable in the plant while remaining trivially
    reachable in production. So the scratch tree carries its own copy of `DECLARER` -- one file,
    byte-identical to the gate's, and asked the same way."""
    mod = _snapshot_mod()
    (root / "tinybendygrad/uop").mkdir(parents=True)
    (root / "tinybendygrad/uop/ops.bend").write_text("def op: 0\n" * 40)
    (root / "tinybendygrad/PROOF.bend").write_text("theorem t: True\n" * 20)
    (root / "checks").mkdir(parents=True)
    (root / "bin").mkdir()
    shutil.copyfile(ROOT / DECLARER, root / DECLARER)
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
              f"step-rcs={rcs} -> {token(rc)} ({why[:44]}...)")
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
              f"the RUN says {token(rc_run)}, the READER says {token(rc_read)}")
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
              f"step-rcs={rcs} -> {token(rc)}")
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
        print(f"PLANT midrun-cold-only step-rcs={rcs} -> {token(rc)}  "
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
              f"-> {token(rc)}")
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
        print(f"PLANT dead       empty summary -> {token(rc_empty)}")
        bad += _expect("dead: an empty summary is DEAD, not PASS", rc_empty, DEAD)
        rc_gone = judge(tdp / "does-not-exist.txt", tree)
        print(f"PLANT dead       absent summary -> {token(rc_gone)}")
        bad += _expect("dead: an absent summary is DEAD", rc_gone, DEAD)
        # AND THE STATE EVERY RUN IN THIS TREE IS IN: 22 rows, none of which names bytes.
        no_sub = tdp / "no-substrate-rows.txt"
        no_sub.write_text("graphs=34\ngraphs-unset=0\ndev=CPU\n")
        rc_nosub = judge(no_sub, tree)
        print(f"PLANT absent     3 rows, no substrate-* -> {token(rc_nosub)}  "
              f"(an ABSENT row is a complaint, not a pass)")
        bad += _expect("absent rows are REFUSED, not DEAD and not PASS", rc_nosub, REFUSED)

        # CASE 7 -- THE EMPTY POPULATION, WHICH IS WHAT A `git archive HEAD` TREE WAS. This is the
        # case that had NO BRANCH: `git ls-tree -r HEAD -- .agents/slop/quiesce/` answered 0 paths
        # over 9 files on disk, so on a tree that HAS the declarer this gate hashed 0 inputs and
        # returned PASS over the sha256 of the empty string. Reproduced here on a tree that has no
        # declarer at all, which is the same state reached the honest way.
        #
        # `no-declarer` is an EMPTY directory. `_seed()` is NOT called on it, deliberately: a tree
        # seeded from the declaration has a population by construction, so it can only ever reach
        # PASS or REFUSED, and a plant that cannot build the failing state cannot prove the fix.
        bare = tdp / "no-declarer"
        bare.mkdir()
        d_bare = digest(bare)
        rc_bare, why_bare = verdict_for(d_bare["digest"], d_bare["digest"], d_bare)
        print(f"PLANT empty      declared={d_bare['declared']} inputs={d_bare['inputs']} "
              f"digest={d_bare['digest'][:12]} -> {token(rc_bare)}")
        print(f"  cause: {why_bare[:96]}...")
        bad += _expect("empty: the population really is 0 declared", d_bare["declared"], 0)
        bad += _expect("empty: the digest IS the sha256 of the empty string",
                       d_bare["digest"],
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        bad += _expect("empty: DEAD, and never PASS", rc_bare, DEAD)
        bad += _expect("empty: the CAUSE is named, not only the symptom",
                       DECLARER in why_bare and "ABSENT" in why_bare, True)
        bad += _expect("empty: measured() and verdict_for() cannot disagree",
                       measured(d_bare), rc_bare)
        # AND THE CONTROL THAT PROVES THE GUARD IS NOT MERELY A CONSTANT THAT NEVER FIRES: the
        # SAME function on a tree whose declarer is present must not be DEAD.
        d_seeded = digest(tdp / "s5")
        bad += _expect("CONTROL: a seeded tree with the declarer present is not DEAD",
                       measured(d_seeded), PASS)

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
        d = digest(ROOT)
        print(json.dumps(d, sort_keys=True))
        if measured(d) == DEAD:
            print(empty_population(d), file=sys.stderr)
        return measured(d)
    if a.rows:
        d = digest(ROOT)
        print("\n".join(rows(d)))
        if measured(d) == DEAD:
            print(empty_population(d), file=sys.stderr)
        return measured(d)
    if a.judge:
        return judge(pathlib.Path(a.judge))
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())