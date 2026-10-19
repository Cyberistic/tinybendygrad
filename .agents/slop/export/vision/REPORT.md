# `extra/models/` — seven vision stubs, and what each one is actually waiting on

Measured **2026-10-19 16:24–16:33 UTC**. HEAD at the first read **`0273fe428`**, at the
last read **`d3fbede23`** — the tree moved under this unit while it worked, which is why
both are recorded rather than one.

The slice came from `.agents/slop/exledger/examples.manifest.rows`, TAB-separated
(`upstream_path ext loc disposition reason ported_path`), restricted to the
`extra/models/` rows whose basename is one of `convnext, efficientnet, inception, unet,
unet3d, vit, resnet`. All seven rows are present and all seven carry
`disposition=PORT`. `resnet` was already done by another unit at
`tinybendygrad/extra/models/resnet.bend`; it was **read first** and used as the shape to
match, and **not rewritten**.

The machine-readable deliverable is **`symbols.rows`** — TAB:
`model / symbol / EXISTS|MISSING / port_file_line / needed_by`, **146 data rows** under one
header (147 lines; `awk -F'\t' '{print NF}' | sort -u` answers `5`, so every row is
five columns and none was truncated). Every `file:line` in this report and in that file
was printed from the port
before being written down; the check is `sed -n '<line>p' <file>`, not recall.

---

## 1. The headline, and it is a correction to `resnet.bend` rather than a confirmation of it

`resnet.bend:21` still reads:

> THE HEADLINE: `nn.Conv2d`, `nn.BatchNorm2d` AND `nn.Linear` ARE ALL MISSING.

and `resnet.bend:35` cites `tinybendygrad/mixin/op.bend:1523` as **"SIDE B IS THE EMPTY
HALF"**. **Both are stale.** `tinybendygrad/nn/layers.bend` (941 lines) and
`tinybendygrad/nn/pool.bend` were written to close exactly that, and they did:

| was "MISSING" | is now | where |
|---|---|---|
| `Tensor.conv2d` | `nn_conv2d` | `nn/layers.bend:756` |
| `Tensor.linear` | `nn_linear` | `nn/layers.bend:427` |
| `Tensor.relu` | `nn_relu` (a name onto `tn_relu`, not a copy) | `nn/layers.bend:262` |
| `Tensor.batchnorm` | `pool_bn` | `nn/pool.bend:381` |

`resnet.bend`'s own `mn/layers.bend` header even explains the mechanism — `mixin/op.bend`'s
SIDE B *was* empty and the conv was therefore written in `layers.bend` from the primitives
rather than parked behind it.

**What did NOT get closed, and this is the finding that matters:**

- **`Tensor.layernorm`** — still missing. `nn/__init__.bend:230` still reads
  `TODO(p3) mixin/op.py:1644  x.layernorm  -- SIDE B, not built.` The wall list at
  `nn/__init__.bend:227-231` decayed: three of its four lines stopped being true and
  nobody went back. **This blocks `convnext` and `vit` directly.**
- **`Tensor.sequential`** — missing for every model in the directory.
  `grep -rniE '^def .*sequential' --include='*.bend' tinybendygrad/` returns **0**.
- **`Tensor.scaled_dot_product_attention`** — missing. `mixin/rand.bend:87-90` carries
  four walled arms of it ("GQA arm", "the matmul", "the causal mask", "the attn_mask arm").
  **This blocks `unet`, and it blocks `vit` through `transformer.bend`.**
- **Every `nn` LAYER CLASS** — `nn/__init__.bend` has **17 defs and zero classes**
  (`grep -cE '^def ' nn/__init__.bend` = 17), and all 17 are shape arithmetic:
  `nn_app nn_len nn_neg1 nn_i64_app nn_mt nn_mt_seq nn_half nn_prod nn_groups nn_k1
  nn_pair.right nn_pair.left nn_pad.go nn_same nn_scale nn_bound nn_glorot`.
  `layers.bend` and `pool.bend` supplied **functions where upstream had methods**; the
  constructors that own weights and fill a state dict exist for no model in this tree.

