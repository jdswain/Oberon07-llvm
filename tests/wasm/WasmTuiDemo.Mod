MODULE WasmTuiDemo;
(* Smoke test for the wasm TUI runtime. Builds against the JS-import
   shim in runtime/wasm/TUI_rt.c — no native side effects when run
   under a plain wasmtime, since wasmtime can't resolve the "tui"
   imports. Useful for verifying the import contract and for running
   under a browser host that supplies the tui shim (see
   tests/wasm/tui-shim.js). *)

  IMPORT TUI;

BEGIN
  TUI.Init;
  TUI.HideCursor;
  TUI.Clear;
  TUI.MoveTo(0, 0);
  TUI.SetAttr(TUI.AttrBold);
  TUI.WriteStr("Hello from wasm TUI!");
  TUI.SetAttr(TUI.AttrNormal);
  TUI.MoveTo(0, 2);
  TUI.WriteStr("rows="); TUI.WriteInt(TUI.Rows);
  TUI.WriteStr(" cols="); TUI.WriteInt(TUI.Cols);
  TUI.Flush;
  TUI.ShowCursor;
  TUI.Shutdown
END WasmTuiDemo.
