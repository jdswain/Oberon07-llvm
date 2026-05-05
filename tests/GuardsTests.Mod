MODULE GuardsTests;
  IMPORT Guards, TestRunner;

  PROCEDURE TestGetRadius*();
    VAR c: Guards.Shape;
  BEGIN
    c := Guards.NewCircle(7);
    IF Guards.GetRadius(c) = 7 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestGetRadius;

  PROCEDURE TestGetSide*();
    VAR s: Guards.Shape;
  BEGIN
    s := Guards.NewSquare(5);
    IF Guards.GetSide(s) = 5 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestGetSide;

  PROCEDURE TestDescribeCircle*();
    VAR c: Guards.Shape;
  BEGIN
    c := Guards.NewCircle(7);
    IF Guards.Describe(c) = 700 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDescribeCircle;

  PROCEDURE TestDescribeSquare*();
    VAR s: Guards.Shape;
  BEGIN
    s := Guards.NewSquare(5);
    IF Guards.Describe(s) = 1000 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestDescribeSquare;

END GuardsTests.
