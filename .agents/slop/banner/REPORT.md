# THE `== n/m` DUPLICATE: what `blocks()` recognises, which repair survives, and what is still red

**HEAD `0273fe4286e2446c28865eaa155ec09e3052a41f`** · read 2026-10-19T16:24Z–16:27Z (local 19:24–19:27) ·
loadavg 5.41 · `verdicts.py` mtime 2026-10-07 local · `live.port.out` mtime 2026-10-07 23:25 local ·
`checks/e2e.py` mtime 2026-10-19 19:27 local, **unedited by me and moving under the measurement**.

**LANDED NOTHING.** Everything below is under `.agents/slop/banner/`. The two `.sh` files were
copied, patched, and `zsh -n`'d; their mtimes are still `2026-10-07T23:25:58` local. No gate was run:
`checks/e2e.py`, `checks/e2e.sh`, `checks/differ.py`, `gates/` and both `run-*.sh` were never executed.

---

## 1. THE PARSING RULE, QUOTED

`blocks()` recognises a stage header by **shape alone**. `verdicts.py:63`:

```python
HEADER = re.compile(r"^== (\d+)/(\d+) (.*)$")
```

and `verdicts.py:130-137`, the only consumer:

```python
    for no, ln in enumerate(text.splitlines(), 1):
        if m := HEADER.match(ln):
            n = int(m.group(1))
            banners.setdefault(n, []).append((no, ln))
            if n not in bodies:            # the FIRST banner for n opens it
                bodies[n], current = [], n
            elif current is not None:      # a RE-OPEN: n is already open, so this is n's own body
                bodies[current].append(ln)
```

So: a line is a stage header iff its TEXT is `== ` + digits + `/` + digits + a space. Nothing else is
consulted — **not the writing process, not indentation beyond column 0, not the gate's own source.**

### WHY A CHILD'S BANNER IS MISREAD. It is not a misparse.

The framing in `AGENTS.md` ("a STAGE's INNER LANE prints a `== n/m` banner") is wrong about the
mechanism, and the correction changes the repair. The two emitters are not inner lanes — they are
**the gate's own header and the sub-gate it shells out to**:

| who | emits | what it meant to report |
|---|---|---|
| `checks/e2e.py` `say("== 6/7 the matmul THROUGH THE PORT ...")` | `live.port.out:74` | **stage 6 opening**, with the gate's own denominator |
| `.agents/slop/e2e_port/run-port-mm.sh:107` `say "== 6/6 THE MATMUL THROUGH THE PORT ..."` | `live.port.out:77` | **the sub-gate's own title block**, when run standalone |
| `checks/e2e.py` `say("== 7/7 the SAME kernel in f64 ...")` | `live.port.out:231` | stage 7 opening |
| `.agents/slop/f64/run-f64.sh:78` `say "== 7/7 AN f64 KERNEL THROUGH THE PORT ..."` | **never reaches the transcript** | the sub-gate's own title block |

The transcript is a **single undifferentiated stream**: `stage()` captures the child's whole output to
a file and `echo_file(pmm)` prints it into the gate's own stdout, in place. `blocks()` is handed that
text and there is no channel marker in it. **The duplicate is real and unavoidable in the artifact;
the parse is correct.** `blocks()` already stopped *losing* the lines (the first banner opens, a later
one is kept as a body line) and `reopens()` turns the duplicate into an explicit failure.

---

## 2. THE TWO EMISSIONS, QUOTED

`run-port-mm.sh:106-108`:

```sh
hr
say "== 6/6 THE MATMUL THROUGH THE PORT  -- execution: no Node, no browser, no adapter,"
say "        no tinygrad Python scheduler in the execution path"
```

Meant to report: *this script, run on its own, is the stage-6 lane* — execution with no Node, no
browser, no adapter, no Python scheduler in the path. The `6/6` was a hand-copied copy of the gate's
denominator and is **already stale** (the gate says `n/7`).

`run-f64.sh:77-79`:

```sh
hr
say "== 7/7 AN f64 KERNEL THROUGH THE PORT -- double, not float"
say "   harness: .agents/slop/portexec/run-kernel.sh mm, UNCHANGED, on a copy"
```

Meant to report: *the same kernel one dtype wider, through the same harness, unchanged.* Same stale
hand-copied denominator.

Both hardcode a count in a file that cannot check it. `readings()` at `verdicts.py:175` reads
`hs[0][1]` — **the first banner only** — so a child's `m` is never disputed by any reading. Control
**V7** below: with the child printing `== 6/99`, `readings()` still reads `m = 7` and counts the `99`
only as a re-open.

---

## 3. THE VERDICT: **(a), and (b) is not merely worse — it is not implementable**

### (b) "only banners at column 0 / from the gate's own stdout"

- **"Column 0" is already the behaviour and has been all along.** `HEADER` starts `^` and is applied
  with `re.match`, which anchors at position 0. Control **V4**: an indented `== 6/6` line simply does
  not match. (b) as stated is a **no-op**, not a repair.
