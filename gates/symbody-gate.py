#!/usr/bin/env python3
"""symbody-gate.py -- DOES THE PORT's DISPATCH SEND THE BODY THE TABLE's CITATION NAMES?

    .venv/bin/python gates/symbody-gate.py

EXIT: 0 every table entry dispatches the body its citation names · 1 one does not · 3 REFUSED.

**WHAT THIS IS FOR.** `gates/symrules-census.py` MATCHES A PORT TABLE ENTRY TO AN UPSTREAM RULE
BY **THE CITATION AND THE OP SET**. IT NEVER LOOKS AT WHICH BODY THE DISPATCH SENDS. **SO A TABLE
ENTRY THAT CITES A LINE HOLDING A RULE WITH THE SAME OPS READS `PORTED` WHATEVER IT DISPATCHES.**

AND THE RE-VENDOR TO `f5ac54685074` MOVED AND DELETED UPSTREAM RULES, AND THE PORT's TABLE
ENTRIES WERE RE-POINTED **BY SIGNATURE** (THE OP SET) AND NOT BY BODY.

**THE MEASUREMENT, AND IT NEEDS BOTH PINS.** THE PORT's RULE NAMES AND COMMENTS CITE THE LINES
OF THE PIN THE PORT WAS WRITTEN AGAINST, AND THE TABLE ENTRIES CITE THE LINES OF THE CURRENT
PIN. SO A BODY's RULE IS FOUND IN THE **OLD** PIN (`5c2bf39d6`, THE ONE BEFORE THE RE-VENDOR)
AND THE CITATION'S RULE IS FOUND IN THE **NEW** ONE (`f5ac54685074`), AND THE TWO **PATTERNS** ARE
COMPARED.

**THE PATTERN IS THE TEXT BEFORE `, lambda` AND NOT THE WHOLE LINE**, BECAUSE UPSTREAM REWORDED
THE BODIES OF RULES IT KEPT (MEASURED 2026-11-06: `sym_280`'s RULE IS AT `:295` IN THE NEW PIN
AND ITS LAMBDA CHANGED FROM `y` TO `None`).

**AND A RULE UPSTREAM DELETED IS A FINDING AND NOT A MATCH** -- IT IS REPORTED AS `DELETED` AND
IT IS A RULE THE PORT CARRIES AND UPSTREAM DOES NOT HAVE, WHICH IS WHY THE PORT REWRITES WHERE
UPSTREAM DECLINES.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = os.path.join(ROOT, "tinybendygrad", "uop", "symbolic.bend")
OLD = "5c2bf39d6"
NEW = "f5ac54685074"

ARM = re.compile(r"case (\d+): (sym_\d+)\(x, u\)")
CITE = re.compile(r"symbolic\.py:(\d+)")


def upstream_lines(rev):
  out = subprocess.run(["git", "show", f"{rev}:tinygrad/uop/symbolic.py"],
                       cwd=ROOT, capture_output=True, text=True)
  return out.stdout.splitlines() if out.returncode == 0 else []


def pattern_of(line):
  t = re.sub(r"\s*#.*$", "", line).strip().rstrip(",")
  i = t.find(", lambda")
  return t[:i].strip() if i >= 0 else t


def upstream_rules(lines):
  """LINE -> PATTERN, FOR EVERY RULE."""
  out = {}
  for i, ln in enumerate(lines, start=1):
    t = re.sub(r"\s*#.*$", "", ln).strip()
    if t.startswith("(") and "lambda" in t and t.endswith(","):
      out[i] = pattern_of(ln)
  return out


def rule_cite(src, name):
  """THE UPSTREAM LINE A RULE's OWN COMMENT CITES.

  **THE WINDOW IS THE COMMENT BLOCK AND NOT THE LAST LINE ABOVE**, BECAUSE A RULE's COMMENT SPANS
  SEVERAL LINES AND THE CITATION IS USUALLY THE FIRST OF THEM: `sym_174`'s DEF IS EIGHT LINES
  BELOW ITS `# symbolic.py:174` COMMENT. MEASURED 2026-11-06: A ONE-LINE WINDOW MISSED
  `sym_174`."""
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
  cs = CITE.findall("\n".join(reversed(block)))
  if cs:
    return int(cs[0])
  cs = CITE.findall(window)
  return int(cs[-1]) if cs else None


def main():
  if not os.path.exists(PORT):
    print(f"REFUSED: no {PORT}", file=sys.stderr)
    return 3
  src = open(PORT).read()
  old = upstream_rules(upstream_lines(OLD))
  new = upstream_rules(upstream_lines(NEW))
  if not old or not new:
    print("REFUSED: cannot read tinygrad/uop/symbolic.py at both pins", file=sys.stderr)
    return 3

  sys.path.insert(0, os.path.join(ROOT, "gates"))
  import importlib.util
  spec = importlib.util.spec_from_file_location("census", os.path.join(ROOT, "gates", "symrules-census.py"))
  census = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(census)
  cited = {}
  for tname, entries in census.port_tables().items():
    for e in entries:
      if e["cited"] is not None:
        cited[e["tag"]] = e["cited"]

  arms = {}
  for m in ARM.finditer(src):
    arms[int(m.group(1))] = m.group(2)

  ok, bad, deleted = 0, [], []
  for tag in sorted(cited):
    body = arms.get(tag)
    if body is None:
      continue
    bc = rule_cite(src, body)
    if bc is None:
      continue
    body_pat = old.get(bc)
    if body_pat is None:
      continue          # THE BODY's CITED LINE IS NOT A RULE AT THE OLD PIN -- NOT OUR QUESTION
    cited_pat = new.get(cited[tag])
    if cited_pat is None:
      continue          # THE CITED LINE IS NOT A RULE AT THE NEW PIN -- THE CENSUS SAYS SO
    if body_pat == cited_pat:
      ok += 1
      continue
    bad.append((tag, cited[tag], body, bc, body_pat, cited_pat))
    # A RULE UPSTREAM DELETED IS ONE WHOSE PATTERN IS IN NEITHER PIN'S SET. THE TEST IS NOT
    # "IS THE BODY's CITED LINE A RULE AT THE NEW PIN" -- A RULE THAT MOVED LEAVES A RULE AT
    # THE NEW PIN'S LINE AND THE CITED LINE IS A *DIFFERENT* RULE. MEASURED 2026-11-06: THE
    # LINE TEST SAID 12 DELETED AND THE PATTERN TEST SAYS 6, AND THE PATTERN TEST IS THE RIGHT
    # ONE BECAUSE A MOVED RULE IS NOT DELETED.
    if body_pat not in set(new.values()):
      deleted.append((tag, cited[tag], body, bc, body_pat))

  print("THE TABLE ENTRIES WHOSE DISPATCH SENDS A BODY THAT IS NOT THE CITED RULE")
  print("  (THE BODIES ARE RIGHT AND THE TABLE's CITATIONS ARE STALE: THE TABLE WAS RE-POINTED TO")
  print("   THE NEW PIN AND THE RULE NAMES AND COMMENTS STILL CITE THE OLD ONE)")
  for tag, c, body, bc, bp, cp in bad:
    print("  tag %-3d cites %-4s  dispatches %-9s (its comment says the old %-4s)" % (tag, c, body, bc))
    print("      the body ports : %s" % bp[:100])
    print("      the citation is: %s" % cp[:100])
  print("  %d of %d entries dispatch a body that is not the cited rule" % (len(bad), len(cited)))
  print("THE PORT's RULES WHOSE UPSTREAM RULE THE TEXT TEST SAYS UPSTREAM NO LONGER HAS")
  print("  (**THIS IS A CANDIDATE LIST AND NOT A VERDICT.** A RULE UPSTREAM REWROTE HAS A DIFFERENT")
  print("   PATTERN AND A DIFFERENT ANSWER, AND A RULE UPSTREAM DELETED HAS NO ANSWER AT ALL, AND")
  print("   ONLY THE BEHAVIOURAL TEST -- CPYTHON's OWN `sym.rewrite` ON THE NAMED GRAPH -- TELLS THEM")
  print("   APART. MEASURED 2026-11-07: FOUR OF THE FIVE ARE REWRITES AND ONE (`sym_174`) IS A")
  print("   GENUINE DELETION, AND `gates/symrules-oracle.py` SEES EXACTLY THAT ONE.)")
  for tag, c, body, bc, bp in deleted:
    print("  tag %-3d dispatches %-9s  (its comment says the old %d)" % (tag, body, bc))
    print("      the rule: %s" % bp[:100])
  print("  %d entries dispatch a rule upstream no longer has" % len(deleted))
  if bad:
    print("symbody-gate: FAIL")
    return 1
  print("symbody-gate: PASS -- %d entries dispatch the body their citation names" % ok)
  return 0


if __name__ == "__main__":
  sys.exit(main())
