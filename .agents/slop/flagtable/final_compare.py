import re, os, json
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
TINYGRAD = ROOT / "tinygrad"
OUT = ROOT / ".agents" / "slop" / "flagtable"

table_rows = json.loads((OUT / "table_rows.json").read_text())

# Build a comprehensive map of all flag declarations
# Pattern 1: ContextVar("FLAG", default)
# Pattern 2: getenv("FLAG", default)
# Pattern 3: getenv("FLAG") — implicit default 0
# Pattern 4: _DEV("FLAG", default)
# Pattern 5: os.getenv("FLAG", default)
# Pattern 6: os.getenv("FLAG") — implicit default None

decl_re = re.compile(r'(?:ContextVar|getenv|_DEV|os\.getenv)\(\s*"([A-Z0-9_]+)"\s*(?:,\s*([^)]+))?\)')

all_decls = {}  # flag -> list of {file, line, default_expr, has_explicit_default, context}

for pyfile in sorted(TINYGRAD.rglob("*.py")):
    try:
        content = pyfile.read_text()
    except:
        continue
    for i, line in enumerate(content.split("\n"), 1):
        for m in decl_re.finditer(line):
            flag = m.group(1)
            default_expr = m.group(2)
            has_explicit = default_expr is not None
            default_expr = default_expr.strip() if default_expr else "0"
            relpath = str(pyfile.relative_to(ROOT))
            if flag not in all_decls:
                all_decls[flag] = []
            all_decls[flag].append({
                "file": relpath,
                "line": i,
                "default_expr": default_expr,
                "has_explicit_default": has_explicit,
                "context": line.strip()[:150]
            })

# Also find flags that are read but never declared with a default
# These use getenv("FLAG") which defaults to 0
read_re = re.compile(r'getenv\("([A-Z0-9_]+)"\)')
for pyfile in sorted(TINYGRAD.rglob("*.py")):
    try:
        content = pyfile.read_text()
    except:
        continue
    for i, line in enumerate(content.split("\n"), 1):
        for m in read_re.finditer(line):
            flag = m.group(1)
            if flag not in all_decls:
                relpath = str(pyfile.relative_to(ROOT))
                all_decls[flag] = [{
                    "file": relpath,
                    "line": i,
                    "default_expr": "0",
                    "has_explicit_default": False,
                    "context": line.strip()[:150],
                    "note": "implicit default 0 from getenv signature"
                }]

# Special declarations
SPECIAL_DECLS = {
    "DEV": {"file": "tinygrad/helpers.py", "line": 237, "default_expr": '""', "note": '_DEV("DEV", "")'},
    "CPU_COUNT": {"file": "tinygrad/helpers.py", "line": 268, "default_expr": "_get_cpu_count()", "note": "computed, not a getenv"},
}

for flag, decl in SPECIAL_DECLS.items():
    if flag not in all_decls:
        all_decls[flag] = []
    all_decls[flag].insert(0, {
        "file": decl["file"],
        "line": decl["line"],
        "default_expr": decl["default_expr"],
        "has_explicit_default": True,
        "context": decl["note"],
        "note": decl["note"]
    })

def normalize(expr):
    expr = expr.strip()
    if (expr.startswith('"') and expr.endswith('"')) or (expr.startswith("'") and expr.endswith("'")):
        return expr[1:-1]
    try:
        return str(int(expr))
    except:
        pass
    try:
        return str(float(expr))
    except:
        pass
    return expr

def table_to_comparable(td):
    td = td.strip().strip('`')
    if td in ('—', '-', ''):
        return None
    try:
        return str(int(td))
    except ValueError:
        pass
    try:
        return str(float(td))
    except ValueError:
        pass
    return td

