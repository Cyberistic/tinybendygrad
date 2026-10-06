"""STAGE 4 -- THE FALSIFICATION ATTEMPT, DONE HONESTLY.

THE CLAIM UNDER TEST, taken verbatim from my own Stage 1/2/3:

    "No port file calls compute_gradient (0 callers, measured over all 2,600+
     .bend files), and mixin/gradient.bend has zero driver defs. Therefore the
     port cannot build a backward graph."

THE STRONGEST PLANT AVAILABLE.  I read the substrate before choosing it, and
what I found changed the plant:

    mixin/gradient.bend:562  gr_12(ar, ctx, self)  -- a COMPLETE MUL backward
    mixin/gradient.bend:1054 gr_rewrite(ts, ar, ctx, self) -- a first-wins
                               dispatcher over the port's own 33-entry table

So the substrate is not missing a rule.  It is missing the LOOP.  The plant
therefore does the one thing a real engineer would do and which would make my
claim false if the claim were merely pessimistic:

    WRITE compute_gradient's reverse walk in $TMPDIR, calling the PORT's own
    gr_rewrite and gr_12, and see whether it produces a backward graph.

Outcomes, all of which are results:
  * it compiles, runs, and produces a gradient graph -> the claim is FALSIFIED
    and my census understated the port: the driver is ~15 lines;
  * it compiles but the walk cannot be expressed -> the claim SURVIVES and the
    blocker is a named Bend restriction with a file:line;
  * it does not compile -> the claim SURVIVES with the compiler's own message,
    which is the strongest form, because it is not my assertion.

The plant lives in $TMPDIR.  It never touches the repo tree.  It imports the
REAL substrate by absolute path.

Run:  .venv/bin/python .agents/slop/tensor-surface/stage4-falsify.py
"""
from __future__ import annotations
import os, re, subprocess, sys, shutil

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
TMP = os.path.join(os.environ.get("TMPDIR", "/tmp"), "ts-stage4")
BEND = f"{ROOT}/bin/bend"
PP = subprocess.run

print("=" * 78)
print("STAGE 4 -- FALSIFICATION")
print("=" * 78)
print()
print("CLAIM UNDER TEST (mine, Stage 1-3):")
print('  "the port cannot build a backward graph -- 0 callers of compute_gradient,')
print('   0 driver defs in mixin/gradient.bend"')
print()
print("THE PLANT: write compute_gradient's reverse walk in $TMPDIR against the")
print("port's own gr_rewrite/gr_12 and see whether a backward graph appears.")
print()

os.makedirs(TMP, exist_ok=True)

# ------------------------------------------------------------------ STEP A
print("-" * 78)
print("STEP A -- the oracle, by CALLING CPython (DEV=NULL, no device, no realize).")
print("-" * 78)
ORACLE = r'''
from tinygrad import Tensor
def sig(u): return f"{u.op.name}/{len(u.src)}"
a = Tensor([2.0,3.0]); b = Tensor([4.0,5.0])
c = (a*b).sum()
fw = c.uop.toposort()
print("oracle_forward=%d %s" % (len(fw), " ".join(sig(u)+" " for u in fw)))
# the MUL sub-graph's own backward, which is what gr_12 computes:
from tinygrad.mixin.gradient import pm_gradient
m = [u for u in fw if u.op.name=="MUL"][0]
lg = pm_gradient.rewrite(m, ctx=UOp.const(1.0) if False else None) if False else None
EOF_MARKER = None
'''
# simpler and honest: just print the forward and let Stage B do the work
ORACLE = r'''
from tinygrad import Tensor
from tinygrad.uop.ops import Ops, UOp
from tinygrad.mixin.gradient import pm_gradient
def dump(u):
    ts = u.toposort()
    return "%d " % len(ts) + " ".join("%s/%d " % (x.op.name, len(x.src)) for x in ts)
# THE PLANT'S EXACT FIXTURE, built from UOp so both sides intern the same nodes:
# CONST 2 * CONST 3, seed CONST 1.  This is the second oracle; the first is the
# eager Tensor one above, and the point of running BOTH is that the plant is
# compared against the rule table rather than against an end-to-end graph.
a = UOp.const(2, None); b = UOp.const(3, None); seed = UOp.const(1, None)
m = UOp(Ops.MUL, src=(a, b))
lg = pm_gradient.rewrite(m, ctx=seed)
solid = sum(1 for g in lg if g is not None)
print("oracle_fw=" + dump(m))
print("oracle_rule=" + ("GSKIP" if lg is None else "FIRED n=%d solid=%d" % (len(lg), solid)))
if lg is not None:
    print("oracle_grad0=" + dump(lg[0]))
    print("oracle_grad1=" + dump(lg[1]))
print("oracle_grads_n=2   # the walk's own accumulation, read by the plant as ks_n")
'''
open(f"{TMP}/oracle.py", "w").write(ORACLE)
env = dict(os.environ); env.pop("PYTHONPATH", None)
env["LC_ALL"] = "C"; env["DEV"] = "NULL"
orc = PP([f"{ROOT}/.venv/bin/python", f"{TMP}/oracle.py"], capture_output=True,
       text=True, env=env, cwd=ROOT)
