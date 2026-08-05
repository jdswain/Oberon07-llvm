MODULE Tasks;
(* Cooperative concurrency — the DDR-014 Option 1 surface (library Spawn/Yield,
   no grammar change). A task is either a parameterless procedure (Spawn) or an
   object with a Run method (SpawnTask) — the object is Oberon's stand-in for a
   closure, carrying the state a bare procedure can't. Tasks run until they
   Yield or block on I/O; Run drives them all to completion on one thread. The
   scheduler and per-task stacks live in Tasks_rt.c (DDR-014 §2.1, LLVM/POSIX).

   Blocking-looking I/O (Net.Conn.Read/Write, Net.Listener.Accept) transparently
   yields here: the socket's would-block turns into a task switch, so a server
   accepting on one connection keeps serving the others — no callbacks, no
   async colouring. Cooperative scheduling means state shared between tasks is
   safe between yields, so there are no locks (DDR-014 §2).

   Typical use:
     Tasks.Spawn(Server);      (* each an accept loop / worker / client *)
     Tasks.Spawn(Client);
     Tasks.Run                 (* returns when every task has finished *)   *)

  TYPE
    Body* = PROCEDURE;

    Task* = INTERFACE
      PROCEDURE Run ()
    END;

    (* adapter so a bare procedure can ride the same slot as an object task *)
    ProcTask = POINTER TO ProcTaskDesc;
    ProcTaskDesc = RECORD IMPLEMENTS Task
      body: Body
    END;

  VAR
    (* taskList[id] is the object the C scheduler will dispatch for slot id.
       Sized to Tasks_rt.c's MAX_TASKS. *)
    taskList: ARRAY 1024 OF Task;

  (* ----- raw C bridges (Tasks_rt.c); weak stubs overridden at link ----- *)

  PROCEDURE spawnRaw* (): INTEGER;
  BEGIN RETURN -1
  END spawnRaw;

  PROCEDURE Yield* ();
  BEGIN
  END Yield;

  PROCEDURE Run* ();
  BEGIN
  END Run;

  (* ----- scheduler -> Oberon dispatch (called from the C trampoline) ----- *)

  PROCEDURE taskMain* (id: INTEGER);
  BEGIN
    taskList[id].Run();
    taskList[id] := NIL          (* drop the reference; ARC reclaims the task *)
  END taskMain;

  (* ----- surface ----- *)

  PROCEDURE SpawnTask* (t: Task);
    VAR id: INTEGER;
  BEGIN
    id := spawnRaw();
    IF id >= 0 THEN taskList[id] := t END
  END SpawnTask;

  PROCEDURE (t: ProcTask) Run ();
  BEGIN t.body
  END Run;

  PROCEDURE Spawn* (b: Body);
    VAR t: ProcTask;
  BEGIN NEW(t); t.body := b; SpawnTask(t)
  END Spawn;

END Tasks.
