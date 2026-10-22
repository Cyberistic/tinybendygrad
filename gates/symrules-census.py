#!/usr/bin/env python3
"""symrules-census.py -- WHICH UPSTREAM REWRITE RULES THE PORT HAS, DERIVED, NOT COUNTED.

    .venv/bin/python gates/symrules-census.py            # print the census
    .venv/bin/python gates/symrules-census.py --rows     # write gates/symrules.rows
    .venv/bin/python gates/symrules-census.py --json     # machine-readable

THE QUESTION. `tinygrad/uop/symbolic.py` is the port's source. It builds FOUR pattern
matchers -- `pm_data_invalid`, `pm_remove_invalid`, `symbolic` and `sym` -- and each of
them is a list of (pattern, rewrite) rules. The port has its own four tables in
`tinybendygrad/uop/symbolic.bend`. **How many of upstream's rules does the port have, and
which ones does it not have?** Every number that has ever been written down for this was
written down by hand, and a hand count of a file with a GENERATOR in it is wrong in a way
nobody can see.

WHY THE COUNT IS AN AST COUNT AND NOT A GREP. `symbolic.py:284` is

    *((UPat.var("x").alu(op, UPat.cvar("c1")).alu(op, UPat.cvar("c2")).named("f"),
       lambda f,x,c1,c2: x.alu(f.op,c1.alu(f.op,c2))) for op in GroupOp.Associative),

ONE line of source and FIVE rules, because `GroupOp.Associative` has five members. A grep
counts one. A hand count counts one. `ast` counts one TOO -- so this file counts the
EXPANSION, by reading the comprehension's iterable against the SAME `GroupOp` the runtime
uses, and then CROSS-CHECKS the total against the runtime matcher itself
(`len(sym.patterns)`), which is the only number that cannot be wrong. If the AST count and
the runtime count disagree, this file PRINTS BOTH AND EXITS 3 (REFUSED). It does not pick
the one it likes.

WHY THE ORDER IS THE ORDER. Upstream's order is a COMPOSITION order, not a line order:
`symbolic = symbolic_simple + commutative + PatternMatcher([...]) + div_and_mod_symbolic +
pm_uncast_const`, and `symbolic_simple = pm_data_invalid + PatternMatcher([...]) +
mop_cleanup`. This file derives that order by walking the `+` tree of the assignments, so
the row order is upstream's FIRST-WINS order -- the order in which a rewrite that fires
early hides a rewrite that fires late. That order is a SEMANTIC property of the port, not
a formatting one, and it is why the port's table has to be laid out the same way.

WHAT A ROW IS. One upstream rule: its file, its line at the pin, the OP SET IT FIRES ON
(upstream's own `pdict` key set, read off the live matcher, NOT a hand list), and whether
the port has it. `port` names the port's table and tag; `MISSING` names the gap.

HOW THE PORT'S RULE IS MATCHED TO UPSTREAM'S. By the upstream line the port's own table
cites, and that citation is then CHECKED rather than trusted: the port's op set must be a
SUBSET of the upstream rule's `pdict` key set. A stale citation -- and the port's
citations WERE stale, because `tinygrad/` was re-vendored forward on 2026-10-20 and the
citations still named the previous revision's lines -- fails that subset test, because the
line it names is a DIFFERENT rule with a different op set. **So the mapping is verified
by the OPS and not asserted by the author.**

WHAT MAKES THE TABLE STABLE. A REVISION, not a timestamp and not a row count. The header
of `gates/symrules.rows` names the upstream pin (`5c2bf39d6c4b`) AND the git blob id of
every upstream file the census read, and the port's blob id for the file the census read.
Those are CONTENT-ADDRESSED: if any of those files changes, the header stops matching, and
`gates/symrules-gate.py` says so. A table that recorded a DATE would be true of the tree
on that date and of no other; a table that records a REVISION is true of exactly one
content state.

THE ONLY WRITER. `gates/symrules.rows` is written by `--rows` and by nothing else, and
`gates/symrules-gate.py` re-derives the census and diffs it against the checked-in table.
There is no second copy of the list anywhere: the port's own table is read from the
port's own source, and upstream's list is derived from upstream's source.
"""

