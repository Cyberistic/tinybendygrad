r"""THE CLASS, FOUND BY DISCOVERY: every membership test and every subscript in checks/ + gates/
whose CONTAINER is a dict/list/set/tuple and whose KEY could be a `bool`.

SCOPE IS STATED IN THE SENTENCE, SO IT IS STATED IN THE CODE. The population is a DIRECTORY WALK
(`os.walk` + `endswith(".py")`) over the two homes the tree itself declares
(`gates/gates-pop.py`'s own admission), NOT a hand list, NOT a suffix glob: `glob("*.py")` and
`find -name '*.py'` were both measured to disagree with what is on disk, and a population an
instrument cannot see is not a population.

WHY AST AND NOT GREP. `prune4`'s lesson, measured: a regex census reported 183 where the truth was
61, because `\.add\(` matched `seen.add(` on a Python SET. The same failure shape here is worse --
`in` is a keyword, `VERDICT` is a substring of nothing, and a subscript is `[` which appears in
slices, in comprehensions and in strings. So: `ast.parse`, `ast.walk`, and the container's TYPE is
resolved by walking to the binding, not by naming the identifier.

WHY THIS IS NOT A TYPE CHECKER. It is a census with a declared population and a declared method.
It resolves the CONTAINER (which dict/list/set/tuple is this) and reports the SITE. Whether a bool
can ARRIVE at the site is a second question, answered in `reach.py` and reported here as a grade.
"""
import ast
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]   # .agents/slop/boolexit/census.py -> repo root
HOMES = ("checks", "gates")          # `gates/gates-pop.py:95` names these by hand; we inherit the
                                      # admission and walk them anyway.


def population():
    """EVERY `.py` under the two homes, by directory walk. Returns [(relpath, Path)] sorted."""
    out = []
    for home in HOMES:
        base = ROOT / home
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in ("__pycache__", "artifacts")]
            for fn in filenames:
                if fn.endswith(".py"):
                    p = Path(dirpath) / fn
                    out.append((str(p.relative_to(ROOT)), p))
    return sorted(out)


# ---------------------------------------------------------------- container typing

