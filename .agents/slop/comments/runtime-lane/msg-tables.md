THE runtime/ LANE's INVENTORY TABLES LEAVE THE COMMENT BLOCKS: 573 LINES, COMMENTS ONLY

THE RULE (RULE 6 OF THIS UNIT's BRIEF): A TABLE IS DATA, AND DATA IN A COMMENT
BLOCK IS A FILE IN THE WRONG PLACE. THE NAMING IS `<path-with-slashes-as-dashes>
-<line>.md` AND THE SOURCE KEEPS A POINTER THAT NAMES IT.

WHAT MOVED, AND WHERE:
  .agents/slop/tables/runtime-ops_amd-62.md                    74 LINES
  .agents/slop/tables/runtime-ops_disk-38.md                   43 LINES
  .agents/slop/tables/runtime-ops_dsp-13.md                    68 LINES
  .agents/slop/tables/runtime-ops_metal-52.md                  64 LINES
  .agents/slop/tables/runtime-support-am-ip-34.md              15 LINES
  .agents/slop/tables/runtime-support-autogen-98.md            26 LINES
  .agents/slop/tables/runtime-support-compiler_amd-54.md       31 LINES
  .agents/slop/tables/runtime-support-compiler_cuda-70.md      22 LINES
  .agents/slop/tables/runtime-support-compiler_llvm-49.md       22 LINES
  .agents/slop/tables/runtime-support-compiler_mesa-19.md      39 LINES
  .agents/slop/tables/runtime-support-compiler_qcom-15.md      33 LINES
  .agents/slop/tables/runtime-support-nv-ip-73.md              50 LINES
  .agents/slop/tables/runtime-support-objc-88.md               37 LINES
  .agents/slop/tables/runtime-support-rdma-bnxtdev-42.md       86 LINES

EVERY TABLE IS AN INVENTORY: "WHAT IS PORTED, DEF BY DEF", ONE ROW PER UPSTREAM
DEF, EACH ROW NAMING THE UPSTREAM LINE IT COVERS AND THE PORT's DEF THAT
ANSWERS IT. THEY ARE THE LANE's LARGEST REMAINING COMMENT BLOCKS AND THEY ARE
DATA.

THE SAFETY PROPERTY, MEASURED, NOT ASSERTED: EVERY LINE THE DIFF REMOVED IS
PRESENT IN A TABLE FILE. THE CHECK IS `.agents/slop/comments/runtime-lane/verify-
tables.py`, WHICH READS EVERY POINTER IN THE LANE AND CONFIRMS (a) THE TABLE
FILE EXISTS, (b) IT CARRIES THE POINTER's FIRST SENTENCE, AND (c) THE DIFF's
REMOVED LINES ARE IN THE TABLES. IT ANSWERS "POINTERS OK: 36   BAD: 0".

AND FOUR PARAGRAPHS WERE PUT BACK AFTER THE FIRST MOVE CUT THEM, BECAUSE THE
FIRST MOVE'S EXTENT RULE STOPPED AT A BLANK SEPARATOR AND LEFT A HEADER WITH
NO BODY:
  * `runtime/support/objc.bend`'s "WHAT THIS FILE IS" (rule 5's header).
  * `runtime/ops_qcom.bend`'s "WHAT this file is" (the same).
  * `runtime/ops_npy.bend`'s "the whole content of the port is FOUR ARGUMENTS".
  * `runtime/ops_nvme.bend`'s "what this file is, and what it is not".
  * `runtime/device.bend`'s "what this file is, and why it exists".

AND ONE PRE-EXISTING DEFECT WAS REPAIRED: `runtime/support/objc.bend` CARRIED A
POINTER TO `.agents/slop/tables/runtime-support-objc-88.md`, AND **THE FILE WAS
NEVER COMMITTED** -- THE COMMIT THAT MOVED THE TABLE (`012448a8d`) REMOVED THE
BODY AND WROTE THE POINTER AND NEVER WROTE THE FILE. THAT IS THE CLASS
`AGENTS.md` NAMES ("A PATH INSIDE A SWEPT TREE IS DELETABLE WHILE THE GATE STILL
NAMES IT"). THE TABLE WAS RECOVERED FROM THE PRE-CUT BLOB (`012448a8d^`) AND
WRITTEN, AND THE VERIFIER NOW ANSWERS 36 OF 36.

AND TWO TABLE FILES FROM EARLIER AGENTS CARRIED NO `# BLOCK:` MARKER, **⇒⇒† AND
THE **VERIFIER **COULD **NOT **READ **THEM**, **⇒⇒† AND **THEY **WERE **NORMALISED
**TO **THE **CONVENTION **SO **THE **VERIFIER **READS **THE **WHOLE **LANE**.

THE BUILD: `bin/bend <file> --check-only` ON ALL 13 FILES TOUCHED. 13 READ `ALL
PROOFS CHECK`.

NOT ONE NON-COMMENT LINE MOVED, MEASURED: `git diff HEAD -- tinybendygrad/runtime/`
FILTERED TO THE NON-COMMENT LINES PRINTS NOTHING.
