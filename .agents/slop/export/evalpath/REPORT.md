# EVAL PATH — the first milestone toward ImageNet

**Unit:** `evalpath`. **Scope:** three manifest rows plus their direct dependency.
**Written:** 2026-10-19 03:46–03:56 UTC.
**HEAD at read time:** `80d329a33`. **HEAD at write time:** `6dab8e95d`.
The tree moved underneath this unit mid-run and that is recorded rather than
smoothed over: every claim below was read against `80d329a33` and the two heads
differ because other units are writing concurrently.
**Machine:** `sysctl -n vm.loadavg` = `8.61 11.96 9.49` at start (< 15, so
normal working size). One process at a time, never backgrounded, no corpus
loops, no `checks/differ.py`, nothing under `gates/`.

---

## 0. WHAT WAS WRITTEN

| manifest row | LOC | ported_path | written | lines |
|---|---|---|---|---|
| `extra/models/resnet.py` | 170 | `tinybendygrad/extra/models/resnet.bend` | yes | 263 |
| `examples/train_resnet.py` | 45 | `tinybendygrad/examples/train_resnet.bend` | yes | 169 |
| `examples/test_pkl_imagenet.py` | 19 | `tinybendygrad/examples/test_pkl_imagenet.bend` | yes | 192 |

Both directories were absent before this unit (`ls tinybendygrad/extra/models/`
and `ls tinybendygrad/examples/` both answered *No such file or directory*).
Nothing outside `tinybendygrad/extra/models/`, `tinybendygrad/examples/` and
`.agents/slop/export/evalpath/` was written. **No `.txt` file was created
anywhere** — `find` over all three directories returns 0.

### The `--check-only` first lines, as `checks/substrate.py` reads them

`checks/substrate.py` defines COLD as "first line != `ALL PROOFS CHECK`", so a
stub reporting anything else reads as a BROKEN file.

```
$ ./bin/bend tinybendygrad/extra/models/resnet.bend        --check-only
ALL PROOFS CHECK
$ ./bin/bend tinybendygrad/examples/train_resnet.bend      --check-only
ALL PROOFS CHECK
$ ./bin/bend tinybendygrad/examples/test_pkl_imagenet.bend --check-only
ALL PROOFS CHECK
```

All three are WARM by that definition. This matters as much as the stubs
existing: a stub that reads COLD would be a broken file wearing a stub's header.

### What each stub refuses on, and refuses with

The refusal convention is **not invented here**. `extra/datasets/__init__.bend:40-46`
— written by another unit at 2026-10-19 06:49 local — already declares
`type Refused is Data: Refused{at: String}` and `def refuse(at: String) -> Refused`,
with the instruction "imported as `D` by the sibling stubs, so the refusal is one
definition rather than ten copies of it." These three files import it as `D` and
return `D.Refused` rather than a `Tensor`.

That return type is the point. A stub returning a zero `Tensor` or an empty list
would be indistinguishable from a layer whose weights happen to be zero. A model
file that reports silence instead of absence is the one lie these files must not
tell.

Run output (each names the FIRST missing symbol in that def's body, so a refusal
carries the *address* of the work):

```
$ ./bin/bend tinybendygrad/extra/models/resnet.bend
resnet_refused_at=extra/models/resnet.py:155 ResNet18 -- FIRST MISSING SYMBOL Conv2d (:87)
resnet_ported=False

$ ./bin/bend tinybendygrad/examples/train_resnet.bend
train_resnet_refused_at=examples/train_resnet.py:42 BLOCKED ON unexercised backward pass AND on sparse_categorical_crossentropy (mixin/op.bend:15, SIDE B)
train_resnet_ported=False

$ ./bin/bend tinybendygrad/examples/test_pkl_imagenet.bend
test_pkl_imagenet_refused_at=examples/test_pkl_imagenet.py:8 FIRST MISSING SYMBOL pickle -- NO UNPICKLER EXISTS; helpers.bend:2812 says 'Bend has no pickle and no object graph'
test_pkl_imagenet_ported=False
```

