# `extra/models/` — the eight non-resnet files. STUB census.

**Written** 2026-10-19 16:24–16:32 UTC. HEAD at the **start** was `0273fe428`; HEAD
at the **end** was `d3fbede23` — **another unit committed while this one worked.**
The tree is a moving target and every `file:line` below carries the time it was read.
**Machine** `vm.loadavg` 5.41 → 6.32 over the run; no corpus run, no `checks/`, no `gates/`.
Every command was one process, foreground, under 15 s.
**Scope** the eight `extra/models/` rows of `.agents/slop/exledger/examples.manifest.rows`
whose basename is one of bert, t5, llama, clip, transformer, mask_rcnn, retinanet, rnnt.
`resnet.py` was ported by another unit and is read here as the reference stub only.
`resnet.bend` is INTACT: `git hash-object` == `git rev-parse HEAD:` == `e5d3f9ab…`.
`git status` prints `D ` on it — that is the ARMED-INDEX artifact `AGENTS.md`
documents, not a deletion. This unit ran **no** mutating git command and made **no** commit.

---

## 0. THE ANSWER TO THE QUESTION THIS SLICE WAS ASKED

> *do these models need anything the vision models did NOT ask for?*

**YES — SIX named symbols, and every one of them is named by a `grep` that returns 0.**

| symbol | instrument | who asked first |
|---|---|---|
| `nn.Embedding` | `grep -rnE "^def [a-z_]*\.?Embedding\(" --include='*.bend' tinybendygrad/` → 0. `mo_i`, `mo_fx` → 0 | **bert:182**, then t5:118, llama:201, clip:319, rnnt:178 |
| `Tensor.scaled_dot_product_attention` | `grep -rnE "^def [a-z_]*\.?scaled_dot_product_attention\(" --include='*.bend' tinybendygrad/` → 0 | **transformer:27**, then bert:279, clip:176/:271, llama:101/:104 |
| `nn.LayerNorm` | `grep -rnE "^def [a-z_]*\.?LayerNorm\("` → 0 | **bert:149**, then clip ×7 |
| `nn.RMSNorm` | `grep -rnE "^def [a-z_]*\.?RMSNorm\("` → 0 | **llama:53** (×5 sites) |
| `LSTM` / `LSTMCell` | `grep -rnE "^def [a-z_]*\.?(lstm\|rnn\|gru\|cell)\("` → 0 | **rnnt:118** — and NOTHING else in the slice asks |
| `Tensor.cos` | `def ew_sin` EXISTS at `mixin/elementwise.bend:550`; `def ew_cos` does **not** | **llama:10** (RoPE) |

`retinanet.py` asks for **nothing new**. `mask_rcnn.py` asks for exactly **one** —
`nn.ConvTranspose2d` — and it is the largest file in the slice. See §7 and §8.

### The six families, asked by name

| family | verdict | where |
|---|---|---|
| **attention** | **MISSING.** No `def` anywhere. Present in 4 of 8 files. | transformer:27 · bert:279 · clip:176,:271 · llama:101,:104 |
| **softmax** | **EXISTS.** `mixin/op.bend:1095 mo_softmax`; `mo_log_softmax` :1109; `mo_softmin`. **THREE direct callers:** `t5:216`, `llama:165`, `mask_rcnn:985`. `bert:54` and `transformer:60` call `log_softmax`, a **different def** — `op.bend:1100-1107` says the one line that separates them is that `_softmax`'s `m` is used, NOT `softmax`'s `e`. |
| **embedding** | **MISSING.** | bert:182 · t5:118 · llama:201 · clip:319 · rnnt:178 — **5 of 8** |
| **matmul** | **MISSING as `Tensor.matmul`** (`grep -rnE "^def mo_matmul"` → 0). **EXISTS as `nn_dot`** `nn/layers.bend:383` — but it returns `Maybe`, so no `x @ y` type-checks today. | t5:210,:218 · bert:144 · clip:337,:361,:471 |
| **argmax** | **MISSING.** (`grep -rnE "^def mo_argmax"` → 0) | bert:66,:70 · llama:151 · rnnt:46 · clip:335,:470 |
| **adam** | **EXISTS, and NO FILE IN THIS SLICE CALLS IT.** `nn/optim.bend:898 op_mstep` (= optim.py:167 verbatim), `:903 op_vstep` (= :168), `op_mhat`, `op_vhat`. | none — bert:90 names `adam_v`/`adam_m` only to **filter them out** |

**A training loop needs NOTHING new on the optimizer side.** The adam half of
this slice is already done. What a training loop would add is a loss —
`Tensor.binary_crossentropy_logits` (bert:61) is **MISSING** — and an in-place
parameter update, which `nn/optim.bend:3-45` records as its own divergence.

