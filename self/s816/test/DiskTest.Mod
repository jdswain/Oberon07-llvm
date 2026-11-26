MODULE DiskTest;
  IMPORT SYSTEM, Out;
  CONST
    FDC_CMD    = 0800H;
    FDC_SECTOR = 0802H;
    FDC_DATA   = 0803H;
    FDC_CTRL   = 0806H;
  VAR
    i, d: INTEGER;
    b: BYTE;
BEGIN
  (* Select drive 0, side 0, motor on *)
  b := 22H;
  SYSTEM.PUT(0, FDC_CTRL, b);

  (* Issue Restore command - seek to track 0 *)
  b := 0;
  SYSTEM.PUT(0, FDC_CMD, b);

  (* Set sector register to 1 *)
  b := 1;
  SYSTEM.PUT(0, FDC_SECTOR, b);

  (* Issue Read Sector command *)
  b := 80H;
  SYSTEM.PUT(0, FDC_CMD, b);

  (* Read 512 bytes from data register, print first 16 *)
  i := 0;
  WHILE i < 512 DO
    SYSTEM.GET(0, FDC_DATA, b);
    d := b;
    IF i < 16 THEN
      Out.Int(d, 4)
    END;
    INC(i)
  END;
  Out.Ln();

  (* Now test write: write known pattern to track 0, sector 2 *)
  b := 2;
  SYSTEM.PUT(0, FDC_SECTOR, b);
  b := 0A0H;
  SYSTEM.PUT(0, FDC_CMD, b);

  (* Write 512 bytes: value = i MOD 256 *)
  i := 0;
  WHILE i < 512 DO
    b := i MOD 256;
    SYSTEM.PUT(0, FDC_DATA, b);
    INC(i)
  END;

  (* Read it back *)
  b := 2;
  SYSTEM.PUT(0, FDC_SECTOR, b);
  b := 80H;
  SYSTEM.PUT(0, FDC_CMD, b);

  i := 0;
  WHILE i < 512 DO
    SYSTEM.GET(0, FDC_DATA, b);
    d := b;
    IF i < 16 THEN
      Out.Int(d, 4)
    END;
    INC(i)
  END;
  Out.Ln();

  Out.Int(9999, 1); Out.Ln()
END DiskTest.
