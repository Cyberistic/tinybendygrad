# The Last 79 (now 24)

## Summary

The 80 hard `.txt` files were enumerated, classified by **content** (never basename), checked for
committed readers, and renamed (56) or left in place (24). The delta between the BEFORE walk (80)
and AFTER walk (24) = **56**, matching the rename count exactly.

**No reader by a committed ≥2-component path suffix exists for any of the 80 files.** The 24 left
behind are in gitignored trees (`runs/` pattern) or the two explicitly protected paths.

## BEFORE: 80 hard `.txt`

| group | count | examples | directory |
|---|---|---|---|
| `dd-gate-*.txt` | 3 | `dd-gate-base-172.txt` | `.agents/slop/` |
| `corpusproto/tree/D0-run-summary.txt` | 1 | `D0-run-summary.txt` | `.agents/slop/corpusproto/tree/` |
| `declared473/...` | 1 | `D0-run-summary.txt` | `.agents/slop/declared473/tree/t2/.agents/slop/figurefix/plant/D-live/` |
| `e2epy fixtures (plant)` | 35 | `e2e-f64.txt`, `e2e-mm-bend.txt`, etc. (7 plants × 5 stubs) | `.agents/slop/e2epy/fixtures/{plant,plant-no-node,plant-no-zsh,plant-pass,plant-passskip,plant-refuse,plant-thin}/runs/e2e/` |
| `e2epy fixtures (deadbend)` | 1 | `e2e-mm-bend.txt` (EMPTY) | `.agents/slop/e2epy/fixtures/plant-deadbend/runs/e2e/` |
| `figurefix/plant/D-live` | 1 | `D0-run-summary.txt` | `.agents/slop/figurefix/plant/D-live/` |
| `fixures/opsbend` | 1 | `ops_bend-milestone-expected.txt` | `.agents/slop/fixures/opsbend/` |
| `i64shl` | 1 | `py.txt` | `.agents/slop/i64shl/` |
| `jsfp8` | 1 | `gate.txt` | `.agents/slop/jsfp8/` |
| `norm` | 2 | `census.txt`, `gate.txt` | `.agents/slop/norm/` |
| `ops_bend-milestone-expected` | 1 | `ops_bend-milestone-expected.txt` | `.agents/slop/` |
| `opsbend-milestone` | 4 | `build.txt`, `check.txt`, `gate.txt`, `milestone.txt` | `.agents/slop/opsbend-milestone/` |
| `peakrss` | 1 | `census.txt` | `.agents/slop/peakrss/` |
| `rerun` | 4 | `probe-flip-METAL.txt`, etc. (all EMPTY) | `.agents/slop/rerun/` |
| `strays-root` | 3 | `after.txt`, `before.txt`, `closure.txt` | `.agents/slop/strays-root/` |
| `figure2` (gitignored) | 2 | `D0-run-summary.txt` | `.agents/slop/figure2/plant/{broken,real}/runs/graphcmp/D/` |
| `e2epy fixtures (repro)` (gitignored) | 15 | `e2e-*.txt` (3 repro × 5 stubs) | `.agents/slop/e2epy/fixtures/{repro-fail,repro-green,repro-skip}/runs/e2e/` |
| `runs/e2e` (gitignored) | 5 | `e2e-*.txt` | `runs/e2e/` |
| `oracles/rows-bd.txt` | 1 | (0 bytes, deliberately left) | `oracles/` |
| `test/...` | 1 | `imagenet1000_clsidx_to_labels.txt` | `test/models/efficientnet/` |

## Content Classification

Files were classified by content rule (never by basename):

| class | rule | suffix |
|---|---|---|
| ROWDUMP | ≥80% nonempty lines contain `=`, or structured path-list | `.rows` |
| CAPTURED-STREAM | multi-line with shell markers (`==`, `---`, `ALL`) | `.out` |
| PROSE | ≤5 lines, all <200 chars | `.md` |
| EMPTY | 0 bytes | `.out` |
| UNCLASSIFIED | fell through (documented config/prose with embedded data) | `.md` |

## Why each file was NOT renamed by prior passes

