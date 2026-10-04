# `norm/` — ONE canonical float spelling, and the census that keeps it the only one

Read `.agents/slop/NORM.md` first. Rules `NORM-1..7`.

| file | what it is |
|---|---|
| `canon.py` | **THE HELPER.** `canon(value, width)`, `canon_bits(pattern, width)`. The width is an argument and `canon` refuses a NaN spelling. |
| `canon.selftest.py` | the four motivating rows, the two properties they rest on, and the plants that make each row able to fail |
| `gate_norm.py` / `gate_norm.bend` | those rows on `node` AND `cc`, four verdicts never summed |
| `lint_norm.py` | the census of every normaliser in the tree's gates; exit 1 on a NEW bad one |
| `lint_demo.sh` | both of the lint's exit branches, measured. `zsh`, not `sh`. |
| `f32show.bend` | the compiler's OWN float spelling, in bulk, from the emitted runtime |
| `census.txt` `gate.txt` `selftest.txt` `fixtures.txt` | the four generated outputs |

```
python3 canon.selftest.py && python3 gate_norm.py && python3 lint_norm.py
zsh lint_demo.sh
```

All five exit 0 on the tree as it stands. `lint_demo.sh` exits 1 by design: it
plants a normaliser in a `$TMPDIR` copy to show the lint can fail.