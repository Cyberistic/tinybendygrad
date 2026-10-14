# msgdiff — the missing guard: a commit MESSAGE against its own DIFF

**Gate:** `gates/msgdiff-gate.py` · **evidence:** this directory (`run.py` regenerates it) ·
**measured:** 2026-10-07, read-only on the live tree.

## WHAT IT CANNOT SEE (first and loudest)

A gate can only resolve a claim that names something a diff can answer. **Three of tonight's four
bad claims named nothing a diff can answer, and this gate does NOT catch them:**

| claim | why the message gate cannot see it | where it lives |
|---|---|---|
| the `41%` | a number with no denominator in the tree is not a claim about the tree | the orchestrator's own prompt — **in no owned surface at all** |
| a dead pid (`2368` when it was `30543`) | a pid is a **live measurement** and a commit message is **immutable**; every pid claim becomes false on its own | `AGENTS.md` prose, and commit `601e7929c`/`2b4cc9e48` |
| an invented config key (`snapshot.auto-track="all()"`, `fsmonitor`) | "in no file in this repo" is a claim about the **filesystem**, not about the diff | `AGENTS.md` prose |

`jjreset`'s `git-massdelete-gate.py` states the matching residual about itself: *it cannot see a
wrong message*. **This gate is the complement and cannot see a message that names nothing.** Neither
is a substitute for the other. A line in this report with no named instrument behind it is a line
not to trust.

## 1. DESIGN, AND WHY IT IS A SEPARATE GATE

It is a gate on `gates/gatekit.py`'s five exits and **no sixth**: `PASS, FAIL, REFUSED, SKIP, DEAD
= 0,1,3,4,5`. It imports those constants from `gatekit` rather than redeclaring them, and it returns
`FAIL` only from its own `--plant`.

**It is NOT an extension of `git-massdelete-gate.py`.** That gate's SUBJECT is the DIFF (does the
commit delete more than the tree's measured churn, 500 files / 900000 lines) and its population is
`D` entries. This gate's SUBJECT is the MESSAGE and its population is claim sentences. They share
`_git` (`--no-optional-locks`, so neither writes the index it reads) and the exit constants, and
**nothing else**. Folding them together would give one commit two subjects and one verdict — the
error `gates/gendirs.py` exists to name: *a gate that cannot say which of its subjects failed is a
gate whose refusal nobody can act on*. The refusal wording is matched to `jjreset`'s on purpose:
`REFUSED, NOT A VERDICT: <label> ... ` plus a re-run hint, because two deletion/message guards in
one tree must not speak two vocabularies.

`REFUSED` (3) and **not `FAIL`**: the gate does not know the message is wrong; it knows only that
**this diff** does not witness it. A rename, a squashed push, or a sibling commit can make an honest
message look unwitnessed by one diff. `MESSAGE_DIFF_ACK="<reason>"` (or `--ack`) records the
explanation and passes.

## 2. PROVEN ON THE REAL CASE (not a fixture)

`00b101574`'s message says, in the `prefixtxt` section:

> **`Deleted the superseded oracles259/plants.py after proving oracletxt/plant.py covers it and the
> census output is byte-identical across the deletion.`**

`git show --numstat 00b101574` touches **four** files — `.agents/slop/censusred/run.err`,
`.agents/slop/censusred/run.out`, `gates/tn_sin_log2_exp2_rsqrt.bend`, `tinybendygrad/tensor.bend`
— and `git diff-tree --diff-filter=D 00b101574` is **empty**. `.agents/slop/oracles259/plants.py`
is **present in that commit's tree** at blob `e6e31707`, the same blob it held in the parent
(`aa457fd25`). The message asserts a deletion the diff does not contain.

```
.venv/bin/python gates/msgdiff-gate.py check 00b101574    # -> rc=3, naming the sentence above
```

**The exact sentence it refuses is the block-quote above.** That is the only refusal in the whole
range (below).

## 3. WHAT IS RESOLVABLE, AND WHAT IS NOT

A message names files, counts, and pids. They are not equally resolvable.

| shape | resolvable? | why |
|---|---|---|
| **file path + delete verb** (`Deleted X`) | **YES** — the diff's `D` set and the commit's tree | this catches `oracles259/plants.py`: present, not deleted |
| **`N files changed\|deleted\|added\|removed\|touched`** | **YES** — the noun is FILES and it is tied to the diff | the message says what it counts |
| **`five units`, `19 sites`, `53 of 77 arms`** | **NO** — unfalsifiable | the diff holds no denominator for "units"; `00b101574`'s "five units" counts UNITS, and the 4-file diff is **not** a contradiction |
| **a pid** | **NO** — counted, never marked | a pid is a claim that *will* be false; refusing it refuses every honest message that cites a process |
| **a percentage with no artefact** | **NO** | not a claim about the tree |
| **a config key "in no file"** | **NO** | a filesystem claim, not a diff claim |
| **a definition inside a file** (`deleted dec_limit`) | **NO** | not a repo path |
| **a claim the message is DISCUSSING** | **NO** — demoted by a meta-marker | a message that REPORTS a defect (`... was deleted IS FALSE`) must not be refused for naming it |

**On PIDs the gate counts; it cannot mark.** Marking would refuse `601e7929c` and `2b4cc9e48` —
both honest — for citing a process. The count is *reported* (`pids=N` on every `check`), so a reader
is told a pid claim exists and is unjudged, which is the most a diff-based gate may honestly do.

Which claims are checked: **deletion assertions** (forward object only, see below) and **explicit
file counts**. Everything else is **counted and passed**.

## 4. THE PROSE LAYER IS A DIFFERENT POPULATION — DO NOT FOLD IT IN

`citeresolve` measured **2 448** committed prose `<path>:<N>` claims (165 unresolved, 352 resolving
only weakly, **1 777 never positively checked**) across `REPORT.md`s, `AGENTS.md`, `TOOLS.md` and
the briefs. **A message gate sees none of them.** They are not commit messages and there is no diff
per report; the population is tracked prose files and the resolution is against the tree at a
revision, not against a diff. That is the `gendirs` lesson, not the second-copy one: **two
populations need two instruments, and folding them into one gate would make one verdict stand for
two questions.**

What the prose instrument **would be** (reported, NOT built):

- population by **discovery**: `git ls-files` of the tracked prose surfaces (`*.md`), not a hand list;
- for each `<path>:<N>` citation, resolve `<path>` in the tree at HEAD and assert the file exists;
- for `:N`, assert the cited line is the thing the prose names — `citeresolve` already does the
  triage (`DRIFT`/`DEAD SUBJECT`/`NEVER EXISTED`/`NARRATIVE`), so this is a **re-pointing and a
  positive-check lane over `citeresolve`'s own output**, not a new scanner;
- for live facts (**pids**, **config keys**), the resolution needs `ps` / a config reader — a
  *runtime* instrument, not a tree instrument. These must be either excluded loudly or given their
  own lane; they are **never** the message gate's job.

## 5. PLANT, AND HOW MUCH OF TONIGHT IT PASSES

```
.venv/bin/python gates/msgdiff-gate.py check 00b101574        # REFUSED, NOT A VERDICT  rc=3
.venv/bin/python gates/msgdiff-gate.py --plant                # 6 states OK             rc=0
.venv/bin/python gates/msgdiff-gate.py range --since=2026-10-06T12:00 HEAD
                                                              # 147 commits -- 146 PASS, 1 REFUSED
