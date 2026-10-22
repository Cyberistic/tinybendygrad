#!/usr/bin/env python3
"""gates/edge-reach-census.py -- CAN THE EDGE RUN EVERY GATE THAT CLAIMS IT CAN, AND WHAT CAN IT
REACH AT ALL?

    .venv/bin/python gates/edge-reach-census.py           # the census and the verdict
    .venv/bin/python gates/edge-reach-census.py --plant   # the plant and its control
    .venv/bin/python gates/edge-reach-census.py --root DIR --trace PATH --cost PATH

THE DEFECT THIS EXISTS FOR, MEASURED TWICE INSIDE ONE HOUR ON 2026-10-22. `checks/compile-census.rows`
said `COLD ... gates/crp_graph_census.bend` **1h51m BEFORE** the change that broke that driver
landed, and NOBODY WAS TOLD -- no code opens that file as a verdict. And the opname census was
UNREACHABLE until it declared `EDGE_CANDIDATE = True` and the edge ran it.

**AN INSTRUMENT THAT IS DISCOVERED BUT NOT REACHABLE MEASURES NOTHING**, and the tree's OWN hook
for it already exists: `EDGE_CANDIDATE = True`, read BY PATH the way `RED_IS` is.
`gates/edge-runner.py` runs a gate that declares it and writes the row to `gates/edge-trace.rows`,
beside the MEASURED cost ledger `gates/edge-cost.rows`. **A HAND-WRITTEN ROW IN EITHER LEDGER
WOULD BE A ROW THE RUNNER NEVER PRODUCED** -- the tree's own class of defect -- so the RUNNER
writes both and this file only READS them.

THE TWO ARMS, AND THEY ARE DIFFERENT CLAIMS.

  * **THE CLAIM -- CHARGED.** A gate that declares `EDGE_CANDIDATE = True` is a gate the runner
    CLAIMS to run. No row in the trace means the claim is unkept: the runner says it runs it and
    does not. **A CLAIM THE EDGE CANNOT AFFORD IS THE SAME CLAIM UNKEPT**, and it is charged too.
  * **THE REACH -- COUNTED AND NAMED, NOT CHARGED.** What the edge can reach at all, against the
    whole discovered population. The gates it cannot reach are COUNTED with their denominator and
    NAMED, because the population grows as other units add gates and a growing population is not a
    defect. **A CENSUS THAT ONLY COUNTS THE REACHABLE ONES IS A CENSUS OF THE EASY HALF.**

THE POPULATION IS DISCOVERED, NEVER LISTED. `checks/gatesweep.py:population()` -- the derived gate
homes from `gates/gates-pop.py:gate_homes()` plus `entry_reason()`, walked with `os.walk`. Never a
suffix, never a glob (`AGENTS.md` records `glob('*.bend')` answering `[]` over a tree holding 1,890
tracked lines), never a hand list.

VERDICTS are `gates/gatekit.py`'s, LOADED BY PATH: `PASS 0 . FAIL 1 . REFUSED 3 . SKIP 4 . DEAD 5`.
**SKIP IS NOT PASS** and **DEAD IS NOT A ZERO**: a census over an EMPTY population ran and measured
nothing, so it is DEAD (5); a census whose TRACE IS ABSENT had a precondition absent, so it is
REFUSED (3). Neither is 0.
"""
import argparse
import ast
import importlib.util
import sys
import tempfile
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def load(name, path):
    """A MODULE, LOADED BY PATH. `gates/` is not a package, and a module loaded by a bindable name
    is a module whose population anybody can choose."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        spec = importlib.util.spec_from_file_location(name, path)
        if spec is None or spec.loader is None:
            return None
        mod = importlib.util.module_from_spec(spec)
        sys.modules[name] = mod
        spec.loader.exec_module(mod)
        return mod


# THE FIVE VERDICTS, `gates/gatekit.py`'s, LOADED BY PATH AND NEVER RE-SPELLED. The edge runner
# loads the same file for itself; two instances of a module of CONSTANTS cannot drift, and this
# file's `judge()` must be able to name PASS and FAIL without a second vocabulary.
GATEKIT = load("edge_reach_gatekit", HERE / "gatekit.py")

# THE EDGE'S HOOK, DECLARED HERE AND READ BY THE EDGE (`gates/edge-runner.py:declares_edge_candidate`).
# This gate holds no pin of its own -- it judges OTHER gates' reachability -- so the edge's
# selection rule ("a member that holds a pin its own code reads") would not see it. The tree's own
# escape, used by `gates/edge-oracle-pin-gate.py` and `gates/compile-census-gate.py`, and read BY
# PATH the way the edge reads `RED_IS`.
#
# **AND THE GATE THAT MEASURES REACHABILITY IS ITSELF REACHABLE, WHICH IS THE POINT OF THE FILE.**
# A census that is discovered and not run is the defect it describes.
EDGE_CANDIDATE = True


def instruments():
    """The tree's OWN instruments, each LOADED BY PATH: the edge runner (the selection, the
    declaration reader, the budget and the two ledgers), the sweep (the population) and the gatekit
    (the five verdicts). **THIS FILE HOLDS NO COPY OF ANY OF THEM**, because a second copy of a
    vocabulary is a second population with a different predicate -- one question, two answers."""
    ed = load("edge_reach_runner", HERE / "edge-runner.py")
    if ed is None:
        return None, None, None, None
    gs, popmod, gk = ed.modules()
    return ed, gs, popmod, gk


class Census:
    """One measurement of one tree: the population, the edge's selection, and the two ledgers."""

    def __init__(self, **kw):
        self.__dict__.update(kw)

    def summary(self):
        """-> the whole measurement as ONE comparable value, so a control can assert that a
        comment-only edit moved NOTHING without naming every field."""
        return (tuple(self.population), tuple(sorted(self.candidates)), tuple(self.declared),
                tuple(self.selected), tuple(self.skipped), tuple(self.unreachable),
                tuple(self.stale_trace), tuple(self.charges))


