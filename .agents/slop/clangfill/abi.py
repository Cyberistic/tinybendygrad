"""The ABI carrier classes, DERIVED from `.agents/slop/ag-libclang.tramp` and
`tinygrad/runtime/autogen/libclang.py`.  Nothing here is a hand list of names.

Three questions, three derivations:

1. WHICH TYPES ARE BY-VALUE STRUCTS.  A name is by-value iff some trampoline row
   mentions it BARE -- not inside `c.POINTER[...]`.  `CXCursor` is a bare
   parameter 113 times and a by-value 32-byte record; `CXStringSet` only ever
   appears as `c.POINTER[CXStringSet]` and is therefore only ever a pointer.

2. WHAT THE STRUCTS CONTAIN.  `libclang.py` is upstream's own generated table and
   carries `SIZE` plus `register_fields([(name, ctype, offset), ...])`, measured
   by CPython.  The C layout is rebuilt from that field list, so a field the
   generator gets wrong shows up as a `sizeof` mismatch against `SIZE`.

3. HOW A `Term` CARRIES EACH CLASS.  One `Term` is one word.  A pointer and an
   integer fit; a 16/24/32-byte struct does not, so it is boxed on the C heap
   and the address travels as a bend HANDLE (`io_hand`/`io_hand_v`, comp.ts:5440).
   A `const char*` is not a number and not a box: it is a WALK, both directions
   (`io_cbuf` out of bend, `io_str` into it), and it is the only class whose two
   directions are different functions.
"""
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TRAMP = REPO / ".agents" / "slop" / "ag-libclang.tramp"
LIBCLANG_PY = REPO / "tinygrad" / "runtime" / "autogen" / "libclang.py"

# ---- carrier classes --------------------------------------------------------
VOID = "VOID"        # None
INT = "INT"          # int / unsigned / long long / unsigned long long / size_t / time_t
FLT = "FLT"          # double
CSTR = "CSTR"        # c.POINTER[ctypes.c_char]
PTR = "PTR"          # c.POINTER[X], ctypes.c_void_p, c.CFUNCTYPE, an opaque handle
BOX = "BOX"          # a by-value struct: one Term is one word, so it is boxed

# ctypes spelling -> (C type, carrier).  The spellings are read out of the
# 324 rows, so a spelling this table lacks is a wall, not a silent default.
SCALARS = {
    "ctypes.c_int32": ("int", INT),
    "ctypes.c_uint32": ("unsigned", INT),
    "ctypes.c_int64": ("long long", INT),
    "ctypes.c_uint64": ("unsigned long long", INT),
    "ctypes.c_double": ("double", FLT),
    "ctypes.c_void_p": ("void *", PTR),
    "size_t": ("unsigned long", INT),
    "time_t": ("long", INT),
    "None": ("void", VOID),
}


def rows():
    """One `Tr` per row: (name, ret_bind, [(pname, pbind), ...])."""
    for line in TRAMP.read_text().splitlines():
        if not line.strip():
            continue
        f = line.split("|")
        assert len(f) >= 3 and (len(f) - 3) % 3 == 0, f
        params = [(f[3 + i], f[4 + i]) for i in range(0, len(f) - 3, 3)]
        yield f[0], f[1], params


def spellings():
    """Every ctypes spelling a row mentions, bare or inside a pointer."""
    out = set()
    for _, ret, params in rows():
        for s in [ret] + [p for _, p in params]:
            out.add(s)
    return out


def by_value_structs():
    """Derivation 1: a name is by-value iff a row's RETURN or PARAMETER is spelled
    as the bare name -- no `c.POINTER[...]` anywhere around it.

    Peeling to find the names a POINTER needs is a DIFFERENT derivation and lives
    in `peel`.  Doing it here put `CXSourceRangeList` (16 bytes upstream, only ever
    used through a pointer) in the by-value set and emitted a full definition for
    a type that is only ever named after a `*`.
    """
    return set(abi_spellings())


def abi_spellings():
    """Every spelling a row mentions, exactly as written."""
    out = set()
    for _, ret, params in rows():
        for s in [ret] + [p for _, p in params]:
            out.add(s)
    return out


