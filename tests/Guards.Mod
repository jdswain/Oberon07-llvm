MODULE Guards;
  (* Type-guards and type-CASE on a pointer-to-record hierarchy. *)

  TYPE
    Shape*     = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD kind*: INTEGER END;

    Circle*     = POINTER TO CircleDesc;
    CircleDesc* = RECORD (ShapeDesc) radius*: INTEGER END;

    Square*     = POINTER TO SquareDesc;
    SquareDesc* = RECORD (ShapeDesc) side*: INTEGER END;

  PROCEDURE NewCircle*(r: INTEGER): Shape;
    VAR p: Circle;
  BEGIN
    NEW(p); p.kind := 1; p.radius := r;
    RETURN p
  END NewCircle;

  PROCEDURE NewSquare*(s: INTEGER): Shape;
    VAR p: Square;
  BEGIN
    NEW(p); p.kind := 2; p.side := s;
    RETURN p
  END NewSquare;

  (* Type guard: narrow Shape to Circle inline so we can read its
     extra `radius` field. *)
  PROCEDURE GetRadius*(s: Shape): INTEGER;
  BEGIN
    RETURN s(Circle).radius
  END GetRadius;

  (* Same but for Square. *)
  PROCEDURE GetSide*(s: Shape): INTEGER;
  BEGIN
    RETURN s(Square).side
  END GetSide;

  (* Type-CASE: dispatch on dynamic type. *)
  PROCEDURE Describe*(s: Shape): INTEGER;
    VAR r: INTEGER;
  BEGIN
    r := -1;
    CASE s OF
      Circle: r := s.radius * 100
    | Square: r := s.side  * 200
    END;
    RETURN r
  END Describe;

END Guards.
