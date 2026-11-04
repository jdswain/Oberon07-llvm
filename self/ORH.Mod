MODULE ORH; (* The compiler's host: its console, where it reports what it
   compiles and the errors it finds, the names of the files it writes in
   its working directory (the module's .816 and .map), and a REAL's bits
   (as the host's integers hold them). Here POSIX's Out
   and names as they are; a system the compiler is moved to gives its own
   (OS16's writes to the terminal, and names files from CWD). *)

  IMPORT SYSTEM, Out;

  PROCEDURE Write*(ch: CHAR);
  BEGIN Out.Write(ch)
  END Write;

  PROCEDURE WriteString*(s: ARRAY OF CHAR);
  BEGIN Out.WriteString(s)
  END WriteString;

  PROCEDURE WriteInt*(x: LONGINT);
  BEGIN Out.WriteInt(x)
  END WriteInt;

  PROCEDURE Ln*;
  BEGIN Out.Ln
  END Ln;

  (* x's IEEE-754 bits: INTEGER has 32 here, as REAL has *)
  PROCEDURE RealBits*(x: REAL): LONGINT;
  BEGIN RETURN SYSTEM.VAL(INTEGER, x)
  END RealBits;

  (* the name of the file name in the working directory *)
  PROCEDURE FileName*(name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(name)) & (i < LEN(path) - 1) & (name[i] # 0X) DO path[i] := name[i]; INC(i) END;
    path[i] := 0X
  END FileName;

END ORH.
