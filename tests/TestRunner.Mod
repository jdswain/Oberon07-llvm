MODULE TestRunner;
  IMPORT Modules, Out;

  VAR
    passed, failed: INTEGER;
    currentName: ARRAY 64 OF CHAR;

  PROCEDURE Passed*(): INTEGER; BEGIN RETURN passed END Passed;
  PROCEDURE Failed*(): INTEGER; BEGIN RETURN failed END Failed;

  PROCEDURE Pass*();
  BEGIN
    INC(passed);
    Out.WriteString("  PASS  "); Out.WriteString(currentName); Out.Ln()
  END Pass;

  PROCEDURE Fail*();
  BEGIN
    INC(failed);
    Out.WriteString("  FAIL  "); Out.WriteString(currentName); Out.Ln()
  END Fail;

  PROCEDURE startsWithTest(name: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (name[0] = "T") & (name[1] = "e") & (name[2] = "s") & (name[3] = "t")
  END startsWithTest;

  PROCEDURE Run*(mod: Modules.Module);
    VAR i, n: INTEGER;
        nm: ARRAY 64 OF CHAR;
        fn: Modules.Command;
  BEGIN
    passed := 0; failed := 0;
    n := Modules.ExportCount(mod);
    Out.WriteString("Running tests in "); Out.WriteString(mod.name);
    Out.WriteString(" ("); Out.WriteInt(n); Out.WriteString(" exports)"); Out.Ln();
    FOR i := 0 TO n - 1 DO
      Modules.ExportName(mod, i, nm);
      IF startsWithTest(nm) THEN
        currentName := nm;
        fn := Modules.ExportProc(mod, i);
        IF fn # NIL THEN fn() END
      END
    END;
    Out.WriteString("Summary: "); Out.WriteInt(passed); Out.WriteString(" passed, ");
    Out.WriteInt(failed); Out.WriteString(" failed"); Out.Ln()
  END Run;

END TestRunner.
