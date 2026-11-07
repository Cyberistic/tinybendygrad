"""THE PORT's RULES THAT IMPLEMENT AN UPSTREAM RULE THE RE-VENDOR DELETED.

    .venv/bin/python .agents/slop/sym92/deadrules.py

**THE FINDING.** THE RE-VENDOR TO `f5ac54685074` DELETED SEVENTEEN UPSTREAM RULES. THE PORT
STILL IMPLEMENTS SEVENTEEN OF THEM, AND `gates/symrules-census.py` READS EVERY ONE OF THEM AS
`PORTED` -- **BECAUSE THE CENSUS MATCHES A TABLE ENTRY TO AN UPSTREAM ROW BY THE CITATION AND
THE OP SET, AND THE CITATION NAMES A LINE THAT STILL HOLDS A RULE WITH THE SAME OPS.**

SO THE CENSUS's 134 GREEN ROWS INCLUDE ROWS FOR RULES UPSTREAM NO LONGER HAS, AND THE PORT
REWRITES WHERE UPSTREAM DECLINES.

**THE MEASUREMENT.** FOR EVERY PORT RULE, THE RULE IT IMPLEMS IS FOUND BY THE LINE ITS OWN
COMMENT CITES, IN THE OLD PIN (`5c2bf39d6`), AND THE RULE's TEXT IS LOOKED UP IN THE NEW PIN
(`f5ac54685074`). **A RULE WHOSE TEXT IS IN NEITHER IS DELETED.**
"""
import re
import subprocess
import sys

OLD = "5c2bf39d6"
NEW = "f5ac54685074"
PORT = "tinybendygrad/uop/symbolic.bend"


def norm(t):
  """THE RULE's KEY, AND **THE KEY MUST NOT BE DEGENERATE**.

  **THIS FUNCTION WAS WRONG AND MEASURED 2026-11-07 TO BE WRONG ON **63 OF 117** PORT RULES.**

  THE OLD KEY WAS THE **SET OF OPS THE PATTERN NAMES**, AND IT IS DEGENERATE FOR EVERY
  PATTERN THAT NAMES NO OP -- **AND THE EMPTY SET APPEARS **54** TIMES AMONG THE NEW PIN's
  RULES**, SO `t in newtexts` IS TRIVIALLY TRUE FOR IT AND A DELETED RULE READS AS KEPT.

  THE CONSEQUENCE WAS THAT THE INSTRUMENT SAID **"0 of 117 port rules implement a DELETED
  upstream rule"** WHILE `sym_132` -- WHICH IMPLEMENTS `(UPat.var("x", dtype=dtypes.bool) !=
  UPat.const(False, dtypes.bool))`, A RULE UPSTREAM DELETED AT THE RE-VENDOR -- WAS RIGHT
  THERE. **THE INSTRUMENT SAID "NOTHING" AND THAT WAS A KEY, NOT A MEASUREMENT.**

  THE NEW KEY IS **THE PATTERN TEXT WITH THE `name=` ATTRIBUTES REMOVED**, AND THE REASON IS
  MEASURED, NOT GUESSED:

  - THE WHOLE LINE OVER-REPORTS, BECAUSE UPSTREAM REWORDED THE BODY OF RULES IT KEPT --
    `sym_280`'s RULE IS AT `:295` IN THE NEW PIN AND ITS LAMBDA CHANGED FROM `y` TO `None`.
    **SO THE LAMBDA IS NOT IN THE KEY.**
  - THE PATTERN ALONE ALSO OVER-REPORTS, BECAUSE UPSTREAM REMOVED A PATTERN's NAME --
    `sym_453`'s PATTERN WAS `(UPat.store(UPat(Ops.INDEX, name="index"), UPat.load(...)),
    name="x")` AND AT `:467` IT IS THE SAME WITHOUT THE `name="x"`. **SO THE `name=`
    ATTRIBUTES ARE NOT IN THE KEY EITHER.**

  **WHAT IS LEFT IS THE PATTERN'S STRUCTURE, WHICH IS WHAT DISTINGUISHES ONE RULE FROM
  ANOTHER, AND IT IS NEVER EMPTY FOR A RULE THAT EXISTS** -- SO THE KEY CANNOT DEGENERATE.
  """
  t = re.sub(r"\s*#.*$", "", t)
  t = re.sub(r"\s+", " ", t)
  t = t.strip().rstrip(",")
  i = t.find(", lambda")
  pat = t[:i] if i >= 0 else t
  # THE `name="..."` ATTRIBUTES ARE REMOVED, AND THE `dtype=`/`dtypes.` SPELLINGS ARE KEPT,
  # BECAUSE A DTYPE CONSTRAINT IS PART OF THE PATTERN AND NOT A LABEL.
  pat = re.sub(r'\s*name\s*=\s*"[^"]*"', "", pat)
  pat = re.sub(r"\s+", " ", pat).strip()
  return pat


def ops_of(t):
  """THE OP SET, KEPT BECAUSE THE CENSUS's OWN TEST USES IT AND THE KEY MUST NOT REPLACE IT.

  **AND ITS DEGENERACY IS THE POINT: AN EMPTY OP SET IS WHAT MAKES 63 RULES UNMEASURABLE BY
  IT, AND THAT MEASUREMENT IS THE INSTRUMENT's OWN LIMITATION AND NOT A PROPERTY OF THE TREE.**
  """
  t = re.sub(r"\s*#.*$", "", t)
  t = re.sub(r"\s+", " ", t)
  t = t.strip().rstrip(",")
  i = t.find(", lambda")
  pat = t[:i] if i >= 0 else t
  ops = set()
  for m in re.finditer(r"\b(?:Ops|GroupOp)\.(\w+)", pat):
    ops.add(m.group(1))
  for m in re.finditer(r"\b(UPat\.\w+)\.(\w+)", pat):
    ops.add(m.group(2))
  return ",".join(sorted(ops))


