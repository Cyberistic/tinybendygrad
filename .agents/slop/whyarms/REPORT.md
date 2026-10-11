# whyarms — what arms the default git index, measured rather than assumed

Unit `whyarms`, 2026-10-11. **Nothing committed, nothing staged.** No `git add`, `commit`,
`reset`, `checkout`, `stash` or `read-tree` was run against this repository at any point.
Every git call in every instrument here carries `--no-optional-locks`, and `.git/index`'s
sha256 was compared before and after each live gate run (§7).

Touched: `checks/index-arm-gate.py` (new) and `.agents/slop/whyarms/` (new). Nothing else.

---

## 0. WHERE MY OWN MEASUREMENTS WERE WRONG FIRST

Four, with the before-value, because eleven instruments this session reported a clean number
by not being able to see.

**(a) A `||` fallback made me name a file that does not exist.** I ran
`cat .jj/repo/config.toml 2>/dev/null || jj config list --repo`, got a config, and wrote in my
working notes that `.jj/repo/config.toml` contains `snapshot.auto-update-stale = true`.
**`.jj/repo/config.toml` DOES NOT EXIST.** The text came from the `||` branch. The content was
right; the *path* was invented by the shell. The real location is
**`~/.config/jj/repos/1013720a994d3c872163/config.toml` — outside the repository**, keyed by a
hash of the repo path, in neither `.jj/`, nor `.git/config`, nor git at all. Anyone auditing
the repo for the arming switch will not find it, which is most of why it survived.

**(b) `RC=0` on a crashed instrument, twice.** I ran
`.venv/bin/python repro.py | tee repro.out; echo RC=$?` and got **`RC=0` over a
`FileNotFoundError` traceback** — `$?` was `tee`'s exit, not Python's. I had been told `timeout`
does not exist here (`rc=127`); the same class of bug is *any* pipeline whose last stage is a
filter. Every run after this uses redirection, never a pipe.

**(c) mtime has 1-second granularity and it made a real change look like no change.** The first
`repro.py` compared `.git/index` by `st_mtime` only, and reported that `jj status` "did not
write the index" — in a run where the index entry count had in fact moved 1→2. `repro2.py`
signs on `sha256/size/inode` instead. *Before-value of the wrong method: "A1 after 'jj status'
(idle) mtime=1791684011", which is consistent with both "unchanged" and "changed".*

