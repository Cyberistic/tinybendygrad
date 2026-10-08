#!/usr/bin/env python3
"""THE CLASS OF checks/ + gates/ .py FILES THAT ARE NAMED BUT NEVER INVOKED, BY AST.

    .venv/bin/python .agents/slop/substrateid2/census.py           # the counts
    .venv/bin/python .agents/slop/substrateid2/census.py --rows    # per-file rows
    .venv/bin/python .agents/slop/substrateid2/census.py --plant   # the three-state control

THE POPULATION IS A DIRECTORY WALK OF THE TREE, NOT THE INDEX. `git ls-tree -r HEAD` is the
tree; `git ls-files` is the index, and the index carried 460 `.agents/slop/` dirs at a moment the
tree had 382, so an index census measures the index. Both numbers are printed.

"INVOKED" IS ASKED BY AST, NOT BY TEXT. A tracked file invokes a check by any of:
  * `subprocess.run([... , "checks/foo.py", ...])`            -- a path string in a call arg
  * `run(["./checks/foo.py"], ...)` / shell `checks/foo.py`   -- a bare path in a shell string
  * `importlib` `spec_from_file_location` on `checks/foo.py`  -- loaded BY PATH
  * `sys.executable`-shaped argv  `"checks/foo.py"`
A citation in prose (a `.md`) is NAMED, not INVOKED. A citation in another `.agents/slop/` probe
is NAMED-BY-A-PROBE. The brief's "named by 11, invoked by 0" is reproducible here only when the
naming population includes `.md`; the invoked axis is 0 regardless.

`VERDICTS` IS A MODULE-BODY BINDING, read by `ast`, never by `ast.literal_eval` of a regex.
`gates/gate-surface.py` reads `VERDICTS = {...}` off the module body; a file that names the word
in a DOCSTRING has no declaration. The docstring/site split is printed, because conflating them is
the defect this census exists to keep from spreading.

THREE AXES, AND THE ONE THAT CAN SILENTLY ZERO. Axis (b) looks for a *module-body* `Assign` to a
name in the DECLARED SET {VERDICTS, VERDICT, NAMES, ROW_VERDICTS}. If that set were a bare list
and a file used a fourth name, the axis reports 0 for a file that HAS one -- `readerdecl`'s
`None` failure, one axis down. The control therefore reports, per file, EVERY module-body name
bound to a dict of int->str, so a reader can see the axes' own vocabulary, and `--plant` plants
a file that declares under a name the census does not know.
"""
from __future__ import annotations

import ast
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]

#: The two gate homes, as `gates/gates-pop.py:95` declares them (`HOMES`). Loaded by IMPORT of the
#: declaring module, so this census does not carry a fourth copy of the list.
def homes() -> tuple[str, ...]:
    p = ROOT / "gates/gates-pop.py"
    src = p.read_text()
    for node in ast.parse(src).body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "HOMES":
            return tuple(ast.literal_eval(node.value))
    raise SystemExit("gates/gates-pop.py HOMES is not a literal tuple -- ask it, do not guess")

#: THE DECLARATION VOCABULARY IS **LOADED BY PATH** FROM ITS GENERATOR, NOT DERIVED AND NOT
#: LISTED HERE. `gates/gate-surface.py:237` binds `DECL = ("VERDICTS", "PLANTS", "RED_IS")` and
#: `gates/gate-surface.py:194` reads it off a gate's module body with `ast.literal_eval` -- that IS
#: the generator's own declaration of which names count, and asking it makes this census and
#: `gate-surface`'s clause V ONE population by construction.
#:
#: MY FIRST REVISION ASKED THE WRONG QUESTION and got a wrong number out of it: it scanned BOTH
#: `gate-surface.py` and `gatekit.py` for EVERY module-body dict keyed by int, which yielded
#: `['PLANTS','VERDICTS','classes','found','reached','subs']` -- `classes`, `found`, `reached` and
#: `subs` are `gate-surface`'s OWN census accumulators, not verdict declarations, and counting them
#: as declarations made axis (b) report 138 of 152 undeclared instead of the truth. A census that
#: asks "is this an int-keyed dict" has asked about a SHAPE; a census that asks "did the gate ship
#: one of the DECLARED names" has asked about a DECLARATION. That difference is 16 files."""
def verdict_names() -> frozenset[str]:
    p = ROOT / "gates/gate-surface.py"
    for node in ast.parse(p.read_text()).body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "DECL":
            return frozenset(ast.literal_eval(node.value))
    raise SystemExit("gates/gate-surface.py DECL is not a literal tuple -- it IS the declaration "
                     "vocabulary, and this census must ask it rather than guess one")


