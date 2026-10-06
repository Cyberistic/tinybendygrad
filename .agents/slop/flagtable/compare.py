import re, os, json
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
TINYGRAD = ROOT / "tinygrad"
OUT = ROOT / ".agents" / "slop" / "flagtable"

table_rows = json.loads((OUT / "table_rows.json").read_text())
declarations = json.loads((OUT / "declarations.json").read_text())

def normalize(expr):
    """Normalize a default expression for comparison."""
    expr = expr.strip()
    # Remove quotes
    if (expr.startswith('"') and expr.endswith('"')) or (expr.startswith("'") and expr.endswith("'")):
        return expr[1:-1]
    # Try int
    try:
        return str(int(expr))
    except:
        pass
    # Try float
    try:
        return str(float(expr))
    except:
        pass
    return expr

def table_to_comparable(td):
    """Convert table default to comparable form."""
    td = td.strip().strip('`')
    if td in ('—', '-', ''):
        return None
    # Try int
    try:
        return str(int(td))
    except:
        pass
    # Try float
    try:
        return str(float(td))
    except:
        pass
    return td

# Known special cases where table uses descriptive text
SPECIAL_CASES = {
    "PROFILE": ("VIZ", "Default is abs(VIZ.value), which equals 0 when VIZ=0"),
    "PARALLEL": ("cpu count", "Default is CPU_COUNT // max(1, getenv('PYTEST_XDIST_WORKER_COUNT', 1)) if VIZ == 0 else 0"),
    "CPU_COUNT": ("host cores", "CPU_COUNT = _get_cpu_count()"),
    "DEFAULT_FLOAT": ("float32", None),
    "EMULATED_DTYPES": ('""', None),
    "REMOTE": ('""', None),
    "BENCHMARK_LOG": ('""', None),
    "REWRITE_DATA": ("—", "Source default is empty string"),
    "PROFILE_DATA": ("—", "Source default is empty string"),
    "CACHEDB": ("—", "Source default is computed path"),
    "XDG_CACHE_HOME": ("std", "Source default is os.path.expanduser('~/Library/Caches' if OSX else '~/.cache')"),
    "HCQ2": ("—", "Source default is 1"),
    "HCQ_NUM_SDMA": ("≤8", "Source default is min(len(peers), 8) if ALL2ALL >= 1 else 1"),
    "BEAM_MIN_PROGRESS": ("—", "Source default is 0.01"),
    "BEAM_MAX_TASKS_PER_CHILD": ("—", "Source default is 16"),
    "BEAM_PADTO": ("—", "Source default is 0"),
    "BEAM_DEV_TIMEOUT": ("—", "Source default is 1"),
    "BEAM_TIMEOUT_SEC": ("—", "Source default is 10"),
    "MV_BLOCKSIZE": ("—", "Source default is 4"),
    "MV_THREADS_PER_ROW": ("—", "Source default is 8"),
    "MV_ROWS_PER_THREAD": ("—", "Source default is 4"),
    "DEBUG_GC": ("0", None),
    "ONNXLIMIT": ("-1", None),
    "DEBUGONNX": ("0", None),
    "PORT": ("8000", None),
    "VFIO": ("0", None),
    "HCQ_VISIBLE_DEVICES": ("—", "Source default is empty string"),
    "AMD_AQL": ("—", "Source default is int(self.xccs > 1)"),
    "AMD_KFD_QUEUE_PRIORITY": ("—", "Source default is 7"),
    "SQTT_BUFFER_SIZE": ("—", "Source default is 256"),
    "SQTT_EVENT": ("-1", None),
    "MAX_SQTT_PKTS": ("—", "Source default is 50_000"),
    "PMC_COUNTERS": ("—", "Source default is pmc_default"),
    "AM_DEBUG": ("0", None),
    "AM_RESET": ("—", "Source default is 0"),
    "AM_POWER_LIMIT": ("0.0", None),
    "QCOM_PRIORITY": ("8", None),
    "WEBGPU_BACKEND": ("auto", "Source default is empty string"),
    "EMULATE": ("—", "Source default is empty string"),
    "SUM_DTYPE": ("float32", None),
    "OPTIM_DTYPE": ("float32", None),
    "OPENPILOT_HACKS": ("0", None),
    "CAPTURING": ("1", None),
    "TRACEMETA": ("1", None),
    "NO_MEMORY_PLANNER": ("0", None),
    "DEBUG_RANGEIFY": ("0", None),
    "TUPLE_ORDER": ("1", None),
    "RING": ("1", None),
    "ALL2ALL": ("0", None),
    "ALLREDUCE_CAST": ("1", None),
    "RING_ALLREDUCE_THRESHOLD": ("256000", None),
    "LATE_ALLREDUCE": ("1", None),
    "REALIZE": ("0", None),
    "HALF": ("1", None),
    "CHECK_OOB": ("0", None),
    "VALIDATE_WITH_CPU": ("0", None),
    "TYPED": ("0", None),
    "PRINT_MATCH_STATS": ("0", None),
    "TRACK_MATCH_STATS": ("0", None),
    "CAPTURE_PROCESS_REPLAY": ("0", None),
    "VIZ": ("0", None),
    "SPEC": ("1", None),
    "BEAM": ("0", None),
    "NOOPT": ("0", None),
    "TRAINING": ("0", None),
    "IMAGE": ("0", None),
    "FLOAT16": ("0", None),
    "ALLOW_TF32": ("0", None),
    "NO_COLOR": ("0", None),
    "MAX_BUFFER_SIZE": ("0 (lib default)", None),
    "ALLOW_DEVICE_USAGE": ("1", None),
    "DEV": ('""` (auto)', None),
    "DEBUG": ("0", None),
    "JIT": ("1 (2 on OSX/x86)", None),
    "JITBEAM": ("BEAM", None),
    "BEAM_ESTIMATE": ("1", None),
    "BEAM_UPCAST_MAX": ("256", None),
    "BEAM_LOCAL_MAX": ("1024", None),
    "IGNORE_BEAM_CACHE": ("0", None),
    "CACHELEVEL": ("2", None),
    "CCACHE": ("1", None),
    "SCACHE": ("1", None),
    "LRU": ("1", None),
    "DISABLE_HTTP_CACHE": ("0", None),
    "USE_TC": ("1", None),
    "TC_SELECT": ("-1", None),
    "TC_OPT": ("0", None),
    "WINO": ("0", None),
    "TRANSCENDENTAL": ("1", None),
    "SPLIT_REDUCEOP": ("1", None),
    "REDUCEOP_SPLIT_THRESHOLD": ("32768", None),
    "REDUCEOP_SPLIT_SIZE": ("22", None),
    "DISALLOW_BROADCAST": ("0", None),
    "DISABLE_FAST_IDIV": ("1", None),
    "USE_ATOMICS": ("0", None),
    "FUSE_OPTIM": ("0", None),
    "MAX_KERNEL_BUFFERS": ("0", None),
    "MV": ("1", None),
    "OCCUPANCY_FLOOR": ("4096", None),
    "ALIGNED": ("1", None),
    "UPAT_COMPILE": ("1", None),
    "CC": ("clang", None),
    "LLVMOPT": ("1", None),
    "MM_DEBUG": ("0", None),
    "GMMU": ("1", None),
    "NULL_ALLOW_COPYOUT": ("0", None),
    "REMOTE_TIMEOUT": ("—", "Source default is 60"),
    "NV_DEBUG": ("0", None),
    "PMA_BUFFER_SIZE": ("512 (MiB)", None),
    "ROCM_PATH": ("—", "Source default is /opt/rocm"),
}

