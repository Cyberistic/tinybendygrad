#!/usr/bin/env python3
"""Mutation harness for tinybendygrad/runtime/support/hcq2.bend.

One edit at a time on a SCRATCH copy, run through the INTERPRETED lane, and the
row NAMES are diffed. The useful column is "rows MOVED", because a mutation that
moves nothing measures what the gate does NOT see.

    .venv/bin/python .agents/slop/hcq2-mutate.py            # all
    .venv/bin/python .agents/slop/hcq2-mutate.py M3 M7      # selected

NOTHING here is written back to hcq2.bend; the file is only ever read.
"""
import subprocess, sys, pathlib, tempfile, shutil, os, re
import patch_not_apply as PNA

ROOT = pathlib.Path(__file__).resolve().parents[2]
TARGET = ROOT / 'tinybendygrad/runtime/support/hcq2.bend'

# (id, one-line description, the python `str.replace(old, new)`)
MUTS = [
 ("M1", "to_name.norm: drop the lower-case",
  ('  String.to_lower(String.join(String.split(s, \':\'), "_"))',
   '  String.join(String.split(s, \':\'), "_")')),
 ("M2", "to_name.go: no `_` between parts",
  ('List.append(&2, String, acc, [String.concat([to_name.norm(h), "_"])]))',
   'List.append(&2, String, acc, [to_name.norm(h)])))')),
 ("M3", "to_name.go: reverse the accumulator",
  ('    case Nil{}: String.concat(acc)\n    case h <> Nil{}: String.concat(List.append(&2, String, acc, [to_name.norm(h)]))',
   '    case Nil{}: String.concat(List.reverse(&2, String, acc))\n    case h <> Nil{}: String.concat(List.append(&2, String, acc, [to_name.norm(h)]))')),
 ("M4", "all_in: `or` becomes `and`",
  ('    case h <> t: all_in.go(t, nm, Bool.or(hit, U32.is_ne(dev_id(dev_head(h)), NO_HCQ_DEV())))',
   '    case h <> t: all_in.go(t, nm, Bool.and(hit, U32.is_ne(dev_id(dev_head(h)), NO_HCQ_DEV())))')),
 ("M5", "cdtype_of: 2 becomes 4",
  ('def cdtype_of(n: U32) -> U32:\n  match n:\n    case 1: 1\n    case 2: 2',
   'def cdtype_of(n: U32) -> U32:\n  match n:\n    case 1: 1\n    case 2: 4')),
 ("M6", "layout: the base offset is dropped",
  ('    case 1n+m:\n      match slots:\n        case Nil{}: acc\n        case s <> st:\n          match ks:\n            case Nil{}: acc\n            case k <> kt: layout.go(m, st, kt, base,',
   '    case 1n+m:\n      match slots:\n        case Nil{}: acc\n        case s <> st:\n          match ks:\n            case Nil{}: acc\n            case k <> kt: layout.go(m, st, kt, 0,')),
 ("M7", "layout: the itemsize is dropped from Arg.k",
  ('[Arg{U32.add(base, s), k}]))', '[Arg{U32.add(base, s), 8}]))')),
 ("M8", "pack.step: emit the pad even at gap 0",
  ('  match gap_zero:\n    case True{}: List.append(&2, Pk, acc, [Pk{PK_WORD(), sz}])\n    case False{}:',
   '  match gap_zero:\n    case True{}: List.append(&2, Pk, List.append(&2, Pk, acc, [Pk{PK_PAD(), 0}]), [Pk{PK_WORD(), sz}])\n    case False{}:')),
 ("M9", "pack.trail: drop the trailing pad",
  ('  pack.wrap(U32.is_gt(end_of(as), size), U32.sub(size, end_of(as)),\n            pack.go(List.length(&2, Arg, as), as, 0, Nil{}))',
   '  pack.wrap(U32.is_gt(end_of(as), size), 0,\n            pack.go(List.length(&2, Arg, as), as, 0, Nil{}))')),
 ("M10", "pack.trail: no refusal on a short size",
  ('  pack.wrap(U32.is_gt(end_of(as), size), U32.sub(size, end_of(as)),',
   '  pack.wrap(False{}, U32.sub(size, end_of(as)),')),
 ("M11", "slot_bytes: drop the leading `2 *`",
  ('def slot_bytes(+bs: List<&2, E>, profile: Bool) -> U32: U32.mul(2, slot_words(bs, profile))',
   'def slot_bytes(+bs: List<&2, E>, profile: Bool) -> U32: slot_words(bs, profile)')),
 ("M12", "slot_words: the profile arm adds 1 per call, not 2",
  ('          Bool.pick(U32, profile, U32.mul(2, U32.from_nat(List.length(&2, E, bs))), 0))',
   '          Bool.pick(U32, profile, U32.from_nat(List.length(&2, E, bs)), 0))')),
 ("M13", "stamp_n: `nq + 1` becomes `nq`",
  ('  Bool.pick(U32, profile, U32.add(U32.add(nq(bs, DEV_N0()), 1), U32.mul(2, tag)), 0)',
   '  Bool.pick(U32, profile, U32.add(U32.add(nq(bs, DEV_N0()), 0), U32.mul(2, tag)), 0)')),
 ("M14", "qsig: the slot index is not doubled",
  ('def qsig(+bs: List<&2, E>, dev: U32, q: U32) -> U32: U32.mul(2, qidx(qlist(bs, dev), q))',
   'def qsig(+bs: List<&2, E>, dev: U32, q: U32) -> U32: U32.mul(1, qidx(qlist(bs, dev), q))')),
 ("M15", "stl: the timeline slot is at `nq`, not `2*nq`",
  ('def stl(+bs: List<&2, E>, dev: U32) -> U32: U32.mul(2, nq(bs, dev))',
   'def stl(+bs: List<&2, E>, dev: U32) -> U32: U32.add(1, nq(bs, dev))')),
 ("M16", "epi: the two arms are swapped",
  ('  Bool.pick(U32, U32.is_eq(nq(bs, dev), 1), qfirst(qlist(bs, dev)), Q_COMPUTE())',
   '  Bool.pick(U32, U32.is_eq(nq(bs, dev), 1), Q_COMPUTE(), qfirst(qlist(bs, dev)))')),
 ("M17", "sig_tags: FIRST-WINS instead of LAST-WINS",
  ('            List.append(&2, U32, acc, [lasttag(bs, E.dev(p), E.q(p))]), acc))',
   '            List.append(&2, U32, acc, [0]), acc))')),
 ("M18", "sig_tags: no queue signals",
  ('  Bool.pick(List<&2, U32>, signs(bs, E.dev(p), E.q(p)),',
   '  Bool.pick(List<&2, U32>, Bool.not(signs(bs, E.dev(p), E.q(p))),')),
 ("M19", "call_block: the CALL goes BEFORE the pre-timestamp",
  ('''  signal_at(bs, tag,
    post_ts(bs, tag, profile,
      List.append(&2, Ins, pre_ts(bs, tag, profile, waits(bs, tag)),
                  [Ins{I_CALL(), tag, 0, 0}])))''',
   '''  signal_at(bs, tag,
    post_ts(bs, tag, profile,
      pre_ts(bs, tag, profile,
        List.append(&2, Ins, waits(bs, tag), [Ins{I_CALL(), tag, 0, 0}]))))''')),
 ("M20", "start_ins: the BARRIER is dropped",
  ('  start.go(U32.to_nat(start_n(dev)), Nil{}, dev, 0, True{})',
   '  start.go(U32.to_nat(start_n(dev)), Nil{}, dev, 1, False{})')),
 ("M21", "start_n: the peer timeline wait is dropped",
  ('def start_n(dev: U32) -> U32: Bool.pick(U32, U32.is_eq(dev, DEV_N0()), 3, 2)',
   'def start_n(dev: U32) -> U32: Bool.pick(U32, U32.is_eq(dev, DEV_N0()), 2, 2)')),
 ("M22", "epi_waits_n: the peer-queue waits are dropped",
  ('  Bool.pick(U32, U32.is_eq(dev, DEV_N0()), U32.sub(nq(bs, dev), 1), npairs(bs))',
   '  Bool.pick(U32, U32.is_eq(dev, DEV_N0()), U32.sub(nq(bs, dev), 1), 0)')),
 ("M23", "overlaps: a write no longer waits for a prior READ",
  ('''  Bool.or(Bool.or(U32.is_eq(E.r(elem(bs, i)), E.w(elem(bs, t))),
                  U32.is_eq(E.w(elem(bs, i)), E.w(elem(bs, t)))),
          U32.is_eq(E.w(elem(bs, i)), E.r(elem(bs, t))))''',
   '''  Bool.or(U32.is_eq(E.r(elem(bs, i)), E.w(elem(bs, t))),
          U32.is_eq(E.w(elem(bs, i)), E.w(elem(bs, t))))''')),
 ("M24", "prodq: the FIFO filter is dropped (every dep is its own queue)",
  ('                 Bool.pick(List<&2, U32>, Bool.not(member(acc, E.q(elem(bs, d)))),\n                   List.append(&2, U32, acc, [E.q(elem(bs, d))]), acc))',
   '                 Bool.pick(List<&2, U32>, True{},\n                   List.append(&2, U32, acc, [E.q(elem(bs, d))]), acc))')),
 ("M25", "staging_chunk: one divide instead of two",
  ('def staging_chunk(it: U32) -> U32: U32.div(staging_slot_bytes(), it)',
   'def staging_chunk(it: U32) -> U32: staging_slot_bytes()')),
 ("M26", "fld_at: the field lookup is by POSITION, not by NAME",
  ('fld_at.go(m, t, nm, Bool.pick(U32, String.eq(Fld.name(f), nm), Fld.at(f), d))',
   'fld_at.go(m, t, nm, Bool.pick(U32, Bool.not(U32.is_zero(d)), Fld.at(f), d))')),
 ("M27", "fld_names: drop every name",
  ('List.append(&2, String, acc, [Fld.name(f)]))', 'List.append(&2, String, acc, ["?"]))')),
 ("M28", "cstruct_cmd_rows: context_id's offset is wrong",
  ('def cstruct_cmd_rows() -> List<&2, U32>: [8, 16, 20, 56]',
   'def cstruct_cmd_rows() -> List<&2, U32>: [8, 16, 20, 52]')),
 ("M29", "fstr: no separator between field names",
  ('String.concat([" ", h])', 'String.concat([h])')),
 ("M30", "control: a comment-only edit", ('# THE WALLS, named once each', '# THE WALLS, named once each (control)')),
]

