# pinsbytes -- WHICH BYTES SHOULD THE OWNER COMMIT FOR THE 3 ABSENT-FROM-HEAD PINS?

**MEASURED 2026-10-17T05:25:28Z .. 05:28:21Z. NOTHING WAS CHANGED. NO GIT WRITE RAN.**
Local `HEAD` = `2473958642727eeb0e5ed0b86dbe8eadb0a823d5` (**DETACHED**), `origin/master` = `473d7ce988d0f0741e26bccf5e8c1495d864be4c`.
Both re-read at the end of the window and **unchanged**, so every number below held for the whole run.

---

## I AM NOT CHOOSING. HERE ARE THE FACTS.

You asked for the facts so **you** can choose. I am not picking a winner, and where the
evidence points I say so as *evidence*, not as a recommendation. Three of the six
candidate cells would each be defensible; the choice is a **policy** call about what a
committed artifact in this tree means, and that is yours.

The single most important fact, stated once and not argued:

> **BOTH SIDES ARE HONEST SNAPSHOTS. NEITHER IS CORRUPT. They differ because THE TREE MOVED
> UNDER THEM, and the movement is dated to the minute.**

Origin's bytes were **correct when committed** and have since **drifted**. Disk's bytes are
a **later re-run** whose line citations match the tree **right now**. There is no third
possibility here and no "corrupt disk copy" reading available on the evidence.

---

## 1. PRESENCE MATRIX (task 1)

Measured with `git ls-tree <rev> -- <path>` (not `rev-parse`, which echoes its argument),
`ls -la`, and `git ls-files -s`.

| path | in `origin/master` | in local `HEAD` | on disk | index blob |
|---|---|---|---|---|
| `gates/oracleblind.rows` | **YES** `e606d484fc560b25` | **NO** | **YES** 35,858 B / 99 lines | `e69de29bb2d1d643` (**EMPTY**) |
| `gates/assertlit.rows` | **YES** `2a1e8d6198776652` | **NO** | **YES** 5,646 B / 95 lines | `e69de29bb2d1d643` (**EMPTY**) |
| `gates/falseclaim.rows` | **YES** `cd1d641d677bc8bc` | **NO** | **YES** 17,457 B / 122 lines | `e69de29bb2d1d643` (**EMPTY**) |

`GIT_INDEX_FILE` was unset for every read (`env -u GIT_INDEX_FILE`), so these are default-index
reads and not another unit's private index.

### The index state, stated exactly

- `git ls-files -s` reads mode `100644`, **stage `0`**, oid `e69de29b...` for all three.
- `git status --porcelain=v2` reads **`1 .A N...`** with **both** oids `0000...`.
- `git diff --cached --stat -- <the three paths>` prints **NOTHING**.
- `git diff --stat` (index vs worktree) prints **`316 insertions(+)`** across the three.

**What I claim, and what I do not.** I claim the disk bytes are **not staged**: the staged
diff names nothing and the worktree diff names all 316 lines. I **do not** claim what a bare
`git commit` would do to an intent-to-add entry, because answering that requires a commit and
this unit runs no git writes. `AGENTS.md` records its own measurement that a bare commit over
intent-to-add *commits the previous content*, which for a path absent from `HEAD` would leave
it absent. **Either way the 316 lines are not in the index, and the content exists in exactly
two places: `origin/master` and the worktree.** That is the fact the choice turns on.

Note the census in `AGENTS.md` that `git ls-files --others --exclude-standard` names **none**
of the three -- because they are *in* the index, so they are not "others". A sweep trusting
that question alone would report this tree as clean.

---

## 2. DISK vs ORIGIN -- WHAT DIFFERS (task 2)

All three differ. None is a byte-copy of the other.

### `gates/oracleblind.rows` -- 5 of 99 rows; the row SET is identical

The set of oracles is the **same 98 on both sides** (verified by sorting column 1 and diffing:
empty). So no oracle is gained or lost, and no reader can fall off the end of the table.

Five rows differ, in two distinct kinds:

**(a) 2 rows move a MEASUREMENT tuple (`verdict`/`rows`/`base_sha`/`sites`):**

| oracle | origin | disk |
|---|---|---|
| `gates/op_graph_census-oracle.py` | `base_sha=c79c3c954284` | `base_sha=b6823b002d4d` |
| `gates/rand_census-oracle.py` | `sites=64` | `sites=62` |

