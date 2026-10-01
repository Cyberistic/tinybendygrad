# sz comparison — `sz.py` → `tinybendygrad/sz.bend`

`sz.py` is 95 lines and prints two tables and four totals for a tree of Python
files. It is small, and it is the only honest test of a tokenizer that exists in
this repo: **every number it prints is one CPython `tokenize` answer away**, so
`python3 sz.py` and `./bin/bend tinybendygrad/sz.bend` can be diffed byte for
byte. The full table is below; the summary is that the two agree on all 222
counted files of this tree and on every line of output except two.

Read with the Bend file. Line numbers are sz.py's. `bend` is the def in
`tinybendygrad/sz.bend`; a `.go` / `.end` / `.put` suffix is a helper the
representation forces (a `match` cannot scrutinize a computed value, so the value
gets its own def whose *parameter* is the scrutinee).

## Summary

| | count |
| --- | --- |
| sz.py defs / constants, all inventoried | 8 rows |
| **faithful** (same shape, same name, same meaning) | 3 |
| **adapted** (same meaning, different shape; the def carries the reason) | 5 |
| **MISSING** | 0 |
| **dropped** (named here, deliberately not ported) | 2 |
| **divergences** (stated, verified, in the table) | 9 |
| Bend defs / types in the file | 220 defs, 9 types, 1675 lines |
| the two effects | `runtime/sz.c` 88 lines, `runtime/sz.js` 32 lines |
| `@unsafe` | 0 |
| `--check-only` | 7 defs rely on unsafe or foreign code, exit 1: the two effects, three walk defs, two dispatch |
| files whose token and line counts match CPython | **222 / 222** |

The `--check-only` count is 10, not 2, and the compiler is right: the notice is
the transitive closure. `Sz.read_dir` and `Sz.is_dir` are the foreign defs, and
`walk.item` (which stats), `walk.scan`, `walk` (which lists), `sz.stats`,
`sz.one`, `sz.two`, `sz.main` and `main` all reach one. There is no third kind of
problem in the file: no other error is printed, and no `@unsafe` is written.

## The table

| sz.py | line | bend | verdict |
| --- | --- | --- | --- |
| `TOKEN_WHITELIST` | 10 | *(none)* | **dropped as a list** — it is `[OP, NAME, NUMBER, STRING]`, which is what the lexer counts. The whitelist is the set of tokens `emit1` produces, and a name for it would be a list nothing reads |
| `is_docstring` | 12 | `is_docstring` | faithful — `t.string.startswith('"""')` is the `tri` flag the string state already carries, and `t.line.strip().startswith('"""')` is "no counted token has reached this line", which is `last != line` |
| `is_js_token` | 15 | `is_js_token` | faithful — `len(s) and not s.startswith('//')` |
| `gen_stats` | 17 | `sz.stats` + `walk`, `walk.item`, `walk.scan`, `walk.file`, `sz.keep`, `sz.lane`, `sz.py`, `lex`, `js.count` | **adapted** — the `os.walk` loop becomes a worklist of directories on a `Nat` fuel, because Bend has no `for` and no `yield`. The row order is `os.walk`'s exactly: a directory's counted files first, then its subdirectories, each in `readdir` order, and the effects **do not sort** (see *Edge cases*) |
| `gen_diff` | 35 | `gen_diff` + `added`, `deleted`, `same`, `pick`, `add.go`, `del.go`, `diff.go`, `changed` | **adapted** — `files_new - files_old` is a *set*, and a set is a membership question, which is `pick` (a linear scan). A row with an empty name is the one a tree does not have, so `Maybe` is not needed; the sets' iteration order is not specified by Python, and the port emits table order (see *divergences*) |
| `display_diff` | 57 | `display_diff` | faithful — `"+"+str(d) if d > 0 else str(d)`, so the else branch keeps the sign and zero is `0` |
| `NONCORE_DIRS` | 59 | `core` | **adapted** — a set of five strings becomes a `match` over the group name; the comment on the def says what the set was |
| `if __name__ == "__main__":` | 61 | `sz.main`, `sz.one`, `sz.two` | faithful — the three modes by `len(sys.argv)`, and `sz.show` is the `if table:` |
| `tabulate(..., headers="firstrow")` | 76, 81 | `tabulate` + `tab.*` (14 defs) | **adapted** — hand-rolled "simple" format: a column as wide as its widest cell or its header plus 2, two spaces between columns, a dash row, names left and numbers right, no trailing space. `tab.wide` is the `widths` pass, `tab.hd3`/`tab.hd5` the header, `tab.go3`/`tab.go5` the rows, and `d` is the flag the diff table runs under |
| `sorted([x[0].rsplit("/", 1)[0].split("/")[0:2]) ... itertools.groupby` | 82-87 | `group`, `summary`, `summary.put`, `summary.fin`, `gline`, `Run` | **adapted** — the sorted-then-groupby becomes one fold that sorts by group and carries a `Run{text, g, s, n}`, because a stable sort already makes each group one run and the order inside a run is a sum, so it does not matter |
| `sum([v for k, v in dir_sizes.items() if k not in NONCORE_DIRS])` | 91 | `core.lines`, `core.of`, `core.go` | faithful — a `List.foldl` over the rows |
| `sum([x[1] for x in table])` | 92 | `total.rs`, `total.go` | faithful |
| `int(os.getenv("MAX_LINE_COUNT", "-1"))` + `assert` | 94-95 | `sz.checked.rs`, `sz.checked.env`, `num`, `num.go`, `sz.limit` | adapted — `IO.get_env` hands back a `Result`, and `assert` is `IO.die` with the same message. The exit status and the `OVER n LINES` line are verified identical |

