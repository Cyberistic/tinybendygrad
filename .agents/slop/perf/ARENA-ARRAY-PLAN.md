# ARENA-AS-ARRAY: THE EXECUTABLE WORK LIST

Generated from `tinybendygrad/runtime/ops_python.bend` at `d9ad910f4` — every count below is from the file, not from memory.

## Hard constraints found by compiling (REPORT 39.26, 39.25)

- The arena is `Array<Elem>`; `Elem` is a `Data` record, which `Array` accepts.
- It is a `Type`: it CANNOT be passed `+a` ("can be used many times, so its type must be Data") and cannot sit in the `Data` record `Prog`.
- A read is `Array<Elem> & Elem` and must be destructured INSIDE a def: `match Array.get(..)` is refused, and so is binding it to a local and matching that.
- `Array.set` is type-first; `Array.new(T, d, v)` takes DEPTH (`10n` = 1024 slots); records construct positionally.
- `bend` reports ONE error at a time (stops at the first failing def), so expect ~1 cycle per fixed def.

## The arena surface, counted

```
defs naming vs/vc/vi            75
read sites (vat.f/src.f/vat)    29
write sites (vput.go/vput)      9
Prog{ constructions to rewrite  60
Prog patterns to rewrite        30
```

## Order of work (each step must compile before the next)

1. `type Prog is Data:` -> `Prog{st: St, gd: Gd, ms, mk, pc: U32, bad: Bool, dead: Bool, un: List<&2, Uop>}` (drop `vs`, `vc`, `vi`).
2. Delete `Val.gzero/gin/gat/gput/W/Wm/nch/ci/co/ch.at`, `Prog.vat.hit`, `Prog.vat.f`, `Prog.flush.go`, `Prog.vput.flush.go`, `Prog.flush`, `Prog.vs`, `Prog.v0`, `Prog.vc`, `Prog.vi`, `prog_vc_go`, `prog_vi_go`, `Prog.vget`, `Prog.zchunks`.
3. Add `Arena.new() -> Array<Elem>: Array.new(Elem, 10n, Elem.zero())`, `Val.at(a, i) -> Array<Elem> & Elem: Array.get(Elem, a, i)`, `Val.put(a, i, e) -> Array<Elem>: Array.set(Elem, a, i, e)`.
4. `Prog.vput(+p, +a: Array<Elem>, +slot, +e) -> Prog & Array<Elem>` — one `Array.set`, no flush, no chunk.
5. `Prog.vat(+p, +a, +i) -> Array<Elem> & Elem` — `Array.get` and hand the record back.
6. Rewrite the 8-field `Prog{...}` constructions (drop the three arena args).
7. Rewrite the `case Prog{...}` patterns (8 names).
8. Thread `+a` through the 75 defs; each returns `Prog & Array<Elem>`; sequence the 29 read sites as `(p1, v0) = Prog.vat(p, a, s0)` etc.
9. `Prog.of` returns the pair; `run`/`grid`/`tick`/`Prog.reset` thread both; `Prog.tick` reseeds with `Arena.new()` per work item.
10. Verify: `bin/bend <file> --check-only`, `gates/ops_python_exec-gate.py`, `gates/ops_bend_exec-e2e.py`, then `stage3_parity` 3x at 16x16 and 32x32.
