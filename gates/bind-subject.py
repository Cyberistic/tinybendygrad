#!/usr/bin/env python3
"""gates/bind-subject.py -- WHAT A PIN IS ABOUT, IN A FORM A MACHINE CAN READ.

THE DEFECT THIS REPAIRS. `gates/pincensus-gate.py` measures a pin's currency by HASHING THE
PIN'S SUBJECT, and it can only do that when the subject is named IN THE SAME BINDING --
`"diffpy/oracle-run.sh": "<sha256>"` -- so a dict-shaped KEY was read as a PATH. Three pins in
this tree were therefore unmeasurable, and each was unmeasurable for a different reason:

  * `checks/e2e.py:268 ORACLE_SHA` and `:269 BODY_SHA` -- THE TREE'S OWN FLAGSHIP CONTENT PIN.
    Its subject is `checks/e2e.sh` and `.agents/slop/e2epy/oracle-e2e.sh`, and the file said
    WHICH in PROSE and in nothing else. The census answered NO-MEASUREMENT: "len=64, not a
    revision in this object store and no subject named". A digest with no subject is not a
    measurement; it is a literal.
  * `checks/differ.py` `REPRO_PINS` -- whose key `d10-transcript` is a ROW NAME in a
    gitignored run artifact, so reading it as a path produced "looked in ., .agents/slop for
    d10-transcript; found neither": A MISSING SUBJECT THAT IS NOT MISSING. It is untracked BY
    DESIGN, and the census was reporting its absence as a fact about the tree.

THE DECLARATION, AND IT IS ONE SHAPE, DISCOVERED BY A REGEX OVER THE TREE'S OWN CODE.

  * a binding whose name ends in `_SUBJECT` names the FILE a pin is about;
  * a binding whose name ends in `_ARTIFACT` names the file a pin TABLE'S ROWS are carried by.

THE JOIN IS BY NAME, AND IT IS THE LONGEST PREFIX THAT FITS. A pin `BODY_SHA` takes the
subject of `BODY_SUBJECT` because the declaration's prefix is a PREFIX of the pin's name, and
the longest such prefix wins; `REPRO_PINS` takes the artifact of `REPRO_ARTIFACT` by the same
rule, and `REPRO_DIFF_ARTIFACT` does not match it because its prefix is longer and does not
fit. A rule over BINDING NAMES is not a hand list and not a prose parser: the names are code,
the regex finds them, and a declaration that stops matching stops being used.

WHAT THIS DOES NOT DO, AND IT IS THE POINT. It does not RE-DERIVE the pin from the subject.
The pin is the LITERAL in the source; the subject is a FILE ON DISK; the two are INDEPENDENT
values and the census compares them. A census that computed the digest from the thing it
pins would compare `sha256(x)` with `sha256(x)` -- A TAUTOLOGY THAT CANNOT FAIL, WHICH IS
WORSE THAN NO INSTRUMENT.

THE RUN DIRECTORY IS DISCOVERED TOO. A pin table whose rows are carried by an artifact under
`runs/` has no tracked subject, and its bytes are not read: a run may be LIVE, and a live
artifact read under a pin is the "STALE FILE WAS SERVING AS THE WITNESS" defect. So the
census says WHERE the subject lives and refuses to read it, rather than claiming it is absent.
"""
import re

# A BINDING, AND ITS RIGHT-HAND SIDE ON THE SAME LINE. Only the names this module cares about
# are matched: an UPPER-CASE identifier of at least three characters, so a local variable and a
# lowercase constant cannot be mistaken for a declaration.
BIND = re.compile(r"^[ \t]*([A-Z][A-Z0-9_]{2,})[ \t]*=[ \t]*(.*)$")

# A STRING LITERAL ON THAT LINE. Two spellings, because this tree uses both.
STRING = re.compile(r'"([^"\n]*)"|\'([^\'\n]*)\'')