`vit` is worth singling out because of a shape no count would reveal: **its sibling
`extra/models/transformer.py` is ported as a FILE — `transformer.bend` is on disk and 1:1
with upstream's 61 LOC — but every def in it refuses**, and `transformer.bend:108`
(`tf_block_attn`) names `Tensor.scaled_dot_product_attention`. So `vit` is **not blocked
on a sibling that is absent; it is blocked on a sibling that is present and refusing**,
and the address to go to is `transformer.bend:96`.

---

## 2. Per model

Every file below is `NOT YET PORTED`, refuses rather than guesses, and prints
`<model>_ported=False`.

### convnext — `tinybendygrad/extra/models/convnext.bend`
- **LOC** 240 bend / 63 upstream
- **`--check-only` first line: `ALL PROOFS CHECK`**
- **TODO names:** `Block.__init__` at `extra/models/convnext.py:6`. First *primitive*
  missing is **`Tensor.layernorm`** at upstream `:8` (`nn/__init__.bend:220`).
- **EXISTS:** `Tensor.conv2d`, `Tensor.linear`, `Tensor.relu`, `Tensor.ones`,
  `Tensor.permute`, `Tensor.mean`, `Tensor.mul`, `Tensor.add`, `Tensor.uniform`,
  `Context` (helpers.bend:405).
- **MISSING:** `nn.LayerNorm` **class**, `nn.LayerNorm2d` **class**, `nn.Conv2d` **class**,
  `nn.Linear` **class**, `Tensor.layernorm`, `Tensor.sequential`, `Tensor.gelu`,
  `Tensor.assign`, `Tensor.realize`, `Tensor.numpy`, `Tensor.argmax`, `fetch`,
  `get_child`, `torch_load`.
- **The near-miss worth recording:** upstream `:16` names `Tensor.gelu` and
  `mixin/elementwise.bend:1217` **is** `ew_quick_gelu` — but with the `1.702` constant
  (`ew_k.quick_gelu`, `:774`). Plain `gelu` is not a def; `elementwise.bend:43` lists
  `erf` among what this tree lacks, and `:758` records that the `0.044715` cubic is wrong
  in the ninth place. Answering `:16` with `ew_quick_gelu` would be a silent wrong answer.

### efficientnet — `tinybendygrad/extra/models/efficientnet.bend`
- **LOC** 265 bend / 164 upstream
- **`--check-only` first line: `ALL PROOFS CHECK`**
- **TODO names:** `MBConvBlock.__init__` at `extra/models/efficientnet.py:8`, first
  missing symbol **`BatchNorm2d` at `:12`**, whose cause is `nn/pool.bend:415`.
- **This is the only model in the slice whose FIRST constructor line resolves to an
  existing def**, because it stores bare `Tensor`s rather than layer objects:
  `Tensor.glorot_uniform` is `rd_glorot_uniform` (`mixin/rand.bend:861`).
- **The blocker is not the norm, it is the half of the norm that is not a decomposition.**
  `pool_bend:44-48` measures `Tensor.batchnorm` as `x - mean`, `* weight`,
  `.mul(invstd)`, `+ bias` — all four built. `pool_bend:415` refuses the running-stats
  update and names **both** causes: `TRAINING` is not a binding in this tree (comments
  only), and `Tensor.assign` is not a def (`tensor.bend:2539` states the immutability
  divergence). `pool.bend:412-414` notes the **eval** branch is buildable and is "the ONLY
  path ResNet INFERENCE takes" — upstream `:39` is exactly that branch. But `:8`'s
  `track_running_stats=True` is the training default and `load_from_pretrained` reads
  `running_mean`/`running_var` out of the checkpoint, so it is not optional here.
- **EXISTS:** `Tensor.conv2d`, `Tensor.batchnorm` (eval arm), `Tensor.glorot_uniform`,
  `Tensor.avg_pool2d` (unpadded), `Tensor.swish`, `Tensor.sigmoid`, `Tensor.linear`,
  `Tensor.add`, `Tensor.mul`, `Tensor.reshape`, `Tensor.zeros`, `F32.ceil`.
- **MISSING:** `nn.BatchNorm2d` **class**, running stats, `Tensor.sequential`,
  `Tensor.replace`, `Tensor.to`, `Tensor.numpy`, `fetch`, `torch_load`, `get_child`.
