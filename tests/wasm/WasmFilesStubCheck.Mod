MODULE WasmFilesStubCheck;
(* Confirms the wasm Files runtime is stubbed — New must return NIL,
   Delete must report failure. The host filesystem isn't reachable
   from wasm in this prototype, so this is the expected behaviour. *)
  IMPORT Errors, Out, Files;
  VAR f: Files.File; err: Errors.Error;
BEGIN
  Out.WriteString("=== wasm files stub ==="); Out.Ln();
  f := Files.New("anything.txt");
  IF f = NIL THEN Out.WriteString("Files.New = NIL  OK")
  ELSE Out.WriteString("Files.New returned non-NIL — UNEXPECTED") END;
  Out.Ln();
  Files.Delete("anything.txt", err);
  IF err # NIL THEN Out.WriteString("Files.Delete err.code = "); Out.WriteInt(err.Code());
                    Out.WriteString("  OK (non-NIL)")
  ELSE Out.WriteString("Files.Delete err = NIL — UNEXPECTED") END;
  Out.Ln()
END WasmFilesStubCheck.
