#!/usr/bin/env python3
"""arena-audit.py -- per-DEF arena/index provenance for every arena READ in tinybendygrad/.

The census question is not "is the index a parameter" (954 of 1111 sites are, and that
classifies nothing). It is: for the read `O.Arena.X(AR, IDX)`, can AR address the node IDX
names? Two things decide it and both are LOCAL to the def:

  1. HOW IDX IS BOUND in this def. If IDX is `Found.i(f)` and AR is not `Found.ar(f)`, the
     index and the arena come from two different values -- the defect, at the call site of
     a def that hands out indices without their arena.
  2. HOW AR IS BOUND. If AR is the def's own `+ar: O.Arena` param, the arena is threaded and
     every index the def reads was minted by a caller holding THAT arena. If AR is a
     non-affine `ar: O.Arena` param the arena is COPYABLE, so a caller can hand the same
     arena to two builders and the second overwrites the first -- the defect the rules name.

So each site lands in exactly one of:

  SAFE    arena and index provably come from the same value, in this def, with no
          cross-def step in between.
  LATENT  index and arena are threaded from the caller and CANNOT be mismatched by the
          affine rules (the arena is `+`, so it is consumed once and a `Found` that grows
          it forces the grown value back through), but nothing local proves it.
  EXPOSED the index is bound from `Found.i(f)` while the arena is some OTHER expression, or
          the arena is a non-affine copyable parameter. Both are reachable by a caller.
  DEFECT  both bounds are local and they disagree -- decided here, not at a call site.

usage: arena-audit.py [--tsv out.tsv]
"""
import re, sys, os, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TREE = os.path.join(ROOT, "tinybendygrad")

READERS = ["node", "src0", "src", "op", "arg", "tag", "srcs", "next", "nsrc",
           "src_from", "src_to", "src_without_body", "depth", "at", "budget"]
NO_INDEX = {"next", "budget"}

def split_top(s, sep=","):
  out, d, cur, q = [], 0, [], False
  for i, c in enumerate(s):
    if c == '"': q = not q
    if not q:
      if c in "([{": d += 1
      elif c in ")]}": d -= 1
      elif c == sep and d == 0:
        out.append("".join(cur).strip()); cur = []; continue
    cur.append(c)
  out.append("".join(cur).strip())
  return out

def args_from(text, open_paren):
  # start AFTER the call's own `(`, so the arg list is the inside only
  d, cur, q, i = 0, [], False, open_paren + 1
  while i < len(text):
    c = text[i]
    if c == '"': q = not q
    if not q:
      if c in "([{": d += 1
      elif c in ")]}":
        d -= 1
        if d == 0: return split_top("".join(cur)), i
    cur.append(c); i += 1
  return None, None

# ---------------------------------------------------------------- def extraction
DEF_RE = re.compile(r"^def ([A-Za-z_][\w.]*)\(([^\n]*)\)" )
def parse_defs(text):
  """-> [(name, [param_names], body_start, body_end)] over the file."""
  lines = text.split("\n")
  out, i = [], 0
  while i < len(lines):
    ln = lines[i]
    m = DEF_RE.match(ln)
    if not m:
      i += 1; continue
    name, sig = m.group(1), m.group(2)
    # gather the full signature (it may wrap)
    depth = ln.count("(") - ln.count(")")
    while depth > 0 and i + 1 < len(lines):
      i += 1
      depth += lines[i].count("(") - lines[i].count(")")
    params = split_top(sig)
    start = i + 1
    d, j = 0, start
    while j < len(lines):
      s = lines[j].lstrip()
      if s.startswith("def ") and d == 0 and j != i:
        break
      d += lines[j].count("(") - lines[j].count(")") + \
           lines[j].count("[") - lines[j].count("]") + \
           lines[j].count("{") - lines[j].count("}")
      if d < 0: break
      j += 1
    out.append((name, params, start, j))
    i = j
  return out, lines

def param_affine(p):
  return "+" in p

