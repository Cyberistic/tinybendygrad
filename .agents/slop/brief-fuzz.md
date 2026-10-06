# THE FUZZ BRIEF

You are building a property-based differential harness for ONE Bend unit,
copying the TEMPLATE at `.agents/slop/tools/szfuzz.py` (read it first — it is
short and it works). Repo: `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.

## The shape (do not deviate)

    seeded generator -> CPython oracle (the unit's OWN python) -> one compiled
    run of the Bend unit per case -> diff -> next seed

- NO hand-written expectations anywhere. The oracle is the Python being ported.
- One counterexample is the finding: print seed + repro command, exit 1, stop.
- The generator must bias toward the EDGES the unit's hand fixtures never
  reached. Read the unit's port report (in the commit message and the file
  header) to find where its bugs lived, and target those shapes.
- `--seeds N --verbose`, small first: get 5 seeds green before running 50.
- The machine may be heavily loaded (other agents). Compile the unit ONCE with
  a long timeout (`subprocess.run(..., timeout=600)`), reuse the binary across
  seeds (the sz template's `--binary` flag shows how). Never sit in a tight
  compile loop.

## The driver: making the Bend unit fuzzable

The unit's `main` currently prints fixed gate rows. Add a driver branch:
`main` with no argument = the gate, UNCHANGED (every existing gate row must stay
green); `main` with one argument = read that case file, run the port, print ONE
canonical line (the same shape the oracle prints). `sz.bend`'s `main` already
reads an argument this way — copy that. Keep the driver THIN: parse, call the
existing port entry point, print. No new logic in the driver; if you need logic
to parse the case format, put it in small named defs.

Case format: one case per file, one line, a simple s-expr or `|`-separated
fields — whatever the unit's arena construction already speaks. Both sides
(build the same case independently) is the rule; do not serialize from one side
and hand to the other in a way that hides a construction bug.

## Gate discipline still applies

The fuzz harness is IN ADDITION to the unit's printed gate, not a replacement.
After your driver edit: `--check-only` green, both lanes of the gate still
print identically, and the printed gate rows unchanged.

## Report

- the property you encoded, in one line
- generator coverage: what shapes it produces that the hand fixtures did not
- seeds run, pass/fail; any counterexample with its repro
- any bug found in the UNIT (report precisely; you own the unit file for the
  driver edit ONLY — if the bug is beyond the driver, report it, do not fix
  silently)
- any bug found in the TEMPLATE (`szfuzz.py`) — report, do not edit szfuzz.py
- new general Bend rules go to `.agents/slop/notes/bend2-constraints.md`
  (append only)

Do NOT commit. Be honest about what is not done; a harness that found nothing
because the generator was too weak is a reportable negative, not a success.
