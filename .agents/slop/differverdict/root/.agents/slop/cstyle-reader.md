# DELIVERABLE 1 — what I did to `rows_shipped`

`.agents/slop/cstyle-gate.py`. Import the shared reader; do not copy it.

## The change

`rows_shipped` was a 32-line fork whose docstring opened *"rebase-gate.py's `rows()`,
**verbatim**"*. It is now the imported function, three lines:

```python
def load(name):
  spec = importlib.util.spec_from_file_location(name, str(pathlib.Path(__file__).parent / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod

rows_shipped = load("rebase-gate").rows
```

`rebase-gate.py` was **not edited**. It is owned by another unit.

## The claim was false, and the measurement is by CALL

Both readers called on six shapes. They agree on **2 of 6**.

| shape | the fork said | `rows()` said | agree |
|---|---|---|---|
| `a=b` (F1) | `{'a': 'b'}` | `{'a': 'b'}` | yes |
| `alpha  1` (F3) | `{}` | `{'alpha': '1'}` | **NO** |
| `kern=[*V]   py=[*W]` (F2) | `{'kern': '[*V]   py=[*W]'}` | `{'kern': '[*V]'}` | **NO** |
| `== SECTION ==` | `{'': '= SECTION =='}` | `{}` | **NO** |
| `=v` | `{'': 'v'}` | `{}` | **NO** |

Three distinct failures, not one: it could not read F3; it could not fold F2's `py=` column away;
and it **manufactured the `""` phantom** that `rows()` excludes on purpose.

## What the number it printed actually was

The line it fed was `len(readerA) - len(readerB)` labelled *"of them shredded out of multi-line
values"*. Over this tree's own oracle lane it printed:

```
the shipped rows() over the SAME oracle stdout: 222 names -- -2 of them shredded out of multi-line values
```

**`-2`.** Two readers do not have a shred relationship; they have a disagreement set, and it is
symmetric. Replaced with a parity line carrying both directions and the intersection:

```
the SHARED reader (rebase-gate.py:rows()) over the SAME oracle stdout: 222 names --
  6 only it finds, 8 only rows_strict finds, 216 in common
  only the shared reader: ['kern BASE  lb', 'kern CLANG lb', 'kern CUDA  lb', ...]
  only rows_strict     : ['kern BASE  lb=1', 'kern CLANG lb=4', 'kern CUDA  lb=1', ...]
```

## Two things the fix could not be waved through

**`rows()` must NOT become `judge()`'s reader.** `rows()` returns `left` with `py=` already folded
away; `split_py()` reads `py=` back *out of* the value to report STALE-LITERAL. MEASURED by
substituting one for the other inside `judge()`: **BROKEN on 225 of 227 rows**, all of them
`"carry no py= column"` — an incompatibility between contracts, not a disagreement. So this name
stays a *parity* reader; the comparison keeps `rows_strict`, and the docstring says why.

**The name set and the values are separate measurements, and on this pair they point opposite
ways.** Over the real port lane the fork and `rows()` agree on **225 of 225 names** and differ on
**225 of 225 values**; over the oracle lane (no `py=` tail) they agree on 222 of 222 names *and*
222 of 222 values. A reader-swap that moves only the print on this lane pair is a coincidence of
this text, not a general property — hence the six-shape control set in deliverable 3.

## Also fixed in this file, because deliverable 2 could not be answered without them

Both are pre-existing, both were reproduced against the committed blob, neither is the reader.

1. **Capture mode discarded the oracle's stderr.** `--oracle-stdout` alone gave
   `count_refusals("") == 0` and `UNREPORTED-REFUSALS 9` over sound lane text — BROKEN for a
   reason belonging to neither lane. A capture mode that can only ever be red is not a capture
   mode. Added `--oracle-stderr`, and a capture without one is now **refused** rather than guessed.
2. **Capture mode printed `live port lane rc=0` while running nothing live.** The rc came from the
   `CompletedProcess` built out of the capture. Now the word matches the lane that ran.

After both: `--selftest` passes under `.venv/bin/python` (exit 0, all four lanes), identical to the
committed file's behaviour.