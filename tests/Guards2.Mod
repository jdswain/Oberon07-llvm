MODULE Guards2;
  (* Multi-level type-CASE with shared ancestor types. *)

  TYPE
    Animal*     = POINTER TO AnimalDesc;
    AnimalDesc* = RECORD age*: INTEGER END;

    Mammal*     = POINTER TO MammalDesc;
    MammalDesc* = RECORD (AnimalDesc) fur*: INTEGER END;

    Dog*        = POINTER TO DogDesc;
    DogDesc*    = RECORD (MammalDesc) breed*: INTEGER END;

    Cat*        = POINTER TO CatDesc;
    CatDesc*    = RECORD (MammalDesc) lives*: INTEGER END;

    Bird*       = POINTER TO BirdDesc;
    BirdDesc*   = RECORD (AnimalDesc) feathers*: INTEGER END;

  PROCEDURE NewDog*(b: INTEGER): Animal;
    VAR d: Dog;
  BEGIN NEW(d); d.age := 7; d.fur := 1; d.breed := b; RETURN d
  END NewDog;

  PROCEDURE NewCat*(l: INTEGER): Animal;
    VAR c: Cat;
  BEGIN NEW(c); c.age := 5; c.fur := 2; c.lives := l; RETURN c
  END NewCat;

  PROCEDURE NewBird*(f: INTEGER): Animal;
    VAR b: Bird;
  BEGIN NEW(b); b.age := 2; b.feathers := f; RETURN b
  END NewBird;

  (* Hierarchical type-CASE — Dog ancestors include Mammal, AnimalDesc.
     Asking IS Dog returns true for a Dog only.
     Asking IS Mammal returns true for Dog and Cat. *)
  PROCEDURE Classify*(a: Animal): INTEGER;
    VAR r: INTEGER;
  BEGIN
    r := -1;
    CASE a OF
      Dog:  r := 1000 + a.breed
    | Cat:  r := 2000 + a.lives
    | Bird: r := 3000 + a.feathers
    END;
    RETURN r
  END Classify;

  (* Mammal CASE — both Dog and Cat should match. *)
  PROCEDURE FurCount*(a: Animal): INTEGER;
    VAR r: INTEGER;
  BEGIN
    r := 0;
    CASE a OF
      Mammal: r := a.fur
    END;
    RETURN r
  END FurCount;

  (* Type guard: narrow Animal to Dog and read breed. *)
  PROCEDURE Breed*(a: Animal): INTEGER;
  BEGIN
    RETURN a(Dog).breed
  END Breed;

END Guards2.
