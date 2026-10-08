# `concise` — unit report

**Rule enforced.** `AGENTS.md`: *"You must use concise, clean code… He hates unclean
code and hacks. He loves his documentations. LOCs IS a measure of quality, the LESS,
the better."* **The target is REDUNDANT AND PARAPHRASED PROSE, NOT THE DOCUMENTATION.**
This tree's comments are the record; almost nothing in it is prose-for-prose's-sake.

**Nothing committed. Nothing staged.** 3 comment edits + 7 new instruments under this
directory, all unstaged/untracked. Verified against `git ls-tree -r HEAD`, not `git ls-files`.

---

## 0. HOW MY OWN MEASUREMENT WAS WRONG, BEFORE ANY RESULT

Four defects, each found by a control rather than by reasoning, each with its
before-value. **Read this section before any number below, because three of the four
numbers I would otherwise have reported were wrong.**

### 0.1 The `.py` docstring count UNDERCOUNTED by 9 503 lines

`census.py` v1 rolled its own docstring rule over `tokenize`: "a STRING token right
after a `def`/`class` keyword". **It never fired for a single docstring**, because the
rule cleared itself on the very next NAME token — which is the function's own name:

```python
pending_def = ttype == tokenize.NAME and text in ("def", "class")   # `def` -> True
# next token is `f`, the NAME: -> pending_def = False, and the docstring is never seen
```

| | before (v1 heuristic) | after (`ast`) |
|---|---|---|
| docstring lines over the `.py` population | **16 561** | **26 447** |
| headline PROSE ratio | **39.7 %** | **42.2 %** |

Caught by `.agents/slop/concise/selftest.py` CHECK 2, which cross-counts against
`ast.get_docstring` — **16 561 vs 26 064, a −9 503 UNDERCOUNT.** `ast` drops comments
and `tokenize` cannot see docstring bodies, so the fix was to split the work: `tokenize`
counts COMMENT tokens, `ast` counts docstrings. Both are named in `census.py`'s header.
`selftest.py` now reads **26 440 = 26 440, 0 files differing.**

### 0.2 `paste.py` reported **0 sites in 823 files** — and one of them was a real paste

The instrument I wrote it for, `.agents/slop/e2epy/diff.py:124-129`, was not in the
output. Grouping comment lines into *maximal* runs put 124-126 and 127-129 in the same
group, and comparing whole groups cannot see a duplication **inside** one. The unit of
comparison had to be the line, scoped to a run. **23 real sites in 13 files** after the
fix, against **0** before — on a population where 1 known positive existed.

### 0.3 `language.py` reported **0** for the wrong reason twice over

Two independent faults, both caught by one control:

- Its vocabulary was `keyword.kwlist | dir(builtins) | 46 stdlib names`. **The brief's
  own example of the target is `# increment the counter` — two ENGLISH words.** A
  keyword vocabulary cannot see English. Now `/usr/share/dict/words` (234 456 words,
  casefolded) is loaded, and the detector **REFUSES with exit 3** if it is absent,
  rather than reporting a zero it cannot support.
- `PROJECT` was compiled `re.IGNORECASE`. That guard is the load-bearing filter, and
  `IGNORECASE` made its CamelCase clause `[A-Z][a-z]+[A-Z]` — which exists to catch
  *this project's* type names — match **any lowercase word of 3+ letters**, including
  the `increment` in the example. Case sensitivity is the whole point of that clause.

### 0.4 The third `language.py` error: the unit of analysis was the wrong shape

