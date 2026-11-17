# COMMENT GAP AUDIT — does the Bend port carry upstream tinygrad's REASONING?

**MEASURED 2026-11-17 23:14** on
`tinygrad/` (the vendored upstream, 216 `.py` files) against `tinybendygrad/`
(198 `.bend` files). No file was edited; this is a read-only audit.

**METHOD.** Every contiguous `#` comment block in every upstream `.py` is one
row. The join key is the port's own citation: the port writes
`# <upstream>.py:<line> -- "<upstream's words>"`, so upstream `(file, line)`
resolves to the port comment block that cites it. A row is **PORTED** when a
port comment block carries that block's reasoning — a verbatim quote, or a
contiguous phrase of >= 4 content tokens, or a contiguous run of >= 3
distinctive tokens, in the port file that cites the upstream file (for cited
rows) or anywhere in the port (for uncited rows). A citation with no reasoning
is a **stamp**, not a port.

---

## 1. HEADLINE NUMBERS

| | count |
|---|---|
| upstream comment blocks (the population) | **2406** |
| of those, upstream files with NO port counterpart (`N/A-PYTHON-ONLY`) | 67 |
| **scored** (upstream file IS ported) | **2339** |
| **PORTED** (the reasoning is in the port) | **495** |
| **PORTED rate over the scored population** | **21.2%** |
| PORTED rate over the whole population | 20.6% |
| GAP-NO-CITATION | 1618 |
| GAP-CITED-NO-REASONING (a stamp) | 97 |
| GAP-DIFFERENT-REASONING (the port reasons, and says so) | 129 |
| **total gaps** | **1844** |

**Upstream files with a port counterpart: 136 of 216.** The 80 without are
`runtime/autogen/**` (generated C header bindings, 67 comment blocks total,
all of them a one-line `# NOTE:` on a generated table) plus `llm/hf.py`,
`llm/__main__.py`, `runtime/autogen/amd_gpu.py`.

**Gaps by upstream file** (the twenty biggest):

| upstream file | gaps |
|---|---|
| `uop/ops.py` | 139 |
| `renderer/x86.py` | 125 |
| `mixin/op.py` | 97 |
| `uop/symbolic.py` | 82 |
| `nn/onnx.py` | 61 |
| `uop/spec.py` | 51 |
| `llm/kernels/amd.py` | 50 |
| `renderer/amd/generate.py` | 49 |
| `llm/model.py` | 47 |
| `viz/serve.py` | 45 |
| `renderer/cstyle.py` | 40 |
| `runtime/support/hcq2.py` | 35 |
| `codegen/__init__.py` | 34 |
| `helpers.py` | 33 |
| `schedule/__init__.py` | 33 |
| `runtime/ops_amd.py` | 31 |
| `tensor.py` | 30 |
| `renderer/amd/sqtt.py` | 30 |
| `runtime/ops_nv.py` | 27 |
| `runtime/support/am/ip.py` | 27 |

**PORTED by upstream file** (the twenty best-covered):

| upstream file | ported |
|---|---|
| `schedule/multi.py` | 30 |
| `schedule/rangeify.py` | 30 |
| `uop/ops.py` | 30 |
| `schedule/indexing.py` | 29 |
| `schedule/prepare.py` | 29 |
| `codegen/__init__.py` | 27 |
| `codegen/decomp/transcendental.py` | 23 |
| `codegen/decomp/op.py` | 17 |
| `uop/__init__.py` | 17 |
| `codegen/late/coalesce.py` | 14 |
| `runtime/support/hcq2.py` | 13 |
| `codegen/decomp/dtype.py` | 13 |
| `codegen/late/regalloc.py` | 13 |
| `uop/symbolic.py` | 13 |
| `tensor.py` | 11 |
| `codegen/late/linearizer.py` | 10 |
| `renderer/wgsl.py` | 9 |
| `mixin/gradient.py` | 9 |
| `runtime/support/am/amdev.py` | 9 |
| `function.py` | 8 |

---

## 2. TOP TWENTY GAPS

