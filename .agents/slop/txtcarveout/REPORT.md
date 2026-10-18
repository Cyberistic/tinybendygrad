# `.txt` RULE AND ITS CARVE-OUT, RE-MEASURED 2026-10-18

Every figure below carries the exact command and a UTC timestamp. One unit, no `bend` needed —
this was a walk and an import, as the task predicted.

**NO FILE WAS DELETED TO MAKE A COUNT DROP.** The two plants that touched the tree were removed by
restoring them to their exact prior content, and both readings returned to the exact baseline SET,
not merely to the same count.

---

## 1. DOES THE CARVE-OUT STILL DESCRIBE ITSELF CORRECTLY? — **YES. THEY AGREE.**

`2026-10-18T19:13:41Z`, `.venv/bin/python`, `os.walk` + `endswith` (+ `os.path.exists`), never `glob`:

| | value |
|---|---|
| `len(differ.declared())` | **244** |
| `.txt` on disk under `runs/graphcmp/D` | **244** |
| on disk but NOT declared | **0** |
| declared but NOT on disk | **0** |

**THE TWO NUMBERS AGREE.** `AGENTS.md` says **175** and 175 on disk (dated 2026-10-07). **BOTH
SIDES MOVED TOGETHER, 175 → 244 (+69), and they are still equal.** That is the good news: the
declaration is not a stale hand list, it is a generator's own `declared()` and it tracks its subject.
`AGENTS.md`'s 175 is a month-old transcription of a number that is still true in *shape* and false
in *value*.

Note the denominator is 488, not 244: `no-txt.py:graphcmp_artifacts()` adds a `.tmp.` staging
spelling of every name (`differ.run()` stages then `os.replace`s, `differ.py:304`).

## 2. `checks/no-txt.py` — rc=1, AND THE 2026-10-06 FIGURES HAVE MOVED A LOT

`2026-10-18T19:13:41Z`, `.venv/bin/python checks/no-txt.py`, stderr note `ARTIFACTS-FRESH`:

| | `AGENTS.md` 2026-10-06 | measured 2026-10-18 | delta |
|---|---|---|---|
| `rc` | 1 | **1** | — |
| HARD | 550 | **183** | **−367** |
| EXCUSED | 139 | **249** | **+110** |
| OWNED | 689 | **433** | **−256** |

EXCUSED breaks down per generator, all loaded by path: **244** differ, **2** figure2 plant,
**1** rename remnant, **0** skipexit (15 declared, none on disk), **2** dup-census lanes.

**THE 183 HARD ARE NOT 183 FILES OF SLOPPINESS — THEY ARE ONE DIRECTORY:**
`.agents/slop/graphcmp-run1/D-published-backup/` holds **176 of them**. All 176 basenames ARE in
`differ.declared()`, but at a **different relative path**, so the carve-out does not reach them —
which is the design working, not failing: *"a carve-out is never the DIRECTORY, which would also
excuse residue."* `filecmp` says **13 identical / 163 differing** from `runs/graphcmp/D`, so it is
a retained earlier run, not dead weight. The other 7 are `.agents/slop/reproloop/{d01,d12,d34,
summary1..4}.txt`.

**A CARVE-OUT THAT HAS DRIFTED FROM ITS SUBJECT IS A HOLE WEARING AN EXEMPTION'S CLOTHES.**
`no-txt.py` INTERSECTS, so a declared name with no file on disk contributes nothing and prints
nothing — deleting one graphcmp artifact without touching `declared()` makes the gate one exemption
WIDER while saying nothing. **MEASURED: 259 of 488 declared names are absent today.** All 259 are
covered by dormancy (`.tmp.` staging + the on-demand skipexit lane); a BASE name going missing is
the RED, and **`gates/txt-carveout-gate.py` is now the reader for it.**

## 3. `oracles/` — **`AGENTS.md` IS STILL EXACTLY RIGHT. NOTHING TO DO.**

`2026-10-18T19:06:38Z`, `os.walk` + `endswith`: **`.rows` = 277, `.txt` = 1**, and
`oracles/rows-bd.txt` is **0 bytes** and still the only one. Untouched — the rule exempted it on
purpose, and 0 bytes is that decision.

`checks/oracle-txt-census.py` **is still there (26,294 B)** and was used, not re-implemented. It
reports `oracles/rows-bd.txt` as `ABSENT`-reach (`NAMED BY NOTHING 0 / 1`), naming 9 readers that
open a *different* `rows-bd.txt`. It classes 0 B as `prose-in-txt`, which is a classifier artefact
of an empty file having no content to read — its business, not mine.

## 4. THE PLANT — **ALL FIVE PROPERTIES HOLD. THIS IS THE ANSWER.**

`2026-10-18T19:06:58Z → 19:07:05Z`. Each reading is a SET of project-relative paths, so a change
caused by another unit is visible as a named path rather than absorbed into a number. Baseline was
taken twice, 1.5 s apart, and the two idle readings were **identical** before anything was planted.

| step | HARD | what it proves |
|---|---|---|
| BASELINE ×2 | 183 | the tree is quiescent and the count is reproducible |
| A1 owned `.txt` created | **184** | the gate DETECTS a `.txt` it owns |
| A2 removed | **183** | returned to the **exact baseline SET** (`== ` on the path list, not just the count) |
| B1 `.txt` created at a **DECLARED** path with no file on disk | **183** | **EXEMPT** — and the file appears in EXCUSED. *This is the property that makes the exemption an exemption and not a hole.* |
| B2 `oracles/rows-bd.txt` +1 byte | **184** | the `empty_remnants()` size guard is **LIVE**, not a blanket |
| B3 truncated back to 0 B | **183** | exact baseline SET again |

