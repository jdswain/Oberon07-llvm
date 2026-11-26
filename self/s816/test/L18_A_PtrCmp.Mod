MODULE L18_A_PtrCmp; (* a pointer compared with an unrelated pointer *)
  TYPE Node = POINTER TO NodeDesc; NodeDesc = RECORD key: INTEGER END;
    Tree = POINTER TO TreeDesc; TreeDesc = RECORD left, right: Tree END;
  VAR p: Node; t: Tree; b: BOOLEAN;
BEGIN b := p = t
END L18_A_PtrCmp.
