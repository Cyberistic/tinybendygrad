# `checks/txt-owners.py`: it is not the second opinion, and it did not need to run

Measured 2026-10-19 04:25Z-04:45Z, `.venv/bin/python` = CPython 3.12.10, `HEAD 12149576f7ef`.
Every number below carries its command. The tree was being written by other units throughout; two
readings of the SAME instrument differ by one file and the difference is identified, not smoothed.

## 1. WHY IT TIMED OUT, AND HOW FAR IT GOT

**ONE LINE. `checks/txt-owners.py:85` evaluated `no-txt.py`'s `excused_names()` inside the filter,
so it ran once per owned `.txt`.**

```
.venv/bin/python .agents/slop/txowners/probe2.py
  walk only                 0.285s  owned .txt found = 432
  excused_names() #1        0.333s  |set|=508
  excused_names() #2        0.394s  (identical=True)
  ONE excused call          0.000s  hard=183
  AS WRITTEN (per-item)   124.245s  hard=183
```

`probe3.py` attributes the per-call cost to a single loader:

```
  loader graphcmp_artifacts  0.0010s   loader empty_remnants  0.0001s
  loader plant_artifacts     0.0002s   loader skipexit_artifacts 0.0006s
  loader dup_census_lanes    0.2379s   <- 99% of every call
```

`no-txt.py:162` re-`rglob`s all of `.agents/slop` -- **6,430 files** -- on every call. So the cost is
**432 calls x 6,430 files = 2.78M path stats**, i.e. **O(owned .txt x .agents/slop)**: quadratic in the
product of two counts that both grow with the tree. Not one quadratic; two multiplicative factors, and
99% of the time in one of them.

**How far in 120 s** (`probe4.py`, the line replayed verbatim against a hard 120 s cutoff):

```
CUT OFF at 120.0s after 379/432 items (87.7%), hard so far=183
measured rate = 3.16 items/s -> full run ETA = 137s
```

`hard so far = 183` IS the final answer at item 379: the set is order-independent, so the last 12% was
not progress, it was 53 more calls that could not change the count. **Completing it once, for real:
129.62 s** (`time .venv/bin/python checks/txt-owners.py`, 04:32:44Z-04:34:54Z), rc 0.

**It is not a subprocess per file and not a `git` call per file.** `code_files()` runs `git ls-files`
**once** (0.020 s). There IS a second quadratic -- `callers(gen)` re-ran that subprocess AND re-opened
every file, once per generator -- but it is **latent**: with 0 attributed generators it never fires.

## 2. IT IS NOT A SECOND OPINION. IT IS NOT EVEN A SIMILAR-LOOKING ONE.

The question was framed as "the second opinion on the carve-out". It is an **attribution census over
the hard set**: which generator's own source writes each file the guard reports. Different subject,
different output, no overlap in what it asserts. Its own docstring says so at lines 39-42, and it is
right: `no-txt.py:excused_names()` is **IMPORTED**, so the two hold one opinion by construction.

## 3. RUN TO COMPLETION, AND THE SET DIFFERENCE

```
.venv/bin/python checks/txt-owners.py      -> 129.62 s, rc 0
  184 `.txt` reported by checks/no-txt.py, attributed to OWNING GENERATORS
  0 generators own 0 credits over 0 distinct files.
  184 are named by NO write path in the tree
```

The EXEMPT set difference is **0, and the 0 is not evidence.** `probe7.py`: no-txt's EXCUSED (249
owned) and txt-owners' exempted set are the SAME SET, because the second is computed as
`owned - hard_set()` and `hard_set()` subtracts that same function. A second opinion cannot agree with
the first when it is the first.

The tree moved under the run and it is worth naming: the as-is run (04:32Z) said **184** including
`.agents/slop/export/nnnorm/`; the fixed run (04:44Z) said **183** and that path is gone.
**`no-txt.py`, untouched, said 183 at 04:44:24Z too** -- the shift was another unit, not this change.
Baselines here must be read as a PAIR inside one command, never across two.

## 4. THE PLANT: THEY CANNOT DIVERGE

A real declaration change with no protected file edited: `no-txt.py:124 empty_remnants()` honours
`txtexec/rename.py:LEFT_EMPTY` **only while the file is 0 bytes**, so one byte in
`oracles/rows-bd.txt` makes exactly one declared path stop being declared.

```
pre-plant : no-txt.py -> 183 .txt FILE(S)
planted   : excused_names() 508 -> 507 ;  empty_remnants() -> set()
UNDER PLANT: no-txt.py      -> 184 .txt FILE(S)
UNDER PLANT: txt-owners.py  -> 184 `.txt` reported by checks/no-txt.py
restore   : stat -f%z = 0 ; git hash-object = git rev-parse HEAD:oracles/rows-bd.txt = e69de29b
```

