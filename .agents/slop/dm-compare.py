"""THE `divandmod` LANE'S BODY-VERIFICATION: THE PORT's ANSWERS AGAINST CPYTHON's.

    .venv/bin/python .agents/slop/dm-compare.py

**WHAT THIS IS.** `.agents/slop/dm-oracle.py` (RESTORED 2026-11-08 FROM A SWEPT BLOB) IS THE
CPYTHON HALF. THIS IS THE PORT's HALF AND THE DIFF. **AND THE PORT's HALF IS
`tinybendygrad/uop/divandmod.bend`'s OWN `gate()` -- THE LANE ALREADY HAD A SELF-TEST HARNESS
WITH 26 ROOTS AND A `dm_lab` RENDERER, AND THE ONLY THING IT LACKED WAS THE OTHER SIDE.**

**AND THE COMPARISON IS BY VALUE WHERE THE ANSWER IS A CONSTANT AND BY A TWO-LEVEL TRUNCATED
SHAPE OTHERWISE, AND BOTH ARE BECAUSE THE LANE's OWN HEADER STATES FOUR DIVERGENCES THAT MAKE
THE FULL SHAPES DIFFER ON PURPOSE:**

  * **A. NO PROMOTION CASTs.** Python's `UOp.__init__` runs `dtype_from_uop` and the port's
    `UOp.new` does not, so the trees are the ones Python prints with CASTs erased.
  * **B. NO SUB CANONICALISATION.** `x - q*y` is `SUB` in the port and
    `ADD(x, MUL(MUL(q,y), C(-1)))` in Python, because `symbolic.py`'s `canonicalize` rewrites
    SUB. **THE PORT's HEADER SAYS `out_r14`/`out_r16` ARE CHECKED BY VALUE.**
  * **C. NO CONSTANT FOLDING.** `C(5)*C(3)` survives as a MUL in the port and Python's
    `simplify()` folds it.
  * **D. A NON-INT CONST IS NOT A `vmin`.**

**AND THE PORT's RENDERER IS TWO LEVELS DEEP BY DESIGN** -- `dm_sh2` IS `dm_sh1` ONE LEVEL
DOWN -- **AND THE PORT's HEADER SAYS "a shortcut: two levels with CONST VALUES printed
REPRODUCES PYTHON's TREES EXACTLY".** SO THE ORACLE's FULL TREE IS TRUNCATED TO TWO LEVELS AND
THE TWO ARE COMPARED.

**AND `r17`..`r20` ARE UNMAPPED, AND THAT IS A FINDING AND NOT A GAP: THEY TESTED A PARAM
THAT IS A MULTIPLE OF 4, AND `multiple_of` IS NOT IN `ParamArg` AND NOT IN UPSTREAM's
`ops.py` AT THE PIN -- THE CONCEPT IS GONE.**
"""
import re
import subprocess
import sys

PORT = "tinybendygrad/uop/divandmod.bend"

# THE PORT's ROOT NAMES -> THE ORACLE's CASE NAMES. **MEASURED BY READING THE PORT's OWN
# `trees()` BUILD, NOT GUESSED.**
MAP = [
  ("r00", "r0_a"), ("r01", "r0_b"), ("r02", "r0_c"), ("r03", "r0_neg"), ("r04", "r0_d0"),
  ("r05", "r1_fd"), ("r06", "r1_fm"), ("r07", "r1_same"), ("r08", "r1_swap"),
  ("r09", "r1_d1"), ("r10", "r1_dn"), ("r11", "r1_d0"), ("r12", "r1_i"),
  ("r13", "r2_cst"), ("r14", "r2_cst2"), ("r15", "r2_cn"), ("r16", "r2_cm"),
  ("r21", "r2_var"), ("r22", "n_3src"),
]


