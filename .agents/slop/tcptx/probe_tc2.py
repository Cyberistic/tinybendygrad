import sys; sys.path.insert(0,'.')
from tinygrad.renderer import tc
from tinygrad.dtype import dtypes
def p(label, v): print(f"{label} = [{v}]")
cores = {
  "mma16hf": tc.cuda_81616[0], "mma16bf": tc.cuda_81616[1], "mma16hh": tc.cuda_81616[2],
  "mma32f8": tc.cuda_81632_f8[0], "mma8f16": tc.cuda_8168_f16[0], "mma8tf32": tc.cuda_8168_tf32[0],
  "rdna3": tc.amd_rdna3[0], "rdna4": tc.amd_rdna4[0],
  "cdna16": tc.amd_cdna_161616[0], "cdna32": tc.amd_cdna_161632[0], "cdna128": tc.amd_cdna_1616128[0],
  "metal": tc.metal[0],
}
for nm, t in cores.items():
    p(f"ax {nm}", ",".join(t.axis_coords()))
    p(f"dims {nm}", ",".join(str(x) for x in t.dims))
    p(f"thr {nm}", t.threads)
    p(f"bua {nm}", ",".join(t.base_upcast_axes()))
    p(f"rel {nm}", "|".join(",".join(f"{k}={v}" for k,v in r.items()) for r in t.relabel()))
    p(f"dio {nm}", f"{t.dtype_in.name}/{t.dtype_out.name}")
for nm, t in cores.items():
    for oi,(f,ax) in enumerate(zip((t.frag_a,t.frag_b,t.frag_c),("mk","kn","mn"))):
        p(f"fc {nm}.{oi}", ";".join(
            ",".join("".join(f"{d}{int(c[d]):02d}" for d in ax) for c in (coord(f,ax,lane,elem)
              for elem in range(2**len(f[1])) for lane in range(2**len(f[0])))
            for lane in []) or "|".join(
            ",".join("".join(f"{d}{int(c[d]):02d}" for d in ax) for c in (coord(f,ax,lane,elem)
              for elem in range(2**len(f[1])))) for lane in range(2**len(f[0])))))
def coord(f, ax, lane, elem):
  return tuple(sum(((v>>j)&1) << int(c[1:]) for bits,v in zip(f, (lane, elem)) for j,c in enumerate(bits) if c[0]==d) for d in ax)
