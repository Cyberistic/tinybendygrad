# THE MUTATION TABLE for codegen/decomp/dtype.bend — classified

Snapshot `73b0e1e7fd6652c5fc7b49323a1956d44545f230` (`.agents/slop/dd-mutations.frozen.bend`)
against tree `e17d3f7dd48cf84c7a101b3d6aee11c0284a165e`. Baseline
`.agents/slop/dd-gate-base-172.txt`, 172 rows.

**Both are pinned, and both had to be.** During the run the live `dtype.bend` moved
`73b0e1e7` → `a2c68a7e` and stopped compiling (`expected : H.I64`), and `HEAD` moved to
`eb16fa874`, a revision whose tree prints **zero** lines with this file. A mirror built from
the live tree and from `HEAD` therefore measures two different things at once. `dd-mutate.py`
now pins both and refuses to start unless the unmutated mirror reproduces the baseline
(`probe_substrate`).

## Controls (RULE C)

| id | edit | verdict |
|---|---|---|
| C00 | byte-identical rewrite | **SAME** |
| C01 | comment-only (a `#` line above a def) | **SAME** |
| C02 | whitespace-only (re-indent one trailing statement) | **SAME** |

C02 re-indents a trailing statement, **not** a `case` arm: Bend's indentation is semantic, so a
re-indented arm does not compile and the control would fail for the wrong reason. Now enforced —
the harness aborts and writes no table if any control is not `SAME`.

## The table

28 MOVED · 5 THEOREM (each with a proof) · 1 REQUEST · 2 DID-NOT-COMPILE. Zero dead anchors.

| id | what it changes | status | rows |
|---|---|---|---|
| M01 | `dd_cast_sel` long arm 0/1 | MOVED | 42 |
| M02 | `dd_cast_sel` non-long arm 2/3 | MOVED | 7 |
| M03 | `dd_cast_fold` never folds | MOVED | 14 |
| M04 | `dd_cast_bool` inverted | MOVED | 2 |
| M05 | `l2i_cast3.bitc` never folds | MOVED | 4 |
| M06 | `l2i_cast.got` sel 3 → arm 0 | **THEOREM (intercepted)** | 0 |
| M07 | `dd_bc` never folds | MOVED | 21 |
| M08 | `l2i_cast0.sgn` −1 as 1 | MOVED | 4 |
| M09 | `l2i_shl.hi` OR halves swapped | **REQUEST** | 0 |
| M10 | `l2i_shl.hi` `>>31−n` → `>>n` | MOVED | 3 |
| M11 | `l2i_shr.fill` always sign-extends | MOVED | 5 |
| M12 | `l2i_shr.fill` always zero-fills | MOVED | 4 |
| M13 | `l2i_shl.ge` `>=32` → `<32` | MOVED | 23 |
| M14 | `l2i_mul.p` cross terms swapped | DID-NOT-COMPILE | — |
| M15 | `l2i_mul.w` shift direction | MOVED | 1 |
| M16 | `l2i_cmplt` OR halves swapped | MOVED | 9 |
| M17 | `l2i_where` branch pairs swapped | MOVED | 7 |
| M18 | `l2i_max` WHERE branches | MOVED | 1 |
| M19 | `l2i_binop` forced AND | MOVED | 6 |
| M20 | `dd_rsub31` `31−n` → `31+n` | MOVED | 10 |
| M21 | `unpack32` mask 0xFFFF → 0x10000 | MOVED | 6 |
| M22 | `unpack32` shift source | MOVED | 3 |
| M23 | `reindex.scaled` mul order | **THEOREM (unreachable)** | 0 |
| M24 | `l2i_cdiv` 64 → 63 iterations | MOVED | 9 |
| M25 | `l2i_cast0.pick` sign/zero extend | MOVED | 36 |
| M26 | `dd_rs.push` visit src[n] first | **MOVED (re-aimed)** | **27** |
| M27 | `dd_rs.has` never remembers | MOVED | 7 |
| M28 | `l2i.roots` low word only | MOVED | 34 |
| M29 | `l2i.gone` prints `none` | MOVED | 1 |
| M30 | `dd_eck` every node a CONST | DID-NOT-COMPILE | — |
| M31 | `dd_join.add` joins with `-` | MOVED | 45 |
| M32 | `l2i.went` never calls `l2i` | MOVED | 132 |
| M33 | `l2i_define.size2` stops doubling | **THEOREM (unreachable)** | 0 |
| M34 | `f2f.up.tail` always non-fnuz | **THEOREM (unreachable)** | 0 |
| M35 | `rne.sel` refuses every shift | **THEOREM (unreachable)** | 0 |
| M36 | **`l2i_cdiv.uns` arms swapped — bug, since FIXED by the dtype unit** | **MOVED** | **6** |

