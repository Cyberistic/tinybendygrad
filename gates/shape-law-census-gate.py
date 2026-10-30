#!/usr/bin/env python3
"""shape-law-census-gate.py -- CAN THE SHAPE LAWS GO RED?

THE CLAIM. `LAWS/PROOF-ALL.bend` reports `ALL PROOFS CHECK`, and `LAWS.bend`'s 34
laws are the port's specification.  A green gate over a law that CANNOT FAIL is
a label, not a law: `differ.py`'s own plant 3 says "if it does not go red, the
row is a label", and `AGENTS.md` doctrine 2 names DEAD as the verdict nobody
writes down.

`gates/alu-law-census-gate.py` asks that question of the ALU/dtype half.  THIS
gate asks it of the SHAPE half -- the sixteen laws about `Sp.shape` -- and it
asks it with the ANSWER THE ALU GATE COULD NOT GIVE, because a shape law's
subject is often SHARED with another shape law.

THE POPULATION IS DISCOVERED, NOT LISTED.  The proof set is split in two, and
the halves are told apart by CONTENT: the ALU/dtype half is the one whose law
bodies name the DECOMPOSITION TABLE (`A.<fn>`) or the DTYPE COLUMN
(`dtype_of`).  So a law that moves from one half to the other moves this gate's
population with it, and neither half is named here.

THREE VERDICTS FOR A LAW, AND TWO OF THEM ARE NOT "PASS".  A law's subject may
be SHARED with another law, and `bend` reports the FIRST failure only, so a
shared subject means the later law is MASKED -- the gate IS red, under the
earlier law's name.  That is not the same as vacuous, and the gate separates
them by MASKING: the masking law is removed from a COPY of the book, and the
law under test is then reached.

  RED       the gate went red NAMING THIS LAW.
  MASKED    the gate went red naming ANOTHER law, and with the masking law
            removed the gate goes red naming THIS one.  The law can fail; it
            is just not the failure `bend` reports first.
  VACUOUS   the gate stayed green, or it went red under another law's name and
            the masking did not reach this one.  The law's conclusion cannot
            fail -- and `store_matches_its_buffer` is the case in point: its
            conclusion IS its premise.

AND THE COVERAGE.  Every arm of the shape fold is listed, and an arm NO LAW
READS is UNPINNED: the arm may be wrong and the book says nothing.

THE MASK IS WHY A LIST OF SUBJECTS IS NOT ENOUGH, so the subject of each law is
FOUND from the law's own CONCLUSION -- the fold arm whose op the conclusion
names, or the helper the conclusion calls.  A law that names no term is
REPORTED, not guessed at.

THE WORKING TREE IS NEVER EDITED.  Every case is a fresh copy of
`tinybendygrad/` in a private temp dir, mutated there, and checked there --
the same shape `gates/alu-law-census-gate.py` uses and the reason
`gates/artifacts/` is `.gitignore`d: a gate's inputs must not live where a
gate's runs are written.

AND THE BASELINE IS WHY A GATE THAT IS ALWAYS RED IS NOT A GATE.  The vacuous
laws and the unpinned arms are defects THAT EXIST TODAY, so the gate compares
the census against a DECLARED BASELINE (`gates/shape-law-census.rows`) and
FAILS when the census gets WORSE -- a law that becomes vacuous, an arm that
loses its law.  A defect that is FIXED is reported and the baseline is then
narrowed, so the gate stays green at rest and goes red on a regression.

USAGE.
    .venv/bin/python gates/shape-law-census-gate.py            # the gate
    .venv/bin/python gates/shape-law-census-gate.py --plant    # its own control
    .venv/bin/python gates/shape-law-census-gate.py --rows     # the table
    .venv/bin/python gates/shape-law-census-gate.py --refresh
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

ROOT = gatekit.ROOT
PORT = ROOT / "tinybendygrad"
BEND = gatekit.BEND

# THE BOOK THAT MUST STAY GREEN.  The aggregate, because a half-book is not a
# verdict: `PROOF.bend` alone reports 18 TODOs and `PROOF2.bend` alone 16, and
# each shows the other's laws as open.
AGGREGATE = PORT / "LAWS" / "PROOF-ALL.bend"

# THE BASELINE.  The defects that exist TODAY, declared, so the gate is green
# at rest and goes red on a REGRESSION.  It lives BESIDE THE GATE and in git,
# because `gates/artifacts/` is `.gitignore`d and emptied before every run.
BASELINE = HERE / "shape-law-census.rows"

# THE TWO FILES A MUTATION MAY LAND IN: the spec datatype the fold lives in and
# the law book that holds the helpers.  They are named by the SUBJECT, not
# here, because the subject says where its term lives.

WARM = "ALL PROOFS CHECK"

# THE TWO VERDICTS THAT ARE NOT "RED", spelled so a row can be read.
RED = "RED"
MASKED = "MASKED"
VACUOUS = "VACUOUS"


# --------------------------------------------------------------------------- discovery
def law_names(path: Path) -> list[str]:
    """The `law NAME:` names this file declares, in order."""
    return re.findall(r"^law (\w+):", path.read_text(errors="replace"), re.M)


def proof_books(port: Path) -> list[Path]:
    """The proof books: the `.bend` files that carry a `def L.<name>` proof."""
    out = []
    for p in sorted(port.rglob("*.bend")):
        if re.search(r"^def L\.\w+\(", p.read_text(errors="replace"), re.M):
            out.append(p)
    return out


def shape_half(port: Path) -> tuple[Path, list[str]]:
    """`(the book that holds the shape half, its law names)`.

    THE ALU/dtype half is the one that names the DECOMPOSITION TABLE or the
    DTYPE COLUMN, and the shape half is the other one.  That is a RULE over the
    law TEXTS, so a law that moves from one half to the other moves this gate
    with it.
    """
    books = proof_books(port)
    if len(books) != 2:
        return (books[0] if books else Path(""), [])
    shape_book = None
    for b in books:
        text = b.read_text(errors="replace")
        if re.search(r"\bA\.\w+\(", text) or "dtype_of" in text:
            continue
        shape_book = b
    if shape_book is None:
        return (Path(""), [])
    declared = set(law_names(port / "LAWS.bend"))
    own = [n for n in re.findall(r"^def L\.(\w+)\(", shape_book.read_text(errors="replace"), re.M)
           if n in declared]
    return (shape_book, own)


def law_block(laws_text: str, name: str) -> str:
    """The body of `law <name>:` in `LAWS.bend`."""
    m = re.search(rf"^law {re.escape(name)}:\n((?:[ \t]+[^\n]*\n)*[ \t]+[^\n]*$)", laws_text, re.M)
    return m.group(1) if m else ""


# --------------------------------------------------------------------------- the mutation
def fold_body(text: str, fold: str) -> tuple[int, int] | None:
    """`(start, end)` of `def <fold>(`'s body in `text`, or None."""
    m = re.search(rf"^def {re.escape(fold)}\(", text, re.M)
    if not m:
        return None
    start = m.start()
    nxt = re.search(r"^def \w+\(", text[m.end():], re.M)
    end = m.end() + nxt.start() if nxt else len(text)
    return (start, end)


