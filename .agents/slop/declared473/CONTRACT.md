# CONTRACT — the `DECLARED-NAME` claim, stated

## The sentence (AGENTS.md voice, ready to paste)

**Every `.txt` basename under a `runs/graphcmp/D/` — the live tree or a committed mirror
under `.agents/slop/{figurefix/plant/D-live,rerun/D-before,figurefix/plant/scratch/runs/graphcmp/D,differverdict}/`
— is DECLARED once by `checks/differ.py:declared()` (`:260`, over `LITERALS`+`REPORTS` at
`:251-257`, derived from `corpus()`/`CONTROLS`/`PLANTS`/`STAB`), the nameset that
`checks/no-txt.py`'s `.txt` carve-out and `differ.py`'s `artefacts_ok()` both ask by import,
and renaming `D0-run-summary.txt` in a mirror breaks the copy-then-read driver
`.agents/slop/figurefix/plant/plant.py:54,58` (`copytree(D-live)` then
`read_text("D0-run-summary.txt")`) and every reader that reopens `$D/D0-run-summary.txt`
(`checks/corpus-figure.py:170`, `.agents/slop/devrecord/xcheck.py:46`), while renaming the
other 472 mirror names breaks no reader at all — they are owned by the nameset, not by an
opener.**

## What is measured, and what is only claimed

- **Declared by:** `checks/differ.py:declared()`, one nameset of **139** names. Consumed by
  import in `checks/no-txt.py` (the `.txt` carve-out) and `differ.py:artefacts_ok()`.
- **The 473:** `plan.py:89` selects them by `os.path.basename(t) in declared()`. They are
  **473 files carrying those 139 names** across three full mirrors and six `differverdict`
  snapshots.
- **What breaks on rename:** exactly **one** name per copy that a copy-then-read driver
  consumes — `D0-run-summary.txt` — because `plant.py:58` and `corpus-figure.py:170` read it
  **by name**. `plant.py:54` `copytree`s the other 138 D-live files but never reads them by
  name. `rerun/D-before` and every `differverdict/*` mirror are opened by **no** committed
  code (`git grep D-before -- '*.py'` returns only two prose strings; `git grep D-live` one
  real opener).

## The weak step this names

The nameset is a real generator declaration. Applying it to **copies** by **basename** is a
second step that the generator never made: `cmd_run` writes the live `runs/graphcmp/D`, and
nothing in `checks/differ.py` knows about `.agents/slop/**/D*/`. For 472 of the 473 the
refusal is *the nameset by basename*, not *a reader that opens the file*.
