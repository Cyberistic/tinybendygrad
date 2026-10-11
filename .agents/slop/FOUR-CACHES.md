# FOUR CACHES, AND THE INSTRUMENT READS THE ONE THAT IS GITIGNORED

**MEASURED 2026-10-11 05:0x. Three caches of the one 34-graph corpus exist. The gate built to answer
"which is authoritative" reads the one that nothing in the tree owns.**

| location | files | gitignored | tracked | content vs live | slots with a key |
|---|---|---|---|---|---|
| `checks/rows-<g>-<s>.rows` — **what `census.py:133` opens** | 69 | **YES** | **0** | matches | **2 of 68** |
| `checks/rows/rows-<g>-<s>.rows` — published | 68 | no | **68** | matches | census never reads it |
| `oracles/rows-<g>-<s>.rows` | 54 | no | tracked | **stale** | no generator at all |

`.gitignore:167` is `checks/rows-*.rows`. **That one line is what makes the gate's own population
invisible.** On this tree: **28,411 ignored, 4 untracked non-ignored — a ratio of ~7,000:1**, and the
prescription in `AGENTS.md` that ignored is "~200x untracked" is now off by more than an order of
magnitude. `git ls-files --others --exclude-standard` is the only correct "what does nothing own"
question, and it returns **0** for all 69 — so every sweep tonight that asked it reported them clean.

## `census.py`'s `rc=3` is HONEST, AND ITS REASON IS THE DEFECT

`checks/rows-key.rows` holds **2 rows** — `flip py`, `flip bend` — and their sha256 is
`2e180103…`, which is the **current** `graphcmp.bend`. So the keying works. **66 of 68 slots have no
key, so the gate cannot say they are current, so it refuses** (line 136: `return ("STALE", 0, None,
set())  # served NOTHING, and 0 here is "not counted"`). **That is `whosecache`'s own rule applied
correctly: authority needs BOTH halves of the generator — the write path AND the ability to say the
slot is stale.**

**And the key file is gitignored by the SAME LINE, so a cache that cannot say it is current can never
learn to.** The refusal is self-sealing.

## I made `whosecache`'s named mistake thirty seconds after being told it

I ran a hand census comparing cached bytes to a live generation and reported **"0 of 68 slots differ
— the corpus is current."** That is **content resemblance**, and the report I had just landed says in
its own words: **"Content resemblance is not authority."** I read a question the instrument exists to
answer and answered a different one, then treated the cleaner number as the finding. **A number that
looks clean because it compared something other than the subject.**

The correct reading is the gate's: the corpus *may* be current, and **nothing in the tree can say so.**

## THE FIX, AND IT IS NOT "REFRESH THE CACHE"

The tracked, published set — `checks/rows/`, 68 files, which I regenerated this session to 34 of 34
byte-identical — **is never read by the instrument built to answer this question.** The refusal would
be true and actionable if the gate read the tracked set and keyed it. It reads a sibling path
distinguished only by a trailing `/`, and that sibling is invisible to git.

**Either the gate keys the TRACKED set, or the key file stops being gitignored.** The first is
correct: a published set that is in the tree must be the set that can be checked.