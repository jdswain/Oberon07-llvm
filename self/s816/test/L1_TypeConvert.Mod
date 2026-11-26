MODULE L1_TypeConvert;
  IMPORT Out;
  VAR b: BYTE;
      x: INTEGER;
BEGIN
  (* BYTE to INTEGER promotion *)
  b := 42;
  x := b;
  Out.Int(x, 1); Out.Ln();

  (* INTEGER to BYTE truncation *)
  x := 300;
  b := x MOD 256;
  Out.Int(b, 1); Out.Ln();

  (* BYTE in arithmetic becomes INTEGER *)
  b := 100;
  x := b + 200;
  Out.Int(x, 1); Out.Ln()
END L1_TypeConvert.
