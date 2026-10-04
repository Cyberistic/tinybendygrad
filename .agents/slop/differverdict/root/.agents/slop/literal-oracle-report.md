# Literal-oracle conversion — unit report

**Unit**: convert literal `py=` expectations to CPython-derived calls, plus wire `kernel.bend`'s
`ops` row to the already-derived measurement.

**Status**: IN PROGRESS — this file is written as I go.

## Baseline (measured, not assumed)

- `.agents/slop/handtyped-audit.py` — AST classifier, 578 hand-typed rows across 33 oracles.
- `.agents/slop/handtyped-rank.py` — `score = 3·LIES + 2·REIMPL + MAGIC`.
- `.agents/slop/reimpl-scan.py` — 94 reimpl expressions across 16 oracles.
- Consequence ranking given by the coordinator: `nv` 148, `ip` 43, `ops-python-render` 33,
  `objc` 27, `cs` 26, `amdev` 23.

## Denominators used throughout

| quantity | value | source |
|---|---|---|
| hand-typed rows, whole repo | 578 | `handtyped-audit.py` |
| oracles with hand-typed rows | 33 | `handtyped-audit.py` |
| reimpl expressions, whole repo | 94 across 16 oracles | `reimpl-scan.py` |
| prior unit's converted rows | 27 of 578 = 4.7% | coordinator brief |

---

# 1. `kernel.bend`'s `ops` row — WIRED, AND THE LITERAL AND THE CALL AGREED

## State found on arrival

The oracle the gate reads is **`.agents/slop/notes/kn-truth.py`** (cited at
`tinybendygrad/codegen/kernel.bend:954`). `jj diff` shows it **modified, uncommitted**.
The committed parent (`jj file show -r @-`) printed the row as a hardcoded literal at
**line 167**:

```python
print("pos=20"); print("dup=0"); print("pos_same=1")
print("ix=" + " ".join(str(i) for i in range(20)) + " ")
print("ops=NOOP CONST CONST CONST SPECIAL BUFFER BUFFER PARAM RANGE RANGE SQRT STORE ALLOC REDUCE SINK PROGRAM PROGRAM INS PROGRAM PROGRAM ")
print("ab=BUFFER")
```

The working copy (mtime Oct 4 06:59, i.e. **after** `kn-noop-truth.py` at 06:09) replaces
those six prints with measurements off real `UOp(...)` objects:
`pos`/`dup`/`pos_same`/`ix` off `fixture()` + `intern_order()`,
`ops` off `n.op.name for n in nodes`, at **line 262**.
**That edit is the dead previous unit's work.** It is uncommitted. I verified it; I did not
write it.

## The measurement, run twice

| run | rows | `ops` |
|---|---|---|
| oracle run 1 | 38 | `NOOP CONST CONST CONST SPECIAL BUFFER BUFFER PARAM RANGE RANGE SQRT STORE ALLOC REDUCE SINK PROGRAM PROGRAM INS PROGRAM PROGRAM ` |
| oracle run 2 | 38 | identical — `diff` rc=0 |
| port `./bin/bend tinybendygrad/codegen/kernel.bend` | 38 | identical |

```
diff oracle port   -> rc=0 (no output)
sha256 oracle = 464e17ad01b46c322032038971677b6e8047e07dd2b505f6147c17ea005bd622
sha256 port   = 464e17ad01b46c322032038971677b6e8047e07dd2b505f6147c17ea005bd622
```

Byte-identical, 38 rows each. (Count-based diffs mislead, so: the sha256 of the whole
lane text, not a row count, is the claim.)

## Did the literal and the call AGREE? — YES, on all six rows

| row | committed literal | derived | agree |
|---|---|---|---|
| `ops` | `NOOP CONST … PROGRAM ` | same | **YES** |
| `pos` | `20` | 20 | YES |
| `dup` | `0` | 0 | YES |
| `pos_same` | `1` | 1 | YES |
| `ix` | `0 1 … 19 ` (from `range(20)`) | `0 1 … 19 ` (from `UOpMetaClass.ucache` insertion order) | YES |
| `ab` | `BUFFER` | BUFFER | YES |

**So the literal had not been wrong.** That is the finding, and it is a *negative*
finding: 6 of 6 rows of `kernel.bend`'s oracle were correct when hand-typed. It is worth
exactly as much as that — it does not license typing the next oracle.

