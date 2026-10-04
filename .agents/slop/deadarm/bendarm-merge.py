#!/usr/bin/env python3
r"""bendarm-merge.py -- ONE denominator for the port side: which defs does NO lane reach?

    .venv/bin/python .agents/slop/deadarm/bendarm-merge.py "${TMPDIR:-/tmp}/bendarm.tsv"

`bendarm.py` reports PER ENTRY, and a per-entry number is not a tree-wide one: `uop/fold.bend` is in
`renderer/cstyle.bend`'s import closure and `cstyle.bend`'s lane calls none of it, so read per
entry the fold looks dead and it is not -- `uop/fold.bend` has its OWN lane, and `NVDUP.md:62`'s law
is about lanes, not about files.  So this merges on the right key.

THE AGGREGATION RULE, stated before the number:

  a def `D` in file `F` is TREE-UNREACHED  <=>  for EVERY traced entry `e` whose import closure
  contains `F`, `D` is in `e`'s NOT-EMITTED or NOT-ENTERED set.

and the denominator is printed next to it, because a count of the unreachable with no count of the
reachable is the multiplicity census's mistake:

    defs in the tree / defs inside >=1 traced lane's closure / defs NO traced lane reaches

A def that no traced entry's closure contains is reported as COVERAGE, not as dead.  Calling an
uncovered def dead is the `Bool.pick` failure in a new costume: a number that cannot be wrong
because nothing checks what it counts.

`bendarm.py` writes only rows for entries whose instrumented lane is BYTE-IDENTICAL to the plain
one, and this keeps only those: an entry whose lane text moved under instrumentation is measuring a
different program, and its verdicts are withheld -- the control `bendarm.py --selftest` asserts.
"""
import collections, csv, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import bendarm as B                                          # noqa: E402


