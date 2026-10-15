# Which instruments declare their population by shape

`.agents/slop/shapecensus/` · measured **2026-10-15T19:15:52Z** · scope: the commit tree at the
working directory `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`, read only.

Doctrine under audit: `AGENTS.md` §"1. AN INSTRUMENT DECLARES ITS POPULATION BY DISCOVERY, OR IT IS
NOT A GATE". Acceptable = a generator's own declaration loaded by path, a directory walk, or a
regex over the tree's own write sites. Not acceptable = a basename regex, a suffix/extension set,
a hand-written list, a glob scoped to one directory, or a regex over a file's whole text with no
section boundary.

**Nothing here was fixed.** This is a census.

---

## 1. THE DENOMINATOR, AND HOW IT WAS ENUMERATED

**226 instruments. 244 rows.** A file that carries more than one membership expression gets one
row per expression; 13 files carry a second or third, which is where 244 comes from.

The 226 is **discovered**, not taken from any document:

```
rglob("*.py") over checks/ and gates/     ->  72 + 154 = 226
```

Both directories are flat — `checks/` has 0 nested `.py`, `gates/` has 0 nested `.py`
(measured). No list from `AGENTS.md`, `README.md` or any report contributes a row. The walk is in
`.agents/slop/shapecensus/build.py`; its output is `.agents/slop/shapecensus/findings.rows`.

`findings.rows` is TSV, five columns, **no header row**, so `wc -l` on it is the row count:

```
instrument <TAB> the_expression <TAB> class <TAB> evidence_file_line <TAB> present_or_fixed
```

Verified before writing this: `wc -l` = **244**, `cut -f1 | sort -u | wc -l` = **226**, every row
has exactly 5 tab-separated fields (0 malformed).

### How each row was decided

`extract.py` walks all 226 files and emits every walk call, glob call, `endswith`/`startswith`,
module-level string container and `re.compile` — 1338 signals (`.agents/slop/shapecensus/
signals.rows`). `iterated.py` narrows to the literals that are actually **iterated** (132 rows
over 88 files). Those two are *where to look*, not the verdict: the class in column 3 is assigned
by reading the file, and column 4 cites a `file:line` a reader can open.

---

## 2. THE TALLIES (244 rows, of 226 instruments, 2026-10-15T19:15:52Z)

| class | rows | verdict |
|---|---:|---|
| `no-population` | 104 | neutral — the file declares no population to sweep |
| `hand-list-cross-checked` | 51 | NOT ACCEPTABLE, but a run compares it — see §4 |
| `hand-list` | 31 | **NOT ACCEPTABLE** |
| `walk` | 19 | acceptable |
| `self-declared-arms` | 16 | acceptable — the file *is* the generator of the members |
| `class-table` | 6 | neutral — decides which BUCKET a row lands in, never WHICH rows exist |
| `suffix-set` | 5 | **NOT ACCEPTABLE** |
| `declaration-by-path` | 5 | acceptable |
| `single-dir-glob` | 4 | **NOT ACCEPTABLE** |
| `write-site-regex` | 1 | acceptable |
| `unscoped-text-regex` | 1 | **NOT ACCEPTABLE** (the row is FIXED) |
| `basename-regex` | 1 | **NOT ACCEPTABLE** |
| **total** | **244** | |

Acceptable **41**, neutral **110**, not acceptable **93**. 41 + 110 + 93 = 244.

State column: `PRESENT` 209, `FIXED` 4, `PARTIAL` 2, `REFUSED` 29. 209 + 4 + 2 + 29 = 244.

**29 of 244 rows (29 files) rest on a file this census did not read** and say so in column 5.
They are all classified `no-population` or `walk` because the AST census found no membership
expression to read, but that is an inference from a missing signal, not a reading. 21 of the 29
are `checks/*.py`; all 29 are listed in `findings.rows` with `REFUSED` as the first word of
column 5. Do not quote them as cleared.

---

## 3. EVERY NOT-ACCEPTABLE INSTANCE, BY NAME

### 3.1 `hand-list` — 31 rows, 27 distinct files

**The census roots — a list standing in for the tree.**

