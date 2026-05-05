MODULE StrPass;

  PROCEDURE FirstByte*(VAR s: ARRAY OF CHAR): INTEGER;
  BEGIN
    RETURN ORD(s[0])
  END FirstByte;

  PROCEDURE Length*(VAR s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO
      i := i + 1
    END;
    RETURN i
  END Length;

  PROCEDURE FirstByteOfHi*(): INTEGER;
  BEGIN
    RETURN FirstByte("hi")
  END FirstByteOfHi;

  PROCEDURE LengthOfHello*(): INTEGER;
  BEGIN
    RETURN Length("hello")
  END LengthOfHello;

END StrPass.