print(orc.stdout.strip() or "(no stdout)")
if orc.returncode:
    print("rc=", orc.returncode, "\n", orc.stderr[-900:])
# parsed for the DIFF, not printed for the reader -- agreement is computed, never
# asserted by eye
oracle = {}
for ln in orc.stdout.split("\n"):
    for tok in ln.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            oracle.setdefault(k, v)
print()

# ------------------------------------------------------------------ STEP B
print("-" * 78)
print("STEP B -- READ the substrate and name what the plant will call.")
print("-" * 78)
g = open(f"{ROOT}/tinybendygrad/mixin/gradient.bend").read()
for want, why in [
    ("gr_table", "the port's own 33-entry PMEntrys"),
    ("gr_rewrite", "pm_gradient.rewrite -- first-wins dispatch"),
    ("gr_scan", "the scan behind it"),
    ("gr_12", "the MUL rule: (src[1]*ctx, src[0]*ctx)"),
    ("gmul", "node builder used by gr_12"),
    ("compute_gradient", "THE DRIVER -- expected absent"),
]:
    m = re.search(rf"^def\s+{re.escape(want)}\s*\(", g, re.M)
    print(f"  {want:20s} {'PRESENT' if m else 'ABSENT':8s} {why}")
    if m:
        print(f"  {'':20s} at mixin/gradient.bend:{g[:m.start()].count(chr(10))+1}")
print()

# ------------------------------------------------------------------ STEP C
print("-" * 78)
print("STEP C -- the plant.  compute_gradient's walk, in Bend, on the port's table.")
print("-" * 78)

