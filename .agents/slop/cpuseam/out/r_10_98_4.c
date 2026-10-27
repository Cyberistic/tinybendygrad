typedef float float4 __attribute__((aligned(4),ext_vector_type(4)));
void r_10_98_4(float* restrict data0_10, float* restrict data1_392, float* restrict data2_3920, float* restrict data3_10) {
  float buf0[1];
  for (int Lidx1 = 0; Lidx1 < 10; Lidx1++) {
    *(buf0+0) = 0.0f;
    for (int Lidx0 = 0; Lidx0 < 98; Lidx0++) {
      int alu1 = (Lidx0<<2);
      float4 val0 = (*((float4*)((data1_392+alu1))));
      float4 val1 = (*((float4*)((data2_3920+(alu1+(Lidx1*392))))));
      *(buf0+0) = ((*(buf0+0))+(val0[0]*val1[0])+(val0[1]*val1[1])+(val0[2]*val1[2])+(val0[3]*val1[3]));
    }
    float val2 = (*(data3_10+Lidx1));
    *(data0_10+Lidx1) = ((*(buf0+0))+val2);
  }
}
