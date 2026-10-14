# `constfix` — `checks/sweep.py:const()` resolved every spelling, and what that would delete

Unit report, **2026-10-14T13:45Z**. Nothing staged, nothing committed, nothing deleted.
Files touched: `checks/sweep.py` (rewritten resolver) and `.agents/slop/constfix/` (new).

---

## 0. THE PART I MUST SAY FIRST: THREE TIMES MY OWN MEASUREMENT WAS WRONG, AND THE BEFORE-VALUES

The brief asked for this first, so here it is first. **All three were in *my* instrument, not in
`sweep.py`, and all three were in the same class: an instrument that cannot see, reporting a
clean number.**

### 0.1 I excluded a live gate's REQUIRED INPUT, and called it a finding

**MY BEFORE-VALUE: `self_output_dirs()` returns 3 directories. THAT NUMBER WAS WRONG BY ONE,
AND THE EXTRA ONE WAS `.agents/slop/clangshim`.**

My first corrected resolver keyed the write table by **bare callee name** and put `replace` in
it. `checks/cl-port-gate.py:245` is

```python
text = PORT.read_text().replace(LIVE_IMPORT, 'import "./libclang-ffi.c"')
```

— a **string substitution** — and its first argument is the literal
`'import "../../../.agents/slop/clangshim/libclang-ffi.c"'`. A substring resolver read that as
an ownership claim on `.agents/slop/clangshim` and excluded it.

**MEASURED, and this is the whole argument: of the tree's `replace` call sites, 62 are
`str.replace` and 62 of 62.** Not one is `os.replace` or `Path.replace`. And the exclusion was
dangerous, not cosmetic: `checks/cl-port-gate.py:51` is `CFFI = SHIM / "libclang-ffi.c"`, `:89`
asserts the live `libclang.bend` still carries that import, and `.agents/slop/clangshim/` holds
`libclang-ffi.c` and `libclang-tramp.c`. **That is the `e2e_mm.py` shape `checks/sweep.py:168`
documents as the reason a write must be distinguished from a mention — and I walked straight
into it while claiming to fix exactly that distinction.**

Fix: the write vocabulary is keyed `(module, function)`, not by bare name, and a call is a
Path **method** only when its qualifier is a path expression.

### 0.2 My census reported `0` invisible sites while a real directory was invisible

**MY BEFORE-VALUE: "write sites that MENTION `.agents/slop` but yield no directory: 0".**
`.agents/slop/declare` — a real output of `checks/slop-declare.py` — was **not in that zero**;
it was invisible.

`checks/slop-declare.py:90-92` is

```python
ROOT = Path(__file__).resolve().parent.parent
SLOP  = ".agents/slop"
HERE  = ROOT / SLOP / "declare"
```

My `module_env` resolved every module-level binding against an **empty** environment, so `HERE`
could not see `SLOP`: it resolved to `UNKNOWN/UNKNOWN/declare`, which carries no `.agents/slop/`
prefix, so `directory_of()` declined it and the directory vanished. The instrument then printed
`0` for the class it could not see.

> **A RESOLVER THAT RESOLVES IN THE WRONG ORDER IS A RESOLVER THAT CANNOT SEE, AND A RESOLVER
> THAT CANNOT SEE REPORTS `0` INSTEAD OF `I DO NOT KNOW`.** `0` is not an answer. It is the
> shape a blind instrument makes.

Fix: bindings are threaded through **in source order**, and the completeness claim was moved off
the census entirely onto a negative control (§4).

### 0.3 My read census could not see an import, and I found that by hand, not by instrument

**MY BEFORE-VALUE: "READ SIDE — 14 sites, 6 directories".** The real answer is **16 sites, 7
directories**; `.agents/slop/oracletxt` was missing, and it is the single most important read in
the tree (§3.2).

