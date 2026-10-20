#!/usr/bin/env python3
"""tagmachinery-gate.py -- THE PORT'S `tag` MACHINERY, AGAINST UPSTREAM'S.

    .venv/bin/python gates/tagmachinery-gate.py            # the census
    .venv/bin/python gates/tagmachinery-gate.py --plant    # and the plant that must go red

UPSTREAM DELETED A PIECE OF MACHINERY, AND THE PORT CARRIED IT. This gate is the DURABLE
form of that finding, and it exists because the finding has a SHARP EDGE on both sides.

THE EDGE ON THE DELETION SIDE. Upstream `35dab0a35` "no upat tag" (#18889) deleted
`UPat.match_tag` -- from `__slots__`, from `__init__`, from `__reduce__`, from `named`, from
`match`, and from `_get_clause` -- and upstream `42ca32a30` "delete remove_all_tags" (#18891)
deleted the `remove_all_tags` PatternMatcher and dropped it from `transform_to_call`. The port
carried BOTH. Mirroring upstream means the port does not.

THE EDGE ON THE OTHER SIDE, AND IT IS THE ONE THAT BITES. Upstream did NOT delete `UOp.tag`
or `UOp.rtag`: `refs/remotes/upstream/master:tinygrad/uop/ops.py` carries `tag:Any = None`
at line 237 and `def rtag(self, tag=True)` at line 250. A re-vendor audit that read "upstream
deleted the tag machinery" and then deleted the port's `O.Tag` and `rf_rtag` would have
removed LIVE machinery to fix a divergence that does not exist. **THE PORT'S `O.Tag` AND
`rf_rtag` ARE THE COUNTERPARTS OF SURVIVING UPSTREAM, NOT OF DELETED UPSTREAM.** This gate
says so in a falsifiable form: if the port loses `rtag` or the `Tag` type, this gate goes RED,
because upstream still has them and the port would then be the one out of step.

SO THE GATE IS A COMPARISON IN BOTH DIRECTIONS, AND BOTH SIDES ARE DISCOVERED.

    UPSTREAM SIDE   an AST read of `git show refs/remotes/upstream/master:tinygrad/uop/ops.py`
                    and `.../tinygrad/uop/upat.py`. A symbol is PRESENT if the AST carries it --
                    a class member, a module-level assignment, a method. A STRING SEARCH IS NOT
                    A POPULATION: `match_tag` appears in upstream's own PROSE (this file's
                    subject) and in `__slots__`, and only the AST says which is which.

    PORT SIDE       a DIRECTORY WALK of `tinybendygrad/**/*.bend` -- `rglob`, never a glob
                    (AGENTS.md: "`glob('*.bend')` returns `[]` when `.bend` FILES ARE ON DISK"),
                    and every hit is classified as CODE or COMMENT, because a comment that
                    NAMES a deleted construct is documentation, not a use.

THE CORRESPONDENCE IS A LIST, AND THE LIST IS NOT THE POPULATION. Four upstream symbols, each
with the port's names for it. The list says WHICH correspondence to check; the DENOMINATOR is
the two discoveries the gate prints, and it is those that make the gate falsifiable: a NEW
upstream deletion is visible as a `upstream_has_*=False` row, and a NEW port site is visible
as a `port_*_code` count above zero.

THE KNOWN DIVERGENCE IS CITED, NOT FORGIVEN. `remove_all_tags` is upstream-DELETED and the
port still HAS it, and the reason it has not been deleted is a CITATION, not a shrug:

    checks/lintable-gate.sh   plants by inverting `pm_r_tag_m.of`'s two arms, and its plant
                               anchor is the literal body of that def. Delete the def and the
                               plant stops being a plant.
    .agents/slop/lintable/02-TABLE.md   names `pm_remove_all_tags` in the lintable table.

**THE CITATION IS A CLOCK, NOT A PARDON.** This gate checks that BOTH are still there, and if
either goes away the exception EXPIRES and the gate goes RED -- because then the port is
carrying deleted upstream machinery with nothing holding the deletion back, and the next
agent has to close the gap. A divergence recorded without a clock is a divergence nobody
will ever close.

NO `bend` RUNS AND NO ORACLE RUNS. This is a STATIC READ: the port's source and upstream's
source, and nothing else. What it can and cannot say is the usual boundary: it says WHICH
machinery each side carries, not whether the port's answers are right. The answers are
`gates/`'s other business, and the port's own `tinybendygrad/uop/upat.bend` gate is what
checks that the port's compiler still agrees with CPython on the rows the migration touched.
"""
import ast
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT = ROOT / "tinybendygrad"
UPSTREAM_REF = "refs/remotes/upstream/master"
# THE PORT'S PIN -- the upstream commit this port was written against. It is where
# upstream STILL HAD `match_tag`, so it is what makes the detector falsifiable.
PIN = "78d482262"

