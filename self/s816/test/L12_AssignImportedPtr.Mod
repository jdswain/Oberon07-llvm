MODULE L12_AssignImportedPtr; (* the imported pointer variable itself stays read-only *)
  IMPORT M := L18_LIMid, B := L18_LIBase;
  VAR q: B.P;
BEGIN M.p := q
END L12_AssignImportedPtr.
