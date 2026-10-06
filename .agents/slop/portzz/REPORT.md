# Five not-source `.bend` files in the shipped port — classified, four relocated, one held

Unit `portzz`. Measured 2026-10-06. Interpreter `.venv/bin/python` throughout; **`bend` never run**.
No commit, no `git add`. The only files written are under `.agents/slop/portzz/`.

**Population by DISCOVERY** (`classify.py`): importers = every `.bend` under `tinybendygrad/`
scanned for `import … .bend`; citers = `git grep -l -F <basename> HEAD`; byte-copies =
`git rev-parse HEAD:<path>` matched against `git ls-files -s`. The five paths are the task's
population, named once in `classify.py`; every other cell is measured. Capture: `classify.rows`.

## 1. Classification, by CONTENT, with `file:line`

| file (`tinybendygrad/…`) | verdict | evidence |
|---|---|---|
| `runtime/zzdiag.bend` | **PROBE** | `:1` `import Base`; `:3` `def row(nm,v) -> IO(Unit): IO.print(…)`; `:18` `def main() -> IO(Unit): go()`. Prints `n_split=`/`fld=` and exits. 18 lines, headerless. |
| `runtime/zzread.bend` | **PROBE** | `:1` `import Base`; `:3` row printer; `:4` `dd(s)` folds `U32.read`; `:14` `main`. Prints `dec=` and exits. 14 lines, headerless. |
| `runtime/zzsplit.bend` | **PROBE** | `:1` `import Base`; `:3-4` row printers; `:8/:13` `parts()`/`chars()`; `:25` `main`. Prints `p_split_nl_*`/`p_char*`. 25 lines, headerless. |
| `runtime/support/zz_objc_mutant.bend` | **MUTANT** | `:1` header names a *different* file (`objc.bend`). 1129 lines, **byte-identical to `runtime/support/objc.bend` except one token at `:196`** — `c <> r` → `c <> t` inside `mangle.rtrim.go`. The comment at `:190-194` says `c <> r` is the *correct* spelling, so the mutant plants the bug the gate row `mangle_1` catches. |
| `runtime/support/am/ip_scratch_sweep.bend` | **MUTANT** | `:1` header names `support/am/ip.bend`. 2791 lines, **byte-identical to `runtime/support/am/ip.bend` except one token at `:1618`** — the `amp_reg_137` register name `reg{ip}VM_CONTEXT{vmid}_CNTL` → `reg{ip}VM_L2_CONTEXT1_IDENTITY_APERTURE_LOW_ADDR`. |

The three `zz*` probes end in `.bend` (not `.mut`); only `zz_objc_mutant` names itself, and the
other mutant, `ip_scratch_sweep`, does **not** — its name says "scratch", its content is a mutant of
`ip.bend`. **The name is not the class; the diff is.**

## 2. Structural facts (measured; `classify.rows`)

| file | tracked | in HEAD | read by any `.bend`? | byte-equal to another file? | non-slop citers |
|---|---|---|---|---|---|
| `zzdiag.bend` | yes | yes | **no** | yes — its own debris mirror | `checks/census.json` |
| `zzread.bend` | yes | yes | **no** | yes — its own debris mirror | `checks/census.json`, **`checks/disarm.sh:27`** |
| `zzsplit.bend` | yes | yes | **no** | yes — its own debris mirror | none |
| `zz_objc_mutant.bend` | yes | yes | **no** | yes — its own debris mirror | none |
| `ip_scratch_sweep.bend` | yes | yes | **no** | yes — its own debris mirror | none |

- **Imported by no `.bend`** — all five. (`grep -E 'import .*(zzdiag|zzread|zzsplit|zz_objc_mutant|ip_scratch_sweep)'` over `tinybendygrad/` = 0.)
- **Every one has exactly 2 copies in the index**: itself and a copy under the committed debris
  mirror `.agents/slop/substratepop/tree/tinybendygrad/…` (`substratepop/REPORT.md` calls that tree
  "12 MB copy, debris"). The mirror is a copy *of* these files, so it does **not** make them
  "provably redundant" — the only independent copy is debris.
