# STUB -- 1:1 PATH MIRROR of extra/datasets/squad.py (148 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. SQuAD v1.1 to BERT features. It is (b) and the interesting part is
# that HALF of it is pure arithmetic that ports cleanly once the tokenizer exists:
# `_check_is_max_context` (upstream:43) and the `doc_spans` window loop (upstream:77-85)
# are the part worth doing first, and neither touches the network.
#   * `_check_is_max_context` (upstream:43) scores every span containing `position`
#     with `min(num_left_context, num_right_context) + 0.01 * doc_length` (upstream:53)
#     and returns `cur_span_index == best_span_index` (upstream:57) -- a FIRST-WINS
#     claim (`if best_score is None or score > best_score`, upstream:54) whose tie
#     behaviour is the whole function. Note it is a Bool, not the index.
#   * the window loop (upstream:79-85) strides by `min(length, 128)` (upstream:85)
#     where `length = min(len(all_doc_tokens) - start_offset, max_tokens_for_doc)` and
#     `max_tokens_for_doc = 384 - len(query_tokens) - 3` (upstream:75), so the -3 is
#     the `[CLS]` + two `[SEP]` reservation and a query over 64 tokens shrinks it.
#   * `init_dataset` (upstream:9) is the half that cannot start: it `fetch`es
#     `dev-v1.1.json` (upstream:11) and then runs the BERT whitespace pretokenizer
#     (upstream:20-29), whose `ord(c) == 0x202F` (upstream:22) is the NARROW NO-BREAK
#     SPACE. A pretokenizer that drops 0x202F silently loses SQuAD answers.
# TODO(port): STOPPED AT `init_dataset` (extra/datasets/squad.py:9).
#   MISSING: `fetch` (the `helpers.bend:2815` HTTP seam, upstream:11); a JSON reader
#   for the nested `data -> articles -> paragraphs -> qas` walk (upstream:13-40);
#   `transformers.BertTokenizer` (upstream:4) -- `tokenizer.tokenize` (upstream:60,70),
#   `convert_tokens_to_ids` (upstream:110) and `convert_tokens_to_ids` over the vocab
#   are HF, not tinygrad, so there is no substrate to call; and the `dict` for
#   `token_to_orig_map` / `token_is_max_context` (upstream:91-92) plus the 384-entry
#   pad loops (upstream:113-116) whose three `assert len(...) == 384` (upstream:118-120)
#   are the shape claim.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `_check_is_max_context` (upstream:43),
#   `convert_example_to_features` (upstream:59), `iterate` (upstream:133), and the
#   `__main__` block (upstream:143) which loads `weights/bert_vocab.txt`.
#
# The upstream signature is kept on the stub because the tokenizer is a PARAMETER
# (`iterate(tokenizer, start=0)`, upstream:133), so the whole feature builder is
# generic in a type this port does not have -- naming it `Str` would be a lie about
# the port and `Refused` names the absence instead.
import Base
import ./__init__.bend as D

# upstream: `def init_dataset()` -> `list[dict]` of examples with tokenised `context`
def init_dataset() -> D.Refused:
  D.refuse("extra/datasets/squad.py:9 init_dataset")

# upstream: `def _check_is_max_context(doc_spans, cur_span_index, position) -> bool`
def check_is_max_context(doc_spans: String, cur_span_index: U32, position: U32) -> D.Refused:
  D.refuse("extra/datasets/squad.py:43 _check_is_max_context")

# upstream: `def convert_example_to_features(example, tokenizer) -> list[dict]`
def convert_example_to_features(example: String, tokenizer: String) -> D.Refused:
  D.refuse("extra/datasets/squad.py:59 convert_example_to_features")

# upstream: `def iterate(tokenizer, start=0)` -> generator of `(features, example)`
def iterate(tokenizer: String, start: U32) -> D.Refused:
  D.refuse("extra/datasets/squad.py:133 iterate")