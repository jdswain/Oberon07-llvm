MODULE MethBase;
  (* Cross-module method test, base side: the extension and every caller
     live in other modules. Describe dispatches dynamically from here —
     this module knows nothing about the extension. *)

  TYPE
    Animal*     = POINTER TO AnimalDesc;
    AnimalDesc* = RECORD legs*: INTEGER END;

  PROCEDURE (a: Animal) Sound* (): INTEGER;
  BEGIN
    RETURN 100
  END Sound;

  PROCEDURE (a: Animal) Legs* (): INTEGER;
  BEGIN
    RETURN a.legs
  END Legs;

  PROCEDURE Describe* (a: Animal): INTEGER;
  BEGIN
    RETURN a.Sound() + a.Legs()
  END Describe;

END MethBase.