---

## 1. `transformer.bend` — 136 lines (upstream 61)

`./bin/bend tinybendygrad/extra/models/transformer.bend --check-only`
→ **first line: `ALL PROOFS CHECK`**

`resnet.bend`'s shape exactly: `# STUB -- 1:1 PATH MIRROR` header, a
`# TODO(port):` naming the first missing thing, upstream signatures, every body a
`D.refuse`, and the 15 imports. `srow`/`row` printers and a `<pfx>_at` accessor
onto `D.Refused`.

**First missing symbol:** `Tensor.scaled_dot_product_attention` at `transformer.py:27`.

**`TransformerBlock.__init__` is PORTABLE TODAY.** All seven weight tuples (:12–22)
are `rd_scaled_uniform` (`mixin/rand.bend:855`) + `cr_zeros` (:446) + `cr_ones`
(:487), and `x.linear` is `nn/layers.bend:427`. The def refuses anyway.

Second wall, which survives fixing attention: **`x.layernorm`** (:32,:36,:38).
Then `dropout` (:32,:33,:35,:37), `Tensor.eye` (:51), `one_hot` (:54),
`cat` (:56), `flatten` (:56), `sequential` (:59 — already MISSING per
`resnet.bend:87-88`, so **not** a new ask).

## 2. `bert.bend` — 286 lines (upstream 300)

`--check-only` → **first line: `ALL PROOFS CHECK`**

**First missing symbol:** `Embedding(vocab_size, hidden_size)` at `bert.py:182`.

BERT gets **free from the vision work**, measured: `nn_linear`
(`nn/layers.bend:427`, 9 sites), `mxw_stk` (`mixin/movement.bend:1269`, :40),
`mxw_reshape` (:1431, :37,:38,:282,:287), `mxw_permute` (:1449, :281,:288),
`mo_log_softmax` (:1109, :54), `op_arange` (`mixin/rand.bend:361`, :55,:192),
`cr_zeros` (:446, :141), `mo_cast_t` (`mixin/op.bend:370`, :54,:70),
`ew_add`/`ew_mul` (:509/:510, :56,:67,:197,:232).

**BERT-only, beyond the six:** `gelu` at :236 is `x * 0.5 * (1.0 + (x/1.41421).erf())`.
`.erf` is **MISSING** and `def ew_gelu` does **not** exist —
`mixin/elementwise.bend:772` has only the *constant* `ew_k.gelu`, and `:1217`
`ew_quick_gelu` is the **openai** gelu. **So `bert.py` and `clip.py` use the
same word for two different functions.** Plus `binary_crossentropy_logits`
(:61,:72), `chunk` (:36), `flatten` (:56), `one_hot` (:164).

The two `load_from_pretrained` (:18, :78) are **not a porting problem**:
:24 reads a **torch** checkpoint, :81 reads a **tensorflow** one.

## 3. `t5.bend` — 230 lines (upstream 285)

`--check-only` → **first line: `ALL PROOFS CHECK`**

**First missing symbol:** `nn.Embedding(...)` at `t5.py:118`.

**T5 is the only file in the slice that CALLS `softmax` directly** (:216) — and it
is the only one that does not need `scaled_dot_product_attention`. That is the
whole reason its wall is different: **`Tensor.matmul` at :210/:218**, which is
`grep -rnE "^def mo_matmul"` → 0. `mixin/op.bend:85` names matmul as WALL 8
("a WMMA lowering over `UOp(Ops.WMMA, …)`") — but `nn/layers.bend:1-27` says that
name is a **lie for the layer's arithmetic**: `nn_dot` is
RESHAPE+RESHAPE+PERMUTE+MUL+REDUCE+CAST and all six exist.

Then `Tensor.rsqrt` (:66) — note `nn/pool.bend:388 pool_rsqrt` **is** rsqrt but is
named for a batchnorm — `Tensor.abs` (:145), `ew_gelu` (:82), `Tensor.cat` (:285).
T5's own `T5LayerNorm` (:51) is RMS-norm with no mean and no bias, and
`T5Config` (:29) is ten ints and a float, both portable.

## 4. `llama.bend` — 206 lines (upstream 286)

`--check-only` → **first line: `ALL PROOFS CHECK`**

**First missing symbol:** `nn.RMSNorm(dim, qk_norm)` at `llama.py:53` — the
**second statement** of `Attention.__init__`, after four `linear(...)` calls that
exist. Five RMSNorm sites (:53,:54,:137,:138,:200).

