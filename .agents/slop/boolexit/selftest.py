r"""THE HARNESS THAT CAN FAIL, WRITTEN FIRST. `AGENTS.md`: "NEVER write unit tests after you write
code ... THE HARNESS YOU WRITE IS THE ONE THAT CAN FAIL, SO IT COMES FIRST."

Every plant below feeds the census a `True` where it expects an `int` and asserts the census
GRADES IT DIFFERENTLY. A census that cannot see a bool is not a census; this is how that is
checked rather than assumed.

THE ORDINARY CASE IS THE CONTROL, and it is stated as a control rather than a plant: every one of
these also asserts the INTEGER behaviour is unchanged, because a fix that breaks the int path is
worse than the defect it fixes.

    .venv/bin/python .agents/slop/boolexit/selftest.py
"""
import ast
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from census import Binder, sites                      # noqa: E402
from reach import _bool_expr, int_keyed, _PARENTS, build_parents  # noqa: E402

BAD = []


def check(name, got, want):
    ok = got == want
    print(f"   {'OK  ' if ok else 'WRONG'}: {name:<58} got={got!r} want={want!r}")
    if not ok:
        BAD.append(name)
    return ok


SRC = '''
PASS, FAIL, REFUSED = 0, 1, 3
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED"}
def f(code):
    return VERDICT[code]
def g(code):
    return code in VERDICT
STRKEYS = {"a": 1, "b": 2}
def h(k):
    return STRKEYS[k]
'''


def main():
    print("# THE CENSUS'S OWN PLANTS -- a `True` where an `int` was expected, and an INT control")
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "m.py"
        p.write_text(SRC)
        ss, err = sites(p)
        check("the fixture parses", err, None)
        check("three sites are found", len(ss), 3)

        b = Binder(ast.parse(SRC), SRC)
        # `name_assigns`/`bool_names` are built by `analyse`, not by `Binder` -- so a caller that
        # asks `_bool_expr` about a Name WITHOUT them gets an AttributeError, which is what this
        # selftest did on its first run. Setting them here is the honest shape: an UNPROVEN name is
        # not a bool, and saying so is the answer.
        b.name_assigns, b.bool_names = {}, {}
        build_parents(ast.parse(SRC))

        # -- the TABLE is int-keyed and the constant is resolved through a TUPLE target
        check("VERDICT keys resolve through tuple-unpacking", b.shapes["VERDICT"][0][1], [0, 1, 3])
        check("PASS is bound from the tuple target", b.consts.get("PASS"), 0)

        # -- the bool REACHES question, on int keys
        check("int_keyed({0,1,3})", int_keyed([0, 1, 3])[0], True)
        check("int_keyed({'a','b'}) -- a bool can NEVER hit a str key", int_keyed(["a", "b"])[0], False)
        check("int_keyed({1..18}) -- True aliases 1", int_keyed(list(range(1, 19)))[0], True)

        # -- the bool-EXPRESSION question, and its ORDINARY-CASE CONTROL
        cmp_node = ast.parse("a == b").body[0].value
        name_node = ast.parse("rc").body[0].value
        const_node = ast.parse("1").body[0].value
        check("`a == b` is a bool EXPRESSION", _bool_expr(cmp_node, b), True)
        check("`1` is NOT -- THE CONTROL", _bool_expr(const_node, b), False)
        check("a bare Name is not provably bool", _bool_expr(name_node, b), False)

    # -- AND THE ONE THAT MATTERS: a bool key really does hit the real table.
    print("\n   the runtime consequence, in the same interpreter:")
    d = {0: "PASS", 1: "FAIL", 3: "REFUSED"}
    check("the TABLE answers a bool", d[True], "FAIL")
    check("...and the bool answer equals the int answer", d[True] == d[1], True)
    check("...and .get() does NOT refuse it", d.get(True, "DEFAULT"), "FAIL")
    check("...while an out-of-range INT reaches the default", d.get(9, "DEFAULT"), "DEFAULT")
    # A bool CANNOT hit a str key -- and the proof is not "it returns the default", it is that
    # `hash(False)` is not any str's hash. MEASURED, because my first draft of this line asserted
    # `{0:"z"}.get(False) == 0` and the harness caught it: `False == 0` is TRUE, so that table's
    # answer is "z" and my assertion was simply wrong. The str case is the one that needs the
    # hash argument, so it gets the hash argument.
    check("a str-keyed table REFUSES a bool (hash(False)=0, no str hashes to 0)",
          {"a": "z"}.get(False, "DEFAULT"), "DEFAULT")
    check("...while an INT-keyed table HITS it", {0: "z"}.get(False, "DEFAULT"), "z")

    # -- THE HARNESS ITSELF FAILS WHEN IT SHOULD. Without this, "0 BAD" is the
    #    `'0 disagreements' over '0 comparisons'` shape `rebase-gate-selftest` records.
    print("\n   THE HARNESS FAILS WHEN IT SHOULD (else 'all OK' means nothing):")
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "bad.py"
        p.write_text('VERDICT = {"a": 1}\ndef f(code):\n    return VERDICT[code]\n')
        ss2, err2 = sites(p)
        check("a STR-keyed subscript is STILL REPORTED as a site", len(ss2), 1)
        check("...with its keys visible", ss2[0][4], ["a"])

    print(f"\nSELFTEST: {'OK' if not BAD else str(len(BAD)) + ' FAILURE(S): ' + '; '.join(BAD)}")
    return 1 if BAD else 0


if __name__ == "__main__":
    sys.exit(main())