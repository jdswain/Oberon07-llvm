MODULE L2_CharArray;
  IMPORT Out;
  VAR buf: ARRAY 8 OF CHAR;
BEGIN
  buf[0] := "H"; buf[1] := "i"; buf[2] := 0X;
  Out.String(buf); Out.Ln()
END L2_CharArray.
