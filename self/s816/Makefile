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
# Files/Out/Errors are the POSIX runtime modules the frontend imports (ORS
# imports Files + Out) and the compiler links against. Stage-0 ../../bin/oc
# resolves the imports from ../../runtime/posix automatically, but those
# .smb/.o are gitignored build artifacts — absent on a clean checkout, or
# after an unrelated `rm *.smb` in runtime/posix. This Makefile now builds
# them (below) before the frontend; without that the ORS/ORP compile fails
# with a confusing "import not available" cascade that looks like an s816
# regression but is only a missing dependency.

OC0 ?= ../../bin/oc
RT  := ../../runtime/posix
RT_SMB := $(RT)/Errors.smb $(RT)/Out.smb $(RT)/Files.smb

CC     := clang
CFLAGS := -std=c11 -Wall -Wno-unused-parameter -Wno-unused-function -g

MODS := ORS ORB OCG ORGFP ORGW ORG ORP
OBJS := $(MODS:%=%.o) main.o

all: oc816

# Copy the shared frontend in from ../ (masters live there).
ORS.Mod: ../ORS.Mod
	cp ../ORS.Mod .
ORB.Mod: ../ORB.Mod
	cp ../ORB.Mod .
ORP.Mod: ../ORP.Mod
	cp ../ORP.Mod .

# POSIX runtime modules the frontend imports and the link needs. `oc -s`
# emits <mod>.smb + <mod>.o next to the source. Errors is a leaf; Files
# imports Errors.
$(RT)/Errors.smb: $(RT)/Errors.Mod
	$(OC0) -s $(RT)/Errors.Mod
$(RT)/Out.smb: $(RT)/Out.Mod
	$(OC0) -s $(RT)/Out.Mod
$(RT)/Files.smb: $(RT)/Files.Mod $(RT)/Errors.smb
	$(OC0) -s $(RT)/Files.Mod

# Stage-0 compilation. Modules depend on each other's .smb files, so the
# order is fixed: ORS -> ORB -> OCG -> ORGFP -> ORGW -> ORG -> ORP. ORS
# imports Files + Out, so the runtime .smb must exist first. ORGFP (the FP
# subroutine library, imports only OCG) and ORGW (the .816 module serializer,
# imports OCG/ORB/Files) are both peeled out of ORG and build after OCG/ORB
# and before ORG (which imports them).
ORS.o: ORS.Mod $(RT_SMB)
	$(OC0) -s ORS.Mod
ORB.o: ORB.Mod ORS.o
	$(OC0) -s ORB.Mod
OCG.o: OCG.Mod
	$(OC0) -s OCG.Mod
ORGFP.o: ORGFP.Mod OCG.o
	$(OC0) -s ORGFP.Mod
ORGW.o: ORGW.Mod OCG.o ORB.o
	$(OC0) -s ORGW.Mod
ORG.o: ORG.Mod OCG.o ORGFP.o ORGW.o ORB.o
	$(OC0) -s ORG.Mod
ORP.o: ORP.Mod ORG.o
	$(OC0) -s ORP.Mod

main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<

# No libLLVM: the 816 backend emits bytes, not IR. Link the compiler
# objects with the POSIX runtime (module .o + their _rt.c + runtime.c).
oc816: $(OBJS) $(RT_SMB)
	$(CC) -o $@ $(OBJS) \
	    $(RT)/Files.o $(RT)/Out.o $(RT)/Errors.o \
	    $(RT)/Files_rt.c $(RT)/Out_rt.c $(RT)/runtime.c

clean:
	rm -f *.o *.smb *.ll *.deps oc816 ORS.Mod ORB.Mod ORP.Mod

.PHONY: all clean
