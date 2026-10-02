#!/usr/bin/env python3
"""Generate ops_bend.bend's GATE from the CPython oracle's output.

Reads `.agents/slop/nodes-*.txt`, `.agents/slop/packet-*.txt` and
`.agents/slop/bend_oracle_rows.txt` -- all of which are CPython's OWN output --
and writes the fixture block plus every row. Nothing here is transcribed.
"""
import pathlib, re, sys

OUT = pathlib.Path('.agents/slop')
TARGET = pathlib.Path('tinybendygrad/runtime/ops_bend.bend')

rows = {}
for line in (OUT / 'bend_oracle_rows.txt').read_text().splitlines():
    k, _, v = line.partition('=py=')
    rows[k] = v

FIX = ['tiny', 'fconst', 'cmp']
rows_first_line = (OUT / 'packet-tiny.txt').read_text().splitlines()[1].split(' ', 1)[1]


def bend_node_line(l):
    # Bend string literals take no `\xNN`, and tinygrad's own reprs carry ANSI
    # escapes in the kernel name. An ESC is spelled `?`, which is a value no
    # `wire_arg` branch reads.
    return l.replace('\\x1b', '?').replace(chr(27), '?')


def nodes(nm):
    ls = [bend_node_line(l).strip() for l in
          (OUT / f'nodes-{nm}.txt').read_text().rstrip('\n').splitlines()[1:] if l.strip()]
    # the oracle closes its NODES(...) block with a `)` on the last line
    ls[-1] = ls[-1].rstrip(')')
    return '  [' + ', '.join(ls) + ']'


def packet(nm):
    # NOT rstripped: `encode` ends the packet with "\n" (:145) and the reference
    # keeps it, so a stripped reference would differ from the emission by exactly
    # one character.
    return (OUT / f'packet-{nm}.txt').read_text()


def bend_str(s):
    # NEWLINES STAY REAL. A Bend string literal takes `\\n` as two characters,
    # while `String.join(acc, "\\n")` produces a real 0x0A -- MEASURED: with the
    # newlines escaped the reference packet and the emitted one differed on
    # every line boundary and `bend_emit_tiny_match` was False while the printed
    # packet was byte-identical.
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


L = []
w = L.append

w('# ' + '=' * 74)
w('# THE GATE. Every expectation below is CPython output, read out of')
w('# `.agents/slop/` by `tools`-less generator `.agents/slop/bend_gate.py`, which')
w('# takes it from `nodes-<case>.txt`, `packet-<case>.txt` and')
w('# `bend_oracle_rows.txt`. NONE of it is a transcription of ops_bend.py: a row')
w('# whose expectation is a re-reading of the Python would agree with a port that')
w('# misread it.')
w('# ' + '=' * 74)
w('')

for nm in FIX:
    w(f'# ---- the fixture: {nm}, {nodes(nm).count("N{")} uops, from the')
    w('# renderer input of a REAL kernel. `packet-%s.txt` is CPython\'s `encode`.' % nm)
    w('def NODES_%s() -> List<&2, N>:' % nm.upper())
    w(nodes(nm))

w('')
w('# ---- the packets CPython emitted, as ONE escaped string each.')
for nm in FIX:
    w('def PKT_%s() -> String: %s' % (nm.upper(), bend_str(packet(nm))))

w('')
w('def ujoin.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:')
w('  match xs:')
w('    case Nil{}:')
w('      List.reverse(&2, String, acc)')
w('    case x <> t:')
w('      ujoin.go(t, List.append(&2, String, acc, [U32.show(x)]))')
w('')
w('def ujoin(+xs: List<&2, U32>) -> String: String.join(ujoin.go(xs, Nil{}), " ")')
w('')
w('def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))')
w('def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))')
w('def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))')
w('def lrow(nm: String, v: List<&2, U32>) -> IO(Unit): srow(nm, ujoin(v))')
w('')

# ---------------------------------------------------------------- 1: lanes
w('# --- 1: THE LANE TABLE, :90, both directions -----------------------------')
w('#')
w('# The forward direction is `lanes(dt)`; the reverse is the dtype round trip')
w('# `getattr(dtypes, name.lower()).name == name`, which is what the executor\'s')
w('# `to_dtype` does with the name `wire_dtype` emits. A one-directional table')
w('# is how ops_nv shipped 33 wrong constants behind 590 green rows.')
w('def t_lanes() -> IO(Unit):')
w('  do IO<Unit>:')
for dt in ['i32', 'u32', 'f32', 'bool', 'void', 'weakint', 'weakfloat']:
    w(f'    row("bend_lanefree_{dt}", lane_free("{dt}"))')
    w(f'    row("bend_lanefree_{dt}_not_lane", Bool.not(lanes("{dt}")))')
