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
  """THE RULE's SHAPE, AND **NOT ITS LAMBDA AND NOT ITS NAMES**.

  MEASURED 2026-11-06, TWICE:
  - COMPARING THE WHOLE LINE OVER-REPORTS DELETIONS, BECAUSE UPSTREAM REWORDED THE BODY OF RULES
    IT KEPT -- `sym_280`'s RULE IS AT `:295` IN THE NEW PIN AND ITS LAMBDA CHANGED FROM `y` TO
    `None`.
  - COMPARING THE PATTERN ALONE ALSO OVER-REPORTS, BECAUSE UPSTREAM REMOVED A PATTERN's NAME --
    `sym_453`'s PATTERN WAS `(UPat.store(UPat(Ops.INDEX, name="index"), UPat.load(...)), name="x")`
    AND AT `:467` IT IS THE SAME WITHOUT THE `name="x"`.

  **SO THE COMPARISON IS THE SET OF OPS THE PATTERN NAMES** -- WHICH IS THE CENSUS's OWN TEST,
  AND WHICH IS WHY A CITATION THAT NAMES A LINE HOLDING A RULE WITH THE SAME OPS LOOKS RIGHT.
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
  # THE OP SET IS THE COMPARISON'S KEY AND THE LINE NUMBER IS NOT
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
  newtexts = set(new.values())
  src = open(PORT).read()
  bodies = sorted(set(re.findall(r"^def (sym_\d+)\(", src, re.M)))
  print("THE PORT's RULES THAT IMPLEMENT AN UPSTREAM RULE THE RE-VENDOR DELETED")
  n = 0
  for b in bodies:
    bc = body_cites(src, b)
    if bc is None:
      continue
    t = old.get(bc)
    if t is None or t in newtexts:
      continue
    n += 1
    print("  %-9s was the old %-4d  %s" % (b, bc, t[:86]))
  print("  %d of %d port rules implement a DELETED upstream rule" % (n, len(bodies)))
  return 0


if __name__ == "__main__":
  sys.exit(main())
