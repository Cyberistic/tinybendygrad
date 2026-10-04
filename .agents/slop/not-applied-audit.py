#!/usr/bin/env python3
"""not-applied-audit.py -- RULE D, asserted over EVERY stale-anchor branch in this
directory.  It is the check that could not have been fooled the way
`ops-python-mutate.py:106` was fooled.

THE FAILURE THIS EXISTS TO CATCH.  For two days one harness printed `0` when its
anchor was stale, and twenty-seven neighbours printed eleven other things.  The
number nobody had was the census: what does each of them print?  It could not be
got by grepping, because

    if old not in src:          <- grep sees this.  Identical in all 29 files.
        print(...)              <- the MARKER is here, on the next line.

A grep of the `if` line cannot tell you which branch produced a figure, because
the branch produces no figure -- the branch DECIDES what the figure is.  So this
audit reads the branch BODY, via the AST, and asserts four things about it:

  A1 ANTI-DRIFT   the body calls the shared reporter (`patch_not_apply`).  A
                  per-file literal marker is a sixth spelling, and
                  zero-classify.py EXITS on an unrecognised measurement rather
                  than inventing a verdict -- so a drift does not degrade the
                  table, it breaks the classifier.  This is the assertion that
                  makes "one shared reporter" mean something: it is what stops
                  the next author from inlining `'PATCH NOT APPLIED'`.
  A2 NON-NUMERIC  no cell the branch emits parses as an integer.  A bare `0` in
                  a count column is not a refusal, it is a MEASUREMENT, and a
                  reader -- or a `sum()` over the column -- cannot tell them
                  apart.  `hcq2-mutate.py` shipped `0 -- EDIT DID NOT APPLY` in
                  exactly that position and passed every other check here.
  A3 PARITY       a `|`-row this branch builds has the SAME cell count as the
                  normal rows of the table it is joining.  The bad row at
                  `ops-python-mutations.txt:7` had four cells where every other
                  row had three, so any parser reading column 3 as the count read
                  `(pattern not found)` there instead: the cell count moved the
                  figure out from under the reader and nothing failed.  Width is
                  compared against the table's OWN header and its sibling normal
                  prints, both read from this file.
  A4 VOCABULARY   the marker is one of zero-classify.py's five verdicts,
                  QUERIED via its `--verdicts` flag rather than transcribed from
                  its source -- zero-classify.py built that flag so a consumer
                  would not regex a constant, and a self-test that regexes its
                  own tool's constants tests the regex.

It is a RE-PARSE of the harness SOURCES, not a re-run: a re-run mutates the live
tree in three cases and is forbidden.  Nothing here executes a harness.

    usage: not-applied-audit.py [--verbose]
    exits non-zero if any assertion fails.
"""
import ast
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# `--dir D` audits D instead of this file's own directory.  It exists so the audit
# can be pointed at the PRE-FIX sources out of history: an auditor that has only
# ever been shown correct code has not been tested, and this project treats a
# check that cannot fail as harmful rather than reassuring.
AUDIT_DIR = HERE
for _i, _a in enumerate(sys.argv):
    if _a == "--dir" and _i + 1 < len(sys.argv):
        AUDIT_DIR = sys.argv[_i + 1]

# --- DISCOVERY: what a stale-anchor guard looks like --------------------------
# This matches the guard TEST, which is the thing a grep would match and the
# thing that tells you NOTHING.  It is used only to find the branch to then read
# the BODY of.
ANCHOR = re.compile(r'^(old|old_s|find|anchor|a|pat|needle|patn|txt|n)$')
# DISCOVERY IS DELIBERATELY BROAD.  A first version carried a hand-maintained list
# of "names that hold file text" -- `src`, `s`, `base`, `original` -- and that list
# was WRONG in the way hand-maintained lists always are: `cs_mutate.py` reads into
# `orig`, `rf2-mutate.py` into `BASE_SRC`, `debug-mutate.py` into `green`, and all
# three were reported as having no guard at all.  A whitelist of names is a fixture
# list; it is stale the moment someone names a variable `green`.  So the name is
# NOT the test -- the COMPARISON is (`count(...)` against a count that means
# wrong), and the scope filter below decides which branches can actually matter.
# Broad discovery plus a real filter beats narrow discovery plus a hopeful list.
COUNTABLE = re.compile(r'^[a-z_][a-z_0-9]*$')
CALLS = frozenset(("print", "append", "raise", "exit", "write", "fail", "die",
                   "warn", "error"))