---

## 1. THE SYMBOL TABLE — 45 symbols, and the denominators

Machine-readable at `.agents/slop/export/evalpath/symbols.rows`
(TAB: `upstream_symbol`, `state`, `port_file_line`, `needed_by`, `evidence`).

**`symbols.rows` carries a THIRD state value, `PARTIAL`, and declares it here
rather than letting a reader meet it unannounced.** The brief specified
`EXISTS|MISSING`. A `PARTIAL` recorded as `EXISTS` would be a lie, and a rows
file with an undeclared value is worse than one with a declared one. 8 of the 45
are `PARTIAL`: the machinery is written and something needed to reach it is not.

| state | count |
|---|---|
| EXISTS | 14 |
| PARTIAL | 8 |
| MISSING | 24 |

### 1.1 What EXISTS, and it is not nothing

| symbol | where |
|---|---|
| `Tensor` | `tinybendygrad/tensor.bend` (2,867 lines) |
| `Tensor.relu` | `tensor.bend:774 tn_relu` |
| `Tensor.cast` | `tensor.bend:1389 tn_cast.put` |
| `Tensor.shape` / `.dtype` / `.device` | `tensor.bend:216` / `:219` / `:213` |
| `Tensor.mean` | `mixin/op.bend:891 mo_mean` |
| `get_state_dict` | `nn/state.bend:318` |
| `get_parameters` | `nn/state.bend:375` |
| `GlobalCounters.reset` | `helpers.bend:2582` (typed, not ambient) |
| `getenv` | `helpers.bend:148 getenv_str`, `:304 getenv_int` |
| `Context` | `helpers.bend:405` |
| `dtypes` | `dtype.bend:518 to_dtype` |

And the finding that reframes the whole slice:

> **`tinybendygrad/nn/__init__.bend` is 429 lines and holds EXACTLY 17 `def`s.
> All 17 are shape arithmetic — `nn_app nn_len nn_neg1 nn_i64_app nn_mt nn_mt_seq
> nn_half nn_prod nn_groups nn_k1 nn_pair nn_pair nn_pad nn_same nn_scale
> nn_bound nn_glorot` — and ZERO layer classes.** The file says so itself at
> `nn/__init__.bend:94`: *"every `__call__` is a `TODO(p3)` naming the line: 11 of
> the 13 classes. I am NOT writing defs that return a `TODO`."*

So the arithmetic half of ResNet is ported and gated, and the execution half is
not. The shape of `conv1.weight` can be computed today. Not one activation can
be produced.

### 1.2 The wall, named once

`tinybendygrad/mixin/op.bend:1523` **is the last line of that 1,523-line file**
and reads:

```
# SIDE B's SECTION GOES BELOW THIS LINE.
```

`mixin/op.bend:13-15` enumerates SIDE B: *"sequential, linear, the pools, the
convolutions, layernorm, batchnorm, the losses, qr, svd, keccak, hash"*. Every
`def` in the file is on SIDE A. **SIDE B IS THE EMPTY HALF**, and it contains
Conv2d, BatchNorm2d, Linear, `sequential`, the pools and the losses — i.e. the
six things all three of these files need first.

---

## 2. THE GAP LIST FOR THE EVAL PATH — the actual distance

`examples/test_pkl_imagenet.py` is 19 lines. It needs 16 distinct symbols.
**4 exist, 11 are missing, 1 is partial.** In order of size:

### Gap E1 — no unpickler, and no byte source to feed one. (`MISSING`)

- `pickle` — `test_pkl_imagenet.py:1`, used `:8`.
- The name LOOKS covered and is not. `engine/jit.bend:261` has a def called
  `m_pickle`, and it is the **message string** `"can't pickle an uncaptured JIT"`,
  not a codec.
