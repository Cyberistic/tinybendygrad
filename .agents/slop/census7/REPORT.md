# census7 — the `from census import PREAMBLE` defect in `checks/coverage.py`

## 1. The seven, by discovery (7 found of 1,900 `.py` files walked; 33,030 files total)

| # | file | lines | bytes | `PREAMBLE` | `classify` | what it is |
|---|------|------:|------:|:----------:|:----------:|------------|
| 1 | `checks/census.py` | 112 | 5,383 | no | no | DENOM census: ops reached py/bend per graph, via `graphcmp` |
| 2 | `.agents/slop/shfinish/census.py` | 84 | 4,102 | no | no | `.sh`-gate census of `.agents/slop` |
| 3 | `.agents/slop/gatecensus/census.py` | 302 | 13,809 | no | no | tree-wide gate census (verdicts, dedup, tripwires) |
| 4 | `.agents/slop/i64mul/census.py` | 97 | 4,854 | no | no | hi==lo fixture census for the libclang null-handle gate |
| 5 | `.agents/slop/want/census.py` | 73 | 3,451 | no | no | `graphcmp.GRAPHS` vs `differ.WANT`, both directions |
| 6 | `.agents/slop/reach/census.py` | 42 | 1,762 | no | no | ops-reached number over every graph |
| 7 | `.agents/slop/portexec/census.py` | 84 | 3,716 | **YES** (:22) | **YES** (:25) | **THE INTENDED ONE** — the 227-row text/execution classifier |

Exactly 1 of the 7 defines `PREAMBLE`; exactly 1 of the 7 defines `classify`. They are the same file.

## 2. The intended owner, from evidence (not guesswork)

`checks/coverage.py:40-41` imports `PREAMBLE, classify` from `census` and `port_rows` from `exec_harness`. The intended directory is `.agents/slop/portexec/`:

1. **It is the only `census.py` of the 7 defining `PREAMBLE`** (line 22) — the exact name imported.
2. **It is the only one defining `classify`** (line 25) — the other name imported.
3. **`exec_harness.py` exists nowhere else in the tree** (find: 1 result). Both imports must resolve from the same directory; only portexec/ holds both.
4. **The `sys.path.insert` target is named `portexec`** — matches the directory name.
5. **The tree's own canonical path**: `checks/run-port-mm.sh:47` sets `PORTEXEC="$ROOT/.agents/slop/portexec"`; `checks/sweep.py:265` knows portexec lives at `.agents/slop/portexec/`.
6. **The file's own docstring** (`portexec/census.py:2`) names it `portexec/census.py`, and `coverage.py:13-15` says the row set and fragment/kernel split come from `portexec/census.py`'s own `classify`, "imported rather than re-implemented".

No other candidate is importable by this script at all: the other five are standalone scripts run by path, and nothing in the tree imports any of the 7 except `coverage.py` and its twin.

## 3. The defect

`checks/coverage.py:39` inserted `HERE.parent / "portexec"` = `<root>/portexec` — **a directory that does not exist** (measured: `ls` → No such file or directory). The insert was a silent no-op, so `from census import PREAMBLE` fell through to `checks/census.py` (the script's own directory is `sys.path[0]`), which has no `PREAMBLE` → `ImportError`, exit 1.

It failed loudly **only by luck**: `checks/census.py` happens to lack `PREAMBLE`. Any `census.py` defining `PREAMBLE` earlier on the path would have been silently imported — a gate that reads as a pass.

## 4. The fix (one line, `checks/coverage.py:39`)

```diff
-sys.path.insert(0, str(HERE.parent / "portexec"))
+sys.path.insert(0, str(HERE.parent / ".agents" / "slop" / "portexec"))
```

The intended directory is now declared explicitly and sits **first** on `sys.path` — ahead of `checks/` (script dir), ahead of `PYTHONPATH`, ahead of `site-packages`. Both `census` and `exec_harness` resolve from it. A second `census.py` appearing tomorrow in `checks/`, `.agents/slop/`, or site-packages cannot shadow it. `git diff --stat`: 1 file, 1 insertion, 1 deletion.

## 5. Planted and shown: the failure mode is now impossible

Decoy planted at `.agents/slop/census7/decoy/census.py` defining `PREAMBLE = "DECOY-PREAMBLE\n"` and a stub `classify`, plus a decoy `exec_harness.py`, both reachable via `PYTHONPATH` — i.e. earlier on the path than any site-packages hit.

**Control — original import logic** (copy with the old line, placed so `HERE.parent/"portexec"` is absent, decoys on `PYTHONPATH`):

```
PREAMBLE resolves to: 'DECOY-PREAMBLE\n'
classify is the decoy's: ('fragment', None)
port_rows is the decoy's: {}
```

Silent, no error, no warning — the wrong file imported, exactly the "reads as a pass" hazard.

**Fixed — same decoys, same `PYTHONPATH`:**

```
PREAMBLE resolves to: 'typedef float float4 __attribute__((aligned(16),ext_vector_type'
classify("kern2 CLANG", "void k() { float4 x; }") -> ('kernel', 'CLANG')
port_rows is exec_harness
```

The decoy is defeated; the intended file wins. Reproduce with:

```
PYTHONPATH=.agents/slop/census7/decoy .venv/bin/python -c "
import importlib.util
spec = importlib.util.spec_from_file_location('cov', 'checks/coverage.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(repr(m.PREAMBLE[:60]))"
```

## 6. Exit codes, and what the red was

| run | exit | reason |
|-----|:----:|--------|
| BEFORE, no args | **1** | `ImportError: cannot import name 'PREAMBLE' from 'census' (.../checks/census.py)` — **RED FOR THIS REASON** (the import) |
| AFTER, no args | **1** | `IndexError: list index out of range` at `sys.argv[1]` — **RED FOR A DIFFERENT REASON**: no `port-rows.txt` input exists in the tree (find: 0 results), so the script cannot run end-to-end without a synthetic input. The import defect itself is gone. |
| AFTER, with synthetic `port-rows.rows` | **0** | runs end-to-end, decoy armed on `PYTHONPATH` |

The BEFORE red was the import, measured directly (`TRUE_EXIT=1` with the traceback on the unfixed tree). The AFTER red without args is a missing-input artifact of this tree, not the import.

## 7. Out of scope, reported

`.agents/slop/e2e_port/coverage.py` is **byte-identical** to `checks/coverage.py` (diff: empty) and carries the same defective line 39. It was not touched — the assignment named `checks/coverage.py`, and this twin lives in a swept tree. It needs the same one-line fix.