import argparse
import ast
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# THE UPSTREAM FILES, and where each matcher they define LIVES. This is a NAME -> FILE
# map, not a list of rules: the rules are derived from the files, and the map only says
# which file a name is defined in. A name that is not here is a REFUSED census, not a
# silently-skipped matcher.
UPSTREAM = {
  "symbolic.py": os.path.join(ROOT, "tinygrad", "uop", "symbolic.py"),
  "movement.py": os.path.join(ROOT, "tinygrad", "uop", "movement.py"),
  "divandmod.py": os.path.join(ROOT, "tinygrad", "uop", "divandmod.py"),
  "weak.py": os.path.join(ROOT, "tinygrad", "uop", "weak.py"),
}
# WHERE A CROSS-FILE NAME IS DEFINED. `symbolic.py` composes three matchers that live
# elsewhere, and a census that did not follow the composition would under-count by 13.
HOME = {
  "mop_cleanup": "movement.py",
  "div_and_mod_symbolic": "divandmod.py",
  "pm_uncast_const": "weak.py",
}
PORT = os.path.join(ROOT, "tinybendygrad", "uop", "symbolic.bend")
ROWS = os.path.join(ROOT, "gates", "symrules.rows")

# THE PIN, as a NAME. The string is the human-facing one; the blob ids in the table's
# header are the machine-facing one, and the gate checks those.
PIN = "5c2bf39d6c4b"


def blob_id(path):
  """The git blob id of `path` as HEAD holds it, or its own sha256 when it is not in HEAD."""
  rel = os.path.relpath(path, ROOT)
  out = subprocess.run(["git", "rev-parse", "HEAD:" + rel], cwd=ROOT,
                       capture_output=True, text=True)
  if out.returncode == 0:
    return out.stdout.strip()
  return "sha256:" + hashlib.sha256(open(path, "rb").read()).hexdigest()


# ---------------------------------------------------------------- the AST side

def assignments(path):
  """{name: assign_node} for every top-level assignment in `path`."""
  tree = ast.parse(open(path).read(), filename=path)
  out = {}
  for node in tree.body:
    if isinstance(node, ast.Assign):
      for t in node.targets:
        if isinstance(t, ast.Name):
          out[t.id] = node
  return out


def group_sizes():
  """{group name: size}, read off the LIVE `GroupOp` -- the same object upstream uses."""
  sys.path.insert(0, ROOT)
  from tinygrad.uop.ops import GroupOp
  return {name: len(getattr(GroupOp, name)) for name in dir(GroupOp)
          if name[0].isupper() and isinstance(getattr(GroupOp, name), set)}


def rule_ops(node):
  """The `Ops.X` / `GroupOp.X` names a rule's source mentions, as a sorted list."""
  ops = set()
  for sub in ast.walk(node):
    if isinstance(sub, ast.Attribute) and isinstance(sub.value, ast.Name) \
       and sub.value.id in ("Ops", "GroupOp"):
      ops.add(sub.attr if sub.value.id == "Ops" else "GroupOp." + sub.attr)
  return sorted(ops)


def rule_vars(node):
  """The names a rule's pattern binds, as a sorted list."""
  out = set()
  for sub in ast.walk(node):
    if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute) and sub.func.attr == "var":
      if sub.args and isinstance(sub.args[0], ast.Constant):
        out.add(str(sub.args[0].value))
  return sorted(out)


def expansion(node, sizes):
  """HOW MANY RULES ONE SOURCE TUPLE IS. A tuple that holds a comprehension over a
  `GroupOp` set is that set's SIZE, and this is the whole reason a grep under-counts."""
  factor, group = 1, None
  for sub in ast.walk(node):
    if isinstance(sub, (ast.ListComp, ast.GeneratorExp)):
      for gen in sub.generators:
        if isinstance(gen.iter, ast.Attribute) and isinstance(gen.iter.value, ast.Name) \
           and gen.iter.value.id == "GroupOp":
          group = gen.iter.attr
          factor = sizes.get(group, 1)
  return factor, group


def matcher_terms(value):
  """The `+`-tree of a composition, LEFT TO RIGHT. `a + b + c` is [(a), (b), (c)]."""
  if isinstance(value, ast.BinOp) and isinstance(value.op, ast.Add):
    return matcher_terms(value.left) + matcher_terms(value.right)
  return [value]


