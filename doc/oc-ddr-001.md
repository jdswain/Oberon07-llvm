# Web Port

## Server
Server provides HTTP serving of web UI files and WASM code.
Written in Go

## Runtime
Any extensions to Runtime interface should be added to the posix port as well, no need to implement the functionality, just keep the interface consistent.

### UI
Provide typescript based TUI support using TUI.Mod as interface.
Looks like a terminal interface, no graphics. Editor should have fixed width font. 
Provide foreground and background color support. Limited palette based on IBM 3270 or 5250 terminal colors.
Bold and Italic support (fixed width).

### Env
Env values come from server and URL, so URL sets base path.

### Files
Files API passes through to server.
Server has base FileStore path.
URL extends this with further ProjectBase path.
Security check that paths cannot escape FileStore.
 
# Later
Authentication
Font support