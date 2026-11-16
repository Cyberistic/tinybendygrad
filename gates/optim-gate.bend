# gates/optim-gate.bend -- the gate driver for `tinybendygrad/nn/optim.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/nn/optim.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/dtype.bend as DT
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def sig.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: sig.go(t, ar, String.concat([acc, O.Ops.name.of(O.Arena.op(ar, u)), "/",
      U32.show(O.Arena.nsrc(ar, u)), " "]))

def sig.len(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

def sig.print(nm: String, +xs: List<&2, U32>, +ar: O.Arena) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(sig.len(xs)), " ", sig.go(xs, ar, "")]))

def sig(nm: String, +ar: O.Arena, i: U32) -> IO(Unit):
  sig.print(nm, O.UOp.toposort(O.Arena.budget(ar), ar, i), ar)

# and the rows read the arena off the built tensor, not off the fixture. That is
# tensor.bend's rule 5 one level up: every graph is built into an arena that GREW past
# `St.ar`, so `st_ar(s)` is the arena the four fixtures live in and the graph's nodes
# are not all in it. MEASURED: passing `st_ar(s)` printed `1 NOOP/0` for every graph
# row, because the sink's index belongs to a later arena. `sig.t` is the fix and it is
# the only correct spelling.
def sig.t(nm: String, +t: T.Tensor) -> IO(Unit):
  sig(nm, P.op_ar(t), T.Tensor.u(t))

def us.go(xs: List<&2, U32>, acc: String) -> String:
  List.foldl(~&2, ~U32, ~String, (a: String) => (x: U32) => String.concat([a, U32.show(x), ","]), xs, acc)

def us(xs: List<&2, U32>) -> String:
  us.go(xs, "")

# --- the fixture, ONE ARENA for every node in the file ------------------------

# `Tensor([1.0, 2.0], device='PYTHON')` and `Tensor([4.0, 5.0, 6.0], ...)`. The
# second is SIZE 3 on purpose: a fused fixture where every parameter has the same
# size cannot see an off-by-one in the accumulate, so `P.op_acc` would pass against a
# `pos_params` that was off by one per element.
# --- the fixture TENSORS, ONE ARENA for every node in this file --------------
#
# `Tensor([1.0, 2.0], device='PYTHON')` is slot 0, `Tensor([4.0, 5.0, 6.0], ...)` is
# slot 1, and the BUFFER (is_param False) is slot 2. The size-3 one is load-bearing:
# a fused fixture where every parameter has the SAME size cannot see an off-by-one in
# the accumulate, so `P.op_acc` would pass against a `pos_params` that was off by one
# per element. That is the brief's "include a row that pins a COUNT, not just a
# boolean" rule applied to a list rather than to a graph.
#
# every fixture takes the incoming arena. Three `Arena.empty()`s would intern the same
# nodes under the same indices and every row would still print a plausible number.
# the arena is threaded, and this is not a style point -- it is tensor.bend's rule 5,
# "the arena a build returns is not the arena that went in". `P.pbuf` RETURNS a `Found`
# carrying the grown arena, and a fixture that passed the INCOMING `ar` on to the next
# call would intern every node under index 1. It typechecks, `op_params` and
# `op_bufs` each print a single `1`, and `P.op_acc` goes on printing `0,2,5` because it
# never reads an index -- so two of the three comprehension rows would be wrong and the
# third would be right, which is exactly the shape of a gate that cannot see it. This
# is the fixture bug the header predicted, measured.
def g_a(ar: O.Arena) -> O.Found:
  P.pbuf(ar, 0, 2, S.single())

def g_c(ar: O.Arena) -> O.Found:
  P.pbuf(ar, 1, 3, S.single())

def g_bu(ar: O.Arena) -> O.Found:
  P.pbuf(ar, 2, 1, S.single())

def g_ta.put(+f: O.Found) -> T.Tensor:
  T.tn_alu.put(f)

# `bu.is_param_(False)` -- optim.py:15's `if not x.is_param`. `Tensor.is_param_`
# (tensor.py:124) is in-place in Python and RETURNS A NEW RECORD here, which is
# tensor.bend's `tn_param_old` divergence; `op_bufs` is the row that sees it.
def g_tb(ar: O.Arena) -> T.Tensor:
  T.tn_is_param_(g_ta.put(g_bu(ar)), False{})

def g_all.go2(xs: List<&2, T.Tensor>, b: T.Tensor) -> List<&2, T.Tensor>:
  List.append(&2, T.Tensor, xs, [b])

# the three fixture tensors in one pass, so the arena is threaded once instead of
# re-derived at each site, and `g_two` and `g_all` cannot disagree about the indices.
def g_all.pick(a: O.Found, +c: O.Found) -> List<&2, T.Tensor>:
  g_all.go2(List.append(&2, T.Tensor, [g_ta.put(a)], [g_ta.put(c)]), g_tb(O.Found.ar(c)))