**Caveat that makes the agreement weaker than it looks.** The committed `ix` was
`range(20)`, which asserts "the fixture interns 0..19 in construction order" without
reading anything; the derived `ix` reads `UOpMetaClass.ucache`'s insertion order. Those
two are different claims that happen to hold on the same fixture. Agreement between them
is corroboration of *ordering*, not of *node identity*.

## The lead literal: `kn-noop-truth.py` builds the WRONG RANGE and STILL agreed

`kn-noop-truth.py` (the instrument the brief points at) builds its RANGEs by hand as
`UOp(Ops.RANGE, src=(c4, CONST(0)), arg=AxisType.UPCAST)` — axis type in `arg`, axis id in
`src`. I measured both spellings against the pin:

```
kn-noop-truth RANGE    op=RANGE  len(src)=2 arg=AxisType.UPCAST         src_ops=['CONST', 'CONST']
kn-truth UOp.range     op=RANGE  len(src)=1 arg=(AxisType.UPCAST, (0,))  src_ops=['CONST']
op NAME identical (so the `ops` row cannot see the difference): True
```

`kn-noop-truth.py` agrees with the port **on a node CPython never builds**. This is the
`nv_query_litter` failure mode one level down: a wrong instrument that agrees with a
right port is indistinguishable from a right instrument. The working-copy `kn-truth.py`
uses `UOp.range(4, (0,), UL)` and its comment names this; I re-measured it rather than
believing it. **`kn-noop-truth.py` should not be used as a witness again.**

## What the converted row actually discriminates — 5 mutations, `kn-ops-mutate.py`

Baseline 38 rows, scratch copy asserted byte-identical to the live tree before and after
(`md5 a5094b436d53be050916206dee9bd495` both ends).

| mutation | rows moved | `ops` moved? | what it was |
|---|---|---|---|
| M1 fixture mints SIN where CPython mints SQRT | 1 | **YES** | op-name swap |
| M2 stale arena: pr3 interned in pr2's | 3 | **YES** | dedup drops INS, `ix` shortens 20→19, `pos_same` 1→0 |
| M3 pr2's two srcs swapped | 0 | no | same op multiset |
| M4 `ru` axis UNROLL→LOOP | 2 (`rm`, `rm_unroll`) | **no** | op name still `RANGE` |
| M5 b7's slot 7→9 | 0 | no | no op name changes |

**`ops` moved under M1 and M2 and not under M3, M4, M5.** That is the whole of its
discriminative power over this fixture: it is an **op-NAME sequence**, so it is blind to
src order (M3), to anything inside an `arg` (M4, M5), and — as measured above — to a
node whose `src` count and `arg` shape are wrong as long as the name is `RANGE`.

M3 moved **zero rows in the entire 38-row oracle**, not just `ops`. Two srcs swapped on
`pr2` is invisible to every row `kernel.bend` has.

---

# 2. THE TRANCHE — `nv-oracle.py`, the top of the consequence ranking

## Ranking order as measured, not as given

`handtyped-rank.py` (`score = 3·LIES + 2·REIMPL + MAGIC`), re-run on the tree as I found it:

```
rank oracle          score  DEFECT  LIES  MAGIC  REIMPL  reimpl-defs
   1 nv-oracle.py       148     95    32     12      20            9
   2 ip_oracle.py        43     54     3     14      10            3
   3 ops-python-render   33     11    11      0       0            0
   4 objc_oracle.py      27     22     9      0       0            0
   5 cs_oracle.py        26     63     7      5       0            0
   6 amdev_oracle.py     23     44     0     23       0            0
```

I took **rank 1, `nv-oracle.py`**. **65% of its score (96 of 148) is `LIES`**, and
`LIES` is the component with measured false positives, so the ranking's head is the
softest part of it — see §5.

## What I converted, and what each conversion actually is

**27 distinct row names, across 3 families + one.** Baseline lane: 574 printed lines / **547
distinct names**, sha256 `1d1349635bb0…`. After: same 547 names, **0 value
disagreements**, verified by set comparison and not by a count.

### Family 1 — `nv_iowr`'s command word and its refusal (15 names). A real call.

