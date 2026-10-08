# `quiescefix` — the false green in `checks/substrate-id.py`, closed, and the population given a home

**Unit:** `quiescefix`. **Date:** 2026-10-08. **Python only.** **Committed nothing, staged nothing**
(verified: `git status --porcelain` shows the **index column empty** for all 10 paths I touched).

**The verdict tokens for this unit's own gate, with denominators:**

| surface | token | denominator |
|---|---|---|
| `checks/substrate-id.py --hash` (real tree) | **PASS (0)** | 150 declared / 148 present inputs, 11,355,344 B |
| `checks/substrate-id.py --hash` (`git archive HEAD`, **before**) | **PASS (0)** | **0 declared / 0 present** — the false green |
| `checks/substrate-id.py --hash` (archive + fix, no declarer) | **DEAD (5)** | **0 declared / 0 present**, cause named |
| `checks/substrate-id.py --hash` (archive + fix + declarer) | **PASS (0)** | 147 declared / 144 present inputs, 11,355,344 B |
| `checks/substrate-id.py --plant` | **PLANT: OK** | 11 `PLANT` cases, **31** assertions (counted: 31 `_expect()` sites by `ast`, 31 executed) |

---

## 1. HOW MY OWN MEASUREMENT WAS WRONG — six, before anything else

I inherited six claims. **Four did not survive being run.** Every before-value is stated.

**(a) "`checks/substrate-id.py` (532 lines)" — the number was right and the file was not.**
532 is the **HEAD blob**. The worktree copy was **559**, carrying 36 uncommitted lines from a prior
unit (the `token()` extraction that hoisted ten `NAMES[...]` index sites into one function). I nearly
edited on top of a foreign diff. The diff is preserved intact; `token()` still has **0** `NAMES[...]`
subscript sites, confirmed by `ast`, not grep.

**(b) "Its entire population is `.agents/slop/quiesce/snapshot.py`." — wrong by 150.**
On a real tree the population is **150 declared / 148 present**: **140 members are `tinybendygrad/`
port files**, 9 are `COPIES`, 1 is the `bin` directory. **The declarer is not a member of its own
population** — measured by listing `inputs()` directly, and proved a second way below: two copies of
it at two different paths produce the **identical** digest, which is impossible if it contributed.
The phrase is true only of a tree where the declarer is absent, and there the population is **0**.
So the brief described the *declarer* and called it the *population*.

**(c) "returns `PASS`" — true of 2 surfaces out of 3, and the third was already `DEAD`.**
Measured on `git archive HEAD`: `--hash` → **0 (PASS)**, `--rows` → **0 (PASS)**, `--judge` →
**5 (DEAD)**. `--judge` was `DEAD` **by accident**: `runs/` is gitignored *output*, so the summary
was absent, and `judge()`'s first branch is the absent-summary `DEAD`. A cause with nothing to do
with the population. A gate that reaches `DEAD` for the wrong reason still cannot say why.

**(d) "`checks/differ.py` on that same tree computes **145 entries**." — does not reproduce.**
`len(differ.declared())` is **176** on the `git archive HEAD` tree and **176** on the real tree
(imported and run twice, one process each). `AGENTS.md` records 175 as of 2026-10-07, so the count
has moved by one and is not what the brief named. **I could not name any quantity that is 145, and
I say so rather than substituting 176 for it silently.** The comparison I can defend: on the same
tree, `differ.declared()` sees **176** and `substrate-id.py` saw **0**.

**(e) "moving the subject beside the gate **changes the digest, which invalidates
`runs/graphcmp/D/`**." — measured false, and it is the load-bearing cost claim.**
Controlled A/B, **one process, one tree, both homes**, so a concurrent edit by another agent cannot
be mistaken for the effect of the move:

| declarer at | digest | declared | present |
|---|---|---|---|
| `checks/substrate-snapshot.py` | `3aed4e4517baf8cda12b929ea14620209a5079162a9545b75fdfa32059fa7bf2` | 150 | 148 |
| `.agents/slop/quiesce/snapshot.py` | `3aed4e4517baf8cda12b929ea14620209a5079162a9545b75fdfa32059fa7bf2` | 150 | 148 |

**Identical. The move invalidates ZERO rows of `runs/graphcmp/D/`.** `inputs()` reads
`tinybendygrad/` and `COPIES`; the declarer is in neither. I would not have known this by hashing
before and after — **another agent is editing the port right now** (the live digest moved between
my first and last `--hash` runs), so a before/after pair would have produced a number whose cause
was unidentifiable. That is why the A/B is one process.