def g_all(+ar: O.Arena) -> List<&2, T.Tensor>:
  g_all.pick(g_a(ar), g_c(O.Found.ar(g_a(ar))))

# the params only, in order -- `self.params` is what `pos_params` accumulates over
def g_two.pick(a: O.Found, c: O.Found) -> List<&2, T.Tensor>:
  List.append(&2, T.Tensor, [g_ta.put(a)], [g_ta.put(c)])

def g_two(+ar: O.Arena) -> List<&2, T.Tensor>:
  g_two.pick(g_a(ar), g_c(O.Found.ar(g_a(ar))))

# the gradient, `unwrap(t.grad)` at optim.py:55
def g_grad(ar: O.Arena) -> T.Tensor:
  T.tn_alu.put(P.pbuf(ar, 3, 2, S.single()))

# --- the `_new_optim_param` printers, ABOVE the row that uses them -----------

# `_new_optim_param`'s three arms, printed as `CONSTRUCTOR:P.numel`. The LETTER IS
# UPSTREAM'S, NOT THIS PORT'S: `optim.py:24-27` calls `Tensor.zeros` on the fused arm and on
# the `t.shape` arm and `Tensor.zeros_like` on the tuple arm, so those are the two names there
# are, and `gates/op_graph_census-oracle.py` reads its half off `Tensor.zeros.__name__` rather
# than typing a string. A port-only spelling (`P.Nz`/`P.Nzl`/`P.Nzs`) graded UNSOURCED -- driver and
# oracle agreed on a LETTER NEITHER COMPUTED, and the census's own header held that CPython
# had no name for it, which is FALSE: `_new_optim_param()[0].dtype.name` IS `f32`, and `f32`
# is no better because it is `f32` on ALL THREE ARMS.
#
# `P.Nz` and `P.Nzs` therefore print the SAME letter, and that is UPSTREAM'S ANSWER rather than a
# collapse: `optim.py:24` and `optim.py:27` both call `Tensor.zeros`. What still tells those
# two arms apart is what always told them apart -- the COUNT (1 against 2) and the P.numel (the
# fused arm returns the running total) -- and what no value ever told them apart is the
# dtype: MEASURED, shape, P.numel, device, `dtype.name` and the ENTIRE deep toposort of the
# returned tensor are IDENTICAL across the tuple and non-tuple arms.
#
# The tag is still what says WHICH ARM fired: a `_new_optim_param` that always took the fused
# arm would print `zeros` ONCE and every count row would still match. That is the row the tag
# exists for.
def nop_name(n: P.NewOpt) -> String:
  match n:
    case P.Nz{n}: "zeros"
    case P.Nzl{sz}: "zeros_like"
    case P.Nzs{sz}: "zeros"

def nop_n(n: P.NewOpt) -> U32:
  match n:
    case P.Nz{n}: n
    case P.Nzl{sz}: sz
    case P.Nzs{sz}: sz

def nop_names(ns: List<&2, P.NewOpt>, acc: String) -> String:
  match ns:
    case Nil{}: acc
    case +n <> t: nop_names(t, String.concat([acc, nop_name(n), ":", U32.show(nop_n(n)), ","]))

# an P.Optim with EVERY field at its default, which is all `_new_optim_param` reads:
# `self.fused` (False), `self.device` and `self.params`.
#
# THE DEVICE IS THE ONE PARAMETER, and it is a parameter rather than the literal
# `S.D1{0}` because `P.op_nop.arm` selects on the device's CLASS and nothing else: a
# fixture pinned to one class can never reach the other arm, so a pinned fixture
# gates one arm and reports nothing about the other. `S.Dn{[6, 0]}` is the
# two-device list `device.bend:344 symbol=reg_has tag_of` interns DISK into (6) alongside a tag-0
# device, and `schedule/memory.bend:979 symbol=mem_buf` already mints `S.Dn{[2, 3]}`, so the
# multi-device spelling needs no interner and no missing symbol.
def g_opt.on(d: S.Dev) -> P.Optim:
  P.Optim{O.Arena.empty(), Nil{}, Nil{}, d, S.single(), False{}, 0, Nil{},
    Nil{}, 0.9, 0.999, 0.00000001, 0.0, True{}, 0, 0, Nil{}, Nil{},
    0.9, 0, Nil{}, False{}, True{}, True{}, 0.0}

# --- 1-4: the two comprehensions, the accumulate, and `_new_optim_param` ------

