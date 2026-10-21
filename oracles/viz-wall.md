# `VIZ=1` — the wall table for `tinybendygrad/viz/serve.bend`

**Question.** A user asked whether `VIZ=1` is implemented. This is the answer, measured.

**Upstream** `refs/remotes/upstream/master` = `5c2bf39d6c4b6b201abdf2865dd4a14228de4e60`, file
`tinygrad/viz/serve.py`, **757 lines**. **Port** `tinybendygrad/viz/serve.bend`, **1967 lines**.
Nothing was fetched; the upstream side is the LOCAL ref.

**Instrument** `gates/viz-wall-gate.py` (new, beside this file's pins at
`gates/viz-wall-pins.rows`). It re-derives the table on every run: upstream's capabilities by
`ast` over the ref's blob, the port's by `os.walk(tinybendygrad/)` + `endswith(".bend")`.
**59 capabilities, 13 of them ROUTES** (also discovered — the path and `fmt` literals in
upstream's own `do_GET` and `get_render`).

    .venv/bin/python gates/viz-wall-gate.py            # the table + the verdict
    .venv/bin/python gates/viz-wall-gate.py --plant    # proves it goes red when a capability appears
    .venv/bin/python gates/viz-wall-gate.py --refresh  # rewrites the pins

Measured 2026-10-21T17:56Z. **10 PRESENT · 7 PARTIAL · 42 ABSENT** (the 42 include all 13
routes).

## THE ANSWER, IN ONE PARAGRAPH

`VIZ=1` is **not** implemented. The port's `serve.bend` is a **gate harness**, not a server: it
prints `name=value` rows for 10 helper functions it has ported (`shape_to_str`, `mask_to_str`,
`fmt_colored`, `enum_str`, `option`, `rel_ts`, `cpu_ts_diff`, `encode_mem_free`, `row_tuple`,
`device_sort_fn`, `get_arch`, `filter_keys`, `create_step`) and it **has no HTTP server, no
route table, and no oracle**. Every one of upstream's 13 routes is ABSENT, and the two
functions the question names — `get_profile` and `graph_layout` — are ABSENT too. The port's own
header says so at `serve.bend:4`: *"viz's LOGIC, without viz's SERVER"*.

**The port has no oracle.** `checks/vz_gate.py` is the gate for this file; it **REFUSES**
(exit 3) because its CPython oracle `checks/viz_oracle.py` is not on disk and has never been
committed (MEASURED: `git log --all -- checks/viz_oracle.py` returns 0 commits; the older
`.agents/slop/vz/` is gone too). So the **175** rows the port prints (MEASURED: 175
`row(...)`-family calls in `serve.bend`'s `main()`) have **nothing to be compared against**
today, and `gates/viz-wall-gate.py` is the instrument that replaces the missing one for the
question it can answer — the SHAPE of the gap, not the values.

## THE WALL TABLE

`serve.py:N` is the upstream line at `refs/remotes/upstream/master`; the port column is
`tinybendygrad/viz/serve.bend` unless it says otherwise. The last column is what must exist
**first**; `UP:` items are upstream capabilities, and the "0 live hits" figures are
MEASURED greps for the name in the port's `.bend` files, excluding comment lines.

| upstream capability | upstream | port | port file | what the gap needs first |
|---|---|---|---|---|
| `TCPServerWithReuse` | `serve.py:16` | **ABSENT** | -- | Bend TCP (`Base` has `TCP.listen`/`accept`/`send_bytes`/`recv_bytes`) + a listen loop |
| `HTTPRequestHandler` | `serve.py:22` | **ABSENT** | -- | the same TCP primitives + a request parser and a response writer |
| `create_step` | `serve.py:56` | **PARTIAL** | `serve.bend:511` | PRESENT in the port as a List of Kv |
| `VizData` | `serve.py:60` | **ABSENT** | -- | the port's `RewriteTrace` (upstream `uop/ops.py:1735`) -- 0 live hits in the port |
| `load_rewrites` | `serve.py:68` | **ABSENT** | -- | `VizData` + `_reconstruct` + `canonicalize_ast` + `create_step` |
| `GraphRewriteDetails` | `serve.py:91` | **ABSENT** | -- | the port's rewrite-record type -- 0 live hits |
| `shape_to_str` | `serve.py:99` | **PRESENT** | `serve.bend:577` | -- |
| `mask_to_str` | `serve.py:100` | **PRESENT** | `serve.bend:585` | -- |
| `fmt_colored` | `serve.py:101` | **PRESENT** | `serve.bend:594` | -- |
| `canonicalize_ast` | `serve.py:103` | **PARTIAL** | `serve.bend:602` | PRESENT in the port as `canonicalize_ast_is` |
| `tokenize_uir` | `serve.py:105` | **ABSENT** | -- | `render_uir` -- the port HAS it under upstream's PRE-2026-10-02 name, `print_uops` (`uop/render.bend:2794`) |
| `uop_to_json` | `serve.py:114` | **ABSENT** | -- | `srender` (upstream `ops.py:76`) and `word_wrap` (upstream `helpers.py`) -- 0 live hits each |
| `_reconstruct` | `serve.py:171` | **ABSENT** | -- | the port's serialized-UOp field table (`RewriteTrace.uop_fields`) |
| `get_full_rewrite` | `serve.py:179` | **ABSENT** | -- | `uop_to_json` + `tokenize_uir` + a unified-diff implementation (upstream `difflib`) |
| `get_sink_at` | `serve.py:195` | **ABSENT** | -- | `get_full_rewrite` |
| `enum_str` | `serve.py:204` | **PRESENT** | `serve.bend:633` | -- |
| `option` | `serve.py:209` | **PRESENT** | `serve.bend:643` | -- |
| `rel_ts` | `serve.py:211` | **PARTIAL** | `serve.bend:665` | PRESENT in the port as a `Maybe` |
| `cpu_ts_diff` | `serve.py:218` | **PRESENT** | `serve.bend:733` | -- |
| `flatten_events` | `serve.py:221` | **ABSENT** | -- | the port's profile-event family (`ProfileRangeEvent`/`ProfilePointEvent`/`ProfileGraphEvent`) -- 0 live hits |
| `timeline_layout` | `serve.py:232` | **PARTIAL** | `serve.bend:1037` | the 6th packed field (the float) -- `F32.bits` is available, so this is a WRITER, not a wall |
| `encode_mem_free` | `serve.py:257` | **PARTIAL** | `serve.bend:1160` | PRESENT in the port; only the `Exec` shape differs |
| `graph_layout` | `serve.py:265` | **ABSENT** | -- | `encode_mem_free` (PRESENT) + `rel_ts` (PRESENT) + the profile-event family |
| `soft_err` | `serve.py:295` | **ABSENT** | -- | an error carrier: the port's `Maybe`/`Result` substitutes for Python's exception |
| `row_tuple` | `serve.py:300` | **PRESENT** | `serve.bend:1542` | -- |
| `unpack_pmc` | `serve.py:310` | **ABSENT** | -- | the port's PMC blob layout (upstream `ProfilePMCEvent.blob`/`sched`) -- 0 live hits |
| `load_amd_counters` | `serve.py:337` | **ABSENT** | -- | `VizData` + `create_step` + the PMC/SQTT event types |
| `sqtt_timeline` | `serve.py:370` | **ABSENT** | -- | `map_insts` (upstream `renderer/amd/sqtt.py`) -- 0 live hits; the port HAS the packet tables (`renderer/amd/sqtt.bend`) |
| `device_sort_fn` | `serve.py:459` | **PRESENT** | `serve.bend:1240` | -- |
| `get_profile` | `serve.py:466` | **ABSENT** | -- | `flatten_events` + `graph_layout` + `timeline_layout` + `VizData` + `soft_err` |
| `load_nv_counters` | `serve.py:509` | **ABSENT** | -- | `VizData` + `create_step` + `ProfilePMAEvent` -- 0 live hits |
| `pma_timeline` | `serve.py:520` | **ABSENT** | -- | upstream's `extra/nv_pma.decode` -- a Python-only module, not in the port |
| `get_stdout` | `serve.py:538` | **ABSENT** | -- | a captured-stdout sink: Bend's `IO.print` writes to stdout |
| `get_elf_section` | `serve.py:545` | **ABSENT** | -- | the port HAS an ELF loader (`runtime/support/elf.bend:1578` `elf_loader`); it needs the SECTION READER over a byte blob |
| `get_arch` | `serve.py:549` | **PRESENT** | `serve.bend:1348` | -- |
| `amd_decode` | `serve.py:551` | **ABSENT** | -- | `detect_format` (upstream `renderer/amd/__init__.py`) -- 0 live hits; the port HAS `dsl.bend`'s `Reg`/`Inst` |
| `parse_branch` | `serve.py:565` | **PARTIAL** | `serve.bend:1334` | PRESENT in the port as `parse_branch_row` |
| `is_acc_operand` | `serve.py:571` | **ABSENT** | -- | `Reg` (`renderer/amd/dsl.bend`, PRESENT) + `OpType` (upstream `runtime/autogen/amd/common.py`) |
| `get_cfg` | `serve.py:581` | **ABSENT** | -- | `amd_decode` + `is_acc_operand` |
| `tokenize_asm` | `serve.py:606` | **ABSENT** | -- | `get_cfg` + `is_acc_operand` |
| `get_render` | `serve.py:624` | **ABSENT** | -- | every producer above: it is the dispatch that assembles them |
| `get_int` | `serve.py:684` | **PARTIAL** | `serve.bend:1360` | PRESENT in the port as `get_int_row` |
| `filter_keys` | `serve.py:686` | **PRESENT** | `serve.bend:535` | -- |
| `Handler` | `serve.py:688` | **ABSENT** | -- | `HTTPRequestHandler` + `get_render` + the route table |
| `reloader` | `serve.py:716` | **ABSENT** | -- | a file-mtime watch (`File` has no `mtime` in `Base`) + a process re-exec |
| `load_pickle` | `serve.py:727` | **ABSENT** | -- | a Python-pickle reader -- and a port-side trace/profile file format to read instead |
| route `/` | `serve.py:692` | **ABSENT** | -- | a static-file server + the vendored `index.html` |
| route `/assets/` | `serve.py:694` | **ABSENT** | -- | the static-file server + the vendored CDN blobs |
| route `/js/` | `serve.py:694` | **ABSENT** | -- | the static-file server + the vendored `js/` |
| route `/ctxs` | `serve.py:701` | **ABSENT** | -- | `load_rewrites` (the ctx list) |
| route `/get_profile` | `serve.py:704` | **ABSENT** | -- | `get_profile` |
| route `graph-rewrites` | `serve.py:628` | **ABSENT** | -- | `get_full_rewrite` |
| route `uops` | `serve.py:629` | **ABSENT** | -- | `get_sink_at` + `render_uir` |
| route `code` | `serve.py:635` | **ABSENT** | -- | `get_sink_at` + the port's renderer |
| route `asm` | `serve.py:638` | **ABSENT** | -- | `tokenize_asm` + `get_elf_section` + `amd_decode` |
| route `all-pmc` | `serve.py:656` | **ABSENT** | -- | `unpack_pmc` + `load_amd_counters` |
| route `prg-pmc` | `serve.py:665` | **ABSENT** | -- | `unpack_pmc` |
| route `sqtt` | `serve.py:666` | **ABSENT** | -- | `sqtt_timeline` + `get_profile` |
| route `prg-pma-pkts` | `serve.py:674` | **ABSENT** | -- | `pma_timeline` + `get_profile` |

## THE ORDERED DEPENDENCY LIST — AND IT IS DERIVED, NOT ASSERTED

The order comes from **upstream's own call graph**, extracted with `ast` over the same blob:
for every upstream `def`/`class`, the set of *other* upstream `def`s it mentions. Restricted to
the 29 ABSENT capabilities and topologically sorted (ties broken by upstream's line order), the
order is **total** — 29 of 29 placed, **no cycle left over** once `_reconstruct`'s self-edge is
dropped (it recurses; a self-edge is not a dependency).

    1.  TCPServerWithReuse   serve.py:16    --
    2.  HTTPRequestHandler   serve.py:22    --
    3.  VizData              serve.py:60    --
    4.  GraphRewriteDetails  serve.py:91    --
    5.  tokenize_uir         serve.py:105   VizData
    6.  _reconstruct         serve.py:171   VizData
    7.  load_rewrites        serve.py:68    VizData, _reconstruct
    8.  flatten_events       serve.py:221   --
    9.  graph_layout         serve.py:265   --
    10. soft_err             serve.py:295   --
    11. uop_to_json          serve.py:114   VizData, soft_err
    12. get_full_rewrite     serve.py:179   GraphRewriteDetails, VizData, _reconstruct, tokenize_uir, uop_to_json
    13. get_sink_at          serve.py:195   VizData, _reconstruct, get_full_rewrite
    14. unpack_pmc           serve.py:310   --
    15. load_amd_counters    serve.py:337   VizData
    16. load_nv_counters     serve.py:509   VizData
    17. get_profile          serve.py:466   VizData, flatten_events, graph_layout, load_amd_counters, load_nv_counters, soft_err
    18. pma_timeline         serve.py:520   --
    19. get_stdout           serve.py:538   --
    20. get_elf_section      serve.py:545   --
    21. amd_decode           serve.py:551   --
    22. sqtt_timeline        serve.py:370   amd_decode, get_elf_section
    23. is_acc_operand       serve.py:571   --
    24. get_cfg              serve.py:581   amd_decode, is_acc_operand
    25. tokenize_asm         serve.py:606   is_acc_operand
    26. get_render           serve.py:624   VizData, amd_decode, get_cfg, get_elf_section, get_full_rewrite, get_profile, get_sink_at, get_stdout, pma_timeline, soft_err, sqtt_timeline, tokenize_asm, unpack_pmc
    27. Handler              serve.py:688   HTTPRequestHandler, get_render
    28. reloader             serve.py:716   --
    29. load_pickle          serve.py:727   --

    then the 13 ROUTES, which need `Handler` and the producer each one serves.

**Where a unit should start.** Two of the three largest blockers are **DATA TYPES, NOT
ALGORITHMS**, and they gate almost everything above them:

1. **`RewriteTrace` / `TrackedGraphRewrite`** (upstream `tinygrad/uop/ops.py:1735` and `:1632`).
   0 live hits in the port. `VizData`, `_reconstruct`, `load_rewrites`, `get_full_rewrite`,
   `get_sink_at` and every route depend on it.
2. **The profile-event family** (`ProfileRangeEvent`, `ProfilePointEvent`, `ProfileGraphEvent`,
   `ProfileDeviceEvent`, `ProfileProgramEvent`, upstream `tinygrad/helpers.py`). 0 live hits.
   `flatten_events`, `graph_layout`, `get_profile`, `load_amd_counters`, `load_nv_counters` and
   `pma_timeline` depend on it.
3. **`get_profile`**, once (1) and (2) exist. It is the join point: it is what
   `route /get_profile` and `route sqtt` serve, and `get_render` calls it.
4. **`get_render`**, which is the dispatch that assembles the eight format producers.
5. **`Handler` / `HTTPRequestHandler` / `TCPServerWithReuse`**, which is the server, and then
   the 13 routes.

**The order CAN be derived, and it was.** The only place it cannot be is *within* the leaves
(1)–(2) and the AMD leaf-cluster (18)–(25): upstream's call graph does not order them
relative to each other, so a unit may take them in any order.

**The good news, and it is measured: MORE OF THE SUBSTRATE IS ALREADY PORTED THAN THE WALL
TABLE SUGGESTS.** `tinybendygrad/uop/render.bend:2794` has `print_uops` — upstream's
`render_uir` under the name it had before 2026-10-02. `tinybendygrad/renderer/amd/sqtt.bend`
(580 defs) has the SQTT packet tables. `tinybendygrad/renderer/amd/dsl.bend` has `Reg`/`Inst`.
`tinybendygrad/runtime/support/elf.bend:1578` has `elf_loader`. What is missing is the
**viz-level glue** and the two data-type families above, not the AMD machinery.

## `F32.to_bits` — IT IS **NOT** A WALL TODAY

`tinybendygrad/viz/serve.bend:102-112` claims:

> `bend 2.0.34's base has NO `F32.to_bits` … `match u { case U32{data: w}: }` is a PARSE
> ERROR … Base defines exactly ten `F32.*` and none is a bit cast. So the float's four bytes
> are the ONE thing this port cannot produce.

**Every clause of that is false of the tree as it stands**, and the falsifications are
inside the port:

| the claim | the measurement |
|---|---|
| "base has NO `F32.to_bits`" | `F32.bits` is a `law` in `references/bend/bend2/base.bend:1785`, and it is a COMPILER INTRINSIC: `comp.ts:227` `f32_bits: { C: "$0", JS: "f32_bits($0)" }`, `comp.ts:493` `new Uint32Array(new Float32Array([x]).buffer)[0]`. In the C lane it is the identity (the F32 is carried as its raw pattern); in the JS lane it is the IEEE-754 bit pattern. |
| "`match u { case U32{data: w}: }` is a PARSE ERROR" | `tinybendygrad/base.bend:54-56` is exactly that match: `def F32.from_bits(bits: U32) -> F32: match bits: case U32{data}: F32{data}`. It compiles, and `dtype.bend:608` calls it. |
| "Base defines exactly ten `F32.*`" | 10 `def F32.*` (min, max, clamp, lerp, square, hypot, round, pi, from_nat, to_nat) **and 36 `law F32.*`**. The census counted only the `def`s. |
| "none is a bit cast" | `F32.bits` **is** a bit cast (F32 → U32). |
| "the float's four bytes are the ONE thing this port cannot produce" | The port CALLS `F32.bits` in live code in six files: `tinybendygrad/dtype.bend:758,759,760,1129,1138`, `tinybendygrad/helpers.bend:909,912,918`, `tinybendygrad/renderer/tc_ptx.bend:299,311`, `tinybendygrad/mixin/elementwise.bend:995`, `tinybendygrad/mixin/gradient.bend:132`, `tinybendygrad/runtime/ops_python.bend:569,1844`, `tinybendygrad/runtime/ops_hip.bend:403`. |

**How the wall was reached.** The reasoning counted `grep '^def F32\.' base.bend` and stopped
at ten. The base declares its intrinsics as **`law`**, not `def`, and `F32.bits` is one of
them. A census that reads only one of the two declaration forms cannot see a bit cast.

**What it costs.** The port's `timeline_layout` packs **five** of upstream's six `<IIIIfI`
fields (`serve.bend:895` `tl_pack5` is five `pack_u32` calls), and `tl_row` substitutes
`st_ns=<et-st>` for the float. With `F32.bits` available, that sixth field is a WRITER, not a
wall. **The port's `timeline_layout` should be PARTIAL because it is unfinished, not because
it is impossible.** `gates/viz-wall-gate.py` reports this as the `f32.wall_claim` row and it
is RED today.

*(One caveat, stated because it is a real one: the JS lane's `f32_bits` collapses every NaN
onto `0x7FC00000`, because JavaScript's `NaN` is a single value. `tinybendygrad/base.bend:42-44`
records this. So a float's bits are available in the C lane EXACTLY and in the JS lane for
every non-NaN. That is a property of the JS backend, not of `F32.bits`, and no definition of
`F32.bits` can repair it.)*

## `op_color_len` — THE MEASURED VALUE IS **64**, AND THE LITERAL SAYS 65

    tinybendygrad/viz/serve.bend:1868
      row("op_color_len", String.concat([op_color_len(), "|65"]))

**Measured 2026-10-21T17:56Z**, by asking upstream's own module:

    .venv/bin/python -c "from tinygrad.uop.render import uops_colors; print(len(uops_colors))"
    64

and by replaying the port's OWN ladder (`uops_color` at `serve.bend:379-423`, `op_list` at
`:1485-1496`, `count_tinted` at `:1518-1524`) against upstream's dict:

* the port's `op_list` is **75** ops and is **the same set, in the same order**, as upstream's
  75 `Ops` members at HEAD (0 either way);
* the port's `GroupOp.movement` (5) and `GroupOp.alu` (28) are upstream's, member for member;
* the port's ladder yields **64** non-`#ffffff` entries, and **all 75 colours match upstream's
  `uops_colors.get(op, "#ffffff")` with ZERO mismatches**.

So the port's own measurement is right and the hard-coded expectation is wrong: the row would
read **`64|65`**.

**Where 65 came from.** The port was written against upstream `cff94ae8828dd05edc4743283800606a91f28b40`
(**2026-10-02**), where `GroupOp.Movement` still had **`Ops.FLIP`** (6 members, not 5) and
`Ops` had **77** members. `32 explicit + 6 Movement + 28 ALU − 1 (THREEFRY counted twice) = 65`.
The tree still carries that upstream revision, byte-identical, as **`checks/serve.py`**
(`git hash-object checks/serve.py` = `c59b5678924d3158811a7822825a4767ef26fd04`, which is
upstream's blob at `cff94ae8`). The port's `op_list` was later updated to 75 to match HEAD;
the literal and the prose were not.

**The one-token fix (NOT APPLIED).** In `tinybendygrad/viz/serve.bend:1868`, `65` → `64`:

    row("op_color_len", String.concat([op_color_len(), "|64"]))

That is the whole fix for the row. The prose at `serve.bend:1515-1517` is also stale and would
read "**64**, NOT 75: **eleven** ops carry no entry" — and `serve.bend:1471-1484` says
"SEVENTY-SEVEN OPS" where it is 75.

**The digest it would move.** `checks/differ.py:1210` `substrate_digest()` hashes the
`tinybendygrad/` and `tinygrad/` walks plus its named inputs, keyed on content:

| | value |
|---|---|
| `substrate_digest()` **now** | `10a0de50fc2c5851e08734e4fbf89556c42ac49fc6bfc3d172e92c354a7e3282` |
| `tinybendygrad/viz/serve.bend` sha256 now | `73905c926921d92127d27aba6d37f3b927f6dff78826ef30d06470a23b5e88ec` |
| the same file's sha256 after the fix | `2c5cc34df024ac8cebf73e26266114b6e7c40f0db5b8d509f00a2a92e0e84979` |
| `substrate_digest()` **after** the fix | `0aa56e6c60ff20d9bd14e892fa4a6f37226ff71615f023f6008e93b4e82c65bd` |

The digest is unchanged by this investigation, and that is worth saying: it equals the
`substrate-start`/`substrate-end` pair the green corpus run recorded
(`runs/graphcmp/D/D0-run-summary.txt:24-25`), so **the substrate has not moved since the
corpus went green**, even though `HEAD` has moved several times. Applying the fix would move
it, and the corpus would have to be re-run — which is why the fix is NOT applied here.

## THE HEADER'S LINE-COUNT CLAIMS — FALSE, AND THE TREE'S OWN INSTRUMENT SAYS SO

Instrument: **`gates/header-census-gate.py`** (run 2026-10-21T17:50Z, 1m33s, 4328 rows).
For `tinybendygrad/viz/serve.bend` it emits **32 rows**: **7 line-count claims** and **25
file:line citations**.

| the header's claim | the census's verdict | the measured truth |
|---|---|---|
| `:6` "serve.py is 771 lines" | `RESOLVES-AT-OLDER-REVISION` | `tinygrad/viz/serve.py` is **757** lines at HEAD; it had 771 at `a0fca89d2ab1` |
| `:19` "index.html 451 lines" | `STALE` | **465** at HEAD (451 held at `ed0848c05`) |
| `:20` "index.js 1,202 lines" | `STALE` | **1225** at HEAD (1202 held at `ed0848c05`) |
| `:21` "worker.js 122 lines" | `STALE` | **142** at HEAD (122 held at `ed0848c05`) |
| `:22` "assets 1,883 lines" | `STALE` | **1369** at HEAD; and the total was NEVER 1883 — the full history of `tinygrad/viz/assets` reads 6152, 6150, 2154, 2136, 1356, 1369 |
| `:26` "1,775 lines of hand-written browser code" | `STALE` | the census says "`tinygrad/viz/serve.py` … has NEVER had 1775 lines" — **and the census is looking at the WRONG FILE**. 1775 was `451 + 1202 + 122`, true at `ed0848c05` (2026-09-01) and **never true of `serve.py`**. It is **1832** at HEAD (465 + 1225 + 142). |
| `:27` "1,883 lines of minified vendor" | `STALE` | **1369** at HEAD; never 1883 at any commit |
| `:56` `serve.py:745-771` (`__main__`) | `DANGLING-LINE` | the file is 757 lines; `__main__` is at 731-757 |

Two of these need the honest caveat the census itself prints: the census resolves a header's
count against the header's **declared target**, which for `serve.bend` is
`tinygrad/viz/serve.py` — so a count about `index.html` is checked against the WRONG file and
comes out "STALE" for that reason. The truth, measured directly against upstream's blobs, is
in the third column above: **451/1202/122 were true at `ed0848c05` and are stale now; 1775
was the sum of those three and was true at the same commit; 1883 was never true of anything.**

The other 24 citations RESOLVE.

## WHAT WAS NOT DONE, AND WHAT WAS DELIBERATELY NOT DONE

* **No `.bend` file was edited.** A `.bend` edit moves `substrate_digest()` and would
  invalidate the green corpus. The `op_color_len` fix is therefore **named and not applied**,
  and the `f32` wall is **named and not corrected**.
* **Nothing was ported**, nothing was fetched, and neither `differ.py` nor `bend` was run.
  `substrate_digest()` was computed by importing `checks/differ.py` as a MODULE (its CLI is
  behind `if __name__ == "__main__"`) and calling the pure function — no corpus, no gate, no
  compiler.
* **The `op_color_len` replay** is a Python replay of the port's ladder, not a `bend` run. It
  is the port's own `uops_color`/`op_list`/`count_tinted` logic read out of the source and
  evaluated against upstream's dict, so it is a *static* measurement of the port's arithmetic,
  and it agrees with upstream on all 75 ops.
* **The AMD/SQTT/ELF leaf-cluster's internal order (18)–(25) is not derivable** from upstream's
  call graph, and no attempt was made to order it by other means.
* **`.agents/TODO.md` was not touched** (out of scope for this unit) and **no task was ticked
  off** there.
* `gates/viz-wall-gate.py` is **RED on arrival, on two rows**, and both are one-token fixes in
  a `.bend` file this unit may not edit: `op_color_len.literal` and `f32.wall_claim`. The
  capability-table lane — the lane the gate exists for — is GREEN, and `--plant` proves it
  goes red the moment a capability appears in the port.