So: **an instrument whose answer moves when the WORLD moves is correct, and one that moves when
the INSTRUMENT moves is not.** A1/A2 and B2/B3 are the same 183↔184 pair reached from both sides,
which is the whole point — the number is a function of the tree and of nothing else.

**EXCUSED read 249 at 19:06:25 and 250 at 19:06:59 with HARD unmoved.** That is not noise and was
not absorbed: two `differ` runs were in flight (pids 69982 `differ.py repro`, 92407 `differ.py run`)
and the 250th excused file was `.tmp.D1-graph-commute.txt` — **the staging name, covered by
construction**. That is the carve-out's third clause catching a live race it was written for, and
it is why HARD stayed 183 throughout.

## 5. WHAT `AGENTS.md` SHOULD CARRY — **DELETE 9 · POINTER 5 · KEEP 3. RE-TRANSCRIBED 0.**

A re-transcribed number is a new transcription that will be wrong again. Every moving figure
becomes an instrument or a pointer.

| # | `AGENTS.md`'s claim | verdict | action |
|---|---|---|---|
| a | *"EXITS 1 … WITH **550 HARD AND 139 EXCUSED (689 OWNED)**"* | rc right, **all 3 counts stale** | **DELETE the 3 counts.** The exit is the durable part; the counts are printed by `checks/no-txt.py` on every run. |
| b | *"it read **830** before … **258** … **258** IS THE EXACT DELTA BOTH WAYS"* | **not a current count — a dated migration record** | **KEEP, labelled as completed history.** It does not rot, and the delta-both-ways agreement is the valuable part. |
| c | *"`oracles/` holds **277** `.rows` AND **ONE** `.txt`"* | **re-measured TRUE today** | **DELETE the 2 counts, POINTER to `checks/oracle-txt-census.py`.** KEEP the durable claim: *the one `.txt` is 0 bytes and its extension was a DECISION by the renamer, not an oversight.* |
| d | *"the **175** `.txt` names — `len(differ.declared())` = **175**, and 175 on disk"* | **stale value, still-true shape** (+69) | **DELETE both counts.** Replace with: *the declared set and the files on disk are the same set; `gates/txt-carveout-gate.py` charges any drift.* That converts a transcription into an instrument. |
| e | *"carves out `differ.declared()` … **and nothing else**"* | **FALSE — there are FIVE generators** | **DELETE "and nothing else", POINTER to `checks/no-txt.py:carveouts()`.** The most consequential correction here: it is a claim about the carve-out's SHAPE, not a count. |
| f | *"the HARD count **MOVES as units write**"* | **CONFIRMED** | **KEEP.** Re-measured: EXCUSED moved 249→250 under a live `differ run` while HARD held. |
| g | *"**NO `.txt` FILES, EVER.**"* | the rule is good | **KEEP.** It now has a plant. |
| h | *"A CARVE-OUT MUST BE A GENERATOR'S DECLARATION LOADED BY PATH"* | **HELD** | **KEEP.** Proved by B1: a declared name with no file on disk was still exempt. |

Two more that are not `.txt` counts but that this unit's measurement contradicts:
`gates/gate-surface.py --report` finds `checks/no-txt.py` by walk (`gates-pop.discover()`), so
`AGENTS.md`'s claim that it "names gates by hand" is right about *this file* and not about
`gate-surface`; and `no-txt.py`'s RED shows `UNTAKEN` in that census because the tree is genuinely
red, which is why the plant had to be measured by hand.

## 6. `ruff check`, `git fsck`, `git show --stat`

- `ruff check checks/no-txt.py gates/txt-carveout-gate.py` → **4 errors, all pre-existing**: docstring
  table lines 26–28 (`E501`) and unused `cache` at 161 (`F841`). **HEAD's copy, run under the same
  config, gives the same 4 at lines 26–28 and 160** — line 160→161 is my one added `import`. **My diff
  adds ZERO new findings.** `gates/txt-carveout-gate.py` is clean.
- `git show --stat HEAD` → **2 files, 146 insertions, 1 deletion**: `M checks/no-txt.py`,
  `A gates/txt-carveout-gate.py`. **No sweep.**
- `git fsck --no-progress` → names **exactly the same 3** pre-existing malformed trees
  (`d57bc484`, `d83cf685`, `3a60f33f`, all `duplicateEntries`), **none reachable from HEAD**.
  **No fourth.**
- Committed through `GIT_INDEX_FILE=.git/agent-index-txtcarveout` (chosen once, same string in
  `read-tree`, `add` and `commit`). The **default index was ARMED** before starting —
  `checks/index-arm-gate.py` REFUSED, **172 paths** a bare commit would have acted on.

## 7. FOUND BUT NOT DONE

- **176 hard `.txt` in `.agents/slop/graphcmp-run1/D-published-backup/`.** Deliberately NOT deleted:
  they are a retained earlier corpus, 163 of 176 differ from the live copy, and the carve-out's
  refusal to reach them is the mechanism working. Whether they should be renamed `.rows` is a call
  for whoever owns that run.
- **15 skipexit names declared, 0 on disk.** Dormancy by construction; `CONDITIONAL` covers them.
  If that lane is retired rather than on-demand, the declaration should go with it — flagged, not
  changed.
- **`checks/txt-owners.py` did not finish** — timed out past 120 s. It is the second opinion on the
  exemption set and it remains **UNMEASURED** by this unit. Run it with a larger budget.
- **The rule this gate charges is now enforced, but nothing enforces that `AGENTS.md`'s prose matches
  it.** A prose-vs-instrument gate is a different instrument and out of this grant; §5 is the hand-off.