- `checks/census.json` names `zzdiag.bend`/`zzread.bend` as `port_where` for a `renderer/nir.bend`
  TODO (`"port": "P-ELSEWHERE"`); it is a static dataset, not a runtime consumer.
- **`checks/disarm.sh:27` passes `tinybendygrad/runtime/zzread.bend` to
  `.agents/slop/substrate-check.sh`** (the shim onto `checks/substrate.py`). That is a runtime
  consumer inside `checks/`, which this unit may not edit.

## 3. Decision, per file — counts

| file | outcome | why |
|---|---|---|
| `runtime/zzdiag.bend` | **RELOCATE** | probe, no importer, no runtime consumer → moved to `.agents/slop/portzz/relocated/` |
| `runtime/zzsplit.bend` | **RELOCATE** | probe, no importer, no runtime consumer → moved |
| `runtime/support/zz_objc_mutant.bend` | **RELOCATE** | one-token mutant of `objc.bend`, no importer → moved (mutation evidence preserved under slop) |
| `runtime/support/am/ip_scratch_sweep.bend` | **RELOCATE** | one-token mutant of `ip.bend`, no importer → moved |
| `runtime/zzread.bend` | **REPORT ONLY** | probe by content, but `checks/disarm.sh:27` consumes it at runtime and I may not edit `checks/` |

**Counts: RELOCATE 4 · REPORT ONLY 1 · DELETE 0 · KEEP 0.**

**Nothing was DELETE.** A mutant is not a byte-copy of its base (one token differs); a probe has no
independent copy. The stated DELETE criterion ("bytes in HEAD or a byte-copy") is only satisfied by
the debris mirror, which is not an authority. **`REPORT ONLY` is not `KEEP`: `zzread.bend` is not
source.** What would prove it safe to relocate: re-pointing `checks/disarm.sh:27` at a probe
`disarm.sh` itself creates (it already creates `PROBE-DISARM.bend` at `:19`/`:34`) or retiring that
shell control, **then** moving the file. That edit is one line in a file this unit does not own.

## 4. On-disk action taken + the orchestrator's index list

Already moved (plain `mv`, worktree only, no index touched):

```
tinybendygrad/runtime/zzdiag.bend                        -> .agents/slop/portzz/relocated/runtime/zzdiag.bend
tinybendygrad/runtime/zzsplit.bend                       -> .agents/slop/portzz/relocated/runtime/zzsplit.bend
tinybendygrad/runtime/support/zz_objc_mutant.bend        -> .agents/slop/portzz/relocated/runtime/support/zz_objc_mutant.bend
tinybendygrad/runtime/support/am/ip_scratch_sweep.bend   -> .agents/slop/portzz/relocated/runtime/support/am/ip_scratch_sweep.bend
```

Orchestrator, to stage the move (never `git add` by this unit; prefer a private index):

```
GIT_INDEX_FILE=.git/agent-index git rm --cached \
  tinybendygrad/runtime/zzdiag.bend \
  tinybendygrad/runtime/zzsplit.bend \
  tinybendygrad/runtime/support/zz_objc_mutant.bend \
  tinybendygrad/runtime/support/am/ip_scratch_sweep.bend
GIT_INDEX_FILE=.git/agent-index git add \
  .agents/slop/portzz/relocated/runtime/zzdiag.bend \
  .agents/slop/portzz/relocated/runtime/zzsplit.bend \
  .agents/slop/portzz/relocated/runtime/support/zz_objc_mutant.bend \
  .agents/slop/portzz/relocated/runtime/support/am/ip_scratch_sweep.bend
```

(The real index currently shows the four as worktree-deleted, still tracked: `git status` ` D` ×4.)
`zzread.bend` stays at `tinybendygrad/runtime/zzread.bend` until `checks/disarm.sh:27` moves.

## 5. The numbers that cite the population — before → after

Three numerators cite one population (the `tinybendygrad/` tree); all move together.

