# cidsweep — CID guard sweep.  DONE.  Nothing committed.

Report:  `../CIDSWEEP.md`
Gate:    `sh .agents/slop/cidsweep/gate.sh`   -> exits 1 TODAY, on purpose (CIDS-1 unfixed)

| file | what it is |
|---|---|
| `gate.sh` | the per-seam BUILD gate. 12 builds, `cc -fsyntax-only` on each emit |
| `census2.py` | the CORRECT empty-body detector (CIDS-1: check the RETURN TYPE) |
| `cidcensus.py` | per-seam constructor-id census + `#ifdef` guard coverage |
| `probe-dtype-one.bend` / `probe-dtype-none.bend` | one dtype.c seam / no seam |
| `probe-sz-none.bend` | reaches nothing (the isdir/readdir pair is `szlane`'s, reused not copied) |
| `probe-libclang-none.bend` | reaches no libclang seam |
| `probe-libclang-ffi-one.bend` | **reaches ONE ffi effect -> CIDS-1, cc rc 1, 9 undeclared ids** |
| `probe-libclang-tramp-one.bend` | one tramp effect -> WARM, and ffi.c is NOT pasted |
| `libclang-ffi-CIDS-1.patch` | the fix, NOT APPLIED (clangshim is another unit's tree) |

`census.py` (v1) is DELETED, not kept: its 478 "empty bodies" were 460 `case X: None{}`
match arms.  `census2.py` supersedes it and the report says why.
