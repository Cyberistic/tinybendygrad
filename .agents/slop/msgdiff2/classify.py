#!/usr/bin/env python3
"""msgdiff2 -- MESSAGE polarity against DIFF polarity over ONE captured range.

WHAT IS REUSED AND HOW, AND WHY IT IS NOT `import`. The claim grammar -- every regex the
gates/msgdiff-gate.py claim lane and subject lane are built from -- is LOADED FROM THAT FILE BY
PATH AND PARSED WITH `ast`: this module reads the gate's own `re.compile("<...>")` sources and
compiles them here. It NEVER imports the gate module and NEVER executes it, because this unit's
machine contract forbids running anything under `gates/`. The consequence is the one that
matters: THERE IS ONE COPY OF THE GRAMMAR IN THIS REPO AND IT IS THE GATE'S, not a second one
that can rot. What IS mine is the ALGORITHM (a re-implementation of the gate's documented
`judge_message` / `judge_subject` / `unacknowledged_removals`) and the INVERSION LANE, which the
gate does not have at all -- see `INVERSE` below.

THE THREE LANES AND WHAT EACH ONE IS, SO A VERDICT NAMES ITS QUESTION.

  CLAIM   (the gate's lane 1, `judge_message`): the MESSAGE asserts a DELETION of a path it
          names, and the path is PRESENT in this commit's tree and NOT in the diff's `D` set.
          Fired -> the message claims a change this diff does not witness.
  SUBJECT (the gate's lane 2, `judge_subject`): the DIFF removes a path the message never names
          nor acknowledges. Fired -> an UNDECLARED removal. This is how a message that says
          nothing about its removals gets graded at all.
  INVERSE (MINE -- the gate has no such lane): the MESSAGE asserts a RESTORATION, ADDITION or
          REPAIR of a path it names, and the diff REMOVES that same path. Fired -> the polarity
          is inverted: the message says "restored X" over a diff that deletes X.

WHY THE GATE IS BLIND TO INVERSION, IN ONE PARAGRAPH. `VERB` is the gate's only message-driven
trigger and it is a DELETE grammar: `deleted|delete|deletes|deleting|removed|removes|removing|
git rm|dropped|drops|dropping` (`gates/msgdiff-gate.py:106`). `restored`, `reintroduced`,
`reinstated`, `reverted`, `undeleted`, `repaired` and `added` are not in it, so a message
asserting any of them produces ZERO claims, the claim lane prints `0 deletion claims checked`,
and it PASSes -- structurally, not accidentally. The SUBJECT lane can still fire, but it fires
for a DIFFERENT reason: it fires when the removed paths are UNNAMED. A message that says
"restored `foo.py`" over a diff whose `D` set is exactly `foo.py` names the path, so
`unacknowledged_removals` is EMPTY, the subject lane PASSes, and BOTH LANES PASS on a commit
whose message and diff point in opposite directions. That is the case this unit exists to name.

THE VERDICTS. CONFIRMED -- every checkable claim is witnessed, and if there were none, that is
stated in the reason rather than counted as agreement. FALSE-CLAIM -- a deletion assertion or an
explicit file count the diff contradicts. FALSE-CLAIM-INVERSE -- a restore/add/repair assertion
the diff's removals contradict. UNCLEAR -- no checkable assertion survives the grammar, so the
gate CANNOT see this commit and neither can this; UNCLEAR IS NOT CONFIRMED.

FIDELITY, BEFORE ANY VERDICT IS BELIEVED. `VECTORS` below are six REAL commits in this repo with
the gate's OWN documented verdicts, quoted from its docstring and code comments. They are the
denominator this re-implementation is judged against: if the re-implementation does not
reproduce them, it is not the gate's logic and this run REFUSES to classify anything.
"""
import ast
import os
import re
import subprocess
import sys
from fnmatch import fnmatch
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GATE = ROOT / "gates" / "msgdiff-gate.py"

