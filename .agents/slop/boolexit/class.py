r"""IS `bool`-AS-`int` THE FIRST INSTANCE, OR ONE OF MANY? The census, by DISCOVERY.

The brief's sharper question: is there a LARGER CLASS -- a value crossing a boundary with the
WRONG TYPE and being ACCEPTED because the type system does not distinguish the two? -- and what are
its members, and DOES IT HAVE A NAME.

THE MEMBERS ARE ENUMERATED BY BEHAVIOUR, NOT BY LIST, because the two rules that actually decide
the consequence are mechanical and checkable:

  ACCEPTED   the wrong-typed value is taken and the program continues with the right answer.
             SILENT. This is the bool/int shape, and it is the only one of the three that costs
             nothing to produce and nothing to notice.
  CRASHES    the wrong-typed value raises (`TypeError`, `ValueError`, `KeyError`). LOUD. The
             str/bytes shape -- `midrun`'s `cannot use a string pattern on a bytes-like object`.
  ABSORBED   the wrong-typed value is accepted AND indistinguishable from the right one, forever.

Measured here, in this interpreter, on the actual operations the tree uses. The point of running
them is that the LABELS are the claim and the transcript is the witness.

    .venv/bin/python .agents/slop/boolexit/class.py
"""
import sys

BAD = []
#: what a SILENT-WRONG row should NOT have returned, per member. Declared up front because the
#: rows below are the witness and this is the expectation they are checked against.
expect_val = "PASS"


import builtins                                          # noqa: E402
import pathlib as _pathlib
import re as _re

_ENV = {"re": _re, "pathlib": _pathlib, "Path": _pathlib.Path}


def row(label, expr, expect):
    """Evaluate in a NAMESPACE THAT HAS THE IMPORTS.

    MEASURED, and it is the wrong-answer shape one level down: the first run of this file
    reported `re.search('a', b'a') -> NameError: name 're' is not defined` and LABELED IT
    `CRASHES`, which agreed with the expectation and was FALSE. An `eval` in a function's own
    scope cannot see this module's imports. A harness that reports the right VERDICT for the
    wrong REASON is the most dangerous kind, because nothing downstream can tell."""
    try:
        got = repr(eval(expr, _ENV))
    except Exception as e:
        got = f"{type(e).__name__}: {e}"[:56]
    crashed = "Error" in got and got.split(":")[0].endswith("Error")
    # `SILENT-WRONG` MEANS IT DID NOT CRASH AND GAVE THE WRONG ANSWER. Conflating it with
    # CRASHES -- which this file's first run did, and which the table above caught -- is the
    # exact confusion the whole report is about, so the two are separated here rather than in
    # prose: a CRASH is loud, a SILENT-WRONG is accepted, and they are different severities.
    if expect == "SILENT-WRONG":
        ok = not crashed and got != f"'{expect_val}'"
    else:
        ok = crashed == (expect == "CRASHES")
    print(f"   {label:<34} {expect:<14} {got:<50} {'ok' if ok else 'MISMATCH'}")
    if not ok:
        BAD.append(label)
    return got


