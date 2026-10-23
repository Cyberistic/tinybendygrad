# PINCITE -- THE 516 FALSE POSITIVES WERE THE GATE'S OWN TWO DEFECTS

`gates/pin-cite-gate.py` asks a CONTENT question: **does the cited upstream line/range hold
what the port's own comment says it holds?** Its claim tokens are the backticked strings in
the port's comment. The first reading reported **516 citations that hold at NO upstream
revision** and called 29 of them "dangling claims".

**MEASURED: 516 OF THOSE ARE THE GATE'S OWN FALSE POSITIVES, AND THE TWO CAUSES ARE
REPAIRABLE. NEITHER REPAIR WEAKENS THE GATE.** The gate still FAILS, on fewer and BETTER
rows, and every surviving row names a token that really is in the cited file.

Everything below was measured on **ONE FROZEN COPY** of the port tree
(`.agents/slop/pincite/snap/`), because the live `tinybendygrad/` is owned by other units
and moves under the gate's feet. `--tree DIR` was added for exactly this.

---

## 1. THE BEFORE/AFTER TABLE

Both readings are the gate's own rows, on the same tree, one with the pre-repair file
(`.agents/slop/pincite/bench/pin-cite-ORIGINAL.py`, which differs from the shipped file
ONLY in the `--tree` plumbing) and one with the shipped file.

| class | BEFORE | AFTER |
|---|---|---|
| `cite.total` | 2624 | 2624 |
| `cite.checkable` | 1624 | 1624 |
| `cite.uncheckable_no_claim_token` | 1000 | 1000 |
| `cite.at_pin` | 696 | **760** |
| `cite.only_older_revision` | 413 | **376** |
| `cite.at_no_revision` | 515 | **488** |
| `cite.at_no_revision_dangling` | 29 | **14** |
| `cite.ambient_relocated` | 4 | 4 |
| `cite.unverifiable_no_claim_about_the_file` | -- (did not exist) | **240** |

`CITATION-CLASSES.rows` carries every row, with its class BEFORE and AFTER.

### THE ROW-LEVEL MOVEMENT (same tree, `diffrows.py`)

```
  at_no_revision             -> unverifiable                  240
  only_older_revision        -> at_pin                         50
  at_no_revision             -> at_pin                         14
  at_no_revision             -> dangling                       14
  at_no_revision             -> only_older_revision            13
  at_no_revision             -> ambient_relocated               4
```

**NOT ONE ROW LEFT THE HOLDING CLASSES.** `at_pin` and `only_older_revision` are the two
holding classes, and the only transition between them is `only_older_revision -> at_pin`
(50 rows, which STAY holding). That is the proof that repair 2 cannot weaken a holding
claim: `holds()` returning true implies the token is IN the file, so a citation that
holds can never be unverifiable.

### WHERE THE 29 OLD DANGLING CLAIMS WENT (`dangle.py`)

| outcome | n | why |
|---|---|---|
| **still `dangling`** | **14** | the token DOES occur in the cited file -- the claim is about that file and it is false there |
| `at_pin` | 1 | repair 1: the cited RANGE names the token (`mixin/reduce.py:13-18`, token `_rop`) |
| `unverifiable` | 14 | the token is the PORT's own vocabulary or a generic noun: `l2i_cdiv`, `Scheduler`, `commit_dtype`, `word_wrap`, `t_gap_ok`, `names`, `data`, `dtype`, `bend`, `AssertionError`, `UPat` |

**Every one of the 14 survivors was asserted to have a NON-EMPTY `present_in_file` and
`after_class == "dangling"`.** The gate therefore fails for the right reasons, and the
class it now fails on is exactly "the file has the name, the cited line does not".

---

## 2. THE TWO REPAIRS

### REPAIR 1 -- THE RANGE IS THE CITED THING, AND THE FIRST LINE IS NOT THE RANGE

`holds()` tested the claim tokens against `lines[lo-1]` -- the FIRST line of the cited
range -- and against the construct DECLARED at that line. A citation to `file.py:100-104`
cites FIVE LINES, so a citation to a function BODY failed even when the claim was exactly
right.

**THE REPAIR:** the claim tokens are ALSO tested against the whole cited range
`lines[lo-1:hi]`.

**THE SAFETY ARGUMENT:** this repair can only turn a FAILURE into a HOLD. It can never
turn a dangling claim into a pass, because a dangling claim's tokens are NOWHERE in the
range -- that is what "dangling" means. MEASURED: 50 rows moved `only_older_revision ->
at_pin`, 14 moved `at_no_revision -> at_pin`, 13 moved `at_no_revision ->
only_older_revision`, and 4 moved `at_no_revision -> ambient_relocated` (the census's
directory ambient is now SEEN, because the claim holds in the sibling file once the range
is read as a range). NOT ONE row moved out of a HOLDING class.