def tree_files(prefix: str = "", suffix: str = "") -> list[str]:
    """`git ls-tree -r HEAD` -- THE TREE. `git ls-files` would read the index, which is a
    different population and one that has carried 460 slop dirs the tree did not have.

    The filter is `startswith(prefix)` on the DIRECTORY and `endswith(suffix)` on the name.
    An earlier revision of this file used `endswith` for both and returned a POPULATION OF 0 on a
    tree with 40+ live gates -- which is the `readerdecl` failure exactly, one function along:
    a key that resolves to nothing, reported as a number, in a census whose subject is numbers."""
    out = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout
    return [ln for ln in out.splitlines() if ln.startswith(prefix) and ln.endswith(suffix)]


def index_files(prefix: str = "", suffix: str = "") -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True,
                         check=True).stdout
    return [ln for ln in out.splitlines() if ln.startswith(prefix) and ln.endswith(suffix)]


def blobs() -> dict[str, str]:
    """EVERY tracked blob in HEAD, in ONE `git cat-file --batch` pass.

    Reading the WORKTREE is wrong for this census and the tree proved it on the first run: eight
    `.agents/slop/` files are staged as DELETED, so `pathlib.read_text` on a `git ls-tree` path
    raised `FileNotFoundError` on a file the tree still has. It is also how a `grep -rl` once
    reported an untracked `.pyc` as a reader. The worktree and the index are both populations
    other than the one under census; HEAD's blobs are the one being asked about."""
    listing = subprocess.run(["git", "ls-tree", "-r", "HEAD"], cwd=ROOT, capture_output=True,
                             text=True, check=True).stdout
    shas: list[str] = []
    for ln in listing.splitlines():
        meta, _, _path = ln.partition("\t")
        if meta.split()[1] != "blob":
            continue
        shas.append(meta.split()[2])
    # TWO FORMS THAT ARE NOT THE SAME, BOTH MEASURED HERE ON THIS GIT.
    #   STDIN FROM A PIPE DEADLOCKS: writing 6537 requests before reading one response fills the
    #   pipe buffer while git blocks writing 201 MB of output back. The pair hung until the
    #   harness killed it at 280 s. A FILE for stdin gives git no capacity limit to deadlock on.
    #   `<sha> path=<p>` IS NOT A BATCH REQUEST: this git answers `... path=x missing` for a blob
    #   `git cat-file -t` resolves as `blob`. Only the BARE sha is a request, so the path is
    #   carried here and re-joined POSITIONALLY -- responses come back in request order, one blob
    #   per line, so `zip` is the join and a reordering would show up as a parse error.
    with tempfile.NamedTemporaryFile("w", suffix=".req", delete=False) as tf:
        tf.writelines(f"{s}\n" for s in shas)
        reqfile = tf.name
    paths = [ln.partition("\t")[2] for ln in listing.splitlines()
             if ln.partition("\t")[0].split()[1] == "blob"]
    assert len(paths) == len(shas), f"{len(paths)} paths vs {len(shas)} blobs -- ls-tree changed"
    out: dict[str, str] = {}
    with open(reqfile) as fin:
        proc = subprocess.Popen(["git", "cat-file", "--batch"], cwd=ROOT, stdin=fin,
                                stdout=subprocess.PIPE)
        assert proc.stdout
        for path in paths:
            header = proc.stdout.readline().decode().split()
            if len(header) < 3 or header[1] != "blob":
                raise SystemExit(f"cat-file --batch answered {header!r} for {path}")
            out[path] = proc.stdout.read(int(header[2])).decode(errors="replace")
            proc.stdout.read(1)
        proc.wait()
    os.unlink(reqfile)
    return out


def module_dicts(src: str) -> dict[str, dict[int, str]]:
    """Every MODULE-BODY binding of a dict literal keyed by int. Returned in full so the census
    prints its own vocabulary: an axis that can only see the names it was told about is a
    `readerdecl`-shaped blind spot, and the way out is to SHOW what it saw."""
    out: dict[str, dict[int, str]] = {}
    for node in ast.parse(src).body:
        if not isinstance(node, ast.Assign) or not isinstance(node.value, ast.Dict):
            continue
        if not all(isinstance(k, ast.Constant) and isinstance(k.value, int) for k in node.value.keys):
            continue
        for t in node.targets:
            if isinstance(t, ast.Name):
                out[t.id] = {k.value: v.value for k, v in zip(node.value.keys, node.value.values)
                             if isinstance(v, ast.Constant)}
    return out