**(d) A vocabulary collision in my own census.** My regex over 190,824 commit messages for the
destruction vocabulary matched **20** commits, and **4 of the 20 are about *graph arms***, not
index arms (`c3b4da262f` "FOUR GRAPHS ARMED", `9275e1a783` "THE THREE SUBSTITUTED GRAPHS ARE
ARMED"). The word "armed" means two things in this tree's own prose. Anyone counting incidents
by that word overcounts. **The denominator in §1 is the 16, not the 20.**

---

## 1. THE INCIDENT CENSUS — RECOVERED BY DISCOVERY, WITH ITS DENOMINATOR

**Population:** a regex over the tree's own write site — the commit-message stream of
`git log --all` — then each hit **verified by `git diff-tree`, not believed**.

**Denominator, said in the same sentence as the number:** of the brief's **fourteen** incidents
I could recover **10 destructive events with a naming commit in this repository's history**,
and **could not recover 4** because nothing in the tree names them. **The tree's own ordinals
disagree with the brief's** — `6e6725d3b` (2026-10-08) calls the empty-blob failure
**"THE EIGHTH STALE-INDEX FAILURE"** and `PRUNE-LEDGER.md:20` calls another **"THE NINTH"**, so
"thirteen" and "fourteen" are numbers from outside the evidence, not from it. **A census whose
denominator comes from the brief is not a census.**

| # | commit | date | deletions (measured) | shape | named by |
|---|---|---|---|---|---|
| 1 | `9144d179e25a` | 10-07 | **111** | staged deletions | `08eb1265eb` "deleted 110 files … all 51 artifacts of five units already pushed" |
| 2 | `b70551451278` | 10-07 | **47** | staged deletions | `881f3ed7cb` "**THE THIRD STALE-INDEX DELETION**, and the first one to erase a commit message's own claim" |
| 3 | `75ab9b8f8984` | 10-07 | 5 (**50 additions**) | collateral re-add | `9b0cd99dee` "**THE FOURTH** STALE-INDEX COLLATERAL COMMIT" |
| 4 | *(the jj index wipe)* | 10-07 | **6141** | whole-tree wipe, `origin/master` left with 2 files | `813bbec3ee` "RESTORE 6141 FILES DELETED BY THE JJ INDEX WIPE" |
| 5 | *(broad `add -A`)* | 10-07 | 15 `.txt` re-committed | stale content | `9d44f2c632` "fix, **THE SECOND TIME**: MY OWN `git add -A` RE-COMMITTED THE SAME 15 `.txt`" |
| 6 | `c7ad2ac4d` | 10-10 | **7** | foreign entries | `ee517b819` "committed 8 files that were not mine and did not belong to its message" |
| 7 | *(520-file deletion, pushed)* | 10-07 | 520 | the guard was decoration | `9aaad018f8` "PROVEN BY PUSHING A 520-FILE DELETION WITH IT INSTALLED" |
| 8 | *(index lying, live)* | 10-07 | 88 invisible | paths absent from the index | `480859c97c` "THE INDEX IS LYING AT 88 FILES RIGHT NOW … THE CATASTROPHE GUARD ITSELF IS ONE OF THE 102" |
| 9 | *(400 empty blobs, 7.4 MB)* | 10-08 | 0 (latent) | **`--intent-to-add`** | `6e6725d3b` "**THE EIGHTH** STALE-INDEX FAILURE … THE ONLY ONE THAT PRODUCES A **VALID** COMMIT FROM AN **INVALID** STAGE" |
| 10 | *(untracked/ignored conflation sweep)* | 10-08 | 0 | wrong population question | `PRUNE-LEDGER.md:20` "cost **THE NINTH** STALE-INDEX INCIDENT" |

**Four I could NOT recover, and how I know:** the brief's *thirteenth* (30 staged entries, 29
deletions, paths absent from `git ls-files --stage` entirely) and three unnamed ones. No commit
message, no report under `.agents/slop/` (606 directories, walked), and no reflog entry
(`.git/logs/HEAD`, 1022 lines, of which **650 are `export from jj`**) names them. **Stating
them as recovered would be exactly the unsourced attribution `jjhazard/REPORT.md` §7 retracts.**

**Shape × cause, and the one number that matters:** of the 10 recovered, **4 are staged
deletions, 2 are foreign/stale entries, 2 are whole-index wipes, 1 is intent-to-add, 1 is a
wrong-population question.** Every one of the 10 is a **git-side** event. Not one of them is
attributable to `jj` *deleting* anything — which is the finding §2 and §3 turn on.

### The messages are the casualty report, and the messages are wrong
Measured by `git diff-tree` at HEAD `05aab2165`, 2026-10-11T02:0xZ:

| commit | message says | `diff-tree` says |
|---|---|---|
| `b70551451278` | "46 renames … 46" | **47** deletions |
| `9144d179e25a` (via `08eb1265eb`) | "110 files" | **111** deletions, 12 additions |
| `c7ad2ac4d` (via `ee517b819`) | "8 files" | **7** deletions, 0 additions |
| `75ab9b8f8984` (via `9b0cd99dee`) | "RE-ADDED ALL 46" | **50** additions, 5 deletions |

**Every one is off, and every one is off by a small number, which is the dangerous kind.**
The casualty report is written by the unit that was hurt; the diff is the only witness.

---

## 2. WHAT IS ARMING IT RIGHT NOW — ISOLATED, WITH A CONTROL

### The chain, reproduced with no other process in the room

A fresh `git init` + `jj git init --colocate`, config `snapshot.auto-update-stale = true`
copied from the real repo's per-repo file, **in a `mkdtemp`**, 2026-10-11:

```
create new.rows, 5000 bytes of random content on disk, UNTRACKED
$ jj status
$ git ls-files -s -- new.rows
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0      new.rows   <-- git's EMPTY blob
$ git status --porcelain=v2 -- new.rows
1 .A N... 000000 000000 100644 0000... 0000...  new.rows   <-- git says N... (intent-to-add)
$ git diff --cached --name-only -- new.rows
                       (nothing -- the instrument named in HEAD's own commit message sees 0)
$ wc -c < new.rows
5000
```

**`jj util snapshot` does the identical thing** — and that is the command the VisualJJ
**branching server** issues on its own, unaided by any unit:

```
$ jj util snapshot
$ git ls-files -s -- new2.rows
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0      new2.rows
```

**So: in a colocated repo, `jj` writes `git add --intent-to-add` placeholders into git's
index, for every new untracked file, on a routine read command.** Not a bug, not an accident —
**this is `jj git colocation` doing what colocation means: the git index and the jj working
copy are two views of one tree, and jj owns writing it.** The brief's hypothesis is right, and
it is the right shape of hypothesis: *by design, not by accident.*

### What jj does NOT do — three negatives, each measured, because the positives are only half a claim

`repro2.py`, six routes, one fresh colocated repo each, 2026-10-11:

| route | result |
|---|---|
| R1 tracked file deleted, then `jj status` | index **rewritten** (sig `9fdd7582bc`→`9ed31e7321`) but **no deletion staged**, `nidx` unchanged |
| R3 `git read-tree HEAD` then `jj status` | index signature **byte-identical** — jj does **not** re-arm |
| R4 disarmed, 6 s idle, nothing invoked | unchanged |
| R5 `git commit` then `jj status` | unchanged |
| **R2 `git rm --cached <p>`** | **ARMS** — `stagedD=['a.rows']`, file still on disk |
| **R6 `git add -A` while the file is transiently absent** | **ARMS** — and a bare `git commit` then **`b.rows` is gone from HEAD**: `tree=['a.rows']` |

**This corrects the brief's premise in one place and confirms it in another.** The brief said
the index "re-armed three seconds after `git read-tree HEAD`". **R3 does not reproduce it:** jj
leaves a disarmed index disarmed, byte for byte. What re-arms is a **git-side** event —
`git rm --cached`, or a broad `git add -A` that catches a file mid-absence — and R6 shows that
one is immediately destructive. The brief was right that the cause runs continuously; it is
right for a different reason than the one it named.

### The writer, counted

**Of 1721 committed `.py` files, exactly ONE constructs a `git add --intent-to-add` argv** —
`.agents/slop/clauseVfix/plant.py:75`, a plant with **one named target path**, run once.
`checks/sweep.py:378` and `gates/gendirs.py:470` both contain the phrase and **both are
docstrings**: `ast` puts a module/function docstring's `Constant` inside an `Expr`, which my
scanner excludes, so **a text search for `intent-to-add` reports three files and the AST reports
one.** The arming is not a committed instrument sweeping the tree. It is **jj, by colocation**,
plus any unit that types `git rm --cached` or an unscoped `git add -A`.

---

## 3. THE LIVE STATE, PINNED

**At HEAD `05aab2165fd9f0c61bf6cc69c32e24f10c5e7701`, read 2026-10-11T02:07:36Z:**

```
index entries                 : 7367
HEAD tree paths               : 7002
[D] staged deletions          : 0
[C] stale                     : 0
[E] foreign additions         : 0
[A] intent-to-add placeholders: 365      7,896,716 bytes with content on disk
    of which `git diff --cached` names : 0
    across 41 owner directories (modulerefuse 26, unreachable 26, orcdecide 24, synonyms 23,
    livenum 22, exitzero 20, citeresolve 16, boolexit 15, …)
```

**It grows.** Measured 350 → 365 within this session; `untrack/REPORT.md:203` measured its own
files going 7 → 12 between two consecutive lines. **The residue is accumulated, not
instantaneous.**

### And the doctrine correction, which is the most important sentence in this report

