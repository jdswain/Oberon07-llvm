MODULE BitwiseEORTest;

VAR 
  a, b, result1, result2, result3, result4: BYTE;

BEGIN
  (* Test EOR with constants *)
  a := 255;  (* 11111111 in binary *)
  result1 := EOR(a, 15);  (* EOR with 00001111 = 240 *)
  
  a := 170;  (* 10101010 in binary *)
  result2 := EOR(a, 85);  (* EOR with 01010101 = 255 *)
  
  (* Test EOR with variables *)
  a := 240;  (* 11110000 in binary *)
  b := 15;   (* 00001111 in binary *)
  result3 := EOR(a, b);  (* Should be 255 *)
  
  a := 136;  (* 10001000 in binary *)
  b := 68;   (* 01000100 in binary *)
  result4 := EOR(a, b);  (* Should be 11001100 = 204 *)

END BitwiseEORTest.