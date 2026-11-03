census: the four STORE rows were cited one rule apart; `:471` added (132 PORTED / 0 BROKEN / 3 MISSING)

Four rows all claim `Ops.STORE`, and all four were cited ONE RULE APART FROM THEIR BODIES:

    body      header says   should cite   HEAD's rule
    sym_453   :453          :467          store(INDEX, load(INDEX)) -> NOOP.after(...)
    sym_454   :454          :468          store(INDEX, gate.where(alt, load))
    sym_458   :458          :474          (STORE, invalid_pat) -> NOOP.after(*src)
    sym_460   :460          :476          store(INDEX, cond.where(val, invalid))

`sym_458` wore `:471` and `sym_460` wore `:474`, so the census counted `:474` PORTED (by the body
that is `:476`'s) and `:476` MISSING -- **and the OP-SET TEST CANNOT SEE THIS: all four rules are
one op, so a rotation among them is invisible to the only check the census runs.** The bodies were
right and the citations were the defect.

AND `:471` -- `store(INDEX, gate.where(load(INDEX), alt))`, the MIRROR of `:468` -- had no body at
all. It is now `sym_471x`: the LOAD is read from the WHERE's THEN arm and the gate that reaches
`valid` is NEGATED, which is the whole difference between the two rules. **I got the arm wrong
first** (`src0` for the load) and the probe said so: `WHERE`'s sources are `(cond, then, else)`, so
`sym_454` reads the load at `src2` and this one at `src1`.

VERIFIED with `.agents/slop/sym92/probe-471.bend` / `probe-471.py`:

    port     (store (index b (where (cmpeq g bf) c0 bad)) c7)
    CPython  STORE(INDEX(b, WHERE(CMPEQ(CMPLT(b,5), False), CAST(CONST 0), Invalid)), CAST(CONST 7))

Same tree; the cast is the port's renderer eliding a no-op on a bool. **The negated gate is
`CMPEQ(g, False)` and not `CMPNE(g, True)` -- the same primitive swap, in a rule that had never
been written, which is why it had to be written from HEAD's text and not from the pin's.**

A THIRD SELF-INFLICTED BUG THE PROBE CAUGHT: `case 129: sym_471x(x, u)` went into the table and
NOT into `MINT_TAGS`, so the rule answered correctly when called directly and never fired through
`sym_dispatch_f`. That is the second time this session that "it compiles" and "it fires" were two
different measurements.

STATE: **132 PORTED, 0 BROKEN, 3 MISSING** of 135 rows. `symrules-gate` 0 problems;
`symclosure-gate`'s four structural rows green (130 rows / 130 distinct tags, mint 99 == 99).

REMAINING, and all three are the SAME shape of wall -- a rule that cannot be called from where it
has to run: `divandmod.py:103` (`fold_divmod_general` needs `UOp.simplify`+`gcd`+`divide_exact`, and
`symbolic` imports `divandmod` so `divandmod.bend` cannot reach back), `:450` (`simplify_valid`) and
`:451` (`gated_given_valid`), both behind `# late import!` at `ops.py:490` -- an escape Bend has no
spelling for.
