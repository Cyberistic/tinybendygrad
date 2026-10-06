# TOOLS.md ledger — population census, 2026-10-06

## 1. The population, discovered from the file

Generator rule (authoritative, in `.agents/slop/toolsledger/extract.py`):
every **backtick-quoted token containing `/`**, normalized — markdown
emphasis (`*_[]()` and stray backticks) stripped, trailing punctuation
stripped, a leading `./` stripped, URLs and `git@` excluded, tokens with
whitespace/`$`/`::` excluded. Classified PRESENT iff the path exists on disk
OR appears in `git ls-files` OR a tracked file lives under it (directory);
otherwise ABSENT. No `git check-ignore` was used.

Measured today: 2319 backtick spans in the file, 333 distinct path tokens,
of which **160 present** and **173 absent**; 96 of the absent sit under
`.agents/slop/`. Denominators: 333 distinct paths extracted; 1543 lines
total; 373 lines name ≥1 path token.

## 2. Why other extractions give 213 or 321

Same file, same disk, three other rules:

| rule | distinct | absent | absent under `.agents/slop/` |
|---|---|---|---|
| backticked, `/`, any extension (mine) | 333 | 173 | 96 |
| backticked, `/`, must end in a known file extension | 322 | 195 | 96 |
| whitespace token, `/`, must end in a known extension | 273 | 136 | 94 |
| whitespace token, any `/` | 506 | 340 | 127 |

So the axes that move the number are: **backtick vs any whitespace token**
(prose mentions of paths, command lines, and table cells without backticks),
**extension whitelist vs any `/`** (pulls in relative fragments like
`uop/divandmod.bend`, URLs, `/tmp/...`), and **duplicates vs distinct**
(364 duplicate-kept backtick+extension tokens vs 322 distinct). Brief's
"321" is one edit away from the 322 whitelisted-backtick count, and "213"
from a whitespace+extension ABSENT count measured in a buggy state (leading
dots stripped, which mislabels every dotfile); neither survives a fixed
normalizer. The pair disagrees on direction and denominator because the two
authors ran two different rules and both cited the absent count as "the
count of paths".

## 3. Instruments vs oracles vs evidence (declared rule)

INSTRUMENT = basename matches the project's runnable-verdict vocabulary
(`gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|no-txt|substrate`).
ORACLE = basename contains `oracle` or `arena`. Everything else is EVIDENCE
(notes, `.rows`, data, docs, binaries).

Measured: 173 absent overall = **16 absent INSTRUMENTs, 17 absent ORACLEs**,
141 absent evidence/other. The 16 absent instruments are the live cases of
"a rule nobody can run" — e.g. `.agents/slop/state-mutate.py`,
`.agents/slop/nn-init-mutate.py`, `.agents/slop/tcptx-mutate.py`,
`.agents/slop/mixin-op-mutate.py`, `.agents/slop/tools/mutate-dm.py`,
`.agents/slop/tools/mutate-sz.py`, `.agents/slop/pin-tables.py`.
Full list: `.agents/slop/toolsledger/paths.tsv`.

## 4. What I changed

`.agents/TOOLS.md` gains one section, "This ledger is measured, not
remembered", naming the extractor and today's counts. Nothing was deleted:
absent entries are the record of deletions.
`.agents/slop/toolsledger/extract.py` + `paths.tsv` are the generator and
its output table; re-run the former to refresh the latter.

## 5. AGENTS.md correction (REPORT ONLY — not applied)

Replace: *"Of the 213 paths `.agents/TOOLS.md` names, **99 are gone**."*

With: *"Extracting every backtick-quoted path token from `.agents/TOOLS.md`
and testing each against disk and `git ls-files` (measured 2026-10-06 by
`.agents/slop/toolsledger/extract.py`): **333 distinct paths, 160 present,
173 absent, 96 of the absent under `.agents/slop/`, and 16 of the absent
are instruments (a rule's would-be enforcer), 17 are oracles**. The
extraction rule, not the number, is the thing to keep: it is re-runnable,
which is why the count now lives in the file it measures."*
