#!/usr/bin/env python3
"""Audit of `tinybendygrad/runtime/ops_webgpu.bend` numeric constants against
the autogen header `tinygrad/runtime/autogen/webgpu.py`.

The smoke-test script `.agents/slop/const-audit.py` is documented to reach only
0/65 of these consts because the port invents names. So we build the
port->autogen name map by hand and walk it. The map is the audit's authority:
each entry maps a port name to either an autogen attribute name or None (a
port-internal constant with no autogen counterpart).

For each port const the script writes one line to stdout:

  <port_name> = <port_value> | <autogen_name_or_NONE> = <autogen_value> | STATUS: OK | WRONG | PORT_ONLY

Then a summary line for the commit message.
"""
import sys
sys.path.insert(0, '.')
from tinygrad.runtime.autogen import webgpu as w


# ---------------------------------------------------------------------------
# THE HAND MAP. Each entry is (port_name, autogen_name_or_None).
# `None` means "port-internal: no autogen counterpart".
# ---------------------------------------------------------------------------
HAND_MAP: dict[str, str | None] = {
    # OBJ_* -- the port's own object-id tags, no autogen counterpart
    "OBJ_INSTANCE":                None,
    "OBJ_ADAPTER":                 None,
    "OBJ_QUEUE":                   None,
    "OBJ_SHADER_MODULE":           None,
    "OBJ_BIND_GROUP_LAYOUT":       None,
    "OBJ_PIPELINE_LAYOUT":         None,
    "OBJ_BIND_GROUP":              None,
    "OBJ_COMPUTE_PIPELINE":        None,
    "OBJ_COMMAND_ENCODER":         None,
    "OBJ_COMPUTE_PASS":            None,
    "OBJ_COMMAND_BUFFER":          None,
    "OBJ_QUERY_SET":               None,
    "OBJ_BUFFER":                  None,

    # CALL_* -- the port's own call-kind ids, no autogen counterpart
    "CALL_CREATE":                 None,
    "CALL_WAIT":                   None,
    "CALL_RELEASE":                None,
    "CALL_PUSH":                   None,
    "CALL_POP":                    None,
    "CALL_MAP_ASYNC":              None,
    "CALL_MAPPED_RANGE":           None,
    "CALL_WRITE":                  None,
    "CALL_COPY":                   None,
    "CALL_BEGIN":                  None,
    "CALL_SET_PIPELINE":           None,
    "CALL_SET_BIND_GROUP":         None,
    "CALL_DISPATCH":               None,
    "CALL_END":                    None,
    "CALL_RESOLVE":                None,
    "CALL_FINISH":                 None,
    "CALL_SUBMIT":                 None,
    "CALL_UNMAP":                  None,
    "CALL_DESTROY":                None,
    "CALL_DESTROY_QUERY_SET":      None,
    "CALL_GET_FEATURES":           None,
    "CALL_FREE_FEATURES":          None,
    "CALL_GET_LIMITS":             None,

    # SYNC_* -- the SYNC_* ids NAME the six synchronous-wrapped calls;
    # the SYNC_NONE/ONE/MANY/HAS_EMSG/NO_EMSG are port-internal.
    # The six sync ids (1..6) are a port ordinal, not a header value, so
    # they are PORT_ONLY. (The header has its own
    # WGPURequestAdapterStatus_Success et al. with value 1, but those are
    # status codes, not sync ids.)
    "SYNC_MAP_ASYNC":              None,
    "SYNC_POP_ERROR_SCOPE":        None,
    "SYNC_CREATE_PIPELINE":        None,
    "SYNC_REQUEST_ADAPTER":        None,
    "SYNC_REQUEST_DEVICE":         None,
    "SYNC_WORK_DONE":              None,
    "SYNC_HAS_EMSG":               None,
    "SYNC_NO_EMSG":                None,
    "SYNC_NONE":                   None,
    "SYNC_ONE":                    None,
    "SYNC_MANY":                   None,

    # bind type
    "BIND_UNIFORM":                "WGPUBufferBindingType_Uniform",
    "BIND_STORAGE":                "WGPUBufferBindingType_Storage",

    # error filter (called at every PushErrorScope)
    "FILTER_VALIDATION":           "WGPUErrorFilter_Validation",

    # map state (used by free() to decide whether to unmap first)
    "MAP_UNMAPPED":                "WGPUBufferMapState_Unmapped",
    "MAP_MAPPED":                  "WGPUBufferMapState_Mapped",

    # feature names
    "FEATURE_TIMESTAMP_QUERY":     "WGPUFeatureName_TimestampQuery",
    "FEATURE_SHADER_F16":          "WGPUFeatureName_ShaderF16",

    # buffer usage flags
    "USAGE_MAP_READ":              "WGPUBufferUsage_MapRead",
    "USAGE_COPY_SRC":              "WGPUBufferUsage_CopySrc",
    "USAGE_COPY_DST":              "WGPUBufferUsage_CopyDst",
    "USAGE_UNIFORM":               "WGPUBufferUsage_Uniform",
    "USAGE_STORAGE":               "WGPUBufferUsage_Storage",
    "USAGE_QUERY_RESOLVE":         "WGPUBufferUsage_QueryResolve",

    # status success: the `synchronous` wrapper's guard reads `status != 1`,
    # so this is the SUCCESS code in any of the six status enums; every
    # header enum has Success=1, so the port uses a single 1 here.
    "STATUS_SUCCESS":              "WGPUBufferMapAsyncStatus_Success",

    # port-internal constants
    "BIND_GROUP_INDEX":            None,
    "UNIFORM_SIZE":                None,
    "QUERY_COUNT":                 None,
    "QUERY_BUF_SIZE":              None,
}