for dt in ['f16', 'bf16', 'f64', 'i64', 'u8', 'u16', 'i16', 'u64', 'i8',
           'fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz']:
    r = wire = rows.get(f'wire_dtype_PARAM_{dt}', rows.get(f'wire_dtype_CONST_{dt}'))
    nm = f'bend_lane_no_{dt}'
    if r and r.startswith('NotImplementedError'):
        w(f'    row("{nm}_ok", Res.ok(wire_dtype("{dt}", "PARAM")))')
        w(f'    srow("{nm}", Res.s(wire_dtype("{dt}", "PARAM")))')
    else:
        w(f'    row("bend_lane_{dt}", lanes("{dt}"))')
w(f'    srow("bend_lane_sorted", "{rows["lanes_sorted_by_str"]}")')
w('    row("bend_lane_sorted_is_literal", String.eq(LANES_SORTED(), "%s"))' % rows['lanes_sorted_by_str'])
w('')

# ---------------------------------------------------------------- 2: dtype round trip
w('# --- 2: THE DTYPE ROUND TRIP, both directions ---------------------------')
w('#')
w('# `wire_dtype` emits `u.dtype.name` and the executor\'s `to_dtype` is')
w('# `getattr(dtypes, name.lower())`, so the pair (name -> attribute -> name) has')
w('# to be the identity. MEASURED by `getattr(dtypes, n.lower()).name` in CPython')
w('# for every name in the vocabulary; a name that is not an attribute would have')
w('# raised, so the fixture is the CLOSURE of the attribute set.')
w('def t_dtypes() -> IO(Unit):')
w('  do IO<Unit>:')
for n in ['i8', 'u8', 'i16', 'u16', 'i32', 'u32', 'i64', 'u64', 'f16', 'bf16',
          'f32', 'f64', 'fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz',
          'void', 'weakint', 'weakfloat']:
    w(f'    srow("bend_rt_{n}", "{rows[f"dtype_roundtrip_{n}"]}")')
for n in ['i8', 'u8', 'i16', 'u16', 'i32', 'u32', 'i64', 'u64', 'f16', 'bf16',
          'f32', 'f64', 'fp8e4m3', 'fp8e5m2', 'void', 'weakint', 'weakfloat']:
    name, sz = rows[f'dt_{n}'].split()
    w(f'    srow("bend_sz_{n}", "{rows[f"dt_{n}"]}")')
w('')

# ---------------------------------------------------------------- 3: wire_dtype refusals
w('# --- 3: THE `wire_dtype` REFUSAL, text and all --------------------------')
w('#')
w('# `BEND v1 has no lane for X (on Y); it has Z` is a decision with a MESSAGE, so')
w('# a boolean about it would be exactly the row that cannot fail. The rows are')
w('# the message.')
w('def t_refuse_dtype() -> IO(Unit):')
w('  do IO<Unit>:')
# The message names the OP it was refused on, so the row is keyed by the dtype
# and carries the op the message says. Both come out of CPython's own text.
seen = set()
for k in sorted(rows):
    v = rows[k]
    if not v.startswith('BEND v1 has no lane'): continue
    dt = k[len('wire_dtype_'):].rsplit('_', 1)[1]
    op = v.split('(on ')[1].split(')')[0]
    if dt in seen: continue
    seen.add(dt)
    w(f'    srow("bend_refuse_{dt}", Res.s(wire_dtype("{dt}", "{op}")))')
    w(f'    row("bend_refuse_{dt}_refused", Bool.not(Res.ok(wire_dtype("{dt}", "{op}"))))')
w('')

# ---------------------------------------------------------------- 4: emit
w('# --- 4: THE EMITTED SOURCE. STRINGS BEFORE BOOLEANS ---------------------')
w('#')
w('# `String.concat` drops a literal silently, so a boolean about a string can be')
w('# true while the string is wrong. Each row below IS the packet, escaped, and')
w('# the check is `diff .agents/slop/packet-<case>.txt` against what')
w('# `bend_emit_<case>` prints.')
w('def t_emit() -> IO(Unit):')
w('  do IO<Unit>:')
for nm in FIX:
    u = nm.upper()
    w(f'    srow("bend_emit_{nm}", Res.s(encode(NODES_{u}())))')
    w(f'    row("bend_emit_{nm}_ok", Res.ok(encode(NODES_{u}())))')
    w(f'    srow("bend_pkt_{nm}", compiler.of(PKT_{u}()))')
    w(f'    row("bend_emit_{nm}_match", String.eq(Res.s(encode(NODES_{u}())), PKT_{u}()))')
