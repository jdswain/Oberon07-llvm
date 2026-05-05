MODULE Types;

  TYPE
    Shape*     = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      kind*: INTEGER
    END;

    Circle*     = POINTER TO CircleDesc;
    CircleDesc* = RECORD (ShapeDesc)
      radius*: INTEGER
    END;

    Square*     = POINTER TO SquareDesc;
    SquareDesc* = RECORD (ShapeDesc)
      side*: INTEGER
    END;

    SmallCircle*     = POINTER TO SmallCircleDesc;
    SmallCircleDesc* = RECORD (CircleDesc)
      tag*: INTEGER
    END;

  PROCEDURE NewShape*(): Shape;
    VAR p: Shape;
  BEGIN
    NEW(p);
    p.kind := 0;
    RETURN p
  END NewShape;

  PROCEDURE NewCircle*(): Shape;
    VAR p: Circle;
  BEGIN
    NEW(p);
    p.kind := 1;
    p.radius := 7;
    RETURN p
  END NewCircle;

  PROCEDURE NewSquare*(): Shape;
    VAR p: Square;
  BEGIN
    NEW(p);
    p.kind := 2;
    p.side := 5;
    RETURN p
  END NewSquare;

  PROCEDURE NewSmallCircle*(): Shape;
    VAR p: SmallCircle;
  BEGIN
    NEW(p);
    p.kind := 3;
    p.radius := 1;
    p.tag := 42;
    RETURN p
  END NewSmallCircle;

  PROCEDURE IsShape*(p: Shape): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN r := p IS Shape; RETURN r
  END IsShape;

  PROCEDURE IsCircle*(p: Shape): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN r := p IS Circle; RETURN r
  END IsCircle;

  PROCEDURE IsSquare*(p: Shape): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN r := p IS Square; RETURN r
  END IsSquare;

  PROCEDURE IsSmallCircle*(p: Shape): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN r := p IS SmallCircle; RETURN r
  END IsSmallCircle;

END Types.
