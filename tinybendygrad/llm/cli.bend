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
import ./gguf.bend as G

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

# ===========================================================================
# cli.py:77,82 -- `decode` AND `is_end`, THE CHEAP HALF OF `SimpleTokenizer`.
#
# **`decode` IS THE UTF-8 DECODE OF THE TOKENS' BYTES, AND THE PORT ALREADY HAS THAT DECODER.**
# `llm/gguf.bend:396`'s `utf8.of` is imported and reused rather than re-written, so the two ports cannot
# disagree about a code point. THE SEAM, STATED: upstream decodes with `errors='replace'`, and `utf8.of`
# does NOT emit U+FFFD for an invalid sequence -- it decodes what it can. A vocabulary whose bytes are
# not valid UTF-8 is therefore OUTSIDE this port's contract, and the differential gate uses valid ones.
#
# A MISSING TOKEN ID IS `None`, because upstream RAISES `KeyError` and a `String` return would have to
# invent one. That is the same choice `Template.role` makes for `tekken`'s `ValueError`.
# ===========================================================================
type Tok is Data:
  Tok{tid: U32, bytes: List<&2, U32>}

def Tok.find(+vocab: List<&2, Tok>, +tid: U32) -> Maybe<&1, Tok>:
  match vocab:
    case Nil{}: None{}
    case h <> t:
      match h:
        case Tok{k, bytes}:
          Bool.pick(Maybe<&1, Tok>, U32.is_eq(k, tid), Some{Tok{k, bytes}}, Tok.find(t, tid))

#: ONE self-recursive def carrying the Maybe for the CURRENT id, because a def may not use a later one
#: and two defs may not call each other (PARITY 18). `rest` LEADS so the shrinking argument comes first.
#: ONE self-recursive def, and the matches are in DECLARATION ORDER (`rest` first, then `m`, then `tok`):
#: this tree's Bend refuses matching a binder after a match on a LATER parameter, which is why the two
#: orderings that read the same do not both compile.
def Tokenizer.loop(+rest: List<&2, U32>, m: Maybe<&1, Tok>, +vocab: List<&2, Tok>,
  acc: List<&2, U32>) -> Maybe<&1, List<&2, U32>>:
  match rest:
    case Nil{}:
      match m:
        case None{}: None{}
        case Some{tok}:
          match tok:
            case Tok{tid, bytes}: Some{List.concat(&2, U32, [acc, bytes])}
    case h <> t:
      match m:
        case None{}: None{}
        case Some{tok}:
          match tok:
            case Tok{tid, bytes}:
              Tokenizer.loop(t, Tok.find(vocab, h), vocab, List.concat(&2, U32, [acc, bytes]))

def Tokenizer.decode.start(+vocab: List<&2, Tok>, +ids: List<&2, U32>) -> Maybe<&1, List<&2, U32>>:
  match ids:
    case Nil{}: Some{Nil{}}
    case h <> t: Tokenizer.loop(t, Tok.find(vocab, h), vocab, Nil{})

def Tokenizer.decode(+vocab: List<&2, Tok>, +ids: List<&2, U32>) -> Maybe<&1, String>:
  # a lambda, because `utf8.of` takes its bytes LINEARLY (`+bs`) and `Maybe.map` wants a plain function
  Maybe.map(&1, List<&2, U32>, String, b => G.utf8.of(b), Tokenizer.decode.start(vocab, ids))



#: cli.py:82 -- `token_id in (self.eos_id, self.eot_id, self.eom_id)`. Upstream carries three `int|None`;
#: the SET of present ids is the same thing, and a `List<&2, U32>` avoids putting a `Maybe` over a `Type`
#: in a record field -- which Bend REFUSES: MEASURED, `Maybe<&1, U32>` as a record field answers
#: "expected : Data, observed : Type", exactly as `Maybe<&1, F32>` did in `SSMConfig` (PARITY 7).
def Tokenizer.is_end(+ends: List<&2, U32>, +tid: U32) -> Bool:
  match ends:
    case Nil{}: False{}
    case h <> t: Bool.or(U32.is_eq(h, tid), Tokenizer.is_end(t, tid))

# ===========================================================================
# cli.py:126-141 -- `render`. **THE MAP-THEN-FOLD SHAPE, BECAUSE THE DIRECT SHAPE IS NOT EXPRESSIBLE.**
#
# Upstream threads a `Maybe` (`role()` raises for tekken) through a `for` over messages. Here a loop whose
# continuation consumes a `Maybe` cannot be loop + helper: a def may not use a later def, and two defs may
# not call each other (PARITY 18). So PASS 1 resolves every message into a record of ALREADY-RESOLVED
# `Maybe`s, and PASS 2 is ONE recursive fold over that list with a single chain of matches per step.
#
# THE CONTENT VARIANTS ARE UPSTREAM'S FOUR CASES, INCLUDING THE TWO THAT RAISE: a non-text part and a
# content that is neither a string, a list nor None. Upstream raises `RuntimeError`; the port answers
# `None`, which is the same choice `Template.role` makes for tekken's `ValueError`.
# ===========================================================================
type Content is Data:
  CText{text: String}          # isinstance(content, str)
  CParts{text: String}         # list of {type: text} parts, already joined
  CEmpty{}                     # content is None or absent
  CBad{what: String}           # a non-text part, or a content type upstream refuses

