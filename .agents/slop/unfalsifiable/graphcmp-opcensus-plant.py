#!/usr/bin/env python3
"""graphcmp-opcensus-plant.py -- the op census's denominator, and its vocabulary.

TWO CLAIMS IN `.agents/slop/graphcmp-LIMITS.md`, both checked here by CALLING, not by
reading the numbers out of prose:

  1. "(CROSSED THROUGH IN ROUND THREE, and these are the ten: ...)" -- a denominator
     the file publishes about ITSELF. MEASURED through the census itself
     (`census(G.emit_py(g))["ops"]`, the very call the oracle makes -- NOT a second
     walk, because a second reader is what forked the counts in the first place), the
     set is ELEVEN: `CMPLT` was reached and was not named. The file's own word beside
     its own list is checked against the list, so the prose cannot drift from itself.

  2. "N of 77 ops" -- `tot_ops` was a `set[str]` of whatever `unchunks(ln)[1]`
     yields, with nothing asserting those names are members of `Ops`. So an invented
     name became a 35th reached op and the census's SELFCHECK still printed OK at
     rc=0: a coverage number that accepts a word outside its own vocabulary cannot
     tell you the vocabulary was covered.

THE PLANT IS ON `emit_py`, NOT `emit_bend`, and that is deliberate. `emit_py` is pure
Python; `emit_bend` spawns `./bin/bend` on `graphcmp.bend`, which imports
`tinybendygrad/uop/ops.bend` -- a file under another unit's single ownership, and
MEASURED BROKEN while this ran (its first line reads
`set_end_none=Ops.AFTER(Ops.BUFFER Ops.STORE)`, so `graphcmp.bend` answers
`SOME PROOFS FAIL / Error: - expected : n` and `emit_bend` raises after 5 attempts).
Planting the py side keeps the measurement of MY change independent of another unit's
mid-edit. Same code path either way: both sides feed the same `census()`.

RUN:
  env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python \\
    .agents/slop/unfalsifiable/graphcmp-opcensus-plant.py
"""
import collections
import contextlib
import importlib.util
import io
import os
import re
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
sys.path.insert(0, REPO)
sys.path.insert(0, SLOP)

# The numeral WORD the file uses beside its list, so the prose's own count is checked
# against the names beside it rather than against a number transcribed into this file.
WORDS = {8: "eight", 9: "nine", 10: "ten", 11: "eleven", 12: "twelve"}


def declared():
  """(claimed_count_word, [names]) READ OUT OF graphcmp-LIMITS.md.

  The names are the run of comma-separated UPPERCASE tokens between the colon and the
  `--`, so `IF` is included. A first attempt regexed `\\b[A-Z][A-Z_0-9]{2,}\\b`, which
  needs three characters and silently dropped `IF` -- reporting NINE names for a list
  the file calls ten, the same defect one layer down."""
  txt = open(os.path.join(SLOP, "graphcmp-LIMITS.md")).read()
  i = txt.index("(CROSSED THROUGH IN ROUND THREE")
  j = txt.index(")", i)
  body = txt[i:j]
  claimed = re.search(r"these are the (\w+):", body).group(1)
  tail = body.split(":", 1)[1].split("--")[0]
  return claimed, [w.strip() for w in tail.split(",") if w.strip()]


def per_graph_ops(G, census):
  """WHICH graphs reach which op, through the census -- not a second walk."""
  where = collections.defaultdict(list)
  for g in sorted(G.GRAPHS):
    for nm in census(G.emit_py(g, None))["ops"]:
      where[nm].append(g)
  return where


def invent(lines, G, name):
  """Append ONE well-formed wire line naming an op that is not in `Ops`. The wire is
  LENGTH-PREFIXED (`5:ALLOC`), so the prefix must carry the new length; keeping `5:`
  and writing `INVENTED` desynchronises `unchunks`, which then raises
  `ValueError: invalid literal for int() ... 'TED 3'`. That is how the first attempt at
  this plant failed to land, silently, at 34."""
  tmpl = next(ln for ln in lines if len(G.unchunks(ln)) == 8)
  parts = tmpl.split(" ")
  newid = "i9999"
  parts[0] = str(len(newid)) + ":" + newid
  parts[1] = str(len(name)) + ":" + name
  out = list(lines) + [" ".join(parts)]
  assert G.unchunks(out[-1])[1] == name, "the invented line did not parse"
  assert G.unchunks(out[-1])[0] == newid, "the invented line's id did not parse"
  return out


