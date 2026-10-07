# `.agents/runs/` was not a duplicate. It was a run that never ran.

Measured 2026-10-05. 151 files, committed at `@-` (`c68bc8ad2f3f`), so this deletion is recoverable
with `jj restore -r @- .agents/runs`.

## 1. Does the repro gate read a prior run? NO — it manufactures both of its own.

**WARRANT, QUOTED (WALL/3, a decision citation must be quoted not pointed at).**
`checks/differ.py:477-489`, `cmd_repro`:

```python
    with tempfile.TemporaryDirectory() as tmp:
        shots = {}
        for label, run_label in (("A", "run A"), ("B", "run B")):
            if not clean_run(run_label, a.wait):
                return 2
            path = Path(tmp) / f"gcrepro{label}.sha"
            with path.open("w") as f:
                snap(f)
            shots[label] = path
        if shots["A"].read_bytes() == shots["B"].read_bytes():
```

Each `clean_run` shells `differ.py run` (`checks/differ.py:462`), which writes into
`D = ROOT/"runs/graphcmp/D"` (`checks/differ.py:39`, `:240`) — **one directory, overwritten**.
`snap` (`checks/differ.py:389`) hashes `D.rglob("*")` into `gcrepro{A,B}.sha` **in the temp dir**.

So the third hypothesis is the true one, and it is not "copies first": run B really does destroy
run A's artifacts. **What survives the overwrite is the `sha256` line list, not the artifacts**, and
it dies with the temp dir. A repro gate needs no earlier run, and `.agents/runs/` is doubly invisible
to it — `snap` only walks `D`, which is `runs/graphcmp/D`.

## 2. Which of the three answers. Answer 1 — but the frame was wrong.

Answer 1 (output, newest supersedes) is the *bucket*. The measurement is sharper: **this run produced
no output at all.** It is a crash log, not a verdict.

- **51 `.err` files, 1 distinct sha256.** All read `env: .venv/bin/python: No such file or directory`.
  One failure, recorded 51 times.
- **48 `.txt` files whose entire body is `rc=127\n`.** 32 more are **0 bytes**.
- Its own summary, `.agents/runs/graphcmp/D/D0-run-summary.txt`: `not-comparable=16`,
  `byte-identical=0`, `controls=0 of 5`, `stable-failed=5 of 5`, `selfcheck=rc=127`.
- **`D2-bytediff.txt`:** all 16 lines `NOT COMPARED: py=0 bytes bend=0 bytes`.
  **`D9-stability.txt`:** all 5 lines `NOT a reproducibility result`.

**The gate has already ruled this run worthless, in code.** Scored against `checks/differ.py`'s own
`PINS`, it violates **12 of 14**; and `artefacts_ok()` rejects it on shape alone — **32 EMPTY `.txt`,
48 rc-only `.txt`**, the two shapes its docstring names. `cmd_repro` would `return 2` at that step
and compare nothing. No oracle was ever here to move to `oracles/`, and keeping names for a verdict
that reads `VERDICT=` (empty) buys nothing.

## 3. THE RULE, as a sweep can apply it

**Do not write a new worth-test. Reuse the gate's.** Per-run directory, worth is a property of the
RUN, not of a file:

> **A run directory is EVIDENCE iff `unhealthy()` returns `[]`. Anything else is DELETE.**
> Fallback when there is no summary: **`artefacts_ok()` is empty.** A crash log fails both.

Per-file discriminator for a tree with no summary — three checks, each a `grep`:

| check | DELETE when | why |
|---|---|---|
| `.err` distinct shas | N files, 1 distinct content | one crash recorded N times is one crash |
| `.txt` body | empty, or wholly `rc=<nonzero>` | a return code is not a measurement |
| diff report | every line says `NOT COMPARED` | a negative is not an observation |

**Mechanism:** worth = a measurement someone can compare later. A run that never launched has none,
so its files are evidence *of the crash* and nothing else.
**Counterexample (the rule must NOT fire here):** a healthy run with `stable-failed=0 of 5` may
legitimately contain **empty `*.err`** — `artefacts_ok()` excludes `.err` on purpose, "a rule that
flags a correct file is a rule that always fails." Never delete on `.err` emptiness alone.
**Command:** `.venv/bin/python checks/no-txt.py`; verdict test is `unhealthy()`/`artefacts_ok()` in
`checks/differ.py`.

## 4. THE TRAP, which is why this was nearly deleted wrong

> **A CRASHED RUN AND A GOOD RUN PRODUCE THE SAME 151 FILENAMES.**

Filename set and file count are not evidence of a run. "83 files exist nowhere else" reads like
unique evidence until you open them and find 51 copies of one 49-byte string. *This* is the reason
`.agents/runs/` was almost dismissed as a stale duplicate of `runs/` — the inference was not wrong
about the arithmetic and was completely wrong about the artifact.

## 5. Outcome

**Removed: 151** (103 `.txt`, 48 `.err`), all of `.agents/runs/`. **Kept: 0 files** — nothing in the
tree was evidence, so nothing was renamed and **no generator was left writing a stale name**.

`checks/no-txt.py` was **not edited**. A carve-out is permission, not obligation, and a carve-out for
files I deleted would carve out nothing.

**`.txt`: 403 before, 341 after, `exit 1` both times — and the 341 is NOT 403−103.** Other units are
live and wrote `.txt` while this ran (`.agents/slop` 199→243, `checks` 4→24), so the arithmetic is
`403 − 103 mine + 41 theirs = 341`. **Re-measure before citing either number** (WALL/4). Remaining by
owner, none of it mine to move: `.agents` 243 (other units), `oracles` 37, `runs` 28, `checks` 24,
`langs` 8, `test` 1. `gates/artifacts` 24 was counted before and is now 0 — another unit retired
those while I worked.

## 6. Not settled

- **Who launched it, and from where.** All 51 `.err` say the relative `.venv/bin/python` did not
  resolve, so the `cwd` was wrong — but the committing change is empty-message `c68bc8ad2f3f` and
  carries no `file:line` for the invocation, so I cannot name the cause. It may still be live: if
  some unit runs `differ.py` from outside `ROOT`, it will recreate this directory.
- **Whether `runs/graphcmp/D` is currently healthy.** I did not run it — two units are live and
  `bend` must not run concurrently. My claim is only that `.agents/runs` fails the pins, which I
  measured without executing anything.
- **`runs/` still emits `.txt`.** The generator is `checks/differ.py`, which I may only read, so the
  22 `.txt` it writes into `runs/graphcmp/D` (28 across `runs/`) stay red until their owner renames
  both file *and* writer.