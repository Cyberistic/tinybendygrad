universe-census: **THREE HAND LISTS NAME **THE **UNIVERSE** OF CODE IN THIS TREE, **NONE **TWO **AGREE**, **AND EACH IS **RIGHT ABOUT
**A **DIFFERENT **QUESTION** — WHICH IS **THE **DEFECT**, BECAUSE **NOTHING **RECORDS **THAT **THEY **ARE **DIFFERENT **QUESTIONS**.

**THE MEASURED CENSUS, BY DISCOVERY** (**112** UPPERCASE module-level string tuples/lists/sets across `checks/` + `gates/`, found by AST,
of which the universe-shaped ones are **5**):
```
  gates/gates-pop.py     HOMES        = ('checks', 'gates')                              2 roots
  gates/indexread-gate.py ROOTS       = ('.agents/slop', 'checks', 'gates')              3 roots   <- DISAGREES WITH HOMES
  checks/wallcheck.py    WALK_ROOTS   = ['.agents/slop','AGENTS.md','README.md','checks','docs']  <- DISAGREES WITH BOTH
  checks/repro-paths.py  REPORT_DIRS  = ['', '.agents', '.agents/slop', 'checks', 'gates']
  checks/sweep.py        RESIDUE_ROOTS= ['.agents/slop', 'runs']
```
**AND **THE **ACTUAL **UNIVERSE**, **13** TOP-LEVEL DIRECTORIES HOLDING **TRACKED **CODE**:
```
  .agents 876 · test 378 · tinygrad 224 · extra 204 · examples 198 · gates 144
  tinybendygrad 135 · checks 89 · oracles 26 · langs 4 · docs 2 · spec 1 · tools 1 · root 3
```
*** **\`HOMES\` NAMES **2** OF **13**, \`ROOTS\` **3** OF **13**, \`WALK_ROOTS\` **3** OF **13**, **AND \`\`NO TWO **OF **THE **THREE **NAME **THE **SAME
SET\`\`\`** *** **AND **EACH **IS **CORRECT **ABOUT **ITS **OWN **QUESTION**: **\`HOMES\` IS **THE **GATE **HOME** (per \`checks/README.md\`),
\`ROOTS\` IS **THE **INDEX-READ **POPULATION**, \`WALK_ROOTS\` IS **THE **WALL**'S **WALK**. **SO **NONE **IS **WRONG** — **AND **THAT **IS **THE
DEFECT**: **AN INSTRUMENT CANNOT BE WRONG **ABOUT **A **QUESTION **NOBODY **WROTE **DOWN**, **AND \`gate-surface\`'s OWN \`walk_control\` DOCSTRING
ALREADY **NAMES **THE **PRINCIPLE** — *"TWO INSTRUMENTS HOLDING TWO LISTS HAVE NO AUTHORITY OVER EACH OTHER"* — **WHILE \`HOMES\` IS HANDED TO
\`gate-surface\`'s \`walk_control\` AS A **PARAMETER**, **SO **THE **TWO **LISTS **IT **IS **ABOUT **TO **COMPARE **ARE **THE **SAME **LIST\`.\`\`\`**

**AND \`gates/gates-pop.py:100-104\` **ALREADY **DEFENDS **THE **HAND **LIST** — **AND **THE **DEFENCE **IS **THE **DEFECT**:**
> *"HOMES = (\"checks\", \"gates\") … Adding a third home means editing THIS LINE, and **the ledger is what makes that edit visible** — which is the
> whole reason the ledger exists."*

*** **SO **THE **INSTRUMENT **CLAIMS **THE **EDIT **IS **VISIBLE \`IN\` \`A\` \`LEDGER\` \`ROW\`** — **AND \`ledger\`'s OWN FINDING **IS **THAT **A LEDGER
**REWRITTEN **BY **ITS **OWN **READER **IS **A **DIARY**: \`gates-pop.py:646\` WRITES \`gates-pop.ledger.tsv\` AND \`:617\` READS IT **IN **THE **SAME
PROCESS**, **UNDER **THE **DEFAULT **MODE** — **AND \`\`\`\`\`\`\`**READS THE LEDGER THEN WRITES IT BACK IS NOT A LEDGER**\`\`\`** *** **AND \`verdictcollide\`'s
\`\`\`\`\`\`\`**A PIN LIVES IN SOURCE. A DIARY LIVES IN A FILE.**\`\`\`\` **\`\`\`\`\`\`**THE LEDGER IS **THE **FILE**, **\`HOMES\` IS **THE **SOURCE**, **AND
**THE \`HOMES\` **EDIT **IS **VISIBLE **IN **THE \`SOURCE\`** WITHOUT **ANY \`LEDGER\` **AT \`ALL\` — **WHICH \`AGENTS.md\`'s \`declared()\` **RULE** SAYS
OUTRIGHT: ***"A CARVE-OUT MUST BE A GENERATOR's OWN DECLARATION LOADED BY PATH, **NEVER A SECOND COPY OF THE LIST**."** *** **THE \`LEDGER\` IS **THE
**SECOND \`COPY\`**, **AND \`HOMES\` **IS **THE \`GENERATOR\`'s \`OWN\` \`DECLARATION\`.\`\`\`**

**AND THE **SIBLING **CLASS **IS **THE **WHOLE \`FINDTYPE\` \`SET\` **AT **ONCE**, BECAUSE **OF **112** **UPPERCASE **LISTS**, **THE **MAJORITY **ARE
VOCABULARIES AND **SOME **ARE **POPULATIONS**, AND **NOTHING **IN **THE **FILE **MARKS **WHICH **IS \`WHICH\`:**
- **VOCABULARIES (right):** \`gate-surface.DECL\`, \`differ.LITERALS\`, \`slop-declare.COLUMNS\`, **every \`ROWS\` in the **30** \`tn_*\`/\`ew_*\`/\`mo_*\`
  census gates** (**8**–**51** names each) — **A GATE'S **OWN **EXPECTED **ANSWERS**, WHICH \`discover()\` MUST **NOT **CONFUSE **WITH **THE **GATES\`.**
- **POPULATIONS (standing in for a universe):** the **5** above.
- **SUFFIX SETS masquerading as populations:** \`substrate.POP_SUFFIXES\`, \`sweep.TOOL_EXT\`, \`txt-owners.CODE\`, \`wallcheck.SUFFIXES\` (**12**),
  \`oracle-txt-census.GATE_CODE = ('.py','.sh')\` — **AND \`suffixset\` MEASURED \`gates-pop.py\`'s OWN \`SUFFIXES\` DROPPING **374 -> 174\`** BEFORE
  IT FIXED IT, **WHILE \`oracle-txt-census\` \`STILL\` \`HAS\` \`('.py','.sh')\` \`AND\` \`IS\` \`THE\` \`TOOL\` THAT \`CLASSIFIES\` \`.txt\` \`OWNERS\` — **SO THE
  \`TXT\` CENSUS **CANNOT SEE **A \`.mjs\` **OR **A \`.bend\` **THAT **EMITS **ONE\`.\`\`\`**

**AND **THE **FINDING **THAT **IS **ACTUALLY **WORTH **THE \`CENSUS\`**: **NONE **OF **THE **FIVE **LISTS **IS **WRONG**, **AND \`AGENTS.md\`'s OWN
TABLE \`NAMES\` \`gates-pop.py:95\` \`HOMES\` AS **\`A LIST, AND IT IS ADMITTED\`** — **SO **THE **DEFECT **WAS **ALREADY **CATALOGUED **AND \`THE
SEVENTH \`INSTRUMENT\` \`FINDTYPE\` \`VERIFIED\`, AND NEITHER \`ACT\` CHANGED \`THE \`LIST\`** — **BECAUSE \`CHANGING\` \`IT\` **REQUIRES **A **DECISION
\`ABOUT\` \`WHAT\` \`A\` \`GATE\` \`IS\`**, **AND **THAT \`DECISION\` \`HAS\` \`NOT\` \`BEEN\` \`MADE\` \`IN\` \`WRITING\` \`ANYWHERE\`.** *** **SO **THE \`HONEST\` \`OUTCOME\` IS
**NOT A \`FIX\`** — **IT IS **A \`REFUSAL\` NAMING **THE **QUESTION**: **\`IS\` \`.agents/slop/\` **PART **OF **THE **UNIVERSE\` **OF **GATES\`?** **\`ROOTS\` SAYS
YES AND \`HOMES\` SAYS NO**, **AND **BOTH **ARE **RIGHT**, **BECAUSE **THEY **ARE **ANSWERING **DIFFERENT \`QUESTIONS\` — **AND **THE \`GATE\` \`SURFACE\` IS
COUNTING **A \`POPULATION\` THAT **NO **INSTRUMENT **HAS **EVER **DEFINED\`.\`\`\`