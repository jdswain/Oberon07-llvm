MODULE ArrPtrs;
  (* ARRAY OF POINTER local should release each element on scope exit. *)

  TYPE
    Box*     = POINTER TO BoxDesc;
    BoxDesc* = RECORD val*: INTEGER END;

  PROCEDURE Make*(v: INTEGER): Box;
    VAR p: Box;
  BEGIN
    NEW(p); p.val := v;
    RETURN p
  END Make;

  PROCEDURE TestArrayOfPtr*(): INTEGER;
    VAR arr: ARRAY 5 OF Box; i, sum: INTEGER;
  BEGIN
    FOR i := 0 TO 4 DO arr[i] := Make(i + 1) END;
    sum := 0;
    FOR i := 0 TO 4 DO sum := sum + arr[i].val END;
    RETURN sum
    (* on exit, all 5 boxes must be released *)
  END TestArrayOfPtr;

  PROCEDURE TestReplacing*(): INTEGER;
    VAR arr: ARRAY 3 OF Box; i: INTEGER;
  BEGIN
    FOR i := 0 TO 2 DO arr[i] := Make(i) END;
    (* overwrite each slot with a fresh Box; old must be released. *)
    FOR i := 0 TO 2 DO arr[i] := Make(i + 100) END;
    RETURN arr[0].val + arr[1].val + arr[2].val
  END TestReplacing;

END ArrPtrs.
