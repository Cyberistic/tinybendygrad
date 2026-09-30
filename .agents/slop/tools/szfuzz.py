#!/usr/bin/env python3
"""szfuzz -- property-based differential harness. THE TEMPLATE.

Property: for a tree of random .py and .js files, the sz.bend table equals
sz.py's gen_stats(table), row for row. The generator biases HARD toward the
lexer edges that a hand-written fixture never reaches: f-strings with nested
fields and format specs, triple-quoted docstrings (excluded from the count),
`#` inside strings, implicit concat, raw/escape strings, unicode names,
spanned lines. A mismatch prints the seed, the file, and the repro command.

This file is the shape every unit's fuzz harness copies:
  generator (seeded) -> CPython oracle (the unit's OWN python) -> one compiled
  run of the Bend unit -> diff. No expectations are hand-written anywhere.

Usage:
  uv run --with tabulate python3 .agents/slop/tools/szfuzz.py --seeds 30
Options: --files N (files per tree, default 8), --max-lines L (default 40),
  --keep-dir (leave the failing tree for inspection), --verbose.
Exit 0 = all seeds agreed; exit 1 = first mismatch (or the Bend side failed).
"""

import argparse, os, random, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SZ_PY = os.path.join(ROOT, "sz.py")
BEND = os.path.join(ROOT, "bin", "bend")
SZ_BEND = os.path.join(ROOT, "tinybendygrad", "sz.bend")

PY_FRAGS = [
    "x{i} = {n}\n",
    "name_{i} = {a} + {b} * 2\n",
    "y = a @ b ** c // d % e << 2 | g & h ^ ~i\n",
    "s = 'single {i}'\n",
    's = "double {i}"\n',
    "s = '''triple {i}\nstill a string'''\n",
    "s = r'raw\\n not escape {i}'\n",
    's = f"val {{x!r:>10.2f}} end {i}"\n',
    's = f"{{ {{\'k\': 1}}[\'k\'] }} {i}"\n',
    's = f"{{{{escaped}}}} {{x}} {{i}}"\n',
    "s = 'it''s adjacent {i}'\n",
    's = "esc\\n\\t\\x41 {i}"\n',
    's = "not # a comment {i}"\n',
    "d = {{1: [2, (3, {{4}})]}}  # dict {i}\n",
    "n = 0x1F + 0b101 + 1_000_000 + 3.14 + 1e-5 + .5 + 10j\n",
    "\u03c0_{i} = 3.14\n",
    "\u53d8\u91cf{i} = 1\n",
    "# a full comment {i}\n",
    "x = {n}  # trailing comment\n",
    "x = (1 +\n     2)  # spanned {i}\n",
    "if x{i}:\n    pass\nelse:\n    pass\n",
    "a = 1; b = 2  # semicolon {i}\n",
    "@dec_{i}\ndef f{i}():\n    return {n}\n",
    "\n",
    "   \n",
]
PY_DOCS = '"""module docstring {i}\nspread over lines"""\n'
JS_FRAGS = [
    "let x{i} = {n}; // c\n",
    "// full line comment {i}\n",
    'const s{i} = "with // inside";\n',
    "const s{i} = 'single';\n",
    "function f{i}() {{ return {n}; }}\n",
    "const t{i} = `template ${{x}} {i}`;\n",
    "\n",
    "    \n",
    "x{i} + y // trailing\n",
]


def rand_source(rng, exts, max_lines):
    """One random file's text, valid for CPython's tokenize (sz.py dies otherwise)."""
    if exts == "js":
        pool, docs = JS_FRAGS, None
    else:
        pool, docs = PY_FRAGS, PY_DOCS
    n = rng.randint(1, max_lines)
    parts = []
    if docs and rng.random() < 0.25:
        parts.append(docs.format(i=rng.randint(0, 999)))
    for _ in range(n):
        parts.append(rng.choice(pool).format(
            i=rng.randint(0, 999), n=rng.randint(0, 999),
            a=rng.randint(0, 99), b=rng.randint(0, 99), x="v"))
    src = "".join(parts)
    if rng.random() < 0.8:
        src += "\n"  # sometimes no trailing newline
    return src


def build_tree(rng, tree, nfiles, max_lines):
    os.makedirs(os.path.join(tree, "tinygrad", "sub"), exist_ok=True)
    for k in range(nfiles):
        exts = "js" if rng.random() < 0.3 else "py"
        sub = "sub/" if rng.random() < 0.3 else ""
        path = os.path.join(tree, "tinygrad", sub, f"f{k}.{exts}")
        with open(path, "w", encoding="utf-8") as f:
            f.write(rand_source(rng, exts, max_lines))
    # A symlink cycle: os.walk(followlinks=False) never descends it, so sz.py is
    # unaffected. sz.bend's Sz.is_dir uses stat() which FOLLOWS the link, so it
    # descends forever and only the 2^24 fuel stops it -- silently truncating.
    # Divergence recorded 2026-10-01; the port fix is stat -> lstat in sz.c, and
    # these cases pin it. Until the fix lands, a tree with a cycle MISmatches.
    if rng.random() < 0.5:
        os.symlink(".", os.path.join(tree, "tinygrad", "loop"))
        os.symlink("sub", os.path.join(tree, "tinygrad", "link_to_sub"))


