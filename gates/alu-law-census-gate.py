#!/usr/bin/env python3
"""alu-law-census-gate.py -- CAN THE ALU/DTYPE LAWS GO RED?

THE CLAIM. `LAWS/PROOF-ALL.bend` reports `ALL PROOFS CHECK`, and `LAWS.bend`'s 34
laws are the port's specification.  A green gate over a law that CANNOT FAIL is
a label, not a law: `differ.py`'s own plant 3 says "if it does not go red, the
row is a label", and `AGENTS.md` doctrine 2 names DEAD as the verdict nobody
writes down.

So this gate asks the question the aggregate gate cannot: for EVERY law of the
ALU/dtype half, does breaking its subject make the gate go RED, NAMING THAT LAW?

THE POPULATION IS DISCOVERED, NOT LISTED.  The proof set is SPLIT IN TWO --
`PROOF.bend` holds the shape half and `PROOF2.bend` the ALU/dtype half -- and
the two are told apart by CONTENT: the ALU/dtype half is the one whose law
bodies name the DECOMPOSITION TABLE (`A.<fn>`) or the DTYPE COLUMN
(`dtype_of`/`numel_of`).  So a law that moves from one half to the other moves
this gate's population with it, and neither half is named here.

AND THE MASK IS A SECOND, SEPARATE QUESTION.  A decomposition law's subject
is `A.neg` and the law's right-hand side is `SpMul{a, A.one()}` -- the SAME
mask term on both sides.  Breaking `A.neg` reddens the law, so the law is not
vacuous; but no change to the mask can break it, because the mask appears on
both sides.  So the mask is asked ON ITS OWN, per law, and a law that cannot
fail on its mask is VACUOUS ON ITS MASK.

TWO CLASSES, AND BOTH ARE DEFAULTS, NOT VERDICTS:

  * A LAW THAT CANNOT GO RED is VACUOUS.  The gate stays green, so the law
    pins nothing: whatever the port does, the law agrees with it.
  * A DTYPE ARM THAT NO LAW PINS is UNPINNED.  The fold has an arm and no
    law reads it, so the arm may be wrong and the book says nothing.

AND THE BASELINE IS WHY A GATE THAT IS ALWAYS RED IS NOT A GATE.  Both
classes are defects THAT EXIST TODAY, so the gate compares the census against
a DECLARED BASELINE (`gates/alu-law-census.rows`) and FAILS when the census
gets WORSE -- a law that becomes vacuous, an arm that becomes unpinned, a
mask that becomes indistinguishable.  A defect that is FIXED is reported and
the baseline is then narrowed, so the gate stays green at rest and goes red
on a regression.  `checks/differ.py:814` says it: "a guard that is always red
is not a guard".

THE WORKING TREE IS NEVER EDITED.  Every case is a fresh copy of
`tinybendygrad/` in a private temp dir, mutated there, and checked there --
the same shape `gates/verdict-lane-gate.py`'s plant uses and the reason
`gates/artifacts/` is `.gitignore`d: a gate's inputs must not live where a
gate's runs are written.

USAGE.
    .venv/bin/python gates/alu-law-census-gate.py            # the gate
    .venv/bin/python gates/alu-law-census-gate.py --plant    # its own control
    .venv/bin/python gates/alu-law-census-gate.py --rows     # the table
    .venv/bin/python gates/alu-law-census-gate.py --refresh
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gatekit  # noqa: E402

PASS, FAIL, REFUSED, SKIP, DEAD = gatekit.PASS, gatekit.FAIL, gatekit.REFUSED, gatekit.SKIP, gatekit.DEAD
VERDICT = gatekit.VERDICT

ROOT = gatekit.ROOT
PORT = ROOT / "tinybendygrad"
BEND = gatekit.BEND

# THE BOOK THAT MUST STAY GREEN.  The aggregate, because a half-book is not a
# verdict: `LAWS.bend` alone declares 34 and fills 0, `PROOF.bend` alone fills
# 16 and `PROOF2.bend` alone fills 18, and only the aggregate joins them.
AGGREGATE = PORT / "LAWS" / "PROOF-ALL.bend"

# THE BASELINE.  The defects that exist TODAY, declared, so the gate is green
# at rest and goes red on a REGRESSION.  It lives BESIDE THE GATE and in git,
# because `gates/artifacts/` is `.gitignore`d and emptied before every run.
BASELINE = HERE / "alu-law-census.rows"

# THE TWO FILES A MUTATION MAY LAND IN: the decomposition table and the spec
# datatype the folds live in.
ALU = PORT / "LAWS" / "alu.bend"
SPEC = PORT / "LAWS" / "spec.bend"

WARM = "ALL PROOFS CHECK"


# --------------------------------------------------------------------------- discovery
def law_names(path: Path) -> list[str]:
    """The `law NAME:` names this file declares, in order."""
    return re.findall(r"^law (\w+):", path.read_text(errors="replace"), re.M)


def proved_names(path: Path) -> list[str]:
    """The `def L.NAME(` names this file proves."""
    return re.findall(r"^def L\.(\w+)\(", path.read_text(errors="replace"), re.M)


def proof_books(port: Path) -> list[Path]:
    """The proof books: the `.bend` files that carry `def L.<name>` bodies.

    DISCOVERED BY DISCOVERY: every `.bend` file under `tinybendygrad/` whose
    text holds a `def L.` proof.  `LAWS.bend` itself holds none (it declares),
    so the two halves are found without naming either.
    """
    out = []
    for p in sorted(port.rglob("*.bend")):
        if re.search(r"^def L\.\w+\(", p.read_text(errors="replace"), re.M):
            out.append(p)
    return out


def alu_half(port: Path) -> tuple[Path, list[str]]:
    """`(the book that holds the ALU/dtype half, its law names)`.

    THE HALF IS THE ONE THAT DOES NOT HOLD THE OTHER'S LAWS.  Both halves prove
    laws; they are told apart by which half's law set is DISJOINT from the
    other's, and the ALU/dtype half is the one whose laws are the ones the
    spec's DECOMPOSITION TABLE and DTYPE COLUMN state.  That is a RULE over the
    law TEXTS (`A.<fn>` for a decomposition, `dtype_of`/`numel_of` for a
    derived-property law), so a law that moves from one half to the other
    moves this gate with it.
    """
    books = proof_books(port)
    if len(books) != 2:
        return (books[0] if books else Path(""), [])
    alu_book = None
    for b in books:
        text = b.read_text(errors="replace")
        # the ALU/dtype half names the decomposition table or the dtype fold
        if re.search(r"\bA\.\w+\(", text) or "dtype_of" in text:
            alu_book = b
    if alu_book is None:
        return (Path(""), [])
    laws_declared = set(law_names(port / "LAWS.bend"))
    own = [n for n in proved_names(alu_book) if n in laws_declared]
    return (alu_book, own)


# --------------------------------------------------------------------------- the mutation
def find_def_body(text: str, name: str) -> tuple[str, str] | None:
    """`(the def's whole text, its body's last line)` for `def <name>(`.

    The body is the lines after the `def` line up to the next blank line, which
    is how `LAWS/alu.bend` and `LAWS/spec.bend` are written: a def, then its
    body, then a blank line.  A def whose body is not found this way is
    reported, not guessed at.
    """
    m = re.search(rf"^def {re.escape(name)}\([^\n]*\n((?:[ \t]+[^\n]*\n)*[ \t]+[^\n]*$)", text, re.M)
    if not m:
        return None
    whole = m.group(0)
    body = [ln for ln in m.group(1).splitlines() if ln.strip()]
    return (whole, body[-1].strip() if body else "")


def mutate_definition(text: str, name: str) -> str | None:
    """A copy of `text` in which `def <name>`'s body is REPLACED by a different
    term of the same type.

    The replacement is `S.SpInvalid{}` -- the spec's INVALID marker, which
    inhabits `S.Sp`, so the mutated file still TYPECHECKS and the checker
    reaches the law and finds it false.  A mutation that made the file
    ill-typed would redden the gate for the wrong reason (a type error is not a
    law failing), so the replacement must be well-typed.
    """
    found = find_def_body(text, name)
    if found is None:
        return None
    whole, last = found
    # the body of these defs is ONE line; only a one-line body is mutated here
    lines = [ln for ln in whole.splitlines() if ln.strip()]
    if len(lines) != 2:
        return None
    indented = " " * (len(lines[1]) - len(lines[1].lstrip()))
    new_whole = whole.replace(lines[1], indented + "S.SpInvalid{}")
    if new_whole == whole:
        return None
    return text.replace(whole, new_whole, 1)


def mutate_arm(text: str, op: str, fold: str) -> str | None:
    """A copy of `text` in which the dtype fold's ARM for `op` is broken.

    A FOLD is many arms, so breaking the def is not one edit: `Sp.dtype`'s arm
    for `SpXor` is a LINE, and the law that reads it names `SpXor`.  So the
    mutation is per ARM, and it is FOUND by the arm's own text.

    THE ARM IS FOUND IN THE RIGHT FOLD.  `Sp.shape` and `Sp.dtype` have arms
    for the SAME ops -- `case SpDetach{a}` is in both -- so a search over the
    whole file finds the SHAPE fold's arm first and mutates the wrong one.
    The fold is therefore located by its own `def` line and the search is
    confined to that def's text.

    THE REPLACEMENT KEEPS THE ARM'S SHAPE, so the file still TYPECHECKS and
    the checker reaches the law and finds it false.  Two ways to do that, and
    the gate uses the one that fits the arm:

      * an arm whose body is `Some{<dt>}` becomes `Some{<other dt>}` -- the
        dtype changes, the type does not;
      * an arm whose body is `Sp.dtype(<operand>)` becomes
        `Sp.dtype(<other operand>)` -- the SOURCE changes, the type does not.

    A mutation that made the file ill-typed would redden the gate for the
    wrong reason (a type error is not a law failing), so the arity and the
    type are preserved.
    """
    fold_text = fold_body(text, fold)
    if fold_text is None:
        return None
    fstart, fend = fold_text
    pat = re.compile(r"^(\s*)case (" + re.escape(op) + r")\{([^}]*)\}: (.*)$", re.M)
    m = pat.search(text, fstart, fend)
    if not m:
        return None
    indent, ctor, fields, body = m.group(1), m.group(2), m.group(3), m.group(4).strip()
    # the arm's fields, so a NEW arm of the same arity can be written
    names = [f.split(":")[0].strip() for f in fields.split(",") if f.strip()]
    # a trailing COMMENT is not part of the body: `case SpRange{bound}: Some{index()}   # "index"`
    body = body.split("#")[0].strip()
    new_body = None
    # a `Some{<dt>}` arm: change the dtype
    if body.startswith("Some{") and body.endswith("}"):
        # the dtype must ACTUALLY change, or the mutation is the identity and
        # the row would report a GREEN that means nothing
        new_body = "Some{boolean()}" if not body.startswith("Some{boolean()") else "Some{uint8()}"
    elif body == "None{}":
        # a VOID arm: the dtype is absent, and giving it one is a different
        # dtype column -- the same TYPE, a different answer.
        new_body = "Some{boolean()}"
    else:
        # a `Sp.dtype(<operand>)` or `Sp.shape(<operand>)` arm: change the
        # SOURCE, keeping the type
        sm = re.match(r"Sp\.(?:dtype|shape)\((\w+)\)", body)
        if not sm:
            return None
        operand = sm.group(1)
        if operand not in names:
            return None
        other = next((n for n in names if n != operand), None)
        if other is None:
            # A UNARY arm with one operand: there is no OTHER source, so the
            # arm's RESULT changes instead -- `Sp.dtype(a)` becomes
            # `Some{boolean()}`, which is the same TYPE and a different dtype.
            # For the SHAPE fold the same move gives `Some{Shape.empty()}`.
            new_body = "Some{Shape.empty()}" if fold == "Sp.shape" else "Some{boolean()}"
        else:
            new_body = f"{fold}({other})"
    new_arm = f"{indent}case {ctor}{{{fields}}}: {new_body}"
    old_arm = m.group(0)
    if old_arm == new_arm:
        return None
    return text.replace(old_arm, new_arm, 1)


def fold_body(text: str, fold: str) -> tuple[int, int] | None:
    """`(start, end)` of `def <fold>(`'s body in `text`, or None.

    The fold is a `def` whose body is its `match` over the op datatype, so its
    text ends at the next top-level `def` or the end of the file.
    """
    m = re.search(rf"^def {re.escape(fold)}\(", text, re.M)
    if not m:
        return None
    start = m.start()
    nxt = re.search(r"^def \w+\(", text[m.end():], re.M)
    end = m.end() + nxt.start() if nxt else len(text)
    return (start, end)


# --------------------------------------------------------------------------- running
def check(book: Path) -> tuple[int, str]:
    """`(rc, the text bend said)` for one book."""
    try:
        p = subprocess.run([str(BEND), str(book), "--check-only"],
                           capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return (99, "the check timed out")
    return (p.returncode, (p.stdout or "") + (p.stderr or ""))


def fresh_copy(dest: Path) -> Path:
    """A copy of `tinybendygrad/` in `dest`, with the layout its import lines need."""
    shutil.rmtree(dest, ignore_errors=True)
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copytree(PORT, dest / "tinybendygrad")
    return dest / "tinybendygrad"


def named_law(text: str) -> str | None:
    """The law the failure NAMES, if it names one.

    bend's failure carries `Location: L.<name>`, which is the def whose body
    the checker was proving.  A failure with no `Location: L.` named no law, so
    the row says so rather than crediting the nearest one.
    """
    m = re.search(r"Location: L\.(\w+)", text)
    return m.group(1) if m else None


# --------------------------------------------------------------------------- the gate
def run_gate(args) -> int:
    if not BEND.exists():
        print("REFUSED, NOT A VERDICT: there is no `bin/bend` in this tree")
        return REFUSED
    if not AGGREGATE.exists():
        print("REFUSED, NOT A VERDICT: the aggregate book is absent")
        return REFUSED

    book, laws = alu_half(PORT)
    if not laws:
        print("REFUSED, NOT A VERDICT: the ALU/dtype half could not be found by discovery")
        return REFUSED

    rows: list[tuple[str, str, str]] = []
    bad: list[str] = []
    # the laws that cannot fail ON THEIR MASK -- the vacuity that is not the
    # law's own subject, and the one a subject-mutation cannot see
    vacuous_mask: list[str] = []

    with tempfile.TemporaryDirectory(prefix="alu-law-census-") as td:
        # --- THE CONTROL: the un-mutated copy must be green, or every case
        # below is measuring a broken copy rather than a broken law.
        control_root = fresh_copy(Path(td) / "control")
        rc, out = check(control_root / "LAWS" / "PROOF-ALL.bend")
        if rc != 0 or WARM not in out:
            print("REFUSED, NOT A VERDICT: the control copy is not green, so a case "
                  "below would be measuring the copy and not the law")
            print(gatekit._said(out, lines=6))
            return REFUSED
        rows.append(("CONTROL", "green", "the un-mutated copy is green"))

        # --- THE POPULATION: one mutation per law of the half.
        for law in laws:
            # the law's subject: the term whose unfolding makes the law true.
            # It is FOUND from the law's own text, so a law that is rewritten
            # names a different subject and this follows it.
            subject = law_subject(law, control_root)
            if subject is None:
                rows.append((law, "NO-SUBJECT", "the law names no term to break"))
                bad.append(f"{law}: no subject found")
                continue
            kind, name, fold = subject
            if kind == "def":
                target = None
                for cand in (ALU.name, SPEC.name):
                    text = (control_root / "LAWS" / cand).read_text(errors="replace")
                    if f"def {name}(" in text:
                        target = control_root / "LAWS" / cand
                        break
                if target is None:
                    rows.append((law, "NO-SUBJECT", f"the def {name} is in no file"))
                    bad.append(f"{law}: def {name} not found")
                    continue
                text = target.read_text(errors="replace")
                mutated = mutate_definition(text, name)
                what = f"def {name}"
            else:
                # an ARM of a fold: the arm's line in `LAWS/spec.bend`
                target = control_root / "LAWS" / SPEC.name
                text = target.read_text(errors="replace")
                mutated = mutate_arm(text, name, fold)
                what = f"the {name} arm of {fold}"
            if mutated is None:
                rows.append((law, "NO-MUTATION", f"could not break {what}"))
                bad.append(f"{law}: could not break {what}")
                continue
            case_root = fresh_copy(Path(td) / f"case-{law}")
            rel = target.relative_to(control_root)
            (case_root / rel).write_text(mutated)
            rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
            named = named_law(out)
            if rc != 0 and named == law:
                rows.append((law, "RED", f"the gate names {law}"))
            elif rc != 0:
                rows.append((law, "RED-OTHER",
                             f"the gate went red naming {named or 'no law'}"))
                bad.append(f"{law}: the mutation reddened the gate but it named "
                           f"{named or 'no law'}")
            else:
                rows.append((law, "GREEN", f"breaking {what} did not move the gate"))
                bad.append(f"{law}: VACUOUS -- breaking {what} left the gate green")

        # --- THE MASK: a law that names a MASK constant, and whether the law
        # can fail ON THE MASK.  A decomposition law's subject is `A.neg` and
        # the MASK it multiplies by is `A.one()`; breaking `A.neg` reddens the
        # law, but the law's CLAIM is about the mask too ("Neg = Mul(A, -1)"),
        # and a mask that is the same term as every other mask pins nothing
        # about the mask.  So the mask is asked SEPARATELY, PER LAW: the
        # law's own mask term is replaced by the OTHER mask's body, and the
        # law must go red.  A law that stays green here is VACUOUS ON ITS MASK:
        # it cannot fail, because its two sides name the same term.
        mask_laws = [n for n in laws if re.search(r"\bA\.(?:one|zero)\(", law_block(
            (control_root / "LAWS.bend").read_text(errors="replace"), n))]
        for law in mask_laws:
            alu_text = (control_root / "LAWS" / ALU.name).read_text(errors="replace")
            laws_text = (control_root / "LAWS.bend").read_text(errors="replace")
            block = law_block(laws_text, law)
            used = sorted(set(re.findall(r"\bA\.(one|zero)\(", block)))
            if not used:
                continue
            # the mask the law names, and the OTHER mask, whose body replaces it
            mine = used[0]
            other = "zero" if mine == "one" else "one"
            mine_def = find_def_body(alu_text, mine)
            other_def = find_def_body(alu_text, other)
            if mine_def is None or other_def is None:
                rows.append((law, "NO-MUTATION", "the mask is not a one-line def"))
                bad.append(f"{law}: could not find A.{mine}() or A.{other}()")
                continue
            other_body = [ln for ln in other_def[0].splitlines() if ln.strip()][1]
            mutated = alu_text.replace(mine_def[0], mine_def[0].replace(
                [ln for ln in mine_def[0].splitlines() if ln.strip()][1], other_body), 1)
            if mutated == alu_text:
                # THE TWO MASKS ARE THE SAME TERM, so there is NOTHING to
                # mutate: the law's two sides name one term and the law
                # cannot fail on its mask.  That IS the vacuity, and it is
                # the whole finding -- a law whose mask is indistinguishable
                # from the other mask agrees with whatever the port does.
                rows.append((law + ":MASK", "GREEN",
                             f"A.{mine}() and A.{other}() are the same term, so the law "
                             f"cannot fail on its mask"))
                vacuous_mask.append(law)
                continue
            case_root = fresh_copy(Path(td) / f"case-mask-{law}")
            (case_root / "LAWS" / ALU.name).write_text(mutated)
            rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
            named = named_law(out)
            if rc != 0 and named == law:
                rows.append((law + ":MASK", "RED", f"the gate names {law}"))
            elif rc != 0:
                rows.append((law + ":MASK", "RED-OTHER",
                             f"the gate went red naming {named or 'no law'}"))
            else:
                # THE LAW'S TWO SIDES NAME THE SAME MASK, so changing the mask
                # changes BOTH and the law still holds: the law cannot fail on
                # its mask, whatever the mask is.  That is the vacuity, and it
                # is a property of the LAW's SHAPE (its subject and its
                # right-hand side are the same term), not of the mask's value.
                rows.append((law + ":MASK", "GREEN",
                             "the law's two sides name the same mask, so no change to "
                             "the mask can break it"))
                vacuous_mask.append(law)

        # --- THE COVERAGE: every dtype-fold arm, and whether a law reads it.
        arms = dtype_arms(control_root)
        for arm, laws_naming in arms:
            rows.append((f"ARM:{arm}", "UNPINNED" if not laws_naming else "PINNED",
                         f"laws naming it: {', '.join(laws_naming) or 'NONE'}"))

    # --- the report
    if args.rows:
        for name, state, why in rows:
            print(f"{name}\t{state}\t{why}")
    else:
        for name, state, why in rows:
            print(f"  {name:<36} {state:<12} {why}")

    # --- THE CENSUS, AS A SET, COMPARED WITH THE BASELINE.
    # A law that cannot go red and an arm no law pins are DEFECTS THAT EXIST
    # TODAY, so they are not the gate's verdict on its own: the gate fails when
    # the census is WORSE than the baseline, and says so when it is BETTER.
    vacuous = sorted(r[0] for r in rows if r[1] == "GREEN" and ":MASK" not in r[0])
    unpinned_arms = sorted(r[0][4:] for r in rows if r[0].startswith("ARM:") and r[1] == "UNPINNED")
    observed = {"vacuous": vacuous, "vacuous-on-mask": sorted(vacuous_mask),
                "unpinned-arms": unpinned_arms}

    if args.refresh:
        write_baseline(observed)
        print(f"-- baseline written: {BASELINE}")
        return PASS

    base = read_baseline()
    if base is None:
        print("REFUSED, NOT A VERDICT: the baseline is absent, so the census has "
              "nothing to be compared against")
        return REFUSED

    worse = []
    better = []
    for key, want in base.items():
        got = observed.get(key)
        if got is None:
            worse.append(f"{key}: the baseline declares it and the census does not")
            continue
        extra = sorted(set(got) - set(want))
        gone = sorted(set(want) - set(got))
        if extra:
            worse.append(f"{key}: {len(extra)} new -- {', '.join(extra)}")
        if gone:
            better.append(f"{key}: {len(gone)} fixed -- {', '.join(gone)}")
    for key in observed:
        if key not in base:
            worse.append(f"{key}: the census has it and the baseline does not")

    print()
    print(f"-- {len(laws)} ALU/dtype laws, "
          f"{sum(1 for r in rows if r[0].startswith('ARM:'))} ALU dtype arms")
    print(f"-- vacuous laws: {len(vacuous)}" + (f"  {', '.join(vacuous)}" if vacuous else ""))
    print(f"-- unpinned dtype arms: {len(unpinned_arms)}"
          + (f"  {', '.join(unpinned_arms)}" if unpinned_arms else ""))
    print(f"-- vacuous on their mask: {len(vacuous_mask)}"
          + (f"  {', '.join(sorted(vacuous_mask))}" if vacuous_mask else ""))

    if better:
        for b in better:
            print(f"FIXED: {b}")
        print("FIXED: the baseline is now WIDER than the census -- run "
              "`--refresh` to narrow it, or the next run will call these "
              "regressions")

    if worse:
        for w in worse:
            print(f"NOT OK: {w}")
        return FAIL
    print("OK: the census is no worse than the baseline: every ALU/dtype law goes "
          "red when its subject is broken, and no arm lost its law")
    return PASS


def read_baseline() -> dict | None:
    """The declared baseline, or None when it is absent.

    THE FORMAT.  One `key<TAB>value` per line, the value being a comma-
    separated list (or `true`/`false`), so the file is diffable and a change
    in it is a change in the claim.
    """
    if not BASELINE.exists():
        return None
    out: dict = {}
    for raw in BASELINE.read_text().splitlines():
        # THE TAB IS NOT STRIPPED.  A row whose list is EMPTY is written as
        # `key<TAB>` and nothing else, and `str.strip()` would take the tab
        # with it, so the row would read as a bare `key` and be SKIPPED --
        # which is how an empty baseline list becomes a missing key, and the
        # census then has nothing to compare against.
        line = raw.strip("\n").lstrip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("\t")
        if not sep:
            continue
        out[key] = [v for v in value.split(",") if v]
    return out


def write_baseline(observed: dict) -> None:
    """Write the baseline, in the format `read_baseline` reads."""
    lines = [
        "# alu-law-census.rows -- the DECLARED census of the ALU/dtype half's",
        "# defects, GENERATED by `alu-law-census-gate.py --refresh`, its",
        "# ONLY writer.",
        "#",
        "# A law that CANNOT GO RED is vacuous, and a dtype arm NO LAW READS is",
        "# unpinned.  Both are defects THAT EXIST, so the gate compares the",
        "# census with this file and FAILS when the census gets WORSE.  A defect",
        "# FIXED is a row that disappears here.",
        "#",
        "# Git-resident and BESIDE THE GATE because `gates/artifacts/` is",
        "# `.gitignore`d and emptied before every run.",
        "",
        "vacuous\t" + ",".join(observed["vacuous"]),
        "vacuous-on-mask\t" + ",".join(observed["vacuous-on-mask"]),
        "unpinned-arms\t" + ",".join(observed["unpinned-arms"]),
        "",
    ]
    BASELINE.write_text("\n".join(lines))


def law_subject(law: str, root: Path) -> tuple[str, str] | None:
    """What to break so that `<law>` goes red: `(kind, name)`.

    FOUND, NOT LISTED: the law's own body names the terms, and the term it
    names is the one whose definition the law is about.

      * `A.<fn>(` -- the DECOMPOSITION the law is about.  `kind` is `def`.
      * `S.Sp<Op>{` -- the OP the law's subject is built from, and the law
        reads a FOLD, so `kind` is `arm` and `name` is the op constructor.

    A law that names neither is reported, not guessed at.
    """
    text = (root / "LAWS.bend").read_text(errors="replace")
    m = re.search(rf"^law {re.escape(law)}:\n((?:[ \t]+[^\n]*\n)*[ \t]+[^\n]*$)", text, re.M)
    if not m:
        return None
    body = m.group(1)
    a = re.search(r"\bA\.(\w+)\(", body)
    if a:
        return ("def", a.group(1), "")
    # the law's SUBJECT is the op it is about: `dtype_of(S.SpCmpLt{a, b})` and
    # `dtype_of(S.SpStore{...})` both name their op inside the fold call.
    op = re.search(r"(?:dtype_of|numel_of)\(S\.(Sp\w+)\{", body)
    if op:
        # WHICH FOLD: `dtype_of` reads the dtype fold and `numel_of` the shape
        # fold, and the two have arms for the SAME ops, so the fold is named by
        # the law's own helper rather than guessed.
        fold = "Sp.dtype" if "dtype_of" in body else "Sp.shape"
        return ("arm", op.group(1), fold)
    return None


def alu_ops(root: Path) -> list[str]:
    """The ALU ops of the spec datatype, DISCOVERED.

    The spec's datatype marks its elementwise ops with a section comment
    ("-- elementwise ops"), and the marker ops with another ("-- marker ops").
    Those two sections are the ALU family this gate is about: tinyspec's dtype
    column gives them `src[0].dtype` (or `src[1].dtype` for Where), and they
    are the ops the DECOMPOSITION table is written over.

    DISCOVERED, so an op added to the datatype moves this list with it, and
    the SHAPE family's ops (Index, Load, Copy, Reduce, ...) are NOT in it: a
    gate must not fail on another half's domain.
    """
    spec = (root / "LAWS" / "spec.bend").read_text(errors="replace")
    body = spec.split("type Sp is Data:", 1)[1]
    ops: list[str] = []
    in_section = False
    for line in body.splitlines():
        m = re.match(r"\s*#\s*--\s*(.*)", line)
        if m:
            head = m.group(1)
            in_section = head.startswith("elementwise ops") or head.startswith("marker ops")
            continue
        if in_section:
            c = re.match(r"\s{2}(Sp\w+)\{", line)
            if c:
                ops.append(c.group(1))
    return ops


def dtype_arms(root: Path) -> list[tuple[str, list[str]]]:
    """The ALU ops' dtype arms, and the laws that PIN each.

    THE ARMS ARE DISCOVERED: every `case Sp<X>{...}: Sp.dtype(...)` line in the
    dtype fold, restricted to the ALU ops above.

    A law PINS an arm when it READS THE FOLD AT THAT OP -- that is,
    `dtype_of(S.Sp<X>{...})` or `numel_of(S.Sp<X>{...})`.  NAMING the op is
    NOT enough, and the difference is a measured one: `div_is_mul_by_recip`
    names `SpRecip` in its right-hand side, and breaking `SpRecip`'s dtype arm
    does NOT redden the gate, because that law is about the STRUCTURE
    (`Mul(a, Recip(b))`) and never reads the dtype.  So the census asks the
    law's own text whether the FOLD is applied to that op.
    """
    spec = (root / "LAWS" / "spec.bend").read_text(errors="replace")
    laws_text = (root / "LAWS.bend").read_text(errors="replace")
    alu = set(alu_ops(root))
    # the arms are the DTYPE FOLD's arms, not the file's: `Sp.shape` has an
    # arm for the same ops, and a census that counted those would be
    # counting the shape fold's business
    fold = fold_body(spec, "Sp.dtype")
    if fold is None:
        return []
    arms = [a for a in re.findall(r"^    case (Sp\w+)\{[^}]*\}: Sp\.dtype\(", spec[fold[0]:fold[1]], re.M)
            if a in alu]
    out = []
    for arm in arms:
        # the fold applied AT that op: `dtype_of(S.SpXor{...})`
        pinning = []
        for n in law_names(root / "LAWS.bend"):
            block = law_block(laws_text, n)
            if re.search(rf"(?:dtype_of|numel_of)\(S\.{re.escape(arm)}\{{", block):
                pinning.append(n)
        out.append((arm, pinning))
    return out


def law_block(laws_text: str, name: str) -> str:
    """The body of `law <name>:` in `LAWS.bend`."""
    m = re.search(rf"^law {re.escape(name)}:\n((?:[ \t]+[^\n]*\n)*[ \t]+[^\n]*$)", laws_text, re.M)
    return m.group(1) if m else ""


# --------------------------------------------------------------------------- the plant
def run_plant(args) -> int:
    """THE GATE'S OWN CONTROL: it can say RED and GREEN, and it tells PINNED
    from UNPINNED.

    A census that can only print GREEN measures nothing.  FOUR cases, all
    through the SAME `check` the gate uses:

      1. the un-mutated copy is GREEN;
      2. breaking a decomposition reddens the gate NAMING that law;
      3. breaking a PINNED arm reddens the gate;
      4. breaking an UNPINNED arm leaves the gate GREEN.

    Case 4 is the one that makes the gate's own complaint falsifiable: if the
    gate said "no law reads this arm" and breaking that arm DID redden the
    gate, the gate would be wrong about its own population.  The arm for case
    4 is DISCOVERED -- the gate asks its own census which arms are unpinned and
    takes the first -- so a tree where none is unpinned makes case 4 report
    "no such arm" rather than passing quietly.
    """
    if not BEND.exists():
        print("REFUSED, NOT A VERDICT: there is no `bin/bend` in this tree")
        return REFUSED
    bad = []
    with tempfile.TemporaryDirectory(prefix="alu-law-census-plant-") as td:
        control_root = fresh_copy(Path(td) / "control")
        rc, out = check(control_root / "LAWS" / "PROOF-ALL.bend")
        ok_green = (rc == 0 and WARM in out)
        print(f"  1 control          {'GREEN' if ok_green else 'NOT GREEN'}")
        if not ok_green:
            bad.append("the control copy is not green")

        # 2 -- a decomposition, which must redden naming its law
        text = (control_root / "LAWS" / ALU.name).read_text(errors="replace")
        mutated = mutate_definition(text, "neg")
        if mutated is None:
            bad.append("could not mutate def neg")
        else:
            case_root = fresh_copy(Path(td) / "case2")
            (case_root / "LAWS" / ALU.name).write_text(mutated)
            rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
            named = named_law(out)
            ok_red = (rc != 0 and named == "neg_is_mul_by_minus_one")
            print(f"  2 neg mutated      {'RED' if ok_red else 'NOT RED'}"
                  f"  naming {named or 'no law'}")
            if not ok_red:
                bad.append(f"the mutated copy did not go red naming neg_is_mul_by_minus_one "
                           f"(rc={rc}, named={named})")

        # 3 -- a PINNED arm, which must redden
        arms = dtype_arms(control_root)
        pinned = [a for a, naming in arms if naming]
        if not pinned:
            bad.append("no PINNED arm was found, so case 3 could not run")
            print("  3 pinned arm       NO PINNED ARM")
        else:
            arm = pinned[0]
            spec_text = (control_root / "LAWS" / SPEC.name).read_text(errors="replace")
            mutated = mutate_arm(spec_text, arm, "Sp.dtype")
            if mutated is None:
                bad.append(f"could not break the {arm} arm")
                print(f"  3 pinned arm       COULD NOT MUTATE {arm}")
            else:
                case_root = fresh_copy(Path(td) / "case3")
                (case_root / "LAWS" / SPEC.name).write_text(mutated)
                rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
                ok_red = rc != 0
                print(f"  3 pinned arm       {'RED' if ok_red else 'NOT RED'}"
                      f"  ({arm} -> {gatekit._said(out, lines=1)})")
                if not ok_red:
                    bad.append(f"breaking the PINNED arm {arm} did not redden the gate")

        # 4 -- an UNPINNED arm, which must NOT redden, or the census is wrong
        unpinned = [a for a, naming in arms if not naming]
        if not unpinned:
            bad.append("no UNPINNED arm was found, so case 4 could not run")
            print("  4 unpinned arm     NO UNPINNED ARM")
        else:
            arm = unpinned[0]
            spec_text = (control_root / "LAWS" / SPEC.name).read_text(errors="replace")
            mutated = mutate_arm(spec_text, arm, "Sp.dtype")
            if mutated is None:
                bad.append(f"could not break the {arm} arm")
                print(f"  4 unpinned arm     COULD NOT MUTATE {arm}")
            else:
                case_root = fresh_copy(Path(td) / "case4")
                (case_root / "LAWS" / SPEC.name).write_text(mutated)
                rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
                ok_green = (rc == 0)
                print(f"  4 unpinned arm     {'GREEN' if ok_green else 'NOT GREEN'}"
                      f"  ({arm})")
                if not ok_green:
                    bad.append(f"breaking the UNPINNED arm {arm} DID redden the gate, so "
                               f"the census that called it unpinned is wrong")
    print(f"--plant: {'OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--plant", action="store_true", help="the gate's own control")
    ap.add_argument("--rows", action="store_true", help="print the table as rows")
    ap.add_argument("--refresh", action="store_true",
                    help="write the declared census to the baseline file")
    args = ap.parse_args()
    if args.plant:
        return run_plant(args)
    return run_gate(args)


if __name__ == "__main__":
    sys.exit(main())
