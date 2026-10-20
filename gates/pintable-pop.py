#!/usr/bin/env python3
"""gates/pintable-pop.py -- THE EXPECTATION ROWS: A PIN TABLE'S ROWS, AS PIN SITES.

WHAT THIS IS, AND WHY IT IS A SEPARATE MODULE RATHER THAN A BRANCH OF `pincensus-pop.py`.
`gates/pincensus-pop.py`'s value token is a CONTENT ADDRESS: a `>=7` lowercase hex run.
That is what makes a pin RE-DERIVABLE -- the census hashes the pin's subject and compares
two independent values. A PIN TABLE'S ROWS ARE NOT ADDRESSES. `checks/differ.py`'s `PINS`
holds `"graphs": "34"`, `"stable-pairs": "5 of 5"`, `"selfcheck": "# SELFCHECK: OK"`: those
are EXPECTATIONS about a recorded measurement, and an expectation cannot be re-derived by
hashing anything, because the thing it is about is a RUN. So the census's rule cannot see
them, and the flagship table of the tree -- the one `checks/corpus-figure.py` prints
`RUN HEALTH : OK` over -- was invisible to the instrument that exists to ask about pins.

THE JOIN IS NOT NEW, AND THAT IS THE POINT. `gates/bind-subject.py` already says what a
pin TABLE's subject is: *"a binding whose name ends in `_ARTIFACT` names the file a pin
TABLE'S ROWS are carried by ... a row name is what an artifact carries; a bare literal has
no row."* `gates/pincensus-gate.py:subject_of()` already implements the join: with an
`_ARTIFACT` declaration the DICT KEY IS A ROW NAME IN THAT ARTIFACT; without one the key is
a PATH. So the machinery for the table shape is BUILT and JOINED and the only reason
`checks/differ.py`'s `PINS` does not reach it is that its values are not hex literals.

THE POPULATION IS DISCOVERED, AND IT IS DISCOVERED BY THE PARSE. A table is a dict binding
whose name matches the census's own `PIN_NAME`, and its ROWS are read from `ast`, never
from a line window. `gates/pincensus-pop.py:rhs_of()` stops at `BIND_RHS_LINES` (7) lines,
which is right for a scalar binding and WRONG for a table: `checks/differ.py`'s `PINS`
opens at line 248 and its values are at lines 256-293, so the window stops at line 254 and
never reaches a single one of them. A rule that reads the source with a window cannot see
a table, and a table is a pin site.

WHAT THE DECLARATION IS FOR, AND WHY THE MODULE IS EXECUTED. The census's rows must be the
rows the TREE WILL COMPARE, not the rows the source appears to hold. A table can be patched
after it is declared -- `PINS["graphs"] = "35"` -- and then the literal and the module
disagree, and only the module's value is what `checks/differ.py:unhealthy()` compares. So
the population is read from the tree's own declaration, BY PATH, BY EXECUTING the defining
module; and the SCAN (what `ast` sees) and the DECLARATION (what the module holds) are two
INDEPENDENT readings of the same table, compared against each other. `gates/corpusverdict-gate.py`
already executes `checks/differ.py` the same way, so this is the tree's own practice and
not a new hazard. A module that cannot be read is REPORTED as not cross-checkable; it is
never silently skipped.

THE HAZARD IS NAMED RATHER THAN DISMISSED. Executing a file out of the tree is executing
code the census did not write. It is bounded here to the files that DEFINE a table of
expectations -- five of them, all of them `checks/differ.py` or a byte-identical copy of it
-- and it is refused outright when the module raises. A census that imports the tree is a
census with a sharp edge, and the edge is this one.
"""
import ast
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load_pop():
    """The census's own discovery module, BY PATH -- `gates/pincensus-pop.py` is loaded by
    `gates/pincensus-gate.py:load_pop()` the same way, and a hyphen is not an importable
    name. ITS `HEX` AND `PIN_NAME` ARE USED HERE RATHER THAN COPIED: a second copy of the
    value token would be a second definition of what a pin value is, and the two would
    drift apart without anyone noticing."""
    spec = importlib.util.spec_from_file_location("pincensus_pop", os.path.join(HERE, "pincensus-pop.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _name_of(node):
    """-> the NAME a binding binds, or None.

    Two shapes bind a name: `NAME = ...` and `NAME[key] = ...`. The second one is a
    REBINDING of the table, and it is the shape this module has to see, because a table
    patched after its declaration is a table whose literal and whose live value differ."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name):
        return node.value.id
    return None


def bindings(corpus, host):
    """-> {file: {name: [ {line, shape, rows, key} ]}}.

    `shape` is "dict" for a dict LITERAL and "other" for every other binding of the name.
    `rows` is the literal's `(key, value)` pairs, and only for the pairs whose key and
    value are BOTH string constants: a table whose value is computed (`str(x)`, an
    f-string, a tuple) is not a table of recorded expectations, and the census says so
    rather than carrying a row it cannot read.

    THE LINE IS THE BINDING'S OWN. `ast` reports the line of the statement, and the
    census's own `rule_a` reports the line of the FIRST line of the binding, which for a
    multi-line dict is the same line. They agree on every table in this tree.
    """
    out = {}
    for t, txt in corpus.items():
        if host[t] == "prose":
            continue
        try:
            tree = ast.parse(txt)
        except (SyntaxError, ValueError, RecursionError, MemoryError):
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                targets = node.targets
                value = node.value
            elif isinstance(node, ast.AnnAssign):
                targets = [node.target]
                value = node.value
            else:
                continue
            for target in targets:
                name = _name_of(target)
                if name is None:
                    continue
                key = None
                if isinstance(target, ast.Subscript):
                    k = target.slice
                    key = k.value if isinstance(k, ast.Constant) and isinstance(k.value, str) else "<computed>"
                rows = []
                if isinstance(value, ast.Dict):
                    for k, v in zip(value.keys, value.values):
                        if isinstance(k, ast.Constant) and isinstance(k.value, str) \
                           and isinstance(v, ast.Constant) and isinstance(v.value, str):
                            rows.append((k.value, v.value))
                out.setdefault(t, {}).setdefault(name, []).append(
                    {"line": node.lineno, "shape": "dict" if isinstance(value, ast.Dict) else "other",
                     "rows": rows, "key": key})
    return out


def tables(binds, pin_name):
    """-> [{file, line, name, rows, rebindings}] for every PIN-NAMED dict binding.

    `rebindings` are the OTHER bindings of the same name in the same file. A table bound
    once is CARRIED: the literal IS the table. A table bound again is NOT, and the census
    has to say so -- see `gates/pintable-gate.py` for what that costs."""
    out = []
    for f, names in sorted(binds.items()):
        for name, bs in sorted(names.items()):
            if not pin_name.match(name):
                continue
            dicts = [b for b in bs if b["shape"] == "dict"]
            for d in dicts:
                others = [b for b in bs if b is not d]
                out.append({"file": f, "line": d["line"], "name": name,
                            "rows": d["rows"], "rebindings": others})
    return out


def expectations(tabs, hex_re):
    """-> the rows of every table whose value carries NO content address.

    THE TWO POPULATIONS ARE DISJOINT BY CONSTRUCTION, AND THE DISJOINTNESS IS BY THE
    CENSUS'S OWN TEST. `gates/pincensus-pop.py`'s `HEX` is the value token, so a row whose
    value contains one of those tokens is ALREADY a row of the content-addressed
    population, and a row whose value contains none is an expectation. `REPRO_PINS` is the
    proof that the split is a split and not a gap: its `d10-transcript` row carries a
    sha256 and is in the content-addressed population, its `repro-rc` row carries `rc=0`
    and is an expectation, and BOTH are pins."""
    out = []
    for t in tabs:
        for key, value in t["rows"]:
            if hex_re.search(value):
                continue
            out.append({"file": t["file"], "line": t["line"], "name": t["name"], "key": key,
                        "value": value, "rebindings": t["rebindings"]})
    return out


def declaration(root, rel, name):
    """-> (rows, note). The tree's OWN declaration of the table: the module's attribute,
    read by EXECUTING the defining module BY PATH.

    `rows` is None when the declaration could not be read, and `note` then says why. A
    declaration that cannot be read is REPORTED; it is never treated as an empty table,
    because "the table has no rows" and "the table could not be read" are different claims
    about the tree and only one of them is a finding.

    THE EXECUTION IS OF A FILE OUTSIDE THE CENSUS, and that is the sharp edge of this
    module. It is bounded to files that DEFINE a table of expectations, and it is refused
    when the module raises -- an exception is a REFUSAL, not an empty table."""
    path = os.path.join(root, rel)
    # THE TAG IS THE ABSOLUTE PATH, NOT THE RELATIVE ONE. A plant judges two copies of the
    # same relative path in one process. A tag of the relative path would hand the second
    # execution the first copy's module, and a planted rebinding would then compare equal
    # to its control -- a vacuous negative, scored as a pass.
    tag = "pintable_decl_" + re.sub(r"\W", "_", os.path.abspath(path))
    sys.modules.pop(tag, None)
    try:
        spec = importlib.util.spec_from_file_location(tag, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception as exc:                      # noqa: BLE001 -- a refusal, named below
        return None, f"the module could not be executed ({type(exc).__name__}: {exc})"
    table = getattr(mod, name, None)
    if not isinstance(table, dict):
        return None, f"the module's `{name}` is {type(table).__name__}, not a dict"
    rows = [(k, v) for k, v in table.items() if isinstance(k, str) and isinstance(v, str)]
    dropped = len(table) - len(rows)
    note = f"read from the tree's own declaration; {dropped} row(s) are not (str, str) and were not read"
    return rows, note
