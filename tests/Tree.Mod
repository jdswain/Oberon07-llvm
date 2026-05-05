MODULE Tree;

  TYPE
    Node* = POINTER TO NodeDesc;
    NodeDesc* = RECORD
      val*: INTEGER;
      left*, right*: Node
    END;

  PROCEDURE Make*(v: INTEGER): Node;
    VAR n: Node;
  BEGIN
    NEW(n);
    n.val := v;
    n.left := NIL;
    n.right := NIL;
    RETURN n
  END Make;

  PROCEDURE Sum*(t: Node): INTEGER;
    VAR s: INTEGER;
  BEGIN
    s := 0;
    IF t # NIL THEN
      s := t.val + Sum(t.left) + Sum(t.right)
    END;
    RETURN s
  END Sum;

END Tree.