- **"From the gate's own stdout" cannot be expressed.** The gate's stdout *is* the transcript and it
  *contains* the child's output by construction (`echo_file`). A `.out` file carries no channel
  metadata. Distinguishing them would mean changing the gate to tag lines — a larger change to the
  artifact's fidelity than the defect.
- **The one form of (b) that could work is circular.** Whitelisting banner text against
  `checks/e2e.py`'s own `say("== n/m …")` strings makes the TRANSCRIPT population a function of the
  GATE SOURCE. That is exactly what this file's own docstring (`:23-28`) rejects: *"A CENSUS THAT
  DERIVES ITS OWN DENOMINATOR FROM THE THING IT IS CHECKING CHECKS NOTHING."* It would also stop
  reporting any duplicate the gate does not itself produce.

### THE DEAD CASE, MEASURED — control **V5**

If (b) is implemented as narrowing and ever over-narrows, `blocks()` sees **no stage at all**:

| variant | stages `blocks()` saw | stage 6 denominator | re-opens | verdict |
|---|---|---|---|---|
| V5 | `NONE -- DEAD` | `None` | none | nothing to fail on |

Seven stages print `RETIRED`, `bad` stays empty, rc 0. **The check would go green having measured
nothing** — which this tree's own doctrine calls worse than no check: *"A GATE THAT EXITS 0 HAVING
MEASURED NOTHING IS WORSE THAN NO GATE, BECAUSE IT IS TRUSTED."*

### (a) KEEPS THE ABILITY TO FAIL — control **V3**, and it is the decisive one

Under (a) with the repair applied **and** stage 6's denominator row removed:

> `FAIL: EMITTED, verdict PASS, no denominator counted`

The re-open is gone and the stage **still fails** on the real defect. (a) removes a *duplicate at the
source*; it does not teach the census to ignore duplicates. That is why it is the right one.

### PREFERENCE ALREADY IN THE TREE

`run-f64.sh:94` prints `== 0  THE SUBSTRATE, …` — a section header deliberately **outside** the
`n/m` shape, alongside `== COVERAGE`, `== NEGATIVE CONTROLS`, `== WHERE EACH STAGE …` in the same
transcript. The rename follows a convention the tree already uses.

---

## 4. THE CONTROL — `.agents/slop/banner/blocks-test.py` → `blocks-test.rows`

Run: `.venv/bin/python .agents/slop/banner/blocks-test.py`. It **imports** `verdicts.py` and calls
`blocks()` / `reopens()` / `denominator()` / `readings()` on synthetic and real text. No gate, no
`bend`, no `node`, no `cc`.

| variant | stages seen | stage 6 body lines | stage 6 denom | re-opens | `main()` on stage 6 |
|---|---|---|---|---|---|
| **V1** as-is | 6, 7 | 4 | 64 | `stage 6 @line 3`, `stage 7 @line 7` | — |
| **V2** repair (a) | 6, 7 | 4 | 64 | **none** | no denominator failure |
| **V3** repair (a) + denominator row deleted | 6, 7 | 3 | `None` | none | **FAIL: EMITTED, verdict PASS, no denominator counted** |
| **V4** (b1) column 0 | 6, 7 | 4 | 64 | none | no denominator failure |
| **V5** (b) at its failure mode | **NONE — DEAD** | 0 | `None` | none | nothing to fail on |
| **V6** what is on disk today | 6, 7 | 4 | 64 | `stage 6 @line 3` **only** | — |

**V8, on the REAL artifact, not a synthetic one** — the candidate's one line applied to
`live.port.out` in memory:

| | stage 6 denominator | re-opens | stages seen |
|---|---|---|---|
| before | 64 | `stage 6 @line 77` | 7 |
| **after** | **64** | **NONE** | **7** |

Re-running the real `readings()` over the patched banners against the live `checks/e2e.py` leaves
**6 `DENOMINATOR FAIL`s — stage 1, 2, 3, 4, 5, 6** — all `gate SAYS 7` against a transcript whose own
banners read `1/4 2/4 3/4 4/4 5/5 6/6 7/7`. **The re-open is not among them.** The candidate clears
exactly one failure and leaves six that only a fresh run can clear.

**V6 is the finding that halves the work**: stage 7's duplicate is **LATENT, not live.** `checks/e2e.py`
routes stage 7 through `grep_file(f64, F64_RE)` and `F64_RE`'s alternatives (`STAGE 7 PASS|FAILED`,
`64/64 MET`, `IDENTICAL`, `port now says`, `REFUSED[`, `RED   [`, `GREEN [`, `THEOREM [`, `F64-[0-9]`)
do not match the banner, so it is filtered out before `blocks()` ever sees it. Confirmed against the
raw child artifact: `runs/e2e/e2e-f64.out:3` **does** carry `== 7/7 AN f64 KERNEL …`, and it is still
absent from the transcript. Stage 6 has no such filter — `echo_file(pmm)` prints the whole file.

