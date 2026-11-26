MODULE L9_StrLib; (* string constants exported, for L9_ImportStr *)
  CONST S* = "Volumes"; Empty* = ""; Long* = "a longer string, of forty characters ok";
  VAR n*: INTEGER;   (* data before the strings: their offsets are past it *)
BEGIN n := 7
END L9_StrLib.
