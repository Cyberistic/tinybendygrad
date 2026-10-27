typedef float float4 __attribute__((aligned(4),ext_vector_type(4)));
void r_4_28_7_4_3_3(float* restrict data0_3136, float* restrict data1_784, float* restrict data2_36, float* restrict data3_4) {
  float4 cast0 = (float4){0.0f,0.0f,0.0f,0.0f};
  for (int Lidx2 = 0; Lidx2 < 4; Lidx2++) {
    int alu0 = (Lidx2*9);
    float val0 = (*(data2_36+(alu0+1)));
    float val1 = (*(data2_36+(alu0+2)));
    float val2 = (*(data2_36+(alu0+3)));
    float val3 = (*(data2_36+(alu0+4)));
    float val4 = (*(data2_36+(alu0+5)));
    float val5 = (*(data2_36+(alu0+6)));
    float val6 = (*(data2_36+(alu0+7)));
    float val7 = (*(data2_36+(alu0+8)));
    float val8 = (*(data2_36+alu0));
    float val9 = (*(data3_4+Lidx2));
    for (int Lidx3 = 0; Lidx3 < 28; Lidx3++) {
      _Bool alu1 = (0<Lidx3);
      _Bool alu2 = (Lidx3<27);
      for (int Lidx4 = 0; Lidx4 < 7; Lidx4++) {
        int alu3 = ((Lidx3*28)+(Lidx4<<2));
        _Bool alu4 = (0<Lidx4);
        float val10 = (alu4?*(data1_784+(alu3+-1)):0.0f);
        _Bool alu5 = (Lidx4<6);
        float val11 = ((alu5&alu1)?*(data1_784+(alu3+-24)):0.0f);
        float val12 = ((alu4&alu1)?*(data1_784+(alu3+-29)):0.0f);
        float val13 = ((alu4&alu2)?*(data1_784+(alu3+27)):0.0f);
        float val14 = ((alu5&alu2)?*(data1_784+(alu3+32)):0.0f);
        float val15 = (alu5?*(data1_784+(alu3+4)):0.0f);
        float4 val16 = (alu1?*((float4*)((data1_784+(alu3+-28)))):cast0);
        float4 val17 = (alu2?*((float4*)((data1_784+(alu3+28)))):cast0);
        float4 val18 = (*((float4*)((data1_784+alu3))));
        float alu6 = ((val16[0]*val8)+(val16[1]*val0)+(val16[2]*val1)+(val18[0]*val2)+(val18[1]*val3)+(val18[2]*val4)+(val17[0]*val5)+(val17[1]*val6)+(val17[2]*val7)+val9);
        float alu7 = ((val16[1]*val8)+(val16[2]*val0)+(val16[3]*val1)+(val18[1]*val2)+(val18[2]*val3)+(val18[3]*val4)+(val17[1]*val5)+(val17[2]*val6)+(val17[3]*val7)+val9);
        float alu8 = ((val16[2]*val8)+(val16[3]*val0)+(val11*val1)+(val18[2]*val2)+(val18[3]*val3)+(val15*val4)+(val17[2]*val5)+(val17[3]*val6)+(val14*val7)+val9);
        float alu9 = ((val12*val8)+(val16[0]*val0)+(val16[1]*val1)+(val10*val2)+(val18[0]*val3)+(val18[1]*val4)+(val13*val5)+(val17[0]*val6)+(val17[1]*val7)+val9);
        float alu10 = ((0.0f<alu6)?alu6:0.0f);
        float alu11 = ((0.0f<alu7)?alu7:0.0f);
        float alu12 = ((0.0f<alu8)?alu8:0.0f);
        float alu13 = ((0.0f<alu9)?alu9:0.0f);
        *((float4*)((data0_3136+(alu3+(Lidx2*784))))) = (float4){alu13,alu10,alu11,alu12};
      }
    }
  }
}
