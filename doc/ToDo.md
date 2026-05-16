* Web
x WASM target
Web UI
Server 
- File access
- Env, based on URL
- Serve app at URL base
- Authentication


# Design By Contract

PROCEDURE Test(a: INTEGER, p: POINTER) 
VAR
  i: INTEGER;
REQUIRE
  a > 0;
  p == NIL;
BEGIN
  p := NEW(typ);
  RETURN p;
ENSURE
  p <> NIL;
END

# Single value functions

PROCEDURE Result(b: BOOLEAN)

TestRunner.Result := a > 10;

