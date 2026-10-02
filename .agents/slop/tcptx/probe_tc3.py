import sys; sys.path.insert(0,'.')
from tinygrad.renderer import tc
def p(label, v): print(f"{label} = [{v}]")
def coord(f, ax, lane, elem):
  return tuple(sum(((v>>j)&1) << int(c[1:]) for bits,v in zip(f, (lane, elem)) for j,c in enumerate(bits) if c[0]==d) for d in ax)
def fc_str(t, oi, ax):
  f = (t.frag_a,t.frag_b,t.frag_c)[oi]
  lanes=[]
  for lane in range(2**len(f[0])):
    elems=[]
    for elem in range(2**len(f[1])):
      c = coord(f,ax,lane,elem)
      elems.append("".join(f"{d}{c[i]:02d}" for i,d in enumerate(ax)))
    lanes.append(",".join(elems))
  return "|".join(lanes)
cores = {
  "mma16hf": tc.cuda_81616[0], "mma8tf32": tc.cuda_8168_tf32[0],
  "rdna3": tc.amd_rdna3[0], "cdna16": tc.amd_cdna_161616[0], "cdna128": tc.amd_cdna_1616128[0],
  "metal": tc.metal[0],
}
for nm, t in cores.items():
    for oi, ax in enumerate(("mk","kn","mn")):
        p(f"fc {nm}.{oi}", fc_str(t,oi,ax))
# the raw nested structure for one core, to confirm the shape
import json
p("fclen", f"{len(tc.cuda_81616[0].frag_coords())}")
p("fcshape", f"{len(tc.cuda_81616[0].frag_coords()[0])}x{len(tc.cuda_81616[0].frag_coords()[0][0])}x{len(tc.cuda_81616[0].frag_coords()[0][0][0])}")
