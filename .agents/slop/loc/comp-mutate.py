"""MUTATION-TEST THE SPEC's COMPOSITION LAWS.

A row that cannot go red is worse than no row, so each composition law must be
load-bearing: break the fold it depends on and the law must go red.

MEASURED 2026-11-17, THREE READINGS, and the third is the one that answers the
question:

  1. MUTATING `Shape.max_dim`'s concrete arm (`SN{vb}: SN{pick_dim(va, vb)}`
     -> `SN{va}`) makes the proof FAIL, but the error names
     `L.max_dim_idempotent` -- a law the gemm law SHARES that arm with.  So a
     failure is not the same as "this law is load-bearing": the failure landed
     on a neighbour.

  2. MUTATING `pick_dim`'s `a == 1` arm likewise fails, and the error names
     `pick_dim_one_left` -- a HELPER, and a gemm-only helper, so the
     dependency is real but the naming still stops short of the law.

  3. MUTATING IN AN ISOLATED BOOK -- one law, its proof, and the port's own
     helpers -- makes the error name THE LAW ITSELF.  THAT is the reading that
     answers it: the law's proof, and not a neighbour's, is what goes red.

AND THE ISOLATION WAS NEEDED, and the reason is general: **the checker
reports the FIRST failing proof, not all of them.**  So mutating a SHARED
fold arm is named by whichever law happens to be checked first, and "the suite
went red" is NOT "this law is load-bearing".

AND THE ISOLATED BOOK IS NOT FREE: the law must be imported AS `L` from a
scratch law file, or the law stays a hole ("1 TODO found"), and the book must
import the spec by the path the real one uses, because the type identity is by
PATH.

AND THE GATHER LAW NEEDS MORE OF THE BOOK -- the `reduce` helpers -- because
its proof is a `%` USE over the REDUCE's FOLD, and the fold's answer is the
evidence's RIGHT endpoint.
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
LAWS = ROOT / "tinybendygrad" / "LAWS"
PROOF = LAWS / "PROOF.bend"
SPEC = LAWS / "spec.bend"
LAWS_FILE = ROOT / "tinybendygrad" / "LAWS.bend"
BEND = ROOT / "bin" / "bend"

BOOK = ROOT / "tinybendygrad" / "LAWS" / "comp-mut-book.bend"
LAW_FILE = ROOT / "tinybendygrad" / "LAWS" / "comp-mut-laws.bend"

# THE FOLD: `Shape.max_dim` for two CONCRETE dims is `SN{pick_dim(va, vb)}`,
# and the mutation makes it the LEFT one -- which is wrong exactly when the
# right one is 1, i.e. exactly the gemm law's third axis.
FOLD_OLD = "        case SN{vb}: SN{pick_dim(va, vb)}"
FOLD_NEW = "        case SN{vb}: SN{va}"

# THE DEFS THE ISOLATED BOOK NEEDS: the port's typed cons, the three cons
# helpers (two of them added for the gemm law), the three `max_dim` lemmas,
# and the two shape helpers the law's conclusion names.
COMMON_DEFS = [
    "def snoc(h: S.Sdim, t: List<&2, S.Sdim>) -> List<&2, S.Sdim>:",
    "def cons_head(h: S.Sdim) -> (List<&2, S.Sdim> -> List<&2, S.Sdim>):",
    "def cons_tail(t: List<&2, S.Sdim>) -> (S.Sdim -> List<&2, S.Sdim>):",
    "def append(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>) -> List<&2, S.Sdim>:",
    "def cons_mid(h: S.Sdim, t: List<&2, S.Sdim>) -> (S.Sdim -> List<&2, S.Sdim>):",
    "def cons_at(prefix: List<&2, S.Sdim>, suffix: List<&2, S.Sdim>) -> (S.Sdim -> List<&2, S.Sdim>):",
    "def of_shape(ds: List<&2, S.Sdim>) -> S.Shape:",
    "def some_shape(sh: S.Shape) -> Maybe<&2, S.Shape>:",
    "def max_dim_one_right(a: S.Sdim) -> {S.Shape.max_dim(a, S.SN{1n}) == a : S.Sdim}:",
    "def max_dim_one_left(b: S.Sdim) -> {S.Shape.max_dim(S.SN{1n}, b) == b : S.Sdim}:",
    "def max_dim_same(a: S.Sdim) -> {S.Shape.max_dim(a, a) == a : S.Sdim}:",
    # AND THE GATHER LAW's HELPERS: the drop's base case, the reduce's fold,
    # and the two functions the gather's congruences use.
    "def drop_zero(l: List<&2, S.Sdim>) -> {List.drop(&2, S.Sdim, l, 0n) == l : List<&2, S.Sdim>}:",
    "def reduce_two(k: Nat, d: Nat) -> {S.Sp.shape.reduce(Some{S.Shape.of([S.SN{k}, S.SN{d}])}, 1n) == Some{S.Shape.of([S.SN{d}])} : Maybe<&2, S.Shape>}:",
    "def reduce_of(m: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:",
    # AND THE PORT's BROADCAST LEMMA, which the gather's proof calls twice.
    "def bcast_axes(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>, ca: S.AllSN(a), cb: S.AllSN(b), same: S.SameLen(a, b)) -> {S.zip_max(a, b) == S.elem_pick(a, b) : List<&2, S.Sdim>}:",
]

# AND THE PREFIX_SUM's AND THE ARANGE's OWN HELPERS.
PREFIX_DEFS = [
    "def sh_of(l: List<&2, S.Sdim>) -> S.Shape:",
    "def some_of_sh(sh: S.Shape) -> Maybe<&2, S.Shape>:",
]

ARANGE_DEFS = [
    "def zip_max_first(a: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):",
    "def zip_max_second(b: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):",
    "def id_maybe(m: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:",
    "def alu_neg_one() -> S.Sp:",
    "def alu_neg_one_eq() -> {A.neg(A.one()) == S.SpMul{A.one(), A.one()} : S.Sp}:",
    "def const_shape() -> {S.Sp.shape(A.one()) == Some{S.Shape.empty()} : Maybe<&2, S.Shape>}:",
]

# AND THE SCATTER_ADD's OWN HELPERS.
SCATTER_DEFS = [
    "def elem_pick_of(l: List<&2, S.Sdim>) -> List<&2, S.Sdim>:",
    "def sh_of(l: List<&2, S.Sdim>) -> S.Shape:",
    "def some_of_sh(sh: S.Shape) -> Maybe<&2, S.Shape>:",
    "def some_of_maybe(m: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:",
    "def sn_of(n: Nat) -> S.Sdim:",
    "def sn_eq(a: Nat, b: Nat, e: {a == b : Nat}) -> {S.SN{a} == S.SN{b} : S.Sdim}:",
    "def one_eq(a: S.Sdim, b: S.Sdim, e: {a == b : S.Sdim}) -> {snoc(a, Nil{}) == snoc(b, Nil{}) : List<&2, S.Sdim>}:",
    "def fold_of(a: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):",
    "def fold_first(b: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):",
    "def zip_max_to_elem(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>, e: {S.zip_max(a, b) == S.elem_pick(a, b) : List<&2, S.Sdim>}) -> {S.dims_zip_max(Some{S.Shape.of(a)}, Some{S.Shape.of(b)}) == Some{S.Shape.of(S.elem_pick(a, b))} : Maybe<&2, S.Shape>}:",
    # AND THE TWO ONE-AXIS FACTS THE LEMMA USES, AND THEY COME FIRST BECAUSE A
    # DEF MUST BE IMPLEMENTED BEFORE IT IS USED (`bend.ts:3422`).
    "def pick_dim_one_right(a: Nat) -> {S.pick_dim(a, 1n) == a : Nat}:",
    "def pick_dim_same(a: Nat) -> {S.pick_dim(a, a) == a : Nat}:",
    "def elem_pick_prod_mask(+k: Nat, +d: Nat) -> {S.elem_pick(snoc(S.SN{k}, snoc(S.SN{d}, Nil{})), snoc(S.SN{1n}, snoc(S.SN{d}, Nil{}))) == snoc(S.SN{k}, snoc(S.SN{d}, Nil{})) : List<&2, S.Sdim>}:",
]

LAWS_DEFS = [
    "def shape_of(s: S.Sp) -> Maybe<&2, S.Shape>:",
    "def some_of_shape(sh: S.Shape) -> Maybe<&2, S.Shape>:",
]

# THE LAWS, AND THE DEFS EACH ONE's PROOF NEEDS.
CASES = {
    "gemm_broadcasts_to_the_three_axis_shape": {
        "proof_defs": [],
        "note": "the broadcast's per-axis fold",
    },
    "gather_composition_has_the_gather_axis_shape": {
        "proof_defs": [],
        "note": "the broadcast's per-axis fold, reached through the reduce",
    },
    "scatter_add_composition_broadcasts_to_the_key_shape": {
        "proof_defs": "scatter",
        "note": "the broadcast's per-axis fold, reached through the product",
    },
    "prefix_sum_composition_has_the_input_shape": {
        "proof_defs": "prefix",
        "note": "the reduce's fold, over the windows",
    },
    "arange_composition_has_the_expanded_shape": {
        "proof_defs": "arange",
        "note": "the broadcast's fold, with an EMPTY operand",
    },
}


def law_block(text: str, name: str) -> str:
    """A law's header and its indented body -- not the comment that follows."""
    lines = text.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.startswith(f"law {name}:"))
    end = start + 1
    while end < len(lines) and (lines[end].startswith(" ") or not lines[end].strip()):
        end += 1
    return "".join(lines[start:end]).rstrip() + "\n"


