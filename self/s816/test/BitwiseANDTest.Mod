MODULE BitwiseANDTest;

VAR 
  a, b, result1, result2, result3, result4: INTEGER;

BEGIN
  (* Test AND with constants *)
  a := 255;  (* 11111111 in binary *)
  result1 := AND(a, 15);  (* AND with 00001111 = 15 *)
  
  a := 170;  (* 10101010 in binary *)
  result2 := AND(a, 85);  (* AND with 01010101 = 85 *)
  
  (* Test AND with variables *)
  a := 240;  (* 11110000 in binary *)
  b := 15;   (* 00001111 in binary *)
  result3 := AND(a, b);
  
  a := 136;  (* 10001000 in binary *)
  b := 68;   (* 01000100 in binary *)
  result4 := AND(a, b);

END BitwiseANDTest.