MODULE L11_ByteShift;
  (* ASL and LSR of a BYTE give an INTEGER: the byte's bits shifted up
     past its 8 are kept (oc's LLVM host compiler once shifted in 8 bits,
     ASL(b, 8) 0). *)
  IMPORT Out;
  VAR b: BYTE; i, j: INTEGER;
BEGIN
  b := 0ABH; i := b;
  j := ASL(b, 8); Out.Int(j, 0); Out.Ln;
  Out.Int(ASL(b, 4), 0); Out.Ln;
  Out.Int(ASL(i, 1), 0); Out.Ln;
  Out.Int(LSR(b, 4), 0); Out.Ln
END L11_ByteShift.
