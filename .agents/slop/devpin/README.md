# `.agents/slop/devpin/` — the device is a precondition, and these are the measurements

**Start with `00-device.md`.** Four files, in the order the job asked the questions.

| file | the question | the answer, in one line |
|------|--------------|-------------------------|
| `00-device.md` | **what device was every run in `runs/graphcmp/D` taken under, and how do you know?** | `DEV=CPU` — **three** independent ways: the `graphcmp.py:2839` argparse default `:2853` writes before `load_tinygrad()`, `sCPU` in 99 of 139 artifacts, and `--dev CPU` re-emitting `D2-canon-py-lin.txt` **byte for byte** |
| `01-env-table.md` | **every environment variable the two sides can read, and can it move a verdict?** | 147 flags AST-counted; **8 can** (4 move the rows, 3 move only the artifact's non-row bytes, `NO_COLOR` is already neutralised), **5 refuse**, **128 measured inert**, 6 excluded with a reason each |
| `02-lin-decision.md` | **which of the three answers for `lin`?** | **none as framed — `lin`'s `DISAGREE` holds on all four devices and does not move.** The device dependency is real and lives in **14 other AGREE rows** |
| `03-injectivity.md` | **is the canonical form injective on the 25 graphs' rows?** | **yes** — 88 live instances → 44 strings, **0 collisions**, 0 ambiguous parses. The `""`-join's blind spot is real and constructed; it did not fire |

**Every number above is reproducible from this directory with no arguments:**

```
.venv/bin/python .agents/slop/devpin/injectivity.py     # 03
.venv/bin/python .agents/slop/devpin/lin-decision.py   # 02   (~14 s)
.venv/bin/python .agents/slop/devpin/envsweep.py       # 01   (~2 m20 s)
.venv/bin/python checks/devpin.py --plant satisfied    # the gate, pin as the repo stands
.venv/bin/python checks/devpin.py --pin METAL --plant moved
```

**NOTHING HERE WRITES TO `runs/graphcmp/D`.** The recorded artifacts are opened read-only and
compared; `devpin.py` re-emits into a pipe. `checks/differ.py` was neither edited nor run.
`bend` was never invoked, so **the BEND side's injectivity is measured from the recorded
artifacts only and is named as NOT DONE** rather than glossed.