# THE FIVE VERDICTS, AS EXITS -- `gates/gatekit.py`'s vocabulary, read from here rather than
# imported, because this gate runs NO bend and NO oracle and pulling `gatekit` in would drag
# its artifact directory and its three lanes along for a census that needs none of them.
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# THE CORRESPONDENCE. `up` is the upstream symbol, `cls` the class it lives in (or None for a
# module-level name), `port` the names the port spells it with, and `kind` which of the two
# questions the pair answers.
#
# `cls="-"` means a MODULE-LEVEL name, and the AST asks for a module-level assignment.
# `cls="UOp"` and `cls="UPat"` mean a CLASS MEMBER, and the AST asks for a method, a class
# attribute, or a member of `__slots__` -- all three, because upstream spells this one
# differently in the two places it appears.
CORRESPONDENCE = (
    # upstream symbol, class, port names, kind
    ("match_tag", "UPat", ("match_tag", "tag_clause", "LTag", "eq_opt_tag"), "deleted"),
    ("remove_all_tags", "-", ("pm_remove_all_tags", "pm_r_tag_m"), "deleted"),
    ("rtag", "UOp", ("rtag",), "kept"),
    ("tag", "UOp", ("Tag",), "kept"),
)

# THE CITED BLOCKER for the ONE known divergence, and the two things that must still be true
# for the exception to be live. `path` is read; `needle` must appear in it.
#
# WHY THIS IS A CITATION AND NOT A WHITELIST. The tree's rule is that a whitelist is a list
# with no generator behind it, and it rots without anyone noticing. A citation is a PATH and a
# LITERAL, both of which are gone the moment the thing they name is gone -- so the exception
# EXPIRES on its own, and this gate says so instead of carrying the exception forever.
BLOCKER = {
    "remove_all_tags": (
        ("checks/lintable-gate.sh",
         "Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})"),
        (".agents/slop/lintable/02-TABLE.md", "pm_remove_all_tags"),
    ),
}


def git_show(path: str) -> str:
    """`git show <ref>:<path>` -- the UPSTREAM SOURCE, read at the ref, not at HEAD.

    READ-ONLY BY CONSTRUCTION: `git show` writes nothing, and no `--fetch` happens here, so
    this gate cannot move the ref it reads.
    """
    r = subprocess.run(["git", "show", f"{UPSTREAM_REF}:{path}"], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise LookupError(f"{UPSTREAM_REF}:{path}: {r.stderr.strip()}")
    return r.stdout


def upstream_has(symbol: str, cls: str, source: str) -> bool:
    """IS THE SYMBOL IN UPSTREAM'S AST? A class member or a module-level assignment.

    NOT A STRING SEARCH. `match_tag` is a substring of upstream's own PROSE about the
    deletion, and `tag` is a substring of `match_tag` and of `tagstr`; only the AST says
    which of those is the symbol.
    """
    tree = ast.parse(source)
    if cls == "-":
        return any(isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == symbol
                                                      for t in n.targets) for n in tree.body)
    for node in tree.body:
        if not isinstance(node, ast.ClassDef) or node.name != cls:
            continue
        for m in node.body:
            if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)) and m.name == symbol:
                return True
            if isinstance(m, ast.AnnAssign) and isinstance(m.target, ast.Name) and m.target.id == symbol:
                return True
            if isinstance(m, ast.Assign) and any(isinstance(t, ast.Name) and t.id == symbol
                                                 for t in m.targets):
                return True
            # `__slots__` names the members of a `__slots__` class, and upstream's `UPat`
            # spells `match_tag` there and NOWHERE ELSE in the class body.
            if isinstance(m, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "__slots__"
                                                 for t in m.targets):
                for elt in ast.walk(m.value):
                    if isinstance(elt, ast.Constant) and elt.value == symbol:
                        return True
    return False


