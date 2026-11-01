#include <metal_stdlib>
using namespace metal;
struct args_t { device float* data0_1024; device float* data1_1024; device float* data2_1024; };
kernel void E_8_32_4(constant args_t& args [[buffer(0)]], uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {
  device float* data0_1024 = args.data0_1024; device float* data1_1024 = args.data1_1024; device float* data2_1024 = args.data2_1024;
  int gidx0 = gid.x; /* 8 */
  int lidx0 = lid.x; /* 32 */
  int alu0 = ((gidx0<<7)+(lidx0<<2));
  float4 val0 = (*((device float4*)((data1_1024+alu0))));
  float4 val1 = (*((device float4*)((data2_1024+alu0))));
  float alu1 = ((0.0f<val0.x)?val0.x:val1.x);
  float alu2 = ((0.0f<val0.y)?val0.y:val1.y);
  float alu3 = ((0.0f<val0.z)?val0.z:val1.z);
  float alu4 = ((0.0f<val0.w)?val0.w:val1.w);
  *((device float4*)((data0_1024+alu0))) = float4(alu1,alu2,alu3,alu4);
}