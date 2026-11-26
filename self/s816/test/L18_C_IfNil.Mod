MODULE L18_C_IfNil; IMPORT Out;
TYPE
  Sink = INTERFACE PROCEDURE Put(c: CHAR) END;
  Buf = POINTER TO BufDesc;
  BufDesc = RECORD IMPLEMENTS Sink n: INTEGER END;
VAR b: Buf; s: Sink;
PROCEDURE (b: Buf) Put(c: CHAR);
BEGIN INC(b.n); Out.Char(c)
END Put;
BEGIN
  NEW(b); s := b; s.Put("a"); Out.Ln;
  s := NIL; Out.String("before"); Out.Ln; s.Put("b"); Out.String("after"); Out.Ln
END L18_C_IfNil.