| instrument | expression | evidence |
|---|---|---|
| `checks/wallcheck.py` | `WALK_ROOTS = ('tinybendygrad','.agents/slop','docs','checks','gates','AGENTS.md','README.md')`, then `SUFFIXES` of 12 extensions | `checks/wallcheck.py:47,48`, walked at `:139` |
| `checks/no-strays.py` | `SOURCE_TREES = ('tinybendygrad',)` then `os.walk` per tree | `checks/no-strays.py:139,147` |
| `checks/citation-gate.py` | `PYROOTS = ('tinygrad','examples','extra')` | `checks/citation-gate.py:43,127` |
| `checks/devgate.py` | `VENDOR_PREFIX = ('tinygrad/','references/','xd1/','opstree/')` | `checks/devgate.py:210` |
| `checks/sweep.py` | `RESIDUE_ROOTS = ('.agents/slop','runs')` | `checks/sweep.py:81,1049` |
| `checks/sweep.py` | `os.walk` over a per-unit BASE list | `checks/sweep.py:550` |
| `checks/sweep.py` | `ROLE_DIRS = {'oracles':'ORACLE','gates':'GATE','checks':'GATE'}` vs a path part | `checks/sweep.py:766,1201-1202` |
| `checks/abi4_gate.py` | `OTHER_GATES = ('checks/abi_gate.py','checks/jsfix_gate.py')` | `checks/abi4_gate.py:93` |
| `checks/substrate-snapshot.py` | `COPIES = ('bin','checks/differ.py',...)` — typed a second time at `checks/differ.py:884 SUBSTRATE_INPUTS` | `checks/substrate-snapshot.py:76,103` |
| `checks/runs-artifacts.py` | `READS = {'read_text','read_bytes','iterdir','glob',...}` — a finite vocabulary of FS-call names | `checks/runs-artifacts.py:96` |
| `checks/e2e.py` | its own STAGE table | line **REFUSED — not read**; the class is inferred from the file's role, not verified |
| `checks/disagree-gate.py` | `ARMED = ('allred','cdiv','late')` | `checks/disagree-gate.py:60,327` |

`checks/runs-artifacts.py:96` is the cheapest instance in the tree to understand and the hardest
to dismiss: the instrument's whole subject is "which FS calls does this repo's code make", and
the answer is a typed set of **11 call names**. A new API is invisible by construction.

**The graph and table names a driver must cover.**

| instrument | expression | evidence |
|---|---|---|
| `gates/rng_graph_census-gate.py` | `TABLES = ("rb","nic","nv","aprt","sk","gs","ct","fb","dg","lb","ab")` | `gates/rng_graph_census-gate.py:106` |
| `gates/tn_binop_sweep-gate.py` | `BINOPS = ("tn_add", ..., "tn_xor")` | `gates/tn_binop_sweep-gate.py:33` |
| `gates/tc_ptx_types-gate.py` | `TABLES = ("types","mem_types","cast_types")` | `gates/tc_ptx_types-gate.py:46` |
| `gates/ptx_render_census-gate.py` | `FIXTURES = [...]` | `gates/ptx_render_census-gate.py:153` |
| `gates/ops_python_exec-gate.py` | `ops_python_exec-pins.rows`, a pins file beside the gate | `gates/ops_python_exec-gate.py:65-66` |

`gates/rng_graph_census-gate.py:104-106` is the sharpest of these, because its own comment says
**"THE TWO DISCOVERY RULES"** and then types eleven names, justifying them with `grep -c`. A
measurement was taken; the measurement was written down as a list. A twelfth `def *_table` in
`rangeify.bend` is invisible, and nothing turns red.

**Bare counts — weaker still, because there are not even names.**

| instrument | expression | evidence |
|---|---|---|
| `gates/beautiful-mnist-gate.py` | `rows=36` | `:75` |
| `gates/mixin-op-gate.py` | `rows=36` | `:84` |
| `gates/bc-u32-gate.py` | `ROWS = 39` | `:50` |
| `gates/tn_nodes-gate.py` | `ROWS = tuple(f'n{i}' for i in range(15))` | `:52` |
| `gates/tn_minimum-gate.py` | rows literal **REFUSED — not found at module scope** | `:24` names the count in prose only |

**Pin tables — argued in §5, listed here because the census cannot tell them apart
mechanically.**