def _arm_span(text: str, op: str, fold: str) -> tuple[int, int] | None:
    """`(start, end)` of the shape fold's ARM for `op`, or None.

    THE ARM IS FOUND IN THE RIGHT FOLD.  `Sp.shape` and `Sp.dtype` have arms
    for the SAME ops -- `case SpDetach{a}` is in both -- so a search over the
    whole file finds the SHAPE fold's arm first and mutates the wrong one.
    The fold is therefore located by its own `def` line and the search is
    confined to that def's text.
    """
    fb = fold_body(text, fold)
    if fb is None:
        return None
    fstart, fend = fb
    m = re.search(r"^(\s*)case " + re.escape(op) + r"\{([^}]*)\}:", text[fstart:fend], re.M)
    if not m:
        return None
    start = fstart + m.start()
    indent = len(m.group(1))
    # the arm runs to the next line at the fold's own indent, or a blank line
    end = len(text)
    for tail in re.finditer(r"^\s{%d}\S" % indent, text[start + 1:], re.M):
        end = start + 1 + tail.start()
        break
    else:
        end = fend
    return (start, end)


def mutate_arm(text: str, op: str, fold: str = "Sp.shape") -> str | None:
    """A copy of `text` in which the shape fold's ARM for `op` is broken.

    THE REPLACEMENT KEEPS THE ARM'S SHAPE, so the file still TYPECHECKS and the
    checker reaches the law and finds it false.  A mutation that made the file
    ill-typed would redden the gate for the wrong reason (a type error is not a
    law failing), so the arity and the type are preserved.

    THREE SHAPES OF ARM, AND EACH HAS ITS OWN REPLACEMENT:

      * a UNARY passthrough (`Sp.shape(t)`): the arm's RESULT changes --
        `Some{Shape.empty()}`, the same TYPE and a different answer;
      * a `Some{Shape.of(<list>)}` arm: the LIST changes -- a fixed one-dim
        shape, the same TYPE and a different count;
      * a MULTI-LINE arm (`SpStack`, `SpReduce`, `SpAdd`): one LINE inside it
        changes, and the line is chosen so the arm's TYPE is unchanged.
    """
    span = _arm_span(text, op, fold)
    if span is None:
        return None
    start, end = span
    arm = text[start:end]
    # A MULTI-LINE arm is handled FIRST, because its text also contains the
    # single-line shapes -- a Stack arm holds `Sp.shape(t)` and a binary arm
    # holds `Sp.shape(a)`, so a single-line rule applied to them would replace
    # the wrong term.
    for old, new in (
        ("Sp.shape.stack(m, Nat.add(n, 1n))", "Sp.shape.stack(m, Nat.add(n, 2n))"),
        ("Sp.shape.reduce(m, k)", "Sp.shape.reduce(m, Nat.add(k, 1n))"),
        # a binary broadcast arm: the RESULT changes, not the operand order.
        # Swapping the operands would leave `dims_zip_max` unchanged when the
        # two shapes are EQUAL -- which is exactly the case the elementwise
        # laws are about -- so the swap would break the broadcast law and not
        # the elementwise one.
        ("dims_zip_max(sa, sb)", "Some{Shape.empty()}"),
    ):
        if old in arm:
            new_arm = arm.replace(old, new, 1)
            return text[:start] + new_arm + text[end:]
    # a `Some{Shape.of(<list>)}` arm: the LIST is replaced by a fixed one-dim
    # shape, so the answer changes and the type does not.
    m = re.search(r"Some\{Shape\.of\((\w+)\)\}", arm)
    if m:
        new_arm = arm.replace(m.group(0), "Some{Shape.of([SN{0n}])}", 1)
        return text[:start] + new_arm + text[end:]
    # a unary passthrough: `Sp.shape(<operand>)`
    m = re.search(r"Sp\.shape\((\w+)\)", arm)
    if m:
        new_arm = arm.replace(m.group(0), "Some{Shape.empty()}", 1)
        return text[:start] + new_arm + text[end:]
    # a VOID arm: `None{}` -- giving it a shape is a different shape column.
    if arm.rstrip().endswith("None{}"):
        new_arm = arm.rstrip()[:-len("None{}")] + "Some{Shape.empty()}"
        return text[:start] + new_arm + text[end:]
    return None


