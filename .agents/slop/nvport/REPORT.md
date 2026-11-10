# `ops_nv` and `ops_nvme` — the two EMPTY runtime backends, brought to life

**Unit:** bringing the NVIDIA backends up.
**Date:** 2026-11-10.
**Commits:** `90de86caa`, `fa7dec063`, `20489e37e`, `50c90ed4d`, `5ed9f4e37`.

---

## 0. THE BRIEF'S PREMISE WAS WRONG, AND THAT CHANGED EVERYTHING

The brief said:

> `tinybendygrad/runtime/ops_nv.bend` exists but is **0 LINES**

**Measured: it was 94 lines, and every one of them was a COMMENT.** The
3960-line body had been **deleted**, and the 94 lines were a *header describing
the deleted work*.

### Where the body went

```
git log --format=%H -- tinybendygrad/runtime/ops_nv.bend
for each commit: git cat-file -p <commit>:<path> | wc -l

524737e35  2026-10-01  3837   the port lands
c10f65901  2026-10-01  3897
d2cde2f2c  2026-10-02  3960
d5783a8ff  2026-10-06  3962   the LAST commit with a body
564733bed  2026-10-06    94   <-- THE DELETION
e51904b04  2026-10-06    94
813bbec3e  2026-10-07    94   the RECOVERY, which restored the TOMBSTONE
056eeb1d5  2026-10-23    94   citation re-pointing, on the tombstone
```

`git show --stat 564733bed -- tinybendygrad/runtime/ops_nv.bend`:

```
tinybendygrad/runtime/ops_nv.bend | 3869 +------
1 file changed, 1 insertion(+), 3868 deletions(-)
```

That commit's own subject: it added
`.agents/slop/arghalf/pin-tree/tinygrad` — **1378 files, 817,650 insertions**,
a pin-tree snapshot. **The port file was collateral.** Its ONE insertion is
the last `TODO` line; the whole body went with it.

### The same commit did it to three more port files

`git show --numstat 564733bed` — every file that lost more than 100 lines:

```
tinybendygrad/engine/jit.bend       -1283
tinybendygrad/renderer/cstyle.bend  -1058
tinybendygrad/nn/__init__.bend       -595
tinybendygrad/runtime/ops_nv.bend   -3868
```

`jit.bend` (444 lines now) and `cstyle.bend` (3207) have since been rewritten.
`nn/__init__.bend` is 433 lines with 36 code lines. **`ops_nv.bend` was the
one that stayed a tombstone.** The other three are **not my task** and are
**reported, not fixed**.

### The tombstone's claims were false

The 94-line header said *"3960 lines, 630 `def`/`type`, 611 gate rows"* and
named **`.agents/slop/nv-diff.py`** — **a file that does not exist**.
`.agents/slop/` has `nv_gate.py` (18 lines; it appends a gate block to
`nvdev.bend`, a *different* file) and `nv-oracle.py` (1205 lines, the oracle).

---

## 1. `ops_nv` — END STATE **(A)** for the reachable part

### What was restored

`git cat-file -p d5783a8ff:tinybendygrad/runtime/ops_nv.bend` is byte-identical
to the tree's copy: sha256 `e2079915a0051b5cf3cc9ae74fb382f7418479f437e240d29085438e78a52637`.

**The header was NOT restored blind.** The tree's 94-line header is the
*newer* one (commit `056eeb1d5` re-pointed its citations to the constructs
they claim: `ops_nv.py:45 symbol=nvm` and friends); the recovered blob's
header is the *older* one (`(:47-48)`). **The merge is: the tree's 94-line
header + the recovered body from its line 95.** 3963 lines.

### Compile

```
.venv/bin/python checks/bounded.py --mb 3072 -- ./bin/bend tinybendygrad/runtime/ops_nv.bend
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=215 MB (ceiling 3072)  1s
```

### The gate

```
.venv/bin/python gates/ops-nv-gate.py
ops-nv-gate: 569 rows compared, 65 port-only -- rc=0
```

