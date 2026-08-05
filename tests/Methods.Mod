MODULE Methods;
  (* Type-bound procedures (DDR-001/002): dynamic dispatch through pointer
     receivers, OVERRIDE, inherited methods, VAR-record receivers. *)

  TYPE
    Shape*      = POINTER TO ShapeDesc;
    ShapeDesc*  = RECORD id*: INTEGER END;

    Circle*     = POINTER TO CircleDesc;
    CircleDesc* = RECORD (ShapeDesc) radius*: INTEGER END;

    Square*     = POINTER TO SquareDesc;
    SquareDesc* = RECORD (ShapeDesc) side*: INTEGER END;

    Point*      = RECORD x*, y*: INTEGER END;

  PROCEDURE (s: Shape) Area* (): INTEGER;
  BEGIN
    RETURN 0
  END Area;

  PROCEDURE (s: Shape) Kind* (): INTEGER;
  BEGIN
    RETURN 1
  END Kind;

  PROCEDURE (c: Circle) Area* (): INTEGER OVERRIDE;
  BEGIN
    RETURN 3 * c.radius * c.radius
  END Area;

  PROCEDURE (q: Square) Area* (): INTEGER OVERRIDE;
  BEGIN
    RETURN q.side * q.side
  END Area;

  PROCEDURE (q: Square) Kind* (): INTEGER OVERRIDE;
  BEGIN
    RETURN 2
  END Kind;

  (* VAR-record receiver: static binding, receiver mutable. *)
  PROCEDURE (VAR p: Point) MoveBy* (dx, dy: INTEGER);
  BEGIN
    p.x := p.x + dx;
    p.y := p.y + dy
  END MoveBy;

  PROCEDURE (VAR p: Point) Sum* (): INTEGER;
  BEGIN
    RETURN p.x + p.y
  END Sum;

  PROCEDURE NewCircle* (r: INTEGER): Shape;
    VAR c: Circle;
  BEGIN
    NEW(c); c.id := 10; c.radius := r;
    RETURN c
  END NewCircle;

  PROCEDURE NewSquare* (s: INTEGER): Shape;
    VAR q: Square;
  BEGIN
    NEW(q); q.id := 20; q.side := s;
    RETURN q
  END NewSquare;

  (* Dispatch from a context that only knows the base type. *)
  PROCEDURE AreaOf* (s: Shape): INTEGER;
  BEGIN
    RETURN s.Area()
  END AreaOf;

END Methods.