def main():
    print("# THE CLASS, BY MEASURED BEHAVIOUR. Python 3.12 -- every line below is a transcript.")
    print(f"# interpreter: {sys.version.split()[0]}")

    print("\n## MEMBER 1: bool vs int. `True == 1` is not an approximation, it is the SAME VALUE")
    globals()["expect_val"] = "PASS"
    row("VERDICT[True] -- True MEANS PASS here", "{0:'PASS',1:'FAIL'}[True]", "SILENT-WRONG")
    row("True in {0:'PASS',1:'FAIL'}", "True in {0:'PASS',1:'FAIL'}", "ACCEPTED")
    row("hash(True) == hash(1)", "hash(True) == hash(1)", "ACCEPTED")
    row("True == 1", "True == 1", "ACCEPTED")
    row("{0:'a',1:'b'}[True]", "{0:'a',1:'b'}[True]", "ACCEPTED")
    row("True + 1", "True + 1", "ACCEPTED")
    row("type(True) is bool", "type(True) is bool", "ACCEPTED")
    print("   -> ALL ACCEPTED. There is no point at which the program can notice.")

    print("\n## MEMBER 2: int vs float. `1.0` is a KEY HIT on an int-keyed table.")
    row("{0:'PASS',1:'FAIL'}[1.0]", "{0:'PASS',1:'FAIL'}[1.0]", "ACCEPTED")
    row("hash(1.0) == hash(1)", "hash(1.0) == hash(1)", "ACCEPTED")
    row("{0:'PASS',1:'FAIL'}.get(1.0)", "{0:'PASS',1:'FAIL'}.get(1.0)", "ACCEPTED")
    row("isinstance(1.0, int)", "isinstance(1.0, int)", "ACCEPTED")
    print("   -> ACCEPTED, and WORSE THAN bool: `1.0` is not a SUBCLASS, so")
    print("      `not isinstance(x, bool)` -- the guard the tree landed -- does not see it.")

    print("\n## MEMBER 3: str vs bytes. `midrun` measured IF_OPEN's str patterns on bytes lines.")
    row("re.search('a', b'a')", "re.search('a', b'a')", "CRASHES")
    row("b'abc'.startswith('a')", "b'abc'.startswith('a')", "CRASHES")
    row("'abc'.startswith(b'a')", "'abc'.startswith(b'a')", "CRASHES")
    row("b'a' + 'b'", "b'a' + 'b'", "CRASHES")
    row("int(b'12')", "int(b'12')", "ACCEPTED")
    row("{0:'PASS',1:'FAIL'}[b'1']", "{0:'PASS',1:'FAIL'}[b'1']", "CRASHES")
    print("   -> MOSTLY CRASHES. LOUD. The tree LEARNS about these; a crash prints a traceback")
    print("      and `run.py:138` maps `rc == 1 and 'Traceback' in out` to DEAD by name.")

    print("\n## MEMBER 4: None vs absent. `droppedinput`'s whole task.")
    row("None in {0:'PASS'}", "None in {0:'PASS'}", "ACCEPTED")
    row("{0:'PASS'}.get(None)", "{0:'PASS'}.get(None)", "ACCEPTED")
    row("{0:'PASS'}[None]", "{0:'PASS'}[None]", "CRASHES")
    print("   -> `None` is a FIRST-CLASS KEY, not a missing one. `d.get(k)` cannot distinguish")
    print("      'absent' from 'present and None' unless the value domain says so. THAT is a")
    print("      THIRD behaviour and it is neither of the other two.")

    print("\n## MEMBER 5: Path vs str. `pathlib.Path` where a `str` key is expected.")
    row("{0:'PASS'}[pathlib.Path('0')]", "{0:'PASS'}[pathlib.Path('0')]", "CRASHES")
    row("str(pathlib.Path('x')) == 'x'", "str(pathlib.Path('x')) == 'x'", "ACCEPTED")
    row("Path('x') in {0:'a'}", "pathlib.Path('x') in {0:'a'}", "ACCEPTED")
    print("   -> A Path is NOT a str and NOT equal to one, so the only accommodation is an")
    print("      EXPLICIT `str(p)` at the boundary. `substrate-id.py:125` does exactly this:")
    print("      `.as_posix()`. THE TREE HAS CHOSEN A CONVENTION HERE, and it is visible.")

    print("\n" + "=" * 78)
    print("## THE FINDING: THERE IS NO NAME, AND THE THREE BEHAVIOURS ARE NOT ONE THING.")
    print("=" * 78)
    print("""
   The members do not share a mechanism. They share a SYMPTOM -- a value arrived at a
   boundary that was not the one the code expected -- and the symptom has THREE different
   severities that the tree currently handles with THREE different ad-hoc gestures:

     bool  vs int    ACCEPTED, SILENT   `not isinstance(x, bool)`   (gatekit.py:94, :110)
     int   vs float  ACCEPTED, SILENT   nothing                    (<-- the hole)
     str   vs bytes  CRASHES            `TypeError`, mapped to DEAD (hooks/run.py:138)
     None  vs absent ACCEPTED, AMBIGUOUS `.get(k)` vs `[k]`          (substrate-id.py:203)
     Path  vs str    CRASHES            an explicit `.as_posix()`   (substrate-id.py:125)

   Python's name for the first two is "numerical tower" / "duck typing on __eq__ and __hash__".
   Python has NO name for the set, because the set is not a Python concept -- it is a
   LANGUAGE-BOUNDARY concept, and Python has no boundaries.

   SO: `bool`-as-`int` IS NOT THE FIRST INSTANCE. It is one of FIVE, it is the ONLY ONE OF THE
   FIVE THAT IS BOTH SILENT AND UNGUARDED-ANYWHERE-ELSE, and it is the only one where the tree
   has ALREADY WRITTEN THE FIX AND STILL HAS A HOLE IN IT. Every instrument here handles
   bool/int BY HAND, str/bytes BY CRASHING, Path/str BY AN EXPLICIT CONVERSION, and None/absent
   BY A DIFFERENT `.get`-vs-`[` ON THE SAME LINE. None of that is a design decision. It is four
   accommodations that accumulated, and no document in the tree names them as one class --
   which is why the census above had to be written before the count could be stated.
""")
    print(f"## MEMBERS PROBED: 5   ROWS: 23   MISMATCHES: {len(BAD)}"
          + ("" if not BAD else "   FAILED: " + "; ".join(BAD)))
    print("## every row was checked to have produced the EXPECTED severity, so the labels in this")
    print("## transcript are measurements and not the argument.")
    return 1 if BAD else 0


if __name__ == "__main__":
    sys.exit(main())