#!/usr/bin/env python3
"""Audit of `tinybendygrad/runtime/ops_cl.bend` numeric constants against
the OpenCL autogen header `tinygrad/runtime/autogen/opencl.py`.

The smoke-test script `.agents/slop/const-audit.py` covers 0 of these
because the port invents names. So we build the port->autogen name map
by hand and walk it. The map is the audit's authority.

The brief notes the audit covers three vendor spellings (cl/cuda/hip).
After the 1:1 file split (`ops_cuda.bend` and `ops_hip.bend` are
separate), this file ONLY contains the CL spelling -- `vend.cu` is in
ops_cuda.bend and `vend.hp` is in ops_hip.bend -- so the cl autogen
is the only authority for `ops_cl.bend`.

For each port const the script writes one line to stdout:

  <port_name> = <port_value>   | <autogen_name_or_NONE> = <autogen_value>   | STATUS: OK | WRONG | PORT_ONLY

A derived const (e.g. `cl_err_n` whose body is `63`) is HANDED the
declared body -- if the body's a numeric literal, the audit treats it
as the port's value; if the body's a fold, the audit reports PORT_ONLY
(such a constant is a fold over a header table and only CPython can
verify it).

The `cl_err_n` and `cl_err_names_n` constants have NUMERIC bodies but
their SEMANTICS are "the number of unique error codes / alias names in
the cl autogen" -- so the audit checks them against the autogen
directly: 63 unique codes from 74 names, which matches.
"""
import sys
sys.path.insert(0, '.')
from tinygrad.runtime.autogen import opencl as cl


# ---------------------------------------------------------------------------
# THE HAND MAP.
# ---------------------------------------------------------------------------
HAND_MAP: dict[str, str | None] = {
    # OP_* -- port-internal trace op tags (39 of them + V_CL + OP_NONE + OP_N)
    "V_CL":                         None,
    "OP_NONE":                      None,
    "OP_SET_DEVICE":                None,
    "OP_GET_DEVICES":               None,
    "OP_GET_DEVICE_COUNT":          None,
    "OP_GET_DEVICE_INFO":           None,
    "OP_GET_DEVICE_PROPS":          None,
    "OP_INIT":                      None,
    "OP_CTX_CREATE":                None,
    "OP_CTX_SET":                   None,
    "OP_QUEUE_CREATE":              None,
    "OP_PRG_FROM_SRC":              None,
    "OP_PRG_FROM_BIN":              None,
    "OP_BUILD":                     None,
    "OP_BUILD_LOG":                 None,
    "OP_PRG_INFO":                  None,
    "OP_KERNEL":                    None,
    "OP_RELEASE_KERNEL":            None,
    "OP_RELEASE_PRG":               None,
    "OP_PLATFORMS":                 None,
    "OP_ALLOC":                     None,
    "OP_ALLOC_HOST":                None,
    "OP_FREE":                      None,
    "OP_FREE_HOST":                 None,
    "OP_HOST_REGISTER":             None,
    "OP_HOST_UNREGISTER":           None,
    "OP_COPY_IN":                   None,
    "OP_COPY_OUT":                  None,
    "OP_FINISH":                    None,
    "OP_IMAGE":                     None,
    "OP_SET_ARG":                   None,
    "OP_LAUNCH":                    None,
    "OP_WAIT_EVENT":                None,
    "OP_TIME_START":                None,
    "OP_TIME_END":                  None,
    "OP_SIGNAL":                    None,
    "OP_WAIT_VALUE":                None,
    "OP_HOST_FUNC":                 None,
    "OP_COMPUTE_CAP":               None,
    "OP_ERRSTR":                    None,
    "OP_N":                         None,

    # chk_count -- derived fold over vend.checked (39 = OP_N). PORT_ONLY.
    "chk_count":                    None,

    # cl_err_n/cl_err_names_n/cl_err_aliases
    #   cl_err_n (63) and cl_err_names_n (74) are NUMERIC literals but their
    #   MEANING is "count of unique error codes / alias names in the cl
    #   autogen" -- so the audit checks them against the live autogen below.
    #   cl_err_aliases (74 - 63 = 11) is a FOLD over the other two. PORT_ONLY.
    "cl_err_n":                     "__measured_unique_codes__",
    "cl_err_names_n":               "__measured_name_count__",
    "cl_err_aliases":               None,

    # CL_* -- the OpenCL autogen equivalents (14 of them)
    "CL_DEVICE_TYPE_GPU":           "CL_DEVICE_TYPE_GPU",
    "CL_DEVICE_TYPE_DEFAULT":       "CL_DEVICE_TYPE_DEFAULT",
    "CL_MEM_OBJECT_IMAGE2D":        "CL_MEM_OBJECT_IMAGE2D",
    "CL_HALF_FLOAT":                "CL_HALF_FLOAT",
    "CL_FLOAT":                     "CL_FLOAT",
    "CL_QUEUE_PROFILING_ENABLE":    "CL_QUEUE_PROFILING_ENABLE",
    "CL_PROGRAM_BINARY_SIZES":      "CL_PROGRAM_BINARY_SIZES",
    "CL_PROGRAM_BINARIES":          "CL_PROGRAM_BINARIES",
    "CL_PROFILING_COMMAND_START":   "CL_PROFILING_COMMAND_START",
    "CL_PROFILING_COMMAND_END":     "CL_PROFILING_COMMAND_END",
    "CL_DEVICE_NAME":               "CL_DEVICE_NAME",
    "CL_DRIVER_VERSION":            "CL_DRIVER_VERSION",
    "CL_DEVICE_EXTENSIONS":         "CL_DEVICE_EXTENSIONS",
    "CL_DEVICE_IMAGE_PITCH_ALIGNMENT": "CL_DEVICE_IMAGE_PITCH_ALIGNMENT",

    # port-internal sentinels and types
    "NO_IDX":                       None,
    "PROG_INIT_N":                  None,
    "KIND_MEM":                     None,
    "KIND_IMAGE":                   None,
    "KIND_SCALAR":                  None,
    "PTR_SZ":                       None,
    "IMAGE_CHANNELS":               None,
}


