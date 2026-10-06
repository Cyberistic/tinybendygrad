# gendirs — the shared, DISCOVERED generated-directory population

**One module, two consumers.** `gates/gendirs.py` is imported by path by both
`gates/retention-check.py` (clause V) and `gates/gates-pop.py` (clause IV). MEASURED: both print
**194**. Not reconciled — there is one function, so they cannot disagree.

| file | what it is |
|---|---|
| `TABLE.md` | **every directory in the tree something writes into**, tracked / ignored / empty-blob, and which instrument can see it |
| `properties.md` | the four candidate properties, each measured, and **why a scan and not a list** |
| `writetargets.py` | the standalone scanner that produced `TABLE.md`; superseded by `gates/gendirs.py`, kept because it is the first version and its **four misses are the argument** |
| `properties.py` | the git-side measurements behind the `empty blob` column |

## The subject

`checks/gen/` — `checks/abi_gate.py:606` `gendir.mkdir(exist_ok=True)`, `:616`
`subprocess.run([BEND, probe, "-o", str(gendir / f"probe.{ext}")])`, 268,523 bytes of `bend`
backend per run, whose two index entries were git's **empty blob** while the worktree held the
real bytes, and which **9 of 9** citations in `checks/abi.json` resolve into and
`checks/abi_gate.py:624` reads back. `checks/census.py:64` writes `checks/rows-*.rows` the same
way: **51** more.

Neither meta-instrument could name it. `retention-check.py` had a two-item `Output(...)` registry;
`gates-pop.py` had `HOMES = ("checks", "gates")`. **A POPULATION DEFINED BY A THREE-ITEM LIST
CANNOT BE WRONG ABOUT A FOURTH ITEM BECAUSE IT NEVER LOOKS AT ONE.**

## Run

```sh
python3 gates/gendirs.py             # the table, with the coverage denominator
python3 gates/gendirs.py --plant     # 7 plants on synthetic trees; never touches the live one
```

**A LOWER BOUND, PRINTED ON EVERY RUN.** `checks/abi4_gate.py:501` reaches `checks/gen/` through
`rc_of`, a `subprocess.run` that **names no output path at all**. No static scan closes that: the
writer is named by a call and the target by a convention inside another program. Closing it needs
execution, and nothing here executes a gate.