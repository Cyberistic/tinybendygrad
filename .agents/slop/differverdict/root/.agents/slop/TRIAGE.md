# TRIAGE — the 21 preserved stray `.bend` copies

`.agents/slop/strays/working/` vs `.agents/slop/strays/origin/`, plus
`.agents/slop/strays/artifacts/`. **Nothing in `strays/` was deleted or modified.**
Nothing committed. Rule prefix for this unit: **TRIAGE-01..** (see `triage/NOTES.md`).

## Instruments, and what they were asked

| question | instrument | note |
|---|---|---|
| does the live tree equal the origin copies? | `cmp`, 21/21 | **0 mismatches** — the live tree *is* the origin baseline |
| is it green now? | `.agents/slop/e2e.sh` | rc **0**, `-- verdicts: 0 failed, 0 skipped --` |
| does a file parse? | `substrate-check.sh` half 1, all 137 `.bend` | **14 COLD / 0 names-BAD**, matching `agent-core.md`'s table |
| are the cold claims true? | re-measured both sides | reproduced the 6 COLD / 1 SAME / 14 WARM table **exactly** |
| why is each of the 6 cold? | `bend --check-only` line 2 | every one named by the compiler, below |
| does a change depend on another | `substrate-check.sh` half 2, whole tree | `refs=36407 exact=36407 unresolved=0` before **and** after |

`substrate-check.sh`, `helpers.bend`, `dtype.*`, `e2e*`, `LAWS/**`, `PROOF*`, `tinygrad/**`
and the other unit's slop trees were **not** edited. `helpers.bend` was only read.

## THE TABLE — 21 files

`+/-` is line delta origin→working. `W/O` is `bend --check-only` on working / origin.

