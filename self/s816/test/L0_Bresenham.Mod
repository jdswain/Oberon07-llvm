MODULE L0_Bresenham;
  IMPORT Out, SYSTEM;

  CONST
    SCREEN_BUFFER = 08000H;
    SCREEN_WIDTH_BYTES = 320 DIV 8;

  PROCEDURE BitMask(bit: INTEGER): INTEGER;
    VAR m, i: INTEGER;
  BEGIN
    m := 1; i := 0;
    WHILE i < bit DO m := m * 2; i := i + 1 END;
    RETURN m
  END BitMask;

  PROCEDURE SetPixel(x, y: INTEGER);
    VAR addr, data, mask: INTEGER;
  BEGIN
    Out.Char("("); Out.Int(x, 1); Out.Char(","); Out.Int(y, 1); Out.Char(")"); Out.Ln();
    addr := SCREEN_BUFFER + y * SCREEN_WIDTH_BYTES + x DIV 8;
    mask := BitMask(x MOD 8);
    SYSTEM.GET(0, addr, data);
    data := ORA(data, mask);
    SYSTEM.PUT(0, addr, data)
  END SetPixel;

  PROCEDURE DrawLine(x0, y0, x1, y1: INTEGER);
    VAR dx, dy, sx, sy, err, e2: INTEGER;
        done: BOOLEAN;
  BEGIN
    dx := x1 - x0;
    IF dx < 0 THEN dx := -dx END;
    dy := y1 - y0;
    IF dy < 0 THEN dy := -dy END;
    IF x0 < x1 THEN sx := 1 ELSE sx := -1 END;
    IF y0 < y1 THEN sy := 1 ELSE sy := -1 END;
    err := dx - dy;
    done := FALSE;
    WHILE ~done DO
      SetPixel(x0, y0);
      IF (x0 = x1) & (y0 = y1) THEN
        done := TRUE
      ELSE
        e2 := 2 * err;
        IF e2 > -dy THEN
          err := err - dy;
          x0 := x0 + sx
        END;
        IF e2 < dx THEN
          err := err + dx;
          y0 := y0 + sy
        END
      END
    END
  END DrawLine;

BEGIN
  (* Diagonal line going down-left *)
  DrawLine(12, 8, 5, 3);
  (* Diagonal line going up-right *)
  DrawLine(0, 0, 7, 4);
  (* Steep line *)
  DrawLine(2, 1, 4, 9)
END L0_Bresenham.
