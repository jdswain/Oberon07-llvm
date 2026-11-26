MODULE ShiftASLTest;

VAR 
  a, result1, result2, result3, result4: INTEGER;

BEGIN
  (* Test ASL single shift *)
  a := 5;         (* 00000101 in binary *)
  result1 := ASL(a, 1);   (* Should be 10 (00001010) *)
  
  a := 128;       (* 10000000 in binary *)
  result2 := ASL(a, 1);   (* Should be 0 (overflow) *)
  
  (* Test ASL multiple shifts *)
  a := 3;         (* 00000011 in binary *)
  result3 := ASL(a, 2); (* Should be 12 (00001100) - shift left 2 bits *)
  
  a := 7;         (* 00000111 in binary *)
  result4 := ASL(a, 4); (* Should be 112 (01110000) - shift left 4 bits *)

END ShiftASLTest.