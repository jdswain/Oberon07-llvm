MODULE TestHost;
  IMPORT Out, Modules, TestRunner, Files, FileDir, Env,
         Branch, Loops, Cases, Short, Chain,
         Sets, Reals, Types, Guards, Guards2,
         Arrs, Recs, RecCopy, Strings, StrPass, Open,
         StackRec, ArrPtrs, Arc, ArcCons, Weak, Tree,
         App, Util, Diamond, A, B, Counter, Mix, Math;

  VAR totalPassed, totalFailed: INTEGER;

  PROCEDURE RunPlugin(name: ARRAY OF CHAR);
    VAR mod: Modules.Module;
  BEGIN
    Modules.Load(name, mod);
    IF mod # NIL THEN
      TestRunner.Run(mod);
      INC(totalPassed, TestRunner.Passed());
      INC(totalFailed, TestRunner.Failed());
      Modules.Free(name)
    ELSE
      Out.WriteString("  ERROR: cannot load plugin"); Out.Ln();
      INC(totalFailed)
    END
  END RunPlugin;

BEGIN
  Out.WriteString("=== TestHost ==="); Out.Ln();
  totalPassed := 0; totalFailed := 0;

  RunPlugin("BranchTests");
  RunPlugin("LoopsTests");
  RunPlugin("CasesTests");
  RunPlugin("ShortTests");
  RunPlugin("ChainTests");
  RunPlugin("SetsTests");
  RunPlugin("RealsTests");
  RunPlugin("TypesTests");
  RunPlugin("GuardsTests");
  RunPlugin("Guards2Tests");
  RunPlugin("ArrsTests");
  RunPlugin("RecsTests");
  RunPlugin("RecCopyTests");
  RunPlugin("StringsTests");
  RunPlugin("StrPassTests");
  RunPlugin("OpenTests");
  RunPlugin("StackRecTests");
  RunPlugin("ArrPtrsTests");
  RunPlugin("ArcTests");
  RunPlugin("ArcConsTests");
  RunPlugin("WeakTests");
  RunPlugin("TreeTests");
  RunPlugin("SysTests");
  RunPlugin("AppTests");
  RunPlugin("DiamondTests");
  RunPlugin("MixTests");
  RunPlugin("MathTests");
  RunPlugin("FilesTests");
  RunPlugin("EnvTests");

  Out.WriteString("======================="); Out.Ln();
  Out.WriteString("TOTAL: ");
  Out.WriteInt(totalPassed); Out.WriteString(" passed, ");
  Out.WriteInt(totalFailed); Out.WriteString(" failed"); Out.Ln()
END TestHost.
