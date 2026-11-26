MODULE L10_BankPutGet;
  IMPORT SYSTEM, Out;

  CONST
    VideoBase = 0000H;
    VideoBank = 2;

  VAR
    b: BYTE;
    w: INTEGER;

BEGIN
  (* Write single bytes to bank 2 using PUT(bank, addr, val) *)
  SYSTEM.PUT(VideoBank, VideoBase, 0AAH);
  SYSTEM.PUT(VideoBank, VideoBase + 1, 055H);
  SYSTEM.PUT(VideoBank, VideoBase + 2, 0FFH);
  SYSTEM.PUT(VideoBank, VideoBase + 3, 000H);

  (* Read them back using GET(bank, addr, var) *)
  SYSTEM.GET(VideoBank, VideoBase, b);
  Out.Int(b, 0); Out.Ln();
  SYSTEM.GET(VideoBank, VideoBase + 1, b);
  Out.Int(b, 0); Out.Ln();
  SYSTEM.GET(VideoBank, VideoBase + 2, b);
  Out.Int(b, 0); Out.Ln();
  SYSTEM.GET(VideoBank, VideoBase + 3, b);
  Out.Int(b, 0); Out.Ln();

  (* Write and read a word (2 bytes) *)
  SYSTEM.PUT(VideoBank, VideoBase + 10, 1234H);
  SYSTEM.GET(VideoBank, VideoBase + 10, w);
  Out.Int(w, 0); Out.Ln();

  (* Write to bank 0 and read back to verify bank isolation *)
  SYSTEM.PUT(0, 80H, 42);
  SYSTEM.GET(0, 80H, b);
  Out.Int(b, 0); Out.Ln()
END L10_BankPutGet.
