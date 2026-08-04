MODULE Streams;
(* The portable stream core (DDR-008 §3, DDR-009, DDR-010 §2).

   These are the named interfaces that a file and a socket both INCLUDE,
   so the two are interchangeable wherever only the stream is needed.
   The interface is *nominal* (DDR-008): a concrete type reaches these by
   declaring `RECORD IMPLEMENTS Streams.ReadWriteCloser`, not by matching
   shape. This module carries no implementation — only obligations — so it
   has no C sidecar and is identical on every backend.

   Read fills up to LEN(buf) bytes and returns the count actually read;
   0 means end-of-stream, a negative result means an error. Write writes
   LEN(buf) bytes and returns the count written (a short count signals the
   caller must retry the tail). *)

  TYPE
    Reader* = INTERFACE
      PROCEDURE Read (VAR buf: ARRAY OF BYTE): INTEGER
    END;

    Writer* = INTERFACE
      PROCEDURE Write (buf: ARRAY OF BYTE): INTEGER
    END;

    Closer* = INTERFACE
      PROCEDURE Close ()
    END;

    ReadWriter* = INTERFACE
      Reader;
      Writer
    END;

    ReadWriteCloser* = INTERFACE
      Reader;
      Writer;
      Closer
    END;

END Streams.