**+1 in lockstep, both instruments, and the plant restored byte-exact.** That is the finding: there is
no disagreement available to find, because the second opinion is a function call into the first. An
unrunnable second opinion would have been a gap. A second opinion that is *the first opinion* is a
different thing, and nobody should plan around it.

## 5. WHAT WAS ACTUALLY WRONG WITH IT -- the finding that outranks the timeout

**The census is blind to `os.replace`, and `checks/differ.py` writes 100% of the carve-out that way.**

```
differ.declared() = 244 names, of which 244 end in .txt
differ.py:443  tmp = D / f".tmp.{out}"
differ.py:448  os.replace(tmp, D / out)          <- the write
REDIRECT.findall('    os.replace(tmp, D / out)') = []
PYWRITE.findall('    with tmp.open("wb") as f, ...') = []
txt_writes('checks/differ.py') = [(1379, '', 'not a .txt path')]   <- ONE hit, a docstring
```

The resolver follows REDIRECTS and `open(...)`/`write_text(...)`. `capture()` stages and renames, so
**no write line carries a `.txt` literal and the resolver sees nothing.** Consequences, both measured:

* **Recall 7 of 249.** Pointed at the EXCUSED set as a control (`probe6.py`) the same machinery
  attributes 7 files to 1 generator (`.agents/slop/diffpy/oracle-run.sh`); **237 of the 242 misses
  are under `runs/graphcmp/D/`**, which differ.py demonstrably writes. The machinery is ALIVE, not the
  dead lane -- 717 resolved write paths, 166 files with hits, 0 refusals.
* **`--gate checks/differ.py` returns rc 0, "none of checks/differ.py names a `.txt` write target"**,
  for the generator that writes every single exempted artifact. A gate that cannot go red on its own
  subject. **Latent, not active**: nothing in `checks/` or `gates/` invokes `txt-owners.py --gate`.

So the honest reading of `0 generators own 0 credits over 0 distinct files` is **not** "nothing owns
these 183 files". It is **"the resolver does not model the writer that owns 244 others"**.

## 6. WHAT CHANGED

`checks/txt-owners.py` only. Three changes, none of them touching a population, a threshold or an exit.

1. `hard_set()`: `excused_names()` hoisted out of the per-item filter. **129.62 s -> 1.46-1.56 s**
   (three runs, 04:45:01Z). Behaviour-identical: the set is a pure function of a tree that does not
   move under the run, and `no-txt.py:290` already computes it exactly once for the same verdict.
2. `callers()`: one pass over the population instead of one per generator, so the latent
   O(generators x files) read storm cannot fire when the census acquires an attribution. This CHANGED
   ITS SIGNATURE (`callers(gen) -> int` becomes `callers(gens) -> dict`).
3. The two counts that were bare now carry their denominator -- `resolved` beside `0 generators`, and
   `seen` beside `none of ... names a .txt write target` -- and the claim `named by NO write path in the
   tree` became `... THIS CHECK CAN FOLLOW`, which is what is true.

**Deliberately NOT done:** teaching the resolver `os.replace`. It would turn `--gate differ.py` RED on
a write that is legitimately EXEMPTED, trading a false pass for a false alarm. That is a redesign of
the resolver's write-path model and needs its own plant; it is filed below, not smuggled in here.

## 7. FOUND, NOT DONE

* **`code_files()` reads the ARMED INDEX.** `gates/indexread-gate.py` already lists
  `checks/txt-owners.py: ls-files` as a pinned **base** offender. Live: index 7777 vs HEAD tree 7811,
  **21 CODE files invisible** to this census (`gates/untested-gate.py`, `gates/todo-census.py`,
  `gates/e2estage8-*`, `.agents/slop/exledger/*`). **MEASURED LATENT**: run both ways (`probe5.py`),
  attributed = **0 armed, 0 disarmed** -- identical, so it costs coverage, not correctness, today.
  `gates/ledger-denominator-gate.py` is the existing shape for asking this properly.
* **`oracles/rows-bd.txt` moved 183->184->183 across this session** from other units. The `.txt`
  baseline is not a constant; every citation of it needs a timestamp and a command.
* `gates/txt-carveout-gate.py` **PASS 0 stale**, and it confirms the caller's `244 / 244`: differ's
  carve-out is 244 base names on disk plus 244 `.tmp.` staging names, all absent.