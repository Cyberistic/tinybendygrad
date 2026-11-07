"""THE CPYTHON ORACLE FOR THE `divandmod` LANE, RESTORED AND RE-POINTED AT THE PIN.

    .venv/bin/python .agents/slop/dm-oracle.py

**THIS FILE WAS SWEPT.** MEASURED 2026-11-08: `git log --all -- .agents/slop/dm-oracle.py`
NAMES FOUR COMMITS AND THE LAST ONE IS `371cc64c9` "sweep: **THE SWEEP DELETED 3,603 FILES
AND TOOK 166 REPRODUCTION PA**" -- **AND THE BLOBS WERE GONE FROM EVERY COMMIT'S TREE**, BUT
`git rev-list --all --objects` STILL NAMES THREE `dm-oracle.py` BLOBS
(`a4fdbd891acef27f104fb56787065f0be069b42e` 2870 B, `fa2af38057668f83b0f03b9e01f69c0dab1f91b8`
2872 B, `6065cd94bc2360eed4f9a56343e3458a144017e2` 3346 B), **AND THE LARGEST ONE IS
RESTORED HERE.** **A SWEPT FILE IS NOT A LOST FILE WHEN THE BLOB IS STILL IN THE OBJECT
STORE, AND "IT WAS DELETED" IS NOT A REASON TO REBUILD IT.**

**AND THE RESTORED FILE REFUSED TO RUN, AND THE REASONS ARE THE RE-VENDOR DRIFT AND NOT A
BUG IN IT.** MEASURED, THREE SPELLINGS MOVED SINCE IT WAS WRITTEN:

  * `Ops.FLOORDIV` AND `Ops.FLOORMOD` ARE NOW `Ops.DIV` AND `Ops.MOD` -- `hasattr(Ops,
    "FLOORDIV")` READS **False**. **AND THIS IS THE SAME DRIFT THAT MADE
    `gates/decomp_graph_census-oracle.py` REFUSE WITH `KeyError: 'FLOORDIV'`, AND THE SAME
    ONE THAT MADE `gates/symrules-oracle.py` REFUSE 24 OF ITS 232 CASES.**
  * `UOp.variable(..., multiple_of=N)` IS **GONE**: THE SIGNATURE IS NOW
    `(name, min_val, max_val, dtype)` **AND `multiple_of` IS NOT A FIELD OF `ParamArg`
    EITHER** -- MEASURED, `ParamArg`'s FIELDS ARE `slot, dtype, vmin_vmax, name, addrspace,
    device, volatile, image, buffer, bind_on_realize, val, spec`. **AND UPSTREAM's
    `tinygrad/uop/ops.py` AT THE PIN MENTIONS `multiple_of` **ZERO TIMES**, SO THE CONCEPT
    ITSELF IS GONE AND NOT JUST THE SPELLING.**
  * SO THE `p4`/`p3`/`p1` CASES -- WHICH TESTED "A PARAM THAT IS A MULTIPLE OF 4" -- TEST A
    CONCEPT UPSTREAM NO LONGER HAS, **AND THEY ARE DROPPED RATHER THAN REWRITTEN INTO
    SOMETHING ELSE, BECAUSE A CASE THAT MEANS SOMETHING ELSE IS NOT A CASE.**

**AND THE `vmin_vmax` FIELD IS WHAT REPLACES IT FOR THE ONE CASE THAT STILL MEANS SOMETHING**:
A PARAM WHOSE RANGE IS `[0, 12]` IS NOT A MULTIPLE OF 4, BUT A PARAM WHOSE RANGE IS `[0, 0]`
IS A ZERO AND `fold_divmod_general`'s `y.vmin==y.vmax==0` TEST IS STILL LIVE.

**AND THE PORT's OWN `divandmod.bend` HEADER NAMES FOUR DIVERGENCES AND SAYS THE ORACLE
PRINTS "LEVELS DEEP WITH CONST VALUES", SO THE ORACLE IS THE LANE's ORACLE AND NOT A NEW
THING.**
"""
from tinygrad.uop.ops import UOp, Ops
from tinygrad.dtype import dtypes
from tinygrad.uop.divandmod import div_and_mod_symbolic