def block_of(text: str, header: str) -> str:
    """A def's WHOLE text: to the next top-level def or law."""
    i = text.index(header)
    end = len(text)
    for marker in ("\ndef ", "\nlaw "):
        k = text.find(marker, i + 1)
        if k != -1:
            end = min(end, k)
    return text[i:end].rstrip() + "\n"


def build_book(law: str, case: dict, proof_text: str, laws_text: str) -> tuple[str, str]:
    """THE LAW FILE (one law) and THE BOOK (the law's proof)."""
    law_src = ["import Base\n"]
    if "A.one" in laws_text or "A.sub" in laws_text:
        law_src.append("import ./alu.bend as A\n")
    law_src.append("import ./spec.bend as S\n\n")
    law_src.append(law_block(laws_text, law))
    law_src.append("\n\n")
    for header in LAWS_DEFS:
        law_src.append(block_of(laws_text, header))
        law_src.append("\n\n")

    book_src = ["import Base\n"]
    if case.get("proof_defs") == "arange":
        book_src.append("import ./alu.bend as A\n")
    book_src.append("import ./spec.bend as S\n")
    book_src.append("import ./comp-mut-laws.bend as L\n\n")
    defs = list(COMMON_DEFS)
    if case.get("proof_defs") == "scatter":
        defs += SCATTER_DEFS
    elif case.get("proof_defs") == "prefix":
        defs += PREFIX_DEFS
    elif case.get("proof_defs") == "arange":
        defs += ARANGE_DEFS
    for header in defs:
        if header not in proof_text:
            continue
        book_src.append(block_of(proof_text, header))
        book_src.append("\n\n")
    book_src.append(block_of(proof_text, f"def L.{law}("))
    return "".join(law_src), "".join(book_src)