def compose(name, where, sizes, seen=None):
  """The rules of `name`, in COMPOSITION order, as (file, line, ops, vars, factor, group)."""
  seen = seen or set()
  if name in seen:
    raise RuntimeError("composition cycle at " + name)
  seen.add(name)
  fname = where.get(name, "symbolic.py")
  path = UPSTREAM[fname]
  node = assignments(path)[name]
  out = []
  for term in matcher_terms(node.value):
    if isinstance(term, ast.Call) and isinstance(term.func, ast.Name) and term.func.id == "PatternMatcher":
      for lst in [a for a in term.args if isinstance(a, ast.List)]:
        for elt in lst.elts:
          f, g = expansion(elt, sizes)
          # ONE SOURCE TUPLE, `f` RULES. The expansion is the whole reason a grep
          # under-counts, so the tuple is emitted `f` times and the sub-index says
          # which of them this is.
          for sub in range(f):
            out.append((fname, elt.lineno, rule_ops(elt), rule_vars(elt), f, g, sub))
      continue
    if isinstance(term, ast.Name):
      out.extend(compose(term.id, where, sizes, seen))
      continue
    raise RuntimeError("unhandled term in composition of %s: %s" % (name, ast.dump(term)[:120]))
  return out


# ---------------------------------------------------------------- the runtime side

def runtime_blocks():
  """Upstream's live matchers, with the op set each rule FIRES ON, read off the matcher's
  own `pdict` -- the key set is the ops the rule is REGISTERED under, and a rule that is
  registered under an op it cannot match is exactly the defect the port's `early_reject`
  sets are about."""
  sys.path.insert(0, ROOT)
  import tinygrad.uop.symbolic as S
  from tinygrad.uop.movement import mop_cleanup
  from tinygrad.uop.divandmod import div_and_mod_symbolic
  from tinygrad.uop.weak import pm_uncast_const
  return [
    ("pm_data_invalid", S.pm_data_invalid),
    ("symbolic_simple", S.symbolic_simple),
    ("commutative", S.commutative),
    ("symbolic", S.symbolic),
    ("pm_remove_invalid", S.pm_remove_invalid),
    ("pm_simplify_valid", S.pm_simplify_valid),
    ("sym", S.sym),
  ]


def runtime_keys(matcher):
  """[{op set}] per rule, in the matcher's own order."""
  keys = {}
  for op, entries in matcher.pdict.items():
    for e in entries:
      keys.setdefault(id(e[0]), set()).add(op.name)
  return [sorted(keys.get(id(pat), [])) for pat, _fn in matcher.patterns]


# ---------------------------------------------------------------- the port side

ENTRY_RE = re.compile(r"O\.PMEntry\{(\d+),\s*(.*?),\s*(.*?)\}\s*,?\s*(?:#\s*(\d+))?\s*$")
OPS_RE = re.compile(r"O\.(Ops[A-Z0-9_]*)\{\}")
HELPER_RE = re.compile(r"^\s*def (OP_[A-Z0-9_]*)\(\) -> List<&2, O\.Op>\s*:?\s*(.*)$")


def op_helpers(src):
  """{name: [op names]} for the port's OWN op-set helpers -- `OP_CASTS()`,
  `OP_SELF()`, `OP_BINARY_3F()`. They are read from the port's source, so a helper
  the port adds is a helper the census sees, and a table entry that SPELLS its ops
  inline and one that NAMES a helper are the same kind of thing to this census.

  A helper's BODY may be on the line after its `def` (`OP_BINARY_3F` is), so the
  reader takes the def line and the next one when the def line has no list."""
  out = {}
  lines = src.splitlines()
  for i, ln in enumerate(lines):
    m = HELPER_RE.match(ln)
    if not m:
      continue
    body = m.group(2)
    j = i
    while "]" not in body and j + 1 < len(lines):
      j += 1
      body += " " + lines[j]
    out[m.group(1)] = sorted(set(o[3:] for o in OPS_RE.findall(body)))
  return out


def port_tables():
  """The port's own tables, read from the port's own source: [(table, tag, ops, cited)].

  THE CITATION IS THE LINK. Each `O.PMEntry` carries a trailing `# <line>` naming the
  upstream rule it ports, and the census resolves that line against the upstream AST.
  A citation that names a line which is not an upstream rule, or names a rule whose op
  set does not contain the port's ops, is a REFUSED mapping -- see `verify`."""
  src = open(PORT).read()
  helpers = op_helpers(src)
  tables, cur = {}, None
  for ln in src.splitlines():
    m = re.match(r"\s*def (\w+)\(\) -> O\.PMEntrys:", ln)
    if m:
      cur = m.group(1)
      tables[cur] = []
      continue
    if cur is None:
      continue
    if re.match(r"\s*def \w", ln):
      cur = None
      continue
    e = ENTRY_RE.search(ln)
    if e:
      # The port spells an op `O.OpsSTACK{}` and upstream's `op.name` is `STACK`, so
      # the `Ops` prefix is stripped: the two sides must be in the SAME SPELLING or
      # the subset test compares "OpsSTACK" against {"STACK"} and fails every rule.
      body = e.group(2)
      ops = sorted(set(o[3:] for o in OPS_RE.findall(body)))
      for h in helpers:
        if re.search(r"\b" + h + r"\(\)", body):
          ops = sorted(set(ops) | set(helpers[h]))
      tables[cur].append({"tag": int(e.group(1)), "ops": ops,
                           "cited": int(e.group(4)) if e.group(4) else None})
  return tables


