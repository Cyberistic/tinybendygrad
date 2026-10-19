#!/usr/bin/env python3
"""todopop-gate.py -- the gate on the POPULATION: do two instruments mean the same row, and does
a row count a line or a token?

    .venv/bin/python gates/todopop-gate.py             # five lanes
    .venv/bin/python gates/todopop-gate.py --numbers   # every unit, differently NAMED, side by side

WHY THIS GATE EXISTS. Two good instruments reported the same population as 916 and 933 and both
were right. `todo-census.py` declares its unit in its own docstring -- "one SITE = one line of one
.bend file containing the token TODO" -- and, MEASURED on 2026-10-19, running it prints 916 while
`rg` over the same tree at another minute counted 933. Two numbers, one definition, and the only
thing that separated them was WHEN. Lane 3 exists because of that: a reading of a tree that is
being edited is a reading of a moving subject, and the only way to say so is to hash the subject
before and after and refuse when the two disagree.

LANE 1 DECLARED-IN-BOTH. The unit is declared in TWO files -- `gates/todopop-unit.py` (the shared
declaration, loaded by path) and `todo-census.py`'s own `SITE = re.compile(...)`. This lane reads the
second out of its AST and compares the pattern strings. It is the structural half of "they share one
declaration": neither file can change its token without this going red, and nothing here is a
document that can drift. `todo-census.py` is NOT edited to import the declaration -- it must not be
-- so the link is a comparison the gate performs rather than an import it relies on.

LANE 2 AGREEMENT. Run the committed census as a subprocess and compare its emitted row SET with the
rows the shared declaration derives from the same bytes. Equal sets and equal counts is the claim
"one population"; a set difference is reported as the rows themselves, because a count that differs
without the differing rows named is the `208-vs-207` shape.

LANES 4 AND 5 PLANT AND CONTROL, AND WHY THE CONTROL IS THE POINT. The whole question "is a row a
line or a token" is answered by putting TWO tokens on ONE line. Lane 4 plants exactly that and
requires the row count to move by 1 while the token count moves by 2. Lane 5 plants the near-miss
`TODOs`, which the word boundary refuses, and requires 0. A plant with no control proves nothing,
because a unit that counted nothing at all would satisfy "the count did not change"; the two
deltas are required to DIFFER, so neither lane can pass vacuously.

WHAT THIS GATE DOES NOT CLAIM. It does not claim a task count, and `--numbers` reports no task
count: "929 TODOs" and "916 TODOs" are the same conflation from opposite ends. It does not claim the
census's classes are right -- it compares row identity and count only. It runs no `bend`, and it
writes only inside a temporary copy of the subject.
"""
import argparse
import ast
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED  # noqa: E402  -- the five verdicts, one vocabulary

# THE DECLARATION, LOADED BY PATH. The hyphen in the filename is why `import` cannot be used.
import importlib.util  # noqa: E402


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


UNIT = _load(HERE / "todopop-unit.py", "todopop_unit")
CENSUS = HERE / "todo-census.py"
SUBJECT = REPO / "tinybendygrad"
PY = REPO / ".venv" / "bin" / "python"

ROWLINE = re.compile(r"^\S+\s+(\S+):(\d+)\s")
SITES = re.compile(r"^\s*SITES \(the unit\)\s*:\s*(\d+)", re.M)
PLANT_A = "# TODO(p3) probe A TODO(p3) probe B"
PLANT_B = "# TODOs are plural in prose and are not a site"


def census_rows(root):
    """The committed instrument, run, parsed. `(rows, sites, rc, stderr)`; `sites` is None if absent.

    The census is run as a SUBPROCESS on purpose. Reimplementing its row rule inside this file
    would make lane 2 a comparison of this file with itself, which is the `differ.py` shape that
    produced 916-vs-933 in the first place.
    """
    proc = subprocess.run([str(PY), str(CENSUS), "--rows", "--root", str(root)],
                          capture_output=True, text=True)
    rows, seen, in_table = [], None, True
    for line in proc.stdout.splitlines():
        found = SITES.match(line)
        if found:
            seen = int(found.group(1))
        if line.startswith("UNIT:"):
            in_table = False  # the summary follows the table; keep scanning it for SITES
            continue
        match = ROWLINE.match(line) if in_table else None
        if match:
            rows.append((match.group(1), int(match.group(2))))
    return rows, seen, proc.returncode, proc.stderr


def census_token():
    """`todo-census.py`'s own `SITE` pattern, read out of its AST rather than its prose."""
    tree = ast.parse(CENSUS.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if (isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == "SITE" for t in node.targets)
                and isinstance(node.value, ast.Call)
                and isinstance(node.value.func, ast.Attribute)
                and node.value.func.attr == "compile"
                and node.value.args
                and isinstance(node.value.args[0], ast.Constant)):
            return node.value.args[0].value
    return None


def append_line(path, text):
    """Append `text` and return its 1-based line number in the file as written."""
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("\n" + text + "\n")
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    return next(i for i, line in enumerate(lines, 1) if line == text)


