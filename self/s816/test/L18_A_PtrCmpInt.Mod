MODULE L18_A_PtrCmpInt; (* a pointer compared with an integer *)
  TYPE Node = POINTER TO NodeDesc; NodeDesc = RECORD key: INTEGER END;
  VAR p: Node; b: BOOLEAN;
BEGIN b := p = 5
END L18_A_PtrCmpInt.
