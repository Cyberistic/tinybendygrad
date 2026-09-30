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
| [depth.md](depth.md) | replacing `@unsafe` with an explicit fuel budget, and what it cost |

The next units of the port add their own file here: `dtype.md`, `ops.md`,
`schedule.md`, `codegen.md`, `renderer.md`.