# `closure` — a key that covers one file where the subject depends on many

Unit `closure`, 2026-10-14. Touched `checks/census.py` and `.agents/slop/closure/` only.
**Staged nothing. Committed nothing.**

Subject: `checks/census.py:100` keys each of 68 cached slots on **two** digests, one of which is
`GENERATOR = {"py": _GRAPH, "bend": G.BEND_PROBE}`. `G.BEND_PROBE` is
`.agents/slop/graphcmp.bend` — **one file** — and that file imports the port.

---

## 0. WHERE MY OWN MEASUREMENT WAS WRONG, FIRST, WITH THE BEFORE-VALUES

Four. The first is the one that matters, because I built the instrument that checks this class
of failure and then committed the class of failure inside it.

**0.1 I wrote "the `P(i..)` citation is not reproducible against this tree." It reproduces
EXACTLY.** Before-value: `grep -o 'P([0-9]*)'` over the 34 cached py row files returned **0
hits**, and from that I concluded in a file header that "the only occurrences of `P(i..)` and
`itertools.count` in the whole subject are the PROSE of that comment." The pattern was wrong: the
row spelling is **`P(i0,` — an `i` prefix**, not a bare digit. After-value, measured:
**37 distinct `P(iN)` values regenerating all 34 graphs in one process, against 4 per process,
with 25 of 34 slots differing** (`alu` → `P(i1,`, `binblob` → `P(i2,`, advancing one per
preceding graph). That is `checks/census.py:220`'s claim, reproduced to the digit, by the probe
written to refute it. **A digit-only pattern found nothing, and "nothing" looked like "there is
nothing to find."** That is the seventh way, redone by hand, in the instrument built to check the
seventh way. What survives of my claim is only the narrower half — `grep -n itertools
.agents/slop/graphcmp.py` really does answer nothing, so the comment **misattributes the
mechanism** even though its outcome and its numbers are right. I corrected both the probe header
and `checks/census.py:220` in place.

**0.2 My AST closure over-counted by 48 of 87 and I did not know which.** Before-value: `87`
files, presented with a confidence the resolver had not earned. Cause: `tinygrad/Tensor.py:8`
reads `from tinygrad.helpers import cpu_profile, suppress_finalizing, disable_gc, VIZ`, where
`VIZ` is the ContextVar **defined at `tinygrad/helpers.py:271`**, and `tinygrad/VIZ/` is a real
package directory on disk. A resolver that treats every from-import NAME as a candidate module
finds a real file and reports a real-looking edge the interpreter never takes.

**0.3 My closure double-counted files, because a path spelling is not a file.** Before-value: the
87 "files" included both `tinygrad/DType.py` and `tinygrad/dtype.py`, both `tinygrad/Device.py`
and `tinygrad/device.py`, both `tinygrad/Tensor.py` and `tinygrad/tensor.py`. **MEASURED: 6 such
pairs, each one inode** on this case-insensitive filesystem. A set keyed by path spelling is not a
set of files, and on Linux — where these are different names — the same code would produce a
different count.

**0.4 My control's verdict logic was inverted, and it printed `UNEXPECTED` on all 14 rows of a
result that was entirely correct.** Before-value: a wall of `<-- UNEXPECTED` over a table whose
real content was "OLD key resolves 1 of 7, NEW key resolves 7 of 7, 0 false positives on 8
outsiders." An alarming instrument over a clean result is the defect this project keeps
cataloguing, and mine did it.

Two smaller ones, for completeness: a **text round-trip was not byte-identity** (my restore used
`"\n".join(t.splitlines()[1:])`, which normalised trailing newlines on 15 mirror files and was
caught *only* by the aggregate check at the end — without it I would have reported
`restored: True` over 15 altered files); and **zsh does not word-split unquoted expansions**, so
`python $g` handed three gates one filename each and I read three `RC=2` that were my quoting.

---

## 1. THE CLOSURE, MEASURED. BOTH LANES. DERIVABLE — BUT NOT BY THE SAME METHOD.

### 1.1 The bend lane: **7 files**, exact, cheap, derivable

