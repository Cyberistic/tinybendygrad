# The corpus is a singleton now, and a second run is REFUSED

`.agents/slop/corpuslock/` — the measurements behind this report, and the plant and control
that prove them.

## The defect

`checks/differ.py` writes every artifact of the `graphcmp` corpus into ONE directory,
`runs/graphcmp/D/`, and `run` and `repro` both write it, artifact by artifact. Nothing stopped
two of them from running at once, and the tree's own record of what happens when they do is
the incident of 2026-10-23: a `differ.py repro` started at 03:37 and a `differ.py run` started
at 03:45 ran CONCURRENTLY; the `run` overwrote the green `D0-run-summary.txt` that a good
02:24 run had written; the summary it wrote was GREEN (35/35 agree, 35/35 byte-identical,
8/8 plants) while its OWN two substrate digests DISAGREED (`substrate-start=0c950c47…` vs
`substrate-end=074e0233…`, because a `.bend` edit landed mid-run);
`gates/corpuswitness-gate.py` then went RED on 4 of its 7 readings (`verdict.current`,
`witness.fresh`, `witness.substrate`, `claim`) while `verdict.reported` stayed OK — a summary
that says green and a witness that says the claim is not established. Both processes had to be
killed by hand.

`gates/corpusverdict-gate.py`'s `run.gated` row was supposed to catch this and did not: it
read `inspect.getsource(differ.cmd_run)` and asked whether `clean_run(` or `ready(` appeared
in it — a SOURCE-LEVEL PROXY. `checks/differ.py` has `def ready(wait)` and
`def clean_run(label, wait)`, and neither CALL appears inside `cmd_run`'s own source, so the
row read FAIL for a reason that had nothing to do with the property it was standing in for.

**The corpus was ALREADY STALE before this work**, measured, so the redness below is not new:
the recorded summary carries `substrate-start=81101a6a…` / `substrate-end=cfeb41ea…` and the
live digest was `88551f9d…` BEFORE any edit here. `checks/differ.py` is in `SUBSTRATE_INPUTS`,
so editing it moves the digest further (`abc68898…` now). **A RE-RUN IS WHAT MAKES THE
RECORDED VERDICT CURRENT AGAIN, and this unit did not re-run the corpus** — see "WHAT I COULD
NOT MAKE TRUE".

## The lock, and why it is this shape

`CORPUS_LOCK = runs/graphcmp/.corpus.lock`, an **`fcntl.flock`**, taken by `run`, `repro`,
`plant` and `snap` BEFORE anything touches the directory.

**It is not the bend lock, and the measurement is why.** `checks/bendlock.sh` serialises
COMPILER invocations; this serialises WRITERS to one directory — two different resources, and
a lock is only a lock if every form of it shares one path. `bendlock.sh`'s own header says a
command that runs MANY bends MONOPOLISES the lock for the whole command (MEASURED: 26 minutes
for an 11-bend gate), and the corpus runs ~100 bends and takes 271 s (AGENTS.md, 2026-10-22),
so holding the bend lock for a corpus run would park every other unit's compiler for the whole
run. And MEASURED: the corpus takes NO bend lock today — 0 references to `bendlock` in
`checks/differ.py` and in `.agents/slop/graphcmp.py`, and the bends are spawned by
`graphcmp.py` as `subprocess.run([str(BEND), …])`. So the corpus-wide lock MUST be its own
lock; and taking the bend lock PER BEND inside the corpus (what `bendlock.sh`'s header
prescribes for a many-bend command) is a SEPARATE change and is not this one. **That residual
is real and is reported: the corpus's bends are still unserialised against other units' bends.**