def peel(spelling):
    """Every non-`c.POINTER` name a spelling is built from, innermost last."""
    out = []
    while True:
        m = re.fullmatch(r"c\.POINTER\[(.+)\]", spelling)
        if not m:
            return out + [spelling]
        out.append(m.group(1))
        spelling = m.group(1)


def enums():
    """Every `enum_<name>: dict[...]` upstream declares.  Upstream names an enum's
    dict `enum_CXTokenKind`, so `CXTokenKind` is a four-byte enum in
    `clang-c/Index.h` and NOT an opaque `void *`.  Without this the generator emits
    `typedef void *CXTokenKind;` and then the enum of the same name, and the C
    compiler refuses the file for exactly the right reason.
    """
    return set(re.findall(r"(?m)^enum_(\w+): dict\[int, str\] = \{", LIBCLANG_PY.read_text()))


def ctypes_structs():
    """Derivation 2: upstream's own `SIZE` and field table, read with a regex."""
    text = LIBCLANG_PY.read_text()
    size = {m[0]: int(m[1]) for m in re.findall(r"class (\w+)\(c\.Struct\):\n  SIZE = (\d+)", text)}
    fields = {}
    for cls, body in re.findall(r"class (\w+)\(c\.Struct\):\n(.*?)(?=\n@|\nclass |\nenum_|\Z)", text, re.S):
        m = re.search(re.escape(cls) + r"\.register_fields\(\[(.*?)\]\)", body, re.S)
        if m:
            fields[cls] = re.findall(r"\('(\w+)', (.*?), (\d+)\)", m.group(1))
    # `X: TypeAlias = Y` -- libclang.py spells a by-value `CXTUResourceUsage` as an
    # ALIAS of the class `struct_CXTUResourceUsage`, so the trampoline's name has
    # to be resolved before "is this a struct?" can be answered.  The map is over
    # EVERY alias, not only over the names that carry a `SIZE`: `CXTUResourceUsage`
    # is a key here and not in `size`, which is exactly where it went wrong once.
    alias = dict(re.findall(r"(?m)^(\w+): TypeAlias = (\w+)$", text))
    resolved = dict(alias)
    resolved.update({n: n for n in size})
    return resolved, size, fields


# The C spelling of an upstream ctypes type inside a `register_fields` row.
FIELD_TYPES = {
    "ctypes.c_void_p": "void *",
    "ctypes.c_uint32": "unsigned",
    "ctypes.c_int32": "int",
    "ctypes.c_uint64": "unsigned long long",
    "ctypes.c_int64": "long long",
    "ctypes.c_char": "char",
    "ctypes.c_ubyte": "unsigned char",
    "ctypes.c_double": "double",
    "int": "int",
    "unsigned": "unsigned",
}


def field_c(ctype):
    if ctype in FIELD_TYPES:
        return FIELD_TYPES[ctype]
    m = re.fullmatch(r"c\.Array\[ctypes\.(\w+), Literal\[(\d+)\]\]", ctype)
    if m:
        return "%s[%s]" % (FIELD_TYPES["ctypes." + m.group(1)], m.group(2))
    m = re.fullmatch(r"c\.POINTER\[(\w+)\]", ctype)
    if m:
        return m.group(1) + " *"
    m = re.fullmatch(r"c\.POINTER\[(ctypes\.\w+)\]", ctype)
    if m:
        if m.group(1) == "ctypes.c_char":
            return "const char *"          # `clang-c/Index.h` says `const char *`
        return FIELD_TYPES.get(m.group(1), m.group(1)) + " *"
    return ctype


def fn_c(ctype):
    """`c.CFUNCTYPE[None, [ctypes.c_void_p, CXCursor]]` -> `void (*)(void *, CXCursor)`.

    A callback is a real C function POINTER and has to be declared as one:
    `struct_CXCursorAndRangeVisitor` has such a field, and the field's own type is
    what makes the struct 16 bytes rather than a guess.
    """
    m = re.fullmatch(r"c\.CFUNCTYPE\[(.+), \[(.*)\]\]", ctype)
    if not m:
        return None
    ret = "void" if m.group(1).strip() == "None" else field_c(m.group(1))
    args = ", ".join(field_c(a.strip()) for a in m.group(2).split(",")) or "void"
    return "%s (*)(%s)" % (ret, args)


