# tinybendygrad/llm/cli.bend -- port of tinygrad/llm/cli.py
#
# **PARTIAL, AND ONE PART IS NOT PORTABLE AT ALL -- WHICH IS THE FINDING.**
#
# `llm/cli.py` is 223 lines in three pieces:
#
#   1. `SimpleTokenizer` -- NOT PORTABLE AS WRITTEN. `__init__` builds a SPLIT REGEX out of
#      `unicodedata.category` ranges (`ucat_range`, compacted with `itertools.groupby`) and compiles it
#      with `re`; `encode` is then `_split_to_word.findall` + a greedy BPE merge. Bend has no regex
#      engine and no Unicode category table, so this is a LANGUAGE-CAPABILITY gap and not an oversight.
#      A port would need `ucat_range` computed as DATA (a generated range table) plus a hand-written
#      matcher for the compiled pattern, and until that exists an `encode` here would be a different
#      tokenizer wearing the same name.
#   2. `FallbackTemplate` -- PORTED HERE. Pure string logic keyed on the tokenizer preset: `role` and
#      `end_turn`. It is the piece with no Tensor, no regex and no I/O.
#   3. `main()` + the `models` URL table -- NOT ported: it needs `model.bend`'s `Transformer` (itself a
#      TODO) and a network fetch.
#
# ⇒ AND `end_turn`'S ONE DEPENDENCY IS EXPRESSED AS A PARAMETER, NOT RECONSTRUCTED: upstream writes
# `self.tok.decode([self.tok.eos_id])`, and `decode` is a concatenation of the token's BYTES followed by
# a UTF-8 decode. Taking the already-decoded end-of-turn STRING as an argument keeps the port honest --
# it does not pretend to know the vocabulary -- and is the same seam `ops_dsp.bend` uses for its device
# calls.

import Base

# ===========================================================================
# cli.py:13-16 -- THE PRESET IS A BEHAVIOUR CLASS, NOT A NAME. Upstream normalises `qwen35`/`qwen35moe`
# to `qwen2` before using it, and `llama-v3`/`llama-bpe`/`gpt-4o` fall through `role`/`end_turn`'s
# default branch. So the code below identifies WHICH BRANCH a preset takes, which is all this file reads.
# `Maybe` is the honest type for `Preset.of`: upstream raises `ValueError` on an unknown preset.
# ===========================================================================
def Preset.llama() -> U32: 0        # llama3, llama-v3, llama-bpe, gpt-4o -- the default branch
def Preset.olmo() -> U32: 1
def Preset.kimi_k2() -> U32: 2
def Preset.qwen2() -> U32: 3        # qwen2, qwen35, qwen35moe
def Preset.glm4() -> U32: 4
def Preset.tekken() -> U32: 5

def Preset.of(+s: String) -> Maybe<&1, U32>:
  match s:
    case "llama3": Some{0}
    case "llama-v3": Some{0}
    case "llama-bpe": Some{0}
    case "gpt-4o": Some{0}
    case "olmo": Some{1}
    case "kimi-k2": Some{2}
    case "qwen2": Some{3}
    case "qwen35": Some{3}
    case "qwen35moe": Some{3}
    case "glm4": Some{4}
    case "tekken": Some{5}
    case _: None{}

# ===========================================================================
# cli.py:109-117 -- `role`. `Maybe` for the same reason: tekken RAISES for a role it does not have
# (`ValueError`), and returning `""` there would be a silent wrong answer instead.
# ===========================================================================
def Template.role(+preset: U32, +role: String) -> Maybe<&1, String>:
  match preset:
    case 1: Some{String.concat(["<|", role, "|>\n"])}                                  # olmo
    case 2: Some{String.concat(["<|im_", role, "|>", role, "<|im_middle|>"])}           # kimi-k2
    case 3: Some{String.concat(["<|im_start|>", role, "\n"])}                           # qwen2
    case 4: Some{String.concat(["<|", role, "|>"])}                                     # glm4
    case 5: Bool.pick(Maybe<&1, String>, String.eq(role, "user"), Some{"[INST]"},
             Bool.pick(Maybe<&1, String>, String.eq(role, "assistant"), Some{""}, None{}))   # tekken
    case _: Some{String.concat(["<|start_header_id|>", role, "<|end_header_id|>\n\n"])}  # default

# ===========================================================================
# cli.py:119-125 -- `end_turn`. `+eos` is the tokenizer's end-of-sequence token DECODED, which is the
# caller's job because the tokenizer is not ported (see the header).
# ===========================================================================
def Template.end_turn(+preset: U32, +eos: String) -> String:
  match preset:
    case 1: "\n"                                                     # olmo
    case 2: eos                                                      # kimi-k2
    case 3: String.concat([eos, "\n"])                               # qwen2
    case 4: ""                                                       # glm4
    case 5: "[/INST]"                                                # tekken
    case _: eos                                                      # default

# TODO(parity): `SimpleTokenizer` -- BLOCKED ON A LANGUAGE CAPABILITY, not on effort: `encode` needs the
#   `ucat_range` regex (a generated Unicode-category range table + a matcher). `decode`/`is_end` are the
#   parts that WOULD port cheaply (`b''.join(self._tok2bytes[tid])` and a membership test), and they are
#   the next slice.
# TODO(parity): `FallbackTemplate.render` -- needs a message list and the tokenizer's `decode` for the
#   BOS/end-turn strings; port it together with `decode`.
# TODO(parity): `main()` and the `models` URL table -- needs `model.bend`'s `Transformer` and a fetch.