# ---------------------------------------------------------------- the census

def build():
  """(rows, rm_rows, counts). `rows` is upstream's `sym` in COMPOSITION order; `rm_rows`
  is `pm_remove_invalid`, which is a SEPARATE matcher and is never composed into `sym`."""
  sizes = group_sizes()
  where = dict(HOME)
  blocks = dict(runtime_blocks())
  counts = {name: len(m.patterns) for name, m in blocks.items()}

  out = {}
  for blk in ("sym", "pm_remove_invalid"):
    a = compose(blk, where, sizes)
    r = runtime_keys(blocks[blk])
    if len(a) != len(r):
      raise RuntimeError("AST/RUNTIME COUNT MISMATCH in %s: ast=%d runtime=%d" % (blk, len(a), len(r)))
    rows = []
    for (fname, line, aops, avars, factor, group, sub), keys in zip(a, r):
      rows.append({"file": fname, "line": line, "ops": keys, "src_ops": aops,
                   "vars": avars, "factor": factor, "group": group, "sub": sub})
    out[blk] = rows
  return out["sym"], out["pm_remove_invalid"], counts


def verify(rows, rm_rows, tables):
  """Match the port's entries to upstream's rows, and REFUSE a mapping that does not hold."""
  pools = {"sym_table": rows, "rm_table": rm_rows}
  out = []
  for tname, entries in tables.items():
    pool = pools.get(tname, rows)
    for e in entries:
      up = None
      for cand in pool:
        if cand["file"] == "symbolic.py" and cand["line"] == e["cited"]:
          up = cand
          break
      if up is None:
        out.append({"table": tname, **e, "upstream": None, "why": "CITATION-NOT-AN-UPSTREAM-RULE"})
        continue
      ups = set(up["ops"])
      missing = [o for o in e["ops"] if o not in ups]
      if missing:
        out.append({"table": tname, **e, "upstream": up,
                    "why": "OPS-NOT-SUBSET:" + ",".join(missing)})
        continue
      # A STRICT SUBSET is a NARROW port: the rule fires on FEWER ops than upstream's
      # does, so the port SKIPS nodes upstream rewrites. It is not a broken mapping --
      # the mapping holds -- but it is a divergence, and it is invisible to the subset
      # test, so it gets its own state.
      why = "OK" if set(e["ops"]) == ups else "NARROW:%d-of-%d" % (len(e["ops"]), len(ups))
      out.append({"table": tname, **e, "upstream": up, "why": why})
  return out


