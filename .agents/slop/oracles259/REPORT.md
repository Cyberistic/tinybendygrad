# `oracles259/` — decision (DECIDED 2026-10-07 by `orcdecide`)

## What this directory is

The working directory of the **`oracles259` unit**: it censused the **259 `.txt` files under
`oracles/`**, classified each **by content** (not name), and proved a restore before the
`txtexec`/`notxt139` rename turned **258 of 259** into `.rows`/`.err`/`.md`/`.tsv`/`.bend`
(`dcd97943e`). The unit's report is **`ce24dd609`'s commit body** and **`MANIFEST.tsv`** — there
was never a `REPORT.md`, which is why the directory read as "retained by accident."

The `MANIFEST.tsv` is the artifact: **259 rows** = `path · sha256 · bytes · shape · disposition ·
why · restore · restore_at_HEAD` (188 `DELETE-CANDIDATE`, 34 `KEEP-ALIVE`, 37 `KEEP-DUPLICATE`;
249 `rowdump`, 7 `crash-dump-in-txt`, 3 `source-in-txt`). `1db00c1e6` added the `restore_at_HEAD`
column after finding the old `restore` column resolved **1/259** at HEAD.

## Verdict: SPLIT — keep the record, retire the workshop

21 tracked files, **2 live inputs, 19 residue**. Reader test: a tracked **code** file outside the
directory naming the file's **full path** (`git grep -l -F`). Full table in
`../orcdecide/VERDICTS.tsv`.

### KEEP (2)

| file | why |
|---|---|
| `MANIFEST.tsv` | The 259-row restore record. Opened by 9 code readers: `oraclerestore/{build,verify,prove,measure}.py`, `txt259/{restore_all,verify_restore}.py`, `txtexec/{digest_audit,fix_manifest2,restore_paths}.py`. |
| `census.json` | The committed 259-row **pre-rename** census. Imported by a **live** instrument, `.agents/slop/oracletxt/shape_of_stale.py:21`, which replays the STALE/ABSENT split from it. |

### RETIRE (19) — nothing opens them by path; superseded or one-time output

`plants.py` `classify.py` `manifest.py` `cited.py` `ordering.py` `othercopies.py`
`declared_join.py` `classified.json` `census.out` `gate.out` `classify.err`
`manifest-prove.out` `manifest-write.out` `ordering.out` `othercopies.json`
`bn.rows` `basenames.rows` `basenames2.rows` `paths.rows`

- `plants.py` — **superseded** by `.agents/slop/oracletxt/plant.py` (see `../orcdecide/REPORT.md` §3);
  it crashes at `plants.py:68` on renamed literals.
- `classify.py` — superseded by `checks/oracle-txt-census.py`.
- `manifest.py` — superseded by `.agents/slop/oraclerestore/build.py`.
- the rest — one-time outputs / stdout captures of the unit's own scripts.

**The `git rm --cached` list is in `../orcdecide/REPORT.md` §4. Not applied here.**

## The precedent this directory missed

`.agents/slop/strays/MANIFEST.tsv` is a tracked **6-column declaration**
(`arm · role · path · verdict · why · restore`) that let `prune3` audit `strays/` even with no
`REPORT.md` — *"the records it looked for exists under another name."* `oracles259/` had that
artifact all along; nobody declared **what the directory itself was for**. This file is that
declaration. See `../orcdecide/REPORT.md` §6 for the generalised guard.