def sh(u):
  if u.op is Ops.CONST: return f"C({u.val})"
  if u.op is Ops.PARAM: return "P" + str(u.arg.name)
  if u.op is Ops.CAST: return sh(u.src[0])          # the port has no promotion CASTs
  ss = [s for s in u.src if s.op is not Ops.CAST]
  return u.op.name + ("(" + ",".join(sh(s) for s in ss) + ")" if ss else "")


def news(r, node):
  """new nodes the rewrite added, with the promotion CASTs stripped"""
  if r is None: return -1
  old = set(node.backward_slice)
  return len([u for u in r.backward_slice if u not in old and u.op is not Ops.CAST])


def show(nm, node):
  try:
    r = div_and_mod_symbolic.rewrite(node)
  except Exception as e:
    print(f"{nm:<8} {sh(node):<40} -> RAISED {type(e).__name__:<20} news=-  dt={node.dtype.name}")
    return
  print(f"{nm:<8} {sh(node):<40} -> {'' if r is None else sh(r):<40} news={news(r,node):<3} dt={node.dtype.name}")


I, W = dtypes.int32, dtypes.weakint
xw = UOp.variable("x", 0, 100, dtype=W)
w = UOp.variable("w", 0, 100, dtype=W)
C = lambda v: UOp.const(v, W)

print("== rule 0  (x//c + a)//d -> (x + a*c)//(c*d)   iff d.vmin>0 ==")
show("r0_a", (xw // C(3) + C(5)) // C(7))
show("r0_b", (C(5) + xw // C(3)) // C(7))
show("r0_c", (xw // C(3) + C(10)) // C(7))   # rule 1 ALSO fires -> first-wins
show("r0_neg", (xw // C(3) + C(5)) // C(-7))  # d.vmin>0 fails
show("r0_d0", (xw // C(3) + C(5)) // C(0))   # -> rule 2 -> raise
print("== rule 1  (x+c)//d -> (x+c%d)//d + c//d ;  (x+c)%d -> (x+c%d)%d ==")
show("r1_fd", (xw + C(10)) // C(7))
show("r1_fm", (xw + C(10)) % C(7))
show("r1_same", (xw + C(3)) // C(7))         # c%d == c -> skip
show("r1_swap", (C(10) + xw) // C(7))
show("r1_d1", (xw + C(10)) // C(1))
show("r1_dn", (xw + C(10)) // C(-7))         # 10%-7=-4, 10//-7=-2  (FLOOR)
show("r1_d0", (xw + C(10)) // C(0))          # -> rule 2 -> raise
show("r1_i", (UOp.variable("i", 0, 100, dtype=I) + C(10)) // C(7))  # numerator not weakint
print("== rule 2  (DIV|MOD, weakint) -> fold_divmod_general ==")
show("r2_cst", C(6) // C(4))                 # line 13, x//y is a point
show("r2_cst2", C(6) % C(4))
show("r2_cn", C(-7) // C(4))                 # floor: -7//4 == -2
show("r2_cm", C(-7) % C(4))                  # floor: -7%4  ==  1
show("r2_var", w % C(4))                     # -> None (the rest is the wall)
show("r2_1", w // C(1))
print("== arity: rules 0,1 are strict_length=True, rule 2 is not ==")
show("n_3src", UOp(Ops.DIV, (xw + C(10), C(7), C(1))))
print("== what Python's UOp construction does that this port cannot: promotion CASTs ==")
print("   r0_a full render:", ((xw // C(3) + C(5)) // C(7)).render())
print("   dsts:", [u.dtype.name for u in (xw // C(3) + C(5) // C(1)).backward_slice])
