MODULE Strings;

  VAR greeting*: ARRAY 16 OF CHAR;

  PROCEDURE Greet*();
  BEGIN
    greeting := "hello"
  END Greet;

  PROCEDURE Echo*(VAR s: ARRAY OF CHAR);
  BEGIN
    s := "echoed"
  END Echo;

  PROCEDURE EqGreeting*(VAR s: ARRAY OF CHAR): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    r := s = greeting;
    RETURN r
  END EqGreeting;

  PROCEDURE FirstChar*(): CHAR;
    VAR c: CHAR;
  BEGIN
    c := "A";
    RETURN c
  END FirstChar;

BEGIN
  greeting := "init"
END Strings.
