MODULE WasmFilesStubCheck;
(* Confirms the wasm Files runtime is stubbed — New must return NIL,
   Delete must report failure. The host filesystem isn't reachable
   from wasm in this prototype, so this is the expected behaviour. *)
  IMPORT Out, Files;
  VAR f: Files.File; res: INTEGER;
BEGIN
  Out.WriteString("=== wasm files stub ==="); Out.Ln();
  f := Files.New("anything.txt");
  IF f = NIL THEN Out.WriteString("Files.New = NIL  OK")
  ELSE Out.WriteString("Files.New returned non-NIL — UNEXPECTED") END;
  Out.Ln();
  Files.Delete("anything.txt", res);
  IF res # 0 THEN Out.WriteString("Files.Delete res = "); Out.WriteInt(res);
                  Out.WriteString("  OK (non-zero)")
  ELSE Out.WriteString("Files.Delete res = 0 — UNEXPECTED") END;
  Out.Ln()
END WasmFilesStubCheck.
