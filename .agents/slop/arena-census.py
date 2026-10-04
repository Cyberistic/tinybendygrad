#!/usr/bin/env python3
"""arena-census.py -- every arena READ site in tinybendygrad/, with the arena expression
and the index expression it indexes, so a mismatch is a visible pair of strings.

`O.Arena.node` is TOTAL (ops.bend:1192: `Maybe.default(&1, Node, Arena.at(ar, i), Arena.bottom())`),
so a read with the wrong arena answers `Node{OpsNOOP{}, Nil{}, ABad{}, TNone{}}` -- a value no
fixture ever mints, and therefore a value nothing reports. Every row here is one
`(arena-expr, index-expr)` pair; the classification lives in arena-alias-audit.md.

usage: arena-census.py [--tsv out.tsv]
"""
import re, sys, os, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TREE = os.path.join(ROOT, "tinybendygrad")

# The readers that INDEX. `empty`/`bottom`/`nodes`/`shp` do not take an index.
READERS = ["node", "src0", "src", "op", "arg", "tag", "srcs", "next", "nsrc",
           "src_from", "src_to", "src_without_body", "depth", "at", "budget"]

def split_top(s, sep=","):
  """split on `sep` at paren/bracket depth 0"""
  out, d, cur, q = [], 0, [], False
  i = 0
  while i < len(s):
    c = s[i]
    if c == '"':
      q = not q
    if not q:
      if c in "([{": d += 1
      elif c in ")]}": d -= 1
      elif c == sep and d == 0:
        out.append("".join(cur).strip()); cur = []; i += 1; continue
    cur.append(c); i += 1
  out.append("".join(cur).strip())
  return out

def args_from(text, open_paren):
  """return (list_of_args, close_index) for a call whose `(` is at open_paren"""
  d, cur, q = 0, [], False
  i = open_paren
  while i < len(text):
    c = text[i]
    if c == '"':
      q = not q
    if not q:
      if c in "([{": d += 1
      elif c in ")]}":
        d -= 1
        if d == 0:
          return split_top("".join(cur)), i
    cur.append(c); i += 1
  return None, None

CALL = re.compile(r"(?:O\.)?Arena\.(" + "|".join(READERS) + r")\(")

def classify(fname, lineno, reader, args):
  """SAFE / LATENT / DEFECT by the SHAPE of the two expressions. Deliberately
  conservative: anything it cannot see the provenance of is LATENT, never SAFE."""
  arena = args[0] if args else ""
  idx = args[1] if len(args) > 1 else ""
  # index is a constant / literal -> cannot be a mismatch, it is an input we chose
  lit = re.fullmatch(r"[0-9]+n?|[0-9]+", idx.strip())
  # `Arena.next(ar)` takes no index
  if reader in ("next", "budget"):
    return "SAFE", arena, idx, "no index argument; reads the arena itself"
  if lit:
    return "SAFE", arena, idx, "literal index, chosen by this reader not minted elsewhere"
  # index derived from a value that carries its own arena
  pair = re.fullmatch(r"(?:O\.)?Found\.i\((\w[\w.]*)\)", idx.strip())
  if pair:
    name = pair.group(1)
    # same expression as the arena?
    if arena.strip() == f"O.Found.ar({name})" or arena.strip() == f"Found.ar({name})":
      return "SAFE", arena, idx, "index and arena both read out of the same Found"
    return "LATENT", arena, idx, f"index is Found.i({name}) but arena is `{arena}`"
  # index is a bare parameter: provenance is the CALLER's, not visible here
  bare = re.fullmatch(r"[\w.]+", idx.strip())
  if bare:
    return "LATENT", arena, idx, "index is a parameter; its arena provenance is at the call site"
  return "LATENT", arena, idx, "computed index; provenance spans the def"

def main():
  rows = []
  for dirpath, _, files in os.walk(TREE):
    for fn in sorted(files):
      if not fn.endswith(".bend"): continue
      path = os.path.join(dirpath, fn)
      rel = os.path.relpath(path, ROOT)
      text = open(path, encoding="utf-8").read()
      lines = text.splitlines()
      for m in CALL.finditer(text):
        reader = m.group(1)
        args, _ = args_from(text, m.end() - 1)
        if args is None: continue
        lineno = text.count("\n", 0, m.start()) + 1
        cls, arena, idx, why = classify(rel, lineno, reader, args)
        rows.append((rel, lineno, "O.Arena." + reader, cls, arena, idx, why))

  tally = collections.Counter(r[3] for r in rows)
  byfile = collections.defaultdict(collections.Counter)
  for r in rows: byfile[r[0]][r[3]] += 1

  print(f"ARENA READ CENSUS -- {len(rows)} call sites in tinybendygrad/**")
  print(f"  readers counted: {', '.join(sorted(set(r[2] for r in rows)))}")
  print(f"  SAFE {tally['SAFE']}  LATENT {tally['LATENT']}  DEFECT {tally['DEFECT']}")
  print()
  print(f"{'file':52} {'SAFE':>5} {'LATENT':>7} {'DEF':>5} {'tot':>5}")
  for f in sorted(byfile):
    c = byfile[f]
    print(f"{f:52} {c['SAFE']:5} {c['LATENT']:7} {c['DEFECT']:5} {sum(c.values()):5}")

  if "--tsv" in sys.argv:
    out = sys.argv[sys.argv.index("--tsv") + 1]
    with open(out, "w", encoding="utf-8") as fh:
      fh.write("file\tline\tcall\tclass\tarena_expr\tindex_expr\twhy\n")
      for r in sorted(rows):
        fh.write("\t".join(str(x).replace("\t", " ") for x in r) + "\n")
    print(f"\nwrote {out}")

if __name__ == "__main__":
  main()