# optim.py:13. The ARENA INDEXES are what this row compares, not the numels: the
# oracle prints `t.numel()` because Python has no index, and the port's `params` are
# indices into the arena the fixture built. Both sides are `[2, 3]` for sizes and
# `[1, 2]` for indices -- arena index 0 is the BOTTOM sentinel ops.bend parks there,
# so the three fixture nodes are 1, 2 and 3.
def t_params() -> IO(Unit):
  row("op_params", String.eq(us(P.op_filter.of(True{}, g_all(O.Arena.empty()))), "1,2,"))

def t_bufs() -> IO(Unit):
  row("op_bufs", String.eq(us(P.op_filter.of(False{}, g_all(O.Arena.empty()))), "3,"))

# THE COUNT ROW, and it compares the JOINED STRING rather than a Bool per element,
# because `pos_params` is what `schedule_step`'s fused slice indexes by POSITION
# (optim.py:53) and a set would lose the order. `[2, 3]` gives `0,2,5`: the
# `initial=0` at the head is the difference between `[2,5]` and `[0,2,5]`.
def t_acc() -> IO(Unit):
  row("op_acc", String.eq(us(P.op_acc(g_two(O.Arena.empty()))), "0,2,5,"))

# `P.op_nop` (not `P.op_nop.arm`) on purpose: the arm form takes the arena as a PARAMETER
# and this row has no arena to hand it, while the record carries the one its params
# were built in. A row that passed a fresh `Arena.empty()` would read every shape as
# the fold's bottom and print two zeros -- which is the mistake this comment prevents.
#
# NO `t_nop.of3`, AND THAT DELETION IS THE FIX: one helper holding the expectation made
# the two arms share a cell, so a fixture that reached one of them had to be edited away
# from the other. Each row below carries its OWN device and its OWN expected string, and
# the two literals disagree on the LETTER -- `zeros:2,zeros:3,` against `zeros_like:2,zeros_like:3,`.
# and that is not the whole of the discrimination, which is why there is a third row: two
# literals that differ do not stop a single edit from satisfying both at once, and
# `t_nop.tag`'s comment below names the edit and the two green rows it produced. What the
# differing literals DO buy is that each row fails if its own fixture stops reaching its own
# arm, which is the reading to take from the first two and not more than the reading.

# the record carries the arena its params live in, and that is load-bearing rather
# than tidy: `P.op_nop` reads each param's shape through `o.ar`, so a record built with
# an `Arena.empty()` reads every P.numel as the fold's bottom. MEASURED: with the arena
# unthreaded, `P.op_nop` printed `P.Nzs:0,P.Nzs:0` while `op_params`, `op_bufs` and `P.op_acc`
# were all CORRECT. Three rows right and one wrong is the shape of a gate that does not
# know which of its rows can see a given bug, so the row builds the record from the
# same fixture the other rows use.
# `P.Optim.ar` is the FIRST field, so rebuilding the record with a different arena is the
# whole of "where do these indices live". It is a def rather than a projection because
# a projection is not an expression, and it is a def rather than a `match` arm because
# `P.Optim` has twenty-four fields and only one of them changes.
def op_with_arena(o: P.Optim, ar: O.Arena) -> P.Optim:
  match o:
    case P.Optim{ar0, params, buffers, device, param_dtype, fused, lr, pos_params, b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v, momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}:
      P.Optim{ar, params, buffers, device, param_dtype, fused, lr, pos_params,
        b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v,
        momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}

# THE LAST TENSOR'S ARENA, not the first's, and that is not a preference: each build
# grows the arena, so the FIRST param's arena does not contain the SECOND param's node
# and reading it answers the fold's bottom. `op_last_ar` walks to the end.
def op_last_ar(xs: List<&2, T.Tensor>, d: O.Arena) -> O.Arena:
  match xs:
    case Nil{}: d
    case x <> t: op_last_ar(t, T.Tensor.ar(x))

def g_opt.grown.on(d: S.Dev, +xs: List<&2, T.Tensor>) -> P.Optim:
  op_with_arena(P.op_set_params(g_opt.on(d), P.op_filter.of(True{}, xs)), op_last_ar(xs, O.Arena.empty()))

# the one-argument form is not a convenience, it is a peer's entry point.
# `gates/op_graph_census.bend:293` calls `Op.op_nop(Op.g_opt.grown(Op.g_two(...)))` with
# ONE argument, and that file is not this unit's to edit, so `g_opt.grown` keeps its
# arity and its `S.D1{0}` and the device-parameterised form is the sibling. MEASURED: the
# census gate's `nop=` row is byte-identical before and after this change.
def g_opt.grown(+xs: List<&2, T.Tensor>) -> P.Optim:
  g_opt.grown.on(S.D1{0}, xs)

