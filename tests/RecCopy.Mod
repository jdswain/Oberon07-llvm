MODULE RecCopy;

  TYPE
    Pt* = RECORD x*, y*, z*: INTEGER END;

  PROCEDURE Copy*(VAR dst, src: Pt);
  BEGIN
    dst := src
  END Copy;

END RecCopy.