`base_sha` is `hashlib.sha256(a["out"].encode()).hexdigest()[:12]` (`oracleblind-census.py:882`)
-- the sha of the oracle's own **emitted output**. So `op_graph_census`'s output bytes really
did change between the two runs. `rand_census` lost 2 reachable sites. **Neither is a `tn_*`
oracle**, so `tnvalue`'s own claim that *0 of the changed rows are `tn_*`* **reproduces exactly**.

**(b) 3 rows move a CITATION only:**

| oracle | origin | disk | why |
|---|---|---|---|
| `gates/ops_python_census-oracle.py` | `CTOR_PARAMS:190` | `CTOR_PARAMS:199` | the oracle grew 9 lines |
| `gates/crp_graph_census-oracle.py` | `PRI_OFF:81` (and `CRASH rc=1`) | `PRI_OFF:82` (`CRASH rc=3`) | the oracle grew 1 line |
| `gates/op_graph_census-oracle.py` | `declared_by` lacks it | `declared_by` gains `gates/assertlit-census.py:literal` | a new gate now names the oracle |

**CROSS-CHECK THAT HOLDS:** `.agents/slop/tnvalue/REPORT.md:18` reads
`new sha256 0cc47cebe9d96def vs the committed 614ea700469eeea9` and says *"Exactly **2** of
98 rows changed `(verdict, rows, base_sha, sites)`"*. I measured **2** tuple-changed rows.
**Disk's bytes are exactly what that later run wrote.** That is an independent witness, not my
inference.

### `gates/assertlit.rows` -- header + 2 of 86 rows

The denominator line moves **UP**:

```
origin: # DENOMINATOR: 78 ORACLE · 98 GATE · 160 PINS
disk:   # DENOMINATOR: 78 ORACLE · 99 GATE · 162 PINS
```

Gates are being **added** in this repo. A run that sees **one more gate and two more pins**
saw a **later tree**. Two rows move `UNSOURCED -> DERIVED`:

- `gates/op_graph_census-oracle.py` : `UNSOURCED 1 32 1 29` -> `DERIVED 0 33 0 29`
- `gates/rand_census-oracle.py` : `UNSOURCED 1 17 1 19` -> `DERIVED 0 17 0 19`

Tally: origin `53 UNSOURCED / 21 DERIVED`, disk `51 UNSOURCED / 23 DERIVED`. Row count 86 both sides.

**The two rows that moved in `assertlit` are the SAME two rows whose `base_sha`/`sites` moved in
`oracleblind`.** Cross-instrument coherence, not coincidence.

### `gates/falseclaim.rows` -- 1 of 122 rows, and it is a pure citation

The **tally is identical on both sides**: `122` claims, `1 AGREE`, `0 FALSE`, `121 UNASKABLE`.
Not one verdict differs. The single difference is a line number:

```
origin: kind=CLAIM file=checks/runs-artifacts.py line=889 form=RETURNS claim="" call=resolve()
disk:   kind=CLAIM file=checks/runs-artifacts.py line=899 form=RETURNS claim="" call=resolve()
```

---

## 3. WHICH SIDE IS THE LATER RUN -- THE TIMELINE (task 4)

This is the part I can prove rather than infer, because **origin's own history says when each
citation was true.**

### `falseclaim.rows` is pinned to the minute

| when (local, +0300) | what |
|---|---|
| 2026-10-17 **02:03:18** | `40b16ac85` commits `assertlit.rows` (origin) |
| 2026-10-17 **03:20:55** | `012583722` commits `falseclaim.rows` **citing line 889**. `runs-artifacts.py` is **1096** lines, and line 889 **is** the `resolve()` prose. **Origin's row was correct.** |
| 2026-10-17 **03:21:39** | `48bbd5700` grows `runs-artifacts.py` **1096 -> 1106 lines**. Line 889 is now something else; the `resolve()` prose is at **899**. |
| 2026-10-17 **03:21:54** | disk's `falseclaim.rows` is written -- **15 seconds later** -- citing **899**. |

Origin's tip is `473d7ce` (**06:51:22**), which still carries the 889 version. **It was never
re-run after `48bbd5700`.** So origin's citation is not wrong, it is **stale by one commit**,
and disk's is a re-run 15 seconds after that commit.

### `oracleblind.rows`: origin's citations were true, disk's are true now

