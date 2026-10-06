# sz: what the Odin port did differently from sz.py

`references/tinyquery/sz.odin` is the same tool — token/lines-per-file, the same
`gen_stats`/`gen_diff`/table/grouping shape — ported to Odin. It is a second
opinion on a file we are porting to Bend, so it is worth knowing exactly where it
diverges from `sz.py`, because most of the divergences are decisions we have to
make deliberately rather than inherit by accident.

`sz.py` is the oracle. The 1:1 rule says we port `sz.py`, not `sz.odin`.

## The big divergence: it throws away the tokenizer

`sz.py` uses Python's `tokenize` for `.py` files and counts real tokens:

```python
tokens = [t for t in tokenize.generate_tokens(file_.readline)
          if t.type in TOKEN_WHITELIST and not is_docstring(t)]
```

`sz.odin` counts whitespace-separated words with `//` comments stripped:

```odin
commentless := line
idx := strings.index(line, "//")
if idx >= 0 { commentless = line[:idx] }
words := strings.fields(commentless)
tok_count += len(words)
```

No lexer. That is a large simplification and it is probably the right call for
Odin, where a real tokenizer is more work than it is worth for a line-counting
metric. **It is not the right call for us**, because:

1. The numbers will not match `sz.py`, so the differential test fails.
2. A metric that silently counts something else is worse than no metric — this is
   the whole reason the differential test is mandatory.

We keep `sz.py`'s two code paths exactly: real tokens for `.py`, whitespace split
for `.js`. That means writing a lexer. It is not optional.

## The subtle bit we would have got wrong

`sz.py`'s `.py` line count is NOT "lines with content":

```python
line_count = len(set([x for t in tokens for x in range(t.start[0], t.end[0]+1)]))
```

It is the number of distinct lines spanned by at least one whitelisted token. A
line containing only a comment, or only a string (docstrings are excluded), does
not count. `sz.odin` gets this for free by iterating lines and skipping empties
and `//` lines — a different mechanism that happens to be closer. Port the Python
semantics literally.

## Where sz.odin is better and we should borrow it

**`ops` and `flags` counts.** `sz.py` prints `len(Ops)` and
`len(ContextVar._cache)`, which need reflection into the running program. Bend has
no equivalent, and neither does Odin's port need one: it greps the source.

```odin
count_ops   :: reads uop/ops.odin, counts members of the `UOp_Kind :: enum` block
count_flags :: reads cfg/cfg.odin, counts lines containing "int = getenv("
```

That is the pragmatic port and we should do the same — count ops by counting the
constructors in our own `uop/ops.bend`, and flags by counting `Config`-style
entries. The grep target changes (`:: enum` and `getenv(` are Odin/Python
spellings) but the approach is right, and it is worth a comment saying why the
reflection was replaced.

**`MAX_LINE_COUNT` as a real gate.** Both have it; `sz.odin` uses a `foreign
getenv` declaration, which is a useful precedent for reading an env var from Bend.

**Selection sort.** `sort_stats`/`sort_diff` are O(n^2) selection sorts, chosen
over a real sort for simplicity. Bend has `List.sort` in Base, so we probably
should — but note that `sz.py` sorts by `-x[1]`, i.e. descending by line count,
and getting that sign right matters for the differential test.

## Where it just dropped things

- `NONCORE_DIRS` is a smaller set in Odin (3 dirs vs `sz.py`'s 5). Ours must be
  `sz.py`'s: `tinygrad/{llm,nn,renderer,runtime,viz}`.
- The path exclusion list (`tinygrad/runtime/autogen`, `tinygrad/viz/assets`)
  exists in `sz.py` and is absent from `sz.odin`. Keep ours.
- `sz.odin` hardcodes the package dir name (`tinyquery`) in three places. Ours
  hardcodes `tinygrad`, same as `sz.py`. Fine — but do not let it leak into a
  constant that reads as configurable when `sz.py` does not make it configurable.

## The output format is the hard part

`sz.py` uses `tabulate`. We have no external dependencies, so we hand-roll the
table. Getting `tabulate`'s exact column padding, the `+d` signed integer format,
and the `.1f` float format to match byte-for-byte is fiddly but it is the
difference between a passing and failing differential test. Budget for it.

If it proves impossible to match byte-for-byte, say so and show the smallest
divergence — do not quietly change what is counted.