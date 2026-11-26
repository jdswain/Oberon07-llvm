MODULE L18_DerefWrite; (* an imported pointer variable is read-only, the
   record it points to is not: a field, p^ as a VAR parameter *)
  IMPORT Out, M := L18_LIMid, B := L18_LIBase;
BEGIN
  M.p.x := 12; Out.Int(M.p.x, 5);
  Out.Int(B.Get(M.p^), 5);
  M.p^.x := 13; Out.Int(B.Get(M.p^), 5);
  M.e.y := 14; Out.Int(M.e.y, 5); Out.Ln
END L18_DerefWrite.
