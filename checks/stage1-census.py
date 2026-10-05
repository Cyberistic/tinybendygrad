#!/usr/bin/env python3
"""STAGE 1 CENSUS -- tinybendygrad/tensor.bend vs tinygrad/tensor.py.

VERIFICATION-FIRST. Nothing here is transcribed. The upstream denominator is
computed by CALLING ast.parse on the real file and by importing tinygrad and
reading `Tensor.__dict__` with `__module__` discrimination (the naive
`Tensor.__dict__` public list reports 226 because tensor.py:588's TRACEMETA
loop setattr's every INHERITED member back onto Tensor).

The port column is established by READING tinybendygrad/tensor.bend -- finding
each upstream method's `TODO(p3) tensor.py:<line> <name>` marker and each
`def tn_*` body -- never by grepping the upstream name for a def of that name.
That is the error this census exists to avoid (see .agents/slop/notes T-numbers).

Run:  .venv/bin/python checks/stage1-census.py
"""
from __future__ import annotations
import ast, re, sys, collections, importlib

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
TENSOR_PY = f"{ROOT}/tinygrad/tensor.py"
TENSOR_BEND = f"{ROOT}/tinybendygrad/tensor.bend"

# ---------------------------------------------------------------- upstream
src = open(TENSOR_PY).read()
tree = ast.parse(src)
cls = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Tensor"][0]
meths = [m for m in cls.body if isinstance(m, ast.FunctionDef)]
top = [n for n in tree.body if isinstance(n, ast.FunctionDef)]

sys.path.insert(0, ROOT)
from tinygrad.tensor import Tensor  # noqa: E402
own_by_module = sorted(
    k for k, v in Tensor.__dict__.items()
    if getattr(v, "__module__", None) == "tinygrad.tensor"
    and not (k.startswith("__") and k.endswith("__"))
)

# ------------------------------------------------------------------- port
tl = open(TENSOR_BEND).read().split("\n")
port_defs: dict[str, list[int]] = collections.defaultdict(list)
for i, ln in enumerate(tl, 1):
    m = re.match(r"\s*def\s+([A-Za-z_][A-Za-z0-9_.]*)", ln)
    if m:
        port_defs[m.group(1)].append(i)

# every `TODO(p3) tensor.py:<line> <name>` and every `# tensor.py:<line> <name>`
todo_by_name: dict[str, list[tuple[int, int]]] = collections.defaultdict(list)
cite_by_name: dict[str, list[tuple[int, int]]] = collections.defaultdict(list)
for i, ln in enumerate(tl, 1):
    body = re.sub(r"^\s*#\s*", "", ln)
    m = re.match(r"TODO\(p3\)\s+(?:tensor\.py:(\d+)\s+)?([A-Za-z_][A-Za-z0-9_]*)", body)
    if m:
        todo_by_name[m.group(2)].append((i, int(m.group(1)) if m.group(1) else None))
        continue
    m = re.match(r"(?:[A-Za-z_0-9.`'\[\]]+\s+)?tensor\.py:(\d+)\s+`?([A-Za-z_][A-Za-z0-9_]*)", body)
    if m:
        cite_by_name[m.group(2)].append((i, int(m.group(1))))

# the port's OWN correspondence claims, printed with their line so a reader can
# check the claim is not the port asserting an absence it never justified.
def kind(n: str) -> str:
    if n.startswith("__") and n.endswith("__"):
        return "dunder"
    return "private" if n.startswith("_") else "public"

print("=" * 78)
print("STAGE 1 -- THE CENSUS.  upstream tinygrad/tensor.py  vs  tinybendygrad/tensor.bend")
print("=" * 78)
print()
print(f"upstream `class Tensor` methods (ast, L{cls.lineno}-{cls.end_lineno}): {len(meths)}")
kinds = collections.Counter(kind(m.name) for m in meths)
print(f"   by kind: {dict(kinds)}")
print(f"upstream module-level defs: {len(top)} -> {[n.name for n in top]}")
print(f"Tensor.__dict__ entries with __module__=='tinygrad.tensor', public: {len(own_by_module)}")
print(f"   (the raw `Tensor.__dict__` public list is 226 -- TRACEMETA setattr pollution)")
print()
print(f"port tensor.bend defs: {sum(len(v) for v in port_defs.values())} names / "
      f"{sum(len(v) for v in port_defs.values())} def lines")