def find_def_body(text: str, name: str) -> tuple[str, str] | None:
    """`(the def's whole text, its body's last line)` for `def <name>(`."""
    m = re.search(rf"^def {re.escape(name)}\([^\n]*\n((?:[ \t]+[^\n]*\n)*[ \t]+[^\n]*$)", text, re.M)
    if not m:
        return None
    whole = m.group(0)
    body = [ln for ln in m.group(1).splitlines() if ln.strip()]
    return (whole, body[-1].strip() if body else "")


# --------------------------------------------------------------------------- the subjects
def law_subject(law: str, root: Path) -> dict | None:
    """What to break so that `<law>` goes red, and where it lives.

    FOUND, NOT LISTED: the law's own body names the terms, and the term it
    names is the one whose definition the law is about.

      * `S.Sp<Op>{` inside a `numel_of`/`shape_of` call -- the OP whose FOLD
        ARM the law reads.  `kind` is `arm`.
      * `S.<Helper>(` -- a HELPER the law calls, which is not part of the fold.
        `kind` is `def`, and the helper lives in the spec.
      * `S.zip_max(` / `S.Shape.max_dim(` -- the SHAPE ALGEBRA, which the two
        section-VIII laws constrain directly.

    A law that names none of these is REPORTED, not guessed at.
    """
    laws_text = (root / "LAWS.bend").read_text(errors="replace")
    body = law_block(laws_text, law)
    if not body:
        return None
    # THE CONCLUSION IS THE LAW's LAST LINE -- the `{... : T}` goal -- and the
    # PREMISES are the `for` binders above it.  The subject is what the
    # CONCLUSION reads, because a law is a claim about its conclusion and the
    # premises are hypotheses it may assume.
    goal = goal_of(body)
    if goal is None:
        return None
    # THE OP IS THE SUBJECT, AND IT COMES FIRST.  A law about an op's shape
    # reads the FOLD at that op, and the op is named in the conclusion as
    # `S.Sp<Op>{`.  The helpers `numel_of`/`shape_of`/`prod_of` are read by
    # SEVERAL laws, so breaking one of them is not breaking THIS law's
    # subject -- it is breaking the fold for every law at once, and the first
    # of them to fail is the one `bend` names.
    op = re.search(r"\bS\.(Sp\w+)\{", goal)
    if op:
        return {"kind": "arm", "name": op.group(1), "file": "LAWS/spec.bend"}
    # a HELPER the conclusion calls: `S.<helper>(` in the spec, or a LAWS.bend
    # helper such as `numel_of`/`shape_of`/`reduced_numel`
    for m in re.finditer(r"\bS\.Shape\.([a-z_]\w*)\(", goal):
        return {"kind": "def", "name": m.group(1), "file": "LAWS/spec.bend"}
    for m in re.finditer(r"\bS\.([a-z_]\w*)\(", goal):
        helper = m.group(1)
        if helper in ("shape", "dtype"):
            continue
        return {"kind": "def", "name": helper, "file": "LAWS/spec.bend"}
    for m in re.finditer(r"\b(numel_of|shape_of|reduced_numel|prod_of|dims_of)\(", goal):
        return {"kind": "def", "name": m.group(1), "file": "LAWS.bend"}
    return None


