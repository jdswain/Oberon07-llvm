MODULE L18_A_ConstArrChar; (* ARRAY OF CHAR constants of one-character
   strings; elements whose expressions use a string; a constant array
   for a value parameter *)
  IMPORT Out;
  CONST Abc = ARRAY OF CHAR {"A", "B", 43X, "D"};
    Ords = ARRAY OF INTEGER {ORD("a"), 2, ORD("c")};
    Days = ARRAY OF INTEGER {31, 28, 31};
  VAR i: INTEGER;
  PROCEDURE Sum(a: ARRAY OF INTEGER): INTEGER;
    VAR i, s: INTEGER;
  BEGIN s := 0; FOR i := 0 TO LEN(a) - 1 DO s := s + a[i] END;
    RETURN s
  END Sum;
BEGIN
  FOR i := 0 TO LEN(Abc) - 1 DO Out.Char(Abc[i]) END;
  Out.Int(LEN(Abc), 2);
  FOR i := 0 TO LEN(Ords) - 1 DO Out.Int(Ords[i], 4) END;
  Out.Int(Sum(Days), 4); Out.Ln
END L18_A_ConstArrChar.
