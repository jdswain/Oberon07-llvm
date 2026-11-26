MODULE L9_TypeLib;
  IMPORT Out;

  TYPE IntProc* = PROCEDURE(x: INTEGER);

  VAR
    byteVar*: BYTE;
    charVar*: CHAR;
    boolVar*: BOOLEAN;
    setVar*: SET;

  (* Value parameter procedures - tests byte values passed as words *)
  PROCEDURE PrintByte*(b: BYTE);
  BEGIN Out.Int(b, 0); Out.Ln
  END PrintByte;

  PROCEDURE PrintChar*(c: CHAR);
  BEGIN Out.Int(ORD(c), 0); Out.Ln
  END PrintChar;

  PROCEDURE PrintBool*(b: BOOLEAN);
  BEGIN Out.Bool(b); Out.Ln
  END PrintBool;

  PROCEDURE PrintSet*(s: SET);
  BEGIN
    IF 0 IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
    IF 3 IN s THEN Out.Char("Y") ELSE Out.Char("N") END;
    Out.Ln
  END PrintSet;

  (* VAR parameter procedures - tests store through pointer for byte-sized types *)
  PROCEDURE SetByte*(VAR b: BYTE; val: BYTE);
  BEGIN b := val
  END SetByte;

  PROCEDURE SetChar*(VAR c: CHAR; val: CHAR);
  BEGIN c := val
  END SetChar;

  PROCEDURE SetBool*(VAR b: BOOLEAN; val: BOOLEAN);
  BEGIN b := val
  END SetBool;

  (* Functions returning short types *)
  PROCEDURE GetByte*(): BYTE;
  BEGIN RETURN byteVar
  END GetByte;

  PROCEDURE GetChar*(): CHAR;
  BEGIN RETURN charVar
  END GetChar;

  PROCEDURE GetBool*(): BOOLEAN;
  BEGIN RETURN boolVar
  END GetBool;

  (* Open array parameter - tests pointer+length across modules *)
  PROCEDURE SumArray*(VAR a: ARRAY OF INTEGER): INTEGER;
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 0 TO LEN(a) - 1 DO
      s := s + a[i]
    END;
    RETURN s
  END SumArray;

  (* Procedure variable parameter - tests proc var across modules *)
  PROCEDURE Apply*(p: IntProc; x: INTEGER);
  BEGIN p(x)
  END Apply;

BEGIN
  byteVar := 42;
  charVar := "Z";
  boolVar := TRUE;
  setVar := {1, 3, 5}
END L9_TypeLib.