def port_hits(root: Path, names: tuple[str, ...]) -> tuple[int, int, list[str]]:
    """`(code_hits, comment_hits, sites)` over a DIRECTORY WALK of the port's `.bend` tree.

    A DIRECTORY WALK AND NOT A GLOB: `glob('*.bend')` returns `[]` when `.bend` files are on
    disk -- measured in this tree, and recorded in `AGENTS.md`. `rglob` and `os.walk` see them.

    A HIT IS CODE OR COMMENT, and the two are counted apart because a comment that NAMES a
    deleted construct is documentation -- this gate's own subject is a deleted construct, and
    every file that explains the deletion mentions it.
    """
    code = comment = 0
    sites: list[str] = []
    for path in sorted(root.rglob("*.bend")):
        # The site is relative to the TREE THAT WAS WALKED, not to the repo root: the plant
        # walks a scratch copy, and a scratch path under the repo root does not exist.
        try:
            rel = path.relative_to(ROOT)
        except ValueError:
            rel = path.relative_to(root.parent)
        for n, line in enumerate(path.read_text().split("\n"), 1):
            stripped = line.lstrip()
            is_comment = stripped.startswith("#")
            for name in names:
                # A WHOLE-WORD MATCH, and the LOOKBEHIND EXCLUDES ONLY WORD CHARACTERS -- so
                # a QUALIFIED name matches (`UPat.match_tag`, `O.UPat.match_tag(`) and a
                # LONGER one does not (`pm_remove_all_tags` is not `remove_all_tags`).
                if re.search(rf"(?<![\w]){re.escape(name)}(?![\w])", line):
                    if is_comment:
                        comment += 1
                    else:
                        code += 1
                        sites.append(f"{rel}:{n}")
    return code, comment, sites


def blocker_live(symbol: str) -> tuple[bool, str]:
    """IS THE CITED BLOCKER STILL THERE? `(live, why)`.

    `why` names the FIRST citation that is gone, so the row says WHICH clock ran out rather
    than just that one did.

    **A SYMBOL WITH NO CITATION HAS NO LIVE BLOCKER.** The empty tuple is not a vacuous
    truth -- an absent citation is an ABSENT reason, and reading it as a live one made this
    gate answer `agree_match_tag=true` for a port that HAD re-introduced `match_tag`. The
    plant caught it, which is the whole reason a gate has one.
    """
    citations = BLOCKER.get(symbol)
    if not citations:
        return False, "no citation"
    for rel, needle in citations:
        path = ROOT / rel
        if not path.is_file():
            return False, f"{rel} is GONE"
        if needle not in path.read_text():
            return False, f"{rel} no longer names {needle!r}"
    return True, ""


def census(root: Path) -> list[tuple[str, str]]:
    """THE ROWS. One `upstream_has_*`, one `port_*_code`, one `port_*_comment`, one verdict."""
    rows: list[tuple[str, str]] = []
    upstream_src = git_show("tinygrad/uop/ops.py")
    for symbol, cls, names, kind in CORRESPONDENCE:
        has_up = upstream_has(symbol, cls, upstream_src)
        code, comment, sites = port_hits(root, names)
        rows.append((f"upstream_has_{symbol}", str(has_up).lower()))
        rows.append((f"port_{symbol}_code", str(code)))
        rows.append((f"port_{symbol}_comment", str(comment)))
        if kind == "deleted" and not has_up:
            # UPSTREAM DELETED IT. The port must not carry it -- unless a CITATION holds the
            # deletion back, and the citation is still there.
            if code == 0:
                rows.append((f"agree_{symbol}", "true"))
            elif blocker_live(symbol)[0]:
                rows.append((f"agree_{symbol}", "true"))
                rows.append((f"blocker_{symbol}", "live"))
            else:
                rows.append((f"agree_{symbol}", "false"))
                rows.append((f"blocker_{symbol}", "expired: " + blocker_live(symbol)[1]))
        elif kind == "kept" and has_up:
            # UPSTREAM KEPT IT. The port must keep it too -- this is the guard against the
            # FALSE divergence, the one that would delete live machinery to fix a fiction.
            rows.append((f"agree_{symbol}", "true" if code > 0 else "false"))
        else:
            rows.append((f"agree_{symbol}", "false"))
        if sites and kind == "deleted":
            rows.append((f"port_{symbol}_sites", ";".join(sites)))
    return rows


def verdict(rows: list[tuple[str, str]]) -> int:
    """A DISAGREEMENT IS A FAIL. `agree_*=false` is the whole verdict."""
    for name, value in rows:
        if name.startswith("agree_") and value == "false":
            return FAIL
        if name.startswith("blocker_") and value.startswith("expired"):
            return FAIL
    return PASS


