#!/usr/bin/env python3
"""proof-plants.py -- can "Proofs 34/34, ALL PROOFS CHECK" go RED?

SUBJECT:    the 34 `law` declarations in tinybendygrad/LAWS.bend, read against
            the spec algebra in tinybendygrad/LAWS/spec.bend + LAWS.bend.
INSTRUMENT: `./bin/bend <book> --check-only`, whose entire output is one line:
            "ALL PROOFS CHECK" or "SOME PROOFS FAIL".
            NOTE: the string "34/34" appears NOWHERE in the output. The 34 is a
            `grep -c '^law '`. See the audit file for what that means.

Nothing here touches the live tree. Every case is a fresh copy of tinybendygrad
in a scratch dir. Every case is run TWICE.
"""
import os, re, shutil, subprocess, sys, tempfile

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
BEND = os.path.join(REPO, "bin", "bend")
SCRATCH = os.path.join(tempfile.gettempdir(), "proofplants")

def fresh(name):
    d = os.path.join(SCRATCH, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    dst = os.path.join(d, "tinybendygrad")
    shutil.copytree(os.path.join(REPO, "tinybendygrad"), dst)
    return dst

def rd(root, rel):
    return open(os.path.join(root, rel)).read()

def wr(root, rel, s):
    open(os.path.join(root, rel), "w").write(s)

def verdict(root, runs=2):
    out = []
    for _ in range(runs):
        p = subprocess.run([BEND, os.path.join(root, "LAWS/PROOF-ALL.bend"),
                            "--check-only"], capture_output=True, text=True)
        out.append((p.stdout + p.stderr).strip().splitlines()[0]
                   if (p.stdout + p.stderr).strip() else "<empty>")
    return out

# ---------------------------------------------------------------- cases
CASES = []

def case(name, note, fn):
    CASES.append((name, note, fn))

# --- PLANTS (a change to the SUBJECT or the PROOF that must go red) ---------

def plant_permute_arm(root):
    """PLANT 1: break the SUBJECT. spec.bend's SpPermute shape arm stops being
    a pass-through of src[0].shape, so permute_preserves_numel becomes false."""
    s = rd(root, "LAWS/spec.bend")
    old = "    case SpPermute{t, order}: Sp.shape(t)"
    assert s.count(old) == 1
    wr(root, "LAWS/spec.bend", s.replace(old, "    case SpPermute{t, order}: Some{Shape.empty()}"))

def plant_delete_proof(root):
    """PLANT 2: delete one proof def. `bend` must notice the law has no proof."""
    s = rd(root, "PROOF.bend")
    m = re.search(r"\ndef L\.permute_preserves_numel\(.*?\n(?=\n|def )", s, re.S)
    assert m, "proof def not located"
    wr(root, "PROOF.bend", s[:m.start()] + "\n" + s[m.end():])

def plant_pick_dim(root):
    """PLANT 3: break a SPEC HELPER the laws lean on. `pick_dim(v, v) == v` is
    exactly `max_dim_idempotent`, so `pick_dim` returning `a` unconditionally in
    the (v,v) case must break that law."""
    s = rd(root, "LAWS/spec.bend")
    old = ("def pick_dim(a: Nat, b: Nat) -> Nat:\n"
           "  match a:\n    case 1n: b\n    case _:\n"
           "      match b:\n        case 1n: a\n        case _: a\n")
    assert s.count(old) == 1, "pick_dim body not located verbatim"
    wr(root, "LAWS/spec.bend",
       s.replace(old, "def pick_dim(a: Nat, b: Nat) -> Nat:\n  0n\n"))

def plant_prod(root):
    """PLANT 4: break the SUBJECT's element-count algebra. `prod` on a Nil is
    the empty product 1n; make it 0n, so every numel law that reduces through a
    base case should go red at once."""
    s = rd(root, "LAWS/spec.bend")
    old = "def prod(ds: List<&2, Sdim>) -> Nat:\n  match ds:\n    case Nil{}: 1n"
    assert s.count(old) == 1
    wr(root, "LAWS/spec.bend",
       s.replace(old, "def prod(ds: List<&2, Sdim>) -> Nat:\n  match ds:\n    case Nil{}: 0n"))

def plant_resize_arm(root):
    """PLANT 5: a SECOND subject arm. SpReshape's shape is `dst`; make it the
    src's shape, so reshape_numel_is_the_new_shape is false."""
    s = rd(root, "LAWS/spec.bend")
    old = "    case SpReshape{t, src, dst}: Some{Shape.of(dst)}"
    assert s.count(old) == 1
    wr(root, "LAWS/spec.bend",
       s.replace(old, "    case SpReshape{t, src, dst}: Sp.shape(t)"))

# --- DISARMS (a change that must NOT move the number) -----------------------

def disarm_comment(root):
    """DISARM 1: prose. PROOF.bend's header is a 40-line essay; none of it is
    load-bearing."""
    s = rd(root, "PROOF.bend")
    wr(root, "PROOF.bend", s + "\n# DISARMED: this comment changes nothing.\n")

def disarm_dtype_rename(root):
    """DISARM 2: the brief's own trap. agent-core.md records that renaming a
    dtype NAME silently broke two name-based `match` patterns with a GREEN gate.
    spec.bend's table has fp8e4m3 and fp8e4m3fnuz at the SAME priority 10, so the
    name is load-bearing. Rename `fp8e4m3fnuz` -> `fp8e4m3FNUZ` EVERYWHERE
    (constructor + every name-keyed pattern) and see whether any of the 34 laws
    notices. They should not: no law in LAWS.bend mentions a dtype NAME."""
    s = rd(root, "LAWS/spec.bend")
    n = s.count("fp8e4m3fnuz")
    wr(root, "LAWS/spec.bend", s.replace("fp8e4m3fnuz", "fp8e4m3FNUZ"))
    # also rename in the OTHER files that pattern-match on the name, the way the
    # original incident did, so this is a faithful reproduction
    for f in ("dtype.bend", "uop/fold.bend"):
        p = os.path.join(root, f)
        if os.path.exists(p):
            t = open(p).read()
            k = t.count("fp8e4m3fnuz")
            open(p, "w").write(t.replace("fp8e4m3fnuz", "fp8e4m3FNUZ"))
            n += k
    return n

def plant_neg(root):
    """PLANT 6: break a SPEC def that a `{==}`-bodied law claims about.
    `neg_is_mul_by_minus_one` is a REFLEXIVE proof -- body `{==}` -- so it
    asserts `A.neg(a)` reduces to `SpMul{a, A.one()}`. Make neg the identity."""
    s = rd(root, "LAWS/alu.bend")
    old = "def neg(a: S.Sp) -> S.Sp:"
    assert s.count(old) == 1
    i = s.index(old) + len(old)
    j = s.index("\n\n", i)
    wr(root, "LAWS/alu.bend", s[:i] + "\n  a" + s[j:])

def plant_where_dtype(root):
    """PLANT 7: `where_takes_the_second_operand_dtype` -- plant in the
    spec.bend dtype fold, not alu.bend."""
    s = rd(root, "LAWS/spec.bend")
    old = "    case SpWhere{q, a, b}: Sp.dtype(b)                     # src[1].dtype"
    assert s.count(old) == 1, "SpWhere dtype arm not located verbatim"
    wr(root, "LAWS/spec.bend", s.replace(old, "    case SpWhere{q, a, b}: Sp.dtype(a)"))

def disarm_alu(root):
    """DISARM 3: add a WRONG def to alu.bend that no law mentions. `neg` IS the
    subject of `neg_is_mul_by_minus_one`, but its PROOF is `{==}` -- reflexive,
    so neg may be anything as long as its own definition says so. Proves the
    dtype/ALU half is a definitional mirror, not a behaviour check."""
    s = rd(root, "LAWS/alu.bend")
    wr(root, "LAWS/alu.bend",
       s + "\ndef DISARM_relu(a: S.Sp) -> S.Sp:\n  S.SpInvalid{}\n")

def run_all():
    print(f"scratch: {SCRATCH}")
    base = fresh("baseline")
    v = verdict(base)
    laws = rd(base, "LAWS.bend").count("\nlaw ")
    print(f"\nBASELINE            {v}   laws declared in LAWS.bend = {laws}")

    for name, note, fn in CASES:
        root = fresh(name)
        extra = fn(root)
        v = verdict(root)
        tag = "RED " if any("FAIL" in x for x in v) else "GREEN"
        print(f"\n{name}\n  {note}\n  -> {tag} {v}"
              + (f"  [{extra} occurrences replaced]" if extra else ""))

if __name__ == "__main__":
    for nm, nt, f in [
        ("plant1_permute_arm", "PLANT: subject. SpPermute shape arm no longer passes src[0].shape through.", plant_permute_arm),
        ("plant2_delete_proof", "PLANT: proof removed. permute_preserves_numel has no def.", plant_delete_proof),
        ("plant3_pick_dim", "PLANT: subject helper. pick_dim stops answering v for (v,v).", plant_pick_dim),
        ("plant4_prod_to_sum", "PLANT: subject. numel_of uses sum instead of product.", plant_prod),
        ("plant5_reshape_arm", "PLANT: subject. SpReshape shape returns src shape, not dst.", plant_resize_arm),
        ("disarm1_comment", "DISARM: append a comment to PROOF.bend.", disarm_comment),
        ("disarm2_dtype_rename", "DISARM: rename dtype float8_e4m3 -> fp8e4m3 in spec.bend.", disarm_dtype_rename),
        ("disarm3_alu_dead_def", "DISARM: add a wrong, unused def to alu.bend.", disarm_alu),
        ("plant6_neg_identity", "PLANT: subject. A.neg becomes the identity; neg_is_mul_by_minus_one should fail.", plant_neg),
        ("plant7_where_dtype", "PLANT: subject. SpWhere dtype arm takes operand A.", plant_where_dtype),
    ]:
        CASES.append((nm, nt, f))
    run_all()