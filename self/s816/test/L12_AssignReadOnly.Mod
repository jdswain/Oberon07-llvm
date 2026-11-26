MODULE L12_AssignReadOnly;
  TYPE R = RECORD x: INTEGER END;
  PROCEDURE P(r: R);
  BEGIN
    r.x := 5
  END P;
BEGIN
END L12_AssignReadOnly.
