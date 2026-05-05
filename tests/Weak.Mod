MODULE Weak;
  (* Cycle-breaking via WEAK POINTER. A parent–child tree where the
     child's back-edge to the parent is weak — releasing the parent
     reclaims the whole graph; without WEAK it would leak. *)

  TYPE
    Node*     = POINTER TO NodeDesc;
    NodeDesc* = RECORD
      val*:    INTEGER;
      child*:  Node;                       (* strong owning ref *)
      parent*: WEAK POINTER TO NodeDesc    (* weak back-edge *)
    END;

  VAR root*: Node;

  PROCEDURE Build*();
    VAR a, b, c: Node;
  BEGIN
    NEW(a); a.val := 1;
    NEW(b); b.val := 2; a.child := b; b.parent := a;
    NEW(c); c.val := 3; b.child := c; c.parent := b;
    root := a
  END Build;

  (* Walk via strong child links — totals 1+2+3 = 6 *)
  PROCEDURE Sum*(): INTEGER;
    VAR p: Node; s: INTEGER;
  BEGIN
    s := 0; p := root;
    WHILE p # NIL DO s := s + p.val; p := p.child END;
    RETURN s
  END Sum;

  PROCEDURE Drop*();
  BEGIN
    root := NIL    (* should free a, b, c — weak parent edges don't pin them *)
  END Drop;

END Weak.