def shape_arms(root: Path, laws: list[str]) -> list[tuple[str, list[str]]]:
    """The shape fold's arms, and the laws that PIN each.

    THE ARMS ARE DISCOVERED: every `case Sp<X>{...}` line in the shape fold.
    They are the SHAPE fold's arms and not the file's, because `Sp.dtype` has
    an arm for the same ops and a census that counted those would be counting
    the dtype fold's business.

    A law PINS an arm when it READS THE FOLD AT THAT OP -- that is, the op
    appears in the law's CONCLUSION.  NAMING the op is NOT enough, and the
    difference is a measured one: `broadcast_is_elementwise_max` names `SpAdd`
    in its premise's binders and reads it in its conclusion, while
    `reduce_numel_divides_by_the_reduced_axes` reads the Reduce through the
    `reduced_numel` HELPER and never names the op at all.  So the census asks
    the law's own CONCLUSION whether the FOLD is applied at that op, and a law
    that reads the op through a helper pins it too.
    """
    spec = (root / "LAWS" / "spec.bend").read_text(errors="replace")
    laws_text = (root / "LAWS.bend").read_text(errors="replace")
    fb = fold_body(spec, "Sp.shape")
    if fb is None:
        return []
    arms = re.findall(r"^    case (Sp\w+)\{", spec[fb[0]:fb[1]], re.M)
    # the helpers that read the fold AT an op, and the op each one reads
    helper_op = {
        "reduced_numel": "SpReduce",
    }
    out = []
    for arm in arms:
        pinning = []
        for n in laws:
            goal = goal_of(law_block(laws_text, n)) or ""
            if re.search(rf"\bS\.{re.escape(arm)}\{{", goal):
                pinning.append(n)
            elif any(re.search(rf"\b{re.escape(h)}\(", goal) and op == arm
                       for h, op in helper_op.items()):
                pinning.append(n)
        out.append((arm, pinning))
    return out


def goal_of(body: str) -> str | None:
    """The law's CONCLUSION: the last line of its body.

    A law's body is a list of `for` binders and then the goal, and the goal is
    the line that OPENS a brace and closes it with a type -- `{... : T}`.  The
    binders are hypotheses, so the subject of the law is what the GOAL reads.
    """
    for line in reversed(body.splitlines()):
        s = line.strip()
        if s.startswith("{") and s.endswith("}"):
            return s
    return None


