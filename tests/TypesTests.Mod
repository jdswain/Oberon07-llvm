MODULE TypesTests;
  IMPORT Types, TestRunner;

  PROCEDURE TestShape*();
    VAR p: Types.Shape;
  BEGIN
    p := Types.NewShape();
    IF Types.IsShape(p) & ~Types.IsCircle(p) & ~Types.IsSquare(p) & ~Types.IsSmallCircle(p)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestShape;

  PROCEDURE TestCircle*();
    VAR p: Types.Shape;
  BEGIN
    p := Types.NewCircle();
    IF Types.IsShape(p) & Types.IsCircle(p) & ~Types.IsSquare(p) & ~Types.IsSmallCircle(p)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCircle;

  PROCEDURE TestSquare*();
    VAR p: Types.Shape;
  BEGIN
    p := Types.NewSquare();
    IF Types.IsShape(p) & ~Types.IsCircle(p) & Types.IsSquare(p) & ~Types.IsSmallCircle(p)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSquare;

  PROCEDURE TestSmallCircle*();
    VAR p: Types.Shape;
  BEGIN
    p := Types.NewSmallCircle();
    IF Types.IsShape(p) & Types.IsCircle(p) & ~Types.IsSquare(p) & Types.IsSmallCircle(p)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSmallCircle;

END TypesTests.
