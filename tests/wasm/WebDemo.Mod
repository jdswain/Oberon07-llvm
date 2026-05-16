MODULE WebDemo;
(* End-to-end demo for the web port. Exercises:
   - TUI colour palette + bold + italic + cursor positioning
   - Env.BasePath (URL-derived project root)
   - Files round-trip via the HTTP API
   The program runs once, paints a screen, then loops on ReadKey so
   the user can press 's' to save / 'l' to load / 'q' to quit. *)

  IMPORT TUI, Env, Files;

  VAR
    base: ARRAY 256 OF CHAR;
    msg:  ARRAY 256 OF CHAR;
    f:    Files.File;
    r:    Files.Rider;
    k:    INTEGER;
    res:  INTEGER;
    quit: BOOLEAN;

  PROCEDURE labelled(label: ARRAY OF CHAR; value: ARRAY OF CHAR);
  BEGIN
    TUI.SetFg(TUI.ColorTurquoise);
    TUI.WriteStr(label);
    TUI.SetFg(TUI.ColorWhite);
    TUI.WriteStr(value);
    TUI.SetFg(TUI.ColorDefault)
  END labelled;

  PROCEDURE paint();
  BEGIN
    TUI.Clear;
    TUI.MoveTo(2, 1);
    TUI.SetAttr(TUI.AttrBold);
    TUI.SetFg(TUI.ColorYellow);
    TUI.WriteStr("oc web port demo");
    TUI.SetAttr(TUI.AttrNormal);
    TUI.SetFg(TUI.ColorDefault);

    TUI.MoveTo(2, 3);
    Env.BasePath(base);
    labelled("project base : ", base);

    TUI.MoveTo(2, 5);
    TUI.SetAttr(TUI.AttrItalic);
    TUI.SetFg(TUI.ColorGreen);
    TUI.WriteStr("italic green");
    TUI.SetAttr(TUI.AttrNormal);
    TUI.SetFg(TUI.ColorDefault);

    TUI.MoveTo(20, 5);
    TUI.SetAttr(TUI.AttrReverse);
    TUI.WriteStr(" reverse video ");
    TUI.SetAttr(TUI.AttrNormal);

    TUI.MoveTo(2, 7);
    labelled("last status  : ", msg);

    TUI.MoveTo(2, 9);
    TUI.SetFg(TUI.ColorPink);
    TUI.WriteStr("s = save  ");
    TUI.SetFg(TUI.ColorTurquoise);
    TUI.WriteStr("l = load  ");
    TUI.SetFg(TUI.ColorRed);
    TUI.WriteStr("q = quit");
    TUI.SetFg(TUI.ColorDefault);

    TUI.MoveTo(0, 11);
    TUI.Flush
  END paint;

  PROCEDURE doSave();
  BEGIN
    f := Files.New("demo.txt");
    IF f = NIL THEN msg := "save: New returned NIL"
    ELSE
      Files.Set(r, f, 0);
      Files.WriteString(r, "Hello from Oberon in your browser! Last keypress: ");
      Files.WriteInt(r, k);
      Files.Register(f);
      msg := "saved demo.txt"
    END
  END doSave;

  PROCEDURE doLoad();
    VAR s: ARRAY 256 OF CHAR; v: INTEGER;
  BEGIN
    f := Files.Old("demo.txt");
    IF f = NIL THEN msg := "load: not found (save first)"
    ELSE
      Files.Set(r, f, 0);
      Files.ReadString(r, s);
      Files.ReadInt(r, v);
      msg := s
    END
  END doLoad;

BEGIN
  msg := "ready";
  TUI.Init;
  TUI.HideCursor;
  paint;
  quit := FALSE;
  WHILE ~quit DO
    k := TUI.ReadKey();
    IF k = ORD("q") THEN quit := TRUE
    ELSIF k = ORD("s") THEN doSave; paint
    ELSIF k = ORD("l") THEN doLoad; paint
    END
  END;
  TUI.ShowCursor;
  TUI.Shutdown
END WebDemo.