def mutate_helper(text: str, name: str) -> str | None:
    """A copy of `text` in which the helper `name` gives a different answer.

    THE HELPER'S OWN ARM IS THE TARGET, and the replacement keeps the type:

      * `Shape.max_dim`'s `SN` arm returns `SN{pick_dim(va, vb)}`; it becomes
        `SN{va}`, the same TYPE and a different dim;
      * `zip_max`'s cons arm returns `Shape.max_dim(x, y) <> ...`; it becomes
        `x <> ...`, the same TYPE and a different list;
      * `elem_pick`'s `SN` arm returns `SN{pick_dim(va, vb)}`; it becomes
        `SN{vb}`, the same TYPE and a different dim;
      * `pick_dim`'s `1n` arm returns `b`; it becomes `a`, the same TYPE and a
        different size.
    """
    for m in re.finditer(r"^def (?:[A-Za-z_]\w*\.)?" + re.escape(name) + r"\(", text, re.M):
        start = m.start()
        nxt = re.search(r"^def \w+\(", text[m.end():], re.M)
        end = m.end() + nxt.start() if nxt else len(text)
        block = text[start:end]
        if name == "max_dim" and "case SN{vb}: SN{pick_dim(va, vb)}" in block:
            new = block.replace("case SN{vb}: SN{pick_dim(va, vb)}", "case SN{vb}: SN{va}", 1)
            return text[:start] + new + text[end:]
        if name == "zip_max" and "case y <> ys: Shape.max_dim(x, y) <> zip_max(xs, ys)" in block:
            new = block.replace("case y <> ys: Shape.max_dim(x, y) <> zip_max(xs, ys)",
                                "case y <> ys: x <> zip_max(xs, ys)", 1)
            return text[:start] + new + text[end:]
        if name == "elem_pick" and "case SN{vb} <> rb: SN{pick_dim(va, vb)} <> elem_pick(ra, rb)" in block:
            new = block.replace("case SN{vb} <> rb: SN{pick_dim(va, vb)} <> elem_pick(ra, rb)",
                                "case SN{vb} <> rb: SN{vb} <> elem_pick(ra, rb)", 1)
            return text[:start] + new + text[end:]
        if name == "pick_dim" and "case 1n: b" in block:
            new = block.replace("case 1n: b", "case 1n: a", 1)
            return text[:start] + new + text[end:]
    return None


# THE HELPERS THAT LIVE IN `LAWS.bend`, AND THE REPLACEMENT THAT KEEPS THE
# TYPE AND CHANGES THE ANSWER.  A helper whose body is one line is replaced by
# one line of the same type: `numel_of` and `shape_of` are the fold's wrappers,
# `reduced_numel` builds a Reduce, and `prod_of` is the spec's product.
LAWS_HELPER_REPLACEMENT = {
    "numel_of": "Nat.add(S.dims_prod(S.Sp.shape(s)), 1n)",
    "shape_of": "Some{S.Shape.empty()}",
    "reduced_numel": "Nat.add(numel_of(S.SpReduce{t, Nil{}, S.SpInvalid{}, n}), 1n)",
    "prod_of": "Nat.add(S.prod(ds), 1n)",
}


def mutate_laws_helper(text: str, name: str) -> str | None:
    """A copy of `text` in which the `LAWS.bend` helper `name` gives a different
    answer, of the SAME TYPE.

    The replacement adds one to the answer, so the helper's TYPE is unchanged
    and the file still typechecks: a mutation that made the file ill-typed
    would redden the gate for the wrong reason (a type error is not a law
    failing).
    """
    replacement = LAWS_HELPER_REPLACEMENT.get(name)
    if replacement is None:
        return None
    found = find_def_body(text, name)
    if found is None:
        return None
    whole, _ = found
    lines = [ln for ln in whole.splitlines() if ln.strip()]
    if len(lines) != 2:
        return None
    indent = " " * (len(lines[1]) - len(lines[1].lstrip()))
    new_whole = whole.replace(lines[1], indent + replacement, 1)
    if new_whole == whole:
        return None
    return text.replace(whole, new_whole, 1)


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


