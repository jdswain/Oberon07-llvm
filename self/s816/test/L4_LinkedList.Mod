MODULE L4_LinkedList;
  IMPORT Out, HeapManager;
  TYPE Node = RECORD val: INTEGER; next: POINTER TO Node END;
       NodePtr = POINTER TO Node;
  VAR head, n: NodePtr;
      i: INTEGER;

BEGIN
  head := NIL;
  FOR i := 3 TO 1 BY -1 DO
    NEW(n);
    n.val := i;
    n.next := head;
    head := n
  END;
  n := head;
  WHILE n # NIL DO
    Out.Int(n.val, 1); Out.Ln();
    n := n.next
  END
END L4_LinkedList.
