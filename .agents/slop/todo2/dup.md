# TODO.md duplication + stable-id index

## Duplicate TASK items

| quantity | value | denominator |
|---|---|---|
| task items | 1317 | file |
| distinct task texts (whitespace+case-normalised) | 1316 | 1317 items |
| duplicated task texts | 1 | 1316 distinct |
| duplicated task instances | 2 | 1317 items |
| texts with CONFLICTING states ([ ] and [x]) | 0 | 1 duplicated |

### All duplicated task texts

| xN | states | line(s) | text |
|---|---|---|---|
| 2 | `x` | 8501,8633 | **NOT COMMITTED**, per brief. |

## Stable-id index

- ids generated: 1317; distinct: 1317; collisions: **0**.
- id = `sha1(section-slug + NUL + normalised text + NUL + occurrence)[:10]`, so it is stable across LINE MOVES and unique within a section.
- written to `.agents/slop/todo2/tasks.idx.tsv` (1317 rows).

## External `file:line` citations INTO TODO.md (they pin line numbers)

Found **345** citation lines in tracked files outside TODO.md itself:

```
./checks/differ.py:911:    and by a ticked `- [x] Report.` box at `.agents/TODO.md:12108`). A pointer to a document
./.agents/slop/txt398/REPORT.md:99:`norm/fixtures.txt`"), `NORM.md:212`, `.agents/TODO.md:12051`. `.agents/slop/norm/` holds
./.agents/slop/stale71/REPORT.md:134:  `.agents/TODO.md:385`), and says **199 lines**; it is **237**. Six committed files still cite the
./.agents/slop/shadowtrees/REPORT.md:125:`.agents/TODO.md:3311` already records the debt (*"and `.agents/slop/xd1/wt/` the moment that
./.agents/slop/shadowtrees/REPORT.md:309:*Then* remove the `wt-sync.sh` line from `.agents/TOOLS.md:437` and tick `.agents/TODO.md:3311`.
./.agents/slop/sloptxt/readers.json:3730:   ".agents/TODO.md:3769",
./.agents/slop/sloptxt/readers.json:3731:   ".agents/TODO.md:4618",
./.agents/slop/sloptxt/readers.json:3732:   ".agents/TODO.md:4635",
./.agents/slop/sloptxt/readers.json:3742:   ".agents/TODO.md:7565",
./.agents/slop/sloptxt/readers.json:3829:   ".agents/TODO.md:7565",
./.agents/slop/sloptxt/readers.json:3886:   ".agents/TODO.md:12805",
./.agents/slop/sloptxt/readers.json:3887:   ".agents/TODO.md:12807",
./.agents/slop/sloptxt/readers.json:3888:   ".agents/TODO.md:13277",
./.agents/slop/sloptxt/readers.json:3889:   ".agents/TODO.md:13300",
./.agents/slop/sloptxt/readers.json:3890:   ".agents/TODO.md:7564",
./.agents/slop/sloptxt/readers.json:4084:   ".agents/TODO.md:8104",
./.agents/slop/sloptxt/readers.json:4085:   ".agents/TODO.md:8107",
./.agents/slop/sloptxt/readers.json:4573:   ".agents/TODO.md:7167",
./.agents/slop/sloptxt/readers.json:4633:   ".agents/TODO.md:7565",
./.agents/slop/sloptxt/readers.json:4720:   ".agents/TODO.md:7565",
./.agents/slop/sloptxt/readers.json:4921:   ".agents/TODO.md:7565",
./.agents/slop/sloptxt/readers.json:5008:   ".agents/TODO.md:7565",
./.agents/slop/sloptxt/readers.json:5065:   ".agents/TODO.md:12805",
./.agents/slop/sloptxt/readers.json:5066:   ".agents/TODO.md:12807",
./.agents/slop/sloptxt/readers.json:5067:   ".agents/TODO.md:13277",
./.agents/slop/sloptxt/readers.json:5068:   ".agents/TODO.md:13300",
./.agents/slop/sloptxt/readers.json:5069:   ".agents/TODO.md:7564",
./.agents/slop/sloptxt/readers.json:5263:   ".agents/TODO.md:8104",
./.agents/slop/sloptxt/readers.json:5264:   ".agents/TODO.md:8107",
./.agents/slop/sloptxt/readers.json:5822:   ".agents/TODO.md:7167",
./.agents/slop/sloptxt/readers.json:5882:   ".agents/TODO.md:7565",
./.agents/slop/sloptxt/readers.json:5969:   ".agents/TODO.md:12805",
./.agents/slop/sloptxt/readers.json:5970:   ".agents/TODO.md:12807",
./.agents/slop/sloptxt/readers.json:5971:   ".agents/TODO.md:13277",
./.agents/slop/sloptxt/readers.json:5972:   ".agents/TODO.md:13300",
./.agents/slop/sloptxt/readers.json:5973:   ".agents/TODO.md:7564",
./.agents/slop/sloptxt/readers.json:6167:   ".agents/TODO.md:8104",
./.agents/slop/sloptxt/readers.json:6168:   ".agents/TODO.md:8107",
./.agents/slop/sloptxt/readers.json:6656:   ".agents/TODO.md:7167",
./.agents/slop/sloptxt/readers.json:6716:   ".agents/TODO.md:7565",
... and 305 more
```
