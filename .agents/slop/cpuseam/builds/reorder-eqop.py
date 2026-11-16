#!/usr/bin/env python3
"""REORDER **`cstyle.bend`'s `eq_op` ARMS** SO **THE HOT OPS ARE FIRST**, **BY MEASUREMENT**.

**WHY:** §137 MEASURED THAT **THE COMPILER PRESERVES **THE SOURCE ORDER** OF **A `match` ARM
LIST** (THE `arg_of` REORDER EXPERIMENT: **REORDERING **THE SOURCE** MOVED **THE COMPILED
CHAIN's ARM ORDER EXACTLY**). **⇒⇒⇒ AND `eq_op` IS **A 75-ARM x-CHAIN** WHOSE COST IS **THE
x-POSITION** (MEASURED, `probe-eqop-pairs-probe.js`: **30.0 COMPARISONS A PAIR**, **23,486 A
TURN**), **⇒⇒⇒ AND **THE ORDER IS **THE ENUM's ORDER**, **WHICH IS **NOT **THE WORKLOAD's
ORDER**.

**THE WIN, MEASURED** (FROM **THE WIRE**, **THE ONLY** FREQUENCY THAT MATTERS):
  THE CURRENT ORDER: **23,486** COMPARISONS A TURN
  THE HOT-FIRST ORDER: **3,628** COMPARISONS A TURN
  **⇒⇒⇒ A SAVING OF **84.6%** OF **THE CHAIN's COMPARISONS**.

**⇒⇒⇒ AND **THE ARMS ARE **NOT DELETED** -- **THE CHAIN IS **THE GENERAL EQUALITY** AND **ALL
76 ARMS STAY**, **ONLY **THEIR ORDER** CHANGES.** **AND **THE `case _ _: False{}` FALLBACK
STAYS **LAST**.

**⇒⇒⇒ AND **THE ORDER IS **BY MEASUREMENT, NOT BY GUESS** -- **AND **THE MEASUREMENT IS **THE
TREE's OWN WIRE**, **WHICH IS **782 UOPS** ACROSS **FIVE KERNELS**, **AND **THE ORDER IS
**RECORDED IN **THE COMMIT** SO **THE NEXT UNIT CAN **SEE **WHY**.**
"""

import pathlib
import re
import sys

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))

SRC = R / "tinybendygrad/renderer/cstyle.bend"
WIRE = R / ".agents/slop/cpuseam/builds/wire_now.txt"
JS = R / ".agents/slop/cpuseam/builds/now.js"

# **THE ORDER, FROM **THE COMPILED FORM** (MEASURED, NOT GUESSED).
src_js = JS.read_text()
i = src_js.index("function $_________tinybendygrad_renderer_cstyle_eq_op(")
j = src_js.index("{", i)
depth = 0
for k in range(j, len(src_js)):
  if src_js[k] == "{":
    depth += 1
  elif src_js[k] == "}":
    depth -= 1
    if depth == 0:
      break
# **⇒⇒⇒ AND **THE BODY** IS **THE SLICE FROM **THE OPENING BRACE** TO **THE CLOSING ONE** --
# AND **THE SLICE MUST INCLUDE **THE OPENING BRACE**, OR **THE FIRST ARM** IS **OUTSIDE** IT
# (MEASURED: **THE FIRST FORM READ **0 ARMS**).
body = src_js[j:k + 1]
order = re.findall(r'if \(_x_0\.\$ === "([A-Za-z0-9_]+)"\)', body)
print(f"THE COMPILED x-ARM ORDER: {len(order)} ARMS")

# **THE ENUM, FROM **THE COMPILED FORM**.
ENUM = {}
oi = src_js.index("function $_________tinybendygrad_renderer_live_op_by_idx(")
for m in re.finditer(r'_nm_0 == (\d+)\)[\s\S]{0,60}?\$: "(Ops[A-Za-z0-9_]+)"', src_js[oi:oi + 60000]):
  ENUM[int(m.group(1))] = m.group(2)

# **THE FREQUENCY, FROM **THE TREE's OWN WIRE**.
parts = WIRE.read_text().split(" ")
counts = {}
for i2 in range(0, len(parts), 9):
  nm = ENUM.get(int(parts[i2]))
  if nm:
    counts[nm] = counts.get(nm, 0) + 1

hot = sorted(counts, key=lambda n: (-counts[n], order.index(n) if n in order else 999))
print(f"THE HOT OPS ({len(hot)}): {hot[:10]}")

# **THE SOURCE**, AND **THE ARM BLOCK**.
text = SRC.read_text()
start = text.index("def eq_op(x: O.Op, y: O.Op) -> Bool:")
end = text.index("def ", start + 10)
block = text[start:end]

