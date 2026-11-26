MODULE L18_LateImport; (* a module imported directly after an earlier
   import brought it in: one module, its types those already read *)
  IMPORT Out, M := L18_LIMid, B := L18_LIBase;
  VAR q: B.P; d: B.D;
BEGIN
  q := M.Make(); B.Show(q); B.Show(M.p);
  q := M.e; B.Show(q);
  IF q IS B.E THEN Out.Int(q(B.E).y, 5) END;
  d := M.p^; Out.Int(B.Get(d), 5); Out.Int(B.k, 5); Out.Ln
END L18_LateImport.