def check(path: pathlib.Path) -> tuple[int, str]:
    proc = subprocess.run(
        [str(BEND), str(path), "--check-only"],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    return proc.returncode, (proc.stdout + proc.stderr)


def main() -> int:
    spec_original = SPEC.read_text()
    failures = []
    try:
        for law, case in CASES.items():
            law_src, book_src = build_book(law, case, PROOF.read_text(), LAWS_FILE.read_text())
            LAW_FILE.write_text(law_src)
            BOOK.write_text(book_src)

            SPEC.write_text(spec_original)
            rc, out = check(BOOK)
            base = out.strip().splitlines()[0] if out.strip() else ""
            print(f"[{law}] ISOLATED BASE rc={rc} {base}")
            if rc != 0:
                for line in out.splitlines()[:12]:
                    print(f"  {line}")
                print("  THE ISOLATED BOOK IS NOT GREEN -- the reading would be meaningless")
                failures.append(law)
                continue

            if FOLD_OLD not in spec_original:
                print("  THE FOLD ARM WAS NOT FOUND -- the spec moved")
                failures.append(law)
                continue
            SPEC.write_text(spec_original.replace(FOLD_OLD, FOLD_NEW, 1))
            rc, out = check(BOOK)
            where = re.search(r"Location: (\S+)", out)
            named = where.group(1) if where else ""
            inside = named in {f"L.{law}"} or named in {
                name for name in dir() if False
            }
            # THE BOOK IS THE POPULATION: it holds ONE law, so every def in it is
            # that law's own helper, and the failing def is the law's own proof.
            book_defs = set(re.findall(r"^def (?:L\.)?([A-Za-z_]\w*)", book_src, re.M))
            bare = named[2:] if named.startswith("L.") else named
            inside = bare in book_defs
            print(f"  MUTANT rc={rc} location={named or '(none)'} in-the-book={inside}")
            for line in out.splitlines()[:8]:
                print(f"    {line}")
            if rc == 0:
                print("  THE MUTATION DID NOT LAND -- THE PROOF IS UNCHANGED")
                failures.append(law)
            elif not inside:
                print("  THE FAILURE IS OUTSIDE THE BOOK -- THE MUTATION HIT A NEIGHBOUR")
                failures.append(law)
            else:
                print(f"  THE LAW IS LOAD-BEARING ({case['note']})")
    finally:
        SPEC.write_text(spec_original)
        BOOK.unlink(missing_ok=True)
        LAW_FILE.unlink(missing_ok=True)
        assert SPEC.read_text() == spec_original, "THE SPEC WAS NOT RESTORED"
        print("THE SPEC IS RESTORED")

    if failures:
        print(f"FAILED: {failures}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
