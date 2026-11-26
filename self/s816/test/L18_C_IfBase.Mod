MODULE L18_C_IfBase; IMPORT SYSTEM;
TYPE
  Sink* = INTERFACE PROCEDURE Put(c: CHAR) END;
  Pair* = RECORD a*: Sink; k*: INTEGER; b*: Sink END;
VAR p*: Pair; last*: INTEGER;
PROCEDURE Send*(s: Sink; t: Sink; k: INTEGER);
BEGIN s.Put("s"); t.Put("t"); last := k
END Send;
PROCEDURE Take*(VAR s: Sink; t: Sink);
BEGIN s := t
END Take;
PROCEDURE Set*(s: Sink; k: INTEGER);
BEGIN p.b := s; p.k := k
END Set;
PROCEDURE Size*(): INTEGER;
BEGIN RETURN SYSTEM.SIZE(Pair)
END Size;
END L18_C_IfBase.
