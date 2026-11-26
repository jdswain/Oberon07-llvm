MODULE L18_D_OpenAssign; (* an open array assigned to a fixed one: LEN checked, trap 1 *)
  IMPORT Out;
  VAR g: ARRAY 3 OF INTEGER; b4: ARRAY 4 OF INTEGER; b2: ARRAY 2 OF INTEGER;
    c5: ARRAY 5 OF CHAR; c3: ARRAY 3 OF CHAR; after: INTEGER;
  PROCEDURE I(s: ARRAY OF INTEGER);
    VAR a: ARRAY 3 OF INTEGER;
  BEGIN a[0] := 0; a[1] := 0; a[2] := 0; a := s; Out.Int(a[0] + a[1] + a[2], 4)
  END I;
  PROCEDURE C(s: ARRAY OF CHAR);
    VAR a: ARRAY 4 OF CHAR; z: INTEGER;
  BEGIN z := 77; a := s; Out.String(a); Out.Int(z, 4); Out.Ln
  END C;
BEGIN after := 99;
  g[0] := 1; g[1] := 2; g[2] := 3; I(g);
  b2[0] := 10; b2[1] := 20; I(b2); Out.Ln;
  c3 := "ab"; C(c3);
  c5 := "wxyz"; C(c5)
END L18_D_OpenAssign.
