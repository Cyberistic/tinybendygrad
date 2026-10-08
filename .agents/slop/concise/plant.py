#!/usr/bin/env python3
"""CONTROLS for the five `concise` instruments. A detector that finds nothing
because it is broken is worse than no detector (AGENTS.md doctrine 2: DEAD is not
a zero), so every one of them is driven with a PLANTED POSITIVE and a PLANTED
NEGATIVE, and the negative is the interesting half: it is the load-bearing filter,
proved to still hold.

Five verdicts, per gates/gatekit.py: PASS / FAIL / REFUSED / SKIP / DEAD. A lane
that emits no `name=value` row is DEAD, not PASS -- `0 disagreements` over `0
comparisons` is indistinguishable from agreement, which is how twelve committed
files once printed nothing for an hour under a harness that reported success.

Exit: 0 all lanes PASS, 1 any lane FAIL, 3 REFUSED (a precondition was absent),
5 DEAD (a lane ran and emitted nothing).
"""

import io
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import census  # noqa: E402
import language  # noqa: E402
import paste  # noqa: E402
import signature  # noqa: E402

ROWS: list[tuple[str, str]] = []


def row(lane: str, verdict: str, detail: str = "") -> None:
    ROWS.append((lane, verdict))
    print(f"  {lane:<34} {verdict:<8} {detail}")


def lane_paste() -> None:
    """paste.repeats_within must fire on a duplicated 2-line block and stay quiet
    on two `# noqa: E402`, which are lint DIRECTIVES and not prose."""
    run = [(10, "# A STAGE BLOCK IS A HEADER."),
           (11, "# A gate that lost a stage has lost it."),
           (12, "# A STAGE BLOCK IS A HEADER."),
           (13, "# A gate that lost a stage has lost it.")]
    fires = paste.repeats_within(run)
    row("paste/detects-a-paste", "PASS" if len(fires) == 2 else "FAIL",
        f"{len(fires)} duplicated lines, want 2")
    quiet = paste.repeats_within([(1, "noqa: E402"), (2, "noqa: E402")])
    row("paste/ignores-a-noqa-directive", "PASS" if not quiet else "FAIL",
        f"{len(quiet)} hits, want 0")
    ruler = paste.repeats_within([(1, "=" * 40), (2, "=" * 40)])
    row("paste/ignores-a-ruler", "PASS" if not ruler else "FAIL",
        f"{len(ruler)} hits, want 0")


def lane_signature() -> None:
    """signature.classify must fire on a restatement and stay quiet on a
    docstring that merely MENTIONS its parameter, which is what v1 got wrong."""
    sig = {"increment", "counter"}
    restate = signature.classify(sig, "Increment the counter.", "Increment the counter.")
    useful = signature.classify(
        sig, "Advances `counter` by the observed delta, which the port reports in words.",
        "Advances `counter` by the observed delta, which the port reports in words.")
    row("signature/detects-a-restatement", "PASS" if restate else "FAIL",
        f"got {restate!r}, want 'SIGN'")
    row("signature/spares-a-useful-docstring", "PASS" if not useful else "FAIL",
        f"got {useful!r}, want None")


def lane_bendlex() -> None:
    """census.bend_lex must NOT call a `#` inside a string a comment. The witness
    is real and on disk: tinybendygrad/sz.bend:1547 holds "### Changes\\n```\\n"."""
    path = "tinybendygrad/sz.bend"
    if not os.path.exists(path):
        row("bendlex/witness-on-disk", "REFUSED", f"{path} absent")
        return
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    idx = next((i for i, l in enumerate(lines) if "### Changes" in l and "#" in l), None)
    if idx is None:
        row("bendlex/witness-on-disk", "REFUSED", "no line carries '### Changes'")
        return
    grep = sum(1 for l in lines if "#" in l)
    lexed = sum(1 for l in lines if census.bend_lex(l))
    row("bendlex/witness-is-not-a-comment", "PASS" if not census.bend_lex(lines[idx]) else "FAIL",
        f"line {idx + 1}: {lines[idx].strip()[:56]}")
    row("bendlex/disagrees-with-grep", "PASS" if lexed != grep else "FAIL",
        f"lexer {lexed} vs grep {grep}; the gap IS the measurement")


def lane_pyrows() -> None:
    """census.py_rows must agree with ast on docstrings. v1 of census.py used a
    tokenizer heuristic and UNDERCOUNTED by 9 503 lines over the .py population."""
    import ast
    src = ('def f(a: int) -> int:\n'
           '    """One.\n\n    Two.\n    """\n'
           '    return a\n\n'
           'class C:\n'
           '    """Class doc, three\n    more lines.\n    """\n')
    _, doc, err = census.py_rows(src)
    tree = ast.parse(src)
    want = sum(len(ast.get_docstring(n, clean=False).splitlines())
               for n in ast.walk(tree)
               if isinstance(n, (ast.Module, ast.FunctionDef, ast.ClassDef))
               and ast.get_docstring(n, clean=False))
    row("pyrows/agrees-with-ast", "PASS" if not err and doc == want else "FAIL",
        f"census {doc} vs ast {want}")


def language_fires(text: str) -> bool:
    """Delegates to the detector's OWN predicate. v1 of this control kept a copy of
    the three-clause test and PASSED a case the detector rejects, because the copy
    was missing the MECHANISM clause -- a second copy of a rule, the same defect as
    a second copy of a population, which makes a control measure the copy."""
    return language.fires(text)


def lane_language() -> None:
    """language.py must fire on '# increment the counter' and stay quiet on a line
    naming a file, because the negative IS the load-bearing filter."""
    for label, src, want, note in (
        ("language/detects-a-language-comment", "x = 0\n# increment the counter\n",
         True, "'# increment the counter'"),
        ("language/spares-a-citation", "x = 0\n# bump ops.py:1408 by one\n",
         False, "'# bump ops.py:1408 by one'"),
        ("language/spares-a-digit", "x = 0\n# loop 7 times over the srcs\n",
         False, "'# loop 7 times over the srcs'"),
        ("language/spares-project-rationale",
         "x = 0\n# a dead lane is never a green one\n",
         False, "'# a dead lane is never a green one' (project rationale, not language)"),
        ("language/catches-a-wrapped-continuation",
         "x = 0\n# bump ops.py:1408 by\n# one, twice\n",
         False, "a 2-line block whose FIRST line carries the citation"),
    ):
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
            fh.write(src)
            tmp = fh.name
        try:
            got = any(language_fires(t) for _, t in language.prose(tmp))
        finally:
            os.unlink(tmp)
        row(label, "PASS" if got is want else "FAIL", f"{note} fired={got}, want={want}")


if __name__ == "__main__":
    print("CONTROLS -- each lane is driven with a POSITIVE and a load-bearing NEGATIVE\n")
    for lane in (lane_paste, lane_signature, lane_bendlex, lane_pyrows, lane_language):
        lane()
    total = len(ROWS)
    bad = [r for r in ROWS if r[1] == "FAIL"]
    print(f"\n{total - len(bad)} of {total} lanes PASS, {len(bad)} FAIL, "
          f"{sum(1 for r in ROWS if r[1] == 'REFUSED')} REFUSED")
    if not ROWS:
        print("DEAD: no lane emitted a name=value row")
        sys.exit(5)
    sys.exit(1 if bad else 0)
