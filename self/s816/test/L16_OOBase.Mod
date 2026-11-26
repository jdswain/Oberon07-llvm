MODULE L16_OOBase;
  (* Cross-module OO, base side: the extension and callers live in other
     modules; Describe dispatches dynamically knowing only Animal. *)
  TYPE
    Animal*     = POINTER TO AnimalDesc;
    AnimalDesc* = RECORD legs*: INTEGER END;

  PROCEDURE (a: Animal) Sound* (): INTEGER;
  BEGIN RETURN 100 END Sound;

  PROCEDURE (a: Animal) Legs* (): INTEGER;
  BEGIN RETURN a.legs END Legs;

  PROCEDURE Describe* (a: Animal): INTEGER;
  BEGIN RETURN a.Sound() + a.Legs() END Describe;
END L16_OOBase.
