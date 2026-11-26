MODULE L14_ConstArray;
  IMPORT Out;

  CONST
    bytes = ARRAY OF BYTE {10, 20, 30, 40, 50};
    words = ARRAY OF INTEGER {100, 200, 300, 400, 500};
    hex = ARRAY OF BYTE {0, 255, 128, 127};

  VAR i: INTEGER;

BEGIN
  (* Test ARRAY OF BYTE constant access with constant index *)
  Out.Int(bytes[0], 4); Out.Int(bytes[2], 4); Out.Int(bytes[4], 4); Out.Ln;

  (* Test ARRAY OF BYTE with variable index *)
  i := 0;
  WHILE i < 5 DO
    Out.Int(bytes[i], 4);
    INC(i)
  END;
  Out.Ln;

  (* Test ARRAY OF INTEGER constant access *)
  i := 0;
  WHILE i < 5 DO
    Out.Int(words[i], 6);
    INC(i)
  END;
  Out.Ln;

  (* Test hex byte values *)
  i := 0;
  WHILE i < 4 DO
    Out.Int(hex[i], 4);
    INC(i)
  END;
  Out.Ln;
END L14_ConstArray.
