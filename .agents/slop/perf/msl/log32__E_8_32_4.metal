#include <metal_stdlib>
using namespace metal;
struct args_t { device float* data0_1024; device float* data1_1024; };
kernel void E_8_32_4(constant args_t& args [[buffer(0)]], uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {
  device float* data0_1024 = args.data0_1024; device float* data1_1024 = args.data1_1024;
  int gidx0 = gid.x; /* 8 */
  int lidx0 = lid.x; /* 32 */
  int alu0 = ((gidx0<<7)+(lidx0<<2));
  float4 val0 = (*((device float4*)((data1_1024+alu0))));
  *((device float4*)((data0_1024+alu0))) = float4((log2(exp2((val0.x*1.4426950216293335f)))*0.6931471824645996f),(log2(exp2((val0.y*1.4426950216293335f)))*0.6931471824645996f),(log2(exp2((val0.z*1.4426950216293335f)))*0.6931471824645996f),(log2(exp2((val0.w*1.4426950216293335f)))*0.6931471824645996f));
}