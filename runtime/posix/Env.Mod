MODULE Env;
(* Process environment access. The compiler-emitted entry stub stashes
   argc/argv via the runtime's oc_set_args before <Entry>__init runs,
   so these accessors are valid from the very first line of any
   module body.

   Argv slot 0 is the program path (or whatever the OS handed to us),
   matching the conventional C ordering — real arguments start at 1.

   Future env-related helpers (env vars, working directory, exit
   codes) belong here too. *)

  PROCEDURE ArgCount*(): INTEGER;
  BEGIN RETURN 0
  END ArgCount;

  PROCEDURE Arg*(i: INTEGER; VAR s: ARRAY OF CHAR);
  BEGIN
  END Arg;

  PROCEDURE Cwd*(VAR s: ARRAY OF CHAR);
  BEGIN
  END Cwd;

END Env.
