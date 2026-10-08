## THE CLEANUP SET I MEASURED WAS **459**, AND THE TRUE NUMBER IS **0**

**MEASURED 2026-10-08, `git ls-files --others --exclude-standard` vs **my** `os.walk`:**

| question | wrong way | right way | count |
|---|---|---|---|
| what is **untracked** | `os.walk` — counts **IGNORED** files | `--others --exclude-standard` | **28,227** ignored vs **1** not |
| what is **owned** | `git ls-tree -r HEAD` | `jj file list -r @` | **80.3%** jj-owned |
| what is **a path** | counting **directories** | files only | **1,085 -> 449** |

*** **THE ANSWER IS **0** FILES THAT GIT NEITHER TRACKS NOR IGNORES AND \`jj\` DOES NOT OWN** — **AND **THE **ONE** FILE \`--exclude-standard\` REPORTS **IS
A **RUNNING **UNIT's**, **ALREADY \`jj\`-OWNED**.** ***

**SO "459 untracked paths, 9.0 MB" WAS WRONG **THREE** TIMES: it counted **28,227** files that `.gitignore` **already** excuses (**50** entries),
then counted **\`.pyc\`** that `.gitignore:13` covers, then treated a **jj pending commit** as **no owner** — **each error making the number
**bigger**, which is the direction a cleanup brief wants and therefore the direction nobody checks.**

**AND `\`.gitignore\` HAS **50** ENTRIES, \`__pycache__/\` AMONG THEM, AND **0** \`.pyc\` ARE TRACKED IN HEAD** — SO **THE **IGNORED **SET **IS
**~200x** THE **UNTRACKED **SET** IN **THIS **TREE**, **AND \`AGENTS.md\`'s WARNING IS ABOUT **THE **WRONG **ONE**: IT WARNS THAT \`git ls-files\` READS
**THE **INDEX**, **WHICH **IS **TRUE **AND **COST **THE **NINTH **STALE-INDEX **INCIDENT** — **BUT **A **FILESYSTEM **WALK **HAS **THE **MIRROR
DEFECT, **AND **A **WALK **IS **WHAT \`I\` AND **TWO **UNITS **USED**.**

**THE COMMANDS THAT ASK **THE **RIGHT **QUESTIONS**, ONCE EACH:**
- **what is in the tree**   -> `git ls-tree -r HEAD`
- **what git owns**         -> `git ls-files` *(and it is the INDEX — trust it for THIS and nothing else)*
- **what git ignores**      -> `git ls-files --others --ignored --exclude-standard`
- **what nothing owns**     -> `git ls-files --others --exclude-standard` **minus** `jj file list -r @`
- **what a suffix set saw** -> `os.walk` **minus** all of the above

## ARMED: **400 EMPTY BLOBS IN THE DEFAULT INDEX — 7.4 MB A BARE `git commit` WOULD HAVE DESTROYED**

**THE EIGHTH STALE-INDEX FAILURE AND **THE ONLY ONE THAT PRODUCES A **VALID** COMMIT FROM AN **INVALID** STAGE** — so
unlike the seven before it, **nothing about the result looks wrong**: the commit succeeds, the message is honest,
`git push` reports `OK`, and **400 files are emptied in the tree.**

`git add --intent-to-add` writes the **empty blob** `e69de29b…` into the index while leaving the worktree file
intact. Measured at 2026-10-08: **400 armed entries**, all with content on disk —
`boolexit/REPORT.md` (21 025 B), `boolexit/census.out` (119 961 B), `boolexit/census.py` (18 957 B),
`bitcastrow/fold.bend.ORIG` (384 814 B) — **7.4 MB total.**

**539 empty files ARE legitimate** (`__init__.py`, `.agents/slop/substrate/fixtures/empty.bend`, captured
streams that were empty), **so \`size == 0\` IS NOT THE TEST.** ***The test is the PAIR*: **empty in the INDEX
and NOT empty in HEAD** — and that needs `git ls-tree -r HEAD`, **not** `git ls-files`, because **the index is
the thing that is wrong.**

**DISARMED with `git read-tree HEAD`**, verified **0** armed and **0** staged. **IT RE-ARMS**, so this is a
standing hazard while agents are running, not a one-time event.

**THE SEVEN BEFORE IT, FOR THE DENOMINATOR: \`9144d179e25a\` deleted **110**; \`c83f04ad1c12\` deleted **20** and reverted
**46** as \`R100\`; \`75ab9b8f8984\` re-added **46**; one **66 D + 4 M / 13,389 lines**; one **58** entries; one
\`--intent-to-add\` on \`gates/gate-surface.py\` — **which would have committed a **DELETION of a gate body** instead
of a repair.** **ALL EIGHT** ARE **ONE** MECHANISM: **a commit taken against \`HEAD\` with an index that does not
contain \`HEAD\`.**

## PROTECTED: LOAD-BEARING INSTRUMENTS **INSIDE** THE SWEPT TREE

**A path inside a swept tree is deletable while four gate bodies still name it.** Found
2026-10-07, not by a prune but by asking who cites what:

| path | lines | why it is protected |
|---|---|---|
| `.agents/slop/hooks/run.py` | 208 | **THE RUNNER.** `:71` binds `charge = _GK.charge` and `:142` is `return charge(r.returncode), ...` — it assigns every gate's verdict. Cited by name, in prose, from **`checks/cl-port-gate.py:62`, `gates/gate-surface.py:99`, `gates/gatekit.py:86`, `gates/gates-pop.py:149`** — **4 files, 0 of them inside `.agents/slop/`.** |

**Its citations are PROSE, not imports — 0 hard dependencies — so a prune would not break
the tree, it would make **4 gates' docstrings cite a line that is no longer there.** That is
`AGENTS.md`'s measured lesson (`a gate's required input belongs beside the gate IN GIT`)
applied to an **instrument** rather than an input, and it was not on this ledger.