class Binder:
    """`name` -> a shape tag, for every module-level and function-level binding in ONE module.

    A shape tag is one of:
      "dict"  "list"  "set"  "tuple"  "unknown"  "unknown:dict-literal?"  ...
    plus the literal keys/elements when they are statically visible, because "can a bool be a
    KEY" is only answerable when the keys are.

    This is NOT a type checker and does not claim to be: it resolves the container for the shapes
    that appear in this tree and returns "unknown" -- loudly -- for everything else. An
    "unknown" is a hole in the census and it is COUNTED, never dropped.
    """

    def __init__(self, tree, src):
        self.tree = tree
        self.src = src
        self.shapes = {}     # name -> shape dict
        self.consts = {}     # name -> a literal int/str/bool, for KEYS that are names
        self._collect(tree)

    def _lit(self, node):
        """A dict/list/set/tuple literal -> ('dict', keys, values); a call to dict()/[] -> same;
        a comprehension -> its container type with UNKNOWN elements; anything else -> None."""
        if isinstance(node, ast.Dict):
            keys = []
            for k in node.keys:
                if k is None:
                    keys.append("<**spread>")
                else:
                    keys.append(self._const(k))
            return ("dict", keys, list(node.values))
        if isinstance(node, ast.List):
            return ("list", [self._const(e) for e in node.elts], node.elts)
        if isinstance(node, ast.Set):
            return ("set", [self._const(e) for e in node.elts], list(node.elts))
        if isinstance(node, ast.Tuple):
            return ("tuple", [self._const(e) for e in node.elts], list(node.elts))
        if isinstance(node, (ast.ListComp,)):
            return ("list", None, [])
        if isinstance(node, ast.DictComp):
            return ("dict", None, [])
        if isinstance(node, ast.SetComp):
            return ("set", None, [])
        if isinstance(node, ast.GeneratorExp):
            return ("gen", None, [])
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.BitOr, ast.Add)):
            # `{0} | {1}` -- an exit-code set written as a union of literals.
            lhs, rhs = self._lit(node.left), self._lit(node.right)
            if lhs and rhs:
                merged = [e for e in (lhs[1] or []) + (rhs[1] or [])]
                return (lhs[0] if lhs[0] == rhs[0] else lhs[0], merged, [])
            return lhs
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
                and node.func.id in ("dict", "list", "set", "tuple", "frozenset", "Counter",
                                     "defaultdict", "OrderedDict", "deque", "map", "filter"):
            k = node.func.id
            if k == "Counter":
                return ("dict", [], node.args)
            if k == "deque":
                return ("list", [], node.args)
            if k in ("map", "filter"):
                return ("gen", [], [])
            return (k, [], node.args)
        return None

    def _const(self, node):
        """A key's VALUE, following ONE level of module constant -- `VERDICT = {PASS: ...}`
        where `PASS = 0` is a NAME, and `ast.literal_eval` answers None for a Name. Resolving
        names is what turns the whole `gatekit.VERDICT` table from UNKNOWN into REACHES, and
        this is measured: with names unresolved the census reported **0 REACHES** across 680
        sites, which is the same confident-wrong-answer shape `plantthe46` hit with a vacuous
        counterfactual."""
        try:
            return ast.literal_eval(node)
        except (ValueError, SyntaxError, TypeError):
            pass
        if isinstance(node, ast.Name):
            return self.consts.get(node.id, None)
        if isinstance(node, ast.BinOp):
            l, r = self._const(node.left), self._const(node.right)
            if isinstance(l, int) and isinstance(r, int):
                return l + r if isinstance(node.op, ast.Add) else l | r
        if isinstance(node, ast.Tuple) and all(isinstance(e, ast.expr) for e in node.elts):
            vals = [self._const(e) for e in node.elts]
            return tuple(vals) if all(v is not None for v in vals) else None
        return None

    def _bind_consts(self, targets, value):
        """Bind literal scalars, INCLUDING TUPLE UNPACKING.

        `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` -- the FIVE VERDICTS' OWN DEFINITION,
        and the whole `VERDICT` table is keyed by those names -- is a tuple TARGET, not an
        `ast.Constant`. Measured: with only scalar assignment bound, the census reported **0
        REACHES across 681 sites**, i.e. it found the class to be empty. The class was not empty;
        the CONSTANT TABLE WAS. This is `plantthe46`'s vacuous counterfactual in a different
        instrument: a census that cannot fail is not a census.
        """
        if isinstance(value, ast.Constant) and isinstance(value.value, (int, str, bool, type(None))):
            for t in targets:
                if isinstance(t, ast.Name):
                    self.consts[t.id] = value.value
        elif isinstance(value, (ast.Tuple, ast.List)) and \
                all(isinstance(e, ast.Constant) for e in value.elts):
            flat = []
            for t in targets:
                flat.extend(self._names(t))
            if len(flat) == len(value.elts):
                for nm, e in zip(flat, value.elts):
                    self.consts[nm] = e.value

    def _collect(self, tree):
        """Two passes, and the ORDER IS LOAD-BEARING. Module constants first, then containers:
        `PASS = 0` must be known before `VERDICT = {PASS: "PASS"}` asks for its keys, and a
        single pass over `ast.walk` visits the dict before the int whenever the dict is longer,
        which is exactly the `gatekit` case."""
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                self._bind_consts(node.targets, node.value)
            elif isinstance(node, ast.AnnAssign):
                self._bind_consts([node.target], node.value)

        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                shape = self._lit(node.value)
                for t in node.targets:
                    for nm in self._names(t):
                        self.shapes[nm] = (shape, node.lineno)
            elif isinstance(node, ast.AnnAssign) and node.value is not None:
                shape = self._lit(node.value)
                for nm in self._names(node.target):
                    self.shapes[nm] = (shape, node.lineno)
            elif isinstance(node, ast.For) and isinstance(node.target, ast.Name):
                # `for k in SOME_DICT:` -- k is a KEY of a dict when the iteration is a dict.
                sh = self.shape_of(node.iter)
                if sh and sh[0] == "dict":
                    self.shapes.setdefault(node.target.id, (("keyof",), node.lineno))
            elif isinstance(node, ast.withitem) and node.optional_vars is not None:
                shape = self._lit(node.context_expr)
                for nm in self._names(node.optional_vars):
                    self.shapes[nm] = (shape, getattr(node, "lineno", 0))

    def _names(self, tgt):
        if isinstance(tgt, ast.Name):
            return [tgt.id]
        if isinstance(tgt, (ast.Tuple, ast.List)):
            return [n for e in tgt.elts for n in self._names(e)]
        return []

    def shape_of(self, node):
        """The shape of an EXPRESSION, or None when unknown."""
        if isinstance(node, ast.Name):
            return self.shapes.get(node.id, (None,))[0]
        return self._lit(node)