def find_local_binds(body_lines, varname):
  """`(ar, i) = f` or `ar = f` destructuring that binds varname."""
  binds = []
  for bl in body_lines:
    s = bl.strip()
    m = re.match(r"^(?:\(([^)]*)\)|([\w.]+))\s*=\s*(.+)$", s)
    if not m: continue
    tgt = m.group(1) if m.group(1) is not None else m.group(2)
    if tgt is None: continue
    parts = split_top(tgt)
    if varname in parts:
      pos = parts.index(varname)
      binds.append((pos, parts, m.group(3).strip()))
  return binds

CALL_RE = re.compile(r"(?:O\.)?Arena\.(" + "|".join(READERS) + r")\(")

def norm(e):
  e = e.strip()
  e = re.sub(r"^O\.", "", e)
  return e

def classify(reader, args, params, body_lines):
  arena, idx = norm(args[0]), (norm(args[1]) if len(args) > 1 else "")
  param_names = []
  for p in params:
    p = re.sub(r"^\+\s*", "", p).strip()
    p = p.split(":")[0].strip()
    if p: param_names.append(p)
  affine = {re.sub(r"^\+\s*", "", p).strip().split(":")[0].strip()
            for p in params if param_affine(p)}
  allparam = set(param_names)

  if reader in NO_INDEX:
    return "SAFE", arena, idx, "reads the arena itself; takes no index"

  # CASE 1: index and arena out of the SAME Found.
  m = re.fullmatch(r"(?:O\.)?Found\.i\((.+)\)", idx)
  if m:
    src = m.group(1).strip()
    if arena in (f"Found.ar({src})",):
      return "SAFE", arena, idx, f"Found.i({src}) with Found.ar({src}): the pair cannot disagree"
    # the arena is a local binder that was bound from the same Found's ar
    binds = find_local_binds(body_lines, arena)
    if any(any(f"Found.ar({src})" in v for v in b[2].split(", ")) or
             re.search(r"Found\.ar\(" + re.escape(src), b[2]) for b in binds):
      return "SAFE", arena, idx, f"`{arena}` bound from Found.ar({src}) in this def"
    # is ARENA a parameter? then the caller decides -- EXPOSED
    if arena in allparam:
      return ("SAFE" if arena in affine else "EXPOSED"), arena, idx, \
        (f"`{arena}` is a +affine+ arena param: consumed once, so the caller cannot have read "
         f"a node it minted into a DIFFERENT copy"
         if arena in affine else
         f"`{arena}` is a NON-affine (copyable) arena param: a caller can pass the same arena "
         f"to two builders and the second overwrites the first")
    return "EXPOSED", arena, idx, \
      f"index is Found.i({src}) but arena is `{arena}` -- two different values"

  # CASE 2: index is a literal. Nothing minted it, so it is a caller-chosen constant.
  if re.fullmatch(r"[0-9]+n?", idx):
    return "SAFE", arena, idx, "literal index, not an index anything minted"

  # CASE 3: index is a local binder from a destructuring of a Found.
  binds = find_local_binds(body_lines, idx)
  found_src = None
  for pos, parts, rhs in binds:
    for mm in re.finditer(r"Found\.i\((\w[\w.]*)\)", rhs):
      # which position of the pair does this binder sit at?
      lhs = f"Found{{ar, i}}" if "Found.ar" in rhs else None
      if lhs and "case" in body_lines[0]:
        pass
      found_src = (mm.group(1), parts[pos], rhs)
      break
    if found_src: break
  if found_src:
    src, binder, rhs = found_src
    if "Found.ar" in rhs:
      # the case binder names both halves; which one is this index / this arena?
      cmap = dict(re.findall(r"Found\.ar\((\w[\w.]*)\)|case\s+Found\{ar,\s*i\}|(\w+)\s*<>\s*(\w+)", ""))
      # resolve by scanning the case arms that bind this Found
      arms = re.findall(r"case\s+Found\{([^}]*)\}:\s*\(?\s*([A-Za-z_][\w.]*)\s*,\s*([A-Za-z_][\w.]*)", "\n".join(body_lines))
      pairs = [(a.strip(), b) for a, b in arms]
      this_is_i = any(re.fullmatch(re.escape(binder), b) and binder != src for a, b in pairs)
      if any(a == arena and binder != arena for a, b in pairs):
        return "SAFE", arena, idx, f"`{arena}` and `{idx}` are the two halves of one Found"
    return "EXPOSED", arena, idx, \
      f"`{idx}` bound from {rhs} but arena is `{arena}`"

  # CASE 4: index is a plain parameter of this def.
  if idx in allparam:
    if arena == idx:
      return "SAFE", arena, idx, "index == arena name is not an index; def reads its own arena"
    if arena in affine:
      return "SAFE", arena, idx, \
        (f"`{arena}` is affine (+): it is consumed exactly once on this path, so any node the "
         f"caller minted for `{idx}` was minted into this same arena. The linear rules, not a "
         f"row, are the proof.")
    if arena in allparam:
      return "EXPOSED", arena, idx, f"`{arena}` is copyable; nothing stops a caller passing two arenas"
    return "LATENT", arena, idx, f"index `{idx}` is a parameter, arena `{arena}` is computed here"

  # CASE 5: computed index.
  return "LATENT", arena, idx, "computed index; provenance spans the def"