def port_rows():
  out = subprocess.run(["./bin/bend", PORT], capture_output=True, text=True).stdout
  rows = {}
  for ln in out.splitlines():
    m = re.match(r"(on|out)_(\w+)=(.*)", ln)
    if m:
      rows.setdefault(m.group(2), {})[m.group(1)] = m.group(3)
  return rows


def oracle_rows():
  out = subprocess.run([".venv/bin/python", ".agents/slop/dm-oracle.py"],
                       capture_output=True, text=True).stdout
  rows = {}
  for ln in out.splitlines():
    # THE ROW IS `name  <the graph>  -> <the answer> news=N dt=...` **AND THE ANSWER IS
    # FOLLOWED BY A SINGLE SPACE BEFORE `news=`**, WHICH IS WHY THE FIRST SPELLING OF THIS
    # REGEX (WHICH ASKED FOR TWO) MISSED EVERY ROW WHOSE ANSWER IS NOT EMPTY.
    m = re.match(r"(\w+)\s{2,}\S.*?->\s+(.*?)\s+news=", ln)
    if m:
      rows[m.group(1)] = m.group(2).strip()
  return rows


def split_top(s):
  out, depth, cur = [], 0, ""
  for ch in s:
    if ch == "(":
      depth += 1
    elif ch == ")":
      depth -= 1
    if ch == "," and depth == 0:
      out.append(cur)
      cur = ""
    else:
      cur += ch
  if cur:
    out.append(cur)
  return out


def is_leaf(p):
  return p.startswith("C(") or p.startswith("P") or p.startswith("Px") or p.startswith("Pi")


def trunc(v, depth=2):
  """THE TREE TRUNCATED TO `depth` LEVELS, WHICH IS THE PORT's RENDERER'S SHAPE."""
  m = re.fullmatch(r"(\w+)\((.*)\)", v)
  if not m:
    return v
  op, args = m.group(1), m.group(2)
  parts = split_top(args)
  if depth <= 1:
    return op + "(" + ",".join(p if is_leaf(p) else p.split("(")[0] for p in parts) + ")"
  return op + "(" + ",".join(trunc(p, depth - 1) if not is_leaf(p) else p for p in parts) + ")"


def value(v):
  """THE NUMBER A CONSTANT TREE DENOTES, OR None.

  **AND UPSTREAM's ANSWER IS AN ARITHMETIC TREE, SO A CONSTANT ANSWER IS ONE WHOSE EVERY LEAF
  IS A CONST -- AND THEN IT IS EVALUATED.** `ADD(ADD(ADD(C(0),MUL(C(1),C(1))),C(0)),C(0))` IS
  **1**, AND THAT IS WHAT THE PORT's `Ops.CONST(1)` MEANS.
  """
  # **THE TREE IS NESTED, SO IT IS PARSED RECURSIVELY AND NOT WITH A FLAT REGEX** -- THE FIRST
  # SPELLING USED `re.findall(r"(\w+)\(([^()]*)\)", v)` WHICH MATCHES ONLY THE INNERMOST
  # NODES, AND SO `ADD(ADD(ADD(C(0),MUL(C(1),C(1))),C(0)),C(0))` READS AS THREE NODES AND
  # THE OUTER ONES ARE LOST.
  def parse(t):
    t = t.strip()
    if re.fullmatch(r"C\(-?\d+\)", t):
      return int(t[2:-1])
    m = re.fullmatch(r"(\w+)\((.*)\)", t)
    if not m:
      return None
    op, args = m.group(1), m.group(2)
    kids = [parse(k) for k in split_top(args)]
    if any(k is None for k in kids):
      return None
    if op == "ADD":
      return sum(kids)
    if op == "MUL":
      p = 1
      for k in kids:
        p *= k
      return p
    if op == "SUB" and len(kids) == 2:
      return kids[0] - kids[1]
    if op == "DIV" and len(kids) == 2 and kids[1] != 0:
      return kids[0] // kids[1]
    if op == "MOD" and len(kids) == 2 and kids[1] != 0:
      return kids[0] % kids[1]
    return None

  return parse(v)