| instrument | expression | evidence |
|---|---|---|
| `checks/differ.py` | `PINS = {...}`, `REPRO_PINS = {...}` | `checks/differ.py:248,328` |
| `checks/differ.py` | `ORACLE_PIN = {path: sha256}` | `checks/differ.py:62,79` |

### 3.2 `hand-list-cross-checked` — 51 rows, 51 distinct gate files

Every one of the 51 is a `gates/*-gate.py` whose `Gate(rows=…, pins=…)` carries a typed list
where a count or a discovery would do. **This is a separate class from `hand-list` and it exists
because the failure mode is different**, not to soften the count:

`gates/gatekit.py:449` reads `raw = {t: _lines(f) for t, f in lanes.items()}` — the lanes' **own
emitted rows** — `:432-440` fails the gate when a lane's row count differs from `rows`, and
`:492-495` fails it when any name in `pins` is absent from the raw lane. So a driver that gains a
row, loses a row or renames one turns the gate **RED**.

`LIVE_UNITS` was not that. It classified 2,353 files as *live units* and nothing ever compared
the classification against the set. A tripwire is not a census, and I am not claiming these gates
are sound — only that their typed lists cannot silently mis-classify the way a word shape can.
The instrument still cannot *name* what it missed.

53 of the 70 `gates/*-gate.py` carry a `pins=` list; 17 do not, and for those the only
cross-check is the bare count.

### 3.3 `basename-regex` — 1 row

`checks/sweep.py:716` — `ORACLE_WORD = re.compile(r"(^|[-_.])(oracle|rows|expect|pins|baseline)
([-.]|$)")`. **PRESENT, partially retired** — see §6.

### 3.4 `suffix-set` — 5 rows

| instrument | expression | evidence |
|---|---|---|
| `checks/repro-paths.py` | `REPORTS = ".md"` applied as `p.endswith(REPORTS)` over `git ls-tree -r HEAD` | `checks/repro-paths.py:68,81` |
| `checks/slop-declare.py` | `git ls-tree -r -z --name-only HEAD` filtered by `f.endswith(suffixes)` | `checks/slop-declare.py:148,172` |
| `checks/unowned.py` | `PROSE = (".md",".out",".rows",".tsv",".json",".txt",".err")` used to drop paths | `checks/unowned.py:74,198` |
| `checks/gen_gate.py` | `os.listdir(HERE)` then `startswith("gate") and endswith(".bend")` | `checks/gen_gate.py:179-180` |
| `checks/sz.py` | `os.walk(.../tinygrad)` then `endswith(".py") or endswith(".js")` | `checks/sz.py:19,21` |

`checks/slop-declare.py:31` opens with **"THE POPULATION IS A WALK, NOT A LIST"** and the
membership test twelve hundred lines later is a suffix tuple. `checks/repro-paths.py` is the
mirror image: the suffix set that was retracted from `REF` in the 2026-10-15 repair is still the
report population at `:68`.

**A suffix filter that IS the instrument's subject is not counted.** `checks/no-txt.py`,
`checks/txt-owners.py` and `checks/oracle-txt-census.py` all filter on `.txt`; they claim *about*
`.txt` files and drop no member of their own subject. Those rows are classed `walk`
(`checks/txt-owners.py:78,81`). The five above use an extension as a **proxy** for something
else, and the sibling files are dropped silently.

### 3.5 `single-dir-glob` — 4 rows

| instrument | expression | evidence |
|---|---|---|
| `checks/runs-artifacts.py` | `glob.glob(root/checks/"*.py") + glob.glob(root/gates/"*.py")` — **the instrument population is two directory globs** | `checks/runs-artifacts.py:219-220` |
| `checks/differ.py` | `present = {p.name for p in D.glob("*.txt")}` | `checks/differ.py:1117` |
| `checks/devpin.py` | `D.glob("D*.txt")`, `D.glob("D1-graph-*.txt")` | `checks/devpin.py:80,88` |
| `checks/denominator.py` | `sorted(source.glob(pattern))` | `checks/denominator.py:66` — not read beyond this call |

### 3.6 `unscoped-text-regex` — 1 row, and it is FIXED

`checks/repro-paths.py:64` `REF`. The row is classed not-acceptable because the *shape* was
unscoped; its state is FIXED. See §6.

