MODULE Ctors;
  (* Initialisers / named constructors (DDR-003/004/005): allocation and
     initialisation as one expression, multiple constructors per type
     keyed by name, inherited constructors constructing the derived type,
     and a derived initialiser hiding the base set. *)

  TYPE
    Conn*     = POINTER TO ConnDesc;
    ConnDesc* = RECORD host*, port*: INTEGER END;

    (* no own initialisers: inherits Conn's, but constructs an HConn *)
    HConn*     = POINTER TO HConnDesc;
    HConnDesc* = RECORD (ConnDesc) path*: INTEGER END;

    (* own initialiser: hides the base type's constructor set *)
    SConn*     = POINTER TO SConnDesc;
    SConnDesc* = RECORD (ConnDesc) key*: INTEGER END;

  PROCEDURE INIT (c: Conn) Create* (h, p: INTEGER);
  BEGIN
    c.host := h; c.port := p
  END Create;

  PROCEDURE INIT (c: Conn) CreateDefault* ();
  BEGIN
    c.host := 1; c.port := 80
  END CreateDefault;

  PROCEDURE INIT (s: SConn) CreateWithKey* (k: INTEGER);
  BEGIN
    SUPER.Create(9, 443);   (* DDR-003: derived initialisers chain to the base *)
    s.key := k
  END CreateWithKey;

  (* methods and constructors coexist on one type *)
  PROCEDURE (c: Conn) Sum* (): INTEGER;
  BEGIN
    RETURN c.host + c.port
  END Sum;

  PROCEDURE (s: SConn) Sum* (): INTEGER OVERRIDE;
  BEGIN
    RETURN s.host + s.port + s.key
  END Sum;

  (* constructor call from the defining module itself *)
  PROCEDURE MakeDefault* (): Conn;
  BEGIN
    RETURN Conn.CreateDefault()
  END MakeDefault;

END Ctors.