With both fixed it reported **1 383 hits over 18 285 comment lines** — and every hit I
looked at was a *continuation* of a wrapped sentence (`"citation could plausibly
name."` is the tail of a sentence whose first line named a file). **A block's meaning
is distributed across its lines, so testing a line answers a question nobody asked.**
Merging each consecutive comment run before testing: **1 383 → 141 over 5 493 blocks.**
Reading those 141, they were *project rationale in plain English* — `"a dead lane is
never a green one"` — not language explanation. So the negative test ("names nothing
project-specific") is **necessary and not sufficient**, and a `MECHANISM` positive
clause was added: **141 → 13 over 5 493 blocks.**

### 0.5 My control was testing a copy of the rule, not the rule

`plant.py` kept its own reimplementation of `language.py`'s three-clause test, so it
lacked the `MECHANISM` clause and **PASSED a case the detector rejects.** That is
`AGENTS.md`'s own fault — *a second copy of a population* — committed inside my own
instrument. The predicate is now single-sourced in `language.fires()`, which `plant.py`
imports.

---

## 1. CENSUS

**Population, by DISCOVERY, both halves named.** `os.walk` over `checks/`, `gates/`,
`tinybendygrad/`, `.agents/slop/` (suffix `.py`/`.bend`) **intersected with the BLOBS of
`git ls-tree -r HEAD`** — *not* `git ls-files`, which reads the INDEX.

**Tokenizers, named.** `.py` → `tokenize` for comments + `ast` for docstrings (they
cannot see each other's subject; see §0.1). `.bend` → **no tokenizer ships**, so
`bend_lex` is a line lexer tracking `"` and `'` literals.

```
MEASURED 1081 files, of 1081 walked-and-tracked paths
  (os.walk over 1226 on disk; git ls-tree -r HEAD blobs: 4615 tracked)
  LOC (non-blank)  402019
  comment lines    142892  (35.5% of LOC)
  docstring lines   26713  ( 6.6% of LOC)
  PROSE TOTAL      169605  (42.2% of LOC)
```

**`grep -c '#'` measures something else, and here is the size of the difference.** Over
the 258-file `.bend` population: `grep -c '#'` reads **124 844**, `bend_lex` reads
**124 607**, in **21 files**. The witness is real and on disk —
`tinybendygrad/sz.bend:1547` holds `"### Changes\n```\n"`, a `#` inside a live string
literal. `plant.py` asserts this witness every run.

---

## 2. THE FINDING: THE TARGET CLASS IS NOT IN THE `.py` TREE

**The worst offender by volume is `tinybendygrad/uop/ops.bend` — 3 916 prose lines of
7 705 LOC, 50.8 % — and this unit was told not to touch `tinybendygrad/*.bend`.** Of
the 70 files my redundancy ranker marked editable, **69 are `.bend` and one is `.py`**
(`.agents/slop/e2epy/diff.py`). The redundancy is real, and it is almost entirely
outside the surface I may edit. Four independent instruments agree:

| instrument | population | answer |
|---|---|---|
| `redundancy.py` | 70 editable files scoring ≥1 | max score **7**, and that file is `gates/gatekit.py` — **on my do-not-touch list** |
| `redundancy.py`, load-bearing filter **removed** | 104 files | top rises to 342, **every addition is `.bend`** — the filter was not hiding `.py` fat |
| `signature.py` | 823 tracked `.py` | **1** hit, and it is a **false positive**: `nv.fenc(s, x) = shln(x, s)` states the identity the signature does not carry |
| `language.py` | 5 493 comment blocks | **13**, none of which reads as language explanation |
| `paste.py` | 823 tracked `.py` | **6 real pastes** → **0** after §3 |

**Conclusion, stated plainly: there was very little left to remove, and what remained in
the editable `.py` surface was 8 comment lines.** I am reporting that rather than
manufacturing a bigger number.

---

## 3. WHAT I REDUCED — 3 files, before and after, with the survivors quoted

Every edit was a **byte-identical or provably-superset duplicate**. No number, SHA,
path, verdict token (`PASS`/`FAIL`/`REFUSED`/`SKIP`/`DEAD`/`ABSENT`/`EXCUSED`/
`WITHIN-LIMITS`) or `TODO` was touched — none of the removed lines carried one.

### 3.1 `.agents/slop/gatecensus/run.py` — a pure paste, 3 lines

Lines 88-90 and 91-93 were **byte-identical**, with nothing appended to the second.
Deleted 91-93.

```
310 -> 307 non-blank LOC;  80 -> 77 prose lines
```
Load-bearing text immediately below the deletion, still present:
```
:92  # WIDENED AFTER A MEASURED FALSE NEGATIVE, NOT ON THEORY. `arena-census.py` prints
:93  #   `SAFE 172  LATENT 1061  DEFECT 0`
```

### 3.2 `.agents/slop/e2epy/diff.py` — a paste whose second copy was appended to, 3 lines

Lines 124-126 repeated at 127-129, and the second copy had **one extra sentence**
appended. So the surviving copy is a strict **superset** and deleting the first is
provably lossless.

```
277 -> 274 non-blank LOC;  81 -> 78 prose lines
```
Both halves of the surviving comment:
```
:125  # the other is its own outcome: a gate that lost a stage has lost reproducibility without saying
:126  # so, and a byte diff alone would bury that. Matched blocks are compared IN ORDER, because the
:128  # CANON IS APPLIED HERE TOO, not only to the byte comparison below. The stage blocks are split
```

### 3.3 `.agents/slop/nv-oracle.py` — a shared first line with TWO DIFFERENT continuations, 2 lines

The one edit that is a **judgement**, so it is flagged as one. Both copies opened with
the same sentence and then said different things. I kept **one** copy of the shared
opening and **both** claims:

```
1030 -> 1028 non-blank LOC;  334 -> 332 prose lines
```
```
:830  # the port numbers from 0 and the oracle does too; what is claimed is the COUNT of
:831  # advances, and a MISS advances it while a HIT does not.  THE CLAIM WITH TEETH: a HIT
:832  # neither appends an id nor advances the counter.
```

### 3.4 Proof that no CODE changed

Not asserted — measured, on HEAD blobs vs the working copy:

| file | non-comment token stream | `ast.dump` | non-blank LOC |
|---|---|---|---|
| `gatecensus/run.py` | **identical** | **identical** | 310 → 307 |
| `e2epy/diff.py` | **identical** | **identical** | 277 → 274 |
| `nv-oracle.py` | **identical** | **identical** | 1030 → 1028 |

All three `py_compile` rc=0.

### 3.5 The ratio, over a population that did NOT move

The tree moved under me — tracked blobs went **4 529 → 4 615** because other units
committed during this run, so a tree-wide before/after is confounded and I will not
quote one as if it were clean. Instead, **the same 1 081 files**, with my 8 deleted
comment lines added back:

```
BEFORE  LOC 402027 | prose 169613 | 42.19% of LOC
AFTER   LOC 402019 | prose 169605 | 42.19% of LOC
                 −0.001 percentage points
```

The honest reading: **the ratio did not meaningfully fall, and it should not have.** The
8 lines were 0.005 % of a 169 613-line prose corpus. A unit that reported a large ratio
drop here would have had to delete evidence. The corpus is dense because it is the
record; **the win is that it is now 6 pastes cleaner and provably has no paraphrased
copy left, not that it is 3 % shorter.**

---

## 4. WHAT I DID NOT TOUCH, AND WHY

- **`tinybendygrad/*.bend` — 69 of the 70 redundant files, including the worst offender
  in the tree (`uop/ops.bend`, 3 916 prose lines) and the highest redundancy score
  (342, `runtime/ops_amd.bend`).** Out of scope by instruction. **This is where the next
  unit's work is.**
- **The six files I was told not to touch**, and I did not: `checks/no-txt.py`,
  `checks/differ.py`, `gates/gatekit.py`, `gates/gate-surface.py`,
  `checks/substrate-id.py`, `.agents/slop/SUBJECTS.rows`. Three of them carry another
  unit's uncommitted work (+451 lines) — not mine.
- **`.agents/slop/` unit reports and evidence.** `ga-green-87.bend` scores **29** and
  `argowner/fold.MINE.bend` scores 25, but `ga-green-87.bend` is a **snapshot of
  `tinybendygrad/renderer/amd/generate.bend` at a revision** — editing it destroys the
  record of what that file looked like. `.agents/slop/nvdup/nv-oracle-PREFIX.py` carries
  the same duplication as `nv-oracle.py` and I left it: it is a named experiment
  (`PREFIX`), and the twin is its evidence.
- **Shadow copies**, reported and not edited: `.agents/slop/{strays,argowner,rf2root,
  portzz,corpuswire,census7,figure2/plant,…}` — **22 files, redundancy sum 1 828**,
  almost all of it inside `.agents/slop/strays/working/tinybendygrad/**`, which is a
  copy of the port. Trimming a copy does not change the port.
- **`gates/tn_{add_sub,and_or_xor,fdiv_mod,mul,pow}-gate.py` — 10 of the 17 remaining
  `paste.py` hits.** FALSE POSITIVES, and I want the reason on the record: the repeated
  line is **each distinct `ROWS` entry's own claim**. `"the input still has its original
  op."` annotates `add_does_not_mutate_input`, `radd_does_not_mutate_input`,
  `sub_does_not_mutate_input` and `rsub_does_not_mutate_input` — four different rows.
  Deleting three would leave three rows undocumented. **Here the repetition IS the
  documentation.**
- **`.agents/slop/rebase-gate.py:1980-1981` — `"# 24"` twice.** Also a false positive,
  and a dangerous one: they are **two different numbers that happen to be equal**, on two
  different dict entries. This is why nothing in this unit auto-edits.
- **`.agents/slop/helpers-oracle.py:90-91` — `"# NOT GATED -- see the header"` twice.**
  A per-statement marker on two different `G.time_sum_s +=` lines. Same shape as `ROWS`.
- **Vendored upstream mirrors**: `checks/llama.py:493` carries the brief's target class
  verbatim — `# TODO: this is a hack to deal with spaces. i think the decode is fast
  though, so who cares?` — an unresolved hedge with a `TODO`. **I left it: it is
  upstream tinygrad's own comment and that file is a mirror.** A mirror whose comments
  have been edited is no longer a mirror. (`checks/cli.py` IS byte-identical to
  `tinygrad/viz/cli.py`; only **1 of 66** `checks/*.py` is a provable in-tree verbatim
  copy, so the other two rest on reading them, and I say so rather than measuring it.)

---

## 5. GATES, verified after every edit

```
checks/no-txt.py              rc=0                        (want 0)
checks/nl-gate.py             rc=0   AGREE 205/205        (want 0, agree 205/205)
checks/nl-gate.py --selftest  rc=3   REFUSED              (want 3)
.agents/slop/concise/plant.py rc=0   13 of 13 lanes PASS  (my own control)
```

`nl-gate.py --selftest` refuses because `checks/nl-port-post.txt` is swept and
unrecoverable — that is its correct verdict, unchanged by me.

## 6. THE INSTRUMENTS LEFT BEHIND

| file | what it decides | how it is falsified |
|---|---|---|
| `census.py` | prose ratio, per file and total | `selftest.py` CHECK 1 (vs `grep`) and CHECK 2 (vs `ast`) |
| `selftest.py` | `census.py` is not lying | cross-counts two independent tools |
| `paraphrase.py` | exact repeats, paraphrase pairs, hedges | load-bearing filter is on by default |
| `redundancy.py` | ranks files by repetition, not volume | re-run with the filter off; `.py` does not rise |
| `signature.py` | docstrings that restate the signature | density + coverage + length, planted |
| `language.py` | prose explaining the language | needs a positive `MECHANISM` clause, not just a negative |
| `paste.py` | byte-identical duplicated comment blocks | distinguishes a directive from prose from a ruler |
| `plant.py` | **13 controls, 5 instruments, 0 FAIL** | every lane has a planted POSITIVE *and* a load-bearing NEGATIVE |

**`plant.py` exits 5 if any lane emits no row, and 3 if a precondition is absent.**
A detector that finds nothing must be proven *blind*, not *right* — §0.2, §0.3 and §0.5
are all cases where mine was blind and only a control said so.