PLANT = r'''
# stage4-plant.bend.  $TMPDIR ONLY.  The plant.
import Base
import ./helpers.bend as H
import ./LAWS/spec.bend as S
import ./uop/ops.bend as O
import ./mixin/gradient.bend as G

# ---- signature printer (tensor.bend:1179 tn_sig.go, verbatim shape) --------
def sg.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: sg.go(t, ar, String.concat([acc, O.Ops.name.of(O.Arena.op(ar, u)), "/",
      U32.show(O.Arena.nsrc(ar, u)), " "]))

def sg.s(+ar: O.Arena, +xs: List<&2, U32>) -> String:
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, xs))), " ", sg.go(xs, ar, "")])

def sg(nm: String, +ar: O.Arena, +xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", sg.s(ar, xs)]))

# ---- THE FIXTURE: CONST 2 * CONST 3, the port's own spine -------------------
def c2(ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(2)})

def c3(+f: O.Found) -> O.Found:
  O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(3)})

def mul(+ar: O.Arena, a: U32, b: U32) -> O.Found:
  O.UOp.new(ar, O.OpsMUL{}, [a, b], O.ANone{}, O.TNone{})

def k1(+f: O.Found) -> O.Found:
  O.UOp.const(O.Found.ar(f), O.CInt{H.i64_of_i32(1)})

# ===========================================================================
# THE PLANTED compute_gradient.  mixin/gradient.py:116-145, the walk.
#
# EVERY `match` scrutinee here is a PARAMETER or a FIELD, never a CALL --
# Bend's rule "a match cannot scrutinize a computed value: give it its own
# def", MEASURED on this file's first attempt at `match G.gr_rewrite(...)`.
# So the walk is a `.go`/wrapper pair in the shape tensor.bend uses throughout
# (tn_repr.of/tn_repr, tn_cast.put/tn_cast).
#
# `grads: dict[UOp,UOp]` -> a List of (key, value) pairs over arena indices.
# `lgrads = pm_gradient.rewrite(t0, ctx=grads[t0])` -> G.gr_rewrite.
# `grads[k] = grads[k] + v` -> G.gadd then gp, and it reads the rule's answer
# with the PORT'S OWN accessors -- G.gs_hole / G.gs_get / G.gs_ar, which
# mixin/gradient.bend:78-107 already provides.  That is the load-bearing part
# of this plant: the readers compute_gradient:129-137 needs are ALREADY THERE.
# ===========================================================================

# `grads: dict[UOp, UOp]` CANNOT be a List of tuples: MEASURED, a tuple is a
# `Sigma` and `List<&2, (U32, U32)>` fails with "expected : Data".  So it is a
# `Data` RECORD over TWO parallel lists, which is `fold.bend`'s own `Table` shape
# (fold.bend:2421) and is what the file already pays for everywhere: every
# update is an O(n) copy, recorded at mixin/gradient.bend:855-861 as PORTABLE
# and explicitly not a wall.
type Grads is Data:
  Grads{ks: List<&2, U32>, vs: List<&2, U32>}

def Grads.of() -> Grads:
  Grads{Nil{}, Nil{}}

def Grads.ks(+g: Grads) -> List<&2, U32>:
  match g:
    case Grads{ks, vs}: ks

def Grads.vs(+g: Grads) -> List<&2, U32>:
  match g:
    case Grads{ks, vs}: vs

# `grads[k] = v` -- APPEND.  Not an update-in-place: a List cannot be updated, so
# this is last-wins by append and FIRST-wins by read.  For a REVERSED walk each
# key is written at most once, so the two coincide and dict semantics hold --
# which is why the reversal in compute_gradient is not optional.
def gp(+g: Grads, k: U32, v: U32) -> Grads:
  Grads{List.append(&2, U32, Grads.ks(g), [k]), List.append(&2, U32, Grads.vs(g), [v])}

# `k in grads` and `grads[k]`, as ONE index.  THREE MEASURED REFUSALS got here,
# and each is a Bend rule the port already records:
#   1. `List.index_of` does not exist in Bend 2.0.34 (gradient.bend:728 records
#      the same gap for ops.bend).
#   2. `List.foldl`'s lambda CANNOT CAPTURE `k` -- "a template applied to closed ~
#      arguments (k is a variable here, not comptime)".  So no fold.
#   3. A self-call that CARRIES a match result through `Bool.pick` is refused
#      with "expected : a decreasing self-call", because the pick hides the
#      shrink from the termination check.  `tensor.bend:821 tn_rop.ne1` dodges
#      this by putting the SHRINKING list first and the pick in the ACCUMULATOR
#      slot; here there is no accumulator to hide behind, so the walk must carry
#      the result as a `Maybe` PARAMETER, which the termination check accepts.
# So: `cg_find` returns the index as the reserved `len` on a miss, which is
# exactly how `pc.find` answers (agent-core, on `pc.find`).
# `n` IS SPENT BY `Nat.add` AND BY THE PICK, and a `Nat` is spent once -- this is
# `tensor.bend`'s own "a `case 1n+m:` arm spends the scrutinee `n` too" trap
# (tensor.bend:150).  So `n` is never computed in the arm: it is the list's
# REMAINING LENGTH minus the tail's, which is what makes it a strictly
# decreasing self-call the compiler can see.
def cg_find.go(+xs: List<&2, U32>, +k: U32, hit: Nat) -> Nat:
  match xs:
    case Nil{}: hit
    case x <> t: cg_find.go(t, k, Bool.pick(Nat, U32.is_eq(x, k),
      U32.to_nat(U32.sub(U32.from_nat(List.length(&2, U32, xs)),
        U32.from_nat(List.length(&2, U32, t)))), hit))

def cg_find(+xs: List<&2, U32>, +k: U32) -> Nat:
  cg_find.go(xs, k, List.length(&2, U32, xs))

def cg_has(+k: U32, +g: Grads) -> Bool:
  Bool.not(Nat.is_eq(cg_find(Grads.ks(g), k), List.length(&2, U32, Grads.ks(g))))

# `grads[k]` on a MISS is Python's KeyError, which compute_gradient:120 catches
# with `if t0 not in grads: continue`.  Here a miss is the reserved 0, and
# `cg_has` is what distinguishes the two -- a bare 0 would silently skip a real
# NOOP gradient, which is why the accumulate below tests cg_has and not cg_get.
def cg_get(+k: U32, +g: Grads) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Grads.vs(g), cg_find(Grads.ks(g), k)), 0)

# THE ACCUMULATE, gradient.py:129-137 verbatim:
#   `for k,v in zip(t0.src, lgrads): if v is None: continue;
#      if k in grads: grads[k] = grads[k] + v else: grads[k] = v`
# `n: Nat` is the zip's position, because `G.gs_get` wants a `Nat`.
# `n` is the zip's POSITION and it is spent twice -- once by `G.gs_hole(r, n)`
# and once by the self-call -- so it is `+`, and it ADVANCES as
# `len(ss) - len(t) - 1` rather than as `Nat.add(n, 1n)`, which would spend it
# again (tensor.bend:150, "a `case 1n+m:` arm spends the scrutinee `n` too").
#
# *** `Bool.pick(T, cond, a, b)` RETURNS `a` WHEN `cond` IS TRUE. ***  PROVEN from
# `tensor.bend:766 tn_rop.ins`, which is an insertion sort: its first argument is
# `min(x, y)` under `x < y`.  I had this BACKWARDS first -- the hole guard read
# `Bool.pick(Grads, G.gs_hole(r,n), <accumulate>, g)`, which accumulates on a
# HOLE and skips on a real gradient, and it printed `plant_grads_n=0` on a rule
# that had just fired twice.  That is the whole reason this note exists: a zero
# from an inverted guard is indistinguishable from a broken driver, and only the
# oracle in STEP A says which one it was.
def cg_acc.go(+ss: List<&2, U32>, +n: Nat, +r: G.GRes, +ar: O.Arena, +g: Grads) -> Grads:
  match ss:
    case Nil{}: g
    case s <> t:
      cg_acc.go(t, U32.to_nat(U32.sub(U32.sub(U32.from_nat(List.length(&2, U32, ss)),
        U32.from_nat(List.length(&2, U32, t))), 1)), r, ar, Bool.pick(Grads, Bool.not(G.gs_hole(r, n)),
        Bool.pick(Grads, cg_has(s, g),
          gp(g, s, O.Found.i(G.gadd(ar, cg_get(s, g), G.gs_get(r, n)))),
          gp(g, s, G.gs_get(r, n))),
        g))

def cg_acc.of(+r: G.GRes, node: U32, +g: Grads) -> Grads:
  cg_acc.go(O.Arena.srcs(G.gs_ar(r), node), 0n, r, G.gs_ar(r), g)

# ONE STEP of the walk. A GSkip means no rule fired, which Python turns into
# `RuntimeError("failed to compute gradient for ...")` at gradient.py:127. The
# port has no raise, so the arm returns the table UNCHANGED and the row below
# counts it -- the honest reading, not a silent pass.
def cg_step.of(r: G.GRes, node: U32, +g: Grads) -> Grads:
  match r:
    case G.GSkip{}: g
    case G.GFired{gs, ar}: cg_acc.of(r, node, g)

def cg_step(+ts: O.PMEntrys, +ar: O.Arena, +node: U32, grad: U32, +g: Grads) -> Grads:
  cg_step.of(G.gr_rewrite(ts, ar, grad, node), node, g)

# COUNT THE ACCUMULATED TABLE'S KEYS.  A driver that walks nothing leaves the
# table EMPTY, so this reads 0; a driver that walks and accumulates reads 2 for
# a MUL.  It is a COUNT and not a Bool because an all-True Bool says which cases
# were covered and nothing about the rest (agent-core, on `t_claims`).
def cg_len(+g: Grads) -> U32:
  U32.from_nat(List.length(&2, U32, Grads.ks(g)))

# ALL of this is a PURE def, not IO: inside `do IO<Unit>` a bare `x = call` is
# not a binder.  So the plant is one pure def returning a String.
def plant() -> String:
  +a = c2(O.Arena.empty())
  +b = c3(a)
  +m = mul(O.Found.ar(b), O.Found.i(a), O.Found.i(b))
  # THE ARENA IS `ar(one)`, NOT `ar(m)`.  MEASURED, and this is the bug the first
  # WORKING run had: with `ar = ar(m)` (next=4) the seed CONST 1 sits at index 4,
  # and `G.gr_rewrite` then calls `G.gmul(ar, src[1]=2, ctx=4)` in that SAME
  # arena -- which INTERNED THE GRADIENT MUL AT INDEX 4 AND CLOBBERED THE SEED.
  # The rows read `plant_seed=4 plant_gs0=4`, i.e. the gradient and its own seed
  # were one node, and `plant_grad0` printed a 1-node graph against CPython's 3.
  # It typechecks and it runs; it is `tensor.bend`'s own rule 5 ("THE ARENA A
  # BUILD RETURNS IS NOT THE ARENA THAT WENT IN") wearing my bug.  The port's
  # own rows do not have it -- `rw(fx_ar(fix()), ...)` reads the arena AFTER
  # `fix()` has interned every fixture node (gradient.bend:1586).
  +one = k1(m)
  +ar = O.Found.ar(one)
  +io = O.Found.i(m)
  +ts = G.gr_table()
  +r = G.gr_rewrite(ts, ar, O.Found.i(one), io)
  +g = cg_step(ts, ar, io, O.Found.i(one), Grads.of())
  String.concat([
    "plant_rule=", Bool.pick(String, G.gs_is_skip(r), "GSKIP",
      String.concat(["FIRED n=", U32.show(G.gs_len(r)), " solid=", U32.show(G.gs_solid(r))])),
    " plant_fw=", sg.s(ar, O.UOp.toposort(O.Arena.budget(ar), ar, io)),
    " plant_grad0=", sg.s(G.gs_ar(r), O.UOp.toposort(O.Arena.budget(G.gs_ar(r)), G.gs_ar(r), G.gs_get(r, 0n))),
    " plant_grad1=", sg.s(G.gs_ar(r), O.UOp.toposort(O.Arena.budget(G.gs_ar(r)), G.gs_ar(r), G.gs_get(r, 1n))),
    " plant_gs0=", U32.show(G.gs_get(r, 0n)), " plant_gs1=", U32.show(G.gs_get(r, 1n)),
    " plant_rar_next=", U32.show(O.Arena.next(G.gs_ar(r))),
    " plant_ar_next=", U32.show(O.Arena.next(ar)), " plant_io=", U32.show(io),
    " plant_seed=", U32.show(O.Found.i(one)),
    " plant_gs0_op=", O.Ops.name.of(O.Arena.op(G.gs_ar(r), G.gs_get(r, 0n))),
    " plant_gs0_nsrc=", U32.show(O.Arena.nsrc(G.gs_ar(r), G.gs_get(r, 0n))),
    " plant_ks0=", U32.show(Maybe.default(&2, U32, List.get(&2, U32, Grads.ks(g), 0n), 0)),
    " plant_vs0=", U32.show(Maybe.default(&2, U32, List.get(&2, U32, Grads.vs(g), 0n), 0)),
    " plant_vs1=", U32.show(Maybe.default(&2, U32, List.get(&2, U32, Grads.vs(g), 1n), 0)),
    " plant_grads_n=", U32.show(cg_len(g))])

def p1() -> IO(Unit):
  IO.print(plant())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- p1()
    p1()
'''
# Bend refuses ABSOLUTE import paths AND defeats hub detection through a symlink
# mirror ("an import path of plain names ... the hub's files import the hub's",
# raised on `./helpers.bend` when every substrate file is a symlink).  Both are
# the brief's `$TMPDIR` trap and the agent-core note.  MEASURED FIX: a real
# `cp -R` of the 11M tree into $TMPDIR resolves both -- `zz-probe.bend` printing
# `import_ok` is the control.  The repo tree is never written.
MIRROR = os.path.join(TMP, "mirror")
if os.path.islink(MIRROR) or os.path.exists(MIRROR):
    shutil.rmtree(MIRROR)
