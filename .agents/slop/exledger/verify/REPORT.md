# AUDIT of `.agents/slop/exledger/examples.manifest.rows`

**READ-ONLY. Nothing outside `.agents/slop/exledger/verify/` was written. No commit.**

| | |
|---|---|
| population measured against | HEAD **`80d329a33`**, read `2026-10-19 03:46:27Z` |
| this report written at | `2026-10-19 03:55:00Z`, HEAD **`6dab8e95d80f`** |
| HEAD drift | the tree moved under the audit; the population did **not** — `git ls-tree -r HEAD -- examples extra/models extra/datasets` is **299** at both commits, byte-identical path set (`diff` empty) |
| population denominator | **299** rows, from `git ls-tree -r HEAD` — **not** `git ls-files` (the index) |
| machine | `vm.loadavg` 8.40 at start, 6.52 at end; one process at a time, nothing backgrounded, nothing compiled, no `bend`, nothing under `gates/` |
| ledger under audit | generated 06:45 local, `299` data rows, sha unchanged by me |

**Concurrency note.** Other units were writing to this tree throughout the audit (`gates/*.py`,
`checks/e2e*`, `.ruff_cache` all changed between 03:46 and 03:55). None of it is mine — every
command I issued was a read, and every write landed in this directory. The population paths did not
drift, which is why the findings still hold at both HEADs.

`upstream` is a real remote here (`https://github.com/tinygrad/tinygrad.git`, `refs/remotes/upstream/master`
= **`002630241`**), so "is this file actually upstream?" was answerable rather than assumed.

---

## VERDICT

| claim | result |
|---|---|
| population is 299 upstream files | **FALSE** — 299 rows, **6 of them are not upstream** |
| `ALREADY_BEND` "ships as `.bend` upstream" | **FALSE** — upstream ships **0** `.bend` under `examples/`/`extra/` |
| no two rows share a `ported_path` | **FALSE** — **1 collision**, 2 upstream rows → 1 destination |
| `PORT` = 88 | **87** by two independent methods; **1 false positive** |
| regex false negatives | **NONE FOUND** — every named shape is 0 hits over all 299 |
| no destination outside `tinybendygrad/` | **TRUE** — 0 of 299 |
| every `.py` PORT lands on a `.bend` | **TRUE** — 88 of 88 |
| README "19,104 of 44,135 LOC is work" | **TRUE** — PORT alone = 19,104, total = 44,135 |
| README "117 of the 119 `.sh` need no API; the other 2 do" | **FALSE** — **0 of 119** reach the API |
| README "24 of the 26 `.md` reference it; 2 do not" | **FALSE** — **25 of 26** name it; 1 does not |

---

## 1. FALSE NEGATIVES OF THE REGEX

The regex is `\b(from|import)\s+tinygrad|\btinygrad\.`. I attacked it two ways.

### 1a. The direct reach, by AST — 87 of 299, and the ledger agrees on 87 of 88

Every `.py` in the population was `ast.parse`d (0 unparseable) and walked for `Import`/`ImportFrom`
nodes whose module root is `tinygrad`, plus every `Name` bound by such an import. This is a different
mechanism from the regex and it does not use it.

- `87` files reach the API. **All 87 are `.py`.**
- The ledger's `PORT` set is **87 `.py` + 1 `.js`**.
- **`API \ PORT` = 0 files. `PORT \ API` = 1 file** (the false positive, §2a).

Triangulation, a third and blunter rule — *"`py` file with a tinygrad `Import`/`ImportFrom` node"* —
also returns **87**. Three routes, one number.

### 1b. Every shape the brief named — 0 hits

| shape | hits over all 299 |
|---|---:|
| `from`/`import` split across a line continuation | **0** |
| `__import__('tinygrad…')` | **0** |
| `import_module('tinygrad…')` | **0** |
| `getattr(__import__(…))` | **0** |
| `python -c '…tinygrad…'` in shell | **0** |
| JS `require()`/`import` of a tinygrad module | **0** |
| a quoted tinygrad JS runtime path (`ops_webgpu`, `runtime/ops_`, `renderer/wgsl`) | **0** |
| `exec(`/`eval(` of a constructed name | **13, all irrelevant** — every one is `RegExp.prototype.exec` inside vendored `highlight.min.js` / `marked.min.js`. Regex execution, not code execution. |

**A negative result is a result.** The regex's feared false negatives are not present in this population.

### 1c. The real false-negative class is TRANSITIVE, and it is 101 files

`examples/mlperf/model_train.py` is a `PORT` row. **101 `.sh` files execute it** and none of them
names tinygrad in its own bytes:

```
examples/mlperf/training_submission_v4.0/tinycorp/benchmarks/resnet/implementations/tinybox_green/dev_beam.sh:13:
    python3 examples/mlperf/model_train.py
```

- **101 of the 119 `.sh` files** (85%) reach the tinygrad API by calling a `PORT` row.
- Single distinct dependency: `examples/mlperf/model_train.py`.
- Comment-stripped on both sides; all 101 are `VERBATIM_COPY`, all `reason='shell, no API'`.

