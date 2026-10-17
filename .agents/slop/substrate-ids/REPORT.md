# TWO SUBSTRATE IDS FOR ONE TREE — what each hashes, which is authoritative, and whether a run can tell

Read 2026-10-17 · all numbers below are ONE reading of the live tree, taken by
`checks/substrate-current.py --report`, and re-taken by an independent throwaway script
(`/private/…/T/opencode/subid/isolate.py`) which agreed on every id. The tree is moving under other
units; the ids carry a timestamp because of it and the DELTAS below do not.

## 1. WHAT EACH ID HASHES, SIDE BY SIDE

| | writer `differ.substrate_digest()` | reader `substrate-id.py` `digest()` |
|---|---|---|
| lane | `checks/differ.py:890` | `checks/substrate-id.py:168` |
| members | **151** | **153** |
| port walk | `(ROOT/"tinybendygrad").rglob("*")`, `is_file()`, no `__pycache__` | the same walk, asked from `checks/substrate-snapshot.py:101` |
| named inputs | `checks/differ.py`, `checks/devpin.py`, `bin/bend`, 5 × `.agents/slop/graphcmp*` (**8**, a hand list) | `checks/substrate-snapshot.py:76` `COPIES` — the same 8 plus `graphcmp-dbg.bend` and `graphcmp-empty.bend`, and `bin` as a **directory** (**10**) |
| sort key | `sorted(substrate_entries())` — **by relpath string** | `sorted(present + absent)` — **by `pathlib.Path`**, i.e. component-wise |
| per-member fold | `sha256(bytes).hexdigest()` as an ASCII string, NUL-terminated | the **raw bytes**, no trailing NUL |
| absent member | the string `ABSENT` | the bytes `ABSENT` |
| id on this tree | `be6874cab3df501b9732e039fb220772d00c5900a0867be75b705e4e06bf00a0` | `a0e34b14518911f74139abf37fbefa72a437cddb9ab0f7498299374f8f75f332` |

**THE DELTA IS EXACTLY TWO PATHS, AND IT IS ONE-DIRECTIONAL.**

```
only in the writer:  []
only in the reader:  ['.agents/slop/graphcmp-dbg.bend', '.agents/slop/graphcmp-empty.bend']
```

`bin/` holds exactly one file today (`bin/bend`, 2097 B), so `COPIES`'s directory walk and
`SUBSTRATE_INPUTS`'s single file are the same member **by accident** — nothing keeps them so.

## 2. WHICH OF THE THREE ANSWERS — **(2), and neither instrument is right about the other**

Not (1): they are the same question. `differ`'s own docstring (`:866-872`) and `substrate-id`'s
(`:24-28`) both ask "which bytes produced this run" and both answer it with one row pair written
under the same two keys. Not (3): they do not hash the same bytes. So (2) — same question, and
**`differ.substrate_digest()` is the wrong one**, because its population is a hand list that misses
two declared members:

```
differ alg over the WRITER's 151 members  = be6874cab3df   ← differ.substrate_digest()
reader alg over the WRITER's 151 members  = f4f3fca58818   ← isolates the encoding
differ alg over the READER's 153 members  = 185d3bd9a047
reader alg over the READER's 153 members  = a0e34b145189   ← substrate-id.digest()
```

Three **independent** causes, each measured by holding the other two still:

1. **membership** — 151 vs 153; `185d3bd9` vs `be6874ca` under one algorithm.
2. **aggregation** — `f4f3fca5` vs `be6874ca` over the *same 151 members*: the reader folds raw
   bytes where the writer folds a per-file sha256 hex string. **So "make the ids match" by
   touching a hash is the wrong move**: even over an identical population they still differ.
3. **order** — 5 of 151 positions, all at one prefix. The writer sorts
   `tinybendygrad/LAWS.bend` before `tinybendygrad/LAWS/PROOF-ALL.bend`; the reader sorts the
   `LAWS/` directory first, because a `Path` compares component-wise and `'LAWS' < 'LAWS.bend'`.
   **A set-difference reports this as nothing at all**, which is why `--report` prints order
   separately.