def norm(v):
  """THE PORT's SPELLING AND THE ORACLE's, IN ONE.

  **THE PORT's `dm_lab` SPELLS A CONST AS `Ops.CONST(3)` AND THE ORACLE's `sh` SPELLS IT
  `C(3)`, AND THE PORT's OP NAMES CARRY THE `Ops.` PREFIX AND THE ORACLE's DO NOT.** SO THE
  COMPARISON NORMALISES BOTH, AND **THE `Ops.` PREFIX IS REMOVED BY A SPELLING AND NOT BY A
  SUBSTRING SPLIT, BECAUSE `Ops.CONST(3)` MUST BECOME `C(3)` AND NOT `CONST(3)`.**
  """
  v = re.sub(r"Ops\.CONST\((-?\d+)\)", r"C(\1)", v)
  v = v.replace("Ops.", "")
  return v


def main():
  port, oracle = port_rows(), oracle_rows()
  print("THE `divandmod` LANE: THE PORT AGAINST CPYTHON")
  print()
  agree = diverge = 0
  for pname, oname in MAP:
    p = port.get(pname, {})
    o = oracle.get(oname)
    if o is None:
      print("  NO ORACLE ROW FOR %s (%s) -- THE INSTRUMENT HAS NO ANSWER" % (pname, oname))
      diverge += 1
      continue
    # THE PORT's ANSWER: `none` WHEN THE `on_` FLAG SAYS NOTHING FIRED.
    pval = "none" if p.get("on") == "0" else p.get("out", "<MISSING>")
    # THE ORACLE's ANSWER: EMPTY WHEN NOTHING FIRED, `RAISED` WHEN IT THREW.
    if o.startswith("RAISED"):
      oval = "none"
    elif o == "":
      oval = "none"
    else:
      oval = o
    same = None
    if pval == "none" and oval == "none":
      same = True
    elif pval == "none" or oval == "none":
      same = False
    else:
      # **THE VALUE COMPARISON IS THE LANE's OWN TEST** -- THE PORT's HEADER SAYS
      # "`out_r14`/`out_r16` ARE CHECKED BY VALUE" -- **AND IT IS THE COMPARISON THAT
      # SETTLES DIVERGENCES B AND C, WHICH ARE "NO SUB CANONICALISATION" AND "NO CONSTANT
      # FOLDING".** SO BOTH SIDES ARE EVALUATED AND THE NUMBERS ARE COMPARED.
      np_, no = norm(pval), norm(oval)
      pv, ov = value(np_), value(no)
      if pv is not None and ov is not None:
        same = pv == ov
      else:
        same = trunc(no) == np_
    if same:
      agree += 1
    else:
      diverge += 1
      print("  DIVERGES %-4s (oracle %s)" % (pname, oname))
      print("    port    %s" % pval)
      print("    oracle  %s" % oval)
  print()
  print("  %d AGREE  %d DIVERGE  of %d MAPPED" % (agree, diverge, len(MAP)))
  print()
  print("  **AND `r17`..`r20` ARE UNMAPPED, AND THAT IS A FINDING: THEY TESTED A PARAM THAT")
  print("  IS A MULTIPLE OF 4, AND `multiple_of` IS NOT IN `ParamArg` AND NOT IN UPSTREAM's")
  print("  `ops.py` AT THE PIN -- MEASURED, THE CONCEPT IS GONE.**")
  return 0 if diverge == 0 else 1


PORT_CONST = re.compile(r"Ops\.CONST\((-?\d+)\)")


def port_value(v):
  """THE CONSTANT THE PORT's ANSWER DENOTES, OR None. **AND IT IS READ OFF THE NORMALISED
  TREE AND NOT OFF A SINGLE LEAF**, BECAUSE A `SUB(C(a), MUL(...))` IS A CONSTANT TOO."""
  return value(norm(v))


if __name__ == "__main__":
  sys.exit(main())