- **Spelled here, because it needs nothing from the port and shows the arithmetic is not
  the hard part:** `ef_pad_half`, `ef_pad_stride2`, `ef_oup`, `ef_round_filters`,
  `ef_round_repeats`, and the ten-row `global_params` table (`ef_global_width` /
  `ef_global_depth`, so `b7` = 2.0 x 3.1 and `l2` = 4.3 x 5.3 are readable without
  opening Python).
- **Measured correction, made mid-write:** this file's first draft used `F32.from_f64`,
  `F32.lt` and `F32.to_u64`. None exist. The port's conversions are `U32.to_f32` /
  `F32.to_u32` (the pair `helpers.bend:927` uses) and the comparison is `F32.is_lt`.
  `--check-only` caught all three; the fix is in the file.

### inception — `tinybendygrad/extra/models/inception.bend`
- **LOC** 319 bend / 344 upstream
- **`--check-only` first line: `ALL PROOFS CHECK`**
- **TODO names:** `BasicConv2d.__init__` at `extra/models/inception.py:12`, first missing
  symbol the **`nn.Conv2d` CLASS** at `:14`, then `BatchNorm2d` at `:15`.
- **THE POOL RESULT IS THE ONE THAT MATTERS HERE, and a count would have got it wrong.**
  `grep -nE '(avg_pool2d|max_pool2d)\(' extra/models/inception.py` returns **17 call
  sites**, and the split is **12 refused / 5 on the built arm**, both sides named in the
  file header:
  - **needs a refused arm (12):** `:38 :79 :123 :134 :135 :147 :150 :162 :203 :213 :225 :237`
  - **on the built arm (5):** `:54 :97 :290 :294 :308`
  - Both refused arms are the same blocker, quoted from the port:
    *pool_maxpool_padded* (`nn/pool.bend:252`) and *pool_avgpool_padded*
    (`nn/pool.bend:262`) — "BLOCKED: mixin/op.py:290 the value!=0 arm, needs
    **identity_element** (uop/ops.py:61), not a def". `pool.bend:246-248` says why it is
    not built wrong instead: "A `max_pool2d` padded with ZERO would be wrong for any
    negative input."
  - Note the survivors are the *trivial* ones — all five sit in `InceptionB`, `InceptionD`
    or `FidInceptionV3.__call__`, while every named branch pool of a class is refused.
    "5 of 17 pools work" is true and useless.
  - `count_include_pad=False` at `:203 :213 :225` moves those calls **out of** the built
    arm, not into it.
- **MISSING:** `Tensor.cat` (**11** call sites: `:40 56 81 99 121 122 125 205 215 227
  239`), `Tensor.interpolate` (`:284`, the first line of `FidInceptionV3.__call__`),
  `Tensor.sequential`, `Tensor.reshape` `-1` inference (`:135 :190`), `cls_map` dict
  (`:140-141 :246`), `np.load np.cov np.atleast_1d/2d np.trace`, `scipy.linalg.sqrtm`,
  `load_state_dict`, `torch_load`, `fetch`, and the `nn` classes.
- **A FOREIGN-DEPENDENCY gap, not a substrate gap:** `calculate_frechet_distance`
  (`:323-344`) is `scipy.linalg.sqrtm` over 2048x2048 matrices (`from scipy import
  linalg`, upstream `:8`). There is no scipy, no ndarray and no matrix square root here.
  Worth saying plainly rather than queueing behind a conv2d.

### unet — `tinybendygrad/extra/models/unet.bend`
- **LOC** 323 bend / 262 upstream
- **`--check-only` first line: `ALL PROOFS CHECK`**
- **TODO names:** `timestep_embedding` at `extra/models/unet.py:10`, first missing symbol
  **`Tensor.arange` at `:12`**.
- **The headline blocker is farther up and shared:** `Tensor.scaled_dot_product_attention`
  (`upstream:7`, `:57`) — the same wall `transformer.bend:108` refuses on.
- **Two asymmetries worth recording, because both look like typos and are not:**
  - `Tensor.cos` is **missing** while `tn_sin` **exists** at `tensor.bend:423`.
    `grep -rnE '^def (tn|ew)_cos\(' --include='*.bend' tinybendygrad/` returns 0.
  - `Tensor.silu` **exists** (`ew_silu`, `mixin/elementwise.bend:1209`, which is
    `ew_swish` at `:1208`) and this file names it five times.
