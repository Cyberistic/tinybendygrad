# tinybendygrad/llm/model.bend -- port of tinygrad/llm/model.py
#
# partial, and the split is the point. `llm/model.py` is 650 lines and almost all of it is
# `Tensor`/`nn` machinery: RoPE, four attention variants (plain, MLA, GatedDeltaNet/SSM, sliding-window),
# MoE experts, manifold-constrained hyper-connections, a GGUF loader and a generation loop. What is
# ported here is the part that is pure data and can be checked without a device:
#
#   * `ExpertGating` -- an `enum.IntEnum` whose members are 1..4, so the VALUE is the contract.
#   * `YaRNConfig`, `SSMConfig`, `HCConfig`, `IndexerConfig` -- frozen dataclasses of numbers, ported
#     verbatim with upstream's defaults, because a default that differs is a silent behaviour change.
#
# what is not ported, and why it is not silence:
#   * `TransformerConfig` (model.py:92-133) -- 40 fields with defaults. It is the type every block below
#     takes, so it belongs with the first block that CONSUMES it, not with a file that nothing reads yet.
#     Porting it now would be a record with no reader: the class `.agents/slop/PARITY.md` records as
#     "a row that cannot go red".
#   * `precompute_freqs_cis`, `apply_rope`, `gated_activation`, `pairwise_topk` -- `Tensor` ops. They port
#     onto `tensor.bend`/`nn.bend` and each needs a gate against `DEV=CPU` before it can be called 1:1.
#   * `ExpertWeights`, `HyperConnection`, `FFNBlock`, `TransformerBlock`, `MLATransformerBlock`,
#     `GatedDeltaNetBlock`, `Indexer`, `Transformer` -- the blocks and the model itself.
#
# - and the order is forced by the tree's own rule: a port earns its place by having a check. The
# configs below are checkable the moment a consumer exists; the blocks need `gguf.bend`'s loader to
# hand them weights, and the loader needs a fixture. `PARITY.md` 7 records the numbers.

import Base

# model.py:11-16 -- `class ExpertGating(enum.IntEnum)`. THE VALUE IS THE CONTRACT: it is written
# into a GGUF-derived config and compared, so it travels as a `U32` and not as a constructor tag.

def ExpertGating.SOFTMAX() -> U32: 1
def ExpertGating.SIGMOID() -> U32: 2
def ExpertGating.SOFTMAX_WEIGHT() -> U32: 3   # softmax over the top-k selected logits
def ExpertGating.SQRT_SOFTPLUS() -> U32: 4

# model.py:18-23 -- `YaRNConfig`. Four scalars, no defaults upstream.

type YaRNConfig is Data:
  YaRNConfig{factor: F32, orig_ctx_len: U32, beta_fast: F32, beta_slow: F32}

def YaRNConfig.of(+factor: F32, +orig_ctx_len: U32, +beta_fast: F32, +beta_slow: F32) -> YaRNConfig:
  YaRNConfig{factor, orig_ctx_len, beta_fast, beta_slow}

# model.py:68-77 -- `SSMConfig`. `kda` defaults False; `gate_lower_bound` is `float|None` and is
# `Maybe<&1, F32>`, because "kda: bounded decay gate" is an ABSENT bound for every non-kda model and a
# `0.0` sentinel would be a real value.

# - and `float|None` cannot travel as a `Maybe` here, which is a language fact and not a simplification.
# MEASURED with `bin/bend --check-only`: a record field typed `Maybe<&1, F32>` is REFUSED -- "expected :
# Data, observed : Type" -- because `F32` is a `Type`, so a `Maybe` over it is not storable in a
# constructor. (`Maybe<&1, F32>` IS legal as a RETURN type; `cstyle.bend` uses it in three places.) So
# the absence upstream spells `None` travels as `has_bound: Bool` beside `bound: F32`, and `SSMConfig.kda`
# keeps the two in step. A `0.0` sentinel would be wrong: 0.0 is a legal lower bound.
type SSMConfig is Data:
  SSMConfig{conv_kernel: U32, state_size: U32, group_count: U32, time_step_rank: U32, inner_size: U32,
            kda: Bool, has_bound: Bool, bound: F32}

def SSMConfig.of(+conv_kernel: U32, +state_size: U32, +group_count: U32, +time_step_rank: U32,
  +inner_size: U32) -> SSMConfig:
  SSMConfig{conv_kernel, state_size, group_count, time_step_rank, inner_size, False{}, False{}, 0.0}

def SSMConfig.kda(s: SSMConfig, +kda: Bool, +has_bound: Bool, +bound: F32) -> SSMConfig:
  match s:
    case SSMConfig{conv_kernel, state_size, group_count, time_step_rank, inner_size, _k, _hb, _b}:
      SSMConfig{conv_kernel, state_size, group_count, time_step_rank, inner_size, kda, has_bound, bound}

# model.py:78-83 -- `HCConfig`: manifold-constrained hyper-connections, `count` residual streams mixed
# by a doubly stochastic matrix in `sinkhorn_iters` steps at `eps`.

type HCConfig is Data:
  HCConfig{count: U32, sinkhorn_iters: U32, eps: F32}

def HCConfig.of(+count: U32, +sinkhorn_iters: U32, +eps: F32) -> HCConfig:
  HCConfig{count, sinkhorn_iters, eps}

# model.py:84-91 -- `IndexerConfig`: a query attends to the `top_k` keys picked by an indexer scoring
# pools of `kpool` keys.

type IndexerConfig is Data:
  IndexerConfig{n_heads: U32, head_dim: U32, top_k: U32, kpool: U32, norm_eps: F32}

def IndexerConfig.of(+n_heads: U32, +head_dim: U32, +top_k: U32, +kpool: U32, +norm_eps: F32)
  -> IndexerConfig:
  IndexerConfig{n_heads, head_dim, top_k, kpool, norm_eps}

# TODO(parity): `TransformerConfig` (model.py:92-133), 40 fields -- port it WITH its first consumer, and
#   in the same commit, so the record has a reader and a gate.
# TODO(parity): `precompute_freqs_cis`, `apply_rope`, `gated_activation`, `pairwise_topk` -- Tensor ops,
#   each needing a `DEV=CPU` parity gate before it can be called 1:1.
# TODO(parity): the blocks and `Transformer` itself (model.py:134-650), including `from_gguf`,
#   `warmup`, `get_start_pos` and `generate`.