def main():
  tsv = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/bendarm.tsv")
  log = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else tsv.with_name("bendarm-run.txt")
  log_lines = log.read_text(errors="replace").splitlines() if log.exists() else []
  dead, arms = collections.defaultdict(lambda: {"not_emitted": set(), "not_entered": set()}), \
      collections.defaultdict(set)
  entries = set()
  with open(tsv) as fh:
    for r in csv.DictReader(fh, delimiter="\t"):
      entries.add(r["entry"])
      if r["kind"] == "arm_dead":
        arms[r["entry"]].add((r["where"], r["name"]))
      else:
        dead[r["entry"]][r["kind"]].add((r["where"], r["name"]))
  entries = sorted(entries)
  if not entries:
    print("no rows in the TSV -- run bendarm.py --report first")
    return 1

  tree = {}
  files = sorted(set(B.REPO.glob("tinybendygrad/**/*.bend"))) + \
      sorted(B.SLOP.glob("*.bend")) + sorted(B.SLOP.glob("*/*.bend"))
  for f in files:
    # KEYED BY THE SAME STRING `census_entry` WRITES.  `census_entry` records `rel(f)`, and the
    # first version keyed the tree by the ABSOLUTE path, so every `(where, name)` in the TSV
    # missed every key and the merge reported 0 unreached defs out of 10,870 -- a total that is
    # impossible for 88 entries over a 42,109-def tree, and it was accepted because it was green.
    for nm, ln, txt in B.defs_of(f):
      tree[(f"{B.rel(f.resolve())}:{ln}", nm)] = txt
  closures = {e: set(B.rel(x) for x in B.closure(pathlib.Path(e))[0]) for e in entries}

  reach = collections.defaultdict(set)
  for e in entries:
    for f in closures[e]:
      for k in tree:
        if k[0].rsplit(":", 1)[0] == f:
          reach[k].add(e)
  in_a_lane = {k: v for k, v in reach.items() if v}
  unreached, reached = [], []
  for k, es in in_a_lane.items():
    # THE KEY IS EXACTLY WHAT THE TSV WRITES: `(where, name)`, where `where` is
    # `rel(file) + ":" + line`.  The first version keyed the tree by `(rel(file), line)` -- a pair
    # of the right shape and the wrong contents -- so every membership test was False and the
    # merge answered "0 unreached of 10,870".  That is not a result, it is a key mismatch wearing
    # a green shirt, and it was accepted because the number was small and plausible.
    hit = any(k not in dead[e]["not_emitted"] and k not in dead[e]["not_entered"] for e in es)
    (reached if hit else unreached).append(k)
  uncovered = [k for k in tree if k not in in_a_lane]

  # ⚠ THE SPLIT THAT DECIDES WHETHER THE HEADLINE MEANS ANYTHING.  A def counts as "reached" only
  # if SOME traced lane reached it.  But a def in a file whose OWN lane FAILED TO BUILD is reached by
  # nobody in this run -- and that is not deadness, it is a broken build.  `bendarm-run.txt` records
  # `ok=False bend -o failed: ...` for `tinybendygrad/schedule/multi.bend` and
  # `tinybendygrad/runtime/support/am/amdev.bend`, whose 694 and 475 defs are the two largest groups
  # in the table.  Reporting them as "defs no lane reaches" would be reporting a compile error as a
  # finding, which is the `Bool.pick` failure with a build log instead of a value.  So the count is
  # split, and only the first half is a claim about the port.
  own = collections.defaultdict(list)
  for f in files:
    for nm, ln, _ in B.defs_of(f):
      own[f].append((f"{B.rel(f.resolve())}:{ln}", nm))
  built, failed = set(), set()
  for line in log_lines:
    m = re.match(r"\s+(\S+\.bend)\s+ok=(True|False)", line)
    if m:
      (built if m.group(2) == "True" else failed).add(m.group(1))
  def owner(k):
    return pathlib.Path(k[0].rsplit(":", 1)[0]).name
  claimed = [k for k in unreached if owner(k) in built]
  blocked = [k for k in unreached if owner(k) in failed]
  unknown = [k for k in unreached if owner(k) not in built and owner(k) not in failed]

  per_file_arm = collections.Counter()
  for e in entries:
    per_file_arm[e] = len(arms[e])
  print(f"""
BENDARM -- merged over {len(entries)} traced entries whose lane was byte-identical
           ({len(built)} entries built and ran in this run, {len(failed)} failed `bend -o`)

  defs in the tree (tinybendygrad/**/*.bend + slop's own probes)   {len(tree)}
  defs inside >= 1 traced lane's import closure                  {len(in_a_lane)}
  defs a traced lane REACHES                                    {len(reached)}
  defs NO traced lane reaches                                   {len(unreached)}
     of which the file's OWN lane BUILT, so the claim is real    {len(claimed)}
     of which the file's own lane FAILED `bend -o`, so UNKNOWN   {len(blocked)}
     of which the file is not itself an entry at all              {len(unknown)}
  defs in NO traced lane's closure -- COVERAGE, not DEADNESS     {len(uncovered)}
  dead-arm findings, summed over the entries                     {sum(per_file_arm.values())}
  entries with >= 1 dead arm                                     {sum(1 for v in per_file_arm.values() if v)}
""")
  if claimed:
    byfile = collections.defaultdict(list)
    for where, nm in claimed:
      byfile[where.rsplit(":", 1)[0]].append((int(where.rsplit(":", 1)[1]), nm))
    print("  THE DEFS NO TRACED LANE REACHES -- and whose own lane DID build\n")
    for f in sorted(byfile, key=lambda k: -len(byfile[k])):
      print(f"  {f}   ({len(byfile[f])})")
      for ln, nm in sorted(byfile[f])[:40]:
        print(f"      {f}:{ln:<6} def {nm}")
      if len(byfile[f]) > 40:
        print(f"      ... {len(byfile[f]) - 40} more in this file")
  if blocked:
    bf = collections.Counter(pathlib.Path(k[0].rsplit(":", 1)[0]).name for k in blocked)
    print("\n  NOT COUNTED AS DEAD -- these files' own lanes FAILED to build in this run:\n")
    for nm, c in bf.most_common(20):
      print(f"      {nm:<44} {c} def(s)")
    print("      MEASURED substrate, not deadness.  `bendarm.py --entry <file>` on each of these")
    print("      once the build is green turns them into claims or into coverage.")
  print("\n  ⚠ THE ARM COLUMN IS PER-ENTRY AND NOT MERGED.  A `case` arm dead in one entry can be")
  print("    taken in another, so `bendarm-merge.py` does NOT claim a tree-wide arm count: the")
  print("    negative set (arms that were TAKEN) is not in the TSV, and inferring it would be")
  print("    exactly the inference this whole unit exists to distrust.  Read the per-entry column.")
  return 0


if __name__ == "__main__":
  sys.exit(main())