MODULE CtorsTests;
  IMPORT Ctors, TestRunner;

  PROCEDURE TestConstruct*();
    VAR c: Ctors.Conn;
  BEGIN
    (* cross-module constructor call *)
    c := Ctors.Conn.Create(3, 7);
    IF (c.host = 3) & (c.port = 7) & (c.Sum() = 10) THEN
      TestRunner.Pass
    ELSE
      TestRunner.Fail
    END
  END TestConstruct;

  PROCEDURE TestNamedConstructors*();
    VAR c: Ctors.Conn;
  BEGIN
    c := Ctors.Conn.CreateDefault();
    IF (c.host = 1) & (c.port = 80) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNamedConstructors;

  PROCEDURE TestFromDefiningModule*();
    VAR c: Ctors.Conn;
  BEGIN
    c := Ctors.MakeDefault();
    IF c.Sum() = 81 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFromDefiningModule;

  PROCEDURE TestInheritedConstructor*();
    VAR h: Ctors.HConn;
        c: Ctors.Conn;
  BEGIN
    (* HConn declares no initialisers: Conn's Create is inherited, but
       must construct an HConn — extra field zeroed, derived type tag *)
    h := Ctors.HConn.Create(2, 9);
    IF (h.host = 2) & (h.port = 9) & (h.path = 0) THEN
      TestRunner.Pass
    ELSE
      TestRunner.Fail
    END;
    c := Ctors.HConn.Create(4, 5);
    IF c IS Ctors.HConn THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestInheritedConstructor;

  PROCEDURE TestHidingConstructor*();
    VAR s: Ctors.SConn;
  BEGIN
    s := Ctors.SConn.CreateWithKey(5);
    IF (s.key = 5) & (s.Sum() = 457) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestHidingConstructor;

  PROCEDURE TestDispatchOnConstructed*();
    VAR c: Ctors.Conn;
  BEGIN
    (* constructed as SConn, dispatched through the base static type *)
    c := Ctors.SConn.CreateWithKey(1);
    IF c.Sum() = 453 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDispatchOnConstructed;

  PROCEDURE SumOf(c: Ctors.Conn): INTEGER;
  BEGIN
    RETURN c.Sum()
  END SumOf;

  PROCEDURE TestConstructorAsArgument*();
  BEGIN
    IF SumOf(Ctors.Conn.Create(20, 22)) = 42 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestConstructorAsArgument;

END CtorsTests.