`bend`'s imports are **static and total** — `bend --help` reads `--check-only  check the file and
its imports` — so the closure is a fact about the file.

Method: `checks/nvrows-deadrow-gate.py:89 import_closure`, **loaded by path**, never
reimplemented (doctrine 1). It already handles both spellings this tree uses: `import ./x.bend as
Y` relative to the FILE, and `import Base` relative to the PACKAGE ROOT.

```
.agents/slop/graphcmp.bend      tinybendygrad/uop/ops.bend
tinybendygrad/Base.bend        tinybendygrad/uop/render.bend
tinybendygrad/LAWS/spec.bend   tinybendygrad/helpers.bend
tinybendygrad/uop/fold.bend
```

The key covered **1 of 7**. **Zero `.mjs`, zero `.js`** — the closure is 100% `.bend`.

### 1.2 The py lane: the far worse case, and the brief understates it by ~30×

`GENERATOR["py"]` is `.agents/slop/graphcmp.py`, **one file**. That file reaches into `tinygrad/`
— the CPython oracle — at 50 import sites naming **10 distinct modules directly** and, through
them, **69 `.py` files under `tinygrad/`**. The key covers **1 of 87**.

**The exact Python closure is not derivable, and I measured why in both directions:**

| method | count | verdict |
|---|---|---|
| AST walk from `graphcmp.py` | **87** path strings (81 distinct files) | **over-counts** — 48 are edges no import takes |
| `sys.modules` after `load_tinygrad()` | **39** | **under-counts** — imports are lazy and per-graph |
| `tinygrad/` directory walk | **215** with `graphcmp.py` | superset, used |

`sys.modules` under-counts because `graphcmp.py:1155` reaches `line_rewrite` **inside one graph
builder**, so the py lane's closure is a function of *which graph*, and there are 34. A lower
bound is not a key: an under-count serves stale rows silently, which is the one outcome this file
exists to prevent.

### 1.3 Two blind spots in the resolver I adopted, and one I refused to adopt

- **`checks/substrate.py:596`'s `IMPORT` requires an `as` clause.** MEASURED over the 135 port
  `.bend` files: it resolves **342 of 801** import edges. The other **459** have no `as` and are
  **invisible** to it — including all 120 `import Base`. An instrument in this tree computes an
  import graph, finds 342 edges, reports a number, and looks like a working census. Had I used it
  (the obvious "reuse the existing instrument" move) `Base.bend` would have been missing from
  every closure.
- **`import_closure`'s `^import\s+(\S+)` keeps the QUOTES**, and this tree spells **325** lines
  `import "../../../.agents/slop/clangshim/libclang-tramp.c"`. Those resolve to a path containing
  `"` and are dropped **silently**. For `graphcmp.bend`'s closure the drop MEASURED **0**, and
  `checks/census.py` now **prints that 0 every run** (`blind spots 0`) rather than leaving it a
  silence.
- **A basename resolver is fatal here: 5 of the 7 closure basenames are ambiguous**
  (`fold.bend` ×5, `spec.bend` ×3, `graphcmp.bend` ×2, `helpers.bend` ×2, `render.bend` ×2).

---

## 2. WHAT THE KEY SHOULD COVER, AND WHAT IT COSTS

**Decided and landed: one `sha256` over the whole population**, `sorted(relpath<TAB>sha256)`,
joined. Not a per-file list in the row — 215 files × two columns is a table nobody reads, and the
only question a 4-column key row answers is *is this the same set as the set I wrote*. Membership
stays **derivable** (`population()` is a function, not a stored list), so any reader can print
*which* file moved without the gate carrying a second copy of the answer. The **row shape is
unchanged** — `graph<TAB>side<TAB>GEN_SHA<TAB>CACHE_SHA` — so only column 3's meaning moved.

**The asymmetry is the whole answer.** For a language whose imports are static and total, derive
the exact closure (7 files). For one whose imports are lazy and per-call-site, take the superset
(215). Both are named in the gate's own output every run:

```
key py       : sha256 over 215 files (oracle walk, a SUPERSET)   digest 19095fcda5e66acd
key bend     : sha256 over 7 files, blind spots 0                digest e83575c30d07665b
```

### The costs, named

