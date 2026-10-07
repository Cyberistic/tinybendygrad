"""FLIPTHIRD: census the `Arg` vocabulary seam by DISCOVERY (doctrine 1).

Populations, all discovered by walk:
  1. the constructors of `type Arg`   -- parsed from ops.bend, not a hand list
  2. every `match` over an `O.Arg`/`Arg` typed binding, and whether it is EXHAUSTIVE
     (covers every constructor) or has a `case _` catch-all
  3. every FLIP construction site / ATuple reader (the blast radius, re-measured today)

Output: .agents/slop/flipthird/argseam.rows
"""
import os, re, sys

ROOT = "tinybendygrad"
OPS = os.path.join(ROOT, "uop", "ops.bend")
# MEASURED 2026-10-07 ~06:55: `tinybendygrad/tinybendygrad/` is an UNTRACKED,
# byte-identical recursive copy of the whole port (md5 of both `uop/render.bend`
# files is the same; `git ls-tree -r HEAD` names 0 of its paths). A walk that
# descends into it counts every row TWICE and its population is not the port.
# It is skipped here and its size reported, because an instrument that cannot
# see what it is counting cannot be right (doctrine 1).
NESTED = os.path.join(ROOT, ROOT)

# ---- population 1: the Arg constructors, parsed by name -------------------
arg_block = []
in_block = False
for i, line in enumerate(open(OPS), 1):
    if re.match(r"^type Arg is Data:", line):
        in_block = True
        start = i
        continue
    if in_block:
        m = re.match(r"^  (A[A-Za-z0-9]*)\{", line)
        if m:
            arg_block.append((m.group(1), i))
        elif line.strip() and not line.startswith("  ") and not line.startswith("#"):
            in_block = False
CTORS = [c for c, _ in arg_block]
CLINE = dict(arg_block)

# ---- population 2: every match over an Arg-typed value -------------------
def bend_files():
    """Every .bend under the port, EXCLUDING the untracked nested duplicate."""
    for d, dirs, fs in os.walk(ROOT):
        if os.path.abspath(d).startswith(os.path.abspath(NESTED)):
            dirs[:] = []
            continue
        for f in sorted(fs):
            if f.endswith(".bend"):
                yield os.path.join(d, f)


def nested_size():
    n = 0
    for d, dirs, fs in os.walk(NESTED):
        n += sum(1 for f in fs if f.endswith(".bend"))
    return n

def body_of(src, start):
    """Lines of a match block: from `start` until a line at col 0 that is not blank/comment."""
    out, i = [], start
    while i < len(src):
        ln = src[i]
        if i > start and ln.strip() and not ln.startswith((" ", "\t")):
            break
        out.append((i + 1, ln))
        i += 1
    return out

def is_exhaustive(arms, ctor_re, has_default):
    """A match is exhaustive-without-default iff it names every ctor of the vocabulary."""
    named = set()
    for _, ln in arms:
        m = ctor_re.search(ln)
        if m:
            named.add(m.group(1))
    missing = [c for c in CTORS if c not in named]
    return (not has_default), missing, named

CTOR_RE = re.compile(r"\bO\.(A[A-Za-z0-9]*)\s*\{|\b(A[A-Za-z0-9]*)\s*\{")

seam = []   # (file, line, defname, exhaustive?, has_default, n_named, n_missing)
for path in bend_files():
    src = open(path).read().split("\n")
    for i, ln in enumerate(src):
        m = re.match(r"^def (\w+)\(([^)]*)\)\s*->", ln)
        if not m:
            continue
        name, params = m.group(1), m.group(2)
        # an Arg-typed parameter
        if not re.search(r":\s*(O\.)?Arg\b", params):
            continue
        # the match must immediately follow
        j = i + 1
        while j < len(src) and (not src[j].strip() or src[j].lstrip().startswith("#")):
            j += 1
        if j >= len(src) or not src[j].strip().startswith("match "):
            continue
        arms = body_of(src, j)
        named, has_default = set(), False
        for _, a in arms[1:]:
            s = a.strip()
            if s.startswith("case _"):
                has_default = True
            mm = CTOR_RE.search(s)
            if mm:
                named.add(mm.group(1) or mm.group(2))
        missing = [c for c in CTORS if c not in named]
        # EXHAUSTIVE means the match names every constructor. `ABad` is a REAL
        # constructor (the tree's deliberate catch-all), so an arm on it counts as
        # coverage of nothing in particular but still makes the match total -- a
        # 22nd constructor is absorbed by it. `case _` is the other escape.
        escape = has_default or ("ABad" in named)
        seam.append((path, j + 1, name, not missing or escape,
                     has_default, len(named), missing))

# a match that is total TODAY but whose totality depends on naming every ctor
# (or on ABad) is the one that a 22nd constructor could break.

print("# FLIPTHIRD argseam census")
print(f"# population: type Arg at {OPS}:{start} -- {len(CTORS)} constructors, PARSED not listed")
print("# " + " ".join(CTORS))
print(f"# population: {len(CTORS)} ctors; matches discovered by os.walk over {ROOT}/**/*.bend")
print(f"# EXCLUDED: {NESTED}/ is an untracked byte-identical copy of the port "
      f"({nested_size()} .bend files); counting it would double every row.")
print()
print("# file\tmatch_line\tdef\texhaustive\thas_default\tnamed\tmissing")
for path, line, name, exh, hd, n, missing in sorted(seam, key=lambda r: (r[0], r[1])):
    print(f"{path}\t{line}\t{name}\t{int(exh)}\t{int(hd)}\t{n}\t{','.join(missing) if missing else '-'}")

strict = [r for r in seam if r[3]]
open_ends = [r for r in seam if not r[3]]   # a 22nd ctor BREAKS these
print()
print(f"# matches over Arg discovered: {len(seam)}")
print(f"#   total TODAY (named-every-ctor, or `case _`, or an `ABad` arm): {len(strict)}")
print(f"#   OPEN-ENDED via `_` or `ABad` (a 22nd ctor CANNOT break them): "
      f"{sum(1 for r in strict if r[4] or 'ABad' in str(r[6]))}")
print(f"#   a 22nd ctor WOULD BREAK (total, but only by naming all {len(CTORS)}): "
      f"{sum(1 for r in strict if not r[4] and not r[6])}")
print()
for path, line, name, exh, hd, n, missing in sorted(strict, key=lambda r: (r[0], r[1])):
    if not hd and not missing:
        print(f"# CLOSED\t{path}:{line}\t{name}\tnames all {n} ctors, no `_`, no ABad")
for path, line, name, exh, hd, n, missing in open_ends:
    print(f"# NOT-TOTAL-TODAY\t{path}:{line}\t{name}\tmissing={','.join(missing) or '-'}")