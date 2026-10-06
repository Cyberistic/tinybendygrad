# PROBES — probes, plants, and the mechanism that makes them announce themselves

Written 2026-10-05. Rule prefix **`PROBE-`**. **One** instrument does the classification —
the `PROVENANCE` block inside `.agents/slop/substrate-check.sh` — plus two repeatable
demonstration artifacts, `.agents/slop/probes/{demo.sh,disarm.sh}`. (A standalone
`classify.sh` was written first and then deleted: it reimplemented the same predicate, and
two copies of a predicate is one more thing that can be true.) **Nothing committed.**

Companion reading: `MUT-LEDGER.md` classifies *shadow* trees; this classifies the
**live** `tinybendygrad/`, where the rule failed three times today.

## 1. The failure, stated as a number

`find tinybendygrad -name '*.bend'` = **138**. The port is **137**. The entire
discrepancy is `probe_f32lit.bend`, **still on disk, owned by a live unit**.

Two earlier units dropped probes in and were cleaned up before anyone read the number,
so `substrate-check.sh` printed `bend=137` in both worlds. **A denominator that moves
by one still looks like a denominator.** The router counted whatever it was handed and
had no way to say so.

## 2. `runtime/ops_bend.mut.bend` is a HARNESS RESIDUE, not an armed plant

Established by searching for **what reads it**, not for its own name.

| role | `file:line` |
|---|---|
| **producer + consumer** | `.agents/slop/bend_mutate.py:9` — `T = F.with_name('ops_bend.mut.bend')`; written at `:46`, run at `:47` |
| the mutation it holds | `.agents/slop/bend_mutate.py:18` — row **`M3`**, `'lanes: drop the bool lane'` |
| deadarm census | `.agents/slop/deadarm/bendarm.py:136` globs `tinybendygrad/**/*.bend`; `:138` sees `def main(`, so `:155` admits it as an **entry point** |
| frozen file list | `.agents/slop/triage/allfiles.txt:70` (written 2026-10-04 22:34) |
| prose only, not a gate | `.agents/slop/e2e.sh:138` — *"and `ops_bend.mut.bend` (a scratch copy)"* |

The on-disk diff is **exactly one line, 144**, and is byte-for-byte `M3`. `MUT` in
`bend_mutate.py:15-39` runs `M1…M20` **in order**, so a completed run would leave
**M20**'s text (`wire_dtype`). It leaves `M3` ⇒ **the run was interrupted after
`M3.write_text`, i.e. this is residue of a killed harness, not a deliberate plant.**

**No gate asserts the file exists.** Nothing reads it expecting a verdict. Deleting it
removes one line from `substrate-check.sh`'s verdicts and one entry from `bendarm`'s
census; neither is a gate failure.

**And deleting it is NOT the `fresh()` re-arm**, which is the trap `MUT-LEDGER.md:184`
warns about. `mutate.py:20-24 fresh()` is `rmtree` + `copytree(LIVE → MUTANT)`, i.e. it
writes **out of** the live tree. `bend_mutate.py:46` writes **into** it, but only when a
human runs that script. So the delete holds until somebody deliberately re-runs the
harness — and if they do, §3 catches it.

**The mutant cannot be moved to `$TMPDIR`.** `bend_mutate.py:6-8` says why, and
`agent-core.md:217` confirms: a scratch copy cannot resolve `import ../helpers.bend`, so
every mutation reports "did not compile". The residue must stay at the relative path;
what has to change is that its arrival is *visible*, which is §3.

## 3. The mechanism — INDEX MEMBERSHIP, chosen over three alternatives

**Rule `PROBE-1`.** A file in `tinybendygrad/` is **PORT** iff `git ls-files` knows it.
Otherwise it is **NOT-PORT**, and `substrate-check.sh` prints it and fails.

**The property measured: silence requires ownership.** The alarm is silenced by exactly
one act — `git add` the file — which puts it in the index and therefore in the commit.
There is no configuration, no registry to update, and no name to remember. A probe
cannot be quiet unless it has been *committed*, and committing it is a visible, recorded
decision by a named author.

Alternatives, each weighed against a measured property:

- **A `PROBES.md` at the port root the router reads.** A registry reproduces the defect
  one level down: the probe that moves the count is the probe nobody remembered to
  register. Rejected — it is the same bug with a config file.
- **A `.probe` / `.mut` suffix the router routes to `NO INSTRUMENT`.** Removes the file
  from the bend lane, so `./bin/bend` can no longer run it. A probe an instrument cannot
  execute is debris with a polite name. Rejected.
- **A sentinel filename convention / header / comment.** `MUT-LEDGER.md:174-177` already
  measured this: `mutate.py:10 fresh()` is `rmtree` + `copytree`, so in-file markers are
  erased by the next experiment, and a header or comment never appears at the hit site.
  Rejected.
