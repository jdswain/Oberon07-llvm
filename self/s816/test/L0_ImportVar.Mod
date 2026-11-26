MODULE L0_ImportVar;
  IMPORT Out, ExportVar;

BEGIN
  Out.Hex(ExportVar.x);
  Out.Char(" ");
  Out.Hex(ExportVar.y);
  Out.Ln()
END L0_ImportVar.