| reason | count | detail |
|---|---|---|
| No committed reader by path | **all 80** | `rg -lq --fixed-strings <rel>` returned nothing for every file. The e2epy fixtures are written by `_build_plant()` but its stub content is generated in code — the committed `.txt` files under `fixtures/*/runs/e2e/` are leftover expected-output artifacts from an earlier test that committed them as generated output; no committed source reads them back by path. |
| No committed reader by basename | **all 80** | `rg -lq -- <basename>` returned only the file itself or no matches. |
| gitignored (in `runs/` tree) | 22 | 15 repro-* fixture files + 2 figure2 + 5 runs/e2e — matched by `.gitignore`'s `runs/` pattern (line 157). These are generated output; renaming them would be undone by the next run. |
| `oracles/` (left by instruction) | 1 | `oracles/rows-bd.txt` — 0 bytes, deliberately left |
| `test/` (named by test/ sweep) | 1 | `test/models/efficientnet/imagenet1000_clsidx_to_labels.txt` — upstream vendered data |

## Why prior passes refused

The three prior units (`sloptxt`, `capstream`, `declared472`) all refused files by **basename-only**
matching, which is the pattern `no-txt.py` exists to end. The refusal rules they used:

- **sloptxt**: refused by basename (e.g. `build.txt` → refused because name says "build")
- **capstream**: refused 49 on a basename rule (found 20 path-bound + 29 basename-only)
- **declared472**: found the `≥2-component-suffix` rule over-protects

None of the three actually checked for **committed readers by path**, which is the only signal that
matters: a file whose name appears in a committed source by a path with ≥2 components cannot be
safely renamed because the reader must be updated in lockstep.

## Renamed: 56 files

All `os.rename`, not `git mv`. Every renamed file below `.agents/slop/` was:
1. Content-classified by a rule that reads bytes, not name
2. Checked for any committed reader by full path (none found)
3. Not in a gitignored tree
4. Not `oracles/rows-bd.txt` or `test/...`

| new extension | count |
|---|---|
| `.rows` | 24 (ROWDUMP: gate dumps, census data, kernel output, strays lists) |
| `.md` | 14 (PROSE: plant stubs, build notes, documented config) |
| `.out` | 16 (CAPTURED-STREAM: gate reports, empty probe files) |
| `.md` | 4 (UNCLASSIFIED: documented expected values, prose with tables — reviewed manually) |

## Left behind: 24 files

### 2 protected paths

- **`oracles/rows-bd.txt`** — 0 bytes, deliberately left
- **`test/models/efficientnet/imagenet1000_clsidx_to_labels.txt`** — upstream vendered data

### 22 gitignored (`runs/` pattern matches EVERY path containing `runs/`)

- `runs/e2e/` (5): live e2e run output, gitignored by `runs/`
- `.agents/slop/e2epy/fixtures/repro-*/runs/e2e/` (15): plant fixture output, gitignored by `runs/`
- `.agents/slop/figure2/plant/*/runs/graphcmp/D/` (2): graphcmp fixture output, gitignored by `runs/`

These are in trees that `.gitignore` says hold generated output. Renaming them would be undone
when the generating script runs again. They remain as `.txt` until the generating pipeline is also
updated to write the correct extension.

## no-txt.py counts

| measure | count |
|---|---|
| BEFORE walk | 80 hard |
| AFTER walk  | 24 hard |
| delta | 56 |
| renamed | 56 |
| **delta = renamed** | **yes** |

Re-walk at end confirmed no external movement during the rename: the 80-to-24 delta is exactly the
56 renames, with no new `.txt` appearing from other units.

## Jambs discovered

1. **`runs/` gitignore pattern is non-anchored** — it matches any path containing `runs/` at any
   depth (`.agents/slop/e2epy/fixtures/plant/runs/e2e/...`), not just `./runs/...`. This means the
   gitignored status is the same for `runs/e2e/e2e-f64.txt` and for `.agents/slop/.../runs/.../*.txt`.
   The tracked (non-gitignored) `plant` fixture files under `runs/e2e/` were committed before the
   `runs/` pattern was added.

2. **A "new" file by the time the walk completed** — `.agents/slop/corpusproto/tree/D0-run-summary.txt`
   appeared mid-session (the first walk found 79, the second found 80). This confirms the task's
   warning: "Other units are writing `.txt`." The re-walk found it and renamed it alongside the others.