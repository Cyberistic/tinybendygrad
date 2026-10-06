NINE MARKERS, ONE MISSING READER, AND THE WALL IS TRUE BUT MISATTRIBUTED

`uop/weak.bend` has fourteen markers and NINE of them are the same sentence: `commit_dtype` is
not ported. Reading them produced a finding of a kind this session has not produced before,
because it is not a refuted wall -- it is a REAL wall attached to the WRONG SUBJECT.

WHAT CPython HAS. `tinygrad/mixin/dtype.py:16`, three lines:

    def commit_dtype(self, default_int=None):
      return commit_int(self._uop.vmin, self._uop.vmax, default_int) if self.dtype is dtypes.weakint else self.dtype

WHAT THE PORT HAS. The ARITHMETIC, in `mixin/dtype.bend:283`:

    def commit_dtype(+dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, di: S.Dt) -> Maybe<&1, S.Dt>

which is `commit_int` under a weakint test and `strong_dtype` otherwise -- the same
arithmetic, taking the node's dtype and its two bounds ALREADY RESOLVED.

WHAT THE PORT DOES NOT HAVE. The NODE-LEVEL READER that gets them off the node. And that is
the whole of the nine markers.

THE WALL IS AN IMPORT TOPOLOGY, NOT A LANGUAGE LIMIT -- and every marker states it as
though it were the second kind:

  - `D.commit_dtype` lives in `mixin/dtype.bend`, which imports `uop/ops.bend` and
    `uop/fold.bend` -- and does NOT import `uop/weak.bend`.
  - `wk_dt` and the node's `vmin`/`vmax` readers live in `uop/weak.bend`, which imports
    `ops.bend` and `fold.bend` -- and does NOT import `mixin/dtype.bend`.

So the two halves sit on OPPOSITE SIDES of the import graph, and every call site pays for
it by hand: `mixin/creation.bend` has `cr_bounds` for a Const, threads `self_dt`/`m`/`m2`
through `cr_committed`, and calls `D.commit_dtype` with all four spelled out. `weak.bend`
wants the same thing nine times and cannot spell it, so it has nine markers.

**SO EVERY ONE OF THOSE NINE MARKERS IS ACCURATE AND THE LABEL IS WRONG.** Nothing here is
inexpressible. There is no `Maybe` problem, no `Data`-field problem, no Bend rule. Two
readers that already exist are in two files that do not import each other.

AND THE FIX IS VERIFIED AVAILABLE, which is the part worth acting on. MEASURED, the edge
`weak.bend -> mixin/dtype.bend` closes NO cycle:

    ops.bend   imports weak.bend?  no
    fold.bend  imports weak.bend?  no
    spec.bend  imports weak.bend?  no

so `weak.bend` can import `mixin/dtype.bend` freely. The reader therefore belongs in
`uop/weak.bend` -- it has `wk_dt` there, and it can see `commit_dtype` -- as

    def wk_commit_dtype(fx: F.Folded, u: U32) -> Maybe<&1, S.Dt>

reading the node's base dtype and its two bounds and calling `D.commit_dtype`. One def, and
nine markers have a reader. `creation.bend`'s hand-rolled `cr_committed` path is then
de-duplication rather than a workaround, which is what its own comment already claims it is
("`D.commit_dtype`'s own signature already wants them separately, so this costs nothing and
is not a workaround").

NOT LANDED HERE, and the reason is the usual one: the def needs the node's exact `vmin`/`vmax`
reader names and a gate row, and the topology -- which was the open question -- is now
settled and written down. The NEXT unit is this def, and it is the largest single fan-out
available in the tree: nine markers, one def, three files currently spelling the same
extraction by hand.

THE GENERAL LESSON, and it extends the pattern from the previous rounds. Five walls this
session claimed the SUBSTRATE could not do something and four were false. This one claims
the substrate cannot do something and is TRUE -- but not because of the substrate. **Before
believing a wall, ASK WHICH LAYER IT IS ABOUT**: the language, the port's own arithmetic, or
the import graph. The third is invisible in the marker's phrasing, because a wall is written
as a property of the language and read as one.