Llama is **the furthest of the three transformers**, and for a different reason
than the other two: bert/t5 fail on a layer, llama fails on a **stack**.

Free from the vision work: `nn_linear`, `ew_silu` (`elementwise.bend:1209`, :128),
`ew_sin` (:550, :10), `op_arange` (:8,:9,:167), `mxw_stk` (:10,:90), `cr_zeros`
(:83,:158,:170), `cr_zeros_like` (:481, :158), `mxw_reshape` (14 sites),
`mxw_permute` (:100,:101,:103,:104), `nn_repeat` (`layers.bend:523`, :34),
`mo_softmax` (:165), `mo_cast_t`, `ew_contiguous_backward` (:546, 4 sites).

**Llama-only:** `Tensor.cos` (:10) — **half of a pair landed**;
`Tensor.multinomial` (:184,:187), behind `argsort`, which `mixin/rand.bend:880`
marks `TODO(p3)`; `logits.argmax()` (:151); `Tensor.arange`-over-a-reverse
(:167). Plus `nn.Embedding` (:201,:202), `TinyJit` (PARTIAL per
`resnet.bend:116-123`), `Variable`, and the in-place `cache_kv` (:83–93).

**`FeedForward.__call__` (:127) is the one def in this file that is REACHABLE
TODAY** — `w1(x).silu()` is `nn_linear` then `ew_silu`.

## 5. `clip.bend` — 245 lines (upstream 480)

`--check-only` → **first line: `ALL PROOFS CHECK`**

**First missing symbol:** `Embedding(vocab_size, width)` at `clip.py:319`.
Reached past `Tensor.empty` (:320,:323) which EXISTS at `mixin/creation.bend:336`.

CLIP is **both halves at once**, which is why its walls overlap *resnet's* **and**
*bert's* rather than choosing:

* **vision half** (:338) needs `nn.Conv2d` → `nn/layers.bend:756` **EXISTS**.
* **text half** (:318) needs `nn.Embedding` (:319) and `nn.LayerNorm` (:322) →
  both **MISSING**, and LayerNorm has **seven** sites
  (:182,:184,:222,:289,:292,:322,:348,:349). **That is why clip.py is further from
  running than retinanet.py even though both are "vision".**

Free: `nn_linear` (9 sites), `nn_conv2d` (:343), `ew_quick_gelu`
(`elementwise.bend:1217`, :157), `cr_empty` (:320,:323,:345,:346,:351),
`cr_full` (:417, :324), `op_arange` (:470), `mxw_reshape`, `mxw_permute`,
`nn_expand` (`layers.bend:520`, :356), and the **whole Frobenius norm**
(:475,:478) — `ew_square` (:557), `nn_sum` (:242), `ew_sqrt` (:549).

Missing: `scaled_dot_product_attention` (:176,:271), `Tensor.argmax` (:335,:470),
`Tensor.triu` (:324), `Tensor.cat` (:356), `nn_dot`-as-`@`
(:337,:361,:471 — returns `Maybe`).

**`clip.py:11 gelu = Tensor.gelu` is an alias to a body that does not exist**
(`def ew_gelu` absent); the activation actually **called** at :157 is
`h.quick_gelu()`, which **is** ported. Both facts are recorded because both are true.

The first 140 lines are a BPE tokenizer — `gzip` (:64), `re` (:88), a
**49408-entry** dict — and `prepare_image` (:446) is **PIL**. Named, not counted.

## 6. `rnnt.bend` — 223 lines (upstream 202)

`--check-only` → **first line: `ALL PROOFS CHECK`**

**First missing symbol:** `Embedding(vocab_size - 1, hidden_size)` at `rnnt.py:178`.

RNN-T is the only file in the slice asking for a **kind of layer the port has
never had**: **recurrence**. `class LSTM` (:118) and `class LSTMCell` (:97), a
`self.cells` **list** (:124), and `Tensor.stack(*new_hc[1:])` (:148).
`grep -rnE "^def [a-z_]*\.?(lstm|rnn|gru|cell)\(" --include='*.bend' tinybendygrad/` → 0.

That absence is **the honest shape of the port**, not an omission inside a
finished area: in tinygrad an LSTM is `nn.state` plus a Python `for` over time
(:135), **not an op**. `mixin/op.bend:8` enumerates op.py's side and lists no
recurrence either.