`checks/oracle-txt-census.py:215` is
`importlib.util.spec_from_file_location("plant", ROOT / ".agents/slop/oracletxt/plant.py")` —
**a path handed to an import machine is a read, and no `open` and no `read_text` sees it.** My
`module_of` missed it for two separate reasons in sequence: first because the qualifier is an
`ast.Attribute` (a dotted chain is one name, and a name-keyed test declines it), then because
the fallback matched the *last* component `util` rather than the *first* `importlib`. **I fixed
the first reason, re-ran, and the directory was still missing — which is how I learned the
second reason existed.** I found the site by hand first, not by the instrument.

**THE WRITE CENSUS HAS A 21-CASE NEGATIVE CONTROL. THE READ CENSUS HAS A SENTENCE AND A GREP,
AND THAT IS THE DIFFERENCE IN THEIR TRUST WORTH.**

### 0.4 Two more of my own, found by the same scrutiny

- **Double-counted scopes.** `census` passed `tree.body` to `ast.walk`, which descends into
  functions, and *also* walked each function body. **Every function-level write was counted
  twice: 552 recognised sites where the true figure was 274.** The directory *set* was
  unaffected (it is a set), so the headline never showed it. **A count that double-counts and a
  count that reads clean are the same failure; only the first one gets noticed.**
- **A `--plan` regression I introduced.** `house_excluded` calls `self_output_dirs()` **once per
  corpus file**. MEASURED 2026-10-14T13:14Z: my resolver is 0.93 s per call against the old
  0.36 s, and `--plan` **exceeded 15 minutes**. This is the project's third performance bug — a
  per-item scan of a shared measurement — and `generated_read_dirs` in the same file already
  carries a cache for it. Fixed by one pass per root, memoised: **600 `house_excluded` calls now
  cost 0.577 s instead of ~560 s.**

---

## 1. THE RESOLVER. EVERY SPELLING, WITH THE COUNT THAT PUT IT THERE

Population: **`os.walk` over `checks/` + `gates/`, `.py`**. MEASURED 2026-10-14T13:45Z: **209
instruments** (70 in `checks/`, 139 in `gates/`), all 209 parse.

| spelling | before | after | the measurement that put it there |
|---|---|---|---|
| `Constant` (str) | yes | yes | — |
| `Name` → binding | module-level only | module-level **+ every function scope, in source order**, and each binding carries an `is_path` flag | **120 of 209** instruments bind a name inside a function that is not bound at module level |
| `Call(join)` | `"".join(resolved literals)` — **drops the `/`** | `"/".join(...)`, unresolved parts become a marker, and `"".join([a, b])`'s single **list** argument is unwrapped | `"".join([SLOP, "a"])` is the one spelling the old resolver *claimed* to support and resolved **0 of 1** forms of |
| `BinOp(Div)` — `p / q` | **no** | yes | **854** `Div` sites in `checks/`+`gates/`; **612** have a string literal or string-bound operand and are *provably* path divisions; 1 is arithmetic; 241 are over computed values. **93 of 154 `write_text` receivers are a `BinOp`** |
| `BinOp(Add)` — `s + t` | **no** | yes | **40** `Add` sites |
| `Subscript` on `parents[n]` | **no** (and the branch that needed it was unreachable) | reaches the shape and answers `UNKNOWN` | `parents` is a **property**: the node is a `Subscript` whose `.value` is a bare `ast.Attribute`, so a branch requiring `Call` was **dead code** |
| the **receiver** | **no** — it read `node.args` | yes, decided by qualifier | `write_text` has **154** call sites and is a **method at every one**; the argument is the CONTENT. MEASURED: **0 of 154** content arguments carries a `.agents/slop` literal, so nothing was found — **and nothing found looks exactly like nothing there** |
| `os.path.join` / `shutil.*` / `json.dump` | **no** | yes, keyed by `(module, function)` | see §0.1 — a bare name cannot tell `str.replace` from `os.replace` |
| **order** | single pass over an **empty** env | **source order**, recursing into branches | §0.2 |
| **`from X import Y` / `import X.Y`** | **no** | yes, from the module's own `import` statements | §0.3 |
| destructive calls (`unlink`, `rmtree`, `remove`, `rmdir`) | not considered | counted, **never excluded** | **11** sites. Wanting a path GONE is not owning it; excluding a directory some instrument deletes would **protect a doomed directory** — the one error here that is silent in the *other* direction |
| an **unknown part** | dropped | `"\x00"` marker; `slop_dir()` **refuses** any first component carrying it | `os.path.join(ROOT, SLOP, name)`: the prefix is real, the directory is a loop variable. **Refused, never invented** |