---

## 5. THE CANDIDATE — `.agents/slop/banner/candidate.diff`, 2 hunks, nothing landed

Both patched copies `zsh -n` clean. One changed line each; the rest is the reason, named and anchored.

**`run-port-mm.sh` is the REQUIRED fix** (measured, re-opens today).
**`run-f64.sh` is PREVENTIVE** (latent, filtered today; still a stale `7/7` for any reader of
`runs/e2e/e2e-f64.out`, and `AGENTS.md` tells every future agent both are broken).

**Deliberately NOT touched, and this is a scope decision, not an oversight:**
`checks/run-port-mm.sh:124` and `checks/run-f64.sh:85` carry the same banners. **No gate invokes
them** — both `checks/e2e.py` and `checks/e2e.sh` invoke the `.agents/slop/` copies — so they cannot
reach a transcript. They are cited only as source material by `gates/shellverdict-gate.py`,
`gates/shellverdict-reach-gate.py`, `checks/coverage.py` and `checks/oracle_f64.py`. I could not
measure a reason to touch them; changing them would be a guess.

---

## 6. IS `verdicts.py` STILL RED? YES — and the reason has moved **again**

`.venv/bin/python .agents/slop/e2estage8/verdicts.py` → **rc=1, 7 `DENOMINATOR FAIL`s.**

**The `PROSE names [0]` defect is genuinely repaired**, as `AGENTS.md` claims:
`PROSE 7 live: 1 2 3 4 5 6 7 | 1 RETIRED: 8`, and `PROSE == CODE == TRANSCRIPT` all agree. Stage 0 is
gone. That is the 2026-10-15 repair, and it holds.

**The 7 failures split into two unrelated groups, and the brief's premise is half-stale:**

1. **ONE re-open** — `stage 6: re-opened at transcript line 77`. This is the banner in question. It
   is `AGENTS.md`'s defect, it is real, and repair (a) clears it (V8, measured).
2. **SIX `gate SAYS` vs `run PRINTED`** — stages 1-6. **Nothing to do with the banners.** The
   transcript `verdicts.py` reads is `live.port.out`, mtime **2026-10-07 23:25 local — 11 days stale**.
   It was produced by a gate whose denominators were `n/4 … n/7`; today's gate says `n/7`
   throughout. **No code change can clear these six. Only a fresh run can.**

Also worth naming, because it will bite the next agent: **stage 7's SKIP verdict inside that
transcript points at `runs/e2e/e2e-f64.txt`, and the file on disk is `runs/e2e/e2e-f64.out`** — more
evidence the artifact predates the current gate. And `runs/e2e/` holds artifacts from **Oct 17**,
newer than the transcript, so the transcript is not even the newest artifact of the last run.

**One citation in the brief does not hold:** `AGENTS.md` points at `verdicts.py:75 blocks()`. In the
file at this HEAD, line 75 is a comment inside the `PROSE_TABLE` note; `blocks()` is at **:113-140**,
and its docstring (`:30-36`) already describes the re-open as **fixed**, with `reopens()` (`:143`)
reporting it as a failure. **The re-open was already repaired in `verdicts.py`; what remains is the
duplicate in the two `.sh` files.** `AGENTS.md`'s "a re-run will not go green until those two are
moved" is **right about the outcome and wrong about the mechanism.**

**And `checks/e2e.py`'s line numbers moved 21 lines during this measurement** (`:577`→`:598`,
`:583`→`:604`, `:580`→`:601`, `:593`→`:614`, `F64_RE` `:337`→`:350`) at unchanged HEAD, so the
candidate's comments cite **anchors, not line numbers**.

---

## 7. WHAT A LANDING AGENT STILL HAS TO DO

1. Apply `candidate.diff` to the two files. **No pin moves**: `BODY_SHA`/`ORACLE_SHA`
   (`checks/e2e.py:255`) pin `checks/e2e.sh` and `.agents/slop/e2epy/oracle-e2e.sh`, **not** these.
2. Re-run `checks/e2e.py` under the sum-precondition to get a **fresh** transcript. Only that clears
   the six staleness failures.
3. The re-open check then has **never fired green in a fresh transcript** — it should be exercised
   once deliberately, or it is an untested branch.
4. Per `AGENTS.md`, commit through a **private** `GIT_INDEX_FILE` whose value is byte-identical in
   every command of every step, and run `git show --stat` **and** `git fsck --no-progress` in the
   same command as the commit. This tree's index is collocated and armed.

## DELIVERABLES

| file | what |
|---|---|
| `blocks-test.py` | the control; imports `verdicts.py`, runs V1-V8 |
| `blocks-test.rows` | every reading above, as rows |
| `candidate.diff` | 2 hunks, 1 changed line each; `zsh -n` clean |
| `candidate/e2e_port/run-port-mm.sh`, `candidate/f64/run-f64.sh` | patched copies; originals untouched |