Free: `rd_uniform` (`mixin/rand.bend:836`, :101–104) — so **`LSTMCell.__init__`'s
arithmetic is ported** and only the class shell is missing; `nn_linear`,
`ew_sigmoid` (:1196, :110), `ew_tanh` (:1232, :110), `mxw_stk` (:148),
`mxw_pad.go` (:1517, :58,:156), `mxw_reshape`, `mxw_permute` (:171,:183),
`nn_expand` (:196,:197), `nn_relu` (:200), `cr_zeros` (:33,:35,:36),
`cr_ones` (:18), `ew_add`/`ew_mul` (:112,:182).

**The finding: fixing LSTM would NOT make this file run.** It has eleven missing
symbols: `chunk` (:109), `cat` (6 sites), `dropout` (:113,:201), `argmax` (:46),
`clip` (:43), **`numpy` (:28,:45,:46 — the device-state seam**; `mixin/op.bend:87-89`
names `item`/`data` as *not ports*), `unsqueeze` (:26,:38,:195 — `nn_expand` covers
`expand` and **not** `unsqueeze`), `TinyJit` (PARTIAL), `fetch` (:64).

## 7. `retinanet.bend` — 229 lines (upstream 263)

`--check-only` → **first line: `ALL PROOFS CHECK`**

**Asks for nothing new.** Its layer needs are a **subset** of `resnet.bend`'s.

**Landed since `resnet.bend` was written:** `nn.Conv2d` → `nn/layers.bend:756`
(`resnet.bend:69-81` calls this MISSING and discloses its own instrument was the
file's own refusal; `nn/layers.bend:1-30` is the unit that closed it — *"THE WALL
TEXT NAMED THE WRONG BLOCKER, MEASURED AGAINST WHAT IS ON DISK"*); `max_pool2d` →
`nn/pool.bend:250 pool_maxpool` (`resnet.bend:64-66` called the BODY SIDE B);
`ew_sigmoid` (:1196); `ew_where` (:571).

Still missing, all of it resnet.bend's list: **`Tensor.sequential`** (:141,:167,
:214–217) — `resnet.bend:87-88` already names it MISSING — and `Tensor.cat`
(:142,:168,:197), which is the **only** near-new ask here and which
**bert, t5 and llama also hit**. Plus `Tensor.one_hot` (:151).

Two things are **out of slice, not porting gaps**: `examples/mlperf/helpers.py`
(`generate_anchors`, `BoxCoder`, :4) and `examples/mlperf/losses.py`
(`sigmoid_focal_loss`, `l1_loss`, :5) —
`ls tinybendygrad/examples/mlperf/` → **No such file or directory**.
And `postprocess_detections` (:71–132), `nms` (:12) and `decode_bbox` (:28) are
**numpy**; there is no ndarray (`extra/datasets/__init__.bend:17-20`).

## 8. `mask_rcnn.bend` — 421 lines (upstream 1214)

`--check-only` → **first line: `ALL PROOFS CHECK`**

**Largest file in the slice; exactly ONE symbol the other seven do not ask for.**

Census by hit count, `grep -onE "Tensor\.[a-z_0-9]+|x\.(…)\(|nn\.[A-Z][a-zA-Z]*|get_child|torch_load" extra/models/mask_rcnn.py | sort | uniq -c | sort -rn`:

```
18 Tensor.cat                  MISSING  ← the file's real subject
10 Tensor.arange               EXISTS   mixin/rand.bend:361 op_arange
 8 Tensor.where                EXISTS   mixin/elementwise.bend:571 ew_where
 7 nn.Conv2d                   EXISTS   nn/layers.bend:756 nn_conv2d
 5 x.clip                      MISSING
 5 Tensor.stack                EXISTS   mixin/movement.bend:1269 mxw_stk
 5 Tensor.relu                 EXISTS   nn/layers.bend:262 nn_relu
 4 x.reshape                   EXISTS   mixin/movement.bend:1431 mxw_reshape
 4 nn.Linear                   EXISTS   nn/layers.bend:427 nn_linear
 2 torch_load                  MISSING  (resnet.bend:97-98 already names it)
 2 Tensor.sqrt                 EXISTS   mixin/elementwise.bend:549 ew_sqrt
 2 Tensor.full                 EXISTS   mixin/creation.bend:417 cr_full
 2 get_child                   MISSING  (resnet.bend:112-113 already names it)
 1 x.cast                      EXISTS   mixin/op.bend:370 mo_cast_t
 1 Tensor.softmax              EXISTS   mixin/op.bend:1095 mo_softmax
 1 Tensor.ones                 EXISTS   mixin/creation.bend:487 cr_ones
 1 Tensor.max_pool2d           EXISTS   nn/pool.bend:250 pool_maxpool
 1 Tensor.log2                 EXISTS   mixin/elementwise.bend:551 ew_log2
 1 Tensor.chunk                MISSING  (:188)
 1 nn.ConvTranspose2d          MISSING  ← THE ONLY NEW LAYER IN THE SLICE
```

