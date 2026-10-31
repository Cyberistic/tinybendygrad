fn nan() -> f32 { let bits = 0xffffffffu; return bitcast<f32>(bits); }
@group(0) @binding(0)
var<uniform> INFINITY : f32;
@group(0) @binding(1)var<storage,read_write>data0_64:array<f32>;
@group(0) @binding(2)var<storage,read_write>data1_4096:array<f32>;
@compute @workgroup_size(1) fn r_64_64(@builtin(workgroup_id) gindex: vec3<u32>,@builtin(local_invocation_id) lindex: vec3<u32>) {
  var buf0 = UNHANDLED(Ops.BUFFER);
  var gidx0 = i32(gindex.x); /* 64 */
  UNHANDLED(Ops.AFTER)[0] = 0.0f;
  var alu0 = UNHANDLED(Ops.RANGE);
  var val0 = data1_4096[((gidx0<<6)+alu0)];
  UNHANDLED(Ops.AFTER)[0] = (UNHANDLED(Ops.AFTER)[0]+val0);
  data0_64[gidx0] = UNHANDLED(Ops.AFTER)[0];
}