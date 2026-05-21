MODULE PosixTUICheck;
(* Smoke for the 3270 → ANSI colour mapping. Each fg colour prints
   its name through TUI's own buffer (Out goes to a different stream). *)
  IMPORT TUI;

BEGIN
  TUI.SetFg(TUI.ColorBlack);     TUI.WriteStr("black ");
  TUI.SetFg(TUI.ColorBlue);      TUI.WriteStr("blue ");
  TUI.SetFg(TUI.ColorRed);       TUI.WriteStr("red ");
  TUI.SetFg(TUI.ColorPink);      TUI.WriteStr("pink ");
  TUI.SetFg(TUI.ColorGreen);     TUI.WriteStr("green ");
  TUI.SetFg(TUI.ColorTurquoise); TUI.WriteStr("turquoise ");
  TUI.SetFg(TUI.ColorYellow);    TUI.WriteStr("yellow ");
  TUI.SetFg(TUI.ColorWhite);     TUI.WriteStr("white");
  TUI.SetFg(TUI.ColorDefault);   TUI.Write(0AX);
  TUI.Flush
END PosixTUICheck.
