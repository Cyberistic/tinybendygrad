#!/usr/bin/env python3
"""gates/expectcopy-gate.py -- name each NO-SUBJECT-DECLARED copy against a commit.

The census classes a row NO-SUBJECT-DECLARED when no artifact is named. Those
rows live in files. This gate re-derives that population by loading the census
modules by path, drops ``checks/differ.py`` itself, and asks git whether each
remaining file's blob equals ``checks/differ.py`` at a commit that is not HEAD.

  HISTORICAL   the blob equals ``checks/differ.py`` at some commit that is not
               HEAD. Not a drift of the live flagship. Not a verdict that the
               table is current.
  PLANT-PAIR   two or more files are byte-identical and live under a ``plant/``
               directory, and that blob is historical. One pair, not two drifts,
               not another independent fork.
  LIVE-FORK    the blob equals no historical ``checks/differ.py``. The copy
               drifted on its own. Two identical drifted files under ``plant/``
               are still one LIVE-FORK, not a pair that passes.
  CURRENT      the blob equals ``HEAD:checks/differ.py``. A second current table.
  ABSENT       the path is not on disk. FAIL, not a skip.

The ask is ``git log --all -- checks/differ.py``, then
``git rev-parse <commit>:checks/differ.py``. ``git rev-list --all`` is not a
path index. ``git log --all --find-object`` matches the blob at any path,
including the fork itself, so it is not this question. The commit named is the
first ``git log --all`` lists. No such commit is NO-COMMIT. A one-byte
difference is not a match.

PASS means every copy is HISTORICAL or PLANT-PAIR, and none is byte-identical
to ``HEAD:checks/differ.py``. PASS means these are old copies, not a drifted
flagship. FAIL while any LIVE-FORK remains, or while a copy is presented as
the flagship. ``checks/differ.py`` is REFERENCE, not a fork.

The census count is printed as measured. A copy is not dropped to keep a
previous number.
"""
import argparse
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FLAGSHIP = "checks/differ.py"
# The 1755e2338 reading. A comparison point, not a filter: if the census moves,
# the new count is printed and every file is still classified.
PRIOR = 85
PASS_MEANS = "these are old copies, not a drifted flagship"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git_run(args, cwd=None, inp=None):
    """git, without ``GIT_INDEX_FILE``. History is the object store, not an index."""
    env = os.environ.copy()
    env.pop("GIT_INDEX_FILE", None)
    return subprocess.run(
        ["git", *args], cwd=cwd or ROOT, capture_output=True, input=inp, env=env)


def git_text(args, cwd=None):
    got = git_run(args, cwd)
    return got.returncode, got.stdout.decode(errors="replace"), got.stderr.decode(errors="replace")


def differ_running():
    """-> process lines whose args name ``differ.py``, grep excluded. A hit means
    ``runs/graphcmp/`` may be mid-write. This gate does not read it either way."""
    got = subprocess.run(["ps", "-Ao", "pid,args"], capture_output=True, text=True)
    return [ln.strip() for ln in got.stdout.splitlines()
            if "differ.py" in ln and "grep" not in ln.split()]


def corpus_of(pop, root, scratch):
    """The census's own walk. Scratch has no git tree, so it is not intersected
    with ``ls-tree``; the live tree is, which is the bound ``pincensus-pop.load`` uses.
    ``__undecodable__`` is a count the walker stashes in the dict, not a file."""
    if scratch:
        disk = pop.walk_text(root)
        disk.pop("__undecodable__", None)
        return disk, {t: pop.host_of(v) for t, v in disk.items()}
    loaded = pop.load(root)
    return loaded["corpus"], pop.hosts(loaded["corpus"])