def oracle(tree):
    """sz.py's own gen_stats -- the property is 'the port equals sz.py', not
    'the port equals a second reimplementation of sz.py'."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("szmod", SZ_PY)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)  # __name__ != "__main__": main() does not run
    return {row[0]: (row[1], round(row[2], 1)) for row in m.gen_stats(tree)}


ROW = re.compile(r"^\s*(tinygrad/\S+)\s+(\d+)\s+(\d+\.\d)\s*$")


def bend_rows(out):
    rows = {}
    for line in out.splitlines():
        if " in " in line:  # directory aggregate, not a file row
            continue
        m = ROW.match(line)
        if m:
            rows[m.group(1)] = (int(m.group(2)), float(m.group(3)))
    return rows


def run_seed(seed, binary, args, workdir):
    rng = random.Random(seed)
    tree = os.path.join(workdir, f"tree{seed}")
    build_tree(rng, tree, args.files, args.max_lines)
    want = oracle(tree)
    r = subprocess.run([binary, tree], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return f"seed {seed}: sz.bend exited {r.returncode}: {r.stderr.strip()[:200]}"
    got = bend_rows(r.stdout)
    if want != got:
        only_w = {k: v for k, v in want.items() if k not in got}
        only_g = {k: v for k, v in got.items() if k not in want}
        diff = {k: (want[k], got[k]) for k in want.keys() & got.keys() if want[k] != got[k]}
        msg = [f"seed {seed}: MISMATCH"]
        for k, v in list(diff.items())[:5]:
            msg.append(f"  {k}: want {v[0]}, got {v[1]}")
        for k, v in list(only_w.items())[:5]:
            msg.append(f"  {k}: want {v}, got NOTHING")
        for k, v in list(only_g.items())[:5]:
            msg.append(f"  {k}: got {v}, want NOTHING")
        msg.append(f"  repro: uv run --with tabulate python3 {os.path.abspath(__file__)} "
                   f"--seeds {seed + 1} --files {args.files} --max-lines {args.max_lines} --keep-dir")
        if not args.keep_dir:
            shutil.rmtree(tree, ignore_errors=True)
        return "\n".join(msg)
    if not args.keep_dir:
        shutil.rmtree(tree, ignore_errors=True)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--files", type=int, default=8)
    ap.add_argument("--max-lines", type=int, default=40)
    ap.add_argument("--keep-dir", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--binary", help="use a prebuilt sz binary instead of compiling "
                   "(compile once with: ./bin/bend tinybendygrad/sz.bend -o /tmp/sz)")
    ap.add_argument("--collect", action="store_true", help="report EVERY mismatching "
                    "seed instead of stopping at the first, with a distinct-file count")
    args = ap.parse_args()

    workdir = tempfile.mkdtemp(prefix="szfuzz-")
    binary = args.binary
    if not binary:
        binary = os.path.join(workdir, "szfuzz-bin")
        if args.verbose:
            print("compiling sz.bend ...", file=sys.stderr, flush=True)
        c = subprocess.run([BEND, SZ_BEND, "-o", binary], capture_output=True, text=True, timeout=600)
        if c.returncode != 0:
            print(f"sz.bend does not compile:\n{c.stderr[:500]}", file=sys.stderr)
            return 1
    errs = []
    for seed in range(args.seeds):
        if args.verbose:
            print(f"seed {seed}: building + diffing ...", file=sys.stderr, flush=True)
        err = run_seed(seed, binary, args, workdir)
        if err:
            errs.append(err)
            if not args.collect:
                break  # one counterexample is the finding; fix it, then re-run
        elif args.verbose:
            print(f"seed {seed}: ok", file=sys.stderr)
    shutil.rmtree(workdir, ignore_errors=True)
    if errs:
        for e in errs:
            print(e, file=sys.stderr)
        if args.collect:
            import re as _re
            files = set()
            for e in errs:
                files.update(_re.findall(r"tinygrad/\S+", e))
            print(f"MISMATCHES: {len(errs)} seeds, {len(files)} distinct files",
                  file=sys.stderr)
        print("FAIL", file=sys.stderr)
        return 1
    print(f"OK: {args.seeds} seeds x {args.files} files agreed with sz.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
