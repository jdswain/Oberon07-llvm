MODULE ArcCons;
  (* Tests three ARC scenarios:
     A) record-to-record assignment with pointer fields
     B) function-call result consumed in non-store contexts (NIL test)
     C) function-call result passed as parameter to another call.
     All three should produce zero leaks. *)

  TYPE
    Box*     = POINTER TO BoxDesc;
    BoxDesc* = RECORD val*: INTEGER END;

    Pair = RECORD a, b: Box END;

  PROCEDURE Make*(v: INTEGER): Box;
    VAR p: Box;
  BEGIN
    NEW(p); p.val := v;
    RETURN p
  END Make;

  (* Test (B): consume function-call result in NIL relation. *)
  PROCEDURE TestBeNonNil*(): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    r := Make(7) # NIL;     (* Make(7)'s +1 must be released here *)
    RETURN r
  END TestBeNonNil;

  (* Test (C): function-call result passed as argument to another call. *)
  PROCEDURE Identity*(b: Box): Box;
  BEGIN
    RETURN b
  END Identity;

  PROCEDURE TestCallChain*(): INTEGER;
    VAR p: Box; v: INTEGER;
  BEGIN
    p := Identity(Make(99));    (* Make's +1 transferred to Identity's b *)
    v := p.val;
    RETURN v
  END TestCallChain;

  (* Test (A): record-to-record assignment with pointer fields. *)
  PROCEDURE TestRecAssign*(): INTEGER;
    VAR a, b: Pair; v: INTEGER;
  BEGIN
    a.a := Make(11);
    a.b := Make(22);
    b := a;                  (* both Boxes get retained; b's prior NILs released *)
    v := b.a.val + b.b.val;
    RETURN v
  END TestRecAssign;

END ArcCons.