def census(root, trace_path, cost_path):
    """-> a `Census` of `root`, or None when the tree's own instruments are not here.

    **THE SUBJECT IS THE ROOT AND THE INSTRUMENTS ARE THE TREE'S**, and the two are not the same
    thing: the plant points this at a synthetic tree and still measures it with the tree's own
    walk, the tree's own selection rule and the tree's own declaration reader."""
    ed, gs, popmod, _ = instruments()
    if ed is None:
        return None
    members, cands = ed.candidates(gs, popmod, root)
    population = sorted(ed.rel_of(p, root) for p, _ in members)
    declared = sorted(rel for rel in population if ed.declares_edge_candidate(root / rel))
    trace = ed.read_rows(Path(trace_path))
    cost = ed.read_rows(Path(cost_path))
    selected, skipped = ed.select(cands, cost, ed.BUDGET_SECONDS)
    reachable = set(selected)
    return Census(root=root, population=population, candidates=cands, declared=declared,
                  trace=trace, cost=cost, selected=selected, skipped=skipped,
                  reachable=reachable, trace_path=Path(trace_path),
                  unreachable=[rel for rel in population if rel not in reachable],
                  stale_trace=sorted(set(trace) - set(cands)), charges=())


def judge(c):
    """-> (rc, charges, notes). **THE CLAIM IS CHARGED; THE REACH IS COUNTED.**

    **WHY THE CLAIM AND NOT THE COUNT.** The count of unreachable gates MOVES whenever another
    unit adds a gate, and a population that grows is not a defect -- so charging the count would
    make this gate permanently red, and *"a pre-commit gate that cannot pass teaches nothing"*
    with the word "pre-commit" removed and nothing else changed. The CLAIM does not move: a gate
    that says `EDGE_CANDIDATE = True` and is not in the trace is a claim the runner has not kept,
    and that is a fact about the tree, not about how many gates the tree has."""
    charges = []
    for rel in c.declared:
        row = c.trace.get(rel)
        if row is None:
            charges.append(f"{rel} declares EDGE_CANDIDATE = True and has NO ROW in "
                           f"{c.trace_path.name}: the runner claims to run it and does not")
        elif row[1] == "OVER-BUDGET":
            charges.append(f"{rel} declares EDGE_CANDIDATE = True and the trace says OVER-BUDGET "
                           f"({row[3]}): the edge cannot afford it, so it never runs")
    notes = []
    if c.stale_trace:
        notes.append(f"{len(c.stale_trace)} trace row(s) name a gate the edge would not select "
                     f"now: " + ", ".join(c.stale_trace[:8]))
    c.charges = tuple(charges)
    return (GATEKIT.FAIL if charges else GATEKIT.PASS), charges, notes


