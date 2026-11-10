#!/usr/bin/env python3
"""PATCH THE COMPILED DAEMON SO IT TIMES ITS OWN PHASES, AND DUMP THEM A TURN.

**THE PATCH SITES ARE READ FROM THE COMPILED FORM AND NOT GUESSED**, AND THE PATCH IS
**VERIFIED BY A BISECTION** (EVERY SITE ALONE, THEN ALL TOGETHER) BECAUSE THE FIRST ATTEMPT AT
THIS MEASURED A PROGRAM THAT HUNG: `$IO_bind`'s CONTINUATION MUST **RETURN AN EFFECT**, NOT A
VALUE (`run_tail(_f_0(_x_0), _k_0)` RUNS THE CONTINUATION's RESULT), AND A CONTINUATION THAT
RETURNS A VALUE MAKES THE RUNTIME SAY "r.f is not a function".

AND THE EFFECT MUST STAY IN THE **EFFECT SLOT**: `$IO_bind(effect, continuation, k)` -- SO
THE CLOCK IS TAKEN IN A **THIRD** POSITION (A CONTINUATION THAT WRAPS THE NEXT EFFECT) AND NOT BY
REPLACING THE EFFECT, WHICH DELETES IT AND LEAVES "bend: no effect registers undefined".
"""

import pathlib
import sys

PATCHES = [
  # THE ACCUMULATORS.
  ("function $serve(_fuel_0, _m_0, _s_0) {",
   """globalThis.__T = {read:0, decode:0, render:0, walk:0, one:0, kern:0, nturn:0, none:0};
globalThis.__M = (k,t0) => { globalThis.__T[k] += (performance.now()-t0); };
function $serve(_fuel_0, _m_0, _s_0) {"""),

  # THE DECODE.
  ("""    return $IO_bind($$decode(_cs_1), run_clo($serve_c7(_f_0,_k_0)), _x_8);""",
   """    const __t0 = performance.now();
    return $IO_bind($$decode(_cs_1),
      (_x_9b) => { globalThis.__M("decode",__t0); return run_clo($serve_c7(_f_0,_k_0))(_x_9b); },
      _x_8);"""),

  # THE RENDER.
  ("""    return $IO_bind((_x_11) => $IO_print($$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9), _x_11), run_clo($serve_c9(_f_0,_k_0)), _x_10);""",
   """    const __t0 = performance.now();
    const __r = $$_________tinybendygrad_renderer_cstyle_render($$_________tinybendygrad_renderer_cstyle_dev_clang(), true, _x_9);
    globalThis.__M("render",__t0);
    return $IO_bind((_x_11) => $IO_print(__r, _x_11),
      (_x_11b) => run_clo($serve_c9(_f_0,_k_0))(_x_11b), _x_10);"""),

  # THE WALK: `_render_go` IS CALLED ONCE, FROM `_render`.
  ("""  return $_________tinybendygrad_renderer_cstyle__render_go(_kus_0, $$_________tinybendygrad_renderer_cstyle_chunks_of(_kus_0), _dev_0, 0, $$_________tinybendygrad_renderer_cstyle_St_of({$: "Rows", "ts": {$: "Nil"}, "n": 0}, {$: "Nil"}, {$: "Nil"}, $$List_replicate(6, 0), 1, "test"));""",
   """  const __tw = performance.now();
  const __wr = $_________tinybendygrad_renderer_cstyle__render_go(_kus_0, $$_________tinybendygrad_renderer_cstyle_chunks_of(_kus_0), _dev_0, 0, $$_________tinybendygrad_renderer_cstyle_St_of({$: "Rows", "ts": {$: "Nil"}, "n": 0}, {$: "Nil"}, {$: "Nil"}, $$List_replicate(6, 0), 1, "test"));
  globalThis.__M("walk", __tw);
  return __wr;"""),

  # THE PER-UOP EMIT: `_render_one` IS CALLED ONCE A UOP, FROM `_render_go`.
  ("""        $4 = $$_________tinybendygrad_renderer_cstyle__render_one(_dev_0, _i_0, _h_0, _all_0, _st_0);""",
   """        { const __to = performance.now();
          $4 = $$_________tinybendygrad_renderer_cstyle__render_one(_dev_0, _i_0, _h_0, _all_0, _st_0);
          globalThis.__M("one", __to); globalThis.__T.none++; }"""),

  # THE FINAL ASSEMBLY: `render_kernel_go` IS CALLED ONCE, FROM `render_kernel`.
  ("""function $_________tinybendygrad_renderer_cstyle_render_kernel_go(_m_0, _dev_0, _cpu_0, _fn_0, _kernel_0, _bufs_0, _kus_0, _lb_0) {
  if (_m_0) {""",
   """function $_________tinybendygrad_renderer_cstyle_render_kernel_go(_m_0, _dev_0, _cpu_0, _fn_0, _kernel_0, _bufs_0, _kus_0, _lb_0) {
  const __tk = performance.now();
  const __kr = $_________tinybendygrad_renderer_cstyle_render_kernel_go_inner(_m_0, _dev_0, _cpu_0, _fn_0, _kernel_0, _bufs_0, _kus_0, _lb_0);
  globalThis.__M("kern", __tk);
  return __kr;
}
function $_________tinybendygrad_renderer_cstyle_render_kernel_go_inner(_m_0, _dev_0, _cpu_0, _fn_0, _kernel_0, _bufs_0, _kus_0, _lb_0) {
  if (_m_0) {"""),

  # THE `@@END` DUMP. THE DAEMON NEVER EXITS (IT LOOPS ON THE FIFO FOREVER), SO A
  # `process.on("exit")` HOOK WOULD NEVER FIRE AND THE NUMBERS WOULD COME BACK NEVER.
  ("""    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14), run_clo($serve_c11(_f_0,_k_0)), _x_13);""",
   """    globalThis.__T.nturn++;
    try { require("fs").writeFileSync(process.env.__T_OUT || "/tmp/daemon-phase.json",
      JSON.stringify(globalThis.__T)); } catch (e) {}
    return $IO_bind((_x_14) => $IO_print($$ended(), _x_14),
      (_x_14b) => run_clo($serve_c11(_f_0,_k_0))(_x_14b), _x_13);"""),
]


def instrument(src: str) -> str:
  for old, new in PATCHES:
    if src.count(old) != 1:
      raise SystemExit(f"WARN: {src.count(old)} matches for {old[:70]!r}")
    src = src.replace(old, new, 1)
  return src


if __name__ == "__main__":
  base = pathlib.Path(sys.argv[1])
  out = pathlib.Path(sys.argv[2])
  out.write_text(instrument(base.read_text()))
  print(f"instrumented -> {out}")
