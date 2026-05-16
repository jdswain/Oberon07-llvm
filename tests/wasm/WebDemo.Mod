MODULE WebDemo;
(* End-to-end demo for the web port. Exercises:
   - TUI colour palette + bold + italic + underline + reverse
   - Env.BasePath (URL-derived project root)
   - Files round-trip via the HTTP API
   Event-driven loop: registers a key handler with TUI.SetKeyHandler
   and yields control via TUI.Run. On posix Run blocks reading the
   PTY; on wasm Run returns immediately and the JS host invokes the
   handler per keydown. *)

  IMPORT TUI, Env, Files;

  VAR
    base:    ARRAY 256 OF CHAR;
    msg:     ARRAY 256 OF CHAR;
    lastKey: INTEGER;
    typed:   ARRAY 256 OF CHAR;
    typedAt: INTEGER;

  PROCEDURE labelled(label, value: ARRAY OF CHAR);
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
    TUI.SetAttr(TUI.AttrNormal); TUI.SetFg(TUI.ColorDefault);

    TUI.MoveTo(2, 3);
    Env.BasePath(base);
    labelled("project base : ", base);

    TUI.MoveTo(2, 5);
    TUI.SetAttr(TUI.AttrItalic); TUI.SetFg(TUI.ColorGreen);
    TUI.WriteStr("italic green");
    TUI.SetAttr(TUI.AttrNormal); TUI.SetFg(TUI.ColorDefault);

    TUI.MoveTo(20, 5);
    TUI.SetAttr(TUI.AttrUnderline); TUI.SetFg(TUI.ColorBlue);
    TUI.WriteStr("underlined blue");
    TUI.SetAttr(TUI.AttrNormal); TUI.SetFg(TUI.ColorDefault);

    TUI.MoveTo(45, 5);
    TUI.SetAttr(TUI.AttrReverse);
    TUI.WriteStr(" reverse ");
    TUI.SetAttr(TUI.AttrNormal);

    TUI.MoveTo(2, 7); labelled("last status  : ", msg);
    TUI.MoveTo(2, 8); labelled("last keycode : ", "");
    TUI.WriteInt(lastKey);
    TUI.MoveTo(2, 9); labelled("typed so far : ", typed);

    TUI.MoveTo(2, 11);
    TUI.SetFg(TUI.ColorPink);    TUI.WriteStr("s = save  ");
    TUI.SetFg(TUI.ColorTurquoise); TUI.WriteStr("l = load  ");
    TUI.SetFg(TUI.ColorRed);     TUI.WriteStr("q = quit");
    TUI.SetFg(TUI.ColorDefault);

    TUI.MoveTo(0, 13);
    TUI.Flush
  END paint;

  PROCEDURE doSave();
    VAR f: Files.File; r: Files.Rider;
  BEGIN
    f := Files.New("demo.txt");
    IF f = NIL THEN msg := "save: New returned NIL"
    ELSE
      Files.Set(r, f, 0);
      Files.WriteString(r, typed);
      Files.WriteInt(r, lastKey);
      Files.Register(f);
      msg := "saved demo.txt"
    END
  END doSave;

  PROCEDURE doLoad();
    VAR f: Files.File; r: Files.Rider; s: ARRAY 256 OF CHAR; v: INTEGER;
  BEGIN
    f := Files.Old("demo.txt");
    IF f = NIL THEN msg := "load: not found (save first)"
    ELSE
      Files.Set(r, f, 0);
      Files.ReadString(r, s);
      Files.ReadInt(r, v);
      typed := s;
      msg := "loaded demo.txt"
    END
  END doLoad;

  PROCEDURE appendTyped(ch: CHAR);
  BEGIN
    IF typedAt < LEN(typed) - 1 THEN
      typed[typedAt] := ch;
      INC(typedAt);
      typed[typedAt] := 0X
    END
  END appendTyped;

  PROCEDURE handleKey(k: INTEGER);
  BEGIN
    lastKey := k;
    IF k = ORD("q") THEN
      msg := "bye";
      paint;
      TUI.Quit
    ELSIF k = ORD("s") THEN doSave; paint
    ELSIF k = ORD("l") THEN doLoad; paint
    ELSIF (k = 127) OR (k = 8) THEN
      IF typedAt > 0 THEN DEC(typedAt); typed[typedAt] := 0X END;
      paint
    ELSIF (k >= 32) & (k < 127) THEN
      appendTyped(CHR(k));
      paint
    ELSE
      paint
    END
  END handleKey;

BEGIN
  msg := "ready — click the terminal then type";
  typed := ""; typedAt := 0; lastKey := 0;
  TUI.Init;
  TUI.HideCursor;
  paint;
  TUI.SetKeyHandler(handleKey);
  TUI.Run
END WebDemo.
