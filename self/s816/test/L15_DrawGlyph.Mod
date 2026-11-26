MODULE L15_DrawGlyph;
  IMPORT Out, Graphics, Ohlfs10, SYSTEM;

  VAR fAddr, fBank, dx, p: INTEGER;
    s: ARRAY 16 OF CHAR;

BEGIN
  (* Test 1: SYSTEM.ADR and SYSTEM.BANK on imported structured constant *)
  fAddr := SYSTEM.ADR(Ohlfs10.T);
  fBank := SYSTEM.BANK(Ohlfs10.T);
  s := "addr>0: ";
  Out.String(s);
  IF fAddr > 0 THEN Out.Int(1, 0) ELSE Out.Int(0, 0) END;
  Out.Ln;
  s := "bank: ";
  Out.String(s); Out.Int(fBank, 0); Out.Ln;

  (* Test 2: Font scalar export *)
  s := "height: ";
  Out.String(s); Out.Int(Ohlfs10.height, 0); Out.Ln;

  (* Test 3: SetPixel/GetPixel roundtrip *)
  Graphics.SetPixel(40, 10, 15);
  p := Graphics.GetPixel(40, 10);
  s := "pixel: ";
  Out.String(s); Out.Int(p, 0); Out.Ln;

  (* Test 4: DrawGlyph returns advance width *)
  dx := Graphics.DrawGlyph(fAddr, fBank, 48H, 100, 100, 15);
  s := "dx: ";
  Out.String(s); Out.Int(dx, 0); Out.Ln;

  (* Test 5: Verify a pixel was actually drawn *)
  (* With base_screen_y = y + yoff, glyph starts at y=100 upward *)
  p := Graphics.GetPixel(100, 104);
  s := "p100: ";
  Out.String(s); Out.Int(p, 0); Out.Ln;

  (* Test 6: Draw a second character *)
  dx := Graphics.DrawGlyph(fAddr, fBank, 69H, 110, 100, 7);
  s := "dx2: ";
  Out.String(s); Out.Int(dx, 0); Out.Ln
END L15_DrawGlyph.
