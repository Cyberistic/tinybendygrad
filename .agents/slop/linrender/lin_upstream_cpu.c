
void r_4_5_3(float* restrict data0_20, float* restrict data1_12, float* restrict data2_15) {
  for (int Lidx1 = 0; Lidx1 < 4; Lidx1++) {
    int alu0 = (Lidx1*3);
    float val0 = (*(data1_12+(alu0+1)));
    float val1 = (*(data1_12+(alu0+2)));
    float val2 = (*(data1_12+alu0));
    for (int Lidx2 = 0; Lidx2 < 5; Lidx2++) {
      float val3 = (*(data2_15+(Lidx2+10)));
      float val4 = (*(data2_15+(Lidx2+5)));
      float val5 = (*(data2_15+Lidx2));
      *(data0_20+((Lidx1*5)+Lidx2)) = ((val2*val5)+(val0*val4)+(val1*val3));
    }
  }
}