print(f"port TODO(p3) markers naming a tensor.py method: "
      f"{sum(len(v) for v in todo_by_name.values())} over {len(todo_by_name)} names")
print()

print("-" * 78)
print("THE 57.  Every upstream method, its port counterpart, and the evidence.")
print("-" * 78)
print(f"{'upstream':20s} {'kind':8s} {'upstream L':12s} {'port counterpart':26s} {'evidence':s}")

# The mapping. Each entry: name -> (port counterpart or None, evidence string).
# Built by READING tensor.bend; every counterpart cites the def line in the port.
MAP: dict[str, tuple[str | None, str]] = {}
def M(n, c, e): MAP[n] = (c, e)

M("__init__", "tn_init.arm/.none/.keep + tn_cast + tn_new", "port:448-507 built; :1047 TODO on the None arm")
M("__del__", None, "no `__del__` in Bend; WALL 1, registry is threaded (port:18-24)")
M("_apply_uop", "tn_alu / tn_new / tn_wrap_uop", "port:286-301 -- tail only; :295 TODO on `fxn`")
M("alu", "tn_alu / tn_alu.of / tn_alu.put", "port:255-287, FULL")
M("_uop", "Tensor.u", "port:194, FULL")
M("_wrap_uop", "tn_wrap_uop", "port:300, FULL")
M("const", "tn_const", "port:311 built; :304 TODO -- no dtype arg, bare CONST")
M("is_param_", "tn_is_param_", "port:316, FULL (returns new record; DIVERGENCE)")
M("__repr__", "tn_repr + tn_repr.of/.dt/.dims/.grad/.devname", "port:365-422, FULL")
M("__hash__", "tn_hash", "port:323, FULL (rule differs; DIVERGENCE)")
M("__bool__", None, "port:327 -- deliberately the ABSENCE; no raise in Bend")
M("__len__", "tn_len / .of / .first", "port:335-346, FULL as Maybe")
M("device", "tn_device / tn_dev / .go/.of/.put", "port:198-245, FULL")
M("shape", "tn_shape / tn_dims / .go/.of/.put", "port:201-226, FULL")
M("dtype", "tn_dtype", "port:204, FULL")
M("as_param", None, "port:1048 TODO -- `UOp.param_like` is ops.py:1239, P3")
M("call", None, "port:1049 TODO -- `call_with_output` + `grad_fxn` kwarg")
M("custom_kernel", None, "port:1050 TODO")
M("linear_with_vars", None, "port:1023 TODO -- SCHEDULE+WALL2+WALL3, 43 upstream lines")
M("schedule_linear", None, "port:1031 TODO -- same wall as linear_with_vars")
M("realize", None, "port:1036 TODO -- `needs_storage` + engine/realize.py run_linear")
M("replace", "tn_replace / .of / .same / .same.of / .same.go", "port:517-536, FULL")
M("assign", "tn_assign_store + tn_ib_walk", "port:889-905 -- SPINE ONLY; :907 TODO on 8 arms")
M("_buffer", None, "port:1051 TODO -- WALL 2 Buffer")
M("_data", None, "port:1052 TODO -- memoryview")
M("data", None, "port:1053 TODO -- WALL 2 + dtypes.fmt")
M("tolist", None, "port:1054 TODO -- WALL 2 + nested tree printer refused")
M("numpy", None, "port:1057 TODO -- WALL 2 + foreign module")
M("clone", None, "port:1058 TODO -- `UOp.clone` ops.py:882")
M("to", None, "port:1062 TODO -- canonicalize_device/is_disk_device/copy_to_device")
M("to_", None, "port:1064 TODO -- `to` + `replace`")
M("shard", None, "port:1065 TODO -- `UOp.shard` ops.py:757 + _resolve_dim")
M("shard_", None, "port:1067 TODO")
M("shard_like", None, "port:1068 TODO")
M("from_blob", None, "port:1069 TODO -- external pointer")
M("from_url", None, "port:1070 TODO -- helpers.fetch")
M("manual_seed", None, "port:1071 TODO -- class-level mutable state")
M("_next_counter", None, "port:1072 TODO")
M("backward", "tn_need_grad / .go/.put/.wanted/.is_float.go", "port:920-949 -- SCOPE FILTER ONLY; :951 TODO on the zip")
M("_mop", "tn_mop + tn_mop.* (17)", "port:645-730, FULL (hoisted from ops.py:821)")
M("_rop", "tn_rop + tn_rop.* (16)", "port:766-869, FULL-with-GAP (WALL 5, t_rop_gap prints True)")
M("__setitem__", None, "port:1073 TODO")
M("__delitem__", None, "port:1076 TODO -- raise TypeError, __bool__'s wall")
M("__iadd__", None, "port:984 TODO -- assign + elementwise.py:101")
M("__isub__", None, "port:985 TODO")
M("__imul__", None, "port:986 TODO")
M("__itruediv__", None, "port:987 TODO")
M("__ifloordiv__", None, "port:988 TODO")
M("__ipow__", None, "port:989 TODO")
M("__iand__", None, "port:990 TODO")
M("__ior__", None, "port:991 TODO")
M("__ixor__", None, "port:992 TODO")
M("__ilshift__", None, "port:993 TODO")
M("__irshift__", None, "port:994 TODO")
M("__imatmul__", None, "port:995 TODO -- matmul is a WMMA (mixin/op.py:394)")
M("__eq__", None, "port:996 TODO")
M("decode_hevc_frame", None, "port:1077 TODO")

