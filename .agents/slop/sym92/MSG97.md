census: `:273` added (130 PORTED / 0 BROKEN / 5 MISSING)

`symbolic.py:273` -- `a.where(b.where(c, d), d) -> (a & b).where(c, d)` -- is a NEW body
(`sym_273`), not a re-point: the port had no rule for a `WHERE` whose ELSE is repeated. The
identity check is on the TWO ELSE branches (`p_same(src2(x), src2(inner))`), the same shape `:275`
uses for its repeated CONDITION, and the answer is one minted `AND` under one `WHERE`.

The row is placed between `:271` and `:275`, which is upstream's order, and the tag is renumbered
with the rest: 128 rows are 0..127 again and `symclosure-gate`'s three structural rows are green
(`tags.unique`, `mint.arms`, `dispatch.arms` -- `sym_273` returns a `Found`, so its arm is in
`sym_mint_f` AND its tag is in `MINT_TAGS`, which is the pair the gate exists to keep together).

STATE: **130 PORTED, 0 BROKEN, 5 MISSING**, 135 rows. `symrules-gate`: 0 problems.

STILL MISSING and each named: `:316` (`x*-1 < c -> -c < x`, needs upstream's `fits(x, -c.vmin)`
guard -- an unguarded rewrite would be a WRONG rewrite, which is worse than a missing row), and the
four walls -- `divandmod.py:103`, `:450`, `:451`, `:476`.

NOT CLAIMED: `symclosure-gate` still FAILs, on `narrow.symbolic_202_ccast` and `bodies.absent`
(`fold_add_divmod_recombine`, `reduce_collapse`). Both predate this commit and neither is a row this
change touches; they are named here so the next reader does not read a green `symrules-gate` as a
green closure gate.