**(f) Three harness slips of mine, caught before they reached a conclusion.**
`... | tail -3; echo rc=$?` reported `nl-gate.py --selftest` as **rc=0**; `$?` was `tail`'s. The
real value is **3 (REFUSED)**, and the correct baseline is in §6. I loaded `freeze-check.py` under
the module name `freeze_check` and got a `FileNotFoundError` with nothing to do with my move. And
in the final re-verification I ran `$PY` as a **relative** `.venv/bin/python` after `cd`-ing into
each archive tree, so all four trees read **rc=127 (command not found)** and briefly looked like a
code failure. It was the shell, not the gate.

**(g) I quoted "27 assertions" for a plant I had just run.** Counted, it is **31** (`ast` over
`_expect` call sites: 31; executed `OK`/`WRONG` lines: 31). "7 cases" was likewise memory — the
plant prints **11** `PLANT` lines. **A denominator I did not measure is a number I should not have
written**, which is the same rule as (h) below, one level down.

**(h) My own baseline was time-bound, and it moved under me — `AGENTS.md`'s *"never quote one from
a job that may still be running"*, caught in the act.**
`checks/no-txt.py` read **rc=0** twice while I worked, and read **rc=1** on my last reading at
**07:20:31**. The three new `.txt` are `.agents/slop/opsbend-milestone/{check,gate,milestone}.txt`,
mtime **07:19:54–07:19:58** — another unit's directory, created *after* my final code edit
(07:19:05) and in the same minute as this report. `find` over everything this unit created returns
**0 `.txt`**. The excused set also grew under me (0 → 3 more carve-outs from `figure2` and
`txtexec`). **The lesson is not "no-txt is fine"; it is that a bare `rc=0` with no timestamp is not
a measurement of a tree other agents are writing into.**

---

## 2. The defect, measured on two trees