At `b54553071` (the commit that added `oracleblind.rows`, 2026-10-16 20:42:28), and at each of
its six ancestors, `ops_python_census-oracle.py` had `CTOR_PARAMS` at **189** and
`crp_graph_census-oracle.py` had `PRI_OFF` at **81** -- exactly origin's citations. **Today both
files are identical in `origin/master`, local `HEAD`, and on disk**, and read **198/199** and
**82**. So origin's rows were **correct against the tree that existed**, and disk's are
**correct against the tree that exists**.

### `assertlit.rows`: same shape

Origin recorded **98 gates**; disk recorded **99**. The repo gained gates between the two runs.
Disk's disk-mtime (`03:20:20`) is later than origin's commit (`02:03:18`) by **1 h 17 m**.

### Summary of the direction

| file | origin commit | disk mtime | origin's citations true at commit time? | disk's citations true now? |
|---|---|---|---|---|
| `oracleblind.rows` | 2026-10-16 20:42:28 | 2026-10-17 03:47:54 | **YES** (verified at 7 revisions) | **YES** |
| `assertlit.rows` | 2026-10-17 02:03:18 | 2026-10-17 03:20:20 | **YES** (98 gates, then-current) | **YES** (99 gates) |
| `falseclaim.rows` | 2026-10-17 03:20:55 | 2026-10-17 03:21:54 | **YES** (889 of a 1096-line file) | **YES** (899 of a 1106-line file) |

**Evidence statement, not a recommendation: on all three files, disk's bytes are the later run,
and every line citation on both sides was true at the moment it was written.** The reason they
differ is that a committed `.rows` artifact in this tree is a **snapshot of a moving substrate**,
and `origin/master`'s snapshot predates the substrate's last move. I state that because it is
what I measured. **Which of two equally-honest snapshots belongs in the tree is your call.**

---

## 4. PINS -- WHICH SIDE DOES EACH CONSUMER'S PIN MATCH? (task 3)

Searched the whole tree for each sha256 prefix. Results are **asymmetric**, and that asymmetry
is the most decision-relevant thing in this report.

| file | origin sha256 | disk sha256 | pinned? | pin matches |
|---|---|---|---|---|
| `oracleblind.rows` | `614ea700469eeea9` | `0cc47cebe9d96def` | **YES, 6 sites** | **ORIGIN** |
| `assertlit.rows` | `fe9dde82b1c89d53` | `1880d9e634d758a0` | **NO -- neither sha appears anywhere** | **n/a** |
| `falseclaim.rows` | `cf2670c980792577` | `7a941f767c7d4e0c` | **YES** | **DISK** |

### `oracleblind.rows` -- the only pin points at ORIGIN, and it is PROSE, not enforced

`gates/tnvalue-census.py:8`:
> `gates/oracleblind.rows` (COMMITTED, sha256 614ea700469eeea9...) read **28** oracles

`614ea700469eeea9` is **origin's sha, exactly**. Also cited at `.agents/TODO.md:17160`,
`.agents/slop/oracleblind/REPORT.md`, `.agents/slop/unpushed/REPORT.md`.

Two qualifications you need before treating that as a pin:

1. **It is not enforced.** The only runtime `hashlib` use in `tnvalue-census.py` is line 721,
   which hashes **its own output text** to print a self-report. **Nothing compares a stored sha
   against `oracleblind.rows`.** It is a documentary claim in a docstring. Stale it and no gate
   goes red.
2. **Its substantive claim survives either choice.** I counted the rows reading
   `ALL VALID INPUTS AGREE` on **both** sides: **28 on origin, 28 on disk**; of those `tn_*`,
   **23 on origin, 23 on disk**. The 28 and the 23 hold either way. Only the sha *prefix* goes
   stale if disk's bytes are committed.

**And disk's sha already has a witness that calls origin's the committed one.**
`.agents/slop/tnvalue/REPORT.md:18` reads
`| new sha256 | 0cc47cebe9d96def vs the committed 614ea700469eeea9 |` -- i.e. **that report
already treats disk as the newer run and origin as the committed baseline.** So for this file
the tree contains a pin pointing at origin *and* a report announcing disk supersedes it.
**Those two documents disagree, and I am not going to pick between them for you.**

### `falseclaim.rows` -- the only pin points at DISK

