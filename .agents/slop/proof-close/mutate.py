"""Mutation harness for the two new proofs. Copies the proof set; never writes the live tree.

`MUT` SITS UNDER A DIRECTORY WHOSE NAME IS THE WARNING. It was `proof-close/mut`,
renamed to `proof-close/MUTANT` because `mut` is three characters a reading eye
skips, and these are ~290 files that shadow the real port file-for-file. The ONLY
reason a rename can work is that this constant is the sole code reference to the
path (measured: every other mention in the repo is prose or a comment). IF YOU
RENAME THE DIRECTORY, CHANGE THIS LINE; otherwise `fresh()` rmtree's the old name,
`copytree` rebuilds it, and the mutant tree you just renamed returns unlabelled.
See .agents/slop/MUT-LEDGER.md.
"""
import shutil
import subprocess
from pathlib import Path

LIVE = Path("tinybendygrad")
MUT = Path(".agents/slop/proof-close/MUTANT/tinybendygrad")
BEND = "./bin/bend"

def fresh():
    if MUT.parent.exists():
        shutil.rmtree(MUT.parent)
    MUT.parent.mkdir(parents=True)
    shutil.copytree(LIVE, MUT, ignore=shutil.ignore_patterns("*.pyc"))

def gate():
    p = subprocess.run(
        [BEND, str(MUT / "LAWS/PROOF-ALL.bend"), "--check-only"],
        capture_output=True, text=True,
    )
    text = (p.stdout + p.stderr).strip()
    first = text.splitlines()[0] if text else "NO OUTPUT"
    todos = "none"
    for line in text.splitlines():
        if "TODO" in line:
            todos = line.strip()
            break
    return first, todos, text

def apply(label, old, new):
    path = MUT / "PROOF.bend"
    text = path.read_text()
    n = text.count(old)
    if n != 1:
        print(f"{label:6} PATCH DID NOT APPLY  count={n}")
        return
    path.write_text(text.replace(old, new, 1))
    first, todos, text = gate()
    kind = "RED" if first.startswith("SOME") else "GREEN"
    print(f"{label:6} {kind:5} {first}  {todos}")
    if kind == "GREEN":
        print("         BLIND: mutation did not move the gate")

fresh()
first, todos, _ = gate()
print(f"BASE   {first}  {todos}")

# control: comment only
fresh()
apply("C1",
      "# tinyspec Reduce: \"remove the first n axes\".",
      "# tinyspec Reduce: remove the first n axes.")

# reduce induction base (empty list)
fresh()
apply("M-rb",
      """def split(ds: List<&2, S.Sdim>, n: Nat) -> {Nat.mul(S.prod(List.drop(&2, S.Sdim, ds, n)), S.prod(List.take(&2, S.Sdim, ds, n))) == S.prod(ds) : Nat}:
  match ds:
    case Nil{}:
      {==}""",
      """def split(ds: List<&2, S.Sdim>, n: Nat) -> {Nat.mul(S.prod(List.drop(&2, S.Sdim, ds, n)), S.prod(List.take(&2, S.Sdim, ds, n))) == S.prod(ds) : Nat}:
  match ds:
    case Nil{}:
      nat_add_zero(0n)""")

# reduce induction step: drop the IH rewrite, reflexivity too early
fresh()
apply("M-rs",
      """          %sswap : {_ == Nat.mul(dim, S.prod(rr)) : Nat}
          sih = Equal.sym(Nat, Nat.mul(dropp, takep), S.prod(rr), ih)
          %sih : {Nat.mul(dim, _) == Nat.mul(dim, S.prod(rr)) : Nat}
          {==}""",
      """          %sswap : {_ == Nat.mul(dim, S.prod(rr)) : Nat}
          {==}""")

# broadcast induction base
fresh()
apply("M-bb",
      """def bcast_axes(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>, ca: S.AllSN(a), cb: S.AllSN(b), same: S.SameLen(a, b)) -> {S.zip_max(a, b) == S.elem_pick(a, b) : List<&2, S.Sdim>}:
  match a:
    case Nil{}:
      match b:
        case Nil{}:
          {==}""",
      """def bcast_axes(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>, ca: S.AllSN(a), cb: S.AllSN(b), same: S.SameLen(a, b)) -> {S.zip_max(a, b) == S.elem_pick(a, b) : List<&2, S.Sdim>}:
  match a:
    case Nil{}:
      match b:
        case Nil{}:
          nat_add_zero(0n)""")

# broadcast induction step: cong the wrong tail
fresh()
apply("M-bs",
      "Equal.cong(List<&2, S.Sdim>, List<&2, S.Sdim>, f, S.zip_max(ra, rb), S.elem_pick(ra, rb), ih)",
      "Equal.cong(List<&2, S.Sdim>, List<&2, S.Sdim>, f, S.elem_pick(ra, rb), S.zip_max(ra, rb), ih)")

# delete one pre-existing proof
fresh()
apply("M-del",
      """def L.flip_preserves_numel(t, flags):
  {==}
""",
      """# deleted flip proof for the counter self-check
""")

print("LIVE UNTOUCHED", (LIVE / "PROOF.bend").stat().st_mtime)
