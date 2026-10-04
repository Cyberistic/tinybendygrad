# ===========================================================================
# THE TWELVE'S ROWS. Every expectation is `sb-oracle.py`'s printed output and
# NONE is typed. Run `sh .agents/slop/schedule-bodies/sb-gate.sh`, which diffs
# whole `name=value` LINES and never row names.
#
# `gate.code` gains ALLOC and PROGRAM. Both are NEW codes no base row reads, so
# the 81 rows are unaffected -- and `sb-gate.sh` re-checks that on every run
# rather than taking it. `usb_SA_A` NEEDS the ALLOC code: a BUFFER and an ALLOC
# are different `unsharded_base` answers and a boolean row cannot tell them
# apart. `ab_body_C_PROG` needs the PROGRAM code.
# ===========================================================================
def gate.code2(op: O.Op) -> U32:
  match op:
    case O.OpsALLOC{}  : 14
    case O.OpsPROGRAM{}: 13
    case _             : gate.code(op)

# A Python `int` slot as a `U32`: `-1` is `4294967295`. The signed RENDER matters,
# because `U32.show` would print 4294967295 where CPython printed -1 and the gate
# would go red on a port that is right. `U32.sub(0, n)` is `n`'s two's-complement
# negation, which is the ABSOLUTE VALUE for every `n` in the negative half.
def isign(n: U32) -> String:
  match U32.is_lt(n, 2147483648):
    case True{} : U32.show(n)
    case False{}: String.concat(["-", U32.show(U32.sub(0, n))])

# ---------------------------------------------------------------------------
# THE PARAM/ALLOC/CALL BUILDERS. `dev` is a `U32` TAG (CPU=0, DISK=1) because
# `S.Dev` is `D1{tag}` and the NAME is gone -- `schedule/memory.bend:189` hit this
# on `startswith(("DISK","CL","WEBGPU"))` and the treatment was a parameter.
# ---------------------------------------------------------------------------
def rb_pa(slot: U32, +nm: String, dev: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, None{}, None{}, Some{nm}, S.AGlobal{},
    Some{S.D1{dev}}, False{}, None{}, None{}, False{}, None{}}

def rb_p(slot: U32, +nm: String, dev: U32, ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{rb_pa(slot, nm, dev)}, O.TNone{})

def rb_al(slot: U32, +nm: String, ar: O.Arena) -> O.Found:
  +z = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  O.UOp.new(O.Found.ar(z), O.OpsALLOC{}, [O.Found.i(z)], O.AParam{rb_pa(slot, nm, 0)}, O.TNone{})

def rb_call(pre: Bool, +body: U32, ss: List<&2, U32>, ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsCALL{}, List.append(&2, U32, [body], ss),
    O.ACall{O.CallInfo.of(pre)}, O.TNone{})

