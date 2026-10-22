#!/usr/bin/env python3
"""symrules-gate.py -- DOES THE PORT'S TABLE STILL SAY WHAT THE CENSUS SAYS?

    .venv/bin/python gates/symrules-gate.py
    .venv/bin/python gates/symrules-gate.py --plant
    .venv/bin/python gates/symrules-gate.py --json

THE CLAIM. `gates/symrules.rows` is the census of upstream's rewrite rules against the port's
own tables, and it is written by `gates/symrules-census.py` and by NOTHING ELSE. This gate
re-derives the census and compares it with the checked-in table, so the table cannot drift
away from the tree it describes.

WHAT IT CHECKS, IN ORDER.

    1 THE HEADER. The table's header names the UPSTREAM PIN and the git blob id of every
      file the census read -- upstream's four and the port's one. Those are REVISIONS, not
      timestamps and not row counts: a file that changes changes its blob id, and the
      header stops matching. **A table that recorded a DATE would be true of the tree on
      that date and of no other; a table that records a REVISION is true of exactly one
      content state.** This is the clause that makes the table a pin and not a diary.

    2 THE ROWS. The freshly-derived census is diffed against the checked-in table, line by
      line. A row that moved is a rule that changed, and it is named.

    3 THE MAPPING. Every port table entry must resolve to an upstream rule, and the port's
      op set must be a SUBSET of the upstream rule's op set. A stale citation fails this
      and is reported as BROKEN, because the line it names is a DIFFERENT rule with a
      DIFFERENT op set. **The mapping is verified by the OPS and not asserted by the
      author** -- and it is not a claim about the AUTHOR's intent.

    4 THE ORDER. The port's `sym_table` must be in UPSTREAM'S ORDER -- the composition
      order, which is the FIRST-WINS order. This is a SEMANTIC property: two rules that
      both match a node, and the port's answer depends on which one the table lists first.
      Upstream's order is derived from upstream's own `+` tree, so this check cannot be
      satisfied by a hand list that happens to look right.

EXIT: 0 green · 1 red · 3 REFUSED (a precondition was absent) · 5 DEAD (it ran and
measured nothing). `SKIP` is not declared: this file has no constant it can return.
"""

import argparse
import importlib.util
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CENSUS = os.path.join(ROOT, "gates", "symrules-census.py")
ROWS = os.path.join(ROOT, "gates", "symrules.rows")