**THE RUN'S OWN RECORD USES THE WRITER.** `runs/graphcmp/D/D0-run-summary.txt` rows 23-24:

```
substrate-start=5d3f31197e88124246dd819fa1b904439ef255805c36bf30656145171d95ffa3
substrate-end=5d3f31197e88124246dd819fa1b904439ef255805c36bf30656145171d95ffa3
```

and `census()` (by content walk of `checks/` + `gates/`) finds **2 emitters** of these two row keys:

```
EMITS them into the summary, in differ's encoding -- the one D/ is in   checks/differ.py
reads the two rows                                                   checks/substrate-current.py
EMITS ITS OWN ENCODING to stdout -- nothing records these              checks/substrate-id.py
```

`substrate-id.py --rows` writes the same two keys to **stdout** in its own encoding. That is where
`86ce8d93` came from, no lane records it, and it is why the two ids read as the same thing.

## 3. CAN A RUN TELL WHETHER IT IS STILL DESCRIBING ITS TREE? — **it could not; now it can**

`checks/substrate-id.py --judge` compares a `differ`-**encoded** row against a
`substrate-id`-**encoded** live reading. Different populations, different order, different
aggregation — so it answers `REFUSED` on a tree that has not moved a byte, and **can never answer
PASS**, because the only writer of those rows is `differ.py:718`. Plant step, on a scratch tree
with nothing moved:

```
PLANT unmoved    0: this tree IS the substrate the run was taken on -- 12 members, f9c9f4a05d93, recomputed
REFUSED, NOT A VERDICT: the run recorded f9c9f4a05d93 and this tree hashes e8dd5f245e19 …
PLANT old-reader 3: one writer, two encodings, nothing moved
```

**New: `checks/substrate-current.py`.** It asks the **writer** for the live value
(`differ.substrate_digest()`, loaded by path, never re-typed), so the comparison is
apples-to-apples and can go green. It does not re-pin anything, does not touch a recorded figure,
and hashes no `bend`.

```
$ .venv/bin/python checks/substrate-current.py            # rc=1
VERDICT: FAIL: substrate-end=5d3f31197e88 but this tree reads be6874cab3df through the same
function (checks/differ.py) -- THE TREE MOVED SINCE THE RUN, so the pins in D/ are claims about
bytes that are not here. Re-run, or snapshot with checks/substrate-snapshot.py
```

**`FAIL`, not `REFUSED`.** Every precondition is present — summary, both rows, 151 readable
members — and the question has a decidable answer, which is no. The tree has already ruled the
other way: `differ.py:1043` folds these same two rows into `unhealthy()` as a FAIL and
`gates/retention-check.py` clause IV consumes that, so `REFUSED` here would contradict the reader
of the same rows.

**NON-VACUITY ON THE REAL TREE, not on a fixture.** The real 151 members were copied (the
population is discovered by calling the writer, never listed) into a scratch tree; the gate reads
`PASS`/rc=0 there at the current bytes and `FAIL`/rc=1 after one byte in one member. The digest was
also byte-identical over the real tree and the frozen copy, re-measuring `differ`'s mtime-independence
claim on 151 members.

## 4. THE PLANT, AND PROOF IT GOES RED

`.venv/bin/python checks/substrate-current.py --plant` → **rc=0, 19 of 19**. Real functions, loaded
from real copies in a scratch tree, so every assertion is about the instruments and not about
constants in this file.

**IT WENT RED SIX TIMES WHILE BEING WRITTEN, ON SIX REAL DEFECTS, four of them in the plant:**

| the red assertion | the defect it found |
|---|---|
| `the planted populations are equal` | **my assertion was wrong, the tree was right** — the scratch reproduces the real 2-member delta, so the plant was better than the claim |
| `the census … counts it as neither` (×2) | the census matched **itself** as an emitter, once through `WRITE_MARK`'s own literal and once through this file's docstring prose |
| `the census … counts it as neither` | my expected lane order was not the walk's sorted order |
| `plant sensitivity census — … is NOT caught` | the harness took one tree's reading from the **unpatched** module, and captured its "undo" bytes off an already-moved member, so it saw a moved tree where it meant an unmoved one |
| `rows that disagree with EACH OTHER are FAIL` | the case was passing by accident, depending on where the census had left the tree |

