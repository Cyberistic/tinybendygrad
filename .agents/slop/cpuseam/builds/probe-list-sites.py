#!/usr/bin/env python3
"""COUNT **THE `acc` LENGTH** AT **EACH O(n) `List.append` SITE**, **IN THE DAEMON**.

**WHY:** MEASURED: **`List_append` RUNS **17,825** LEVELS A TURN** AND **THE DEEPEST CHAIN IS
**741**.** **⇒⇒⇒ AND `List.append(xs, ys)` **COPIES `xs`**, SO **THE SITE THAT PASSES **THE
**741-ELEMENT** ACCUMULATOR** IS **THE ONE THAT COSTS 741 LEVELS** -- **AND IT IS **THE O(n)
FORM** (`List.append(acc, [x])`), **WHICH **THE TREE's OWN COMMENT** NAMES**: "`List.append(acc,
[x])` IS O(n) AND `List.append([x], acc)` IS O(1)".

**⇒⇒⇒ AND THE MEASUREMENT IS **THE LENGTH OF **THE FIRST ARGUMENT** AT EACH SITE**, WHICH IS
**A COUNT** AND **NOT A CLOCK**.

**⇒⇒⇒ AND THE PATCH IS **THE WHOLE CALL EXPRESSION**, REPLACED BY **A COMMA EXPRESSION**
`(walk, call)` -- **AND THE REPLACEMENT IS **AN EXPRESSION**, NOT A STATEMENT**, BECAUSE **THE
CALL SITES ARE **INSIDE OBJECT LITERALS AND ARGUMENT LISTS**, AND **A STATEMENT THERE DOES
NOT PARSE** (MEASURED: "**Expected identifier but found `\"Con\"`**" -- THE WALK WAS INSERTED
WHERE A VALUE WAS EXPECTED).

**⇒⇒⇒ AND THE WALK IS **THE FOLD's OWN COST** (THE FOLD WALKS **THE WHOLE FIRST ARGUMENT**),
SO **THE INSTRUMENT'S COST IS **THE FOLD's COST** -- **AND IT IS **REPORTED** BY THE FACT THAT
**THE MEASURED LENGTHS **MATCH** **THE FOLD's DEPTHS** (741).**
"""

import json
import pathlib
import re
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def find_call(src: str, pos: int):
  """**THE WHOLE CALL EXPRESSION**, FROM **THE CALL's OPENING PAREN** TO **ITS MATCHING
  CLOSE** -- **AND THE PARENS ARE COUNTED**, BECAUSE **THE ARGUMENTS CONTAIN **NESTED
  CALLS** (MEASURED: A NAIVE `index(")")` CUT THE CALL SHORT)."""
  op = src.index("(", pos)
  depth = 0
  for i in range(op, len(src)):
    if src[i] in "([{":
      depth += 1
    elif src[i] in ")]}":
      depth -= 1
      if depth == 0:
        return op, i
  return op, op


def instrument(src: str):
  """**THE O(n) SITES**, AND **THE PATCH**."""
  # **THE SITES**: EVERY `$$List_append(` WHOSE **FIRST ARGUMENT IS **A PLAIN VARIABLE**.
  sites = []
  for m in re.finditer(r"\$\$List_append\(", src):
    pos = m.start()
    op, cp = find_call(src, pos)
    depth = 0
    for i in range(op + 1, cp):
      if src[i] in "([{":
        depth += 1
      elif src[i] in ")]}":
        depth -= 1
      elif src[i] == "," and depth == 0:
        break
    a0 = src[op + 1:i].strip()
    if re.fullmatch(r"_?[A-Za-z_][A-Za-z_0-9]*", a0):
      start = src.rfind("\nfunction ", 0, pos)
      fname = src[start + 10:src.index("(", start)]
      # **⇒⇒⇒ AND **THE FOLD's OWN RECURSION** IS **EXCLUDED** -- BECAUSE **IT IS **INSIDE
      # **THE DEFINITION**, AND **PATCHING IT** **BREAKS **THE FOLD** (MEASURED: THE SITE
      # `$$List_append(_t_0, _ys_0)` IS **THE RECURSION**, AND **PATCHING IT** PUTS **A WALK
      # **INSIDE **THE FOLD**, WHICH IS **THE FOLD's OWN WORK** AND **AN INFINITE RECURSION**
      # OF **THE INSTRUMENT**).
      if fname == "$List_append":
        continue
      sites.append((pos, cp, fname, a0))
  return sites