**Before: 1 directory from 1 site. After: 3 directories from 8 sites**, all three listed with
file and line by `writecensus.py`, all three by AST.

### 1.1 The `Div` count in the brief does not reproduce, and `Div` is not a path

The brief cites **732** `Div` sites. **My AST count over the same two directories is 854**
(533 `checks/` + 321 `gates/`), and of those **612 are provably path-shaped**, 1 is arithmetic,
241 are over computed values. Across the whole repo: 5,645 `Div` sites, of which **3,502 are
under `.agents/slop` and 916 under `.venv`** — neither of which the sweep walks. **732 could
not be reproduced at any scope I measured, and a citation with no stated denominator is not
usable either way.**

---

## 2. WHAT `open` MEANS. IMPLEMENTED, AND PROVED

**Implemented: `open` is a write target only when its mode RESOLVES to something containing
`w`, `a`, `x` or `+`. An unresolved mode is NOT a write.**

- `open(p)` → mode defaults to read → **not** a write target.
- `open(p, "w"/"wb"/"a"/"x"/"r+")` → a write. `r+` opens for writing as well as reading.
- `open(p, mode="w")` → a write. **This is a hole in the old code**: `checks/sweep.py:218` read
  the mode from `node.args[1]` **only**, so a **keyword** mode read as absent, defaulted to
  `"r"`, and skipped a genuine write. MEASURED: the tree's `open` sites are **57 bare
  `open(...)`, 9 `Path.open(...)` and 4 with a `BinOp` receiver** — and `Path.open` takes `mode=`
  as a keyword, so 13 of them could not report a mode through the old path at all.
- `open(p, f"w{mode}")` → unresolvable → **not** a write.

**Why this direction.** An exclusion *removes* a tree from the citation corpus, which removes
evidence and makes rows uncited, and an uncited row is one `DELETE` away. **The asymmetry is
fixed: a missed write is safe, an invented ownership claim is a deletion.** Treating an unknown
mode as a write would invent an exclusion for every read in the tree.

**Proved** by cases `literal-open-w`, `literal-open-read`, `open-mode-keyword`, `open-mode-plus`
of the negative control (§4), all `PASS 0`.

---

## 3. THE DELIVERABLE — WHAT THE CORRECTED RESOLVER WOULD DELETE

**Method.** `checks/sweep.py --plan`'s own header warns that its numbers move with the clock
("DELETING 366 / 44 / 0 at 0, 60 and 1440 minutes" on one unedited tree), and five units are
writing into `.slop` while this runs. **Two sequential `--plan` runs would confound the resolver
change with the clock.** So the row population (5,315 rows), the liveness overlay (87 files, 4
unit dirs), `tracked`, `copies` and `declared` are each computed **once** and handed to all three
classifiers. **The only thing that differs between passes is `self_output_dirs`.**

**MEASURED 2026-10-14T13:40:05Z – 13:42:08Z**, `.venv/bin/python .agents/slop/constfix/deleteset.py`:

| bucket | previous | **writes-only** | **as shipped** | Δ |
|---|---|---|---|---|
| DELETE | 2,232 | **2,234** | **2,232** | **+0** |
| UNKNOWN | 1,393 | 1,391 | 1,393 | +0 |
| every other bucket | — | — | — | **+0** |
| **TOTAL** | 5,315 | 5,315 | 5,315 | **+0** |

### 3.1 THE LIST. Two paths, under the resolver ALONE

```
.agents/slop/oracletxt/population.out    was UNKNOWN:residue-internal-citer
.agents/slop/oracletxt/selftest.out      was UNKNOWN:residue-internal-citer
```