The project has twice asserted that a bare `git commit` **would have destroyed** the intent-to-add
payload — `6e6725d3b`'s own commit message ("**WOULD HAVE DESTROYED 7.4 MB**") and
`PRUNE-LEDGER.md:32` ("7.4 MB A BARE `git commit` WOULD HAVE DESTROYED").

**MEASURED on git 2.50.1 (Apple Git-155), and it is false:**

```
$ git commit -m "..."                     # index holds ONLY an intent-to-add placeholder
On branch master
no changes added to commit
$ git cat-file -e HEAD:new.rows          -> fatal: path 'new.rows' exists on disk, but not in 'HEAD'
$ git commit -a -m "..."                 -> create mode 100644 new.rows ... 5000 bytes   (REAL content)
```

Same result with a genuine modification staged alongside. **A bare `git commit` REFUSES
intent-to-add entries; `git commit -a` writes the real bytes, not the empty ones.** The 7.89 MB
is **not currently at risk of being committed empty by a bare commit.**

That does not make the shape benign — it makes it **latent**, and latency is exactly how it
becomes an incident: one `git add -A` converts all 365 into staged empty files, and *that* a
bare commit does commit (R6 proved it). **The project's own claim overstates today's risk; the
gate below reports the shape as armed and says in its own output that git currently refuses it,
because an instrument that cries wolf in the other direction is the same defect.**

**One armed state was live during this session and was destroyed by my own command.** At
01:55:33Z the index held **2 staged deletions** of `.agents/slop/stalecites/{REPORT.md,census.py}`
— files that were **on disk and in HEAD** — plus 1 staged modification. At 01:55:39Z I ran
`jj status`; `.git/index`'s mtime became `1791683739`, identical to `.jj/repo/store/extra`'s, and
`jj op log` named the two operations that did it: **`import git head`** and
**`snapshot working copy`, both `args: jj status`**. The staged set went to 0 and the entry count
6998 → 7352. **jj cleared another unit's staged work because I asked it what the tree looked
like.** Nothing was destroyed (both files are on disk), but the demonstration is free and it
happened to me: **`jj status` is not a read-only command in a colocated repo.**

---

## 4. THE INSTRUMENT — `checks/index-arm-gate.py`

Answers one question: **is the default index armed?** Population from `git ls-tree -r HEAD`
(the commit tree) versus `git ls-files --stage` (the index). Names the offending paths and the
shape. Five verdicts imported **from `gates/gatekit.py` by path** — one definition, not a second
copy. `SKIP` is deliberately not imported: this gate has no "could not run" state distinct from
`DEAD`.

| verdict | exit | when |
|---|---|---|
| `PASS` | **0** | the index agrees with HEAD on every path |
| `REFUSED` | **3** | **armed** — *not* `FAIL`: an armed index is a wrong **tool**, not a wrong tree |
| `DEAD` | **5** | no repo, no HEAD, or a 0-path tree — *"a census over nothing is not a clean census"* |