---

## 4. THE ACCEPTABLE ONES, AND WHY THEY ARE

**`walk` — 19 rows.** `os.walk` / `rglob` / `iterdir` / `scandir` / `git ls-tree -r`. The
instruments worth naming: `checks/cites-census.py:73`, `checks/gatesweep.py:107`,
`checks/substrate.py:158`, `checks/stage1-census.py:192`, `checks/residue.py:299`,
`gates/gendirs.py:95`, `gates/retention-check.py:124,181`, `gates/indexread-gate.py:123`
(`ls-tree`, so the commit not the index), `gates/gate-surface.py:309`,
`gates/gates-pop.py:1504` (`HOMES = _homes(ROOT)`), and `gates/gatekit.py:449` — which is the one
place in the whole tree where a gate's row population is **discovered**.

**`declaration-by-path` — 5 rows.** `checks/no-txt.py` (three declarations loaded by path, its
own header names them), `checks/corpus-figure.py` (imports `differ.PINS`),
`checks/substrate-id.py` (its header at `:91` says it is a population by (a)),
`checks/differ.py` (`declared()` at `:357`), `gates/decomp_value-gate.py` (a pins file beside
the gate — a weaker form, since the file's *content* is still typed).

**`self-declared-arms` — 16 rows.** The file is the generator of the members, so the list is the
declaration rather than a substitute for one: the 10 `gates/*-mutate.py` harnesses, the
`checks/abi_gate.py` / `checks/jsfix_gate.py` / `checks/vz_gate.py` plant arms,
`checks/gatesweep.py:287 PLANTS`, `checks/env-precond.py:116 PRECONDS`,
`checks/reorder-gate.py:48,66`, and `gates/msgdiff-gate.py:148 UNCHECKED_KINDS` — which is an
*admission* of what the gate does not check, the opposite defect.

**`class-table` — 6 rows, and this class is why the number is not bigger.** Each entry is
`(class name, pattern)`; the pattern decides what a row **that a lane already produced** is
called. It never decides which rows exist. Instances: `gates/amd_dsl_census-gate.py:755`,
`gates/crp_graph_census-gate.py:981`, `gates/linearizer_census-gate.py:104`,
`gates/ops_python_census-gate.py:630`, `gates/regalloc_census-gate.py:86`,
`gates/wgsl_render_census-gate.py:928`, `checks/citation-gate.py:53`. Every one of them opens
with a catch-all (`UNEXPLAINED` / `^.*$`), which is what makes it a classifier and not a filter.
Compare `checks/sweep.py:716 ORACLE_WORD`, which decides whether a file is in the population at
all: that is a basename-regex, and it is in §3.3.

**`write-site-regex` — 1 row.** `gates/pins-shape-gate.py:239` iterates `gates/` by `iterdir` and
matches by name; its own header at `:33` says **"THE POPULATION IS A WALK AND A NAME, NOT A
SUFFIX SET"**.

---

## 5. DO PINS COUNT AS A POPULATION? — the argument, both ways

The census cannot settle this mechanically, so here it is argued.

**Against (they are hand lists, they are in the file):** `checks/differ.py:248 PINS` and `:328
REPRO_PINS` are typed key=value tables. A pin nobody fires is a comment, which `AGENTS.md`
concedes; a pin whose key has drifted is worse, because it reads as coverage.

**For (they are not populations):** a pin does not enumerate what the tree contains. It asserts a
**value** about a member whose identity is established elsewhere, and every arm that consumes one
is indexed by that other party's own key set: `repro_bad()` at `checks/differ.py:1079-1081`
iterates `REPRO_PINS` only to report rows **present in `REPRO_ARTIFACT`** that disagree, plus keys
`ABSENT from REPRO_ARTIFACT` — the artifact drives the census, the table supplies the expected
answer. `ORACLE_PIN` at `:62` is verified by hashing the file itself (`gates/gatekit.py:208`), so
a file that disappears is caught by `MISSING`, not by the table. And `gates/pins-shape-gate.py`
exists specifically to check that pins have the shape pins must have.

**Ruling: a pin is a claim, not a population, and the census classes it `hand-list` anyway** —
not because the classification is wrong, but because **a census that lets itself exclude classes
it finds inconvenient has stopped being a census.** The class column records what the expression
*is*; §3.1 says why six of the 31 rows are not defects. If the ruling is wrong, the fix is one
edit to `NOT_ACCEPTABLE` in `build.py`, not a re-reading of 244 rows.

---

## 6. THE STATE OF EACH KNOWN INSTANCE

| known instance | state today | evidence |
|---|---|---|
| `checks/sweep.py LIVE_UNITS` (tuple of 14) | **FIXED — removed** | `checks/sweep.py:768` is the tombstone: *"LIVE_UNITS lived here, a tuple of 14 names. It is gone, and `live_units()` … is what answers the question now."* Nothing named `LIVE_UNITS =` survives; the four other mentions (`:116`, `:685`, `:730`, `:765`) are prose. |
| `checks/sweep.py:658 ORACLE_WORD` | **PRESENT, PARTIALLY RETIRED.** `AGENTS.md` says `:658`; the definition is at **`:716`** today. The use at `:1276` is now `if name in mentioned and ORACLE_WORD.search(name) and not name.endswith((".sh",".py"))` — the `name in mentioned` conjunct is the fix, so an **uncited** file cannot reach the arm and the 670-of-675 overcount is closed. **What is still a shape:** for a *cited* file the bucket is chosen from the basename. | `checks/sweep.py:716`, `:1276` |
| `checks/differ.py artefacts_ok()` | **PARTIAL.** `MISSING` (`:1120`) and `UNEXPECTED` (`:1121`) run off `declared()` — `checks/differ.py:357`, built from `corpus()`/`CONTROLS`/`PLANTS`/`STAB` at `:373-381`. But `present` at **`:1117` is still `D.glob("*.txt")`**, and `here = present & declared()` at `:1118` is what the `EMPTY` and `ONE-LINE` arms iterate. The file's own docstring records the measurement the change came from (53 findings → 0 on a rename). | `checks/differ.py:1117-1124` |
| `checks/repro-paths.py REF` | **FIXED.** The five-item suffix set `(?:sh\|py\|bend\|mjs\|json)` is **gone**. `REF` at `:64` is a permissive extraction and membership is decided by `os.path.exists` at `:108`. **Two things survive that the repair did not touch:** `REPORTS = ".md"` at `:68` still decides the *report* population by suffix (`:81`), and `committed_reports()` correctly reads `git ls-tree -r HEAD` rather than `git ls-files` — the index defect was fixed in the same edit (`:72-78`). | `checks/repro-paths.py:64,68,81,108` |
| `gates/gates-pop.py:95 HOMES = ("checks","gates")` | **FIXED.** The literal is gone. `HOMES = _homes(ROOT)` at `:1504`, which is `_measure(root)[0]` at `:868-869` — an AST measurement over the tree. `:97-99` records that the original was right, `:112-118` records that the root set is now measured. | `gates/gates-pop.py:97,112-118,868,1504` |
| `.agents/TOOLS.md` | **STILL A LIST** — see §7 for the measurement and the disagreement with the number in `AGENTS.md`. | — |
| `checks/differ.py REPRO_PINS` / `PINS` | **PRESENT, and argued not to be a population** — §5. | `checks/differ.py:248,328` |
| `.agents/slop/e2estage8/verdicts.py PROSE` | **FIXED — CONFIRMED IN THE CODE.** `PROSE_END = re.compile(r"^EXIT STATUS\b", re.M)` at `:48`, and `prose_rows()` at `:52-57` slices `src[:cut.start()]` before `PROSE_TABLE.finditer(table)`. The cut is at the section **header**, not a line number. `CODE = re.compile(r'say\("== (\d+)/')` at `:49` reads the gate's own write sites. | `.agents/slop/e2estage8/verdicts.py:47-57` |

**`verdicts.py` is outside this census's population.** It lives under `.agents/slop/`, not
`checks/` or `gates/`, so it is **0 of 226** here and is reported from §6 only. Same for
`checks/sb-gate.sh` and the other 17 `checks/*.sh`: this census walked `*.py` and did not read
any shell gate. **REFUSED, and I am not going to estimate it.**

---

## 7. `.agents/TOOLS.md`, MEASURED WITH ITS OWN RULE

`extract.py:42` writes `.agents/slop/toolsledger/paths.tsv`, which is outside this census's write
scope, so `toolsmd.py` re-implements its extraction rule **verbatim** (`:20-41`) and prints
instead of writing. **One change, stated:** `git ls-files` (the index) becomes `git ls-tree -r
HEAD --name-only` (the commit), because `AGENTS.md` records the index as chronically stale here
and `checks/repro-paths.py:72-78` records the same substitution as a repair it had to make for
itself.

```
TOOLS.md                        1631 lines
distinct paths (the ledger rule)  367
INDEX  git ls-files      present 193  absent 174  absent-INSTRUMENT 5  absent under .agents/slop/ 86
HEAD   git ls-tree -r HEAD
                present 193  absent 174  absent-INSTRUMENT 5  absent under .agents/slop/ 86
index \ HEAD disagreement          529 entries
```

Measured 2026-10-15T19:15:52Z. Three things in that block are worth more than the headline:

1. **The index/HEAD disagreement is 529 entries and moves the verdict by zero.** `os.path.exists`
   dominates both populations. This is the same measurement `checks/repro-paths.py:72-78` made
   for its own denominator.
2. **`AGENTS.md` says 333 paths, 153 present, 180 gone. I measure 367 / 193 / 174** on the same
   file with that file's own rule. `TOOLS.md` was modified today at 17:55 UTC, after the
   document's reading, so the two numbers are readings of two states. I am not reconciling them;
   I am reporting mine with its denominator and its timestamp.
3. **The instrument that maintains this ledger has the defect this census is about.**
   `.agents/slop/toolsledger/extract.py:34` classifies by **basename**:
   `INSTR = re.compile(r"(gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|
   no-txt|substrate)")`. `checks/sweep.py:716 ORACLE_WORD` is the same mistake with a different
   word list — the census at `AGENTS.md` records that it called 670 of 675 files INSTRUMENTs and
   5 were named by a live gate. `extract.py:25` is a hand-rolled token regex, so the ledger's
   *population* is a regex over the ledger's text rather than a generator's declaration. **This
   file is not in `checks/` or `gates/`, so it is 0 of 226 and is not counted; it is named here
   because the report would be worse for pretending the census stops at two directories.**

---

## 8. WHAT THIS CENSUS DID NOT MEASURE

Stated so nobody reads an absence as a zero.

- **17 `checks/*.sh` and 0 `gates/*.sh`.** Walked `*.py` only. `checks/sb-gate.sh` is named in
  `AGENTS.md` and was not opened. **REFUSED.**
- **`.agents/slop/**`.** 63 of the 75 offenders `gates/indexread-gate.py` reports live there, per
  its own header at `gates/gates-pop.py:100-118`. None are in the 226. **REFUSED.**
- **`checks/e2e.py`'s stage table.** Classed `hand-list` on the strength of the file's role; the
  binding was not read. **REFUSED on the line, admitted in `findings.rows`.**
- **29 files not read at all**, listed in §2. **REFUSED.**
- **Whether each `hand-list` has ever been wrong.** The census classifies the *expression*. It
  does not measure a delta for any of them, because measuring one means running a gate, and the
  brief forbids that. **Every `hand-list` row in this report is a statement about the code, and
  none of them is a claim about a consequence.**

---

## 9. FILES

| file | what it is |
|---|---|
| `findings.rows` | the 244 rows, TSV, no header |
| `extract.py` → `signals.rows` | 1338 AST signals over the 226 files |
| `iterated.py` → `strlists.rows` | 132 iterated module-level literals over 88 files |
| `rollup.py` → `rollup.rows` | one summary line per file |
| `build.py` → `findings.rows` | the classification; `CLS` is hand-assigned, `RULES`/`gate_evidence` cover the rest |
| `toolsmd.py` | §7, read-only |

```
.venv/bin/python .agents/slop/shapecensus/build.py  > .agents/slop/shapecensus/findings.rows
env -u GIT_INDEX_FILE .venv/bin/python .agents/slop/shapecensus/toolsmd.py
```

`build.py` prints its own denominators on stderr; they are reproduced in §1 and §2 and agree with
the file.