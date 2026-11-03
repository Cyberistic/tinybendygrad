census: 129 PORTED / 0 BROKEN / 6 MISSING, and the `ne`/`eq` PRIMITIVE SWAP is paid for

The re-vendor swapped tinygrad's two comparison primitives, and every rule the port wrote from
`.logical_not()` or `.ne(...)` was matching a node the tree no longer builds:

    pin :  logical_not = cast(bool).ne(True)   -> CMPNE(x, True)
           ne = _binop(CMPNE) ; eq = ne().logical_not()
    HEAD:  logical_not = cast(bool).eq(False)  -> CMPEQ(x, False)
           eq = _binop(CMPEQ) ; ne = eq().logical_not()

`git diff 5c2bf39d6c4b..upstream/master -- tinygrad/mixin/elementwise.py` shows both lines flipping,
and `rg 'Ops\.CMPNE' tinygrad/uop/symbolic.py` answers NOTHING at HEAD: inside this lane CMPNE is a
node that is never built. So the port's 42 `CMPNE` sites were patterns for a shape that cannot occur.

WHAT LANDED, each re-ported from the HEAD text and not re-pointed by line:

  * `mint_not` -- ONE LINE, and it is the primitive: `CMPNE(v, CONST True)` -> `CMPEQ(v, CONST False)`.
  * `:140` double negation  -> `CMPEQ(CMPEQ(x, False), False)` (tag 27)
  * `:138` `x == True -> x`  -- NEW body `sym_138`, non-minting, tag 135 placed between `:137` and `:139`
  * `:144` `CAST(bool->wints) == cvar` -- the three arms MIRROR: `0 -> logical_not`, `1 -> x`,
        `else -> const_like(False)`; the pin's `!=` spelling had `0 -> x`, `1 -> logical_not`,
        `else -> const_like(True)`. Body renamed `sym_144c` because `sym_144` is the XOR rule.
  * `:155` `x == x -> True` -- the pin's `x != x -> False` is GONE; `ne` is `eq().logical_not()`, so
        `x != x` builds `CMPEQ(CMPEQ(x,x),False)` and `:140` takes it. Pattern op CMPEQ, answer
        `mint_true` (a new one-line sibling of `mint_false`).
  * `:271` `gate.where(x,0) != 0 -> gate & (x != 0)` -- TWO CMPEQ LEVELS where the pin had one
        CMPNE; the answer is `mint_not(CMPEQ(x,0))`, which is the same shape because `mint_not` is
        the one place it is written.
  * `:287` min==max -> CONST -- op set `CMPNE`->`CMPEQ`, op table and pattern together.
  * the six `GroupOp.Associative` arms of `:171` -- they were parked on the pin's `:284`, which at
        HEAD is a COMMENT. Five existed; the sixth (XOR) is new, tag 136.

AND FIVE RULES UPSTREAM DELETED, which is not a row (a row that fires on a shape no producer builds
is a label, not a port):

  * `:462`..`:464` `(x*x).reciprocal()` and its two products -- `rg reciprocal` answers only `:18`
        and `:478`..`:480`, and those three ARE the port's tags 128,129,130 (tags 125,126,127 gone).
  * `-1 * (x + y) -> (-x) + (-y)` (tag 132) -- `rg 'lambda x,y: (-x)'` answers nothing.
  * `(x & mask) // k` (tag 37) -- HEAD keeps only the `>>` form at `:153`.
  * `x != x -> False` is the same class and is covered above.
  * movement.py's `remove noop PERMUTEs` (tag 66) -- HEAD's PERMUTE rules are the merge at `:14` only.
  * `:324`'s END rule that drops CONST srcs (tag 116) -- HEAD keeps the AFTER half at `:334` and
        `:338` handles `{AFTER, END}` with one src.
  * TWO DUPLICATES: tag 44's body was the same bool-MUL->AND as tag 47's, and `x != False` (tag 25)
        is now literally the `:140` node.

TAGS ARE NOW 0..126 CONTIGUOUS (`symclosure-gate`'s `tags.unique`), because the tag IS the dispatch
key: a hole is a key nothing can reach, a duplicate is a body reached by the wrong rule. The
renumbering moved `sym_mint_f`, `sym_dispatch.go` AND `MINT_TAGS` together; `MINT_TAGS` had been
carrying nine tags that no longer have a row, and was missing 48 (`sym_284`), which mints.

STATE, MEASURED: 135 census rows -- **129 PORTED, 0 BROKEN, 6 MISSING** (was 121/1/13 at the re-pin).
`symrules-gate`: `port entries 129, mapped 129, broken 0, unresolved 0`, **0 problems** -- the
`ORDER` complaint is gone too, which needed the six `:171` arms under tag 44, tag 47 above tag 45, and
the two `:338` rows adjacent.

STILL MISSING, and each is named rather than counted: `:273` (where-of-where under an equal else),
`:316` (`x*-1 < c -> -c < x`), and the four behind real walls -- `divandmod.py:103` (needs
`UOp.simplify`+`gcd`+`divide_exact` and the `usum` import cycle), `:450`/`:451` (`simplify_valid`'s
late import), `:476` (STORE with where/invalid, needs the valid/INDEX machinery).

NOT CLAIMED: the other `CMPNE` sites in this file. They MINT rather than match, and a minted shape is
correct even where the census cannot see it -- `mint_not` was the shared one and it is fixed, but each
remaining site is a rule to re-read, not a search to replace.
