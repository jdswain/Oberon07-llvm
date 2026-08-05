MODULE Chars;
  (* Regression coverage for CHR argument passing. CHR(x) yields a CHAR (i8);
     passed straight into a CHAR parameter it must be an i8, not a widened
     INTEGER — the frontend once reused ORD's lowering for CHR and emitted an
     i32 argument against an i8 parameter, which the LLVM verifier rejects. *)

  PROCEDURE Code* (c: CHAR): INTEGER;
  BEGIN RETURN ORD(c)
  END Code;

  PROCEDURE Echo* (c: CHAR): CHAR;
  BEGIN RETURN c
  END Echo;

  PROCEDURE Digit* (n: INTEGER): CHAR;
  BEGIN RETURN CHR(ORD("0") + n)
  END Digit;

END Chars.
