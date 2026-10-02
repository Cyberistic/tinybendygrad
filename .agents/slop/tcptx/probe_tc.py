import sys; sys.path.insert(0,'.')
from tinygrad.renderer import tc
def p(label, v): print(f"{label} = [{v}]")
for name in ["cuda_81616","cuda_81632_f8","cuda_8168_f16","cuda_8168_tf32","cuda_sm75","cuda_sm80","cuda_sm89",
             "amd_rdna3","amd_rdna4","amd_cdna_161616","amd_cdna_161632","amd_cdna_1616128","amd_cdna3_161632",
             "amd_cdna3","amd_cdna4","metal"]:
    p(f"tc_n {name}", len(getattr(tc,name)))
for arch in ["sm_75","sm_80","sm_86","sm_89","sm_90"]:
    p(f"get_cuda {arch}", len(tc.get_cuda(arch)))
for arch in ["gfx942","gfx950","gfx1200","gfx1201","gfx1100"]:
    r = tc.get_amd(arch); p(f"get_amd {arch}", len(r))
p("get_amd gfx1100 is rdna3", tc.get_amd("gfx1100") is tc.amd_rdna3)
p("get_cuda sm_75 is cuda_8168_f16", tc.get_cuda("sm_75") is tc.cuda_8168_f16)