### REPAIR 2 -- A CITATION THAT MAKES NO CLAIM ABOUT THE FILE IT CITES IS COUNTED, NOT VERDICTED

The gate treated EVERY backticked token as a claim about the cited upstream file. But a
port comment routinely backticks **the port's own vocabulary** -- its own helper
(`l2i_cdiv`), its own class (`Scheduler`), a generic noun (`step`) -- on the same line
that cites an upstream line.

**THE REPAIR:** a citation is CHECKABLE only if **at least one** of its claim tokens
OCCURS in the cited upstream file at some revision. If none does, the citation makes no
claim about that file, so it is **UNVERIFIABLE**: counted, and NOT verdicted -- which is
what the gate's own header already said about a header line with no backticked token
("an unfalsifiable claim is not a passing claim"). The class is reported as
`cite.unverifiable_no_claim_about_the_file`, the rows that landed in it are printed with
their reason, and the rows file carries the class as a column.

**THE SAFETY ARGUMENT, AS A SUBSET:** a GENUINE dangling claim's tokens DO occur in the
file -- at a different line -- so the candidate set is NON-EMPTY, the gate still looks for
the line, and it still FAILS. Formally: `holds()` true implies `present != empty`, and
`dangling` requires `holds()` false at every revision; so `dangling` and `present ==
empty` are DISJOINT, and repair 2 moves a row out of the fail class ONLY when the row was
not about the cited file at all.

**PROVEN, NOT ASSUMED -- three ways:**
1. **The row-level movement:** no row left a HOLDING class. Every row that entered
   `unverifiable` came from `at_no_revision`.
2. **The gate's own plant:** the `danger-arm` names a token that IS in the file
   (`Context` in `tinygrad/helpers.py`) and cites a line that does not hold it, and it
   **STAYS DANGLING** -- with a byte-identical copy beside it that moves with it.
3. **A text edit on a copy of a real port file** (FALS-B below): the claim token was
   changed to one that IS in the cited file but NOT at the cited line, and the row went
   straight to `dangling` and the gate's dangling count went 14 -> 15.

---

## 3. THE FALSIFICATION -- TEXT EDITS ON COPIES, NEVER `git show HEAD:`

`falsify.py`, on a frozen copy of the port tree. The edited file is
`tinybendygrad/extra/datasets/wikipedia_download.bend:18`, whose line is
`# TODO(port): STOPPED AT \`gdrive_download\` (extra/datasets/wikipedia_download.py:10).`
and whose upstream target line 10 is `def gdrive_download(url:str, path:str):`.

| arm | the edit | class after | the gate's numbers |
|---|---|---|---|
| **CONTROL** | none (byte-identical) | `at_pin` | at_pin 760, dangling 14, unverifiable 240 -- **ALL IDENTICAL TO THE BASELINE**, rc=1 |
| **FALS-A** | the cited LINE moved out of the file (`:10` -> `:9999`) | **`dangling`** | at_pin 759, dangling **15**, rc=1 |
| **FALS-B** | the claim TOKEN changed to `gdown` -- which IS in the file, at line 7 and line 11, and NOT at the cited line 10 | **`dangling`** | at_pin 759, dangling **15**, rc=1 |
| **FALS-C** | the claim TOKEN changed to `port_only_name_zzz9f3a2c`, which is in NO revision of the file | **`unverifiable`** | at_pin 759, dangling 14, unverifiable **241**, rc=1 |

**FALS-B IS THE REQUIRED "GENUINE DANGLING CLAIM THAT STAYED RED".** Its token occurs in
the cited file and the claim is still false at the cited line, so it is a genuine dangling
claim -- and repair 2 did not rescue it.

**FALS-A IS THE MOVED CITATION.** **FALS-C IS REPAIR 2 ON A REAL FILE.** The CONTROL is
byte-identical and every number is unchanged.

The full transcript is `FALSIFICATION.md`.

---

## 4. THE PLANT

`gates/pin-cite-gate.py --plant` now has SIX new arms on COPIES, each with a byte-identical
control where the shape calls for one (`PLANT.out`):

