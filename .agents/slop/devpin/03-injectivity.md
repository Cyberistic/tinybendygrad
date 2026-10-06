# 03 — IS THE CANONICAL FORM INJECTIVE ON THE 25 GRAPHS' ROWS?

**ANSWER: YES, MEASURED ON THE LIVE OBJECTS. `lin`'s MOVEMENT WAS NOT A SERIALISATION
ARTEFACT. THE HAZARD IS REAL AND IT DID NOT FIRE — AND SAYING THAT IS THE POINT, BECAUSE
THE JOB NAMED THIS AS A "HIGHER-PRIORITY FINDING THAN `lin`" AND IT IS NOT ONE.**

```
.venv/bin/python .agents/slop/devpin/injectivity.py
```

## THE CLAIM UNDER TEST

`graphcmp.py:672-674` joins dataclass fields with `""`, not `","`:

```python
  if hasattr(x, "__dataclass_fields__"):
    return f"{type(x).__name__}(" + "".join(
      f"{n}={_carg(getattr(x, n))}" for n in x.__dataclass_fields__) + ")"
```

so `Opt(op=SPLIT, axis=2, arg=X)` renders `Opt(op=EOptOps.SPLITaxis=i2arg=X)` — which is
what the job means by "ambiguously unparseable". `:681` has the same join for the
`__dict__` arm. **If two different objects can produce one string, no amount of pinning the
environment makes a comparison sound.**

## THE MEASUREMENT

| | result |
|---|---|
| dataclass instances reachable from the **live** trees of all 25 graphs | **88** |
| distinct rendered strings | **44** |
| **Q1  rendered-string COLLISIONS on live objects** | **0** |
| **Q2  `""`-joined renderings whose parse is not unique** | **0 of 6** |
| **Q4  `""`-joined renderings with a depth-0 comma or a surplus `name=`** | **0** |

Only **6** of the 88 go through the `""`-join arm; the other 82 are `P(...)` (comma-joined
by `paramarg()`) and `Df32` (by `dt()`). Counting all 88 as dataclass-join cases would have
been the measurement answering a question nobody asked.

**Q2's parser is a brute-force caret enumeration over the field NAMES and shares no code
with `split_top` (`graphcmp.py:1969`) or with the emitter's join.** That matters, and it
cost me a run: the first version of this file offset the caret past the delimiter it had
just matched and reported **0 parses for 88 of 88 unambiguous strings** — a clean-looking
number that meant the opposite of what it said. **SELF-CONSISTENCY IS NOT INDEPENDENCE, AND
A PARSER THAT IS WRONG IN ONE DIRECTION LOOKS EXACTLY LIKE A CLEAN RESULT.**

## THE HAZARD IS REAL, CONSTRUCTED (Q3)

```
plain                             Probe(head='a',          tail='b',     n=1)
    renders Probe(head=satail=sbn=i1)                        1 parse
head eats tail's delimiter       Probe(head='a tail=b',   tail='b',     n=1)
    renders Probe(head=sa tail=btail=sbn=i1)                2 parses
       [('sa ', 'btail=sb', 'i1'), ('sa tail=b', 'sb', 'i1')]
tail eats n's delimiter          Probe(head='a',          tail='b n=1', n=1)
    renders Probe(head=satail=sb n=1n=i1)                  2 parses
       [('sa', 'sb ', '1n=i1'), ('sa', 'sb n=1', 'i1')]
```

**So the `""`-join is prefix-UNAMBIGUOUS exactly as long as no value's rendering contains a
later field's `name=`.** `bstr` (`graphcmp.py:387`) is `ATOMS["str"] + s` with **no
escaping**, so a `str` value is the one value kind that can carry arbitrary text, and
therefore the only thing that can break the encoding. Q4 asks whether any did: **no.**

## THE PRECEDENT, AND WHY IT IS NOT A COUNTEREXAMPLE

DEFECT 19 (`graphcmp.py:2858-2878`) is the same hazard, already fixed: a LINEARIZED KERNEL'S
NAME IS ANSI-COLOURED TEXT and `kI(sr\x1b[90m_\x1b[0m\x1b[31m4\x1b[0m…, …)` put 18 bytes of
`\x1b[..m` inside a structural field. The fix is `Context(NO_COLOR=1)` at the source.
**I re-derived the coloured name on the live tree** — it is in the Q2 dump above — and
re-ran `graphcmp.py emit --side py --graph lin` under `NO_COLOR=1`: the artifact is
**byte-identical to the recorded one either way**, because the harness already neutralises
it. So the hazard has fired before, on this exact field, and it is closed.

## WHAT THIS DOES AND DOES NOT SETTLE

* **It is not the `lin` explanation.** `lin`'s row is
  `kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0)` against
  `kI(sr_4_5_3,n(q),N,i0)`. That is **two different strings**, parsed cleanly by both
  methods, with `Opt` objects=1 on `CPU`/`NULL` and 2 on `METAL`/`PYTHON`. Nothing here is
  ambiguous and nothing here is device-caused. See `02-lin-decision.md`.
* **It is not free.** The encoding's soundness rests on a property `bstr` does not enforce
  and no code checks: that no `str` value contains a later field's `name=` or a depth-0
  `,`. Q4 checks it for these 25 graphs today. **A corpus that grows a graph whose SINK name
  contains a comma would silently make two nodes compare equal**, and `D2-cmp-*.txt` would
  print `IDENTICAL`.
* **The BEND side was NOT measured, because running `bend` is out of scope for this unit.**
  The 50 recorded `D2-canon-bend-*.txt` files were read, never regenerated. A bend-side
  injectivity check needs a `bend` run and is NOT DONE — that is the honest limit of this
  measurement and it is named rather than glossed.
