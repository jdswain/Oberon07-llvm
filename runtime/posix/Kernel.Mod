MODULE Kernel;
(* Slim port of NW's Project Oberon Kernel — keeps the sector-I/O,
   sector-map, and clock interface that Files / FileDir depend on, but
   drops the GC, SPI, SD-card and trap machinery that's specific to the
   RISC FPGA target. Strong overrides live in Kernel_rt.c, which backs
   sectors against a host file (default ./oberon.disk). *)

  CONST SectorLength* = 1024;
        mapsize       = 10000H;   (* 1K-sector × 64 = 64MB pool *)

  TYPE Sector* = ARRAY SectorLength OF BYTE;

  VAR
    allocated*, NofSectors*: INTEGER;
    clock: INTEGER;
    sectorMap: ARRAY mapsize DIV 32 OF SET;

  PROCEDURE InitSecMap*();
    VAR i: INTEGER;
  BEGIN NofSectors := 0; sectorMap[0] := {0..31}; sectorMap[1] := {0..31};
    FOR i := 2 TO mapsize DIV 32 - 1 DO sectorMap[i] := {} END
  END InitSecMap;

  PROCEDURE MarkSector*(sec: INTEGER);
  BEGIN sec := sec DIV 29;
    INCL(sectorMap[sec DIV 32], sec MOD 32); INC(NofSectors)
  END MarkSector;

  PROCEDURE FreeSector*(sec: INTEGER);
  BEGIN sec := sec DIV 29;
    EXCL(sectorMap[sec DIV 32], sec MOD 32); DEC(NofSectors)
  END FreeSector;

  PROCEDURE AllocSector*(hint: INTEGER; VAR sec: INTEGER);
    VAR s: INTEGER;
  BEGIN
    hint := hint DIV 29; s := hint;
    REPEAT INC(s);
      IF s = mapsize THEN s := 1 END
    UNTIL ~(s MOD 32 IN sectorMap[s DIV 32]);
    INCL(sectorMap[s DIV 32], s MOD 32); INC(NofSectors); sec := s * 29
  END AllocSector;

  (* The four Get/Put procs are weak stubs; Kernel_rt.c provides the
     real disk-backed bodies. Empty bodies trigger the compiler's
     "stub→weak" detection so the linker picks the C version. *)

  PROCEDURE GetSector*(src: INTEGER; VAR dst: Sector);
  BEGIN
  END GetSector;

  PROCEDURE PutSector*(dst: INTEGER; VAR src: Sector);
  BEGIN
  END PutSector;

  PROCEDURE Clock*(): INTEGER;
  BEGIN RETURN clock
  END Clock;

  PROCEDURE SetClock*(dt: INTEGER);
  BEGIN clock := dt
  END SetClock;

  PROCEDURE Init*();
  BEGIN
  END Init;

END Kernel.