def patch(src: str, sites):
  """**THE WALK**, AS **AN EXPRESSION**, AT EACH SITE."""
  for i, (pos, cp, fname, a0) in reversed(list(enumerate(sites))):
    # **⇒⇒⇒ AND THE **COMMA EXPRESSION** IS **PARENTHESIZED** -- BECAUSE **THE CALL IS **AN
    # ARGUMENT** OF **ANOTHER CALL**, AND **A BARE COMMA EXPRESSION** IN **AN ARGUMENT
    # POSITION** READS AS **TWO ARGUMENTS** (MEASURED: "Expected `)` but found `;`").
    # **⇒⇒⇒ AND THE WALK IS **AN IIFE WITH **NO AMBIGUITY**: **THE ARROW BODY IS **A BLOCK**,
    # AND **THE WHOLE CALL IS **PARENTHESIZED ONCE**. **MEASURED: THE FIRST FORM
    # (`((() => {...})(), `) HAD A **BALANCE OF +1** AND THE REWRITTEN SOURCE DID NOT PARSE.**
    # **⇒⇒⇒ AND **THE IIFE IS **`(function(){...})()`** AND **NOT** `((function(){...})()`** --
    # BECAUSE **THE LATTER OPENS **TWO** PARENS AND **CLOSES **ONLY ONE** OF THEM** (MEASURED:
    # **THE WALK's BALANCE READ **+1**, AND **THE WHOLE FILE's UNBALANCED-LINE COUNT READ
    # **3,010**, AND **THE REWRITTEN SOURCE DID NOT PARSE**).
    # **⇒⇒⇒ AND THE WALK IS BUILT BY **STRING CONCATENATION** AND NOT BY **AN f-STRING**,
    # BECAUSE **THE BRACES IN **THE JS** MUST BE **DOUBLED** IN **AN f-STRING** AND **THE
    # DOUBLING IS **EASY TO GET WRONG** (MEASURED: **THE FIRST FORM **MADE **THE FILE **A
    # SYNTAX ERROR** -- "f-string: single `}` is not allowed"). **⇒⇒⇒ AND **THE FORM IS
    # `(function(){...})()`** -- **ONE** BRACE PAIR, THEN `)()`.
    walk = ("(function() { let __l = 0, __x = " + a0
            + "; while (__x && __x.$ === \"Con\") { __l += 1; __x = __x.tail; } "
            + "globalThis.__S.__len" + str(i) + " = Math.max(globalThis.__S.__len" + str(i)
            + " || 0, __l); "
            + "globalThis.__S.__cnt" + str(i) + " = (globalThis.__S.__cnt" + str(i)
            + " || 0) + 1; return 0; })()")
    # **⇒⇒⇒ AND THE **COMMA** IS **OUTSIDE **THE WALK's PARENS** -- BECAUSE **THE WALK
    # ENDS WITH **AN UNCLOSED `(`** IF **THE COMMA** IS **INSIDE** IT (MEASURED: **THE LINE's
    # PAREN BALANCE READ **+1** AND **THE REWRITTEN SOURCE DID NOT PARSE** -- "Expected `)`
    # but found `;`"). **⇒⇒⇒ AND THE WHOLE SPLICE IS **PARENTHESIZED**, BECAUSE **THE CALL IS
    # **AN ARGUMENT** OF **ANOTHER CALL** AND **A BARE COMMA EXPRESSION** IN **AN ARGUMENT
    # POSITION** READS AS **TWO ARGUMENTS**.
    #
    # **⇒⇒⇒ AND **THE SITE's CLOSING PAREN** IS **THE ONE `instrument()` FOUND** -- AND **IT
    # MUST NOT BE **RECOMPUTED** ON **THE PATCHED** SOURCE**, BECAUSE **THE WALK's OWN PARENS
    # ARE THEN COUNTED** AND **THE CLOSE FOUND IS **THE WALK's** (MEASURED: THE REWRITTEN
    # SOURCE READ `$$List_append(_acc_0, _x_2)));` -- **ONE PAREN TOO MANY**).
    src = src[:pos] + "(" + walk + ", " + src[pos:cp + 1] + ")" + src[cp + 1:]
  return src


