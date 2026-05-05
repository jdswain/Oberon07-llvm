MODULE StackRec;
  (* Stack-allocated record holding pointer fields. ARC must release the
     fields' targets when the procedure returns, even though the record
     itself is on the stack. *)

  TYPE
    Box*     = POINTER TO BoxDesc;
    BoxDesc* = RECORD val*: INTEGER END;

    Pair = RECORD
      a, b: Box
    END;

  PROCEDURE Make*(v: INTEGER): Box;
    VAR p: Box;
  BEGIN
    NEW(p);
    p.val := v;
    RETURN p
  END Make;

  PROCEDURE UseLocalPair*(): INTEGER;
    VAR pair: Pair; sum: INTEGER;
  BEGIN
    pair.a := Make(10);
    pair.b := Make(20);
    sum := pair.a.val + pair.b.val;
    (* on procedure exit, both pair.a and pair.b targets must be released *)
    RETURN sum
  END UseLocalPair;

  PROCEDURE LeakIfBroken*(n: INTEGER);
    VAR pair: Pair; i: INTEGER;
  BEGIN
    FOR i := 1 TO n DO
      pair.a := Make(i);
      pair.b := Make(i * 10)
      (* iteration overwrite must release prior pair.a and pair.b *)
    END
    (* on exit, final pair.a and pair.b must be released *)
  END LeakIfBroken;

END StackRec.
