"""census.py -- the EXIT-CODE TABLE CENSUS, by AST discovery, against ONE owner loaded by path.

    .venv/bin/python .agents/slop/verdictcollide/census.py            # the table, as .rows
    .venv/bin/python .agents/slop/verdictcollide/census.py --check    # exit token, for a gate

WHAT THIS IS. Every module-level mapping in `checks/` and `gates/` from an EXIT CODE to a VERDICT
NAME is one owner's answer to the same question, so the tree holds many tables and they can disagree.
This file counts them by walking the tree and parsing it with `ast` -- never `grep`, because a grep
for `VERDICT` finds the NAME and not the TABLE, and a grep cannot tell `4: "SKIP"` from `4: "NO-ROW"`.

THE POPULATION IS A DIRECTORY WALK. `checks/` and `gates/` are the two homes `gates/gates-pop.py:discover()`
already owns, so this census reuses that declaration BY PATH rather than naming a list of files: two
instruments holding two lists have no authority over one another, and the second list is what roted.

THE SUBJECT'S TABLE IS IMPORTED BY PATH, NEVER RE-SPELLED. `sys.path.insert(0, "gates"); import gatekit`
and read `gatekit.VERDICT`. Re-typing `{0:"PASS",1:"FAIL",3:"REFUSED",4:"SKIP",5:"DEAD"}` here would
be a SECOND copy of the vocabulary, and two copies are blind exactly where they disagree -- which is the
one place anybody reads either of them. Re-spelling it has already produced two `TypeError`s in this
tree; the import is cheaper than the traceback.

FOUR DISAGREEMENT CLASSES, each NAMED rather than collapsed:

  AGREE      every code in the table has the owner's name for that code.
  NAME       a code the owner also declares, but under a DIFFERENT name. `4` is `SKIP` to one owner
             and `NO-ROW` to another; the code collides, the WORDS do not, and the doctrine says a
             gate that RAN and found no row is not a gate that COULD NOT RUN.
  EXTRA      a code the table declares that the owner does not have a name for at all -- `2: "USAGE"`.
  MISSING    a code the owner declares that this table does not. Not a defect in the table: a gate
             need not be able to produce every verdict, and forcing one would be inventing a fixture.
"""
import argparse
import ast
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def owner():
    """`gates/gatekit.py` BY PATH: its live MODULE, never a copy of its tables.

    The MODULE and not just the mapping, because a census must also exit with the owner's own
    codes -- and it must take those from `gatekit.PASS`/`gatekit.FAIL`, never from `VERDICT[0]`.
    `VERDICT` maps CODE -> NAME, so `VERDICT.get(0)` is the STRING `"PASS"`, and
    `sys.exit("PASS")` prints the string to stderr and exits **1** -- a census that answered
    PASS and was charged FAIL. That is this file's own first bug, found by reading the exit code
    beside the verdict: the two disagreed, and the reason was an INVERTED LOOKUP on the owner's
    own table. The `gatekit.PASS` attribute is the code, and reading an attribute cannot invert.
    """
    p = ROOT / "gates" / "gatekit.py"
    sys.path.insert(0, str(p.parent))
    import gatekit
    return gatekit


