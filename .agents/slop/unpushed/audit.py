#!/usr/bin/env python3
"""Read-only health inventory of the unpushed range origin/master..HEAD.

Writes range.rows (TAB) and findings for REPORT.md. Mutates nothing.
Every git call is a read: rev-list/cat-file/ls-tree/log/diff-tree/merge-base.
Index reads are disarmed with `env -u GIT_INDEX_FILE` so a colocated
jj-staged index cannot change a denominator.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GIT = ["git"]


def git(*args: str, check: bool = True) -> str:
    env = dict(os.environ)
    env.pop("GIT_INDEX_FILE", None)
    p = subprocess.run(GIT + list(args), capture_output=True, text=True, env=env, timeout=60)
    if check and p.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} rc={p.returncode}: {p.stderr.strip()}")
    return p.stdout if p.returncode == 0 else f"__RC{p.returncode}__ {p.stderr.strip()}"


def git_rc(*args: str) -> tuple[int, str, str]:
    env = dict(os.environ)
    env.pop("GIT_INDEX_FILE", None)
    p = subprocess.run(GIT + list(args), capture_output=True, text=True, env=env, timeout=60)
    return p.returncode, p.stdout, p.stderr


def raw_tree(sha: str) -> tuple[bool, list[tuple[str, str, str]]]:
    """cat-file -p <sha>^{tree}: raw on-disk entries (mode, type, oid, name).
    Returns (parsed_ok, entries). This is the RAW form, so a duplicate entry
    is visible here even where ls-tree would collapse it."""
    rc, out, err = git_rc("cat-file", "-p", f"{sha}^{{tree}}")
    if rc != 0:
        return False, []
    ents = []
    for line in out.splitlines():
        m = re.match(r"^(\d{6}) (\w+) ([0-9a-f]{40})\t(.*)$", line)
        if not m:
            return False, ents
        ents.append((m.group(1), m.group(2), m.group(4)))
    return True, ents


def root_names(sha: str) -> set[str]:
    _, ents = raw_tree(sha)
    return {n for _, _, n in ents}


def rec_walk(sha: str) -> tuple[int, str]:
    """git ls-tree -r <sha>: full recursive parse. (rc, text)."""
    rc, out, err = git_rc("ls-tree", "-r", sha)
    return rc, (err.strip() if rc != 0 else out)


DEL_WORDS = re.compile(
    r"\b(delet\w*|remov\w*|prun\w*|mass[- ]delet\w*|drop\w*|revert\w*|purge\w*)\b", re.I)
UNIT_TAG = re.compile(r"^([A-Za-z][A-Za-z0-9_.-]{1,24}):\s")


def main() -> int:
    shas = [l.strip() for l in (HERE / "range.sha.rows").read_text().splitlines() if l.strip()]
    head = git("rev-parse", "HEAD").strip()
    origin = git("rev-parse", "origin/master").strip()
    base = git("merge-base", origin, head).strip()
    n = len(shas)
    print(f"range={base}..{head} n={n}", file=sys.stderr)

    # parents, for the mass-deletion comparison
    parents = {}
    for s in shas:
        pl = git("log", "-1", "--format=%P", s).split()
        parents[s] = pl

    rows = []
    findings = {
        "author_ids": set(),
        "dup_trees": [],           # sha -> [(name, count)]
        "root_drops": [],          # sha -> sorted list of names dropped vs first parent
        "rec_bad": [],             # sha -> rc/err
        "raw_bad": [],             # sha -> err
        "claims_no_delete": [],    # (sha, subject, deletions_found)
        "claims_delete": [],       # (sha, subject, n_deletions)
        "merge_commits": [],
    }

    for s in shas:
        # %an <%ae> is ONE field; three fields total: identity, date, subject.
        ident, ci, subject = git("log", "-1", "--format=%an <%ae>%x1f%ci%x1f%s", s).rstrip("\n").split("\x1f")
        findings["author_ids"].add(ident)

        # files changed vs FIRST PARENT (no merges in this range, but be explicit)
        if len(parents[s]) != 1:
            findings["merge_commits"].append((s, parents[s]))
        p = parents[s][0] if parents[s] else None
        if p:
            _, nml, _ = git_rc("diff-tree", "-r", "--no-commit-id", "--name-only", p, s)
            changed = [x for x in nml.splitlines() if x]
            _, dl, _ = git_rc("diff-tree", "-r", "--no-commit-id", "--name-only",
                              "--diff-filter=D", p, s)
            deleted = [x for x in dl.splitlines() if x]
        else:
            changed, deleted = [], []

        # --- integrity: does every commit's tree parse? (recursive walk) ---
        rc, _txt = rec_walk(s)
        praw, ents = raw_tree(s)
        note = []
        if rc != 0:
            findings["rec_bad"].append((s, rc))
            note.append("ls-tree-r-RC%d" % rc)
        if not praw:
            findings["raw_bad"].append((s, "raw cat-file -p failed"))
            note.append("raw-tree-unparsed")

        # --- duplicates in the ROOT tree only (limit is visible on purpose) ---
        tree_ok = "parses" if (rc == 0 and praw) else "BAD"
        if praw:
            names = [n for _, _, n in ents]
            dupes = sorted({n for n in names if names.count(n) > 1})
            if dupes:
                findings["dup_trees"].append((s, [(n, names.count(n)) for n in dupes]))
                note.append("ROOT-DUP:" + ",".join(f"{n}x{names.count(n)}" for n in dupes))
                # parses != well-formed: say so in the verdict column, do not
                # let a readable tree read as a healthy one.
                tree_ok = "parses+DUP"

        # --- root tree missing paths relative to parent (mass deletion) ---
        if p:
            gone = sorted(root_names(p) - root_names(s))
            if gone:
                findings["root_drops"].append((s, gone))
                note.append("ROOT-DROP:%d" % len(gone))

        if not note:
            note.append("-")
        if not changed:
            note.append("EMPTY-diff")

        # --- coarse message-vs-diff ---
        body = git("log", "-1", "--format=%B", s)
        if DEL_WORDS.search(subject) or DEL_WORDS.search(body):
            if deleted:
                findings["claims_delete"].append((s, subject.splitlines()[0][:70], len(deleted)))
            else:
                findings["claims_no_delete"].append((s, subject.splitlines()[0][:70], 0))

        m = UNIT_TAG.match(subject)
        author_kind = f"unit:{m.group(1)}" if m else "unit:none"

        rows.append("\t".join([s, author_kind, str(len(changed)),
                               tree_ok, ";".join(note)]))

    (HERE / "range.rows").write_text("\n".join(rows) + "\n")

    # ---------- report inputs ----------
    L = []
    L.append(f"head={head}")
    L.append(f"origin={origin}")
    L.append(f"merge_base={base}")
    L.append(f"n_commits={n}")
    L.append(f"author_identities={len(findings['author_ids'])} " +
             ";".join(sorted(findings['author_ids'])))
    L.append(f"merge_commits={len(findings['merge_commits'])}")
    L.append(f"recursive_parse_fail={len(findings['rec_bad'])}")
    L.append(f"raw_tree_parse_fail={len(findings['raw_bad'])}")
    L.append(f"root_dup_trees={len(findings['dup_trees'])}")
    for s, d in findings["dup_trees"]:
        L.append(f"  DUP {s} {d}")
    L.append(f"commits_with_root_drop={len(findings['root_drops'])}")
    for s, g in findings["root_drops"]:
        L.append(f"  DROP {s} n={len(g)} {g}")
    L.append(f"msg_deletion_words_and_D_present={len(findings['claims_delete'])}")
    for s, subj, k in findings["claims_delete"]:
        L.append(f"  WITHDEL {s} nD={k} {subj}")
    L.append(f"msg_deletion_words_but_no_D={len(findings['claims_no_delete'])}")
    for s, subj, k in findings["claims_no_delete"]:
        L.append(f"  NODEL {s} {subj}")
    (HERE / "findings.rows").write_text("\n".join(L) + "\n")
    print("\n".join(L))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