def field_decl(ctype, name):
    """`('data', c.Array[ctypes.c_void_p, Literal[3]], 8)` -> `void *data[3]`.

    The ARRAY goes after the name in C, and a bare `void *` field still needs its
    name -- `void *;` is a declaration of nothing and `void *[3] d` is not C at
    all.  Both were written and both compiled in a draft of this file.
    """
    m = re.fullmatch(r"c\.Array\[ctypes\.(\w+), Literal\[(\d+)\]\]", ctype)
    if m:
        return "%s %s[%s]" % (FIELD_TYPES["ctypes." + m.group(1)], name, m.group(2))
    fn = fn_c(ctype)
    if fn:
        m = re.fullmatch(r"(.+) \(\*\)\((.*)\)", fn)
        return "%s (*%s)(%s)" % (m.group(1), name, m.group(2))
    return "%s %s" % (field_c(ctype), name)


def struct_defs(needed):
    """The C `typedef struct` for each by-value type, rebuilt from upstream.

    Returns (defs, sizes, resolved).  `defs` maps the spelling a trampoline row
    uses onto the C text that declares it, so an ALIASED struct gets both names.
    """
    resolved, size, fields = ctypes_structs()
    # TRANSITIVELY: `struct_CXTUResourceUsage` has a
    # `c.POINTER[struct_CXTUResourceUsageEntry]` field, so an incomplete
    # declaration of the entry is the whole declaration that field needs, and the
    # generator emits it instead of discovering it as a wall from the C compiler.
    want = set(needed)
    while True:
        grown = set(want)
        for n in list(want):
            for _fn, ft, _off in fields.get(resolved[n], []):
                m = re.fullmatch(r"c\.POINTER\[(\w+)\]", ft)
                # resolve the ALIAS first: the field names `CXTUResourceUsageEntry`
                # and the class is `struct_CXTUResourceUsageEntry`, so asking
                # `size` about the field's own spelling says no and the entry is
                # dropped, and then the C compiler names the unknown type.
                if m and resolved.get(m.group(1), m.group(1)) in size:
                    grown.add(m.group(1))
        if grown == want:
            break
        want = grown
    out = {}
    for name in sorted(want):
        cls = resolved[name]
        assert cls in size, f"{name} is by-value but upstream declares no SIZE"
        body = ["  %s;" % field_decl(ft, fn) for fn, ft, _off in fields[cls]]
        assert body, f"{cls} has no register_fields row"
        text = "typedef struct {\n%s\n} %s;" % ("\n".join(body), cls)
        for alias, target in sorted(resolved.items()):
            if target == cls and alias != cls:
                text += "\ntypedef %s %s;" % (cls, alias)
        # `struct_CXUnsavedFile` is upstream's CLASS name and `CXUnsavedFile` is
        # `clang-c/Index.h`'s; the trampoline rows spell the class, the fixture
        # wants the header's, so both names are declared and neither is invented.
        if name.startswith("struct_"):
            text += "\ntypedef %s %s;" % (name, name[7:])
        out[name] = text
    return out, size, resolved


def c_proto(spelling, structs):
    """The C type and carrier class of one ABI type spelling."""
    if spelling in SCALARS:
        return SCALARS[spelling]
    if spelling.startswith("c.CFUNCTYPE"):
        # a callback PARAMETER is the function pointer itself, not a pointer to one
        return fn_c(spelling), PTR
    m = re.fullmatch(r"c\.POINTER\[(.+)\]", spelling)
    if m:
        inner = m.group(1)
        if inner == "ctypes.c_char":
            return "const char *", CSTR
        if inner.startswith("ctypes."):
            return "void *", PTR
        if inner.startswith("c."):
            return "void *", PTR           # a callback: addressable, not callable here
        return inner + " *", PTR
    if spelling == "struct_CXUnsavedFile":
        return "CXUnsavedFile *", PTR
    if spelling.startswith("struct_") and spelling[7:] in structs:
        return "struct_" + spelling[7:] + " *", PTR
    if spelling in structs:
        return spelling, BOX
    # an OPAQUE HANDLE: every other name is a pointer typedef in clang-c/Index.h.
    return spelling + " *", PTR


