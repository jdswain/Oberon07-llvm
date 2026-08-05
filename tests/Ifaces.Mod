MODULE Ifaces;
  (* Interfaces (DDR-008): nominal, declared conformance; inclusion by
     naming; fat-pointer values; dispatch via slot-index itables. *)

  TYPE
    Shape* = INTERFACE
      PROCEDURE Area (): INTEGER;
      PROCEDURE Kind (): INTEGER
    END;

    Scaled* = INTERFACE
      Shape;                          (* inclusion: {Area, Kind, Scale} *)
      PROCEDURE Scale (f: INTEGER)
    END;

    Box*     = POINTER TO BoxDesc;
    BoxDesc* = RECORD IMPLEMENTS Scaled
      w*, h*: INTEGER
    END;

  PROCEDURE (b: Box) Area* (): INTEGER;
  BEGIN
    RETURN b.w * b.h
  END Area;

  PROCEDURE (b: Box) Kind* (): INTEGER;
  BEGIN
    RETURN 1
  END Kind;

  PROCEDURE (b: Box) Scale* (f: INTEGER);
  BEGIN
    b.w := b.w * f;
    b.h := b.h * f
  END Scale;

  PROCEDURE NewBox* (w, h: INTEGER): Box;
    VAR b: Box;
  BEGIN
    NEW(b); b.w := w; b.h := h;
    RETURN b
  END NewBox;

  (* interface-typed function result *)
  PROCEDURE MakeShape* (w, h: INTEGER): Shape;
    VAR b: Box;
  BEGIN
    b := NewBox(w, h);
    RETURN b
  END MakeShape;

  (* dispatch from a module that may never see the implementing type *)
  PROCEDURE AreaOf* (s: Shape): INTEGER;
  BEGIN
    RETURN s.Area()
  END AreaOf;

END Ifaces.