| # | file | +/- | W/O | class | the evidence, one line |
|---|---|---|---|---|---|
| 1 | `codegen/__init__.bend` | +1/−1 | COLD/WARM | **DAMAGE** | `Rewritten.capped`'s body is the token `NoSuchDef(1)`; compiler: `expected : a defined name / observed : NoSuchDef`. Not a Bend expression — nothing to complete. |
| 2 | `codegen/gpudims.bend` | +1/−1 | WARM/WARM | **DAMAGE** | `rs_claimed` swaps `O.eq_axis(at, O.AXIS_LOCAL{})` → `Bool.and(False{}, False{})`; `Bool.or(x, False) == x`, so LOCAL can never be claimed. The 4 comment lines above name LOCAL/WARP/LOOP/WEAK/DEVICE as the negative cases. |
| 3 | `codegen/late/linearizer.bend` | +2/−71 | WARM/WARM | **DAMAGE** | Deletes the whole `lt_edg` family (`lt_pos.of`, `lt_pos`, `lt_epos.go`, `lt_epos`, `lt_edg.piece`, `lt_edg.go`, `lt_edg`, `lt_lin_edg`, `lt_linc_edg`) + rows `lin_edg`/`linc_edg`. Its own deleted comment calls it "**THE ROW `lin_srcs` COULD NOT BE**" — the only instrument that can see a permuted src list (CPython moves 2/0/20/6/9/3/10 rows). Also reverts `u32_none()` from `O.ParamArg.no_slot()` to a literal `4294967295` and deletes the comment explaining the shared binding. |
| 4 | `codegen/simplify.bend` | +2/−1 | WARM/WARM | **DAMAGE** | `fr_off`'s 4th arm gains `O.OpsLINEAR{}`, so LINEAR answers **1**. The comment 20 lines above cites `ops.py:58 = {STAGE:1, REDUCE:1, END:1, CALL:1, LINEAR:0}` and says "FIVE OPS ANSWER 0 -- LINEAR plus every op OUTSIDE the dict", and a row `fr_off_linear` exists to catch exactly this. |
| 5 | `device.bend` | +1/−1 | WARM/WARM | **DAMAGE** | `pmb_cond1` replaces its second conjunct `Pn.named_b(n)` with `True{}`. The def is rule 1, `UPat(Ops.PARAM, tag="program", name="b")`; it no longer tests the name. |
| 6 | `engine/jit.bend` | +4/−4 | WARM/WARM | **DAMAGE** | Four independent breaks: `execs_thresh` 10→11 under the comment "a 10-CALL linear prints"; `jit_mode.at1` arm `2`→`1`; `jit_mode.at2` drops its `off` arm; `jt_refusal.at` drops its `r` passthrough. The last two leave `off` and `r` as **unused parameters**. |
| 7 | `renderer/amd/dsl.bend` | +1403/−2 | COLD/WARM | **DAMAGE** | `duplicate declaration: VOP2_ALL` at :1741. `dsl_gen.py` truncates at `MARK` but re-appends `FIXTURES`, so it is **non-idempotent**: "THE FIXTURE" headers are **1 at origin, 7 in the copy** = 6 extra runs. The copy's own comment says a fixture written after the marker is deleted on the next run — it was inserted where the generator will destroy it. |
| 8 | `renderer/amd/generate.bend` | +99/−13 | COLD/WARM | **DAMAGE** | `duplicate declaration: gl.go` at :2564 — the same 20-line block appended 6× (4→10 headers). It also **deletes `def g(...)`**, the row emitter its own deleted comment calls necessary ("a count row would be identical for a dropped member, a dropped alias, a swapped `default=NULL` and a reordered field"), while the appended blocks still call it. Plus `arg3_names[16]` `"default=3"`→`"default=1"`, `repr_str` loses both quote calls, `skip_cls` loses the `"DPP"` disjunct. |
| 9 | `renderer/amd/sqtt.bend` | +454/−404 | COLD/WARM | **DAMAGE** | Same `duplicate declaration: VOP2_ALL` at :1741 — the appended block re-declares names that live in `dsl.bend`, which it imports. |
| 10 | `runtime/autogen/libclang.bend` | +227/−27 | COLD/COLD | **REAL WORK — APPLIED** | See the gate below. |
| 11 | `runtime/ops_cpu.bend` | +1/−68 | WARM/WARM | **DAMAGE** | Deletes `cpu.lib_objc()`, `cpu.link_libs()`, `cpu.link_libs_n()` and 7 gate rows (`cpu_lib_objc`, `cpu_link_libs_00/10/01/11`, `cpu_link_libs_n`), plus the `dyld_info` evidence that motivates them. `elf.bend:10` and `objc.bend:55` still document the missing-`libobjc` link set → the tree contradicts itself. Compiles; loses 7 rows. |
| 12 | `runtime/ops_disk.bend` | +3/−3 | WARM/WARM | **DAMAGE** | `open_direct` drops the `has` disjunct under the comment "**TWO variables, not one**"; `map_locked` swaps its two `Bool.pick` arms so it now disagrees with the untouched `map_populate` **one line below**; `Lst.step` drops `Bool.or(seen, …)`, i.e. de-duplicates nothing. |
| 13 | `runtime/support/am/ip.bend` | +456/−0 | WARM/WARM | **DAMAGE** | Pure append: "THE MUTATION TABLE. MEASURED, NOT ASSERTED." in which **every count is zero** — "0 LOGIC mutations, 0 of 0 move rows", "0 constants, 0 moving", "0/0" — closing "**0 BLIND SPOTS SURVIVE**". It also claims "the 46 unread constants the sweep found were DELETED" while the diff is `+456/−0`: nothing was deleted. `ip_mutate.sh` and `ip_sweep.py` both exist, so the instruments exist and produced nothing. |
| 14 | `runtime/support/autogen.bend` | +28/−48 | COLD/WARM | **DAMAGE** | Rewrites `colons_to_underscores` to a fixed stride of 2; bend rejects it — `expected : 1 patterns (one per scrutinee) / observed : 'c1 c2 rest'` at :745. A list pattern destructures exactly one element, so the stride-2 form is **inexpressible**; the deleted pending-state version was total (a lone trailing `:` survives). Also permutes `uints()` (`ty_uchar` ↔ `ty_char_u`), and `ints` is derived from it. |
| 15 | `runtime/support/compiler_amd.bend` | +2/−2 | WARM/WARM | **DAMAGE** | `C.hipcc_key`'s `Bool.pick(String, nohipcc, "_nohipcc", "")` → `Bool.pick(String, nohipcc, "", "")`: both arms identical, so `nohipcc` becomes an unused parameter and the `nohipcc` cache key **collides with the normal one**. Plus `-Wno-missing-prototypes` dropped from `h.options`. |
| 16 | `runtime/support/compiler_mesa.bend` | +1/−1 | WARM/WARM | **DAMAGE** | `String.drop(arch, 3n)` → `2n`, directly under the comment "`arch[3:]` -- drop exactly three characters, no more and no fewer". Upstream `tinygrad/runtime/support/compiler_mesa.py:59` is `int(arch[3:])` and `:79` is `SM{self.arch[3:]}` — **3 is right, 2 is wrong**. |
| 17 | `runtime/support/nv/ip.bend` | +28/−38 | WARM/WARM | **DAMAGE** | A revert to a pre-`hcq2`-port state. The copy's header says `hcq2.bend` "is still a 29-line STUB … I have NOT picked a side" and calls `ops_nv.bend` 3897 lines. Measured: **`hcq2.bend` is 2348 lines / 275 defs, `ops_nv.bend` is 3960 lines** — origin's prose is current, the copy's is falsified by the tree. It also renames 5 identifiers in prose back to pre-rename spellings (`q.init`, `q.ring_len`, `q.rx_hdr_off`, `over.fixtures_fit`, `ip_nm_first`). |
| 18 | `runtime/support/nv/nvdev.bend` | +313/−358 | COLD/WARM | **DAMAGE** | Replaces **313 of 374** gate-row calls (`IP.urow`/`IP.srow`/`IP.row`) with 313 bare `String.concat([…])` expressions that print nothing and are not rows; the first leaves a dangling `,` at :1194 (`expected : 'def', 'type' or 'law' / observed : ','`). This **is** the file's entire gate. |
| 19 | `runtime/support/usb.bend` | +179/−41 | WARM/WARM | **PARTIAL** | One measured fix — `21 enum_libusb_* dicts` → **22**, and upstream `grep -oE 'enum_libusb_[a-z_0-9]+' tinygrad/runtime/autogen/libusb.py \| sort -u \| wc -l` = **22** (also 22 `@c.record`), so origin's own sentence already contradicted itself. But it also changes "twenty-one user-visible strings" → "nineteen" with **no measurement, and both are wrong**: the port emits **22** distinct `usb_str*`/`usb_msg*` row names in *both* copies. One correct edit + one edit that is falsified by the port's own rows + a 129-line doc-only append (`usb-seam.py` exists). Not correct-and-complete → left in `strays/`. |
| 20 | `schedule/prepare.bend` | +3/−3 | WARM/WARM | **DAMAGE** | Three edits to a generated pattern table, **each leaving its own trailing `# …` comment stale**: adds `O.OpsCONST{}` to the ALU arity list while the comment still reads "… WHERE XOR"; slot `2 END`→`2 STORE` while the comment reads "2 END"; slot `10 REDUCE`→`10 WHERE` while the comment reads "10 REDUCE". |
| 21 | `uop/fold.bend` | +6/−3 | WARM/WARM | **DAMAGE** | 3 of 4 edits are damage and 1 is a no-op. `mm.u64.add` replaces the carry `mm.u32c(al, bl)` with `0`, destroying 64-bit addition's carry-in. `mm.bin.enter` flips `Bool.and(O.GroupOp.binary(op), dt_is.not_float(d))` to `Bool.or` — intersection to union. Two blank lines added at :3254. The fourth, `mm.lift.mv`: `mm.s0(srcs)` → `mm.src2(srcs, 0)` is **semantically identical** — `mm.s0` *is* `def mm.s0(+xs) = mm.src2(xs, 0)` at :3499. |