# THE GRAMMAR IS NAMED HERE BY BINDING NAME ONLY, NOT RESTATED: `load_grammar` asks the gate's
# own source for each of these. A binding this list misspells raises, so the list cannot silently
# fall back to a built-in copy.
GRAMMAR_BINDINGS = ("VERB", "PATH", "GLOB", "DIR", "GAP_STOP", "NEGATION", "META", "COUNT",
                    "PID", "SUBJECT_RE")


def _flags(node):
    """`re.compile`'s flags, read from the AST: an int literal, a `re.X` attribute, or an OR of
    them. `getattr(re, ...)` rather than a list of flag NAMES, so a flag this file has never
    heard of is still resolved -- the flag set is discovered from the `re` module, not declared."""
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) \
            and node.value.id == "re":
        return getattr(re, node.attr)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr):
        return _flags(node.left) | _flags(node.right)
    raise RuntimeError(f"unresolved re.compile flag: {ast.dump(node)}")


def load_grammar(path):
    """The gate's compiled regexes, from its source text. `ast`, so the module never runs."""
    tree = ast.parse(path.read_text())
    found = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        name = node.targets[0].id if isinstance(node.targets[0], ast.Name) else None
        # `re.compile` is an ast.Attribute, not an ast.Name. The pattern argument is an
        # ast.Constant even where the gate splits it across adjacent literals, because the
        # parser folds implicit concatenation before this walk ever sees it.
        if name in GRAMMAR_BINDINGS and isinstance(node.value, ast.Call) \
                and isinstance(node.value.func, ast.Attribute) \
                and node.value.func.attr == "compile" \
                and node.value.args and isinstance(node.value.args[0], ast.Constant):
            pat = node.value.args[0].value
            # THE FLAGS ARE PART OF THE GRAMMAR AND DROPPING THEM IS A SILENT DEGRADATION.
            # `VERB` is `re.compile(..., re.I)`: with the flag lost it matches no capitalised
            # sentence at all, so the claim lane would read an HONEST "Deleted X" as having no
            # claim -- the exact failure this unit exists to catch, manufactured by the loader.
            flags = 0
            for extra in node.value.args[1:]:
                flags |= _flags(extra)
            found[name] = re.compile(pat, flags)
    missing = [b for b in GRAMMAR_BINDINGS if b not in found]
    if missing:
        raise RuntimeError(f"grammar bindings not found in {path}: {missing}")
    return found


G = load_grammar(GATE)
G = load_grammar(GATE)
VERB, PATH_RE, GLOB_RE, DIR_RE = G["VERB"], G["PATH"], G["GLOB"], G["DIR"]
GAP_STOP, NEGATION, META, COUNT_RE = G["GAP_STOP"], G["NEGATION"], G["META"], G["COUNT"]

# INVERSE, AND IT IS MINE. A hand list, admitted as one: the gate owns the DELETE grammar and
# has no RESTORE grammar at all, so this vocabulary is the whole of the inversion lane's
# vocabulary and the report says so. Word-bounded, case-insensitive, and `replant`/`un-plant`
# are here because this tree's own vocabulary calls an injected fault a "plant" (`--plant`,
# `oracles/plants.py`), so "replanted" is a restoration here and not a typo.
INVERSE = re.compile(
    r"(?<![\w-])(restor(?:e|es|ed|ing)|re-?introduc(?:e|es|ed|ing)|reinstat(?:e|es|ed|ing)"
    r"|resurrect(?:ed|ing)?|re-?add(?:s|ed|ing)?|bring(?:s|ing)?\s+back|brought\s+back"
    r"|recover(?:ed|s|ing)?|revert(?:ed|s|ing)?|undo(?:ne|es)?|undid|un-?delet(?:e|ed|es|ing)"
    r"|replant(?:ed|s|ing)?|un-?plant(?:ed|s|ing)?|repair(?:ed|s|ing)?|refix(?:ed|es)?"
    r"|add(?:s|ed|ing)?|creat(?:e|es|ed|ing)|wrote|written)\b", re.I)

