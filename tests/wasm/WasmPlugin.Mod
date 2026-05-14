MODULE WasmPlugin;
  IMPORT Out;

  PROCEDURE TestOne*();
  BEGIN
    Out.WriteString("    test one ran"); Out.Ln()
  END TestOne;

  PROCEDURE TestTwo*();
  BEGIN
    Out.WriteString("    test two ran"); Out.Ln()
  END TestTwo;

  PROCEDURE Helper*(): INTEGER;
  BEGIN RETURN 42
  END Helper;

END WasmPlugin.