# one row per arm, and each row builds its own arena and its own record. `P.op_nop.dn` is
# the `S.Dn` arm of `P.op_nop.arm` (optim.py:26, `isinstance(self.device, tuple)`), whose
# body is `Tensor.zeros_like` rather than `Tensor.zeros` -- `zeros_like` against `zeros`.
def t_nop() -> IO(Unit):
  row("op_nop", String.eq(nop_names(P.op_nop(g_opt.grown.on(S.D1{0}, g_two(O.Arena.empty()))), ""), "zeros:2,zeros:3,"))

def t_nop.dn() -> IO(Unit):
  row("op_nop.dn", String.eq(nop_names(P.op_nop(g_opt.grown.on(S.Dn{[6, 0]}, g_two(O.Arena.empty()))), ""), "zeros_like:2,zeros_like:3,"))

# the printer's own row, and it is the one that makes the two above non-vacuous. Both of them
# compare `nop_names`' OUTPUT against a literal, so any edit that moves the output and the
# literal together leaves them green -- MEASURED, and this row was written because it did:
# collapsing `nop_name`'s `zeros_like` arm to `zeros` AND replacing `op_nop.dn`'s expectation with
# `P.op_nop`'s printed `P.op_nop=True` AND `P.op_nop.dn=True` at rc=0 with the `zeros_like`/`zeros`
# distinction GONE. The vacuity route never hands both rows one string; it collapses the
# PRINTER until both rows read the same line, and only `P.op_nop.dn`'s literal has to move
# because `P.op_nop`'s was already `zeros`. This row builds the three `P.NewOpt`s BY HAND, so
# nothing in `P.op_nop.arm`, in the fixtures or in the device can reach it, and it pins all
# THREE TAGS -- including `P.Nz`, which no `P.op_nop` fixture can print and which prints the SAME
# letter as `P.Nzs` because upstream calls `Tensor.zeros` from both. THAT IS THE NINTH
# CAUSE, "the witness is a separate def": the witness for a printer is a row of its own,
# because every other row's use of it is a comparison whose other operand moves with it.
def t_nop.tag() -> IO(Unit):
  row("op_nop.tag", String.eq(nop_names([P.Nz{7}, P.Nzl{7}, P.Nzs{7}], ""), "zeros:7,zeros_like:7,zeros:7,"))

# --- 5-13: the GRAPH rows ------------------------------------------------------
#
# These are the rows the unit exists for. `optim.py`'s `_step` is PURE graph
# construction -- no Buffer, no realize, no `.data()` -- so the same graph is available
# on both sides and CPython prints its toposort as the oracle.
#
# the fixtures are handles, and that is wall 1 applied to the oracle as well as to
# the port. Python's `self.b[i]` is a `Tensor.zeros` whose graph is six nodes
# (`ALLOC/CONST/CAST/CONST/EXPAND/STORE/AFTER`) that are `empty_like` -- device state
# the port does not build. So the ORACLE REPLACES the momentum buffer with a plain
# `Tensor([0.0, 0.0], device='PYTHON')` and the port receives a BUFFER index. Both
# sides then see one BUFFER and the six-node prefix is gone from BOTH. A reader who
# compares against an unreplaced oracle sees six extra nodes and should read this.
#
# ONE ARENA PER ROW, threaded through every fixture, because an arena index means
# nothing outside its arena -- and ONE `g_step()` CALL PER ROW, which is the same rule
# from the other side. A row that called `g_step()` twice built its fixtures in TWO
# arenas and then read the graph out of the first: measured, every graph row printed
# `1 NOOP/0`, because the index it toposorted was 0 and index 0 is the BOTTOM sentinel.
# A row that prints a signature of length one is the tell, and that is why the `n=` is
# the first thing every signature row prints. `St` is the four fixtures each row needs -- the parameter,
# the gradient, the momentum buffer and the learning rate -- and it is ONE def so no
# two rows can disagree about them.
type St is Data:
  St{ar: O.Arena, t: U32, g: U32, b: U32, lr: U32}

# THE LEARNING RATE IS A CONST, not a BUFFER. Python's `self.lr` is
# `Tensor([lr])` (optim.py:20), and every `_step` fixture's toposort shows it as
# `BUFFER/0` -- so it IS a buffer on the oracle side and a CONST here, which is a
# DESIGNED divergence and the reason it is called out: a CONST is what `Tensor(lr)`
# reduces to once `full`'s `empty_like` is not built, and WALL 1 already said the
# materialization is the caller's. the rows that use `lr` are the ones that would
# SEE IT, so each prints its own signature and the difference is one CONST.
def st_of(f: O.Found, h: O.Found, j: O.Found, +lr: O.Found) -> St:
  St{O.Found.ar(lr), O.Found.i(f), O.Found.i(h), O.Found.i(j), O.Found.i(lr)}