# A file count is the gate's `COUNT` lane: `N files changed|deleted|added|removed|touched`. It
# grades against the diff's CHANGED-path count (`commit_view`'s `changed`), which counts every
# name-status line, so a rename is one changed path.
COUNT_VERB = re.compile(r"(?<![\w-])(?P<n>\d+)\s+(?:files?|paths?)\s+"
                        r"(?P<noun>changed|deleted|added|removed|touched)\b"
                        r"|(?P<noun2>changed|deleted|added|removed|touched)\s+(?P<n2>\d+)\s+"
                        r"(?:files?|paths?)\b", re.I)


def git(*args):
    """One git call. `--no-optional-locks` never writes the index it reads, and `GIT_INDEX_FILE`
    is unset so a colocated `jj` snapshot's armed index cannot answer a question about the tree."""
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: rc={r.returncode}: {r.stderr.strip()}")
    return r.stdout


# ---- the gate's algorithm, re-implemented from its documented source -----------------------
def commit_view(sha, want_present):
    """(present, deleted, removed, changed). Mirrors the gate's `commit_view`.

    `present` is LAZY and that is the one deviation, and it cannot change a verdict: the gate
    computes it for every commit and then reads it on exactly one branch -- the claim lane's
    refusal, which needs a candidate path token to exist first. `removed`/`changed` come from the
    same `diff-tree -r -M --root --name-status` the gate uses, so `D` and rename SOURCES are in
    `removed` and only `D` is in `deleted`, exactly as the gate documents."""
    status = git("diff-tree", "-r", "-M", "--root", "--no-commit-id", "--name-status", sha)
    deleted, removed, changed = set(), set(), 0
    for line in status.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        changed += 1
        if parts[0].startswith("D"):
            deleted.add(parts[-1])
            removed.add(parts[-1])
        elif parts[0].startswith("R") and len(parts) >= 3:
            removed.add(parts[1])
    present = set(git("ls-tree", "-r", "--name-only", sha).splitlines()) if want_present else set()
    return present, deleted, removed, changed


def _clause(text, i):
    """The gate's `_clause`, verbatim in behaviour: bounded by a newline, `***`, or `. `."""
    start = max(text.rfind(c, 0, i) for c in ("\n", "***", ". "))
    if start >= 0 and start == text.rfind("***", 0, i):
        start += 3
    start = max(start, 0)
    ends = [e for e in (text.find(c, i) for c in ("\n", "***", ". ")) if e != -1]
    hi = (min(ends) + 1) if ends else len(text)
    return " ".join(text[start:hi].split()).lstrip(".* "), start, hi


def _nearest_path(text, i, hi, window=40):
    """The gate's `_nearest_path`: forward-only, window-bounded, gap-filtered."""
    m = PATH_RE.search(text, i)
    if not m or m.start() - i > window or m.start() >= hi:
        return None
    return None if GAP_STOP.search(text[i:m.start()]) else m.group()


def deletion_claims(message):
    """The gate's `deletion_claims`: (token, clause, kind) per delete verb."""
    out = []
    for m in VERB.finditer(message):
        at = m.start()
        clause, _lo, hi = _clause(message, at)
        skip = NEGATION.search(message[max(0, at - 48):at]) or META.search(clause)
        out.append((_nearest_path(message, at, hi), clause,
                    "skip" if skip else "claim"))
    return out


def inverse_claims(message):
    """MINE, the mirror of `deletion_claims` with the INVERSE grammar: a restore/add/repair verb
    and the path it governs, or None when the verb governs no path in this clause."""
    out = []
    for m in INVERSE.finditer(message):
        at = m.start()
        clause, _lo, hi = _clause(message, at)
        if NEGATION.search(message[max(0, at - 48):at]) or META.search(clause):
            out.append((None, clause, "skip"))
            continue
        out.append((_nearest_path(message, at, hi), clause, "claim"))
    return out


def _message_names(message):
    """The gate's `_message_names`: the path tokens PLUS their parent directories."""
    tokens = set(PATH_RE.findall(message))
    parents = set()
    for t in tokens:
        parts = t.split("/")
        parents.update("/".join(parts[:i]) for i in range(1, len(parts)))
    return tokens, parents