def population(root):
    """`(entries, libs)` from `gates/gates-pop.py:discover()` -- the tree's OWN declaration of the
    gate population, loaded by path. A census that walked `checks/` by hand would be a second
    population, and a second population is the defect this file exists to measure."""
    spec = importlib.util.spec_from_file_location("gates_pop", root / "gates" / "gates-pop.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.discover(root)


def verdict_tables(root, entries):
    """`{path: {code: NAME}}` for every MODULE-BODY mapping to a verdict name, by AST.

    A module-level `Assign` (or `AnnAssign`) whose single target name contains `VERDICT` and whose
    value is a dict literal with integer keys and string values. The name shape is the MARKER; the
    `ast.literal_eval` is the READ. A table assembled at run time is not discoverable by any static
    read and is not counted -- said here so the denominator means what it says.
    """
    found = {}
    for p in entries:
        if p.suffix != ".py":
            continue
        try:
            tree = ast.parse(p.read_text(errors="replace"))
        except (SyntaxError, OSError):
            continue
        for node in tree.body:  # MODULE BODY ONLY: a local named VERDICTS is not a declaration
            target = None
            if isinstance(node, ast.Assign) and len(node.targets) == 1:
                target = node.targets[0]
            elif isinstance(node, ast.AnnAssign):
                target = node.target
            if not isinstance(target, ast.Name) or "VERDICT" not in target.id:
                continue
            try:
                val = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if isinstance(val, dict) and all(
                isinstance(k, int) and isinstance(v, str) for k, v in val.items()
            ):
                found[p] = val
    return found


def compare(table, vocab):
    """`(class -> [codes])` for one table against the owner's vocabulary.

    **MISSING IS NOT A COLLISION, and calling it one was this file's second bug.** A table need not
    declare every verdict -- `checks/nl-gate.py` cannot produce DEAD, and forcing it to would mean
    inventing a plant for a state the gate has no way to reach. So MISSING is reported as a
    *capability* (what this gate cannot say) and never counted as disagreement. With MISSING folded
    into the verdict, 14 of 14 tables collided and `--check` was red at rest for a reason that is
    not a defect -- the "gate that can never pass teaches nothing" shape, self-inflicted.
    """
    extra = sorted(c for c in table if c not in vocab)
    names = sorted(c for c in table if c in vocab and table[c] != vocab[c])
    missing = sorted(c for c in vocab if c not in table)
    kind = "COLLIDE" if (extra or names) else "AGREE"
    return kind, {"EXTRA": extra, "NAME": names, "CANNOT-SAY": missing}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="exit COLLIDE-red, so this can be a gate")
    ap.add_argument("--rows", default=str(HERE / "tables.rows"))
    a = ap.parse_args(argv)

    gk = owner()
    vocab = gk.VERDICT  # the owner's own mapping, read from the module -- never re-spelled here
    entries, libs = population(ROOT)
    tables = verdict_tables(ROOT, entries)

    rows = []
    colliding = []
    for p in sorted(tables, key=lambda q: str(q.relative_to(ROOT))):
        kind, parts = compare(tables[p], vocab)
        if kind == "COLLIDE":
            colliding.append(p)
        rel = str(p.relative_to(ROOT))
        d = " ".join(f"{c}:{tables[p][c]}" for c in sorted(tables[p]))
        detail = ";".join(f"{k}={v}" for k, v in sorted(parts.items()) if v)
        rows.append(f"{rel}\t{kind}\t{d}\t{detail}")
        if parts["NAME"]:
            # The collision, printed where it is found, not summarised by a count.
            for c in parts["NAME"]:
                rows.append(f"  NAME-COLLISION {rel} code={c} this={tables[p][c]!r} "
                            f"owner={vocab[c]!r}")

    have4 = [p for p, t in tables.items() if gk.SKIP in t]
    have2 = [p for p, t in tables.items() if 2 in t]
    same4 = [p for p in have4 if tables[p][gk.SKIP] == vocab[gk.SKIP]]
    header = (f"# {len(entries)} entries from gates-pop.discover(), {len(libs)} modules, "
              f"{len(tables)} declare a verdict table by AST\n"
              f"# owner gates/gatekit.py VERDICT = {vocab}\n"
              f"# declare 4: {len(have4)}   call it SKIP: {len(same4)}   declare 2: {len(have2)}")
    Path(a.rows).write_text("\n".join([header] + rows) + "\n")

    for line in rows:
        print(line)
    print()
    print(f"DENOMINATOR: {len(tables)} verdict tables in {len(entries)} discovered entries "
          f"({len(libs)} modules).")
    print(f"  declare code {gk.SKIP}: {len(have4)}; of those call it {vocab[gk.SKIP]!r} (the owner's "
          f"word): {len(same4)}; call it something else: {len(have4) - len(same4)}")
    print(f"  declare code 2: {len(have2)} of {len(tables)} tables, and 2 is in the owner's vocabulary: "
          f"{2 in vocab}")
    print(f"  colliding with the owner: {len(colliding)} -- "
          f"{', '.join(str(p.relative_to(ROOT)) for p in colliding) or 'none'}")
    print(f"ROWS: {a.rows}")
    if a.check:
        # The owner's own constants, not an inverted lookup and not a retyped number.
        return gk.FAIL if colliding else gk.PASS
    return gk.PASS


if __name__ == "__main__":
    sys.exit(main())