def _code_only(text, pc):
    """The file with every comment REMOVED and every blank line DROPPED.

    The comment removal is `checks/port-compile-gate.py`'s own `strip_comments()`, imported by path
    and not re-implemented -- it is the house's stripper and it knows that a `#` inside a string
    is not a comment. The BLANK-LINE DROP is `gates/ptx_render_census-gate.py`'s addition, and it
    is what makes the proof cover a WHOLE-LINE comment: a comment on its own line contributes a
    line that is empty once the comment is stripped, and comparing LINE LISTS would call that "not
    comment-only" -- which is the most comment-only edit there is."""
    return "\n".join(l for l in pc.strip_comments(text).split("\n") if l.strip())


# THE SYNTHETIC GATE THE PLANT MEASURES. **IT CARRIES TWO STATEMENTS ON ONE LINE ON PURPOSE**, so
# the wrong shape (a comment BETWEEN them) is a shape this file can MEASURE rather than assert.
CLAIMED = '''#!/usr/bin/env python3
# a synthetic gate that CLAIMS to be an edge candidate
EDGE_CANDIDATE = True; ALSO_CLAIMED = 1
if __name__ == "__main__":
    print("PASS")
'''


def plant():
    """THE PLANT, THE CONTROL, AND THE TWO WRONG SHAPES OF A COMMENT-ONLY EDIT.

    THE PLANT: a gate that declares `EDGE_CANDIDATE = True` and has NO ROW in the trace. The
    census must go RED on it, and the RED must be about the CLAIM.

    THE CONTROL: the same tree with a row for that gate in the trace. The census must be GREEN, so
    the plant cannot be satisfied by a census that is red over everything.

    THE COMMENT-ONLY CONTROL: a comment appended to the CLAIMING GATE's own file. The census must
    move NOTHING -- not the verdict, not the counts, not the charges. **AND THE PROOF OF THAT IS
    THE COMMENT-STRIPPED BYTES**, because a verdict is a verdict about the TREE and a comment is a
    comment about the SOURCE.

    THE TWO WRONG SHAPES, because a control that cannot fail proves nothing:

      SHAPE A -- a comment BETWEEN the two statements of a one-line pair DELETES the second, and
        the file STILL PARSES. Only the comment-stripped proof catches it, which is the whole
        reason the proof strips comments instead of asking the parser.
      SHAPE B -- a whole-line comment AT COLUMN 0 does not break the file, and the proof says
        comment-only -- because the proof DROPS BLANK LINES, and a whole-line comment is a blank
        line once the comment is gone. MEASURED on a bend file by
        `gates/ptx_render_census-gate.py`; the parser skips a whole-line comment in both
        languages, and this plant measures it in Python.

    **THE PLANT IS A TEXT EDIT ON THE SYNTHETIC TREE, NEVER ON THE LIVE ONE, AND NEVER ON
    `git show HEAD:`** -- a plant that reads HEAD plants nothing the moment HEAD carries the
    defect's fix, and three units scored green under `--falsify` for exactly that reason."""
    ed, _, _, _ = instruments()
    gpop = load("edge_reach_gatespop", HERE / "gates-pop.py")
    pc = load("edge_reach_portcompile", ROOT / "checks" / "port-compile-gate.py")
    if ed is None or gpop is None or pc is None:
        print("== REFUSED, NOT A VERDICT: the tree's own instruments are not here "
              "(gates/edge-runner.py, gates/gates-pop.py, checks/port-compile-gate.py)",
              file=sys.stderr)
        return GATEKIT.REFUSED
    bad = 0
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "tree"
        (tree / "gates").mkdir(parents=True)
        (tree / "tinybendygrad").mkdir()
        (tree / "pyproject.toml").write_text("[project]\nname='x'\n")
        # THE HOME IS EARNED, NOT DECLARED. `gates/gates-pop.py:gate_homes()` derives the gate
        # homes from the gates themselves -- a home is a directory holding a tracked file that
        # NAMES A ROOT, REFUSES ON A WRONG ONE and RESOLVES ON-REPO -- so a synthetic tree earns
        # one the only way a real one does: by holding that witness. `GOOD_ROOT` is the tree's own
        # fixture, LOADED BY PATH and not retyped.
        (tree / "gates" / "home-witness.py").write_text(gpop.GOOD_ROOT)
        gate = tree / "gates" / "claimed-gate.py"
        gate.write_text(CLAIMED)
        trace = tree / "edge-trace.rows"
        cost = tree / "edge-cost.rows"
        trace.write_text("# the trace of a synthetic tree\n")

        # 1. THE PLANT: the gate claims to be a candidate and the trace has no row for it.
        c1 = census(tree, trace, cost)
        rc1, charges1, _ = judge(c1)
        planted = rc1 == 1 and len(charges1) == 1 and "claimed-gate.py" in charges1[0]
        print(f"  {'PASS' if planted else 'FAIL'}  PLANT: a gate that declares EDGE_CANDIDATE = "
              f"True and is NOT in the trace makes the census RED\n"
              f"          observed: rc={rc1} charges={charges1}")

        # 2. THE CONTROL: the trace HAS a row for that gate, so the claim is kept and the census
        #    is green. A census that is red over everything satisfies the plant and nothing else.
        trace.write_text("# the trace of a synthetic tree\n"
                         "gates/claimed-gate.py\tRAN\tPASS\tPASS\t0\t0.10\t20\t2026-10-22T00:00:00Z\n")
        c2 = census(tree, trace, cost)
        rc2, charges2, _ = judge(c2)
        control = rc2 == 0 and not charges2
        print(f"  {'PASS' if control else 'FAIL'}  CONTROL: the SAME tree with a row for that gate "
              f"in the trace is GREEN\n"
              f"          observed: rc={rc2} charges={charges2}")

        # 3. THE COMMENT-ONLY CONTROL: a comment appended to the claiming gate's own file must move
        #    NOTHING -- and the proof is the comment-stripped bytes, not the verdict.
        #
        #    **THE COMMENT GOES ON A LINE CARRYING ONE STATEMENT, AND THAT IS NOT A STYLE CHOICE.**
        #    MEASURED HERE, and it is the brief's own wrong shape: a comment APPENDED between the
        #    two statements of a one-line pair DELETES the second one, the file STILL PARSES, and
        #    only the comment-stripped proof catches it. The first version of this control put the
        #    comment on the two-statement line and the proof REJECTED the control -- correctly,
        #    because the control was not comment-only. **A CONTROL THAT IS REJECTED FOR BEING WHAT
        #    IT IS, IS NOT A CONTROL.**
        commented = CLAIMED.replace('if __name__ == "__main__":',
                                    'if __name__ == "__main__":  # a comment')
        gate.write_text(commented)
        c3 = census(tree, trace, cost)
        rc3, charges3, _ = judge(c3)
        same = _code_only(commented, pc) == _code_only(CLAIMED, pc)
        moved_nothing = (rc3, tuple(charges3), c3.summary()) == (rc2, tuple(charges2), c2.summary())
        comment_only = same and moved_nothing
        print(f"  {'PASS' if comment_only else 'FAIL'}  COMMENT-ONLY CONTROL: a comment appended to "
              f"the claiming gate's own file moves NOTHING\n"
              f"          observed: comment-only={same} moved-nothing={moved_nothing} rc={rc3}")

        # 4. WRONG SHAPE A: the comment goes BETWEEN the two statements of the one-line pair, so
        #    the second is DELETED -- and the file still parses. The proof must call it NOT
        #    comment-only, because a proof that cannot fail is not a proof.
        wrong_a = CLAIMED.replace("EDGE_CANDIDATE = True; ALSO_CLAIMED = 1",
                                  "EDGE_CANDIDATE = True;  # between them ALSO_CLAIMED = 1")
        still_parses = True
        try:
            ast.parse(wrong_a)
        except SyntaxError:
            still_parses = False
        caught = _code_only(wrong_a, pc) != _code_only(CLAIMED, pc)
        shape_a = still_parses and caught
        print(f"  {'PASS' if shape_a else 'FAIL'}  WRONG-SHAPE-A: a comment BETWEEN two statements "
              f"DELETES the second, the file still parses, and the proof CATCHES it\n"
              f"          observed: still-parses={still_parses} proof-catches={caught}")

        # 5. WRONG SHAPE B: a whole-line comment AT COLUMN 0 does not break the file, and the proof
        #    says comment-only -- because the proof drops blank lines.
        wrong_b = CLAIMED.replace('if __name__ == "__main__":',
                                  '# a comment at column 0\nif __name__ == "__main__":')
        shape_b_parses = True
        try:
            ast.parse(wrong_b)
        except SyntaxError:
            shape_b_parses = False
        shape_b = shape_b_parses and _code_only(wrong_b, pc) == _code_only(CLAIMED, pc)
        print(f"  {'PASS' if shape_b else 'FAIL'}  WRONG-SHAPE-B: a whole-line comment AT COLUMN 0 "
              f"does not break the file, and the proof says comment-only\n"
              f"          observed: still-parses={shape_b_parses} comment-only="
              f"{_code_only(wrong_b, pc) == _code_only(CLAIMED, pc)}")
        bad += sum(1 for ok in (planted, control, comment_only, shape_a, shape_b) if not ok)
    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return GATEKIT.FAIL if bad else GATEKIT.PASS