**Why `flock` and not `mkdir`-and-a-PID:** the kernel's lock has three properties the
directory shape does not. It is RELEASED WHEN THE HOLDER DIES, so there is no stale lock to
reclaim and no window in which a killed run blocks the next one (`bendlock.sh` needs 300 s of
stale-owner reclamation and a SECOND check for its `bun` child, because its owner is a shell
that can die while its child lives; this lock's owner IS the writer). It CANNOT BE STOLEN, so
there is no read-then-remove window in which a live holder's lock is deleted by a second
process that read it a moment earlier. And it CANNOT BE DOUBLE-HELD. `bendlock.sh` cannot use
it: it is POSIX `sh`, where `flock(2)` does not exist.

**One consequence, and it is the reason `clean_run` changed:** the lock is held by the process
that WRITES the artifacts, so `clean_run` can no longer spawn `differ.py run` as a child — a
child would be a second writer, and the only ways out are a re-entrancy rule any second
`differ.py` could forge, or a parent-death check a killed parent fails. `one_run()` calls
`cmd_run` IN-PROCESS, captures the two streams the child used to send to `DEVNULL`, and
re-emits them only when the run FAILED.

## The refusal

```
another corpus run holds the lock: runs/graphcmp/.corpus.lock is held by pid 15333 (held for
1s, /…/.venv/bin/python /…/checks/differ.py run).  This run refuses to start: the corpus is a
SINGLETON -- two runs write the SAME directory (runs/graphcmp/D) and would overwrite each
other's artifacts.  Wait for the holder.
```

Exit **3** (`REFUSED`, `gates/gatekit.py:83`). Nothing is written: the lock is taken before
`D.mkdir`, before the stale-temp sweep and before the population check.

## The plant (`.agents/slop/corpuslock/plant.py`)

A REAL corpus run, redirected to a scratch directory with `GRAPHCMP_ARTIFACTS` so it cannot
destroy the tree's 319 files of evidence, then a SECOND real `checks/differ.py run`:

```
# first run: pid 15333, artefacts -> runs/graphcmp/.plant-15328
# the first run holds the lock: pid 15333 (held for 0.1s)
# the first run has written 2 artefact(s): ['.tmp.D0-selfcheck.txt', 'D0-selfcheck.txt.err']
# second run: rc=3
another corpus run holds the lock: runs/graphcmp/.corpus.lock is held by pid 15333 (held for 1s, /…/checks/differ.py run).  This run refuses to start: …
# artefacts after the second run: 2 -> ['.tmp.D0-selfcheck.txt', 'D0-selfcheck.txt.err']
# artefacts byte-identical across the refusal: True
# first run killed (rc=-15)
# the tree's evidence byte-identical across the plant: True
# scratch removed: True
# PLANT PASSED
```

## The control (`.agents/slop/corpuslock/control.py`)

A COPY of `checks/differ.py` with the lock removed (`take_lock` returns `None`) and the work
removed (`_command` returns 0), and a COPY of the gate beside it, so the copy's `ROOT` is a
scratch tree and the copy's `singleton()` really does spawn the copy's `run`:

```
control.singleton	state=OK	note=planted second-runs all read NOT-refused
run.gated	state=FAIL	verdict=SHARED	holder=62800	rc=0	note=the second run was not refused: ''
# CONTROL PASSED -- the row went RED without the lock
```

The real tree reads `run.gated state=OK verdict=SINGLETON`. **The row can go red.**

## The probe that found a defect in the lock itself

`.agents/slop/corpuslock/onerun.py` measures `one_run()`'s plumbing, the `clean_run`
composition, and the lock's WIRING into the command path — 15 checks, GREEN 15 of 15. It
also found a real defect, in the lock this unit had just written:

* `take_lock()` is re-entrant inside one process (`repro` runs `cmd_run` in the process that
  holds the lock), and the re-entrant path returned `None` WITHOUT counting the hold, while
  `drop_lock()` always decremented. The inner `drop_lock()` that `command()` runs in its
  `finally` therefore released the OUTER hold.
* The probe's child — started to measure the refusal — was NOT refused, and it ran a corpus
  into the tree's `runs/graphcmp/D`: **315 of the 319 evidence files were rewritten by that
  killed run**, and `D0-coverage-census.txt` was left 0 bytes.
* Fixed in `84f9c7925`: the hold is COUNTED (`take_lock` increments the depth on the
  re-entrant path too; `drop_lock` releases one hold and closes the descriptor only at depth
  0), and the probe is now SANDBOXED — its child gets `GRAPHCMP_ARTIFACTS=<tempdir>` and the
  probe asserts the child wrote nothing there.

## The gate's row, before and after

| row | before | after |
|---|---|---|
| `run.gated` | `state=FAIL verdict=UNGATED cmd=differ.py run -> cmd_run` — a grep of `cmd_run`'s SOURCE for `clean_run(`/`ready(` | `state=OK verdict=SINGLETON holder=20592 rc=3 note=refused and named the holder` — the gate HOLDS the lock, runs the REAL `checks/differ.py run` against a scratch `GRAPHCMP_ARTIFACTS` directory, and asserts it refused, named the holder, and wrote nothing |
| `run.readiness` | — (it WAS `run.gated`) | `state=FAIL verdict=NOT-READINESS-GATED` — the old source-level check, KEPT as its own row so nothing is dropped |
| `control.singleton` | — | `state=OK note=planted second-runs all read NOT-refused` — the positive control for the new comparator, the same shape as the gate's existing `control` row |

## What I could NOT make true, and why

* **THE TREE'S ARTEFACT SET IS A MIXTURE, AND THIS UNIT MADE IT WORSE.** The recorded
  summary's own two substrate digests already disagreed (`81101a6a…` vs `cfeb41ea…`) — that
  is the incident of 2026-10-23, still in place — so the live set was ALREADY a mixture
  before this unit touched it. Then a probe of this unit's own making found a REAL DEFECT in
  the lock: `take_lock()` is re-entrant inside one process (`repro` runs `cmd_run` in the
  process that holds the lock) and the re-entrant path returned `None` WITHOUT counting the
  hold, while `drop_lock()` always decremented — so the inner release released the OUTER
  hold. A child the probe started to measure the refusal was therefore NOT refused, and it
  ran a corpus into `runs/graphcmp/D`: **315 of the 319 evidence files were rewritten by that
  killed run, and `D0-coverage-census.txt` was left 0 bytes.** The fix is committed
  (`84f9c7925`): the hold is COUNTED, and the probe is now SANDBOXED (its child gets
  `GRAPHCMP_ARTIFACTS=<tempdir>` and the probe asserts the child wrote nothing there).
  **A FULL CORPUS RE-RUN IS NOW REQUIRED** to restore a coherent set, and this unit did not
  do it: the machine measured loadavg 16.61 on 12 cores with ~800 MB of free pages, a corpus
  run is 271 s and ~975 MB over ~100 bend compiles, and — the reason that decides it — a
  re-run on a tree this busy would probably land a `.bend` edit mid-run and produce ANOTHER
  mixture. The damage is REPORTED and not silent: `differ.unhealthy()` says "THE SUBSTRATE
  MOVED WHILE THE RUN WAS IN FLIGHT, so D/ holds a MIXTURE of two substrates", and
  `artefacts_ok()` reports the 0-byte artifact.
* **THE RECORDED CORPUS VERDICT IS STILL STALE, AND IT WAS ALREADY STALE BEFORE THIS WORK.**
  Measured: recorded `81101a6a…`/`cfeb41ea…` against a live `88551f9d…` before any edit, so
  `gates/corpusverdict-gate.py`'s `substrate` row and `gates/corpuswitness-gate.py`'s
  `verdict.current`, `witness.fresh`, `witness.substrate` and `claim` rows were ALREADY red
  (4 of 7 — exactly the set the incident of 2026-10-23 produced). Editing `checks/differ.py`
  moves the digest again, because that file is in `SUBSTRATE_INPUTS`. The `bend` row now reads
  `ALL PROOFS CHECK` rc=0, so the substrate DOES settle today and a re-run is possible — that
  is the next unit's move, on a quiet tree.
* **`run.readiness` IS STILL RED.** `cmd_run` has no readiness gate, so a `run` against an
  unsettled substrate would overwrite the evidence with a dead bend lane. That is a real
  hazard and a DIFFERENT one from two runs interleaving; the check was kept, not weakened,
  and it goes green when `cmd_run` consults `ready()`.
* **THE CORPUS'S BENDS ARE STILL UNSERIALISED AGAINST OTHER UNITS' BENDS.** The corpus takes
  no bend lock today, and taking it PER BEND (as `bendlock.sh`'s header prescribes for a
  many-bend command) would mean editing `.agents/slop/graphcmp.py`, which is a path other
  units hold. The corpus lock does not address that and is not the right lock for it.
* **`repro` WAS NOT RUN END TO END.** `one_run()`'s plumbing and the `clean_run` ->
  `ready` -> `one_run` -> `cmd_run` -> health-check composition are measured with a stubbed
  `cmd_run` (15 of 15, `.agents/slop/corpuslock/onerun.py`), and the REAL `cmd_run` is
  exercised by the plant — but a full `repro` is two corpus runs (~9 minutes) and the brief
  forbids a long-lived corpus run. The failure mode if `one_run()` were wrong is a `REFUSED`
  repro, not a corrupted one.
* **THE WITNESS GATE'S PROSE IS NOW STALE.** `gates/corpuswitness-gate.py`'s header says
  "`corpusverdict-gate.py` exits non-zero today: its `run.gated` row is FAIL because
  `cmd_run` has no readiness gate". `run.gated` now reads OK and `run.readiness` reads FAIL,
  and the gate still exits non-zero — the sentence's REASON moved. That file was not edited
  here: it was not this unit's file, and it is a shared path.
