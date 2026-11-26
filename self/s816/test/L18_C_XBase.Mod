MODULE L18_C_XBase; IMPORT Out;
TYPE
  Rect* = POINTER TO RectDesc;
  RectDesc* = RECORD w*, h*: INTEGER END;
  Shape* = POINTER TO ShapeDesc;
  ShapeDesc* = RECORD n*: INTEGER END;
VAR made*: INTEGER;
PROCEDURE INIT (r: Rect) Make*(w, h: INTEGER);
BEGIN r.w := w; r.h := h; INC(made)
END Make;
PROCEDURE (r: Rect) Area*(): INTEGER;
BEGIN RETURN r.w * r.h
END Area;
PROCEDURE (s: Shape) hidden(k: INTEGER): INTEGER;
BEGIN RETURN s.n * 10 + k
END hidden;
PROCEDURE (s: Shape) Name*;
BEGIN Out.String("shape")
END Name;
PROCEDURE (s: Shape) secret;
BEGIN Out.String("secret "); Out.Int(s.n, 0)
END secret;
PROCEDURE Show*(s: Shape);
BEGIN Out.Int(s.hidden(3), 0); Out.Char(" "); s.secret; Out.Char(" "); s.Name; Out.Ln
END Show;
END L18_C_XBase.