Upstream `ops_nv.py:42-44`:
```python
def nv_iowr(fd:FileIOInterface, nr, args, cmd=None):
  ret = fd.ioctl(cmd or ((3 << 30) | (ctypes.sizeof(args) & 0x1FFF) << 16 | (ord('F') & 0xFF) << 8 | (nr & 0xFF)), args)
  if ret != 0: raise RuntimeError(f"ioctl returned {ret}")
```

The oracle was transcribing **both** the bit pattern and the f-string. It now imports
`nv_iowr` and hands it an `fd` stub that records the word and returns a chosen `ret`:

| row | was | now |
|---|---|---|
| `nv_iowr_{0_0,4_1,64_44,40_43,96_65,1280_2,8191_136,8192_1,8192_255}` | `(3<<30)\|((sz&0x1FFF)<<16)\|…` typed at 2 sites | `_iowr_cmd(sz, nr)` |
| `nv_iowr_explicit_kept` | `201` | `_iowr_cmd(40, 43, cmd=201)` |
| `nv_iowr_explicit_0` | the same pattern again | `_iowr_cmd(40, 43)` |
| `nv_iowr_msg_{0,5,4096}` | `"" if _r==0 else "ioctl returned %d" % _r` | `_iowr_msg(40, 43, _r)` — upstream's own `RuntimeError`, caught |
| `nv_iowr_size_is_same` | one transcription compared with another | two calls compared |

`sz` is upstream's `ctypes.sizeof(args)`, so the fixture is a real ctypes object of
exactly that size (`c_uint8 * sz`). **MEASURED side effect:** `sz=8192` and `sz=0`
therefore produce the same word — which is what `nv_iowr_size_is_same` asserts, so that
row is now two calls rather than one hand-copy checked against another hand-copy.

### Family 2 — the four header fields (4 names). A real call, by differencing two calls.

Upstream `ops_nv.py:47`. Each field is isolated by **differencing two `nvm` calls** with
that field moved and nothing else, so no shift and no mask is typed in the oracle, and
the row still fails if upstream moves the field:

| row | derivation | value | the literal it replaced |
|---|---|---|---|
| `nv_hdr_typ2` | `nvm(0,0,0,typ=2)[0] - nvm(0,0,0,typ=0)[0]` | 1879048192 | `2 << 28` — **agreed** |
| `nv_hdr_subc4` | `nvm(4,0,0)[0] - nvm(0,0,0)[0]` | 32768 | `4 << 13` — **agreed** |
| `nv_hdr_nvals5` | `nvm(0,0,0,0,0,0,0)[0] - nvm(0,0)[0]` | 327680 | `5 << 16` — **agreed** |
| `nv_hdr_all` | `nvm(4, M_OFFSET_IN_UPPER, U64, U64)[0]` | 537166080 | `(2<<28)\|(4<<16)\|(4<<13)\|(M>>2)` — **agreed** |

`nv_hdr_all` is now **one call with nothing typed at all** except `subc=4`: `typ`
defaults to 2 upstream, `mthd >> 2` is upstream's, and `nvals=4` falls out of two
`uint64` UOps because upstream counts `itemsize // 4`.

### Family 3 — the program-cache counts (6 names). A read, NOT a call — and it found a bug.

The seven `nv_pc_*` rows were literals `0, 1, 3, 3, 3, 3, 0` under a `_put` chain, and
the block's own comment claimed they were "the COUNT of advances".

**MEASURED: the chain was one put ahead of the values it was annotating.** `len(_c)` at
the three count rows was **1, 2, 3**, not 0, 1, 3. Every literal was *correct against the
port* and *wrong against the oracle's own state*, and nothing noticed because nothing
read it. The chain is rebuilt to the port's shape (`ops_nv.bend:3453-3459` is
`PC.n(PC.of())`, `PC.n(pc_one(PC.of(), K1()))`, `PC.n(a)`, …), so the empty cache is
measured before the first put, and the two repeat keys — the negative case — sit one row
from the third distinct key at the same size. `nv_pc_id_0` moved down to the `_put_id`
block, where a dict that actually holds ids exists, and reads its value out of it.

**This family is provenance over the ORACLE'S OWN STATE, not over upstream, and I am not
counting it as a conversion to a call.** `_put` is a re-implementation of
`ops_nv.py:314-318` and `nv_build_program` needs a real ELF, so there is no upstream call
to make. The row says "what this oracle's own helper did", which is weaker and is labelled
weaker.