def _covered(path, roots):
    """The gate's `_covered`: equal, prefix, SUFFIX, or `*` glob. `fnmatch` is the only
    metacharacter, which is the gate's measured choice."""
    return (path in roots
            or any(path.startswith(pre + "/") for pre in roots)
            or any(path.endswith("/" + r) for r in roots if r)
            or any(fnmatch(path, pat) or fnmatch(path, pat.rstrip("/") + "/*")
                   for pat in roots if "*" in pat))


def unacknowledged_removals(removed, message):
    """The gate's `unacknowledged_removals` with an EMPTY ack: the gate's SUBJECT_DIFF_ACK is
    per-commit prose a caller supplies, and this run supplies none, so every undeclared removal
    stands unacknowledged. That is the strict reading and it is stated in the report."""
    tokens, parents = _message_names(message)
    decl = tokens | parents | set(GLOB_RE.findall(message)) | set(DIR_RE.findall(message))
    return [p for p in sorted(removed) if not _covered(p, decl)]


# ---- the verdict ------------------------------------------------------------------------
# ADJUDICATION -- WHAT READING EACH GATE FIRING ACTUALLY FOUND. One entry per firing, keyed by the
# 12-CHAR PREFIX, and `classify` RAISES on a firing with no entry, so this table cannot fall behind
# the lane it audits. Four firings over the captured range, and all four are the SAME underlying
# gap in different clothes: the grammar attributes a verb to a path when the sentence is not
# asserting that verb about that path. The four shapes are named, because a shape is reusable and
# a verdict is not.
#
#   HYPOTHETICAL-MOOD   a bare `git commit` "WOULD TRY TO DELETE x.py" -- a prediction about a
#                       future command, and the sentence says so.
#   FILE-LINE-REF       "pr_0 dropped BOTH halves of spec.py:204" -- `spec.py` is a location inside
#                       a file, and `PATH` has no `:` so it captures the half-path and calls it a
#                       file deletion.
#   QUOTED-GIT-OUTPUT   "`delete mode 100644 gates/README.md`" -- that is a LINE OF `git commit`
#                       stdout, quoted as evidence about a DIFFERENT commit.
#   OTHER-COMMIT-REF    "commit 591f6b499 carried 435 changed files and delete mode ...gates/
#                       README.md" -- a true statement about the PARENT, graded against this
#                       commit's diff because the gate has no notion of which commit a claim is
#                       about. This is the gate's largest measured gap and it is NOT in its
#                       docstring: the docstring lists what the gate cannot see (a bare
#                       percentage, a dead pid, an invented key) and every one of those names
#                       NOTHING. This gap is the opposite -- a perfectly checkable claim about
#                       the WRONG COMMIT, which the gate grades and gets wrong.
ADJUDICATION = {
    "f19347f66e20": ("FALSE-CLAIM-ARTIFACT", "HYPOTHETICAL-MOOD: 'would try to DELETE "
                     "checks/substrate-manifest.py' predicts what a future bare `git commit` would "
                     "do over a phantom index; the same message says 'NOTHING IS WRONG WITH THE "
                     "COMMIT' and its diff deletes nothing (0 D)."),
    "57b8f71c9466": ("FALSE-CLAIM-ARTIFACT", "FILE-LINE-REF: 'pr_0 dropped BOTH halves of "
                     "spec.py:204' is two conjuncts removed from a LINE; `PATH` stops at the `:` "
                     "and yields `spec.py`, so an in-file edit reads as a file deletion. 0 D."),
    "02329daf0847": ("FALSE-CLAIM-ARTIFACT", "OTHER-COMMIT-REF + "
                     "QUOTED-GIT-OUTPUT: the message's deletion and its '435 files changed' are "
                     "both about commit 591f6b499, its PARENT, which it names in the sentence. "
                     "591f6b499's own name-status is 435 lines / 309 distinct paths -- the message "
                     "is right about the parent and is graded against its own diff."),
    "1655307d1f37": ("FALSE-CLAIM-ARTIFACT", "OTHER-COMMIT-REF: "
                     "'deleted gates/README.md; a 178-path --only carried 430' is the INDEXRACE "
                     "record describing EARLIER commits, and this commit's diff deletes nothing."),
}


