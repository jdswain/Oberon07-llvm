MODULE L4_PointerNil;
  IMPORT Out;
  TYPE Rec = RECORD x: INTEGER END;
       Ptr = POINTER TO Rec;
  VAR p: Ptr;

BEGIN
  p := NIL;
  IF p = NIL THEN Out.Int(1, 1); Out.Ln() END;
  IF p # NIL THEN Out.Int(0, 1) ELSE Out.Int(2, 1); Out.Ln() END
END L4_PointerNil.
