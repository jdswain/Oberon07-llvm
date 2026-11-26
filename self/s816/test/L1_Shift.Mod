MODULE L1_Shift;
  IMPORT Out;
  VAR x, r: INTEGER;
BEGIN
  x := 1;
  (* ASL - shift left *)
  r := ASL(x, 4);
  Out.Hex(r); Out.Ln();

  (* LSR - logical shift right *)
  x := 0FF00H;
  r := LSR(x, 8);
  Out.Hex(r); Out.Ln();

  (* ASL by 1 = multiply by 2 *)
  x := 25;
  r := ASL(x, 1);
  Out.Int(r, 1); Out.Ln();

  (* LSR by 1 = divide by 2 for positive *)
  x := 100;
  r := LSR(x, 1);
  Out.Int(r, 1); Out.Ln()
END L1_Shift.