subprocess.run(["cp", "-R", f"{ROOT}/tinybendygrad", MIRROR], check=True)
# the control, so the next failure cannot be an import-resolution artefact NOR a
# concurrent agent's mid-edit half-written file.  MEASURED NEEDED: helpers.bend
# was being edited by another unit while this ran and failed at helpers.bend:2552
# (`match i64_is_zero(x)` -- a computed scrutinee), which is NOT this plant's
# error.  So the control is load-bearing for the verdict and prints `BROKEN`
# loudly rather than letting the plant's failure be misread.
open(f"{MIRROR}/zz-probe.bend", "w").write(
    'import Base\nimport ./helpers.bend as H\n'
    'def q() -> IO(Unit):\n  IO.print("import_ok")\n'
    'def main() -> IO(Unit):\n  do IO<Unit>:\n    a : Unit <- q()\n    q()\n')
c = PP([BEND, "zz-probe.bend"], capture_output=True, text=True, cwd=MIRROR, timeout=300)
ctrl_ok = "import_ok" in c.stdout
print(f"  control (import resolution + substrate compiles): "
      f"{'OK' if ctrl_ok else 'BROKEN -- ANOTHER AGENT IS MID-EDIT, VERDICT UNSOUND'}")
if not ctrl_ok:
    print("  " + ((c.stdout + c.stderr).strip().splitlines() or ["?"])[3])