**AND ALL 5 SPOT-CHECKED LINE NUMBERS ARE CORRECT** (`:33`, `:112`, `:138`, `:142`, `:166`
— verified by reading each line, not by trusting the claim). **So the defect is LOCATION,
not ACCURACY** — which is the opposite of the usual citation failure, and the reason a
reader must check *both*.

## SLOP PRUNE LEDGER (2026-10-06T16:00Z, HEAD `4bb9afa1`)

`.agents/slop` went **133 MB -> 43 MB** this session. Every deletion below named a
**generator, a report, or a per-file reason**, per the rule that a prune which cannot say
what it spared is a prune nobody can audit.

| removed | bytes | authority |
|---|---|---|
| `substratepop/tree/` | 11 MB | **its own `REPORT.md:8` calls it "debris"**; a frozen copy of the port that already DIVERGES from the live tree (`renderer/tc_ptx.bend` differs) — neither a mirror nor re-derivable |
| `arghalf/`, `loopfix/`, `xd1/`, `dd-cone-wt/` frozen trees | 84 MB | `prune2` — superseded by a re-takeable measurement |
| 11 `__pycache__` dirs | 0.5 MB | already `.gitignore`d (`.gitignore:13`), 0 tracked |
| `jjhazard/index-snapshot.bin` | 732 KB | a raw `.git/index` DIRC dump, untracked, named by nothing |
| 11 `loopfix/*.bin` | 10.0 MB | `prune3` — each a `bend -o` build with a committed generator and a committed `.err` naming the command; outputs (`.rows`) committed |
| `run34/gcb-{head,now}.bend` | 108 KB | **my own scratch** — the byte-identity that proved `graphcmp.bend` unchanged is IN the commit message, not two copies of the file |
| `webgpu_call.fresh.mjs` | 1.0 MB | build product; `e2e_mm_run.mjs:48` documents the port's own is STALE and the runner regenerates it; byte-identical to tracked `e2e/webgpu_call.mjs` |

**SPARED, each with a measured reason (not a shrug):**
- `strays/` 3 MB — `prune3` re-audited all history: **0 of 24 KEEP blobs ever appeared at the live path**, so they are UNIQUE, not a mirror.
- `e2e/` 2 MB — **named by 25 committed readers**; deleting it breaks readers that are not tests.
- `loopfix/insprobe{,-v2,-old}.bin` 340 KB — the generator was **deleted and never committed**, so "no generator" is an **absence, not a proof of redundancy**.
- `spine/` (8 identical `.out`) and `rerun/` (7) — **the duplicates ARE the measurement**: `stable-pairs` exists because two runs must produce the same bytes.
- 1.96 MB of remaining redundant blobs — every group is either a fixture sandbox (37 groups, 0.09 MB, load-bearing) or **run evidence where a duplicate is the witness**.

**THE ONE I BROKE MYSELF:** my own `git add -A` committed 15 regenerated `.txt` fixtures
(`git ls-files '*.txt'` 2 -> 19). `git add -A` **cannot tell a violation from evidence** — it
adds everything the index lacks, which is exactly what `no-txt.py` refuses. Fixed in its own
commit so the check still means something. **Commit-by-explicit-path exists for this.**