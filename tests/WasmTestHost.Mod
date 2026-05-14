MODULE WasmTestHost;
(* Single-binary TestHost for the wasm target. Where the native
   TestHost loads each XTests.dylib at runtime via dlopen, wasm has
   no dynamic linking — so every test plugin must be statically
   imported here. The compiler-emitted oc_module_manifest then makes
   `Modules.Load(name)` find them by name without any filesystem
   lookup.

   Otherwise the structure is the same as tests/TestHost.Mod:
   iterate plugin names, hand each to TestRunner.Run.

   Caveat: the wasm Files / FileDir runtime is stubbed (see
   runtime/wasm/Files_rt.c). FilesTests will therefore report
   failures here — that's the expected diagnostic for "no host
   filesystem on wasm yet". *)

  IMPORT Out, Modules, TestRunner,
         Files, FileDir, Env,
         (* modules under test *)
         Branch, Loops, Cases, Short, Chain,
         Sets, Reals, Types, Guards, Guards2,
         Arrs, Recs, RecCopy, Strings, StrPass, Open,
         StackRec, ArrPtrs, Arc, ArcCons, Weak, Tree,
         App, Util, Diamond, A, B, Counter, Mix, Math,
         Repeat, While, For,
         (* the test plugins themselves — statically imported so they
            land in the manifest and Modules.Load can find them by
            name without ever touching the host filesystem. *)
         BranchTests, LoopsTests, RepeatTests, WhileTests, ForTests,
         CasesTests, ShortTests, ChainTests, SetsTests, RealsTests,
         TypesTests, GuardsTests, Guards2Tests, ArrsTests, RecsTests,
         RecCopyTests, StringsTests, StrPassTests, OpenTests,
         StackRecTests, ArrPtrsTests, ArcTests, ArcConsTests,
         WeakTests, TreeTests, SysTests, AppTests, DiamondTests,
         MixTests, MathTests, FilesTests, EnvTests;

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
  Out.WriteString("=== WasmTestHost ==="); Out.Ln();
  totalPassed := 0; totalFailed := 0;

  RunPlugin("BranchTests");
  RunPlugin("LoopsTests");
  RunPlugin("RepeatTests");
  RunPlugin("WhileTests");
  RunPlugin("ForTests");
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
END WasmTestHost.