# ONE arena for the whole rule-body fixture set, in `sb-oracle.py`'s ORDER. The
# `rb.*` readers below are INDICES INTO IT and are the ONLY thing that couples the
# fixture to the rows, so a construction-order slip is a fixture bug and is
# visible as a row that names itself.
def rb() -> O.Found:
  +pc  = rb_p(0, "c", 0, O.Arena.empty())
  +pc2 = rb_p(0, "c2", 0, O.Found.ar(pc))
  +pd  = rb_p(0, "d", 1, O.Found.ar(pc2))
  +pn  = rb_p(0, "n", 2, O.Found.ar(pd))
  +st  = g_body(1, O.Found.ar(pn))
  +bo  = O.Found.i(st)
  +k   = rb_call(True{}, bo, [O.Found.i(pc), O.Found.i(pc2)], O.Found.ar(st))
  +ks  = rb_call(True{}, bo, [O.Found.i(pd), O.Found.i(pc)], O.Found.ar(k))
  +e   = O.UOp.new(O.Found.ar(ks), O.OpsEND{}, [O.Found.i(k)], O.ANone{}, O.TNone{})
  +snk = sc_store(O.Found.ar(e), O.Found.i(pc), O.Found.i(pc2), None{})
  +al  = rb_al(7, "al", O.Found.ar(snk))
  +sab = O.UOp.new(O.Found.ar(al), O.OpsAFTER{}, [O.Found.i(pc), O.Found.i(k)], O.ANone{}, O.TNone{})
  +saa = O.UOp.new(O.Found.ar(sab), O.OpsAFTER{}, [O.Found.i(al), O.Found.i(k)], O.ANone{}, O.TNone{})
  +sas = O.UOp.new(O.Found.ar(saa), O.OpsAFTER{}, [O.Found.i(al), O.Found.i(snk)], O.ANone{}, O.TNone{})
  +sae = O.UOp.new(O.Found.ar(sas), O.OpsAFTER{}, [O.Found.i(al), O.Found.i(e)], O.ANone{}, O.TNone{})
  +an  = rb_al(4294967293, "an", O.Found.ar(sae))
  +sin = O.UOp.sink(O.Found.ar(an), [O.Found.i(sab), O.Found.i(saa), O.Found.i(sas), O.Found.i(sae)])
  +a2  = rb_al(9, "a2", O.Found.ar(sin))
  +lin = O.UOp.new(O.Found.ar(a2), O.OpsLINEAR{}, [bo], O.ANone{}, O.TNone{})
  +prg = O.UOp.new(O.Found.ar(lin), O.OpsPROGRAM{}, [bo], O.ANone{}, O.TNone{})
  +cl  = rb_call(False{}, O.Found.i(lin), [O.Found.i(pc)], O.Found.ar(prg))
  +cp  = rb_call(False{}, O.Found.i(prg), [O.Found.i(pc)], O.Found.ar(cl))
  +cn  = rb_call(False{}, bo, [O.Found.i(pc)], O.Found.ar(cp))
  +ski = O.UOp.new(O.Found.ar(cn), O.OpsSINK{}, [bo], O.AKernel{O.KernelInfo.of()}, O.TNone{})
  +lp  = rb_call(True{}, O.Found.i(sin), [O.Found.i(pc)], O.Found.ar(ski))
  O.UOp.new(O.Found.ar(lp), O.OpsCALL{}, [O.Found.i(sin), O.Found.i(pc)],
    O.ACall{O.CallInfo.of(False)}, O.TNone{})

def rb.ar() -> O.Arena: O.Found.ar(rb())
def rb.pc() -> U32: 0
def rb.pc2() -> U32: 1
def rb.pd() -> U32: 2
def rb.bo() -> U32: 4
def rb.k() -> U32: 5
def rb.ks() -> U32: 6
def rb.e() -> U32: 7
def rb.snk() -> U32: 8
def rb.al() -> U32: 9
def rb.sab() -> U32: 10
def rb.saa() -> U32: 11
def rb.sas() -> U32: 12
def rb.sae() -> U32: 13
def rb.an() -> U32: 14
def rb.sin() -> U32: 15
def rb.a2() -> U32: 16
def rb.lin() -> U32: 17
def rb.prg() -> U32: 18
def rb.cl() -> U32: 19
def rb.cp() -> U32: 20
def rb.cn() -> U32: 21
def rb.ski() -> U32: 22
def rb.lp() -> U32: 23

def rb.noarg(ar: O.Arena) -> U32:
  +z = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  O.UOp.new(O.Found.ar(z), O.OpsALLOC{}, [O.Found.i(z)], O.ANone{}, O.TNone{})