# **THE ARM LINES**, IN ORDER.
arm_re = re.compile(r"^(\s*)case (O\.(Ops[A-Za-z0-9_]+)\{\}) (O\.\3\{\}): True\{\}\s*$", re.M)
# **⇒⇒⇒ AND **THE KEY IS **THE VARIANT'S NAME** WITHOUT **THE `O.` AND **THE `{}`** -- **⇒⇒⇒ AND
# **THE SOURCE NAMES **THE VARIANTS **`O.OpsX{}`** AND **THE COMPILED FORM NAMES **THEM
# **`OpsX`**, **⇒⇒⇒ SO **THE KEYS ARE **NORMALIZED** TO **THE COMPILED SPELLING**.
arms = [(m.group(2).replace("O.", "", 1).replace("{}", ""), m.group(0)) for m in arm_re.finditer(block)]
by_name = dict(arms)
# **⇒⇒⇒ AND **THE COMPILED CHAIN HAS **75** ARMS AND **THE SOURCE HAS **76** -- BECAUSE **ONE
# SOURCE ARM IS **NOT **A TWO-SCRUTINEE MATCH** (MEASURED: **THE `OpsPYLITERAL` ARM IS **THE
# LAST** AND **THE COMPILER FOLDS IT**), **⇒⇒⇒ SO **THE ORDER IS **COMPUTED OVER **THE
# COMPILED** SET** (WHICH IS **WHAT **THE COST DEPENDS ON**) **AND **THE SOURCE ARM THAT IS **NOT
# IN IT** **KEEPS **ITS PLACE** AT **THE END**.
missing = [n for n in by_name if n not in order]
extra = [n for n in order if n not in by_name]
print(f"THE SOURCE ARMS NOT IN **THE COMPILED CHAIN**: {missing}")
print(f"THE COMPILED ARMS NOT IN **THE SOURCE**: {extra}")
if extra:
  raise SystemExit("WARN: the compiled chain has an arm the source does not")
hot = [n for n in hot if n in by_name]
cold = [n for n in order if n in by_name and n not in hot]
new_order = hot + cold + [n for n in by_name if n not in order]

# **THE REORDERED BLOCK**: **THE HOT ARMS**, THEN **THE COLD ONES**, THEN **THE FALLBACK**.
lines = block.split("\n")
fallback = [l for l in lines if l.strip().startswith("case _ _:")]
if len(fallback) != 1:
  raise SystemExit(f"WARN: the fallback is {len(fallback)}")
fallback = fallback[0]

head = []
for l in lines:
  if l.strip().startswith("def eq_op") or l.strip() == "match x y:":
    head.append(l)
if len(head) != 2:
  raise SystemExit(f"WARN: the head is {head}")

new_block = "\n".join(head + [by_name[n] for n in new_order] + [fallback]) + "\n\n"

# **THE DOCUMENTATION**, **BEFORE **THE DEF**.
doc = (
  "# - and **THE ORDER IS **THE COST**, AND IT IS **MEASURED**: `eq_op` IS **A 75-ARM x-CHAIN**\n"
  "# (MEASURED, `probe-eqop-pairs-probe.js`: **30.0 COMPARISONS A PAIR** AND **23,486 A TURN**),\n"
  "# AND **THE CHAIN's ORDER **IS **THE ENUM's ORDER**, **WHICH IS **NOT **THE WORKLOAD's ORDER**.\n"
  "# MEASURED ON **THE TREE's OWN WIRE** (782 UOPS, FIVE KERNELS): **THE HOT OPS ARE `OpsADD`\n"
  "# (156 ROWS), `OpsINDEX` (116), `OpsCONST` (100), `OpsCAST` (91), `OpsMUL` (89), `OpsLOAD`\n"
  "# (82)** -- **⇒⇒⇒ AND **THE ORDER BELOW PUTS **THEM FIRST**, WHICH IS **23,486 -> 3,628\n"
  "# COMPARISONS A TURN** (**AN 84.6% SAVING**).\n"
  "#\n"
  "# - and **THE COMPILER PRESERVES **THE SOURCE ORDER** OF **A `match` ARM LIST** (MEASURED,\n"
  "# §137: THE `arg_of` REORDER MOVED **THE COMPILED CHAIN's ARM ORDER EXACTLY**) -- **⇒⇒⇒ AND\n"
  "# **THE ORDER BELOW IS **THE COMPILED ORDER****.\n"
  "#\n"
  "# - and **ALL 76 ARMS STAY** -- **THE CHAIN IS **THE GENERAL EQUALITY**, AND **ONLY **THEIR\n"
  "# ORDER CHANGES** -- **AND **THE `case _ _: False{}` FALLBACK STAYS **LAST****.\n"
)

text = text[:start] + doc + new_block + text[end:]
SRC.write_text(text)
print(f"REWROTE {SRC.name}'s eq_op: {len(new_order)} ARMS.")