def classify(sha, message):
    claims = deletion_claims(message)
    inv = inverse_claims(message)
    need_present = any(k == "claim" and t for t, _c, k in claims) \
        or any(k == "claim" and t for t, _c, k in inv)
    present, deleted, removed, changed = commit_view(sha, need_present)

    checked, refusals, uncheckable = 0, [], {"no_path": 0, "meta": 0, "renamed_or_absent": 0}
    witnessed = []
    for tok, clause, kind in claims:
        if kind == "skip" or not tok:
            uncheckable["meta" if kind == "skip" else "no_path"] += 1
            continue
        cands = [p for p in (present | deleted) if p == tok or p.endswith("/" + tok)]
        if not cands:
            uncheckable["renamed_or_absent"] += 1
            continue
        checked += 1
        if not any(p in deleted for p in cands):
            refusals.append((tok, clause, "present in this commit's tree, not deleted by it"))
        else:
            witnessed.append(f"deletion of {tok} is in the diff")

    count_refusals = []
    for m in COUNT_VERB.finditer(message):
        n = int(m.group("n") or m.group("n2"))
        noun = (m.group("noun") or m.group("noun2")).lower()
        if noun == "added":
            # an added count needs an ADDED set, which the gate does not compute and this
            # re-implementation does not either; an unverifiable direction is UNCHECKABLE
            # rather than guessed, and it is not counted as checked.
            uncheckable["no_path"] += 1
            continue
        checked += 1
        if noun == "changed":
            if n != changed:
                count_refusals.append((f"{n} files changed", _clause(message, m.start())[0],
                                       f"the diff changes {changed} name-status path(s)"))
            else:
                witnessed.append(f"'{n} files changed' == the diff's {changed} name-status path(s)")
        elif noun in ("deleted", "removed") and n > len(deleted):
            count_refusals.append((f"{n} files deleted", _clause(message, m.start())[0],
                                   f"the diff deletes {len(deleted)} distinct path(s)"))
        elif noun in ("deleted", "removed"):
            witnessed.append(f"'{n} files deleted' <= the diff's {len(deleted)} distinct deletion(s)")

    # ---- the inversion lane, on named paths only -----------------------------------------
    inv_hits, inv_unnamed = [], []
    for tok, clause, kind in inv:
        if kind == "skip" or not tok:
            continue
        hits = sorted(p for p in removed
                      if p == tok or p.endswith("/" + tok) or _covered(p, (tok,)))
        if hits:
            inv_hits.append((tok, clause, hits))

    subject_bad = unacknowledged_removals(removed, message)

    numstat = git("diff-tree", "-r", "-M", "--root", "--no-commit-id", "--numstat", sha)
    add_lines = del_lines = 0
    for line in numstat.splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            add_lines += 0 if parts[0] == "-" else int(parts[0])
            del_lines += 0 if parts[1] == "-" else int(parts[1])

    mpolarity = message_polarity(claims, inv)
    dpolarity = diff_polarity(add_lines, del_lines, deleted, removed)

    # ---- the verdict -----------------------------------------------------------------------
    # A GATE FIRING IS NOT A VERDICT, AND `gates/msgdiff-gate.py:66` says so in its own docstring.
    # So every firing below is passed through ADJUDICATION, a table of what reading the sentence
    # actually found. A firing with NO entry raises and the run refuses: a new false claim cannot
    # reach the report unadjudicated, which is the only thing that makes "0 FALSE-CLAIM" mean
    # anything rather than "nobody looked".
    if refusals or count_refusals:
        mech = "FALSE-CLAIM"
        why = [f"deletes/[{tok}] :: {clause[:100]} :: {r}" for tok, clause, r in refusals]
        why += [f"count :: {c} :: {r}" for _t, c, r in count_refusals]
        if sha[:12] not in ADJUDICATION:
            raise RuntimeError(f"{sha[:12]}: the gate fired and nobody read the sentence. "
                               f"Add an ADJUDICATION entry or REFUSE the run.")
        adj = ADJUDICATION[sha[:12]]
        why.append(f"ADJUDICATED {adj[0]}: {adj[1]}")
        verdict = adj[0]
    elif inv_hits:
        mech = "FALSE-CLAIM-INVERSE"
        verdict = mech
        why = [f"says restored/added/repaired [{tok}] but the diff REMOVES {h} :: {c[:70]}"
               for tok, c, h in inv_hits]
    elif subject_bad:
        mech = "FALSE-CLAIM-INVERSE" if mpolarity in ("RESTORE", "ADD") else "UNCLEAR"
        verdict = mech
        why = [f"the diff REMOVES {len(subject_bad)} path(s) the message never names, and the "
               f"message's own polarity is {mpolarity}"]
    elif checked:
        mech = verdict = "CONFIRMED"
        why = witnessed
    else:
        mech = verdict = "UNCLEAR"
        why = ["0 checkable claims: the grammar reads no assertion this diff could answer "
               f"({uncheckable}) -- NOT agreement"]
    if subject_bad and mech == "CONFIRMED":
        verdict = "CONFIRMED+UNDECLARED-REMOVAL"
        why = witnessed + [f"BUT the diff REMOVES {len(subject_bad)} undeclared path(s)"]

    return {
        "sha": sha, "verdict": verdict, "message_polarity": mpolarity,
        "diff_polarity": dpolarity,
        "reason": f"[msg_polarity={mpolarity} diff=+{add_lines}/-{del_lines}L "
                  f"{len(deleted)}D/{len(removed)}R paths; claim_checked={checked} "
                  f"uncheckable={sum(uncheckable.values())} "
                  f"subject_undeclared={len(subject_bad)}] " + " | ".join(why),
        "_n_del": len(deleted), "_n_removed": len(removed), "_checked": checked,
        "_subject_bad": len(subject_bad), "_del_lines": del_lines, "_add_lines": add_lines,
    }


