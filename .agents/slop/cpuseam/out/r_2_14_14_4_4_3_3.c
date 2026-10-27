typedef float float4 __attribute__((aligned(4),ext_vector_type(4)));
void r_2_14_14_4_4_3_3(float* restrict data0_1568, float* restrict data1_784, float* restrict data2_288, float* restrict data3_8) {
  float buf0[4];
  for (int Lidx3 = 0; Lidx3 < 2; Lidx3++) {
    float4 val0 = (*((float4*)((data3_8+(Lidx3<<2)))));
    for (int Lidx4 = 0; Lidx4 < 14; Lidx4++) {
      _Bool alu0 = (0<Lidx4);
      _Bool alu1 = (Lidx4<13);
      for (int Lidx5 = 0; Lidx5 < 14; Lidx5++) {
        int alu2 = ((Lidx4*14)+Lidx5);
        _Bool alu3 = (0<Lidx5);
        _Bool alu4 = (Lidx5<13);
        *(buf0+0) = 0.0f;
        *(buf0+1) = 0.0f;
        *(buf0+2) = 0.0f;
        *(buf0+3) = 0.0f;
        for (int Lidx0 = 0; Lidx0 < 4; Lidx0++) {
          int alu9 = (alu2+(Lidx0*196));
          float val1 = (alu3?*(data1_784+(alu9+-1)):0.0f);
          float val2 = ((alu4&alu0)?*(data1_784+(alu9+-13)):0.0f);
          float val3 = (alu0?*(data1_784+(alu9+-14)):0.0f);
          float val4 = ((alu3&alu0)?*(data1_784+(alu9+-15)):0.0f);
          float val5 = (alu4?*(data1_784+(alu9+1)):0.0f);
          float val6 = ((alu3&alu1)?*(data1_784+(alu9+13)):0.0f);
          float val7 = (alu1?*(data1_784+(alu9+14)):0.0f);
          float val8 = ((alu4&alu1)?*(data1_784+(alu9+15)):0.0f);
          float val9 = (*(data1_784+alu9));
          int alu10 = ((Lidx0*9)+(Lidx3*144));
          float val10 = (*(data2_288+(alu10+1)));
          float val11 = (*(data2_288+(alu10+108)));
          float val12 = (*(data2_288+(alu10+109)));
          float val13 = (*(data2_288+(alu10+110)));
          float val14 = (*(data2_288+(alu10+111)));
          float val15 = (*(data2_288+(alu10+112)));
          float val16 = (*(data2_288+(alu10+113)));
          float val17 = (*(data2_288+(alu10+114)));
          float val18 = (*(data2_288+(alu10+115)));
          float val19 = (*(data2_288+(alu10+116)));
          float val20 = (*(data2_288+(alu10+2)));
          float val21 = (*(data2_288+(alu10+3)));
          float val22 = (*(data2_288+(alu10+36)));
          float val23 = (*(data2_288+(alu10+37)));
          float val24 = (*(data2_288+(alu10+38)));
          float val25 = (*(data2_288+(alu10+39)));
          float val26 = (*(data2_288+(alu10+4)));
          float val27 = (*(data2_288+(alu10+40)));
          float val28 = (*(data2_288+(alu10+41)));
          float val29 = (*(data2_288+(alu10+42)));
          float val30 = (*(data2_288+(alu10+43)));
          float val31 = (*(data2_288+(alu10+44)));
          float val32 = (*(data2_288+(alu10+5)));
          float val33 = (*(data2_288+(alu10+6)));
          float val34 = (*(data2_288+(alu10+7)));
          float val35 = (*(data2_288+(alu10+72)));
          float val36 = (*(data2_288+(alu10+73)));
          float val37 = (*(data2_288+(alu10+74)));
          float val38 = (*(data2_288+(alu10+75)));
          float val39 = (*(data2_288+(alu10+76)));
          float val40 = (*(data2_288+(alu10+77)));
          float val41 = (*(data2_288+(alu10+78)));
          float val42 = (*(data2_288+(alu10+79)));
          float val43 = (*(data2_288+(alu10+8)));
          float val44 = (*(data2_288+(alu10+80)));
          float val45 = (*(data2_288+alu10));
          *(buf0+0) = ((*(buf0+0))+(val4*val45)+(val3*val10)+(val2*val20)+(val1*val21)+(val9*val26)+(val5*val32)+(val6*val33)+(val7*val34)+(val8*val43));
          *(buf0+1) = ((*(buf0+1))+(val4*val22)+(val3*val23)+(val2*val24)+(val1*val25)+(val9*val27)+(val5*val28)+(val6*val29)+(val7*val30)+(val8*val31));
          *(buf0+2) = ((*(buf0+2))+(val4*val35)+(val3*val36)+(val2*val37)+(val1*val38)+(val9*val39)+(val5*val40)+(val6*val41)+(val7*val42)+(val8*val44));
          *(buf0+3) = ((*(buf0+3))+(val4*val11)+(val3*val12)+(val2*val13)+(val1*val14)+(val9*val15)+(val5*val16)+(val6*val17)+(val7*val18)+(val8*val19));
        }
        int alu16 = (alu2+(Lidx3*784));
        float alu17 = ((*(buf0+0))+val0[0]);
        float alu18 = ((*(buf0+1))+val0[1]);
        float alu19 = ((*(buf0+2))+val0[2]);
        float alu20 = ((*(buf0+3))+val0[3]);
        float alu21 = ((0.0f<alu17)?alu17:0.0f);
        float alu22 = ((0.0f<alu18)?alu18:0.0f);
        float alu23 = ((0.0f<alu19)?alu19:0.0f);
        float alu24 = ((0.0f<alu20)?alu20:0.0f);
        *(data0_1568+(alu16+196)) = alu22;
        *(data0_1568+(alu16+392)) = alu23;
        *(data0_1568+(alu16+588)) = alu24;
        *(data0_1568+alu16) = alu21;
      }
    }
  }
}