# the three buffers and the CONST in one arena, and each is threaded off the
# PREVIOUS one's `Found` -- four `Arena.empty()`s would intern all four at index 1 and
# every graph row would print a plausible graph over the wrong nodes. The chaining is
# written out rather than looped because a `fold` over a list of `Found`s is the one
# shape this file has no business introducing.
def st_t.ar(ar: O.Arena) -> O.Found:
  P.pbuf(ar, 0, 2, S.single())

def st_g.ar(ar: O.Arena) -> O.Found:
  P.pbuf(ar, 1, 2, S.single())

def st_b.ar(ar: O.Arena) -> O.Found:
  P.pbuf(ar, 2, 2, S.single())

def st_lr.ar(ar: O.Arena) -> O.Found:
  P.pbuf(ar, 3, 2, S.single())

def g_step.of(t: O.Found, g: O.Found, +b: O.Found) -> St:
  st_of(t, g, b, st_lr.ar(O.Found.ar(b)))

def g_step() -> St:
  g_step.of(st_t.ar(O.Arena.empty()), st_g.ar(O.Found.ar(st_t.ar(O.Arena.empty()))),
    st_b.ar(O.Found.ar(st_g.ar(O.Found.ar(st_t.ar(O.Arena.empty()))))))

def st_ar(s: St) -> O.Arena:
  match s:
    case St{ar, t, g, b, lr}: ar

