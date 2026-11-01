#include <metal_stdlib>
using namespace metal;
struct args_t { device float* data0_4096; device float* data1_4096; device float* data2_4096; };
kernel void E_32_32_4(constant args_t& args [[buffer(0)]], uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {
  device float* data0_4096 = args.data0_4096; device float* data1_4096 = args.data1_4096; device float* data2_4096 = args.data2_4096;
  int gidx0 = gid.x; /* 32 */
  int lidx0 = lid.x; /* 32 */
  int alu0 = ((gidx0<<7)+(lidx0<<2));
  float4 val0 = (*((device float4*)((data1_4096+alu0))));
  float4 val1 = (*((device float4*)((data2_4096+alu0))));
  float alu1 = ((val1.x*val0.x)+val1.x);
  float alu2 = ((val1.y*val0.y)+val1.y);
  float alu3 = ((val1.z*val0.z)+val1.z);
  float alu4 = ((val1.w*val0.w)+val1.w);
  float alu5 = ((0.0f<alu1)?alu1:0.0f);
  float alu6 = ((0.0f<alu2)?alu2:0.0f);
  float alu7 = ((0.0f<alu3)?alu3:0.0f);
  float alu8 = ((0.0f<alu4)?alu4:0.0f);
  *((device float4*)((data0_4096+alu0))) = float4(((alu5*2.0f)-val0.x),((alu6*2.0f)-val0.y),((alu7*2.0f)-val0.z),((alu8*2.0f)-val0.w));
}