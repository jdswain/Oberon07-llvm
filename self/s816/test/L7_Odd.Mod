MODULE L7_Odd;
  IMPORT Out;
  VAR x: INTEGER;
BEGIN
  x := 0;
  IF ODD(x) THEN Out.Char("T") ELSE Out.Char("F") END; Out.Ln();
  x := 1;
  IF ODD(x) THEN Out.Char("T") ELSE Out.Char("F") END; Out.Ln();
  x := 2;
  IF ODD(x) THEN Out.Char("T") ELSE Out.Char("F") END; Out.Ln();
  x := 3;
  IF ODD(x) THEN Out.Char("T") ELSE Out.Char("F") END; Out.Ln();
  x := -1;
  IF ODD(x) THEN Out.Char("T") ELSE Out.Char("F") END; Out.Ln()
END L7_Odd.