def main():
    ap = argparse.ArgumentParser(prog="gates/edge-reach-census.py",
                                 description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=str(ROOT), help="the tree to measure")
    ap.add_argument("--trace", default=None, help="the edge's trace (default <root>/gates/edge-trace.rows)")
    ap.add_argument("--cost", default=None, help="the edge's cost ledger (default <root>/gates/edge-cost.rows)")
    ap.add_argument("--names", type=int, default=25, help="how many unreachable gates to name")
    ap.add_argument("--plant", action="store_true", help="the plant and its control")
    a = ap.parse_args()
    if a.plant:
        return plant()

    ed, _, _, _gk = instruments()
    if ed is None:
        print("== REFUSED, NOT A VERDICT: gates/edge-runner.py is not here", file=sys.stderr)
        return GATEKIT.REFUSED
    root = Path(a.root).resolve()
    trace = Path(a.trace) if a.trace else root / "gates" / "edge-trace.rows"
    cost = Path(a.cost) if a.cost else root / "gates" / "edge-cost.rows"
    if not trace.is_file():
        print(f"== REFUSED, NOT A VERDICT: the edge's trace {trace} is absent, so 'was this gate "
              f"ever run?' has no answer and a census over no answer measures nothing.",
              file=sys.stderr)
        return GATEKIT.REFUSED
    c = census(root, trace, cost)
    if c is None:
        print("== REFUSED, NOT A VERDICT: the tree's own instruments are not here", file=sys.stderr)
        return GATEKIT.REFUSED
    if not c.population:
        print("== DEAD: the population is EMPTY. The census ran and measured nothing.", file=sys.stderr)
        return GATEKIT.DEAD
    rc, charges, notes = judge(c)

    over = set(c.skipped)
    unclaimed = [rel for rel in c.unreachable if rel not in over]
    print("EDGE-REACH: can the edge run every gate that claims it can, and what can it reach?")
    print(f"  population {len(c.population)}   candidates {len(c.candidates)}   "
          f"declare EDGE_CANDIDATE {len(c.declared)}   traced {len(c.trace)}   "
          f"budget {ed.BUDGET_SECONDS}s / {ed.BUDGET_MB} MB")
    print(f"  REACHABLE {len(c.reachable)} of {len(c.population)}   "
          f"UNREACHABLE {len(c.unreachable)} of {len(c.population)} "
          f"({len(c.skipped)} the edge cannot afford, {len(unclaimed)} nothing claims)")
    if c.declared:
        for rel in c.declared:
            row = c.trace.get(rel)
            print(f"    CLAIMS  {rel:44} trace={row[1] if row else 'NO ROW'}")
    print("  THE GATES THE EDGE CANNOT REACH -- counted, with their denominator, and NAMED:")
    for rel in c.unreachable[:a.names]:
        print(f"    UNREACHABLE  {rel:44} "
              f"{'over budget' if rel in over else 'no claim'}")
    if len(c.unreachable) > a.names:
        print(f"    ... and {len(c.unreachable) - a.names} more")
    for charge in charges:
        print(f"  CHARGE: {charge}")
    for note in notes:
        print(f"  note: {note}")
    print(f"EDGE-REACH: {GATEKIT.VERDICT.get(rc, 'FAIL')} (exit {rc})")
    return rc


if __name__ == "__main__":
    sys.exit(main())