### Plus one — `nv_err_unknown` (1 name)

`nv_err_unknown` — `"Unknown error"` → `get_error_str(999).split(": ", 1)[1]`, the
default out of upstream's own `nv_status_codes.get(...)`.

## The ratio, honestly

| quantity | before | after |
|---|---|---|
| `nv-oracle.py` DEFECT sites | **95** | **83** |
| `nv-oracle.py` score | **148** | **144** |
| repo-wide DEFECT (the coordinator's 578 → the tree's actual count) | 571 | **559** |
| **distinct row names converted in `nv`** | — | **27** |

- 27 names = 15 (`nv_iowr_*` incl. the refusal and `size_is_same`) + 4 (`nv_hdr_*`)
  + 7 (`nv_pc_*`) + 1 (`nv_err_unknown`).
- **Against `nv-oracle.py`'s own 95 defect sites: 12 sites cleared, 12/95 = 12.6%.**
- **Against the repo's 559 remaining hand-typed row sites: 12/559 = 2.1% cleared by me.**
  With the previous unit's 27, the cumulative conversion is **39 of 578 = 6.8%** — and
  the 578 denominator is the coordinator's, while the live tree now says 559 because other
  agents are moving under me. Both numbers are stated; neither is a coverage claim.
- 27 names come from **29 row call sites**: the `nv_iowr_*` family is emitted at TWO sites
  (both now call the same helper, so the duplicate can no longer disagree with itself).
- I did not touch ranks 2-6. This tranche is the top of the list and nothing below it.

## Reimpl sites in the tranche — the 9 nv defs that were NOT converted, and why

`reimpl-scan.py` finds **11 expressions across 9 defs** in `nv-oracle.py`, leaning on 22
row call sites. **I converted none of them, on purpose.** Every one is upstream code that
lives inside a method which allocates a `Buffer` before it can be reached:

| def | upstream | why it cannot be called |
|---|---|---|
| `_max_threads` | `ops_nv.py:306` | inside the same method as `exec`; `NVProgramData` needs a built ELF |
| `_smem_cfg` | `:294` | a local of `exec`, computed after `nv_build_program` |
| `_bpt` | `:693` | `_ensure_has_local_memory` allocates `Buffer(...)` on the line after |
| `_coloc`, `_top`, `_unk_size` | `:703`, `:704`, `:705` | `_ensure_has_vid_hw` allocates `_vid_buf(...)` on the line after |
| `_q_idx`, `_q_litter` | `:666` | `_query_gpu_info` needs `iface.rm_control` on a live subdevice |
| `sass` | `:603` | inside `NVDevice.__init__` |

**Converting these would be trap #1 exactly: replacing an honest literal with a
dishonest call into a copy.** `reimpl-scan.py`'s own blind spot applies here too — it has
a 12-char canonical floor, so `ok_dims`, `ok_prod`, `stage`, `_put` and `b7like` are
**not** among its 9 findings and they are all copies. Measured: `ok_dims` and `ok_prod`
back `nv_dims_*` (11 names) and `nv_launch_ok_*` / `nv_launch_*_refuses` (6 names).

**One row is a transcription I could convert and did not: `nv_dims_msg_lz`**
(`"Invalid global/local dims global_size=(1, 1, 1), local_size=(1, 1, 65)"`) is upstream's
f-string at `ops_nv.py:169`, typed by hand. It is not convertible either, because the
`raise` is inside `exec` and `{global_size=}` interpolates the port's own device repr.
Reported, not fixed.

---

# 3. CONVERTED ROWS THAT A MUTATION DOES NOT MOVE — listed separately

`.agents/slop/nv-iowr-mutate.py`, 12 mutations of `tinybendygrad/runtime/ops_nv.bend`.
Scratch copy is the whole `tinybendygrad/` tree (a $TMPDIR copy of one `.bend` cannot
resolve a relative import — that produced 22 phantom blind spots in one unit), asserted
byte-identical to the live port before and after (`sha256[:16] 24497e96ddebc56c` both
ends). Rows come from **`rebase-gate.py`'s own `rows()`**, imported, not reimplemented.
Diff is over whole `name=value` lines.

Baseline: **600 port rows, 547 oracle rows, 543 shared, 0 pre-existing disagreements.**

