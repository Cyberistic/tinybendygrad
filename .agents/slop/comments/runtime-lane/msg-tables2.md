THE runtime/ LANE's SECOND TABLES LEAVE THE COMMENT BLOCKS: 885 LINES, COMMENTS ONLY

THE SAME RULE AS `909ceb4a2` (A TABLE IS DATA, AND DATA IN A COMMENT BLOCK IS A
FILE IN THE WRONG PLACE), AND THE SAME NAMING: `<path-with-slashes-as-dashes>-
<line>.md`.

WHAT MOVED:
  .agents/slop/tables/runtime-ops_amd-9.md                 25 LINES
  .agents/slop/tables/runtime-ops_bend-510.md                5 LINES
  .agents/slop/tables/runtime-ops_nv-3.md                  15 LINES
  .agents/slop/tables/runtime-ops_nv-130.md              120 LINES
  .agents/slop/tables/runtime-ops_qcom-67.md               35 LINES
  .agents/slop/tables/runtime-support-am-ip-3.md            8 LINES
  .agents/slop/tables/runtime-support-am-ip-29.md           9 LINES
  .agents/slop/tables/runtime-support-amd-29.md            19 LINES
  .agents/slop/tables/runtime-support-compiler_cpu-44.md   18 LINES
  .agents/slop/tables/runtime-support-elf-104.md          37 LINES
  .agents/slop/tables/runtime-support-hcq2-11.md           39 LINES
  .agents/slop/tables/runtime-support-hcq2-737.md           4 LINES
  .agents/slop/tables/runtime-support-system-16.md        42 LINES

THE TOOL's EXTENT RULE WAS FIXED FIRST, AFTER IT MEASURED A WRONG MOVE: **A
TABLE's **HEADER **MAY **SPAN **LINES**, **⇒⇒† AND **THE **FIRST **RULE **STOPPED **AT
**THE **SECOND **HEADER **LINE**, **⇒⇒† AND **`runtime/support/system.bend`'s **TABLE
**HAS **A **TWO-LINE **HEADER**, **⇒⇒† AND **SO **IT **WAS **NOT **MOVED **AT **ALL**.
THE **RULE **NOW **RUNS **THE **HEADER **TO **THE **FIRST **BLANK **SEPARATOR**.

AND TWO MOVES **WERE **REVERTED **AFTER **THE **DIFF **WAS **READ**, **⇒⇒† AND **BECAUSE
**THE **CONTENT-PRESERVATION **CHECK **NAMED **THE **LINES **THAT **THE **MOVE **DROPPED**:
  * `runtime/ops_metal.bend` -- THE MOVE **TOOK **THE **"THREE **defs **were **written
    **and **nothing **reached **them"** **SECTION**, **⇒⇒† AND **THAT **IS **A **BUG
    **RECORD** (**THE **PORT's **HISTORY **IS **LOAD-BEARING**), **⇒⇒† AND **THE **RULE
    **IS **THE **BLOCK **THAT **THE **TABLE's **HEADER **OPENS**, **⇒⇒† AND **NOT **THE
    **RUN **OF **INDENTED **LINES **THAT **FOLLOWS **IT**.
  * `runtime/ops_python.bend` -- **THE **MOVE **TOOK **THE **DISPATCH **TABLE**, **⇒⇒† AND
    **THE **DISPATCH **TABLE **IS **THE **LIST **OF **ARMS **WITH **THEIR **UPSTREAM
    **LINES**, **⇒⇒† AND **IT **IS **THE **DIFFERENCE**, **⇒⇒† AND **NOT **A **TABLE**.

THE SAFETY PROPERTY, MEASURED: **EVERY **LINE **THE **DIFF **REMOVED **IS **PRESENT **IN
**A **TABLE **FILE**. THE **CHECK **IS **THE **SAME **ONE **AS **THE **LAST **COMMIT**
(**`.agents/slop/comments/runtime-lane/verify-tables.py`**), AND **IT **NOW **ANSWERS
"POINTERS OK: 48   BAD: 0"** -- **⇒⇒† AND **48 **IS **EVERY **POINTER **IN **THE **LANE**,
**⇒⇒† AND **THE **POINTER's **QUOTED **TEXT **IS **IN **THE **TABLE **IT **NAMES**.

THE BUILD: `bin/bend <file> --check-only` ON ALL 10 FILES TOUCHED. 10 READ `ALL
PROOFS CHECK`.

AND THE **DANGLING-SENTENCE **COUNT **OF **THE **LANE **STAYS **0**, MEASURED BY
`.agents/slop/comments/runtime-lane/dangle.py`.

NOT ONE NON-COMMENT LINE MOVED, MEASURED: `git diff HEAD -- tinybendygrad/runtime/`
FILTERED TO THE NON-COMMENT LINES PRINTS NOTHING.
