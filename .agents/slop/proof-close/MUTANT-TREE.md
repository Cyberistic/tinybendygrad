THIS DIRECTORY IS NOT A LANE AND IS NOT A WORKTREE. DO NOT READ, EDIT, OR IMPORT FROM IT.
==========================================================================================

Every `.bend` file under

    MUTANT/tinybendygrad/**      (143 files)
    MUTANT2/tinybendygrad/**     (144 files)

is a COPY of a real port file, placed at the SAME relative path as the real one.
They exist so a mutation can be run against a scratch tree that the live port
cannot reach. They are NOT part of the port, they are NOT lanes, and they are
NOT a second opinion on anything.

THE HAZARD, MEASURED
--------------------
`grep -rn 'def foo' .` prints

    .agents/slop/proof-close/MUTANT/tinybendygrad/helpers.bend:1055:...

for a file that is NOT `tinybendygrad/helpers.bend`. Two files, one relative path,
one definition, no signal in the text. A unit that greps for a definition can land
in the wrong copy and cannot tell. That already happened once: a unit reported
`tinybendygrad/helpers.bend` as a RENAME to
`.agents/slop/nested/baseline-probe.err`, and the coordinator's note on it is the
reason this file exists -- AN EMPTIED FILE AND A MOVED FILE ARE THE SAME OBSERVATION
AT THE PORCELAIN LEVEL, so "it is not at the old path" is not evidence of anything.

WHY THE NAME IS THE WARNING
---------------------------
The PATH is the only part of a grep hit a reader cannot skip: every line is
`path:line:text`. A `README` does not appear in grep output at all, so a unit
running `grep -rn 'def foo' .agents/slop/` never meets it -- which is exactly why a
README is not the mechanism here. The directory name `MUTANT` appears in 100% of
hits. `mut` was three characters and read as "mutated", i.e. skimmable.

WHY NOT A HEADER LINE IN EVERY FILE
-----------------------------------
`mutate.py:10 fresh()` does `shutil.rmtree(MUT.parent)` and then `copytree(LIVE, MUT)`.
Anything written inside `MUTANT/` -- a header, a marker, this file if it were moved
down one level -- is destroyed on the next run and the sandbox is rebuilt verbatim
from the live tree. A header would need 287 edits and would last until the next
experiment. This directory is ONE level up, which is the only level that survives.

FULL LEDGER: .agents/slop/MUT-LEDGER.md