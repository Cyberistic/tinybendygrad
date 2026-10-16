#!/usr/bin/env python3
"""plant-stat.py -- THE DECISIVE PLANT: AN INDEX ENTRY WITH THE EMPTY BLOB AND A *MATCHING STAT*.

plant-truncate.py answered "no" for a reason that does not apply here: `git update-index
--cacheinfo` also ZEROES the cached stat, so git saw a stat mismatch, re-read the worktree, and
re-staged the real bytes. The 11 paths on this tree are the other thing: `git ls-files --debug`
reads `size: 33208` next to `blob e69de29b`, i.e. git's stat cache says "this entry matches the
worktree" while the SHA says the file is empty. That is the state jj leaves behind and it cannot
be produced by a git command -- `git update-index` cannot set a SHA and keep a stat.

So forge it at the byte level: `git add` the file, then overwrite the 20 SHA bytes in place and
leave every other byte of the entry -- including the stat cache -- untouched. Then bare-commit.

A control that cannot distinguish is not a control, so A must come back PASS.
"""
import subprocess, shutil, tempfile, struct, hashlib, importlib.util, sys
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "checks_index_arm_gate",
    str(Path(__file__).resolve().parents[3] / "checks" / "index-arm-gate.py"))  # armclass/slop/.agents/repo
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

EMPTY_SHA = bytes.fromhex("e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
def G(*a, cwd):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True)


def patch_index_sha(idx_path: Path, target: str, sha: bytes) -> bytes:
    """Replace ONE entry's 20-byte SHA in .git/index, leaving mode, size, mtime and every
    checksum untouched except the trailing one, which is recomputed. Returns the bytes changed."""
    raw = bytearray(idx_path.read_bytes())
    n = struct.unpack(">I", raw[8:12])[0]
    mine = [name for name, _ in _entries(raw)]
    theirs = [ln for ln in G("ls-files", "-z", cwd=idx_path.parent).stdout.split("\0") if ln]
    assert sorted(mine) == sorted(theirs), f"index parser disagrees with git: {set(mine) ^ set(theirs)}"
    assert len(mine) == n, f"parsed {len(mine)} of {n} entries"
    for name, off in _entries(raw):
        if name == target:
            raw[off:off + 20] = sha          # `off` IS the sha offset; do not add 40 again
            idx_path.write_bytes(bytes(raw))
            _restamp(raw, idx_path)
            return bytes(raw[off:off + 20])
    raise SystemExit(f"entry not found: {target}")


def _entries(raw):
    """Yield (name, sha_offset) per entry. v2 layout:
    10 x u32 = 40 bytes of stat+mode, then the 20-byte SHA, then 2-byte flags, then the
    NUL-terminated name padded so that (len(name)+1) is a multiple of 8."""
    assert raw[:4] == b"DIRC"
    ver = struct.unpack(">I", raw[4:8])[0]
    n = struct.unpack(">I", raw[8:12])[0]
    assert ver in (2, 3), f"index v{ver} (v4 is prefix-compressed); not produced by git 2.50 here"
    p = 12
    for _ in range(n):
        start = p
        p += 40                      # stat + mode
        sha_off = p
        p += 20                      # SHA-1
        flags = struct.unpack(">H", raw[p:p + 2])[0]
        p += 2
        if ver >= 3 and flags & 0x4000:
            p += 2                   # extended flags word
        nul = raw.index(b"\0", p)
        name = raw[p:nul].decode()
        yield name, sha_off
        # entry = 40 stat + 20 sha + 2 flags + name + NUL = 63+len(name), rounded UP to a
        # multiple of 8. Round-up is `& ~7`, NOT `& ~8` -- the latter CLEARS bit 3 and is wrong.
        p = start + (((63 + len(name)) + 7) & ~7)
    # Extensions (TREE, REUC, ...) follow the entries, so p is not the end of the file. Prove the
    # parse instead by comparing the names it found against `git ls-files`, the real authority.
    return


def _restamp(raw, idx_path: Path):
    """The index trailer is a 20-byte SHA-1 of everything before it. Writing a 4-byte CRC there
    makes git reject the file and silently rebuild it from the worktree -- which is how a broken
    patch reads as a clean success."""
    body = bytes(raw[:-20])
    idx_path.write_bytes(body + hashlib.sha1(body).digest())