**`Tensor.cat` has no `def`** — `mixin/movement.bend:124 mx_cat` is **shape
arithmetic** `(a,b) -> a+b`, not the op. Four files in eight name it.

**What this grep cannot see, and why it is not the census:** `topk` (:29, a
module-level Python fn called at :569 and :623) — behind `argsort`,
`mixin/rand.bend:880 TODO(p3)`; `_gather` (:46) / `npgather` (:56) /
`tensor_gather` (:79) — `npgather` is **numpy**, `_gather`'s ingredients
(`ew_where` + `op_arange` + `mxw_reshape`) **all exist** and the def is simply
not written; `Tensor.round` (:16,:20) — `rint` and `nearest_interpolate`, and
`nearest_interpolate` is what `FPN.__call__` hits at **:322**; `nn.ConvTranspose2d`.

**The biggest single delegation is to the sibling stub.** `mask_rcnn.py:1211`
builds `ResNet(50, num_classes=None, stride_in_1x1=True)`;
`tinybendygrad/extra/models/resnet.bend` exists, is 264 lines, and **refuses** —
and its named wall (`Conv2d (:87)`, `mixin/op.py:1662 batchnorm is SIDE B`) is
**stale**: `nn/layers.bend:756` and `nn/pool.bend:381 pool_bn` closed both.
**Correcting it is a two-line edit to a file this unit may not touch.**

---

## 9. How these stubs differ from `resnet.bend`, deliberately

1. **`D.refuse` is imported, not redeclared.** `extra/datasets/__init__.bend:40-46`
   owns `Refused`/`refuse`; eight files, one definition.
2. **Every def names the FIRST missing symbol in ITS OWN body**, `path:line`,
   so a refusal carries the address of the work rather than a claim there is none.
3. **Where a def is genuinely portable it says so** —
   `tf_block_head_size` (`:8`), `t5_cfg_*` ×10 (`:31-40`), `rt_stacktime_init`
   (`:152`), `lm_attn_n_rep` (`:41`) compute, because a census that lists only
   walls misreports a file as harder than it is.
4. **`main` prints two rows, never a census.** A 1:1 mirror that emits rows
   upstream does not emit is not a mirror.

## 10. Two claims this report corrected before publishing

* **`Tensor.prod` was written up as MISSING** (it was claimed absent in a first
  draft of `mr_boxlist_area`). It **EXISTS**: `mixin/op.bend:822 mo_prod`.
  Corrected in the stub.
* **`np.exp` was written up as the wall for `decode_bbox`.** It is not —
  `mo_exp` (`mixin/op.bend:987`) **and** `ew_exp`
  (`mixin/elementwise.bend:1286`) both exist. The ndarray is the whole of it.
  Corrected in the stub.

A third trap was avoided rather than corrected: `grep -rnE "^def [a-z_]*\.?sin\("`
returns `mo_sints` at `mixin/op.bend:657` — a **prefix match**, not `Tensor.sin`.
The real one is `ew_sin` at `mixin/elementwise.bend:550`. **A grep that reads a
prefix and calls it a hit is the failure this tree already has a name for**, so
every MISSING row in `symbols.rows` is anchored to `^def <name>(`.

## 11. Per-model distance to working, in one line each

| model | first missing symbol | second wall | unique ask |
|---|---|---|---|
| transformer | `scaled_dot_product_attention` :27 | `x.layernorm` :32 | `Tensor.eye` :51 |
| bert | `nn.Embedding` :182 | `scaled_dot_product_attention` :279 | `erf`/BERT-`gelu` :236 |
| t5 | `nn.Embedding` :118 | `Tensor.matmul` :210 | `Tensor.rsqrt` :66 |
| llama | `nn.RMSNorm` :53 | `scaled_dot_product_attention` :101 | `Tensor.cos` :10 |
| clip | `nn.Embedding` :319 | `nn.LayerNorm` ×7 | `Tensor.triu` :324 |
| rnnt | `nn.Embedding` :178 | `Tensor.chunk` :109 | **`LSTM`** :118 |
| retinanet | `Tensor.sequential` :141 | `Tensor.cat` :142 | none |
| mask_rcnn | the sibling `resnet.bend` refusal | `Tensor.cat` :175 | **`nn.ConvTranspose2d`** |

**Ranked by how close each is:** retinanet (only resnet-list symbols are left)
→ mask_rcnn (18× `Tensor.cat`, then `round`, then `topk`) → t5 (two symbols)
→ bert → clip → transformer → llama → rnnt.