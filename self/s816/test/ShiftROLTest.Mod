MODULE ShiftROLTest;

VAR 
  a, result1, result2, result3, result4: INTEGER;

BEGIN
  (* Test ROL single shift *)
  a := 129;       (* 10000001 in binary *)
  result1 := ROL(a, 1);   (* Should be 3 (00000011) - bit rotated from MSB to LSB *)
  
  a := 64;        (* 01000000 in binary *)
  result2 := ROL(a, 1);   (* Should be 128 (10000000) *)
  
  (* Test ROL multiple shifts *)
  a := 15;        (* 00001111 in binary *)
  result3 := ROL(a, 2); (* Should be 60 (00111100) - rotate left 2 bits *)
  
  a := 3;         (* 00000011 in binary *)
  result4 := ROL(a, 4); (* Should be 48 (00110000) - rotate left 4 bits *)

END ShiftROLTest.