**569 compared rows, 0 disagreements.** 65 port-only names (generated, not
typed — see §5).

### The eleven duplicate names — fixed by NAMING, not by deleting

`.agents/TODO.md` had recorded eleven names printed twice as a known,
reported, do-not-touch defect. **A name printed twice is a row that cannot
be addressed**: the reader sees two values under one name and cannot tell
which site produced which, so a wrong one is not a wrong value but an
*unnameable* one.

| class | fix |
|---|---|
| `nv_iface_count`, `nv_encode_names` | deleted from `t_names()` — `t_iface()` already owns them, and the two are not different questions |
| `nv_pc_id_after_hit` | **two different fixtures under one name** — now `nv_pc_id_after_miss_hit` (a hit on a cache that does *not* hold the key) and `nv_pc_id_after_hit` (a hit on one that does) |
| `nv_slmtot_1_48428`, `..._hi` | the first site prints through `hilo.str32` (a saturating shift of a `U32`), the second through `H.i64_of_i32` + `H.i64_text` — **two independent paths to the same string** — so the second became `nv_slmtot_1_48428_i64` / `..._hi_i64` |
| `nv_slm_cmd` | both sites built the same trace with the same arguments; the second is `nv_slm_cmd_held`, and the claim it makes is the one the first *cannot*: that the trace is **held in a variable** and the variable's contents are the trace |
| five `nv_slmtot_*` | byte-identical re-emissions — the first site already prints each, **with** the `_hi` half the second lacked |

**Measured: 610 lines / 599 distinct names → 603 lines / 603 distinct names,
0 duplicates.**

### The oracle's defect — five weeks old, and the port was RIGHT

The first gate run was red with **two** disagreements:

```
port    nv_cpython_args_device_five = 0,4,8,12,16
oracle  nv_cpython_args_device_five = 0,8,16,24,32
```

Measured, by calling upstream:

```
layout_args([W32()]*5, 0)     -> [0, 4, 8, 12, 16]    <- the PORT
iter_sig(..., AddrSpace.ALU)  -> [0, 4, 8, 12, 16]    <- the PORT
iter_sig(..., an integer)     -> [0, 8, 16, 24, 32]    <- the ORACLE
```

and on the mixed fixture `[1,4,2,8,4,1]` — the only one that can see the
walrus — `iter_sig(..., AddrSpace.ALU)` → `[0,4,8,16,24,28]`, **exactly**
what the port printed.