# THE RUN DIRECTORY, AS A PATH RELATIVE TO THE REPOSITORY ROOT. The leading `runs/` is the
# whole point: `runs/` is gitignored, and `checks/differ.py`'s `D = ROOT / "runs/graphcmp/D"`
# is the tree's own spelling of it. A literal that merely CONTAINS a run path ("into
# runs/graphcmp/D") is not one, and the anchor is what says so.
RUN_DIR = re.compile(r"\A(runs/[A-Za-z0-9._/-]+)\Z")

# THE TWO DECLARATION SHAPES.
SUBJECT, ARTIFACT = "_SUBJECT", "_ARTIFACT"

# THE KEY OF A SUBJECT DECLARATION, WITHOUT ITS SUFFIX.
def _prefix(name):
    for suffix in (SUBJECT, ARTIFACT):
        if name.endswith(suffix) and len(name) > len(suffix):
            return name[:-len(suffix)]
    return None


def declarations(corpus, code):
    """-> {file: {"subjects": {prefix: value}, "artifacts": {prefix: value},
                  "run-dirs": [dir], "at": {prefix: "file:line"}}}.

    `corpus` is {relpath: text} and `code` is {relpath: [(lineno, line)]} -- the CODE lines
    only, so a run path inside a docstring or a `#` comment is not a declaration. That map is
    `gates/pincensus-pop.py`'s `code_lines`, passed in rather than recomputed: two readers of
    one file is two witnesses with no generator between them, which is the defect this tree
    calls "ONE COPY OF THE LIST".
    """
    out = {}
    for path, text in corpus.items():
        decl = {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}}
        for lineno, line in code.get(path, []):
            for lit in (a or b for a, b in STRING.findall(line)):
                if RUN_DIR.match(lit) and lit not in decl["run-dirs"]:
                    decl["run-dirs"].append(lit)
            m = BIND.match(line)
            if not m:
                continue
            name, prefix = m.group(1), _prefix(m.group(1))
            if prefix is None:
                continue
            lits = [a or b for a, b in STRING.findall(m.group(2))]
            value = next((l for l in lits if l), None)
            if value is None:
                # AN EMPTY NAME NAMES NO FILE. `REPRO_ARTIFACT = ""` is a declaration with no
                # subject, and treating it as one would let the census report a subject that
                # does not exist -- which is the defect this module exists to remove.
                continue
            if name.endswith(SUBJECT):
                decl["subjects"][prefix] = value
                decl["at"][prefix] = f"{path}:{lineno}"
            elif name.endswith(ARTIFACT):
                decl["artifacts"][prefix] = value
                decl["at"][prefix] = f"{path}:{lineno}"
        out[path] = decl
    return out


def resolve(name, decl):
    """-> the declaration that names the subject of the pin `name`, or None.

    THE JOIN IS THE LONGEST FITTING PREFIX, and it is a join over NAMES and not over paths:
    a declaration with prefix P names the subject of a pin N iff N starts with P and an
    underscore. `BODY_SUBJECT` (prefix `BODY`) names the subject of `BODY_SHA`; `REPRO_ARTIFACT`
    (prefix `REPRO`) names the artifact of `REPRO_PINS`; `REPRO_DIFF_ARTIFACT` (prefix
    `REPRO_DIFF`) names nothing here, because `REPRO_PINS` does not start with `REPRO_DIFF_`.

    TWO DECLARATIONS OF THE SAME PREFIX ARE AMBIGUOUS AND THE ANSWER IS NONE. A subject the
    census cannot choose is not a subject.
    """
    best = None
    for kind, table in (("SUBJECT", decl["subjects"]), ("ARTIFACT", decl["artifacts"])):
        for prefix, value in table.items():
            if not name.startswith(prefix + "_"):
                continue
            if best is not None and len(prefix) == len(best[1]):
                return None
            if best is None or len(prefix) > len(best[1]):
                best = (kind, prefix, value)
    if best is None:
        return None
    return {"kind": best[0], "prefix": best[1], "value": best[2], "at": decl["at"].get(best[1], "")}
