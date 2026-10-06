import re, os, json
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
TINYGRAD = ROOT / "tinygrad"
OUT = ROOT / ".agents" / "slop" / "flagtable"

# Flags that were unverifiable - search for them anywhere in tinygrad/
unverifiable_flags = [
    "DEV", "CPU_COUNT", "IGNORE_JIT_FIRST_BEAM", "BEAM_STRICT_MODE", "BEAM_DEBUG",
    "BEAM_LOG_SURPASS_MAX", "DISABLE_HTTP_CACHE", "NOLOCALS", "ALLOW_HALF8", "DMC",
    "EXPAND_SSA", "JIT_BATCH_SIZE", "PCONTIG", "GRAPH_ONE_KERNEL", "UNSAFE_ALLOW_JIT_BUFFER",
    "ASSERT_COMPILE", "DEBUG_LINEARIZE", "DEBUG_GC", "TRACE", "BROWSER", "NOSKIP",
    "TEST_PICKLE", "THREADS", "APL_REMOTE_SOCK", "IOCTL", "TINYFS_ENDPOINT",
    "TINYFS_TIMEOUT", "ASYNC_COPY_WORKERS", "HCQDEV_WAIT_TIMEOUT_MS", "AMD_DISABLE_SDMA",
    "AMD_SDMA_BIND", "WAVES_PER_SH", "MOCKDSP", "FIX_METAL_ICB", "MLX_IP", "CONST_LR"
]

# Search for each flag in all .py files
for flag in unverifiable_flags:
    pattern = rf'\b{flag}\b'
    found = []
    for pyfile in sorted(TINYGRAD.rglob("*.py")):
        try:
            content = pyfile.read_text()
        except:
            continue
        for i, line in enumerate(content.split("\n"), 1):
            if re.search(pattern, line):
                relpath = str(pyfile.relative_to(ROOT))
                found.append(f"  {relpath}:{i}: {line.strip()[:120]}")
    if found:
        print(f"\n{flag}: FOUND in {len(found)} places")
        for f in found[:5]:  # Show first 5
            print(f)
        if len(found) > 5:
            print(f"  ... and {len(found)-5} more")
    else:
        print(f"\n{flag}: NOT FOUND in tinygrad/")
