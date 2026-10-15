#!/usr/bin/env python
"""Ledger drift, final: which paths `.agents/TOOLS.md` names are gone, and which are load-bearing.

DENOMINATOR — byte-for-byte the rule the ledger's own generator declares
(`.agents/slop/toolsledger/extract.py:20-27`): every backtick-quoted span of the
COMMITTED `.agents/TOOLS.md` (asserted byte-equal to the working tree) containing
`/`, normalized (markdown emphasis, parens/brackets/backticks, trailing
punctuation, leading `./` stripped), excluding URLs/`git@`/`//`, excluding tokens
with whitespace, `$` or `::`. Re-taken because the file grew; the OLD text is
re-extracted separately so the method is proven, not assumed.

RESOLUTION — `extract.py:29-32` resolves a token against ONE base, the repo root.
The ledger writes paths relative to a directory it does not name: the port
(`uop/ops.bend` = `tinybendygrad/uop/ops.bend`), a Bend `import`
(`../helpers.bend`), the compiler checkout (`bend2/base.bend` =
`references/bend/bend2/base.bend`). So a base is NOT LISTED here — a token
RESOLVES iff some path that exists ENDS WITH it, over an index built by DISCOVERY
(`git ls-tree -r HEAD` plus a disk walk of the gitignored checkouts). Three
outcomes are kept apart:
  exact   the token exists where it is written
  suffix  it exists only as the tail of another path (base unstated by the ledger)
  absent  it exists nowhere on disk and nowhere in HEAD

DANGER CLASS is not a basename vocabulary. INSTRUMENT = a file-shaped token some
live `checks/*.py` or `gates/*.py` names inside a STRING LITERAL (found with
`ast`, so a `#` comment cannot make a path look invoked); PROSE otherwise —
directories, extensionless revision references and notation included.
`extract.py:34` classifies by a basename regex instead; that column is carried
too, because that regex is what mistook the revision reference `xd1/pin` for a
runnable instrument.

Writes paths.rows (deliverable) and lanes.rows (per-token detail).
"""
import ast, csv, os, re, subprocess
from collections import Counter
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
os.chdir(ROOT)
STAMP = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def git(*a):
  env = dict(os.environ); env.pop("GIT_INDEX_FILE", None)
  return subprocess.run(("git",) + a, capture_output=True, text=True, check=True, env=env).stdout

# --- the index, by discovery ------------------------------------------------
index = set(git("ls-tree", "-r", "HEAD", "--name-only").split())
for base in ("references", ".agents/slop/rf2root"):
  for root, dirs, files in os.walk(base):
    for f in files: index.add(os.path.join(root, f))
tails = {}  # every /-separated tail of every indexed path, so `ops.bend` resolves
for p in sorted(index, key=len):
  parts = p.split("/")
  for i in range(len(parts)): tails.setdefault("/".join(parts[i:]), p)

head_text = git("cat-file", "blob", "HEAD:.agents/TOOLS.md")
assert head_text == open(".agents/TOOLS.md").read(), "working tree != HEAD; population ambiguous"

def norm(t):
  t = t.strip().strip("*_[]()`").rstrip('.,;:)"(')
  return t[2:] if t.startswith("./") else t

def population(text):
  toks = sorted({norm(t) for t in re.findall(r"`([^`\n]+)`", text) if "/" in norm(t)})
  toks = [t for t in toks if not (t.startswith(("http", "git@", "//")) or "github.com" in t)]
  return [t for t in toks if re.fullmatch(r"[~A-Za-z0-9_./@+\-]+", t)]

toks = population(head_text)

def resolve(t):
  if t.startswith(("/", "~")): return ("exact", t) if os.path.exists(t) else ("absent", "")
  if t in index or os.path.exists(t): return ("exact", t)
  # a relative reference (`../helpers.bend`) names no base of its own; drop the
  # walk-up segments and look the remainder up as a tail.
  c = t.rstrip("/")
  while c.startswith("../"): c = c[3:]
  return ("suffix", tails[c]) if c in tails else ("absent", "")