def apply_mutation(root: Path, subject: dict) -> tuple[str | None, str, str]:
    """`(the mutated text, the file it goes in, what was broken)`.

    The subject says WHICH term to break and WHERE it lives, so the mutation
    lands in the right file and the wrong one is not touched.
    """
    kind, name = subject["kind"], subject["name"]
    rel = subject["file"]
    text = (root / rel).read_text(errors="replace")
    if kind == "arm":
        mutated = mutate_arm(text, name, "Sp.shape")
        what = f"the {name} arm of Sp.shape"
    elif rel == "LAWS.bend":
        mutated = mutate_laws_helper(text, name)
        what = f"the {name} helper"
    else:
        mutated = mutate_helper(text, name)
        what = f"the {name} helper"
    return (mutated, rel, what)


def remove_law(root: Path, law: str) -> None:
    """Remove `law` from the COPY's `LAWS.bend` AND its proof from `PROOF.bend`.

    THE MASK.  `bend` discharges a law by a def of the same name, so a law whose
    proof def is REMOVED becomes an open TODO rather than a failure -- and a
    TODO is a different verdict from a red law.  Removing the law's DECLARATION
    as well makes the law not exist, so the law under test is REACHED and its
    own name is the one `bend` reports.

    The copy is in a temp dir; the tree's `LAWS.bend` and `PROOF.bend` are not
    touched.
    """
    laws_f = root / "LAWS.bend"
    text = laws_f.read_text(errors="replace")
    text = re.sub(rf"^law {re.escape(law)}:\n((?:[ \t]+[^\n]*\n)*[ \t]+[^\n]*$)", "", text, flags=re.M)
    laws_f.write_text(text)
    for book in proof_books(root):
        bt = book.read_text(errors="replace")
        new = re.sub(rf"^def L\.{re.escape(law)}\(.*?(?=^def |\Z)", "", bt, flags=re.M | re.S)
        if new != bt:
            book.write_text(new)


def masked_check(law: str, mutated: str, target_rel: str, td: Path) -> tuple[int, str]:
    """The aggregate checked with the laws that MASK `<law>` removed.

    `bend` reports the FIRST failing law, so a law whose subject is SHARED with
    an earlier law is never the failure `bend` names.  The mask removes the
    laws that were failing FIRST, one at a time, until the law under test is
    the one named -- or until no law fails at all, which says the law under
    test CANNOT FAIL.

    THE MASK IS ITERATIVE, and it has to be: one mask can uncover a second
    masking law.  Removing only the law `bend` named is the FIRST step, and the
    law that appears next is masked in turn.
    """
    masked: list[str] = []
    while True:
        case_root = fresh_copy(td / f"mask-{law}-{len(masked)}")
        (case_root / target_rel).write_text(mutated)
        for other in masked:
            remove_law(case_root, other)
        rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
        named = named_law(out)
        if rc == 0 or WARM in out:
            return (rc, out)
        if named == law:
            return (rc, out)
        if named is None:
            # the failure is in a HELPER, not in a law: no law can be masked
            # away to reach the law under test, so the law cannot fail.
            return (rc, out)
        masked.append(named)