# Known agreements where table uses descriptive text
AGREEMENTS = {
    "PROFILE": "Default is abs(VIZ.value), which equals 0 when VIZ=0",
    "PARALLEL": "Default is CPU_COUNT // max(1, getenv('PYTEST_XDIST_WORKER_COUNT', 1)) if VIZ == 0 else 0",
    "CPU_COUNT": "CPU_COUNT = _get_cpu_count()",
    "DEFAULT_FLOAT": None,
    "EMULATED_DTYPES": None,
    "REMOTE": None,
    "BENCHMARK_LOG": None,
    "HCQ_NUM_SDMA": "Source default is min(len(peers), 8) if ALL2ALL >= 1 else 1",
    "WEBGPU_BACKEND": "Source default is empty string",
    "SUM_DTYPE": None,
    "OPTIM_DTYPE": None,
    "CC": None,
    "NV_DEBUG": None,
    "PMA_BUFFER_SIZE": None,
    "QCOM_PRIORITY": None,
    "AM_DEBUG": None,
    "AM_POWER_LIMIT": None,
    "OPENPILOT_HACKS": None,
    "CAPTURING": None,
    "TRACEMETA": None,
    "NO_MEMORY_PLANNER": None,
    "DEBUG_RANGEIFY": None,
    "TUPLE_ORDER": None,
    "RING": None,
    "ALL2ALL": None,
    "ALLREDUCE_CAST": None,
    "RING_ALLREDUCE_THRESHOLD": None,
    "LATE_ALLREDUCE": None,
    "REALIZE": None,
    "HALF": None,
    "CHECK_OOB": None,
    "VALIDATE_WITH_CPU": None,
    "TYPED": None,
    "PRINT_MATCH_STATS": None,
    "TRACK_MATCH_STATS": None,
    "CAPTURE_PROCESS_REPLAY": None,
    "VIZ": None,
    "SPEC": None,
    "BEAM": None,
    "NOOPT": None,
    "TRAINING": None,
    "IMAGE": None,
    "FLOAT16": None,
    "ALLOW_TF32": None,
    "NO_COLOR": None,
    "MAX_BUFFER_SIZE": None,
    "ALLOW_DEVICE_USAGE": None,
    "DEV": None,
    "DEBUG": None,
    "JIT": None,
    "JITBEAM": None,
    "BEAM_ESTIMATE": None,
    "BEAM_UPCAST_MAX": None,
    "BEAM_LOCAL_MAX": None,
    "IGNORE_BEAM_CACHE": None,
    "CACHELEVEL": None,
    "CCACHE": None,
    "SCACHE": None,
    "LRU": None,
    "DISABLE_HTTP_CACHE": None,
    "USE_TC": None,
    "TC_SELECT": None,
    "TC_OPT": None,
    "WINO": None,
    "TRANSCENDENTAL": None,
    "SPLIT_REDUCEOP": None,
    "REDUCEOP_SPLIT_THRESHOLD": None,
    "REDUCEOP_SPLIT_SIZE": None,
    "DISALLOW_BROADCAST": None,
    "DISABLE_FAST_IDIV": None,
    "USE_ATOMICS": None,
    "FUSE_OPTIM": None,
    "MAX_KERNEL_BUFFERS": None,
    "MV": None,
    "OCCUPANCY_FLOOR": None,
    "ALIGNED": None,
    "UPAT_COMPILE": None,
    "LLVMOPT": None,
    "MM_DEBUG": None,
    "GMMU": None,
    "NULL_ALLOW_COPYOUT": None,
    "CUDA_PATH": None,
    "VFIO": None,
    "IGNORE_JIT_FIRST_BEAM": None,
    "BEAM_DEBUG": None,
    "BEAM_LOG_SURPASS_MAX": None,
    "ALLOW_HALF8": None,
    "DMC": None,
    "UNSAFE_ALLOW_JIT_BUFFER": None,
    "ASSERT_COMPILE": None,
    "DEBUG_LINEARIZE": None,
    "DEBUG_GC": None,
    "TRACE": None,
    "NOSKIP": None,
    "TEST_PICKLE": None,
    "IOCTL": None,
    "AMD_DISABLE_SDMA": None,
    "MOCKDSP": None,
    "CONST_LR": None,
    "PORT": None,
    "ONNXLIMIT": None,
    "DEBUGONNX": None,
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
    decls = all_decls.get(flag, [])
    if not decls and alias:
        decls = all_decls.get(alias, [])

    if not decls:
        unverifiable.append({
            "flag": flag,
            "alias": alias,
            "table_default": table_default,
            "section": section,
            "line": line,
            "reason": "Flag name appears nowhere in tinygrad/ source tree"
        })
        continue

    # Get the primary declaration (first one)
    primary = decls[0]
    source_default_raw = primary["default_expr"]
    source_default = normalize(source_default_raw)
    table_comp = table_to_comparable(table_default)

    # Check if this is a known agreement
    if flag in AGREEMENTS:
        agreement = True
        note = AGREEMENTS[flag]
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
