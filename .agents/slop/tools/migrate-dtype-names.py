#!/usr/bin/env python3
"""migrate-dtype-names.py -- move the port and its oracles onto the RUST dtype
attribute names that tinygrad 793abbb introduced, and leave nothing behind that
spells the legacy ones.

Upstream's canonical `dtypes.*` attributes are now i8 u8 i16 u16 i32 u32 i64 u64
f16 bf16 f32 f64 (plus the fp8s and bool/void/weakint/weakfloat, which did not
move). The old spellings survive only inside a block upstream itself labels
`# legacy dtype aliases`, and leaning on that block means the NEXT dtype change
lands on us instead of us being ready for this one.

Three hazards, all of which have bitten:

  * `dtypes.float` is a PREFIX of `dtypes.float32` and `dtypes.float64`, and
    `dtypes.int` of `dtypes.int8` .. `dtypes.int64`. A naive textual replace
    corrupts the longer names. The alternatives below are sorted LONGEST FIRST
    and the whole match is `\\b`-anchored, so `float32` can never be split.
  * `short`, `long`, `char`, `uchar`, `ushort`, `uint`, `ulong` are also aliases
    and are the ones a sweep forgets: `dtypes.short` is int16 and `dtypes.long`
    is int64, NOT "a string".
  * `dtypes.double` is float64 and `dtypes.bool` did not move.

Usage:  migrate-dtype-names.py [--apply] FILE...
"""
import re
import sys

# old attribute -> new attribute. Every alias upstream keeps is here, so a file
# that says `dtypes.half` and one that says `dtypes.float16` converge.
MAP = {
    "int8": "i8", "char": "i8",
    "uint8": "u8", "uchar": "u8",
    "int16": "i16", "short": "i16",
    "uint16": "u16", "ushort": "u16",
    "int32": "i32", "int": "i32",
    "uint32": "u32", "uint": "u32",
    "int64": "i64", "long": "i64",
    "uint64": "u64", "ulong": "u64",
    "float16": "f16", "half": "f16",
    "bfloat16": "bf16",
    "float32": "f32", "float": "f32",
    "float64": "f64", "double": "f64",
}
# longest first, so `float32` is tried before `float` and `uint8` before `uint`
ALT = "|".join(sorted(MAP, key=len, reverse=True))
RE = re.compile(r"\bdtypes\.(" + ALT + r")\b")

# Owned by other agents RIGHT NOW. Migrating one of these mid-flight is how
# fold.bend got a half-written debug line into someone else's baseline.
OWNED = ("uop/fold.bend", "schedule/prepare.bend", "codegen/opt/",
         "renderer/nir", "renderer/isa/x86.bend", "runtime/support/",
         "runtime/ops_metal.bend",
         # A VERBATIM COPY of upstream tinygrad/, taken by another unit so its
         # oracle can run against a frozen tree. It is not our source and its
         # whole point is that it matches upstream byte for byte; rewriting the
         # dtype names inside it would make it a snapshot of nothing.
         "slop/opstree/",
         # this tool and the dtype gate, whose comments quote the old spellings
         # because that is what they are about
         "slop/tools/migrate-dtype-names.py", "slop/dtype-gate.py",
         "slop/fold.preorder.bend", "slop/fold.before-ladder.bend")


def main():
    apply = "--apply" in sys.argv
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    total, skipped = 0, []
    for path in files:
        rel = path.replace("tinybendygrad/", "").replace(".agents/slop/", "slop/")
        if any(rel.startswith(o) or o in rel for o in OWNED):
            n = len(RE.findall(open(path).read()))
            skipped.append((rel, n))
            continue
        src = open(path).read()
        hits = RE.findall(src)
        if not hits:
            continue
        # a per-file tally so a sweep cannot quietly change the wrong thing
        tally = {}
        for h in hits:
            tally[h] = tally.get(h, 0) + 1
        out = RE.sub(lambda m: "dtypes." + MAP[m.group(1)], src)
        if apply:
            open(path, "w").write(out)
        total += len(hits)
        detail = " ".join("%s>%s:%d" % (k, MAP[k], tally[k])
                          for k in sorted(tally, key=lambda k: -tally[k]))
        print("  %-46s %3d  %s" % (rel, len(hits), detail))
    print("TOTAL migrated: %d occurrence(s)" % total)
    for rel, n in skipped:
        print("SKIPPED (other agent owns it): %-40s %d" % (rel, n))


if __name__ == "__main__":
    main()