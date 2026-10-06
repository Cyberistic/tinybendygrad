# The port's markers, by discovery, and one landed

Measured 2026-10-06. Instrument: `.agents/slop/portmarkers/markers.py`
(`.venv/bin/python`, walks `tinybendygrad`). Every number carries its denominator
and the rule that produced it. No count is quoted from a job that may be running:
each `bend` run below is a finished `bounded.py` line.

## 1. The denominator, and the split per kind

**Files walked: 138** (`os.walk` over `tinybendygrad/**/*.bend`).

**Markers found: 747.** One number cannot carry this, so the kinds are separate:

| kind | count | rule |
|---|---:|---|
| `TODO(p3)` | 716 | whole-line `#` comment matching `^\s*#\s*TODO\(p3\)` |
| `TODO(p1/p4/p6)` | 3 | `ops_metal.bend:277`, `helpers.bend:430`, `helpers.bend:2565` |
| `NOT PORTED` | 28 | `^\s*#\s*NOT PORTED\b` |
| `BACKLOG` | 0 | the word appears once (`multi.bend:3431`) as prose, not a marker |
| `UNPORTED` | 0 | — |
| `FIXME` | 0 | — |
| `OPEN CLAIM` | 18 → **17** | a `law` with no `def` in the `PROOF.bend` import closure |

`BACKLOG` and `UNPORTED` are **zero by discovery**: the tree never writes those
tokens as markers. The "BACKLOG" in commit `5943011d2` is `checks/marker-audit.py`'s
*name for the reachable quadrant*, not a token in any file.

**The sixth kind is bend's own.** `bend` does not read comments for TODOs: it counts
`?TODO` holes (`bend.ts:1963`) **plus every `law` with no `def`** (`bend.ts:3847`,
`book.hols`). There are **zero `?TODO` holes in the tree** (measured, `?TODO` in
`tinybendygrad/**/*.bend` = 0), so **`PROOF.bend`'s 18 TODOs are exactly the 18
unfilled laws in `LAWS.bend:201-295`** — 9 decomposed-op laws (section IV) and 9
dtype-column laws (section V). This is the one marker class the named gate counts.

## 2. Classification (the 716 `TODO(p3)` markers)

Rule, reproduced from `checks/marker-audit.py` so the numbers reconcile: an entry is
the marker line + its own following comment lines; REASONED if the entry matches the
WALL vocabulary, or if the def it names is written down elsewhere in the same file;
otherwise REACHABLE. STALE sits on REACHABLE.

| class | count |
|---|---:|
| REASONED (entry) | 598 |
| REASONED (reason elsewhere in file) | 25 |
| REACHABLE | 87 |
| — of which STALE candidates | 6 |

`UNCLASSIFIED` is **0**: the split is total. (The pre-existing instrument
`checks/marker-audit.py` reads **599 walls / 40 shared / 77 BACKLOG** on the same
files. It agrees to a 10-marker difference in the shared/backlog boundary — my rule
takes names from backticks, its rule takes `def NAME` from the line. Both rules are
stated; neither is called authoritative.)

The 87 REACHABLE concentrate in `schedule/multi.bend` (37), `nn/onnx.bend` (10),
`runtime/support/hcq2.bend` (8), `renderer/tc_ptx.bend` (8), `schedule/__init__.bend`
(8). **`multi.bend`'s 37 are a documented lie of attribution**: its own header
(`multi.bend:3427-3449`) says the reason is in a PRECEDING block that
`marker-audit.py` cannot read, and that "a reader who trusts `not ported` will
under-scope the work" — they are unported RULE BODIES, not missing primitives.

## 3. STALE — checked for real

The broad rule (named def exists, no reason in entry) flags **6**; verifying each
shows **all six are false positives** from method-name matching (`.bitcast`,
`ms.replace`, `.pad_to`, `UOp.after`, `call.replace`, `backward_slice`): the named
method exists, but the marker's actual gap is a rule body, not the def.

A targeted hunt for absence-claims the tree refutes found the real class:

