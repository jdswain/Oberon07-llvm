MODULE L1_ByteType;
  IMPORT Out;
  VAR b1, b2: BYTE;
      x: INTEGER;
BEGIN
  b1 := 42;
  b2 := 200;
  Out.Int(b1, 1); Out.Ln();
  Out.Int(b2, 1); Out.Ln();
  (* BYTE arithmetic *)
  x := b1 + b2;
  Out.Int(x, 1); Out.Ln();
  (* BYTE assignment *)
  b1 := 255;
  Out.Int(b1, 1); Out.Ln()
END L1_ByteType.