def message_polarity(claims, inv):
    """What the message asserts about the direction of the world. `MIXED` when it asserts both."""
    dele = any(k == "claim" and t for t, _c, k in claims)
    rest = any(k == "claim" and t for t, _c, k in inv)
    if dele and rest:
        return "MIXED"
    if dele:
        return "DELETE"
    if rest:
        return "RESTORE"
    if any(k == "claim" and t for t, _c, k in inv) or VERB.search("".join(c for _t, c, _k in claims)):
        return "UNSPECIFIED"
    return "NEUTRAL"


def diff_polarity(add_lines, del_lines, deleted, removed):
    if del_lines == 0 and add_lines == 0:
        return "NO-CHANGE"
    if del_lines > add_lines:
        return "DELETES"
    if add_lines > del_lines:
        return "ADDS"
    return "MIXED"


# ---- fidelity: the gate's OWN documented verdicts, as vectors -----------------------------
# Six REAL commits, the expected verdicts quoted from `gates/msgdiff-gate.py`'s own docstring and
# code comments. This is the denominator the re-implementation is judged against. If any vector
# fails, this run classifies NOTHING.
VECTORS = [
    ("00b101574", "CLAIM", "REFUSED", "oracles259/plants.py is present in its tree at e6e31707"),
    ("9144d179e25a", "CLAIM", "PASS", "0 checked, 0 uncheckable -- no claim sentence"),
    ("c83f04ad1c12", "CLAIM", "PASS", "0 checked, 0 uncheckable -- no claim sentence"),
    ("75ab9b8f8984", "CLAIM", "PASS", "0 checked, 0 uncheckable -- no claim sentence"),
    ("9144d179e25a", "SUBJECT", "REFUSED", "removed 110 paths, message names 7 globs and none"),
    ("c83f04ad1c12", "SUBJECT", "REFUSED", "removed 66 paths as R100 renames"),
    ("75ab9b8f8984", "SUBJECT", "REFUSED", "removed 4 paths, message names none"),
    ("9b55d16a4", "SUBJECT", "PASS", "honest strays-removal: GLOB/DIR declare all four"),
    ("169ee6ac8", "CLAIM", "PASS", "meta-report: the predecessor's claim IS FALSE"),
    ("3c4ceeea3", "CLAIM", "PASS", "MOVED, NOT DELETED / retire 19 -- negated, kept"),
    ("3188c1af86a1", "SUBJECT", "PASS", "four relocated paths named relative to tinybendygrad/"),
]