def reach(target):
    """Prove the unit can produce EXACTLY `target` rows, on a copy, and print the census saying so.

    This is how "933 and 916 are the same unit" stops being an inference. A number that is an
    OUTPUT of the unit cannot be evidence of a different unit: reach any N by planting whole lines,
    and every reading either lands inside the range the unit spans or came from somewhere else.
    `target` is an ARGUMENT, so nothing here is a transcribed expected value.
    """
    with tempfile.TemporaryDirectory(prefix="todopop-reach-") as tmp:
        copy = Path(tmp) / "subject"
        shutil.copytree(SUBJECT, copy)
        rows_now = census_rows(str(copy))[0]
        step = target - len(rows_now)
        sink = max(UNIT.walk(str(copy)), key=lambda p: len(UNIT.rows([p], str(REPO), str(copy))))
        if step > 0:
            for i in range(step):
                append_line(sink, f"# TODO(p3) reach plant {i}")
        else:
            keep = [n for _, n in UNIT.rows([sink], str(REPO), str(copy))][::-1][: -step]
            lines = open(sink, encoding="utf-8", errors="replace").read().splitlines(True)
            with open(sink, "w", encoding="utf-8") as handle:
                handle.writelines(line for n, line in enumerate(lines, 1) if n not in keep)
        got, sites, rc, err = census_rows(str(copy))
        paths = UNIT.walk(str(copy))
        print(f"reach {target}: census SITES={sites} rows={len(got)} declaration rows="
              f"{len(UNIT.rows(paths, str(REPO), str(copy)))} rc={rc} "
              f"digest={UNIT.digest(paths, str(REPO))[:16]} stamp={UNIT.stamp()}"
              + (f" err={err.strip()[:120]}" if err.strip() else ""))
        return PASS if sites == target == len(got) else FAIL


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--numbers", action="store_true",
                    help="print every unit under its OWN NAME and exit without the lanes")
    ap.add_argument("--reach", type=int, metavar="N",
                    help="prove the unit can produce exactly N rows, on a copy, by planting lines")
    args = ap.parse_args()

    if not SUBJECT.is_dir() or not CENSUS.is_file() or not PY.is_file():
        # An absent precondition is a REFUSAL, never a crash. `todopop-falsify.py` found this the
        # hard way: the gate raised FileNotFoundError and exited 1, and 1 is also FAIL, so a missing
        # interpreter and a real disagreement were the same number to a reader of `$?`.
        print(f"REFUSED: a precondition is absent: subject={SUBJECT.is_dir()} "
              f"census={CENSUS.is_file()} python={PY.is_file()}", file=sys.stderr)
        return REFUSED

    paths = UNIT.walk(str(SUBJECT))

    if args.numbers:
        # EVERY UNIT, DIFFERENTLY NAMED. Four questions, four names; no two of them is "the" count.
        print(UNIT.unit())
        print(f"stamp            : {UNIT.stamp()}")
        print(f"subject digest   : {UNIT.digest(paths, str(REPO))}")
        print(f"  .bend files         ROWS-POPULATION size      {len(paths):5d}")
        print(f"  lines with \\bTODO\\b  ROWS (todo-census SITES) {len(UNIT.rows(paths, str(REPO), str(SUBJECT))):5d}")
        print(f"  \\bTODO\\b tokens       TOKEN-OCCURRENCES        {UNIT.tokens(paths):5d}")
        print(f"  lines with TODO     NEAR-MISS-LINES           {UNIT.substring_rows(paths):5d}")
        print(f"  files with >=1      ROWS-FILES                "
              f"{len({p for p, _ in UNIT.rows(paths, str(REPO), str(SUBJECT))}):5d}")
        return PASS

    if args.reach is not None:
        return reach(args.reach)

    failures = []

    # LANE 1. The token is declared in both files; the ASTs are the witness, not the prose.
    pattern = census_token()
    if pattern != UNIT.TOKEN.pattern:
        failures.append(f"LANE1 DECLARED-IN-BOTH: census SITE={pattern!r} unit TOKEN={UNIT.TOKEN.pattern!r}")
    else:
        print(f"LANE1 DECLARED-IN-BOTH PASS  both declare the token {pattern!r} (AST of todo-census.py:62)")

    # LANE 3 first, so the reading lane below is bracketed by the two digests it must match.
    before = UNIT.digest(paths, str(REPO))

    # LANE 2. The census's own rows against the declaration's rows on the same bytes.
    census, sites, rc, err = census_rows(str(SUBJECT))
    mine = UNIT.rows(paths, str(REPO), str(SUBJECT))
    if rc != 0 or not census or sites is None:
        print(f"LANE2 AGREEMENT DEAD rc={rc} rows={len(census)} sites={sites} err={err.strip()[:200]}")
        return DEAD
    if census != mine or sites != len(mine):
        only_census, only_mine = sorted(set(census) - set(mine)), sorted(set(mine) - set(census))
        failures.append(f"LANE2 AGREEMENT: census {sites} rows, declaration {len(mine)}; "
                        f"census-only {only_census[:5]} declaration-only {only_mine[:5]}")
    else:
        print(f"LANE2 AGREEMENT PASS  census SITES={sites} == declaration rows={len(mine)}, "
              f"same {len(census)} rows in the same order")

    # LANE 3. A reading of a tree being edited is a reading of a MOVING subject.
    after = UNIT.digest(UNIT.walk(str(SUBJECT)), str(REPO))
    print(f"LANE3 SUBJECT-PIN  digest {before[:16]} -> {after[:16]} "
          f"({'stable' if before == after else 'MOVED UNDER THE RUN'}) stamp {UNIT.stamp()}")
    if before != after:
        print("REFUSED: the subject changed while it was being measured; this reading is of two "
              "subjects and is not a fact about either")
        return REFUSED

    # LANES 4 AND 5. One copy, two plants, and each number measured TWICE -- once by the census and
    # once by the shared declaration. Measuring only the census would leave the declaration free to
    # be wrong here, and `todopop-falsify.py`'s ONE-ROW-PER-FILE break did exactly that: lane 2
    # caught it, and the plant did not notice. A plant that cannot see the thing it plants into is
    # a decoration.
    with tempfile.TemporaryDirectory(prefix="todopop-") as tmp:
        copy = Path(tmp) / "subject"
        shutil.copytree(SUBJECT, copy)

        def measure():
            paths = UNIT.walk(str(copy))
            return (census_rows(str(copy))[0], UNIT.rows(paths, str(REPO), str(copy)),
                    UNIT.tokens(paths), paths)

        base_census, base_decl, base_tok, base_paths = measure()

        target = next((p for p in base_paths if UNIT.rows([p], str(REPO), str(copy))), None)
        if target is None:
            # No file in the subject carries a row, so the plant has nothing to land on. That is
            # an absent precondition, not a crash: `next()` without a default raised StopIteration
            # and exited 1, which is also FAIL.
            print(f"REFUSED: no subject file carries a row; the plant has no target "
                  f"({len(base_paths)} files walked)")
            return REFUSED
        line_a = append_line(target, PLANT_A)
        a_census, a_decl, a_tok, _ = measure()
        planted = [(k, n) for k, n in a_census if n == line_a and k.endswith(os.path.basename(target))]

        line_b = append_line(target, PLANT_B)
        ab_census, ab_decl, ab_tok, _ = measure()
        # The control is checked at ITS OWN LINE, not only in the total: a count that did not move
        # is also what a unit that counted something else produces, so name the line and ask.
        unplanted = [(k, n) for k, n in ab_census if n == line_b and k.endswith(os.path.basename(target))]

        d_census = len(a_census) - len(base_census)
        d_decl = len(a_decl) - len(base_decl)
        d_tok = a_tok - base_tok
        c_census = len(ab_census) - len(a_census)
        c_decl = len(ab_decl) - len(a_decl)
        c_tok = ab_tok - a_tok
        print(f"LANE4 PLANT       2 tokens on 1 line -> rows census {len(base_census)}+{d_census} "
              f"declaration {len(base_decl)}+{d_decl}, tokens {base_tok}+{d_tok}; "
              f"{len(planted)} row at {os.path.basename(target)}:{line_a}")
        print(f"LANE5 CONTROL     near-miss 'TODOs' -> rows census +{c_census} declaration +{c_decl}, "
              f"tokens +{c_tok}; {len(unplanted)} rows at {os.path.basename(target)}:{line_b}")
        if not (d_census == d_decl == 1 and d_tok == 2 and len(planted) == 1):
            failures.append(f"LANE4 PLANT: census rows+{d_census} declaration rows+{d_decl} "
                            f"(want 1 and 1), tokens+{d_tok} (want 2), rows at the planted line "
                            f"{len(planted)} (want 1)")
        if not (c_census == c_decl == c_tok == 0 and not unplanted):
            failures.append(f"LANE5 CONTROL: census rows+{c_census} declaration rows+{c_decl} "
                            f"tokens+{c_tok} (want 0, 0, 0), rows at the control line {len(unplanted)} "
                            f"(want 0)")
        # NON-VACUITY. The plant and the control must move the count DIFFERENTLY, or a unit that
        # moves nothing satisfies both and neither lane has said anything.
        for who, plant, control in (("census", d_census, c_census), ("declaration", d_decl, c_decl)):
            if plant == control:
                failures.append(f"LANE4/LANE5 VACUOUS ({who}): plant and control both moved the count "
                                f"by {plant}; a unit that counts nothing passes both")

    if failures:
        for line in failures:
            print("FAIL " + line)
        return FAIL
    print("todopop-gate PASS -- one row per line under \\bTODO\\b, agreed by the census and the "
          "shared declaration on a pinned subject; a row is a LINE and a token is not")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
