MODULE L1_DivPow2;
  IMPORT Out;

  PROCEDURE Run;
    VAR a: INTEGER;
  BEGIN
    (* Positive dividend, various powers of 2 *)
    a := 100;
    Out.Int(a DIV 2, 1); Out.Ln;
    Out.Int(a DIV 4, 1); Out.Ln;
    Out.Int(a DIV 8, 1); Out.Ln;
    Out.Int(a DIV 16, 1); Out.Ln;

    (* Small values *)
    a := 7;
    Out.Int(a DIV 2, 1); Out.Ln;
    Out.Int(a DIV 4, 1); Out.Ln;

    a := 1;
    Out.Int(a DIV 2, 1); Out.Ln;

    a := 0;
    Out.Int(a DIV 4, 1); Out.Ln;

    (* Exact negative division *)
    a := -8;
    Out.Int(a DIV 2, 1); Out.Ln;
    Out.Int(a DIV 4, 1); Out.Ln;

    (* Inexact negative division *)
    a := -7;
    Out.Int(a DIV 2, 1); Out.Ln;
    Out.Int(a DIV 4, 1); Out.Ln;

    a := -1;
    Out.Int(a DIV 2, 1); Out.Ln
  END Run;

BEGIN
  Run
END L1_DivPow2.
