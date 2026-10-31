fn nan() -> f32 { let bits = 0xffffffffu; return bitcast<f32>(bits); }
@group(0) @binding(0)
var<uniform> INFINITY : f32;
@group(0) @binding(1)var<storage,read_write>data0_1024:array<f32>;
@group(0) @binding(2)var<storage,read_write>data1_1024:array<f32>;
@group(0) @binding(3)var<storage,read_write>data2_1024:array<f32>;
@compute @workgroup_size(1) fn E_1024(@builtin(workgroup_id) gindex: vec3<u32>,@builtin(local_invocation_id) lindex: vec3<u32>) {
  var gidx0 = i32(gindex.x); /* 1024 */
  var val0 = data1_1024[gidx0];
  var val1 = data2_1024[gidx0];
  data0_1024[gidx0] = ((val1*val0)+val1);
}