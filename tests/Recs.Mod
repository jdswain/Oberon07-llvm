MODULE Recs;

  TYPE
    Point* = RECORD
      x*, y*: INTEGER
    END;

  VAR
    origin*: Point;

  PROCEDURE Sum*(VAR p: Point): INTEGER;
  BEGIN
    RETURN p.x + p.y
  END Sum;

  PROCEDURE Set*(VAR p: Point; vx, vy: INTEGER);
  BEGIN
    p.x := vx;
    p.y := vy
  END Set;

  PROCEDURE Init*();
  BEGIN
    origin.x := 0;
    origin.y := 0
  END Init;

BEGIN
  origin.x := 100;
  origin.y := 200
END Recs.