w('')

# ---------------------------------------------------------------- 5: prog
w('# --- 5: `BendProgram.__init__`, :195-209 --------------------------------')
w('#')
w('# `nbufs` is the header\'s second field, `in_bufs` the buffer PARAM extents in')
w('# uop order, and `out_bufs` the POSITIONS of the buffers a STORE reaches. The')
w('# position is `sum(is_buf(x.arg) for x in uops[:b])`, a COUNT of buffer PARAMs')
w('# before the base -- not the uop index -- and that is the line this gate is')
w('# most likely to get wrong.')
w('def t_prog() -> IO(Unit):')
w('  do IO<Unit>:')
meta = {}
for nm in FIX:
    t = (OUT / f'bend_meta_{nm}.txt')
    if not t.exists():
        continue
    d = {}
    for ln in t.read_text().splitlines():
        k, _, v = ln.partition(' ')
        d[k] = v
    meta[nm] = d
for nm, d in meta.items():
    u = nm.upper()
    w(f'    urow("bend_prog_{nm}_nbufs", Prog.nbufs(prog.of(NODES_{u}())))')
    w(f'    row("bend_prog_{nm}_nbufs_ok", U32.is_eq(Prog.nbufs(prog.of(NODES_{u}())), {d["nbufs"]}))')
    exp_in = ' '.join(d['in_bufs'].split())
    exp_out = ' '.join(d['out_bufs'].split())
    w(f'    lrow("bend_prog_{nm}_in_bufs", Prog.in_bufs(prog.of(NODES_{u}())))')
    w(f'    row("bend_prog_{nm}_in_bufs_ok", String.eq(ujoin(Prog.in_bufs(prog.of(NODES_{u}()))), "{exp_in}"))')
    w(f'    lrow("bend_prog_{nm}_out_bufs", Prog.out_bufs(prog.of(NODES_{u}())))')
    w(f'    row("bend_prog_{nm}_out_bufs_ok", String.eq(ujoin(Prog.out_bufs(prog.of(NODES_{u}()))), "{exp_out}"))')
w('')

# ---------------------------------------------------------------- 6: trace
w('# --- 6: THE LAUNCH TRACE, and the three refusals ------------------------')
w('def t_call() -> IO(Unit):')
w('  do IO<Unit>:')
w('    # a clean launch: exe, mv, pkt, run, out, then one write-back per')
w('    # out_bufs -- and NO raise step, because a non-raising step still shows')
w('    # its name in the trace.')
w('    srow("bend_call_ok", String.join(Tr.calls(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 0, 3), Tr.of())), ","))')
w('    # :221 local_size -- the refusal records itself and truncates.')
w('    srow("bend_call_local", String.join(Tr.calls(prog.call(prog.of(NODES_TINY()), Lc.of(1, 2, 1, 0, 3), Tr.of())), ","))')
w('    row("bend_call_local_refused", Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 2, 1, 0, 3), Tr.of())))')
w('    row("bend_call_warp1", is_warp1(Lc.of(1, 2, 1, 0, 3)))')
w('    row("bend_call_warp1_1", Bool.not(is_warp1(Lc.of(1, 1, 1, 0, 3))))')
w('    srow("bend_call_warp1_msg", warp1_msg(Lc.of(1, 2, 1, 0, 3)))')
w('    srow("bend_call_warp1_msg_py", "%s")' % rows['local_size_msg'])
w('    row("bend_call_warp1_msg_ok", String.eq(warp1_msg(Lc.of(1, 2, 1, 0, 3)), "%s"))' % rows['local_size_msg'])
w('    # :224 a non-zero exit code.')
w('    row("bend_call_rc_refused", Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 3, 3), Tr.of())))')
w('    urow("bend_call_rc_steps", U32.from_nat(List.length(&2, String, Tr.calls(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 3, 3), Tr.of())))))')
w('    # :226 the wrong buffer count.')
w('    row("bend_call_nbufs_refused", Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 0, 2), Tr.of())))')
w('    row("bend_call_nbufs_ok", Bool.not(Tr.refused(prog.call(prog.of(NODES_TINY()), Lc.of(1, 1, 1, 0, 3), Tr.of()))))')
w('')

