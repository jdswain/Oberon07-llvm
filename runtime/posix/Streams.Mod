MODULE Streams;
(* The portable stream core (DDR-008 §3, DDR-009, DDR-010 §2).

   These are the named interfaces that a file and a socket both INCLUDE,
   so the two are interchangeable wherever only the stream is needed.
   The interface is *nominal* (DDR-008): a concrete type reaches these by
   declaring `RECORD IMPLEMENTS Streams.ReadWriteCloser`, not by matching
   shape. This module carries no implementation — only obligations — so it
   has no C sidecar and is identical on every backend.

   Read/Write take an explicit (start, len) window into buf — Oberon-07 has
   no array slices and no safe pointer-into-buffer, so the window is how a
   caller reads or writes a chunk of a larger buffer without copying; the
   pointer arithmetic is done once, safely, in the backing implementation.
   start and len are clamped to buf's bounds.

   Read fills buf[start ..< start+len] and returns the count actually read;
   0 means end-of-stream, a negative result means an error. Write writes len
   bytes from buf[start] and returns the count written (a short count signals
   the caller must retry the tail). *)

  TYPE
    Reader* = INTERFACE
      PROCEDURE Read (VAR buf: ARRAY OF BYTE; start, len: INTEGER): INTEGER
    END;

    Writer* = INTERFACE
      PROCEDURE Write (buf: ARRAY OF BYTE; start, len: INTEGER): INTEGER
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