type Msg is Data:
  Msg{role: String, content: Content}

#: **ONE `ok` BIT, NOT TWO `Maybe`s, AND THAT IS A LANGUAGE CONSTRAINT RATHER THAN A SIMPLIFICATION.**
#: MEASURED: a record field typed `Maybe<&1, String>` is REFUSED -- "expected : Data, observed : Type" --
#: the same message `Maybe<&1, F32>` gave in `SSMConfig` (PARITY 7). Either failure makes the whole render
#: fail, so one bit carries it and the two strings are "" when `ok` is False.
type RMsg is Data:
  RMsg{ok: Bool, role: String, content: String}

# **`Maybe.default` CANNOT TAKE A `String` PAYLOAD** -- MEASURED: `Maybe.default(&1, String, ...)` answers
# "expected : Data, observed : Type", because `String` is a `Type`. (`Maybe.default(&2, String, ...)` IS
# used in `helpers.bend:3024`, so the constraint is on the depth.) Matching a PARAMETER has no such
# constraint, so the two projections below are the way out.
def Template.ok(m: Maybe<&1, String>) -> Bool:
  match m:
    case None{}: False{}
    case Some{s}: True{}

def Template.str.or(m: Maybe<&1, String>, d: String) -> String:
  match m:
    case None{}: d
    case Some{s}: s

def Content.text(+c: Content) -> Maybe<&1, String>:
  match c:
    case CText{t}: Some{t}
    case CParts{t}: Some{t}
    case CEmpty{}: Some{""}
    case CBad{what}: None{}

# PASS 1: one self-recursive map, so the result can be `List<&2, RMsg>` (`List.map` returns `List<&1, _>`).
def Template.render.prep(+msgs: List<&2, Msg>, +preset: U32, acc: List<&2, RMsg>) -> List<&2, RMsg>:
  match msgs:
    case Nil{}: List.reverse(&2, RMsg, acc)
    case h <> t:
      match h:
        # the projections are INLINED and the binders are `+`: a local `+r = Template.role(...)` would need
        # `Maybe<&1, String>` to be `Data`, and it is a `Type` (MEASURED: "expected : Data, observed : Type"
        # pointing at the binder). Calling the pure projections twice is the cheap way out.
        case Msg{+role, +content}:
          Template.render.prep(t, preset,
            RMsg{Bool.and(Template.ok(Template.role(preset, role)),
                          Template.ok(Content.text(content))),
                 Template.str.or(Template.role(preset, role), ""),
                 Template.str.or(Content.text(content), "")} <> acc)

# PASS 2: ONE fold. The matches are in declaration order (`xs`, then `h`, then its fields), which is what
# this tree's Bend requires; matching a binder from an earlier parameter after a later one is refused.
def Template.render.fold(+xs: List<&2, RMsg>, +preset: U32, +eos: String, acc: String)
  -> Maybe<&1, String>:
  match xs:
    case Nil{}: Some{acc}
    case h <> t:
      match h:
        case RMsg{ok, role, content}:
          match ok:
            case False{}: None{}
            case True{}:
              Template.render.fold(t, preset, eos,
                String.concat([acc, role, content, Template.end_turn(preset, eos)]))

def Template.render.join(m: Maybe<&1, String>, r: Maybe<&1, String>) -> Maybe<&1, String>:
  match m:
    case None{}: None{}
    case Some{s}:
      match r:
        case None{}: None{}
        case Some{rs}: Some{String.concat([s, rs])}

#: `... + self.role("assistant") if add_generation_prompt else out` -- the LAST Maybe consumption, so it
#: does not recurse and cannot cycle.
def Template.render.tail(m: Maybe<&1, String>, +preset: U32, +gen: Bool) -> Maybe<&1, String>:
  match gen:
    case False{}: m
    case True{}: Template.render.join(m, Template.role(preset, "assistant"))

#: cli.py:126 -- `bos` is the tokenizer's BOS token ALREADY DECODED (the same seam `end_turn` takes its
#: eos through), and `<sop>` is prefixed for `glm4`, exactly as upstream does.
def Template.render(+preset: U32, +bos: String, +eos: String, +msgs: List<&2, Msg>, +gen: Bool)
  -> Maybe<&1, String>:
  +head = String.concat([bos, Bool.pick(String, U32.is_eq(preset, 4), "<sop>", "")])
  Template.render.tail(Template.render.fold(Template.render.prep(msgs, preset, Nil{}), preset, eos, head),
    preset, gen)

# TODO(parity): `SimpleTokenizer.encode` -- BLOCKED ON A LANGUAGE CAPABILITY: `__init__` builds the split
#   regex from `unicodedata.category` ranges, which Bend has neither a regex engine nor a table for.
# TODO(parity): `FallbackTemplate.render` -- needs a message list and the tokenizer's `decode` for the
#   BOS/end-turn strings; port it together with `decode`.
# TODO(parity): `main()` and the `models` URL table -- needs `model.bend`'s `Transformer` and a fetch.
