MODULE L16_OOExt;
  (* Cross-module OO, extension side: overrides an imported method (same
     vtable slot across the .smb boundary) and adds a new slot. *)
  IMPORT L16_OOBase, HeapManager;
  TYPE
    Dog*     = POINTER TO DogDesc;
    DogDesc* = RECORD (L16_OOBase.AnimalDesc) bites*: INTEGER END;

  PROCEDURE (d: Dog) Sound* (): INTEGER OVERRIDE;
  BEGIN RETURN 200 END Sound;

  PROCEDURE (d: Dog) Bites* (): INTEGER;
  BEGIN RETURN d.bites END Bites;

  PROCEDURE NewDog* (legs, bites: INTEGER): Dog;
    VAR d: Dog;
  BEGIN NEW(d); d.legs := legs; d.bites := bites; RETURN d END NewDog;
END L16_OOExt.