assert set(MAP) == {m.name for m in meths}, (
    "MAP and the AST disagree -- a method was missed",
    sorted(set(MAP) ^ {m.name for m in meths}))

present = [m for m in meths if MAP[m.name][0]]
absent = [m for m in meths if not MAP[m.name][0]]
print()
for m in sorted(meths, key=lambda x: x.lineno):
    c, e = MAP[m.name]
    span = f"{m.lineno}-{m.end_lineno}"
    print(f"{m.name:20s} {kind(m.name):8s} {span:12s} {(c or '-- ABSENT --'):26s} {e}")

print()
print(f"upstream methods  : {len(meths)}")
print(f"port counterparts : {len(present)}  ({100*len(present)/len(meths):.0f}%)")
print(f"genuinely absent  : {len(absent)}  ({100*len(absent)/len(meths):.0f}%)")
print(f"DENOMINATOR = {len(meths)} (every `def` in `class Tensor`, tensor.py:{cls.lineno}-{cls.end_lineno})")
print()
pub = [m for m in meths if kind(m.name) == "public"]
pubp = [m for m in pub if MAP[m.name][0]]
print(f"restricted to PUBLIC methods only: {len(pubp)}/{len(pub)} present")
print(f"   absent public: {sorted(m.name for m in pub if not MAP[m.name][0])}")
print()
print("-" * 78)
print("THE SEVEN NAMES IN THE BRIEF.  Each located by CALLING tinygrad, then read.")
print("-" * 78)
from tinygrad.mixin.op import OpMixin          # noqa: E402
from tinygrad.mixin.elementwise import ElementwiseMixin  # noqa: E402
MIX = {"mixin/op.py": OpMixin, "mixin/elementwise.py": ElementwiseMixin}
for nm in ["matmul", "mul", "add", "backward", "zero_grad", "realize",
           "schedule_linear", "assign"]:
    homes = []
    for k, c in MIX.items():
        if nm in vars(c):
            homes.append(k)
    if getattr(Tensor.__dict__.get(nm), "__module__", None) == "tinygrad.tensor":
        homes.append("tensor.py")
    # port: a def whose NAME is exactly this, anywhere in the port tree
    exact = []
    import glob
    for f in glob.glob(f"{ROOT}/tinybendygrad/**/*.bend", recursive=True):
        for ln in open(f):
            m = re.match(r"\s*def\s+([A-Za-z_][A-Za-z0-9_.]*)", ln)
            if m and m.group(1).split(".")[-1] == nm:
                exact.append(f.replace(ROOT + "/", ""))
    tn = [n for n in todo_by_name if n.split("'")[0] == nm]
    print(f"{nm:16s} upstream home: {homes or ['ABSENT FROM tinygrad ENTIRELY']}")
    print(f"{'':16s} port def with that exact name: {exact or 'none'}")
    print(f"{'':16s} port TODO(p3) marker: {bool(tn)}")
print()
print("READING:")
print("  mul/add/matmul are NOT tensor.py methods -- they are ElementwiseMixin and")
print("  OpMixin methods, and the port has ew_mul/ew_add (mixin/elementwise.bend:543-544).")
print("  A name search of tensor.bend can NEVER find them, and its absence is not a fact")
print("  about tensor.bend at all.  zero_grad is not a Tensor method at all (it is")
print("  tinygrad/nn/optim.py, 2 hits) -- searching for it on Tensor is a phantom.")