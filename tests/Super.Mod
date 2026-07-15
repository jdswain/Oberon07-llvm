MODULE Super;
  (* SUPER calls (DDR-006): static binding in the immediate base. A
     two-level chain proves an intermediate override is never skipped.
     Note the declaration order: all of A's methods precede B's new
     methods — an extension taking a new vtable slot freezes its
     ancestors' slot layout (single-pass rule). *)

  TYPE
    A*     = POINTER TO ADesc;
    ADesc* = RECORD tag*: INTEGER END;
    B*     = POINTER TO BDesc;
    BDesc* = RECORD (ADesc) END;
    C*     = POINTER TO CDesc;
    CDesc* = RECORD (BDesc) END;

  PROCEDURE (a: A) Describe* (): INTEGER;
  BEGIN
    RETURN 1
  END Describe;

  PROCEDURE (a: A) Tag* (): INTEGER;
  BEGIN
    RETURN a.tag
  END Tag;

  PROCEDURE (a: A) Bump* ();
  BEGIN
    INC(a.tag)
  END Bump;

  PROCEDURE (b: B) Describe* (): INTEGER OVERRIDE;
  BEGIN
    RETURN SUPER.Describe() * 10 + 2
  END Describe;

  (* super call to a method the extension does not override *)
  PROCEDURE (b: B) TagPlus* (): INTEGER;
  BEGIN
    RETURN SUPER.Tag() + 1
  END TagPlus;

  (* proper procedure: SUPER call in statement position *)
  PROCEDURE (b: B) Bump* () OVERRIDE;
  BEGIN
    SUPER.Bump();
    INC(b.tag)
  END Bump;

  PROCEDURE (c: C) Describe* (): INTEGER OVERRIDE;
  BEGIN
    (* SUPER means B here — an override in the middle of the chain *)
    RETURN SUPER.Describe() * 10 + 3
  END Describe;

  PROCEDURE NewA* (t: INTEGER): A;
    VAR a: A;
  BEGIN
    NEW(a); a.tag := t;
    RETURN a
  END NewA;

  PROCEDURE NewB* (t: INTEGER): B;
    VAR b: B;
  BEGIN
    NEW(b); b.tag := t;
    RETURN b
  END NewB;

  PROCEDURE NewC* (t: INTEGER): C;
    VAR c: C;
  BEGIN
    NEW(c); c.tag := t;
    RETURN c
  END NewC;

END Super.