| marker | claims | refuted at |
|---|---|---|
| `uop/weak.bend:1667` | "Only the `commit_dtype` is missing" | `mixin/dtype.bend:319` `def commit_dtype(...)` |
| `uop/weak.bend:1660,1665,1671,1674,1678,1679,963,990,991,1001` | wall is `commit_dtype`/`_min_max` | same; `_min_max` landed per `weak.bend:13` |
| `viz/serve.bend:1297` | "`H.i64_mul` does not exist in helpers.bend" | `helpers.bend:2281` `def i64_mul(...)` |
| `codegen/late/linearizer.bend:108` | helpers has NOT `i64_mul/div/mod` | `helpers.bend:2281/2044/2175` |
| `mixin/dtype.bend:52` | "`i64_mul` NOWHERE" | `helpers.bend:2281` (and the same file contradicts it at :61) |
| `uop/symbolic.bend:79` | helpers has NOT `i64_mul` | `helpers.bend:2281` |

So **at least 15 markers state a blocker the tree refutes**. `weak.bend:20` and
`mixin/rand.bend:458` are the two that *self-correct* — the tree is inconsistent with
itself, not uniformly stale.

## 4. The single marker landed — an open claim

Highest value because it is the only class a **named gate** counts, and because each
one pins a rule nothing else checks. Landed: **`where_takes_the_second_operand_dtype`**
(`LAWS.bend:266`) — `Sp.dtype(SpWhere{p,a,b})` must be `Sp.dtype(b)` (src[1]), the arm
a port is most likely to write as src[0].

Change: `tinybendygrad/PROOF.bend`, 6 lines:

```bend
def L.where_takes_the_second_operand_dtype(p, a, b):
  {==}
```

Measured under `bounded.py --mb 2048` (token + count):

| state | token | TODO count |
|---|---|---:|
| before | `WITHIN-LIMITS rc=1 ... Error: 18 TODOs found.` | **18** |
| after | `WITHIN-LIMITS rc=1 ... Error: 17 TODOs found.` | **17** |

The token is `WITHIN-LIMITS` in both; the child exits 1 because the gate is red at
rest. **The count, not the red, is the verdict on the change: 18 → 17.** stdout is 0 B
in both (`--check-only` prints to stderr), so `ALL PROOFS CHECK` is not in play here.

## 5. Blast radius

The change touches **1 tracked file**: `tinybendygrad/PROOF.bend` (+6 lines, 0
deletions; `git diff --stat -- tinybendygrad` = `1 file changed, 6 insertions(+)`).

- **1 of 138 `.bend` files the census walked = 0.72%** of the port's surface.
- **1 of 4 files in the `PROOF.bend` import closure = 25%** of the proof set.

No regression, both re-run:

| gate | before | after |
|---|---|---:|
| `PROOF.bend --check-only` | 18 TODOs | **17 TODOs** |
| `LAWS.bend --check-only` | 34 TODOs | **34 TODOs** (unchanged — the def is in PROOF, not LAWS) |

## 6. Planted, two states

Fault: `LAWS/spec.bend:806` `Sp.dtype(b)` → `Sp.dtype(a)` (reverted after).

- **Fixed**: `WITHIN-LIMITS`, 17 TODOs, no proof error.
- **Planted**: `WITHIN-LIMITS rc=1 ... Error: - expected : S.Sp.dtype(a) / -
  observed : S.Sp.dtype(b) / Location: L.where_takes_the_second_operand_dtype`.

The gate **names the law and both terms** — the proof is not vacuous, and it bites
on exactly the src[0] mistake it was written for.

`tinybendygrad/helpers.bend`: **130719 bytes, 2843 lines, non-zero** — unchanged (no
edit went near it).

## Files

- `.agents/slop/portmarkers/markers.py` — the discovery instrument.
- `.agents/slop/portmarkers/markers.{before,after}.out` — its two censuses.
- `.agents/slop/portmarkers/proof.{before,after,plant}.err` — the bounded tokens.
- `.agents/slop/portmarkers/census.before.out` — `checks/marker-audit.py`'s census.
- `tinybendygrad/PROOF.bend` — the landed law.

Not committed (orchestrator commits by path).