def run_oracle(G, O):
  """The oracle's REAL main(), captured. `G` here must be the module object the oracle
  itself imported -- `graphcmp-oracle.py` does `import graphcmp as G`, so the module is
  in sys.modules under the name `graphcmp`. The first attempt of this file patched a
  second, separately-loaded copy of graphcmp.py and the plant did not land at all."""
  buf = io.StringIO()
  try:
    with contextlib.redirect_stdout(buf):
      rc = O.main()
  except SystemExit as e:
    return buf.getvalue(), -1, str(e).splitlines()[0] if str(e) else "SystemExit"
  return buf.getvalue(), rc, ""


def report(label, out, rc, err):
  hdr = [ln for ln in out.splitlines() if ln.startswith("# TOTAL")]
  voc = [ln for ln in out.splitlines() if "OP NAMES ALL IN Ops" in ln]
  chk = [ln for ln in out.splitlines() if "SELFCHECK" in ln]
  n = re.search(r"(\d+) distinct ops", hdr[0]).group(1) if hdr else "?"
  print(f"  {label}")
  print(f"    distinct ops            : {n}")
  print(f"    vocabulary line         : {voc[0].lstrip('# ') if voc else '(absent)'}")
  print(f"    SELFCHECK               : {chk[0].split('SELFCHECK: ')[-1] if chk else '(absent)'}")
  if err:
    print(f"    RAISED                  : {err[:90]}")
  print(f"    rc                      : {rc}")
  named = [ln for ln in out.splitlines() if "NOT\n" in ln or "UNKNOWN" in ln
           or "NOT members of Ops" in ln]
  for ln in named[:3]:
    print(f"    NAMED IT                : {' '.join(ln.split())[:150]}")
  return n, chk[0] if chk else "", rc


def main():
  import graphcmp as G                      # the name the oracle itself imports
  spec = importlib.util.spec_from_file_location(
    "gc_oracle", os.path.join(SLOP, "graphcmp-oracle.py"))
  O = importlib.util.module_from_spec(spec)
  sys.modules["gc_oracle"] = O
  spec.loader.exec_module(O)
  G.load_tinygrad()
  ops = {o.name for o in list(G.Ops)}

  print("=" * 78)
  print("1  THE DECLARED LIST, read out of graphcmp-LIMITS.md itself")
  claimed, ten = declared()
  print(f"    the file says 'these are the {claimed}' and names {len(ten)}: {ten}")

  print("=" * 78)
  print("2  WHICH GRAPHS REACH EACH -- through the census, per graph")
  where = per_graph_ops(G, O.census)
  # `ten + ["CMPLT"]` deduped: CMPLT is now NAMED in the file, and listing it twice
  # made the report read as if the file still omitted it.
  for name in dict.fromkeys(ten + ["CMPLT", "WHERE", "CMPNE"]):
    print(f"    {name:10s} {sorted(set(where.get(name, []))) or 'NOT REACHED'}")
  reached = sorted({n for n in ten + ["CMPLT"] if where.get(n)})
  missing = [n for n in reached if n not in ten]
  print(f"    -> reached but NOT named in the file: {missing or 'none'}")
  print(f"    -> the file's word '{claimed}' vs the {len(ten)} names it lists: "
        f"{'CONSISTENT' if claimed == WORDS.get(len(ten)) else 'INCONSISTENT'}")
  print(f"    -> every named op is an Ops member: {all(n in ops for n in reached)}")

  print("=" * 78)
  print("3  BASELINE -- the census as committed")
  base_n, base_chk, base_rc = report("baseline", *run_oracle(G, O))

  print("=" * 78)
  print("4  PLANT -- one well-formed wire line naming `INVENTED`, on the PY side")
  print("   (bend-free by choice; see the docstring on the other unit's broken ops.bend)")
  orig = G.emit_py
  G.emit_py = lambda g, p: invent(orig(g, p), G, "INVENTED")
  n, chk, rc = report("PLANTED", *run_oracle(G, O))
  G.emit_py = orig
  print(f"    the count MOVED {base_n} -> {n}: {n != base_n}   (a plant that does not "
        f"move is not a plant)")
  print(f"    SELFCHECK went OK -> {chk.split('SELFCHECK: ')[-1]}: "
        f"{'FAIL' in chk}")
  print(f"    rc is nonzero: {rc != 0}")

  print("=" * 78)
  print("5  DISARM -- the census restored, nothing invented")
  n2, chk2, rc2 = report("DISARMED", *run_oracle(G, O))
  print(f"    identical to the baseline: {n2 == base_n and chk2 == base_chk and rc2 == base_rc}")
  return 0


if __name__ == "__main__":
  sys.exit(main())