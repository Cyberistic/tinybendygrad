#!/usr/bin/env python3
"""nul-refusal-gate.py -- WHEN THE CENSUS CANNOT READ A FILE, DOES THE CENSUS SAY SO?

    .venv/bin/python gates/nul-refusal-gate.py

`gates/nul-census-gate.py` ALREADY OWNS THE FIRST HALF OF THIS QUESTION and does it well: it
measures the BYTES (which committed files carry a NUL, which of them are binaries), measures
the ARM (why one NUL escapes and another does not), and its verdict is -- in its own words --
"ABOUT THE EXTRACTOR DYING, NOT ABOUT THE BYTES BEING THERE".  This file does NOT repeat any
of that.  It measures the one thing nothing in the tree measures:

    *** WHAT THE CENSUS EMITS FOR A FILE IT COULD NOT READ. ***

WHICH IS NOT A RHETORICAL QUESTION.  `checks/cites-census.py`'s population is
`EXTS = (".md", ".py")`, and the one committed text file carrying a NUL is a `.bend`, so the
census's DEFAULT RUN CANNOT SEE IT: `prose()` is never handed the file and the census reports
nothing about it.  Every statement anyone has made about "what the census does with that
file" -- including the one in `gates/cites-pop-gate.py`'s clause IV, which runs `prose()` by
hand -- is a statement about a file that is NOT IN THE POPULATION.  This gate puts it IN:

  I    THE ROW          `census([witness])` -> what it emits, the verdict, and THE LINE.
  II   THE EXIT         `worst()` over that row, and the number `main()` would return.
  III  THE THREE ARMS   the plants, run HERE, each one able to fail, with a control that can
                        fail the other way.
  IV   NOT-A-FALSE-PASS the row is ABSENT -> `DEAD` (exit 5).  Never `PASS`.

CLAUSE IV IS THE POINT OF THE FILE.  The failure this tree already made once was a catch that
swallowed the escape: the run printed `PASS`, the gate said `no-exception`, and a file that
nothing could read was reported as agreement.  A gate that cannot tell "emitted the refusal"
from "emitted nothing" is that same gate with a different name, so the ABSENCE of the row is
a verdict here and it is `DEAD`, which is the one word `AGENTS.md` says nobody writes down.

LOADS `checks/cites-census.py` BY PATH.  `gates/` is not a package, and putting it on
`sys.path` would make `cites_census` a name any file in the tree could shadow.

EXIT: PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import tokenize
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASS, FAIL, REFUSED, SKIP, DEAD = "PASS", "FAIL", "REFUSED", "SKIP", "DEAD"
EXITS = {PASS: 0, FAIL: 1, REFUSED: 3, SKIP: 4, DEAD: 5}

DECLARED_SOURCE = ROOT / "checks/cites-census.py"
# THE SUBJECT, named rather than discovered.  A `.bend` is Doctrine 1's suffix set; the
# subject of this gate is one file with one NUL, and that is a constant, not a population.
WITNESS = "tinybendygrad/runtime/ops_dsp.bend"


def nul_line() -> int:
  """THE LINE THE WITNESS'S NUL IS ON, DERIVED FROM THE WITNESS.  The NUL byte is searched
  for rather than the line number written down: a transcribed number is the defect this tree
  keeps re-finding, and a value that moves with the file cannot be wrong about the file.
  LAZY, not a module constant -- a module constant reads the file at import and turns this
  gate's `REFUSED`-when-the-witness-is-gone path into a traceback."""
  body = (ROOT / WITNESS).read_bytes().decode("utf-8", "replace")
  return body[:body.index("\x00")].count("\n") + 1