# --------------------------------------------------------------------------- the gate
def run_gate(args) -> int:
    if not BEND.exists():
        print("REFUSED, NOT A VERDICT: there is no `bin/bend` in this tree")
        return REFUSED
    if not AGGREGATE.exists():
        print("REFUSED, NOT A VERDICT: the aggregate book is absent")
        return REFUSED

    book, laws = shape_half(PORT)
    if not laws:
        print("REFUSED, NOT A VERDICT: the shape half could not be found by discovery")
        return REFUSED

    rows: list[tuple[str, str, str]] = []
    bad: list[str] = []

    with tempfile.TemporaryDirectory(prefix="shape-law-census-") as td:
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

        for law in laws:
            subject = law_subject(law, control_root)
            if subject is None:
                rows.append((law, "NO-SUBJECT", "the law names no term to break"))
                bad.append(f"{law}: no subject found")
                continue

            # --- the mutation, applied to a fresh copy
            case_root = fresh_copy(Path(td) / f"case-{law}")
            mutated, target_rel, what = apply_mutation(case_root, subject)
            if mutated is None:
                rows.append((law, "NO-MUTATION", f"could not break {what}"))
                bad.append(f"{law}: could not break {what}")
                continue
            (case_root / target_rel).write_text(mutated)

            rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
            named = named_law(out)
            if rc == 0 or WARM in out:
                # THE GATE STAYED GREEN.  The law cannot fail on its subject.
                verdict, why = VACUOUS, f"breaking {what} left the gate green"
            elif named == law:
                verdict, why = RED, f"the gate names {law}"
            else:
                # THE GATE WENT RED UNDER ANOTHER LAW'S NAME.  The subject is
                # SHARED, so the mask decides whether this law CAN fail.
                rc2, out2 = masked_check(law, mutated, target_rel, Path(td))
                named2 = named_law(out2)
                if rc2 != 0 and WARM not in out2 and named2 == law:
                    verdict = MASKED
                    why = (f"the gate went red naming {named or 'no law'}; with the "
                           f"masking law removed it names {law}")
                elif rc2 != 0 and WARM not in out2 and named2 is None:
                    verdict = VACUOUS
                    why = (f"the gate went red naming {named or 'no law'}, and with the "
                           f"masking law removed the failure is in a HELPER, not in "
                           f"a law -- {law} cannot fail")
                else:
                    verdict = VACUOUS
                    why = (f"the gate went red naming {named or 'no law'}, and with the "
                           f"masking law removed it still names "
                           f"{named2 or 'no law'} -- the law cannot fail")
            rows.append((law, verdict, why))
            if verdict == VACUOUS:
                bad.append(f"{law}: VACUOUS -- {why}")

        # --- THE COVERAGE: every shape-fold arm, and whether a law reads it.
        for arm, laws_naming in shape_arms(control_root, laws):
            rows.append((f"ARM:{arm}", "UNPINNED" if not laws_naming else "PINNED",
                         f"laws naming it: {', '.join(laws_naming) or 'NONE'}"))

    # --- the report
    if args.rows:
        for name, state, why in rows:
            print(f"{name}\t{state}\t{why}")
    else:
        for name, state, why in rows:
            print(f"  {name:<48} {state:<9} {why}")

    vacuous = sorted(r[0] for r in rows if r[1] == VACUOUS)
    masked = sorted(r[0] for r in rows if r[1] == MASKED)
    unpinned = sorted(r[0][4:] for r in rows if r[0].startswith("ARM:") and r[1] == "UNPINNED")
    observed = {"vacuous": vacuous, "masked": masked, "unpinned-arms": unpinned}

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
    print(f"-- {len(laws)} shape laws, "
          f"{sum(1 for r in rows if r[0].startswith('ARM:'))} shape fold arms")
    print(f"-- vacuous laws: {len(vacuous)}" + (f"  {', '.join(vacuous)}" if vacuous else ""))
    print(f"-- masked laws: {len(masked)}" + (f"  {', '.join(masked)}" if masked else ""))
    print(f"-- unpinned shape arms: {len(unpinned)}"
          + (f"  {', '.join(unpinned)}" if unpinned else ""))

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
    print("OK: the census is no worse than the baseline: no shape law is more "
          "vacuous than the declared baseline")
    return PASS


def read_baseline() -> dict | None:
    """The declared baseline, or None when it is absent.

    THE FORMAT.  One `key<TAB>value` per line, the value being a comma-
    separated list, so the file is diffable and a change in it is a change in
    the claim.  A row whose list is EMPTY is written as `key<TAB>` and nothing
    else, and `str.strip()` would take the tab with it, so the row would read as
    a bare `key` and be SKIPPED -- which is how an empty baseline list becomes a
    missing key.
    """
    if not BASELINE.exists():
        return None
    out: dict = {}
    for raw in BASELINE.read_text().splitlines():
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
        "# shape-law-census.rows -- the DECLARED census of the shape half's",
        "# defects, GENERATED by `shape-law-census-gate.py --refresh`, its",
        "# ONLY writer.",
        "#",
        "# A shape law that CANNOT GO RED is vacuous, a law whose subject is",
        "# SHARED with an earlier law is masked -- the gate IS red under the",
        "# earlier law's name, so the law can fail but is never the failure",
        "# `bend` reports first -- and a shape-fold arm NO LAW READS is",
        "# unpinned: the arm may be wrong and the book says nothing.  All",
        "# three are defects THAT EXIST, so the gate compares the census with",
        "# this file and FAILS when the census gets WORSE.  A defect FIXED is a",
        "# row that disappears here.",
        "#",
        "# Git-resident and BESIDE THE GATE because `gates/artifacts/` is",
        "# `.gitignore`d and emptied before every run.",
        "",
        "vacuous\t" + ",".join(observed["vacuous"]),
        "masked\t" + ",".join(observed["masked"]),
        "unpinned-arms\t" + ",".join(observed["unpinned-arms"]),
        "",
    ]
    BASELINE.write_text("\n".join(lines))


