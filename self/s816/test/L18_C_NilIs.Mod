MODULE L18_C_NilIs; IMPORT Out;
TYPE
  F = POINTER TO FD; FD = RECORD k: INTEGER END;
  G = POINTER TO GD; GD = RECORD (FD) g: INTEGER END;
  H = POINTER TO HD; HD = RECORD (FD) h: INTEGER END;
  Sink = INTERFACE PROCEDURE Put(c: CHAR) END;
  S = POINTER TO SD; SD = RECORD IMPLEMENTS Sink END;
VAR f: F; g: G; h: H; s: Sink; b: BOOLEAN; sp: S;
PROCEDURE (p: S) Put(c: CHAR);
BEGIN Out.Char(c)
END Put;
PROCEDURE Kind(f: F);
BEGIN
  CASE f OF
    G: Out.String("G")
  | H: Out.String("H")
  | F: Out.String("F")
  END;
  Out.Char(" ")
END Kind;
BEGIN
  f := NIL;
  Out.Bool(f IS G); Out.Bool(f IS F); b := f IS H; Out.Bool(b); Out.Bool(~(f IS G)); Out.Ln;
  Out.Bool((f IS G) OR (f = NIL)); Out.Bool((f = NIL) & (f IS G)); Out.Ln;
  IF f IS G THEN Out.String("wrong") ELSE Out.String("not G") END; Out.Ln;
  Kind(f); NEW(g); Kind(g); NEW(h); Kind(h); NEW(f); Kind(f); Out.Ln;
  f := g; Out.Bool(f IS G); Out.Bool(f IS H); Out.Bool(f IS F); Out.Ln;
  f := NIL; g := f(G); Out.Bool(g = NIL); Out.Ln;
  s := NIL; Out.Bool(s IS S); NEW(sp); s := sp; Out.Bool(s IS S); Out.Ln
END L18_C_NilIs.
