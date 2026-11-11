schedule/rangeify.bend: THE GATE DRIVER WAS LEFT OUT OF THE MOVE COMMIT

The previous commit (4622622c0) carried seven of the eight new gate drivers
and MISSED `gates/rangeify-gate.bend`, and the omission COST THE ROWS: the
port file `schedule/rangeify.bend` emits NO rows (it has no `main`) and the
driver is where the 159 rows live -- and without it the module lost 159
measurements.

MEASURED: the union of the port and the driver IS 159 rows, and without the
driver it is ZERO.

AND THE LESSON IS THE TREE's OWN: `git commit --only` is bounded by the
pathspec, the pathspec was right, and the index did not carry the file -- and
`git show --stat` is the check, and it said 15 files.

AND `schedule/rangify.bend` AND `schedule/rangify.bend` ARE TWO DIFFERENT
FILES (the stems differ by one letter), and the collision check did not catch
it -- and the catch WAS the compile gate, which saw both files and said
nothing about the missing one.
