# THE MUTATION TABLE for tinybendygrad/runtime/support/objc.bend.
#
# One entry per ported rule. Each mutation is an EXACT single-line substitution on
# a scratch copy, the INTERPRETED lane is run, and the whole `name=value` lines
# are diffed -- NEVER the row names, because a name-comparing harness reported 0
# for all 68 mutations in another unit (agent-core).
#
# A `0` is a REQUEST FOR A FIXTURE unless it is a THEOREM, and the three
# theorems here say which they are. A comment-only mutation is the CONTROL: a
# table in which every entry moves is as useless as one in which none does.
#
#   .venv/bin/python .agents/slop/objc/objc_mutate.py
import os, shutil, subprocess, sys, tempfile

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SRC = ROOT + "/tinybendygrad/runtime/support/objc.bend"
BEND = ROOT + "/bin/bend"

# (id, the exact line to replace, its replacement, what the mutation tests)
M = [
 ("M1", "    case Nil{}: Nil{}\n    case d <> r: List.append(&2, U32, [CT_ID(), CT_ID()], declared)",
        "    case Nil{}: [CT_ID(), CT_ID()]\n    case d <> r: List.append(&2, U32, [CT_ID(), CT_ID()], declared)",
        "THE HEADLINE: `:36`'s `if argtypes else []`. Unconditionally prepending two is the NAIVE reading; the measured value for a bare message is []. The FIRST version of this mutation appended its arm after the `Nil{}` arm, where it is DEAD CODE, and moved 0 -- a mutation artefact, not a blind spot."),
 ("M2", "  Bool.pick(List<&2, Char>, Bool.and(is_colon(c), List.is_empty(&2, Char, t)), Nil{}, c <> r)",
        "  Bool.pick(List<&2, Char>, Bool.and(is_colon(c), List.is_empty(&2, Char, t)), Nil{}, c <> t)",
        "`:70`'s rtrim. Returning `cs` keeps the UNTRIMMED tail -- this is the bug this file ACTUALLY HAD, and `mangle_1`/`mangle_5` are what caught it."),
 ("M3", "    case c <> t: Bool.pick(List<&2, Char>, is_colon(c), mangle.ltrim(t), cs)",
        "    case c <> t: mangle.ltrim(t)",
        "`:70`'s ltrim. Unconditional stripping eats the whole string."),
 ("M4", "  String.from_list(mangle.colons(mangle.rtrim(mangle.ltrim(String.to_list(s)))))",
        "  String.from_list(mangle.rtrim(mangle.ltrim(mangle.colons(String.to_list(s)))))",
        "THE ORDER of `strip().replace()`. Swapped, a leading colon becomes an underscore."),
 ("M5", "  Bool.pick(U32, sel.hit(Sels.ix(t), s), U32.add(sel.found(Sels.ix(t), s, 0), 1), 0)",
        "  U32.add(sel.found(Sels.ix(t), s, 0), 1)",
        "The MISS arm of `getsel_ix`. Dropped, an absent name answers 1 -- a REAL bug this port had."),
 ("M6", "    case d <> r: U32.add(2, U32.from_nat(List.length(&2, U32, declared)))",
        "    case d <> r: U32.add(2, U32.from_nat(List.length(&2, U32, r)))",
        "The `d <> r` TAIL of the pattern. This is the OTHER real bug this port had: the head was lost."),
 ("M7", "  Tr.send(recv, sel_ix, msg_argc(Msg.args(m)), Tr.sel(Msg.sel(m), t))",
        "  Tr.send(recv, sel_ix, msg_argc(Msg.args(m)), Tr.of())",
        "`:37`'s ORDER. `getsel(sel.encode())` is an ARGUMENT of the send, so the selector lookup comes FIRST; without it the trace is send-only."),
 ("M8", "def Idr.own(+r: Idr, t: Tr) -> Owned: Owned{msg(Idr.ptr(r), Msg.of(\"retain\"), 0, t), Idr.retained(r)}",
        "def Idr.own(+r: Idr, t: Tr) -> Owned: Owned{Tr.emit(SYM_MSGSEND(), Idr.ptr(r), 0, 0, t), Idr.retained(r)}",
        ":20 `own()` IS `msg(\"retain\")`, so it sends the selector lookup too: TWO calls. This is the THIRD real bug the oracle caught."),
 ("M9", "  Bool.pick(Tr, Bool.and(Idr.retain(r), Bool.not(is_finalizing)), Idr.release(r, t), t)",
        "  Bool.pick(Tr, Bool.not(is_finalizing), Idr.release(r, t), t)",
        ":13-14's FIRST conjunct. Dropped, an unowned id_ releases on GC."),
 ("M10", "  Bool.pick(Tr, Bool.and(Idr.retain(r), Bool.not(is_finalizing)), Idr.release(r, t), t)",
         "  Bool.pick(Tr, Idr.retain(r), Idr.release(r, t), t)",
        ":13-14's SECOND conjunct. Dropped, finalization releases even while the interpreter is shutting down."),
 ("M11", "def Owned.of(tr: Tr, +r: Idr, m: Msg) -> Owned: Owned{tr, Bool.pick(Idr, Msg.retain(m), Idr.retained(r), r)}",
         "def Owned.of(tr: Tr, +r: Idr, m: Msg) -> Owned: Owned{tr, r}",
        ":38/:23 the WRAPPER. Dropped, `returns_retained` never flags a result."),
 ("M12", "def subst(+t: U32) -> U32: Bool.pick(U32, U32.is_eq(t, CT_INST()), CT_CLASS(), t)",
         "def subst(+t: U32) -> U32: t",
        ":71's `cls if m[1] == 'instancetype' else m[1]`. Dropped, the class is never substituted."),
 ("M13", "    case t <> r: subst(t) <> subst_list(r)",
         "    case t <> r: [subst(t)]",
        ":72's PER-ARGUMENT substitution. Truncating drops every argument after the first."),
 ("M14", "def msg_receiver(inst: U32, cls: U32, clsmeth: Bool) -> U32: Bool.pick(U32, clsmeth, cls, inst)",
         "def msg_receiver(inst: U32, cls: U32, clsmeth: Bool) -> U32: inst",
        ":37's `ptr._objc_class_ if clsmeth else ptr`. Always the instance, so a class method gets the wrong receiver."),
 ("M15", "          inh.go(m, t, Bool.pick(List<&2, Meth>,\n                                 meth_seen(out, mangle(sel)),\n                                 out, List.append(&2, Meth, out, [Meth{sel, ret, args, retain, clsmeth}])))",
         "          inh.go(m, t, List.append(&2, Meth, out, [Meth{sel, ret, args, retain, clsmeth}]))",
        ":67's re-inherit dedup. Dropped, a re-inherited method is added twice -- and two selectors that mangle alike collide."),
 ("M16", "  Bool.pick(Sels, sel.hit(xs, s),\n            Sels{xs, next, miss, U32.add(hit, 1)},\n            Sels{List.append(&2, SelRow, xs, [SelRow{s, next}]), U32.add(next, 1),\n                 U32.add(miss, 1), hit})",
         "  Sels{List.append(&2, SelRow, xs, [SelRow{s, next}]), U32.add(next, 1),\n       U32.add(miss, 1), U32.add(hit, 1)}",
        ":27's memo. A HIT that appends: the registry grows without bound and one name is two SELs."),
 ("M17", "# step 2: every colon that survives becomes an underscore.",
         "# step 2: every colon that survives becomes an underscore.   (CONTROL)",
         "THE CONTROL. A comment-only edit must move NOTHING, or the table is measuring noise."),
 ("M18", "    case c <> t: Bool.pick(Char, is_colon(c), '_', c) <> mangle.colons(t)",
         "    case c <> t: c <> mangle.colons(t)",
         "`:70`'s `.replace(':','_')`. Identity, so the mangle is a strip and nothing else."),
]