- The port's own header says it in as many words, **`helpers.bend:2812`**:
  *"Bend has no pickle and no object graph to store"*.
- What it would take: a pickle decoder that reconstructs an arbitrary Python
  object graph *including class instantiation*, because the `.pkl` payload is a
  live `run_onnx_jit` carrying a `captured` record. This is the single largest
  piece of work on the eval path and there is no partial credit in it.
- The adjacent half: `open(fetch(...), "rb")` at `:7` has **no byte source**.
  `nn/state.bend:498` is `# TODO(p3) state.py:8 TensorIO -- io.RawIOBase;
  readinto (:17) needs ...` and `nn/onnx.bend` names the same wall: *"Nothing in
  this port can read a byte out of a tensor"*.

### Gap E2 — `OnnxRunner` STAGE 3 and 167 ONNX op bodies STAGE 4. (`MISSING`)

- `nn/onnx.bend:37-38` — STAGE 3 NOT DONE: `OnnxRunner.__init__` `:374-376`
  through `__call__` `:441-470`.
- `nn/onnx.bend:39` — STAGE 4 NOT DONE: the **167 op BODIES** (`:475-1307`), the
  node-shape arithmetic, the quantization family.
- `nn/onnx.bend:57-58` gives the dependency order honestly: *"`OnnxRunner.__call__`
  — the interpreter loop, and it dispatches into the op table, so it is
  **unreachable before the op bodies exist**."*
- The protobuf reader under it (`:53-58`, `PBBufferedReader :73-119`,
  `OnnxPBParser :121-349`) is blocked too: *"a protobuf reader OVER A TENSOR"*.

### Gap E3 — `Tensor.argmax` and `Tensor.item`: no prediction. (`MISSING`)

- `grep -rnE '^def mo_argmax' --include='*.bend' tinybendygrad/` = **0**.
- `mixin/op.bend:11` lists `argmax` inside **SIDE A** and no def carries it.
  `rc_arg` (`mixin/reduce.bend:208`) is a reduction internal, not `Tensor.argmax`.
- `grep -rnE '^def .*item' --include='*.bend'` — every hit is `renderer/*` or
  `Lds.item`. None is `Tensor.item`.
- **Consequence: the eval loop has no way to produce a PREDICTION**, which is the
  one thing an eval script exists to produce. `Tensor.to` (`:15`,`:17`) is
  missing too — `mixin/movement.bend`'s wall list says outright *"`to` is
  `tensor.py:353`"* and is *"reported rather than ported"*.

### Gap E4 — `fetch` and `imagenet_dataloader`. (`MISSING`)

- `fetch`: `grep -rnE '^def fetch\(' --include='*.bend' tinybendygrad/` = **0**.
  `helpers.bend:2815`: *"The HTTP machinery (fetch, fetch_fw, _ensure_downloads_dir)
  is urllib plus a temp file plus an atomic rename. It is I/O of exactly the kind
  the master plan puts in runtime/."*
  **Instrument warning:** a looser `grep -rnE '^def .*fetch'` answers **2**, and
  both are the sibling *refusals* at `extra/datasets/__init__.bend:49,:53`. A grep
  that reads a prefix and calls it a hit is the failure this tree already has a
  name for. The instrument is anchored to `fetch\(`.
- `imagenet_dataloader` (`examples/test_onnx_imagenet.py:25` upstream):
  `grep -c imagenet tinybendygrad/nn/datasets.bend` = **0**. The 469-line
  `nn/datasets.bend` has MNIST *and* CIFAR URL tables and no ImageNet one.

### Gap E5 — what is genuinely NOT the eval path's problem

- `getenv("CNT", 100)` is **ported**: `helpers.bend:304 getenv_int` is that call.
- `GlobalCounters.reset()` is **ported**: `helpers.bend:2582`.
- `captured.expected_input_info` is **PORTIAL-EXISTS**: `engine/jit.bend:370-389`
  `InInfo` is `(view, variables, dtype, device)` = jit.py:55, and `jit.bend:38-41`
  says it is ported **IN FULL**. `ii_vars` `:393` is the name list. *The record
  exists; the object that carries it does not.*