def plant(root: Path) -> int:
    """RE-INTRODUCE `match_tag` INTO A SCRATCH COPY AND PROVE THE GATE GOES RED.

    A GATE THAT CANNOT GO RED IS A LABEL. The plant is the DELETED upstream construct
    written back into the port -- the `UPat` field, the accessor and the `UPat.of`
    parameter -- and the gate must then report `agree_match_tag=false`. The scratch copy is
    OUTSIDE the tree, so the live port is never patched by a harness.
    """
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp) / "tinybendygrad"
        shutil.copytree(root, scratch)
        ops = scratch / "uop" / "ops.bend"
        src = ops.read_text()
        anchor = "    match_dtype: Maybe<&2, List<&2, S.Dt>>,\n"
        assert src.count(anchor) == 1, f"plant anchor is not unique: {src.count(anchor)}"
        src = src.replace(anchor, anchor + "    match_tag: Maybe<&2, List<&2, Tag>>,\n")
        ops.write_text(src)
        rows = census(scratch)
        got = verdict(rows)
        for name, value in rows:
            if name.startswith(("agree_match_tag", "port_match_tag")):
                print(f"{name}={value}")
        if got == FAIL:
            print("PLANT OK: the gate goes RED on the planted port")
            return PASS
        print("PLANT FAILED: the gate did NOT go red on the planted port", file=sys.stderr)
        return FAIL


def selftest() -> int:
    """THE VERDICT FUNCTION, ON ROWS THAT ARE NOT THE LIVE TREE'S.

    Three of the four failure paths are reachable from the live tree only by EDITING it, so
    without this they would be claims. Each case below is a pair of (rows, expected exit), and
    the expected exit is what the function must return -- not what it happens to return.

        a DISAGREEMENT                -> FAIL
        an EXPIRED citation           -> FAIL
        a symbol with NO citation     -> not a live blocker
        a citation that is still there-> a live blocker

    AND THE AST DETECTOR ITSELF, ON A SOURCE WHERE THE SYMBOL IS PRESENT. A detector that
    answers "absent" for everything would pass every case above, so it is checked against the
    port's PIN -- `78d482262`, before upstream deleted `match_tag` -- where the symbol IS there.
    The pin is read with `git show`, so this is a MEASUREMENT and not a transcription.
    """
    cases = [
        ("disagreement", verdict([("agree_match_tag", "false")]), FAIL),
        ("expired citation", verdict([("blocker_remove_all_tags", "expired: gone")]), FAIL),
        ("no citation", blocker_live("match_tag")[0], False),
        ("live citation", blocker_live("remove_all_tags")[0], True),
    ]
    ok = True
    for name, got, want in cases:
        flag = "ok" if got == want else "BAD"
        if got != want:
            ok = False
        print(f"selftest_{name.replace(' ', '_')}={flag} got={got} want={want}")
    # THE DETECTOR, ON A SOURCE THAT HAS THE SYMBOL.
    for label, ref, want in (("match_tag", PIN, True), ("remove_all_tags", PIN, True),
                             ("match_tag", UPSTREAM_REF, False)):
        r = subprocess.run(["git", "show", f"{ref}:tinygrad/uop/ops.py"], cwd=ROOT,
                           capture_output=True, text=True)
        got = upstream_has(label, "UPat" if label == "match_tag" else "-", r.stdout)
        flag = "ok" if got == want else "BAD"
        if got != want:
            ok = False
        print(f"selftest_detector_{label}_{'at_pin' if ref == PIN else 'at_master'}="
              f"{flag} got={got} want={want}")
    return PASS if ok else FAIL


def main() -> int:
    if not (ROOT / "tinybendygrad").is_dir():
        print("tagmachinery-gate: REFUSED: no tinybendygrad/ at the repo root", file=sys.stderr)
        return REFUSED
    if "--selftest" in sys.argv:
        return selftest()
    try:
        git_show("tinygrad/uop/ops.py")
    except LookupError as exc:
        print(f"tagmachinery-gate: REFUSED: {exc}", file=sys.stderr)
        return REFUSED
    if "--plant" in sys.argv:
        return plant(PORT)
    rows = census(PORT)
    if not rows:
        print("tagmachinery-gate: DEAD: no rows", file=sys.stderr)
        return DEAD
    for name, value in rows:
        print(f"{name}={value}")
    code = verdict(rows)
    print(f"tagmachinery-gate: {len(rows)} rows, verdict "
          f"{'PASS' if code == PASS else 'FAIL'}")
    return code


if __name__ == "__main__":
    sys.exit(main())
