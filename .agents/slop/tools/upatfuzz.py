#!/usr/bin/env python3
"""upatfuzz -- property-based differential harness for the pattern COMPILER.

Property: for a random UPat, upat.bend's compiled code == tinygrad's
`_get_code(pat, has_ctx)` -- the source STRING and the `dyn_lookup` KEY order,
which is the whole of `_get_code`'s return.

The oracle is the unit's OWN python (tinygrad/uop/upat.py), reached through its
own `_get_code`. Nothing is hand-expected: a case is a one-line string, the
oracle builds a real `UPat` from it and reads `_get_code` back, the Bend side
parses the SAME string and runs the same `upat_compile` the gate runs, and the
two canonical lines are compared.

Generator bias -- the edges a hand fixture never reached:
  * `max_depth` NODES in post-order, not depth-first descent: a src may name any
    EARLIER node, so the tree is a DAG and the shapes are dense. An earlier
    depth-first version produced a repeat-whose-child-has-a-src (the M18 shape)
    1.75% of the time, which is a harness that would have MISSED the bug the
    unit just lost a gate row over.
  * a repeat's child is chosen from the `rich` set -- children that already have
    a src -- so the repeat/tuple arms reach DEEP subtrees by construction
  * `is_any` with 1-4 alternatives, at least one of them a repeat
  * a name bound in TWO alternatives of an is_any (safe: store copies per
    alternative) AND a name bound twice within ONE src tuple (the port must emit
    an identity check) -- both generated, and they are distinguishable: the
    second one prints `uop is uop.src[1]` and the first does not
  * `allow_any_len` on and off against a tuple src, so `strict_length` and
    `required_len` take every combination
  * op/dtype/tag lists of length 1 (the `is`/`==` arms) and 2+ (the `in` arms),
    so the `a{n}` sharing `wrap` does is exercised both ways
  * arg as a bare int (the inlined arm, spends no `a{n}`) and as a literal
  * a `l` (list) src, which is the `itertools.permutations` fork

# KNOWN DIVERGENCES, both reported and both left UNFIXED in the unit (2026-10-01).
# They are the harness working, not the harness failing. The exit code is 1
# because the property is false, and these are why.

#  1. A NESTED FORK FLATTENS.  `get_clause.go`'s child walk hardcodes
#     `one = True{}` for a src-TUPLE child, so when that child is a fork
#     (`SList`, two or more alternatives) `alt_group` leaves each permutation's
#     children as SEPARATE groups instead of one group per permutation, and the
#     OR gets 2x the branches with the `and` grouping lost. Visible only when
#     the fork is NOT the root, which is why the printed gate never saw it.
#     Minimal:  ctx|-;-;-;-;-;-;0;0|ADD;...|MUL;...|-;-;-;-;-;l1,2;0;0|-;-;-;-;-;t3;0;0
#     A ONE-LINE FIX EXISTS and was verified against all 15 gate rows and this
#     whole harness: pass `one_alt(O.UPat.src(nth(pat, y)))` in place of that
#     `True{}`. It is NOT applied -- the driver edit is the only change to
#     upat.bend and the bug is the file owner's to take.

#  2. TWO STRUCTURALLY EQUAL CHILDREN IN A `l` SRC.  The pattern arena
#     (`pintern`) interns, so two case nodes with identical fields are ONE arena
#     index; `all_same` compares indices and says "all same", giving ONE
#     alternative. tinygrad's `UPat` is NOT interned and `all_same` is
#     `all(x == items[0])`, i.e. identity, so CPython gets TWO permutations.
#     This is ops.bend's modelling, not upat.bend's, and the header already
#     records the region as unreachable from ops.py (the only list-src caller is
#     `alu`, always BINARY). Minimal:
#     ctx|-;-;-;-;-;-;0;0|-;-;-;-;-;-;0;0|-;-;-;-;-;l0,1;0;0
#     A `l` src of arity 3+ is the same story (ops.bend's `perms` refuses it).

# Neither is a hand-written expectation anywhere in this file: the only
# comparison is `want != got` against CPython's own `_get_code`.


Usage:
  uv run python3 .agents/slop/tools/upatfuzz.py --seeds 5 --verbose
Options: --max-depth D (default 5), --binary PATH, --keep-case, --verbose.
Exit 0 = every seed agreed; exit 1 = first counterexample (printed with its
seed and a repro command).
"""

import argparse, os, random, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
BEND = os.path.join(ROOT, "bin", "bend")
UPAT_BEND = os.path.join(ROOT, "tinybendygrad", "uop", "upat.bend")

# The vocabulary of the case format. Every one of these is a real Op / DType /
# Tag in ops.bend, and the oracle maps the same names to tinygrad's.
OPS = ["ADD", "MUL", "SUB", "MAX", "NEG", "INDEX", "CONST", "CALL"]
DTS = ["f32", "i32", "h"]
TAGS = ["A", "B"]
NAMES = ["a", "b", "m", "s", "p", "i", "x", "y"]