```

`--plant` builds **six states in a scratch repo, never this one**, distinguishable in token and
exit code: (A) an honest message → `PASS` 0; (B) a message that says it deleted `keep.py` while
`keep.py` is present → `REFUSED` 3; (C) a message naming only a pid and `41%` → `PASS` 0
(uncheckable); (D) the state-B message with `--ack` → `PASS` 0; (E) `changed 9 files` over a 1-file
diff → `REFUSED` 3; (F) `changed 1 file` → `PASS` 0.

**Against tonight's real history the gate fires on exactly one commit and passes the rest.**
`verdicts.rows` records the replay:

```
.venv/bin/python .agents/slop/msgdiff/run.py
```

| sha | rc | what it is |
|---|---|---|
| `00b101574` | **3 REFUSED** | the real defect |
| `169ee6ac8` | 0 PASS | honest meta-report: says the predecessor's deletion claim is FALSE |
| `601e7929c` | 0 PASS | uncheckable: dead pid `2368`, config keys in no file |
| `2b4cc9e48` | 0 PASS | uncheckable: pid `2368`/`30543`, the mass-delete guard's own message |
| `3c4ceeea3` | 0 PASS | honest: **moved** `oracles259/` residue and says "MOVED, NOT DELETED" |
| `9b55d16a4` | 0 PASS | honest: removed the strays, including `elf.bend.mut` (1 claim checked, witnessed) |

**A guard that refuses the whole history is not a guard, it is a policy.** This one passes
146 of 147 commits unchanged and refuses the one that lies.

### The 11 honest messages it refused before it was tightened

The first draft refused **12 of 145**. Eleven were honest, and each taught the grammar something —
recorded because *a guard proven only on synthetic defects has not been proven against honest
prose*:

- `deleting is the file's own prescribed cure` → a gerund whose object is a clause, not a path;
- `deleted \`dec_limit\`` → a **definition**, not a repo path;
- `\`residue.py\` \`commit-or-drop\` live 0 -> DELETE` → the verb is a **state name**;
- `"one of the 99 deleted"` / `"DELETED FIXTURE"` → **quoted** text;
- `ARE REMOVED — \`elf.bend.mut\`` → the path had **two extensions** and was truncated to `elf.bend`;
- `DELETED, GUARDED BY \`delete.py\`` → the verb's object is governed by a **relative clause**;
- `\`dev\` DELETED` → the object is a **symbol**, and the only path was before the verb;
- `DROPPED THE TWO RELOCATED` → the object is a **noun phrase**;
- `... 4 cstyle cites are deleted subjects` → the verb is a **participle**;
- `deleting them makes the repro ...` → a **pronoun** object;
- `\`delete.py\`` → the verb regex matched **`delete` inside a filename**.

The fixes are all in one direction: **forward object only, within 40 chars, with no stop-word or
punctuation between verb and path, and a path must not be a filename the verb sits inside.** A
missed claim is a PASS; a blamed innocent is a refused honest message.

## 6. WHAT THE GATE CANNOT SEE (restated)

- **a claim that names nothing checkable** — a percentage, a dead pid, an invented config key;
- **a count whose noun the diff cannot denominate** — "five units", "19 sites", "53 of 77 arms";
- **a wrong claim inside a tracked prose file** — that is the prose instrument's population;
- **a message whose object sits before the verb** (`X was deleted`) — deliberately not checked, to
  avoid refusing honest passive prose;
- **an untracked-file deletion** (`11 FILES, .gitignore-MATCHED ONLY` in `34b8c493decf`) — the diff
  shows nothing, so the claim is uncheckable and passed.
