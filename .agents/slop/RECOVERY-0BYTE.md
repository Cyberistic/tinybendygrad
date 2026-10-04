RECOVERY LOG -- the four 0-byte files, and how one of them was MY fault

THE STATE I FOUND. Four files were 0 bytes in the working copy while HEAD had every
byte: `tinybendygrad/helpers.bend` (125,668), `runtime/support/compiler_mesa.bend`
(39,514), `.agents/slop/graphcmp.py` (170,623) and `.agents/slop/rf2root/helpers.bend`
(35). All four were UNCOMMITTED, so nothing was lost, and jj had the 0-byte state captured
in `@` -- which is what made the restore reversible and therefore worth doing rather than
waiting on.

WHY IT MATTERED MORE THAN IT LOOKS. `helpers.bend` is imported by nearly everything, and an
EMPTY FILE TYPECHECKS. `substrate-check.sh` MEASURED that `--check-only` answers
`ALL PROOFS CHECK` for an empty file and for one holding only a comment -- and I watched it
happen in the command that diagnosed this: `bend tinybendygrad/helpers.bend --check-only`
printed `ALL PROOFS CHECK` on a 0-byte file. So the tree was not merely broken, it was
broken in the one way that makes every unit that checks the substrate report it warm. That
is the fourth truncation of that file, and the script written to catch it records the first
three, each by a unit that then saw green and reported it fine.

WHAT I DID, AND MY OWN ERROR IN IT. I ran:

    jj restore tinybendygrad/helpers.bend tinybendygrad/runtime/support/compiler_mesa.bend \
              .agents/slop/graphcmp.py .agents/slop/rf2root/helpers.bend

which reported "modified 3 files" -- so `rf2root/helpers.bend` was NOT restored, and I
assumed it was a plain 35-byte file. It is not. **It is a SYMLINK to
`../../../tinybendygrad/helpers.bend`**, and my next command was

    git show HEAD:.agents/slop/rf2root/helpers.bend > .agents/slop/rf2root/helpers.bend

**which wrote THROUGH the symlink and replaced `tinybendygrad/helpers.bend` with the stub's
own text.** The shell reported no error, because writing through a symlink is not an error;
the file was simply replaced. I caught it because `helpers.bend --check-only` then said
`SOME PROOFS FAIL` with `observed : '.'` on line 1.

REPAIRED: `git show master:tinybendygrad/helpers.bend > /tmp/...` and then `cp` to the
target, so the write lands on the real path and not through a link. `helpers.bend` is
125,668 bytes, has its 5 `i64_dec` defs, is byte-identical to master, and is
`ALL PROOFS CHECK`. The symlink is intact.

THE LESSON, AND IT IS THE THIRD TIME THIS SESSION: **NEVER REDIRECT INTO A PATH WITHOUT
`ls -la` FIRST.** A symlink in a tree of generated slop is not exotic -- this one has been
there since October 2nd -- and a redirect through it is silent, total, and destroys the file
it points at. `cp` through a symlink behaves the same way. The habit to build is: when a file
is unexpected, look at what it IS before writing to it, and write to a temporary path before
moving anything into place.

ALSO WORTH KEEPING: `differ.py run` COMPLETED AND REPORTED exit 0 WITH EVERY COUNT ZERO
while `graphcmp.py` was empty. 16 graphs, 0 comparable, 0 of 5 controls, 0 of 7 plants,
`stable-failed=5 of 5`. That is the same lying-gate class as the five harnesses fixed
earlier today, now in the primary driver, and it is the reason a gate that "passes" has to
be read for its COUNTS and not its exit code. `run` GENERATES and `repro` GATES, per its own
`--help`, so the health check lives in `repro` -- but a reader who runs `run` alone sees
exit 0.
