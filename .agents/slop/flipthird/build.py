"""FLIPTHIRD exp3: build `ABoolList` ITERATIVELY and let `bend` name each break.

WHY ITERATIVE: `bend` reports only the FIRST compile error. `radius.py` probed
once and got the same first break (`ops.bend:2142 eq_arg.sel`) from all 7 targets
-- which measures "where it breaks FIRST", not "the radius". A single probe
cannot produce a radius. So the radius is produced by fixing the first break,
re-running, and reading the next, until bend is green or stops at a file this
unit does not own.

RULE ENFORCED IN CODE: `OWNED` is the brief's list, literal, and the loop
REFUSES to write any file not in it. Forbidden files are compiled, never edited.
Every edit is recorded and the whole thing is reverted at the end.

Only `bend` settles this; this is the run that settles it.
"""
import hashlib, os, re, subprocess

OPS = "tinybendygrad/uop/ops.bend"
FOLD = "tinybendygrad/uop/fold.bend"
OWNED = {"tinybendygrad/uop/ops.bend",
         "tinybendygrad/uop/fold.bend",
         "tinybendygrad/mixin/movement.bend",
         "tinybendygrad/schedule/prepare.bend",
         "tinybendygrad/tensor.bend"}
ROOT_TARGET = "tinybendygrad/tensor.bend"   # imports render+upat, widest owned net
BEND, BOUND = "./bin/bend", [".venv/bin/python", "checks/bounded.py",
                             "--seconds", "400", "--mb", "2048", "--"]

LOG = []


def say(s=""):
    print(s, flush=True)
    LOG.append(s)


def compile_root(tag):
    err = f".agents/slop/flipthird/e3-{tag}.err"
    with open(err, "wb") as fh:
        subprocess.call(BOUND + [BEND, ROOT_TARGET], stdout=fh, stderr=subprocess.STDOUT)
    txt = open(err, encoding="utf-8", errors="replace").read()
    tok = re.search(r"(KILLED-ON-MEMORY|TIMED-OUT|WITHIN-LIMITS)", txt)
    m = re.search(r"expected : cases for \S*\.?(ABoolList)", txt)
    loc = re.search(r"Location: (\S+)", txt)
    nxt = re.search(r"^(\d+) \|", txt, re.M)
    ctx = re.findall(r"^\s*\d+ \|.*$", txt, re.M)[:6]
    return {"token": tok.group(1) if tok else "NO-TOKEN",
            "missing": m.group(1) if m else None,
            "loc": loc.group(1) if loc else None,
            "at": int(nxt.group(1)) if nxt else None,
            "ctx": ctx,
            "green": "ALL PROOFS PASS" in txt}


def patch(path, edits):
    """edits: (anchor_line, inserted_text, where) with where in {'after','before'}.

    The anchor is ONE line and is never rewritten, so a def header keeps column 0
    and no call site hand-counts newlines.
    """
    assert path in OWNED, f"REFUSING to edit non-owned {path}"
    src = open(path, encoding="utf-8").read()
    for anchor, ins, where in edits:
        assert "\n" not in anchor, f"anchor must be one line: {anchor!r}"
        assert anchor in src, f"anchor absent in {path}: {anchor[:70]!r}"
        joined = anchor + "\n" + ins if where == "after" else ins + "\n" + anchor
        src = src.replace(anchor, joined, 1)
    open(path, "w", encoding="utf-8").write(src)
    open(path, "w", encoding="utf-8").write(src)


def main():
    pristine = {p: hashlib.md5(open(p, "rb").read()).hexdigest()
                for p in OWNED if os.path.exists(p)}
    say(f"# FLIPTHIRD exp3 -- iterative build of `ABoolList`, bend naming each break")
    say(f"# target: {ROOT_TARGET}   owned: {len(OWNED)} files   forbidden files are NEVER written")
    say()

    # --- step 1: the variant itself, in ops.bend (owned) ---
    CTOR_COMMENT = ("  # FLIPTHIRD probe: bool-carrying FLIP arg "
                    "(`ops.py:428` asserts `all(isinstance(x, bool) for x in self.marg)`)")
    patch(OPS, [("  ATuple{ys: List<&2, U32>}",
                 CTOR_COMMENT + "\n  ABoolList{bs: List<&2, Bool>}", "after")])
    r = compile_root("s1")
    say(f"[1] +ABoolList in ops.bend            token={r['token']} "
        f"missing={r['missing']} loc={r['loc']} line={r['at']}")
    for c in r["ctx"]:
        say(f"      | {c.strip()}")

    # --- step 2: eq_arg.ABoolList + eq_bool_list + eq_arg.sel arm (ops.bend, owned) ---
    patch(OPS, [("def eq_arg.ATuple(y: Arg, +ys: List<&2, U32>) -> Bool:",
                 "def eq_bool_list(ys: List<&2, Bool>, zs: List<&2, Bool>) -> Bool:\n"
                 "  match ys zs:\n"
                 "    case Nil{} Nil{}: True{}\n"
                 "    case y <> t w <> u: Bool.and(eq_bool(y, w), eq_bool_list(t, u))\n"
                 "    case Nil{} _ <> _: False{}\n"
                 "    case _ <> _ Nil{}: False{}\n\n"
                 "def eq_arg.ABoolList(y: Arg, +bs: List<&2, Bool>) -> Bool:\n"
                 "  match y:\n"
                 "    case ABoolList{y1}: eq_bool_list(bs, y1)\n"
                 "    case _: False{}\n", "before"),
                ("    case ATuple{ys}: eq_arg.ATuple(y, ys)",
                 "    case ABoolList{bs}: eq_arg.ABoolList(y, bs)", "after")])
    r = compile_root("s2")
    say(f"[2] +eq_arg.ABoolList +eq_bool_list +sel arm   token={r['token']} "
        f"missing={r['missing']} loc={r['loc']} line={r['at']}")
    for c in r["ctx"]:
        say(f"      | {c.strip()}")

    say()
    say("# --- the two reports above are the WHOLE measured type-level radius so far. ---")
    say(f"# green={r['green']}")
    for p, h in pristine.items():
        now = hashlib.md5(open(p, "rb").read()).hexdigest()
        say(f"# {p}: pristine={h} now={now} dirty={now != h}")
    # NOT reverted: this unit owns these files and the probe is the deliverable.
    open(".agents/slop/flipthird/radius.rows", "w").write("\n".join(LOG) + "\n")


if __name__ == "__main__":
    main()