def render(rows, rm_rows, port):
  """The `.rows` text. TAIL-separated, one line per upstream rule."""
  port_by = {}
  for p in port:
    if p["upstream"] is not None:
      port_by.setdefault((p["upstream"]["file"], p["upstream"]["line"]), []).append(p)
  L = []
  L.append("# symrules.rows -- GENERATED by `gates/symrules-census.py --rows`, which is its ONLY writer.")
  L.append("#")
  L.append("# WHAT THIS IS. One row per UPSTREAM rewrite rule, in UPSTREAM'S OWN FIRST-WINS ORDER,")
  L.append("# with the OP SET THE RULE FIRES ON (upstream's own `pdict` key set, read off the live")
  L.append("# matcher) and whether the port has it. The order is the COMPOSITION order of")
  L.append("# `tinygrad/uop/symbolic.py` -- `sym = symbolic + pm_simplify_valid + ... +")
  L.append("# pm_clean_up_group_sink` -- and NOT a line order, because the order is what decides which")
  L.append("# of two matching rewrites wins. `pm_remove_invalid` is a SEPARATE matcher and is never")
  L.append("# composed into `sym`, so its two rules are the LAST two rows and the port's `rm_table`")
  L.append("# is matched against them.")
  L.append("#")
  L.append("# WHAT MAKES IT STABLE. A REVISION, not a timestamp: the UPSTREAM PIN and the git blob id")
  L.append("# of every file this census read. Those are content-addressed, so a change to any of")
  L.append("# them makes the header stop matching and `gates/symrules-gate.py` says so. A table that")
  L.append("# recorded a DATE would be true of the tree on that date and of no other.")
  L.append("#")
  L.append("# HOW A PORT ENTRY IS MATCHED TO AN UPSTREAM RULE. By the upstream line the port's own")
  L.append("# table cites, and then CHECKED: the port's op set must be a SUBSET of the upstream rule's")
  L.append("# op set. A stale citation fails that test, because the line it names is a DIFFERENT")
  L.append("# rule with a DIFFERENT op set. `gates/symrules-gate.py` REFUSES on a mapping that does")
  L.append("# not hold; it does not print a table it cannot vouch for.")
  L.append("#")
  L.append("# COLUMNS: n | file:line | ops (the op set it fires on) | port table | port tag | state")
  L.append("#   state: PORTED  the port has it, and the op set is EQUAL to upstream's")
  L.append("#          NARROW  the port has it and the mapping holds, but the port's op set is a")
  L.append("#                  STRICT SUBSET of upstream's: the port fires on FEWER ops, so it")
  L.append("#                  SKIPS nodes upstream rewrites. A divergence, not a break.")
  L.append("#          MISSING the port has no entry for it")
  L.append("#          BROKEN  the port has an entry and the subset test FAILED")
  L.append("#")
  L.append("# UPSTREAM-PIN\t%s" % PIN)
  for rel, path in sorted(UPSTREAM.items()):
    L.append("# UPSTREAM-BLOB\t%s\t%s" % (rel, blob_id(path)))
  L.append("# PORT-BLOB\tuop/symbolic.bend\t%s" % blob_id(PORT))
  L.append("#")
  n = 0
  for row in list(rows) + list(rm_rows):
    n += 1
    cands = port_by.get((row["file"], row["line"]), [])
    ok = [p for p in cands if p["why"] == "OK"]
    nar = [p for p in cands if p["why"].startswith("NARROW")]
    bad = [p for p in cands if p["why"] != "OK" and not p["why"].startswith("NARROW")]
    if ok:
      p = ok[0]
      L.append("%d\t%s:%d\t%s\t%s\t%d\tPORTED" % (n, row["file"], row["line"],
               ",".join(row["ops"]) or "-", p["table"], p["tag"]))
    elif nar:
      p = nar[0]
      L.append("%d\t%s:%d\t%s\t%s\t%d\tNARROW:%s" % (n, row["file"], row["line"],
               ",".join(row["ops"]) or "-", p["table"], p["tag"], p["why"].split(":", 1)[1]))
    elif bad:
      p = bad[0]
      L.append("%d\t%s:%d\t%s\t%s\t%d\tBROKEN" % (n, row["file"], row["line"],
               ",".join(row["ops"]) or "-", p["table"], p["tag"]))
    else:
      L.append("%d\t%s:%d\t%s\tMISSING\t-\tMISSING" % (n, row["file"], row["line"],
               ",".join(row["ops"]) or "-"))
  return "\n".join(L) + "\n"


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--rows", action="store_true", help="write gates/symrules.rows")
  ap.add_argument("--json", action="store_true", help="machine-readable")
  ap.add_argument("--quiet", action="store_true")
  args = ap.parse_args()

  try:
    rows, rm_rows, counts = build()
  except Exception as e:  # REFUSED: a precondition was absent
    print("symrules-census: REFUSED: %s" % e, file=sys.stderr)
    return 3
  tables = port_tables()
  port = verify(rows, rm_rows, tables)

  if args.json:
    print(json.dumps({"pin": PIN, "counts": counts, "rows": rows, "rm_rows": rm_rows,
                      "port": port}, indent=1))
    return 0

  if args.rows:
    open(ROWS, "w").write(render(rows, rm_rows, port))
    if not args.quiet:
      print("symrules-census: wrote %s" % os.path.relpath(ROWS, ROOT))
    return 0

  print("UPSTREAM PIN %s" % PIN)
  for blk, c in counts.items():
    print("  %-20s %d rules" % (blk, c))
  ported = sum(1 for p in port if p["why"] == "OK")
  broken = [p for p in port if p["upstream"] is not None and p["why"] != "OK"]
  print("PORT: %d entries, %d mapped and CHECKED, %d BROKEN" % (len(port), ported, len(broken)))
  for p in broken:
    print("  BROKEN %s tag %d cites %d: %s" % (p["table"], p["tag"], p["cited"], p["why"]))
  print(render(rows, rm_rows, port))
  return 0


if __name__ == "__main__":
  sys.exit(main())