def bend_consts(path: str) -> dict[str, str]:
    """Read `def NAME() -> U32: <body>` and return {name: body_str}.

    Bodies that are NUMERIC literals come back as e.g. "4"; folds come back as
    e.g. "chk_count.at(U32.to_nat(OP_N()), 0)" and are reported PORT_ONLY.
    """
    import re
    out: dict[str, str] = {}
    pat = re.compile(r"^def\s+([A-Za-z_][A-Za-z_0-9]*)\(\)\s*->\s*U32:\s*(.+?)\s*$")
    for line in open(path).read().splitlines():
        m = pat.match(line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main() -> int:
    port = bend_consts("tinybendygrad/runtime/ops_cl.bend")
    if set(port) != set(HAND_MAP):
        missing = set(port) - set(HAND_MAP)
        extra = set(HAND_MAP) - set(port)
        if missing: print(f"!! missing from HAND_MAP: {sorted(missing)}", file=sys.stderr)
        if extra:   print(f"!! extra in HAND_MAP: {sorted(extra)}", file=sys.stderr)
        return 1

    # MEASURED: count CL_* attributes whose value <= 0; unique values count
    # the codes, the names count the source names.
    neg_names = []
    for n in dir(cl):
        if not n.startswith("CL_"): continue
        try:
            v = getattr(cl, n)
        except AttributeError: continue
        if isinstance(v, int) and v <= 0:
            neg_names.append((n, v))
    unique_codes = len({v for _, v in neg_names})
    name_count = len(neg_names)

    rows = []
    n_exact, n_wrong, n_port_only = 0, 0, 0
    for name, body in port.items():
        a = HAND_MAP[name]
        # determine whether the body is a numeric literal (auditable) or a fold (PORT_ONLY)
        try:
            pval = int(body)
            is_fold = False
        except ValueError:
            pval = body
            is_fold = True
        # PORT_ONLY if HAND_MAP says so OR if the body is a fold
        if is_fold or a is None:
            rows.append((name, pval, "NONE" if a is None else a, None, "PORT_ONLY", is_fold))
            n_port_only += 1
            continue
        if a == "__measured_unique_codes__":
            aval = unique_codes
            a_disp = "<autogen: unique err codes>"
        elif a == "__measured_name_count__":
            aval = name_count
            a_disp = "<autogen: error-name count>"
        else:
            try:
                aval = getattr(cl, a)
            except AttributeError:
                aval = None
            a_disp = a
        if aval is None:
            rows.append((name, pval, a_disp, None, "WRONG", False))
            n_wrong += 1
            continue
        status = "OK" if pval == aval else "WRONG"
        if status == "OK": n_exact += 1
        else:              n_wrong += 1
        rows.append((name, pval, a_disp, aval, status, False))

    print(f"tinybendygrad/runtime/ops_cl.bend: {len(port)} consts | "
          f"EXACT {n_exact} | WRONG {n_wrong} | PORT_ONLY {n_port_only}")
    for name, pval, a, aval, status, is_fold in rows:
        if status == "PORT_ONLY":
            if is_fold:
                print(f"  {name} = <fold>   | {a}   | STATUS: PORT_ONLY")
            else:
                print(f"  {name} = {pval}   | {a}   | STATUS: PORT_ONLY")
        else:
            print(f"  {name} = {pval}   | {a} = {aval}   | STATUS: {status}")
    print(f"# measured cl_err (autogen): {name_count} names -> {unique_codes} codes")

    return 0 if n_wrong == 0 else 1


if __name__ == "__main__":
    sys.exit(main())