CELLS = re.compile(r'(?:^|\|)\s*([^|]*?)\s*(?=\||$)')


def _first_token_is_int(cell):
    """Would a column reader read this cell as a number?

    `int(cell)` is the lenient test and it is the wrong one: it calls
    `0 rows moved` and `PATCH-NOT-APPLY: x | 0` safe by refusing, while the
    reader that actually caused this bug took the first token.
    """
    tok = cell.strip().split()
    return bool(tok) and tok[0].lstrip("+-").isdigit()


def target(node):
    """The name of the thing holding file text, through Subscript/Attribute."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, (ast.Subscript, ast.Attribute)):
        return target(node.value)
    return None


def count_aliases(tree):
    """`n = src.count(find)` then `if n == 0` / `if n != 1` -- n IS a count.

    THE SECOND HALF OF THIS FUNCTION IS THE LESSON.  A first pass matched only
    `count(x) == 0`, found 24 of 30 sites, and called the other six unguarded.
    They were guarded: `if src.count(old) != 1` asks the SAME question -- "is the
    anchor here?" -- as an INEQUALITY, because a two-occurrence anchor is as
    unusable as a zero-occurrence one.  A discovery keyed on the SHAPE of the `if`
    line misses every author who phrased it differently, which is the same
    blindness as grepping the test at all.
    """
    out = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign) and isinstance(n.value, ast.Call) \
           and isinstance(n.value.func, ast.Attribute) and n.value.func.attr == "count" \
           and n.targets and isinstance(n.targets[0], ast.Name) \
           and isinstance(n.value.func.value, ast.Name):
            out[n.targets[0].id] = True
    return out


# A count is WRONG, not only absent, at 0 and at anything above 1.  Both are the
# same defect: the patch did not land where its author meant it to.
COUNT_CMP = frozenset((
    (ast.Eq, 0), (ast.Eq, 1), (ast.NotEq, 0), (ast.NotEq, 1),
    (ast.Gt, -1), (ast.GtE, 0), (ast.GtE, 1), (ast.Lt, 1),
    (ast.LtE, 0), (ast.LtE, 1)))


def _count_is_wrong(node):
    """`TEXT.count(anchor)` compared against a count that means 'wrong'."""
    if not (isinstance(node.left, ast.Call)
            and isinstance(node.left.func, ast.Attribute)
            and node.left.func.attr == "count"
            and isinstance(node.left.func.value, ast.Name)
            and isinstance(node.comparators[0], ast.Constant)):
        return False
    return (type(node.ops[0]), node.comparators[0].value) in COUNT_CMP


def is_stale_anchor(node, alias):
    """Does this test say "the anchor is not in the text I am about to patch"?"""
    if isinstance(node, ast.BoolOp):
        return any(is_stale_anchor(v, alias) for v in node.values)
    if isinstance(node, ast.Compare) and len(node.ops) == 1:
        op = node.ops[0]
        if isinstance(op, ast.NotIn) and isinstance(node.left, ast.Name) \
           and ANCHOR.match(node.left.id) and target(node.comparators[0]):
            return True
        if _count_is_wrong(node):
            return True
        if isinstance(node.left, ast.Call) and isinstance(node.left.func, ast.Attribute) \
           and node.left.func.attr == "count" \
           and isinstance(node.left.func.value, ast.Name):
            return True
        if isinstance(node.left, ast.Name) and node.left.id in alias:
            return True
        if isinstance(node.left, ast.Call) and isinstance(node.left.func, ast.Attribute) \
           and node.left.func.attr == "find" and len(node.left.args) == 2 \
           and target(node.left.args[1]) \
           and ANCHOR.match(target(node.left.args[0]) or ""):
            return True
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not) \
       and isinstance(node.operand, ast.Call) \
       and isinstance(node.operand.func, ast.Attribute) \
       and node.operand.func.attr == "find" and len(node.operand.args) == 2 \
       and target(node.operand.args[1]) \
       and ANCHOR.match(target(node.operand.args[0]) or ""):
        return True
    # `any(src.count(a) != 1 for a, _ in edits)` -- the MULTI-ANCHOR form.  The
    # same question over a list of anchors, and just as invisible to a test-shape
    # matcher as everything else here.
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
       and node.func.id in ("any", "all") and node.args \
       and isinstance(node.args[0], (ast.GeneratorExp, ast.ListComp)):
        g = node.args[0]
        body = ([g.elt] if isinstance(g, ast.ListComp) else []) + \
            [v for comp in g.generators for v in comp.ifs] + \
            [comp.iter for comp in g.generators]
        return any(is_stale_anchor(v, alias) for v in body)
    return False


def is_loud_anchor_assert(node, alias):
    """`assert old in src` -- a guard that ABORTS.  Kept, not converted."""
    return (isinstance(node, ast.Assert) and isinstance(node.test, ast.Compare)
            and isinstance(node.test.ops[0], ast.In)
            and target(node.test.comparators[0])
            and ANCHOR.match(target(node.test.left) or ""))


def emitted(node):
    """Every string this node can put on stdout or into a table row."""
    out = []
    for n in ast.walk(node):
        if isinstance(n, ast.Call):
            fn = n.func
            name = fn.attr if isinstance(fn, ast.Attribute) else getattr(fn, "id", "")
            if name not in CALLS:
                continue
            for a in list(n.args) + [k.value for k in n.keywords]:
                for piece in _strings(a):
                    out.append(piece)
    return out


def _strings(a):
    """The literal text of an argument, with `{expr}` collapsed to one cell.

    An f-string's `{}` is one cell by construction, so collapsing it is what
    makes a cell count comparable between `f'| {a} | {b} |'` and a plain row.
    """
    if isinstance(a, ast.Constant) and isinstance(a.value, str):
        return [a.value]
    if isinstance(a, ast.JoinedStr):
        return ["".join(v.value if isinstance(v, ast.Constant) else "{}"
                        for v in a.values)]
    if isinstance(a, ast.BinOp):
        return _strings(a.left) + _strings(a.right)
    if isinstance(a, (ast.List, ast.Tuple)):
        return [s for e in a.elts for s in _strings(e)]
    return []


def imports_reporter(tree):
    """Does this FILE bind the shared reporter at all?"""
    for n in ast.walk(tree):
        if isinstance(n, ast.Import) and any(a.name == "patch_not_apply" for a in n.names):
            return True
        if isinstance(n, ast.ImportFrom) and (n.module or "") == "patch_not_apply":
            return True
    return False


def reporter_aliases(tree):
    """The names this FILE binds the reporter to (`import patch_not_apply as PNA`
    binds one; a plain `import patch_not_apply` binds the module name)."""
    out = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                if a.name == "patch_not_apply":
                    out.add(a.asname or a.name)
    return out


def calls_reporter(body, bound):
    """Does the branch BODY get its text from the reporter rather than a literal?

    A literal is the drift.  `PNA.not_applied()` cannot spell the marker any way
    the reporter does not, so this is what makes the marker un-driftable rather
    than merely centralised -- the next author has to type the name, and A1 fails
    the moment they inline a string instead.
    """
    for st in body:
        for n in ast.walk(st):
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
               and isinstance(n.func.value, ast.Name) and n.func.value.id in bound:
                return True
    return False


def pipe_rows(node):
    """`(cells, declared_width)` for every `PNA.pipe(...)` this node builds."""
    out = []
    for n in ast.walk(node):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
           and n.func.attr == "pipe" and len(n.args) == 2 \
           and isinstance(n.args[1], ast.Constant):
            out.append((len(n.args[0].elts) if isinstance(n.args[0], (ast.List, ast.Tuple))
                        else -1, n.args[1].value))
    return out


def cells_of(text):
    """The `|`-delimited cells of a row, ignoring the empty ends.

    Counted by SPLITTING, not by scanning for `|` followed by a cell: a scan
    double-counts the row's own leading delimiter and reported every 3-column
    table in this directory as 4 wide -- which made A3 fail on CORRECT code,
    which is how an auditor gets ignored.
    """
    parts = text.split("|")
    return parts[1:-1] if len(parts) > 2 else []


def table_width(scope, exclude=None):
    """The cell counts this table's OTHER rows have, read from the file.

    Every count seen is reported, not one: a table's header, its `| --- |` rule
    and its data rows must agree, and disagreement is itself a finding.  The
    branch under audit is excluded, so the row being checked cannot define the
    width it is checked against.
    """
    counts = []
    for n in ast.walk(scope):
        if n is exclude:
            continue
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
           and n.func.attr == "pipe":
            continue
        if isinstance(n, ast.Call):
            fn = n.func
            name = fn.attr if isinstance(fn, ast.Attribute) else getattr(fn, "id", "")
            if name != "print" or not n.args:
                continue
            for s in _strings(n.args[0]):
                if s.count("|") >= 2:
                    counts.append(len(cells_of(s)))
    return counts


def enclosing_scope(tree, target):
    """The nearest FunctionDef/Module around `target`.

    The width must come from the scope's OTHER rows.  Reading it from the branch
    itself is the bug this replaced: the branch holds one row, so it agreed with
    itself and a 4-cell row in a 3-column table passed A3.  An auditor that
    checks a thing against itself is not a check.
    """
    path = []

    def walk(n):
        if n is target:
            return True
        for c in ast.iter_child_nodes(n):
            if walk(c):
                path.append(n)
                return True
        return False

    walk(tree)
    for n in reversed(path):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Module)):
            return n
    return tree


def scope_emits_a_count(scope, exclude=None):
    """Does this scope publish a COUNT anywhere?

    This is the scope test, and it is what keeps RULE D from sprawling.  RULE D
    exists because a refusal printed where a measurement belongs can be READ as a
    measurement.  A tool that prints no count anywhere -- an oracle, a gate, a
    proof driver, an analyser -- cannot have its refusal misread that way, so
    requiring a marker there would be a uniformity fetish, and it is exactly the
    sort of thing that gets a real finding ignored.  Those sites are still
    LISTED, with whatever they do print, under "out of scope".
    """
    for n in ast.walk(scope):
        if n is exclude:
            continue
        if isinstance(n, ast.Call):
            fn = n.func
            name = fn.attr if isinstance(fn, ast.Attribute) else getattr(fn, "id", "")
            if name not in CALLS:
                continue
            for a in list(n.args) + [k.value for k in n.keywords]:
                for s in _strings(a):
                    if re.search(r'(?<![\w.])len\(', s) or _first_token_is_int(s) \
                       or re.search(r'\|\s*\{?\}?\s*(?:rows?|moved)\b', s) \
                       or re.search(r'\b\d+ rows\b|\b\d+ moved\b', s):
                        return True
    return False


def main():
    verbose = "--verbose" in sys.argv
    verdicts = subprocess.run(
        [sys.executable, os.path.join(HERE, "zero-classify.py"), "--verdicts"],
        capture_output=True, text=True).stdout.split()
    marker = "PATCH-NOT-APPLY"
    W = 78
    print("=" * W)
    print("NOT-APPLIED AUDIT -- RULE D over every stale-anchor branch in .agents/slop")
    print("A1 anti-drift (calls the shared reporter) | A2 non-numeric | A3 column")
    print("parity | A4 marker in zero-classify.py's vocabulary.  Re-parses harness")
    print("SOURCES; it runs no harness, and it never mutates the tree.")
    print("=" * W)
    print("A4  zero-classify.py verdicts: %s" % " ".join(verdicts))
    if marker not in verdicts:
        sys.exit("FAIL A4: %r is not a verdict zero-classify.py can classify." % marker)
    print("    %s IS among them -- one spelling, five verdicts, no sixth." % marker)
    print("-" * W)
    print("%-24s %5s  %-9s %s" % ("HARNESS", "LINE", "SHAPE", "WHAT THE BRANCH EMITS"))
    print("-" * W)

    census, failures, loud, outside = [], [], [], []
    for f in sorted(os.listdir(AUDIT_DIR)):
        # The auditor excludes ITSELF: `is_stale_anchor(...)` inside this file is
        # a call site that mentions the question, not a branch that asks it.
        if not f.endswith(".py") or f == os.path.basename(__file__):
            continue
        path = os.path.join(AUDIT_DIR, f)
        src = open(path, errors="replace").read()
        try:
            tree = ast.parse(src)
        except SyntaxError as e:
            print("%-24s SKIPPED: %s" % (f, e))
            continue
        alias = count_aliases(tree)
        bound = reporter_aliases(tree)
        for n in ast.walk(tree):
            branch = None
            shape = None
            if isinstance(n, ast.If) and is_stale_anchor(n.test, alias):
                branch, shape = n, "stale-anchor"
            elif is_loud_anchor_assert(n, alias):
                branch, shape = n, "LOUD-assert"
            if branch is None:
                continue
            body = branch.body if isinstance(branch, ast.If) else [branch]
            texts = [t for st in body for t in emitted(st)]
            scope = enclosing_scope(tree, branch)
            # A loud abort is REPORTED wherever it is: refusing to write a table is
            # a fact about the harness, not about whether it publishes counts.
            if shape == "LOUD-assert":
                loud.append((f, n.lineno, texts))
                continue
            # RULE D BINDS WHERE A COUNT IS PUBLISHED.  See `scope_emits_a_count`.
            # Out of scope is REPORTED, never dropped: an unlisted site is an
            # unexamined site.
            if not scope_emits_a_count(scope, exclude=branch):
                outside.append((f, n.lineno, next(
                    (t for t in texts if t.strip()), "(no text)")))
                continue
            # A branch whose whole body is `continue` REPORTS NOTHING: it is a
            # search skipping a miss (`tc-audit.py` hunting a needle at a line),
            # not a patch refusing to land.  Demanding a marker there would be
            # demanding one where no figure is produced.
            if isinstance(branch, ast.If) and not texts \
               and all(isinstance(st, ast.Continue) for st in body):
                census.append((f, n.lineno, "search-skip", "n/a, emits nothing", ""))
                continue
            uses_pna = calls_reporter(body, bound)
            # A2 counts a cell as a MEASUREMENT if its FIRST TOKEN parses as an
            # integer -- not if the whole cell does.  `0 -- EDIT DID NOT APPLY`
            # is the sharper case, and it is the one that shipped in
            # `hcq2-mutate.py`: `int(cell)` raises, so a whole-cell test calls it
            # safe, while `int(cell.split()[0])` -- what any real column reader
            # does -- answers 0 and the row reads as a measurement again.
            bad_cells = [(t, c) for t in texts for c in cells_of(t)
                         if _first_token_is_int(c)]
            declared = pipe_rows(branch)
            widths = (table_width(enclosing_scope(tree, branch), exclude=branch)
                      if isinstance(branch, ast.If) else [])
            if shape == "LOUD-assert":
                loud.append((f, n.lineno, texts))
                verdict = "LOUD (kept)"
            elif bad_cells:
                verdict = "A2 DIGIT"
                failures.append((f, n.lineno, "A2", "%r" % (bad_cells[0],)))
            elif not uses_pna:
                verdict = "A1 no-shared"
                failures.append((f, n.lineno, "A1", "branch body does not call the reporter"))
            elif any(w != d for w, d in declared):
                verdict = "A3 width"
                failures.append((f, n.lineno, "A3", "pipe builds %d cells but claims %d"
                                 % (declared[0][0], declared[0][1])))
            elif declared and widths and declared[0][1] not in widths:
                verdict = "A3 width"
                failures.append((f, n.lineno, "A3", "declared %d cells, the table's own "
                                 "rows have %s" % (declared[0][1], sorted(set(widths)))))
            else:
                verdict = "shared"
            shown = next((t for t in texts if marker in t),
                         next((t for t in texts if t.strip()), "(no text)"))
            census.append((f, n.lineno, shape, verdict, shown))
            print("%-24s %5d  %-9s %s" % (f[:24], n.lineno, shape,
                                          ("%s  -> %s" % (verdict, shown))[:70].replace("\n", " ")))
            if verbose:
                for t in texts:
                    print("        emits %r" % t[:100])

    quiet = [c for c in census if c[2] == "stale-anchor"]
    print("-" * W)
    print("THE DENOMINATOR, because a count without one is arithmetic:")
    print("  stale-anchor branches, RULE D scope (a count is published)  : %d" % len(quiet))
    print("  loud aborts on a stale anchor (kept as loud)               : %d  %s"
          % (len(loud), " ".join("%s:%d" % (f, l) for f, l, _ in loud)))
    print("  routed through the one shared reporter                     : %d"
          % sum(1 for c in quiet if c[3] == "shared"))
    print("  files carrying >=1 in-scope branch                        : %d"
          % len({c[0] for c in quiet}))
    print("  stale-anchor branches OUT of scope (no count published)   : %d"
          % len(outside))
    if verbose:
        for f, l, t in outside:
            print("      %-24s %5d  %s" % (f, l, t.replace("\n", " ")[:60]))
    print("-" * W)
    if failures:
        print("FAILURES -- a stale-anchor branch that can read as a measurement:")
        for f, ln, a, why in failures:
            print("  %-24s %5d  %s  %s" % (f, ln, a, why))
        sys.exit(1)
    print("A1/A2/A3 HOLD on all %d in-scope stale-anchor branches." % len(quiet))
    print("A4 holds: the marker is a verdict zero-classify.py classifies, and it is")
    print("QUERIED from that file, not transcribed -- so a rename there fails here.")
    print("=" * W)


if __name__ == "__main__":
    # Guarded so `false-zero-sweep.py` can IMPORT the predicates above rather than
    # re-implement them.  Two copies of "what is a stale-anchor branch" is two
    # answers, and they will disagree -- which is the whole defect.
    main()