# ---------------------------------------------------------------- 7: misc
w('# --- 7: THE SMALL DEFS, :232 and :238 -----------------------------------')
w('def t_misc() -> IO(Unit):')
w('  do IO<Unit>:')
w('    row("bend_has_local", has_local())')
w('    row("bend_compiler_passthrough", String.eq(compiler.of(PKT_TINY()), PKT_TINY()))')
w('    row("bend_compiler_is_encode", String.eq(compiler.of(Res.s(encode(NODES_TINY()))), Res.s(encode(NODES_TINY()))))')
w('    # `is_image_shape` :126, `len(shape)==3 and shape[-1]==4`.')
for k in sorted(rows):
    if k.startswith('is_image_'):
        shp = k[len('is_image_'):]
        dims = [int(x) for x in shp.split('x')] if shp and shp != 'None' else []
        ndim, last = (len(dims), dims[-1]) if dims else (0, 0)
        tag = (shp.replace('x', '_') or 'empty').replace('None', 'none')
        w(f'    row("bend_img_{tag}", is_image_shape({ndim}, {last}))')
w('    # `wire_width` :103, and the two `op` arms a real packet reaches.')
w('    urow("bend_width_load", wire_width(Ns.at(NODES_TINY(), 7)))')
w('    urow("bend_width_param", wire_width(Ns.at(NODES_TINY(), 1)))')
w('    urow("bend_width_const", wire_width(Ns.at(NODES_TINY(), 4)))')
w('    # `is_buf` :177 and `buf_extent` :178.')
w('    row("bend_buf_g", is_buf("k:param:16:g"))')
w('    row("bend_buf_l", is_buf("k:param:16:l"))')
w('    row("bend_buf_r", Bool.not(is_buf("k:param:16:r")))')
w('    row("bend_buf_a", Bool.not(is_buf("k:param:16:a")))')
w('    row("bend_buf_dash", Bool.not(is_buf("-")))')
w('    urow("bend_extent_16", buf_extent("k:param:16:g"))')
w('    urow("bend_extent_4", buf_extent("k:param:4:g"))')
w('    urow("bend_extent_1024", buf_extent("k:param:1024:g"))')
w('    # the PARAM LETTER, :116 -- a direct fixture, because NO REAL PACKET')
w('    # carries a REG or an ALU PARAM and M6/M17 cannot move a row without it.')
w('    srow("bend_letter_global", letter_str(letter.of("GLOBAL")))')
w('    srow("bend_letter_reg", letter_str(letter.of("REG")))')
w('    srow("bend_letter_alu", letter_str(letter.of("ALU")))')
w('    srow("bend_letter_local", letter_str(letter.of("LOCAL")))')
w('    urow("bend_letter_local_code", letter.of("LOCAL"))')
w('    # `const_arg` :118 and `vec_arg` :130 read their node directly, so the')
w('    # two CONST carriers and the two LOAD widths have fixtures of their own.')
w('    srow("bend_const_c", const_arg(Ns.at(NODES_TINY(), 4)))')
w('    srow("bend_const_f", const_arg(Ns.at(NODES_FCONST(), 19)))')
w('    srow("bend_vec_1", vec_arg(1))')
w('    srow("bend_vec_4", vec_arg(4))')
w('    srow("bend_vec_0", vec_arg(0))')
w('')
w('# --- 8: `parse` :180, round trip and the header refusal ----------------')
w('def Line.text(+l: Line) -> String:')
w('  String.concat([Line.op(l), " ", Line.dt(l), " ", Line.arg(l)])')
w('')
w('def line1(src: String) -> String:')
w('  Line.text(Maybe.default(&2, Line, List.get(&2, Line, Pkt.lines(parse(src)), 0n),')
w('    Line.of("-", "-", "-", Nil{})))')
w('')
w('def t_parse() -> IO(Unit):')
w('  do IO<Unit>:')
w('    urow("bend_parse_nbufs", Pkt.nbufs(parse(PKT_TINY())))')
w('    urow("bend_parse_nlines", U32.from_nat(List.length(&2, Line, Pkt.lines(parse(PKT_TINY())))))')
w('    row("bend_parse_ok", Pkt.ok(parse(PKT_TINY())))')
w('    row("bend_parse_bad", Bool.not(Pkt.ok(parse("bendexec 1 0\\n"))))')
w('    srow("bend_parse_bad_msg", Pkt.msg(parse("bendexec 1 0\\n")))')
w('    # the FIRST line of the packet, back out of `parse`. `Line.of.of` is')
w('    srow("bend_parse_l1", line1(PKT_TINY()))')
w('    srow("bend_parse_l1_py", "' + rows_first_line + '")')
w('def main() -> IO(Unit):')
w('  do IO<Unit>:')
for k, t in enumerate(['t_lanes', 't_dtypes', 't_refuse_dtype', 't_emit', 't_prog', 't_call', 't_misc', 't_parse']):
    w(f'    m{k} : Unit <- {t}()')
w('    IO.print("bend-done=1")')

print('\n'.join(L))