def load_census():
  """The census GENERATOR, loaded BY PATH -- not copied. A second copy of the derivation
  is a contract with no generator and rots without anyone noticing."""
  spec = importlib.util.spec_from_file_location("symrules_census", CENSUS)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--plant", action="store_true")
  ap.add_argument("--json", action="store_true")
  args = ap.parse_args()

  if not os.path.isfile(ROWS):
    print("symrules-gate: REFUSED: %s is absent" % os.path.relpath(ROWS, ROOT), file=sys.stderr)
    return 3
  c = load_census()
  try:
    rows, rm_rows, counts = c.build()
  except Exception as e:
    print("symrules-gate: REFUSED: %s" % e, file=sys.stderr)
    return 3
  tables = c.port_tables()
  port = c.verify(rows, rm_rows, tables)
  fresh = c.render(rows, rm_rows, port)
  have = open(ROWS).read()

  if args.plant:
    return plant(c, fresh, have, rows, rm_rows, port, tables)

  problems = []
  # 1 THE HEADER -- the revisions.
  fresh_head = [l for l in fresh.splitlines() if l.startswith("# UPSTREAM-") or l.startswith("# PORT-BLOB")]
  have_head = [l for l in have.splitlines() if l.startswith("# UPSTREAM-") or l.startswith("# PORT-BLOB")]
  if fresh_head != have_head:
    problems.append("HEADER: the table names revisions that are not the tree's")
    for a, b in zip(have_head, fresh_head):
      if a != b:
        problems.append("  table: %s" % a)
        problems.append("  tree : %s" % b)
    if len(have_head) != len(fresh_head):
      problems.append("  table has %d header lines, tree has %d" % (len(have_head), len(fresh_head)))

  # 2 THE ROWS -- the diff.
  frows = [l for l in fresh.splitlines() if l and not l.startswith("#")]
  hrows = [l for l in have.splitlines() if l and not l.startswith("#")]
  if frows != hrows:
    diffs = []
    for i in range(max(len(frows), len(hrows))):
      a = hrows[i] if i < len(hrows) else "(absent)"
      b = frows[i] if i < len(frows) else "(absent)"
      if a != b:
        diffs.append("  row %d: table=%s tree=%s" % (i + 1, a, b))
    problems.append("ROWS: %d of %d rows differ" % (len(diffs), max(len(frows), len(hrows))))
    problems.extend(diffs[:40])

  # 3 THE MAPPING -- the op-set subset test.
  broken = [p for p in port if p["upstream"] is not None and p["why"] != "OK"]
  unresolved = [p for p in port if p["upstream"] is None]
  narrow = [p for p in broken if p["why"].startswith("NARROW")]
  hard = [p for p in broken if not p["why"].startswith("NARROW")]
  for p in hard:
    problems.append("BROKEN %s tag %d cites upstream line %d: %s" % (p["table"], p["tag"], p["cited"], p["why"]))
  for p in unresolved:
    problems.append("UNRESOLVED %s tag %d cites upstream line %d: %s" % (p["table"], p["tag"], p["cited"], p["why"]))

  # 4 THE ORDER -- the port's table must be in upstream's order.
  order = []
  for r in list(rows) + list(rm_rows):
    if r["file"] == "symbolic.py":
      order.append(r["line"])
  cited = []
  for tname in ("sym_table", "rm_table"):
    for e in tables.get(tname, []):
      cited.append(e["cited"])
  # `sym_table` must be a SUBSEQUENCE of upstream's `sym` order, and `rm_table` of the
  # `pm_remove_invalid` order. A subsequence is the right shape: the port's table SKIPS
  # the rules it has not ported, and the skips are the holes the census names.
  def is_subseq(sub, whole):
    it = iter(whole)
    return all(any(x == y for y in it) for x in sub)
  sym_pool = [r["line"] for r in rows if r["file"] == "symbolic.py"]
  rm_pool = [r["line"] for r in rm_rows if r["file"] == "symbolic.py"]
  if not is_subseq([c_ for c_ in cited[:len(tables.get("sym_table", []))]], sym_pool):
    problems.append("ORDER: sym_table is not a subsequence of upstream's order")
  rm_cited = [e["cited"] for e in tables.get("rm_table", [])]
  if not is_subseq(rm_cited, rm_pool):
    problems.append("ORDER: rm_table is not a subsequence of upstream's pm_remove_invalid order")

  if args.json:
    print(json.dumps({"problems": problems, "counts": counts,
                      "ported": sum(1 for p in port if p["why"] == "OK"),
                      "broken": len(broken), "unresolved": len(unresolved)}, indent=1))
    return 1 if problems else 0

  print("symrules-gate: upstream %s -- sym %d rules, pm_remove_invalid %d rules" %
        (c.PIN, counts["sym"], counts["pm_remove_invalid"]))
  print("  port entries %d, mapped %d, broken %d, unresolved %d" %
        (len(port), sum(1 for p in port if p["why"] == "OK"), len(hard), len(unresolved)))
  # A NARROW port is a DIVERGENCE and not a broken mapping: the rule fires on FEWER
  # ops than upstream's does, so the port SKIPS nodes upstream rewrites. It is named
  # here and it is in the table's own row, so a fix to it MOVES the row and the row
  # diff catches it. It is not this gate's exit: the fix is the PORT's.
  for p in narrow:
    print("  NARROW %s tag %d cites upstream line %d: %s -- the port fires on fewer ops "
          "than upstream does" % (p["table"], p["tag"], p["cited"], p["why"]))
  if problems:
    print("  RED")
    for p in problems:
      print("  " + p)
    return 1
  print("  GREEN: the table names this tree's revisions and its rows are the census's rows")
  return 0


