"""THE DIVERGENCES, ATTRIBUTED: WHICH PORT RULE OWNS EACH ONE.

    .venv/bin/python .agents/slop/sym92/attribute.py

**THE FINDING, IN ONE LINE.** THE RE-VENDOR TO `f5ac54685074` DELETED UPSTREAM RULES AND MOVED
OTHERS, THE PORT's TABLE ENTRIES STILL CITE THE OLD LINES, AND **THE CENSUS MATCHES A TABLE
ENTRY TO AN UPSTREAM ROW BY THE CITATION AND THE OP SET -- SO A ROW FOR A DELETED RULE READS
`PORTED`.**

**WHY A TEXT COMPARISON IS NOT THE INSTRUMENT.** MEASURED 2026-11-06, THREE TIMES:
- COMPARING THE WHOLE RULE LINE OVER-REPORTS DELETIONS, BECAUSE UPSTREAM REWORDED THE BODY OF
  RULES IT KEPT (`sym_280`'s RULE IS AT `:295` IN THE NEW PIN AND ITS LAMBDA CHANGED FROM `y` TO
  `None`).
- COMPARING THE PATTERN ALONE ALSO OVER-REPORTS, BECAUSE UPSTREAM REMOVED A PATTERN's NAME
  (`sym_453`'s PATTERN LOST ITS `name="x"`).
- COMPARING THE OP SET UNDER-REPORTS, BECAUSE THE OP SET DOES NOT TELL TWO RULES APART.

**SO THE INSTRUMENT IS BEHAVIOURAL: THE PORT's `sym_f` AGAINST CPYTHON's `sym.rewrite`, ON THE
232 CASES OF `gates/symrules-cases.rows`.** A CASE WHERE THE PORT REWRITES AND UPSTREAM
DECLINES IS A CASE WHERE THE PORT CARRIES A RULE UPSTREAM DOES NOT HAVE -- WHATEVER THE
CITATIONS SAY.
"""
import re
import subprocess
import sys

CASES = "gates/symrules-cases.rows"
DRIVER = None


def cases():
  out = []
  for ln in open(CASES):
    ln = ln.rstrip("\n")
    if not ln or ln.startswith("#") or "|" not in ln:
      continue
    name, expr = ln.split("|", 1)
    out.append((name, expr))
  return out


def upstream_answers():
  """UPSTREAM's ANSWER FOR EVERY CASE, AND IT IS CPYTHON's OWN `sym.rewrite`."""
  sys.path.insert(0, "gates")
  import importlib.util
  spec = importlib.util.spec_from_file_location("orc", "gates/symrules-oracle.py")
  orc = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(orc)
  ans = {}
  for name, expr in cases():
    u = orc.parse(orc.P(orc.lex(expr)), {})
    ans[name] = orc.sh(orc.sym.rewrite(u))
  return ans


def main():
  out = subprocess.run(["./bin/bend", "gates/symrules-driver.bend"],
                       capture_output=True, text=True).stdout
  port = {}
  for ln in out.splitlines():
    if "=" not in ln:
      continue
    name, ans = ln.split("=", 1)
    port[name] = ans
  up = upstream_answers()
  print("THE DIVERGENCES, AND WHICH WAY EACH ONE GOES")
  print("  (the port's answer is the FLAT listing; the oracle re-nests it)")
  sys.path.insert(0, "gates")
  import importlib.util
  spec = importlib.util.spec_from_file_location("orc", "gates/symrules-oracle.py")
  orc = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(orc)
  for name, expr in cases():
    p = orc.renest(port.get(name, ""))
    u = up.get(name, "")
    if p == u:
      continue
    if u == "norewrite":
      direction = "THE PORT REWRITES AND UPSTREAM DECLINES"
    elif p == "norewrite":
      direction = "UPSTREAM REWRITES AND THE PORT DECLINES"
    else:
      direction = "BOTH REWRITE AND THEY DIFFER"
    print("  %-8s %-42s %s" % (name, expr[:42], direction))
  return 0


if __name__ == "__main__":
  sys.exit(main())