# `ag-emit.bend`'s `ty_prims`, ONE table, so this module and the emitter spell a
# ctypes type the same name.  A second, smaller table here is how `Ptr_ctypes.c_char`
# got emitted where the product says `Ptr_CChar`: both were derived, they were not
# the same derivation, and nothing compared them.  `cross_check()` is what compares
# them, over all 324 signatures.
PRIMS = [("U32", "ctypes.c_uint32"), ("I32", "ctypes.c_int32"), ("I32", "int"),
         ("I64", "ctypes.c_int64"), ("I64", "time_t"), ("U64", "ctypes.c_uint64"),
         ("U64", "size_t"), ("F64", "ctypes.c_double"), ("F64", "float"),
         ("CVoidP", "ctypes.c_void_p"), ("CChar", "ctypes.c_char"), ("CChar", "bytes"),
         ("CBool", "ctypes.c_bool"), ("CBool", "bool"), ("CWChar", "ctypes.c_wchar"),
         ("CWChar", "str"), ("Unit", "None")]
PRIM_OF = {s: n for n, s in reversed(PRIMS)}


def bend_type(bind, structs=None):
    """The bend name for one ABI spelling, matching `ag-emit.bend`'s `enc`."""
    if bind in PRIM_OF:
        return PRIM_OF[bind]
    m = re.fullmatch(r"c\.POINTER\[(.+)\]", bind)
    if m:
        return "Ptr_" + bend_type(m.group(1), structs)
    m = re.fullmatch(r"c\.CFUNCTYPE\[(.+)\]", bind)
    if m:
        # `ag-emit.bend`'s `enc_arg` strips the `[...]` around a CFUNCTYPE argument
        # list BEFORE encoding it, so `Fn_Unit_[ctypes.c_void_p]` here and
        # `Fn_Unit_CVoidP` there.  `cross_check()` is what found that: 1 disagreement
        # out of 324, and it was the only name in the table with a `[` in it.
        args = [p.strip()[1:-1] if p.strip().startswith("[") and p.strip().endswith("]")
                else p.strip() for p in m.group(1).split(",")]
        return "Fn_" + "_".join(bend_type(a, structs) for a in args)
    return bind


def cross_check(path=None):
    """Compare this module's `bend_type` against the 324 LAW SIGNATURES in the product.

    The signature is the `law` line, not the `def`: the def carries only names
    (`def clang_getFile(tu, file_name):`) and the types live one line above it.
    Two independent derivations of the same 324 signatures agreeing is the only
    evidence that `ag-emit.bend`'s `enc` and this module's `bend_type` are one
    derivation; it returns the disagreements, and an empty list is a measurement.
    """
    path = path or (REPO / "tinybendygrad" / "runtime" / "autogen" / "libclang.bend")
    want = {}
    for m in re.finditer(r"^law (clang_\w+):\n  (.*?)IO\((\w+)\)\n", path.read_text(), re.M):
        sig = m.group(2)
        want[m.group(1)] = ([t.strip() for t in sig.split("->")[:-1]] if sig else [],
                            m.group(3))
    bad = []
    for name, ret, params in rows():
        got = ([bend_type(pb) for _pn, pb in params], bend_type(ret))
        if name not in want:
            bad.append((name, "absent from the product"))
        elif want[name] != got:
            bad.append((name, "product %s != derived %s" % (want[name], got)))
    return bad, len(want)

def rows_list():
    """One dict per row: name, the bend return type, and per parameter (name, the
    ctypes spelling, the C type, the carrier class, the BEND type).

    `fill.py` builds its `_run`s from this and `gate.py` builds its 324-arm
    dispatch from it, so the call the gate makes and the body the generator wrote
    come from ONE list.  A gate that spelled its own calls would be a second
    derivation of the signature and could disagree with the first silently.
    """
    bare = by_value_structs()
    resolved, size, _f = ctypes_structs()
    byval = sorted(n for n in bare if resolved.get(n, n) in size)
    struct_c, _sz, _rs = struct_defs(byval + ["struct_CXUnsavedFile"])
    import fill as _f2  # `c_proto_n` is the only spelling-peeler there
    out = []
    for name, ret, params in rows():
        rbend = bend_type(ret, struct_c)
        ps = []
        for pn, pb in params:
            _ct, pcls = _f2.c_proto_n(pb, struct_c)
            ps.append((pn, pb, _ct, pcls, bend_type(pb, struct_c)))
        out.append(dict(name=name, rbend=rbend, ps=ps))
    return out
