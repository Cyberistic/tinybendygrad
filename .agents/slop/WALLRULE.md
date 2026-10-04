# WALL RULE

Adopted 2026-10-05. Prefix `WALL/`. Applies to every `WALL:` entry in
`.agents/slop/notes/bend2-constraints.md` and to every future wall written anywhere in this project.

## WALL/1 — A wall names its prerequisite

> **A WALL NAMES ITS PREREQUISITE. WHEN THE PREREQUISITE LANDS, THE WALL IS NOT RETIRED —
> IT IS *STALE*, AND THE DISTINCTION IS THE POINT: A WALL SAYS "THIS CANNOT BE DONE";
> A STALE WALL SAYS "NOBODY HAS CHECKED SINCE."**

Every wall carries three fields:

| field | meaning | absent ⇒ |
|---|---|---|
| **(a) anchor** | `file:line` (or symbol name for generated files) where the blocking prerequisite would live | the wall is a **story**, not a claim |
| **(b) reopen** | the exact check whose result would clear the wall | the wall is **open-ended**; nobody can ever retire it |
| **(c) date** | `YYYY-MM-DD` of the measurement | the wall has no provenance and ages silently |

Anchor + reopen + date = a claim, checkable by one grep, and falsifiable by the grep failing.
Anchor alone = an anecdote with a coordinate. Reopen alone = a permanent veto. Date alone = a diary.

**Retirement is two distinct acts and must be reported as such:**
- **RETIRED** — the capability arrived; the wall is deleted. Say *what arrived* and *where it landed*.
- **STALE** — the prerequisite landed but the *original question* was never re-asked; the wall is
  annotated in place with the new measurement and its date. **Do not delete a wall merely because it
  is stale.** A deleted wall is a wall somebody will re-derive, at the same cost, in a later session.

Corollary: **the anchor is the unit of re-measurement.** A wall anchored to a line number in a
generated file is anchored to an offset, not to a thing. Generated files are cited by **name**;
generated line numbers are cited only alongside the generator that produced them.

## WALL/2 — A compressed observation is a new claim

> **A COMPRESSED OBSERVATION IS A NEW CLAIM AND IT OWES THE SAME EVIDENCE AS THE OBSERVATION.**
> **"THE PIPE IS THE TRAP" COMPRESSED TO "`md5` TAKES ONE FILE" DROPPED THE MECHANISM AND KEPT
> THE AUTHORITY.**

Compression is where truth loses its falsifier. The bare observation (`md5 -q < file` returns nothing)
carried a mechanism (`md5` reads stdin; `find … | md5 -q` feeds it nothing). Dropping the mechanism
left a rule that is *wider than the evidence* and therefore **wrong where it will actually be used** —
`md5 -q a b` is fine.

So, for any rule recorded from an observation:
- **(a) mechanism** — *why* the observation implies the rule, in one clause that could itself be tested.
- **(b) counterexample test** — a case where the rule must *not* apply. A rule with no out-of-scope case
  is an overfit.
- **(c) the command that produced it** — re-runnable verbatim.

A rule whose mechanism cannot be stated in one testable clause is not a rule; it is a **slogan**, and
slogans must not be cited as grounds for a decision.

## WALL/3 — A citation supporting a decision is a different claim from one supporting a note

> **A `file:line` IS A COORDINATE IN A SYSTEM WITH AN OFFSET.**
> **CITE GENERATED FILES BY NAME. A CITATION THAT WARANTS A *DECISION* IS CHECKED AT THE TIME OF
> THE DECISION, AND IF IT IS FALSE THE DECISION IS UN-DERIVABLE — WHICH IS WHY FALSE PREMISES INSIDE
> A DECISION LOOK DERIVED AND ARE NEVER RE-DERIVED.**

Two citation classes, two obligations:

- **NOTE citation** — supports a note. Must carry (a) anchor, (b) reopen, (c) date, per WALL/1.
- **DECISION citation** — the cited text is the *warrant* for a choice made in the note. The obligation
  is stronger: the warrant is **quoted, not pointed at**, because the pointed-at line can move.
  A decision whose warrant is a pointer is a decision that silently inherits every future edit of the
  pointed-at line.

Precedent, same day: nine stale-citation classes were found, six of them inside the reports that
raised them; one `graphcmp.py` comment quoted a false line as the warrant for its own refusal to accept
a boolean.

## WALL/4 — Count no number you did not measure yourself

> **A COUNT IN A NOTE IS A MEASUREMENT OF THE FILE IT WAS TAKEN IN, AT THE TIME IT WAS TAKEN.**
> Re-measure before citing. Today nine counts in these notes were stale, and each was individually
> true once.

Corollary for instruments: **an instrument that cannot fail is not an instrument, it is a comment that
adds up.** Report the instrument's hit rate *and* its error rate against a stated denominator. An
instrument with no error rate is not reporting.

## Checker

`zsh .agents/slop/wallrule/wallcheck.sh <WALLID>…` — one grep per wall against its anchor.
Exit 0 = anchors still absent (wall stands). Exit 1 = an anchor now exists (wall is stale or retired).
Exit 2 = a wall is missing anchor / reopen / date (wall is a story, regardless of exit status).
Zero arguments is refused, not `CLEAN`.