def main():
  rows = []
  for dirpath, _, files in os.walk(TREE):
    for fn in sorted(files):
      if not fn.endswith(".bend"): continue
      path = os.path.join(dirpath, fn)
      rel = os.path.relpath(path, ROOT)
      text = open(path, encoding="utf-8").read()
      defs, lines = parse_defs(text)
      # map each line -> enclosing def
      owner = {}
      for (nm, params, s, e) in defs:
        for ln in range(s, min(e, len(lines))):
          owner[ln + 1] = (nm, params)
      for m in CALL_RE.finditer(text):
        reader = m.group(1)
        args, _ = args_from(text, m.end() - 1)
        if args is None: continue
        lineno = text.count("\n", 0, m.start()) + 1
        nm, params = owner.get(lineno, ("<file toplevel>", []))
        body = lines[max(0, lineno - 1):]
        cls, arena, idx, why = classify(reader, args, params, body)
        rows.append((rel, lineno, nm, "O.Arena." + reader, cls, arena, idx, why,
                     "|".join(re.sub(r"^\+\s*", "", p).strip() for p in params)))

  tally = collections.Counter(r[4] for r in rows)
  byfile = collections.defaultdict(collections.Counter)
  for r in rows: byfile[r[0]][r[4]] += 1

  print(f"ARENA READ AUDIT -- {len(rows)} call sites in tinybendygrad/**")
  print(f"  SAFE {tally['SAFE']}   LATENT {tally['LATENT']}   EXPOSED {tally['EXPOSED']}   DEFECT {tally['DEFECT']}")
  print()
  hdr = f"{'file':46} {'SAFE':>5} {'LATENT':>7} {'EXPOSED':>8} {'DEF':>4} {'tot':>5}"
  print(hdr); print("-" * len(hdr))
  for f in sorted(byfile):
    c = byfile[f]
    print(f"{f:46} {c['SAFE']:5} {c['LATENT']:7} {c['EXPOSED']:8} {c['DEFECT']:4} {sum(c.values()):5}")
  print()
  exp = [r for r in rows if r[4] == "EXPOSED"]
  print(f"EXPOSED sites, by reason ({len(exp)}):")
  byreason = collections.Counter(r[7][:60] for r in exp)
  for k, v in byreason.most_common():
    print(f"  {v:5}  {k}")

  if "--tsv" in sys.argv:
    out = sys.argv[sys.argv.index("--tsv") + 1]
    with open(out, "w", encoding="utf-8") as fh:
      fh.write("file\tline\tdef\tcall\tclass\tarena_expr\tindex_expr\twhy\tparams\n")
      for r in sorted(rows):
        # a field may contain a newline (a multi-line call), which would split one row
        # into two and make the TSV row count disagree with the tally above
        fh.write("\t".join(re.sub(r"[\t\r\n]+", " ", str(x)) for x in r) + "\n")
    print(f"\nwrote {out}")

if __name__ == "__main__":
  main()