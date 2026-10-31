# render_wgsl.bend -- THE PORT's OWN WALK, OVER A REAL UOP LIST.
#
#   ./bin/bend .agents/slop/perf/render_wgsl.bend
#
# `W.walk` is the uop->body walk (`wgsl_walk.bend`, `_render`'s equivalent) and
# `W.render_kernel` is `wgsl.bend`'s own assembler. NOTHING here is a pasted body string.
import Base
import ./../../../tinybendygrad/renderer/wgsl.bend as V
import ./../../../tinybendygrad/renderer/wgsl_walk.bend as W
import ./gen_wgsl/E_1024.bend as G

def render(rs: List<&2, W.R>) -> String:
  +w = W.walk(rs)
  V.render_kernel(W.Wk.nm(w), W.Wk.body(w), W.Wk.bufs(w), V.Scan{[1], False{}})

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(render(G.rs()))
