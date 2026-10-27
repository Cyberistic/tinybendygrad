typedef float float2 __attribute__((aligned(4),ext_vector_type(2)));
void r_56_7_2_2(float* restrict data0_392, float* restrict data1_1568) {
  for (int Lidx2 = 0; Lidx2 < 56; Lidx2++) {
    for (int Lidx4 = 0; Lidx4 < 7; Lidx4++) {
      int alu0 = ((Lidx2*28)+(Lidx4<<1));
      float2 val0 = (*((float2*)((data1_1568+(alu0+14)))));
      float2 val1 = (*((float2*)((data1_1568+alu0))));
      float alu1 = ((val1[0]<val1[1])?val1[1]:val1[0]);
      float alu2 = ((alu1<val0[0])?val0[0]:alu1);
      float alu3 = ((alu2<val0[1])?val0[1]:alu2);
      *(data0_392+((Lidx2*7)+Lidx4)) = alu3;
    }
  }
}
