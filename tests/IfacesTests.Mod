MODULE IfacesTests;
  IMPORT Ifaces, TestRunner;

  TYPE
    (* a record in THIS module implementing an IMPORTED interface — the
       base module dispatches implementations it has never seen *)
    Disc*     = POINTER TO DiscDesc;
    DiscDesc* = RECORD IMPLEMENTS Ifaces.Shape
      r*: INTEGER
    END;

  PROCEDURE (d: Disc) Area* (): INTEGER;
  BEGIN
    RETURN 3 * d.r * d.r
  END Area;

  PROCEDURE (d: Disc) Kind* (): INTEGER;
  BEGIN
    RETURN 2
  END Kind;

  PROCEDURE TestDispatch*();
    VAR s: Ifaces.Shape;
        b: Ifaces.Box;
  BEGIN
    b := Ifaces.NewBox(3, 4);
    s := b;
    IF (s.Area() = 12) & (s.Kind() = 1) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDispatch;

  PROCEDURE TestInclusion*();
    VAR sc: Ifaces.Scaled;
        s: Ifaces.Shape;
        b: Ifaces.Box;
  BEGIN
    b := Ifaces.NewBox(3, 4);
    sc := b;
    sc.Scale(2);
    (* included members callable through the including interface *)
    IF sc.Area() = 48 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    (* implementing Scaled implements the included Shape too *)
    s := b;
    IF s.Area() = 48 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestInclusion;

  PROCEDURE TestParamAndResult*();
    VAR s: Ifaces.Shape;
  BEGIN
    (* pointer converts at the argument, owned temp released after call *)
    IF Ifaces.AreaOf(Ifaces.NewBox(2, 5)) = 10 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    (* interface-typed function result *)
    s := Ifaces.MakeShape(6, 7);
    IF s.Area() = 42 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestParamAndResult;

  PROCEDURE TestCrossModuleImpl*();
    VAR d: Disc;
  BEGIN
    NEW(d); d.r := 2;
    (* Ifaces.AreaOf knows nothing about Disc *)
    IF Ifaces.AreaOf(d) = 12 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCrossModuleImpl;

  PROCEDURE TestNarrowing*();
    VAR s: Ifaces.Shape;
        b: Ifaces.Box;
        d: Disc;
  BEGIN
    s := Ifaces.MakeShape(2, 3);
    IF s IS Ifaces.Box THEN TestRunner.Pass ELSE TestRunner.Fail END;
    IF ~(s IS Disc) THEN TestRunner.Pass ELSE TestRunner.Fail END;
    b := s(Ifaces.Box);
    IF b.w = 2 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    NEW(d); d.r := 5;
    s := d;
    IF s(Disc).r = 5 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNarrowing;

  PROCEDURE TestNilAndEquality*();
    VAR s, t: Ifaces.Shape;
        b: Ifaces.Box;
  BEGIN
    (* locals start as the null fat value *)
    IF s = NIL THEN TestRunner.Pass ELSE TestRunner.Fail END;
    b := Ifaces.NewBox(1, 1);
    s := b;
    IF s # NIL THEN TestRunner.Pass ELSE TestRunner.Fail END;
    t := b;
    IF s = t THEN TestRunner.Pass ELSE TestRunner.Fail END;
    s := NIL;
    IF s = NIL THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNilAndEquality;

END IfacesTests.