- **MISSING:** `Tensor.arange`, `Tensor.cos`, `Tensor.cat`, `Tensor.unsqueeze`,
  `Tensor.chunk`, `Tensor.layernorm`, `Tensor.gelu`, `Tensor.sequential`,
  `Tensor.scaled_dot_product_attention`, `nn.GroupNorm`, `nn.LayerNorm` **class**,
  `nn.Conv2d` **class**, `nn.Linear` **class**, `Device[...].renderer.supported_dtypes()`
  (`:15 :240` — a runtime capability query with no def), reshape `-1`.
- **Note on `nn.GroupNorm`:** it is not a parameter away from the built `pool_bn`.
  BatchNorm's decomposition is a **per-CHANNEL** reduction; GroupNorm splits into
  `num_groups`. Different reduction, different shape arithmetic.
- **The nearest-miss in the file:** `Upsample.__call__` `:136-137` is
  `reshape(...).expand(...).reshape(...)`, and `cr_expand`
  (`mixin/creation.bend:271`) and `mxw_reshape` (`mixin/movement.bend:1431`) are **both
  built** with every dimension an explicit `U32`. It is blocked by the layer store, not by
  a primitive.

### unet3d — `tinybendygrad/extra/models/unet3d.bend`
- **LOC** 186 bend / 59 upstream
- **`--check-only` first line: `ALL PROOFS CHECK`**
- **TODO names:** `DownsampleBlock.__init__` at `extra/models/unet3d.py:7`, first missing
  symbol **`nn.InstanceNorm` at `:9`**; the `nn.Conv2d` class at `:9` is missing too.
- **The 3-D conv is NOT the blocker, and this is the finding:** `nn_conv2d` is
  **nd-generic on purpose** — it reads `ni = len(weight.shape[2:])` at
  `nn/layers.bend:724` and derives every shape from it — so a `(3,3,3)` kernel and a
  `(1,1,1,1,1,1)` padding are arithmetically expressible.
- **MISSING:** `nn.InstanceNorm` (which is **strictly easier** than BatchNorm — no running
  stats, no `TRAINING` read: it is the `pool_bn` decomposition over `shape[1:]`),
  `nn.ConvTranspose2d` (`:17`; the port has a **forward** conv only, and a transpose is a
  different graph, not a parameter of it), `Tensor.cat` (`:23`, the skip), `torch`
  (`:2 :51` — `torch.jit.load` is a **second weight format** on top of the `torch_load`
  seam the others stop at), `fetch`, `get_child`, `Tensor.assign`, `Tensor.numpy`,
  `Tensor.sequential`, `pathlib.Path`.
- **Its `filters = [32, 64, 128, 256, 320]` table is spelled** (`u3_filters`), so a reader
  need not open Python to learn the bottleneck is 320 wide.

### vit — `tinybendygrad/extra/models/vit.bend`
- **LOC** 197 bend / 73 upstream
- **`--check-only` first line: `ALL PROOFS CHECK`**
- **TODO names:** `ViT.__init__` at `extra/models/vit.py:6`, first missing symbol
  **`TransformerBlock` at `:13`** — which is **present and refusing**.
- **The only model in the slice that does not begin with a convolution, and that is the
  whole of its distinctive blocker.** `ViT.__init__` `:8-11,16-17` name `Tensor.uniform`,
  `Tensor.zeros` and `Tensor.ones` — **all four exist** — and then hit `TransformerBlock`.
- **Second blocker, and it is one line:** `upstream:29  x = x.layernorm().linear(...)`.
- **Third blocker, and it is a real primitive rather than a layer:** `:21`
  `x.reshape(shape=(x.shape[0], x.shape[1], -1))`. `mxw_reshape` takes an **explicit**
  `List<&2, U32>` and does not infer an axis — `nn/pool.bend:322-324` states the same
  boundary in its own words for its `flatten`. `:30`'s `x[:, 0]` needs a **slice**, and
  `rd_slice` (`mixin/rand.bend:392`) is a 1-D shrink, not an index read.
- **EXISTS:** `Tensor.uniform`, `Tensor.zeros`, `Tensor.ones`, `Tensor.conv2d`,
  `Tensor.reshape`, `Tensor.permute`, `Tensor.add`, `Tensor.linear`.