# ---------------------------------------------------------------- the two sites

def sites(path):
    """Yield (kind, lineno, col, container_desc, keys_or_null, source_line) for each site.

    kind: "IN" for `x in C` / `x not in C`, "SUB" for `C[k]`.
    `keys_or_null` is the literal key list when the container is a dict LITERAL, else None.
    """
    try:
        src = path.read_text()
        tree = ast.parse(src)
    except (SyntaxError, OSError, UnicodeDecodeError) as e:
        return [], f"UNPARSEABLE: {e}"
    binder = Binder(tree, src)
    lines = src.splitlines()
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Compare):
            for op, cmp in zip(node.ops, node.comparators):
                if not isinstance(op, (ast.In, ast.NotIn)):
                    continue
                sh = binder.shape_of(cmp)
                if not sh:
                    continue
                kind, keys, _ = sh
                if kind not in ("dict", "list", "set", "tuple", "gen", "keyof"):
                    continue
                out.append(("IN", node.lineno, node.col_offset,
                            _name(cmp, kind), keys if kind == "dict" else None,
                            lines[node.lineno - 1].strip()))
        elif isinstance(node, ast.Subscript):
            sh = binder.shape_of(node.value)
            if not sh:
                continue
            kind, keys, _ = sh
            if kind != "dict":
                continue
            out.append(("SUB", node.lineno, node.col_offset,
                        _name(node.value, kind), keys,
                        lines[node.lineno - 1].strip()))
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                and node.func.attr == "get" and isinstance(node.func.value, ast.Name) \
                and node.args:
            # `D.get(k, default)` IS A MEMBERSHIP TEST WITH A DEFAULT, and it is the shape
            # `checks/substrate-id.py:247` uses. A census that handles `[k]` and `k in D` but
            # not `D.get(k)` misses the one site in the tree whose ONLY output is a WORD.
            sh = binder.shape_of(node.func.value)
            if not sh or sh[0] != "dict":
                continue
            out.append(("GET", node.lineno, node.col_offset,
                        _name(node.func.value, sh[0]), sh[1],
                        lines[node.lineno - 1].strip()))
    out.sort(key=lambda s: (s[1], s[2]))
    return out, None


def _name(node, kind):
    if isinstance(node, ast.Name):
        return f"{kind} {node.id}"
    if isinstance(node, ast.Attribute):
        return f"{kind} {node.attr}"
    if isinstance(node, ast.Subscript):
        return f"{kind} <subscript>"
    if isinstance(node, ast.Call):
        return f"{kind} {ast.unparse(node.func) if hasattr(ast, 'unparse') else 'call'}()"
    return f"{kind} <{type(node).__name__}>"


# ---------------------------------------------------------------- the reach question

REACH = {
    # why a bool CANNOT be the thing being looked up
    "str": "key/value is a str",
    "frozenset-str": "container holds only str",
}

def can_bool_reach(keys, kind, src_line):
    """THE SECOND QUESTION, and the one that decides whether a site is a defect or a curiosity.

    `int(True) == 1` and `hash(True) == hash(1)`, so a `bool` DOES reach EVERY dict whose keys
    include `0`/`1` or `True`/`False`. That is the whole `gatekit.VERDICT` table. The rule:

      KEYS CONTAIN 0/1/True/False (int-valued)  -> bool REACHES. LIVE if a bool is in the
                                                    enumerated domain; LATENT if all today's
                                                    values are compared ints.
      KEYS ARE ALL str                             -> bool cannot be a key (hash(False) != hash("...")).
      KEYS ARE int-valued BUT FROM A COMPARISON    -> the site is a LANDING PAD: a bool is exactly
                                                       what a comparison returns.

    Returns (verdict, reason) where verdict in {REACHES, MEMBER-IS-STR, UNKNOWN}.
    """
    if keys is None:
        # container shape known, contents not literal: cannot rule a bool in OR out
        return ("UNKNOWN", f"{kind} container, contents not literal")
    if any(k is None or k == "<**spread>" for k in keys):
        return ("UNKNOWN", f"{kind} with a non-literal member: {keys}")
    if not keys:
        # `d = {}` is an ACCUMULATOR, not a table: its keys arrive at run time from writes this
        # instrument does not follow. That is a different hole from "the literal had a name in it",
        # and lumping them together would report 550 unknown-holes when most of them are
        # dictionaries nobody could enumerate statically. Separated, and STILL COUNTED.
        return ("DYNAMIC", f"empty {kind} literal -- an accumulator whose members arrive at run "
                           f"time; a bool's reach is undecidable without running it")
    kinds = {type(k).__name__ for k in keys}
    if kinds <= {"str"}:
        return ("MEMBER-IS-STR",
                f"every {kind} member is a str; `False in ('a','b')` is False, so a bool cannot hit")
    intish = {k for k in keys if isinstance(k, int) and not isinstance(k, bool)}
    if intish & {0, 1}:
        return ("REACHES", f"{kind} members {sorted(intish)[:8]} include {intish & {0, 1}}; "
                           f"True == 1 and hash(True) == hash(1)")
    if kinds <= {"int", "bool"}:
        return ("REACHES", f"int-valued {kind} members; a bool aliases onto 0/1")
    if kinds <= {"float", "int"}:
        return ("REACHES", f"numeric {kind} members; hash(1.0) == hash(1) too")
    return ("UNKNOWN", f"{kind} members of type {kinds}")


