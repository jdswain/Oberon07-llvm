MODULE MethodsTests;
  IMPORT Methods, MethBase, MethExt, TestRunner;

  PROCEDURE TestBaseMethod*();
    VAR s: Methods.Shape;
  BEGIN
    NEW(s); s.id := 1;
    IF (s.Area() = 0) & (s.Kind() = 1) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestBaseMethod;

  PROCEDURE TestOverrideDispatch*();
    VAR s: Methods.Shape;
  BEGIN
    (* static type Shape, dynamic type Circle: must hit the override *)
    s := Methods.NewCircle(2);
    IF s.Area() = 12 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestOverrideDispatch;

  PROCEDURE TestInheritedMethod*();
    VAR s: Methods.Shape;
  BEGIN
    (* Circle does not override Kind: base implementation via Circle tag *)
    s := Methods.NewCircle(2);
    IF s.Kind() = 1 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestInheritedMethod;

  PROCEDURE TestSecondExtension*();
    VAR s: Methods.Shape;
  BEGIN
    s := Methods.NewSquare(3);
    IF (s.Area() = 9) & (s.Kind() = 2) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSecondExtension;

  PROCEDURE TestDispatchFromOtherProc*();
    VAR s: Methods.Shape;
  BEGIN
    s := Methods.NewSquare(4);
    IF Methods.AreaOf(s) = 16 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDispatchFromOtherProc;

  PROCEDURE TestVarRecordReceiver*();
    VAR p: Methods.Point;
  BEGIN
    p.x := 1; p.y := 2;
    p.MoveBy(10, 20);
    IF (p.x = 11) & (p.y = 22) & (p.Sum() = 33) THEN
      TestRunner.Pass
    ELSE
      TestRunner.Fail
    END
  END TestVarRecordReceiver;

  PROCEDURE TestCrossModuleInherited*();
    VAR d: MethExt.Dog;
  BEGIN
    (* base-module method through an extension pointer, from a third module *)
    d := MethExt.NewDog(4, 1);
    IF d.Legs() = 4 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCrossModuleInherited;

  PROCEDURE TestCrossModuleOverride*();
    VAR d: MethExt.Dog;
        a: MethBase.Animal;
  BEGIN
    d := MethExt.NewDog(4, 2);
    a := d;
    IF (a.Sound() = 200) & (d.Bites() = 2) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCrossModuleOverride;

  PROCEDURE TestCrossModuleDispatchFromBase*();
    VAR d: MethExt.Dog;
        a: MethBase.Animal;
  BEGIN
    (* MethBase.Describe knows only Animal; must call Dog's override *)
    d := MethExt.NewDog(4, 0);
    IF MethBase.Describe(d) = 204 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    NEW(a); a.legs := 2;
    IF MethBase.Describe(a) = 102 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCrossModuleDispatchFromBase;

END MethodsTests.