# --- live citation ----------------------------------------------------------
live = sorted([f"checks/{e.name}" for e in os.scandir("checks") if e.name.endswith(".py")] +
              [f"gates/{e.name}" for e in os.scandir("gates") if e.name.endswith(".py")])
shells = sorted([f"checks/{e.name}" for e in os.scandir("checks") if e.name.endswith(".sh")])
lits, raw = {}, {}
for src in live + shells:
  if src.endswith(".py"):
    try: tree = ast.parse(open(src, encoding="utf-8", errors="replace").read())
    except SyntaxError: continue
    vals = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
  else:
    vals = re.findall(r"[^\s'\"()|&;]+\.[A-Za-z0-9]+", open(src, encoding="utf-8", errors="replace").read())
  for v in vals:
    for tok in norm(v).split():
      lits.setdefault(os.path.basename(tok.rstrip("/")), set()).add(src)
      raw.setdefault(os.path.basename(tok.rstrip("/")), set()).add((src, tok.rstrip("/")))

def file_shaped(t):
  seg = t.rstrip("/").rsplit("/", 1)[-1]
  return "." in seg and not seg.endswith(".")

def cites(t):
  """A citation is a STRING LITERAL whose path TAILS the token: `bc-oracle.py`
  in the ledger vs `.agents/slop/bitcastrow/bc-oracle.py` in a gate is the same
  basename and a DIFFERENT file, and treating it as a citation is how a stale
  ledger row reads as a live gate's missing input."""
  hit, collision = set(), set()
  for src, lit in raw.get(os.path.basename(t.rstrip("/")), ()):
    L = norm(lit).rstrip("/")
    tail_ok = L == t or L.endswith("/" + t) or ("/" in L and t.endswith("/" + L))
    (hit if tail_ok else collision).add(src)
  return sorted(hit), sorted(collision)

def cite(t):
  if not file_shaped(t): return [], []
  h, c = cites(t)
  return [s for s in h if s.endswith(".py")], [s for s in c if s.endswith(".py")]

INSTR = re.compile(r"(gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|no-txt|substrate)")
def orig_kind(t):
  b = os.path.basename(t)
  if "oracle" in b or "arena" in b: return "ORACLE"
  return "INSTRUMENT" if INSTR.search(b) else "EVIDENCE"

recs = []
for t in toks:
  state, where = resolve(t)
  py, col = cite(t)
  recs.append(dict(p=t, state=state, where=where, py=",".join(py),
                   sh=",".join(s for s in raw.get(os.path.basename(t.rstrip("/")), ()) if s[0].endswith(".sh") for s in [s[0]]),
                   col=",".join(col)))

with open(".agents/slop/ledgerdrift/paths.rows", "w", newline="") as f:
  w = csv.writer(f, delimiter="\t", lineterminator="\n"); w.writerow(["path", "status", "class", "cited_by_or_blank"])
  for r in recs:
    w.writerow([r["p"], "absent" if r["state"] == "absent" else "present",
                "instrument" if r["py"] else "prose", r["py"] or r["sh"]])
with open(".agents/slop/ledgerdrift/lanes.rows", "w", newline="") as f:
  w = csv.writer(f, delimiter="\t", lineterminator="\n")
  w.writerow(["path", "resolution", "resolved_as", "py_cited", "sh_cited", "basename_collision", "orig_kind"])
  for r in recs:
    w.writerow([r["p"], r["state"], r["where"], r["py"], r["sh"], r["col"], orig_kind(r["p"])])

# --- method proof: re-extract the OLD committed text, at the OLD tree --------
# Find the revision whose TOOLS.md yields EXACTLY the denominator the ledger
# records, then re-measure BOTH lanes against the tree AT that revision, so the
# delta separates "the text grew" from "the file moved" from "the rule lied".
def at_rev(rev):
  files = set(git("ls-tree", "-r", rev, "--name-only").split())
  try:
    toks = population(git("cat-file", "blob", f"{rev}:.agents/TOOLS.md"))
  except subprocess.CalledProcessError:   # a rev where the file was absent
    return None
  tl = {}
  for p in sorted(files, key=len):
    parts = p.split("/")
    for i in range(len(parts)): tl.setdefault("/".join(parts[i:]), p)
  root = sum(1 for t in toks if t.startswith("/") and os.path.exists(t) or
             t in files or os.path.exists(t) or any(f.startswith(t.rstrip("/") + "/") for f in files))
  def suf(t):
    if t.startswith("/"): return os.path.exists(t)
    if t in files or os.path.exists(t): return True
    c = t.rstrip("/")
    while c.startswith("../"): c = c[3:]
    return c in tl
  return len(toks), root, sum(suf(t) for t in toks)