def vectors():
    """(lane, verdict, detail) per vector, computed by the same functions `classify` uses."""
    out = []
    for sha, lane, want, detail in VECTORS:
        try:
            msg = git("log", "-1", "--format=%B", sha)
        except RuntimeError as e:
            out.append((sha, lane, "ABSENT", "SKIP", str(e)[:80]))
            continue
        claims = deletion_claims(msg)
        present, deleted, removed, changed = commit_view(sha, True)
        if lane == "CLAIM":
            checked, refusals, unc = 0, [], 0
            for tok, _c, kind in claims:
                if kind == "skip" or not tok:
                    unc += 1
                    continue
                cands = [p for p in (present | deleted) if p == tok or p.endswith("/" + tok)]
                if not cands:
                    unc += 1
                    continue
                checked += 1
                if not any(p in deleted for p in cands):
                    refusals.append(tok)
            got = "REFUSED" if refusals else "PASS"
            out.append((sha, lane, got, want,
                        f"{detail}; measured checked={checked} uncheckable={unc} "
                        f"refused={refusals[:2]}"))
        else:
            bad = unacknowledged_removals(removed, msg)
            got = "REFUSED" if bad else "PASS"
            out.append((sha, lane, got, want,
                        f"{detail}; measured removals={len(removed)} undeclared={len(bad)}"))
    return out


def main():
    """Two phases so neither is a long process. `rows` grades the captured range; `vectors`
    proves the grader reproduces the gate's own documented verdicts and therefore REFUSES to
    publish `classify.rows` if it does not. Run `vectors` FIRST, always."""
    phase = sys.argv[1] if len(sys.argv) > 1 else "rows"

    if phase == "vectors":
        vec = vectors()
        bad = [v for v in vec if v[2] != v[3]]
        with (HERE / "vectors.rows").open("w") as fh:
            fh.write("sha\tlane\tmeasured\texpected\tmatch\tdetail\n")
            for sha, lane, got, want, detail in vec:
                ok = "MATCH" if got == want else "MISMATCH"
                fh.write(f"{sha}\t{lane}\t{got}\t{want}\t{ok}\t{detail.replace(chr(9), ' ')}\n")
        print(f"fidelity vectors: {len(vec) - len(bad)}/{len(vec)} reproduced")
        for v in bad:
            print(f"  MISMATCH {v[0]} {v[1]}: measured {v[2]} expected {v[3]} -- {v[4]}")
        return 0 if not bad else 5

    snap = HERE / ".range-snapshot.rows"
    shas = [s.strip() for s in snap.read_text().split() if s.strip()]
    rows = [classify(s, git("log", "-1", "--format=%B", s)) for s in shas]

    with (HERE / "classify.rows").open("w") as fh:
        fh.write("sha\tverdict\tmessage_polarity\tdiff_polarity\treason\n")
        for r in rows:
            fh.write("\t".join([r["sha"][:12], r["verdict"], r["message_polarity"],
                                r["diff_polarity"], r["reason"].replace("\t", " ")]) + "\n")

    n = len(rows)
    # A STALE ADJUDICATION is the mirror failure of a missing one: an entry for a firing that no
    # longer fires would let a future false claim inherit a stranger's verdict. Both directions
    # are checked here, so the table is proved against the lane rather than trusted.
    fired = {r["sha"][:12] for r in rows if r["verdict"].startswith("FALSE-CLAIM-ARTIFACT")}
    stale = set(ADJUDICATION) - fired
    if stale:
        raise RuntimeError(f"ADJUDICATION entries for firings that did not happen: {sorted(stale)}")
    tally = {}
    for r in rows:
        tally[r["verdict"]] = tally.get(r["verdict"], 0) + 1
    for k in sorted(tally):
        print(f"{k}: {tally[k]} of {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())