| # | upstream | line | upstream says | verdict | what the port says instead | why it is a gap |
|---|----------|------|---------------|---------|----------------------------|---------------|
| 1 | `renderer/cstyle.py` | 536 | https://clang.llvm.org/docs/AttributeReference.html#amdgpu-flat-work-group-size NOTE: this | GAP-DIFFERENT-REASONING | `renderer/wgsl.bend:961` — ING pass fills in before it calls `string_rewrite.rewrite` (cstyle.py:245-250). So `ctx[x]` is not a fold and not a rewrite engine -- it is the CHILD'S TEXT, and the text is a parameter here | the port cites it and gives a different why |
| 2 | `renderer/llvmir.py` | 49 | scaled mfma call require E8M0 scale args, byte | GAP-NO-CITATION | `renderer/llvmir.bend:32` — d-bearing: `abi=`  `abi` IS upstream's own class attribute (llvmir.py:165), read at :177 and assigned `None` at :225 and `"amdgpu_kernel"` at :254. `abi=None` is the falsy case of `{' ' + se | no port comment cites this block; the upstream why is simply absent |
| 3 | `renderer/amd/dsl.py` | 428 | VOPD: FMAMK/FMAAK opcodes always require literal (check by | GAP-NO-CITATION | `renderer/amd/dsl.bend:21` — the deferred boundary, measured, and it is not this file. dsl.py:239-242 imports three GENERATED operand tables and merges them: tinygrad/runtime/autogen/amd/rdna3/operands.py   1522 lines t | no port comment cites this block; the upstream why is simply absent |
| 4 | `llm/model.py` | 368 | selected incomplete pools add only tail/future tokens, handled | GAP-NO-CITATION | `llm/model.bend:1` — tinybendygrad/llm/model.bend -- port of tinygrad/llm/model.py partial, and the split is the point. `llm/model.py` is 650 lines and almost all of it is `Tensor`/`nn` machinery: RoPE, four att | no port comment cites this block; the upstream why is simply absent |
| 5 | `runtime/ops_metal.py` | 30 | Opening METAL after LLVM doesn't fail because ctypes.CDLL | GAP-NO-CITATION | `device.bend:1090` — buffer for this alloc (`ops_null.py:77`, `ops_cl.py:123`, `ops_metal.py:238`). | no port comment cites this block; the upstream why is simply absent |
| 6 | `renderer/amd/generate.py` | 347 | also re-export HWREG/MSG enums (plain enums, not instruction | GAP-NO-CITATION | `renderer/amd/generate.bend:315` — SECTION 2 -- the CONFIG TABLES, generate.py:11-42.  PORTED AS DATA, in DECLARATION ORDER, and the order is load-bearing twice over: * `_FIELD_RENAMES` is a `dict`, so it is applied in INSERT | no port comment cites this block; the upstream why is simply absent |
| 7 | `llm/serve.py` | 46 | string-only templates need text parts joined and explicit | GAP-NO-CITATION | `llm/serve.bend:26` — serve.py:44-47 -- the router's four modes. Upstream carries them as `str`; the value is that they are COMPARED and never parsed, so a `U32` constant per mode is the same contract with less t | no port comment cites this block; the upstream why is simply absent |
| 8 | `llm/kernels/amd.py` | 81 | Only unwrap storage/order-preserving views, then require the exact | GAP-NO-CITATION | `runtime/support/amd.bend:4` — piler_amd.bend` uses for its comgr enum constants. TODO(p3) amd.py:34 -- `getattr(tinygrad.runtime.autogen.am, submod)`. TODO(p3) amd.py:36 -- `getattr(mod, children[-1])` over the real `__a | no port comment cites this block; the upstream why is simply absent |
| 9 | `runtime/ops_amd.py` | 214 | gfx11+ and later require even-numbered SQ *_SELECT registers | GAP-NO-CITATION | `helpers.bend:28` — vice.py:18, uop/ops.py:1623-1624, hcq2.py:18, ops_nv.py:27, ops_amd.py:31-34) and 85 more read through a bare `getenv("KEY", ...)`, and `Flags` implements THREE of the 61 ContextVars -- NO_C | no port comment cites this block; the upstream why is simply absent |
| 10 | `runtime/support/rdma/bnxtdev.py` | 23 | Thor2 static-mode retransmission indexes WQEs, not 16B slots. | GAP-NO-CITATION | `runtime/ops_rdma.bend:41` — THE NETLINK AND THE DRIVER (support/system.py, support/rdma/bnxtdev.py). `System.list_devices(*BNXT_IDS)`, `filter_visible_devices`, `PCIDevice` probing, `BNXTDev` firmware state and the mlx | no port comment cites this block; the upstream why is simply absent |
| 11 | `helpers.py` | 172 | ContextDecorator otherwise reuses self, so recursive calls overwrite | GAP-NO-CITATION | `device.bend:875` — _server` would hand one back. `round_up` is `(n+a-1)//a*a` (helpers.py:69). `(num+amt-1)//amt*amt` (helpers.py:69). The amount is read THREE times and `U32` is affine, so it travels in a rec | no port comment cites this block; the upstream why is simply absent |
| 12 | `helpers.py` | 616 | ContextDecorator otherwise reuses self, so recursive calls overwrite | GAP-NO-CITATION | `device.bend:875` — _server` would hand one back. `round_up` is `(n+a-1)//a*a` (helpers.py:69). `(num+amt-1)//amt*amt` (helpers.py:69). The amount is read THREE times and `U32` is affine, so it travels in a rec | no port comment cites this block; the upstream why is simply absent |
| 13 | `schedule/__init__.py` | 219 | NOTE: scheduling rewrites belong in prepare; only storage/interface | GAP-NO-CITATION | `renderer/__init__.bend:86` — `with_storage` -- __init__.py:11-13 def with_storage(x:UOp, dt:DType) -> UOp: if x.op in {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}: return x.replace(arg=replace(x.arg, dtype=dt)) return x.replace(s | no port comment cites this block; the upstream why is simply absent |
| 14 | `schedule/__init__.py` | 239 | NOTE: lambda for late binding, canonicalize_call_body references pm_canonicalize_alloc | GAP-NO-CITATION | `renderer/__init__.bend:86` — `with_storage` -- __init__.py:11-13 def with_storage(x:UOp, dt:DType) -> UOp: if x.op in {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}: return x.replace(arg=replace(x.arg, dtype=dt)) return x.replace(s | no port comment cites this block; the upstream why is simply absent |
| 15 | `llm/kernels/amd.py` | 173 | nontemporal scalar load: streamed weights must not evict | GAP-NO-CITATION | `runtime/support/amd.bend:4` — piler_amd.bend` uses for its comgr enum constants. TODO(p3) amd.py:34 -- `getattr(tinygrad.runtime.autogen.am, submod)`. TODO(p3) amd.py:36 -- `getattr(mod, children[-1])` over the real `__a | no port comment cites this block; the upstream why is simply absent |
| 16 | `nn/onnx.py` | 108 | need copy here because packed ints are varint | GAP-NO-CITATION | `nn/onnx.bend:8` — nn/onnx.bend -- tinygrad/nn/onnx.py (1230 lines). stage 1 -- what is ported, what is not, and which python lines the rest COVERS. Staged on purpose: this file is 40% of what is left to port, | no port comment cites this block; the upstream why is simply absent |
| 17 | `mixin/op.py` | 341 | shrink after for negative pads (reflection/replication must see | GAP-NO-CITATION | `tensor.bend:2009` — cause a row that cannot tell them apart cannot fail: `mixin/op.py:471`  `[self._wrap_uop(grads[x] if x in grads else x.const_like(0)) for x in target_uops]`  -- the ANSWER: one slot per targ | no port comment cites this block; the upstream why is simply absent |
| 18 | `runtime/ops_nv.py` | 447 | host memory keeps its cpu address unless the | GAP-DIFFERENT-REASONING | `helpers.bend:28` — 36-290 plus device.py:18, uop/ops.py:1623-1624, hcq2.py:18, ops_nv.py:27, ops_amd.py:31-34) and 85 more read through a bare `getenv("KEY", ...)`, and `Flags` implements THREE of the 61 Conte | the port cites it and gives a different why |
| 19 | `runtime/support/rdma/bnxtdev.py` | 125 | RoCE notification ring: never armed or serviced, but | GAP-NO-CITATION | `runtime/ops_rdma.bend:41` — THE NETLINK AND THE DRIVER (support/system.py, support/rdma/bnxtdev.py). `System.list_devices(*BNXT_IDS)`, `filter_visible_devices`, `PCIDevice` probing, `BNXTDev` firmware state and the mlx | no port comment cites this block; the upstream why is simply absent |
| 20 | `codegen/opt/postrange.py` | 260 | NOTE: hand_coded_optimizations doesn't support multiblock opts yet | GAP-NO-CITATION | `codegen/opt/heuristic.bend:15` — Scheduler.upcast_size` -- the SAME fold at search.py:84 and postrange.py:82. It is here because `heuristic.py:115` guards the MORE-UPCAST loop on `k.upcast_size() < 32`, so it is the block's | no port comment cites this block; the upstream why is simply absent |

---

## 3. BLOCKS THE PORT PORTED WITH **DIFFERENT** REASONING

**129 blocks.** This is the most valuable list in this report: a port
that reasons differently **and says so** is better than a port that copies.
Each row below is an upstream comment the port CITES, does not restate, and
replaces with its own why.

| upstream | line | upstream says | the port says (and where) |
|---|---|---|---|
| `device.py` | 259 | check if old most is free | `device.bend:769` — ALLOCATORS. `Allocator` (device.py:259) is the cache, and the cache has ONE policy: `free` recycles a storage when it is reusable and drops it otherwise, and `alloc` hands back the MOST RECENTLY freed. That is LIFO, and getting it wrong is invisible until it matters, which is why `alloc_take` is a f |
| `device.py` | 274 | add that buf to cache | `device.bend:769` — ALLOCATORS. `Allocator` (device.py:259) is the cache, and the cache has ONE policy: `free` recycles a storage when it is reusable and drops it otherwise, and `alloc` hands back the MOST RECENTLY freed. That is LIFO, and getting it wrong is invisible until it matters, which is why `alloc_take` is a f |
| `device.py` | 379 | hcq2 | `runtime/ops_webgpu.bend:16` — what is ported, DEF by DEF. :11  `backend_types`            ported  the port's own backend_names/backend_of tinygrad/runtime/ops_webgpu.py:12 `instance`      ported  `dev.create_instance` symbol=instance :13  from_wgpu_str               wall 1  string views :14  to_wgpu_str                 wall 1  s |
| `dtype.py` | 84 | NOTE: float('nan') != float('nan'), so we canonicalize here | `dtype.bend:1145` — `truncate` -- dtype.py:296. THE FLOAT ARM, and the reason a float CONST can hold a value AT ITS DTYPE. UPSTREAM'S `truncate` IS A DICT FROM A DTYPE TO A CONVERSION, and the conversion is chosen by the dtype's CLASS: `DType.const` (dtype.py:84) takes the float arm when `dtypes.is_float(self)`, the bo |
| `dtype.py` | 104 | NOTE: isinstance(True, int) is True, so bool must be checked before int | `codegen/decomp/dtype.bend:3001` — the `f2f` rows -- dtype.py:101-125, the whole region, which had no row at all. Until these existed the 182-row gate reached `f2f_clamp_max` (the `c*` rows) and NOTHING ELSE in dtype.py's float half. `f2f`, `f2f.up`, `f2f.up.tail`, `f2f.fnuz`, `f2f.ocp`, `f2f.isnan`, `f2f.qnan`, `f2f.down.*`, `rne` a |
| `dtype.py` | 108 | put this in the last is faster because there are more items than lists/tuples to check | `codegen/decomp/dtype.bend:1595` — `qnan = shl(shl(1, te) - 1, tm) \| shl(1, tm - 1)`, dtype.py:108. BOTH operands of that `\|` are Python ints -- `shl` is `x * (2y)` with two int arguments (transcendental.py:20) -- so the disjunction is evaluated in PYTHON and the whole thing is ONE interned CONST. MEASURED, `q4` (fp8e4m3fnuz -> flo |
| `helpers.py` | 16 | NOTE: helpers is not allowed to import from anything else in tinygrad | `mixin/rand.bend:696` — `all_int(shape)` and `all(s >= 0 for s in shape)` -- rand.py:64 and :171. `all_int` is helpers.py:16 and every shape this port builds is a `List<&2, U32>`, so the `all_int` half is VACUOUS and `ref_shape_u32` is the row that says so. |
| `helpers.py` | 306 | **************** timer and profiler **************** | `helpers.bend:2554` — GlobalCounters -- `class GlobalCounters`, helpers.py:302 SIX ClassVars (helpers.py:303-308) and one `@staticmethod reset` (:309-310). The class has no methods beyond `reset` and no instances anywhere: every write is `GlobalCounters.<name> = ...` or `GlobalCounters.<name> += ...` on the CLASS. THE MU |
| `tensor.py` | 106 | directly create the Tensor | `tensor.bend:2098` — TODO(p3) tensor.py:492  backward's other three arms -- `g.clone(device=t.device)` is WALL 2 (`UOp.clone` is ops.py:882), `:493`'s `else` is `assign` plus `__add__`, and `mixin/op.py:468`'s `const_like(1.0)` seed needs the float CONST MINTED HERE. The PORT CAN: a literal is an `F32` and `nn/optim.ben |
| `tensor.py` | 469 | ***** movement ops ***** | `mixin/rand.bend:1` — mixin/rand.bend -- tinygrad/mixin/rand.py. `RandMixin`, which is ALSO the `Tensor` constructor for every random distribution in tinygrad. All TWENTY defs are here (`grep -c "^  def " tinygrad/mixin/rand.py` = 20), in Python's order. NOT IN rand.py, despite a brief that lists them: `arange` (op.py:16 |
| `renderer/__init__.py` | 68 | TODO: make this generic with a list of supported types | `runtime/ops_bend.bend:1` — ops_bend.bend -- the BEND TARGET: the port of the PORT'S own `ops_bend.py` (the repo root -- upstream tinygrad HAS no `ops_bend.py` AT any revision; it was OURS until the purge c2a66ea41 moved it out of `tinygrad/`), WHICH forks upstream's `tinygrad/runtime/ops_python.py` THE BEND TARGET ITSELF. Eve |
| `renderer/cstyle.py` | 39 | casting | `renderer/cstyle.bend:2695` — THE FALLBACK IS BARE, NOT CAST-WRAPPED. cstyle.py:39 is `(UPat.cvar("c").cast(), lambda ctx,c: str(c.val))` -- the DEFAULT arm writes the value with no cast at all. MEASURED 2026-11-03, found by extending ksweep to f64: upstream emits `((double)(val0[0]))*2.0` and the port emitted `*((double)(2.0))` |
| `renderer/cstyle.py` | 372 | language options | `renderer/cstyle.bend:2455` — `uops_to_dtypes` -- cstyle.py:112-113. return dedup((u.dtype, u.max_numel()) for u in uops if u.addrspace in (AddrSpace.ALU, None) and u.dtype != dtypes.void and u._shape is not None) three filters and they are not independent. `addrspace in (ALU, None)` is the one that keeps a REGISTER value out (a |
| `renderer/cstyle.py` | 536 | https://clang.llvm.org/docs/AttributeReference.html#amdgpu-flat-work-group-size NOTE: this makes hlb_cifar10 t | `renderer/llvmir.bend:932` — `AMD._render_footer` -- llvmir.py:265-271. Its ONE input is `prod([d.vmax for d in uops if u.op is SPECIAL and u.arg[0] == "l"])` and the filter is as load-bearing as the product: `ftr amd prod wglobal` and `ftr amd prod wgl` are the two rows where a `g` contributes nothing and a `l` contributes 16. |
| `renderer/llvmir.py` | 82 | memory load/store | `renderer/llvmir.bend:508` — RULE 1, the REGISTER INDEX (llvmir.py:82-83). The ONLY rule that can answer `None`, and it does so for every addrspace that is not ALU: the line is `... if buf.addrspace == AddrSpace.ALU else None`. Three of these five rows say `None`, and that `None` is what makes `_render_kernel`'s `if l is None:  |
| `renderer/llvmir.py` | 146 | if | `renderer/nir_llvmir.bend:527` — stage 1d. the renderer as a record of its options -- llvmir.py:146-155, 204-231, 226-247. `Renderer` carries fifteen attributes, `LLVMRenderer` overrides three and `AMDLLVMRenderer` overrides five. Python's "override" is a class attribute being rebound; Bend has no inheritance, so a `Data` record pl |
| `renderer/llvmir.py` | 283 | TODO: this is copied from cstyle | `renderer/llvmir.bend:932` — `AMD._render_footer` -- llvmir.py:265-271. Its ONE input is `prod([d.vmax for d in uops if u.op is SPECIAL and u.arg[0] == "l"])` and the filter is as load-bearing as the product: `ftr amd prod wglobal` and `ftr amd prod wgl` are the two rows where a `g` contributes nothing and a `l` contributes 16. |
| `renderer/tc.py` | 46 | A and B must relabel k identically | `renderer/tc.bend:645` — :26 `mma` -- NVIDIA `mma.m16n8kK`: k, g = [f"k{i}" for i in range(int(math.log2(K)))], int(math.log2(4//di.itemsize)) lane, elem = tuple(k[g:g+2]), tuple(k[:g]+k[g+2:]) frag_a=(lane+("m0","m1","m2"), elem[:g]+("m3",)+elem[g:]), frag_b=(lane+("n0","n1","n2"), elem), frag_c=(("n1","n2","m0","m1","m2") |
| `renderer/tc.py` | 54 | mma.m16n8kK: lane is threadID_in_group (2 k bits) then groupID (m0-m2); elements lsb first are 2**g k in a 32- | `renderer/tc.bend:645` — :26 `mma` -- NVIDIA `mma.m16n8kK`: k, g = [f"k{i}" for i in range(int(math.log2(K)))], int(math.log2(4//di.itemsize)) lane, elem = tuple(k[g:g+2]), tuple(k[:g]+k[g+2:]) frag_a=(lane+("m0","m1","m2"), elem[:g]+("m3",)+elem[g:]), frag_b=(lane+("n0","n1","n2"), elem), frag_c=(("n1","n2","m0","m1","m2") |
| `renderer/x86.py` | 152 | int/float casts only for signed int | `renderer/isa/x86.bend:17` — STAGE 1  THE REGISTER TABLE                     py:173-192, 20 lines   DONE `RAX = Register("rax", 0)` and its 31 siblings, name -> number, number -> name, class membership (GPR / WGPR / XMM / CALLEE_SAVED), and `reg_strs`'s forty-eight sub-register names. 121 rows. stage 2  the op enum and the oper |
| `renderer/x86.py` | 198 | a gate the flags can be picked with, or the bool compared to zero that replaces one they can't: only an intege | `renderer/isa/x86.bend:743` — `to_int` (x86.py:199) -- `{dtypes.float16: dtypes.int16, dtypes.float32: dtypes.int32, dtypes.float64: dtypes.int64}[dt]`. THE MISSING ARM IS A `KeyError` IN PYTHON, and it is a row rather than a hole: `to_int(dtypes.int32)` has no answer, and a port that answered one would be answering a question n |
| `renderer/x86.py` | 280 | vpinsrd xmm2, xmm0, eax, imm inserts the element in eax into any position in xmm0, result is written to xmm2 a | `renderer/isa/x86.bend:705` — STAGE 3 -- THE MOV SPELLING. x86.py:281-289. def _xmm_sz(x):   bits = x.max_numel() * x.dtype.itemsize if bits >= 16: return X86Ops.VMOVUPS if bits >= 8:  return X86Ops.VMOVSD return X86Ops.VMOVSS two thresholds and three arms, and the gate's fixture grid straddles both: the (dtype, numel) pairs are |
| `renderer/amd/sqtt.py` | 566 | ═══════════════════════════════════════════════════════════════════════════════ DECODER ══════════════════════ | `renderer/amd/sqtt.bend:53` — NOT PORTED, WITH PYTHON LINES. Named, not half-written. sqtt.py:566-638  `decode(data)` -- the NIBBLE READER, 73 lines. It keeps a 64-bit `reg`, consumes `need = nib_count - nib_off` NIBBLES in up to three steps (align on a high nibble, read whole bytes, read a low nibble), and `pos` advances by BYT |
| `schedule/__init__.py` | 96 | bind ALLOCs to fresh BUFFERs for this invocation | `codegen/__init__.bend:539` — THE GATE: build the smallest `pm_post_sched_cache` fixture, run `walk_rewrite` over it, and print the repl map (old_index -> new_index). The CPython oracle at `.agents/slop/codegen-init-oracle.py` prints the same shape for the same fixture; the diff is the gate. UPSTREAM'S COMMENT FOR THE ENGINE ITS |
| `schedule/__init__.py` | 276 | create copies | `codegen/__init__.bend:380` — THE FIXPOINT, ops.py:1777-1885. Upstream's `unified_rewrite` is a THREE-STAGE WORKLIST: stage 0 pushes a node and its srcs (running a bottom-up table to a per-node fixed point first), stage 1 rebuilds once every src is in `replace` and runs the top-down table, stage 2 links the rebuilt node's replac |
| `schedule/indexing.py` | 130 | REDUCE(op, axis) -> REDUCE(op) with ranges | `schedule/rangify.bend:1045` — THE APPLY. `pm_apply_rangeify` (`indexing.py:130-141`) IS FIVE RULES IN A list, and the list's order is the order `PatternMatcher.rewrite` tries THEM -- MEASURED, NOT ASSUMED: `.agents/slop/rangify/rr-rules.py` ASKS upstream's own matcher about every node of the same program and prints what each one |
| `schedule/indexing.py` | 136 | finally, apply_rangeify | `schedule/indexing.bend:149` — THE THREE WALLS, stated where they bite. Two of the three were named for me: `mixin/creation.bend` and `mixin/rand.bend` name `resolve` and `UOp._min_max` at their own heads, and this file hits BOTH. W1. `resolve` -- ops.py:64. def resolve(x, default=True): if isinstance(x, bool): return x return bo |
| `schedule/indexing.py` | 138 | remove movement op | `schedule/rangify.bend:1217` — THE FIVE RULES, IN UPSTREAM's ORDER. RULE 4 -- `GroupOp.All-{Ops.STAGE, Ops.INDEX}` (`indexing.py:138`): `x.replace(src=tuple(create_bufferize_and_index_srcs(ctx, x)))`. |
| `schedule/indexing.py` | 238 | if this has two consumers, we have to merge the ranges and might create new ones | `schedule/rangify.bend:604` — the merge -- `indexing.py:238-261`. => the port's answer is upstream's fallback for every axis: a new RANGE and the axis realized. upstream keeps the RANGE when every consumer agrees and refines it with `.valid`, which is W3 (`UOp.valid` is not ported) -- => the agree case is a named deviation. => a |
| `schedule/memory.py` | 23 | compute lifetimes for all plannable internal buffers | `schedule/memory.bend:1` — memory.bend -- tinygrad/schedule/memory.py, the memory planner. WHAT THIS FILE IS. `memory.py` is 62 lines and one function. It takes a LINEAR of kernels, works out how long each internal buffer is live, packs the non-overlapping ones into one shared arena per (device, copy/compute) lane, and return |
| `schedule/prepare.py` | 113 | reduce original axes, then split | `schedule/prepare.bend:162` — THE WALLS. Six, each with the Python line that hits it. Nothing here is approximated and nothing here is faked: a row that cannot be computed prints the wall's name, so a diff can tell a wall from a value. W1. `graph_rewrite` -- ops.py:1886 symbol=graph_rewrite, called FOUR TIMES at prepare.py:280-2 |
| `schedule/rangeify.py` | 46 | if a buffer is being stored just for permutes or something, remove it we want to reexpress the indexes of idx2 | `uop/__init__.bend:1` — __init__.bend -- tinygrad/uop/__init__.py. this file is one DEF and three gate rows, and that is the finding. `__init__.py` is 135 lines and has three pieces: the `FastEnum` wrapper (6 lines), the `Ops` enum (90 lines, 77 members), and the `GroupOp` class (31 lines, 15 frozensets). `ops.bend` alread |
| `schedule/rangeify.py` | 131 | END on NOOP is NOOP | `schedule/rangeify.bend:589` — `ret is not uop` -- tinygrad/uop/ops.py:1618 -- IS `M.hop_self`, applied ONCE PER TABLE in the `True{}` arm of each `*_try.of`, which is where CPython applies it: inside `rewrite`, around `match`. A rule body therefore cannot forget it, and `M.hop_next`/`M.hop_first` sit beside it in the same file.  |
| `schedule/rangeify.py` | 351 | bufferize -> store | `schedule/rangeify.bend:2350` — `get_kernel_graph` -- rangeify.py:351-376. PORTED AS A STAGE ORDER, and the reason is the `ctx` wall rather than a missing idea. SEVEN `graph_rewrite` CALLS, in this order, and the order is the port: the tables are all here, each applied to the arena the previous stage left, and `rf_stages` is the r |
| `mixin/gradient.py` | 11 | count the ties in the acc dtype, the count can overflow the gradient dtype | `mixin/gradient.bend:680` — --- 14. REDUCE -- gradient.py:82. `reduce_gradient(ctx, ret, ret.arg[0])` DISPATCHED, not inlined: the body is `reduce_gradient`, a top-level Python function with three arms keyed on the REDUCE's op (`gradient.py:8-18`). Three nodes' worth of shape work each, and all three need `_min_max` or `broadc |
| `mixin/op.py` | 215 | NOTE: this matches numpy, torch raises RuntimeError if stop-start and step have different signs | `mixin/creation-mut.bend:1` — mixin/creation.bend -- tinygrad/mixin/creation.py, all 165 lines. `CreationMixin`, which is ALSO `UOp.empty` / `UOp.empty_like` / `UOp.const_like` (ops.py:581 symbol=const_like, :603, MEASURED: `UOp.empty.__qualname__ == "CreationMixin.empty"`). ------------------------------------------------------ |
| `mixin/op.py` | 468 | align all tensors to output letters then summed letters, multiply, sum | `tensor.bend:2085` — `backward`'s zip -- tensor.py:490-494. `ts` is `tensors_need_grad` (the filter above, in scope order, which is `all_tensors` order upstream), and `root_grad` is upstream's `gradient=` argument. `gradient=None` -> `self.const_like(1.0)` (mixin/op.py:468) is the FLOAT CONST wall, so the seed is a PARA |
| `mixin/op.py` | 1844 | full-length Householder reflector v with zeros above row i; w = tau*v is the rank-1 update factor | `mixin/rand.bend:1` — mixin/rand.bend -- tinygrad/mixin/rand.py. `RandMixin`, which is ALSO the `Tensor` constructor for every random distribution in tinygrad. All TWENTY defs are here (`grep -c "^  def " tinygrad/mixin/rand.py` = 20), in Python's order. NOT IN rand.py, despite a brief that lists them: `arange` (op.py:16 |
| `runtime/ops_amd.py` | 798 | the controller's memory the queue and the host share, one range (usb.py slices it): the sys page at 0, the cq  | `runtime/support/usb.bend:37` — THE WALLS THIS CLOSES. the PORT's own `ops_amd.bend` records WALL 3 ("USB3, USBIface"), and upstream's `USB3.list_devices` (tinygrad/runtime/ops_amd.py:786) IS the enumeration it names, with `dma_view` and the `0/4096/20480` controller window, with `TODO(p3) runtime/ops_amd.py:786  symbol=__init__   |
| `runtime/ops_amd.py` | 862 | Scratch setup | `runtime/ops_amd.bend:36` — NO PROOFS FAIL HERE, and the brief expected some. `dtype.bend`'s seams are `def ... -> IO(R)` over two `import "./x.c"` lines, and every one of them is expected to make its importer print SOME PROOFS FAIL (constraints line 1868: the foreign notice is a "who names whom" closure that `@unsafe` does no |
| `runtime/ops_cpu.py` | 33 | RWX pages are unrepresentable on apple silicon (https://blog.svenpeter.dev/posts/m1_sprr_gxf/), so flip the wr | `runtime/ops_cpu.bend:993` — THE SEAM -- LANDED 2026-10-27. THE TRACE TAGS ABOVE ARE STILL THERE AND THEY STILL RECORD WHAT UPSTREAM's `CPUProgram` DOES; WHAT FOLLOWS IS THE PART THAT ACTUALLY DOES IT. UPSTREAM's SEQUENCE, `tinygrad/runtime/ops_cpu.py:23-46`: 1. `cc` COMPILES THE C TO AN ELF OBJECT (support/compiler_cpu.py:21-2 |
| `runtime/ops_nv.py` | 447 | host memory keeps its cpu address unless the cpu touches it: semaphores only reach 40 bits, so those go low | `runtime/ops_nv.bend:1` — tinybendygrad/runtime/ops_nv.bend -- port of tinygrad/runtime/ops_nv.py =========================================================================== STAGES. This file is ported in five stages and THIS HEADER SAYS WHERE IT STANDS, because a staged file with an accurate header beats a complete one that |
| `runtime/ops_nv.py` | 527 | PCIIface's MAP_FIXED mmap will overwrite UVM allocations made by NVKIface, so don't try PCIIface if kernel dri | `runtime/ops_nv.bend:1` — tinybendygrad/runtime/ops_nv.bend -- port of tinygrad/runtime/ops_nv.py =========================================================================== STAGES. This file is ported in five stages and THIS HEADER SAYS WHERE IT STANDS, because a staged file with an accurate header beats a complete one that |
| `runtime/ops_python.py` | 35 | cores sharing (dims, dtype_in, threads) share fragments, so the first match is the layout | `runtime/ops_python.bend:1` — ops_python.bend -- port of tinygrad/runtime/ops_python.py: `PythonProgram.__call__`, the BEND device. `bend-executor PACKET gx gy gz vals...` reads a packet, walks its toposorted uops once per global work item, and writes PACKET.out. STATE OF THIS FILE, MEASURED 2026-10-26. `--check-only` is clean a |
| `runtime/ops_python.py` | 101 | REGs are per thread | `runtime/ops_python.bend:1194` — THE STORE: the packet's bytes in packet order, then `nbytes` zeros for each scratch buffer (ops_python.py:101,104 allocate `bytearray(n)`, and two scratch buffers must not share bytes). the zeros go after the packet's bytes, and there are `w*e` of them. `Prog.bases` gives the scratch buffer the base |
| `runtime/ops_rdma.py` | 70 | one qp per gpu pair | `runtime/ops_npy.bend:1` — tinybendygrad/runtime/ops_npy.bend -- port of tinygrad/runtime/ops_npy.py FOUR LINES: 1  from tinygrad.device import Compiled, HostAllocator 2 3  class NpyDevice(Compiled): 4    def __init__(self, device:str): super().__init__(device, HostAllocator(self), [], None) So the class INHERITS EVERYTHING a |
| `runtime/ops_rdma.py` | 127 | sdma fills in the wqe | `runtime/ops_rdma.bend:41` — WHAT IS PORTED, DEF BY DEF. Line numbers are ops_rdma.py. :16  RDMA_CHUNK                  PORTED  `RDMA_CHUNK()` tinygrad/runtime/ops_rdma.py:18 `BNXT_IDS`          PORTED  the four constants and `vram_bar` symbol=BNXT_IDS :22  `BNXTIface.__init__`         PORTED  `Iface.of`  -- vram_bar=2, base_cl |
| `runtime/ops_webgpu.py` | 22 | turns a webgpu function returning a future into python-synchronous function the new function handles the statu | `runtime/ops_webgpu.bend:577` — ops_webgpu.py:23-43 -- `synchronous`, the future-to-synchronous protocol. See the payload for why `has_emsg` changes the payload length and not its content. the status names are measured, not transcribed from a header: each of the six calls carries its own status enum, and at status 2 all six are `… |
| `runtime/support/c.py` | 66 | lazily resolve field descriptors | `runtime/support/hcq2.bend:16` — WHAT IS PORTED, DEF BY DEF. `hcq2.py` is 646 lines and most of it is a `graph_rewrite` over the UOp ARENA, which `uop/ops.bend` owns and this file must not re-derive. What survives as PURE ARITHMETIC is the queue model, and that is what is here. hcq2.py:16 `HCQ_CACHE_THRESH`         PORTED  symbol=H |
| `runtime/support/compiler_llvm.py` | 76 | +reserve-x18 here does the same thing as -ffixed-x18 in ClangCompiler, see comments there for why it's needed  | `runtime/support/compiler_llvm.bend:38` — THE THIRD: `compile` CLEARS the diagnostic list before it does anything, so the `if self.diag_msgs: raise RuntimeError("llvm diagnostic: " + "\n".join(...))` at :62 is reachable ONLY when the handler fired DURING the compile. The diagnostic handler is a `@llvm.LLVMDiagnosticHandler` ctypes callback, |
| `runtime/support/elf.py` | 34 | Prealloc image for all fixed addresses. | `runtime/support/elf.bend:1251` — elf.py:34-38, THE IMAGE LOOP. `Built` exists because elf.py:38 writes back into `sh.header.sh_addr`, so the fold returns BOTH the image and the section list with those addresses filled in -- and the gate reads the ADDRESSES back out of the returned list, which is the only observation of elf.py:38. ` |
| `runtime/support/hcq2.py` | 100 | group into stacks based on dtype, alignment, is_link (rt/lt can't share a store) and ranges (a ranged offset i | `runtime/support/hcq2.bend:16` — WHAT IS PORTED, DEF BY DEF. `hcq2.py` is 646 lines and most of it is a `graph_rewrite` over the UOp ARENA, which `uop/ops.bend` owns and this file must not re-derive. What survives as PURE ARITHMETIC is the queue model, and that is what is here. hcq2.py:16 `HCQ_CACHE_THRESH`         PORTED  symbol=H |
| `runtime/support/hcq2.py` | 248 | calc deps for each tag | `runtime/support/hcq2.bend:1293` — `_build_queues` (:258-283) -- THE ORDER, and it is the load-bearing part of the whole file: :263  first use of a queue -> `_start_ins(devices[0], queue)` :266  ts_ins = one TIMESTAMP per stamp slot :267  `q += waits + ts_ins[:1] + [call] + ts_ins[1:]` -- THE call goes between the two timestamps, nev |
| `runtime/support/hcq2.py` | 277 | all tags that should signal | `runtime/support/hcq2.bend:1293` — `_build_queues` (:258-283) -- THE ORDER, and it is the load-bearing part of the whole file: :263  first use of a queue -> `_start_ins(devices[0], queue)` :266  ts_ins = one TIMESTAMP per stamp slot :267  `q += waits + ts_ins[:1] + [call] + ts_ins[1:]` -- THE call goes between the two timestamps, nev |
| `runtime/support/system.py` | 150 | All 3 values must be written at the same time. | `runtime/support/system.bend:1041` — --- (a) the eight bus-enable writes --------------------------------------- `buses = (0 << 0) \| ((bus+1) << 8) \| (gpu_bus << 16)` -- three terms and the first is the CONSTANT ZERO, which is there to say the secondary and subordinate bus fields are written as zero. MEASURED: bus=0 -> 0x40100, bus=1 |
| `runtime/support/nv/ip.py` | 438 | Copy image | `runtime/support/nv/ip.bend:92` — THE SEAMS, named with their Python lines. These are FFI, not logic. * every `ctypes` struct construction, and `bytes(x)`: the field VALUES are real ctypes writes into a real buffer. This port reproduces the layouts (THE LAYOUTS) and the U32-representable field values, and the ctypes marshalling itse |
| `codegen/__init__.py` | 437 | register definitions (INS without srcs) move to the top so regalloc sees their live ranges span the whole prog | `renderer/estimates.bend:24` — `Estimates` -- __init__.py:15-61. ops:sint = 0   # number of FLOPS used in the Kernel lds:sint = 0   # bytes accessed in loads and stores mem:dict[tuple[UOp, Ops], sint] = {}   # total bytes, counted ONCE `sint` is `UOp\|int` and has NO Bend spelling, so the port carries the COUNT as a `U32`. That i |
| `codegen/simplify.py` | 14 | real ranges only | `codegen/simplify.bend:29` — 1  8-13   fold   flatten_range             PORTED, wall at `s.ranges` 2  14-19  table  pm_flatten_range          1 of 1, PORTED 3  20     fold   count_divmod              NOT CLAIMED: one-line count helper 4  21-39  fold   simplify_merge_adjacent   WALL: a rule that calls graph_rewrite 5  40-50  fol |
| `codegen/decomp/transcendental.py` | 260 | negative base: nan for non-integer exponent, negate for odd integer exponent. -inf is never nan, it stays |bas | `uop/symbolic.bend:5663` — ---- `symbolic.py:451`, the pow rule ---------------------------------------------- ((UPat(Ops.POW, name="p"), lambda p: xpow_int(p.src[0], p.src[1], p.dtype) if dtypes.is_int(p.dtype) else xpow(*p.src))) `dtypes.is_int` is not `x in dtypes.ints`, and the difference is two cases: `is_int(weakint)` i |
| `viz/serve.py` | 16 | NOTE: using HTTPServer forces a potentially slow socket.getfqdn | `viz/serve.bend:4` — WHAT THIS FILE IS: viz's LOGIC, without viz's SERVER. `serve.py` is 757 lines and 12 of them mention http/socket/handler/do_GET/ send_header. The other 745 are a profiler, a graph labeler and a binary encoder, and none of it needs a socket. That is the shape of this port: the logic is here and it is |
| `uop/__init__.py` | 134 | These can change the dtype to bool | `uop/ops.bend:4421` — THE OPS.PY RULE TABLES -- ops.py:1898 symbol=_substitute, ops.py:1899 symbol=_pm_resolve_params, ops.py:1908 symbol=pm_drop_after, and tinygrad/uop/spec.py:207 symbol=spec_program. The FOURTH is NOT IN upstream's `ops.py` AT ALL -- upstream has NO `remove_all_tags`, which is THIS port's own table -- |
| `uop/divandmod.py` | 12 | x//y is constant | `uop/divandmod.bend:229` — `x//y is constant` -- divandmod.py:12, and the arm is EXACT rather than conservative on CONST/CONST, where `_min_max` is four identical `a//b` and the test always holds. Outside CONST/CONST it needs the range (see the TODO block). `x - xdiv.vmin*y`, the MOD half of divandmod.py:13. |
| `uop/divandmod.py` | 19 | ** Constant Denominator Rules ** these rules strictly require y to be a scalar constant > 0 | `uop/symbolic.bend:6901` — `nested_div` -- divandmod.py:23. AND IT IS THE NEXT UNPORTED ARM OF `fold_divmod_general`, AND IT IS THE ONE THAT NEEDS NO `usum`. if d.op is Ops.DIV and x.op is Ops.MOD and (k := x.src[1].divides(c)) is not None and k.vmin > 0: return x.src[0] // y % k AND IT IS INSIDE THE " Constant Denominator Ru |
| `uop/divandmod.py` | 67 | ** Variable Denominator / Fallback Rules ** These rules apply to variables OR constants that failed the checks | `codegen/decomp/op.bend:1667` — `vmax < d` -- tinygrad/uop/divandmod.py:68. `dc_ival` on the `None` from `_min_max` is 0, and Python's `vmax` for a node whose `_min_max` is unreadable is ALSO not something this port can answer, so the guard reads the two arms the port CAN: a CONST and a PARAM. `dc_vmax_of` is that reader. |
| `uop/movement.py` | 19 | const INDEX into STACK is src | `uop/movement.bend:148` — `x.shape == y.shape` -- `movement.py:12`'s second conjunct and `movement.py:19`'s first. A shape element that is a uop rather than a literal compares by index, which is what Python's `==` on `sint`s does. |
| `uop/ops.py` | 40 | the memory the linker gives an ALLOC | `mixin/creation-mut.bend:1` — mixin/creation.bend -- tinygrad/mixin/creation.py, all 165 lines. `CreationMixin`, which is ALSO `UOp.empty` / `UOp.empty_like` / `UOp.const_like` (ops.py:581 symbol=const_like, :603, MEASURED: `UOp.empty.__qualname__ == "CreationMixin.empty"`). ------------------------------------------------------ |
| `uop/ops.py` | 56 | https://en.wikipedia.org/wiki/Identity_element | `uop/ops.bend:775` — `axis_to_pos` IS GONE. ops.py:57 at the pin, deleted by 78d482262 and replaced by the literal `0` at the four call sites that read it (`_shard`'s device range, `device_range_src`, and `axis`'s default), because "RANGE args sort by axis type, then axis id" makes the position redundant with the TYPE.  |
| `uop/ops.py` | 58 | unsigned arithmetic wraps mod 2^n, so its interval holds only if it fits the dtype | `mixin/op.bend:40` — THE EIGHT WALLS, each named at its Python line. All eight are missing SUBSTRATE; W9 below is a different animal, a measured DEFECT in substrate that is present. W1 mixin/op.py:74 `_getitem` -- the index is Python's `int\|slice\|Tensor\|None\|list\|tuple\|Ellipsis`, a SEVEN-WAY sum type of heterogene |
| `uop/ops.py` | 66 | NOTE: generating the text for the exception is expensive, so we do this | `uop/fold.bend:2159` — THE TWO CHECKS, ops.py:408-410, and they are ONE walk. if not all(x >= 0 for x in self.marg): raise ValueError(...) if resolve(prod(ps) != prod(self.marg), False): raise ValueError(...) Both read the same dims of the same `marg`, so they are one walk: `marg_prod` multiplies them and remembers the tw |
| `uop/ops.py` | 81 | per right-aligned dim: sizes of 1 broadcast to the others, which must all agree | `uop/ops.bend:6972` — `UOp.gcd` AND `UOp.divide_exact` -- ops.py:1073-1079. and both are built on the counter (above), and the counter is a list of pairs because the port has no integer-keyed map -- measured 2026-11-08, `helpers.bend:494`: "Bend's `Map` is string-keyed only, so the set is a linear scan". `UOp.gcd(*uops)` |
| `uop/ops.py` | 116 | here are the dtype production rules, total over all Ops | `mixin/rand.bend:1` — mixin/rand.bend -- tinygrad/mixin/rand.py. `RandMixin`, which is ALSO the `Tensor` constructor for every random distribution in tinygrad. All TWENTY defs are here (`grep -c "^  def " tinygrad/mixin/rand.py` = 20), in Python's order. NOT IN rand.py, despite a brief that lists them: `arange` (op.py:16 |
| `uop/ops.py` | 124 | a call has the dtype of its body, void for opaque bodies | `uop/fold.bend:1119` — `dtype_from_uop` (ops.py:124) and `UOp._shape` (ops.py:329), together. The arms are grouped by the RULE they use rather than by declaration order, because ops.py's own order is: every op that names its dtype, then every op that names its shape, then three `GroupOp` fallbacks. The list of ops is the  |
| `uop/ops.py` | 185 | NOTE: CMPLT, CMPNE, CMPEQ, WHERE, SHL, SHR are handled above | `mixin/creation-mut.bend:238` — ops.py:630 `if dtype is None or b is Invalid: dtype = dtypes.from_py(b)`. `dt` here is an `S.Dt` and never `None`, so only the `b is Invalid` arm is reachable -- and it REPLACES the dtype rather than narrowing it: `from_py(Invalid)` is bool (dtype.py:102) and `bool.const(Invalid)` is `Invalid` UNCHA |
| `uop/ops.py` | 193 | NOTE: the key must separate nodes of different dtype: a CONST's dtype is the type of its arg, and True == 1 as | `uop/ops.bend:2405` — UOpMetaClass.__call__ -- ops.py:193 symbol=UOpMetaClass.__call__. THE CONSTRUCTOR. THE KEY MUST SEPARATE DTYPES. ops.py:193 -- a CONST's dtype comes from the TYPE of its arg, and Python says `True == 1`, so a bool CONST and an int CONST would share a dict key without the arg type in it. The port's ` |
| `uop/ops.py` | 199 | SPEC=3 checks the shape | `uop/fold.bend:7177` — THE `_min_max` ARITHMETIC ROWS. `.agents/slop/mm-gate.py` generates BOTH the fixtures and these lines, so a row cannot be right on one lane and wrong on the other; 72 rows, byte-identical to CPython on both the interpreted and `-o` lanes. NOT PORTED, one line each, and the wall each one is behind. T |
| `uop/ops.py` | 272 | Check self first, then iterate backward_slice (avoids creating intermediate dict) | `uop/fold.bend:7177` — THE `_min_max` ARITHMETIC ROWS. `.agents/slop/mm-gate.py` generates BOTH the fixtures and these lines, so a row cannot be right on one lane and wrong on the other; 72 rows, byte-identical to CPython on both the interpreted and `-o` lanes. NOT PORTED, one line each, and the wall each one is behind. T |
| `uop/ops.py` | 309 | arg goes through repr: args of different types (None, str, tuple) must stay mutually comparable for the sort | `uop/ops.bend:3547` — topovisit -- ops.py:309. "NOTE: this shares a lot of code with toposort". It has no caller in ops.py, and its visitor is a Python callable, so the def is here for the inventory and its body is the toposort order with the visitor call left to the caller that has one. TODO(p3): the visitor is a Callab |
| `uop/ops.py` | 322 | INS shape is always scalar, vector width is in the instruction encoding | `codegen/late/.linearizer-mut.bend:1` — codegen/late/linearizer.bend -- port of tinygrad/codegen/late/linearizer.py ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `codegen/late.bend` until the 1:1 ruling; `codegen/late/regalloc.bend` and `codegen/late/gater.bend` are the other two slices, the rows are the SAME rows, and 128 be |
| `uop/ops.py` | 398 | TODO: why do i need resolve here? | `mixin/rand.bend:198` — `_broadcast_to` (movement.py:128-147) for the ONE shape transition `_pool` needs: a 1-D source whose only axis is 1, expanded to `[r, i]`. `repeat`'s `expand` (movement.py:594) only ever inserts the new axis on the LEFT of an `unsqueezed_shape` that already has the source's axis, so `new_shape[:n_le |
| `uop/ops.py` | 465 | if it's not a RANGE, we include all ranges in srcs. technically we shouldn't flow through these ranges either, | `codegen/rewriter.bend:6` — IT HAS NO UPSTREAM `.py` AT THIS PATH, and that is not an omission: every def in it is PORT-LOCAL TOOLKIT and none of it is from `simplify.py`, `late/coalesce.py` or `gpudims.py`. `find tinygrad -name rewriter.py` returns nothing -- the lowerer is split three ways -- and what this file was is all th |
| `uop/ops.py` | 515 | *** uop tracing stuff *** | `uop/movement.bend:507` — THE RANK TEST, and it is the whole of the `_mop` deferral. `_mop`'s node is buildable exactly when `UOp.sink(*usrcs).simplify()` is ops.py:515's EARLY RETURN, which needs both `shape_to_shape_arg` results to be CONSTs -- that is, ONE axis per side, because `shape_to_shape_arg` of a ONE element shape |
| `uop/ops.py` | 520 | the trace must not retain the device Buffer: store a placeholder instead (the real one would pin memory and fa | `schedule/multi.bend:1712` — THE OWN TEST (multi.py:167), the two conjuncts, and BOTH are load-bearing: `sint_to_uop(l).ssimplify() == shard_sz` and `(sint_to_uop(s) - rng*shard_sz).ssimplify() == 0`. The first says the shrink's LENGTH is this shard's whole extent, the second says its START is where this shard starts. `sint_to_ |
| `uop/ops.py` | 559 | apply SHRINK for slices that aren't the full range | `codegen/kernel.bend:92` — THE WALL THAT DOMINATES, and it is ONE wall: `itertools.product` over a shape and `UOp.permute`/`reshape`/`reduce`/`unflatten`. Items 4, 5, 6, 9, 10, 13 and 19 are all the same wall from seven directions: the vectorizer DE-INDEXES a node by enumerating every element of its shape and rebuilding the n |
| `uop/ops.py` | 608 | cast, except for CONST, in which case rebuild a new CONST at the dtype | `mixin/movement.bend:896` — SECTION G -- THE ARENA FIXTURE. `mxm_marg` reads a UOp ARENA, so it needs a graph to read, and the graph is built with `ops.bend`'s own builders rather than by hand. EVERY BUILDER CHAINS ON A `Found` AND NOT AN INDEX. `Arena` is affine, so a builder written `-> U32` grows a copy the caller throws aw |
| `uop/ops.py` | 659 | *** multi-device helpers *** | `tensor.bend:3159` — THE MUTATION TABLE, MEASURED, and re-runnable: .venv/bin/python .agents/slop/tensor-mutate.py RESTORED 2026-10-16 from `.agents/slop/tensor-mutate.py`, blob e853efc4b, 5821 B, byte for byte, together with `.agents/slop/zero-classify.py` (18662 B), the dependency its `import patch_not_apply` chain ne |
| `uop/ops.py` | 752 | the storage this uop ultimately targets: base with UNSHARD, BITCAST and AFTER stripped | `tensor.bend:2478` — WHAT A TENSOR CARRIES. Upstream's writer is `all_metadata[new_uop] = (metadata,)` at tensor.py:106 and its reader is `UOp.metadata` (ops.py:752), which is `O.UOp.metadata` here. A method the loop SKIPS opens no scope, so the tensor it builds carries NOTHING; a method it WRAPS opens one, so the tenso |
| `uop/ops.py` | 832 | bfloat16 and fp8 have no struct format, so pack a float32 buffer and cast | `mixin/rand.bend:551` — rand.py:18 `random_bits`. The loop is `for i in range(0, num, dtypes.u32.max)` (rand.py:21) and `dtypes.u32.max` is 4294967295, so for any `num` a real shape produces -- `num = ceildiv(prod(shape) * itemsize, 4)`, so 17 GiB of random bits to reach the second iteration -- the loop has exactly ONE ite |
| `uop/ops.py` | 866 | NOTE: no device means no place to store, weak means no width to store. neither can back a buffer as-is TODO: u | `mixin/creation-mut.bend:1` — mixin/creation.bend -- tinygrad/mixin/creation.py, all 165 lines. `CreationMixin`, which is ALSO `UOp.empty` / `UOp.empty_like` / `UOp.const_like` (ops.py:581 symbol=const_like, :603, MEASURED: `UOp.empty.__qualname__ == "CreationMixin.empty"`). ------------------------------------------------------ |
| `uop/ops.py` | 899 | WEBGPU and CL do not support views. WEBGPU requires that minUniformBufferOffsetAlignment be at least 32 bytes: | `renderer/kuconv.bend:111` — the addrspace.  the FOLD answers `Maybe<Maybe<S.Addr>>`: the outer one is "the FOLD knows this node" and the inner one is "the node has an ADDRSPACE" (`ops.py:896` ANSWERS `None` FOR A SINK).  `S.Aalu{}` IS THE default because upstream's `Ops.CONST`/`Ops.RANGE`/`Ops.SPECIAL` are alu (`ops.py:899`) a |
| `uop/ops.py` | 1100 | NOTE: returned UOp is assumed to be CONST | `schedule/multi.bend:1865` — `index_multi` (multi.py:202-222). THE TWO OWNERSHIP PATTERNS, and the only place in multi.py where `_min_max` is not just a shard COUNT: idxs = list(root.src[1:]) for ax, rng in multi.sharding: shard_sz = multi.src[0].shape[ax] local = (idxs[ax] - rng*shard_sz).simplify() if local.vmin >= 0 and loca |
| `uop/ops.py` | 1104 | a load from a constant table is one of its values | `schedule/indexing.bend:149` — THE THREE WALLS, stated where they bite. Two of the three were named for me: `mixin/creation.bend` and `mixin/rand.bend` name `resolve` and `UOp._min_max` at their own heads, and this file hits BOTH. W1. `resolve` -- ops.py:64. def resolve(x, default=True): if isinstance(x, bool): return x return bo |
| `uop/ops.py` | 1111 | a cast rounds monotonically, except an int wraps past an int dtype and an inf a float dtype can't hold becomes | `uop/fold.bend:1` — fold.bend -- the derived properties of tinygrad/uop/ops.py, as ONE topological fold over the arena. WHAT THIS FILE IS. `ops.bend` builds the arena: a UOp is a `U32` index into an append-only `List<Node>`, so every property read goes through the store. That store is what stops the property folds -- a |
| `uop/ops.py` | 1181 | TODO: this should replace placeholder | `uop/ops.bend:5125` — THE INVENTORY: every ops.py def that is NOT yet a Bend def, with the reason. THESE ARE NOT DEFS, ON PURPOSE. A def whose body answers a placeholder would be a stub, and the brief for this file rules stubs out: a stub hides the wall, and the wall is the thing this unit exists to find. So each entry i |
| `uop/ops.py` | 1194 | Scalar arguments bind by slot; names and values stay at the call site, not in schedule cache keys. | `uop/ops.bend:5125` — THE INVENTORY: every ops.py def that is NOT yet a Bend def, with the reason. THESE ARE NOT DEFS, ON PURPOSE. A def whose body answers a placeholder would be a stub, and the brief for this file rules stubs out: a stub hides the wall, and the wall is the thing this unit exists to find. So each entry i |
| `uop/ops.py` | 1347 | the arg of CUSTOM_FUNCTION: an external function symbol and the dtype of the value it returns | `runtime/ops_webgpu.bend:16` — what is ported, DEF by DEF. :11  `backend_types`            ported  the port's own backend_names/backend_of tinygrad/runtime/ops_webgpu.py:12 `instance`      ported  `dev.create_instance` symbol=instance :13  from_wgpu_str               wall 1  string views :14  to_wgpu_str                 wall 1  s |
| `uop/ops.py` | 1366 | ******** ops in python ******** | `uop/ops.bend:5604` — TODO(p3) ops.py:1247  def call WALL(p3) ops.py:1274  def call_with_outputs -- BLOCKED. ENDS IN THE `alloc` CHAIN: the body binds output ALLOCs through `mint` below, and `mint` calls `UOp.alloc`, which ends in `view_as` -- absent as a definition. WALL(p3) ops.py:1280  def mint -- BLOCKED. CALLS `UOp. |
| `uop/ops.py` | 1423 | only one if it's a tuple | `runtime/ops_python.bend:1` — ops_python.bend -- port of tinygrad/runtime/ops_python.py: `PythonProgram.__call__`, the BEND device. `bend-executor PACKET gx gy gz vals...` reads a packet, walks its toposorted uops once per global work item, and writes PACKET.out. STATE OF THIS FILE, MEASURED 2026-10-26. `--check-only` is clean a |
| `uop/ops.py` | 1598 | find the unittest frame we're capturing in | `schedule/multi.bend:2525` — TODO(p3) ops.py:1094  symbol=_min_max  -- `UOp._min_max` is DECLARED here and `fold.bend` carries its WALK. DEPENDENCY ON SIBLINGS, both named because both are call sites this file does not make. `schedule/allreduce.bend` owns the BODY of `replace_allreduce`'s `_early_allreduce` arm (multi.py:106 sy |
| `uop/ops.py` | 1726 | A pure Python sentinel, but *typed* as UOp so it fits all the dict annotations | `viz/serve.bend:4` — WHAT THIS FILE IS: viz's LOGIC, without viz's SERVER. `serve.py` is 757 lines and 12 of them mention http/socket/handler/do_GET/ send_header. The other 745 are a profiler, a graph labeler and a binary encoder, and none of it needs a socket. That is the shape of this port: the logic is here and it is |
| `uop/ops.py` | 1764 | no rewrite, process children then come back to rebuild | `schedule/rangeify.bend:921` — table 6: `pm_gate_substitute` -- rangeify.py:45-47. one rule, and it is the odd one out in this entire file. it does not return a node. It raises `BottomUpGate` (ops.py:1764), which the graph engine's own loop catches (ops.py:1827) and reads as "stop descending here", and a raise is not a value, so  |
| `uop/ops.py` | 1790 | apply rewrite rules until a fixed point is reached. may return `uop` itself if PatternMatcher doesn't match | `codegen/__init__.bend:296` — `walk_rewrite` is the MLIR-style single-pass driver (ops.py:1790). `ctx` is a `List<&2, U32>` here because the engine does not yet own a typed context record. The codegen pipeline passes the real `ctx` as a single arena-indexed U32 (the `ctx[0]` from Python's `RewriteContext`), and the rule bodies r |
| `uop/ops.py` | 1886 | *** what was symbolic.py *** | `schedule/__init__.bend:1870` — THE guard of `simplify_copy_kernel` IS ported and the rule is not, so the def is `simplify_copy_kernel.ok` and NOT `simplify_copy_kernel`. The answer is a SINK and the only way to get one is graph_rewrite(ast, sym+pm_mops+pm_flatten_range+pm_simplify_ranges, ctx={}, name="simplify ranges in copy") a |
| `uop/render.py` | 82 | comparison operators are not in here because they are chained in python, not left-associative | `uop/render.bend:775` — `syms` -- render.py:25. `for debug`: the spelling of each binary operator, and it is a `dict` Python never adds to. Eleven arms and a `_`, and the `_` is `KeyError` in Python -- but both readers only ever reach it for an op the `UPat(set(syms.keys()))` rules matched, so it is unreachable and answers |
| `uop/spec.py` | 79 | RANGE can be in the big graph now. a void RANGE is a bound-less loop header, the arg is an axis id like RANGE  | `uop/spec.bend:297` — THE `Arg` QUESTIONS. `spec.py` asks `isinstance(x.arg, ...)` about eight different Python types, and `Arg` already names all eighteen, so each question is one constructor arm and the wall is gone: there is no `isinstance`, only a `match` the compiler checks against the full set. `isinstance(x.arg, D |
| `uop/spec.py` | 110 | a CUSTOM_FUNCTION names an external function: the arg is a CustomFunction stating the return dtype | `uop/ops.bend:1` — ops.bend -- tinygrad/uop/ops.py. THIS FILE IS THE GATE. .agents/TODO.md: "if the arena does not work here, the 30k-line plan changes and we say so rather than limping along". So the first thing to report is what the arena turned out to be: A UOp is a U32 index into an append-only `List<Node>`, threa |
| `uop/spec.py` | 112 | CALL: the body is always an opaque body stating the dtype, the arg is a CallInfo | `uop/ops.bend:1149` — CallInfo -- ops.py:1391. TWO FIELDS DROPPED, and both for the same reason: * `grad_fxn: Callable\|None` is a Python function object. Bend has no function values except a closure, and a closure is single-use and is a `Type`, so it cannot be a `Data` field. The reverse-mode plumbing that calls it is t |
| `uop/spec.py` | 133 | STORE: the target must be storage or a STAGE realization point (or an AFTER/BITCAST/view of one); STAGE target | `uop/spec.bend:1257` — spec.py:133 (UPat(Ops.STORE, dtypes.void, (UPat(name="x"), UPat())), lambda x: True if (b:=x.storage_base).op in {BUFFER, ALLOC, PARAM, STAGE} else None if b.op is INDEX else False) `storage_base` (ops.py:801) is `base` with UNSHARD, BITCAST and AFTER stripped, and `base` (ops.py:785) is `src[0].bas |
| `uop/spec.py` | 206 | a bare CONST only appears under its width CAST or as a PARAM/BUFFER/ALLOC size | `uop/spec.bend:2420` — WHICH BLOCK, as a number rather than as a Bool per boundary. A `match` may not scrutinise a call, so the three comparisons have to cross a def boundary as three Bools and be re-joined here -- and joining them as a number is what lets the dispatch below be a four-arm `match` instead of a nine-def lad |
| `uop/symbolic.py` | 29 | the mint truncates to a strong dtype, ints wrap and floats re-round | `uop/symbolic.bend:1` — symbolic.bend -- tinygrad/uop/symbolic.py. The REWRITER: four rule tables, the fold-like rule bodies, and `exec_alu`'s numeric evaluation. THE INVENTORY, def by def: 475 Python lines, and the honest question is not "how much is ported" but "which is a TABLE, which is a FOLD, and which is a REWRITE t |
| `uop/symbolic.py` | 120 | folding a strong dtype WHERE to a weak const branch keeps the strong dtype | `uop/symbolic.bend:2029` — symbolic.py:120  (UPat.var("x") // UPat.var("x"), lambda x: x.const_like(1)) x//x -> 1. `x` IS BOUND TWICE IN ONE SRC TUPLE, so this rule carries the IDENTITY CHECK and it is LOAD-BEARING: without it the rule also fires on `x // y` for two different nodes, and that is a wrong rewrite. |
| `uop/symbolic.py` | 125 | ** self folding ** | `uop/symbolic.bend:2753` — symbolic.py:125  (UPat.var("x") // -1, lambda x: -x) `-x` IS `x * (-1)` -- `mixin/elementwise.py`'s `neg` is `self * (-1)` for a non-bool -- and that is the port's `sy_neg`. |
| `uop/symbolic.py` | 157 | ** constant folding ** canonicalize casted CONST | `uop/symbolic.bend:342` — `GroupOp.ALU - {Ops.THREEFRY}` -- TWENTY-SEVEN ops, and it is the op set of `symbolic.py:158`, `:159` and `:161`. the port's body for :161 already tests it (`sym_161.pat` asks `O.GroupOp.alu(op) && op != THREEFRY`) and the table entry listed one op -- so the rule was correct and UNREACHABLE for twen |
| `uop/symbolic.py` | 182 | x*0 -> 0 or 0*x -> 0 if x is nan or inf it should render the nan value. NOTE: this can be wrong for loaded NaN | `uop/symbolic.bend:1` — symbolic.bend -- tinygrad/uop/symbolic.py. The REWRITER: four rule tables, the fold-like rule bodies, and `exec_alu`'s numeric evaluation. THE INVENTORY, def by def: 475 Python lines, and the honest question is not "how much is ported" but "which is a TABLE, which is a FOLD, and which is a REWRITE t |
| `uop/symbolic.py` | 202 | unpack a uint64 packed from two uint32 (threefry) | `uop/symbolic.bend:1` — symbolic.bend -- tinygrad/uop/symbolic.py. The REWRITER: four rule tables, the fold-like rule bodies, and `exec_alu`'s numeric evaluation. THE INVENTORY, def by def: 475 Python lines, and the honest question is not "how much is ported" but "which is a TABLE, which is a FOLD, and which is a REWRITE t |
| `uop/symbolic.py` | 206 | ** simple where folding ** a conditional with the same results either way is a noop, also fold const condition | `uop/symbolic.bend:8439` — NOT PORTED, one line each, and the WALL each one is behind. The Python line numbers are `symbolic.py`'s, so this list diffs against it line for line and `grep "TODO(p3)" tinybendygrad/uop/symbolic.bend` is the work queue. THE `skip=104` ROW IS THE ARITHMETIC OF THIS BLOCK: 127 is what symbolic.py's  |
| `uop/symbolic.py` | 235 | ** COMMUTATIVE flipping (only for index) ** NOTE: this can break merging vector math by only flipping some of  | `uop/fold.bend:5454` — `UOp.bool_slice` -- ops.py:284-287: _bool_slice = lambda self: frozenset().union(*[s.bool_slice for s in self.src]) bool_slice  = lambda self: self._bool_slice \| {self} if self.dtype is bool else self._bool_slice i.e. every BOOL-TYPED node in the backward slice, the root included when it is bool. t |
| `uop/symbolic.py` | 269 | in cond.where(t, f), uses of cond fold to True within t and False within f | `uop/fold.bend:1595` — `sym_dim` -- THE `ssimplify` WALL, CLOSED. `as_shape`'s two arms (ops.py:807-808) both end in `ssimplify`, and `marg` reached `None` on every non-CONST element because of it. This is the one def that answers them. WHAT `ssimplify` IS (ops.py:92, ops.py:518-520): `u.simplify()` -- a `graph_rewrite(se |
| `uop/symbolic.py` | 312 | *** rules from symbolic *** generic lt folding | `uop/symbolic.bend:5153` — ---- `symbolic.py:312`, "try to do math in int instead of long" ------------------- (UPat(GroupOp.Binary, src=(UPat.var("x", (long, weakint)), UPat.var("y", (long, weakint))), name="u"), lambda u,x,y: (CONST(x.val) if x is CONST else x.cast(int)).alu(u.op, ...same for y).cast(u.dtype) if long in (x. |
| `uop/symbolic.py` | 400 | ******** phase 3 is the complete symbolic ******** | `uop/symbolic.bend:8439` — NOT PORTED, one line each, and the WALL each one is behind. The Python line numbers are `symbolic.py`'s, so this list diffs against it line for line and `grep "TODO(p3)" tinybendygrad/uop/symbolic.bend` is the work queue. THE `skip=104` ROW IS THE ARITHMETIC OF THIS BLOCK: 127 is what symbolic.py's  |
| `uop/symbolic.py` | 464 | ** pow ** | `uop/symbolic.bend:2531` — symbolic.py:464  ((UPat.var("x") * UPat.cvar("c")).reciprocal(), lambda x,c: x.reciprocal()*c.reciprocal())   # 1/(x*c) -> (1/x)*(1/c) `x` and `c` are DIFFERENT names, so there is no identity check -- the rule fires on `1/(x*c)` for any pair -- and the `*` is commutative, so which src is `c` is a `S |
| `uop/upat.py` | 21 | build the and_clause for acceptance | `uop/upat.bend:546` — _get_clause -- upat.py:15. `UPat` -> the predicate tree. THE AND CLAUSE IS THE ACCEPTANCE TEST. upat.py:21 -- the clause collects every predicate the pattern must satisfy; the port keeps that order. THE `and_clause` CLAUSES ARE DEFS HERE, because a `Bool` match IS an `if` and there is no other spell |
| `uop/upat.py` | 101 | duplicate store is an identity compare | `uop/upat.bend:801` — A DUPLICATE STORE IS AN IDENTITY CHECK. upat.py:101 -- the first store of a name wins, and a later store of that name must bind the same value, so the duplicate becomes `{0} is {1}` rather than silently rebinding it. `dict_stores`: the first STORE of a name wins, and a repeat of it becomes the ident |
| `uop/validate.py` | 14 | general int bitops are bit-blasted through the narrowest BV that fits both sides in two's complement (BV ops g | `uop/validate.bend:1216` — `z3_bv(x, op, a, b) = BV2Int(op(Int2BV(a,w), Int2BV(b,w)), is_signed=True)`. validate.py:14 -- THE WIDTH IS THE NARROWEST ONE THAT FITS BOTH SIDES IN TWO'S COMPLEMENT, because bit-vector solving gets exponentially slower as the width grows. A `Maybe` because the width needs `_min_max`, and a node wh |
| `uop/validate.py` | 35 | Factor out the minimum count, then shift by its varying bits. Constant counts need no stages. | `uop/validate.bend:1253` — FACTOR OUT THE MINIMUM COUNT, THEN THE VARYING BITS. validate.py:35 -- a constant shift count needs no bit stages; only the varying bits do. The port's `steps` count is that varying-bit width. `a = z3.If(((b-lo) / (1 << i)) % 2 == 1, a / factor if SHR else a * factor, a)` -- a LEAF, and the whole re |
| `engine/jit.py` | 67 | aliased inputs | `engine/jit.bend:1` — jit.bend -- tinygrad/engine/jit.py:180 symbol=TinyJit. `TinyJit`: the input spec, the run counter, the `captured` record and the dispatch that decides, on every call, whether to EAGERLY RUN, to CAPTURE, or to REPLAY. THE SIBLING THAT OWNS MY TYPES. `tinybendygrad/function.bend` is porting `tinygrad/ |
| `engine/realize.py` | 50 | **************** Stat **************** | `engine/realize.bend:1070` — realize.py:50 -- `if ast.op is Ops.CUSTOM_FUNCTION and ast.arg.name == "encdec": return colored(f"enc/dec {_uop_sz_to_str(arg_uops[0])}", "yellow")`. `sym_infer` is not the dependency here, and the reason this file gave for leaving else u` (ops.py:93), and `prod(uop.shape) * uop.dtype.itemsize` is a |
| `engine/realize.py` | 114 | **************** run linear **************** | `engine/realize.bend:1135` — runtime cache TODO(p3) realize.py:107  runtime_cache -- a module-level `dict[tuple[bytes,str], Any]`. WALL: there is no `Device` to build a value for it and a Bend program has no process-global mutable store; the arena is the one global this port has and it holds nodes, not ELF runtimes. P6. TODO(p3 |
| `engine/realize.py` | 138 | the DEVICE axis is bound per device at launch: it's a RANGE in the AST and the _device_num variable after code | `engine/realize.bend:28` — THE TWO GROUPS, INVENTORIED. `[a]` is ported, `[b]` is the foreign-effect seam. [a] realize.py:16   get_call_arg_uops     -- `call.src[1:]`, minus VARIABLES [a] realize.py:17   get_call_kernel_args  -- one entry per kernel PARAM, in slot order [a] realize.py:21   get_call_outs_ins     -- (outs, ins) |
| `engine/realize.py` | 225 | **************** parallel lowering + compilation **************** | `engine/realize.bend:28` — THE TWO GROUPS, INVENTORIED. `[a]` is ported, `[b]` is the foreign-effect seam. [a] realize.py:16   get_call_arg_uops     -- `call.src[1:]`, minus VARIABLES [a] realize.py:17   get_call_kernel_args  -- one entry per kernel PARAM, in slot order [a] realize.py:21   get_call_outs_ins     -- (outs, ins) |

---

## 4. THE PORT'S OWN REASONING — THE BLOCKS UPSTREAM DOES NOT HAVE

**1557 port comment blocks** carry the port's own reasoning and cite
**no** upstream line at all. **This count is the sign that the port is not a
transcript.** A transcript would have ~2406 port comment blocks and ~0
of them would be the port's own.

Definition: a contiguous `#` comment block in a `.bend` file, >= 120
characters, containing no `*.py:<line>` citation, and containing at least one
explicit decision marker (`DEPARTURE`, `DIVERGES`, `INSTEAD`, `RATHER THAN`,
`UNLIKE UPSTREAM`, `NOT UPSTREAM`, `THE PORT`, `THE WALL`, `NOT PORTED`,
`BEND`, `CONTRAST`, `DIFFERENT`, …).

| port file | port-own reasoning blocks |
|---|---|
| port file | port-own reasoning blocks |
|---|---|
| `uop/fold.bend` | 72 |
| `uop/ops.bend` | 68 |
| `uop/symbolic.bend` | 67 |
| `uop/render.bend` | 51 |
| `runtime/support/nv/nvdev.bend` | 38 |
| `runtime/ops_metal.bend` | 31 |
| `uop/validate.bend` | 31 |
| `codegen/decomp/transcendental.bend` | 29 |
| `helpers.bend` | 27 |
| `renderer/amd/generate.bend` | 27 |
| `schedule/rangeify.bend` | 26 |
| `mixin/gradient.bend` | 26 |
| `runtime/support/am/ip.bend` | 26 |
| `codegen/late/linearizer.bend` | 25 |
| `renderer/cstyle.bend` | 24 |
| `renderer/amd/dsl.bend` | 24 |
| `schedule/multi.bend` | 24 |
| `function.bend` | 23 |
| `mixin/movement.bend` | 23 |
| `nn/onnx.bend` | 22 |
| `codegen/decomp/dtype.bend` | 22 |
| `runtime/ops_bend.bend` | 21 |
| `runtime/ops_disk.bend` | 21 |
| `LAWS.bend` | 20 |
| `runtime/ops_python.bend` | 20 |
| `runtime/support/elf.bend` | 20 |
| `codegen/late/.linearizer-mut.bend` | 20 |
| `renderer/wgsl.bend` | 17 |
| `renderer/isa/x86.bend` | 17 |
| `mixin/elementwise.bend` | 16 |
| `runtime/support/c.bend` | 15 |
| `runtime/support/am/amdev.bend` | 15 |
| `tensor.bend` | 14 |
| `runtime/ops_nv.bend` | 14 |
| `runtime/ops_webgpu.bend` | 14 |
| `runtime/support/system.bend` | 14 |
| `runtime/support/usb.bend` | 14 |
| `codegen/late/regalloc.bend` | 14 |
| `runtime/webgpu_call.bend` | 13 |
| `uop/upat.bend` | 13 |
| `renderer/nir_llvmir.bend` | 12 |
| `schedule/rangify.bend` | 12 |
| `runtime/ops_qcom.bend` | 12 |
| `runtime/ops_null.bend` | 11 |
| `runtime/ops_nvme.bend` | 11 |
| `runtime/ops_rdma.bend` | 11 |
| `runtime/support/compiler_mesa.bend` | 11 |
| `runtime/support/memory.bend` | 11 |
| `codegen/kernel.bend` | 11 |
| `codegen/decomp/op.bend` | 11 |
| `uop/spec.bend` | 11 |
| `dtype.bend` | 10 |
| `schedule/__init__.bend` | 10 |
| `nn/item.bend` | 10 |
| `LAWS/spec.bend` | 10 |
| `codegen/__init__.bend` | 10 |
| `codegen/gpudims.bend` | 10 |
| `uop/movement.bend` | 10 |
| `renderer/tc_ptx.bend` | 9 |
| `renderer/amd/sqtt.bend` | 9 |
| `mixin/op.bend` | 9 |
| `runtime/ops_cl.bend` | 9 |
| `runtime/ops_cpu.bend` | 9 |
| `runtime/support/amd.bend` | 9 |
| `runtime/support/objc.bend` | 9 |
| `engine/realize.bend` | 9 |
| `renderer/live.bend` | 8 |
| `renderer/llvmir.bend` | 8 |
| `renderer/nir.bend` | 8 |
| `runtime/ops_cuda.bend` | 8 |
| `runtime/support/rdma/bnxtdev.bend` | 8 |
| `viz/serve.bend` | 8 |
| `uop/weak.bend` | 8 |
| `renderer/tc.bend` | 7 |
| `nn/state.bend` | 7 |
| `mixin/reduce.bend` | 7 |
| `runtime/ops_dsp.bend` | 7 |
| `codegen/simplify.bend` | 7 |
| `schedule/indexing.bend` | 6 |
| `schedule/memory.bend` | 6 |
| `runtime/ops_amd.bend` | 6 |
| `engine/worker.bend` | 6 |
| `nn/mnist_cnn.bend` | 5 |
| `nn/pool.bend` | 5 |
| `runtime/support/compiler_cpu.bend` | 5 |
| `device.bend` | 4 |
| `renderer/__init__.bend` | 4 |
| `renderer/wgsl_walk.bend` | 4 |
| `nn/argmax.bend` | 4 |
| `nn/datasets.bend` | 4 |
| `mixin/dtype.bend` | 4 |
| `runtime/support/compiler_amd.bend` | 4 |
| `runtime/support/compiler_cuda.bend` | 4 |
| `runtime/support/compiler_qcom.bend` | 4 |
| `runtime/support/hcq2.bend` | 4 |
| `codegen/opt/postrange.bend` | 4 |
| `engine/jit.bend` | 4 |
| `sz.bend` | 3 |
| `renderer/kuconv.bend` | 3 |
| `schedule/prepare.bend` | 3 |
| `llm/cli.bend` | 3 |
| `llm/ggml.bend` | 3 |
| `nn/layers.bend` | 3 |
| `nn/optim.bend` | 3 |
| `LAWS/PROOF.bend` | 3 |
| `LAWS/alu.bend` | 3 |
| `mixin/creation-mut.bend` | 3 |
| `mixin/creation.bend` | 3 |
| `mixin/rand.bend` | 3 |
| `runtime/ops_hip.bend` | 3 |
| `runtime/support/autogen.bend` | 3 |
| `runtime/autogen/libclang.bend` | 3 |
| `codegen/decomp/transcendental_f32.bend` | 3 |
| `codegen/opt/search.bend` | 3 |
| `codegen/late/gater.bend` | 3 |
| `extra/datasets/imagenet.bend` | 3 |
| `uop/probe-mmcore.bend` | 3 |
| `renderer/ptx.bend` | 2 |
| `schedule/realize.bend` | 2 |
| `llm/gguf.bend` | 2 |
| `nn/__init__.bend` | 2 |
| `runtime/ops_npy.bend` | 2 |
| `runtime/support/compiler_llvm.bend` | 2 |
| `runtime/support/nv/ip.bend` | 2 |
| `uop/divandmod.bend` | 2 |
| `uop/f32_repr.bend` | 2 |
| `__init__.bend` | 1 |
| `renderer/estimates.bend` | 1 |
| `renderer/isa/__init__.bend` | 1 |
| `renderer/amd/__init__.bend` | 1 |
| `schedule/allreduce.bend` | 1 |
| `llm/__init__.bend` | 1 |
| `llm/serve.bend` | 1 |
| `llm/kernels/__init__.bend` | 1 |
| `llm/kernels/amd.bend` | 1 |
| `test/dtype_oracle.bend` | 1 |
| `mixin/__init__.bend` | 1 |
| `runtime/support/__init__.bend` | 1 |
| `runtime/support/compileserver.bend` | 1 |
| `codegen/opt/__init__.bend` | 1 |
| `codegen/opt/heuristic.bend` | 1 |
| `viz/__init__.bend` | 1 |
| `extra/datasets/__init__.bend` | 1 |

**By far the largest concentration is `uop/fold.bend` (72 blocks),
`uop/ops.bend` (68) and `uop/symbolic.bend`
(67)** — the three files where the port had to
invent a representation upstream does not have (the fold arena, the op arena,
the symbolic arena) and therefore had to explain its own design.

---

## 5. BAD CITATIONS

**The port's own rule: a wrong line number is worse than no comment.** So this
section counts them.

### 5a. Citations that point at a line the upstream file does not have

**72 citation lines** name a line number beyond the end of the
upstream file:

| upstream file | upstream length | line numbers cited |
|---|---|---|
| `uop/ops.py` | 1891 | 1894, 1895, 1896, 1898, 1899, 1908, 1909, 1915, 1917, 1923 |
| `runtime/ops_cpu.py` | 73 | 75, 78, 80, 81, 84, 88, 89, 90, 91, 92 |
| `tensor.py` | 549 | 553, 567, 570, 571, 576, 578, 588 |
| `engine/worker.py` | 51 | 52, 54, 55 |
| `schedule/prepare.py` | 260 | 264, 273, 280 |
| `runtime/ops_rdma.py` | 158 | 163, 164, 166 |
| `schedule/rangeify.py` | 364 | 366, 367 |
| `codegen/gpudims.py` | 103 | 104 |
| `uop/render.py` | 150 | 151, 163 |
| `helpers.py` | 641 | 1084 |
| `schedule/multi.py` | 303 | 305 |
| `mixin/gradient.py` | 138 | 140 |
| `runtime/ops_cl.py` | 134 | 139 |
| `codegen/late/gater.py` | 17 | 25 |
| `codegen/decomp/dtype.py` | 214 | 220 |
| `uop/divandmod.py` | 104 | 108 |

The overshoot is small and one-sided (1 to 29 lines over, mostly 2–7), which
is the signature of a citation written against a *different revision* of
upstream. **Measured proof:** for the **612** citations that quote upstream's words or
name an upstream symbol (and whose file resolves uniquely), the claimed line
holds the claim at the tree's **prior** vendored pin (upstream `5c2bf39d6c4b`,
git `77e6c2bec`) **366 times (59.8%)** and at the **current** pin (upstream
`f5ac54685`, vendored 2026-11-03) only **188 times (29.7%)**; the remaining
446 land on the wrong line today and 9 name a symbol that upstream **deleted**
in the re-vendor.

| where the cited line is checked | exact | off by some lines | claim absent upstream |
|---|---|---|---|
| current pin (`tinygrad/` as vendored now) | 188 (29.7%) | 446 | 9 |
| prior pin (git `77e6c2bec`, upstream `5c2bf39d6c4b`) | **366 (59.8%)** | 246 | 31 |

**⇒ THE 2026-11-03 RE-VENDOR MOVED UPSTREAM AND DID NOT MOVE THE PORT'S
LINE-NUMBER CITATIONS.** Half the port's citations are now wrong by a few
lines, and they are wrong *in a way that names a real but different
upstream line*. This is the tree's own finding too — `gates/pin-cite-gate.py`
independently reports `cite.at_no_revision=735` of 1629 checkable citations
holding at **no** upstream revision, with `cite.at_pin=894`.

Worked example, hand-checked: `tinybendygrad/mixin/op.bend:910` writes
"`ufix` (ops.py:606)". Upstream `uop/ops.py:606` is `# .cast folds away at
exactly the dtypes a CONST derives …`; `ufix` is at `uop/ops.py:578`.

### 5b. Citations whose quoted words are not at the cited line

**2**:

- `mixin/movement.bend:324` cites `movement.py:616` and quotes *"permute to move reduce to the end"*, but that line reads *"s_, d_ = make_tuple(stride, len(k_)), make_tuple(dilation, len(k_))"*.
- `extra/models/vit.bend:16` cites `mixin/op.py:1661` and quotes *"TODO(p3) mixin/op.py:1661 x.layernorm -- SIDE B, not built"*, but that line reads *"x = x.pad((None, None, *flatten((None,(0,s-1)) for s in stride)))"*.

### 5c. Citations naming a file upstream does not have

**10** name a file with no upstream counterpart. Most are the
port's own tools, not upstream claims, and are **not** counted as bad
upstream citations:

- `ops_bend.py` — 6
- `test_validate_oob.py` — 3
- `nvdriver.py` — 1

**One of these is a real wrong path:** the port's `renderer/isa/x86.bend`
header and 20+ comments cite **`tinygrad/renderer/isa/x86.py`**. Upstream has
**no `renderer/isa/` directory** — the file is `tinygrad/renderer/x86.py`
(800 lines), and `tinygrad/renderer/isa/` is an empty directory in the
vendored tree. The port renamed the file and then cited the renamed path as
if it were upstream's.

### 5d. The ledger's join, verified on a random sample

**120 rows sampled at random (seed 31337) from the rows that
carry a citation**, and each was checked by hand-and-script: does the cited
upstream line actually contain the reasoning the port claims it ported?

| | count |
|---|---|
| verified OK | **68** |
| **BAD** | **52** |

**43% of the sampled citations are bad.**
Every one was hand-checked; the confirmed failures are of three kinds:
(a) the line number names a different upstream line (the re-vendor drift
above), (b) the port's citation names a symbol that upstream **deleted** in
the re-vendor (`ops.py:1726` "A pure Python sentinel", `tensor.py:570`
`_ContextVar`), (c) the port's citation points at the wrong file
(`ops.py:606` for `ufix`).

---

---

## 6. WHAT THIS MEANS

1. **The port carries upstream's reasoning for 495 of 2339 upstream
   comment blocks (21.2%).** The rate is wildly uneven.
   The scheduling lane is well covered; the op-lane, the x86 lane and the
   hardware lanes are not:

| upstream file | ported | of |
|---|---|---|
| `schedule/multi.py` | 30 | 36 |
| `schedule/rangeify.py` | 30 | 49 |
| `schedule/indexing.py` | 29 | 51 |
| `uop/symbolic.py` | 13 | 95 |
| `nn/onnx.py` | 5 | 66 |
| `mixin/op.py` | 2 | 99 |
| `renderer/x86.py` | 1 | 126 |
| `uop/ops.py` | 30 | 169 |

   `mixin/op.py` (2 of 99) and `renderer/x86.py` (1 of 126) are the two
   sharpest edges: upstream's *per-op* and *per-instruction* comments are
   almost entirely absent from the port, while upstream's *pass-level*
   comments (the ones that explain a scheduling decision) are carried.
2. **1844 blocks are gaps.** The largest single class
   (1618) is upstream comments that were never cited —
   usually a gotcha attached to a *code* line that the port cites by symbol
   without carrying the comment above it. `renderer/x86.py` is the extreme
   case: the port cites x86.py **62 times** (by `symbol=`) and carries
   **one** of its 126 comment blocks.
3. **The port's own reasoning is real and large: 1557 blocks**
   that upstream does not have. The port is not a transcript; it is a
   re-derivation.
4. **Half the port's line-number citations are stale** (59.8% exact at the
   prior pin, 29.7% at the current one). This is the one finding that makes
   the other three less trustworthy: a citation is a join key, and a wrong
   key joins the port to the wrong upstream thought.

---

## 7. REPRODUCING

The instruments are in `/private/var/folders/.../opencode/` (throwaway, not
committed). The ledger is `.agents/slop/commentgap/gap.rows`
(tab-separated, one header row, one row per upstream comment block):

```
upstream_file  upstream_line  block_first_words  ported  port_citation  verdict  note
```

`verdict` is one of `PORTED`, `GAP-NO-CITATION`, `GAP-CITED-NO-REASONING`,
`GAP-DIFFERENT-REASONING`, `N/A-PYTHON-ONLY`.