1. **False staleness is now real and I can point at a specific instance.** `uop/render.bend` is in
   the closure and `graphcmp.bend` references alias `R` **exactly once** (against `O`'s 2,307).
   An edit there moves the key and **cannot** move a row. That is a corpus-wide stale bought for
   nothing — the failure mode the brief asked me to name, measured rather than asserted.
2. **The port is the cheap side and the oracle is the expensive side.** 7 of 135 `.bend` files
   (5.2%) — near-exact. But the py walk is **215 files where ≥39 are eager-loaded**, so up to
   ~176 files of over-inclusion: every `tinygrad` touch re-emits 34 py slots. That is bounded
   (the oracle is pinned and moves rarely) and it is the *safe* direction, but it is not free.
3. **The bend compiler is outside the closure and cannot be in it.** `bin/bend` is a 32-line shim
   that `exec bun references/bend/bend2/main.ts`, and `references/` is **gitignored**. The rows
   are emitted by a compiler this key cannot see. A `bend update` changes every bend row and
   moves no digest.
4. **Cost of walking: 121 ms** for 214 `.py` + 99.7 ms for 134 `.bend`, memoized per run.

---

## 3. THE CONTROL — BOTH HALVES DRIVEN

`checks/no-strays.py`'s reason applies: `uop/ops.bend` is **owned by another live unit**
(`checks/nl-gate.py:485` records it moving between two captures), so perturbing it in place to
prove a point about a digest would be clobbering someone else's work. So the control runs on a
**mirror** that reproduces the path shape that matters (`graphcmp.bend` two levels below the
package root, so `import ./../../tinybendygrad/uop/ops.bend` resolves exactly as live).

`.agents/slop/closure/control-closure-key.py`, **RC=0**.

**PART 1 — resolving power, exhaustive over the population, no `bend` at all.** One byte in each
of the 7 closure files and each of 8 outsiders (the brief's own list of files that changed during
the session that motivated this task):

| | OLD key | NEW key |
|---|---|---|
| resolves | **1 of 7** | **7 of 7** |
| false positives on 8 outsiders | 0 | **0** |

**PART 2 — end to end, one real `bend matmul` run per half.** The IN-side edit is
`tinybendygrad/LAWS/spec.bend:741`, `def single() -> Dt: Dt{14, 32, CFloat{}, "f32"}` → `"f32X"`,
where `S.single` is referenced 11 times by `graphcmp.bend` — chosen so it **changes emitted rows**
and not merely some byte:

```
INSIDE  tinybendygrad/LAWS/spec.bend  (in closure: True)
        rows    18 -> 18   CHANGED=True
        OLD key still    <- GATE IS BLIND
        NEW key MOVED    <- STALE, correctly
OUTSIDE tinybendygrad/renderer/wgsl.bend  (in closure: False)
        rows    18 -> 18   CHANGED=False
        NEW key still    <- no false stale, and bend agrees: rows unmoved
```

**A control that cannot distinguish the two halves is not a control.** This one distinguishes them
on three axes at once — key movement, and rows movement measured by a real compiler run on both
halves. `restored: every mirror file byte-identical to the live tree: True`.

**Note what the brief's motivating example does *not* show.** Of the 8 port files that changed
during that session (`dsl.bend`, `wgsl.bend`, `elementwise.bend`, `creation.bend`,
`ops_python.bend`, `tensor.bend`, `weak.bend`, `realize.bend`), **none is in the 7-file closure**.
`census.py` answering `rc=0` there was **correct**, not lucky — and the new key agrees with it on
all 8. The closure matters for a different reason: **`ops.bend` is in it**, and `ops.bend` is one
of the most-edited files in the tree.

---

## 4. THE 68 KEYS

Changing the key's shape means the 68 rows have **never been vouched for by the new key**, and
writing it over them would assert a provenance nobody checked. So: snapshot, regenerate **out of
process, one graph per process**, diff every slot, and re-key **only if all 68 reproduce**.
`.agents/slop/closure/rekey-out-of-process.py`.

- 34/34 graphs regenerated out of process, all `rc=0`, 48 s.
- **68/68 row files byte-identical to the snapshot.** `keys.rows` CHANGED — that is the re-key.
- Only then was the new key written. The harness **restores the snapshot and returns 3** on any
  slot that fails to reproduce.

### The out-of-process rule is load-bearing — measured, not inherited

**25 of 34** py slots differ between one-process and per-process regeneration; **37 distinct
`P(iN)` values against 4**; `alu`→`P(i1,`, `binblob`→`P(i2,`. See §0.1: the rule is right and the
mechanism named in `census.py` belongs to tinygrad's `UOp.unique_num`
(`graphcmp.py:864`), not to `itertools.count` in the harness.

### A second finding the regeneration produced, which nobody had recorded

The first run **refused (3)** on `rows-lin-py.rows`. It differed in exactly one field — the
`<bytecount>:` prefix, `66:` against `120:` — with the content after the colon **identical**. The
row carried **ANSI SGR escapes**: tinygrad's `rgb()` colorises the `4` and `3` of the kernel name
`sr_4_5_3` when `NO_COLOR` is unset, and each escape is a byte that `String.length` counts wrongly
— the exact hazard `graphcmp.bend`'s own header documents.

**So the py lane's rows depend on an environment variable that the key did not cover, the tool did
not set, and the cache did not record** — and it fails **silently**, because a differently
configured shell rewrites one slot's bytes and `census.py` reports it as a fresh emission. Fixed by
pinning `NO_COLOR=1` beside the `DEV` that was already pinned, which is what makes a closure digest
sufficient in the first place: **one environment, decided in one place.** With it, 68/68 reproduce.

---

## 5. VERIFICATION — every rc, with its token

| check | result |
|---|---|
| `checks/census.py` | **rc=0 (PASS)** — 34 graphs, **68 of 68 slots keyed**, all served `CACHE`, `WALLS: []`, no `STALE`, denominator **77** (`len(list(Ops))`), reached **70** both sides |
| `checks/no-txt.py` | **rc=0** CLEAN |
| `checks/nl-gate.py` | **rc=0** `AGREE`, 205/205 identical |
| `gates/gate-surface.py --report` | **rc=0** `SHELL HALF: 18` |
| `checks/disagree-gate.py --lane citations` | **rc=0** `ok CITATIONS` |
| `checks/runs-artifacts.py` | **rc=0** `ARTIFACTS-FRESH`, `runs/graphcmp/D: 242 files` |
| `checks/bounded.py --selftest` | **rc=0** `PASS: 13 case(s) run, 0 failed` |
| `checks/index-arm-gate.py` | **rc=3 (REFUSED)** — 9 deletion + 5 stale, 0 foreign-add |
| `runs/graphcmp/D` | **242 files**, untouched, never written by anything here |
| `.agents/slop/closure/control-closure-key.py` | **rc=0 (PASS)**, both halves |
| `.agents/slop/closure/rekey-out-of-process.py` | **rc=0**, 68/68 rows reproduced |

### `.git/index` — the one requirement I could NOT hold, and why

**Its sha256 changed during my session: `6349f93c…` → `71448c93…`.** I did not cause it and I
am not claiming I preserved it. Evidence: mtime **16:03:14**, 33 s before I read it; intent-to-add
went **373 → 512 (+139)** between my 15:33 reading and 16:03. **No command I ran writes the
index** — my only git command all session was a read-only `git ls-tree -r HEAD`. `jj status`
snapshots the working copy and arms git's index by design, which is the documented mechanism here.
**Holding `.git/index` byte-constant across a 40-minute session is only possible if no other unit
runs `jj`, and four units were writing.** I report the before and after rather than a clean claim.

### Size, honestly

`checks/census.py` **224 → 326 lines, 135 → 200 code lines (+65 code, +102 total)**. Most of the
total is measurement recorded in comments, which this tree values and which is why the key's scope
is auditable. But **+65 code lines for a key is not free**, and the brief's standard is that fewer
is better. The 65 are: a 3-line path-loaded import, a 9-line `population()`, an 8-line
`gen_digest()`, a 6-line `blind_spots()`, and 3 report lines. The alternative — a hand list — is
the defect this whole unit exists to remove.

---

## 6. WHAT I DID NOT DO

- Did **not** stage or commit anything.
- Did **not** touch `checks/sweep.py`, `checks/runs-artifacts.py`, `.gitignore`, or `AGENTS.md`.
- Did **not** write to, move, or delete anything under `runs/graphcmp/`.
- Did **not** write to any live `.bend` file. Every perturbation ran on a mirror, and the control
  asserts byte-identity on restore.
- Did **not** delete a second resolver rather than load one: `import_closure` is loaded **by path**.
- **Did not** delete the two probe files that document my own wrong measurements — `.agents/`
  is pruned, and a wrong number that is retracted is worth more than a wrong number that is gone.