- `TinyJit` is **PARTIAL-EXISTS**: `engine/jit.bend` is a real port —
  `_TinyJit.__call__` `:125-178` *"all four arms and both refusals"*. What is
  absent is the NAME and the DECORATOR (`jit.bend:24` wants `tiny_jit.of3(f)`).

### 2.1 THE FINDING: the eval path and the model path converge on the same wall

`test_pkl_imagenet.py` **looks** like it dodges ResNet entirely, because it runs a
pre-executed pickle instead of building the graph. **It does not dodge it.** The
pickle's bytes *contain* a ResNet-50 ONNX graph, and executing that graph needs
the same Conv/Gemm/MaxPool/Relu/BatchNormalization bodies that
`extra/models/resnet.bend` needs — which are `mixin/op.bend` **SIDE B**, the empty
half of a 1,523-line file.

So of the four gaps above, **E2 is exactly the gap `resnet.bend` stops at, and
only E1 and E3 are uniquely the eval path's.**

> **What the eval path genuinely does not need is the BACKWARD pass. That is the
> whole and only difference between the two milestones.**
> "First milestone toward ImageNet" is therefore **right**, and "nearly done"
> would be **a lie told by subtraction**.

---

## 3. WHY TRAIN IS NOT THE MILESTONE — the measured backward claim

`examples/train_resnet.py` is 45 lines. **3 of its 12 upstream symbols exist, 8
are missing, 1 is partial. Two of the missing eight are the milestone itself.**

The backward pass, read as five separate instruments:

| instrument | reading |
|---|---|
| `compute_gradient` at `mixin/gradient.bend:1473` | EXISTS |
| `grep -cE '^def gr_[0-9]+' mixin/gradient.bend` | **61** rule defs |
| `grep -rn 'gr_table' --include='*.bend' tinybendygrad/ \| grep -v gradient.bend` | **0** |
| `compute_gradient` call sites outside `mixin/gradient.bend` | **exactly 1** — `tensor.bend:2011`, inside `tn_backward.of`. Its one other mention in the whole tree is a *comment*, `mixin/op.bend:54` |
| `tn_backward` (`tensor.bend:2015`) call sites outside `tensor.bend` | **0** |

Read together: the reverse-mode rule table is 61 rules of real code and the driver
reaches it, and **nothing calls the driver**. The pass has never produced a single
gradient against a CPython oracle, so not one of those 61 rules has ever been
compared against the rule it claims to port. **A rule that has never been executed
has never been wrong either** — which is why the word here is *unexercised* and not
*working*, and it is the same argument `AGENTS.md` makes about the `DEAD` verdict.

The train path is blocked **twice over**:

1. the backward pass (above), and
2. `sparse_categorical_crossentropy` — `grep -rnE '^def mo_sparse' --include='*.bend'
   tinybendygrad/` = **0**; `mixin/op.bend:15` puts *"the losses"* in SIDE B. It is
   the **default `lossfn`** of `extra/training.py:7`.

Plus, in source order: `numpy` (`:2`) and `PIL.Image` (`:3`) missing entirely;
`optim.SGD` (`:6`) missing — **`grep -c SGD tinybendygrad/nn/optim.bend` = 0**, and
that file's two bodies are LAMB `:873` and LARS `:717`, while SGD is the default
optimizer of tinygrad's own `train_resnet.py`; `extra.training.train` /
`.evaluate` (`extra/training.py:7`, `:41`) not ported.