## The lexer

The tokenizer is the whole file: 91 of sz.py's 95 lines are `gen_stats`, and
`gen_stats` is 8 lines of Python over `tokenize`. It becomes `chars`, `lex`, `go`
and about 90 defs of state machine over the three types `Pnd` (the open token),
`St` (the f-string state) and `Xs` (all three), because **Bend has no lookahead
and no rewind**. A token one char cannot decide is left OPEN in the state (`Pnd`)
and the next char decides it; the alternative, a three-char window, needs the
window shifted on every step, and a list can only be passed on as a bare tail.

Three rules cost most of the shape, and each is a comment on the def it binds:

- **A `match` cannot scrutinise a computed value.** Every test a `match` reads
  arrives as a parameter: `eq(c, q)`, `cls3(c)`, `brm(c)`, `isdig(r, c)`,
  `pfx1`/`pfx2b`.
- **A def body is one term.** A `match` cannot follow a `let`, which is why
  `Lit{q, back, close, tri, k}` carries the char in hand, why `p0.end` is
  `Xs{Nxt{c}, st, a}` and why the states are threaded instead of returned in
  pairs.
- **No forward references.** Every callee is defined earlier, so a recursion must
  live in one def that calls only earlier pure helpers.

`go` is one recursive def over a char list, tail-recursive, and its list is its
first argument so the self-call shrinks structurally.

## Verified

| check | result |
| --- | --- |
| 222 counted files (124 `.py` + 2 `.js`), tokens and lines against CPython `tokenize` | **222 / 222 match** |
| `/tmp/sz` vs `.venv/bin/python sz.py` on this tree, 0-arg | identical except the two dropped lines |
| the same, 1-arg (`.`) | identical except the two dropped lines |
| `/tmp/sz a b` vs `sz.py a b` on two trees with one added, one deleted, one changed file | **byte identical** |
| edge tree: empty file, comments-only, no trailing newline, unicode in a string, f-strings, `.js`, an unwalked path | **byte identical** |
| `MAX_LINE_COUNT` unset / `-1` / over the limit | identical output, identical `OVER n LINES`, exit 1 both |
| a tree with no counted file, and a tree that does not exist | identical (no output) |
| interpreted lane (`./bin/bend tinybendygrad/sz.bend <tree>`) vs compiled | byte identical output on every tree both lanes can run |

### The two differences, in full

```
                                        tinygrad/uop                   :   2614 in 10 files
 core lines: 9495
total lines: 25591
```

`sz.py` also prints, between the group summary and `core lines`:

```
        ops: 77
      flags: 55
```

`len(Ops)` and `len(ContextVar._cache)` are **tinygrad's own reflection**: the
number of members of a `UOp` enum and the number of `ContextVar` flags that
`helpers.py` has constructed. Neither is a thing a tokenizer can see, and
porting them would mean importing `tinybendygrad/uop/` and `helpers.bend` and
making this file depend on the two. The lines are dropped, and `sz.text.stats`
says so on the def. Everything else in the 131 lines is identical.

