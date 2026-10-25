"""THE PLANTS -- a mutation sweep over the port, and the COVERAGE PROOF.

**A ROW THAT CANNOT GO RED IS A LABEL.**  So every row this unit adds must be MOVED by
some mutation of the port, and this file PROVES that mechanically: it applies each
mutation, runs the port, diffs the rows against the base, and then ASSERTS that the
UNION of the rows every mutation moved COVERS every new row.

THE MUTATIONS ARE EDITS TO A COPY OF THE TREE, and each edit is ASSERTED BY RE-READING
THE FILE -- a plant that did not apply is reported as VACUOUS, not as a verdict.  The
prior art's `run.sh` has the same discipline and the same reason: `checks/walk-mutate.sh`
once shipped a vacuous plant.

THE MUTATIONS, AND WHAT EACH ONE IS FOR:

  noargsort       `gr_21` copies the order instead of ARGSORTING it.  **⇒ THIS IS THE
                  PLANT FOR THE BRIEF'S SUSPICION** -- and because the fixture's order
                  is `(1, 2, 0)` and its argsort is `(2, 0, 1)`, the rule's ORDER row
                  tells the two apart.  (A 2-element permutation is an INVOLUTION, so a
                  2-D fixture could NOT have told them apart -- which is why the
                  fixture is 3-D.)
  argsortbyindex  `helpers.bend`'s `argsort_u32` sorts by the INDEX instead of the
                  VALUE.  **⇒ THE BRIEF'S SUSPICION, PLANTED IN THE OTHER DIRECTION:
                  IF THE PORT SORTED BY THE INDEX, EVERY ARGSORT ROW WOULD GO RED.**
  flagfalse       the IDENTITY test is forced false, so the identity early-return never
                  fires.
  neverpermute    `gr_21` NEVER builds a PERMUTE -- the other end of the same axis.
  zerograds       `gr_21`'s PERMUTE arm answers NO gradient.
  twograds        `gr_21`'s IDENTITY arm answers TWO gradients for a ONE-src node.
  nosrc           the PERMUTE node is built with NO src.
  emptytargets    the 3-D fixture's TARGET LIST is empty.
  targetsub       the 3-D fixture's TARGET is the node BELOW the 3-D node, so the walk
                  reaches a node no rule claims and the target gets the `const_like(0)`
                  SUBSTITUTE.
  collide         two leaves share a PARAM SLOT, so two nodes of the same class become
                  one node.
  emptyP1targets  the 1-D fixture's TARGET LIST is empty.
  targetsubP1     the 1-D fixture's TARGET is the leaf's shape src, so the leaf gets no
                  gradient and the SUBSTITUTE fires.

usage: plants.py <base.rows> <expect.rows>
  <expect.rows>  THE EXPECTATIONS -- the rows this unit added.  The list of rows that
                 must be covered is READ FROM IT rather than typed here, so the
                 coverage claim and the gate's row set cannot drift apart.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
BEND = ROOT / "bin" / "bend"

GRAD = ROOT / "tinybendygrad" / "mixin" / "gradient.bend"
HELP = ROOT / "tinybendygrad" / "helpers.bend"

# (label, file, old, new)
MUTATIONS = [
  ("noargsort", GRAD,
   "  +inv = H.argsort_u32(gr_21_marg(ar, self))",
   "  +inv = gr_21_marg(ar, self)"),
  ("argsortbyindex", HELP,
   "def argsort_u32(xs: List<&2, U32>) -> List<&2, U32>:\n  ix_map(List.sort(Ix, ix_le, ix_of(xs)))",
   "def argsort_u32(xs: List<&2, U32>) -> List<&2, U32>:\n  ix_map(ix_of(xs))"),
  ("flagfalse", GRAD,
   "  gr_21.pick(gr_21_is_id(inv), ar, ctx, inv)",
   "  gr_21.pick(False{}, ar, ctx, inv)"),
  ("neverpermute", GRAD,
   "    case _: gr_21.build(ar, ctx, inv)",
   "    case _: fired([ctx], ar)"),
  ("zerograds", GRAD,
   "  fired([O.Found.i(n)], O.Found.ar(n))",
   "  fired(Nil{}, O.Found.ar(n))"),
  ("twograds", GRAD,
   "    case True{}: fired([ctx], ar)",
   "    case True{}: fired([ctx, ctx], ar)"),
  ("nosrc", GRAD,
   "  +n = gnew(ar, O.OpsPERMUTE{}, [ctx], O.ATuple{inv})",
   "  +n = gnew(ar, O.OpsPERMUTE{}, Nil{}, O.ATuple{inv})"),
  ("emptytargets", GRAD,
   "def pm_targets.of(a: U32) -> List<&2, U32>: [a]",
   "def pm_targets.of(a: U32) -> List<&2, U32>: Nil{}"),
  ("targetsub", GRAD,
   "      +ts = pm_targets.of(a)",
   "      +ts = pm_targets.of(O.Arena.src(ar, a, 0))"),
  ("collide", GRAD,
   "  +m0 = pm_leaf(O.Found.ar(per), 3, 2)",
   "  +m0 = pm_leaf(O.Found.ar(per), 0, 2)"),
  ("emptyP1targets", GRAD,
   "def pm1_targets.of(leaf: U32) -> List<&2, U32>: [leaf]",
   "def pm1_targets.of(leaf: U32) -> List<&2, U32>: Nil{}"),
  ("targetsubP1", GRAD,
   "      +ts = pm1_targets.of(leaf)",
   "      +ts = pm1_targets.of(O.Arena.src(ar, leaf, 0))"),
]


def read_rows(path) -> dict:
    rows = {}
    for line in open(path):
        line = line.rstrip("\n")
        if "=" not in line:
            continue
        name, _, value = line.partition("=")
        rows[name] = value
    return rows


def run_port(workdir: pathlib.Path):
    """Run the port in a COPY of the tree and return its rows, or None if it failed."""
    out = workdir / "rows.out"
    err = workdir / "rows.err"
    with open(out, "w") as fh:
        proc = subprocess.run([str(BEND), str(workdir / "tinybendygrad" / "mixin" / "gradient.bend")],
                              stdout=fh, stderr=err.open("w"),
                              env={**os.environ, "BEND_NO_TELEMETRY": "1"})
    if proc.returncode != 0:
        return None, err.read_text()
    return read_rows(out), err.read_text()


def main() -> int:
    base_path, names_path = sys.argv[1], sys.argv[2]
    base = read_rows(base_path)
    wanted = sorted(read_rows(names_path))
    print("THE BASE: %d rows" % len(base))
    print("THE ROWS THAT MUST BE COVERED: %d" % len(wanted))

    moved_by = {}
    failures = 0
    for label, path, old, new in MUTATIONS:
        with tempfile.TemporaryDirectory() as tmp:
            work = pathlib.Path(tmp)
            tree = work / "tinybendygrad"
            shutil.copytree(ROOT / "tinybendygrad", tree)
            target = work / path.relative_to(ROOT)
            text = target.read_text()
            n = text.count(old)
            if n != 1:
                print("    %-16s VACUOUS: %d occurrence(s) of the target, expected 1 -- NO VERDICT"
                      % (label, n))
                failures += 1
                continue
            target.write_text(text.replace(old, new))
            back = target.read_text()
            if back.count(new) != 1:
                print("    %-16s VACUOUS: THE WRITE DID NOT LAND -- NO VERDICT" % label)
                failures += 1
                continue
            rows, err = run_port(work)
            if rows is None:
                print("    %-16s VACUOUS: THE MUTATED PORT DID NOT RUN:" % label)
                print("        " + err.strip().replace("\n", "\n        "))
                failures += 1
                continue
            moved = sorted(k for k in base if k in rows and rows[k] != base[k])
            lost = sorted(k for k in base if k not in rows)
            moved_by[label] = set(moved) | set(lost)
            print("    %-16s moved %2d row(s): %s" % (label, len(moved_by[label]),
                                                     " ".join(sorted(moved_by[label])) or "(none)"))

    covered = set()
    for s in moved_by.values():
        covered |= s
    uncovered = [w for w in wanted if w not in covered]
    print("THE COVERAGE: %d of %d new row(s) are moved by some plant" % (len(wanted) - len(uncovered), len(wanted)))
    if uncovered:
        print("    UNCOVERED (a row that CANNOT GO RED is a label): %s" % " ".join(uncovered))
    else:
        print("    every new row is moved by at least one plant")
    print("PLANTS: %d mutations, %d VACUOUS/FAILED, %d UNCOVERED row(s)"
          % (len(MUTATIONS), failures, len(uncovered)))
    return 0 if failures == 0 and not uncovered else 1


if __name__ == "__main__":
    raise SystemExit(main())