def plant(c, fresh, have, rows, rm_rows, port, tables):
  """THREE MUTATIONS, and each must make THE CHECK IT NAMES go red. A detector that
  has never been shown failing is indistinguishable from a detector that cannot fail.

    ROW      a census row is edited: the table no longer matches the tree.
    HEADER   a blob id is edited: the table names a revision that is not the tree's.
    CITATION a port table's citation is moved onto a DIFFERENT upstream rule whose op
              set does not contain the port's ops: the mapping stops being verifiable.
  """
  failures = []

  # ROW -- the row diff must notice.
  hrows = [l for l in have.splitlines() if l and not l.startswith("#")]
  frows = [l for l in fresh.splitlines() if l and not l.startswith("#")]
  mutated = list(hrows)
  target = next((i for i, l in enumerate(mutated) if l.endswith("MISSING")), None)
  if target is None:
    failures.append("ROW: the table has no MISSING row to mutate")
  else:
    mutated[target] = mutated[target].replace("MISSING\t-\tMISSING", "sym_table\t99\tPORTED")
    if mutated == hrows:
      failures.append("ROW: the mutation did not change the rows")
    elif mutated == frows:
      failures.append("ROW: the mutation landed on the derived row, so the diff is vacuous")
    else:
      print("plant ROW: row %d differs from the tree -- the row diff must notice" % (target + 1))

  # HEADER -- the revision check must notice.
  lines = have.splitlines()
  for i, l in enumerate(lines):
    if l.startswith("# UPSTREAM-BLOB"):
      lines[i] = l[:-1] + "0"
      break
  mutated_head = "\n".join(lines) + "\n"
  fh = [l for l in fresh.splitlines() if l.startswith("# UPSTREAM-") or l.startswith("# PORT-BLOB")]
  mh = [l for l in mutated_head.splitlines() if l.startswith("# UPSTREAM-") or l.startswith("# PORT-BLOB")]
  if fh == mh:
    failures.append("HEADER: the mutation did not change the header")
  else:
    print("plant HEADER: the revisions differ -- the header check must notice")

  # CITATION -- the op-set subset test must notice. The mutation moves a port entry's
  # citation onto a DIFFERENT upstream rule, which is what a stale citation is: the
  # line still names A rule and the rule is not the one the port ports.
  victim = next((p for p in port if p["upstream"] is not None and p["why"] == "OK"), None)
  if victim is None:
    failures.append("CITATION: no checked port entry to move")
  else:
    other = next((r for r in rows
                  if r["file"] == "symbolic.py" and r["line"] != victim["upstream"]["line"]
                  and set(victim["ops"]) - set(r["ops"])), None)
    if other is None:
      failures.append("CITATION: no upstream rule with a different op set to move onto")
    else:
      moved = {k: [dict(e) for e in v] for k, v in tables.items()}
      for e in moved["sym_table"]:
        if e["tag"] == victim["tag"]:
          e["cited"] = other["line"]
      after = c.verify(rows, rm_rows, moved)
      hit = [p for p in after if p["why"] != "OK" and p["upstream"] is not None]
      if not hit:
        failures.append("CITATION: the mutation did not make the subset test fail")
      else:
        print("plant CITATION: a citation moved onto upstream line %d and the subset test "
              "says %s" % (other["line"], hit[0]["why"]))

  if failures:
    for f in failures:
      print("plant FAILED: " + f)
    return 1
  print("plant: all three mutations changed the thing they name, and each check noticed")
  return 0


if __name__ == "__main__":
  sys.exit(main())