Four shapes, each measured rather than hypothesised: `DELETION` (R2/R6),
`INTENT` (§2), `STALE`, `FOREIGN` (another unit's staged work).

```
$ .venv/bin/python checks/index-arm-gate.py
INDEX-ARM HEAD 05aab2165fd9  TREE 7002  INDEX 7367
INDEX-ARM SHAPES deletion=0 stale=0 foreign-add=0 intent-to-add=365
INDEX-ARM INTENT detail: 365 paths, 7896716 bytes with content on disk; 2.50.1 (Apple
  Git-155), measured 2026-10-11 -- on this version a bare `git commit` REFUSES intent-to-add
INDEX-ARM INTENT (365): .agents/slop/bitcastrow/fold.bend.ORIG, .agents/slop/boolexit/…
INDEX-ARM REFUSED, NOT A VERDICT: 365 intent-to-add placeholder(s) carry 7896716 bytes of
  real work that `git diff --cached` names 0 of. git 2.50.1 refuses to commit them, so nothing
  is lost YET -- and a later `git add -A` converts every one of them into a committed empty file.
$ echo $?
3
```

`--json`, `--tree <path>`, and `--plant` (two states, in a scratch repo).

### The control, proven in both directions

**`--plant` (self-contained, in-repo):**
```
STATE A (clean index)  -> PASS(0)
STATE B (armed index)  -> REFUSED(3)      # armed by git rm --cached + git add --intent-to-add
PLANT OK: the control distinguishes ARMED from DISARMED.   rc=0
```
**And independently, outside `--plant`, two scratch repos through the live entry point:**
```
DISARMED   rc=0   INDEX-ARM PASS: the index agrees with HEAD on all 1 paths.
ARMED      rc=3   INDEX-ARM REFUSED, NOT A VERDICT: 1 path(s) a bare `git commit` acts on
                    RIGHT NOW (1 deletion, 0 stale, 0 foreign addition).
```
**A control that cannot distinguish is not a control**, so this is stated twice, by two routes.

### Read-only, verified
`.git/index` sha256 `d957c2a034f2` and mtime `1791684282` **before and after** a live run:
identical. Every git call carries `--no-optional-locks`, which is what stops git from
*refreshing* (and so rewriting) the index as a side effect of reading it.

---

## 5. WHAT `AGENTS.md`'s CLAUSE SHOULD SAY

**I did not edit `AGENTS.md`** — another unit is reading it. Here is the exact replacement text
for the clause that currently names only `git add -A`.

> **The default index can be armed by a tool you did not type.** `jj git colocation` makes
> `.git/index` and the jj working copy two views of one tree, and **jj writes git's index**:
> **MEASURED in an isolated colocated repo, 2026-10-11 — `jj status`, and `jj util snapshot`
> (the command the VisualJJ branching server issues by itself), each write a
> `git add --intent-to-add` placeholder (`e69de29…`, `git status --porcelain=v2` shows `N...`)
> into `.git/index` for every new untracked file.** At HEAD `05aab2165`, **2026-10-11T02:07:36Z:
> 365 such paths, 7,896,716 bytes with content on disk, across 41 other units' directories**,
> and **`git diff --cached` names 0 of them.** The arming switch
> (`snapshot.auto-update-stale = true`) lives at
> **`~/.config/jj/repos/1013720a994d3c872163/config.toml` — outside the repository**, so it is
> in neither `.jj/`, nor `.git/config`, nor git.
> **AND `jj status` IS NOT A READ-ONLY COMMAND HERE**: at 01:55:39Z it re-imported git HEAD,
> rewrote the index, and cleared another unit's staged work (`jj op log`: `import git head` and
> `snapshot working copy`, both `args: jj status`).
> **THE SHAPES, ALL MEASURED:** staged **deletions** (`git rm --cached`; `git add -A` while a
> file is transiently absent — R6 committed one and the file was gone from HEAD afterwards);
> **`--intent-to-add` empty blobs**; **stale content**; and **another unit's fully staged
> entries**. **`git read-tree HEAD` disarms, discards staged deletions, and jj does NOT re-arm
> afterwards** (R3: index signature byte-identical) — so disarm, then re-apply explicitly.
> **`git diff --cached` IS NOT A DETECTOR**: it names 0 of 365. `git ls-files --stage` against
> `git ls-tree -r HEAD` is.
> **RUN `.venv/bin/python checks/index-arm-gate.py` BEFORE ANY BARE `git commit`.** It exits
> **`PASS 0`** when disarmed, **`REFUSED 3`** when armed — **never `FAIL`, because an armed index
> is a wrong tool, not a wrong tree** — and **names the paths and the shape**. Stage by path
> only; `git add -A` and `git rm --cached` are how R6 happens.
> **AND ON GIT 2.50.1 A BARE `git commit` REFUSES `--intent-to-add` ENTRIES** (measured:
> "no changes added to commit"; `git commit -a` writes the real bytes). **The payload is
> LATENT, not lost** — `PRUNE-LEDGER.md`'s "7.4 MB A BARE `git commit` WOULD HAVE DESTROYED"
> is **false on this git**; one later `git add -A` is what makes it true.

---

## 6. WHAT I DID NOT DO, AND WHAT I WOULD CHANGE

