MODULE L10_SystemCopy;
  IMPORT SYSTEM, Out;
  VAR src, dst, val: INTEGER;
BEGIN
  src := 2000H;
  dst := 2010H;

  (* Write source data: 3 words *)
  SYSTEM.PUT(0, src, 111);
  SYSTEM.PUT(0, src + 2, 222);
  SYSTEM.PUT(0, src + 4, 333);

  (* Copy 3 words from src to dst *)
  SYSTEM.COPY(src, dst, 3);

  (* Read back from destination *)
  SYSTEM.GET(0, dst, val);
  Out.Int(val, 1); Out.Ln();

  SYSTEM.GET(0, dst + 2, val);
  Out.Int(val, 1); Out.Ln();

  SYSTEM.GET(0, dst + 4, val);
  Out.Int(val, 1); Out.Ln()
END L10_SystemCopy.