def bend_consts(path: str) -> dict[str, int]:
    out: dict[str, int] = {}
    import re
    pat = re.compile(r"^def\s+([A-Za-z_][A-Za-z_0-9]*)\(\)\s*->\s*\w+:\s*(-?\d+)\s*$")
    for line in open(path).read().splitlines():
        m = pat.match(line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def main() -> int:
    port = bend_consts("tinybendygrad/runtime/ops_webgpu.bend")
    if set(port) != set(HAND_MAP):
        missing = set(port) - set(HAND_MAP)
        extra = set(HAND_MAP) - set(port)
        if missing: print(f"!! missing from HAND_MAP: {sorted(missing)}", file=sys.stderr)
        if extra:   print(f"!! extra in HAND_MAP: {sorted(extra)}", file=sys.stderr)
        return 1

    rows = []
    n_exact, n_wrong, n_port_only = 0, 0, 0
    for name, pval in port.items():
        a = HAND_MAP[name]
        if a is None:
            rows.append((name, pval, "NONE", None, "PORT_ONLY"))
            n_port_only += 1
            continue
        try:
            aval = getattr(w, a)
        except AttributeError:
            rows.append((name, pval, a, None, "WRONG"))
            n_wrong += 1
            continue
        status = "OK" if pval == aval else "WRONG"
        if status == "OK": n_exact += 1
        else:              n_wrong += 1
        rows.append((name, pval, a, aval, status))

    print(f"tinybendygrad/runtime/ops_webgpu.bend: {len(port)} consts | "
          f"EXACT {n_exact} | WRONG {n_wrong} | PORT_ONLY {n_port_only}")
    for name, pval, a, aval, status in rows:
        a_disp = a if a is None else f"{a} = {aval}"
        if status == "OK":
            print(f"  {name} = {pval}   | {a_disp}   | STATUS: OK")
        else:
            print(f"  {name} = {pval}   | {a_disp}   | STATUS: {status}")

    return 0 if n_wrong == 0 else 1


if __name__ == "__main__":
    sys.exit(main())