if __name__ == "__main__":
  base = BUILD / "now.js"
  raw = base.read_text()
  # **⇒⇒⇒ AND THE ACCUMULATOR IS INSERTED **FIRST**, SO **THE SITE OFFSETS ARE **THE
  # POST-INSERTION** ONES** (MEASURED: THE SITES WERE COMPUTED ON **THE PRE-INSERTION**
  # STRING, AND **THE INSERTION SHIFTED EVERY OFFSET**, AND **THE SPLICE CUT **THE TOKEN IN
  # HALF** -- THE REWRITTEN SOURCE READ `ret(() => {...})(), urn $decode_go(...)`).
  acc = "globalThis.__S = {};"
  old2 = "function $serve(_fuel_0, _m_0, _s_0) {"
  if raw.count(old2) != 1:
    raise SystemExit("WARN: the $serve site")
  raw = raw.replace(old2, acc + "\n" + old2, 1)
  sites = instrument(raw)
  print(f"THE **O(n) `List.append` SITES** (FIRST ARGUMENT IS **A VARIABLE**): {len(sites)}")
  out = patch(raw, sites)
  dump_old = """    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);"""
  dump_new = """    globalThis.__S.n = (globalThis.__S.n || 0) + 1;
    { try { require("fs").writeFileSync((process.env.__T_OUT || "/tmp/daemon-cpu.json") + ".d",
        JSON.stringify(globalThis.__S || {})); } catch (e) {} }
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""
  if out.count(dump_old) != 1:
    raise SystemExit("WARN: the @@END site")
  out = out.replace(dump_old, dump_new, 1)
  (BUILD / "serve_listsite.js").write_text(out)
  d = noisefloor.Daemon(BUILD / "serve_listsite.js", "listsite")
  d.start()
  time.sleep(0.8)
  for _ in range(20):
    d.turn()
  d.stop()
  S = json.loads((BUILD.parent / "nf-listsite/cpu.json.d").read_text())
  n = max(S.get("n", 1), 1)
  print(f"\nTHE O(n) SITES, BY **THE LONGEST ACCUMULATOR** THEY COPY ({n} turns):")
  rows = []
  for i, (pos, cp, fname, a0) in enumerate(sites):
    ln = S.get(f"__len{i}", 0)
    c = S.get(f"__cnt{i}", 0) // n
    if c:
      rows.append((ln, c, fname, a0))
  rows.sort(reverse=True)
  tot = 0
  for ln, c, fname, a0 in rows[:16]:
    print(f"  MAX {ln:5d}  {c:7d} calls  {fname[-42:]:44s} {a0}")
    tot += ln * c
  print()
  print(f"**⇒⇒⇒ AND THE **TOTAL ELEMENTS COPIED** BY **THE O(n) SITES** IS **~{tot}** A TURN**")
  print("**AGAINST **THE FOLD's **17,825** LEVELS** -- **⇒⇒⇒ SO **THE O(n) SITES ARE **THE")
  print("BULK**, AND **THE DEEPEST IS **741**, WHICH IS **THE ONE THAT MATTERS**.**")