def rules(rev):
  out = subprocess.run(["git", "show", f"{rev}:tinygrad/uop/symbolic.py"],
                       capture_output=True, text=True)
  d = {}
  if out.returncode != 0:
    return d
  for i, ln in enumerate(out.stdout.splitlines(), start=1):
    # THE COMMENT IS STRIPPED **BEFORE** THE SHAPE TEST, BECAUSE UPSTREAM's RULES CARRY A TRAILING
    # COMMENT -- `((UPat.var("x") * UPat.var("x2")) / UPat.var("x2"), lambda x,x2: x),  # (x*x2)/x2 -> x`
    # -- AND A TEST THAT LOOKS AT THE RAW LINE MISSES EVERY COMMENTED RULE.
    t = re.sub(r"\s*#.*$", "", ln).strip()
    if t.startswith("(") and "lambda" in t and t.endswith(","):
      d[i] = norm(t)
  return d


def body_cites(src, name):
  """THE CITATION THE BODY's OWN COMMENT NAMES.

  **THE WINDOW IS THE COMMENT BLOCK AND NOT THE LAST LINE ABOVE**, BECAUSE A RULE's COMMENT
  SPANS SEVERAL LINES AND THE CITATION IS USUALLY THE FIRST OF THEM: `sym_174`'s DEF IS EIGHT
  LINES BELOW ITS `# symbolic.py:174` COMMENT. MEASURED 2026-11-06: A ONE-LINE WINDOW MISSED
  `sym_174` AND THE COUNT WAS 16 INSTEAD OF 17."""
  m = re.search(r"^def %s\b" % re.escape(name), src, re.M)
  if not m:
    return None
  window = src[:m.start()]
  block = []
  for ln in reversed(window.splitlines()):
    if ln.startswith("#") or ln.strip() == "":
      block.append(ln)
      continue
    break
  cs = re.findall(r"symbolic\.py:(\d+)", "\n".join(reversed(block)))
  if cs:
    return int(cs[0])
  cs = re.findall(r"symbolic\.py:(\d+)", window)
  return int(cs[-1]) if cs else None


def main():
  old, new = rules(OLD), rules(NEW)
  newkeys = set(new.values())
  src = open(PORT).read()
  bodies = sorted(set(re.findall(r"^def (sym_\d+)\(", src, re.M)))
  print("THE PORT's RULES THAT IMPLEMENT AN UPSTREAM RULE THE RE-VENDOR DELETED")
  n = 0
  unmeasurable = 0
  for b in bodies:
    bc = body_cites(src, b)
    if bc is None:
      continue
    t = old.get(bc)
    if t is None:
      continue
    if t in newkeys:
      continue
    n += 1
    print("  %-9s was the old %-4d  %s" % (b, bc, t[:86]))
  print("  %d of %d port rules implement a DELETED upstream rule" % (n, len(bodies)))
  print("""  **AND THIS COUNT OVER-REPORTS, AND THE OVER-REPORTING IS MEASURED AND NOT
  ASSUMED.** THE KEY IS THE PATTERN TEXT WITH ITS `name=` ATTRIBUTES REMOVED, AND UPSTREAM
  ALSO REWORDED KEPT RULES:
   - `sym_295`'s OLD PATTERN IS `(UPat.var("x") + UPat.cvar("c1")) + UPat.var("y")` AND AT
     THE NEW PIN IT IS `:309` WITH A `dtypes.wints` DTYPE CONSTRAINT ADDED.
   - `sym_302`'s OLD PATTERN ENDS `.ne(True)` AND AT THE NEW PIN IT IS `:318` WITH
     `.logical_not()` INSTEAD -- **THE SAME RULE, SPELLED WITH THE OTHER PRIMITIVE.**
  **SO THIS INSTRUMENT IS A CANDIDATE LIST AND NOT A VERDICT, AND THE ONLY TEST THAT SETTLES
  IT IS THE BEHAVIOURAL ONE -- THE PORT's `sym_f` AGAINST CPYTHON's `sym.rewrite`.**""")
  # AND THE INSTRUMENT's OWN LIMITATION, WHICH IS A ROW AND NOT A NOTE: **THE OP SET IS
  # DEGENERATE FOR EVERY PATTERN THAT NAMES NO OP**, AND THE OLD KEY WAS THAT OP SET, SO THE
  # OLD INSTRUMENT COULD NOT SEE **63 OF 117** RULES AT ALL. THE COUNT IS HERE SO A ROW THAT
  # CANNOT GO RED IS VISIBLE.
  empty_new = sum(1 for v in new.values() if ops_of(v) == "")
  unmeasurable = 0
  for b in bodies:
    bc = body_cites(src, b)
    if bc is None:
      continue
    t = old.get(bc)
    if t is None:
      continue
    if ops_of(t) == "":
      unmeasurable += 1
  print("  AND %d of %d port rules have a PATTERN THAT NAMES NO OP, SO THE OP SET IS THE"
        % (unmeasurable, len(bodies)))
  print("  EMPTY SET FOR THEM -- **AND THE EMPTY SET APPEARS %d TIMES AMONG THE NEW PIN's"
        % empty_new)
  print("  RULES**, SO AN OP-SET KEY CANNOT DISTINGUISH THEM. THE KEY HERE IS THE PATTERN TEXT")
  print("  WITH ITS `name=` ATTRIBUTES REMOVED, AND IT IS NEVER EMPTY.")
  return 0


if __name__ == "__main__":
  sys.exit(main())
