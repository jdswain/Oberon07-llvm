MODULE L1_SystemPut; (* SYSTEM.PUT to a device: the board's serial port,
   channel A of the SCC, waiting with SYSTEM.GET for room as Out does *)
  IMPORT SYSTEM, Out;
  CONST SccCtl = 0822H; SccData = 0823H;

  PROCEDURE Put(ch: CHAR);
    VAR b: BYTE;
  BEGIN REPEAT SYSTEM.GET(0, SccCtl, b) UNTIL ODD(b DIV 4); SYSTEM.PUT(0, SccData, ch)
  END Put;

BEGIN
  Put("H"); Put("i"); Put(0AX);
  Out.Char("."); Out.Ln()
END L1_SystemPut.