def build_case(rng, max_depth):
    """One case: the ctx flag and a post-order node list, `|` separated."""
    nodes, srcs = [], []
    n = rng.randint(1, max_depth)
    for _ in range(n):
        depth = rng.randint(1, max_depth)
        # op: none, one (the `is` arm), or several (the `in` arm) -- and a
        # repeat of a set already used, in a different order, so the two
        # PYLITERALs are EQUAL in Python and the port must agree.
        r = rng.random()
        if r < 0.25:
            op = "-"
        elif r < 0.72:
            op = rng.choice(OPS)
        else:
            k = rng.randint(2, 3)
            op = "+".join(rng.sample(OPS, k))
        name = "-" if rng.random() < 0.5 else rng.choice(NAMES)
        r = rng.random()
        arg = "-" if r < 0.6 else (f"i{rng.randint(0, 9)}" if r < 0.85 else "s")
        r = rng.random()
        dt = "-" if r < 0.6 else "+".join(rng.sample(DTS, 1 if r < 0.8 else 2))
        r = rng.random()
        tag = "-" if r < 0.7 else "+".join(rng.sample(TAGS, 1 if r < 0.85 else 2))
        # the src arm. A repeat needs exactly one child, and a `t` with an
        # index repeated is the shape the arena interns.
        # POST-ORDER IS THE ACYCLICITY GUARANTEE: a node's src may name any
        # EARLIER node, so no depth filter is needed and none is used. An
        # earlier depth filter thinned the space to the point where a repeat
        # whose child has a src -- the exact shape the unit's M18 mutation
        # lives on -- came out 1.75% of the time, which is a harness that would
        # have missed the bug this file just lost a gate row over. `max_depth`
        # now caps the size of the node list instead.
        kids = list(range(len(nodes)))
        # `rich` is the subset of kids that ALREADY HAVE A SRC, and the repeat
        # and tuple arms both prefer one: a repeat of a child with a src of its
        # own is what makes `substitute` meet a two-element INDEX(CUSTOMI,
        # CONST) and rebuild it, and the M18 row is the one that moves.
        rich = [i for i in kids if srcs[i] != "-"]
        want_any = rng.random() < 0.3
        r = rng.random()
        if r < 0.2 or not kids:
            src = "-"
        elif r < 0.45:
            src = f"r{rng.choice(rich or kids)}"
        elif r < 0.82:
            pool = rich or kids
            src = "t" + ",".join(str(rng.choice(pool))
                                 for _ in range(rng.randint(1, min(3, len(pool)))))
        else:
            # the permutations fork, arity 1 or 2 -- ops.bend REFUSES 3+
            k = rng.randint(1, min(2, len(kids)))
            src = "l" + ",".join(str(rng.choice(kids)) for _ in range(k))
        any = "1" if (want_any and src.startswith("t")) else "0"
        aal = "1" if rng.random() < 0.3 else "0"
        nodes.append(";".join([op, name, arg, dt, tag, src, any, aal]))
        srcs.append(src)
    # THE PAIR THE HEADER CALLS OUT. A name bound in two alternatives of an
    # is_any is SAFE -- the store copies live per alternative -- while the same
    # name bound twice in ONE src tuple is the duplicate store the port must
    # render as an identity compare. Both are emitted, and they ARE
    # distinguishable: the second prints a `{0} is {1}` and the first does not,
    # so a harness that could not tell them apart would be a weak one.
    if rng.random() < 0.35:
        m = rng.choice(NAMES)
        two = f"{rng.choice(OPS)};{m};-;-;-;-;0;0"
        if rng.random() < 0.5:
            # TWO ALTERNATIVES of an is_any, both binding m: the safe shape.
            nodes = [f"{rng.choice(OPS)};-;-;-;-;-;0;0", two,
                     "-;-;-;-;-;t0,1;1;0"]
        else:
            # ONE src tuple, two children, both binding m: the identity check.
            nodes = [f"{rng.choice(OPS)};-;-;-;-;-;0;0", two,
                     f"{rng.choice(OPS)};{m};-;-;-;t0,1;0;0"]
    ctx = "noctx" if rng.random() < 0.2 else "ctx"
    return ctx + "|" + "|".join(nodes)