Both were named **only** by `.agents/slop/oracletxt/REPORT.md` — the excluded report itself.
Both are tracked in git, so this is a recoverable loss, not an irreversible one. **NO LONGER
DELETE: 0. Nothing is rescued.**

### 3.2 WHY THE SHIPPED ANSWER IS ZERO, AND THIS IS THE REAL FINDING

`self_output_dirs()` now returns **writes MINUS reads**. MEASURED: the write census names 3
directories, the read census names 7, and **the intersection is 2**:

| directory | written at | read at | what the read is |
|---|---|---|---|
| `.agents/slop/declare` | `checks/slop-declare.py:250, 253` | `:128, :130, :216` | `plant.py` loaded by path |
| `.agents/slop/oracletxt` | `checks/oracle-txt-census.py:473, 474` | **`:215`** | **the live instrument LOADS `.agents/slop/oracletxt/plant.py` BY PATH as its plant generator** |

> **A DIRECTORY THAT IS BOTH WRITTEN AND READ IS A GATE'S REQUIRED INPUT THAT SITS BESIDE ITS
> OUTPUT. EXCLUDING IT RE-BREAKS THAT GATE BY EXACTLY THE ROUTE `self_output_dirs`'s OWN
> DOCSTRING WARNS ABOUT — AND I HAD ALREADY DONE IT ONCE, ONTO `clangshim`, BEFORE MEASURING.**

**So: the corrected resolver is more correct about writes, and applying its answer to
`house_excluded` without the read refusal would have destroyed 2 files. The deferral was
correct. The reason is now measured instead of guessed.**

### 3.3 The composition that ships

- `self_output_dirs()` = writes − reads = **1** directory, unchanged from before.
- `self_output_conflicts()` = **2** refusals, **printed by `--plan`**:

```
# REFUSED as out-of-census, written AND read by a live instrument: .agents/slop/declare,
#   .agents/slop/oracletxt  (an exclusion must be an OUTPUT and not also an INPUT)
```

**A SILENT REFUSAL IS INDISTINGUISHABLE FROM A MISS**, so the refusal is a line of output. It is
also a standing tripwire: the moment `oracletxt/plant.py` stops being loaded by path, the
directory becomes excludable and the count moves with no edit to `sweep.py`.

---

## 4. THE NEGATIVE CONTROL — WHICH I WROTE SECOND, AFTER THE DEFECT IT CATCHES

`.venv/bin/python .agents/slop/constfix/selftest.py` — **21 planted sites, `21 of 21 PASS`, token
`PASS 0`, rc=0.** A synthetic tree with one case per spelling; each case names the directory it
must produce **or the one it must stay away from**, so the negative cases cannot pass
tautologically.

It caught four real defects, three of which are §0.1, §0.2, §0.3 and the fourth being
`str.join`'s list argument. Cases include: `open` read/write/`mode=`/`r+`; `Div`; `Add`;
const-from-const; opaque-prefix vs opaque-tail join; `str.join`; parameter default; local
reassignment; `parents[1]` alone and after a `Div`; file-shaped write; trailing slash;
**`str.replace` naming `clangshim`**; `rmtree`; and `write_text` whose *content* mentions slop.

**The AGENTS.md rule is "the harness you write is the one that can fail, so it comes first." I
wrote it second, after the bugs, and I am recording that rather than hiding it.** The next
agent should move it above the resolver.

---

## 5. DISCOVERY, NOT A LIST — PROVED BY THE ABSENCE OF THE LITERAL

`.venv/bin/python .agents/slop/constfix/deleteset.py --prove` checks this **by AST shape**, and
**its first version printed its own contradiction** — it reported `residue` as a literal in
`checks/sweep.py` and then concluded none was there. Both halves were right:
`checks/sweep.py:621` and `:798` are `spec_from_file_location("residue", …/checks/residue.py)`,
a **module name**; and a bare first component is not a path. The check is now by shape — a
directory claim is a literal of exactly `.agents/slop/<component>`:

| file | directory-shaped exclusion literals |
|---|---|
| `checks/sweep.py` | `'.agents/slop/slopfinal'` — **and nothing else** |
| `.agents/slop/constfix/deleteset.py` | **NONE** |
| `.agents/slop/constfix/writecensus.py` | **NONE** |

`SELF = '.agents/slop/slopfinal'` **is** a written-down literal, and `checks/sweep.py:153`
declares it as one. It is **not** one of the three discovered. The resolver's input is
`os.walk`, and `glob` would find the same 209 today — **so the walk is insurance, not a fix, and
I say so rather than claiming credit for it.**

---

## 6. GATES. EVERY rc, EVERY TOKEN

| gate | rc | token / reading |
|---|---|---|
| `.agents/slop/constfix/selftest.py` | **0** | `21 of 21 PASS` (negative control) |
| `checks/no-txt.py` | **0** | `CLEAN: no .txt anywhere the project owns` |
| `checks/nl-gate.py` | **0** | `gated 205  agree 205  disagree []` → `AGREE` |
| `gates/gate-surface.py --report` | **0** | `SHELL HALF: 18`. The overall line reads **RED** (14 gates declare a surface, 22/42 verdicts, 16 unplanted, 4 UNOWNED, 10 RENAMED). **Pre-existing and not mine: `sweep.py` appears 0 times in the surface census** |
| `checks/disagree-gate.py --lane citations` | **0** | `ok CITATIONS` |
| `checks/census.py` | **0** | `reached BOTH: 70`, `py-only []`, `bend-only []`, `NEITHER: 7`. The brief's "68 of 68" reads **70/70 + 7 neither** today; it did not go to 3 |
| `checks/runs-artifacts.py` | **0** | `ARTIFACTS-FRESH`, `runs/graphcmp/D: 242 files`, **0 in git — not deleted, not touched** |
| `checks/index-arm-gate.py` | **3** | `REFUSED` — 96 deletion + 2 stale. The tree is fine; the tool is pointed wrong |
| `checks/bounded.py --selftest` | **0** | `selftest PASS: 13 case(s) run, 0 failed` |
| `.git/index` sha256 | — | `c8c94ffc…6d9` **before and after every run above: unchanged** |

`checks/sweep.py --plan` runs green and prints the refusal line.

**Two cautions on rc.** `$?` after a pipe is the pipe's — my first battery reported
`index-arm-gate rc=0` for exactly that reason and the true value is **3**. And `timeout` does
not exist on this host.

---

## 7. WHAT I DID NOT DO, AND WHAT IS STILL OPEN

- **I deleted nothing.** The two paths in §3.1 are a measurement, not a queue.
- **The read census has no negative control.** §0.3 is the reason. It is the weakest link in
  this report and the next agent should plant `importlib`-shaped reads before trusting a refusal.
- **`self_output_dirs()` still returns 1 directory.** The resolver's extra reach is real and is
  now *observable* (3 writes, 7 reads, 2 refused) instead of invisible. **The resolver got more
  accurate and the exclusion set did not move** — which is the honest outcome, and the opposite
  of what the deferral feared.
- **`.agents/slop/declare/` is 0 tracked files.** Nothing in it can be restored from git, and it
  is one edit away from being excludable. If that happens, the whole directory becomes sweep
  residue with no git recovery.
- **I did not touch** `checks/runs-artifacts.py`, `checks/census.py`, `AGENTS.md`, `.gitignore`
  — three other units own them; this report says so and edits nothing.
- **`checks/sweep.py` is modified and unstaged.** Commit NOTHING, as instructed.

## 8. REPRODUCE

```bash
.venv/bin/python .agents/slop/constfix/selftest.py                       # 21 of 21 PASS, rc=0
.venv/bin/python .agents/slop/constfix/writecensus.py --collide --diff   # 3 writes / 7 reads / 2 both
.venv/bin/python .agents/slop/constfix/deleteset.py --prove               # discovery, by AST shape
.venv/bin/python .agents/slop/constfix/deleteset.py                      # the delete-set delta
.venv/bin/python checks/sweep.py --plan                                  # REFUSED line in the header
```