def rows_of(root, scratch=False):
    """-> expectation rows, currency included.

    THE MODULES ARE LOADED BY PATH, and the class is theirs: ``expectations``
    drops a hex value, ``resolve`` joins a table to its artifact, and
    ``expectation_currency`` is what says NO-SUBJECT-DECLARED. This function does
    not execute the defining modules. Executing ``checks/differ.py`` is running
    it, and the currency of a missing subject does not depend on that
    execution -- it depends on the binding the file already contains.
    """
    pop = load("expectcopy_pop", "pincensus-pop.py")
    tab = load("expectcopy_tab", "pintable-pop.py")
    bind = load("expectcopy_bind", "bind-subject.py")
    pc = load("expectcopy_pc", "pincensus-gate.py")
    corpus, host = corpus_of(pop, root, scratch)
    code = {t: pop.code_lines(corpus[t], host[t]) for t in corpus if host.get(t) != "prose"}
    decls = bind.declarations(corpus, code)
    empty = {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}}
    exps = tab.expectations(tab.tables(tab.bindings(corpus, host), pop.PIN_NAME), pop.HEX)
    rows = []
    for exp in exps:
        decl = decls.get(exp["file"], empty)
        resolved = bind.resolve(exp["name"], decl)
        subject = pc.expectation_subject(resolved, decl, exp["key"])
        verdict = pc.expectation_currency(exp["value"], subject, root, root)[0]
        rows.append({"file": exp["file"], "name": exp["name"], "key": exp["key"],
                     "currency": verdict})
    return rows


