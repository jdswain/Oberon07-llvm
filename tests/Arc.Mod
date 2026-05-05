MODULE Arc;
  (* Exercises ARC: builds a list, drops it, verifies reclamation. *)

  TYPE
    List* = POINTER TO ListDesc;
    ListDesc* = RECORD
      val*: INTEGER;
      next*: List
    END;

  VAR head*: List;

  (* Build a list of n nodes [n, n-1, ..., 1] starting from head. Always
     stores via the global root, so reclamation is deterministic when
     we drop head. *)
  PROCEDURE Build*(n: INTEGER);
    VAR i: INTEGER; node: List;
  BEGIN
    head := NIL;
    FOR i := 1 TO n DO
      NEW(node);
      node.val := i;
      node.next := head;
      head := node
    END
  END Build;

  PROCEDURE Sum*(): INTEGER;
    VAR p: List; s: INTEGER;
  BEGIN
    p := head; s := 0;
    WHILE p # NIL DO
      s := s + p.val;
      p := p.next
    END;
    RETURN s
  END Sum;

  PROCEDURE Drop*();
  BEGIN
    head := NIL    (* releases entire chain via cascading oc_release *)
  END Drop;

END Arc.