# --------------------------------------------------------------------------- the plant
def run_plant(args) -> int:
    """THE GATE'S OWN CONTROL: it can say RED and GREEN, and it tells MASKED
    from VACUOUS.

    A census that can only print GREEN measures nothing.  FOUR cases, all
    through the SAME `check` the gate uses:

      1. the un-mutated copy is GREEN;
      2. breaking a fold ARM reddens the gate NAMING its law;
      3. breaking the SHAPE ALGEBRA reddens the gate;
      4. a law whose conclusion restates its premise stays GREEN -- the
         vacuity the gate exists to report.

    Case 4 is the one that makes the gate's own complaint falsifiable: if the
    gate said "this law is vacuous" and breaking its subject DID redden the
    gate, the gate would be wrong about its own population.
    """
    if not BEND.exists():
        print("REFUSED, NOT A VERDICT: there is no `bin/bend` in this tree")
        return REFUSED
    bad = []
    with tempfile.TemporaryDirectory(prefix="shape-law-census-plant-") as td:
        control_root = fresh_copy(Path(td) / "control")
        rc, out = check(control_root / "LAWS" / "PROOF-ALL.bend")
        ok_green = (rc == 0 and WARM in out)
        print(f"  1 control          {'GREEN' if ok_green else 'NOT GREEN'}")
        if not ok_green:
            bad.append("the control copy is not green")

        # 2 -- a fold ARM, which must redden naming its law
        target = control_root / "LAWS" / "spec.bend"
        text = target.read_text(errors="replace")
        mutated = mutate_arm(text, "SpPermute", "Sp.shape")
        if mutated is None:
            bad.append("could not mutate the SpPermute arm")
        else:
            case_root = fresh_copy(Path(td) / "case2")
            (case_root / "LAWS" / "spec.bend").write_text(mutated)
            rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
            named = named_law(out)
            ok_red = (rc != 0 and named == "permute_preserves_numel")
            print(f"  2 SpPermute arm   {'RED' if ok_red else 'NOT RED'}  naming {named or 'no law'}")
            if not ok_red:
                bad.append(f"the mutated copy did not go red naming permute_preserves_numel "
                           f"(rc={rc}, named={named})")

        # 3 -- the shape algebra, which must redden
        text = target.read_text(errors="replace")
        mutated = mutate_helper(text, "max_dim")
        if mutated is None:
            bad.append("could not mutate the max_dim helper")
        else:
            case_root = fresh_copy(Path(td) / "case3")
            (case_root / "LAWS" / "spec.bend").write_text(mutated)
            rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
            named = named_law(out)
            ok_red = (rc != 0 and named == "max_dim_idempotent")
            print(f"  3 max_dim helper   {'RED' if ok_red else 'NOT RED'}  naming {named or 'no law'}")
            if not ok_red:
                bad.append(f"the mutated copy did not go red naming max_dim_idempotent "
                           f"(rc={rc}, named={named})")

        # 4 -- a law whose conclusion restates its premise must stay GREEN
        text = target.read_text(errors="replace")
        mutated = mutate_arm(text, "SpStore", "Sp.shape")
        if mutated is None:
            bad.append("could not mutate the SpStore arm")
        else:
            case_root = fresh_copy(Path(td) / "case4")
            (case_root / "LAWS" / "spec.bend").write_text(mutated)
            rc, out = check(case_root / "LAWS" / "PROOF-ALL.bend")
            ok_green = (rc == 0 or WARM in out)
            print(f"  4 SpStore arm     {'GREEN' if ok_green else 'NOT GREEN'}"
                  f"  (store_matches_its_buffer restates its premise)")
            if not ok_green:
                bad.append("breaking the SpStore arm DID redden the gate, so the "
                           "census that calls that law vacuous is wrong")
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
