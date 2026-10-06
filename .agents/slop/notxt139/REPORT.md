# notxt139 — one stale number, and it was stale in FIVE files, not three

**MEASURED 2026-10-06.** `len(differ.declared())` = **139**, and 139 `.txt` files sit under
`runs/graphcmp/D/`; declared set == on-disk set exactly (`present - declared == declared - present == 0`).
The number the two owned files carried was **103**.

## 1. The witnesses and the denominator

Every site that names a count for the EXCUSED `.txt` set, `file:line`:

| file:line | says | owner | after this unit |
|---|---|---|---|
| `checks/no-txt.py:19` | "holds **103** `.txt` files this project therefore does not flag" | me | literal removed |
| `checks/no-txt.py:25` | "writes all 103; reads 12 by name" | me | "every declared name" |
| `checks/no-txt.py:26` | "writes all 103, reads 12" | me | "every declared name" |
| `checks/no-txt.py:30` | "**103 of 103** are named by two or more instruments" | me | "every declared name" |
| `checks/no-txt.py:65` | "a second list of 103 names" | me | "the declared names" |
| `checks/README.md:51` | "Why these **103** names end in `.txt`" | me | **139** |
| `checks/README.md:53` | "carves out exactly the 103 names" | me | **139**, and now "`differ.declared()` returns" |
| `checks/README.md:55` | "writes all 103" | me | **139** |
| `checks/README.md:58` | "**All 103** are named by two or more instruments" | me | **139** |
| `checks/README.md:75` | "reports **103 `MISSING`**" | me | **139** |
| `checks/differ.py:243` | "`oracle-run.sh` writes all 103" | NOT MINE | still 103 — reported |
| `checks/sweep.py:212` | "`LIVE_UNITS`, `ORACLE_WORD` and the **103** `.txt` names" | NOT MINE | still 103 — reported |
| `AGENTS.md:89-92` | meta: "THE 103 IN `checks/README.md:51-58` AND `checks/no-txt.py:19-30` IS STALE" | orchestrator | replacement below |
| `AGENTS.md:87-88` | "`len(differ.declared())` = **139**, and 139 on disk" | orchestrator | already correct |

**DENOMINATOR: 13 count-bearing sites over FIVE files; 12 of them were the literal `103`.** The
task's "THREE WITNESSES" undercounted: `differ.py:243` and `sweep.py:212` are two more, and neither
is in this unit's scope. `AGENTS.md` itself was already right (139) and so was not a witness to 103 —
it was a witness to the *claim that the other two were stale*.

## 2. Derive, don't assert

`checks/no-txt.py`'s RUNTIME already derived the count: `len(excused)` where
`excused = found & graphcmp_artifacts()` and `graphcmp_artifacts()` reads `differ.declared()` by
imported path (`no-txt.py:87,93`). The only literals were in the MODULE DOCSTRING, which `main()`
never reads. I removed every literal count from that docstring rather than updating it to 139,
because **a docstring carrying the number is a third witness that can go stale** — the exact defect
class. No literal is now unavoidable anywhere: the printed number is `len(excused)`, computed.

## 3. Before / after — and NOTHING measured moved

| | EXCUSED | HARD | owned total | exit |
|---|---|---|---|---|
| before (inline, pre-edit) | 139 | 830 | 969 | 1 |
| after (`.agents/slop/notxt139/after.out`) | 139 | 830 | 969 | 1 |
| after re-run (`after2.out`) | 139 | 830 | 969 | 1 |

`diff -q after.out after2.out` → identical. **My change is prose-only and moved NONE of the three
counts**; the docstring is not on `main()`'s path, which is why the output is unchanged. A change
that prints a different number without changing what it measures would have been the worst outcome —
it did not happen.

**The `~258` HARD drop the brief warned about did NOT occur in my window**: HARD was 830 before and
830 after. Note the `553` HARD `AGENTS.md:39,112` reports is itself now stale (measured 830, owned
total 969) — that is the `oracles/` unit's number, not mine, and I did not touch it.

## 4. Plant: the derived number MOVES, proven and reverted

`checks/differ.py` is not mine, so the plant was a temporary edit restored from a byte copy
(`.agents/slop/notxt139/differ.py.orig`), with the hash as the proof.

1. original hash: `700ab4e17905f72af8ae18d1f5e8eea2e9b78d55e99d7025499298855c311909`
2. added `| {"PLANT-notxt139.txt"}` to `declared()` and created `runs/graphcmp/D/PLANT-notxt139.txt`
3. `no-txt.py` then printed **140 EXCUSED**, HARD stayed 830 — the new file moved from unexcused to
   excused exactly as the declared set grew
4. restored `differ.py` from the copy, removed the plant file
5. re-hash: `700ab4e…311909`, `diff -q differ.py differ.py.orig` → identical, `git status` shows
   `differ.py` unmodified, plant file absent, `no-txt.py` back to **139 EXCUSED / 830 HARD**

A derived number that could not move would be a literal wearing a function's name; this one moved.

## 5. What is NOT verified

`checks/README.md:58`'s claim "**all 139** are named by two or more instruments" is INHERITED from the
103-name revision, not re-measured here. I verified the population facts only: 139 declared, 139 on
disk, declared == on-disk. The "≥2 instruments" claim needs the oracle-name witness it always did.

ADJACENT and in my file: `checks/README.md:56` still cites `differ.py:58` as the pin, which
`AGENTS.md:84-85` corrects (`:61` is `ORACLE_PIN`, `:58` is a comment). Out of this task's scope (it
is a line citation, not the count) and left for the `differ.py`-owning unit to settle in one edit.

## 6. Exact replacement for `AGENTS.md:89-92`

Replace:

```
  else, and renaming them means the pin has to move with them in one commit. **THE 103 IN
  `checks/README.md:51-58` AND `checks/no-txt.py:19-30` IS STALE — this file, `checks/README.md` and
  `checks/no-txt.py` are THREE WITNESSES TO ONE SUPERSEDED NUMBER, SO FIX ALL THREE OR SAY WHY ONLY ONE
  IS AUTHORITATIVE.**
```

with:

```
  else, and renaming them means the pin has to move with them in one commit. **FIXED 2026-10-06: all
  THREE now carry 139 — `checks/README.md:51,53,55,58,75` say 139, and `checks/no-txt.py` no longer
  TYPES the count at all: its docstring DEFERS to `len(differ.declared())`, printed at runtime, so a
  stale literal there is now unrepresentable. TWO MORE WITNESSES REMAIN, OUT OF THIS UNIT'S SCOPE:
  `checks/differ.py:243` and `checks/sweep.py:212` still read "103", and their owners must move them —
  the denominator was FIVE files, not THREE.**
```

## Files this unit changed
- `checks/no-txt.py` — docstring literals removed; runtime unchanged.
- `checks/README.md` — 103 → 139 at `:51,53,55,58,75`.
- `.agents/slop/notxt139/` — this report, `after.out`, `after2.out`, `plant.out`,
  `differ.py.orig`, `differ.py.orig.sha256`.
