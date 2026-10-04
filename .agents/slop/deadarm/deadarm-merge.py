#!/usr/bin/env python3
r"""deadarm-merge.py -- merge the sharded TSVs into ONE table with ONE denominator.

    .venv/bin/python .agents/slop/deadarm/deadarm-merge.py "${TMPDIR:-/tmp}/deadarm-sweep"

`deadarm.py --shard k/n` runs one instrument at a time under `sys.settrace`, and a traced run
costs ~20s against ~7s untraced, so the tree-wide census has to be sharded.  Sharding is only
honest if the shards PARTITION the population, so this file checks that every instrument name
appears in exactly one shard and says so if it does not.

The merge prints the DENOMINATOR and not just the headline:

    instruments examined / with emitting sites / TRACEABLE / dead emitting lines
    and, of those, how many sit in a def the lane ENTERED

That last split is the one that decides whether the headline means anything.  A dead emitting line
is either inside a def the no-argument lane entered -- the `D2` the brief is about -- or inside a
def it never entered, which is *either* a helper nothing calls *or* this census's own blindness,
because an instrument run with no argv cannot reach its own `--selftest`.  `cstyle-gate.py` reads 43
dead sites and only 20 of them are in an entered def.  A census that printed 43 as "dead code"
would be reporting its own harness as a finding.

None of the uncounted instruments is a measurement of deadness: `no-sites` is a mutator or a table
generator, `crash` and `hang` are lanes that did not run here (mostly a missing optional module or
a missing argv), `harness` is a lane whose output is not reproducible under tracing.  All are
counted and none is silently dropped.
"""
import collections, csv, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[3]


def main():
  out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/deadarm-sweep")
  per, dead, truncated = [], [], []
  for tsv in sorted(out.glob("shard-*.tsv")):
    with open(tsv) as fh:
      for r in csv.DictReader(fh, delimiter="\t"):
        if r.get("instrument") is None:
          continue
        if r["instrument"] == "DEAD":
          dead.append((r["sites"], r["kind"]))
        elif r.get("kind") is None or r.get("sites") is None:
          truncated.append(r)
        else:
          per.append(r)
  dupes = [k for k, v in collections.Counter(r["instrument"] for r in per).items() if v > 1]
  kinds = collections.Counter(r["kind"].split(" ")[0] for r in per)
  traced = [r for r in per if r["kind"] == "lane"]
  sites = sum(int(r["sites"]) for r in traced)
  incalled = sum(int(r["dead_in_called"] or 0) for r in traced)
  byfile = collections.defaultdict(list)
  for where, txt in dead:
    f, _, ln = where.rpartition(":")
    byfile[f].append((int(ln) if ln.isdigit() else 0, txt))
  print(f"""
DEADARM -- the tree-wide census, merged from {len(list(out.glob('shard-*.tsv')))} shard(s)

  instruments EXAMINED (every .py under .agents/slop)      {len(per)}
  with >= 1 emitting site                                 {len(per) - kinds['no-sites'] - kinds['unparsable']}
  TRACEABLE -- ran to completion AND emitted >=1 row      {len(traced)}
  emitting sites inside those traceable instruments       {sites}
  DEAD emitting lines                                    {len(dead)}
     of which in a def the lane ENTERED                   {incalled}   <- the D2 class
     of which in a def it never entered                  {len(dead) - incalled}   <- either a
        dead helper or THIS CENSUS's no-argv blindness; never counted as D2
  dead lines in                                          {len(byfile)} file(s)
  duplicate names in the same traceable lanes            {sum(int(r['dup']) for r in traced)}
     <- the OTHER census, printed beside this one because neither substitutes for the other

  every instrument NOT counted as traceable, by reason:
""" + "".join(f"    {k:<12} {v}\n" for k, v in sorted(kinds.items())))
  if dupes:
    print(f"  !! {len(dupes)} instrument name(s) in more than one shard: {dupes[:5]}"
          " -- the shards are NOT a partition and the totals above are not counts")
  else:
    print("  shard partition: every instrument name appears exactly once   OK")
  if truncated:
    # A TRUNCATED LAST ROW means a shard was SIGKILLed mid-write.  Dropping it silently is a
    # census that quietly loses an instrument, so the count is printed rather than absorbed.
    print(f"  !! {len(truncated)} truncated row(s) dropped -- a shard did not finish writing its TSV")
  if byfile:
    print("\n  THE DEAD EMITTING LINES, by file\n")
    for f in sorted(byfile, key=lambda k: -len(byfile[k]))[:60]:
      print(f"  {f.replace(str(REPO) + '/', '')}   ({len(byfile[f])})")
      for ln, txt in sorted(byfile[f])[:60]:
        print(f"      {f.replace(str(REPO) + '/', '')}:{ln:<6} {txt[:88]}")
    if len(byfile) > 60:
      print(f"  ... and {len(byfile) - 60} more file(s); the full table is the union of the shard TSVs")
  return 0


if __name__ == "__main__":
  sys.exit(main())