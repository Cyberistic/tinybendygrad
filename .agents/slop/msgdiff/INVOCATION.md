msgdiff-invocation: **THE MODE SIGNATURE IS `range`/`check` (POSITIONAL SUBCOMMAND), NOT `--range`/`--check`, AND `revs_for`
TAKES RAW `git rev-list` ARGS.** A CALLER WHO GUESSES `--range ... HEAD` GETS `unknown mode '--range'` (rc=4 SKIP) OR, WITH
`--since=`, A `DEAD` (rc=5) FROM `git rev-list` — **AND A GATE THAT RETURNS SKIP OR DEAD WHEN MIS-CALLED IS INDISTINGUISHABLE
FROM ONE THAT IS MIS-CONFIGURED.** The correct invocations, MEASURED:

    .venv/bin/python gates/msgdiff-gate.py range --since='2026-10-06T12:00' HEAD
      -> "range: 148 commits -- 147 PASS, 1 REFUSED"  rc=3   (the one real defect)
    .venv/bin/python gates/msgdiff-gate.py check HEAD
      -> "PASS: HEAD -- 0 deletion claims checked, 2 uncheckable (pids=0, counts=unfalsifiable, meta=0)"  rc=0
    .venv/bin/python gates/msgdiff-gate.py --plant   -> rc=0   (six states)

**BECAUSE THIS IS A REAL FINDING ABOUT THE INSTRUMENT AND NOT ABOUT ITS ARGS: THE HEADER ENUMERATES WHAT IT CANNOT SEE, BUT
NOT HOW TO CALL IT, SO THE FIRST CALLER GUESSES.** Recorded here rather than in a doc nobody reads, because
**`AGENTS.md`: a gate's invocation is part of its contract, and a contract with no CLI is a gate that will be run wrong once.**