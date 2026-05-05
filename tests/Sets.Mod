MODULE Sets;

  PROCEDURE Empty*(): SET;     BEGIN RETURN {} END Empty;
  PROCEDURE Single*(): SET;    BEGIN RETURN {3} END Single;
  PROCEDURE Range*(): SET;     BEGIN RETURN {2..5} END Range;
  PROCEDURE Mixed*(): SET;     BEGIN RETURN {0, 3, 5..7, 10} END Mixed;
  PROCEDURE FullByte*(): SET;  BEGIN RETURN {0..7} END FullByte;
  PROCEDURE FullWord*(): SET;  BEGIN RETURN {0..31} END FullWord;

  PROCEDURE Union*(): SET;
  BEGIN
    RETURN {0..3} + {5..7}
  END Union;

  PROCEDURE Intersect*(): SET;
  BEGIN
    RETURN {0..7} * {3..10}    (* should be {3..7} *)
  END Intersect;

  PROCEDURE Diff*(): SET;
  BEGIN
    RETURN {0..7} - {2..4}     (* should be {0,1,5,6,7} *)
  END Diff;

  PROCEDURE Sym*(): SET;
  BEGIN
    RETURN {0..3} / {2..5}     (* symmetric diff: {0,1,4,5} *)
  END Sym;

  PROCEDURE InTest*(n: INTEGER): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    r := n IN {0..3, 7..9};
    RETURN r
  END InTest;

  PROCEDURE InclExcl*(): SET;
    VAR s: SET;
  BEGIN
    s := {};
    INCL(s, 1);
    INCL(s, 5);
    INCL(s, 10);
    EXCL(s, 5);
    RETURN s    (* {1, 10} *)
  END InclExcl;

END Sets.
