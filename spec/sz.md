# sz: a CPython tokenizer in Bend, and what it cost

`sz.py` counts the tokens and the counted lines of every `.py` file under a tree.
It is 95 lines, and 8 of them are CPython's `tokenize`. Porting it is therefore
porting a tokenizer, and the tokenizer is where a Bend port earns or loses.

The file is `tinybendygrad/sz.bend`; the comparison, def by def, is
`.agents/slop/notes/compare/sz.md`. The claim this walkthrough makes is narrow
and measured: **on all 222 counted files of this tree the port's token and line
counts are CPython's, and the printed tables are byte identical except for two
lines of tinygrad's own reflection.**

## What was gained

**A differential test for the whole port.** Every other unit in this repo is
checked against itself. `sz.py` is checked against CPython, so a wrong count in
the lexer is a wrong count in the table, and the table is `diff`-able. The
`.agents/slop/notes/sz-lexer-proto.py` harness that checks one file's
`(tokens, lines)` in isolation is what made the last four lexer bugs findable;
each was a rule that held for the shape the author was thinking of and not for
Python:

- `a.b` lost the `b`: a lone `.` is opened and only closed if a digit follows, and
  the char in hand was dropped rather than re-read.
- `''` lost the char after it: the state that meant "a second quote, so it may be
  a triple" consumed a char that was never part of the string.
- `rf[0]` became an f-string: a two-letter prefix was taken on the name's length
  and not on the char being a quote.
- `f"{a:{w}}"` miscounted the `}` that closes a field of a format spec.

**The output format is hand-rolled and therefore checked.** `tabulate`'s
"simple" format is 14 defs here, and hand-rolling it is what exposed that
`%.1f` needs tenths carried as an integer with halves to even, and that a
difference of two ratios is not the difference of their rounded forms.

## What it cost

**A `match` cannot scrutinise a computed value, and it is the rule that shaped
the file.** Every test a `match` reads must arrive as a parameter, so the lexer
has `eq(c, q)`, `cls3(c)`, `brm(c)`, `isdig(r, c)` and the `pfx` ladders: small
defs whose only job is to make a value a scrutinee. That is ~20 of the 220 defs,
and it is not incidental — it is the price of the rule.

**A def body is one term, so state is threaded instead of returned.** Two
things follow. A token one char cannot decide is left OPEN in the state and the
next char decides it, because a `match` cannot follow a `let`; and the char that
closed a token travels in the state (`Nxt{c}`) rather than in a result, because
the step that got there has already read it. The `Pnd`/`St`/`Xs` triple is
exactly that constraint spelled out.

**No forward references, so `os.walk` cannot be a generator.** A worklist of
directories is one recursive def on a `Nat` fuel, and a directory's names are
read into two lists — the counted files and the subdirectories — that a third
def joins, because `os.walk`'s order (a directory's files, then its
subdirectories, each in `readdir` order) is not what one list gives you. The
`walk.item` def names the reason on the def.

**The walk's fuel is a bound the original does not have.** 16777216 names, ten
times this tree. It is stated on `sz.stats` rather than hidden.

**Two lines of output are gone.** `len(Ops)` and `len(ContextVar._cache)` are
tinygrad's own reflection, not tokenizer answers, and porting them would make
this file import the UOp arena and the flags table. Dropped, and `sz.text.stats`
says so where a reader will look.

## The wall worth naming

The **interpreted** lane dies on a single file of 28988 bytes or more (28987 passes), per-file and content-independent, with a machine
stack overflow; the compiled lane reads this tree's largest file, 110 KB, and a
20000-line file, without complaint. It is a host limit, not this code: the `.js`
lane, which never runs the lexer, dies at the same size. So the compiled lane is
the one to run `sz` with, and the two agree byte for byte on every tree both
lanes can run.

## Rules this unit established

- A computed value a `match` must read gets **its own def**, named for the test
  (`eq`, `cls3`, `brm`, `isdig`), not a local `let`.
- A state machine whose states share a shape is **one datatype with a tag** and
  an arm per state, not a set of small records.
- A hand-rolled print format is **diffed against the library's**, because the
  library's rounding and alignment rules are the spec.