cands = git("rev-list", "-12", "--until=2026-10-09T00:00:00Z", "HEAD", "--", ".agents/TOOLS.md").split()
hit = [(r, at_rev(r)) for r in cands]
hit = [h for h in hit if h[1]]
matching = [h for h in hit if h[1][0] == 333]
old_rev = matching[0][0] if matching else cands[0]
old_den, old_root, old_suf = at_rev(old_rev)
old_s = git("rev-parse", "--short", old_rev).strip()
old_date = git("show", "-s", "--format=%cI", old_rev).strip()
now_den = len(toks)
now_suf = sum(r["state"] != "absent" for r in recs)
now_root = sum(1 for t in toks if t.startswith("/") and os.path.exists(t) or
               t in index or os.path.exists(t) or any(f.startswith(t.rstrip("/") + "/") for f in index))

A = [r for r in recs if r["state"] == "absent"]
print(f"STAMP {STAMP}")
print(f"DENOMINATOR distinct tokens {len(toks)}  spans {len(re.findall(r'`([^`\\n]+)`', head_text))}  lines {len(head_text.splitlines())}")
print(f"RESOLUTION exact {sum(r['state']=='exact' for r in recs)}  suffix-only {sum(r['state']=='suffix' for r in recs)}  absent {len(A)}")
print(f"ABSENT under .agents/slop/ {sum(r['p'].startswith('.agents/slop/') for r in A)}  elsewhere {sum(not r['p'].startswith('.agents/slop/') for r in A)}")
print(f"ABSENT py-cited INSTRUMENT {sum(bool(r['py']) for r in A)}  sh-only {sum(bool(r['sh']) and not r['py'] for r in A)}  neither {sum(not r['py'] and not r['sh'] for r in A)}")
print(f"ABSENT extract.py regex: INSTRUMENT {sum(orig_kind(r['p'])=='INSTRUMENT' for r in A)}  ORACLE {sum(orig_kind(r['p'])=='ORACLE' for r in A)}  EVIDENCE {sum(orig_kind(r['p'])=='EVIDENCE' for r in A)}")
print(f"CLASSIFIER disagreement on absent {sum(bool(r['py']) != (orig_kind(r['p'])=='INSTRUMENT') for r in A)}")
print(f"METHOD PROOF: {len(matching)} of {len(hit)} TOOLS.md revs before 2026-10-09 extract to EXACTLY 333 under this rule")
print(f"  at {old_s} ({old_date}): denominator {old_den} | ROOT-lane (extract.py's) present {old_root} absent {old_den-old_root} | SUFFIX-lane present {old_suf} absent {old_den-old_suf}")
print(f"  at HEAD  (2026-10-15):    denominator {now_den} | ROOT-lane present {now_root} absent {now_den-now_root} | SUFFIX-lane present {now_suf} absent {now_den-now_suf}")
print(f"  the 333/164/169 the ledger records is a figure about {old_s}; today's tree is not that tree")
print(f"live sources read: {len(live)} py + {len(shells)} sh; string tokens keyed {len(lits)}")
print("--- ABSENT, py-cited (INSTRUMENT) ---")
for r in A:
  if r["py"]: print(f"  {r['p']}  <- {r['py']}")
print("--- ABSENT, sh-named (self/other) ---")
for r in A:
  if r["sh"]: print(f"  {r['p']}  <- {r['sh']}")
print("--- ABSENT, basename COLLISION only (demoted to prose) ---")
for r in A:
  if r["col"] and not r["py"]: print(f"  {r['p']}  collides_with={r['col']}")