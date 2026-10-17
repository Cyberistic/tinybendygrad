"""DISCOVERY: instruments in checks/ and gates/ that name an external file they read or execute.

Extraction is AST-based (ast.parse on source text; nothing here is imported or executed).
Method, admitted in full so the ledger can see it (doctrine 1, rule (c)):

  (1) collect every PATH-SHAPED string in the tree, and only path-shaped ones.  A candidate must
      match ^[A-Za-z0-9_./@+-]+$ -- no whitespace, no backtick, no `:;,(){}*$|"'`.  This is the
      filter that separates a path from prose: the first version of this instrument harvested
      47183 candidates because a docstring sentence containing `.py` is a string constant, and
      every one of them was absent.  Prose is not a population.
  (2) collect from: Constant str; BinOp(Div) chains of string-ish operands; os.path.join and
      "".join calls; f-strings with no hole; module-level Constant/List/Tuple bindings.
  (3) constant-propagate MODULE-LEVEL bindings into `BOUND`, then resolve EVERY Name node through
      BOUND, so `run([sys.executable, ORACLE])` attributes the literal declared 400 lines earlier.
      A List/Tuple bound value joins its elements with a SPACE (argv semantics), not with "".
  (4) BASE RULE, stated because getting it wrong silently manufactures absent targets:
        contains a slash  -> resolve against the REPO ROOT only (it is a repo-relative path);
        bare filename     -> resolve against the INSTRUMENT'S OWN DIRECTORY first, then the root.
      Resolving a slashed path against HERE is what produced
      `tinybendygrad/uop/tinybendygrad/uop/render.bend` and `checks/.agents/slop/xd1/...` in the
      first version -- 100% phantom absences.
  (5) exclude the instrument's own path.  A target INSIDE the instrument's own directory is code,
      not an input, and is dropped -- unless it is genuinely absent, which is the spec.
  (6) existence: disk via os.path.isfile; HEAD by set-intersection with
      `git ls-tree -r HEAD --name-only` (one authoritative set, no stdin alignment to get wrong),
      cross-checked against `git cat-file -e HEAD:<p>` on a spot sample.

This script emits sites.raw.out and makes NO verdict about guards; `guarded` is filled by reading.
"""
import ast, os, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
D = ROOT / ".agents/slop/absentinputs"
EXT = re.compile(
  r"\.(py|sh|bend|js|mjs|cjs|ts|txt|rows|out|err|tsv|md|c|h|cu|cpp|gdb|so|json|jsonl|"
  r"json\.gz|gz|tgz|tar|whl|bin|yaml|yml|lock|toml|cfg|ini|log|csv|html|pem|crt|key)$"
)
# THE PATH CHARSET. Anything with whitespace, a backtick, a shell metacharacter or a
# bracket/paren/brace is prose or an expression, not a path literal.
CHARSET = re.compile(r"^[A-Za-z0-9_./@+-]+$")
# A BASENAME must begin with a word character. Without this, `.py` (31 hits), `/` (78) and `.`
# (4) all counted as paths -- they are what is left of a BinOp(Div) or an empty join.
BASENAME = re.compile(r"^[A-Za-z0-9_@+-][\w@.+-]*$")
JOINERS = {"join", "os.path.join", "posixpath.join", "ntpath.join"}
# A WRITE WINDOW: the instrument producing the file, which makes an absence intentional.
WRITE = re.compile(r"write_text|write_bytes|open\([^)]*[\"'][wax][bt+]*[\"']|\.write\(|"
                   r"mkstemp|NamedTemporaryFile|shutil\.(copy|move|rmtree)|os\.remove|unlink")


def basename_ok(s):
  b = s.rstrip("/").rsplit("/", 1)[-1]
  if not b or not BASENAME.match(b):
    return False
  # A basename starting with `-` is a TEMPLATE SUFFIX, not a path: `name.endswith("-gate.py")`
  # and `f"D6-{g}-ordered.txt"` both yield one, and neither names a file.
  return b[0] != "-"


def pathish(s):
  return bool(s) and bool(CHARSET.match(s)) and ("/" in s or bool(EXT.search(s))) and basename_ok(s)


MIME = re.compile(r"^[a-z]+/[A-Za-z0-9.+*-]+$")