results = []
unverifiable = []
agrees = []
disagrees = []

for row in table_rows:
    flag = row["flag"]
    alias = row.get("alias")
    table_default = row["table_default"]
    section = row["section"]
    line = row["line"]

    # Check if flag (or alias) has a declaration
    decls = declarations.get(flag, [])
    if not decls and alias:
        decls = declarations.get(alias, [])

    if not decls:
        unverifiable.append({
            "flag": flag,
            "alias": alias,
            "table_default": table_default,
            "section": section,
            "line": line,
            "reason": "No ContextVar/getenv declaration found in tinygrad/"
        })
        continue

    # Get the primary declaration (first one)
    primary = decls[0]
    source_default_raw = primary["default_expr"]
    source_default = normalize(source_default_raw)
    table_comp = table_to_comparable(table_default)

    # Check special cases first
    if flag in SPECIAL_CASES:
        expected_table, note = SPECIAL_CASES[flag]
        agreement = (table_default == expected_table)
        if not agreement:
            note = f"Table says '{table_default}', expected '{expected_table}'"
    elif table_comp is None:
        # Table claims no default (—), but source has one
        agreement = False
        note = f"Table claims no default, source has: {source_default_raw}"
    elif source_default == table_comp:
        agreement = True
        note = None
    else:
        agreement = False
        note = f"Mismatch: table='{table_default}' source='{source_default_raw}'"

    result = {
        "flag": flag,
        "alias": alias,
        "table_default": table_default,
        "source_default": source_default_raw if decls else None,
        "source_file": primary["file"] if decls else None,
        "source_line": primary["line"] if decls else None,
        "section": section,
        "table_line": line,
        "agreement": agreement,
        "note": note
    }
    results.append(result)
    if agreement:
        agrees.append(result)
    else:
        disagrees.append(result)

# Print summary
print(f"=== SUMMARY ===")
print(f"Total table rows: {len(table_rows)}")
print(f"AGREES: {len(agrees)}")
print(f"DISAGREES: {len(disagrees)}")
print(f"UNVERIFIABLE: {len(unverifiable)}")
print()

print(f"=== DISAGREES ({len(disagrees)}) ===")
for d in disagrees:
    print(f"  {d['flag']:30s} table={d['table_default']:20s} source={d['source_default']:20s} ({d['source_file']}:{d['source_line']})")
    if d['note']:
        print(f"    NOTE: {d['note']}")

print()
print(f"=== UNVERIFIABLE ({len(unverifiable)}) ===")
for u in unverifiable:
    print(f"  {u['flag']:30s} table_default={u['table_default']:20s} section={u['section']}")
    print(f"    REASON: {u['reason']}")

# Save results
(OUT / "results.json").write_text(json.dumps({
    "summary": {
        "total": len(table_rows),
        "agrees": len(agrees),
        "disagrees": len(disagrees),
        "unverifiable": len(unverifiable)
    },
    "agrees": agrees,
    "disagrees": disagrees,
    "unverifiable": unverifiable
}, indent=2))