d = Path(tempfile.mkdtemp(prefix="statplant-"))
try:
    a = d / "A"
    a.mkdir()
    for argv in (["init", "-q", "-b", "main"], ["config", "user.email", "t@t"], ["config", "user.name", "t"]):
        G(*argv, cwd=a)
    (a / "keep.py").write_text("REAL = 1\n" * 900)
    (a / "gone.py").write_text("BYE = 2\n" * 50)
    G("add", "-A", cwd=a)
    G("commit", "-q", "-m", "seed", cwd=a)
    print(f"A seed: keep.py HEAD {G('rev-parse','HEAD:keep.py',cwd=a).stdout.strip()[:12]} "
          f"gone.py HEAD {G('rev-parse','HEAD:gone.py',cwd=a).stdout.strip()[:12]}")

    s = d / "S"
    shutil.copytree(a, s)
    G("add", "-A", cwd=s)   # index re-staged from disk: real SHA, REAL stat
    # The empty blob must EXIST for the experiment to mean anything: git resolves index entries
    # against the object database and "invalid object" would be a missing-object answer wearing a
    # commit's clothes. This tree already holds it (541 empty-blob paths are in HEAD), so writing
    # it here is what makes the plant faithful rather than a test of absence.
    wrote = G("hash-object", "-w", "--", "/dev/null", cwd=s)
    print(f"S empty blob present in the object db: {wrote.stdout.strip()} "
          f"(is the empty blob: {wrote.stdout.strip() == EMPTY_SHA.hex()})")
    idx = s / ".git" / "index"
    patch_index_sha(idx, "keep.py", EMPTY_SHA)
    dbg = G("ls-files", "--debug", "--", "keep.py", cwd=s).stdout
    print("S ls-files --debug after the byte patch:")
    print("   " + "\n   ".join(ln.strip() for ln in dbg.splitlines() if ln.strip()))
    print(f"S ls-files -s : {G('ls-files','-s','--','keep.py',cwd=s).stdout.strip()}")
    print(f"S worktree on disk: {len((s/'keep.py').read_bytes())} bytes")

    # A shape the gate does not NAME is a claim nobody measured. Point the real gate at the clean A
    # and at S AS FORGED -- before the bare commit, because the commit is what makes S agree with
    # HEAD again, and running the gate afterwards would measure a repaired index and call it PASS.
    print("\n--- the real gate, run on A (clean) ---")
    ra, _ = gate.report(a, None)
    print("--- the real gate, run on S (forged empty-blob entry, pre-commit) ---")
    rs, cs = gate.report(s, None)

    r = G("commit", "-q", "-m", "bare", cwd=s)
    after = G("rev-parse", "HEAD:keep.py", cwd=s).stdout.strip()
    print(f"\nS bare `git commit` rc={r.returncode} stderr={r.stderr.strip()[:120]!r}")
    print(f"S HEAD:keep.py after = {after[:12]}  IS EMPTY BLOB = {after == EMPTY_SHA.hex()}")
    print(f"S worktree after      = {len((s/'keep.py').read_bytes())} bytes on disk")
    print(f"S log   = {G('log','--oneline',cwd=s).stdout.strip()}")

    print(f"\nPLANT gate verdict A={gate.VERDICT.get(ra, ra)} (want PASS=0)  "
          f"S={gate.VERDICT.get(rs, rs)} (want REFUSED=3)")
    print(f"PLANT gate EMPTIED on S = {cs.get('EMPTIED')}")
    print(f"PLANT bare commit wrote the empty blob = {after == EMPTY_SHA.hex()}")
    ok = (ra == gate.PASS and rs == gate.REFUSED
          and cs.get("EMPTIED") == ["keep.py"] and after == EMPTY_SHA.hex())
    print("PLANT " + ("OK: the gate names the shape, A did not soften, and the shape is real."
                      if ok else "FAILED: the shape is unmeasured or A regressed."))
    sys.exit(0 if ok else 1)
finally:
    shutil.rmtree(d, ignore_errors=True)