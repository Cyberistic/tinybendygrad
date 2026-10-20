# STUB -- 1:1 PATH MIRROR of extra/datasets/wikipedia.py (398 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. The largest file in this slice and the one with the most PORTABLE
# logic: the BERT BasicTokenizer + Wordpiece front end is pure string work over
# integer ranges, with no tensor and no network, so it is the best value per line
# anywhere under `extra/`. It is (b).
#   * `_is_punctuation` (upstream:34) is four inclusive ranges and nothing else --
#     `range(33,48)`, `range(58,65)`, `range(91,97)`, `range(123,127)` (upstream:39) --
#     with `unicodedata.category(char).startswith("P")` as the fallback (upstream:41).
#     Those four ranges are EXACTLY ASCII punctuation, so the fallback is the only
#     non-ASCII part and the two halves are separable.
#   * `_is_chinese_char` (upstream:43) is eight ranges over codepoints (upstream:44-51)
#     ending `return False` (upstream:53) -- the standard BERT CJK table, half-width
#     0x3400-0x4DBF first, then the four SIP planes, then 0xF900/0x2F800 compatibility.
#   * `_wordpiece_tokenize` (upstream:101) is greedy longest-match-first over `vocab`
#     with a `##` continuation prefix (upstream:118) and the 200-char guard that
#     emits `[UNK]` (upstream:106-108). The `while start < end: ... end -= 1`
#     (upstream:116-121) is the inner search, and `is_bad`/`sub_tokens` decide whether
#     the WHOLE word degrades or just emits `[UNK]` (upstream:129-130).
#   * `create_masked_lm_predictions` (upstream:173) is the 80/10/10 mask split
#     (upstream:194-200) over `cand_indices` with `[CLS]`/`[SEP]` excluded
#     (upstream:176-177), which is the rule that keeps a separator from being masked.
# TODO(port): STOPPED AT `_is_whitespace` (extra/datasets/wikipedia.py:24), the first
#   def in the file, because every classifier below it needs the one thing this port
#   has least of.
#   MISSING: `unicodedata.category(char)` (upstream:27/32/41/74) -- the Unicode
#   general category, `Zs`/`C*`/`P*`/`Mn` -- which is a table the port does not carry
#   and cannot approximate. `_is_control` (upstream:29) is the trap that makes a
#   partial port unsafe: it returns False for `"\t"/"\n"/"\r"` (upstream:30-31) BEFORE
#   consulting the category, so a port that only has `startswith("C")` would classify
#   the three characters BERT treats as whitespace as control, and `_clean_text`
#   (upstream:78) would delete every tab and newline in the corpus.
#   ALSO MISSING, in rough dependency order: `random.Random` as an injected
#   `rng` PARAMETER (`create_masked_lm_predictions(rng, ...)`, upstream:173) -- the
#   AGENTS.md rule "Inject time instead of sleeping" has the same shape here, and
#   upstream already half does it by threading `rng` instead of using the global;
#   `getenv` with a FLOAT default (`getenv("MASKED_LM_PROB", 0.15)`,
#   `getenv("SHORT_SEQ_PROB", 0.1)`, upstream:182/218) -- `helpers.bend` has
#   `getenv_str` and `getenv_int` only, and a float default read as an int is a
#   silent 0.0; `pickle` for `train/{part}.pkl` (upstream:358-359,391);
#   `tqdm.contrib.concurrent.process_map` with `chunksize=1` (upstream:394);
#   `diskcache` (upstream:381); and numpy for `instance_to_features`' seven
#   `np.expand_dims(np.array(...), 0)` rows (upstream:343-349).
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `_is_control`, `_is_punctuation`,
#   `_is_chinese_char`, `_run_split_on_punc`, `_run_strip_accents`, `_clean_text`,
#   `_tokenize_chinese_chars`, `whitespace_tokenize`, `_wordpiece_tokenize`, the
#   `Tokenizer` class (`__init__`/`tokenize`/`convert_tokens_to_ids`/
#   `convert_ids_to_tokens`, upstream:133-155), `truncate_seq_pair`,
#   `create_masked_lm_predictions`, `create_instances_from_document`, `get_documents`,
#   `get_instances`, `instance_to_features`, `process_part`,
#   `get_features_from_part`, `get_wiki_train_files`, and the `__main__` block.
import Base
import ./__init__.bend as D

# upstream: `def _is_whitespace(char:str) -> bool` -- four literals, then category == "Zs"
def is_whitespace(char: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia.py:24 _is_whitespace")

# upstream: `def _is_control(char:str) -> bool` -- "\t"/"\n"/"\r" are False BEFORE the category
def is_control(char: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia.py:29 _is_control")

# upstream: `def _is_punctuation(char:str) -> bool` -- ranges 33-48, 58-65, 91-97, 123-127
def is_punctuation(char: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia.py:34 _is_punctuation")

# upstream: `def _is_chinese_char(cp:int) -> bool` -- eight codepoint ranges
def is_chinese_char(cp: U32) -> D.Refused:
  D.refuse("extra/datasets/wikipedia.py:43 _is_chinese_char")

# upstream: `def _wordpiece_tokenize(text:str, vocab:dict[str,int]) -> list[str]`
def wordpiece_tokenize(text: String, vocab: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia.py:101 _wordpiece_tokenize")

# upstream: `def instance_to_features(instance:dict, tokenizer:Tokenizer) -> dict` of 7 arrays
def instance_to_features(instance: String, tokenizer: String) -> D.Refused:
  D.refuse("extra/datasets/wikipedia.py:315 instance_to_features")