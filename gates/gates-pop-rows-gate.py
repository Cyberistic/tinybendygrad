#!/usr/bin/env python3
"""gates-pop-rows-gate.py -- WHAT A LEDGER ROW IS, and whether the live one still conforms.

    .venv/bin/python gates/gates-pop-rows-gate.py

THE LEDGER HAS NO STATEMENT OF WHAT A ROW IS. MEASURED 2026-10-19T16:42Z: byte 0 of
`gates/gates-pop.ledger.tsv` is the `p` of `path`, and `grep -c '^#'` over it answers 0. The
definition exists -- `gates/gates-pop.py` states "A ROW IS NOT A CLAIM THAT A GATE EXISTS. IT IS A
RECORD OF A GATE THAT WAS DISCOVERED" -- and `write_ledger` prepends it as `LEDGER_PREAMBLE`.
**THE PREAMBLE IS NOT ON DISK, SO THE LIVE LEDGER PREDATES THE WRITER THAT EMITS IT**, and a reader
of the file alone cannot tell a discovery from a claim, or a tombstone from a gate.

**THIS GATE DOES NOT WRITE THE LEDGER, AND THAT IS THE POINT.** Writing it would run
`--write-ledger`, whose writer MERGES the rows it finds against the rows it reads: the tool absorbs
whatever drift the tree held and the file comes back green without one gate having been measured. A
prior unit MEASURED that write on a COPY (`224 -> 262 row(s), 1 retired, none dropped`) and DECLINED
to apply it, and that was right. **A CLEANUP THAT RUNS THE GENERATOR IS NOT A CLEANUP, IT IS A
SECOND MEASUREMENT PRESENTED AS A FIRST.** So this file reads, and REPORTS the missing preamble as
a NAMED STATE instead of quietly supplying it.

WHAT A ROW IS -- the sentence the file itself does not contain:

  A row is a RECORD OF A GATE THAT WAS DISCOVERED, not a claim that a gate exists. One row is one
  TAB-separated quintuple: <path> <reason> <root_const> <asserts_root> <on_root>.

  `reason` is the word the census classified the file by. `asserts_root` and `on_root` are BOOLEANS
  the census DECIDED, and they are the substance of the row.

  `root_const` IS NOT AN OBSERVATION. It is a whitespace-flattened, width-truncated PREFIX OF THE
  GATE'S OWN SOURCE TEXT -- a quotation, and a truncated one: MEASURED, it reads
  `Path sys.path.insert(0, str(Path(__file__).resolve().parents[1]`, an unclosed paren. **IT IS NOT
  COMPARED**: `gates-pop.DECIDED` is the predicate the ledger diff uses, and it excludes it.

  A row whose `reason` is `gone` is a TOMBSTONE -- a record that a gate LEFT the population. It is
  kept and never erased, and it is not a claim about a gate that is here. **A ROW RECORDING A
  DEPARTURE IS NOT A ROW CLAIMING A GATE.**

EVERY VOCABULARY BELOW IS LOADED FROM `gates-pop.py` BY PATH -- `LEDGER_HEADER`, `RETIRED`, `DECIDED`,
and its own `read_ledger`. A HAND LIST OF REASON WORDS WOULD BE A POPULATION DECLARED BY SPELLING,
which is the class of defect this gate exists beside, and it would rot with no generator to move it.

THE FIVE VERDICTS COME FROM `gates/gatekit.py` (`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`),
because a shared NUMBER is not a shared VOCABULARY unless both sides import the same one. This file
is NOT a `gatekit.Gate`: that shape is a `.bend` driver diffed against a CPython oracle, and a TSV
conformance check has neither a driver nor an oracle. Inventing an oracle for it would be a fake
lane wearing a real lane's name.

**IT NEVER WRITES. THERE IS NO OPEN-FOR-WRITE IN THIS FILE**, and that is asserted structurally
rather than promised: `_preamble` and `conformance` take the ledger's text as an argument and the
only path this module touches is one it reads.
"""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # `gates-pop.py` and `gatekit.py` are siblings and hyphenated
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402