def vals(txt):
  """name -> value. A mutation changes VALUES, never row NAMES, so comparing
  names would report 0 for every edit and that is the M30 trap in a different
  hat."""
  out = {}
  for line in txt.splitlines():
    if '=' in line:
      k, v = line.split('=', 1)
      out[k] = v
  return out

def run(src, tag):
  d = ROOT / 'tinybendygrad/runtime/support'
  f = d / f'_mut_{tag}.bend'
  f.write_text(src)
  try:
    r = subprocess.run(['./bin/bend', str(f)], capture_output=True, text=True,
                       cwd=ROOT, timeout=120)
    return r.stdout if r.returncode == 0 else ''
  except subprocess.TimeoutExpired:
    return ''
  finally:
    f.unlink(missing_ok=True)

def main():
  base = TARGET.read_text()
  want = set(sys.argv[1:])
  ref = vals(run(base, 'base'))
  print(f'baseline rows: {len(ref)}')
  print('| # | the edit | rows moved |')
  print('| --- | --- | --- |')
  for mid, desc, (old, new) in MUTS:
    if want and mid not in want: continue
    if old not in base:
      print(PNA.pipe([mid, desc, PNA.not_applied()], 3))
      continue
    got = vals(run(base.replace(old, new, 1), mid.replace('M', 'm')))
    moved = [n for n in ref if got.get(n) != ref[n]]
    gone = [n for n in ref if n not in got]
    note = ''
    if not got: note = '  -- GATE DIED'
    elif gone: note = f'  ({len(gone)} rows GONE)'
    print(f'| {mid} | {desc} | {len(moved)}{note} |')

if __name__ == '__main__':
  main()