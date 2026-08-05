MODULE MethExt;
  (* Cross-module method test, extension side: overrides an imported
     method (same vtable slot across the .smb boundary) and adds a new
     slot of its own. *)

  IMPORT MethBase;

  TYPE
    Dog*     = POINTER TO DogDesc;
    DogDesc* = RECORD (MethBase.AnimalDesc) bites*: INTEGER END;

  PROCEDURE (d: Dog) Sound* (): INTEGER OVERRIDE;
  BEGIN
    RETURN 200
  END Sound;

  PROCEDURE (d: Dog) Bites* (): INTEGER;
  BEGIN
    RETURN d.bites
  END Bites;

  PROCEDURE NewDog* (legs, bites: INTEGER): Dog;
    VAR d: Dog;
  BEGIN
    NEW(d); d.legs := legs; d.bites := bites;
    RETURN d
  END NewDog;

END MethExt.