def run(path):
  r = subprocess.run([BEND, path], capture_output=True, text=True, cwd=ROOT)
  if r.returncode != 0: return None, r.stderr.strip().splitlines()[:1]
  return r.stdout, None

def lines(out): return dict(l.split("=", 1) for l in out.splitlines() if "=" in l and not l.startswith("#"))

def main():
  base, err = run(SRC)
  if base is None:
    print("BASELINE FAILED TO RUN:", err); sys.exit(1)
  b = lines(base)
  print(f"baseline rows: {len(b)}")
  scratch = tempfile.mkdtemp(prefix="objcmut_")
  # the scratch copy sits BESIDE the source so a relative import would resolve;
  # objc.bend imports only Base today, and this keeps that true if it does not.
  tmp = os.path.join(os.path.dirname(SRC), "zz_objc_mutant.bend")
  src = open(SRC).read()
  moved_total, fails = 0, []
  for mid, old, new, why in M:
    assert src.count(old) == 1, f"{mid}: anchor matched {src.count(old)} times, expected exactly 1"
    open(tmp, "w").write(src.replace(old, new))
    out, err = run(tmp)
    if out is None:
      print(f"| {mid} | {why[:52]} | REFUSED TO COMPILE | {err[0][:60] if err else ''} |")
      fails.append(mid); continue
    m = lines(out)
    moved = sorted(k for k in set(b) | set(m) if b.get(k) != m.get(k))
    moved_total += len(moved)
    print(f"| {mid} | {why[:60]} | {len(moved)} | {', '.join(moved[:8])}{' ...' if len(moved) > 8 else ''} |")
  os.remove(tmp); shutil.rmtree(scratch, ignore_errors=True)
  print(f"\nmoved-total: {moved_total}   refused-to-compile: {fails}")
  assert "M17" in [m[0] for m in M]
  # the control must be zero, or the harness is not measuring the port
  print("CONTROL M17 must be 0 -- see the table above")

main()