def flagship_history(repo=ROOT):
    """blob -> commits whose ``checks/differ.py`` equals that blob.

    ``git log --all -- <path>`` is the path index. A commit that touches the
    path and does not contain it is not a match. HEAD is recorded and is not
    a historical match.
    """
    rc, out, err = git_text(["log", "--all", "--pretty=format:%H", "--", FLAGSHIP], repo)
    if rc != 0:
        return None, "git log --all -- checks/differ.py failed: " + err.strip()
    rc, head, err = git_text(["rev-parse", "HEAD"], repo)
    if rc != 0:
        return None, "HEAD did not resolve: " + err.strip()
    rc, head_blob, err = git_text(["rev-parse", f"HEAD:{FLAGSHIP}"], repo)
    if rc != 0:
        return None, f"HEAD:{FLAGSHIP} did not resolve: " + err.strip()
    by, order = {}, []
    for commit in out.split():
        if commit in order:
            continue
        order.append(commit)
        rc, blob, _err = git_text(["rev-parse", "--verify", f"{commit}:{FLAGSHIP}"], repo)
        if rc != 0:
            continue
        by.setdefault(blob.strip(), []).append(commit)
    return {
        "by": by,
        "order": order,
        "head": head.strip(),
        "head-blob": head_blob.strip(),
        "asked": "git log --all -- checks/differ.py",
        "asked-at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }, None


def file_blob(path):
    rc, out, _err = git_text(["hash-object", "--", path])
    return out.strip() if rc == 0 and out.strip() else None


def under_plant(rel):
    return "plant" in rel.replace("\\", "/").split("/")


def classify(rows, root, history):
    """-> the copy set. The flagship is removed before any file is judged, so
    it cannot be classed as a copy of itself. History is this repo's, not ``root``'s:
    a scratch tree has no commits."""
    nosub = [r for r in rows if r["currency"] == "NO-SUBJECT-DECLARED"]
    by = {}
    for row in nosub:
        by[row["file"]] = by.get(row["file"], 0) + 1
    ref_rows = by.pop(FLAGSHIP, 0)
    result = {
        "rows": rows, "nosubject": len(nosub), "by": by, "reference": FLAGSHIP,
        "reference-rows": ref_rows, "reference-class": "REFERENCE", "copies": [],
        "refused": None, "head": None, "head-blob": None,
        "asked": "git log --all -- checks/differ.py", "asked-at": None,
    }
    if history is None:
        result["refused"] = "flagship history was not read, so a copy cannot be classed"
        return result
    result["head"] = history["head"]
    result["head-blob"] = history["head-blob"]
    result["asked"] = history["asked"]
    result["asked-at"] = history["asked-at"]
    ref_path = os.path.join(root, FLAGSHIP)
    if not os.path.isfile(ref_path):
        result["refused"] = f"{FLAGSHIP} is absent, so a copy cannot be compared to it"
        return result
    ref_blob = file_blob(ref_path)
    result["reference-blob"] = ref_blob
    if ref_blob != history["head-blob"]:
        result["refused"] = (
            f"worktree {FLAGSHIP} blob {ref_blob} != HEAD:{FLAGSHIP} {history['head-blob']}")
        return result
    pending = []
    for rel, n in sorted(by.items()):
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            pending.append({"path": rel, "rows": n, "kind": "ABSENT", "blob": None,
                            "commit": "NO-COMMIT", "matches": 0, "note": "absent"})
            continue
        blob = file_blob(path)
        if blob is None:
            result["refused"] = f"git hash-object failed for {rel}"
            return result
        pending.append({"path": rel, "rows": n, "blob": blob})
    plant_groups = {}
    for item in pending:
        if item.get("kind") == "ABSENT" or not under_plant(item["path"]):
            continue
        plant_groups.setdefault(item["blob"], []).append(item["path"])
    copies = []
    for item in pending:
        if item.get("kind") == "ABSENT":
            copies.append(item)
            continue
        blob = item["blob"]
        commits = [c for c in history["by"].get(blob, []) if c != history["head"]]
        commit = commits[0] if commits else None
        grouped = plant_groups.get(blob, [])
        in_pair = item["path"] in grouped and len(grouped) >= 2
        others = [p for p in grouped if p != item["path"]]
        item["commit"] = commit or "NO-COMMIT"
        item["commits"] = commits
        item["matches"] = len(commits)
        if blob == history["head-blob"]:
            item["kind"] = "CURRENT"
            item["note"] = "byte-identical to HEAD:checks/differ.py; a second current table"
        elif in_pair and commit:
            item["kind"] = "PLANT-PAIR"
            item["note"] = "one pair with " + ", ".join(others) + "; not an independent fork"
        elif in_pair:
            item["kind"] = "LIVE-FORK"
            item["note"] = "one pair, not two drifts; blob equals no historical checks/differ.py"
        elif commit:
            item["kind"] = "HISTORICAL"
            item["note"] = "equals checks/differ.py at a commit that is not HEAD"
        else:
            item["kind"] = "LIVE-FORK"
            item["note"] = "blob equals no historical checks/differ.py"
        copies.append(item)
    result["copies"] = copies
    accounted = ref_rows + sum(c["rows"] for c in copies)
    if accounted != len(nosub):
        result["refused"] = f"accounting {accounted} != NO-SUBJECT-DECLARED {len(nosub)}"
    return result


def exit_of(result):
    if result.get("refused"):
        return REFUSED
    if not result["rows"]:
        return DEAD
    if result["reference-class"] != "REFERENCE":
        return FAIL
    if any(c["path"] == FLAGSHIP for c in result["copies"]):
        return FAIL
    kinds = [c["kind"] for c in result["copies"]]
    if not kinds:
        return REFUSED
    head_blob = result.get("head-blob")
    if any(c.get("blob") == head_blob for c in result["copies"]):
        return FAIL
    if any(k in ("LIVE-FORK", "CURRENT", "ABSENT") for k in kinds):
        return FAIL
    if all(k in ("HISTORICAL", "PLANT-PAIR") for k in kinds):
        return PASS
    return FAIL


def _counts(copies):
    kinds = {}
    for copy in copies:
        kinds[copy["kind"]] = kinds.get(copy["kind"], 0) + 1
    pair_blobs = {c["blob"] for c in copies if c["kind"] == "PLANT-PAIR"}
    live_blobs = {c["blob"] for c in copies if c["kind"] == "LIVE-FORK"}
    return kinds, pair_blobs, live_blobs


def fail_why(result):
    why = []
    if result["reference-class"] != "REFERENCE" or any(
            c["path"] == FLAGSHIP for c in result["copies"]):
        why.append("a copy is presented as the flagship")
    if any(c.get("blob") == result.get("head-blob") for c in result["copies"]):
        why.append("a copy is byte-identical to HEAD:checks/differ.py")
    if any(c["kind"] == "LIVE-FORK" for c in result["copies"]):
        why.append("a LIVE-FORK remains")
    if any(c["kind"] == "ABSENT" for c in result["copies"]):
        why.append("an absent path is in the set")
    if any(c["kind"] == "CURRENT" for c in result["copies"]):
        why.append("a second current table is in the set")
    return why or ["a copy is not HISTORICAL or PLANT-PAIR"]


def report(result, out, live=None):
    n = result["nosubject"]
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    out.write(f"expectcopy-gate: NO-SUBJECT-DECLARED rows={n}")
    if n != PRIOR:
        out.write(f" (moved from {PRIOR}; not dropped to keep {PRIOR})\n")
    else:
        out.write(f" (did not move from {PRIOR})\n")
    out.write(f"  generated {stamp}\n")
    out.write(f"  asked: {result.get('asked')} at {result.get('asked-at') or stamp}\n")
    out.write(f"  then: git rev-parse <commit>:{FLAGSHIP}\n")
    if live is not None:
        out.write(f"  differ.py running: {'yes ' + live[0] if live else 'no'}\n")
    out.write(f"  REFERENCE {result['reference']} rows={result['reference-rows']} "
              f"class={result['reference-class']} blob={result.get('head-blob')} "
              f"commit={result.get('head')} (not a fork)\n")
    if result.get("refused"):
        out.write(f"  REFUSED: {result['refused']}\n")
    for copy in result["copies"]:
        commits = copy.get("commits") or []
        also = ",".join(c for c in commits if c != copy.get("commit"))
        out.write(f"  {copy['kind']:12} {copy['path']} rows={copy['rows']} "
                  f"blob={copy.get('blob') or '-'} commit={copy.get('commit')} "
                  f"matches={copy.get('matches', 0)}"
                  + (f" also={also}" if also else "")
                  + f" {copy['note']}\n")
    kinds, pair_blobs, live_blobs = _counts(result["copies"])
    out.write(f"  historical={kinds.get('HISTORICAL', 0)} "
              f"plant-pairs={len(pair_blobs)} "
              f"plant-pair-files={kinds.get('PLANT-PAIR', 0)} "
              f"live-forks={len(live_blobs)} "
              f"live-fork-files={kinds.get('LIVE-FORK', 0)} "
              f"current={kinds.get('CURRENT', 0)} absent={kinds.get('ABSENT', 0)}\n")
    code = exit_of(result)
    if code == PASS:
        out.write(f"  PASS: {PASS_MEANS}\n")
    elif code == FAIL:
        out.write(f"  FAIL: {'; '.join(fail_why(result))}. PASS would mean {PASS_MEANS}.\n")
    elif code == DEAD:
        out.write("  DEAD: the expectation population emitted no rows\n")
    elif code == REFUSED:
        out.write("  REFUSED: the copy comparison was not made\n")
    out.write(f"expectcopy-gate: exit {code} ({VERDICT[code]})\n")
    return code


def _write(root, rel, raw):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(raw)
    return path


def _kind(result, rel):
    got = [c for c in result["copies"] if c["path"] == rel]
    return got[0] if len(got) == 1 else None


def ancestor_example(history):
    """-> (blob, commit, bytes) of an ancestor's ``checks/differ.py``, not HEAD's blob."""
    for commit in history["order"]:
        if commit == history["head"]:
            continue
        rc, _out, _err = git_text(["merge-base", "--is-ancestor", commit, history["head"]])
        if rc != 0:
            continue
        rc, blob, _err = git_text(["rev-parse", f"{commit}:{FLAGSHIP}"])
        if rc != 0:
            continue
        blob = blob.strip()
        if blob == history["head-blob"]:
            continue
        raw = git_run(["cat-file", "blob", blob])
        if raw.returncode != 0 or not raw.stdout:
            continue
        return blob, commit, raw.stdout
    return None, None, None


def _seen(rows, rel):
    return any(r["file"] == rel and r["currency"] == "NO-SUBJECT-DECLARED" for r in rows)


def plant():
    """Attack copies. The live flagship is opened for reading and never written.

    HISTORICAL  a file whose blob equals an ancestor's ``checks/differ.py``.
    LIVE-FORK   that file plus one byte. FAIL, and not reclassed HISTORICAL.
    PLANT-PAIR  two identical copies of the ancestor under ``plant/``. One pair.
    PAIR-DRIFT  two identical copies of the extra byte under ``plant/``. One
                LIVE-FORK, not a pair that passes.
    CURRENT     a copy of ``HEAD:checks/differ.py``. FAIL, a second current table.
    CONTROL     the flagship is REFERENCE, and it is not in the copy set.
    """
    live_path = os.path.join(ROOT, FLAGSHIP)
    before = open(live_path, "rb").read()
    history, err = flagship_history(ROOT)
    if history is None:
        print(f"expectcopy-plant: REFUSED -- {err}", file=sys.stderr)
        return REFUSED
    ancestor_blob, ancestor_commit, ancestor = ancestor_example(history)
    if ancestor is None or file_blob(live_path) != history["head-blob"]:
        print("expectcopy-plant: DEAD -- no ancestor blob distinct from HEAD", file=sys.stderr)
        return DEAD
    extra = ancestor + b"\n"
    extra_blob = git_run(["hash-object", "--stdin"], inp=extra)
    if extra_blob.returncode != 0:
        print("expectcopy-plant: DEAD -- extra byte did not hash", file=sys.stderr)
        return DEAD
    extra_blob = extra_blob.stdout.decode().strip()
    if extra_blob in history["by"] or extra_blob == history["head-blob"] or len(extra) != len(ancestor) + 1:
        print("expectcopy-plant: DEAD -- one extra byte was not a new blob", file=sys.stderr)
        return DEAD
    head_raw = git_run(["cat-file", "blob", history["head-blob"]]).stdout
    if head_raw != before:
        print("expectcopy-plant: DEAD -- HEAD blob != worktree flagship", file=sys.stderr)
        return DEAD
    hist_rel = os.path.join(".agents", "slop", "copy", "checks", "differ.py")
    fork_rel = os.path.join(".agents", "slop", "copy", "checks", "differ_extra.py")
    pair_a = os.path.join(".agents", "slop", "plant", "broken", "checks", "differ.py")
    pair_b = os.path.join(".agents", "slop", "plant", "real", "checks", "differ.py")
    drift_a = os.path.join(".agents", "slop", "plant", "left", "checks", "differ.py")
    drift_b = os.path.join(".agents", "slop", "plant", "right", "checks", "differ.py")
    current_rel = os.path.join(".agents", "slop", "copy", "checks", "differ_head.py")
    base = tempfile.mkdtemp(prefix="expectcopy-plant-")
    try:
        names = ("historical", "livefork", "pair", "drift", "current", "control")
        roots = {name: os.path.join(base, name) for name in names}
        for dest in roots.values():
            _write(dest, FLAGSHIP, head_raw)
        _write(roots["historical"], hist_rel, ancestor)
        _write(roots["livefork"], fork_rel, extra)
        _write(roots["pair"], pair_a, ancestor)
        _write(roots["pair"], pair_b, ancestor)
        _write(roots["drift"], drift_a, extra)
        _write(roots["drift"], drift_b, extra)
        _write(roots["current"], current_rel, head_raw)
        rows = {name: rows_of(dest, scratch=True) for name, dest in roots.items()}
        judged = {name: classify(rows[name], roots[name], history) for name in names}
        bad = []
        after = open(live_path, "rb").read()
        if after != before:
            bad.append("the live flagship changed")
        if not _seen(rows["historical"], FLAGSHIP):
            bad.append("VACUOUS: the flagship was not NO-SUBJECT-DECLARED in the input")
        if not _seen(rows["historical"], hist_rel):
            bad.append("the ancestor copy left the population, so HISTORICAL compared nothing")
        if not _seen(rows["livefork"], fork_rel):
            bad.append("the extra-byte copy left the population, so LIVE-FORK compared nothing")
        if not _seen(rows["pair"], pair_a) or not _seen(rows["pair"], pair_b):
            bad.append("a plant copy left the population, so the pair compared nothing")
        if not _seen(rows["drift"], drift_a) or not _seen(rows["drift"], drift_b):
            bad.append("a drifted plant copy left the population, so the pair-drift compared nothing")
        if not _seen(rows["current"], current_rel):
            bad.append("the HEAD copy left the population, so CURRENT compared nothing")
        for label, result in judged.items():
            if any(copy["path"] == FLAGSHIP for copy in result["copies"]):
                bad.append(f"{label}: {FLAGSHIP} was classed as a copy")
            if result["reference-class"] != "REFERENCE":
                bad.append(f"{label}: the flagship class is {result['reference-class']}")
        hist = _kind(judged["historical"], hist_rel)
        fork = _kind(judged["livefork"], fork_rel)
        left = _kind(judged["pair"], pair_a)
        right = _kind(judged["pair"], pair_b)
        dleft = _kind(judged["drift"], drift_a)
        dright = _kind(judged["drift"], drift_b)
        current = _kind(judged["current"], current_rel)
        if hist is None or hist["kind"] != "HISTORICAL" or exit_of(judged["historical"]) != PASS:
            bad.append(f"HISTORICAL did not fire ({None if hist is None else hist['kind']}, "
                       f"exit {exit_of(judged['historical'])})")
        elif hist["commit"] in ("NO-COMMIT", history["head"]):
            bad.append(f"HISTORICAL named {hist['commit']}")
        else:
            rc, named, _err = git_text(["rev-parse", f"{hist['commit']}:{FLAGSHIP}"])
            if rc != 0 or named.strip() != ancestor_blob:
                bad.append("HISTORICAL named a commit whose checks/differ.py is a different blob")
        if fork is None or fork["kind"] != "LIVE-FORK" or fork["commit"] != "NO-COMMIT":
            bad.append(f"LIVE-FORK did not fire ({None if fork is None else fork['kind']}, "
                       f"commit {None if fork is None else fork['commit']})")
        if exit_of(judged["livefork"]) != FAIL:
            bad.append(f"LIVE-FORK exited {exit_of(judged['livefork'])}")
        if fork is not None and fork["kind"] == "HISTORICAL":
            bad.append("one extra byte was classed HISTORICAL")
        pair_kinds = {None if left is None else left["kind"], None if right is None else right["kind"]}
        pair_blobs = {c["blob"] for c in judged["pair"]["copies"] if c["kind"] == "PLANT-PAIR"}
        if pair_kinds != {"PLANT-PAIR"} or len(pair_blobs) != 1 or exit_of(judged["pair"]) != PASS:
            bad.append(f"PLANT-PAIR did not fire ({pair_kinds}, pairs={len(pair_blobs)}, "
                       f"exit {exit_of(judged['pair'])})")
        if any(c["kind"] in ("LIVE-FORK", "HISTORICAL") for c in judged["pair"]["copies"]):
            bad.append("the pair was counted as two drifts or two independent forks")
        drift_kinds = {None if dleft is None else dleft["kind"],
                       None if dright is None else dright["kind"]}
        drift_blobs = {c["blob"] for c in judged["drift"]["copies"] if c["kind"] == "LIVE-FORK"}
        if drift_kinds != {"LIVE-FORK"} or len(drift_blobs) != 1 or exit_of(judged["drift"]) != FAIL:
            bad.append(f"PAIR-DRIFT did not fire ({drift_kinds}, live-forks={len(drift_blobs)}, "
                       f"exit {exit_of(judged['drift'])})")
        if any(c["kind"] == "PLANT-PAIR" for c in judged["drift"]["copies"]):
            bad.append("a drifted pair was classed PLANT-PAIR and would have passed")
        if current is None or current["kind"] != "CURRENT" or exit_of(judged["current"]) != FAIL:
            bad.append(f"CURRENT did not fire ({None if current is None else current['kind']}, "
                       f"exit {exit_of(judged['current'])})")
        if judged["control"]["copies"]:
            bad.append(f"CONTROL had copies: {judged['control']['copies']}")
        if exit_of(judged["historical"]) == exit_of(judged["livefork"]):
            bad.append("VACUOUS: historical and live-fork exited the same")
        buf = io.StringIO()
        report(judged["historical"], buf)
        if f"PASS: {PASS_MEANS}" not in buf.getvalue():
            bad.append("the PASS line does not say these are old copies, not a drifted flagship")
        print(f"expectcopy-plant: ancestor {ancestor_commit} blob {ancestor_blob}")
        print(f"  HISTORICAL kind={None if hist is None else hist['kind']} "
              f"commit={None if hist is None else hist['commit']} "
              f"exit={exit_of(judged['historical'])} ({VERDICT[exit_of(judged['historical'])]})")
        print(f"  LIVE-FORK  kind={None if fork is None else fork['kind']} "
              f"commit={None if fork is None else fork['commit']} "
              f"exit={exit_of(judged['livefork'])} ({VERDICT[exit_of(judged['livefork'])]}) "
              f"one extra byte blob {extra_blob}")
        print(f"  PLANT-PAIR files=2 pairs={len(pair_blobs)} kinds={pair_kinds} "
              f"exit={exit_of(judged['pair'])} ({VERDICT[exit_of(judged['pair'])]})")
        print(f"  PAIR-DRIFT files=2 live-forks={len(drift_blobs)} kinds={drift_kinds} "
              f"exit={exit_of(judged['drift'])} ({VERDICT[exit_of(judged['drift'])]})")
        print(f"  CURRENT    kind={None if current is None else current['kind']} "
              f"exit={exit_of(judged['current'])} ({VERDICT[exit_of(judged['current'])]})")
        print(f"  CONTROL    class={judged['control']['reference-class']} "
              f"in-copies={any(c['path'] == FLAGSHIP for c in judged['control']['copies'])} "
              f"copies={len(judged['control']['copies'])}")
        print("  live flagship: untouched" if after == before else "  live flagship: CHANGED")
        if bad:
            print("expectcopy-plant: FAIL -- " + "; ".join(bad), file=sys.stderr)
            return FAIL
        print("expectcopy-plant: an ancestor blob is HISTORICAL, one extra byte is LIVE-FORK, "
              "two identical plant files are one pair, and the flagship is REFERENCE")
        return PASS
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--scratch", action="store_true")
    ap.add_argument("--plant", action="store_true")
    args = ap.parse_args(argv)
    if args.plant:
        return plant()
    history, err = flagship_history(ROOT)
    live = differ_running()
    rows = rows_of(args.root, scratch=args.scratch)
    if history is None:
        nosub = [r for r in rows if r["currency"] == "NO-SUBJECT-DECLARED"]
        result = {
            "rows": rows, "nosubject": len(nosub), "copies": [], "reference": FLAGSHIP,
            "reference-rows": sum(1 for r in nosub if r["file"] == FLAGSHIP),
            "reference-class": "REFERENCE", "refused": err, "head": None, "head-blob": None,
            "asked": "git log --all -- checks/differ.py", "asked-at": None,
        }
        return report(result, sys.stdout, live=live)
    return report(classify(rows, args.root, history), sys.stdout, live=live)


if __name__ == "__main__":
    sys.exit(main())