- **MISSING:** `Tensor.scaled_dot_product_attention`, `TransformerBlock`,
  `Tensor.layernorm`, `Tensor.cat`, `Tensor.sequential`, `Tensor.gelu`, reshape `-1`,
  slice, `Tensor.assign` (**27** call sites, `:45-71`), `np.load`, `fetch`.
- **Said plainly because it is the model's whole value:** `ViT` cannot write a single one of
  its parameters, so a ported ViT could only ever produce its own random initialisation.

### resnet — ALREADY PORTED, READ, NOT REWRITTEN
- **LOC** 263 bend / 170 upstream
- **`--check-only` first line: `ALL PROOFS CHECK`**
- Its header (`:21`, `:35`) is **stale** in the two ways set out in §1. Its census rows
  and its `D.Refused` shape were used as the template for the six files written here.
- **`resnet`'s row in `symbols.rows` is the ONLY one in that file that this unit did not
  derive today**, and it is included because it is the reference the other six are matched
  against, not as a fresh measurement.

---

## 3. Instrument, and what it does and does not prove

**`./bin/bend <file> --check-only` was run once per file, on the seven files in
`tinybendygrad/extra/models/`, and the FIRST LINE is what is reported above.**

Two things about that instrument are worth recording, because both were measured here
rather than assumed:

1. **`--check-only` really does resolve names.** Probed with a scratch file in the
   pre-approved temp dir calling a def that does not exist: it answers
   `SOME PROOFS FAIL` / `- expected : a defined name`. So `ALL PROOFS CHECK` on these six
   files means **every imported module and every referenced name resolved** — it is not a
   syntax-only pass. The scratch file was deleted; nothing was written outside the two
   permitted directories.
2. **`--check-only` returns `rc=0` EVEN WHEN IT FAILS.** The failing probe above exited 0.
   Any gate that reads the exit code here reads a green tree that says
   `- expected : a defined name`. This is the tree's standing rule
   (`checks/substrate.py` defines COLD as "first line != `ALL PROOFS CHECK`") and the run
   confirms the rule is load-bearing.

**What was NOT run, by instruction and by load:** no corpus run, no `checks/differ.py`,
nothing under `gates/`, no `checks/e2e*`, no `checks/sweep.py`, no `checks/bounded.py`, no
pytest / mypy / ruff. `sysctl -n vm.loadavg` read **5.41** at the start and stayed under
the 15 threshold, so this unit worked in one process at a time with no backgrounding.

**Not committed, per instruction.** No mutating git command was run; the only git call was
`git rev-parse --short HEAD`, twice, which is a read.

---

## 4. What a reader should take away

The distance from these seven stubs to working models is **not** dominated by
convolutions. Convolutions, linears, relus, batchnorm, silu, sigmoid, swish, permute,
reshape, expand, add, mul, mean, uniform, glorot_uniform, zeros, ones and casts are all
built and cited above with `file:line`.

What is missing, in the order it blocks things:

1. **`Tensor.sequential`** — one name, six of seven files, `grep` returns 0.
2. **`Tensor.layernorm`** — `nn/__init__.bend:230`, an open wall whose neighbours have
   closed and which nobody has revisited.
3. **`Tensor.scaled_dot_product_attention`** — `mixin/rand.bend:87-90`; blocks `unet`
   outright and `vit` through `transformer.bend`.
4. **`Tensor.cat`** — blocks the skip paths in `unet3d`, the branch joins in `inception`,
   and the class token in `vit`.
5. **`Tensor.layernorm` / reshape `-1` inference / slices** — the "shape read back out of
   the tensor and used as an argument" family: `nn_shape` answers
   `Maybe<&2, List<&2, U32>>` and nothing infers an axis.
6. **`identity_element` (`uop/ops.py:61`)** — the single blocker behind both padded pool
   arms, and therefore behind 12 of inception's 17 pool calls.
7. **`nn` layer CLASSES** — none exist. This is the one gap with no def at all to point
   at, and it is why several TODOs above say "blocked by the layer store" even when every
   primitive they need is built.

Items 1–4 are each **one def** in this tree's idiom. Items 6 and 7 are the ones that are
not.