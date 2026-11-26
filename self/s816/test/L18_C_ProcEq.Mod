MODULE L18_C_ProcEq; IMPORT Out;
TYPE P = PROCEDURE (x: INTEGER): INTEGER;
VAR p, q: P;
PROCEDURE First(x: INTEGER): INTEGER;
BEGIN RETURN x
END First;
PROCEDURE Local(x: INTEGER): INTEGER;
BEGIN RETURN x + 1
END Local;
PROCEDURE Other(x: INTEGER): INTEGER;
BEGIN RETURN x + 2
END Other;
PROCEDURE Pub*(x: INTEGER): INTEGER;
BEGIN RETURN x + 3
END Pub;
PROCEDURE Test(r: P);
BEGIN
  Out.Bool(r = Local); Out.Bool(Local = r); Out.Bool(r # Local); Out.Bool(r = First); Out.Bool(First = r);
  Out.Bool(r = Other); Out.Bool(r = Pub); Out.Bool(Pub = r); Out.Bool(r = NIL); Out.Char(" ")
END Test;
BEGIN
  Test(Local); Test(First); Test(Other); Test(Pub); Test(NIL); Out.Ln;
  p := Local; q := Local; Out.Bool(p = q); Out.Bool(p = Local); q := Other; Out.Bool(p = q);
  IF p = Local THEN Out.String(" yes") END; Out.Int(p(1), 0); Out.Ln
END L18_C_ProcEq.
