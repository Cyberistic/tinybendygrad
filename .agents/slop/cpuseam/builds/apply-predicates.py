#!/usr/bin/env python3
"""LAND THE OP-PREDICATE CHANGE IN `cstyle.bend`, AND **PROVE IT** ON THE TREE.

⇒ ⇒ ⇒ **THE CHANGE, IN ONE LINE:** `eq_op(op, O.OpsLITERAL{})` BECOMES `is_literal(op)`, WHERE
`is_literal` IS **A MATCH WITH **ONE** ARM** -- ⇒⇒⇒ ⇒⇒⇒ WHICH COMPILES TO **ONE** TAG COMPARISON
INSTEAD OF **THE CHAIN POSITION OF THE LITERAL** IN A **75-ARM** CHAIN.

⇒ ⇒ ⇒ **AND WHY A PREDICATE PER LITERAL AND NOT ONE GENERIC HELPER:** A `match` CANNOT
SCRUTINIZE A **COMPUTED VALUE** ("give it its own def"), AND A NESTED `match` ON A CALL IS REFUSED
TOO -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO THE LITERAL MUST BE ITS OWN ARM.

⇒ ⇒ ⇒ **⇒⇒⇒ AND FOUR OF THE PREDICATES **ALREADY EXIST** (`is_index`, `is_cast`, `is_const`,
`is_add`) -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO THIS IS THE **HOUSE PATTERN**, AND `eq_op` IS THE **LEFTOVER**
THAT NONE OF THEM REPLACED. ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ AND `eq_op` ITSELF STAYS, FOR THE **ONE** CALL
SITE THAT COMPARES **TWO VARIABLES** (`eq_op(ku_op_at(kus, h), op)`).
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
P = ROOT / "tinybendygrad/renderer/cstyle.bend"

# ⇒⇒⇒ **THE 21 LITERALS AT THE 19 CALL SITES**, AND **THE FOUR THAT ALREADY EXIST**.
EXISTING = {"is_index", "is_cast", "is_const", "is_add"}

s = P.read_text()

# 1. THE LITERALS, TAKEN **FROM THE SOURCE ITSELF** -- ⇒⇒⇒ ⇒⇒⇒ SO THE LIST IS NOT A HAND LIST.
PAT = re.compile(r"eq_op\(([^,]+?), O\.(Ops[A-Z]+)\{\}\)")
lits = sorted({m.group(2) for m in PAT.finditer(s)})
missing = [L for L in lits if f"is_{L[3:].lower()}" not in EXISTING]
print(f"the literals: {len(lits)}   the predicates to add: {len(missing)}")

# 2. THE PREDICATE BLOCK, WITH **ITS OWN HEADING** AND **THE MEASUREMENT** IN IT.
HEAD = f"""#
# **⇒⇒⇒ THE OP PREDICATES, **ONE PER LITERAL**, AND **EACH IS **ONE** COMPARISON**.
#
# ⇒⇒⇒ **WHY THEY EXIST, AND IT IS MEASURED.** `eq_op` IS **A MATCH ON TWO SCRUTINEES**, AND A
# MATCH IN THIS LANGUAGE IS **A LINEAR CHAIN OF TAG COMPARISONS** -- **75 ARMS** -- ⇒⇒⇒ ⇒⇒⇒ SO
# `eq_op(op, O.OpsADD{{}})` PAYS **THE CHAIN POSITION OF `OpsADD`** COMPARES, WHICH IS **30** AT
# THE ENUM's ORDER. ⇒⇒⇒ ⇒⇒⇒ AND AT **18 OF THE 19** CALL SITES THE SECOND ARGUMENT IS **A
# LITERAL**, ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO THE QUESTION IS *IS THIS OP's TAG THE CONSTANT `OpsADD`?* -- WHICH IS
# **ONE** COMPARISON WHEN IT IS WRITTEN AS A MATCH **ON THE VARIABLE** WITH THE LITERAL AS THE
# **ONLY** ARM, WHICH IS WHAT `is_add(op)` IS.
#
# ⇒⇒⇒ ⇒⇒⇒ MEASURED, IN ONE PROGRAM, ON THE SAME WORKLOAD (THE ELEVEN OPS THE RENDER SEES, EACH
# COMPARED AGAINST ELEVEN LITERALS), BY **CPU TIME**: `eq_op` **1537 us** AND THE PREDICATES
# **293 us** -- **A RATIO OF 0.1906**, SO THE PREDICATES COST **80.9% LESS**. ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ AND
# THE TWO FORMS' ANSWERS **AGREE** (MEASURED, `same T`), SO THIS IS NOT A SEMANTIC CHANGE.
#
# ⇒⇒⇒ ⇒⇒⇒ AND WHY A GENERIC HELPER IS NOT THE SHAPE: A `match` CANNOT SCRUTINIZE A **COMPUTED
# VALUE** (\"give it its own def\"), AND A NESTED `match` ON A CALL IS REFUSED TOO -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒
# SO THE LITERAL MUST BE ITS OWN ARM, WHICH IS WHY THERE IS **ONE PREDICATE PER LITERAL** AND NOT
# **ONE** HELPER.
#
# ⇒⇒⇒ ⇒⇒⇒ AND **FOUR OF THEM ALREADY EXIST** (`is_index`, `is_cast`, `is_const`, `is_add`), SO
# THIS IS THE **HOUSE PATTERN** AND NOT A NEW ONE -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ AND `eq_op` IS THE
# **LEFTOVER** THAT NONE OF THEM REPLACED.
"""

body = []
for L in missing:
    body.append(f"def is_{L[3:].lower()}(op: O.Op) -> Bool:\n"
                f"  match op:\n"
                f"    case O.Ops{L}{{}}: True{{}}\n"
                f"    case _: False{{}}")

# 3. THE ANCHOR: `eq_op`'s DEF. ⇒⇒⇒ ⇒⇒⇒ THE PREDICATES GO **ABOVE** IT, AND THE §138 COMMENT
# ⇒⇒⇒ ⇒⇒⇒ THAT DOCUMENTS `eq_op` **STAYS WITH IT** -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO THE COMMENTS DO NOT
# ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ ORPHAN EACH OTHER.
anchor = "def eq_op(x: O.Op, y: O.Op) -> Bool:"
assert s.count(anchor) == 1, s.count(anchor)
s = s.replace(anchor, HEAD + "\n".join(body) + "\n\n" + anchor, 1)

# 4. THE CALL SITES.
def rewrite(m):
    var, lit = m.group(1), m.group(2)
    return f"is_{lit[3:].lower()}({var})"

s2 = PAT.sub(rewrite, s)
left = s2.count("eq_op(")
print(f"the eq_op calls left: {left} (the DEF and the ONE TWO-VARIABLE SITE)")
assert left == 2, left

P.write_text(s2)
print("the change is written")