| number | rule | before | after (4 moved) | after (all 5) |
|---|---|---:|---:|---:|
| `find tinybendygrad -name '*.bend' \| wc -l` | `.bend` suffix on the port | **138** | **134** | 133 |
| `checks/sweep.py` `port_files()` arm | `os.walk(tinybendygrad)`, **no suffix filter** | **144** | **140** | 139 |
| volume ratio (non-comment lines, port / `tinygrad/**.py` excl `test/`) | port-pop / pin-pop | 94,805 / 235,885 = **40.2%** | 92,968 / 235,885 = **39.4%** | 39.4% |

- `find` and `sweep.py` are measured this session (`.venv/bin/python -c "import sweep; …"`); the
  non-comment rule is the `portpop` method, pin = 235,885 lines.
- The orchestrator's brief says the ratio is **41%**; `.agents/slop/portpop/REPORT.md` §6 already
  found that literal appears **in the task prompt, not in `AGENTS.md`** — the measured value is
  **40.2%**, and it falls to **39.4%** with these four removed. Nothing in `AGENTS.md` needs the
  `41%` moved; the `138` there does.

**Cites of `138`/`144` that must move** (I may not edit these):
`AGENTS.md:71` ("43 of 138 under 50 MB"); `.agents/TOOLS.md:406,413,437,446` ("138 of 138",
`files=138 agree=138`); `.agents/TODO.md:262-266,279,293` (the "DENOMINATOR HAS FOUR VALUES" block);
`checks/sweep.py:579` (docstring prose "all 144 files of the port" — the code walks live, so only the
prose is stale); `checks/census.json` still names `zzdiag.bend`/`zzread.bend`. Whether the `138`
should become `134` or be de-numbered is the owner's call — but leaving `138` cites attached to a
134-file tree is exactly the stale-citation class `AGENTS.md` opens with.

## 6. What `checks/no-strays.py` should have caught, and the structural test

**`checks/no-strays.py` catches 0 of 5** (rc=0, "0 scratch-shaped in source trees"). Its deep walk
*does* descend into source trees, so this is not the root-only bug the file's own docstring records;
the population is the **`RESIDUE_NAME` suffix shape** (`no-strays.py:99`):
`.staged-(mem|blob)-\d+$|\.mut$|~\d*$|\.(bak|orig|rej|swp)$`. All five end in `.bend` and match none.
**A prober that keeps the shipped extension is invisible to a guard that declares its population by
suffix — Doctrine 1 one level down, the fourth instance.** What it *should* catch is content: a
`.bend` nothing imports whose `main()` only `IO.print`s (probe), or a `.bend` whose header names a
different file and whose bytes differ from that file by one token (mutant). The guard's job is to
name non-source, not to name a suffix.

**Would "a `.bend` nothing imports" catch them?** **All five — and 88 real modules too.** Measured
after the move: **93 of 134** `.bend` files are imported by no other `.bend`; the four moved were
among the 97/138 before it. The unimported set includes `runtime/support/objc.bend`,
`runtime/support/am/ip.bend`, `renderer/cstyle.bend`, `renderer/llvmir.bend`, `runtime/ops_metal.bend`
and every `__init__.bend` — real leaves. So the structural rule is a **necessary but not sufficient**
signal: it would flag all five true positives (and `zzprobe2.bend`, `_p6.bend`, `test/_probe/v5.bend`,
`uop/probe-mmcore.bend`, which are also probes) but with 93/134 precision it is unusable alone. The
discriminator is **content**: probe = writes stdout and exits; mutant = header names another file and
differs by one token; source = neither. No suffix rule and no import-absence rule can see that; a
guard that walks `.bend` files and reads their `main()`/diff would.

## 7. Reproduce

```
.venv/bin/python .agents/slop/portzz/classify.py            # -> classify.rows (5 rows + header)
find tinybendygrad -name '*.bend' | wc -l                   # 134 (was 138)
find tinybendygrad -type f | wc -l                          # 140 (was 144) = sweep.port_files()
.venv/bin/python checks/no-strays.py                        # rc=0, "0 scratch-shaped" (0 of 5)
git status --porcelain -- tinybendygrad/runtime/            # ' D' ×4; zzread.bend untouched
```

Artifacts: `classify.py`, `classify.rows`, `REPORT.md`, `relocated/` (the four moved files). No
`.txt` created. `checks/`, `gates/`, `AGENTS.md` untouched; `git add`/commit not run.