**SENSITIVITY CENSUS — can a source edit slip past it? Measured, printed on every plant run:**

```
MUTATION 2 of 3 edits to the comparison are caught by --plant; NOT caught:
delete the empty-population DEAD branch
```

The three edits are applied to **this file's own source** and `verdict()` is re-run from the
patched module. The third is asserted **NOT caught**, and that is the honest record rather than a
lax expectation: that branch is unreachable from any tree this gate can load, because the writer's
population contains `checks/differ.py` itself. It is kept (it guards `substrate_entries()` being
edited to return nothing) and its unreachability is printed. If somebody makes it reachable the
plant goes red and asks them to move the expectation — the only direction a falsifiable record
should move.

**THE CENSUS ITSELF WAS WRONG THREE TIMES BEFORE IT WAS RIGHT**, each time in the direction of
over-reporting: it read one tree's verdict from the unpatched module; it compared a marker that
occurred **twice** and so patched the `MUTATIONS` table instead of `verdict()`; and it ran at the
end of `plant()`, after the summary had been overwritten and the declarer deleted, which made every
reading `DEAD` and reported **3 of 3** caught on a broken fixture. `_patched()` now refuses a
marker that is not unique, and the census runs where its two readings mean something.

## 5. FOUND AND NOT DONE

- **NOT WIRED IN.** Nothing calls `substrate-current.py` yet. `gates/retention-check.py`,
  `gates/gatekit.py` and `checks/differ.py` are other units'. The one line a wiring unit needs is
  `checks/substrate-current.py --check` beside clause IV's `differ.unhealthy()`, whose
  `substrate_bad(got)` covers the *two rows agreeing with each other* and **not** the rows against
  the live tree.
- **`differ.SUBSTRATE_INPUTS` IS A HAND LIST AND THAT IS THE BUG TO FIX THERE.** Two declared
  members are missing. The repair is to ask `checks/substrate-snapshot.py` (the declarer already in
  git, per `substrate-id.py:50-55`) rather than to append two literals — appending them re-creates
  `gates/gates-pop.py`'s `HOMES` defect and leaves the next added member invisible again. **This is
  a change to `differ.py`, outside this unit's grant.**
- **`bin/` vs `bin/bend` is equal by accident** (one file in the directory today). Same repair.
- **THE RESIDUAL THE UNIT COULD NOT CLOSE IS PARTLY CLOSED, NOT CLOSED.** A run now says whether it
  is still describing its tree — decisively, in the writer's own encoding. It still cannot say
  **which** member moved: `RESIDUAL: 0 of 151 members are recorded per-path (24 key=value rows, 2 of
  them 64-hex)`. Closing that means 151 rows in the summary, which
  `substrate-id.py:36-39` rejects on four-parser grounds — or a `MANIFEST.tsv` per run, which is
  what `substrate-snapshot.py build` already writes for a *freeze* and nothing writes for a *run*.
- **THE TREE HAS MOVED SINCE THE RECORDED RUN**, `5d3f3119` → `be6874ca`, live and FAIL today. Not
  a finding; it is the gate doing its job. No re-run was attempted: `differ.py run` is 172 s and a
  third pass re-arms `gates/retention-check.py`'s `II LEFTOVER` clause.
- **`checks/substrate-id.py` was changed by one line of surface**: `digest(root, members=None)`, so
  a caller can hash an explicit member set **in that file's own encoding** instead of re-typing the
  aggregation. `--hash` returns the same `a0e34b145189` before and after, and its `--plant` is still
  0. Without it, `--report`'s `over_writer` column would have been a second copy of an algorithm.
- **`ruff`: clean on the new file; `checks/substrate-id.py`'s 11 `semicolon` findings are identical
  on HEAD** (verified against `git show HEAD:checks/substrate-id.py`).