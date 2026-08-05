MODULE ORG; (* Interface to the LLVM code generator (DDR C-bridge module).

   The implementation is C — self/ORG_rt.c, an adaptation of src/ORG.c
   that drives the LLVM-C API. Every procedure here is an exported empty
   stub, so it compiles to a weak symbol that the C definition overrides
   at link time (the same mechanism the runtime modules use).

   The Item record is the parser<->backend workhorse. Its layout is
   mirrored by a C struct in ORG_rt.c — do not reorder fields. The two
   type fields are WEAK pointers: the backend writes them without ARC
   bookkeeping (symbol-table objects are owned by the scope structure),
   so the frontend must not treat them as owning references either.
   backend/backend2 are opaque codegen handles (LLVMValueRef). *)

  IMPORT ORB;

  (* Target parameters (DDR back-porting: the frontend reads these so
     ORS/ORB/ORP are shared with the 65C816 backend). For LLVM the byte
     sizes are nominal — the backend lays out structs via the LLVM ABI
     and ignores frontend offsets — so these keep their historical values
     and nothing about the emitted IR changes. *)
  CONST
    WordSize* = 4;
    SetMax* = 32;      (* SET elements 0 .. SetMax-1 *)
    ParLimit* = 52;    (* max parameter-block size *)
    IntSize* = 4; LongSize* = 8; RealSize* = 4;
    SetSize* = 4; NilSize* = 4; StrSize* = 8;
    PtrSize* = 4; IntfcSize* = 16;   (* fat pointer = two native 8-byte ptrs *)

  TYPE
    Item* = RECORD
      mode*: INTEGER;
      type*: ORB.WType;
      a*, b*, r*: LONGINT;
      rdo*: BOOLEAN;                (* read only *)
      origType*: ORB.WType;         (* original operand type for signed cmps *)
      backend*, backend2*: LONGINT  (* codegen-private *)
    END;

  (* Register this target's SYSTEM pseudo-module identifiers. Called by
     ORP after ORB.Initialize. Each backend supplies its own set with
     target-appropriate result types and arities (n = procno*10 + nofpar). *)
  PROCEDURE InitSystem*;
  BEGIN
    ORB.SysFunc("SIZE", ORB.intType, 181);
    ORB.SysFunc("ADR", ORB.longType, 171);
    ORB.SysFunc("VAL", ORB.intType, 162);
    ORB.SysFunc("BIT", ORB.boolType, 142);
    ORB.SysProc("COPY", ORB.noType, 123);
    ORB.SysProc("PUT", ORB.noType, 112);
    ORB.SysProc("GET", ORB.noType, 102)
  END InitSystem;

  (* --- item construction --- *)
  PROCEDURE MakeConstItem*(VAR x: Item; typ: ORB.Type; val: LONGINT);
  BEGIN END MakeConstItem;
  PROCEDURE MakeRealItem*(VAR x: Item; val: REAL);
  BEGIN END MakeRealItem;
  PROCEDURE MakeStringItem*(VAR x: Item; len: LONGINT);
  BEGIN END MakeStringItem;
  PROCEDURE MakeItem*(VAR x: Item; y: ORB.Object; curlev: LONGINT);
  BEGIN END MakeItem;
  PROCEDURE StrOffset*(): LONGINT;
  BEGIN RETURN 0 END StrOffset;
  PROCEDURE PutByte*(b: INTEGER);
  BEGIN END PutByte;
  PROCEDURE PatchStr*(off, val, size: LONGINT);
  BEGIN END PatchStr;
  PROCEDURE CopyStr*(dstOff, srcOff, size: LONGINT);
  BEGIN END CopyStr;
  PROCEDURE MakeRecordConst*(VAR x: Item; typ: ORB.Type; start: LONGINT);
  BEGIN END MakeRecordConst;

  (* --- selectors --- *)
  PROCEDURE Field*(VAR x: Item; y: ORB.Object);
  BEGIN END Field;
  PROCEDURE Index*(VAR x, y: Item);
  BEGIN END Index;
  PROCEDURE DeRef*(VAR x: Item);
  BEGIN END DeRef;
  PROCEDURE MethodItem*(VAR x: Item; m: ORB.Object; direct: BOOLEAN);
  BEGIN END MethodItem;
  PROCEDURE InitItem*(VAR x: Item; m: ORB.Object; rec: ORB.Type);
  BEGIN END InitItem;
  PROCEDURE IfaceMethodItem*(VAR x: Item; m: ORB.Object);
  BEGIN END IfaceMethodItem;
  PROCEDURE Discard*(VAR x: Item);
  BEGIN END Discard;
  PROCEDURE PtrToIface*(VAR x: Item; ift: ORB.Type);
  BEGIN END PtrToIface;
  PROCEDURE StoreIface*(VAR x, y: Item);
  BEGIN END StoreIface;
  PROCEDURE IfaceRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN END IfaceRelation;

  (* --- types --- *)
  PROCEDURE BuildTD*(T: ORB.Type; VAR dc: LONGINT);
  BEGIN END BuildTD;
  PROCEDURE FinalizeTDs*;   (* 816 assigns deferred TD offsets here; LLVM: no-op *)
  BEGIN END FinalizeTDs;
  PROCEDURE TypeTest*(VAR x: Item; T: ORB.Type; varpar, isguard: BOOLEAN);
  BEGIN END TypeTest;

  (* --- boolean --- *)
  PROCEDURE Not*(VAR x: Item);
  BEGIN END Not;
  PROCEDURE And1*(VAR x: Item);
  BEGIN END And1;
  PROCEDURE And2*(VAR x, y: Item);
  BEGIN END And2;
  PROCEDURE Or1*(VAR x: Item);
  BEGIN END Or1;
  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN END Or2;

  (* --- arithmetic --- *)
  PROCEDURE Neg*(VAR x: Item);
  BEGIN END Neg;
  PROCEDURE AddOp*(op: LONGINT; VAR x, y: Item);
  BEGIN END AddOp;
  PROCEDURE MulOp*(VAR x, y: Item);
  BEGIN END MulOp;
  PROCEDURE DivOp*(op: LONGINT; VAR x, y: Item);
  BEGIN END DivOp;
  PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);
  BEGIN END RealOp;

  (* --- sets --- *)
  PROCEDURE Singleton*(VAR x: Item);
  BEGIN END Singleton;
  PROCEDURE Set*(VAR x, y: Item);
  BEGIN END Set;
  PROCEDURE In*(VAR x, y: Item);
  BEGIN END In;
  PROCEDURE SetOp*(op: LONGINT; VAR x, y: Item);
  BEGIN END SetOp;

  (* --- relations --- *)
  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN END IntRelation;
  PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN END RealRelation;
  PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN END StringRelation;

  (* --- assignment --- *)
  PROCEDURE StrToChar*(VAR x: Item);
  BEGIN END StrToChar;
  PROCEDURE Store*(VAR x, y: Item);
  BEGIN END Store;
  PROCEDURE StoreStruct*(VAR x, y: Item);
  BEGIN END StoreStruct;
  PROCEDURE CopyString*(VAR x, y: Item);
  BEGIN END CopyString;

  (* --- parameters --- *)
  PROCEDURE OpenArrayParam*(VAR x: Item);
  BEGIN END OpenArrayParam;
  PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
  BEGIN END VarParam;
  PROCEDURE ValueParam*(VAR x: Item; ftype: ORB.Type);
  BEGIN END ValueParam;
  PROCEDURE StringParam*(VAR x: Item);
  BEGIN END StringParam;

  (* --- FOR --- *)
  PROCEDURE For0*(VAR x, y: Item);
  BEGIN END For0;
  PROCEDURE For1*(VAR x, y, z, w: Item; VAR L: LONGINT);
  BEGIN END For1;
  PROCEDURE For2*(VAR x, y, w: Item);
  BEGIN END For2;
  PROCEDURE Snapshot*(VAR x: Item);
  BEGIN END Snapshot;
  PROCEDURE ForClose*;
  BEGIN END ForClose;

  (* --- CASE --- *)
  PROCEDURE CaseLabel*(VAR x: Item; val: LONGINT; VAR chain: LONGINT);
  BEGIN END CaseLabel;
  PROCEDURE CaseRange*(VAR x: Item; lo, hi: LONGINT; VAR chain: LONGINT);
  BEGIN END CaseRange;

  (* --- branches --- *)
  PROCEDURE Here*(): LONGINT;
  BEGIN RETURN 0 END Here;
  PROCEDURE FJump*(VAR L: LONGINT);
  BEGIN END FJump;
  PROCEDURE CFJump*(VAR x: Item);
  BEGIN END CFJump;
  PROCEDURE BJump*(L: LONGINT);
  BEGIN END BJump;
  PROCEDURE CBJump*(VAR x: Item; L: LONGINT);
  BEGIN END CBJump;
  PROCEDURE Fixup*(VAR x: Item);
  BEGIN END Fixup;
  PROCEDURE FixOne*(at: LONGINT);
  BEGIN END FixOne;
  PROCEDURE FixLink*(L: LONGINT);
  BEGIN END FixLink;

  (* --- calls, procedures --- *)
  PROCEDURE PrepCall*(VAR x: Item; VAR r: LONGINT);
  BEGIN END PrepCall;
  PROCEDURE Call*(VAR x: Item; r: LONGINT);
  BEGIN END Call;
  PROCEDURE Enter*(proc, params: ORB.Object; parblksize, locblksize: LONGINT; intProc: BOOLEAN);
  BEGIN END Enter;
  PROCEDURE Return*(proc: ORB.Object; VAR x: Item);
  BEGIN END Return;

  (* --- inline procedures --- *)
  PROCEDURE Increment*(upordown: LONGINT; VAR x, y: Item);
  BEGIN END Increment;
  PROCEDURE Include*(inorex: LONGINT; VAR x, y: Item);
  BEGIN END Include;
  PROCEDURE Assert*(VAR x: Item);
  BEGIN END Assert;
  PROCEDURE New*(VAR x: Item);
  BEGIN END New;
  PROCEDURE Pack*(VAR x, y: Item);
  BEGIN END Pack;
  PROCEDURE Unpk*(VAR x, y: Item);
  BEGIN END Unpk;
  PROCEDURE Get*(VAR addr, var: Item);
  BEGIN END Get;
  PROCEDURE Put*(VAR addr, val: Item);
  BEGIN END Put;
  PROCEDURE Copy*(VAR x, y, z: Item);
  BEGIN END Copy;

  (* --- inline functions --- *)
  PROCEDURE Abs*(VAR x: Item);
  BEGIN END Abs;
  PROCEDURE Odd*(VAR x: Item);
  BEGIN END Odd;
  PROCEDURE Floor*(VAR x: Item);
  BEGIN END Floor;
  PROCEDURE Float*(VAR x: Item);
  BEGIN END Float;
  PROCEDURE Ord*(VAR x: Item);
  BEGIN END Ord;
  PROCEDURE Chr*(VAR x: Item);
  BEGIN END Chr;
  PROCEDURE Len*(VAR x: Item);
  BEGIN END Len;
  PROCEDURE Shift*(fct: LONGINT; VAR x, y: Item);
  BEGIN END Shift;
  PROCEDURE Bitwise*(fct: LONGINT; VAR x, y: Item);
  BEGIN END Bitwise;
  PROCEDURE UML*(VAR x, y: Item);
  BEGIN END UML;
  PROCEDURE Bit*(VAR x, y: Item);
  BEGIN END Bit;
  PROCEDURE Adr*(VAR x: Item);
  BEGIN END Adr;

  (* --- 65C816-only SYSTEM entry points (inert on LLVM: never registered
     by InitSystem, so ORP never dispatches to them) --- *)
  PROCEDURE GetB*(VAR bank, addr, var: Item);
  BEGIN END GetB;
  PROCEDURE PutB*(VAR bank, addr, val: Item);
  BEGIN END PutB;
  PROCEDURE TRB*(VAR x, y: Item);
  BEGIN END TRB;
  PROCEDURE TSB*(VAR x, y: Item);
  BEGIN END TSB;
  PROCEDURE Exec*(VAR addr, bank: Item);
  BEGIN END Exec;
  PROCEDURE IntEn*(VAR x: Item);
  BEGIN END IntEn;
  PROCEDURE Bank*(VAR x: Item);
  BEGIN END Bank;
  PROCEDURE HH*(VAR x: Item);
  BEGIN END HH;
  PROCEDURE Condition*(VAR x: Item);
  BEGIN END Condition;

  (* --- module management --- *)
  PROCEDURE Open*(modid: ARRAY OF CHAR; v: INTEGER);
  BEGIN END Open;
  PROCEDURE SetDataSize*(dc: LONGINT);
  BEGIN END SetDataSize;
  PROCEDURE Header*;
  BEGIN END Header;
  PROCEDURE Close*(modid: ARRAY OF CHAR; key, nofent: LONGINT);
  BEGIN END Close;
  PROCEDURE CheckRegs*;
  BEGIN END CheckRegs;
  PROCEDURE Init*;
  BEGIN END Init;

END ORG.