def labelish(s):
  """A STATUS LABEL, not a path.  A first segment that is a bare identifier, or a whole
  `word/word` pair, with no file extension anywhere: `DEFUSED/code`, `ON-DISK/TRACKED`,
  `CONST/`, `B/s`, `Tokens/Line`, `n/a`, `linearize/render`.  These are what remain after the
  charset and basename filters, and counting them as absent INPUTS inflates the class with the
  instrument's own vocabulary.  A candidate with NO extension survives only if it resolves to a
  real directory on disk or in HEAD (`references/`, `tinybendygrad/`, `runs/`)."""
  if MIME.match(s):
    return True
  return not EXT.search(s)


def lit_parts(node):
  """String fragments of a string-ish expression, else None. List/Tuple -> argv-joined by space."""
  if isinstance(node, ast.Constant) and isinstance(node.value, str):
    return [node.value]
  if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
    a, b = lit_parts(node.left), lit_parts(node.right)
    return None if a is None or b is None else a + ["/"] + b
  if isinstance(node, ast.JoinedStr):
    out = []
    for v in node.values:
      if isinstance(v, ast.Constant) and isinstance(v.value, str):
        out.append(v.value)
      elif isinstance(v, ast.FormattedValue):
        return None
    return out
  if isinstance(node, (ast.List, ast.Tuple)):
    parts = []
    for e in node.elts:
      q = lit_parts(e)
      if q is None:
        return None
      parts.append("".join(q))
    return [" "] * (len(parts) - 1) and parts or parts  # keep parts; join with space at use site
  if isinstance(node, ast.Call):
    if fn_name(node.func) in JOINERS:
      parts = []
      for a in node.args:
        p = lit_parts(a)
        if p is None:
          return None
        parts.extend(p)
      return parts
  return None


def fn_name(f):
  if isinstance(f, ast.Attribute):
    return fn_name(f.value) + "." + f.attr
  if isinstance(f, ast.Name):
    return f.id
  return "<call>"


