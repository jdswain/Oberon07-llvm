MODULE L8_RealCompare;
  IMPORT Out;
  VAR a, b: REAL;
BEGIN
  a := 3.0; b := 2.0;
  IF a = b THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END; Out.Ln();
  IF a # b THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END; Out.Ln();
  IF a < b THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END; Out.Ln();
  IF a > b THEN Out.Int(1, 1) ELSE Out.Int(0, 1) END; Out.Ln()
END L8_RealCompare.
