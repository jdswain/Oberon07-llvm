This is a compiler for the Oberon-07 language using the LLVM backend.

It may be useful for bootstrapping other compilers written in Oberon. 

# Bootstrapping
I initially wrote an Oberon compiler targeting the 65C816 processor. This was implemented in C, being a close port of Nicklas Wirth's Oberon-07 compiler written in Oberon, with ORG changed to target the 65C816. The instruction generation was much more complex than the RISC-5 instruction set targeted in the original compiler, but most of the rest of the compiler stayed the same.

I then retargeted that compiler with a llvm backend, allowing direct compilation to native code in macOS and linux. 

Potentially I can now port both compilers back to Oberon, possibly even using the original Wirth code. This would not make difference for the llvm compiler, but for the 65C816 compiler this would mean I could use it to compile itself, resulting in a 65C816 native compiler.

# Memory Management
The only change I made from the original compiler was to change from garbage collection to Automatic Reference Counting (ARC). It is debatable which is better, but llvm has good support for ARC and there were some issues with the garbage collection in the original compiler.

I have added a WEAK POINTER type to the compiler so that the user can avoid cycles.

## ARC vs mark-sweep, on the axes that matter for Oberon

| | ARC | Mark-sweep (Project Oberon) |
|---|---|---|
| **Stack pointers** | ✅ Automatic — every local pointer is retained on assignment, released on scope exit | ❌ Not roots by design |
| **Pause behavior** | ✅ No stop-the-world, deterministic destruction | ❌ Pauses scale with live heap |
| **Cycles** | ❌ Leak silently unless we add weak refs or a cycle collector | ✅ Reclaimed |
| **Per-assignment cost** | ❌ retain + release on every pointer store, atomic if MT | ✅ Free until GC runs |
| **Field-level cost** | Same — every field-pointer assignment generates retain/release | ✅ Free |
| **Compiler complexity** | Higher: inject retain/release at every pointer touch, scope-exit cleanup, return-value handling | Lower: emit TD pointer-offset list once per type, walk globals at GC time |
| **Runtime size** | Tiny — just retain/release helpers | Modest — heap, free lists, mark, sweep |
| **Project Oberon compat** | None. Every existing Oberon program needs to be reviewed for cycles | High. Idiomatic programs work as-is |
| **C interop** | ✅ C code can hold/release Oberon pointers cleanly | ❌ C must register every held pointer with the GC |
| **Determinism** | ✅ "When does this object die?" has an answer | ❌ "Whenever GC happens" |

The cycle question is the load-bearing one. Oberon-07 has no built-in
weak references, and idiomatic patterns like AST trees with parent
pointers, scope chains with back-references, and doubly-linked lists
all form cycles that ARC alone cannot reclaim. This compiler addresses
that with a `WEAK POINTER TO T` type — fields declared this way are
excluded from the type descriptor's pointer-offset list, so they hold
the target without contributing to its refcount and don't keep cycles
alive when the strong roots drop.