The oracle's `dev_iter_sig` passed **an integer** as the addrspace field.
Upstream's `iter_sig` is `for _,a,dt,_ in signature: if a is not
AddrSpace.ALU: dt = dtypes.uint64` (`tinygrad/device.py:359-363`), so an
integer is not `AddrSpace.ALU` and **every entry was coerced to u64**.

**The fix deletes the oracle's second implementation of `iter_sig`** and asks
**upstream's own `layout_args`** — the function `hcq2.py:113-115` calls and
the one the port's `args.layout` models. Two implementations of one rule in
one file is two things that can be wrong, and the copy was the one that was
wrong.

### The four oracle-only rows are now ASSERTS

`nv_qmd_wide_v3/_v5` and `nv_qmd_straddle_v3/_v5` measured the two *generated*
QMD field tables. The port does not carry the 477 unreferenced fields, so a
Bend row for their width would be **a constant printing itself** — and
`gatekit.py` has no `oracle_only` category: `port_only` is "present in the
port, absent from the oracle" and `diverges` is "present in both, and the two
differ"; a row present in **only** the oracle is neither.

So the oracle now **asserts** them: it computes the counts from CPython's own
generated tables and **fails loudly** if either is nonzero. **That is
strictly stronger than the row was** — a row is checked by a diff against a
value the port prints; an assert fires when the *property* breaks. And the
property is load-bearing: the port's `qmd` module says a field lives in
exactly one `U32` word, and that is true only if both counts are zero.

### The MOCK path — and it is SOFTWARE

**Upstream's NV mock is a driver substitution**, not a different code path:
`test/mockgpu/mockgpu.py` intercepts `open()` and `ioctl()` at the Python
level, so `NVKIface.__init__` runs unchanged against a software driver. **It
needs no NVIDIA card**, it is in the vendored tree, and it imports cleanly:

```
.venv/bin/python -c "from test.mockgpu.nv.nvdriver import NVDriver; d=NVDriver(); print(len(d.gpus))"
-> 6
```

`MOCKIface` itself (`ops_nv.py:552`, `class MOCKIface(NVKIface): count = 1`)
inherits `NVKIface` whole and differs in **exactly one way**. Ported:

* **the count** — `MOCKIface.count = 1` is one line; `NVKIface.count` is the
  card's own GPU count
* **the selection** — `device.py:473`, *"never fallback to mock ifaces"*;
  measured: asking for a real interface leaves **2 of 3**, asking for a mock
  leaves **3 of 3**
* **the driver's answers** — the version (`nvdriver.py:208` answers
  `b"570.00.00\0"`), the GPU count (`NVDriver(gpus=6)`), the PCI device id
  (`0x2684`) and the class list's length; and the version picks the constant
  table (`ops_nv.py:357-359`), so **570 selects `nv_570` — the table the
  port's constants are read from**, a closed loop
* **the trace shape** — the mock's trace *is* the real one's trace

**22 of the 26 mock rows are CPython-compared**; 4 are port-only with the
reason in the name (two negative iface-name rows, two trace-shape rows).

**And the oracle caught a real port defect here**: the port's
`MOCK_CLASSLIST_N` first answered **fifty-five**; the driver's own class list
has **fifty-two** entries, read out of the driver's source rather than
counted from a transcription of it. Planted as P12 so it cannot come back.

### The plants — twelve, measured

| # | the edit | result |
|---|---|---|
| P1 | `nvm.word`: `typ << 28` → `<< 29` | **RED, 24 rows** |
| P2 | `arch_low.at`: `v >> 4` → `>> 1` | **RED, 7 rows** |
| P3 | `qmd.ver.of`: `>=` → `>` | **RED, 6 rows** |
| P4 | **the control**: a comment-only edit | **GREEN** — and it must be |
| P5 | `qmd.slot.ok`: `and` → `or` | **RED, 1 row** |
| P6 | `pc.find`: the miss sentinel `len` → `len+1` | **GREEN — AND THAT IS THE FINDING** |
| P7 | `iowr.cmd`: the 8 KiB size mask dropped | **RED, 3 rows** |
| P8 | `to_name.join.parts`: the separator doubled | **RED, 9 rows** |
| P9 | `dev.count`: the mock's 1 → 2 | **RED, 1 row** |
| P10 | `dev.iface_ok`: `Bool.not(is_mock)` → `True{}` | **RED, 2 rows** |
| P11 | `drv_table_of`: the 570 default → 580 | **RED, 5 rows** |
| P12 | `MOCK_CLASSLIST_N`: 52 → 55 | **RED, 1 row** |

**P6 is green and that is the finding.** `pc.find` answers `len` on a miss
and an index *below* it on a hit, so `found < len` and `found != len` are
**the same predicate** over every possible answer. The plant makes a miss
answer a value that is *neither* an index nor the length, and **every row
still passes**. This is the port's own mutation table's M13, **confirmed by
measurement rather than quoted**. The six `nv_find_*` rows that assert
`pc.find` are port-only — upstream's `_nv_program_cache` is a bare dict and
`pc.find` is the port's own model of it. **Closing it needs a fixture that can
see a miss's answer as a distinct value, and no such fixture exists yet.
Reported, not fixed.**

### What is still NOT ported, and it is the same list as before

The ioctl surface: `NVKIface.__init__` opens two device nodes and issues
three `rm_control`s; `rm_alloc`/`rm_control`/`uvm` marshal NVOS21/NVOS54/UVM
structs; the PMA register *values* are not ported (their *address arithmetic*
is); `_submit_cmds` builds and lowers a linear. **None of that changed.** The
file's own header names eleven as `TODO(p3)` and its footer names six more.

**And the mock does not change it either: the mock is a driver substitution,
not a different code path, so porting the mock's class does not port the
driver under it.**

---

## 2. `ops_nvme` — END STATE **(B)**, and the measurement that forced it

### Why (B) and not (A)

**There is no upstream NVMe mock.** Measured: `test/mockgpu/` has `nv/`,
`cuda/`, `am/`, `amd/` and **no `nvme/`**. There is no mock to run this
backend against, and that is a fact about the tree.

So the port is: **every rule that is arithmetic, ported and gated against
CPython**; and **every rule that needs a drive, named in the file's own
footer with the seam that blocks it** — nine of them.

**And what the port cannot claim: that any of this has run against a drive.
No row in this file is a hardware result and none is claimed to be.**

### Compile

```
.venv/bin/python checks/bounded.py --mb 3072 -- ./bin/bend tinybendygrad/runtime/ops_nvme.bend
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=199 MB (ceiling 3072)  1s
```

### The gate

```
.venv/bin/python gates/ops-nvme-gate.py
ops-nvme-gate: 206 rows compared -- rc=0
```

**206 rows, 206 compared, 0 disagreements, 0 orphans.**

### The oracle calls UPSTREAM'S OWN CODE, not a transcription of it

* `prp_table` is **upstream's own function**, run against a shim whose
  `pci_dev.alloc_sysmem` returns a `bytearray` — upstream's own code produces
  the entries
* `NVMEQueue.submit`'s `struct.pack("<IIQQQQII16x", ...)` is **upstream's
  own pack**, run against a shim whose `sq` is a `bytearray`; the slot, the
  tail, the packed word and the phase all come from upstream
* the constants are read out of `tinygrad/runtime/autogen/nvme.py` and
  `NVME_IDS` out of upstream

**The shim supplies no arithmetic.** A hand-typed expectation is a
transcription and a transcription is a place to be wrong — the
`renderer/cstyle.bend` unit shipped **215 hand-typed expectations of which
seventeen were wrong**, twelve of them real port bugs.

### The first gate run found FIVE real defects — four in the port

1. **`NVME_VENDOR` was 5591 and `0x15b7` is 5559.** A hand-converted hex
   constant.
2. **The capacity register was packed into one `U32`**, and `U32.shln(hi,
   32n)` **saturates to zero** — so the port's doorbell stride was always 4
   and its timeout was always the low word's. The register is sixty-four
   bits and the port now spells it as two words. Measured: `nvme_db_stride_cap1`
   answered 4 where CPython answers 8.
3. **The PRP address's low word came second.** The format is little-endian.
4. **`cdw10` and `cdw11` sat at words 8 and 9**, which is where the fourth
   sixty-four-bit field is. They go at **10 and 11**.
5. **Two row names disagreed with their values**: `nvme_sq_db_q1_s1` printed
   stride 8, and `nvme_cmd_w_2_0` printed slot 1. **A row whose name and
   value disagree is a row that cannot be addressed.**

**And the sixth was in the oracle**: it read a byte past the end of a
`bytearray` by indexing, which raises, where the port returns **zero**. A
Python `bytearray` and a port list are not the same thing at the end, and
the claim is about the port's answer.

### The plants — twelve, measured

| # | the edit | result |
|---|---|---|
| P1 | `q.sq_db`: the `2 * qid` stride → `qid` | **RED, 5 rows** |
| P2 | `q.next_phase`: the inversion → the old tail | **RED, 2 rows** |
| P3 | `prp_ptr`: the `(p + 1)` → `p` | **RED, 7 rows** |
| P4 | `wave_stride`: `entries - 1` → `entries` | **RED, 12 rows** |
| P5 | `lba_step`: the shift by `lba_shift` → zero | **RED, 4 rows** |
| P6 | `has_third_prp`: `== 2` → `>= 2` | **RED, 1 row** |
| P7 | `max_xfer`: the `min(..., 8)` cap dropped | **RED, 3 rows** |
| P8 | `lba_shift_index`: the `+ 2` dropped | **RED, 3 rows** |
| P9 | `sqe_words`: the PRP's halves swapped | **RED, 1 row** |
| P10 | `cap_timeout_ms`: the `* 500` → `* 1` | **RED, 2 rows** — **after the fix below** |
| P11 | `create_cdw10`: the `- 1` dropped | **RED, 4 rows** |
| P12 | **the control**: a comment-only edit | **GREEN** — and it must be |

**P10 was green on the first run, and that was a finding.** All four timeout
fixtures — 0, 1, 255 and 4194304 — **have byte 24 clear**, so all four
timeouts were **0** and the `* 500` multiplier was not measured at all. **A
plant that drops the multiplier moved zero rows**, and that is the class the
tree already names: *"a table with no row that CANNOT move is a table of
coincidences"*. The fixtures are now 0 (the zero case), 16777216 (byte 24 is
**1**) and 4278190080 (byte 24 is **255**), and P10 is red with 2 rows.

### What is ported, rule by rule

| upstream rule | what the port carries |
|---|---|
| `NVMEQueue.__init__` | entry sizes (64 and 16), entry count (64), tail's start (0), **phase's start (1)**, the two doorbells' `2 * qid` stride |
| `NVMEQueue.submit` | the command word (`opcode \| slot << 16`), the tail's modulo advance, **the phase's inversion on the NEW tail**, the SQE's 64-byte layout |
| `NVMEDev.__init__` | the capacity register's two halves, the stride (`4 << n`), the timeout (`* 500`), `max_xfer`'s `or 8` and its `min(..., 8)` cap, the `lba_shift` index (`128 + 4n + 2`), the size |
| `NVMEDev.new_queue` | the qid (`len(queues) + 1`), the create's **zero-based size field**, the two CDW11s |
| `prp_table` | the list page count (`ceildiv(n + 1, 256)`), the table's bytes, the entry count (**twice** the pages), the **interleaved** `(PAGE, POINTER)` pairs, the pointer's `(p + 1)` |
| `nvme_copies` | the command count (ceildiv), the `(full, rem)` split, the **shorter last command**, the wave stride of **`entries - 1`**, the slot and the command index, the PRP base (**16 bytes per page**), the LBA (**in blocks**), the page count, the **third PRP entry for exactly two pages**, the completion's slot and phase offset, the doorbell's value (**the next slot**), the wave count and the last wave's size |
| `loop` | **a loop of zero iterations is no instructions at all** |
| `NVMEAllocator` | `lru = False`, the **zero handle**, the page list's expansion, and the three preconditions on a read — **the `\|` is not `+`** in the block-alignment test |
| `NVMEIface` | the **in-use assertion**, which is a conjunction |
| `NVMEDevice` | **no renderers** and a **no-op `synchronize`** |
| `nvme_submit` | **the absence is an answer** |

And the nine walls are in the file's own footer, one per rule, with the seam
that blocks each.

---

## 3. The compile census's finding count

**Both files compile**, and neither was in the census before:

```
tinybendygrad/runtime/ops_nv.bend      WITHIN-LIMITS  rc=0  peak-RSS=215 MB  1s
tinybendygrad/runtime/ops_nvme.bend    WITHIN-LIMITS  rc=0  peak-RSS=199 MB  1s
```

`gates/compile-census-verdict.rows` is the tree's last committed census
(taken 2026-10-25) and lists **7 FAIL rows**, none of them mine — and it
lists `ops_nvme.bend` **not at all**, because the file did not exist then.
**The finding count does not grow.**

(The census's own file was too heavy to re-take here — a whole-tree compile
sweep — and the brief forbids it. The two files' own verdict tokens are the
measurement that covers them.)

---

## 4. `gatekit.py` — one additive parameter

`Gate` takes an opt-in `order`:

* **`"positional"`** (the default) — every existing gate is unchanged
* **`"by_name"`** — sorts each lane by row name before the diff

**The sort is by the name only** — the whole `name=value` line is kept
intact, so the diff still compares values and only the *alignment* changes —
and it is stable, so two rows with the same name keep their relative order.

**Why it was needed**: the port groups its rows by *rule* (21 test functions)
and the oracle groups them by *upstream source order*, so the same 569 rows
sit in two different sequences. Measured: **540 of 543 positions differ while
every value agrees.** A positional diff of that is a wall of "disagreements"
that are *zero* disagreements seen from the wrong axis.

**The cost is stated in the class docstring because it is real: a by-name diff
cannot see a row that moved.** The mode is only sound because the order of
the rows is not a claim of these gates — the order-bearing claims are the
*word* orders (the SQE's words, the PRP table's interleaving) and every one of
them is a row whose value is a comma-separated list.

---

## 5. The populations are GENERATED, not typed

`ops-nv-gate.py` asks the oracle itself — the generator of the population —
which names the port prints and the oracle does not, and asserts that the set
it compares against is the set it measured. The `ROWS` and `COMPARED` counts
are measured the same way. **A hand-typed list of 65 names is a list whose
every entry is a place the gate cannot see a change**, and the tree's own
rule is that a population is a generator's declaration or a walk, never a list
somebody wrote down.

---

## 6. The three harness failures, measured

The plant harness never edits the tree: it works on a copy in a scratch
directory and runs the **real** gate against the copy. Three failures, each
of which would have read as "the plant moved rows" if the harness had counted
a `REFUSED` as a `RED`:

1. `bin/bend` is a shim onto `references/bend/bend2/main.ts` and **resolves
   that path relative to itself** — so the scratch needs a `references/`.
   Without it: `REFUSED: Module not found ".../bin/../references/bend/bend2/main.ts"`.
2. The port's imports must be **present** — without them: `no such file:
   .../tinybendygrad/helpers.bend`.
3. And they must be **copies, not symlinks** — with them symlinked, the
   compiler refuses with *"an import path of plain names"*, because it
   resolves the import through the link and the resolved path is not a plain
   name.

And a fourth, from the `ops_nv` mock rows: the oracle reads
`test/mockgpu/` relative to the root, so the scratch must copy it too.

**A REFUSED is not a RED plant.** A harness that counted exit code 3 as "the
row moved" would have reported twenty-four load-bearing plants and measured
nothing.

---

## 7. Files

| path | what |
|---|---|
| `tinybendygrad/runtime/ops_nv.bend` | the restored + corrected NVIDIA backend (3963 lines, 603 rows) |
| `tinybendygrad/runtime/ops_nvme.bend` | **new** — the NVMe backend, (B)-shaped (1216 lines, 206 rows) |
| `gates/ops-nv-gate.py` | the NVIDIA gate (569 rows, 12 plants) |
| `gates/ops-nv-oracle.py` | the NVIDIA oracle — CPython-generated, with the mock driver read directly |
| `gates/ops-nvme-gate.py` | the NVMe gate (206 rows, 12 plants) |
| `gates/ops-nvme-oracle.py` | the NVMe oracle — calls upstream's own `prp_table` and `submit` |
| `gates/gatekit.py` | **one** additive parameter, `order` |
| `.agents/slop/nvport/nv-plants.py` | the NVIDIA plants |
| `.agents/slop/nvport/nvme-plants.py` | the NVMe plants |

---

## 8. Honest summary

* **`ops_nv`: end state (A)** for everything not requiring hardware — 569
  CPython-compared rows, 0 disagreements, 12 plants measured, the mock path
  included and verified against the **software** driver. The ioctl surface
  remains a seam, exactly as before.
* **`ops_nvme`: end state (B)** — every pure rule ported and gated (206 rows,
  0 disagreements, 12 plants measured), and nine hardware rules named with
  the seam that blocks each. **No row is a hardware result and none is
  claimed to be.**
* **Neither backend has been run on hardware, and nothing here says it has.**
* The **reported, not fixed** items: the `pc.find` blind spot (M13, measured
  green), the `nv_reloc_bad_n` dispute, the three other files `564733bed`
  gutted, and the `nvdev.bend`/`ip.bend` walls that are not this task's.
