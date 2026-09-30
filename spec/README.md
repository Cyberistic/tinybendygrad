# spec/

Two things live here.

**The specification being ported.** `tinyspec.tex` is tinygrad's own spec, 460
lines of LaTeX tables. It is not ours and is never edited. `render.sh`
regenerates `tinyspec.pdf`.

**The walkthroughs.** One short file per unit of the port, written by whichever
agent did that unit, explaining what converting it to Bend gained. They are
meant to be read in order by someone who has never seen this project, and they
get rewritten by a human afterwards — so they are rough, short, and free of
adjectives.

| file | what it covers |
| --- | --- |
| [laws.md](laws.md) | tinyspec's prose tables, as Bend types and machine-checked laws |
| [shape-laws.md](shape-laws.md) | pinning the element count across views; a vacuous law we caught |
| [ops.md](ops.md) | the UOp arena: a cyclic graph as a `U32` index, and the wall the property folds hit |
| [sz.md](sz.md) | CPython's tokenizer in Bend, and the three Bend rules that shaped it |

The next units of the port add their own file here: `dtype.md`, `schedule.md`,
`codegen.md`, `renderer.md`.