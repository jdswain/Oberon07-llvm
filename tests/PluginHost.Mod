MODULE PluginHost;
  IMPORT Out, Modules;

  VAR plugin: Modules.Module;
      cmd: Modules.Command;

BEGIN
  Out.WriteString("Host starting..."); Out.Ln();

  Modules.Load("Plugin", plugin);
  IF plugin = NIL THEN
    Out.WriteString("Failed to load Plugin"); Out.Ln()
  ELSE
    Out.WriteString("Loaded module: ");
    Out.WriteString(plugin.name);
    Out.WriteString(" (refcnt="); Out.WriteInt(plugin.refcnt); Out.WriteString(")");
    Out.Ln();

    cmd := Modules.ThisCommand(plugin, "Hello");
    IF cmd # NIL THEN cmd() END;

    cmd := Modules.ThisCommand(plugin, "Sum");
    IF cmd # NIL THEN cmd() END;

    Modules.Free("Plugin");
    Out.WriteString("Host: plugin freed"); Out.Ln()
  END
END PluginHost.