**22 of 27 converted rows moved under at least one mutation. 5 did not move under any.**

| converted row | moves under | note |
|---|---|---|
| `nv_iowr_0_0`, `_4_1`, `_64_44`, `_40_43`, `_96_65`, `_1280_2` | I3 (read bit 3→1) | |
| `nv_iowr_8191_136` | I2, I3 | |
| `nv_iowr_8192_1`, `_8192_255` | I1, I3 / I1,I2,I3 | I1 is the `0x1FFF` truncation |
| `nv_iowr_explicit_0` | I3, I4 | |
| `nv_iowr_size_is_same` | I1 | |
| `nv_iowr_msg_5`, `_4096` | I5 | |
| `nv_hdr_typ2` / `_subc4` / `_nvals5` | H1 / H2 / H3 | one field each, as designed |
| `nv_hdr_all` | H1, H2, H3, H4 | the only row all four header mutations reach |
| `nv_pc_grow_1`, `_grow_3`, `_grow_repeat`, `_grow_repeat_k1` | P1 | |
| `nv_err_unknown` | E1 | |

### The 5 that never moved

| row | why | is it a theorem, a fixture, or untested? |
|---|---|---|
| `nv_iowr_msg_0` | `ret == 0` is the **no-raise arm**; I5 only edits the raise text | **NOT a defect.** This is the `nv-oracle.py` 4-dead-sites trap in miniature: a no-raise arm of a `raise if ret != 0`. |
| `nv_pc_grow_0` | `PC.n(PC.of())` — the count of the **empty** cache. P1 changes the insert arm, not the empty start | structural constant: `PC.of()` is `PC{0,0,0,0,Nil{},Nil{}}` |
| `nv_pc_miss_3` | no mutation targets the miss counter. P1 breaks the *key count*; P2 breaks the *id* field | **UNTESTED, not insensitive.** I did not write a mutation for it and I am not claiming one cannot exist. |
| `nv_pc_id_0` | same | **UNTESTED, not insensitive.** |
| `nv_iowr_explicit_kept` | I4's `is_eq(explicit, 1)` still selects 201, so I4 does not reach it; E2 was **INCONCLUSIVE** | **UNTESTED.** The one mutation designed to hit it did not compile. |

### Two mutations that did NOT move anything, reported rather than hidden

- **P2 — 0 of 600 rows.** It makes the HIT arm of `pc.put` stamp `PC.miss(p)` into the id
  field. On this fixture three insertions leave `misses == next == 3`, so the two are
  indistinguishable **here**. That is a **fixture** property, not a row property, and I
  am **not** claiming a theorem.
- **E2 — INCONCLUSIVE, not counted either way.** `Bool.True{}` is not a `U32`, so the
  mutated port emitted **0 rows** and the harness refused to call that `MOVED=True` off a
  zero-row lane. This is the "a mutation that fails to compile reports MOVED=True off
  ZERO rows" trap, hit and refused by construction.

**Bottom line for priority 3: 4 of the 5 non-moving converted rows are untested or a
structural/negative case, and exactly 1 (`nv_iowr_msg_0`) is a genuine no-raise arm.**
A converted row is not a verified row. The 22 that moved are the only ones in this tranche
with a demonstrated kill.

---

# 4. THE `LIES` COLUMN, MEASURED — 7 of nv's 9 "message" LIES are the documented false positive

`handtyped-rank.py`'s `lies()` predicate, replicated (I did not edit the shared
instrument) over nv's 83 DEFECT rows:

| class | count | names |
|---|---|---|
| `message` | 9 | see below |
| `bare-bool` | 12 | `nv_reloc_ok_refused`, `nv_reloc_empty_refused`, `nv_vid_ok_{new,old,none}`, `nv_vid_none_refuses`, `nv_ring_in_table`, `nv_prof_is_bw_{ampere,ada,bwa,bwb}`, `nv_smemcfg_ok_max` |
| `dup-name` | 5 | `nv_reloc_bad_refused` ×3, `nv_smemcfg_too_big` ×2 |
| `control` | 4 | `nv_slm_early_{0,1_have32,33_have32}`, `nv_notifier_absent_from_table` |