**And one correction worth making, because it was wrong when first measured:**
`extra.datasets.fetch_mnist` is **NOT missing**. It `EXISTS` as a refusal —
`extra/datasets/__init__.bend:49 def fetch_mnist(tensors: Bool) -> Refused`,
written by another unit at 06:49 local, 23 minutes into this unit's run. The call
at `train_resnet.py:23` is therefore **answerable, and its answer is a refusal**,
which is the correct answer rather than a gap. `train_resnet.py:41` `optim.SGD`
is the first *missing* symbol its body reaches.

---

## 4. THREE OF MY OWN CLAIMS WERE WRONG, AND THE CORRECTIONS

The brief said to prefer a refusal over a guess. That applies to this report too,
so here is what the instruments overturned:

| my claim | the truth | why it matters |
|---|---|---|
| "`grep -rnE '^def .*fetch' … returns nothing" | it returns **2** — both are the sibling **refusals** at `extra/datasets/__init__.bend:49,:53`. The correct instrument is `^def fetch\(` = **0** | a prefix-reading grep invents coverage from a refusal. The tree already has a name for this failure. |
| "`fetch_mnist` … `grep -rn 'fetch_mnist' tinybendygrad/` = 0" | **16** hits. It was written by a concurrent unit *while this one ran* | the tree is a moving target and the "moving" part was a file I had read 20 minutes earlier |
| "`def .*conv2d` → only the two `TODO(p3)` lines" | **1** hit, and it is **this unit's own** `rs_conv2d_alias` refusal at `resnet.bend:169` | see §5 |

**I also checked `fetch_mnist` against a stale read and did not report the stale
reading.** That is the whole discipline.

---

## 5. A SELF-REFERENTIAL INSTRUMENT, DISCLOSED

Two greps used in this report have **this unit's own output** among their hits:

- `grep -rn 'tn_backward' --include='*.bend' tinybendygrad/ | grep -v tensor.bend`
  returns **5** lines, and **all five are prose in the two stub files this unit
  wrote**. Before this unit ran it returned **0**.
- `grep -rnE '^def .*conv2d' --include='*.bend' tinybendygrad/` returns **1**, and
  it is `resnet.bend:169` — this unit's own refusal.

**A grep whose only hits are the instrument's own comments proves nothing, and
reporting "0 callers" without saying the count was self-produced would be exactly
the citation-of-an-incident failure this tree has a doctrine about.** So for
`conv2d` / `batchnorm` the load-bearing evidence is the reading that does not move
with what I wrote: **`nn/__init__.bend` has 17 `def`s, all shape arithmetic, zero
layer classes.** That number is independent of my stubs and it is the claim to
trust.

---

## 6. WHAT I DID NOT DO, AND WHY

- **No corpus run, no `checks/differ.py`, nothing under `gates/`, no
  `checks/e2e*`, no `checks/sweep.py`, no `checks/bounded.py`, no
  pytest/mypy/ruff.** Per the brief. The 34/34 figure is quoted from the brief's
  own reading and is not re-measured here — I had no instrument for it and no
  licence to run one.
- **`git status` / `git diff` were not used as evidence**, because `AGENTS.md`
  records both as unreliable on this tree right now (an armed index lists fresh
  files as deletions). HEAD was read with `env -u GIT_INDEX_FILE`.
- **No commit, no mutating git command, no `reset`, no `rebase`.**
- **`checks/substrate.py` was read, not run.** Its COLD definition is quoted
  from the brief and applied to my three files' actual `--check-only` output.

## 7. THE ONE-LINE VERSION

> ResNet's **shape arithmetic** is ported and gated (`nn/__init__.bend`, 17 defs,
> zero layers). Its **execution** is not: `mixin/op.bend` SIDE B — conv2d,
> batchnorm, linear, sequential, the pools, the losses — is the **empty half** of a
> 1,523-line file, and `mixin/op.bend:1523` is its last line. The backward pass is
> written (61 rules, a driver) and **exercised by nothing**. So the eval path is
> the right first milestone **only** because it needs no gradient, and it still
> needs the same forward ops the model path needs — plus an unpickler the port
> does not have and a byte source it cannot read.