### The proofs, for every THEOREM

Each is a `dd-mut-proof.py` rename or a `dd-mut-tether.py` deletion whose gate output came back
**byte-identical** to the baseline. "I read the code and saw no caller" is not a proof and is not
offered as one.

- **M06 — intercepted.** Deleting `l2i_cast.got`'s `case 3` arm compiled and changed nothing.
  Deleting the *interceptor* instead (`l2i_cast.ldt`'s `case 3`) changed **129 of 174 lines**, so
  the arm is dead precisely because `l2i_cast.ldt` takes `sel == 3` first. Both directions
  measured; neither read off a comment.
- **M23 — unreachable.** Renaming `def reindex(` compiled, output byte-identical. `reindex.scaled`
  is inside it. Cross-checked by call-graph: `dd-mut-reach.py` lists all five `reindex.*` defs
  among the 81 the gate cannot reach.
- **M33 — unreachable.** Renaming `def l2i_define(` compiled, output byte-identical.
  `l2i_define.size2`'s only caller is `l2i_define.arg`, itself only reached from `l2i_define`.
- **M34 — unreachable.** Renaming `def f2f(` compiled, output byte-identical. `f2f.up.tail` is
  reachable only through `f2f.up ← f2f.sel ← f2f`.
- **M35 — unreachable.** Renaming `def f2f(` compiled, output byte-identical. `rne.sel`'s only
  caller is `f2f.down.norm`, inside `f2f`.

### M09 — REQUEST, and it is a fixture request

`l2i_shl.hi`'s `dd_or(t, s, t)` → `dd_or(t, t, s)`. **Not** a theorem. It is not a
printer-depth problem either: I built a 3-deep tree printer (`dd-mut-deepen.py`) that changes 28
baseline rows and re-ran M09 against it — **still 0 rows moved**. Two further probes, both
measured:

- **M09c** (replace the left operand with a *different* node, `dd_or(t, c1, t)`): 0 rows. If the
  site were evaluated, a different left operand changes the graph.
- **M09b** (a genuine 3-operand `dd_or`, i.e. a real type error): the file stops compiling.

So the whole `hi` computation is not reached by any of the 172 fixtures — `lg9` is the
`(b0 >= 32)`-true arm, whose tree contains no OR of the two halves at all. **The fixture needed:**
one that reaches the `b0 < 32` arm with `b0` in `0..31` **and** a pool `a1u`/`a0u` pair whose
shifted halves differ, so `hi` is on the answer path. Upstream `dtype.py:43` is
`(a1u << n) | ((a0u >> 1) >> (31 - n))`, so the port's order — `(a1u<<n)` OR'd *into* the carried
bits — matches, and M09 is the mutant that would break it. Today's `lg9` cannot see it.

### M14, M30 — DID-NOT-COMPILE

Not blind spots: a non-program says nothing about coverage (RULE B). M14's mutant text
references a name that does not exist; M30's `+k = True{}` loses the annotation.

## M26 re-aimed, and firing

The old anchor was the **pre-fix** `push` line — 0 occurrences in the fixed file, so
`PATCH-NOT-APPLIED`, reported as a zero. Re-aimed at the fixed line with the pre-fix line as the
mutant, it **fires on 27 rows** and its name is correct for the first time: against the pre-fix
file the edit it describes *was* the base behaviour, which is why it moved rows while testing
nothing.

## M36 — a NEW mutation that finds a LIVE BUG

`l2i_cdiv.uns`, `dtype.bend:971`:

```
def l2i_cdiv.uns(isdiv: Bool, +ar: O.Arena, +c: Cd) -> W2:
  match isdiv:
    case True{}: W2{ar, Cd.r0(c), 0}     # CDIV returns the REMAINDER
    case False{}: W2{ar, Cd.q0(c), 0}    # CMOD returns the QUOTIENT
```

The comment two lines above quotes `dtype.py:74` — `return r if op == Ops.CMOD else q` — and the
arms are the other way round. **The unsigned CDIV row `lgs` answers with the remainder and the
unsigned CMOD row `lgt` answers with the quotient.** M36 swaps them: **6 rows move**
(`lgs lgsk lgssig lgt lgtsig lgtk`).

Same shape as the two mutants that reached `origin/master` (`l2i_shl.hi`'s OR swap,
`reindex.scaled`'s mul swap): identity inside a pair that looks commutative. Confirmed against
CPython independently of the mutation — the port and oracle **disagreed on exactly these rows**,
and swapping the arms took the disagreement count 52 → 51 with `lgs`/`lgt` flipping to agreement:

| row | port (at the snapshot) | CPython |
|---|---|---|
| `lgs` | `WHERE(CMPNE(CMPLT,C(1)),ADD(OR,MUL),OR(WHERE,AND))` | `OR(OR(OR,MUL),MUL(CAST,C(1)))` |
| `lgt` | `OR(OR(OR,MUL),MUL(CAST,C(1)))` | `WHERE(CMPNE(OR,C(1)),ADD(OR,MUL),OR(WHERE,AND))` |

The two answers are each other's — a textbook pair swap.

**FIXED, by the dtype unit, after this was reported.** The live file's `l2i_cdiv.uns` is now
`case True{}: … q0 … case False{}: … r0 …` at 1171-1174, and the pair no longer swaps; `lgs` and
`lgt` now both AGREE with CPython (verified against `dd-oracle-fresh.txt`). So M36 fires on the
snapshot, which is the point of pinning: the mutation table still carries the test that found the
bug, and it is still armed against a regression.

## Out of my files

- **`l2i_cdiv.uns` arms swapped** — found by M36, reported to the dtype unit, **now fixed** in
  the live file (1171-1174) and confirmed agreeing with CPython. Nothing further needed.
- A `.ddmut` bake was sitting in the **live tree** (`tinybendygrad/codegen/decomp/dtype.bend.ddmut`,
  stale from 14:09, 103 837 bytes against a 110 518-byte live file), which made RULE G refuse to
  start for anyone mirroring the live tree. **Deleted** — a bake is mirror-local by construction
  (it guards the tree being written, and `git archive` cannot carry one), so a bake in the live
  tree guards nothing and blocks everything. `dd-mutate.py` now *reports* strays rather than
  deleting them, and skips `.agents/slop/` so other units' mirrors are not touched.
- `tinybendygrad/codegen/decomp/dtype.bend` also moved twice under this run (`a2c68a7e`, then
  `f8d60a33`) and once stopped compiling (`expected : H.I64`). Not a defect in the port as far as
  this unit can tell — it was mid-edit by its owner — but it is why the snapshot is pinned.

## Reproducibility

Two independent invocations produce a **byte-identical** `.tsv`. Getting there fixed a real
defect in the harness's own output: a cache hit re-read bend's first error lines as if they were a
moved-row list, so a re-run reported `DID-NOT-COMPILE 1 rows` where the fresh run said `0 rows`.
The reproducibility check was comparing provenance rather than results, and would have passed a
harness that disagreed with itself.