- **Did not** `git add`/`commit`/`reset`/`checkout`/`stash`/`read-tree`. **Did not** touch
  `AGENTS.md`, `checks/differ.py`, `checks/disagree-gate.py`, `checks/census.py`,
  `gates/*`, or `tinybendygrad/`.
- **Did not disarm.** 365 placeholders are live; `git read-tree HEAD` would discard another
  unit's staged work, which is the mass-delete the gate exists to refuse. That is the owner's
  decision, not mine.

**Reported, not edited:**

1. **`AGENTS.md` quotes a dead PID for this daemon.** `601e7929c3`'s message records that it
   corrected a previous dead `pid 2368` to `30543`; the live branching server is now **pid
   10900**, up since 2026-10-11 00:32:04, parented by VS Code's plugin host. **The number will
   be wrong again by the next reader.** The instrument should carry it, not the document.
2. **`checks/sweep.py:378` and `gates/gendirs.py:470` both contain `intent-to-add` in a
   docstring.** A text census reports three armed write sites; the AST reports one. If any
   future gate greps for arming verbs, it inherits a 2-of-3 false-positive rate before it runs.
3. **Two overlapping instruments already exist** and neither answers this question:
   `checks/git-index-guard.py` (from `jjhazard`) answers *"did the index move under me"* — a
   race detector, and it is **green while the index holds 365 armed placeholders**;
   `gates/indexread-gate.py` (from `indextree`) answers *"does any shipped file read its
   population through an index"* — a static source census. **`index-arm-gate.py` is a third
   subject: the state of the index right now.** `indextree`'s own §6 argues for keeping
   message-gates and state-gates apart for exactly this reason; the same argument applies here.
4. **`jj status` needs a warning at its point of use.** The arming is `jj`'s and it is correct,
   but a unit running `jj status` to *look* does not expect to *write*. The cheapest fix is one
   line in `.agents/TOOLS.md`: "`jj status` snapshots; in a colocated repo it writes
   `.git/index`." **I did not edit it** — the brief limits me to two paths.

---

## 7. VERIFICATION, EVERY NUMBER TIMESTAMPED

All at 2026-10-11T02:0xZ against HEAD `05aab2165`, `.venv/bin/python`, git 2.50.1, jj 0.42.0:

| check | expected | measured |
|---|---|---|
| `checks/no-txt.py` | rc 0 | **rc 0** |
| `checks/nl-gate.py` | rc 0, AGREE 205/205 | **`gated 205   agree 205   disagree []`** → `AGREE` |
| `gates/gate-surface.py --report` | rc 0, SHELL HALF: 18 | **`SHELL HALF: 18 entry point(s)`** |
| `checks/disagree-gate.py --lane citations` | rc 0 | **rc 0** |
| `checks/census.py` | rc 3 (stale slot SERVED NEITHER) | **rc 3** |
| `ruff check` on both new files | clean | **All checks passed!** |
| `checks/index-arm-gate.py` (live) | rc 3, names paths + shape | **rc 3**, 365 paths named |
| `checks/index-arm-gate.py --plant` | rc 0, both states distinct | **rc 0**, A→0 B→3 |
| `.git/index` unchanged by the gate | sha equal | **`d957c2a034f2` → `d957c2a034f2`** |
| `.txt` files created by this unit | 0 | **0** (`no-txt.py` rc 0) |

## 8. ARTIFACTS

| file | what it is |
|---|---|
| `repro.py`, `repro.out` | first isolated chain attempt — the one whose mtime granularity lied |
| `repro2.py`, `repro2.out` | six routes, one fresh colocated repo each: **2 arm, 4 do not** |
| `watch2.py` | high-frequency index/HEAD/jj-op-store/process correlator (the attribution instrument `jjhazard` proved) |
| `watch.rows`, `emptydrift.rows` | the live index timeline; `emptydrift` is the growth evidence |
| `armsites.py`, `armsites.json`, `armsites.out` | arming write-site census, AST, over 2550 committed files — **146 offenders, and the classifier's own false positives are named in §2** |
| `idx-not-head.rows`, `head-not-idx.rows` | the two set differences the gate's shapes are built on |