# ===========================================================================
# THE STRING ROWS. `row` takes a `U32` and several of these answers are WORDS --
# `None` for "no rewrite", `ok`/`raise` for a Python that raises -- so
# `rows` prints `name=value` from a `String` and the differ reads both the same.
# ===========================================================================
def rows(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def rb2s(x: Bool) -> String:
  match x:
    case True{} : "True"
    case False{}: "False"

def rnone(m: Maybe<&2, O.Found>) -> String:
  match m:
    case Some{f}: U32.show(gate.code2(O.Arena.op(O.Found.ar(f), O.Found.i(f))))
    case None{} : "None"

# `ca_noarg` -- an ALLOC whose arg is not an `AParam`. Python raises
# AttributeError on `b.arg.slot`; the port's `ca_arg.slot` answers `None{}` and
# `ca_fresh` is False, so the answer is `None{}`. This is the one place in the
# block where the port is TOTAL and Python RAISES, and `ca_noarg=raise` is the
# row that says so rather than a row that pretends the two agree.
def rasd(ar: O.Arena, +ast: U32) -> String:
  match assert_all_same_devices.raises(assert_all_same_devices(ar, ast)):
    case True{} : "raise"
    case False{}: "ok"

def rdevs(ar: O.Arena, +ast: U32) -> U32:
  U32.from_nat(List.length(&2, U32, Ads.ds(assert_all_same_devices(ar, ast))))

# `ca_slot1` -- the NEW node's slot, read off the INTERNED NODE and not off
# `ca_slotn`, which is only the number the port computed. Reading the node is
# what makes the row a test: a port that computed the right number and interned
# the wrong node passes the other reading.
def rca_slot(c: CaPut) -> String:
  match CaPut.a(c):
    case Some{f}: isign(ca_slot_u(O.Arena.arg(O.Found.ar(f), O.Found.i(f))))
    case None{} : "None"

def ca_slot_u(arg: O.Arg) -> U32:
  match ca_arg.slot(arg):
    case Some{v}: v
    case None{}  : 4294967295

# `ca_name1` -- the name SURVIVES the slot rewrite. A port that rebuilt the
# 13-field `ParamArg` and dropped one field passes every slot row and fails here.
def rca_name(c: CaPut) -> String:
  match CaPut.a(c):
    case Some{f}: rb_pa_name(O.Arena.arg(O.Found.ar(f), O.Found.i(f)))
    case None{} : "None"

def rb_pa_name(arg: O.Arg) -> String:
  match arg:
    case O.AParam{pa}: Maybe.default(&2, String, O.ParamArg.name(pa), "None")
    case _            : "None"

# `ca_repeat` -- the SECOND call on the same `b` returns the SAME node, so the
# IDENTITY is the row and a count would not be.
def rca_same(a: CaPut, b: CaPut) -> U32:
  match CaPut.a(a):
    case Some{f1}:
      match CaPut.a(b):
        case Some{f2}: b2u(U32.is_eq(O.Found.i(f1), O.Found.i(f2)))
        case None{}  : 0
    case None{}: 0

# THE STORES: length, the code sequence in APPEND ORDER, the duplicate identity
# and the first-element identity.
def rcs_len(c: CallifyCtx) -> U32:
  U32.from_nat(List.length(&2, U32, CallifyCtx.stores(c)))

def rcs_codes(c: CallifyCtx) -> U32:
  gate.code.of(CallifyCtx.stores(c), rb.ar(), 0)

def rcs_get(c: CallifyCtx, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, CallifyCtx.stores(c), n), 4294967295)

def rcs_same(a: Nat, b: Nat, c: CallifyCtx) -> U32:
  b2u(U32.is_eq(rcs_get(c, a), rcs_get(c, b)))

# THE EIGHT CALLS, in `sb-oracle.py`'s order: K SA_A SA_S E SA_B SA_E SA_E SA_B.
def rb.calls() -> List<&2, U32>:
  [rb.k(), rb.saa(), rb.sas(), rb.e(), rb.sab(), rb.sae(), rb.sae(), rb.sab()]

# `assert_all_same_devices`' two ASTs. SIN2 is `SINK(PC, PC2)` -- one device --
# and SIND is `SINK(PD, PC2)` -- two -- and they are ONE ROW APART, so the `>= 2`
# threshold has a row on each side of it.
def rb.sin2(ar: O.Arena) -> U32:
  O.UOp.new(ar, O.OpsSINK{}, [rb.pc(), rb.pc2()], O.ANone{}, O.TNone{}) |> (&&O.Found.i)

def rb.sin2(ar: O.Arena) -> U32:
  +f = O.UOp.new(ar, O.OpsSINK{}, [rb.pc(), rb.pc2()], O.ANone{}, O.TNone{})
  O.Found.i(f)

def rb.sind(ar: O.Arena) -> U32:
  +f = O.UOp.new(ar, O.OpsSINK{}, [rb.pd(), rb.pc2()], O.ANone{}, O.TNone{})
  O.Found.i(f)

def rb.sinn(ar: O.Arena) -> U32:
  +f = O.UOp.new(ar, O.OpsSINK{}, [rb.pd()], O.ANone{}, O.TNone{})
  O.Found.i(f)