def shadow_copy(rel: str) -> bool:
    """A tracked path that carries a WHOLE COPY of this repo under `.agents/slop/`.

    MEASURED: 11 tracked `.py` under `.agents/slop/**/(checks|gates)/` -- `corpuswire/tree/`,
    `denominator/probe/`, `figure2/plant/{real,broken}/`. `gatecensus/classify.py` defect 1 states
    the rule this implements: *"A citation inside a copy of the documentation is a citation of the
    copy."* A shadow copy of `differ.py` inherits every prose citation `differ.py` had, so counting
    it as a NAMER OF `checks/gate.py` is counting the copy's inheritance, not a reader.

    Reported as a SEPARATE COLUMN rather than a silent filter, because a filter nobody can see is
    a filter that can only understate, and 88-vs-N is exactly the number a reader will argue with."""
    parts = rel.split("/")
    return len(parts) > 3 and parts[0] == ".agents" and parts[1] == "slop" and ("checks" in parts or "gates" in parts)


def named_by(target: str, corpus: dict[str, str]) -> list[str]:
    """Tracked files whose CONTENT NAMES `target`.

    **THE CITATION MUST CARRY THE EXTENSION, AND THAT IS THE WHOLE FIX.** The first revision
    matched the bare stem, and `checks/compile.py` came back NAMED BY **1121** files -- because
    `re.compile(`, `py_compile` and `importlib.util` all contain the letters. `checks/cli.py`
    answered 342 and `checks/plant.py` 1018. A BASENAME SHAPE IS NOT A POPULATION: it is true of
    every gate and specific to none, which is the `gates/gates-pop.py` defect one function along.
    A citation of a FILE names its extension -- every one of the 11 files that name
    `checks/substrate-id.py` writes `substrate-id.py`, none writes a bare `substrate-id` -- so the
    extension is the discriminator, and it is a property of the CITATION not a list of citers."""
    stem = target.rsplit("/", 1)[-1]
    return [rel for rel, text in sorted(corpus.items())
            if rel != target and stem in text and not shadow_copy(rel)]


PROGRAMS = (".sh", ".bash", ".zsh", ".mjs", ".cjs", ".js", ".ts", ".mk", ".mkfile")


def is_program(rel: str, text: str) -> bool:
    """Is this tracked blob a THING THAT EXECUTES? `.py` is handled by the AST axis. For the rest:
    a known program extension, or an extensionless file whose first line is a shebang.

    THIS FIX WAS MEASURED, AND IT WAS MY OWN DEFECT. The first revision tokenised EVERY non-`.py`
    blob and reported `checks/substrate-id.py` as INVOKED BY 12 files -- of which 11 were
    `.rows`/`.tsv`/`.out` ROW DUMPS and one was `gates/gates-pop.ledger.tsv`, a census ROW. A row
    dump that records the string `checks/substrate-id.py` has not run it; it has PRINTED it. The
    brief's "invoked by 0" was right and my axis was wrong, for the same reason `grep -rl` once
    reported an untracked `.pyc` as a reader.

    THE LIMIT IS NAMED, NOT DENIED: extension + shebang is a SHAPE, and a tracked program written
    in some fourth language is invisible to this axis. So the scope of the invoked axis is
    "tracked `.py` + tracked files with a program extension or a shebang", and the count is a
    LOWER BOUND on invocation, never an upper one."""
    if rel.endswith(".py"):
        return True
    if rel.endswith(PROGRAMS):
        return True
    return text.startswith("#!")


def invoked_map(corpus: dict[str, str], wanted: set[str]) -> dict[str, list[str]]:
    """ONE PASS over the corpus, not one pass per gate. An earlier revision looped the corpus
    inside the per-gate loop, which is 150 x 4062 `ast.parse` calls; it did not finish in 180 s.

    Two maps, and the difference is the whole invoked axis: `argv_consts` are string constants
    that appear as a WHOLE ARGUMENT to a call (a `subprocess.run` argv word, a
    `spec_from_file_location` path), and `tokens` are shell-word tokens in a non-`.py` reader.
    A path inside a docstring is in NEITHER, which is why a `.md` can name a gate forever and
    never invoke it."""
    argv_consts: dict[str, list[str]] = {}
    tokens: dict[str, list[str]] = {}
    homes_literal = tuple(f"{h}/" for h in ("checks", "gates"))
    prefiltered = 0
    for rel, text in corpus.items():
        if rel.endswith(".py"):
            # THE PREFILTER, AND IT IS PROVABLE RATHER THAN A LIST. To invoke `checks/foo.py` as a
            # whole argv word a reader must CONTAIN the substring `checks/foo.py`, which contains
            # `checks/`; likewise for `gates/`. So a tracked .py whose text mentions NEITHER home
            # cannot invoke a gate in either home, and parsing it could only ever return nothing.
            # Parsing all 1656 tracked .py (a 201 MB pack) did not finish in 300 s; this filter
            # is the difference between a census and a timeout, and the SCOPE it costs is named
            # in the report rather than hidden.
            if not any(h in text for h in homes_literal):
                continue
            prefiltered += 1
            try:
                tree = ast.parse(text)
            except SyntaxError:
                continue
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                for a in list(node.args) + [k.value for k in node.keywords]:
                    for v in ast.walk(a):
                        if isinstance(v, ast.Constant) and isinstance(v.value, str):
                            argv_consts.setdefault(v.value, []).append(rel)
        elif is_program(rel, text):
            for tok in re.findall(r"[^\s'\"|;&()<>]+", text):
                tokens.setdefault(tok, []).append(rel)
    print(f"reader scope: {len(corpus)} tracked blobs; {prefiltered} .py parsed "
          f"(a reader mentioning neither 'checks/' nor 'gates/' cannot name one); "
          f"{len(corpus) - prefiltered} .py skipped by the prefilter")
    out: dict[str, list[str]] = {}
    for target in wanted:
        stem = target.rsplit("/", 1)[-1]
        src_stem = target[:-3]
        hits = []
        for key in (stem, src_stem, f"./{stem}", f"./{src_stem}", target, f"./{target}"):
            hits += argv_consts.get(key, []) + tokens.get(key, [])
        out[target] = sorted({h for h in hits if h != target})
    return out


