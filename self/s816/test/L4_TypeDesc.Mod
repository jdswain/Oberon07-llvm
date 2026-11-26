MODULE L4_TypeDesc;
  IMPORT Out, SYSTEM;
  TYPE Node = RECORD val: INTEGER; next: POINTER TO Node END;
  VAR first: INTEGER;
      tdBase, w: INTEGER;
BEGIN
  (* TD layout: size(2) + 3*ancestor(4 each) + ptr fields + terminator *)
  (* = 2 + 12 = 14 bytes header, then ptr field offsets, then 0xFFFF *)
  (* Total TD: 14 + 2 + 2 = 18 bytes = 9 two-byte entries *)
  tdBase := SYSTEM.ADR(first) - 18;
  SYSTEM.GET(0, tdBase, w);      Out.Int(w, 1); Out.Ln;  (* size = 6 *)
  SYSTEM.GET(0, tdBase + 2, w);  Out.Int(w, 1); Out.Ln;  (* ancestor[0] lo = -1 (0xFFFF) *)
  SYSTEM.GET(0, tdBase + 14, w); Out.Int(w, 1); Out.Ln;  (* ptr field offset = 2 *)
  SYSTEM.GET(0, tdBase + 16, w); Out.Int(w, 1); Out.Ln   (* terminator = -1 (0xFFFF) *)
END L4_TypeDesc.