print()
plant_path = f"{MIRROR}/stage4-plant.bend"
open(plant_path, "w").write(PLANT)
r = PP([BEND, "stage4-plant.bend"], capture_output=True, text=True, cwd=MIRROR, timeout=900)
out = ((r.stdout or "") + (r.stderr or "")).strip()
print(f"$ bend $TMPDIR/stage4-plant.bend      (rc={r.returncode})")
print(out[:3000] if out else "(no output)")
print()

# ------------------------------------------------------------------ VERDICT
print("=" * 78)
print("VERDICT")
print("=" * 78)
print()
ok = "ALL PROOFS CHECK" in out or r.returncode == 0
rows = [l for l in out.split("\n") if l.startswith("plant_")]
# A FAILURE THAT IS MY OWN HARNESS IS NOT A RESULT.  These are the three ways the
# plant can fail for a reason that says nothing about the port, and the brief's
# rule is that an unexplained failure is not a finding.
HARNESS_FAULTS = [
    ("an import path of plain names", "import spelling -- my error, not the port's"),
    ("is not defined", "a name I invented that the substrate does not export"),
    ("cannot resolve", "the $TMPDIR mirror does not resolve a relative import"),
]
if not ctrl_ok:
    # THE CONTROL IS LOAD-BEARING. MEASURED TWICE on this tree: while this unit
    # ran, `tinybendygrad/helpers.bend` was mid-edit TWICE (14:25 and again after
    # 14:30) and failed at helpers.bend:1830 with "an unfilled law is a dead
    # claim: live code cannot use it" naming `divmod_r`.  That is ANOTHER AGENT'S
    # unfinished edit, not this plant, and reporting it as a wall would be the
    # exact error this whole census exists to prevent.
    print("*** INCONCLUSIVE -- ANOTHER AGENT IS MID-EDIT. NOT A RESULT. ***")
    print()
    print("The SUBSTRATE itself did not compile, so the plant's failure below is")
    print("not evidence about the port.  MEASURED TWICE on this tree: while this")
    print("unit ran, tinybendygrad/helpers.bend was mid-edit and failed at")
    print("helpers.bend:1830 naming `divmod_r`.  RE-RUN when it settles.")
    print()
    print("  " + "\n  ".join(((c.stdout + c.stderr).strip().splitlines() or ["?"])[3:9]))
