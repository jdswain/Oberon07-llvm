MODULE ShiftLSRTest;

VAR 
  a, result1, result2, result3, result4: INTEGER;

BEGIN
  (* Test LSR single shift *)
  a := 10;        (* 00001010 in binary *)
  result1 := LSR(a, 1);   (* Should be 5 (00000101) *)
  
  a := 1;         (* 00000001 in binary *)
  result2 := LSR(a, 1);   (* Should be 0 (00000000) *)
  
  (* Test LSR multiple shifts *)
  a := 48;        (* 00110000 in binary *)
  result3 := LSR(a, 2); (* Should be 12 (00001100) - shift right 2 bits *)
  
  a := 240;       (* 11110000 in binary *)
  result4 := LSR(a, 4); (* Should be 15 (00001111) - shift right 4 bits *)

END ShiftLSRTest.