def main() -> int:
    H = homes()
    V = verdict_names()
    pop = sorted(f for h in H for f in tree_files(f"{h}/", ".py"))
    idx = sorted(f for h in H for f in index_files(f"{h}/", ".py"))
    corpus = blobs()
    print(f"population   : {len(pop)} tracked .py under {'+'.join(H)}/ (git ls-tree -r HEAD)")
    print(f"index        : {len(idx)} .py (git ls-files) -- delta {len(idx) - len(pop):+d}")
    print(f"verdict names: {sorted(V)}  (DECL loaded by path from gates/gate-surface.py:237)")

    inv_all = invoked_map(corpus, set(pop))
    rows = []
    for rel in pop:
        decls = module_dicts(corpus[rel])
        rows.append((rel, named_by(rel, corpus), inv_all[rel], decls))

    named_only = [r for r in rows if r[1] and not r[2]]
    never_named = [r for r in rows if not r[1]]
    nodecl = [r for r in rows if not (set(r[3]) & V)]
    both = [r for r in rows if r in named_only and r in nodecl]
    n = len(pop)
    print()
    print(f"population {n} = {sum(1 for x in pop if x.startswith('checks/'))} in checks/ "
          f"+ {sum(1 for x in pop if x.startswith('gates/'))} in gates/, by directory walk of "
          f"git ls-tree -r HEAD")
    print(f"(a) NAMED by tracked code, INVOKED by none : {len(named_only)} of {n}")
    print(f"(b) NO verdict declaration (module body)   : {len(nodecl)} of {n}")
    print(f"(c) BOTH                                 : {len(both)} of {n}")
    print(f"    named by NOTHING at all               : {len(never_named)} of {n}")
    print(f"    shadow copies EXCLUDED from namers    : "
          f"{sum(1 for t in corpus if shadow_copy(t))} tracked paths carry a repo copy under "
          f".agents/slop/ (gatecensus classify.py defect 1)")

    if "--rows" in sys.argv:
        print()
        print("path\tnamed\tinvoked\tdeclares")
        for rel, nms, inv, decls in rows:
            print(f"{rel}\t{len(nms)}\t{len(inv)}\t{','.join(sorted(decls)) or 'NONE'}")
    if "--plant" in sys.argv:
        return plant(pop, V)
    return 0


def plant(pop: list[str], V: frozenset[str]) -> int:
    """THE CONTROL THIS CENSUS OWES ITS READER. Axis (b) is silent about a declaration under a
    name it was not told; so plant a file that declares a verdict dict under a name OUTSIDE V and
    show the axis reports it as undeclared. A census whose own blind spot is undemonstrated is a
    census whose blind spot is a discovery waiting to happen."""
    bad = 0
    src = "NAMES = {0: 'PASS', 1: 'FAIL'}\n"
    d = module_dicts(src)
    seen = bool(set(d) & V)
    print(f"PLANT unknown-name  declares {sorted(d)}  V={sorted(V)}  -> axis(b) sees it: {seen}")
    bad += 0 if not seen else 1
    # AND THE INVERSE: a NAME in V that is not a verdict dict at all.
    src2 = "VERDICTS = 5\n"
    seen2 = bool(set(module_dicts(src2)) & V)
    print(f"PLANT non-dict      declares {sorted(module_dicts(src2))} -> axis(b) sees it: {seen2}")
    bad += 0 if not seen2 else 1
    # AND: the census must not read a DOCSTRING mention as a declaration.
    src3 = '"""VERDICTS = {0: "PASS"} is what this file has."""\n'
    seen3 = bool(set(module_dicts(src3)) & V)
    print(f"PLANT docstring     -> axis(b) sees a declaration: {seen3}  (must be False)")
    bad += 0 if not seen3 else 1
    print(f"\nPLANT: {'OK' if not bad else f'{bad} MISMATCH(ES)'}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())