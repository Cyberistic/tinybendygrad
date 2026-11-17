"""MUTATION-TEST the gemm composition law -- THE ISOLATED BOOK.

A row that cannot go red is worse than no row, so the new law must be
load-bearing.

MEASURED 2026-11-17, THE SHAPE OF THE PROBLEM: the checker reports the FIRST
failing proof, not all of them.  So mutating a SHARED fold arm is named by a
NEIGHBOUR's proof -- and "the suite went red" is NOT "this law is
load-bearing".  Three readings established that:

  * mutating `Shape.max_dim`'s concrete arm -> named `L.max_dim_idempotent`
    (a neighbour that shares the arm);
  * mutating `pick_dim`'s `a == 1` arm -> named `pick_dim_one_left` (a
    helper);
  * mutating a helper's own STATEMENT -> named the helper (the claim itself
    was changed, so nothing was tested).

SO THE TEST ISOLATES THE LAW: the isolated book declares ONE law -- the gemm
law, copied from `LAWS.bend` into a scratch law file -- and proves it with
the port's own helpers.  A mutation of the fold then names THE LAW OR ONE OF
ITS OWN HELPERS, and a law that cannot go red is exposed.

AND "ONE OF ITS OWN HELPERS" IS NOT A HAND LIST: the isolated book holds
ONE law, so EVERY def in it belongs to that law's proof -- and the book is
the population, read by the instrument itself.  A def outside the book is a
neighbour's.

AND THE SCRATCH LAW FILE IS IMPORTED AS `L`, because that is HOW A LAW IS
DISCHARGED: the laws live in a module, the proofs name them through that
module, and a proof file that does not import the law's module leaves the law
a hole.  MEASURED: the first attempt at this book left "1 TODO found" -- the
law -- because `def L.gemm_...` bound a name `L` that did not exist.  AND THE
BOOK ALSO IMPORTS THE SPEC AS `S`, because its helpers name the spec's
constructors (`S.SN`, `S.Sdim`).

AND THE BOOK IMPORTS THE SPEC BY THE PATH THE REAL ONE USES
(`./LAWS/spec.bend`), because the type identity is by PATH: `LAWS.bend` says
`import ./LAWS/spec.bend as S` and the spec's own constructors are named
`S.SN`, so a spec under another path is a DIFFERENT type.
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

BOOK = ROOT / "tinybendygrad" / "gemm-mut-book.bend"
LAW_FILE = ROOT / "tinybendygrad" / "gemm-mut-laws.bend"
LAW = "gemm_broadcasts_to_the_three_axis_shape"

# THE FOLD: `Shape.max_dim` for two CONCRETE dims is `SN{pick_dim(va, vb)}`,
# and the mutation makes it the LEFT one -- which is wrong exactly when the
# right one is 1, i.e. exactly the gemm law's third axis.
FOLD_OLD = "        case SN{vb}: SN{pick_dim(va, vb)}"
FOLD_NEW = "        case SN{vb}: SN{va}"

# THE DEFS THE ISOLATED BOOK NEEDS: the port's typed cons, the three cons
# helpers (two of them added for this law), the three `max_dim` lemmas, and
# the two shape helpers the law's conclusion names.
PROOF_DEFS = [
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
]

LAWS_DEFS = [
    "def shape_of(s: S.Sp) -> Maybe<&2, S.Shape>:",
    "def some_of_shape(sh: S.Shape) -> Maybe<&2, S.Shape>:",
]


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


def build_books(proof_text: str, laws_text: str) -> tuple[str, str]:
    """THE LAW FILE (one law) and THE BOOK (the law's proof)."""
    law_src = [
        "import Base\n",
        "import ./LAWS/spec.bend as S\n\n",
        law_block(laws_text, LAW),
        "\n\n",
    ]
    for header in LAWS_DEFS:
        law_src.append(block_of(laws_text, header))
        law_src.append("\n\n")

    book_src = [
        "import Base\n",
        "import ./LAWS/spec.bend as S\n",
        "import ./gemm-mut-laws.bend as L\n\n",
    ]
    for header in PROOF_DEFS:
        book_src.append(block_of(proof_text, header))
        book_src.append("\n\n")
    book_src.append(block_of(proof_text, f"def L.{LAW}("))
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
    try:
        law_src, book_src = build_books(PROOF.read_text(), LAWS_FILE.read_text())
        LAW_FILE.write_text(law_src)
        BOOK.write_text(book_src)
        rc, out = check(BOOK)
        print(f"ISOLATED BASE rc={rc} {out.strip().splitlines()[0] if out.strip() else ''}")
        if rc != 0:
            for line in out.splitlines()[:14]:
                print(f"  {line}")
            print("THE ISOLATED BOOK IS NOT GREEN -- the reading would be meaningless")
            return 1

        # THE BOOK IS THE POPULATION: it holds ONE law, so every def in it is
        # that law's own helper, and the failing def is the law's own proof.
        book_defs = set(re.findall(r"^def (L\.)?([A-Za-z_][\w]*)", book_src, re.M))
        book_names = {name for _, name in book_defs}

        if FOLD_OLD not in spec_original:
            print("THE FOLD ARM WAS NOT FOUND -- the spec moved")
            return 1
        SPEC.write_text(spec_original.replace(FOLD_OLD, FOLD_NEW, 1))
        rc, out = check(BOOK)
        where = re.search(r"Location: (\S+)", out)
        named = where.group(1) if where else ""
        bare = named[2:] if named.startswith("L.") else named
        inside = bare in book_names
        print(f"ISOLATED MUTANT rc={rc} location={named} in-the-book={inside}")
        for line in out.splitlines()[:14]:
            print(f"  {line}")
        if rc == 0:
            print("THE MUTATION DID NOT LAND -- THE PROOF IS UNCHANGED")
            return 1
        if not inside:
            print("THE FAILURE IS OUTSIDE THE BOOK -- THE MUTATION HIT A NEIGHBOUR")
            return 1
        print("THE LAW IS LOAD-BEARING")
        return 0
    finally:
        SPEC.write_text(spec_original)
        BOOK.unlink(missing_ok=True)
        LAW_FILE.unlink(missing_ok=True)
        assert SPEC.read_text() == spec_original, "THE SPEC WAS NOT RESTORED"
        print("THE SPEC IS RESTORED")


if __name__ == "__main__":
    sys.exit(main())
