MODULE WasmModuleDemo;
(* Verifies the static-manifest module loader works under wasm. Even
   though `WasmPlugin` is statically linked into this binary,
   `Modules.Load` should still find it (via oc_module_manifest emitted
   by the driver) and walk its exports the same way TestHost does on
   native via dlopen. *)

  IMPORT Out, Modules, WasmPlugin;

  PROCEDURE startsWithTest(name: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (name[0] = "T") & (name[1] = "e") & (name[2] = "s") & (name[3] = "t")
  END startsWithTest;

  PROCEDURE Run();
    VAR mod: Modules.Module;
        i, n: INTEGER;
        nm: ARRAY 64 OF CHAR;
        fn: Modules.Command;
  BEGIN
    Out.WriteString("=== wasm module demo ==="); Out.Ln();
    Modules.Load("WasmPlugin", mod);
    IF mod = NIL THEN
      Out.WriteString("FAIL: WasmPlugin not in manifest"); Out.Ln()
    ELSE
      n := Modules.ExportCount(mod);
      Out.WriteString("loaded "); Out.WriteString(mod.name);
      Out.WriteString(" ("); Out.WriteInt(n); Out.WriteString(" exports)"); Out.Ln();
      FOR i := 0 TO n - 1 DO
        Modules.ExportName(mod, i, nm);
        Out.WriteString("  export["); Out.WriteInt(i); Out.WriteString("] = ");
        Out.WriteString(nm);
        IF startsWithTest(nm) THEN
          Out.WriteString(" — calling:"); Out.Ln();
          fn := Modules.ExportProc(mod, i);
          IF fn # NIL THEN fn() END
        ELSE
          Out.WriteString(" (skip)"); Out.Ln()
        END
      END;
      Modules.Free("WasmPlugin")
    END
  END Run;

BEGIN
  Run()
END WasmModuleDemo.