# ---------------------------------------------------------------------------
# The oracle. The case is the CONTRACT, so this side builds the UPat itself
# from the same string -- it never reads anything the Bend side produced.
# ---------------------------------------------------------------------------
def oracle(case):
    sys.path.insert(0, ROOT)
    from tinygrad.uop.upat import _get_code
    from tinygrad.uop.ops import UPat, Ops
    from tinygrad.dtype import dtypes

    op_of = {n: getattr(Ops, n) for n in OPS}
    dt_of = {"f32": dtypes.float32, "i32": dtypes.int32, "h": dtypes.half}
    tg_of = {n: n for n in TAGS}

    ctx, _, rest = case.partition("|")
    ups = []
    for rec in rest.split("|"):
        op, name, arg, dt, tag, src, aany, aal = rec.split(";")
        kw = {}
        if op != "-":
            kw["op"] = tuple(op_of[o] for o in op.split("+"))
        if name != "-":
            kw["name"] = name
        if arg == "s":
            kw["arg"] = "z"
        elif arg.startswith("i"):
            kw["arg"] = int(arg[1:])
        elif arg.startswith("t"):
            kw["arg"] = tuple(int(x) for x in arg[1:].split(","))
        if dt != "-":
            kw["dtype"] = tuple(dt_of[d] for d in dt.split("+"))
        if tag != "-":
            kw["tag"] = tuple(tg_of[t] for t in tag.split("+"))
        kids = [int(i) for i in src[1:].split(",")] if src != "-" else []
        # `t` is a tuple, `l` a list (permutations), `r` a bare UPat (repeat) --
        # exactly the four shapes `__init__` dispatches on.
        if src.startswith("r"):
            kw["src"] = ups[kids[0]]
        elif src.startswith("t"):
            kw["src"] = tuple(ups[i] for i in kids)
        elif src.startswith("l"):
            kw["src"] = [ups[i] for i in kids]
        if aany == "1":
            kw["is_any"] = True
        if aal == "1":
            kw["allow_any_len"] = True
        ups.append(UPat(**kw))
    code = _get_code(ups[-1], ctx != "noctx")
    if code is None:
        return "NONE"
    # the `# match for {location}` header is get_location's and is NOT PORTED
    body = code[0].split("\n", 1)[1].replace("\n", "\\n")
    return f"{body} | {','.join(code[1].keys())}".strip()


def bend_line(binary, path):
    r = subprocess.run([binary, path], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return f"<exit {r.returncode}: {r.stderr.strip()[:200]}>"
    # the port reads the case with `H.printable`, which trims; trim the oracle
    # to match so a diff is a real difference and not trailing whitespace.
    out = r.stdout.strip()
    return out if out else "<no output>"


def run_seed(seed, binary, args, workdir):
    rng = random.Random(seed)
    case = build_case(rng, args.max_depth)
    path = os.path.join(workdir, f"case{seed}.txt")
    with open(path, "w") as f:
        f.write(case + "\n")
    try:
        want = oracle(case)
    except Exception as e:  # tinygrad's OWN _get_clause may refuse a shape --
        if not args.keep_case:  # that is the oracle's limit, not a port answer
            os.unlink(path)
        if args.verbose:
            print(f"seed {seed}: oracle raised {type(e).__name__} (tinygrad's own "
                  f"limit, not a port divergence) -- skipping", file=sys.stderr)
        return "SKIP"
    got = bend_line(binary, path)
    if want != got:
        msg = [f"seed {seed}: MISMATCH", f"  case: {case}",
               f"  want: {want}", f"  got:  {got}",
               f"  repro: uv run python3 {os.path.abspath(__file__)} "
               f"--seeds {seed + 1} --max-depth {args.max_depth} --keep-case "
               f"--binary {binary}"]
        if not args.keep_case:
            os.unlink(path)
        return "\n".join(msg)
    if not args.keep_case:
        os.unlink(path)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--max-depth", type=int, default=5)
    ap.add_argument("--keep-case", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--binary", help="use a prebuilt binary (compile once with: "
                   "./bin/bend tinybendygrad/uop/upat.bend -o BIN)")
    args = ap.parse_args()

    workdir = tempfile.mkdtemp(prefix="upatfuzz-")
    binary = args.binary
    if not binary:
        binary = os.path.join(workdir, "upatfuzz-bin")
        if args.verbose:
            print("compiling upat.bend (once) ...", file=sys.stderr, flush=True)
        c = subprocess.run([BEND, UPAT_BEND, "-o", binary],
                           capture_output=True, text=True, timeout=600)
        if c.returncode != 0:
            print(f"upat.bend does not compile:\n{c.stderr[:500]}", file=sys.stderr)
            return 1
    bad = 0
    skips = 0
    for seed in range(args.seeds):
        if args.verbose:
            print(f"seed {seed}: building + diffing ...", file=sys.stderr, flush=True)
        err = run_seed(seed, binary, args, workdir)
        if err == "SKIP":
            skips += 1
            continue
        if err:
            print(err, file=sys.stderr)
            bad += 1
            break
        if args.verbose:
            print(f"seed {seed}: ok", file=sys.stderr)
    shutil.rmtree(workdir, ignore_errors=True)
    if bad:
        print("FAIL", file=sys.stderr)
        return 1
    print(f"OK: {args.seeds - skips} seeds agreed with tinygrad's _get_code "
          f"({skips} skipped: the oracle itself refused the shape)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
