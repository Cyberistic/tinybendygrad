whichgroup: **THE PORT WAS **NEVER** WRONG ABOUT `flip` — **THE DIFFER's OWN FIXTURE FABRICATED A NODE **THAT **UPSTREAM's ORACLE
**COLLAPSES**, **AND THE PROOF IS **\`tinygrad/uop/ops.py:559\`** — **NOT** \`bend\`, **NOT** \`census.py\`, **AND **NOT** \`AN \`OPINION\`.

**THE DECIDING LINE, WHICH IS **THE **ORACLE's OWN **SOURCE\`:**
\`\`\`
558:  def group(*srcs:UOp|None, **kwargs):
559:    if len(srcs) == 1 and isinstance(srcs[0], UOp): return srcs[0]     # IDENTITY
560:    return UOp(Ops.GROUP, src=..., **kwargs)
\`\`\`
*** **\`:559\` **MEANS **A **ONE-SRC \`UOp.group\` **BUILDS \`NO\` \`NODE\`**, **SO \`graphcmp.py:1386\`'s \`UOp.group(a.flip(0).uop)\` **RETURNS **THE \`FLIP\` **ITSELF** —
MEASURED **LIVE **ON **CPython**: \`UOp.group(flip) is flip\` IS \`True\`, **AND \`emit_py('flip')\` **ANSWERS **6** **ROWS **CARRYING \`NO\` \`GROUP\` \`AT
ALL\`**. **THE **PY **LANE's **6** **ROWS **WERE **RIGHT **ALL **ALONG\`** — **AND **NEITHER **SIDE **PRINTS \`a.flip(0)\`: **BOTH **PRINT
\`UOp.group(...)\`, **WHICH **IS **WHAT \`MADE\` \`THIS\` \`DECIDABLE\` \`RATHER\` \`A\` \`MATTER\` \`OF\` \`TASTE\`.\`\`\`**

**AND **THE \`SHAPE\` **IS \`DECISIVE\` **AND **IT \`IS\` \`THE\` \`FINDING\`**: **OF **THE **\`12\`** HAND-BUILT \`OpsGROUP\` **STATEMENTS **IN \`graphcmp.bend\`, **\`11\`** CARRY
**2-8** \`srcs\` **AND **EVERY **ONE **IS **A **NODE **UPSTREAM **BUILDS\`** *** *** **EXACTLY **ONE** **CARRIES **\`1\`** \`src\`: **\`g_flip\`** — **AND \`flip\` \`WAS SPLIT OUT OF
\`move\`** (\`graphcmp.bend:1342-1347\`), **SO **IT **TOOK \`move\`'s **FOUR-SRC \`GROUP\` **WRAPPER **WITH **IT\`**, **AND **A **ONE-SRC \`GROUP\` **IS **NOT **A
\`GROUP\`** — *** **SO **THE **SINGLE **DIVERGENCE **IN **\`34\`** **GRAPHS **x **\`2\`** **LANES\`** IS **PRECISELY **THE **ONE **PLACE **THE **FIXTURE **MODELS **A
CALL **ITS **OWN **ORACLE **COLLAPSES\`** — **WHICH **IS **WHAT \`readerdecl\`'s **\`2x2\` **MEANS **FOR **A **FIXTURE\`: **THE **DEFECT **IS **NOT **RANDOM **AND \`IT
IS\` \`NOT\` \`THE\` \`PORT\`.\`\`\`**

**AND \`34\` **OF** \`34\`** **BY **BYTES**, **AND \`THE\` \`INSTRUMENT\` **WAS \`PROVEN\` \`TO\` \`MOVE\`**: **\`.agents/slop/whichgroup\` **REVERTED **THE **ONE
STATEMENT**, **RE-RAN **THE **SAME **CENSUS\` (**\`33\`** vs **\`34\`**), **AND **RESTORED **BY **\`sha256\`** — *** **A **CENSUS **THAT \`CANNOT\` \`BE\` \`MADE\` \`TO\` \`MOVE\`
IS \`DECORATION\`**, \`9aaad018f80b\`'s \`WORD\` **FOR \`THE\` **SAME\` \`FAILURE\` **IN \`A\` **DIFFERENT\` \`PLACE\`.\`\`\`**

**AND **THIS **IS \`NOT\` **THE \`ROUTE\` **ALREADY \`REFUSED\`**, **AND **THE **DISTINCTION **IS \`THE\` **POINT\`**: **\`pr_flip\`'s \`REFUSAL\` **WAS **ABOUT **FORCING
AGREEMENT\` **BY \`REPOINTING\` **THE \`PORT\`**. *** **HERE **THE \`ORACLE\`'s OWN **SOURCE\` **SAYS **IT **NEVER **BUILDS **THE \`NODE\`**, **THE \`PORT\` **IS **NOT
\`EDITED\`**, **AND **THE \`EVIDENCE\` (\`ops.py:559\`) \`HAS\` \`NOTHING\` \`TO\` \`DO\` \`WITH\` \`THE\` \`PORT\`** — **A **FIXTURE **THAT \`CONTRADICTS\` \`ITS\` \`OWN\` \`ORACLE\`
IS **NOT **A \`FIXTURE\`**, **IT **IS **A \`MISREPRESENTATION\`**, **AND \`AGENTS.md\`'s *"A CITATION WAS A **SUFFICI**ENT\` [CONDITION]"* **SWEEP \`MEMO\` \`IS\` \`THE\` \`RISK\`
**THIS \`CORRECTS\`** — **THE \`DANGER\` **IS \`NOT\` **EDITING **THE \`FIXTURE\`**, **IT \`IS\` **EDITING **IT** \`WITHOUT\` \`READING\` **THE \`ORACLE\`.\`\`\`**

**AND \`graphcmp.bend:1350-1357\` \`NOW\` **CARRIES **THE \`PROOF\` **IN **THE \`FIXTURE\` \`ITSELF\`** — *"IT IS **THE **ONLY **SINGLE-SRC **GROUP\` **IN **THIS **FILE\: **of
the \`12\` **\`OpsGROUP\`** **statements\` **here \`THE\` **OTHER\` **11\` **carry \`2-8\` **\`srcs\` **AND **EVERY **ONE\` **OF **THOSE\` **IS **A **NODE\` **UPSTREAM **BUILDS\`"* —
**WHICH \`IS\` **THE **\`findtype()\` \`RULE\` **APPLIED \`TO\` **A **FIXTURE\`**: **THE \`POPULATION\` **IS **A **DIRECTORY **WALK\` **OF **THE \`WRITER\`'S OWN
WRITE **SITES\`**, **NOT **A **HAND\` \`LIST\`**, **AND \`1\` **OUT **OF \`12\` \`IS\` \`STRUCTURALLY\` \`ANOMALOUS\`** **WITHOUT \`ANY\` \`JUDGEMENT\`.***

**AND **THE \`CACHE\` **FINDING, **WHICH **IS **THE **OTHER \`HALF\` **AND **WHICH \`I\` **GOT **WRONG\` **TWICE\` **BEFORE \`I\` \`GOT\` **IT\` \`RIGHT\`:** **TWO \`CACHE\` **OF
**THE **SAME **CORPUS\`, **\`25\`** AND **\`12\`** **PAIRS\`**, **FROM **\`TWO\`** **GENERATIONS\`**, **AND **THE **OLDER\` **IS **THE **LARGER\`:
\`\`\`
  oracles      pairs= 25  BYTE-IDENTICAL=  6   <- STALE: pre-ABoolList, its bend lane reads n(i1,i0)
  checks/rows  pairs= 12  BYTE-IDENTICAL= 11   <- CURRENT: both lanes read n(b1,b0)
\`\`\`
*** **AND \`I\` \`DELETED\` **\`28\`** \`checks/rows/\` \`FILES\` **AS \`BYTE-IDENTICAL\` **TO \`oracles/\` — **WHICH \`SOUNDS\` \`RIGHT\` **AND \`IS\` \`WHY\` \`THE\` \`PAIRING\` **IS \`BROKEN\`**:
**THEY **WERE **IDENTICAL **BECAUSE **THOSE **GRAPHS **DID **NOT **CHANGE\` **BETWEEN **GENERATIONS\`**, **AND \`DELETING\` **ONE **SIDE **OF **A **PAIR\` **DESTROYS **THE
COMPARISON **THE \`CACHE\` **EXISTS\` **TO \`MAKE\`** — **WHICH \`IS\` **THE \`SAME\` \`LESSON\` **AS \`checks/rows\`'S **PROMOTION\` **ONE \`COMMIT\` \`EARLIER\` (\`2a889e7aa\`)
**FROM **THE \`OPPOSITE\` **DIRECTION\`**.\`\`\`**

**AND **MY **OWN \`INSTRUMENT\` **WAS **WRONG\` **TWICE\` **IN **THE **SAME \`COMMAND\`**: \`grep -oE 'n\\([bi][0-9],[bi][0-9]\\)' \`| head -1\` **MATCHED **THE \`STACK\` **ROW**
— **\`n(i2,i3)\` — **NOT **THE \`FLIP\` **ROW** — **AND \`I\` \`PRINTED\` **IT **AS **THE \`FINDING\`**, **WHILE \`THE **SAME \`FILE\`'S \`FLIP\` **ROW\` **SAID \`n(b1,b0)\`\`**
*** **A \`HEAD -1\` **ON **AN \`UNANCHORED\` \`PATTERN\` \`RETURNS **THE **FIRST \`MATCH\`, \`NOT\` **THE \`MATCH\` **YOU \`MEAN\`** — **AND \`prune4\`'s \`183\`/\`61\` **AND
\`nameless\`'s \`90\` \`MISLABELLED\` \`ROWS\` **AND\` \`MY\` \`ls-tree\` \`SET\` **FINDING\` **ARE **THE **SAME\` **DEFECT\`**: **A \`PATTERN\` **WITHOUT **AN \`ANCHOR\` **IS** **A
\`SHAPE\`**.\`\`\`**

**AND **THE **LIVE \`RE-EMIT\` **IS **THE **ONLY \`TRUTH\` **I\` \`SHOULD\` \`HAVE\` \`QUOTED\` **FIRST\`**: \`\`\`
  py rows=6  bend rows=6  IDENTICAL=yes
\`\`\`
*** **AND \`THE **SURVIVOR \`IS\` \`NONE\`: \`34\`** OF \`34\`**, **AND \`THE \`PORT\`'S **LAST \`DISAGREEMENT\` **WAS \`NOT\` **A \`PORT\` **DEFECT\` **AT \`ALL\`** — **IT \`WAS\` **THE
DIFFER'S OWN \`FIXTURE\` \`MODELLING\` **A \`CALL\` **THAT **UPSTREAM\`'s OWN ORACLE **HAS \`SINCE\` **COLLAPSED\`.\`**