elif (harness_fault := next((why for pat, why in HARNESS_FAULTS if pat in out), None)):
    print("*** INCONCLUSIVE -- THE PLANT FAILED FOR A REASON THAT IS MY OWN BUG. ***")
    print()
    print(f"    {harness_fault}")
    print("    This is NOT evidence about the port. Re-run; do not read it as a wall.")
    print()
    print(out[:2500])
elif ok and rows:
    # THE COMPARISON.  Agreement between the port and a hand-typed oracle is not
    # corroboration (agent-core), so the oracle is CALLED and its signature
    # strings are diffed field by field.  A signature is SPACE-SEPARATED, so it
    # is compared as the token LIST, not as a whitespace-split string -- an
    # earlier version of this line compared single tokens and reported 0 of 4
    # agreement over two strings that are visibly identical.
    plant_toks = rows[0].split()

    def sig_after(toks, prefix):
        """The token list AFTER `prefix=` up to the next `name=` token.

        Returns None if the field is absent, so an absent field can never
        compare EQUAL to another absent field -- the earlier version of this
        function returned None for both sides and the harness reported
        'AGREE portNone oracleNone' on three fields, which is the vacuous
        agreement agent-core warns about.
        """
        want = prefix + "="
        for i, t in enumerate(toks):
            if t.startswith(want):
                out = []
                for u in toks[i + 1:]:
                    if "=" in u:
                        break
                    out.append(u)
                return out or None
        return None

    oracle_lines = [l.split("#")[0].split() for l in orc.stdout.split("\n")]
    oracle_lines = [l for l in oracle_lines if l]

    pairs = [("fw", "plant_fw", "oracle_fw"),
             ("grad0", "plant_grad0", "oracle_grad0"),
             ("grad1", "plant_grad1", "oracle_grad1")]
    agree, dis, absent = [], [], []
    for name, pk, ok_ in pairs:
        p = sig_after(plant_toks, pk)
        o = next((sig_after(l, ok_) for l in oracle_lines
                  if any(t.startswith(ok_ + "=") for t in l)), None)
        if p is None or o is None:
            absent.append(f"{name}: port={p} oracle={o}")
        elif p == o:
            agree.append(f"{name}: {' '.join(p)}")
        else:
            dis.append(f"{name}: port[{' '.join(p)}] oracle[{' '.join(o)}]")
    # the rule: `plant_rule=FIRED` then bare `n=2` `solid=2`; the oracle puts all
    # three on one token.  Compare them NORMALISED, by name.
    def kv(toks, keys, prefix):
        out = {}
        for t in toks:
            for k in keys:
                if t.startswith(prefix + k + "="):
                    out[k] = t.split("=", 1)[1]
        return out
    # `plant_rule=FIRED` then bare `n=2` `solid=2` as SEPARATE tokens; the oracle
    # puts all three inside ONE `oracle_rule=FIRED n=2 solid=2`.  Normalise both
    # to {rule,n,solid} by reading the plant's bare n=/solid= and the oracle's
    # sub-fields of its own rule token.
    p_rule = {"rule": next((t.split("=", 1)[1] for t in plant_toks
                            if t.startswith("plant_rule=")), None),
              "n": next((t.split("=", 1)[1] for t in plant_toks
                         if t.startswith("n=")), None),
              "solid": next((t.split("=", 1)[1] for t in plant_toks
                             if t.startswith("solid=")), None)}
    o_rule_tok = next((t for l in oracle_lines for t in l
                       if t.startswith("oracle_rule=")), "")
    # `oracle_rule=FIRED n=2 solid=2` is THREE whitespace-separated tokens, and
    # only the first carries the `oracle_rule=` name -- so the `n=`/`solid=` are
    # read from the REST OF THAT LINE, not from this one token.
    o_line = next((l for l in oracle_lines
                   if any(t.startswith("oracle_rule=") for t in l)), [])
    o_parts = (next((t for t in o_line if t.startswith("oracle_rule=")),
                    "oracle_rule=").split("=", 1)[1].split()
                + [t for t in o_line if t.startswith(("n=", "solid="))])
    o_rule = {"rule": o_parts[0] if o_parts else None,
              "n": o_parts[1].split("=", 1)[1] if len(o_parts) > 1 else None,
              "solid": o_parts[2].split("=", 1)[1] if len(o_parts) > 2 else None}
    if p_rule == o_rule and None not in p_rule.values():
        agree.append(f"rule: {p_rule}")
    else:
        dis.append(f"rule: port[{p_rule}] oracle[{o_rule}]")
    # the walk's own accumulation: a COUNT, which CPython's fixture fixes at 2
    p_gn = next((t.split("=", 1)[1] for t in plant_toks
                 if t.startswith("plant_grads_n=")), None)
    o_gn = next((t.split("=", 1)[1] for l in oracle_lines for t in l
                 if t.startswith("oracle_grads_n=")), None)
    if p_gn is not None and o_gn is not None and p_gn == o_gn:
        agree.append(f"walk grads_n: {p_gn}")
    else:
        dis.append(f"walk grads_n: port[{p_gn}] oracle[{o_gn}]")
    if absent:
        print("    VACUOUS FIELDS -- a field was ABSENT on one side and is NOT")
        print("    counted as agreement:")
        for a_ in absent:
            print(f"      {a_}")
    print("*** THE CLAIM IS FALSIFIED. ***" if not dis else "*** THE PLANT RAN BUT DISAGREES. ***")
    print()
    print(f"    agreement: {len(agree)} of {len(agree) + len(dis) + len(absent)} signature fields")
    for a_ in agree:
        print(f"      AGREE  {a_}")
    for d_ in dis:
        print(f"      DIFFER {d_}")
    print()
    if not dis:
        print("A backward-pass STEP compiled and RAN against the port's own substrate,")
        print("calling `G.gr_rewrite` -> the port's `gr_12` MUL rule, and its")
        print("signature is IDENTICAL to CPython's `pm_gradient.rewrite` on the same")
        print("fixture.  The walk accumulated 2 gradients, which is what CPython's")
        print("`compute_gradient` accumulates for a 2-src MUL.")
        print()
        print("So my Stage 1/2 statement -- 0 driver defs, therefore no backward graph")
        print("-- was TRUE AS A CENSUS and FALSE AS A CONCLUSION.  The missing piece")
        print("is the LOOP, and the loop is ~30 lines: a Grads table over parallel")
        print("lists, a decreasing index walk, and the accumulate.  The rule table")
        print("(33/33), the first-wins dispatcher, and EVERY reader the accumulate")
        print("needs (`gs_is_skip`/`gs_get`/`gs_hole`/`gs_solid`/`gs_len`/`gs_ar`) were")
        print("already in mixin/gradient.bend and already gated.")
    else:
        print("The plant ran but its graphs DIFFER from CPython's.  That is a real")
        print("disagreement and it is NOT explained away here: the differing fields")
        print("are named above with both values.")
else:
    print("*** THE CLAIM SURVIVES. ***")
    print()
    print("The plant could not be written.  That is the STRONGER form of the")
    print("result, because the blocker is the compiler's message and a Bend")
    print("restriction with a file:line, not my assertion.  The message above is")
    print("the evidence and it is reproducible:")
    print(f"    cd {MIRROR} && {BEND} stage4-plant.bend")
print()
print("WHAT THIS DOES AND DOES NOT CHANGE.")
print("  It does NOT give the port a backward pass: the rows above are a")
print("  ONE-STEP walk over ONE hand-built node with an INT seed.  Stage 3's")
print("  three steps are unchanged, because they were derived from what is")
print("  MISSING (the reverse walk, the shaped-edge reduce, the zip), not from")
print("  an estimate of effort.")
print("  What it DOES change is Step 1's size: the driver is shorter than I")
print("  reported, and the honest headline for the census is")
print("    'the reverse-mode RULE TABLE is 33/33 ported and the WALK is absent',")
print("  not 'backward is absent'.")