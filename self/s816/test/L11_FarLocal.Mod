MODULE L11_FarLocal;
(* Locals more than 255 bytes up the stack, beyond LDA d,S (a field at the
   end of a big local record): loaded, stored and compared through dp,X
   in the stack's bank (with OS16's banked direct page and stack, D's
   bank), the bank their addresses have when passed as VAR parameters.
   They were once reached as $000000,X, bank 0, which wrote over the
   kernel's variables there and read back other than a VAR parameter
   saw. And a procedure's start stores its parameters only, not into its
   locals after them (LoadEx's, in ModuleManager, where it was found:
   past 255 bytes). And dp,X's offset, S + v less the direct page's
   place, added without the carry of the first sum: with S above the
   page (a process's banked stack) it was a byte high, and a VAR
   parameter, at the true address, read another value. *)
  IMPORT Out;

  TYPE Big = RECORD pad: ARRAY 300 OF BYTE; x, y: INTEGER END;

  VAR res: INTEGER;

  PROCEDURE Get(VAR x: INTEGER): INTEGER;
  BEGIN RETURN x
  END Get;

  PROCEDURE Set(VAR x: INTEGER; v: INTEGER);
  BEGIN x := v
  END Set;

  PROCEDURE Far(name: ARRAY OF CHAR; VAR res: INTEGER; exec: BOOLEAN);
    VAR r: Big; nm: ARRAY 64 OF CHAR; i: INTEGER;
  BEGIN
    r.x := 1234; r.y := 5678;
    Out.Int(r.x, 0); Out.Char(" "); Out.Int(r.y, 0); Out.Ln;
    Out.Int(Get(r.x), 0); Out.Char(" "); Out.Int(Get(r.y), 0); Out.Ln;
    Set(r.x, 4321); r.y := 8765;
    Out.Int(r.x, 0); Out.Char(" "); Out.Int(Get(r.y), 0); Out.Ln;
    IF (r.x = 4321) & (r.y = 8765) THEN Out.String("equal") ELSE Out.String("not equal") END; Out.Ln;
    i := 0; WHILE (i < LEN(name)) & (name[i] # 0X) DO nm[i] := name[i]; INC(i) END; nm[i] := 0X;
    Out.String(nm); Out.Ln;
    IF exec THEN res := 99 END
  END Far;

BEGIN
  Far("ABC", res, TRUE); Out.Int(res, 0); Out.Ln; Out.String("done"); Out.Ln
END L11_FarLocal.