def st_t(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: t

def st_g(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: g

def st_b(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: b

def st_lr(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: lr

# --- 5: `_apply_update`, optim.py:60 -----------------------------------------
#
# `t.detach() - up.to(t.device)`. the row is chosen for its two arities: elementwise.py:43
# is `return self.alu(Ops.DETACH)`, a ZERO-src node, and the SUB is a ONE-src alu.
# A `_apply_update` that inlined the DETACH or that dropped the `.to()` (WALL: the COPY
# is a device wall and the header says it is dropped) prints `DETACH/1` or no DETACH,
# and either would move this row.
def t_apply.of(+s: St) -> IO(Unit):
  sig.t("unverified_apply", P.op_apply(P.op_detach(st_ar(s), st_t(s)), st_g(s)))

def t_apply() -> IO(Unit):
  t_apply.of(g_step())

# --- 6: LARS with tcoef=0, so `r = 1.0` (optim.py:112, :116, :119) -----------
#
# The MINIMAL `_step`: no trust ratio, no weight decay, no momentum. What survives is
# `g * r * self.lr` -- two MULs and one CONST. It is in the table because it is the
# row a first-wins-vs-conjunction bug CANNOT see (there is nothing to disagree about)
# and because it is the baseline every other LARS row is read against.
# `tcoef = 0` so `r = 1.0` at optim.py:116, and the row is `g * r * self.lr` -- two
# MULs and one CONST.
def op_lars0(+s: St) -> T.Tensor:
  P.op_lr_mul(st_ar(s), st_g(s), T.tn_const(st_ar(s), O.CFloat{1.0}), st_lr(s))

def t_lars0.of(+s: St) -> IO(Unit):
  sig.t("unverified_lars0", op_lars0(s))

def t_lars0() -> IO(Unit):
  t_lars0.of(g_step())

# --- 7: the TRUST RATIO, optim.py:113-115 ------------------------------------
#
# TWENTY-FOUR NODES and the row is worth all of them. It pins, in one signature:
# `square` is `MUL(self, self)` (elementwise.py:575) and not a SQUARE op; `.sum()` is a
# REDUCE (reduce.py:20) over EVERY axis and not a `sum` shape change; `sqrt` is
# `Ops.SQRT` and not a POW; `div` is `MUL` by a RECIP (elementwise.py:250) and not
# a DIV; `where` is the TERNARY `Ops.WHERE` with src order (q, x, y) (elementwise.py:426);
# and the two nested WHEREs are built OUTERMOST FIRST, which is the order the source
# reads in. There is no fixture trick here at all: every one of those is a wrong-op bug
# a reviewer would have to catch by reading, and this row catches it by printing.
def t_trust.of(+s: St) -> IO(Unit):
  sig.t("unverified_trust", P.op_trust(st_ar(s), st_t(s), st_g(s), 0.0, 0.001))

def t_trust() -> IO(Unit):
  t_trust.of(g_step())

# --- 8: pre_wd, optim.py:117 --------------------------------------------------
#
# `g = g + self.wd * t.detach()`. THREE nodes, and the row is here for the FLOAT ON THE
# LEFT: `_broadcasted` (elementwise.py:24) returns `(self, y) if not reverse else ...`
# and `__mul__` passes `reverse=False`, so the CONST is src[0]. A port that wrote
# `P.op_mul(ar, detach, wd)` typechecks, prints `MUL/2` identically, and is WRONG.
def t_prewd.of(+s: St) -> IO(Unit):
  sig.t("unverified_prewd", P.op_prewd(st_ar(s), st_g(s), st_t(s), 0.1))

def t_prewd() -> IO(Unit):
  t_prewd.of(g_step())

# --- 9: the ASSIGN SPINE, optim.py:121 ---------------------------------------
#
# `self.b[i].assign(self.momentum * self.b[i] + g)`. The `STORE/2 AFTER/2` pair at the
# end IS the assign: `tn_assign_store` is tensor.bend's and it is the node that makes
# this in-place in Python. A `_step` that computed the new buffer without assigning
# would print `MUL/2 ADD/2` and stop, and this row is the only one that sees it.
def t_mom.of(+s: St) -> IO(Unit):
  sig.t("unverified_mom", P.op_mom(st_ar(s), st_b(s), st_g(s), 0.9))

def t_mom() -> IO(Unit):
  t_mom.of(g_step())

# --- 10: nesterov, optim.py:122 ----------------------------------------------
#
# `g = (g + self.momentum * self.b[i]) if self.nesterov else self.b[i]`. `Bool.pick`
# is STRICT in Bend, so BOTH arms are built and the node count is the UNION of the two
# branches -- which is why this row's count is larger than `op_mom`'s and NOT a sign
# that the else arm leaked. It is stated here because it is the one place in this file
# where the port's graph is provably LARGER than Python's.
def t_nesterov.of(+s: St) -> IO(Unit):
  sig.t("unverified_nesterov", P.op_nesterov(st_ar(s), st_g(s), st_b(s), 0.9, True{}))

def t_nesterov() -> IO(Unit):
  t_nesterov.of(g_step())

# --- 11: LAMB, optim.py:167-178 ----------------------------------------------
#
# THE BIGGEST ROW, and the only one that exercises `cast` and `sqrt` and a second
# `assign`. It pins `(1.0 - self.b1)` being a PYTHON float folded at trace time (there
# is NO node for it -- a port that built one would print an extra SUB), `b1_t` being a
# TENSOR divisor rather than a scalar (so the CONST is a real node), and the two moment
# updates each carrying their own `STORE/2 AFTER/2`.
# `m_hat / (v_hat.sqrt() + self.eps)` then `+ self.wd * t.detach()`, optim.py:171.
# `m_hat / (v_hat.sqrt() + self.eps)` then `+ self.wd * t.detach()` -- optim.py:171.
# the row compresses the two moments into one variable on purpose: `v_hat.sqrt()` is
# `.sqrt()` of the SECOND moment, and `op_lamb` feeds it the first, so what this row
# pins is the SHAPE of the expression (a DIV by a SQRT-plus-eps, then an ADD of a
# float-times-detach) rather than LAMB's full moment bookkeeping. `op_lamb_extra`
# below is the COUNT row for the bookkeeping this row does not model.
def op_lamb_of.eps(+ar: O.Arena, +m: T.Tensor) -> T.Tensor:
  P.op_add(P.op_sqrt(m), T.tn_const(ar, O.CFloat{0.00000001}))

def op_lamb_of(+m: T.Tensor, +s: St) -> T.Tensor:
  P.op_add(P.op_div_t(m, op_lamb_of.eps(P.op_ar(m), m)),
    P.op_mulf(st_ar(s), 0.01, P.op_detach(st_ar(s), st_t(s))))

def op_lamb.of(m: T.Tensor, +s: St) -> T.Tensor:
  P.op_lamb_up(op_lamb_of(m, s), T.tn_const(st_ar(s), O.CFloat{1.0}),
    T.tn_wrap_uop(st_ar(s), st_lr(s)))

def op_lamb(+s: St) -> T.Tensor:
  op_lamb.of(P.op_mstep(st_ar(s), st_b(s), st_g(s), 0.9), s)

def op_lamb_of_r2(+ar: O.Arena, +m: T.Tensor, +s: St) -> T.Tensor:
  op_lamb_of(m, s)
def t_lamb.of2(u: T.Tensor, ar: O.Arena) -> IO(Unit):
  sig.t("unverified_lamb", u)

def t_lamb.of(+s: St) -> IO(Unit):
  t_lamb.of2(op_lamb(s), st_ar(s))

def t_lamb() -> IO(Unit):
  t_lamb.of(g_step())

# the file's own `main`, and its honest state. six value rows and seven graph rows.
#
# THE ARENA PLUMBING IS FINISHED. `gates/op_graph_census-gate.py` drives each builder directly
# and diffs the deep toposort (with each node's arg) against CPython's own graph; as of
# 2026-10-09 all 24 graph rows and the four value rows of the day match, and the seven rows below that
# used to print `1 NOOP/0` (or a one-node graph) now print CPython's exact trees. The
# `unverified_*` NAMES ARE HISTORICAL, kept only so this file's own output is stable.
#
# the one divergence that is not a graph defect: `P.op_1mb`'s `(1.0 - self.b1)` is a double
# subtraction in CPython and an f32 one here, so the `mstep`/`vstep` CONSTs differ by one ULP.
# MEASURED: CPython double-then-cast answers 0x3dcccccd, the port's f32 answers 0x3dccccd0, and
# NO f32 operand within +-200000 ULP of the f32 literal reproduces CPython's bits under `1 - v`.
#
# "BEND HAS NO f64, SO IT CANNOT BE CLOSED" IS TOO STRONG, and the correction matters because it
# says who can close it. `self.b1` is a CONSTRUCTOR PARAMETER (default 0.9) and `F32.from_bits`
# EXISTS (`base.bend:53`), so a CALLER that knows the double -- the default, or any literal --
# can close it by building the CONST with the double-computed-then-cast bits. What cannot be
# closed is the GENERAL case: `P.op_1mb` receives an f32 `b1` and cannot recover the double that
# produced it. So the pin is honest for the general case and a literal-defaults caller could
# drop it; the gate declares it either way.
#
# GREW it and then built the consuming node in the PRE-GROWTH arena, at the index the const
# took -- the const was orphaned and the consumer's `src[0]` was its own index, a self-loop
# that made `toposort` answer `0`. The fix is one spelling: every two-operand node merges its
# operands' arenas (`tn_binop`) and every three-operand node is `tn_where`.

# the seven rows above, printed under names that say what they are.
def t_unverified() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_apply()
    b : Unit <- t_prewd()
    c : Unit <- t_lars0()
    t_trust()

def t_unverified3() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_mom()
    t_nesterov()

def t_unverified2() -> IO(Unit):
  t_lamb()

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_params()
    b : Unit <- t_bufs()
    c : Unit <- t_acc()
    t_nop()
    t_nop.dn()
    t_nop.tag()
    d : Unit <- t_unverified()
    e : Unit <- t_unverified3()
    t_unverified2()

# THE MUTATION TABLE, MEASURED, and it is SHORT because only the rows below are claims.
#
# THE TABLE IS ALSO A HARNESS NOW. The prose here was typed by hand, which is a claim, so every
# entry below is re-runnable and the runs are what the third column says:
#
#     .venv/bin/python gates/optim-nop-mutate.py     # 11 entries, 13 rows of base
#
# four of its eleven find-strings are now stale and it will say so. `nop_name` stopped
# printing the port-only `P.Nz`/`P.Nzl`/`P.Nzs` and prints upstream's constructor names instead
# (`zeros` / `zeros_like`), which moves the text of P2, P4, Z1 and, through them, P5. The
# harness REFUSES a pattern it cannot match uniquely and prints `REFUSED` per entry rather
# than reporting a green it did not measure -- MEASURED, `gates/optim-nop-mutate.py:142-143`
# is `text.replace(...) if text.count(f) == 1 else None` -- but it still exits 0, so the
# refusal is in its OUTPUT and not in its `$?`. That harness is another unit's file; the four
# strings it needs are its own table rows and this file's three `nop_name` arms.
#
# it reads this file's own `main`, writes a COPY beside it (`optim-mut.bend`, `.gitignore`d),
# and never writes this file. Eleven entries: four of these rows, five plants that must turn an
# arm red, and two that are expected to move nothing with the cause named beside them.
#
# | mutation | the edit | rows that MOVED | what it was testing |
# | --- | --- | --- | --- |
# | M1 | `P.op_acc`: `P.op_acc.go(params, [0])` -> `(params, Nil{})` | `P.op_acc` | `initial=0` at the HEAD of `itertools.accumulate` (optim.py:22). Without it the prefix sum is `[2,5]` and the fused slice bounds at :53 are off by one for every parameter. |
# | M2 | `P.op_filter.t`: `True{}` -> `False{}` | `op_params` `P.op_nop` `P.op_nop.dn` | optim.py:13's `if x.is_param`, the half of the pair that :15's `if not x.is_param` is written against. `P.op_nop` moves too because it builds its `params` through the same filter, so the row that reads shapes is downstream of the row that selects tensors. `P.op_nop.dn` joined it when the second row landed, which is the price of a second row and is paid here in the open. |
# | M3 | `P.op_nop.arm`: the `S.Dn{tags}` arm -> `P.map_nzs` | `P.op_nop.dn` | closed. This row read nothing and the reason it gave was measured FALSE: "a `Dn` fixture would un-gate the `D1` arm". It would not have, and the mechanism is that `P.op_nop` was one row with one fixture and the device was hardcoded inside `g_opt` -- so *any* `Dn` fixture was a replacement, because there was no second row to put it in. Nothing needed a symbol: `device.bend:344 symbol=reg_has tag_of` interns two names into two distinct tags (disk gets 6, everything else 0), so `S.Dn{[6, 0]}` needs no interner, and `schedule/memory.bend:979 symbol=mem_buf` already mints `S.Dn{[2, 3]}`. The fix is `P.op_nop.dn` above, and `g_opt.grown` keeps its one argument because `gates/op_graph_census.bend:293` calls it with one. measured on the shipped tree, not on a copy: M3 moves `P.op_nop.dn` and nothing else -- `P.op_nop` is unaffected, which is the whole claim. |
# | M4 | a no-op edit | NOTHING | a control, and its zero is a VACUOUS EDIT rather than a gap: a mutation table with no row that CANNOT move is a table of coincidences. |
# | P1 | `g_opt.on` ignores its `d` and writes `S.D1{0}` | `P.op_nop.dn` | the PLANT for "a later fixture edit". It edits the def BOTH rows call, not the row, which is what such an edit is in practice. `P.op_nop` stays green. |
# | P2 | `P.op_nop.dn`'s expectation `zeros_like:2,zeros_like:3,` -> `zeros:2,zeros:3,` | `P.op_nop.dn` | HALF the vacuity edit, and on its own it does NOT make the new row vacuous: the `Dn` fixture still prints `zeros_like`. |
# | P3 | `P.op_nop.dn`'s fixture `S.Dn{[6, 0]}` -> `S.D1{0}` | `op_nop.dn` | the prior unit's three-token edit, re-measured on the row it belongs to. Its damage is now LOCAL; before this change it landed on `P.op_nop`. |
# | P4 | `nop_name`'s `Nzl` arm -> `"zeros"` | `op_nop.dn` `op_nop.tag` | the PRINTER's letters collapse. `ptx.bend`'s alias-defect shape, where every fixture put the aliased node at one position. |
# | P5 | P2 and P4 together | `P.op_nop.tag` | the vacuity plant, and it is why `P.op_nop.tag` exists. With only `P.op_nop` and `P.op_nop.dn`, this pair left both green at rc=0 -- measured, once, before the third row existed -- with the `zeros_like`/`zeros` distinction that is the whole of the two arms gone. "The two expectations are mutually exclusive" is not a guard: the vacuity route never hands both rows one string, it collapses the printer until both read the same line, and only `P.op_nop.dn`'s literal has to move because `op_nop`'s was already `zeros`. `P.op_nop.tag` builds the three `P.NewOpt`s by hand, so nothing in `P.op_nop.arm`, in the fixtures or in the device reaches it. |
# | Z1 | `nop_name`'s `P.Nz` arm -> `"zeros_like"` | `P.op_nop.tag` | the `P.Nz` TAG, which no `P.op_nop` fixture can print, and which prints `zeros` rather than a letter of its own because `optim.py:24` and `:27` both call `Tensor.zeros`. Closed by `P.op_nop.tag`. |
# | Z2 | `P.op_nop.arm`'s `case True{} _` -> `[P.Nzs{P.op_last(pp)}]` | nothing | the one measured limit left in this file: dead arm. Every `g_opt.on` record has `fused=False{}`, so the fused arm -- `Tensor.zeros(self.pos_params[-1])` -- never fires and its body is changed by nothing. it is not three tokens, and that is the measurement rather than an excuse: a fused record needs `fused=True{}` and `pos_params = P.op_acc(params)`, and `P.op_pos.of` already computes the right `pos_params` from `fused` and the tensors, so the only missing piece is a record mutation -- and `P.Optim` has twenty-four fields, which is why `op_with_arena` is a def and why closing this costs one more def rather than one more token. |
#
# the seven `unverified_*` rows are now claims too: the census gate drives each builder and
# diffs the deep toposort against CPython, and all seven match. They are not mutated HERE --
# the census gate's pins ARE their mutation -- so this table stays the VALUE rows' table.
#
# BOTH LANES AGREE. `./bin/bend tinybendygrad/nn/optim.bend` and
# `./bin/bend tinybendygrad/nn/optim.bend -o <bin>` are byte identical on all THIRTEEN rows,
# measured.

# THE GATE, AS A COMMAND. The graph rows are gated by `gates/op_graph_census-gate.py`, which
# drives each builder directly and diffs the deep toposort WITH each node's arg -- the arg is
# what sees the `CONST 1.0`-vs-`0` guard and the `P.op_1mb` float divergence:
#
#     .venv/bin/python gates/op_graph_census-gate.py
#
# This file's own `main` prints the thirteen rows below. The SIX value rows print the value
# (`op_params=2,3`) while the port prints the VERDICT (`op_params=True`), because the row defs
# compare against the literal; the seven `unverified_*` rows now print CPython's exact trees.
# `gates/optim-nop-mutate.py` is the table above, made re-runnable.
