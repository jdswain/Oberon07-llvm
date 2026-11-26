MODULE L10_Interrupt;
  IMPORT Out;
  VAR count: INTEGER;

  PROCEDURE * Handler;
  BEGIN
    count := count + 1
  END Handler;

BEGIN
  count := 0;
  (* We cannot trigger a real interrupt in the emulator,
     but we verify that the interrupt procedure compiles
     and the module runs correctly *)
  Out.Int(count, 1); Out.Ln()
END L10_Interrupt.
