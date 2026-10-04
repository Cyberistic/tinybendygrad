#!/usr/bin/env python3
"""tensor.bend's MUTATION TABLE, measured.

Each mutation is a one-token edit to `tinybendygrad/tensor.bend`, the file is run, and
the rows that MOVE are recorded. The file is restored between mutations, so the table is
a claim about the CURRENT gate and not about an earlier one.

    .venv/bin/python .agents/slop/tensor-mutate.py

A mutation that moves NOTHING is reported as such. That is not a broken mutation: it is
a measurement of what the gate does NOT see, and it is the most useful row in the table.
"""
import subprocess, sys, os, re, difflib
import patch_not_apply as PNA

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
F = os.path.join(ROOT, 'tinybendygrad', 'tensor.bend')
BEND = os.path.join(ROOT, 'bin', 'bend')

# (id, a unique substring of the line to edit, the replacement, what it is testing)
MUTS = [
 ('M1', 'O.UOp.new(ar, op, List.append(&2, U32, [self], srcs), O.ANone{}, O.TNone{})',
       'O.UOp.new(ar, op, List.append(&2, U32, srcs, [self]), O.ANone{}, O.TNone{})',
       '`(self,)+srcs` -> `srcs+[self]`: the src ORDER of every movement node'),
 ('M2', 'case _: tn_shape_arg.k(ys, ar, Nat.is_eq(n, 1n))',
       'case _: tn_shape_arg.k(ys, ar, False{})',
       '`shape_to_shape_arg`\'s ONE-element arm (a bare CONST, not a STACK)'),
 ('M3', 'case 0n: O.op_in([O.OpsEXPAND{}, O.OpsSHRINK{}, O.OpsPAD{}], op)',
       'case 0n: O.op_in([O.OpsSHRINK{}, O.OpsPAD{}], op)',
       'the `EXPAND` in the early-NOOP op set (ops.py:823)'),
 ('M4', 'Bool.pick(U32, U32.is_lt(x, y), x, y)', 'Bool.pick(U32, U32.is_le(x, y), x, y)',
       '`sorted`\'s strictness, on a ONE-element axis'),
 ('M5', 'O.UOp.new(ar, O.OpsREDUCE{}, [src], O.AReduce{op, U32.from_nat(tn_rop.len(rn))}, O.TNone{})',
        'O.UOp.new(ar, O.OpsREDUCE{}, [src], O.AReduce{O.OpsMAX{}, U32.from_nat(tn_rop.len(rn))}, O.TNone{})',
        'the `op` `_rop` forwards into the REDUCE arg (tensor.py:500)'),
 ('M6', 'O.UOp.after(O.Found.ar(st), self, [O.Found.i(st)])', 'O.Found{O.Found.ar(st), O.Found.i(st)}',
       'the `AFTER` half of the assign spine (tensor.py:259)'),
 ('M7', 'Tensor{Tensor.ar(t), Tensor.u(t), is_param, Tensor.grad_of(t)}',
       'Tensor{Tensor.ar(t), Tensor.u(t), Tensor.flag(t), Tensor.grad_of(t)}',
       '`is_param_` ignoring the flag it was handed'),
 ('M8', 'O.OpsSHRINK{}, APairs{[tn_mop.k(0)], [tn_mop.k(2)]}',
       'O.OpsSHRINK{}, APairs{t_mop.pair(0, 0), t_mop.pair(0, 2)}',
       'the SHRINK FIXTURE: the ndim-2 transpose shape where ndim 1 belongs'),
 ('M9', 'case True{}: "None"\n    case _: "0"', 'case True{}: "0"\n    case _: "None"',
       '`__repr__`\'s grad column: the reserved-0 test (tensor.py:131)'),
 ('M10', 'case Nil{}: None{}\n    case d <> _: Some{O.SInt.u(d)}',
        'case Nil{}: Some{0}\n    case d <> _: Some{O.SInt.u(d)}',
        '`__len__`\'s 0-d `TypeError` guard (tensor.py:139)'),
 ('M11', 'case Some{ys}: F.eq_sints(xs, ys)\n    case None{}: False{}',
        'case Some{ys}: True{}\n    case None{}: False{}',
        '`replace`\'s shape `assert` (tensor.py:232)'),
 ('M12', 'case Some{dt}: S.Dt.is_float(dt)\n    case None{}: False{}',
        'case Some{dt}: True{}\n    case None{}: False{}',
        '`backward`\'s `is_floating_point` term (tensor.py:487)'),
 ('M13', 'tn_mop.node.of(ar, self, op, usrcs, O.UOp.sink(ar, usrcs))',
        'tn_mop.node.of(ar, self, op, usrcs, O.UOp.sink(O.Arena.empty(), usrcs))',
        'the orphan SINK `tn_mop.node` builds (ops.py:835)'),
 ('M14', 'case Some{rn}: tn_rop.red2(ar, self, op, axis, rn)\n    case None{}: O.Found{ar, self}',
        'case Some{rn}: tn_rop.red2(ar, self, op, axis, rn)\n    case None{}: tn_rop.red2(ar, self, op, axis, Nil{})',
        'the `_rop` GAP arm: reducing anyway when the fold cannot answer (WALL 5)'),
 ('M15', 'List.append(&2, U32, [uop], srcs)', 'List.append(&2, U32, srcs, [uop])',
       '`alu`\'s src order: `(self, *src)` vs `(*src, self)` (ops.py:630)'),
 ('M16', 'case 0n: O.Found{ar, self}\n    case _: tn_rop.reduce(ar, self, op, saxis)',
        'case 0n: tn_rop.reduce(ar, self, op, saxis)\n    case _: tn_rop.reduce(ar, self, op, saxis)',
        'the `not len(reduce_axis)` arm of `_rop` (ops.py:659)'),
 ('M17', 't_row("tn_len3", Bool.not(tn_none(tn_len(tn_new(O.Found.ar(b), O.Found.i(b))))))',
        't_row("tn_len3", Bool.not(tn_none(tn_len(tn_new(O.Found.ar(b), O.Found.i(b))))))',
        'a no-op marker, reported so the table has a row that CANNOT move'),
]

def run():
    out = subprocess.run([BEND, F], capture_output=True, text=True, cwd=ROOT)
    txt = out.stdout + out.stderr
    if 'PROOFS FAIL' in txt or 'Error' in txt:
        return None, txt
    rows = {}
    for line in txt.strip().split('\n'):
        if '=' in line:
            k, v = line.split('=', 1)
            rows[k] = v
    return rows, txt

base, basetxt = run()
if base is None:
    print('BASELINE DOES NOT COMPILE:'); print(basetxt[:2000]); sys.exit(1)

src = open(F).read()
print('| mutation | rows that MOVED | what it is testing |')
print('| --- | --- | --- |')
results = []
for mid, find, repl, what in MUTS:
    if find not in src:
        print(PNA.pipe([mid, PNA.not_applied("the line changed"), what], 3))
        continue
    open(F, 'w').write(src.replace(find, repl, 1))
    rows, txt = run()
    open(F, 'w').write(src)
    if rows is None:
        moved = ['DID NOT COMPILE']
    else:
        moved = [k for k in base if base[k] != rows.get(k)]
        moved += [k for k in rows if k not in base]
        if not moved:
            moved = []
    results.append((mid, moved, what))
    print('| %s | %s | %s |' % (mid, ', '.join(moved) if moved else '**NOTHING**', what))
open(F, 'w').write(src)
print()
print('%d mutations, %d moved nothing' % (len(results), sum(1 for _, m, _ in results if not m)))