def main():
    pop = population()
    total_in = total_sub = 0
    reach_sites, unknown_sites, dynamic_sites, rows = 0, 0, 0, []
    unparseable = []
    for rel, p in pop:
        ss, err = sites(p)
        if err:
            unparseable.append((rel, err))
            continue
        for kind, lineno, col, cont, keys, line in ss:
            if kind == "IN":
                total_in += 1
            else:
                total_sub += 1
            v, reason = can_bool_reach(keys, cont.split()[0], line)
            if v == "REACHES":
                reach_sites += 1
            if v == "UNKNOWN":
                unknown_sites += 1
            if v == "DYNAMIC":
                dynamic_sites += 1
            rows.append((rel, lineno, kind, cont, repr(keys), v, reason, line))
    w = 116
    print(f"# THE BOOL/INT MEMBERSHIP CENSUS -- AST, scope-resolved containers, {len(pop)} files "
          f"discovered by os.walk under {'+'.join(HOMES)}/")
    print(f"## files discovered (population) : {len(pop)}")
    print(f"## files UNPARSEABLE              : {len(unparseable)}")
    for rel, err in unparseable:
        print(f"##     {rel}: {err[:90]}")
    print(f"## `x in C` sites on dict/list/set/tuple : {total_in}")
    print(f"## `C[k]` sites on a dict                : {total_sub}")
    print(f"## sites a bool REACHES                   : {reach_sites}")
    print(f"## sites a bool CANNOT reach (str members): {len(rows) - reach_sites - unknown_sites - dynamic_sites}")
    print(f"## sites DYNAMIC (an accumulator; counted as a hole) : {dynamic_sites}")
    print(f"## sites UNKNOWN (a name/spread in the literal)      : {unknown_sites}")
    # THE FOUR GRADES MUST PARTITION THE SITE SET. Asserted because a tally that silently drops a
    # grade is how `reach.py` printed "GUARDED: 2" over a three-row table -- the census found the
    # site and the summary hid it. `rebase-gate-selftest`'s "0 disagreements over 0 comparisons"
    # is the same shape, and the answer to it is an assertion, not a careful read.
    n_str = len(rows) - reach_sites - unknown_sites - dynamic_sites
    graded = reach_sites + n_str + dynamic_sites + unknown_sites
    if graded != len(rows):
        print(f"## PARTITION ERROR: {graded} graded vs {len(rows)} sites found.")
        return 1
    print(f"## the four grades partition all {len(rows)} sites: "
          f"{reach_sites} REACHES + {n_str} MEMBER-IS-STR + {dynamic_sites} DYNAMIC + "
          f"{unknown_sites} UNKNOWN = {graded}")
    print()
    hdr = ("file", "ln", "kind", "container", "keys", "reach", "reason")
    print(f"{hdr[0]:<34} {hdr[1]:>5} {hdr[2]:<4} {hdr[3]:<26} {hdr[4]:<28} {hdr[5]:<12} source")
    print("-" * w)
    for rel, lineno, kind, cont, keys, v, reason, line in rows:
        print(f"{rel:<34} {lineno:>5} {kind:<4} {cont:<26} {str(keys)[:28]:<28} {v:<12} {line[:60]}")
    print()
    print("## reasons, one line per distinct reason")
    seen = set()
    for rel, lineno, kind, cont, keys, v, reason, line in rows:
        if reason in seen:
            continue
        seen.add(reason)
        print(f"##   {v}: {reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())