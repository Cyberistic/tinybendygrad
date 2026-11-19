#!/usr/bin/env python3
"""callers.py -- THE CALLER CENSUS FOR `.agents/slop/pipelinecensus/`.

THE POPULATION, DECLARED BY DIRECTORY SHAPE AND NOT BY A HAND LIST (`AGENTS.md`,
doctrine 1): the port itself (`tinybendygrad/**/*.bend`), the instruments (`gates/**/*.bend`),
and each live lane's own files (`.agents/slop/<unit>/<file>.bend`, exactly one level under a
unit and never deeper).  THE LAST CLAUSE IS THE POPULATION'S ONLY JUDGEMENT AND IT IS THE
ONE THAT MATTERS: `.agents/slop/<unit>/<sub>/tinybendygrad/...` holds SNAPSHOTS, PLANTS and
MUTATION COPIES of shipped files, and MEASURED, counting them made `linearize` look like it
had 40+ callers when every one of them was a copy of itself.

WHY A WALK AND NOT A GLOB. `AGENTS.md`: `glob('*.bend')` returns `[]` with `.bend` on disk.

WHY COMMENT LINES ARE EXCLUDED. A name in a comment is a MENTION, not an INVOCATION
(`gates/reachability-gate.py` and `gates/pincensus-pop.py`'s `code_lines()` make the same
call). A `#`-leading line is a comment; a trailing `#` after code is not.

OUTPUT: TSV on stdout, one row per stage, with the caller list printed IN FULL so a reader
can check the census instead of trusting it.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

STAGES = [
    ("tensor-realize", "tinybendygrad/tensor.bend",                   "linear_with_vars"),
    ("tensor-life",    "tinybendygrad/tensor.bend",                   "Tensor.realize"),
    ("sink",           "tinybendygrad/schedule/realize.bend",         "rz_built"),
    ("engine-stages",  "tinybendygrad/schedule/rangeify.bend",        "eng_stages"),
    ("run-rangeify",   "tinybendygrad/schedule/rangify.bend",         "rr_kernel_graph"),
    ("schedule",       "tinybendygrad/schedule/__init__.bend",        "schedule"),
    ("add-loads",      "tinybendygrad/codegen/kernel.bend",           "pm_add_loads"),
    ("kernel-body",    "tinybendygrad/runtime/device.bend",           "body_kus"),
    ("device-lane",    "tinybendygrad/runtime/device.bend",           "compile_sink"),
    ("linearizer",     "tinybendygrad/codegen/late/linearizer.bend",  "linearize"),
    ("kuconv",         "tinybendygrad/renderer/kuconv.bend",          "kuconv.convert"),
    ("cstyle",         "tinybendygrad/renderer/cstyle.bend",          "render"),
    ("cc",             "tinybendygrad/runtime/ops_cpu.bend",          "Cpu.compile"),
    ("run",            "tinybendygrad/runtime/ops_cpu.bend",          "Cpu.exec"),
]


def population():
    out = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in {"references", ".git", "node_modules"}]
        for f in files:
            if not f.endswith(".bend"):
                continue
            # A DOTFILE OR A MUTANT IS NOT A CALLER: `.gitignore:36` is `*mut.bend`, and
            # MEASURED `tinybendygrad/codegen/late/.linearizer-mut.bend` (81 KB, UNTRACKED)
            # sat inside the SHIPPED tree and reported three callers of `linearize` -- i.e.
            # a gitignored probe inflating the reachability of the link it mutates.
            if f.startswith(".") or f.endswith("mut.bend") or f.endswith(".bak"):
                continue
            rel = os.path.relpath(os.path.join(base, f), ROOT)
            parts = rel.split(os.sep)
            live = parts[0] == "tinybendygrad" or parts[0] == "gates" or \
                (parts[0] == ".agents" and len(parts) == 4 and parts[1] == "slop")
            if live:
                out.append(rel)
    return sorted(out)


def code_lines(rel):
    try:
        with open(os.path.join(ROOT, rel), "r", encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh, 1):
                if not line.lstrip().startswith("#"):
                    yield i, line
    except OSError:
        return


def def_line(rel, name):
    pat = re.compile(r"^def\s+" + re.escape(name) + r"\s*\(")
    for i, line in code_lines(rel):
        if pat.match(line):
            return i
    return None


def callers(pop, rel, name):
    pat = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"\s*\(")
    out = []
    for other in pop:
        if other == rel:
            continue
        for i, line in code_lines(other):
            if pat.search(line):
                out.append("%s:%d" % (other, i))
    return out


def main():
    pop = population()
    print("# population=%d .bend files (tinybendygrad/ + gates/ + .agents/slop/<unit>/)" % len(pop))
    print("stage\tpath\tdef\tdef_line\tfile_lines\tcallers\tcaller_list")
    for stage, rel, name in STAGES:
        full = os.path.join(ROOT, rel)
        n = sum(1 for _ in open(full, encoding="utf-8", errors="replace")) if os.path.exists(full) else 0
        dl = def_line(rel, name)
        cs = callers(pop, rel, name) if dl else []
        print("%s\t%s\t%s\t%s\t%d\t%d\t%s" % (stage, rel, name, dl if dl else "ABSENT", n,
                                              len(cs), " ".join(cs)))


if __name__ == "__main__":
    sys.exit(main())