**I am not calling these misfiled.** A shell script that invokes a Python file needs no edit of its
own; copying its bytes is correct. The defect is the **schema**: `reason` is a statement about a
file's own text, and the ledger is flat, so a unit working a `VERBATIM_COPY` row is never told the
script stays dead until a `PORT` row lands. That is a missing dependency edge, not a wrong byte.

---

## 2. FALSE POSITIVES

### 2a. One, and it is the whole delta between 88 and 87

```
examples/tinychat/tinychat-browser/index.js
  ledger_disposition  PORT
  reason              'JS runtime, tinygrad-linked'
  correct_disposition MINIMAL        (the ledger's own definition: "prose or js that *names* the API")
```

The file is 927 lines and contains the string `tinygrad` **exactly once**, on line 9, in a comment:

```js
 9: // MODEL_BASE_URL is where the weights are hosted, WEBGPU_EXPORT is the JS-wrapped WebGPU code exported from tinygrad
```

Its only dynamic import is `await import('./tiktoken.js')` (a vendored asset). It loads `./net.js`,
which is a tinygrad-*produced artifact*, not the tinygrad API. It calls nothing of tinygrad.

**Adversarial note against myself:** my first classifier run returned **88 and agreed with the
ledger**, because my own dynamic-import pattern `\bfrom\s+tinygrad\b` matched the English words
"exported **from tinygrad**" inside that `//` comment. I only found it by insisting the two methods
agree file-for-file rather than in aggregate. The bug was mine; the finding is the ledger's.

### 2b. 28 rows whose stated `reason` is contradicted by their own bytes

`reason='no tinygrad API'` on files that contain the string `tinygrad`:

- **20 `mlperf/**/systems/tinybox_*.json`** — every one carries
  `"framework": "tinygrad, commit 0e8aa0e2886bf9a2d3ce093bce87305e182e6d4a"` (or a branch name).
  The string is there; the reason denies it.
- **3 upstream `examples/webgpu/*/index.html`** — `<title>tinygrad has WebGPU</title>`,
  `<title>YOLOv8 tinygrad WebGPU</title>`. The ledger's `MINIMAL` is "prose … that *names* the API",
  and `.html` is prose, yet all 24 `.md` that name the API are `MINIMAL` and these 3 are
  `VERBATIM_COPY`. The split is extension-driven and the README never says so.
- **5 more are the port-authored files of §3** and are counted there, not here.

The dispositions themselves are defensible — a JSON submission manifest needs no port. The
**`reason` strings are not**, and `reason` is the column a reader trusts.

---

## 3. THE POPULATION IS CONTAMINATED — 6 of 299 rows are this project's own output

This is the finding that would cost a unit a day.

```
$ git ls-tree -r upstream/master --name-only -- examples extra/models extra/datasets | wc -l
293
$ git ls-tree -r upstream/master --name-only -- examples extra/models extra/datasets | wc -l   # HEAD
299
```

Set difference, **6 paths present in HEAD and absent from `upstream/master`**:

```
examples/beautiful_mnist.bend
examples/beautiful_mnist.ts
examples/webgpu/mnist/README.md
examples/webgpu/mnist/index.html
examples/webgpu/mnist/mnist-webgpu.js
examples/webgpu/mnist/oracle.json
```

`upstream/master`'s `examples/webgpu/` contains **5 paths and no `mnist/` directory at all**. And
`git ls-tree -r upstream/master -- examples extra | grep -Ec '\.(bend|ts)$'` = **0** — upstream ships
neither a `.bend` nor a `.ts`.

Three consequences, each quoted:

1. **`ALREADY_BEND` (n=1) asserts something false.** Its `reason` is `'shipped as .bend upstream'`.
   `examples/beautiful_mnist.bend` was written by this project; its own comments cite the port
   (`#   W1  conv2d -- \`tinygrad/mixin/op.py:1562\``. CLOSED: THE SHAPE.`). There is no upstream
   `.bend` for it to have shipped as.
2. **`beautiful_mnist.bend`'s `ported_path` is `tinybendygrad/examples/beautiful_mnist.bend`** — the
   row asks for a file to be written at a path that is, in this repo, the same artifact.
3. **The README's "population **`299`** tracked files"** is 293 upstream + 6 port artifacts. The
   denominator is right for the ledger and wrong for the word *upstream*.

---

## 4. `ported_path` COLLISIONS — one, and it is real

299 rows → **298 distinct destinations**. The collision:

```
tinybendygrad/examples/beautiful_mnist.bend   <- 2 upstream rows
    examples/beautiful_mnist.bend   [ALREADY_BEND]  reason='shipped as .bend upstream'
    examples/beautiful_mnist.py     [PORT]         reason='python model/harness'
```

Two upstream paths, one destination. Whichever unit takes the `PORT` row writes the same file the
`ALREADY_BEND` row already names, and the ledger gives no way to tell that it is not a fresh file.
It is a consequence of §3: one of the two rows should not exist.

**These two checks passed and are worth recording as passing:**

- **0 of 299** destinations land outside `tinybendygrad/`.
- **88 of 88** `.py` `PORT` rows land on a `.bend` destination. No `.py` silently becomes `.py`.

---

## 5. THE README'S OWN THREE NUMERIC CLAIMS

| claim | measured | |
|---|---|---|
| "LOC that is actually work: **19,104 of 44,135**" | `PORT` = 19,104; all rows = 44,135 | **holds** |
| "**117** of the **119** `.sh` files need no tinygrad API; the other **2** do" | **0 of 119** reach the API. The 2 are `profile.sh`, `MINIMAL_COPY`, `reason='shell, names the API'` | **false** — and the README's own table defines `MINIMAL_COPY` as "reach **no** API" |
| "**24** of the **26** `.md` reference it; 2 do not" | **25 of 26** name it. The 1 that does not is `examples/tinychat/tinychat-browser/README.md` | **false** |

Both false claims are in the same paragraph, arguing that the classification was measured rather
than guessed. The paragraph's *point* survives — extension alone really would misfile — but the two
numbers offered as its evidence do not.

---

## 6. INDEPENDENT RE-DERIVATION

**My method, stated so it can be disbelieved.** I did not re-run the generator and I did not use its
regex. I read every blob at HEAD (`git cat-file --batch`), then classified each file by mechanism:

- **M1 `API`** — `.py`: `ast.parse`, then any `Import`/`ImportFrom` with module root `tinygrad`, plus
  any `Name` bound by one. Non-`.py`: the string `tinygrad` in **comment-stripped, string-stripped
  executable text**, plus dynamic-import shapes (`__import__`, `import_module`, `require`).
- **M2 `NAME-IN-CODE`** — `tinygrad` in comment-stripped text, no M1 hit.
- **M3 `NONE`** — no occurrence outside comments.

| mechanism | n |
|---|---:|
| M1 `API` | **87** |
| M2 `NAME-IN-CODE` | **51** |
| M3 `NONE` | **161** |
| sum | **299** ✓ |

**I do not reproduce `166/88/24/20/1`.** I reproduce the *PORT* set at **87, not 88**, and the delta
is one named file with one quoted line (§2a). The other four dispositions are not derivable from any
mechanism I can find; they are a **second, unstated rule** keyed on extension (`MINIMAL` = `.md` that
names the API; `VERBATIM_COPY` = everything else). That rule is real and consistent — it just is not
written down, and it is what produces the 3 `.html` rows in §2b. **The headline counts survive only
if you already believe the unstated rule; the 88 does not survive on its own evidence.**

Reconciliation is declined: the ledger says 88, the code says 87, and I am reporting the code.

---

## 7. HOW MUCH I TRUST THE LEDGER NOW

**Split verdict, because the ledger is two things wearing one coat.**

**Trustworthy — use it:**
- **The 87 `.py` `PORT` rows.** Three methods agree file-for-file. Every other `.py` in the population
  is correctly excluded. The regex, on this population, is not the weak link.
- **The destination schema.** 0 escapes from `tinybendygrad/`, 88 of 88 `.py`→`.bend`. It is a sound
  1:1 mirror apart from the single collision in §4.
- **The population *paths*.** Exact against `git ls-tree -r HEAD`, 299 of 299, no duplicates, and
  stable across two different HEADs 9 minutes apart.

**Do not trust — fix before a unit spends a day on it:**
- **"upstream".** 6 of 299 rows are this project's own files. Any reasoning of the form "upstream
  does X, therefore our port must" is unsound on those 6, and `ALREADY_BEND` is a false claim.
- **The `reason` column.** 129 of 299 rows carry a reason their own bytes contradict — 101 because
  the file's need lives in a file it calls, 28 because the file contains the very string the reason
  denies. `reason` reads as a verdict on *need* and is a fact about *bytes*.
- **The README's `.sh` and `.md` counts.** Both false, in the paragraph that argues the numbers were
  measured.
- **`PORT` = 88.** It is 87.

**Bottom line:** the hard part — deciding what actually needs porting — is right, and better than I
expected to find. The bookkeeping around it is not: the population is contaminated, one destination
is claimed twice, one `PORT` is a comment, and the ledger's prose sells its own precision with two
numbers that do not survive contact with the files.

---

### Reproduce

Every number here comes from a script in this directory. No compiling, no `bend`, no network.
Run them in this order — `dump.py` writes `blobs.bin` (4,523,731 B, sha256-stable across runs,
deleted afterwards because it is 4.5 MB of blobs git already holds) and every later script reads it.

```
verify/dump.py       HEAD blobs -> blobs.bin          (299 frames, 4,523,731 bytes)
verify/recon.py      names tinygrad anywhere / regex-blind set
verify/mine.py       M1/M2/M3 by AST + comment-stripped lexical  -> my-verdict.json
verify/crosstab.py   per-file cross-tab + transitive pass         -> cross-tab.rows, transitive.json
verify/dests.py      ported_path collisions / escapes / extension rule
verify/shapes.py     the 10 named false-negative shapes
verify/buckets.py    the README's three claims + every bucket not decided by 'reaches the API'
verify/emit.py       -> misfiles.rows
verify/pop.head.rows / pop.upstream.rows / pop.ledger.rows   the three populations, diffed
```