**`git ls-tree -r HEAD -- .agents/slop/quiesce/` = 0 paths** over **9 files** on disk. The gate that
loads its entire population from that path was, in the tree, a gate whose population did not exist.
On a `git archive HEAD` tree it hashed **0 inputs** and printed `PASS` over
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` — **the sha256 of the empty
string**, a value every empty measurement shares.

`AGENTS.md` doctrine 2 ranks this above a hang: a hang lies about its *work*; this lies about its
*existence*, and it costs nothing to run.

---

## 3. DID THE TREE ALREADY OWN THE ANSWER? — **yes. Four instruments. I added no new word.**

I checked before writing. **The empty population was already refused in four places**, and one of
them uses **the same `DEAD` (5)**:

- `checks/wallcheck.py:621,630` — *"a ledger with no rows. `report()` refuses an empty population,
  so **exit 5**"*, and its plant writes `# no rows: the population is empty and an empty population
  cannot be graded`. **This is the exact precedent, in this tree, with this token.**
- `checks/substrate.py:805` — *"REFUSED: no files given. A guard invoked with an empty population
  must not report agreement"* — called *"the FOURTEENTH instance of the project's oldest failing"*.
- `gates/gates-pop.py:580,795,888` and `gates/gate-surface.py:84,329` — empty population refused.

**So `substrate-id.py` was the FIFTH instance, and the only one that returned `PASS`.** The answer
was to honour the declaration `:55` already made, not to invent vocabulary.

---

## 4. Task 1 — the `DEAD` branch, in the file's own words

`:55` declared `DEAD` (5) *"the population is empty -- nothing was measured at all"* and **no code
path emitted it**: `ast` over every `return` found `DEAD` at exactly two sites, both inside
`judge()`, both about the **summary file**. The clause was true of the constants and false of the code.

Three surfaces, one check, so they cannot disagree:

- **`measured(here)`** — the only empty-population test in the file. Denominator is **`declared`,
  not `inputs`**: a declared-but-absent member is still a member (`snapshot.inputs()`'s `else`), so
  `inputs == 0` over `declared == 10` is a measurement of ten paths and only `declared == 0` means
  nothing was measured. Counting `inputs` would have made the two absent probes
  (`graphcmp-dbg.bend`, `graphcmp-empty.bend`) indistinguishable from a missing population.
- **`empty_population(here)`** — names the **cause**, not the symptom: whether `DECLARER` is absent
  or present-and-declares-nothing. `digest()` grew one key, `declarer`, so that is a recorded fact
  about the measurement rather than an inference by the caller.
- **`verdict_for()` takes `DEAD` FIRST, before any row comparison.** The order is the argument: with
  0 declared inputs, *"the rows disagree"*, *"the rows are absent"* and *"the run is a measurement
  of bytes that are not here"* are questions about nothing, and answering any of them prints a
  cause that is not the cause. `judge()` does not re-check — one check, one message.

**Plant case 7** builds the state on a bare directory, and carries a **control** so the guard is not
a constant that never fires: a seeded tree with its declarer present must not be `DEAD`. The whole
plant is **11 `PLANT` cases / 31 assertions**, `PLANT: OK`.

**One thing the refactor nearly broke, and did break until I caught it:** `_snapshot_mod(root)`
reads the declaration from the tree being measured, so every seeded plant tree became `DEAD`.
`_seed()` now seeds the declarer too. A seed that quietly borrowed the real one would have made
`DEAD` unreachable in the plant while remaining trivially reachable in production — a green plant
over an untested branch.

**LOC, honestly.** 532 → 680 raw, but this file's house style is that every choice is argued in
place. Code-only (docstrings and comments removed, by `ast` + `tokenize`): **296 → 338, +42.**

---

## 5. Task 2 — where the population belongs. **The brief's (a)/(b) is a false dichotomy.**

The brief framed the choice as *track `.agents/slop/quiesce/`* vs *move the subject*. Measured, **the
subject was never the problem**:

| member class | in HEAD | note |
|---|---|---|
| `tinybendygrad/` | **137 of 137 blobs** | the walk, fully tracked |
| `checks/differ.py`, `checks/devpin.py` | 1 + 1 | tracked |
| `graphcmp.py`, `graphcmp.bend`, 3 oracles | 5 | tracked |
| `bin/bend` | **0** | `.gitignore:5:/bin/bend` — a gitignored toolchain, absent by design |
| **the DECLARER** | **0 of 9** | **the only untracked thing, and it is the gate's required input** |

**Decision: option (b) — the declaration moved beside the gate, to `checks/substrate-snapshot.py`.**
`AGENTS.md`: *"a gate's required input belongs beside the gate in git."* Option (a) would track **9
files of which 1 is required**, into the tree `AGENTS.md` records as under active pruning — **85 of
the 169 named paths it could not find are under `.agents/slop/`, and 14 of the lost ones are
instruments**, which is exactly the *a path inside a swept tree is deletable while a gate still
names it* failure the rule was written from.

**What the move cost, itemised:**

1. **`ROOT = parents[3]` → `parents[1]`** in the declarer.
2. **Two sibling loaders would have crashed.** `quiesce.py:64` and `freeze-check.py:31` both loaded
   it as a sibling by `__file__` parent. I changed both, one line each, to `ROOT / "checks/
   substrate-snapshot.py"`. **This is outside the file list the brief gave me, and I am flagging it
   rather than hiding it**: leaving them would have converted a working quiet-window instrument into
   a `FileNotFoundError` crash, which is worse than the defect I was sent to fix. Both verified
   afterwards — `quiesce.py --declare` prints *"quietness population = 150 paths (identical to the
   freeze population)"*, and `freeze-check.py` loads the declarer and reads **150** declared inputs.
3. **One pre-existing lint finding entered `checks/`.** The moved file has `out if out else ...` at
   what is now `:155`, and `checks/` is where ruff runs; `.agents/slop/` was never linted. Fixed to
   `out or ...`. Net: **ruff 12 findings before, 11 after** on these two files; the remaining 11
   `E702` are pre-existing semicolons in the plant's `_steps`.
4. **Comments now stale, in files I may not touch:** `checks/differ.py:843,862` cite
   `` `quiesce/snapshot.py` `` and `.agents/slop/quiesce/REPORT.md:191,193` cite the old
   invocation. Both are prose citations, not loads. **`differ.py` is a four-consumer file other
   units are editing — I did not touch it.**
5. **Zero digest change, zero `runs/graphcmp/D/` invalidation** — §1(e). The digest there is
   byte-identical.

**And the live-vs-archive digest difference, which is *not* the move's doing:** archive
**147 declared / 144 present** vs live **150 / 148**. The archive has no `bin/` (gitignored) and no
`__pycache__`, and the live port has gained files from other agents. That is a genuinely different
substrate and the digest correctly says so.

---

## 6. Verification — three trees, verdict **tokens**, never exit codes alone

| tree | `--hash` | `--rows` | denominator |
|---|---|---|---|
| **(A)** `git archive HEAD`, unmodified — **before** | **0 / PASS** | 0 / PASS | **0 declared, 0 present** ← the false green |
| **(B)** archive + fixed gate, declarer absent — **fresh clone, pre-landing** | **5 / DEAD** | **5 / DEAD** | **0 declared, 0 present**, cause named |
| **(C)** archive + fixed gate + declarer — **post-landing** | **0 / PASS** | 0 / PASS | **147 declared / 144 present, 11.36 MB** |
| **(D)** real worktree | **0 / PASS** | 0 / PASS | **150 declared / 148 present, 11.36 MB** |

