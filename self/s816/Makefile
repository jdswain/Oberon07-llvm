# Self-hosted Oberon compiler, 65C816 backend (oc816).
#
# Frontend: the SHARED ORS/ORB/ORP.Mod (in ../), compiled by the stage-0
# C compiler ../../bin/oc. Backend: OCG.Mod (65C816 instruction encoder)
# + ORG.Mod (816 code generator) — both PURE OBERON, so unlike the LLVM
# backend there is no C bridge and no libLLVM at link time. Driver:
# main.c (hand-written, ~80 lines; the 816 ".816" module is self-
# contained so there is no link step to drive).
#
# The shared frontend .Mod files are COPIED in before compiling so this
# target's .smb/.o artifacts stay local — type sizes differ per backend
# (816: INTEGER=2, LONGINT=4, ptr=4), so artifacts must not be shared
# with llvm/. Edit the masters in ../.
#
# Files.smb / Out.smb / Errors.smb are resolved automatically: stage-0
# ../../bin/oc adds ../../runtime/posix as a search path relative to its
# own location. Those runtime objects are linked in below.

OC0 ?= ../../bin/oc
RT  := ../../runtime/posix

CC     := clang
CFLAGS := -std=c11 -Wall -Wno-unused-parameter -Wno-unused-function -g

MODS := ORS ORB OCG ORG ORP
OBJS := $(MODS:%=%.o) main.o

all: oc816

# Copy the shared frontend in from ../ (masters live there).
ORS.Mod: ../ORS.Mod
	cp ../ORS.Mod .
ORB.Mod: ../ORB.Mod
	cp ../ORB.Mod .
ORP.Mod: ../ORP.Mod
	cp ../ORP.Mod .

# Stage-0 compilation. Modules depend on each other's .smb files, so the
# order is fixed: ORS -> ORB -> OCG -> ORG -> ORP.
ORS.o: ORS.Mod
	$(OC0) -s ORS.Mod
ORB.o: ORB.Mod ORS.o
	$(OC0) -s ORB.Mod
OCG.o: OCG.Mod
	$(OC0) -s OCG.Mod
ORG.o: ORG.Mod OCG.o ORB.o
	$(OC0) -s ORG.Mod
ORP.o: ORP.Mod ORG.o
	$(OC0) -s ORP.Mod

main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<

# No libLLVM: the 816 backend emits bytes, not IR. Link the compiler
# objects with the POSIX runtime (module .o + their _rt.c + runtime.c).
oc816: $(OBJS)
	$(CC) -o $@ $(OBJS) \
	    $(RT)/Files.o $(RT)/Out.o $(RT)/Errors.o \
	    $(RT)/Files_rt.c $(RT)/Out_rt.c $(RT)/runtime.c

clean:
	rm -f *.o *.smb *.ll *.deps oc816 ORS.Mod ORB.Mod ORP.Mod

.PHONY: all clean