`.agents/TODO.md:17779-17780`:
> **122 CLAIMS: 1 AGREE, 0 FALSE, 121 UNASKABLE, rc 0** (VERIFIED BY THE CALLER:
> **`122 rows, sha256 7a941f767c7d4e0c`**)

`7a941f767c7d4e0c` is **disk's sha, exactly**. Its claimed tally reproduces on both sides
(`122 / 1 AGREE / 0 FALSE / 121 UNASKABLE`), so this pin is **satisfied in substance by either
candidate** and distinguishes them only by sha.

`falseclaim-census-gate.py:78` mentions sha256 stability across `PYTHONHASHSEED` but **names no
hash**, so it pins nothing.

### `assertlit.rows` -- NO PIN ON EITHER SIDE

Neither `fe9dde82b1c89d53` nor `1880d9e634d758a0` appears anywhere in the tree. The generator
`gates/assertlit-census.py` contains no hex run of 12+ characters. **A pin that matches neither
side would mean both are wrong -- here there is simply no pin, so this file has the weakest
external constraint of the three and the most freedom.**

### The pattern in one line

> **Of the two pins that exist, one points at origin and one points at disk. `assertlit` has
> neither. So for this file the tree cannot tell you which is right, because it contains two
> documents that each bless a different side.**

---

## 5. DECISION MATRIX AND CONSEQUENCES (task 5)

### How the consumers actually use these files -- this determines every consequence below

Measured, and it matters more than the diffs do:

- **All three generators are WRITE-ONLY for their own file.** `oracleblind-census.py:1321`
  `REPORT.write_text(text)`; `assertlit-census.py:1286` `REPORT.write_text(...)`;
  `falseclaim-census-gate.py:618` `--rows` default `str(ROWS)`. **None of the three reads its
  own `.rows` back to compare.** So none of them can detect that its committed artifact is stale.
- **Exactly one consumer READS a `.rows` file as data: `gates/tnvalue-census.py`.** At line ~260
  it does `for line in BLIND.read_text().split("\n")[1:]` and builds `blind[cells[0]] =
  {verdict, rows, base_sha, why, declared_by}`, then `probe(rel, p, sites, blind.get(rel))`.
  **Its verdicts are inherited from `gates/oracleblind.rows`, not recomputed.**
  - Missing an oracle from the file yields `blind is None`, which `probe` stores verbatim
    (`out["blind"] = blind`) -- i.e. a **silent absent verdict**, not a refusal.
  - **Because the row SET is identical on both sides, no `blind.get(rel)` returns `None` on
    either candidate.** There is no DEAD-shaped consequence from this file's choice.
- **Nothing anywhere compares these files' bytes to a stored hash.** (See task 3.)

**So the honest headline: for all three files, no gate goes red on either choice. The
consequences are about *truthfulness of the artifact*, not about a gate turning red.**

### The matrix

| file | if you commit **ORIGIN's** bytes | if you commit **DISK's** bytes |
|---|---|---|
| **`oracleblind.rows`** | Restores `HEAD` to what `origin/master` has. `tnvalue-census.py:8`'s sha `614ea700469eeea9` and `TODO.md:17160`'s "SHA256 `614ea700469eeea9` ... IN `HEAD`" both stay **true**. Costs: 3 rows carry citations (`CTOR_PARAMS:190`, `PRI_OFF:81`) that are **wrong against every current revision**, and 2 rows carry a stale `base_sha` and a stale `sites=64` for `rand_census`. `tnvalue` would report `rand_census` with **2 phantom sites** and `op_graph_census` with a `base_sha` that **does not hash its current output** -- i.e. a reader who checks the claim finds it false. | Ships the later run. `tnvalue-census.py:8`'s sha becomes **stale** (its *counts*, 28 and 23, stay true), and `TODO.md:17160`'s "SHA256 `614ea700469eeea9` ... IN `HEAD`" becomes **false**. Both are **prose**, and nothing enforces either, so **no gate goes red**. Gains: every citation is checkable against the tree as it stands, and it is the exact byte stream `.agents/slop/tnvalue/REPORT.md:18` already describes. |
| **`assertlit.rows`** | Restores the 02:03 snapshot. Header would claim **98 GATE · 160 PINS** while the tree now has **more gates** -- a self-declared denominator that is **too small**, in a file whose whole subject is denominators. 2 oracles would read `UNSOURCED` when a current run classifies them `DERIVED`, i.e. the file would **over-report the named defect by 2**. | Ships `99 GATE · 162 PINS` and the 2 `DERIVED` rows. Denominator agrees with the tree. **No pin on either side exists to be broken.** This is the file with the **fewest constraints** in either direction. |
| **`falseclaim.rows`** | Ships `line=889` for a `checks/runs-artifacts.py` that has been **1106** lines since `48bbd5700`. The row's own `file=`/`line=` pair is **not checkable** -- line 889 is about `node`-lane lanes, not `resolve()`. Verdict tally is unaffected. | Ships `line=899`, which **resolves to the exact prose the row quotes** (`**THE AST RESOLVER LOSES A DIRECTORY.** resolve() returns "" ...`) in the current file. `TODO.md:17780`'s pin `7a941f767c7d4e0c` stays **true**. |

