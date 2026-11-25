"""symbolic-table-gate.py -- is `symbolic.bend`'s rule TABLE still CPython's rule table?

    .venv/bin/python gates/symbolic-table-gate.py

A `PMEntry` is `{tag, ops, rej}`: the ops the root may be, and the ops that must appear among
its SOURCES. CPython derives both from the `UPat` itself -- `p.op` and `p.early_reject`
(`tinygrad/uop/ops.py:1554`, `entry=[p, None, p.early_reject]`) -- so the table is not a
transcription at all. It is a PROJECTION of `sym.patterns`, and this gate projects it.

THE POPULATION IS THE ORACLE'S OWN DECLARATION (doctrine 1a). Nothing here is typed: the
oracle side is `tinygrad.uop.symbolic`'s matcher objects, and the port side is PARSED out of
`tinybendygrad/uop/symbolic.bend`'s `*_table()` defs, with the macros expanded from that
file's own `def OP_*` bodies.

`sym` AND NOT `symbolic`, AND THE DIFFERENCE IS NOT COSMETIC: the file composes

    sym = symbolic + pm_simplify_valid + PatternMatcher([...]) + pm_clean_up_group_sink

so `symbolic` is only the FIRST of four matchers `sym` sums (119 of 133). A comparison
against `symbolic` reported the last 14 rows as unpaired when they are simply the next
matcher's, which is the shape of false positive this gate exists to avoid, committed here
once so the next reader does not repeat it.

THREE TABLES, THREE DIFFERENT CONTRACTS:

  sym_table     DISPATCHED, so its `rej` matters -- compared in full against `sym` minus
                `pm_simplify_valid`'s two rows, which the port routes elsewhere.
  rm_table      DISPATCHED (`rm_rewrite`), compared in full against `pm_remove_invalid`.
  valid_table   A LEDGER, NOT A DISPATCH. `symbolic.bend:5909` reads ONLY `valid_table()`'s
                LENGTH -- it is added to `sym_table`'s so the port can report CPython's 133
                while two rules are unported (`symbolic.py:450`, `:451`, and the comment at
                `symbolic.bend:5914` says so). A `rej` hazard there would be a FALSE POSITIVE:
                a table nobody consults cannot skip a rewrite. Ops only.

THREE WAYS A HAND-COPIED ROW GOES WRONG, AND THEY ARE NOT THE SAME SEVERITY:

  OPS      the row claims a different op set, so the rewrite fires on the wrong nodes.
  HAZARD   the row's `rej` demands an op upstream does not. `early_reject` is a NECESSARY
           condition (`ops.py:1564`, `if not early_reject.issubset(ler): continue`), so
           demanding MORE than upstream means the port SKIPS a rewrite CPython performs.
           This is the silent one: node counts do not move, the graph is just less rewritten.
  NARROW   the row's `rej` is a SUBSET of upstream's. Harmless by construction -- the body
           still answers `None` -- so it is COUNTED, not failed: dropping a fast path costs
           time, it does not change an answer.

`rej` is compared with `<=` and not `==` for exactly that reason. An `==` here reports 72
harmless rows as failures and buries the ones that matter.

THE THREE ROWS THIS GATE FOUND, ALL NOW FIXED (2026-11-25). Each was a `rej` that named
`CONST`, and each body's own guard is what said the row was wrong:

  tag 2  (`symbolic.py:91`, the Invalid-moves-inside-the-gate rule) demanded `CONST` while
         its `UPat` src is `invalid_gate`, a `WHERE`. `sym_84.pat` reads `p_where_gate(x,u,0)`
         -- the body wants a WHERE at src 0 -- so with `{CONST}` the entry could NEVER fire
         and the rule was dead. Now `[O.OpsWHERE{}]`.
  tag 12/13 (`:108`/`:110`, fold gated STORE/LOAD) demanded `CONST` while upstream requires
         nothing (`early_reject=[]`) and the test lives in the src pattern, `INDEX.or_casted()`,
         which a disjunction cannot put in `early_reject`. Bodies `sym_101`/`sym_103` carry
         that test in `p_index_bad_or_cast`. Now `Nil{}`.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pmtable  # noqa: E402  (the projection lives in one place, not once per table)
from gatekit import DEAD, FAIL, PASS  # noqa: E402  (house vocabulary, never re-spelled)

ROOT = pathlib.Path(__file__).resolve().parents[1]
PORT = ROOT / "tinybendygrad/uop/symbolic.bend"

# (port table, oracle matcher, matcher whose rows the port routes elsewhere, does `rej` bind?)
PAIRS = (("sym_table", "sym", "pm_simplify_valid", True),
         ("rm_table", "pm_remove_invalid", None, True),
         ("valid_table", "pm_simplify_valid", None, False))


def main() -> int:
    text = PORT.read_text()
    mac = pmtable.macros(text)
    if not mac:
        print("== DEAD: symbolic-table-gate: no `OP_*` macro parsed -- every row would read as "
              "an empty op set and agree with nothing")
        return DEAD

    import tinygrad.uop.symbolic as sym

    bad = 0
    for tname, mname, ename, rej_binds in PAIRS:
        port = pmtable.table(text, tname)
        matcher = getattr(sym, mname, None)
        if not port or matcher is None or not matcher.patterns:
            print(f"== DEAD: symbolic-table-gate: `{tname}` parsed {len(port)} rows and "
                  f"`{mname}` declares {len(getattr(matcher, 'patterns', []))} -- one side is "
                  "empty, so nothing was compared")
            return DEAD
        # `sym` sums matchers whose `UPat` objects are SHARED (`__add__` concatenates the
        # lists and `__init__` rebuilds only the tuples), so the exclusion is by UPat identity.
        ex = {id(p) for p, _ in getattr(sym, ename).patterns} if ename else set()
        up = [p for p, _ in matcher.patterns if id(p) not in ex]
        r = pmtable.pair(port, up, mac, rej_binds)
        print(f"{tname}: oracle={mname}{'\\' + ename if ename else ''} rows={r['rows']} "
              f"port={r['port']} paired={r['paired']} "
              f"narrow={r['narrow']} hazard={len(r['hazard'])} ops={len(r['ops'])} "
              f"order={len(r['order'])}" + ("" if rej_binds else "  (rej not bound: ledger)"))
        for label in ("order", "ops", "hazard"):
            for line in r[label]:
                print(f"  {label.upper()} {line}")
        bad += len(r["ops"]) + len(r["hazard"]) + (r["port"] != r["rows"])

    if bad:
        print(f"== FAIL: symbolic-table-gate: {bad} row(s) disagree with CPython or are unpaired")
        return FAIL
    print("== PASS: symbolic-table-gate: every dispatched row carries CPython's op set, no row "
          "demands an early-reject op CPython does not, and no rule is unaccounted for")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
