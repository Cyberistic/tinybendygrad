# The 16 ABSENT INSTRUMENTS — a census of which evidence still exists

Read-only census, 2026-10-06. Population: the rows of
`.agents/slop/toolsledger/paths.tsv` with `status=ABSENT` and `kind=INSTRUMENT`
(produced by `.agents/slop/toolsledger/extract.py`). One row per path in
`.agents/slop/lostinst/INSTRUMENTS.tsv`. Nothing was restored, moved or deleted.

**Denominator: 16** (extract.py's `kind()` basename regex). By CONTENT the true
count is **14 instrument files** — see §4, where two of the 16 turn out not to be
instruments.

---

## 1. The four states, counted

| state | count | which |
|---|---|---|
| **RECOVERABLE** | **14** | every one verified: `git cat-file blob <sha>` returns non-empty bytes |
| **GENERATED** | **0** | no absent instrument has a generator that writes it |
| **DUPLICATE** | **0** | no recovered blob is byte-equal to any file on disk (all 14 hashes distinct) |
| **GONE** | **1** | `.agents/slop/xd1/mutate.py` |
| not a path / not an instrument | **1** | `xd1/pin` (a pinned revision; see §4) |

Denominator 16 = 14 + 0 + 0 + 1 + 1.

**Every RECOVERABLE restore command resolves with non-empty bytes** — verified by
executing `git cat-file blob <sha>` for all 14 (`.agents/slop/lostinst/verify.py`);
sizes 110 B – 23,711 B, blobs all distinct. Each recovered path is *also* present
as a committed mirror copy under `.agents/slop/differverdict/{root,warm}/...` (and
`.agents/slop/dd-mirror/...`, `.jjconflict-*` for the `*mutate` ones). Those
mirrors are **copies in history, not on disk**; a copy is corroboration, never a
second witness, so the state is RECOVERABLE, not DUPLICATE.

## 2. RECOVERABLE (14) — bytes in git history

| path | blob | bytes | last commit holding it |
|---|---|---|---|
| `.agents/slop/cstyle-shapes-selftest.py` | `2d84b114e0cc…` | 8798 | `64b174c0abd5` |
| `.agents/slop/e2e_gpu_probe.mjs` | `1733e593348d…` | 6826 | `44713fe03b63` |
| `.agents/slop/fold-rng-mutate.py` | `c366ea73e4e8…` | 11695 | `cbd6005f0a41` |
| `.agents/slop/ga_mutate.py` | `13c5e0f2cc51…` | 15178 | `7fe55a5938b9` |
| `.agents/slop/mixin-op-mutate.py` | `0a20af04016a…` | 9305 | `2e577f8667fc` |
| `.agents/slop/nn-init-mutate.py` | `78bec34a9967…` | 6211 | `7fe55a5938b9` |
| `.agents/slop/pin-tables.py` | `79a3981dc87b…` | 10941 | `0acd87f1358a` |
| `.agents/slop/rf2-mutate.py` | `d469dc20c6a8…` | 13774 | `7fe55a5938b9` |
| `.agents/slop/runs/elf-checkonly-2026-10-04.txt` | `d5b616bbd602…` | 110 | `e64f30b5bb7c` |
| `.agents/slop/state-mutate.py` | `ea5a0652b2c0…` | 4598 | `7fe55a5938b9` |
| `.agents/slop/substrate-audit.py` | `e61dd6eb11fe…` | 14796 | `14eb322d7789` |
| `.agents/slop/tcptx-mutate.py` | `e0ac3181c709…` | 23711 | `3f3b786ed162` |
| `.agents/slop/tools/mutate-dm.py` | `68a4e41b4645…` | 5765 | `0056b78451f0` |
| `.agents/slop/tools/mutate-sz.py` | `01ce3f85863a…` | 6928 | `6e738cbffc34` |

Full SHAs and per-path restore commands are in `INSTRUMENTS.tsv`.

## 3. GONE (1) — and it is named out loud

**`.agents/slop/xd1/mutate.py` is GONE.** Evidence:
- No commit in any ref touches the exact path: `git log --all --diff-filter=A -- '*mutate.py'`
  lists every added `mutate.py` and **never `xd1/mutate.py`**.
- All 75,336 distinct paths in all history (`.agents/slop/lostinst/histpaths.py`)
  contain **no path matching `xd1/mutate.py`**, in any mirror
  (`.agents/slop/dd-mirror/`, `.agents/slop/differverdict/{root,warm}/`, `.jjconflict-*`).
- The `.agents/slop/xd1/` directory is `.gitignore`d, so nothing under it was ever
  committed.
- The other `mutate.py` files in history (`.agents/slop/mutate.py`, `probe/mutate.py`,
  `wip/mutate.py`, …) are a **different, generic** mutation runner — not this one.

It is not GENERATED (the two "generator" hits a naive scan finds are prose:
`.agents/slop/dd-mut-base.sh:80` reads *"dd-mutate.py RULE E"*, not `xd1/mutate.py`),
not DUPLICATE, no blob. **Its instrument is gone; the claim it carried is dead.**

## 4. Two of the 16 are not instruments — the extractor's `kind()` is a basename shape

`extract.py:34` classifies by `re.search(r'(gate|check|…|pin|…)', basename)`. That
is a **basename shape**, the thing doctrine 1 forbids, and it produces two false
positives here:

- **`xd1/pin`** — not a file anywhere. It resolves to the directory
  `.agents/slop/xd1/pin/` (a checkout of the pinned bend revision; `AGENTS.md`,
  `README.md`, `spec/`). `TOOLS.md:645` says `` `xd1/pin` = `6c3d401cf324` ``, and
  `git cat-file -t 6c3d401cf324` returns **`commit`** — the token names a revision,
  not a missing instrument. `kind()` matched the bare word `pin`.
- **`.agents/slop/runs/elf-checkonly-2026-10-04.txt`** — a **captured stdout**
  (content: `ALL PROOFS CHECK` / `done rc=0`, 110 B). It is EVIDENCE, not an
  instrument; `kind()` matched the substring `check` inside `checkonly`.

So **14** of the 16 are instrument files (13 RECOVERABLE + 1 GONE), **1** is a
stream (RECOVERABLE) and **1** is a revision reference. A basename regex cannot
tell an instrument from a stream or a revision.

## 5. What each instrument's evidence carried, and whether the claim is live

An instrument nobody cites is different from one a **live** claim rests on. Cited
by a present script (live) vs cited only in `TOOLS.md`/`TODO.md` prose:

| instrument | claim | live referrer (present file) |
|---|---|---|
| `cstyle-shapes-selftest.py` | cstyle gate's reader reaches RED on every row shape | `cstyle-gate.py:192`, `reader-guard.py:164` |
| `e2e_gpu_probe.mjs` | "is there a device that [renders]" — the adapter is probed, not assumed | `e2e_negctl.sh:48` (runs it), `e2e_mm_run.mjs:13` |
| `ga_mutate.py` | 41 mutations of `renderer/amd/generate.bend`, 40 move gate rows | `zero-audit.py:49`, `table-pin.py:61` |
| `rf2-mutate.py` | the rf2 mutation table | `zero-audit.py:67`, `table-pin.py:67`, `formblind-census.py:114` |
| `substrate-audit.py` | 4 instruments right about form, wrong about the substrate | `formblind-census.py:439` SELF set |
| `pin-tables.py` | WRITES the pin into each table; "a pin is a claim about a run" | tables in the tree read "Written by pin-tables.py, 2026-10-04" |
| `fold-rng-mutate.py` | 19 mutations of the ranges fold; 15 move rows | prose only (`TOOLS.md:731`, `TODO.md:852`) |
| `mixin-op-mutate.py` | 17 mutations of `mixin/op.bend`; 4 of 17 zero | prose only (`TOOLS.md:50`) |
| `nn-init-mutate.py` | one-token mutations of the `nn/` files; M14 = control | prose only (`TOOLS.md:53`) |
| `state-mutate.py` | one-token mutations of `nn/state.bend`; M12 = control | prose only (`TOOLS.md:53`) |
| `tcptx-mutate.py` | 51 mutations of `renderer/tc_ptx.bend`; 4 controls | prose only (`TOOLS.md:55`) |
| `tools/mutate-dm.py` | one edit to `uop/divandmod.bend`, restores the file | prose only (`TOOLS.md:42`) |
| `tools/mutate-sz.py` | one edit to `tinybendygrad/sz.bend` | prose only (`TOOLS.md:45`) |
| `xd1/mutate.py` **(GONE)** | 13 one-edit reverts of the xd1 fixes | `TODO.md:3424` (prose; no present script runs it) |
| `runs/elf-checkonly-…txt` | recorded stdout of `bend elf.bend --check-only` | prose only (`TOOLS.md:628`) |
| `xd1/pin` | the pinned revision `6c3d401cf324` | prose only (`TOOLS.md:645`) |

Five instruments are named by a **present, runnable** script; the rest are cited
only in prose. **None of the 16 is invoked by a `checks/` or `gates/` script**
(measured: `rg --fixed-strings <basename> checks gates` returns nothing runnable
for all 16). One — `nn-init-mutate.py` — is *named* inside the recorded gate dump
`checks/census.json:5452` ("THE MUTATION TABLE, MEASURED, by
`.agents/slop/nn-init-mutate.py`"), which is data, not an invocation. The 16 are a
`.agents/slop/` toolchain cited by `TOOLS.md`/`TODO.md` and by five present
`.agents/slop/` scripts.

## 6. Cross-check: which RULE produces which number, and can each see the 16?

I reproduced each rule (`.agents/slop/lostinst/crosscheck.py`) rather than argue:

| rule | distinct | absent | absent INSTRUMENTS | of the 16 seen |
|---|---|---|---|---|
| **A** backticked token containing `/` (extract.py) | **333** | **173** | **16** | **16 / 16** |
| B backticked + known extension (my whitelist) | 275 | 144 | 15 | 15 / 16 |
| B′ backticked + any `.ext` | 277 | 146 | 15 | 15 / 16 |
| C whitespace + known extension | 265 | 126 | 14 | 14 / 16 |
| D whitespace, any `/` | 347 | 182 | 15 | 15 / 16 |

- **333 / 173 / 16** is rule A, and it is the one that names all 16. Reproduced
  exactly today.
- **322 / 195** (and the brief's **321**) is "backticked + must end in a known
  extension" per `.agents/slop/toolsledger/REPORT.md` §2. **I could not reproduce
  322**: my extension whitelist gives 275, an any-extension rule 277. The gap is the
  extension set, which no artifact records. 321 is one token from 322.
- **213 / 99** is "whitespace + known extension, leading dots stripped" per that
  same §2. **I could not reproduce 213 either**: stripping leading dots gives
  265/229 (known ext) or 266/127 (any ext). Stated as unresolved; what would settle
  it is the exact normalizer + extension whitelist of that run, which is not
  committed.
- **The 16 appear in ALL THREE only under rule A.** Every extension-gated rule
  drops **`xd1/pin`** (it has no extension) and, at rule C, also the `.txt` stream.
  So the `321`/`213` corpora are *structurally blind* to `xd1/pin` — the doctrine-1
  failure the whole exercise is about, reappearing in the population census itself.

The 16 rest on `kind()` (a basename regex) *and* on rule A. Rule A sees them; the
extension rules cannot. Neither `kind()` nor rule A can tell an instrument from a
stream or a revision (§4).

## 7. Exact AGENTS.md replacement sentence

`AGENTS.md` has already been edited to carry "173 of the 333 paths … gone, 16 of
them INSTRUMENTS". That 16 is `kind()`'s number, and §4 shows it is 2 too high.
Replace the clause:

> **173 of the 333 paths `.agents/TOOLS.md` names are gone, 16 of them INSTRUMENTS.**

with:

> **173 of the 333 paths `.agents/TOOLS.md` names are gone; `extract.py`'s `kind()`
> calls 16 of them INSTRUMENTS, but BY CONTENT only 14 are: 13 are RECOVERABLE
> (git blobs named in `.agents/slop/lostinst/INSTRUMENTS.tsv`) and **one —
> `.agents/slop/xd1/mutate.py`, in the `.gitignore`d `.agents/slop/xd1/` — is
> GONE**, with no blob, generator or copy in any ref. The other two are the
> classifier's own errors: `.agents/slop/runs/elf-checkonly-2026-10-04.txt` is a
> captured stdout and `xd1/pin` names the pinned revision `6c3d401cf324`, not a
> file — `kind()` is a basename regex, so it cannot tell an instrument from a
> stream or a revision.**

## 8. Not settled

- The exact rules behind **321** and **213/99** are not reproducible from any
  committed artifact (extension set + normalizer unrecorded). §6 says so.
- Whether `.agents/slop/xd1/mutate.py`'s bytes survive in a **jj** operation log or
  a filesystem backup — I searched git refs only. What would settle it: a jj
  op-log walk (`jj op log` / `jj evolog`) or a Time Machine snapshot of
  `.agents/slop/xd1/`.

## Reproduce

```
.venv/bin/python .agents/slop/lostinst/census.py      # states + blobs + restore cmds
.venv/bin/python .agents/slop/lostinst/verify.py      # restore commands -> non-empty bytes
.venv/bin/python .agents/slop/lostinst/histpaths.py   # copies/mirrors in all history
.venv/bin/python .agents/slop/lostinst/crosscheck.py  # the rule table of §6
.venv/bin/python .agents/slop/lostinst/build_tsv.py   # emit INSTRUMENTS.tsv
```