**Tally: 19 DAMAGE · 1 PARTIAL · 1 REAL WORK.** Plus 6 artifacts, below.

## THE ONE APPLIED: `runtime/autogen/libclang.bend`

The coordinator's premise was that this +200 sat in a generated product whose repair belongs
in the generator layer. It does — and **origin is the copy that is out of step with its own
generator.** Three independent facts, all measured:

1. `apply-port-lane.py --check` on the **live** file printed **`OUT OF SYNC`** (rc 1).
2. `fix(live) == working` **byte-for-byte**: 63,334 B → 71,324 B, md5 `04199adf44475397189de8aa36e4b943`,
   which is exactly the md5 the coordinator recorded — **that md5 belongs to the preserved copy,
   not to the file in the tree.**
3. `fix` is idempotent, so the layer converges.

So the restore rolled a correctly generated product back to a stale one. The repair was applied
**at the generator layer** — `python3 .agents/slop/clangshim/apply-port-lane.py`, no `--check`,
not one byte of hand editing — and the result is byte-identical to the preserved copy.

**Is the +200 in the product or only in its header? IN THE PRODUCT.** The header grows
24 → 56 lines (+32); the body differs by **184 lines**. The substantive repairs are all body:
`type Ty` declared (it is the return of all 60 `ty_*` defs and was declared nowhere), 13 ABI type
names added (`F64`/`I64`/`U64` among them), `type U32 is Data` and `type Unit is Data` **removed**
(they redeclared Base's own — `duplicate declaration: U32`), `clang_Type_getObjCEncoding(type:…)`
→ `_type` and `clang_getCursorKindSpelling(Kind:…)` → `_Kind` (`type` and `Kind` are Bend keywords),
and the FFI lane appended at the foot. Header: +32 of 200.

**Does a +32 header move every `file:line` citation into the file? Yes — and here it is harmless.**
There are **7 distinct** `libclang.bend:LINE` citations (12 occurrences), all in `.agents/slop`
prose (`.py`, `STAGE1/2/4.md`, `CLANGSHIM.md`, `SPELLING.md`, `W64-MILE.md`,
`notes/bend2-constraints.md`), **0 in `.bend` source, and 0 files import `libclang.bend`**, so
nothing compiled can shift. Measured target by target: `:15`/`:19` were inside the old header and
now land on different header prose; `:95` (`ty_CXIdxClientEntity`) is now `:127`; `:1080` is now
`:1112`; and **`:617`, `:638`, `:641` were already blank lines at origin** — 3 of the 7 were stale
before this unit touched anything. After regeneration they land on real defs, which is a
coincidence, not a repair.

### The gate, before and after

This file **cannot** go to WARM under `--check-only`, and did not need to: it is S-1, a `.bend`
importing only `.c`, and it reads `SOME PROOFS FAIL` on **both** sides. The 11 foreign laws are
the **same 11, same cause, before and after** (`diff` of the two lists: identical). So half 1 is
the wrong instrument here and the build lane is the right one — which is what `agent-core.md`
records for exactly this file.

| leg | origin `07383541…` 63,334 B | regenerated `04199adf…` 71,324 B |
|---|---|---|
| `bend --check-only` | `SOME PROOFS FAIL`, 11 foreign laws | `SOME PROOFS FAIL`, **identical** 11 — no regression |
| **`bend -o out.c`** | **rc 1, 0 lines emitted** | **rc 0, 5,503 lines emitted** |
| `cl-port-gate.py` (the lane's own gate) | — | **rc 0, `FAILURES: 0`**, `ROWS shared 10/10`, `0 port-only, 0 oracle-only`, `offof_bytes*8==offof_bits` on 3/3 FIELD rows, `FIXTURE port=57B oracle=57B same=True` |
| `apply-port-lane.py --check` | `OUT OF SYNC` | `IN SYNC` |
| whole tree, 137 files, half 1 | 14 COLD, 0 BAD | **14 COLD — the same 14**, 0 BAD |
| whole tree, half 2 | `refs=36407 exact=36407 unresolved=0` | **identical** |
| `e2e.sh` | rc 0, 0 failed / 0 skipped | **rc 0, 0 failed / 0 skipped** |

The whole-tree gate output diffs in exactly two lines, both about this file and both expected:
its line count (1298 → 1498) and `unseen` (46831 → **46846**, +15, the unqualified `Foo.bar`
references the 15 new type declarations introduce — the instrument prints its own blind spot, so
read the `unseen` number, which I did). No other file's verdict moved.

**S-6 is NOT in this copy.** `helpers.bend:1167` occurs exactly **once**, in `renderer/amd/dsl.bend`
— count **1 at origin and 1 in the copy**. It is a pre-existing committed defect at
`dsl.bend:64`. The real line is **`helpers.bend:1639`** (`type I64 is Data:`, with
`I64{hi: U32, lo: U32}` at `:1640`); `helpers.bend:1167` is a comment about a reversed list.
`helpers.bend` is off-limits to me, so this is **reported, not fixed**.

## THE 6 ARTIFACTS — all DAMAGE, none appliable

| artifact | what it is | evidence |
|---|---|---|
| `elf.bend.mut` | a backup of a **generated** file (`elfbuild.py`) | md5 `1a37024e…` **== live `elf.bend`** — zero information |
| `memory.staged-mem-33281` | editor staging temp + PID | `ASPACE_PHYS_VAL() 1 → 0`. The port's own predicate `aspace_val_is_ix_plus1` (`:627`) requires `val == ix + 1` with `ASPACE_PHYS_IX() = 0`; the copy breaks its own named invariant |
| `memory.staged-mem-33929` | ditto | `Mv{h, addr, nbytes, fmt}` → `Mv{addr, nbytes, h, fmt}` — a **record field-order permutation**, which `agent-core.md` calls "a silently wrong register write" |
| `memory.staged-mem-44257` | ditto | `"size next prev is_free"` → `"size prev next is_free"`; upstream `tinygrad/runtime/support/memory.py:39` reads `# size, next, prev, is_free` — origin is right |
| `ops.staged-blob-24323` | ditto | `+406/−2413` vs live `ops.bend` (6306 vs 8313 lines). That is `ops.bend` at an **earlier** state, not a candidate change; 2,413 lines were removed from it since |
| `trip` | — | **0 bytes** |

Three mutually distinct one-line variants of one file, under three PIDs, none matching the tree.
None of the six names a `.bend` file among the 21, so they are separate from the triage itself.

## WHAT I COULD NOT CLASSIFY, AND WHY

Nothing. Every one of the 21 got a class with a named instrument behind it, and the one I could
not have established — whether `usb.bend`'s string count was 19 or 21 — is why that file is
PARTIAL and not REAL WORK, rather than a gap in the triage. Per the brief, **nothing in `strays/`
was deleted**, and nothing outside `libclang.bend` was touched.

## THE PATTERN, because it is the finding

Nineteen of twenty-one are **character-level semantic edits that keep the file compiling**: an
`and` flipped to `or`, a disjunct dropped, a carry replaced by `0`, two `Bool.pick` arms swapped,
a record field order permuted, a list constant transposed, a parameter left unused, a gate row
count turned into a dead `String.concat`. Six more are **non-idempotent generator appends**
(`dsl_gen.py` ×6 runs, `generate.bend`'s block ×6, `nvdev`'s row-strip) and one is a **mutation
table reporting 0/0 as a pass**. A unit killed mid-flight leaves a file that does not parse or a
file with an unfinished block; **these files parse, and are wrong in ways the gate cannot see**,
which is the exact failure mode this repo has catalogued: "a file that compiles can still be
missing a name something else needs", and "a pattern that stops matching does not fail, it falls
through".

So the practical reading of this set is not "21 files of progress were lost". It is **one real
change was lost, and the restore was correct for 20 of the 21 files and wrong for exactly one** —
in the opposite direction from what was assumed.

## Files I wrote

`.agents/slop/TRIAGE.md`, `.agents/slop/triage/NOTES.md` (method + rules TRIAGE-01..06),
`.agents/slop/triage/d/*.diff` (21 unified diffs, ~350 KB), `gate-BEFORE.txt`, `gate-AFTER.txt`,
`allfiles.txt`. **Nothing committed.**
