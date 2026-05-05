MODULE Cases;

  PROCEDURE Day*(n: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    CASE n OF
      0:        r := 100
    | 1, 2, 3:  r := 200
    | 4..6:     r := 300
    | 7:        r := 400
    ELSE
                r := 999
    END;
    RETURN r
  END Day;

  PROCEDURE Vowel*(c: CHAR): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    r := FALSE;
    CASE c OF
      "a", "e", "i", "o", "u": r := TRUE
    | "A".."Z":                r := (c = "A") OR (c = "E") OR (c = "I")
                                                  OR (c = "O") OR (c = "U")
    ELSE
                               r := FALSE
    END;
    RETURN r
  END Vowel;

  PROCEDURE NoElse*(n: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    r := -1;
    CASE n OF
      1: r := 10
    | 2: r := 20
    END;
    RETURN r
  END NoElse;

END Cases.
