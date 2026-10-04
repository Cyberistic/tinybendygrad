#!/usr/bin/env python3
"""arena-stale.py -- find reads where the INDEX came out of one arena and the ARENA is
something else. The `codegen/__init__.bend:117` shape, generalised.

The proven defect was: call `O.UOp.new(ar, ...)` (which GROWS `ar` and returns
`Found{grown, i}`), keep only `Found.i(f)`, and then read index `i` against the arena the
engine still holds. `Arena.node` is total, so that read answers `Node{OpsNOOP{}, ...}` --
a value nothing mints and nothing reports.

Two ways that shape appears, and both are searched here:

  A. WITHIN ONE EXPRESSION: `O.Arena.<r>(ar, O.Found.i(f))` where `ar` is not `Found.ar(f)`.
     One line, decidable, and every hit is a read whose index is guaranteed to be from a
     different arena than the one it is looked up in -- unless `f` was minted into `ar`, in
     which case `ar` is the STALE copy and `f`'s index may be past the end. Either way the
     two are not the same value and the linear types do not say which.

  B. ACROSS A DEF BOUNDARY: a def that takes a U32 index and an Arena, where the index is
     obtained from a `Found` whose arena the CALLER supplies separately. Enumerated as
     (caller-arg-of-index, arena-arg) pairs, so a hand-check can see them.

usage: arena-stale.py [--tsv out.tsv]
"""
import re, sys, os, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TREE = os.path.join(ROOT, "tinybendygrad")

READERS = ["node", "src0", "src", "op", "arg", "tag", "srcs", "nsrc",
           "src_from", "src_to", "src_without_body", "depth", "at"]
NO_INDEX = {"budget"}

def split_top(s, sep=","):
  out, d, cur, q = [], 0, [], False
  for c in s:
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
  """args of the call whose `(` is at open_paren, plus the index of its `)`.

  The depth counter starts AT the call's own bracket, so the matching `)` is the one that
  brings it back to 0. Starting after it -- the obvious-looking version -- leaves depth at
  -1 on that paren, the return never fires, and the arg list runs to the end of the file.
  That is SILENT: it produced a 346-row audit on garbage expressions before it was caught,
  so the counter is written to make the failure impossible rather than to be short.
  """
  d, cur, q, i = 0, [], False, open_paren
  while i < len(text):
    c = text[i]
    if i == open_paren:
      d += 1; i += 1; continue
    if c == '"': q = not q
    if not q:
      if c in "([{": d += 1
      elif c in ")]}":
        d -= 1
        if d == 0: return split_top("".join(cur)), i
    cur.append(c); i += 1
  return None, None

CALL = re.compile(r"(?:O\.)?Arena\.(" + "|".join(READERS) + r")\(")
FI = re.compile(r"(?:O\.)?Found\.i\(")

def strip_comments(text):
  """Blank out `# ...` to end of line, PRESERVING every offset.

  Bend comments carry quotes -- `\"long as 2 ints\"` is a comment, not a string -- and a
  naive quote tracker latches on one and never closes it, so every bracket after it is
  counted at the wrong depth and the arg split runs to the end of the file.
  """
  out, in_str, i = [], False, 0
  while i < len(text):
    c = text[i]
    if in_str:
      out.append(c)
      if c == "\\": out.append(text[i + 1]); i += 2; continue
      if c == '"': in_str = False
      i += 1; continue
    if c == '"': in_str = True; out.append(c); i += 1; continue
    if c == "#":
      while i < len(text) and text[i] != "\n": out.append(" "); i += 1
      continue
    out.append(c); i += 1
  return "".join(out)

def main():
  rows = []
  for dirpath, _, files in os.walk(TREE):
    for fn in sorted(files):
      if not fn.endswith(".bend"): continue
      path = os.path.join(dirpath, fn)
      rel = os.path.relpath(path, ROOT)
      text = open(path, encoding="utf-8").read()
      scan = strip_comments(text)   # same offsets, no comment quotes
      lines = text.split("\n")
      # the def each line belongs to, with its signature
      owner = {}
      cur_def = ("<file toplevel>", [])
      for i, ln in enumerate(lines):
        m = re.match(r"^def ([\w.]+)\((.*)$", ln)
        if m:
          sig, d = m.group(2), ln.count("(") - ln.count(")")
          while d > 0 and i + 1 < len(lines):
            i += 1; sig += lines[i]; d += lines[i].count("(") - lines[i].count(")")
          cur_def = (m.group(1), split_top(sig[:-1] if sig.endswith(")") else sig))
        owner[i + 1] = cur_def

      for m in CALL.finditer(scan):
        reader = m.group(1)
        args, close = args_from(scan, m.end() - 1)
        if args is None or reader in NO_INDEX: continue
        # find every Found.i( ... ) inside the INDEX argument (arg 1)
        if len(args) < 2: continue
        idx_arg = args[1]
        arena_arg = args[0]
        for fm in FI.finditer(idx_arg):
          # the balanced span of the Found.i( ... ) call
          sub = args_from(idx_arg, fm.end() - 1)
          if sub is None or not sub[0]: continue
          src = sub[0][0].strip()
          if re.sub(r"^O\.", "", arena_arg.strip()) == f"Found.ar({src})":
            continue   # the good shape: index and arena out of one Found
          lineno = text.count("\n", 0, m.start()) + 1
          defnm, params = owner.get(lineno, ("?", []))
          rows.append((rel, lineno, defnm, "O.Arena." + reader,
                       arena_arg.strip(), idx_arg.strip(), src,
                       "|".join(re.sub(r"^\+\s*", "", p).split(":")[0].strip() for p in params)))

  print(f"STALE-ARENA CANDIDATES -- {len(rows)} reads whose INDEX is Found.i(...) "
        f"but whose ARENA is a different expression")
  byfile = collections.Counter(r[0] for r in rows)
  for f, n in byfile.most_common():
    print(f"  {n:4}  {f}")
  print()
  for r in sorted(rows):
    print(f"{r[0]}:{r[1]}  in {r[2]}")
    print(f"    read   {r[3]}({r[4]}, {r[5]})")
    print(f"    from   Found.i({r[6]})   [the index's own arena is Found.ar({r[6]})]")
    print(f"    params {r[7]}")
  if "--tsv" in sys.argv:
    out = sys.argv[sys.argv.index("--tsv") + 1]
    with open(out, "w", encoding="utf-8") as fh:
      fh.write("file\tline\tdef\tcall\tarena_expr\tindex_expr\tfound_src\tparams\n")
      for r in sorted(rows):
        fh.write("\t".join(re.sub(r"[\t\r\n]+", " ", str(x)) for x in r) + "\n")
    print(f"\nwrote {out}")

if __name__ == "__main__":
  main()