def load_census():
  """`checks/cites-census.py` BY PATH.  Absent -> the caller REFUSES, naming the file."""
  if not DECLARED_SOURCE.is_file():
    return None
  spec = importlib.util.spec_from_file_location("cites_census_by_path", DECLARED_SOURCE)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def main() -> int:
  cites = load_census()
  if cites is None:
    # NOT `relative_to(ROOT)`: this is the branch that runs when the path is somewhere else
    # entirely, and that call raises `ValueError` -- so the most graceful branch of the gate
    # was the one that crashed.
    print(f"{REFUSED}: {DECLARED_SOURCE} is absent -- this gate cannot be measured")
    return EXITS[REFUSED]
  if not (ROOT / WITNESS).is_file():
    print(f"{REFUSED}: {WITNESS} is absent -- this gate cannot be measured")
    return EXITS[REFUSED]
  cases: list = []
  NUL = nul_line()

  print("--- I. THE ROW: what the census emits for a file it could not read ---")
  print(f"  population declared by the census itself: {cites.EXTS} -- and {WITNESS} ends "
        f"`.bend`, so the DEFAULT RUN NEVER CALLS prose() ON IT.")
  try:
    claims, _ = cites.census([WITNESS], ROOT)
  except BaseException as e:                # noqa: BLE001 -- the escape IS the defect
    print(f"  THE CENSUS DIED: {type(e).__name__} escaped `census()`.")
    print(f"  cause: {e.__cause__!r}")
    print("\nVERDICT: FAIL -- the census cannot read this file and cannot say so.")
    return EXITS[FAIL]
  judged = [cites.judge(c) for c in claims]
  rows = [c for c in judged if c.get("kind") == "unproseable"]
  if not rows:
    print(f"  EMITTED NOTHING.  {len(judged)} row(s), none of them a refusal.")
    print("\nVERDICT: DEAD -- the census ran, read the file, and said nothing about it.")
    print("  A CENSUS THAT IS SILENT ABOUT A FILE IT COULD NOT READ IS NOT PASSING.")
    return EXITS[DEAD]
  for r in rows:
    print(f"  lane={r['lane']} kind={r['kind']} verdict={r['verdict']} "
          f"line={r['at']} needle_kind={r['needle_kind']}")
    print(f"  evidence: {r['evidence']}")
  prose_claims = len([c for c in judged if c["lane"] in "BCDE"])
  print(f"  claims about this file's prose: {prose_claims} -- and 0 is not agreement")

  # --- II. THE EXIT -----------------------------------------------------------
  # PRINTING THE VERDICT AND CHECKING IT ARE DIFFERENT THINGS, AND AN EARLIER REVISION OF
  # THIS FILE ONLY DID THE FIRST: with `judge`'s guard removed the row arrived carrying SKIP,
  # `worst` answered PASS, exit came back 0, and the gate said PASS over a file nothing could
  # read.  Two of its five arms were decoration.  Both numbers are asserted below.
  print("\n--- II. THE EXIT: `SKIP` AND `DEAD` ARE NOT PASS, AND `REFUSED` IS NOT 0 ---")
  w = cites.worst(judged)
  print(f"  worst() = {w} -> main() would return {EXITS[w]}")
  print(f"  and the census's own EXITS table: REFUSED={EXITS[cites.REFUSED]} "
        f"PASS={EXITS[cites.PASS]} SKIP={EXITS[cites.SKIP]} DEAD={EXITS[cites.DEAD]}")
  # DERIVED, not written down, and CHECKED against the row the census just emitted -- so a
  # census that names the wrong line fails here even though every other clause passes.
  cases.append(("THE ROW'S VERDICT IS REFUSED, not SKIP and not PASS",
                rows[0]["verdict"], cites.REFUSED))
  cases.append(("THE ROW NAMES THE WITNESS'S NUL LINE, derived from the file",
                rows[0]["at"], NUL))
  cases.append(("THE EXIT IS 3, not 0 -- `worst()` sees the refusal",
                EXITS[w], EXITS[cites.REFUSED]))

  # --- III. THE THREE ARMS ----------------------------------------------------
  # RUN HERE, not delegated to `--selftest`: a gate whose only content is another file's
  # self-test can only fail when that self-test fails, which is a smoke check and not a
  # gate.  Each case asserts on the ROW, and the expected line is derived from the fixture.
  print("\n--- III. THE THREE ARMS, each able to fail, and a control that can fail back ---")
  with tempfile.TemporaryDirectory(prefix="nul-refusal-") as tmp:
    d = Path(tmp)

    def census_row(name: str, raw: bytes) -> dict:
      (d / name).write_bytes(raw)
      got = [c for c in cites.census([name], d)[0] if c.get("kind") == "unproseable"]
      return got[0] if got else {"verdict": None, "at": None}

    def fixture_line(raw: bytes) -> int:
      """THE LINE THE NUL IS ON IN A FIXTURE, read off the fixture.  A written-down number is
      the defect this tree keeps re-finding -- and an earlier revision of THIS file counted
      every newline including the trailing one and was one out, which the two FAILs caught."""
      body = raw.decode()
      return body[:body.index("\x00")].count("\n") + 1

    # arm 1: an INDENT token before the NUL -> the SystemError arm, the one nobody caught
    raw_a = b"# cite\n" * 4 + b"    a\n\x00\n"
    indented = census_row("indent-first.bend", raw_a)
    # arm 2: no INDENT -> the TokenError arm, which the old code CAUGHT AND DISCARDED
    raw_b = b"# cite\n" * 2 + b"a\n" + b"# cite\n\x00\n"
    bare = census_row("nul-first.bend", raw_b)
    cases.append(("NUL AFTER AN INDENT  -> REFUSED, at the line the tokenizer stopped",
                  (indented.get("verdict"), indented.get("at")),
                  (cites.REFUSED, fixture_line(raw_a))))
    cases.append(("NUL BEFORE ANY INDENT -> the SAME verdict from the other arm",
                  (bare.get("verdict"), bare.get("at")), (cites.REFUSED, fixture_line(raw_b))))
    (d / "clean.bend").write_bytes(b"# nothing wrong here\n")
    cases.append(("CONTROL: a file that tokenizes emits no refusal row",
                  [c for c in cites.census(["clean.bend"], d)[0]
                   if c.get("kind") == "unproseable"], []))

    # arm 3: a SystemError that is NOT the tokenizer's must not be answered with a position
    unrelated = SystemError("not the tokenizer")
    unrelated.__cause__ = ValueError("something else entirely")
    saved = tokenize.generate_tokens
    tokenize.generate_tokens = lambda *_: (_ for _ in ()).throw(unrelated)
    try:
      cites.tokenizer_fault(unrelated)
      arm3 = ("no-exception", False, False)
    except BaseException as e:                       # noqa: BLE001 -- the point is that it ESCAPES
      arm3 = (type(e).__name__, e is unrelated, isinstance(e.__cause__, ValueError))
    finally:
      tokenize.generate_tokens = saved
    cases.append(("UNRELATED CAUSE -> propagates as ITSELF, diagnostic not laundered",
                  arm3, ("SystemError", True, True)))

    # THE THIRD ARM, WHICH NOTHING IN THE TREE WAS PLANTING.  `IndentationError` is a
    # `SyntaxError` and the pre-fix catch listed it, so dropping that arm would NARROW a
    # catch rather than widen one -- and a mutation proved it: removing it changed no verdict
    # here, which is what an unplanted arm looks like.  Planted on the same seam.
    indent_fault = IndentationError("unindent does not match any outer indentation level",
                                    ("<plant>", 9, 4, "  x = 1", 3, 7))
    saved_i = tokenize.generate_tokens
    tokenize.generate_tokens = lambda *_: (_ for _ in ()).throw(indent_fault)
    try:
      arm_syntax = cites.tokenizer_fault(indent_fault)
    except BaseException as e:                       # noqa: BLE001
      arm_syntax = (type(e).__name__, None)
    finally:
      tokenize.generate_tokens = saved_i
    cases.append(("A `SyntaxError` arm -> its OWN lineno, not the TokenError path",
                  arm_syntax, (9, "IndentationError")))

    # ...and THE API CONTRACT a caller with nowhere to record a refusal depends on.  The
    # census always passes `fault`, so nothing above exercises the BARE call -- and the bare
    # call is what `gates/nul-census-gate.py` makes.  It must RAISE, carrying the line, and
    # it must land in `tokenize.TokenError`'s family because both live gates already wrap
    # `prose()` in `except (tokenize.TokenError, IndentationError)`.  One arm covers both:
    # if the class leaves the family this `except` does not fire and the gate dies loudly.
    try:
      cites.prose(WITNESS, (ROOT / WITNESS).read_bytes().decode("utf-8", "replace"))
      bare_shape = ("no-exception", None)
    except tokenize.TokenError as e:
      bare_shape = (type(e).__name__, e.args[1][0])
    cases.append(("BARE `prose()` -> a TokenError carrying the line, never a silent []",
                  bare_shape, ("Unproseable", NUL)))

  fails = 0
  for why, got, want in cases:
    ok = got == want
    fails += not ok
    print(f"  [{'PASS' if ok else 'FAIL'}] {why}")
    print(f"         got {got}, want {want}")

  # --- IV. NOT-A-FALSE-PASS ---------------------------------------------------
  print("\n--- IV. NOT-A-FALSE-PASS: the three readings this file must never confuse ---")
  print(f"  'the census REFUSED it'      -> rows={len(rows)} verdict={rows[0]['verdict']}")
  print(f"  'the census read it'         -> 1 file read, {prose_claims} prose claims taken from it")
  print("  'the census agreed with it'  -> NOT A THING, and never printed by this file")
  print(f"  A row that is ABSENT is {DEAD} (exit {EXITS[DEAD]}), never {PASS}.")

  print(f"\nVERDICT: {PASS if not fails else FAIL} -- {len(cases)} arm(s) run, {fails} failed; "
        f"the census names line {rows[0]['at']} of {WITNESS}")
  return EXITS[FAIL if fails else PASS]


if __name__ == "__main__":
  sys.exit(main())