**7 of the 9 `message` LIES have the value `""`:** `nv_reloc_msg_2`,
`nv_launch_msg_ok`, `nv_dims_msg_ok`, `nv_vid_msg_ok`, `nv_smemcfg_msg_0`,
`nv_smemcfg_msg_big`, `nv_reloc_msg_%d`. These are **the no-raise arm of the oracle's own
`try/except`** — the exact shape `agent-core.md` and this brief both name as *not a
defect*. **7 × 3 = 21 of nv's 144 points, ~15% of the score that put it at rank 1, is the
false positive.** The remaining 2 are real transcriptions (`nv_dims_msg_lz`,
`nv_vid_msg_none`).

**Two `dup-name` groups are real shadows and one of them loses a row:**

- `nv_smemcfg_too_big` is emitted at `:1139` as `"False"` and at `:1141` as `"True"`.
  `rows()` keeps the LAST, so **the `"False"` row never reaches the gate.**
- `nv_reloc_bad_refused` is emitted **three** times (`:721` `"True"`, `:1159` `"False"`,
  `:1161` `"True"`). Two sites are invisible.

**27 of nv's 574 printed rows are duplicate names** (measured: 574 printed, 547 distinct),
so **9 emitted rows of `nv_iowr_*` and 18 others are invisible to the gate.** For
`nv_iowr_*` the two fixture tuples are the SAME 9 pairs, so no coverage is lost there;
for the others I did not check every pair.

---

# 5. FOUND BUT NOT FIXED

1. **`kn-noop-truth.py` builds a node CPython never builds.** Its two `RANGE`s have
   `len(src)==2` and a bare `AxisType` in `arg`; `UOp.range(4,(0,),UL)` has
   `len(src)==1` and `arg=(AxisType.UPCAST,(0,))`. It agrees with the port on the op name
   anyway. It is not on my write list conceptually (a *truth* script is) so I left it and
   am flagging it: **do not use it as a witness.** `notes/kn-truth.py` already says this
   in a comment; I re-measured it rather than trusting the comment.
2. **`nv_dims_msg_lz` and `nv_vid_msg_none`** are typed upstream f-strings and are not
   convertible (`raise` inside `exec`; `{self.device}` is a device repr).
3. **The 9 nv reimpl defs** — see the table in §2. Converting them would be trap #1.
4. **`reimpl-scan.py`'s 12-char canonical floor hides 5 more copies in `nv-oracle.py`**:
   `ok_dims`, `ok_prod`, `stage`, `_put`, `b7like`. Measured effect: `ok_dims` backs 11
   `nv_dims_*` rows and `ok_prod` backs 6. So **nv's reimpl surface is 9 defs / 22 sites
   as reported, and at least 14 defs / 39 sites in truth.**
5. **`uop/ops.bend` and `rebase-gate.py`** — under single ownership, not touched.
6. **`M3` in `kn-ops-mutate.py` moves 0 of 38** — a src-order swap on `pr2` is invisible
   to every row `kernel.bend` has. Reported as a blind spot, not closed with a row that
   encodes the current behaviour.

---

# 6. REPRODUCIBILITY

Nothing here needs `$TMPDIR` state. Every number above comes from one of:

| claim | command |
|---|---|
| kn `ops` derived | `python3 .agents/slop/notes/kn-truth.py` (twice, identical) |
| kn port lane | `./bin/bend tinybendygrad/codegen/kernel.bend` (38 rows, sha256 equal to the oracle's) |
| `ops` mutation table | `.venv/bin/python .agents/slop/kn-ops-mutate.py` |
| nv tranche baseline/after | `python3 .agents/slop/nv-oracle.py` → 574 lines / 547 names, 0 value disagreements |
| nv mutation table | `.venv/bin/python .agents/slop/nv-iowr-mutate.py` |
| ranking + counts | `.venv/bin/python .agents/slop/handtyped-rank.py`, `.venv/bin/python .agents/slop/handtyped-audit.py` |
| nv reimpls | `.venv/bin/python .agents/slop/reimpl-scan.py --oracle nv-oracle.py` |

**Files I changed:** `.agents/slop/nv-oracle.py` (the tranche),
`.agents/slop/nv-iowr-mutate.py` (new), this report, and the appended section of
`.agents/slop/notes/bend2-constraints.md`. **Nothing committed.**
`.agents/slop/notes/kn-truth.py` was already modified when I arrived; I verified it and
did not touch it.