### The third option, and it is not neutral

**Deleting the index entry and NOT re-adding** leaves all three **absent from the tree** while
still present in the worktree. Consequences, per file:

- `gates/oracleblind-census.py:118` names `REPORT = HERE / "oracleblind.rows"`. Its **only**
  writer is `:1321`, so the next full census run **regenerates** it and the file reappears
  **untracked** -- reproducing exactly the state this report is about. `--only` runs do **not**
  write it (`:1311-1318` says so and returns without writing), so a partial run cannot heal it.
- `gates/assertlit-census.py:85` / `:1286` and `gates/falseclaim-census-gate.py:100` / `:618`
  behave the same way: **each is regenerated only by its own full run.**
- `gates/tnvalue-census.py` would then find `BLIND.read_text()` on a **missing path** --
  an uncaught `FileNotFoundError` at import-adjacent read time, i.e. a **crash, not a
  verdict**. It has no existence check on `BLIND`.

So "do nothing" is not a neutral third option: it makes `tnvalue-census.py` **crash** and leaves
all three as untracked regenerable artifacts.

---

## 6. WHAT I DID NOT DO

- **I did not choose.** The task put the decision outside this unit and I left it there.
- **I ran no git write.** No `add`, `commit`, `checkout`, `reset`, `restore`, `stash`, `rebase`,
  or `jj` mutation. Every git call was `rev-parse`/`ls-tree`/`ls-files`/`status`/`diff`/`log`/
  `show`/`cat-file`/`merge-base`/`hash-object`, prefixed `env -u GIT_INDEX_FILE` for index reads.
- **I ran none of the prohibited tools**: no `bend`, no `checks/differ.py`, no `gates/*` execution,
  no `e2e*`, `sweep.py`, `bounded.py`, `repro-paths.py`, `cites-census.py`, corpus loops,
  `pytest`, `mypy`, `ruff`. The three `.py` files were **read and grepped only**.
- **I wrote only** `.agents/slop/pinsbytes/matrix.rows` and this file. **No `.txt` was created.**
- **One process at a time**, nothing backgrounded, every command a single quick read.

### Caveats an owner should weigh

1. **The tree is a moving target.** I re-read `HEAD`, `origin/master`, all three index entries
   and all three shas at `05:28:21Z`, after all diffs, and **nothing had changed** -- so the
   measurements are internally consistent. But a gate writing these files at any moment will
   make disk's bytes move again. **Re-verify the shas immediately before committing.**
2. **`mtime` is evidence of when bytes were written, not proof of what tree they saw.** I leaned
   on *content agreement* for the direction (origin's citations resolve at their commit's tree,
   disk's resolve at the current tree) and used `mtime` only as corroboration. The two agree.
3. **The `in_HEAD = NO` reading is from `git ls-tree HEAD`**, which printed an empty line with
   `rc=0`. I deliberately avoided `git rev-parse HEAD:<path>`, which **echoes its unresolved
   argument to stdout** and can be misread as output.
4. **I did not establish WHY the index holds `e69de29b` for exactly these three.** I report the
   state, not a cause.
5. **`assertlit`'s `GATE` denominator (99) is not reproducible from a shell glob** (`gates/*gate*.py`
   reads 86); `gates-pop.py` admits gates by stem **plus** an AST `Gate(` test, per the file's own
   header. I did **not** reconstruct that population -- so *the 99 is asserted by the file, not
   independently confirmed by me*. What I **did** confirm independently is the directional fact:
   origin saw **98** and disk saw **99**, and gates are only ever **added**.
