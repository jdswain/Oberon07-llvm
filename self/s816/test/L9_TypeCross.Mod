MODULE L9_TypeCross;
  IMPORT Out, L9_TypeLib;

  VAR
    b: BYTE;
    c: CHAR;
    bl: BOOLEAN;
    arr: ARRAY 5 OF INTEGER;

  PROCEDURE PrintX*(x: INTEGER);
  BEGIN Out.Int(x, 0); Out.Ln
  END PrintX;

BEGIN
  (* 1. Read exported short-type variables *)
  Out.Int(L9_TypeLib.byteVar, 0); Out.Ln;
  Out.Int(ORD(L9_TypeLib.charVar), 0); Out.Ln;
  Out.Bool(L9_TypeLib.boolVar); Out.Ln;

  (* 2. Value params: byte values in word registers *)
  L9_TypeLib.PrintByte(7);
  L9_TypeLib.PrintChar("A");
  L9_TypeLib.PrintBool(FALSE);
  L9_TypeLib.PrintSet({0, 3});

  (* 3. VAR params: store through pointer for byte-sized types *)
  b := 0;
  L9_TypeLib.SetByte(b, 99);
  Out.Int(b, 0); Out.Ln;

  c := " ";
  L9_TypeLib.SetChar(c, "X");
  Out.Int(ORD(c), 0); Out.Ln;

  bl := TRUE;
  L9_TypeLib.SetBool(bl, FALSE);
  Out.Bool(bl); Out.Ln;

  (* 4. Functions returning short types *)
  Out.Int(L9_TypeLib.GetByte(), 0); Out.Ln;
  Out.Int(ORD(L9_TypeLib.GetChar()), 0); Out.Ln;
  Out.Bool(L9_TypeLib.GetBool()); Out.Ln;

  (* 5. Open array param across modules *)
  arr[0] := 10; arr[1] := 20; arr[2] := 30; arr[3] := 40; arr[4] := 50;
  Out.Int(L9_TypeLib.SumArray(arr), 0); Out.Ln;

  (* 6. Procedure variable cross-module *)
  L9_TypeLib.Apply(PrintX, 77)
END L9_TypeCross.