def _load_gates_pop():
    """`gates/gates-pop.py` BY PATH. Its name has a hyphen, so `import` cannot reach it and the
    only honest route is `spec_from_file_location`. Registering it in `sys.modules` first is what
    lets its own `from gatekit import ...` resolve against THIS `gatekit` rather than a second one."""
    spec = importlib.util.spec_from_file_location("gates_pop", HERE / "gates-pop.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["gates_pop"] = mod
    spec.loader.exec_module(mod)
    return mod


POP = _load_gates_pop()
LEDGER = HERE / "gates-pop.ledger.tsv"
PREAMBLE_STATE = ("not-measured",)  # set by `main`; the summary line reads it, and a fact that is
                                   # printed mid-report and absent from the summary is unread


def preamble(rows_text):
    """`(state, detail)`. THREE states and no fourth, because a ledger with no preamble is not a
    gate that could not run -- it is a FILE FACT, and naming it is the whole job here.

        PREAMBLE-PRESENT  the generator's own `#` block is on disk
        PREAMBLE-ABSENT   byte 0 is a data byte; the live file predates the writer that emits one
        NO-LEDGER         there is nothing to state anything about
    """
    if not rows_text.strip():
        return "NO-LEDGER", "the ledger is empty or missing"
    first = rows_text.splitlines()[0]
    if first.startswith("#"):
        return "PREAMBLE-PRESENT", f"{sum(1 for l in rows_text.splitlines() if l.startswith('#'))} `#` line(s)"
    return "PREAMBLE-ABSENT", f"byte 0 is {first[:1]!r} of {first.split(chr(9))[0]!r}, not `#`"


def conformance(data_lines, rows):
    """`(code, complaints)`, checking the RAW TEXT and not `read_ledger`'s return.

    **THIS CHECKS THE DISK, AND THAT IS THE WHOLE POINT.** MEASURED 2026-10-19T16:52Z,
    `gates-pop.read_ledger` coerces with `f[3] == "1"`, so `True`, `garbage`, `` and `0` ALL read
    back as `False` -- and the row is indistinguishable from a well-formed one either way. **A
    READER THAT COERCES CANNOT REPORT WHAT IT COERCED, AND `asserts_root=False` IS A CLAIM --
    "this gate does not assert its root" -- SO A CORRUPTED COLUMN READS AS A DECISION.** An
    earlier draft of this gate checked `isinstance(v, bool)` and therefore could not fail on a
    malformed boolean at all; that is the failure this comment exists to prevent.

    The canonical spelling is ASKED OF THE GENERATOR rather than written here: `ledger_line` is
    called on a row and its columns 4 and 5 are the two spellings this gate accepts. A hand list
    of `'0'`/`'1'` would be a format contract with no generator behind it."""
    bad = []
    live = [r for r in rows if r[1] != POP.RETIRED]
    tombs = [r for r in rows if r[1] == POP.RETIRED]
    # THE CANONICAL SPELLING, ASKED OF THE GENERATOR **FOR BOTH BOOLEAN VALUES**. An earlier draft
    # derived it from `rows[0]` -- which is just THE FIRST ROW'S OWN VALUES, so every row was being
    # compared against row 0's booleans and 42 of 224 "failed" a rule that does not exist. **A
    # CANONICAL SPELLING TAKEN FROM ONE SAMPLE IS NOT A CANONICAL SPELLING, IT IS A COMPARISON
    # AGAINST ROW ZERO.** Calling `ledger_line` on both booleans enumerates the whole set, because
    # `ledger_line` writes `int(...)` and `int` over `(False, True)` is exactly `{0, 1}`.
    canon = set()
    for a, o in ((False, False), (False, True), (True, False), (True, True)):
        canon.update(POP.ledger_line(("x", "r", "q", a, o)).split("\t")[3:])
    for line in data_lines:
        f = line.split("\t")
        if len(f) != 5:
            bad.append(f"{f[0] if f else '?'}: {len(f)} field(s), the header declares 5 -- "
                       f"`read_ledger` DROPS a short row silently (`if len(f) >= 5`), so this line "
                       f"is invisible to the census that reads it")
            continue
        for name, v in zip(("asserts_root", "on_root"), f[3:]):
            if v not in canon:
                bad.append(f"{f[0]}: {name}={v!r}, outside {sorted(canon)} -- `read_ledger` would "
                           f"have read this as {v == '1'}, indistinguishable from a real "
                           f"{canon and min(canon)}")
    quoted = sum(1 for r in rows if len(r) == 5 and r[2] not in ("-", ""))
    sample = POP.DECIDED(rows[0][1:]) if rows else ()
    print(f"ROWS      {len(rows)} row(s) over {len(data_lines)} data line(s): {len(live)} live, "
          f"{len(tombs)} tombstone(s) reason={POP.RETIRED!r}. A tombstone is a RECORD that a gate "
          f"LEFT, not a claim about a gate here.")
    print(f"SPELLING  the generator's own, from `ledger_line` over both booleans: {sorted(canon)}"
          f" -- anything else reads back as False")
    print(f"DECIDED   the ledger diff compares {len(sample)} column(s) {sample!r} of a 5-field "
          f"row -- and NOT the quotation.")
    print(f"QUOTED    {quoted} row(s) carry a root_const, and it is EXCLUDED: a truncated prefix "
          f"of the gate's own source, not an observation.")
    return (FAIL if bad else PASS), bad


def main():
    if not LEDGER.exists():
        print(f"gates-pop-rows-gate: NO LEDGER at {LEDGER.name} -- nothing to state a row about")
        return REFUSED
    text = LEDGER.read_text()
    state, detail = preamble(text)
    global PREAMBLE_STATE
    PREAMBLE_STATE = (state,)
    print(f"PREAMBLE  {state}: {detail}")
    if state == "NO-LEDGER":
        return REFUSED
    body = [ln for ln in text.splitlines() if ln and not ln.startswith("#")]
    hdr_ok = bool(body) and body[0] == POP.LEDGER_HEADER
    print(f"HEADER    {'matches' if hdr_ok else 'DOES NOT MATCH'} the generator's "
          f"LEDGER_HEADER ({POP.LEDGER_HEADER!r})")
    data = body[1:]
    rows = POP.read_ledger(LEDGER) or []
    # DEAD IS "THERE WAS NOTHING TO COMPARE". A data line that `read_ledger` DROPPED is not
    # nothing -- it is a line the census cannot see -- so the emptiness is decided on the RAW
    # lines and the dropped-line complaint comes from `conformance`, which still sees them.
    if not data:
        print("ROWS      no data line after the header -- COMPARED NOTHING, which is DEAD, "
              "not PASS")
        return DEAD
    code, bad = conformance(data, rows)
    for b in bad:
        print(f"  BAD ROW {b}")
    if not hdr_ok:
        code = FAIL
    return code


if __name__ == "__main__":
    rc = main()
    # THE VERDICT LINE CARRIES THE PREAMBLE STATE, not just the exit. A fact printed mid-report and
    # absent from the summary is the defect this file was written beside: `root_const` moved the
    # ledger diff for five files and the only number a reader took away was "5 changed".
    print(f"gates-pop-rows-gate: a row is a RECORD of a gate that was DISCOVERED "
          f"[{PREAMBLE_STATE[0]}]" if rc == PASS else f"gates-pop-rows-gate: {VERDICT.get(rc, rc)}")
    sys.exit(rc)