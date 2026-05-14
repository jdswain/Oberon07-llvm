MODULE WasmHello;
  IMPORT Out;

  VAR i, total: INTEGER;

BEGIN
  Out.WriteString("hello from oberon-wasm"); Out.Ln();
  total := 0;
  FOR i := 1 TO 10 DO total := total + i END;
  Out.WriteString("1+2+...+10 = "); Out.WriteInt(total); Out.Ln()
END WasmHello.
