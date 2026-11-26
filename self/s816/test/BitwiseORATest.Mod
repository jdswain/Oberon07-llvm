MODULE BitwiseORATest;

VAR 
  a, b, result1, result2, result3, result4: BYTE;

BEGIN
  (* Test ORA with constants *)
  a := 240;  (* 11110000 in binary *)
  result1 := ORA(a, 15);  (* ORA with 00001111 = 255 *)
  
  a := 170;  (* 10101010 in binary *)
  result2 := ORA(a, 85);  (* ORA with 01010101 = 255 *)
  
  (* Test ORA with variables *)
  a := 136;  (* 10001000 in binary *)
  b := 68;   (* 01000100 in binary *)
  result3 := ORA(a, b);  (* Should be 11001100 = 204 *)
  
  a := 0;    (* 00000000 in binary *)
  b := 255;  (* 11111111 in binary *)
  result4 := ORA(a, b);  (* Should be 255 *)

END BitwiseORATest.