
void E_4(float* restrict data0_4, float* restrict data1_4) {
  float4 val0 = (*((float4*)((data1_4+0))));
  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};
}

