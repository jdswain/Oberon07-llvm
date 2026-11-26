MODULE L18_LIMid; (* for L18_LateImport: re-exports L18_LIBase's types *)
  IMPORT L18_LIBase, HeapManager;
  VAR p*: L18_LIBase.P; e*: L18_LIBase.E;
  PROCEDURE Make*(): L18_LIBase.P;
    VAR q: L18_LIBase.P;
  BEGIN NEW(q); q.x := 42; RETURN q
  END Make;
BEGIN NEW(p); p.x := 5; NEW(e); e.x := 3; e.y := 4
END L18_LIMid.