## Divergences

Each is measured, not assumed.

| divergence | what sz.py does | what the port does | why |
| --- | --- | --- | --- |
| `ops:` / `flags:` | prints both | drops both | tinygrad's reflection, above |
| an error message | `tokenize.TokenError` with a message and a traceback, on stderr | `a line the tokenizer cannot read` with the CPython **error code** as the exit status, on stderr | a Bend def cannot raise with a message it built, and the code is the part that is comparable. **Both die on the same inputs** — verified on 9 malformed f-strings, an unterminated string, an unterminated bracket, a lone `}` in an f-string and a spec field left open |
| the diff row order | `set` iteration order, which Python does not specify | added, then deleted, then unchanged, each in table order | a `List` has no set order to reproduce. The two agree on every tree here; a larger added/deleted set could order differently |
| the f-string errors | `f-string: expecting '}'`, `single '}' is not allowed` | the same inputs die, with the code, not the text | as above |
| Unicode whitespace in the `.js` lane | `str.split()` breaks on all Unicode whitespace | `is_hspace`, the ASCII half | the port's whitespace test is the one CPython's tokenizer uses, and `str.split()` uses a wider set. A `.js` line separated by U+00A0 would count differently |
| an unclosed bracket at EOF | raises `unexpected EOF in multi-line statement` | counts the tokens and the line | the port has no error for it. No file in this tree has one, and the per-file check would have printed it |
| a non-printable character in a source file | raises | counts it | as above |
| NFKC | `tokenize` NFKC-normalises an identifier before the NAME test | no normalisation | it can only change whether a name is a name, and the count of names is the same either way for every file here |
| the walk's bound | `os.walk` has no bound | a `Nat` fuel of 16777216 names | a Bend recursion must be structurally decreasing and a worklist tail cannot carry what a tail call would have to add, so the count of names left is what decreases. 16777216 is ten times this tree's name count |
| a single file of 28988+ bytes (28987 passes), per-file and content-independent | — | the **interpreted** lane dies with `bend: memory fault (machine stack overflow?)`; the compiled lane is fine | the bun/JS host stack, not this code: the `.js` lane, which never runs the lexer, dies at the same size, and the compiled lane reads this tree's largest file (`uop/ops.py`, 110 KB) and a 20000-line file without complaint. **This is the one wall that stops the interpreted lane from running this tree**, and it is a host limit |

## Edge cases checked

| Python edge case | survives? | where |
| --- | --- | --- |
| an empty file | yes — no row, because `line_count > 0` | `sz.keep` |
| a comments-only file | yes — no row | the lexer's `Cmt{}` never reaches `emit1` |
| no trailing newline | yes | the EOF sentinel at 1114112 closes the last token |
| a `\r\n` line ending, and a bare `\r` | yes | `Cr{}`, and `sq.cr` / `lit.cr` for a string |
| unicode in a string and in a comment | yes | `chars` reads code points, `Char.to_u32` is the one number |
| a line continuation | yes | `Bs{k}` |
| a file that is not `.py`/`.js` | yes — skipped | `counted` |
| a **directory** named `x.py` | yes — a directory, not a file | `walk.item` tests `is_dir` first, which is what `os.walk`'s split does |
| `tinygrad/runtime/autogen`, `tinygrad/viz/assets` | yes — the files are skipped and the directories are still walked, as `os.walk` does | `skip` in `walk.item`'s file test only |
| a path with a `\` in it | **no** — `path.replace('\\', '/')` is a Windows concern and no path here has one | `skip` compares the forward-slash path |
| two files of the same length | yes — the table keeps `os.walk`'s order, because the effects do not sort and `List.sort` is stable | `tab.le` is `>=`, which is the tie a stable sort needs |
| a group of one file, and a file at the top of the tree | yes | `group.go`'s `case _ <> Nil{}` and `String.drop`'s empty result |
| `MAX_LINE_COUNT` unset, `-1`, and over the limit | yes, all three | `sz.checked.env`, `num`, `sz.limit` |
| a `Maybe` where a set membership was | replaced by an empty name | `Row.none`, `Row.found` |
| the `ops`/`flags` reflection | **no** — dropped | `sz.text.stats` |
