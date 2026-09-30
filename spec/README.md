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
| [weak.md](weak.md) | the dtype promotion table: 3 of 8 rules, and the `_min_max` wall under them |
| [divandmod.md](divandmod.md) | FLOORDIV folding, and a brief whose premise was wrong three ways |
| [symbolic.md](symbolic.md) | 16 of 130 rewrite rules, and the walls that name the other 114 |
| [movement.md](movement.md) | nine rules on a rewrite engine whose rules return the arena |
| [render.md](render.md) | the repr layer: gates string-diffed against CPython, and the one red row |

The next units of the port add their own file here: `dtype.md`, `schedule.md`,
`codegen.md`, `renderer.md`.