- **`.gitignore`.** Rejected as the *mechanism*, **kept as the producer-side habit.**
  `.gitignore:34-38,51-52,95,100-101` already carry `*.mut.bend`, `probe-*.bend`,
  `_*[0-9].bend`, `tinybendygrad/test/_probe/` — and they are strictly weaker than
  `ls-files`, for three measured reasons: (i) a pattern **cannot untrack**, and
  `.gitignore:48-50` records that no-op as looking exactly like success;
  (ii) `probe-*.bend` needs a **hyphen**, so `probe_f32lit.bend` slipped through and is
  now **staged**; (iii) ignore rules are consulted by *git*, and the router's population
  comes from **`find`** — which never asks git.

## 4. The instrument — `ROUTE` now prints its own denominator split

`substrate-check.sh` gains a `PROVENANCE` line after `ROUTE`. **Measured, live, all four
states** (`probes/demo.sh`, which re-derives its file list on every step — see the
stale-list trap below):

| state | `.bend` handed | port | non-port | not-in-index | **port count** |
|---|---|---|---|---|---|
| A — as it stands | **138** | 113 | 25 | 2 | **113** |
| B — a probe planted under an **innocent name** | **139** | 113 | **26** | **3** | **113** |
| C — that probe removed | 138 | 113 | 25 | 2 | **113** |
| D — `ops_bend.mut.bend` deleted (this unit's plant) | **137** | 113 | 24 | 1 | **113** |

**THE LAST COLUMN IS THE WHOLE THING.** `.bend handed` moves 138 → 139 → 138 → 137 — the
old instrument's `bend=` moved by one, silently, four times, and that is exactly what
nobody saw. **`port=` does not move: it is 113 in every state**, because a probe is not a
port however it is named, and the residue is now printed beside the total instead of
folded into it. `.bend handed` still has to move — it is a count of files on disk — but
it is no longer the only number on the line.

The paired disarm (`checks/disarm.sh`), because a red with no paired green proves
nothing:

| | not-in-index | PORT ALARM |
|---|---|---|
| armed: probe on disk, not staged | 1 | **1** |
| disarmed: `git update-index --add` — i.e. own it | 0 | **0** |
| released from the index again | 1 | **1** |

`port=` did not move across any of the three, so the alarm is the only thing the
off-switch touches, and the script records the whole index state before and proves it
restored after (it uses `git update-index`, which never touches the worktree, because
`probe_f32lit.bend` is staged by a live unit and the index is shared).

**Two criteria, and they are NOT interchangeable — each has the other's blind spot:**

| criterion | fails on | blind spot (measured) |
|---|---|---|
| `not-in-index` | `ops_bend.mut.bend`, `test/_probe/v5.bend` | a probe already swept into a commit (`_p6.bend`, `zzdiag/zzprobe2/zzread/zzsplit`, `uop/probe-mmcore.bend` are all **tracked**) |
| `no-upstream` | 25 `.bend` files with no upstream `.py` | **16 are legitimately not 1:1 with an upstream `.py`** — `LAWS/**`, `PROOF*.bend`, `base.bend`, `sz.bend`, `codegen/kernel.bend`, `codegen/rewriter.bend`, `uop/fold.bend`, `codegen/decomp/transcendental_f32.bend`, `renderer/{tc_ptx,nir_llvmir}.bend`, `runtime/webgpu_call.bend`, `test/dtype_oracle.bend` |

So **`no-upstream` is REPORTED and never FAILS** (16 findings forever is a guard nobody
reads), and **`not-in-index` FAILS** (zero false positives over all 144 files). The
`$TMPDIR` scratch copy is *also* not in the index, so the alarm is scoped to paths
inside `tinybendygrad/` — `agent-core.md:217` makes scratch copies a sanctioned
workflow, and failing them would be a false positive on it.

## 5. Classification of every non-port file in `tinybendygrad/` — 31 of 144

Measured with `substrate-check.sh`'s `PROVENANCE` block over
`find tinybendygrad -type f | sort` (144 files). The number a reader should compare
against is the **port count**, not 144.

**TWO COUNTS, AND SAYING WHICH ONE IS WHICH — `no-upstream=31` vs `no-upstream=25`, both
right, because they ask different questions of a different population.** The
`no-upstream` criterion is asked **only of `.bend` files**: mirroring a `.bend` to
`tinygrad/*.py` is the port's own rule-1 convention, and asking it of `runtime/dtype.c`
is a category error — a `.c` seam half has no `.py` to mirror, so the question has no
answer and a `False` there is an artefact of the question, not a finding. So of the 31
files with no upstream `.py`, **6 are the `.c`/`.js` seam halves (§C) and 25 are `.bend`.**
`MUT-LEDGER.md` §4 counts 31 because it asked the question of every file. Reproducing its
31 independently was worth the run; reporting `25` without saying why would have looked
like a 6-file disagreement with a ledger that was not wrong.

### A. MUTANT — 1, and it is deleted
`runtime/ops_bend.mut.bend` — `M3`, §2. Deleted. **Port count becomes 137 of 143.**

### B. PROBES — 8, **all tracked**, none not-in-index but `probe_f32lit.bend`
| file | bytes | note |
|---|---|---|
| `probe_f32lit.bend` | 1,317 | **staged in the index; owned by a LIVE unit — reported, not touched** |
| `runtime/zzprobe2.bend` | 2,611 | its own header: `# scratch probe -- DELETE.` |
| `runtime/zzdiag.bend` | 583 | prints diagnostic rows |
| `runtime/zzread.bend` | 350 | reads U32s from stdin |
| `runtime/zzsplit.bend` | 1,008 | probe |
| `runtime/_p6.bend` | 204 | prints F32 bits of 3 literals; `.gitignore:44-52` records it as the file that proved the pattern set has holes |
| `uop/probe-mmcore.bend` | 23,478 | self-declared standalone probe |
| `test/_probe/v5.bend` | 742 | **not-in-index** ⇒ trips the alarm; `.gitignore:97-101` already declares the dir scratch |

### C. SEAM / LANE HALVES — 6, tracked, keep
`runtime/dtype.{c,js}`, `runtime/sz.{c,js}`, `runtime/webgpu_call.{js,mjs}`.

### D. PORT INFRASTRUCTURE with no 1:1 `.py` — 16, tracked, keep
`LAWS.bend`, `LAWS/{spec,alu,PROOF-ALL}.bend`, `PROOF.bend`, `PROOF2.bend`,
`base.bend`, `codegen/{kernel,rewriter}.bend`, `codegen/decomp/transcendental_f32.bend`,
`renderer/{tc_ptx,nir_llvmir}.bend`, `sz.bend`, `runtime/webgpu_call.bend`,
`test/dtype_oracle.bend`, `uop/fold.bend`.

## 6. Found while measuring, not fixed — `file:line`

### ⚠ A STALE FILE LIST IS A WAY TO MAKE A DENOMINATOR LIE, AND IT IS SILENT

`probes/demo.sh`'s first cut snapshotted `find tinybendygrad -name '*.bend'` **once**,
before planting anything. All four passes then printed **identical numbers, `of 138` four
times** — because a list frozen before the probe was planted does not contain the probe,
and a deleted file still gets classified because the *path* is still on the list. **The
instrument was correct, the input was stale, and the output looked like four successful
passes.** Re-deriving the list per step is what turned the demonstration from four copies
of the same number into the table in §4.

This is not only my bug: **`.agents/slop/triage/allfiles.txt` is exactly such a list**,
frozen 2026-10-04 22:34, and it is what produced `gate-BEFORE.txt` / `gate-AFTER.txt`. A
reader comparing a router run against that file is comparing against a **census**, not
against a tree. (The freeze is harmless for a before/after pair *about the same instant*,
which is what it was used for. It is not harmless for any comparison across sessions, and
`bend_mutate.py:6-8` names the same trap for a different reason: a copy frozen elsewhere
cannot resolve `import ../helpers.bend`.)

### Two bugs in THIS unit's own new block, and only one of them was safe

- **DROPPING THE `tinygrad/` PREFIX PRODUCED A PLAUSIBLE WRONG NUMBER.** Inlining the
  predicate into `substrate-check.sh`, I wrote `os.path.isfile(p[13:-5] + ".py")` where the
  standalone version had `os.path.join("tinygrad", …)`. It printed
  `port=1 non-port=137 no-upstream=137` — four plausible integers, all wrong, **and the
  line looked exactly like a result.** `not-in-index=2` was still correct, because that
  half of the predicate does not touch the filesystem. **A defect in one conjunct of a
  predicate does not dim the other conjunct, so partial correctness is not a check.**
  Caught only because the standalone version had printed `port=113` seconds earlier and
  the two numbers could not both be right. This is `agent-core.md`'s "verify an instrument
  before believing its output", and the fix was to keep the earlier run's numbers as a
  regression target rather than to re-read the new code.
- **DROPPING THE CLOSING `)` OF `$(...)` FAILED LOUDLY, which is why it is the second item
  and not the first.** Rewriting `')` as `' "$n_bend"` to pass the bend count in lost the
  paren, and zsh reported `parse error near 'PROVENANCE=$(print -...'`. **The parse error
  is the fail-safe direction**: a broken instrument announced itself instead of printing a
  number. Worth recording as the contrast — the paren bug cost one bisect, the prefix bug
  would have shipped a wrong count under a green `SUBSTRATE CLEAN`.

- **`.agents/slop/guardfix/probe-c.bend` DOES NOT COMPILE**, so the router's **entire `.c`
  lane is dead right now** and every `.c` file reports `NO INSTRUMENT`:
  `expected : @-R:Type -> @k:(@_:F32 -> IO.OP<R>) -> IO.OP<R>` / `observed : F32`, at
  `main`. `substrate-check.sh:140-141` correctly refuses and `c_context` returns 1 — the
  fail-safe half works — but **no `.c` file has been judged today**, so any claim that
  the six non-`.bend` files are clean is currently unfounded. `probe-c.bend` is
  `guardfix`'s and `dtype.bend` is a live unit's; neither is mine.
- **The tracked probes (§B) are the alarm's blind spot and I could not close it.** They
  are tracked, so `not-in-index` is silent on 6 of 8. Closing it needs `rm` plus a
  commit — the coordinator's call, exactly as `MUT-LEDGER.md:206-209` says.