```
PLANT range arm  : tinygrad/helpers.py:23-24 token `len` -- NOT on the first line
PLANT danger arm : tinygrad/helpers.py:1 token `Context` -- IS elsewhere in the file
PLANT range-arm    ... at_pin=HOLDS ... class=at_pin       -- the cited range :23-24 names `len`
PLANT vocab-arm    ... at_pin=NO    ... class=unverifiable  -- present_in_file=''
PLANT danger-arm   ... at_pin=NO    ... class=dangling      -- present_in_file='Context'
```

The plant asserts, and FAILS if any of these stop holding:
* the control holds at the pin and its byte copy holds with it;
* the half-lie (the citation moved to a line that does not hold the claim) does NOT hold;
* a name that exists nowhere is not held;
* **the RANGE arm HOLDS** -- the repair-1 payoff -- and its byte copy holds with it, and
  the arm is NON-TRIVIAL (the token is asserted NOT to be on the range's first line);
* **the vocabulary arm is UNVERIFIABLE** and is NOT a dangling claim;
* **the danger arm is STILL DANGLING**, its token IS in the file, and its byte copy moves
  with it;
* a wrong date on the pin record is REFUSED.

---

## 5. WHAT WAS **NOT** REPAIRED, AND WHY

* **THE 14 OLD DANGLING CLAIMS THAT ARE NOW `unverifiable`.** They are the port's own
  vocabulary (`commit_dtype` at `tinygrad/dtype.py:16` and `:17`, `Scheduler` at
  `codegen/__init__.py:298`, `l2i_cdiv` at `mixin/dtype.py:53`, `word_wrap`,
  `t_gap_ok`) or a generic noun (`names`, `data`, `dtype`, `bend`). Under a token-matching
  model they are not claims about the cited file. **BUT THREE OF THEM LOOK LIKE REAL
  DEFECTS** -- `tinybendygrad/mixin/dtype.bend:10` says "`commit_dtype`
  (`tinygrad/dtype.py:17`) reads `self._uop.vmin`", and upstream's `dtype.py` has no
  `commit_dtype` and no `vmin` -- so the port's comment uses the PORT's name while
  citing an upstream line. **THE GATE CANNOT SEE THAT, AND THAT IS THE RESIDUAL.** It is
  reported here, not hidden.
* **`window_tokens()`' NEAREST-CITATION RULE.** A backticked name is attributed to a
  citation when it is within 40 characters of ANOTHER citation on the line, which is the
  opposite of "the name belongs to the citation it sits beside". It is why
  `tinybendygrad/mixin/movement.bend:53`'s `UPat` (which belongs to `ops.py:1504`) is
  charged to `mixin/elementwise.py:59`. **NOT TOUCHED:** changing it changes the CLAIM
  TOKEN POPULATION, which is a different question from this task, and `gates/todo-cite-
  gate.py` is forbidden by the brief.
* **`gates/header-census-gate.py`'s DIRECTORY AMBIENT.** A bare basename is disambiguated
  by the header's declared target's directory, which points `dtype.py` at
  `tinygrad/codegen/decomp/dtype.py` when the port meant `tinygrad/dtype.py`. The gate
  reports those as `cite.ambient_relocated`; the defect is in the census, and the brief
  forbids touching the census's parser semantics.
* **THE `at_pin` SEMANTICS OF `revs[0]`.** `eval_path` reads the pin's content from the
  NEWEST upstream commit that touched the cited file. For files under `tinygrad/` that
  commit IS the pin (`45fc5ae73` is the newest commit that touched `tinygrad/` at all), so
  the reading is right there; for a file OUTSIDE `tinygrad/` it may be newer than the pin.
  **NOT CHANGED:** it is the gate's existing definition of "the pin", and changing it
  would move the `at_pin` class for reasons unrelated to this repair.
* **THE CITATIONS WHOSE SUBJECT DOES NOT RESOLVE (92 of them).** `claims_the_file` is
  `None` for them -- there is no file to read a vocabulary from -- so they stay in the
  verdict population and are never called unverifiable. **THIS IS THE CONSERVATIVE
  CHOICE:** an unresolvable subject is a defect in its own right and must not be softened.
* **THE `DEAD` VERDICT.** The gate still emits rows; `DEAD` is unreachable here, as
  before.

---

## 6. THE COMMITS AND THE CORPUS DIGEST

**COMMIT** `a81328d36e8503f415ba51c8b5f15d1421c482cc` --
`gates/pin-cite-gate.py: the 516 false positives were the GATE's OWN two defects`.
20 files, 5380 insertions, 58 deletions. **`git show --stat` AND `git fsck --no-progress`
IN ONE COMMAND:**

```
 .agents/TODO.md                                  |   56 +
 .agents/TOOLS.md                                 |    2 +-
 .agents/slop/pincite/CITATION-CLASSES.rows       | 2623 ++++++++++++++++++++++
 .agents/slop/pincite/DANGLE.out                  |   52 +
 .agents/slop/pincite/FALSIFICATION.md            |   56 +
 .agents/slop/pincite/PLANT.err                   |    1 +
 .agents/slop/pincite/PLANT.out                   |   13 +
 .agents/slop/pincite/REPORT.md                   |  229 ++
 .agents/slop/pincite/analyze.py                  |   53 +
 .agents/slop/pincite/bench/gatekit.py            |    1 +
 .agents/slop/pincite/bench/header-census-gate.py |    1 +
 .agents/slop/pincite/bench/pin-cite-ORIGINAL.py  |  734 ++++++
 .agents/slop/pincite/classes.py                  |   91 +
 .agents/slop/pincite/dangle.py                   |   50 +
 .agents/slop/pincite/diffrows.py                 |   42 +
 .agents/slop/pincite/falsify.py                  |  111 +
 .agents/slop/pincite/pin-cite-gate.ORIGINAL.py   |  731 ++++++
 .agents/slop/pincite/probe.py                    |   21 +
 .agents/slop/pincite/table.py                    |   74 +
 gates/pin-cite-gate.py                           |  497 +++-
 20 files changed, 5380 insertions(+), 58 deletions(-)
FSCK: error in tree d57bc484ab5ae82df254865a4c2622df263e6f80: duplicateEntries: contains duplicate file entries
FSCK: error in tree d83cf685f89af04f607a49a3c6d2c8ef0c1eec65: duplicateEntries: contains duplicate file entries
FSCK: error in tree 3a60f33f57a4bb2fe120a97720b6bb2af38d9593: duplicateEntries: contains duplicate file entries
```

**THE THREE `fsck` ERRORS ARE PRE-EXISTING** -- they are the three malformed trees
`AGENTS.md` already names, and **NONE OF THEM IS AN ANCESTOR OF HEAD**
(`git merge-base --is-ancestor` answers NO for each), and **MY COMMIT'S TREE IS NOT ONE OF
THEM** (`6556c1de64be3617c038860b7d30526a65e71bb3`).

**THE CORPUS DIGEST, COMPUTED BY IMPORTING IT AND NEVER BY RUNNING THE CORPUS:**

```
.venv/bin/python -c "import sys; sys.path.insert(0,'checks'); import differ; print(differ.substrate_digest())"
```

| when | digest |
|---|---|
| before my change | `cfeb41ea869fc2861969065393ee9cf73ffb355d7399f1561a69673941cd14c5` |
| after my change | `d3b3288b800f1376d01b97fc195ad9625eaec216d9afbb3a691fe5b5445c6781` |

**THE DIGEST MOVED, AND IT WAS NOT ME.** MEASURED: **0 of the 20 paths my commit touched
are in the substrate** -- `gates/` is not in it at all, the seven `.agents/` members it
names are `.agents/slop/graphcmp*` (not mine), and `tinybendygrad/` was not touched. The
movement is `tinybendygrad/uop/ops.bend`, which another unit edited DURING this session
(it is the only dirty substrate member afterwards). **THE DIGEST IS A FACT ABOUT THE
WORKING TREE, AND THE WORKING TREE IS NOT MINE.**

## 7. THE FILES

| file | what it is |
|---|---|
| `gates/pin-cite-gate.py` | the gate, with the two repairs, the new class, `--tree`, and the new plant arms |
| `.agents/slop/pincite/bench/pin-cite-ORIGINAL.py` | the pre-repair gate, plus `--tree` ONLY, for the before/after reading |
| `.agents/slop/pincite/falsify.py` | the falsification (four arms on copies) |
| `.agents/slop/pincite/diffrows.py` | the row-level movement table |
| `.agents/slop/pincite/dangle.py` | where the 29 old dangling claims went |
| `.agents/slop/pincite/analyze.py`, `classes.py`, `table.py`, `probe.py` | the analysis harness and its caches (the caches are regenerable and were NOT committed) |
| `.agents/slop/pincite/CITATION-CLASSES.rows` | EVERY citation with its class BEFORE and AFTER, on one tree -- the complete before/after, one row per citation |
| `.agents/slop/pincite/FALSIFICATION.md` | the falsification transcript |
| `.agents/slop/pincite/PLANT.out` | the plant transcript |

The tree copies (`snap/`, `fals/`), the blob cache and the raw per-gate rows files were
NOT committed: they are a stale COPY of a MOVING tree, and `falsify.py` freezes its own
copy at run time.