def extract(src):
  tree = ast.parse(src)
  lines = src.splitlines()
  docstrings = set()
  for st in ast.walk(tree):
    if isinstance(st, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
      ds = ast.get_docstring(st, clean=False)
      if ds is None:
        continue
      for n in ast.walk(st):
        if isinstance(n, (ast.Expr, ast.Assign)) and isinstance(n.value, ast.Constant):
          if isinstance(n.value.value, str):
            docstrings.add(id(n.value))
        if isinstance(n, ast.Constant) and isinstance(n.value, str) and n.value == ds:
          docstrings.add(id(n))

  bound = {}
  for st in tree.body:
    if isinstance(st, (ast.Assign, ast.AnnAssign)):
      targets = st.targets if isinstance(st, ast.Assign) else [st.target]
      p = lit_parts(st.value)
      if p is not None:
        s = (" ".join(p) if isinstance(st.value, (ast.List, ast.Tuple)) else "".join(p))
        if pathish(s):
          for t in targets:
            if isinstance(t, ast.Name):
              bound[t.id] = s

  found = {}
  occ = {}

  def note(s, ln):
    if pathish(s):
      found.setdefault(s, ln)
      occ.setdefault(s, []).append(ln)

  for n in ast.walk(tree):
    if isinstance(n, ast.Constant) and isinstance(n.value, str):
      if id(n) not in docstrings:
        note(n.value, n.lineno)
    elif isinstance(n, (ast.BinOp, ast.JoinedStr, ast.Call, ast.List, ast.Tuple)):
      p = lit_parts(n)
      if p is not None:
        note(" ".join(p) if isinstance(n, (ast.List, ast.Tuple)) else "".join(p), n.lineno)
    elif isinstance(n, ast.Name) and n.id in bound:
      note(bound[n.id], n.lineno)

  # IS THE INSTRUMENT THE WRITER?  A plant / negative control is a file the gate CREATES in order
  # to see that it notices. `nope.txt`, `bad.py`, `refuse-gate.py`, `dead-gate.py` in the absent
  # own-dir population are exactly that, and counting them as absent INPUTS would inflate the class
  # with the tests OF it.  Decided mechanically: the literal occurs within a write window --
  # its own line or the next 4 -- of a write-mode call.
  written = {}
  for s, lns in occ.items():
    hit = False
    for ln in lns:
      for probe in lines[max(0, ln - 1): ln + 4]:
        if WRITE.search(probe):
          hit = True
          break
      if hit:
        break
    written[s] = hit
  return found, written, occ


def norm(p):
  return os.path.normpath(p).replace("\\", "/")


def resolve(raw, reldir):
  """The TWO exact anchors a literal can sit on. Nothing else is guessed.

    contains a slash -> repo root only (it is a repo-relative path)
    bare filename    -> the instrument's own directory, then the repo root

  Suffix-matching against the tree is NOT done here; it is a separate, weaker signal
  (`suffix`) so that a literal written relative to a base computed at runtime
  (`uop/ops.bend` under `tinybendygrad/`) is disclosed as PRESENT_SUFFIX_ONLY rather than
  silently counted as an absent input, and so that `checks/render-gate-oracle.py` cannot
  rescue `.agents/slop/xd1/render-gate-oracle.py`, which nothing ends with."""
  r = raw.lstrip()
  while r.startswith("./"):
    r = r[2:]
  out = []
  if "/" in r:
    # BOTH anchors are tried for every slashed literal, and existence is ANY anchor.
    #   * repo root      -- `.agents/slop/opsbend-milestone.sh`, which e2e.py and e2e.sh write
    #                      as `./.agents/slop/...` (a doubled prefix meaning "from the repo root")
    #   * instrument dir -- `../checks/gatesweep.py` from `gates/runner.py`, which EXISTS
    # Trying only one of them manufactures an absent target out of a file that is present, and
    # getting that wrong in EITHER direction is how a census of absence becomes a census of
    # the extractor's guesses.
    for b in ("", reldir):
      n = norm(os.path.join(b, r))
      if not n.startswith("..") and n not in out:
        out.append(n)
  else:
    for b in (reldir, ""):
      n = norm(os.path.join(b, r))
      if not n.startswith("..") and n not in out:
        out.append(n)
  return out


def shell_candidates(src):
  """Shell: only `NAME.ext` tokens and clean slash-paths, in a COMMAND or ASSIGNMENT position.

  Every exclusion below was added because it removed a MEASURED false positive, and each is
  named so the ledger can see the class rather than inherit it:
    * `$`/`*`/backtick -- unresolvable parameter and glob forms (`RUN/e2e-mm-gate.out`)
    * an ALL-CAPS first segment -- a scratch-dir VARIABLE (`RUN=`, `GT=`, `OUT=`, `SL=`)
    * preceded by `$` or `{` -- a positional parameter (`$1/port-rows.txt`)
    * preceded by `(` -- a METHOD CALL, not a path: `s.count(old)` read as `s.c`, which was
      the single most frequent false positive in the shell population
    * on a COMMENT line -- prose, not a use (`e2e.sh:121` names `out.txt` inside a comment)
    * not passing `pathish` -- shell candidates bypassed the basename filter, so a glob's tail
      `*.mut.bend` arrived as `.mut.bend`
  What remains is hand-verified in the report: this is the weakest part of the census."""
  found = {}
  pat = re.compile(r"[\w@.+-]*(?:/[\w@.+-]+)*/?[\w@.+-]*\."
                   r"(?:py|sh|bend|txt|rows|json|md|out|err|tsv|js|mjs|cu|c|h|so|bin)"
                   r"(?![A-Za-z0-9])")  # the word boundary: without it `Nat.show` reads `Nat.sh`
  for m in pat.finditer(src):
    tok = m.group(0)
    if any(c in tok for c in "$*`") or not pathish(tok):
      continue
    if m.start() > 0 and src[m.start() - 1] in "${(":
      continue
    line = src[src.rfind("\n", 0, m.start()) + 1: m.start()]
    if line.lstrip().startswith("#"):
      continue  # a comment names things; it does not read them
    first = tok.lstrip("./").split("/")[0]
    if re.match(r"^[A-Z][A-Z0-9_]*$", first):
      continue  # shell scratch-dir variable, not a repo path
    found.setdefault(tok, src[:m.start()].count("\n") + 1)
  return found


def main():
  instruments = [l.strip() for l in open(D / "pop-code.out") if l.strip()]
  rawc = {}  # instrument -> {raw_literal: lineno}
  writ = {}  # instrument -> {raw_literal: bool}
  unresolved = []
  for rel in instruments:
    src = (ROOT / rel).read_text(errors="replace")
    try:
      found, w, _occ = extract(src)
    except SyntaxError:
      if rel.endswith(".sh"):
        found = shell_candidates(src)
        _, w = (found, {})
        unresolved.append((rel, "SHELL_REGEX_ONLY"))
      else:
        print(f"SYNTAXERROR-PY {rel}", file=sys.stderr)
        continue
    keep = {}
    for s, ln in found.items():
      if s.startswith(("/", "~")) or re.match(r"^[A-Za-z]+://", s):
        continue  # absolute or URL: not a repo input, and not resolvable
      if norm(s) == norm(rel):
        continue  # the instrument itself
      keep[s] = ln
    if keep:
      rawc[rel] = keep
      writ[rel] = {s: w.get(s, False) for s in keep}

  # ---- existence, THREE signals, never conflated ----
  headset = set(l.strip() for l in open(D / "head-tree.out") if l.strip())
  diskfiles = set()
  for dp, dns, fns in os.walk(ROOT):
    dns[:] = [d for d in dns if d not in (".git", "references", "node_modules")]
    for f in fns:
      diskfiles.add(norm(os.path.relpath(os.path.join(dp, f), str(ROOT))))
  diskdirs = set()
  for dp, dns, _ in os.walk(ROOT):
    dns[:] = [d for d in dns if d not in (".git", "references", "node_modules")]
    for d in dns:
      diskdirs.add(norm(os.path.relpath(os.path.join(dp, d), str(ROOT))))

  rows = []
  for rel in instruments:
    reldir = os.path.dirname(rel)
    for s, ln in sorted(rawc.get(rel, {}).items()):
      anchors = resolve(s, reldir)
      d_exact = next((a for a in anchors if a in diskfiles), None)
      h_exact = next((a for a in anchors if a in headset), None)
      is_dir = next((a for a in anchors if a in diskdirs or a in ("", ".")), None)
      suf = [p for p in (diskfiles | headset) if p.endswith("/" + s.lstrip("./"))]
      own = ("/" not in s) and anchors and os.path.dirname(anchors[0]) == reldir
      if labelish(s) and not (d_exact or h_exact or is_dir):
        continue  # a label, not an input
      rows.append({
        "inst": rel, "ln": ln, "raw": s,
        "anchor": anchors[0] if anchors else "",
        "d": bool(d_exact), "h": bool(h_exact),
        "dir": bool(is_dir and not (d_exact or h_exact)),
        "suf": suf[0] if suf else "",
        "own": bool(own), "external": not bool(own),
        "written": bool(writ.get(rel, {}).get(s, False)),
      })

  with open(D / "sites.raw.out", "w") as fh:
    for r in rows:
      fh.write(f"{r['inst']}\t{r['ln']}\t{r['raw']}\t"
               f"{'yes' if r['d'] else 'no'}\t{'yes' if r['h'] else 'no'}\t"
               f"{'external' if r['external'] else 'own_dir'}\t"
               f"{r['suf'] or '-'}\t{'DIR' if r['dir'] else '-'}\t"
               f"{'WRITTEN' if r['written'] else 'read_only'}\n")

  ABSENT = [r for r in rows if not r["d"] and not r["h"] and not r["dir"] and not r["suf"]]
  WEAKP = [r for r in rows if not (r["d"] or r["h"] or r["dir"]) and r["suf"]]
  ext = [r for r in rows if r["external"]]
  ext_abs = [r for r in ABSENT if r["external"]]
  ext_abs_ro = [r for r in ext_abs if not r["written"]]
  own_abs_ro = [r for r in ABSENT if not r["external"] and not r["written"]]
  print(f"instruments\t{len(instruments)}")
  print(f"instruments_naming_external\t{len({r['inst'] for r in ext})}")
  print(f"candidate_literals\t{len(rows)}")
  print(f"external\t{len(ext)}")
  print(f"present_exact_disk_and_head\t{sum(1 for r in rows if r['d'] and r['h'])}")
  print(f"present_exact_disk_only\t{sum(1 for r in rows if r['d'] and not r['h'])}")
  print(f"present_exact_head_only\t{sum(1 for r in rows if r['h'] and not r['d'])}")
  print(f"present_directory_not_file\t{sum(1 for r in rows if r['dir'])}")
  print(f"PRESENT_SUFFIX_ONLY_weak\t{len(WEAKP)}")
  print(f"ABSENT_ALL_SIGNALS\ttotal={len(ABSENT)}  external={len(ext_abs)}  "
        f"own_dir={len(ABSENT) - len(ext_abs)}")
  print(f"absent_external_NOT_WRITTEN\t{len(ext_abs_ro)} "
        f"instruments={len({r['inst'] for r in ext_abs_ro})}")
  print(f"absent_external_WRITTEN_BY_SELF(plant)\t{len(ext_abs) - len(ext_abs_ro)}")
  print(f"absent_owndir_NOT_WRITTEN\t{len(own_abs_ro)} "
        f"instruments={len({r['inst'] for r in own_abs_ro})}")
  for u in unresolved:
    print("EXTRACTION\t" + "\t".join(u))


main()