(B) prints the whole diagnosis, not a number: *"the population is EMPTY — 0 declared inputs … The
declaration, `checks/substrate-snapshot.py`, is ABSENT from this tree … A gate that reports PASS over
0 inputs is worse than no gate, because it is trusted."*

`--judge` on the real tree → **3 / REFUSED**, correctly: the live summary now carries
`substrate-start=ec5d92a5c83a` and `substrate-end=7dbea6a472b1`, they disagree, another unit is
writing to the port mid-run. **The gate is doing its real job and the tree is genuinely moving.**

**Baseline, each reading carrying the rule that produced it — `AGENTS.md`: *"NEVER QUOTE A ROW
COUNT WITHOUT THE RULE THAT PRODUCED IT, AND NEVER QUOTE ONE FROM A JOB THAT MAY STILL BE RUNNING."*
Reading taken **2026-10-08 07:20:31**, i.e. while other units are writing this tree:**

| gate | token | denominator |
|---|---|---|
| `checks/nl-gate.py` | **PASS (0)** | `gated 205  agree 205  disagree []` — **AGREE 205/205** |
| `checks/nl-gate.py --selftest` | **REFUSED (3)** | its `nl-port-post.txt` fixture is swept and unrecoverable |
| `checks/no-txt.py` | **FAIL (1)** — *was 0, twice, earlier* | **3 hard `.txt`, all in `.agents/slop/opsbend-milestone/`, all another unit's** (§1(g)). **0 of them are this unit's.** The brief's stated baseline was rc=0 and it was rc=0 when I measured it; the tree moved, not the gate. |

The other two are reproduced **exactly**, including `AGREE 205/205` and `REFUSED`. The third is
reported as the failure it now is, with the cause, rather than as the rc=0 I measured an hour
earlier — because quoting the earlier number without its timestamp is the mistake AGENTS.md names
when it says the count *"carries its own time: other units were writing the tree while it counted."*

---

## 7. What I hand back, and what I refuse

**I do not land this, and I must not.** The declarer is currently absent from **both** the tree and
the index — `checks/substrate-snapshot.py` is `??` and `git ls-files .agents/slop/quiesce/` returns
**8** entries, none of them the declarer. Until one commit lands both halves, HEAD remains in state
(B) — which now **refuses** instead of passing. That is the honest outcome of a fix I cannot commit:
**the false green is closed in the worktree, and the gate is DEAD on any checkout until the owner
lands it.**

**The landing must be one `git mv`, not a delete plus an add.** And note the index already carries
**53 files / 5,789 insertions of other agents' work** — a bare `git commit` lands all of it. The
correct command, for the owner, is:

```
git add checks/substrate-snapshot.py checks/substrate-id.py \
        .agents/slop/quiesce/quiesce.py .agents/slop/quiesce/freeze-check.py
git commit   # NOT `git add -A` -- the index holds 53 other files
```

**Priced and NOT done, needs a human owner:**
- `checks/differ.py:843,862` — two prose citations of the old path. Owned elsewhere; other units are
  editing it.
- `.agents/slop/quiesce/REPORT.md:191,193` — two prose citations of the old invocation, in a tree
  under pruning.
- The other 7 files in `.agents/slop/quiesce/` are still untracked and still sweepable.
  `quiesce.py` is a gate input that 4 things name and git does not hold. **That is the same disease
  one directory over, and I am naming it rather than quietly enlarging my scope to cure it.**

---

## 8. Files touched — 10, and 2 are outside the brief's list

| path | what |
|---|---|
| `checks/substrate-id.py` | `DEAD` branch, `measured()`, `empty_population()`, `DECLARER`, plant case 7 |
| `checks/substrate-snapshot.py` | **moved in** from `.agents/slop/quiesce/snapshot.py`; `parents[1]`; docstring |
| `.agents/slop/quiesce/snapshot.py` | **moved out** (was never in git: `git ls-tree` = 0) |
| `.agents/slop/quiesce/quiesce.py` | **1 line** — loader retargeted; *not in the brief's list; leaving it would have crashed it* |
| `.agents/slop/quiesce/freeze-check.py` | **1 line** — loader retargeted; *same* |
| `.agents/slop/quiescefix/REPORT.md` | this file |

**Nothing staged. Nothing committed.** Verified with `git status --porcelain`: the **index column is
empty for all five paths above**.